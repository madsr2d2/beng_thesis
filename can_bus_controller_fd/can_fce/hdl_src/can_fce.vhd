--------------------------------------------------------------------------------------------------------------------------------------------------------------
-- Copyright 2026 Everllence, Teglholmsgade 41, 2450 Copenhagen SV, Denmark
--------------------------------------------------------------------------------------------------------------------------------------------------------------
--
-- Requirements:
--
-- Description:   Fault Confinement Entity per ISO 11898-1:2015 Section 8.1.4.
--                Manages TEC/REC counters and error state for both TX and RX
--                MAC paths via a single merged MAC interface. The transmitting
--                flag distinguishes TX from RX events.
--                Interfaces (per ISO 11898-1 Tables 14-19):
--                  LLC: Normal_mode_request/response, Bus_off indication
--                  MAC: Error counting signals, Error_passive/active requests
--                  PCS: Bus_off_request/release, idle_condition for recovery
--                Counter update rules follow ISO 8.1.4.2 Table 16/17.
--                State transitions follow ISO 8.1.4.1 (T2-T5).
--                Bus-off recovery counts idle_condition pulses from PCS.
--
-- Revision log:  Date:       Initial:  JIRA:
--                2026-03-31  MRDSA     Converted to company header format
--                2026-04-12  MRDSA     Refactor: explicit FSM, single MAC
--                                      interface, idle detection moved to PCS
--------------------------------------------------------------------------------------------------------------------------------------------------------------

library ieee;
  use ieee.std_logic_1164.all;
  use ieee.numeric_std.all;

  use work.pk_man_global.all;
  use work.pk_can_types.all;

entity can_fce is
  port (
    clk_i : in    std_logic;
    rst_i : in    std_logic;
    -- LLC interface
    llc_i : in    t_can_llc_fce_if_m2s;
    llc_o : out   t_can_fce_llc_if_s2m;
    -- MAC interface
    mac_i : in    t_can_mac_fce_if_m2s;
    mac_o : out   t_can_mac_fce_if_s2m;
    -- PCS interface
    pcs_i : in    t_can_pcs_fce_if_s2m;
    pcs_o : out   t_can_fce_pcs_if_m2s;
    -- Debug output
    debug_tec_o   : out   natural range 0 to c_fce_tec_max;
    debug_rec_o   : out   natural range 0 to c_fce_rec_max
  );
end entity can_fce;

architecture rtl of can_fce is

  ---------------------------------------------------------------------------
  -- Types
  ---------------------------------------------------------------------------
  type t_fce_state is (s_error_active, s_error_passive, s_bus_off);

  ---------------------------------------------------------------------------
  -- Signals
  ---------------------------------------------------------------------------
  signal tec        : natural range 0 to c_fce_tec_max;
  signal rec        : natural range 0 to c_fce_rec_max;
  signal fce_state  : t_fce_state;
  signal idle_count : natural range 0 to c_bus_off_recovery_count;

  ---------------------------------------------------------------------------
  -- Helper functions
  ---------------------------------------------------------------------------
  function count_up (val : natural; inc : natural; max_val : natural) return natural is
  begin
    if (val <= max_val - inc) then
      return val + inc;
    else
      return max_val;
    end if;
  end function count_up;

  function count_dowm (val : natural; dec : natural) return natural is
  begin
    if (val >= dec) then
      return val - dec;
    else
      return 0;
    end if;
  end function count_dowm;

