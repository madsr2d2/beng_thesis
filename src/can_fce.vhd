--------------------------------------------------------------------------------
-- Title      : CAN Fault Confinement Entity
-- Project    : CAN Bus Node
--------------------------------------------------------------------------------
-- File       : can_fce.vhd
-- Standard   : VHDL-2008
--------------------------------------------------------------------------------
-- Description: Fault Confinement Entity per ISO 11898-1:2015 Section 8.1.4.
--              Manages TEC/REC counters and error state for both TX and RX
--              MAC paths. Shared supervisor - one instance per CAN node.
--
--              Counter update rules follow ISO 8.1.4.2 Table 16/17.
--              State transitions follow ISO 8.1.4.1 (T2-T5).
--              Bus-off recovery uses internal 11-bit idle detection.
--------------------------------------------------------------------------------

library ieee;
  use ieee.std_logic_1164.all;
  use ieee.numeric_std.all;
  use work.can_types_pkg.all;

entity can_fce is
  generic (
    -- Nominal bit time in clock cycles (prescaler * (sync + prop + ph1 + ph2))
    -- Used for bus-off idle detection sampling.
    nom_bit_time : integer := 200
  );
  port (
    clk_i : in    std_logic;
    rst_i : in    std_logic;

    -- TX MAC interface
    tx_mac_i : in    can_mac_fce_if_s2d_t;
    tx_mac_o : out   can_mac_fce_if_d2s_t;

    -- RX MAC interface (stub for now)
    rx_mac_i : in    can_mac_fce_if_s2d_t;
    rx_mac_o : out   can_mac_fce_if_d2s_t;

    -- Raw bus for idle detection (bus-off recovery)
    rx_bus_i : in    std_logic;

    -- Control interface
    ctrl_i : in    can_fce_ctrl_t;

    -- Status/debug output
    status_o : out   can_fce_status_t
  );
end entity can_fce;

architecture rtl of can_fce is

  signal tec       : integer range 0 to 511;
  signal rec       : integer range 0 to 255;
  signal fce_state : fce_state_t;

  -- Bus-off recovery: idle detection
  signal idle_shift_reg  : std_logic_vector(10 downto 0);
  signal idle_count      : integer range 0 to 127;
  signal prescaler_count : integer range 0 to nom_bit_time - 1;
  signal prescaler_tick  : boolean;

  -- Guard: bus-off recovery active
  signal bus_off_active : boolean;

