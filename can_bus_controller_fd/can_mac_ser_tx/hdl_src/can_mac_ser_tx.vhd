--------------------------------------------------------------------------------------------------------------------------------------------------------------
-- Copyright 2026 Everllence, Teglholmsgade 41, 2450 Copenhagen SV, Denmark
--------------------------------------------------------------------------------------------------------------------------------------------------------------
--
-- Requirements:
--
-- Description:   The module sits at the boundary between the LLC and the MAC in the transmission path. It is responsible for:
--                  1) Calculating frame parameters (frame_params) and registering these at the interface to the MAC FSM.
--                  2) Serializing the LLC frame ID and data bytes received from the LLC and presenting these as a bit steam to the MAC FSM.
--                  3) Forwarding transfer status information from the MAC FSM to the LLC.
--
-- Revision log:  Date:       Initial:  JIRA:
--                2026-03-16  TMYAES    [TRIT-4336] Initial implementation
--
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
  signal count                  : integer range 0 to t_byte'left + 1;
  signal llc_frame_buffer       : t_byte;
  signal config_byte_0          : t_byte;
  signal id_bits_remaining      : integer range 0 to c_base_id_width + c_extended_id_width;
  signal padding_bits_remaining : integer range 0 to c_llc_id_stream_width - c_base_id_width;

