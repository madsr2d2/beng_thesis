--------------------------------------------------------------------------------------------------------------------------------------------------------------
-- Copyright 2026 Everllence, Teglholmsgade 41, 2450 Copenhagen SV, Denmark
--------------------------------------------------------------------------------------------------------------------------------------------------------------
--
-- Requirements:  
--
-- Description:
--
-- Revision log:  Date:       Initial:  JIRA:
--                2026-03-16  TMYAES    Initial implementation
--
--------------------------------------------------------------------------------------------------------------------------------------------------------------
  
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.pk_man_global.all;
use work.pk_can_types.all;

entity can_mac_ser_tx is
  port (
    clk_i : in    std_logic;
    rst_i : in    std_logic;

    -- LLC interface
    llc_i : in    t_can_llc_mac_tx_if_s2d;
    llc_o : out   t_can_llc_mac_tx_if_d2s;

    -- can_mac_fsm_tx interface
    tx_mac_fsm_i : in    t_can_mac_ser_fsm_tx_if_m2s;
    tx_mac_fsm_o : out   t_can_mac_ser_fsm_tx_if_s2m
  );
end entity can_mac_ser_tx;

architecture rtl of can_mac_ser_tx is

  type t_state is (
    load_config_byte_0,
    load_config_byte_1,
    load_llc_frame_byte,
    shift_out_bits
  );

  signal state                  : t_state;
  signal count                  : integer range t_byte'left downto 0;
  signal llc_frame_buffer       : t_byte;
  signal config_byte_0          : t_byte;
  signal id_bits_remaining      : integer range 0 to c_base_id_width + c_extended_id_width;
  signal padding_bits_remaining : integer range 0 to c_llc_id_stream_width - c_base_id_width;

