--------------------------------------------------------------------------------------------------------------------------------------------------------------
-- Copyright 2026 Everllence, Teglholmsgade 41, 2450 Copenhagen SV, Denmark
--------------------------------------------------------------------------------------------------------------------------------------------------------------
--
-- Requirements:  
--
-- Description: Structural wrapper instantiating can_mac_tx and can_mac_rx.
--              TX and RX paths have separate PCS interfaces. The FCE interface
--              merges the TX and RX FCE outputs (OR of all fields) and fans 
--              the FCE response back to both paths. 
--
-- Revision log:  Date:       Initial:  JIRA:
--                2026-03-23  TMYAES:   [TRIT-4355] [FPGA] Controlling FSM form MAC layer in CAN-FD module
--
--------------------------------------------------------------------------------------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use work.pk_can_types.all;

entity can_mac is
  port(
    clk      : in  std_logic;
    rst      : in  std_logic;

    -- TX LLC interface
    tx_llc_i : in  t_can_llc_mac_tx_if_s2d;
    tx_llc_o : out t_can_llc_mac_tx_if_d2s;

    -- RX LLC interface
    rx_llc_i : in  t_can_llc_mac_rx_if_d2s;
    rx_llc_o : out t_can_llc_mac_rx_if_s2d;

    -- PCS interfaces
    pcs_i    : in  t_can_mac_pcs_if_s2m;
    pcs_o    : out t_can_mac_pcs_if_m2s;

    -- FCE interface (exposed for top-level wiring)
    fce_i    : in  t_can_mac_fce_if_s2m;
    fce_o    : out t_can_mac_fce_if_m2s
  );
end entity can_mac;

architecture rtl of can_mac is

  signal tx_fce_o : t_can_mac_fce_if_m2s;
  signal rx_fce_o : t_can_mac_fce_if_m2s;


  signal tx_pcs_o : t_can_mac_pcs_if_m2s;
  signal rx_pcs_o : t_can_mac_pcs_if_m2s;

begin

  ---------------------------------------------------------------------------
  -- can_mac_tx
  ---------------------------------------------------------------------------
  u_mac_tx : entity work.can_mac_tx
    port map(
      clk   => clk,
      rst   => rst,
      llc_i => tx_llc_i,
      llc_o => tx_llc_o,
      pcs_i => pcs_i,
      pcs_o => tx_pcs_o,
      fce_i => fce_i,
      fce_o => tx_fce_o
    );

  ---------------------------------------------------------------------------
  -- can_mac_rx
  ---------------------------------------------------------------------------
  u_mac_rx : entity work.can_mac_rx
    port map(
      clk            => clk,
      rst            => rst,
      llc_i          => rx_llc_i,
      llc_o          => rx_llc_o,
      pcs_i          => pcs_i,
      pcs_o          => rx_pcs_o,
      fce_i          => fce_i,
      fce_o          => rx_fce_o,
      transmitting_i => tx_fce_o.transmitting                                   -- Transmitting signal from TX path
    );

  -- FCE interface ---------------------------------------------------------- 
  fce_o.transmitting                  <= tx_fce_o.transmitting;                 -- Informs FCE which path is active 
  fce_o.error                         <= tx_fce_o.error or rx_fce_o.error;      -- Set by either path
  fce_o.primary_error                 <= tx_fce_o.primary_error or rx_fce_o.primary_error; -- Set by either path
  fce_o.sending_error_overload_flag   <= tx_fce_o.sending_error_overload_flag or rx_fce_o.sending_error_overload_flag; -- Set by either path 
  fce_o.passive_tx_ack_error_exempt_1 <= tx_fce_o.passive_tx_ack_error_exempt_1; -- Only relevant for TX path
  fce_o.error_delimiter_too_late      <= tx_fce_o.error_delimiter_too_late or rx_fce_o.error_delimiter_too_late; -- Set by either path
  fce_o.successful_transfer           <= tx_fce_o.successful_transfer;
  ---------------------------------------------------------------------------

  -- PCS interface ----------------------------------------------------------
  pcs_o.transmitting    <= tx_pcs_o.transmitting or rx_pcs_o.transmitting;      -- Set by either path
  pcs_o.tx_data         <= tx_pcs_o.tx_data and rx_pcs_o.tx_data;               -- Dominant ('0') if either is dominant
  pcs_o.do_hard_sync    <= rx_pcs_o.do_hard_sync;                               -- Only the RX paths does hard sync
  pcs_o.next_bit_is_brs <= tx_pcs_o.next_bit_is_brs or rx_pcs_o.next_bit_is_brs; -- Set by either path if next bit is BRS
  pcs_o.next_bit_is_res <= tx_pcs_o.next_bit_is_res;                            -- Only set by the TX path
  pcs_o.data_phase_stop <= tx_pcs_o.data_phase_stop or rx_pcs_o.data_phase_stop; -- Stop data phase if either path signals it
  ---------------------------------------------------------------------------

end architecture rtl;
