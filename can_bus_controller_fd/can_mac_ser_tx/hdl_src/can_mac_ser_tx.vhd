--------------------------------------------------------------------------------------------------------------------------------------------------------------
-- Copyright 2026 Everllence, Teglholmsgade 41, 2450 Copenhagen SV, Denmark
--------------------------------------------------------------------------------------------------------------------------------------------------------------
--
-- Requirements:  
--
-- Description:
--
-- Revision log:  Date:       Initial:  JIRA:
--                2026-03-16  TMYAES    Initial version
--
--------------------------------------------------------------------------------------------------------------------------------------------------------------
  
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.pk_man_global.all;
use work.pk_can_types.all;

entity can_mac_ser_tx is
  port (
    -- Clock and reset
    clk_i : in    std_logic;
    reset_i : in    std_logic;
    
    -- LLC interface
    llc_i : in    t_can_llc_mac_tx_if_s2d;
    llc_o : out   t_can_llc_mac_tx_if_d2s;
    
    -- can_mac_fsm_tx interface
    tx_mac_fsm_i : in    t_can_mac_ser_fsm_tx_if_m2s;
    tx_mac_fsm_o : out   t_can_mac_ser_fsm_tx_if_s2m
  );
end entity can_mac_ser_tx;

architecture rtl of can_mac_ser_tx is
  
  ------------------------------------------------------------------------------
  -- Types
  ------------------------------------------------------------------------------
  type t_can_mac_ser_tx_state is (
    load_config_byte_0,
    load_config_byte_1,
    load_llc_frame_byte,
    shift_out_bits
  );
  
  ------------------------------------------------------------------------------
  -- Signals
  ------------------------------------------------------------------------------
     
  signal state                  : t_can_mac_ser_tx_state;
  signal count                  : integer range t_byte'left downto 0;
  signal llc_frame_buffer       : t_byte;
  signal config_byte_0          : t_byte;
  signal id_bits_remaining      : integer range 0 to c_base_id_width + c_extended_id_width;
  signal padding_bits_remaining : integer range 0 to c_llc_id_stream_width - c_base_id_width;

