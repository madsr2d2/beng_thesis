library ieee;
  use ieee.std_logic_1164.all;
  use work.can_types_pkg.all;
  use work.can_protocol_pkg.all;

entity tx_mac_ser is
  port (
    -- Clock and reset
    clk_i : in    std_logic;
    rst_i : in    std_logic;

    -- LLC interface
    llc_i : in    llc_to_mac_if_t;
    llc_o : out   mac_to_llc_if_t;

    -- tx_mac_fsm interface
    tx_mac_fsm_i : in    tx_mac_fsm_to_ser_if_t;
    tx_mac_fsm_o : out   tx_mac_ser_to_fsm_if_t
  );
end entity tx_mac_ser;

architecture rtl of tx_mac_ser is

  signal state                  : tx_mac_ser_state_t;
  signal count                  : integer range byte_t'left downto 0;
  signal llc_frame_buffer       : byte_t;
  signal config_byte_0          : byte_t;
  signal id_bits_remaining      : integer range 0 to base_id_width_c + extended_id_width_c;
  signal padding_bits_remaining : integer range 0 to llc_id_stream_width_c - base_id_width_c;

begin

  fsm_sequential : process (clk_i) is

    -- Registered next-value variables
    variable v_state                  : tx_mac_ser_state_t;
    variable v_count                  : integer range byte_t'left downto 0;
    variable v_frame_buffer           : byte_t;
    variable v_config_byte_0          : byte_t;
    variable v_id_bits_remaining      : integer range 0 to base_id_width_c + extended_id_width_c;
    variable v_padding_bits_remaining : integer range 0 to llc_id_stream_width_c - base_id_width_c;

    variable v_llc_o        : mac_to_llc_if_t;
    variable v_tx_mac_fsm_o : tx_mac_ser_to_fsm_if_t;

    -- Named guard variables (evaluated once per cycle)
    variable llc_valid_v              : boolean;
    variable llc_sop_v                : boolean;
    variable fsm_consumed_bit_v       : boolean;
    variable transmission_completed_v : boolean;
    variable byte_finished_v          : boolean;
    variable in_id_padding_v          : boolean;

    -------------------------------------------------------------------------
    -- Procedures
    -------------------------------------------------------------------------

    -- Report transfer status to LLC and drive ready based on state
    procedure report_status_to_llc is
    begin

      v_llc_o.transfer_status := llc_o.transfer_status;

      if (transmission_completed_v) then
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

      if (llc_valid_v and llc_sop_v) then
        v_config_byte_0 := llc_i.avalon_st_source.data;
      end if;

    end procedure capture_config_byte_0;

    -- Latch config byte 1 and initialize frame params and ID padding counters
    procedure capture_config_byte_1 is
    begin

      if (llc_valid_v) then
        if (llc_sop_v) then
          -- Resync: treat as a new config byte 0
          v_config_byte_0 := llc_i.avalon_st_source.data;
        else
          v_tx_mac_fsm_o.frame_params := calculate_frame_params(config_byte_0, llc_i.avalon_st_source.data);

          if (config_byte_0(llc_frame_config_byte_0_extended_bit) = '1') then
            v_id_bits_remaining      := base_id_width_c + extended_id_width_c;
            v_padding_bits_remaining := llc_id_stream_width_c - base_id_width_c - extended_id_width_c;
          else
            v_id_bits_remaining      := base_id_width_c;
            v_padding_bits_remaining := llc_id_stream_width_c - base_id_width_c;
          end if;
        end if;
      end if;

    end procedure capture_config_byte_1;

    -- Load a new byte and optionally present MSB to FSM
    procedure load_byte is
    begin

      if (llc_valid_v and not llc_sop_v) then
        v_frame_buffer := llc_i.avalon_st_source.data;
        v_count        := byte_t'left;

        if (not in_id_padding_v) then
          v_tx_mac_fsm_o.data  := bit_to_polarity(llc_i.avalon_st_source.data(byte_t'left));
          v_tx_mac_fsm_o.valid := true;
        end if;
      end if;

    end procedure load_byte;

    -- Auto-consume one padding bit without presenting to FSM
    procedure consume_padding_bit is
    begin

      v_padding_bits_remaining := padding_bits_remaining - 1;

      if (count = 0) then
        v_count := byte_t'left;
      else
        v_frame_buffer := llc_frame_buffer sll 1;
        v_count        := count - 1;
      end if;

    end procedure consume_padding_bit;

    -- Shift out one normal (non-padding) bit with FSM handshake
    procedure shift_normal_bit is
    begin

      v_tx_mac_fsm_o.valid := true;
      v_tx_mac_fsm_o.data  := bit_to_polarity(llc_frame_buffer(byte_t'left));

      if (transmission_completed_v) then
        v_tx_mac_fsm_o.valid := false;
        v_count              := byte_t'left;
      elsif (fsm_consumed_bit_v) then
        if (id_bits_remaining > 0) then
          v_id_bits_remaining := id_bits_remaining - 1;
        end if;

        if (count = 0) then
          v_tx_mac_fsm_o.valid := false;
          v_count              := byte_t'left;
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
        count                  <= byte_t'left;
        llc_frame_buffer       <= (others => '0');
        config_byte_0          <= (others => '0');
        id_bits_remaining      <= 0;
        padding_bits_remaining <= 0;

        llc_o        <= mac_to_llc_if_reset_c;
        tx_mac_fsm_o <= tx_mac_ser_to_fsm_if_reset_c;
      else
        -- Evaluate guards
        llc_valid_v              := llc_i.avalon_st_source.valid = '1';
        llc_sop_v                := llc_i.avalon_st_source.sop = '1';
        fsm_consumed_bit_v       := tx_mac_fsm_i.ready;
        transmission_completed_v := tx_mac_fsm_i.transfer_status /= ongoing;
        byte_finished_v          := count = 0;
        in_id_padding_v          := id_bits_remaining = 0 and padding_bits_remaining > 0;

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
        v_llc_o.avalon_st_sink.ready := mac_to_llc_if_reset_c.avalon_st_sink.ready;
        v_tx_mac_fsm_o.valid         := tx_mac_ser_to_fsm_if_reset_c.valid;

        report_status_to_llc;

        -----------------------------------------------------------------
        -- State + output logic
        -----------------------------------------------------------------
        case state is
          when load_config_byte_0 =>
            capture_config_byte_0;
            if (llc_valid_v and llc_sop_v) then
              v_state := load_config_byte_1;
            end if;

          when load_config_byte_1 =>
            capture_config_byte_1;
            if (llc_valid_v) then
              if (llc_sop_v) then
                v_state := load_config_byte_1;
              else
                v_state := load_llc_frame_byte;
              end if;
            end if;

          when load_llc_frame_byte =>
            load_byte;
            if (transmission_completed_v) then
              v_state := load_config_byte_0;
            elsif (llc_valid_v) then
              if (llc_sop_v) then
                v_state := load_config_byte_1;
              else
                v_state := shift_out_bits;
              end if;
            end if;

          when shift_out_bits =>
            if (in_id_padding_v) then
              consume_padding_bit;
              if (byte_finished_v) then
                v_state := load_llc_frame_byte;
              end if;
            else
              shift_normal_bit;
              if (transmission_completed_v) then
                v_state := load_config_byte_0;
              elsif (fsm_consumed_bit_v and byte_finished_v) then
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

  end process fsm_sequential;

end architecture rtl;