begin

  p_fsm : process (clk_i) is

    variable v_frame_buffer           : t_byte;
    variable v_id_bits_remaining      : integer range 0 to c_base_id_width + c_extended_id_width;
    variable v_padding_bits_remaining : integer range 0 to c_llc_id_stream_width - c_base_id_width;

    variable v_transmission_completed : boolean;
    variable v_byte_finished          : boolean;
    variable v_in_id_padding          : boolean;

    -------------------------------------------------------------------------
    -- Functions
    ------------------------------------------------------------------------- 
    function f_dlc_to_data_length (
      dlc        : t_dlc;
      can_format : std_logic_vector(2 downto 0)
    ) return integer is
    begin

      case can_format is
        when c_llc_fmt_cb | c_llc_fmt_ce =>

          if (dlc <= 8) then
            return integer(dlc);
          else
            return 8;
          end if;

        when c_llc_fmt_fb | c_llc_fmt_fe =>
          case dlc is
            when 0 to 8 => return integer(dlc);
            when 9 => return 12;
            when 10 => return 16;
            when 11 => return 20;
            when 12 => return 24;
            when 13 => return 32;
            when 14 => return 48;
            when 15 => return c_max_data_bytes;
            when others => return 0;
          end case;
        when others => return 0;
      end case;

    end function f_dlc_to_data_length;

    -- Helper: convert integer position to t_mac_frame_position_vec
    function f_to_pos_vec (val : t_position) return t_mac_frame_position_vec is
    begin
      return std_logic_vector(to_unsigned(val, t_mac_frame_position_vec'length));
    end function f_to_pos_vec;

    function f_calculate_frame_params (
    config_byte_0 : t_byte;
    config_byte_1 : t_byte
  ) return t_frame_params is

    variable v_result            : t_frame_params;
    variable v_data_length       : integer range 0 to c_max_data_bytes;
    variable v_data_bits         : t_position;
    variable v_crc_length        : t_position;
    variable v_fixed_stuff_count : t_position;
    variable v_crc_field_length  : t_position;

    -- Integer working variables for position arithmetic
    variable v_data_start        : t_position;
    variable v_data_stop         : t_position;
    variable v_dlc_start         : t_position;
    variable v_dlc_stop          : t_position;
    variable v_base_id_start     : t_position;
    variable v_base_id_stop      : t_position;
    variable v_extended_id_start : t_position;
    variable v_extended_id_stop  : t_position;
    variable v_sbc_start         : t_position;
    variable v_sbc_stop          : t_position;
    variable v_crc_start         : t_position;
    variable v_crc_stop          : t_position;
    variable v_crc_delimiter     : t_position;
    variable v_ack_slot          : t_position;
    variable v_ack_delimiter     : t_position;
    variable v_eof_start         : t_position;
    variable v_eof_stop          : t_position;

  begin

    -- Extract frame format from config_byte_0[7:5]
    v_result.format := config_byte_0(c_llc_frame_config_byte_0_format_start downto c_llc_frame_config_byte_0_format_end);

    -- Extract DLC vector from config_byte_1[7:4] (raw 4-bit value)
    v_result.dlc_vector := config_byte_1(c_llc_frame_config_byte_1_dlc_start downto c_llc_frame_config_byte_1_dlc_end);

    -- Extract flags from config_byte_0
    v_result.has_brs         := config_byte_0(c_llc_frame_config_byte_0_brs);
    v_result.is_remote_frame := config_byte_0(c_llc_frame_config_byte_0_ftyp);
    v_result.esi_enable      := config_byte_0(c_llc_frame_config_byte_0_esi);
    v_result.is_fd_frame     := '1' when (v_result.format = c_llc_fmt_fb) or (v_result.format = c_llc_fmt_fe) else '0';

    -- Calculate data length from DLC vector
    v_data_length := f_dlc_to_data_length(t_dlc(to_integer(unsigned(v_result.dlc_vector))), v_result.format);

    -- ISO 11898-1: 6.6.10.1 - Remote frames shall not contain a Data field
    if (v_result.is_remote_frame = '1') then
      v_data_length := 0;
    end if;

    v_data_bits := v_data_length * c_byte_width;

    -- Default extended ID to zero (overridden for CE/FE)
    v_extended_id_start := 0;
    v_extended_id_stop  := 0;

    -- Populate field boundaries based on format (integer arithmetic)
    case v_result.format is
      when c_llc_fmt_cb =>
        v_base_id_start := c_cb_base_id_start.position;
        v_base_id_stop  := c_cb_base_id_stop.position;
        v_dlc_start     := c_cb_dlc_start.position;
        v_data_start    := c_cb_data_start.position;

      when c_llc_fmt_ce =>
        v_base_id_start     := c_ce_base_id_start.position;
        v_base_id_stop      := c_ce_base_id_stop.position;
        v_extended_id_start := c_ce_extended_id_start.position;
        v_extended_id_stop  := c_ce_extended_id_stop.position;
        v_dlc_start         := c_ce_dlc_start.position;
        v_data_start        := c_ce_data_start.position;

      when c_llc_fmt_fb =>
        v_base_id_start := c_fd_base_id_start.position;
        v_base_id_stop  := c_fd_base_id_stop.position;
        v_dlc_start     := c_fb_dlc_start.position;
        v_data_start    := c_fb_data_start.position;

      when c_llc_fmt_fe =>
        v_base_id_start     := c_fe_base_id_start.position;
        v_base_id_stop      := c_fe_base_id_stop.position;
        v_extended_id_start := c_fe_extended_id_start.position;
        v_extended_id_stop  := c_fe_extended_id_stop.position;
        v_dlc_start         := c_fe_dlc_start.position;
        v_data_start        := c_fe_data_start.position;

      when others =>
        v_base_id_start := 0;
        v_base_id_stop  := 0;
        v_dlc_start     := 0;
        v_data_start    := 0;
    end case;

    v_dlc_stop := v_dlc_start + c_dlc_field_width;

    if (v_data_bits > 0) then
      v_data_stop := v_data_start + v_data_bits - 1;
    else
      v_data_stop := v_data_start;
    end if;

    -- CRC length: CRC-15 for classic, CRC-17 for FD <= 16 bytes, CRC-21 otherwise
    if (v_result.is_fd_frame = '0') then
      v_crc_length := c_crc_15_length;
    elsif (v_data_length < c_crc_17_length) then
      v_crc_length := c_crc_17_length;
    else
      v_crc_length := c_crc_21_length;
    end if;

    -- CAN FD has SBC field after data, CAN Classic goes directly to CRC
    if (v_result.is_fd_frame = '1') then
      v_sbc_start         := v_data_stop + 1;
      v_sbc_stop          := v_sbc_start + c_sbc_field_width;
      v_crc_start         := v_sbc_stop;
      v_fixed_stuff_count := 1 + ((c_sbc_field_width + v_crc_length) / 5);
      v_crc_field_length  := v_crc_length + v_fixed_stuff_count;
      v_crc_stop          := v_crc_start + v_crc_field_length;
    else
      v_sbc_start := 0;
      v_sbc_stop  := 0;
      v_crc_start := v_data_stop + 1;
      v_crc_stop  := v_crc_start + v_crc_length;
    end if;

    v_crc_delimiter := v_crc_stop;
    v_ack_slot      := v_crc_delimiter + 1;
    v_ack_delimiter := v_ack_slot + 1;
    v_eof_start     := v_ack_delimiter + 1;
    v_eof_stop      := v_eof_start + c_eof_field_width;

    -- Determine CRC polynomial selection (00=CRC15, 01=CRC17, 10=CRC21)
    case v_crc_length is
      when c_crc_15_length =>
        v_result.crc_poly_select := "00";
      when c_crc_17_length =>
        v_result.crc_poly_select := "01";
      when c_crc_21_length =>
        v_result.crc_poly_select := "10";
      when others =>
        v_result.crc_poly_select := "11";
    end case;

    -- Convert integer positions to t_mac_frame_position_vec
    v_result.base_id_start     := f_to_pos_vec(v_base_id_start);
    v_result.base_id_stop      := f_to_pos_vec(v_base_id_stop);
    v_result.extended_id_start := f_to_pos_vec(v_extended_id_start);
    v_result.extended_id_stop  := f_to_pos_vec(v_extended_id_stop);
    v_result.dlc_start         := f_to_pos_vec(v_dlc_start);
    v_result.dlc_stop          := f_to_pos_vec(v_dlc_stop);
    v_result.data_start        := f_to_pos_vec(v_data_start);
    v_result.data_stop         := f_to_pos_vec(v_data_stop);
    v_result.sbc_start         := f_to_pos_vec(v_sbc_start);
    v_result.sbc_stop          := f_to_pos_vec(v_sbc_stop);
    v_result.crc_start         := f_to_pos_vec(v_crc_start);
    v_result.crc_stop          := f_to_pos_vec(v_crc_stop);
    v_result.crc_delimiter     := f_to_pos_vec(v_crc_delimiter);
    v_result.ack_slot          := f_to_pos_vec(v_ack_slot);
    v_result.ack_delimiter     := f_to_pos_vec(v_ack_delimiter);
    v_result.eof_start         := f_to_pos_vec(v_eof_start);
    v_result.eof_stop          := f_to_pos_vec(v_eof_stop);

    return v_result;

  end function f_calculate_frame_params;
    -------------------------------------------------------------------------
    -- Procedures
    -------------------------------------------------------------------------

    procedure report_status_to_llc is
    begin

      if (tx_mac_fsm_i.transfer_status /= c_ongoing) then
        llc_o.transfer_status <= tx_mac_fsm_i.transfer_status;
      elsif (state = load_config_byte_0) then
        llc_o.transfer_status <= c_ongoing;
      end if;

      case state is
        when load_config_byte_0 | load_config_byte_1 | load_llc_frame_byte =>
          llc_o.avalon_st_sink.ready <= '1';
        when others =>
          llc_o.avalon_st_sink.ready <= '0';
      end case;

    end procedure report_status_to_llc;

    procedure capture_config_byte_0 is
    begin

      if (llc_i.avalon_st_source.valid and llc_i.avalon_st_source.startofpacket) then
        config_byte_0 <= llc_i.avalon_st_source.data;
      end if;

    end procedure capture_config_byte_0;

    procedure capture_config_byte_1 is
    begin

      if (llc_i.avalon_st_source.valid) then
        if (llc_i.avalon_st_source.startofpacket) then
          config_byte_0 <= llc_i.avalon_st_source.data;
        else
          tx_mac_fsm_o.frame_params <= f_calculate_frame_params(config_byte_0, llc_i.avalon_st_source.data);

          if (config_byte_0(c_llc_frame_config_byte_0_extended_bit) = '1') then
            v_id_bits_remaining      := c_base_id_width + c_extended_id_width;
            v_padding_bits_remaining := c_llc_id_stream_width - c_base_id_width - c_extended_id_width;
          else
            v_id_bits_remaining      := c_base_id_width;
            v_padding_bits_remaining := c_llc_id_stream_width - c_base_id_width;
          end if;
        end if;
      end if;

    end procedure capture_config_byte_1;

    procedure load_byte is
    begin

      if (llc_i.avalon_st_source.valid and not llc_i.avalon_st_source.startofpacket) then
        v_frame_buffer := llc_i.avalon_st_source.data;
        count        <= t_byte'left;

        if (not v_in_id_padding) then
          tx_mac_fsm_o.data  <= llc_i.avalon_st_source.data(t_byte'left);
          tx_mac_fsm_o.valid <= '1';
        end if;
      end if;

    end procedure load_byte;

    procedure consume_padding_bit is
    begin

      v_padding_bits_remaining := padding_bits_remaining - 1;

      if (count = 0) then
        count <= t_byte'left;
      else
        v_frame_buffer := llc_frame_buffer sll 1;
        count        <= count - 1;
      end if;

    end procedure consume_padding_bit;

    procedure shift_normal_bit is
    begin

      tx_mac_fsm_o.valid <= '1';
      tx_mac_fsm_o.data  <= llc_frame_buffer(t_byte'left);

      if (v_transmission_completed) then
        tx_mac_fsm_o.valid <= '0';
        count              <= t_byte'left;
      elsif (tx_mac_fsm_i.ready = '1') then
        if (id_bits_remaining > 0) then
          v_id_bits_remaining := id_bits_remaining - 1;
        end if;

        if (count = 0) then
          tx_mac_fsm_o.valid <= '0';
          count              <= t_byte'left;
        else
          v_frame_buffer       := llc_frame_buffer sll 1;
          count              <= count - 1;
          tx_mac_fsm_o.data  <= v_frame_buffer(t_byte'left);
        end if;
      end if;

    end procedure shift_normal_bit;

  begin

    if rising_edge(clk_i) then
      if (rst_i = '1') then
        state                  <= load_config_byte_0;
        count                  <= t_byte'left;
        llc_frame_buffer       <= (others => '0');
        config_byte_0          <= (others => '0');
        id_bits_remaining      <= 0;
        padding_bits_remaining <= 0;

        llc_o        <= c_mac_to_llc_if_reset;
        tx_mac_fsm_o <= c_tx_mac_ser_to_fsm_if_reset;
      else
        v_transmission_completed := tx_mac_fsm_i.transfer_status /= c_ongoing;
        v_byte_finished          := count = 0;
        v_in_id_padding          := id_bits_remaining = 0 and padding_bits_remaining > 0;

        -- Defaults: hold registered values
        v_frame_buffer           := llc_frame_buffer;
        v_id_bits_remaining      := id_bits_remaining;
        v_padding_bits_remaining := padding_bits_remaining;

        -- Clear pulses
        llc_o.avalon_st_sink.ready <= c_mac_to_llc_if_reset.avalon_st_sink.ready;
        tx_mac_fsm_o.valid         <= c_tx_mac_ser_to_fsm_if_reset.valid;

        report_status_to_llc;

        -----------------------------------------------------------------
        -- State + output logic
        -----------------------------------------------------------------
        case state is
          when load_config_byte_0 =>
            capture_config_byte_0;
            if (llc_i.avalon_st_source.valid and llc_i.avalon_st_source.startofpacket) then
              state <= load_config_byte_1;
            end if;

          when load_config_byte_1 =>
            capture_config_byte_1;
            if (llc_i.avalon_st_source.valid) then
              if (llc_i.avalon_st_source.startofpacket) then
                state <= load_config_byte_1;
              else
                state <= load_llc_frame_byte;
              end if;
            end if;

          when load_llc_frame_byte =>
            load_byte;
            if (v_transmission_completed) then
              state <= load_config_byte_0;
            elsif (llc_i.avalon_st_source.valid) then
              if ( llc_i.avalon_st_source.startofpacket) then
                state <= load_config_byte_1;
              else
                state <= shift_out_bits;
              end if;
            end if;

          when shift_out_bits =>
            if (v_in_id_padding) then
              consume_padding_bit;
              if (v_byte_finished) then
                state <= load_llc_frame_byte;
              end if;
            else
              shift_normal_bit;
              if (v_transmission_completed) then
                state <= load_config_byte_0;
              elsif (tx_mac_fsm_i.ready = '1' and v_byte_finished) then
                state <= load_llc_frame_byte;
              end if;
            end if;

        end case;

        -----------------------------------------------------------------
        -- Register outputs
        -----------------------------------------------------------------
        llc_frame_buffer       <= v_frame_buffer;
        id_bits_remaining      <= v_id_bits_remaining;
        padding_bits_remaining <= v_padding_bits_remaining;

      end if;
    end if;

  end process p_fsm;

end architecture rtl;

-- eof