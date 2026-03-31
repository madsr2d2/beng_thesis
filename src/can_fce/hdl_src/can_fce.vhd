--------------------------------------------------------------------------------------------------------------------------------------------------------------
-- Copyright 2026 Everllence, Teglholmsgade 41, 2450 Copenhagen SV, Denmark
--------------------------------------------------------------------------------------------------------------------------------------------------------------
--
-- Requirements:
--
-- Description:   Fault Confinement Entity per ISO 11898-1:2015 Section 8.1.4.
--                Manages TEC/REC counters and error state for both TX and RX
--                MAC paths. Shared supervisor - one instance per CAN node.
--                Interfaces (per ISO 11898-1 Tables 14-19):
--                LLC: Normal_mode_request/response, Bus_off indication
--                MAC: Error counting signals, Error_passive/active requests
--                PCS: Bus_off_request/release for physical disconnection
--                Counter update rules follow ISO 8.1.4.2 Table 16/17.
--                State transitions follow ISO 8.1.4.1 (T2-T5).
--                Bus-off recovery uses internal 11-bit idle detection.
--
-- Revision log:  Date:       Initial:  JIRA:
--                2026-03-31  MRDSA     Converted to company header format
--------------------------------------------------------------------------------------------------------------------------------------------------------------

library ieee;
  use ieee.std_logic_1164.all;
  use ieee.numeric_std.all;
  use work.pk_can_types.all;

entity can_fce is
  generic (
    gc_nom_bit_time : integer := 200
  );
  port (
    clk_i : in    std_logic;
    rst_i : in    std_logic;

    -- LLC interface (ISO 11898-1 Tables 14/15)
    llc_i : in    t_can_llc_fce_if_m2s;
    llc_o : out   t_can_fce_llc_if_s2m;

    -- TX MAC interface (ISO 11898-1 Tables 16/17)
    tx_mac_i : in    t_can_mac_fce_if_m2s;
    tx_mac_o : out   t_can_mac_fce_if_s2m;

    -- RX MAC interface (ISO 11898-1 Tables 16/17)
    rx_mac_i : in    t_can_mac_fce_if_m2s;
    rx_mac_o : out   t_can_mac_fce_if_s2m;

    -- PCS interface (ISO 11898-1 Tables 18/19)
    pcs_i : in    t_can_pcs_fce_if_s2m;
    pcs_o : out   t_can_fce_pcs_if_m2s;

    -- Raw bus for idle detection (bus-off recovery)
    rx_bus_i : in    std_logic;

    -- Debug output
    debug_tec_o   : out   integer range 0 to 511;
    debug_rec_o   : out   integer range 0 to 255;
    debug_state_o : out   std_logic_vector(1 downto 0)
  );
end entity can_fce;

architecture rtl of can_fce is

  -- FCE error states (ISO 8.1.4.1)
  constant c_error_active  : std_logic_vector(1 downto 0) := "00";
  constant c_error_passive : std_logic_vector(1 downto 0) := "01";
  constant c_bus_off       : std_logic_vector(1 downto 0) := "10";

  signal tec       : integer range 0 to 511;
  signal rec       : integer range 0 to 255;
  signal fce_state : std_logic_vector(1 downto 0);

  -- Bus-off recovery: idle detection
  signal idle_shift_reg  : std_logic_vector(10 downto 0);
  signal idle_count      : integer range 0 to 127;
  signal prescaler_count : integer range 0 to gc_nom_bit_time - 1;

  -- Guard: bus-off recovery active
  signal bus_off_active : std_logic;