begin

  bus_off_active <= (fce_state = bus_off);

  fce_proc : process (clk_i) is

    variable v_tec       : integer range 0 to 511;
    variable v_rec       : integer range 0 to 255;
    variable v_fce_state : fce_state_t;

    -- Named guard predicates for counter rules
    variable tx_error_v              : boolean;
    variable tx_error_delim_late_v   : boolean;
    variable rx_error_delim_late_v   : boolean;
    variable tx_success_v            : boolean;
    variable rx_error_v              : boolean;
    variable rx_primary_error_v      : boolean;
    variable rx_error_during_flag_v  : boolean;
    variable rx_success_v            : boolean;

  begin

    if rising_edge(clk_i) then
      if (rst_i = '1') then
        tec              <= 0;
        rec              <= 0;
        fce_state        <= error_active;
        idle_shift_reg   <= (others => '0');
        idle_count       <= 0;
        prescaler_count  <= 0;

      else
        -- Snapshot current values
        v_tec       := tec;
        v_rec       := rec;
        v_fce_state := fce_state;

        -----------------------------------------------------------------------
        -- Bus-off recovery: prescaler and idle detection (gated)
        -----------------------------------------------------------------------
        if (bus_off_active) then
          if (prescaler_count = nom_bit_time - 1) then
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
        -- Counter update rules (ISO 8.1.4.2) - only when error signalling enabled
        -----------------------------------------------------------------------
        if (ctrl_i.error_signalling_enabled and v_fce_state /= bus_off) then

          -- Named guard predicates
          tx_error_v             := tx_mac_i.error and tx_mac_i.transmitting and
                                    not tx_mac_i.counters_unchanged;
          tx_error_delim_late_v  := tx_mac_i.error_delimiter_too_late and tx_mac_i.transmitting;
          rx_error_delim_late_v  := rx_mac_i.error_delimiter_too_late and not rx_mac_i.transmitting;
          tx_success_v           := tx_mac_i.successful_transfer;
          rx_error_v             := rx_mac_i.error and not rx_mac_i.transmitting and
                                    not rx_mac_i.sending_error_flag;
          rx_primary_error_v     := rx_mac_i.primary_error and not rx_mac_i.transmitting;
          rx_error_during_flag_v := rx_mac_i.error and rx_mac_i.sending_error_flag and
                                    not rx_mac_i.transmitting;
          rx_success_v           := rx_mac_i.successful_transfer;

          -- Rule c: TX error -> TEC += 8
          if (tx_error_v) then
            if (v_tec <= 503) then
              v_tec := v_tec + 8;
            else
              v_tec := 511;
            end if;
          end if;

          -- Rule d/f: TX error delimiter too late -> TEC += 8
          if (tx_error_delim_late_v) then
            if (v_tec <= 503) then
              v_tec := v_tec + 8;
            else
              v_tec := 511;
            end if;
          end if;

          -- Rule f (RX): RX error delimiter too late -> REC += 8
          if (rx_error_delim_late_v) then
            if (v_rec <= 247) then
              v_rec := v_rec + 8;
            else
              v_rec := 255;
            end if;
          end if;

          -- Rule g: TX success -> TEC -= 1 (if > 0)
          if (tx_success_v) then
            if (v_tec > 0) then
              v_tec := v_tec - 1;
            end if;
          end if;

          -- Rule a: RX error (not during flag) -> REC += 1
          if (rx_error_v) then
            if (v_rec < 255) then
              v_rec := v_rec + 1;
            end if;
          end if;

          -- Rule b: RX primary error -> REC += 8
          if (rx_primary_error_v) then
            if (v_rec <= 247) then
              v_rec := v_rec + 8;
            else
              v_rec := 255;
            end if;
          end if;

          -- Rule e: RX error during error flag -> REC += 8
          if (rx_error_during_flag_v) then
            if (v_rec <= 247) then
              v_rec := v_rec + 8;
            else
              v_rec := 255;
            end if;
          end if;

          -- Rule h: RX success -> REC adjustment
          if (rx_success_v) then
            if (v_rec > 127) then
              v_rec := 127;
            elsif (v_rec > 0) then
              v_rec := v_rec - 1;
            end if;
          end if;

        end if; -- error_signalling_enabled and not bus_off

        -----------------------------------------------------------------------
        -- State transitions (evaluated after counter updates)
        -----------------------------------------------------------------------
        -- T4: TEC > 255 -> bus_off (highest priority)
        if (v_tec > 255 and v_fce_state /= bus_off) then
          v_fce_state := bus_off;

        -- T5: bus_off recovery complete -> error_active
        elsif (v_fce_state = bus_off and idle_count = 127) then
          v_fce_state := error_active;
          v_tec       := 0;
          v_rec       := 0;

        -- T2: counter > 127 -> error_passive
        elsif (v_fce_state = error_active and (v_tec > 127 or v_rec > 127)) then
          v_fce_state := error_passive;

        -- T3: both counters <= 127 -> error_active
        elsif (v_fce_state = error_passive and v_tec <= 127 and v_rec <= 127) then
          v_fce_state := error_active;

        end if;

        -- Register updates
        tec       <= v_tec;
        rec       <= v_rec;
        fce_state <= v_fce_state;

      end if; -- rst
    end if; -- rising_edge

  end process fce_proc;

  ---------------------------------------------------------------------------
  -- Combinational outputs from registered state
  ---------------------------------------------------------------------------
  tx_mac_o.error_passive <= (fce_state = error_passive) or (fce_state = bus_off);
  tx_mac_o.bus_off       <= (fce_state = bus_off);

  rx_mac_o.error_passive <= (fce_state = error_passive) or (fce_state = bus_off);
  rx_mac_o.bus_off       <= (fce_state = bus_off);

  status_o.state <= fce_state;
  status_o.tec   <= tec;
  status_o.rec   <= rec;

end architecture rtl;