begin

  p_fsm : process (clk_i) is
  begin

    if rising_edge(clk_i) then
      if (rst_i = '1') then
        tec        <= 0;
        rec        <= 0;
        fce_state  <= s_error_active;
        idle_count <= 0;
        mac_o      <= c_fce_to_mac_if_reset;
        llc_o      <= c_fce_to_llc_if_reset;
        pcs_o      <= c_fce_to_pcs_if_reset;
      else
        -- Clear pulse outputs
        llc_o.normal_mode_response    <= '0';
        pcs_o.bus_off_request         <= '0';
        pcs_o.bus_off_release_request <= '0';

        -----------------------------------------------------------------
        -- State machine
        -----------------------------------------------------------------
        case fce_state is

          when s_error_active | s_error_passive =>
            llc_o.bus_off <= '0';
            if (fce_state = s_error_passive) then
              mac_o.error_active  <= '0';
            else
              mac_o.error_active  <= '1';
            end if;

            ---------------------------------------------------------------
            -- TEC updates (ISO 8.1.4.2)
            ---------------------------------------------------------------
            if (mac_i.error = '1' and mac_i.transmitting = '1' and mac_i.passive_tx_ack_error = '0') then
              tec <= count_up(tec, 8, c_fce_tec_max); -- Rule c: TEC += 8
            elsif (mac_i.error_delimiter_too_late = '1' and mac_i.transmitting = '1') then
              tec <= count_up(tec, 8, c_fce_tec_max); -- Rule d/f: TEC += 8
            elsif (mac_i.successful_transfer = '1' and mac_i.transmitting = '1') then
              tec <= count_dowm(tec, 1); -- Rule g: TEC -= 1
            end if;

            ---------------------------------------------------------------
            -- REC updates (ISO 8.1.4.2)
            ---------------------------------------------------------------
            if (mac_i.error = '1' and mac_i.transmitting = '0' and mac_i.sending_error_overload_flag = '0') then
              rec <= count_up(rec, 1, c_fce_rec_max); -- Rule a: REC += 1
            elsif (mac_i.primary_error = '1' and mac_i.transmitting = '0') then
              rec <= count_up(rec, 8, c_fce_rec_max); -- Rule b: REC += 8
            elsif (mac_i.error = '1' and mac_i.sending_error_overload_flag = '1' and mac_i.transmitting = '0') then
              rec <= count_up(rec, 8, c_fce_rec_max); -- Rule e: REC += 8
            elsif (mac_i.error_delimiter_too_late = '1' and mac_i.transmitting = '0') then
              rec <= count_up(rec, 8, c_fce_rec_max); -- Rule f (RX): REC += 8
            elsif (mac_i.successful_transfer = '1' and mac_i.transmitting = '0') then
              if (rec > c_fce_error_passive_threshold) then -- Rule h: REC adjustment
                rec <= c_fce_error_passive_threshold;
              elsif (rec > 0) then
                rec <= rec - 1;
              end if;
            end if;

            ---------------------------------------------------------------
            -- State transitions (ISO : 8.1.4.4 Figure 43)
            ---------------------------------------------------------------
            if (tec > c_fce_bus_off_threshold) then
              fce_state                     <= s_bus_off;
              idle_count                    <= 0;
              pcs_o.bus_off_request         <= '1';
              mac_o.error_active    <= '0';
              llc_o.bus_off                 <= '1';
            elsif (fce_state = s_error_active and (tec > c_fce_error_passive_threshold or rec > c_fce_error_passive_threshold)) then
              fce_state                     <= s_error_passive;
              mac_o.error_active    <= '0';
            end if;

            if (fce_state = s_error_passive and tec <= c_fce_error_passive_threshold and rec <= c_fce_error_passive_threshold) then
              fce_state                   <= s_error_active;
              mac_o.error_active  <= '1';
            end if;

          when s_bus_off =>
            mac_o.error_active  <= '0';
            llc_o.bus_off               <= '1';
            -- Count idle conditions from PCS
            if (pcs_i.idle_condition = '1' and idle_count < c_bus_off_recovery_count) then
              idle_count <= idle_count + 1;
            elsif (idle_count = c_bus_off_recovery_count or llc_i.normal_mode_request = '1') then
              fce_state                     <= s_error_active;
              tec                           <= 0;
              rec                           <= 0;
              idle_count                    <= 0;
              mac_o.error_active    <= '1';
              llc_o.bus_off                 <= '0';
              llc_o.normal_mode_response    <= '1';
              pcs_o.bus_off_release_request <= '1';
            end if;
          when others =>
            fce_state <= s_error_active;
        end case;

      end if;
    end if;
  end process p_fsm;

  debug_tec_o <= tec;
  debug_rec_o <= rec;

end architecture rtl;

-- eof