begin

  bus_off_active <= '1' when fce_state = c_bus_off else '0';

  fce_proc : process (clk_i) is

    variable v_tec       : integer range 0 to 511;
    variable v_rec       : integer range 0 to 255;
    variable v_fce_state : std_logic_vector(1 downto 0);

    -- Named guard predicates for counter rules
    variable v_tx_error             : boolean;
    variable v_tx_error_delim_late  : boolean;
    variable v_rx_error_delim_late  : boolean;
    variable v_tx_success           : boolean;
    variable v_rx_error             : boolean;
    variable v_rx_primary_error     : boolean;
    variable v_rx_error_during_flag : boolean;
    variable v_rx_success           : boolean;
    variable v_normal_mode_request  : boolean;

  begin

    if rising_edge(clk_i) then
      if (rst_i = '1') then
        tec              <= 0;
        rec              <= 0;
        fce_state        <= c_error_active;
        idle_shift_reg   <= (others => '0');
        idle_count       <= 0;
        prescaler_count  <= 0;

        tx_mac_o <= c_fce_to_mac_if_reset;
        rx_mac_o <= c_fce_to_mac_if_reset;
        llc_o    <= c_fce_to_llc_if_reset;
        pcs_o    <= c_fce_to_pcs_if_reset;
      else
        -- Evaluate guards
        v_normal_mode_request := llc_i.normal_mode_request = '1';

        -- Snapshot current values
        v_tec       := tec;
        v_rec       := rec;
        v_fce_state := fce_state;

        -- Clear pulse outputs
        llc_o.normal_mode_response <= '0';
        pcs_o.bus_off_request         <= '0';
        pcs_o.bus_off_release_request <= '0';

        -----------------------------------------------------------------------
        -- LLC normal_mode_request: reset counters (ISO T5 alternative path)
        -----------------------------------------------------------------------
        if (v_normal_mode_request and v_fce_state = c_bus_off) then
          -- Only honoured during bus-off recovery after 128 idle sequences
          -- (handled below in state transitions). LLC can also force reset.
          null; -- Actual reset happens in state transition below
        end if;

        -----------------------------------------------------------------------
        -- Bus-off recovery: prescaler and idle detection (gated)
        -----------------------------------------------------------------------
        if (bus_off_active = '1') then
          if (prescaler_count = gc_nom_bit_time - 1) then
            prescaler_count <= 0;

            -- Shift in current bus sample
            idle_shift_reg <= idle_shift_reg(9 downto 0) & rx_bus_i;

            -- Check for 11 consecutive recessive bits
            if (idle_shift_reg(9 downto 0) & rx_bus_i = "11111111111") then
              if (idle_count < 127) then
                idle_count <= idle_count + 1;
              end if;
            end if;
          else
            prescaler_count <= prescaler_count + 1;
          end if;
        else
          -- Gated inactive: hold reset values
          prescaler_count <= 0;
          idle_shift_reg  <= (others => '0');
          idle_count      <= 0;
        end if;

        -----------------------------------------------------------------------
        -- Counter update rules (ISO 8.1.4.2) - not in bus_off
        -----------------------------------------------------------------------
        if (v_fce_state /= c_bus_off) then

          -- Named guard predicates
          v_tx_error             := tx_mac_i.error = '1' and tx_mac_i.transmitting = '1' and
                                    tx_mac_i.counters_unchanged = '0';
          v_tx_error_delim_late  := tx_mac_i.error_delimiter_too_late = '1' and tx_mac_i.transmitting = '1';
          v_rx_error_delim_late  := rx_mac_i.error_delimiter_too_late = '1' and rx_mac_i.transmitting = '0';
          v_tx_success           := tx_mac_i.successful_transfer = '1';
          v_rx_error             := rx_mac_i.error = '1' and rx_mac_i.transmitting = '0' and
                                    rx_mac_i.sending_error_overload_flag = '0';
          v_rx_primary_error     := rx_mac_i.primary_error = '1' and rx_mac_i.transmitting = '0';
          v_rx_error_during_flag := rx_mac_i.error = '1' and rx_mac_i.sending_error_overload_flag = '1' and
                                    rx_mac_i.transmitting = '0';
          v_rx_success           := rx_mac_i.successful_transfer = '1';

          -- Rule c: TX error -> TEC += 8
          if (v_tx_error) then
            if (v_tec <= 503) then
              v_tec := v_tec + 8;
            else
              v_tec := 511;
            end if;
          end if;

          -- Rule d/f: TX error delimiter too late -> TEC += 8
          if (v_tx_error_delim_late) then
            if (v_tec <= 503) then
              v_tec := v_tec + 8;
            else
              v_tec := 511;
            end if;
          end if;

          -- Rule f (RX): RX error delimiter too late -> REC += 8
          if (v_rx_error_delim_late) then
            if (v_rec <= 247) then
              v_rec := v_rec + 8;
            else
              v_rec := 255;
            end if;
          end if;

          -- Rule g: TX success -> TEC -= 1 (if > 0)
          if (v_tx_success) then
            if (v_tec > 0) then
              v_tec := v_tec - 1;
            end if;
          end if;

          -- Rule a: RX error (not during flag) -> REC += 1
          if (v_rx_error) then
            if (v_rec < 255) then
              v_rec := v_rec + 1;
            end if;
          end if;

          -- Rule b: RX primary error -> REC += 8
          if (v_rx_primary_error) then
            if (v_rec <= 247) then
              v_rec := v_rec + 8;
            else
              v_rec := 255;
            end if;
          end if;

          -- Rule e: RX error during error flag -> REC += 8
          if (v_rx_error_during_flag) then
            if (v_rec <= 247) then
              v_rec := v_rec + 8;
            else
              v_rec := 255;
            end if;
          end if;

          -- Rule h: RX success -> REC adjustment
          if (v_rx_success) then
            if (v_rec > 127) then
              v_rec := 127;
            elsif (v_rec > 0) then
              v_rec := v_rec - 1;
            end if;
          end if;

        end if; -- not bus_off

        -----------------------------------------------------------------------
        -- State transitions (evaluated after counter updates)
        -----------------------------------------------------------------------
        -- T4: TEC > 255 -> bus_off (highest priority)
        if (v_tec > 255 and v_fce_state /= c_bus_off) then
          v_fce_state                   := c_bus_off;
          pcs_o.bus_off_request         <= '1';

        -- T5: bus_off recovery (128 idle sequences) or normal_mode_request
        elsif (v_fce_state = c_bus_off and (idle_count = 127 or v_normal_mode_request)) then
          v_fce_state                       := c_error_active;
          v_tec                             := 0;
          v_rec                             := 0;
          llc_o.normal_mode_response        <= '1';
          pcs_o.bus_off_release_request     <= '1';

        -- T2: counter > 127 -> error_passive
        elsif (v_fce_state = c_error_active and (v_tec > 127 or v_rec > 127)) then
          v_fce_state := c_error_passive;

        -- T3: both counters <= 127 -> error_active
        elsif (v_fce_state = c_error_passive and v_tec <= 127 and v_rec <= 127) then
          v_fce_state := c_error_active;

        end if;

        -- Register updates
        tec       <= v_tec;
        rec       <= v_rec;
        fce_state <= v_fce_state;

        -- MAC state outputs (registered, derived from next state)
        if (v_fce_state = c_error_passive or v_fce_state = c_bus_off) then
          tx_mac_o.error_passive_request <= '1';
          tx_mac_o.error_active_request  <= '0';
          rx_mac_o.error_passive_request <= '1';
          rx_mac_o.error_active_request  <= '0';
        else
          tx_mac_o.error_passive_request <= '0';
          tx_mac_o.error_active_request  <= '1';
          rx_mac_o.error_passive_request <= '0';
          rx_mac_o.error_active_request  <= '1';
        end if;

        -- Bus-off indication (registered, to LLC and MAC)
        if (v_fce_state = c_bus_off) then
          llc_o.bus_off    <= '1';
          tx_mac_o.bus_off <= '1';
          rx_mac_o.bus_off <= '1';
        else
          llc_o.bus_off    <= '0';
          tx_mac_o.bus_off <= '0';
          rx_mac_o.bus_off <= '0';
        end if;

      end if; -- rst
    end if; -- rising_edge

  end process fce_proc;

  debug_tec_o   <= tec;
  debug_rec_o   <= rec;
  debug_state_o <= fce_state;

end architecture rtl;
