library ieee;
  use ieee.std_logic_1164.all;
  use work.can_types_pkg.all;
  use work.can_protocol_pkg.all;
  use work.can_timing_pkg.all;

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

  ---------------------------------------------------------------------------
  -- Registered state signals (driven by state_update)
  ---------------------------------------------------------------------------
  signal state_reg           : tx_mac_ser_state_t;
  signal count               : integer range byte_t'left downto 0;
  signal llc_frame_buffer    : byte_t;
  signal config_byte_reg_0   : byte_t;
  signal transfer_status_reg : transfer_status_t;

  ---------------------------------------------------------------------------
  -- Combinational next-cycle signals (driven by output_logic)
  ---------------------------------------------------------------------------
  signal next_state           : tx_mac_ser_state_t;
  signal next_count           : integer range byte_t'left downto 0;
  signal next_frame_buffer    : byte_t;
  signal next_config_byte_0   : byte_t;
  signal next_transfer_status : transfer_status_t;

  -- Intermediate signals for registered outputs
  signal next_llc_o        : mac_to_llc_if_t;
  signal next_tx_mac_fsm_o : tx_mac_ser_to_fsm_if_t;

begin

  ---------------------------------------------------------------------------
  -- Process 1: next_state_logic (combinational)
  ---------------------------------------------------------------------------
  next_state_logic : process (all) is

    -- Named guard variables (RTL guide Rule 3)
    variable llc_valid_v        : boolean;
    variable llc_sop_v          : boolean;
    variable fsm_consumed_bit_v : boolean;
    variable fsm_finished_v     : boolean;
    variable byte_finished_v    : boolean;

  begin

    -- Evaluate guards
    llc_valid_v        := llc_i.avalon_st_source.valid = '1';
    llc_sop_v          := llc_i.avalon_st_source.sop = '1';
    fsm_consumed_bit_v := tx_mac_fsm_i.ready;
    fsm_finished_v     := tx_mac_fsm_i.transfer_status /= ongoing;
    byte_finished_v    := count = 0;

    -- Default: hold current state
    next_state <= state_reg;

    case state_reg is
      when load_config_byte_0 =>
        if (llc_valid_v and llc_sop_v) then
          next_state <= load_config_byte_1;
        end if;

      when load_config_byte_1 =>
        if (llc_valid_v) then
          if (llc_sop_v) then
            next_state <= load_config_byte_1;                      -- Resync
          else
            next_state <= load_llc_frame_byte;
          end if;
        end if;

      when load_llc_frame_byte =>
        if (llc_valid_v) then
          if (llc_sop_v) then
            next_state <= load_config_byte_1;                      -- Resync
          else
            next_state <= shift_out_bits;
          end if;
        end if;

      when shift_out_bits =>
        if (fsm_finished_v) then
          next_state <= load_config_byte_0;
        elsif (fsm_consumed_bit_v) then
          if (byte_finished_v) then
            next_state <= load_llc_frame_byte;
          end if;
        end if;

      when others =>
        null;
    end case;

  end process next_state_logic;

  ---------------------------------------------------------------------------
  -- Process 2: output_logic (combinational Mealy)
  ---------------------------------------------------------------------------
  output_logic : process (all) is

    -- Named guards
    variable llc_valid_v        : boolean;
    variable llc_sop_v          : boolean;
    variable fsm_consumed_bit_v : boolean;
    variable fsm_finished_v     : boolean;

    -------------------------------------------------------------------------
    -- Local procedures for state logic abstraction
    -------------------------------------------------------------------------

    -- Handle configuration and handshake with LLC
    procedure report_status_to_llc is
    begin

      -- Default: hold registered status
      next_llc_o.transfer_status <= transfer_status_reg;

      -- Update status from MAC FSM feedback
      if (tx_mac_fsm_i.transfer_status /= ongoing) then
        next_llc_o.transfer_status <= tx_mac_fsm_i.transfer_status;
        next_transfer_status       <= tx_mac_fsm_i.transfer_status;
      elsif (state_reg = load_config_byte_0) then
        -- Reset status when starting or waiting for a new frame
        next_llc_o.transfer_status <= ongoing;
        next_transfer_status       <= ongoing;
      end if;

      -- Drive ready based on state
      case state_reg is
        when load_config_byte_0 | load_config_byte_1 | load_llc_frame_byte =>
          next_llc_o.avalon_st_sink.ready <= '1';
        when others =>
          next_llc_o.avalon_st_sink.ready <= '0';
      end case;

    end procedure report_status_to_llc;

    -- Handle bit shifting and handshaking with MAC FSM
    procedure manage_serialization is
    begin

      case state_reg is
        when load_llc_frame_byte =>
          if (llc_valid_v and not llc_sop_v) then
            -- Load byte and present MSB immediately
            next_frame_buffer       <= llc_i.avalon_st_source.data;
            next_tx_mac_fsm_o.data  <= bit_to_polarity(llc_i.avalon_st_source.data(byte_t'left));
            next_tx_mac_fsm_o.valid <= true;
            next_count              <= byte_t'left;
          end if;

        when shift_out_bits =>
          -- Hold valid while we have bits remaining
          next_tx_mac_fsm_o.valid <= true;
          next_tx_mac_fsm_o.data  <= bit_to_polarity(llc_frame_buffer(byte_t'left));

          if (fsm_finished_v) then
            next_tx_mac_fsm_o.valid <= false;
            next_count              <= byte_t'left;
          elsif (fsm_consumed_bit_v) then
            if (count = 0) then
              -- Byte finished, prepare for next fetch
              next_tx_mac_fsm_o.valid <= false;
              next_count              <= byte_t'left;
            else
              -- Shift to next bit
              next_frame_buffer <= llc_frame_buffer sll 1;
              next_count        <= count - 1;
            end if;
          end if;

        when others =>
          null;
      end case;

    end procedure manage_serialization;

    -- Handle configuration capture and frame param calculation
    procedure manage_config_capture is
    begin

      if (llc_valid_v) then
        if (state_reg = load_config_byte_0 and llc_sop_v) then
          next_config_byte_0   <= llc_i.avalon_st_source.data;
          next_transfer_status <= ongoing;
        elsif (state_reg = load_config_byte_1) then
          if (llc_sop_v) then
            next_config_byte_0 <= llc_i.avalon_st_source.data; -- Resync
          else
            -- Calculate and cache parameters once at start of frame
            next_tx_mac_fsm_o.frame_params <= calculate_frame_params(config_byte_reg_0, llc_i.avalon_st_source.data);
          end if;
        end if;
      end if;

    end procedure manage_config_capture;

  begin

    -- Evaluate guards
    llc_valid_v        := llc_i.avalon_st_source.valid = '1';
    llc_sop_v          := llc_i.avalon_st_source.sop = '1';
    fsm_consumed_bit_v := tx_mac_fsm_i.ready;
    fsm_finished_v     := tx_mac_fsm_i.transfer_status /= ongoing;

    -------------------------------------------------------------------------
    -- Output defaults: hold current registered values
    -------------------------------------------------------------------------
    next_count           <= count;
    next_frame_buffer    <= llc_frame_buffer;
    next_config_byte_0   <= config_byte_reg_0;
    next_transfer_status <= transfer_status_reg;

    next_llc_o        <= llc_o;
    next_tx_mac_fsm_o <= tx_mac_fsm_o;

    -- Clear pulse/level control signals
    next_tx_mac_fsm_o.valid <= false;

    -------------------------------------------------------------------------
    -- Logic evaluation
    -------------------------------------------------------------------------
    report_status_to_llc;
    manage_config_capture;
    manage_serialization;

  end process output_logic;

  ---------------------------------------------------------------------------
  -- Process 3: state_update (clocked)
  ---------------------------------------------------------------------------
  state_update : process (clk_i) is
  begin

    if rising_edge(clk_i) then
      if (rst_i = '1') then
        state_reg           <= load_config_byte_0;
        count               <= byte_t'left;
        llc_frame_buffer    <= (others => '0');
        config_byte_reg_0   <= (others => '0');
        transfer_status_reg <= ongoing;

        llc_o        <= mac_to_llc_if_reset_c;
        tx_mac_fsm_o <= tx_mac_ser_to_fsm_if_reset_c;
      else
        state_reg           <= next_state;
        count               <= next_count;
        llc_frame_buffer    <= next_frame_buffer;
        config_byte_reg_0   <= next_config_byte_0;
        transfer_status_reg <= next_transfer_status;

        llc_o        <= next_llc_o;
        tx_mac_fsm_o <= next_tx_mac_fsm_o;
      end if;
    end if;

  end process state_update;

end architecture rtl;
