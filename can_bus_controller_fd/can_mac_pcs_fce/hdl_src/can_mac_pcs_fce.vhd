--------------------------------------------------------------------------------
-- Title      : MAC + PCS + FCE structural wrapper
-- Project    : Implementation and Verification of a CAN-FD Bus Transceiver in VHDL
--------------------------------------------------------------------------------
-- File       : can_mac_pcs_fce.vhd
-- Author     : Mads Richardt
-- Standard   : VHDL-2008
--------------------------------------------------------------------------------
-- Description: Structural wrapper that instantiates can_mac, can_fce, and
--              can_pcs and wires them together. Exposes LLC TX/RX interfaces,
--              the LLC-FCE interface (bus-off status and normal_mode handshake),
--              and a physical bus interface (tx_o / rx_i) to the top level.
--------------------------------------------------------------------------------

library ieee;
  use ieee.std_logic_1164.all;
  use ieee.numeric_std.all;

  use work.pk_man_global.all;
  use work.pk_can_types.all;

entity can_mac_pcs_fce is
  port(
    clk      : in  std_logic;
    rst      : in  std_logic;
    -- TX LLC interface
    tx_llc_i : in  t_can_llc_mac_tx_if_s2d;
    tx_llc_o : out t_can_llc_mac_tx_if_d2s;
    -- RX LLC interface
    rx_llc_i : in  t_can_llc_mac_rx_if_d2s;
    rx_llc_o : out t_can_llc_mac_rx_if_s2d;
    --
    llc_fce_i : in  t_can_llc_fce_if_m2s;
    llc_fce_o : out t_can_fce_llc_if_s2m;
    -- Bus interface
    tx_o     : out std_logic;
    rx_i     : in  std_logic
  );
end entity can_mac_pcs_fce;

architecture rtl of can_mac_pcs_fce is

  -- FCE <-> MAC interface --------------------------------------------------
  signal mac_to_fce : t_can_mac_fce_if_m2s;
  signal fce_to_mac : t_can_mac_fce_if_s2m;
  -- FCE <-> PCS interface --------------------------------------------------
  signal pcs_to_fce : t_can_pcs_fce_if_s2m;
  signal fce_to_pcs : t_can_fce_pcs_if_m2s;
  -- (LLC-FCE signals are routed through the wrapper ports llc_fce_i / llc_fce_o)
  -- PCS <-> MAC interface --------------------------------------------------
  signal mac_to_pcs : t_can_mac_pcs_if_m2s;
  signal pcs_to_mac : t_can_mac_pcs_if_s2m;

begin

  -- MAC layer entity -------------------------------------------------------
  u_mac : entity work.can_mac
    port map(
      clk      => clk,
      rst      => rst,
      -- LLC interfaces
      rx_llc_i => rx_llc_i,
      rx_llc_o => rx_llc_o,
      tx_llc_i => tx_llc_i,
      tx_llc_o => tx_llc_o,
      -- PCS interfaces
      pcs_o    => mac_to_pcs,
      pcs_i    => pcs_to_mac,
      -- FCE interfaces
      fce_i    => fce_to_mac,
      fce_o    => mac_to_fce
    );
  ---------------------------------------------------------------------------

  -- FCE entity -------------------------------------------------------------
  u_fce : entity work.can_fce
    port map(
      clk_i => clk,
      rst_i => rst,
      llc_i => llc_fce_i,
      llc_o => llc_fce_o,
      mac_i => mac_to_fce,
      mac_o => fce_to_mac,
      pcs_i => pcs_to_fce,
      pcs_o => fce_to_pcs
    );
  ---------------------------------------------------------------------------

  -- PCS entity -------------------------------------------------------------
  u_pcs : entity work.can_pcs
    port map(
      clk_i => clk,
      rst_i => rst,
      mac_i => mac_to_pcs,
      mac_o => pcs_to_mac,
      fce_i => fce_to_pcs,
      fce_o => pcs_to_fce,
      tx_o  => tx_o,
      rx_i  => rx_i
    );
  ---------------------------------------------------------------------------
end architecture rtl;
