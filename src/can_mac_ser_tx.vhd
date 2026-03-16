--------------------------------------------------------------------------------------------------------------------------------------------------------------
-- Copyright 2026 Everllence, Teglholmsgade 41, 2450 Copenhagen SV, Denmark
--------------------------------------------------------------------------------------------------------------------------------------------------------------
--
-- Requirements:
--
-- Description:   MAC serializer for CAN/CAN-FD TX path. Accepts LLC frame
--                bytes via Avalon-ST and shifts them out bit-by-bit to the
--                MAC FSM. Handles config byte capture, ID padding skip, and
--                frame parameter calculation.
--
-- Revision log:  Date:       Initial:  JIRA:
--                2026-03-16  TMYAES    Initial version
--
--------------------------------------------------------------------------------------------------------------------------------------------------------------

library ieee;
  use ieee.std_logic_1164.all;
  use ieee.numeric_std.all;
  use work.pk_can_types.all;
  use work.can_protocol_pkg.all;

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

    -- Registered next-value variables
    variable v_state                  : t_state;
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

    -------------------------------------------------------------------------
    -- Procedures
    -------------------------------------------------------------------------

    procedure report_status_to_llc is
    begin

      v_llc_o.transfer_status := llc_o.transfer_status;

      if (v_transmission_completed) then
        v_llc_o.transfer_status := tx_mac_fsm_i.transfer_status;
      elsif (v_state = load_config_byte_0) then
        v_llc_o.transfer_status := c_ongoing;
      end if;

      case v_state is
        when load_config_byte_0 | load_config_byte_1 | load_llc_frame_byte =>
          v_llc_o.avalon_st_sink.ready := '1';
        when others =>
          v_llc_o.avalon_st_sink.ready := '0';
      end case;

    end procedure report_status_to_llc;

    procedure capture_config_byte_0 is
    begin

      if (v_llc_valid and v_llc_sop) then
        v_config_byte_0 := llc_i.avalon_st_source.data;
      end if;

    end procedure capture_config_byte_0;

    procedure capture_config_byte_1 is
    begin

      if (v_llc_valid) then
        if (v_llc_sop) then
          v_config_byte_0 := llc_i.avalon_st_source.data;
        else
          v_tx_mac_fsm_o.frame_params := calculate_frame_params(config_byte_0, llc_i.avalon_st_source.data);

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

      if (v_llc_valid and not v_llc_sop) then
        v_frame_buffer := llc_i.avalon_st_source.data;
        v_count        := t_byte'left;

        if (not v_in_id_padding) then
          v_tx_mac_fsm_o.data  := llc_i.avalon_st_source.data(t_byte'left);
          v_tx_mac_fsm_o.valid := '1';
        end if;
      end if;

    end procedure load_byte;

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

    procedure shift_normal_bit is
    begin

      v_tx_mac_fsm_o.valid := '1';
      v_tx_mac_fsm_o.data  := llc_frame_buffer(t_byte'left);

      if (v_transmission_completed) then
        v_tx_mac_fsm_o.valid := '0';
        v_count              := t_byte'left;
      elsif (v_fsm_consumed_bit) then
        if (id_bits_remaining > 0) then
          v_id_bits_remaining := id_bits_remaining - 1;
        end if;

        if (count = 0) then
          v_tx_mac_fsm_o.valid := '0';
          v_count              := t_byte'left;
        else
          v_frame_buffer := llc_frame_buffer sll 1;
          v_count        := count - 1;
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
        -- Evaluate guards
        v_llc_valid              := llc_i.avalon_st_source.valid = '1';
        v_llc_sop                := llc_i.avalon_st_source.sop = '1';
        v_fsm_consumed_bit       := tx_mac_fsm_i.ready = '1';
        v_transmission_completed := tx_mac_fsm_i.transfer_status /= c_ongoing;
        v_byte_finished          := count = 0;
        v_in_id_padding          := id_bits_remaining = 0 and padding_bits_remaining > 0;

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
