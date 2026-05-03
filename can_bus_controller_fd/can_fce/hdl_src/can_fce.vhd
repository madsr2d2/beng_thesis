--------------------------------------------------------------------------------------------------------------------------------------------------------------
-- Copyright 2026 Everllence, Teglholmsgade 41, 2450 Copenhagen SV, Denmark
--------------------------------------------------------------------------------------------------------------------------------------------------------------
--
-- Requirements:
--
-- Description:   Fault Confinement Entity (FCE). Implements Transmitter error counter (TEC) and Receiver error counter (REC).
--                Error state and bus-off recovery logic. (ISO : 8.1.4.2-4).
--
-- Revision log:  Date:       Initial:  JIRA:
--                2026-04-10  TMYAES:   [TRIT-4336] [FPGA] CAN FD extensions of TRIT-3880   
--------------------------------------------------------------------------------------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

use work.pk_man_global.all;
use work.pk_can_types.all;

entity can_fce is
  port(
    clk_i : in  std_logic;
    rst_i : in  std_logic;
    -- LLC interface
    llc_i : in  t_can_llc_fce_if_m2s;
    llc_o : out t_can_fce_llc_if_s2m;
    -- MAC interface
    mac_i : in  t_can_mac_fce_if_m2s;
    mac_o : out t_can_mac_fce_if_s2m;
    -- PCS interface
    pcs_i : in  t_can_pcs_fce_if_s2m;
    pcs_o : out t_can_fce_pcs_if_m2s
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
  signal transmitter_error_count : natural range 0 to c_bus_off_threshold + 8;
  signal receiver_error_count    : natural range 0 to c_bus_off_threshold + 8;
  signal fce_state               : t_fce_state;
  signal idle_count              : natural range 0 to c_bus_off_recovery_count;

begin
  ---------------------------------------------------------------------------
  -- State machine
  ---------------------------------------------------------------------------
  p_fsm : process(clk_i) is
  begin

    if rising_edge(clk_i) then
      if (rst_i = '1') then
        transmitter_error_count <= 0;
        receiver_error_count    <= 0;
        fce_state               <= s_error_active;
        idle_count              <= 0;
        mac_o                   <= c_fce_to_mac_if_reset;
        llc_o                   <= c_fce_to_llc_if_reset;
        pcs_o                   <= c_fce_to_pcs_if_reset;
      else

        case fce_state is
          when s_error_active | s_error_passive =>
            -- Error count logic ------------------------------------------------------
            if mac_i.transmitting then                                          -- Transmitter errors
              if ((mac_i.error and not mac_i.passive_tx_ack_error_exempt_1) or mac_i.error_delimiter_too_late) then
                transmitter_error_count <= transmitter_error_count + 8;         -- ISO 8.1.4.2,c/d/f (TEC += 8)
              elsif (mac_i.successful_transfer) then
                transmitter_error_count <= 0 when transmitter_error_count = 0 else transmitter_error_count - 1; -- ISO 8.1.4.2,g (TEC -= 1)
              end if;
            else                                                                -- Receiver errors
              if ((mac_i.error and mac_i.sending_error_overload_flag) or mac_i.primary_error or mac_i.error_delimiter_too_late) then
                if (receiver_error_count <= c_bus_off_threshold) then
                  receiver_error_count <= receiver_error_count + 8;             -- ISO 8.1.4.2,b/e/f (REC += 8); clamped at c_bus_off_threshold + 8 to stay in range
                end if;
              elsif mac_i.error then
                if (receiver_error_count <= (c_bus_off_threshold + 7)) then
                  receiver_error_count <= receiver_error_count + 1;             -- ISO 8.1.4.2,a (REC += 1); clamped at c_bus_off_threshold + 8
                end if;
              elsif (mac_i.successful_transfer) then
                if (receiver_error_count > c_error_count_threshold) then        -- ISO 8.1.4.2,h (REC adjustment)
                  receiver_error_count <= c_error_count_threshold;
                elsif (receiver_error_count > 0) then
                  receiver_error_count <= receiver_error_count - 1;
                end if;
              end if;
            end if;

            -- State transition logic (ISO : 8.1.4.4 Figure 43) -----------------------
            if (transmitter_error_count > c_bus_off_threshold) then
              fce_state          <= s_bus_off;
              idle_count         <= 0;
              pcs_o.bus_off      <= '1';
              mac_o.error_active <= '0';
              mac_o.bus_off      <= '1';
              llc_o.bus_off      <= '1';
            elsif ((fce_state = s_error_active) and ((transmitter_error_count > c_error_count_threshold) or (receiver_error_count > c_error_count_threshold))) then
              fce_state          <= s_error_passive;
              mac_o.error_active <= '0';
            elsif ((fce_state = s_error_passive) and (transmitter_error_count <= c_error_count_threshold) and (receiver_error_count <= c_error_count_threshold)) then
              fce_state          <= s_error_active;
              mac_o.error_active <= '1';
            end if;
          when s_bus_off =>
            mac_o.error_active <= '0';
            mac_o.bus_off      <= '1';
            llc_o.bus_off      <= '1';
            pcs_o.bus_off      <= '1';

            -- Count idle conditions from PCS -----------------------------------------
            if ((pcs_i.idle_condition = '1') and (idle_count < c_bus_off_recovery_count)) then
              idle_count <= idle_count + 1;
            elsif ((idle_count = c_bus_off_recovery_count) and (llc_i.normal_mode = '1')) then
              fce_state               <= s_error_active;
              transmitter_error_count <= 0;
              receiver_error_count    <= 0;
              idle_count              <= 0;
              mac_o.error_active      <= '1';
              mac_o.bus_off           <= '0';
              llc_o.bus_off           <= '0';
              pcs_o.bus_off           <= '0';
            end if;
        end case;
      end if;
    end if;
  end process p_fsm;
end architecture rtl;

-- eof