begin

  p_fsm : process (clk_i) is

    -- Registered next-value variables
    variable v_state                  : t_can_mac_ser_tx_state;
    variable v_count                  : integer range t_byte'left downto 0;
    variable v_frame_buffer           : t_byte;
    variable v_config_byte_0          : t_byte;
    variable v_id_bits_remaining      : integer range 0 to c_base_id_width + c_extended_id_width;
    variable v_padding_bits_remaining : integer range 0 to c_llc_id_stream_width - c_base_id_width;

    variable v_llc_o        : t_can_llc_mac_tx_if_d2s;
    variable v_tx_mac_fsm_o : t_can_mac_ser_fsm_tx_if_s2m;

    -- Named guard variables (evaluated once per cycle)
    variable v_llc_valid              : boolean;
    variable v_llc_sop                : boolean;
    variable v_fsm_consumed_bit       : boolean;
    variable v_transmission_completed : boolean;
    variable v_byte_finished          : boolean;
    variable v_in_id_padding          : boolean;

  ------------------------------------------------------------------------------
  -- Helper function
  ------------------------------------------------------------------------------

  function f_calculate_frame_params (
    config_byte_0 : t_byte;
    config_byte_1 : t_byte
  ) return t_frame_params is

    -- TODO: These position_t integer subtype is unnecessarily large for many of these variables.
    variable v_result            : t_frame_params;
    variable v_data_length       : t_position;
    variable v_data_start        : t_position;
    variable v_data_bits         : t_position;
    variable v_has_brs           : boolean;
    variable v_is_remote         : boolean;
    variable v_crc_length        : t_position;
    variable v_fixed_stuff_count : t_position;
    variable v_crc_field_length  : t_position;
    variable v_sbc_start         : t_position;
    variable v_rtr_polarity      : t_polarity;
    variable v_brs_polarity      : t_polarity;
    variable v_esi_polarity      : t_polarity;

  begin

    -- Extract frame format from config_byte_0[7:5]
    case config_byte_0(c_llc_frame_config_byte_0_format_start downto c_llc_frame_config_byte_0_format_end) is
      when c_llc_fmt_ce => v_result.format := cc_extended;
      when c_llc_fmt_cb => v_result.format := cc_basic;
      when c_llc_fmt_fb => v_result.format := fd_basic;
      when c_llc_fmt_fe => v_result.format := fd_extended;
      when others => v_result.format := unknown;
    end case;

    -- Extract DLC vector from config_byte_1[7:4] (raw 4-bit value)
    v_result.dlc_vector := config_byte_1(c_llc_frame_config_byte_1_dlc_start downto c_llc_frame_config_byte_1_dlc_end);

    -- Extract flags from config_byte_0
    v_has_brs   := (config_byte_0(c_llc_frame_config_byte_0_brs) = '1');
    v_is_remote := (config_byte_0(c_llc_frame_config_byte_0_ftyp) = '1');

    v_result.is_fd_frame     := (v_result.format = fd_basic) or (v_result.format = fd_extended);
    v_result.has_brs         := v_has_brs;
    v_result.esi_enable      := (config_byte_0(c_llc_frame_config_byte_0_esi) = '1');
    v_result.is_remote_frame := v_is_remote;

    -- Determine frame-dependent polarities for control bits
    v_rtr_polarity := recessive when v_result.is_remote_frame else dominant;
    v_brs_polarity := recessive when v_result.has_brs else dominant;
    v_esi_polarity := recessive when v_result.esi_enable else dominant;

    -- Calculate data length from DLC vector
    v_data_length := dlc_to_data_length(t_dlc(to_integer(unsigned(result.dlc_vector))), v_result.format);

    -- ISO 11898-1: 6.6.10.1 - Remote frames shall not contain a Data field
    if (v_result.is_remote_frame) then
      v_data_length := 0;
    end if;

    v_data_bits := v_data_length * c_byte_width;

    -- Populate field boundaries based on format
    case v_result.format is
      when cc_basic =>
        v_data_start             := c_cb_data_start.position;
        v_result.dlc_start         := c_cb_dlc_start.position;
        v_result.base_id_start     := c_cb_base_id_start.position;
        v_result.base_id_stop      := c_cb_base_id_start.position + c_base_id_width - 1;
        v_result.extended_id_start := 0;
        v_result.extended_id_stop  := 0;
        v_result.rtr_bit           := (position => c_cb_rtr.position, polarity => v_rtr_polarity);
        v_result.ide_bit           := c_cb_ide;
        v_result.r0_bit            := c_cb_r0;
        v_result.srr_bit           := c_unknown_bit;
        v_result.rrs_bit           := c_unknown_bit;
        v_result.fdf_bit           := c_unknown_bit;
        v_result.res_bit           := c_unknown_bit;
        v_result.r1_bit            := c_unknown_bit;
        v_result.brs_bit           := c_unknown_bit;
        v_result.esi_bit           := c_unknown_bit;

      when cc_extended =>
        v_data_start             := c_ce_data_start.position;
        v_result.dlc_start         := c_ce_dlc_start.position;
        v_result.base_id_start     := c_ce_base_id_start.position;
        v_result.base_id_stop      := c_ce_base_id_start.position + (c_base_id_width - 1);
        v_result.extended_id_start := c_ce_extended_id_start.position;
        v_result.extended_id_stop  := c_ce_extended_id_start.position + (c_extended_id_width - 1);
        v_result.srr_bit           := c_ce_srr;
        v_result.ide_bit           := c_ce_ide;
        v_result.rtr_bit           := (position => c_ce_rtr.position, polarity => v_rtr_polarity);
        v_result.r1_bit            := c_ce_r1;
        v_result.r0_bit            := c_ce_r0;
        v_result.rrs_bit           := c_unknown_bit;
        v_result.fdf_bit           := c_unknown_bit;
        v_result.res_bit           := c_unknown_bit;
        v_result.brs_bit           := c_unknown_bit;
        v_result.esi_bit           := c_unknown_bit;

      when fd_basic =>
        v_data_start             := c_fb_data_start.position;
        v_result.dlc_start         := c_fb_dlc_start.position;
        v_result.base_id_start     := c_fd_base_id_start.position;
        v_result.base_id_stop      := c_fd_base_id_start.position + (c_base_id_width - 1);
        v_result.extended_id_start := 0;
        v_result.extended_id_stop  := 0;
        v_result.rrs_bit           := c_fb_rrs;
        v_result.ide_bit           := c_fb_ide;
        v_result.fdf_bit           := c_fb_fdf;
        v_result.res_bit           := c_fb_res;
        v_result.brs_bit           := (position => c_fb_brs.position, polarity => v_brs_polarity);
        v_result.esi_bit           := (position => c_fb_esi.position, polarity => v_esi_polarity);
        v_result.srr_bit           := c_unknown_bit;
        v_result.rtr_bit           := c_unknown_bit;
        v_result.r0_bit            := c_unknown_bit;
        v_result.r1_bit            := c_unknown_bit;

      when fd_extended =>
        v_data_start             := c_fe_data_start.position;
        v_result.dlc_start         := c_fe_dlc_start.position;
        v_result.base_id_start     := c_fe_base_id_start.position;
        v_result.base_id_stop      := c_fe_base_id_start.position + (c_base_id_width - 1);
        v_result.extended_id_start := c_fe_extended_id_start.position;
        v_result.extended_id_stop  := c_fe_extended_id_start.position + (c_extended_id_width - 1);
        v_result.srr_bit           := c_fe_srr;
        v_result.ide_bit           := c_fe_ide;
        v_result.rrs_bit           := c_fe_rrs;
        v_result.fdf_bit           := c_fe_fdf;
        v_result.res_bit           := c_fe_res;
        v_result.brs_bit           := (position => c_fe_brs.position, polarity => v_brs_polarity);
        v_result.esi_bit           := (position => c_fe_esi.position, polarity => v_esi_polarity);
        v_result.rtr_bit           := c_unknown_bit;
        v_result.r0_bit            := c_unknown_bit;
        v_result.r1_bit            := c_unknown_bit;

      when others =>
        v_data_start             := 0;
        v_result.dlc_start         := 0;
        v_result.base_id_start     := 0;
        v_result.base_id_stop      := 0;
        v_result.extended_id_start := 0;
        v_result.extended_id_stop  := 0;
        v_result.rtr_bit           := c_unknown_bit;
        v_result.ide_bit           := c_unknown_bit;
        v_result.srr_bit           := c_unknown_bit;
        v_result.rrs_bit           := c_unknown_bit;
        v_result.fdf_bit           := c_unknown_bit;
        v_result.res_bit           := c_unknown_bit;
        v_result.r0_bit            := c_unknown_bit;
        v_result.r1_bit            := c_unknown_bit;
        v_result.brs_bit           := c_unknown_bit;
        v_result.esi_bit           := c_unknown_bit;
    end case;

    -- Calculate all data and CRC field positions
    v_result.data_start := v_data_start;

    if (v_data_bits > 0) then
      v_result.data_stop := v_data_start + (v_data_bits - 1);
    else
      v_result.data_stop := v_data_start;
    end if;

    -- DLC field boundaries
    v_result.dlc_stop := v_result.dlc_start + c_dlc_field_width;

    v_crc_length     := get_crc_length(v_result.format, v_data_length);
    v_result.crc_start := v_result.data_stop + 1;

    -- CAN FD has SBC field after data, CAN Classic goes directly to CRC
    if (v_result.is_fd_frame) then
      v_sbc_start         := v_result.crc_start;
      v_result.sbc_start    := v_sbc_start;
      v_result.sbc_stop     := v_sbc_start + c_sbc_field_width;
      v_result.crc_start    := v_result.sbc_stop;
      v_fixed_stuff_count := get_fixed_stuff_bit_count(c_sbc_field_width + v_crc_length);
      v_crc_field_length  := v_crc_length + v_fixed_stuff_count;
      v_result.crc_stop     := v_result.crc_start + v_crc_field_length;
    else
      v_result.sbc_start   := 0;
      v_result.sbc_stop    := 0;
      v_crc_field_length := v_crc_length;
      v_result.crc_start   := v_result.data_stop + 1;
      v_result.crc_stop    := v_result.crc_start + v_crc_length;
    end if;

    v_result.crc_delimiter := v_result.crc_stop;

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

    -- ACK and EOF field positions
    v_result.ack_slot      := v_result.crc_delimiter + 1;
    v_result.ack_delimiter := v_result.ack_slot + 1;
    v_result.eof_start     := v_result.ack_delimiter + 1;
    v_result.eof_stop      := v_result.eof_start + c_eof_field_width;

    return v_result;

  end function f_calculate_frame_params;

    -------------------------------------------------------------------------
    -- Procedures
    -------------------------------------------------------------------------

    -- Report transfer status to LLC and drive ready based on state
    procedure report_status_to_llc is
    begin

      v_llc_o.transfer_status := llc_o.transfer_status;

      if (v_transmission_completed) then
        v_llc_o.transfer_status := tx_mac_fsm_i.transfer_status;
      elsif (v_state = load_config_byte_0) then
        v_llc_o.transfer_status := ongoing;
      end if;

      case v_state is
        when load_config_byte_0 | load_config_byte_1 | load_llc_frame_byte =>
          v_llc_o.avalon_st_sink.ready := '1';
        when others =>
          v_llc_o.avalon_st_sink.ready := '0';
      end case;

    end procedure report_status_to_llc;

    -- Latch config byte 0 on SOP
    procedure capture_config_byte_0 is
    begin

      if (v_llc_valid and v_llc_sop) then
        v_config_byte_0 := llc_i.avalon_st_source.data;
      end if;

    end procedure capture_config_byte_0;

    -- Latch config byte 1 and initialize frame params and ID padding counters
    procedure capture_config_byte_1 is
    begin

      if (v_llc_valid) then
        if (v_llc_sop) then
          -- Resync: treat as a new config byte 0
          v_config_byte_0 := llc_i.avalon_st_source.data;
        else
          v_tx_mac_fsm_o.frame_params := f_calculate_frame_params(config_byte_0, llc_i.avalon_st_source.data);

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

    -- Load a new byte and optionally present MSB to FSM
    procedure load_byte is
    begin

      if (v_llc_valid and not v_llc_sop) then
        v_frame_buffer := llc_i.avalon_st_source.data;
        v_count        := t_byte'left;

        if (not v_in_id_padding) then
          v_tx_mac_fsm_o.data  := bit_to_polarity(llc_i.avalon_st_source.data(t_byte'left));
          v_tx_mac_fsm_o.valid := true;
        end if;
      end if;

    end procedure load_byte;

    -- Auto-consume one padding bit without presenting to FSM
    procedure consume_padding_bit is
    begin

      v_padding_bits_remaining := padding_bits_remaining - 1;

      if (count = 0) then
        v_count := t_byte'left;
      else
        v_frame_buffer := llc_frame_buffer sll 1;
        v_count        := count - 1;
      end if;

    end procedure consume_padding_bit;

    -- Shift out one normal (non-padding) bit with FSM handshake
    procedure shift_normal_bit is
    begin

      v_tx_mac_fsm_o.valid := true;
      v_tx_mac_fsm_o.data  := bit_to_polarity(llc_frame_buffer(t_byte'left));

      if (v_transmission_completed) then
        v_tx_mac_fsm_o.valid := false;
        v_count              := t_byte'left;
      elsif (v_fsm_consumed_bit) then
        if (id_bits_remaining > 0) then
          v_id_bits_remaining := id_bits_remaining - 1;
        end if;

        if (count = 0) then
          v_tx_mac_fsm_o.valid := false;
          v_count              := t_byte'left;
        else
          v_frame_buffer := llc_frame_buffer sll 1;
          v_count        := count - 1;
        end if;
      end if;

    end procedure shift_normal_bit;

  begin

    if rising_edge(clk_i) then
      if (reset_i = '1') then
        state                  <= load_config_byte_0;
        count                  <= t_byte'left;
        llc_frame_buffer       <= (others => '0');
        config_byte_0          <= (others => '0');
        id_bits_remaining      <= 0;
        padding_bits_remaining <= 0;

        llc_o        <= c_mac_to_llc_if_reset;
        tx_mac_fsm_o <= c_tx_mac_ser_to_fsm_if_reset;
      else
        -- Evaluate guards
        v_llc_valid              := llc_i.avalon_st_source.valid = '1';
        v_llc_sop                := llc_i.avalon_st_source.sop = '1';
        v_fsm_consumed_bit       := tx_mac_fsm_i.ready;
        v_transmission_completed := tx_mac_fsm_i.transfer_status /= ongoing;
        v_byte_finished          := count = 0;
        v_in_id_padding          := (id_bits_remaining = 0) and (padding_bits_remaining > 0);

        -- Defaults: hold registered values
        v_state                  := state;
        v_count                  := count;
        v_frame_buffer           := llc_frame_buffer;
        v_config_byte_0          := config_byte_0;
        v_id_bits_remaining      := id_bits_remaining;
        v_padding_bits_remaining := padding_bits_remaining;

        v_llc_o        := llc_o;
        v_tx_mac_fsm_o := tx_mac_fsm_o;

        -- Clear pulses
        v_llc_o.avalon_st_sink.ready := c_mac_to_llc_if_reset.avalon_st_sink.ready;
        v_tx_mac_fsm_o.valid         := c_tx_mac_ser_to_fsm_if_reset.valid;

        report_status_to_llc;

        -----------------------------------------------------------------
        -- State + output logic
        -----------------------------------------------------------------
        case state is
          when load_config_byte_0 =>
            capture_config_byte_0;
            if (v_llc_valid and v_llc_sop) then
              v_state := load_config_byte_1;
            end if;

          when load_config_byte_1 =>
            capture_config_byte_1;
            if (v_llc_valid) then
              if (v_llc_sop) then
                v_state := load_config_byte_1;
              else
                v_state := load_llc_frame_byte;
              end if;
            end if;

          when load_llc_frame_byte =>
            load_byte;
            if (v_transmission_completed) then
              v_state := load_config_byte_0;
            elsif (v_llc_valid) then
              if (v_llc_sop) then
                v_state := load_config_byte_1;
              else
                v_state := shift_out_bits;
              end if;
            end if;

          when shift_out_bits =>
            if (v_in_id_padding) then
              consume_padding_bit;
              if (v_byte_finished) then
                v_state := load_llc_frame_byte;
              end if;
            else
              shift_normal_bit;
              if (v_transmission_completed) then
                v_state := load_config_byte_0;
              elsif (v_fsm_consumed_bit and v_byte_finished) then
                v_state := load_llc_frame_byte;
              end if;
            end if;

          when others =>
            null;
        end case;

        -----------------------------------------------------------------
        -- Register outputs
        -----------------------------------------------------------------
        state                  <= v_state;
        count                  <= v_count;
        llc_frame_buffer       <= v_frame_buffer;
        config_byte_0          <= v_config_byte_0;
        id_bits_remaining      <= v_id_bits_remaining;
        padding_bits_remaining <= v_padding_bits_remaining;

        llc_o        <= v_llc_o;
        tx_mac_fsm_o <= v_tx_mac_fsm_o;
      end if;
    end if;

  end process p_fsm;

end architecture rtl;

-- eof
