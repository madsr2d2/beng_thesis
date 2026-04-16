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
    pcs_o : out   t_can_fce_pcs_if_m2s
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
  -- Ranges allow crossing the thresholds with headroom for coefficient bumps.
  signal transmitter_error_count : natural range 0 to c_bus_off_threshold + 8;
  signal reciever_error_count    : natural range 0 to c_bus_off_threshold + 8;
  signal fce_state  : t_fce_state;
  signal idle_count : natural range 0 to c_bus_off_recovery_count;

begin

  p_fsm : process (clk_i) is
  begin

    if rising_edge(clk_i) then
      if (rst_i = '1') then
        transmitter_error_count        <= 0;
        reciever_error_count        <= 0;
        fce_state  <= s_error_active;
        idle_count <= 0;
        mac_o      <= c_fce_to_mac_if_reset;
        llc_o      <= c_fce_to_llc_if_reset;
        pcs_o      <= c_fce_to_pcs_if_reset;
      else
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
            -- Transmitter error count updates (ISO 8.1.4.2)
            ---------------------------------------------------------------
            if mac_i.transmitting = '1' then
              if (mac_i.error = '1' and mac_i.passive_tx_ack_error_exempt = '0') then
                transmitter_error_count <= transmitter_error_count + 8; -- ISO 8.1.4.2,c/d (TEC += 8)
              elsif (mac_i.error_delimiter_too_late = '1' ) then
                transmitter_error_count <= transmitter_error_count + 8; -- ISO 8.1.4.2,f (TEC += 8)
              elsif (mac_i.successful_transfer = '1' ) then
                transmitter_error_count <= 0 when transmitter_error_count = 0 else transmitter_error_count - 1; -- ISO 8.1.4.2,g (TEC -= 1)
              end if;

            ---------------------------------------------------------------
            -- REC updates (ISO 8.1.4.2)
            ---------------------------------------------------------------
            else
              if (mac_i.error = '1' and mac_i.sending_error_overload_flag = '1') then
                reciever_error_count <= reciever_error_count + 8; -- ISO 8.1.4.2,e (REC += 8)
              elsif (mac_i.error = '1') then
                reciever_error_count <= reciever_error_count + 1; -- ISO 8.1.4.2,a (REC += 1)
              elsif (mac_i.primary_error = '1') then
                reciever_error_count <= reciever_error_count + 8; -- ISO 8.1.4.2,b (REC += 8)
              elsif (mac_i.error_delimiter_too_late = '1') then
                reciever_error_count <= reciever_error_count + 8; -- ISO 8.1.4.2,f (REC += 8)
              elsif (mac_i.successful_transfer = '1') then
                if (reciever_error_count > c_error_count_threshold) then -- ISO 8.1.4.2,h (REC adjustment)
                  reciever_error_count <= c_error_count_threshold;
                elsif (reciever_error_count > 0) then
                  reciever_error_count <= reciever_error_count - 1;
                end if;
              end if;
            end if;

            ---------------------------------------------------------------
            -- State transitions (ISO : 8.1.4.4 Figure 43)
            ---------------------------------------------------------------
            if (transmitter_error_count > c_bus_off_threshold) then
              fce_state          <= s_bus_off;
              idle_count         <= 0;
              pcs_o.bus_off      <= '1';
              mac_o.error_active <= '0';
              llc_o.bus_off      <= '1';
            elsif (fce_state = s_error_active and (transmitter_error_count > c_error_count_threshold or reciever_error_count > c_error_count_threshold)) then
              fce_state                     <= s_error_passive;
              mac_o.error_active <= '0';
            end if;

            if (fce_state = s_error_passive and transmitter_error_count <= c_error_count_threshold and reciever_error_count <= c_error_count_threshold) then
              fce_state                   <= s_error_active;
              mac_o.error_active <= '1';
            end if;

            ---------------------------------------------------------------
            -- State transitions (ISO : 8.1.4.4 Figure 43)
            ---------------------------------------------------------------
          when s_bus_off =>
            mac_o.error_active <= '0';
            mac_o.bus_off      <= '1'; -- Force MAC FSM to idle/reintegration
            llc_o.bus_off      <= '1'; -- Signal LLC that node is in bus_off mode
            pcs_o.bus_off      <= '1'; -- Hold PCS in bus-off recovery

            -- Count idle conditions from PCS
            if (pcs_i.idle_condition = '1' and idle_count < c_bus_off_recovery_count) then
              idle_count <= idle_count + 1;
            elsif (idle_count = c_bus_off_recovery_count and llc_i.normal_mode = '1') then
              fce_state          <= s_error_active;
              transmitter_error_count  <= 0;
              reciever_error_count     <= 0;
              idle_count         <= 0;
              mac_o.error_active <= '1';
              mac_o.bus_off      <= '0';
              llc_o.bus_off      <= '0';
              pcs_o.bus_off      <= '0';
            end if;
          when others =>
            fce_state <= s_error_active;
        end case;

      end if;
    end if;
  end process p_fsm;
end architecture rtl;

-- eof
