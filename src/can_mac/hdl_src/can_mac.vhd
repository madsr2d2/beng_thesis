--------------------------------------------------------------------------------
-- Title      : CAN MAC Sub-layer Wrapper
-- Project    : Implementation and Verification of a CAN-FD Bus Transceiver in VHDL
--------------------------------------------------------------------------------
-- File       : can_mac.vhd
-- Author     : Mads Richardt
-- Standard   : VHDL-2008
--------------------------------------------------------------------------------
-- Description: Structural wrapper instantiating can_mac_tx and can_mac_rx.
--              TX and RX paths have separate PCS interfaces. The FCE interface
--              is exposed as ports: the wrapper merges the TX and RX FCE outputs
--              (OR of all fields, safe under half-duplex) and fans the FCE
--              response back to both paths. The FCE itself is instantiated at
--              the top-level CAN node wrapper where LLC and PCS also connect.
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

    -- Separate PCS interfaces (TX uses t_can_mac_pcs_if, RX uses t_can_mac_pcs_rx_if)
    tx_pcs_i : in    t_can_mac_pcs_if_s2m;
    tx_pcs_o : out   t_can_mac_pcs_if_m2s;
    rx_pcs_i : in    t_can_mac_pcs_rx_if_s2m;
    rx_pcs_o : out   t_can_mac_pcs_rx_if_m2s;

    -- FCE interface (exposed for top-level wiring)
    fce_i : in    t_can_mac_fce_if_s2m;
    fce_o : out   t_can_mac_fce_if_m2s
  );
end entity can_mac;

architecture rtl of can_mac is

  signal tx_fce_o  : t_can_mac_fce_if_m2s;
  signal rx_fce_o  : t_can_mac_fce_if_m2s;

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
      fce_i => fce_i,
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
      fce_i => fce_i,
      fce_o => rx_fce_o,
      transmitting_i => tx_fce_o.transmitting
    );

  ---------------------------------------------------------------------------
  -- FCE output merge (OR all fields; half-duplex guarantees no conflicts)
  ---------------------------------------------------------------------------
  fce_o.transmitting                <= tx_fce_o.transmitting or rx_fce_o.transmitting;
  fce_o.error                       <= tx_fce_o.error or rx_fce_o.error;
  fce_o.primary_error               <= tx_fce_o.primary_error or rx_fce_o.primary_error;
  fce_o.sending_error_overload_flag <= tx_fce_o.sending_error_overload_flag or rx_fce_o.sending_error_overload_flag;
  fce_o.passive_tx_ack_error_exempt_1 <= tx_fce_o.passive_tx_ack_error_exempt_1 or rx_fce_o.passive_tx_ack_error_exempt_1;
  fce_o.error_delimiter_too_late    <= tx_fce_o.error_delimiter_too_late or rx_fce_o.error_delimiter_too_late;
  fce_o.successful_transfer         <= tx_fce_o.successful_transfer or rx_fce_o.successful_transfer;

end architecture rtl;
