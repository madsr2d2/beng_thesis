--------------------------------------------------------------------------------
-- Title      : CAN MAC Sub-layer Wrapper
-- Project    : Implementation and Verification of a CAN-FD Bus Transceiver in VHDL
--------------------------------------------------------------------------------
-- File       : can_mac.vhd
-- Author     : Mads Richardt
-- Standard   : VHDL-2008
--------------------------------------------------------------------------------
-- Description: Structural wrapper instantiating can_mac_tx, can_mac_rx, and
--              can_fce. TX and RX paths have separate PCS interfaces. The FCE
--              receives a merged MAC interface (OR of TX and RX FCE outputs)
--              and fans its response back to both paths. The MAC-FCE wiring is
--              internal; externally the wrapper exposes LLC and PCS interfaces
--              for each path, plus the FCE's LLC and PCS interfaces.
--------------------------------------------------------------------------------

library ieee;
  use ieee.std_logic_1164.all;
  use work.pk_can_types.all;

entity can_mac is
  port (
    clk : in    std_logic;
    rst : in    std_logic;

    -- TX LLC interface
    tx_llc_i : in    t_can_llc_mac_tx_if_s2d;
    tx_llc_o : out   t_can_llc_mac_tx_if_d2s;

    -- RX LLC interface
    rx_llc_i : in    t_can_llc_mac_rx_if_d2s;
    rx_llc_o : out   t_can_llc_mac_rx_if_s2d;

    -- Separate PCS interfaces
    tx_pcs_i : in    t_can_mac_pcs_if_s2m;
    tx_pcs_o : out   t_can_mac_pcs_if_m2s;
    rx_pcs_i : in    t_can_mac_pcs_if_s2m;
    rx_pcs_o : out   t_can_mac_pcs_if_m2s;

    -- FCE LLC interface (ISO 11898-1 Tables 14/15)
    fce_llc_i : in    t_can_llc_fce_if_m2s;
    fce_llc_o : out   t_can_fce_llc_if_s2m;

    -- FCE PCS interface (ISO 11898-1 Tables 18/19)
    fce_pcs_i : in    t_can_pcs_fce_if_s2m;
    fce_pcs_o : out   t_can_fce_pcs_if_m2s;

    -- FCE debug output
    debug_tec_o : out   natural range 0 to c_fce_tec_max;
    debug_rec_o : out   natural range 0 to c_fce_rec_max
  );
end entity can_mac;

architecture rtl of can_mac is

  signal tx_fce_o   : t_can_mac_fce_if_m2s;
  signal rx_fce_o   : t_can_mac_fce_if_m2s;
  signal fce_mac_i  : t_can_mac_fce_if_m2s;
  signal fce_mac_o  : t_can_mac_fce_if_s2m;

begin

  ---------------------------------------------------------------------------
  -- can_mac_tx
  ---------------------------------------------------------------------------
  u_mac_tx : entity work.can_mac_tx
    port map (
      clk   => clk,
      rst   => rst,
      llc_i => tx_llc_i,
      llc_o => tx_llc_o,
      pcs_i => tx_pcs_i,
      pcs_o => tx_pcs_o,
      fce_i => fce_mac_o,
      fce_o => tx_fce_o
    );

  ---------------------------------------------------------------------------
  -- can_mac_rx
  ---------------------------------------------------------------------------
  u_mac_rx : entity work.can_mac_rx
    port map (
      clk   => clk,
      rst   => rst,
      llc_i => rx_llc_i,
      llc_o => rx_llc_o,
      pcs_i => rx_pcs_i,
      pcs_o => rx_pcs_o,
      fce_i => fce_mac_o,
      fce_o => rx_fce_o
    );

  ---------------------------------------------------------------------------
  -- FCE input merge (OR all fields; half-duplex guarantees no conflicts)
  ---------------------------------------------------------------------------
  fce_mac_i.transmitting                <= tx_fce_o.transmitting or rx_fce_o.transmitting;
  fce_mac_i.error                       <= tx_fce_o.error or rx_fce_o.error;
  fce_mac_i.primary_error               <= tx_fce_o.primary_error or rx_fce_o.primary_error;
  fce_mac_i.sending_error_overload_flag <= tx_fce_o.sending_error_overload_flag or rx_fce_o.sending_error_overload_flag;
  fce_mac_i.counters_unchanged          <= tx_fce_o.counters_unchanged or rx_fce_o.counters_unchanged;
  fce_mac_i.error_delimiter_too_late    <= tx_fce_o.error_delimiter_too_late or rx_fce_o.error_delimiter_too_late;
  fce_mac_i.successful_transfer         <= tx_fce_o.successful_transfer or rx_fce_o.successful_transfer;
  fce_mac_i.error_passive_response      <= tx_fce_o.error_passive_response or rx_fce_o.error_passive_response;
  fce_mac_i.error_active_response       <= tx_fce_o.error_active_response or rx_fce_o.error_active_response;

  ---------------------------------------------------------------------------
  -- can_fce
  ---------------------------------------------------------------------------
  u_fce : entity work.can_fce
    port map (
      clk_i       => clk,
      rst_i       => rst,
      llc_i       => fce_llc_i,
      llc_o       => fce_llc_o,
      mac_i       => fce_mac_i,
      mac_o       => fce_mac_o,
      pcs_i       => fce_pcs_i,
      pcs_o       => fce_pcs_o,
      debug_tec_o => debug_tec_o,
      debug_rec_o => debug_rec_o
    );

end architecture rtl;