begin

  p_fsm : process (clk_i) is

    -------------------------------------------------------------------------
    -- Helper function to convert DLC vector to actual data length in bytes.
    -------------------------------------------------------------------------
    function f_dlc_to_data_length (
      dlc        : t_dlc;
      can_format : std_logic_vector(2 downto 0)
    ) return integer is
    begin

      -- Encoding according to table 5 in ISO 11898-1:2024
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

    -------------------------------------------------------------------------
    -- Helper function to convert integer position to vector.
    -------------------------------------------------------------------------
    function f_to_pos_vec (
      val : t_position
    ) return t_mac_frame_position_vec is
    begin

      return std_logic_vector(to_unsigned(val, t_mac_frame_position_vec'length));

    end function f_to_pos_vec;

    -------------------------------------------------------------------------
    -- Function to calculate frame parameters based on config bytes from LLC.
    -------------------------------------------------------------------------
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
      variable v_data_start    : t_position;
      variable v_data_stop     : t_position;
      variable v_sbc_start     : t_position;
      variable v_crc_start     : t_position;
      variable v_crc_delimiter : t_position;
      variable v_is_fd_frame   : boolean;

    begin

      -- Extract frame format from config_byte_0[7:5]
      v_result.format := config_byte_0(c_llc_frame_config_byte_0_format_start downto c_llc_frame_config_byte_0_format_end);

      v_is_fd_frame := (v_result.format = c_llc_fmt_fb) or (v_result.format = c_llc_fmt_fe);

      -- Extract DLC vector from config_byte_1[7:4] (raw 4-bit value)
      v_result.dlc_vector := config_byte_1(c_llc_frame_config_byte_1_dlc_start downto c_llc_frame_config_byte_1_dlc_end);

      -- Extract flags from config_byte_0
      v_result.has_brs         := config_byte_0(c_llc_frame_config_byte_0_brs);
      v_result.is_remote_frame := config_byte_0(c_llc_frame_config_byte_0_ftyp);
      v_result.esi_enable      := config_byte_0(c_llc_frame_config_byte_0_esi);

      -- ISO 11898-1: 6.6.10.1 - Remote frames shall not contain a Data field
      if (v_result.is_remote_frame = '1') then
        v_data_length := 0;
      else
        -- Calculate data length from DLC vector
        v_data_length := f_dlc_to_data_length(t_dlc(to_integer(unsigned(v_result.dlc_vector))), v_result.format);
      end if;

      v_data_bits := v_data_length * c_byte_width;

      -- Populate field boundaries based on format (integer arithmetic)
      case v_result.format is
        when c_llc_fmt_cb => v_data_start := c_cb_data_start.position;
        when c_llc_fmt_ce => v_data_start := c_ce_data_start.position;
        when c_llc_fmt_fb => v_data_start := c_fb_data_start.position;
        when c_llc_fmt_fe => v_data_start := c_fe_data_start.position;
        when others => v_data_start := 0;
      end case;

      if (v_data_bits > 0) then
        v_data_stop := v_data_start + (v_data_bits - 1);
      else
        v_data_stop := v_data_start;
      end if;

      -- CRC length: CRC-15 for classic, CRC-17 for FD <= 16 bytes, CRC-21 otherwise
      if (not v_is_fd_frame) then
        v_crc_length := c_crc_15_length;
      elsif (v_data_length < c_crc_17_length) then
        v_crc_length := c_crc_17_length;
      else
        v_crc_length := c_crc_21_length;
      end if;

      -- CAN FD has SBC field after data, CAN Classic goes directly to CRC
      if (v_is_fd_frame) then
        v_sbc_start         := v_data_stop + 1;
        v_crc_start         := v_sbc_start + c_sbc_field_width;
        v_fixed_stuff_count := 1 + ((c_sbc_field_width + v_crc_length) / 5);
        v_crc_field_length  := v_crc_length + v_fixed_stuff_count;
        v_crc_delimiter     := v_crc_start + v_crc_field_length;
      else
        v_sbc_start     := 0;
        v_crc_start     := v_data_stop + 1;
        v_crc_delimiter := v_crc_start + v_crc_length;
      end if;

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

      v_result.data_start    := f_to_pos_vec(v_data_start);
      v_result.data_stop     := f_to_pos_vec(v_data_stop);
      v_result.sbc_start     := f_to_pos_vec(v_sbc_start);
      v_result.crc_start     := f_to_pos_vec(v_crc_start);
      v_result.crc_delimiter := f_to_pos_vec(v_crc_delimiter);

      return v_result;

    end function f_calculate_frame_params;

    procedure capture_config_byte_0 is
    begin

      -- Capture first config byte.
      if (llc_i.avalon_st_source.valid and llc_i.avalon_st_source.startofpacket) then
        config_byte_0 <= llc_i.avalon_st_source.data;
      end if;

    end procedure capture_config_byte_0;

    procedure capture_config_byte_1 is
    begin

      if (llc_i.avalon_st_source.valid) then
        if (llc_i.avalon_st_source.startofpacket) then
          config_byte_0 <= llc_i.avalon_st_source.data; -- For safety: if a new SOP is seen, treat it as the start of a new frame and capture config byte 0 again.
        else
          -- Calculate frame parameters based on config bytes.
          tx_mac_fsm_o.frame_params <= f_calculate_frame_params(config_byte_0, llc_i.avalon_st_source.data);

          -- Determine the number of ID bits and padding bits to shift out based on frame format (first bit of format determines if extended ID is used)
          if (config_byte_0(c_llc_frame_config_byte_0_extended_bit) = '1') then
            id_bits_remaining      <= c_base_id_width + c_extended_id_width;
            padding_bits_remaining <= c_llc_id_stream_width - (c_base_id_width + c_extended_id_width);
          else
            id_bits_remaining      <= c_base_id_width;
            padding_bits_remaining <= c_llc_id_stream_width - c_base_id_width;
          end if;
        end if;
      end if;

    end procedure capture_config_byte_1;

    procedure load_byte is
    begin

      if (llc_i.avalon_st_source.valid) then
        llc_frame_buffer   <= llc_i.avalon_st_source.data;
        count              <= 0;
        tx_mac_fsm_o.data  <= llc_i.avalon_st_source.data(t_byte'left);
        tx_mac_fsm_o.valid <= '1';
      end if;

    end procedure load_byte;

    -----------------------------------------------------------------
    -- Decrement padding bits counter
    -----------------------------------------------------------------
    procedure consume_padding_bit is
    begin

      padding_bits_remaining <= padding_bits_remaining - 1;
      if (count = t_byte'left) then
        count <= 0;
      else
        count <= count + 1;
      end if;

    end procedure consume_padding_bit;

    -----------------------------------------------------------------
    -- Drive drive normal bits from the frame buffer onto the MAC FSM interface.
    -- Start at left-most - 1: First bit was presented during load_byte procedure.
    -----------------------------------------------------------------
    procedure drive_normal_bit is
    begin

      tx_mac_fsm_o.valid <= '1';
      if (tx_mac_fsm_i.ready = '1') then
        -- Decrement ID bits remaining if we are still in the ID field
        if (id_bits_remaining > 0) then
          id_bits_remaining <= id_bits_remaining - 1;
        end if;

        if (count = t_byte'left) then
          tx_mac_fsm_o.valid <= '0';
          count              <= 0;
        else
          tx_mac_fsm_o.data <= llc_frame_buffer(t_byte'left - (count + 1));
          count             <= count + 1;
        end if;
      end if;

    end procedure drive_normal_bit;

  begin

    if rising_edge(clk_i) then
      if (rst_i = '1') then
        state                  <= load_config_byte_0;
        count                  <= 0;
        llc_frame_buffer       <= (others => '0');
        config_byte_0          <= (others => '0');
        id_bits_remaining      <= 0;
        padding_bits_remaining <= 0;

        -- Reset outputs
        llc_o        <= c_mac_to_llc_if_reset;
        tx_mac_fsm_o <= c_tx_mac_ser_to_fsm_if_reset;
      else
        -- Drive defaults
        tx_mac_fsm_o.valid         <= '0';
        llc_o.transfer_status      <= tx_mac_fsm_i.transfer_status;
        llc_o.avalon_st_sink.ready <= '0' when (state = shift_out_bits) else '1';

        -----------------------------------------------------------------
        -- State + output logic
        -----------------------------------------------------------------
        -- Return to idle if MAC FSM signals that transfer is no longer ongoing (e.g. due to error or completion)
        if (tx_mac_fsm_i.transfer_status /= c_ongoing) then
          count <= 0;
          state <= load_config_byte_0;
        else
          case state is
            -------------------------------------------------------------------------
            -- Simply grab first config byte 0 from LLC.
            -------------------------------------------------------------------------
            when load_config_byte_0 =>
              capture_config_byte_0;
              if (llc_i.avalon_st_source.valid and llc_i.avalon_st_source.startofpacket) then
                state <= load_config_byte_1;
              end if;
            -------------------------------------------------------------------------
            -- Grab config byte 1 from LLC, calculate and present frame parameters to MAC FSM,
            -- initialize ID/padding bit counters.
            -------------------------------------------------------------------------
            when load_config_byte_1 =>
              capture_config_byte_1;
              if (llc_i.avalon_st_source.valid) then
                if (llc_i.avalon_st_source.startofpacket) then
                  state <= load_config_byte_1;
                else
                  state <= load_llc_frame_byte;
                end if;
              end if;
            -----------------------------------------------------------------
            -- Gram byte from LLC and present and present left-most bit to MAC FSM.
            -----------------------------------------------------------------
            when load_llc_frame_byte =>
              load_byte;
              if (llc_i.avalon_st_source.valid) then
                if (llc_i.avalon_st_source.startofpacket) then
                  state <= load_config_byte_1;
                else
                  state <= shift_out_bits;
                end if;
              end if;
            -----------------------------------------------------------------
            -- Shift out bits to MAC FSM or consume padding bits from ID byte(s).
            -----------------------------------------------------------------
            when shift_out_bits =>
              if ((id_bits_remaining = 0) and (padding_bits_remaining > 0)) then
                consume_padding_bit;
              else
                drive_normal_bit;
                if ((tx_mac_fsm_i.ready = '1') and (count = t_byte'left)) then
                  state <= load_llc_frame_byte;
                end if;
              end if;
          end case;
        end if;
      end if;
    end if;

  end process p_fsm;

end architecture rtl;

-- eof

