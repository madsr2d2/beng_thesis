--------------------------------------------------------------------------------
-- Title      : Full CAN/CAN-FD controller
-- Project    : Implementation and Verification of a CAN-FD Bus Transceiver in VHDL
--------------------------------------------------------------------------------
-- File       : can_fd_controller.vhd
-- Author     : Mads Richardt
-- Standard   : VHDL-2008
--------------------------------------------------------------------------------
-- Description: Top-level CAN/CAN-FD controller. Instantiates the four ISO
--              11898-1 sub-layers / entities (LLC, MAC, PCS, FCE) as peers,
--              following the layer architecture in ISO 11898-1:2015 Figure 1.
--              Exposes the user TX interface (legacy 71-byte LLC frame), the
--              MAC RX byte stream, and the physical bus (tx_o / rx_i).
--------------------------------------------------------------------------------

library ieee;
  use ieee.std_logic_1164.all;
  use work.pk_can_types.all;

entity can_fd_controller is
  port(
    clk : in  std_logic;
    rst : in  std_logic;

    -- TX user interface (legacy 71-byte LLC frame)
    user_tx_i : in  t_can_user_llc_tx_if_s2d;
    user_tx_o : out t_can_user_llc_tx_if_d2s;

    -- RX byte stream (from MAC; LLC RX layer not yet implemented)
    rx_llc_i : in  t_can_llc_mac_rx_if_d2s;
    rx_llc_o : out t_can_llc_mac_rx_if_s2d;

    -- Physical bus
    tx_o : out std_logic;
    rx_i : in  std_logic
  );
end entity can_fd_controller;

architecture rtl of can_fd_controller is

  -- LLC <-> MAC TX (internal byte stream)
  signal llc_to_mac : t_can_llc_mac_tx_if_s2d;
  signal mac_to_llc : t_can_llc_mac_tx_if_d2s;

  -- MAC <-> PCS
  signal mac_to_pcs : t_can_mac_pcs_if_m2s;
  signal pcs_to_mac : t_can_mac_pcs_if_s2m;

  -- MAC <-> FCE
  signal mac_to_fce : t_can_mac_fce_if_m2s;
  signal fce_to_mac : t_can_mac_fce_if_s2m;

  -- PCS <-> FCE
  signal pcs_to_fce : t_can_pcs_fce_if_s2m;
  signal fce_to_pcs : t_can_fce_pcs_if_m2s;

  -- LLC <-> FCE
  signal llc_to_fce : t_can_llc_fce_if_m2s;
  signal fce_to_llc : t_can_fce_llc_if_s2m;

begin

  ---------------------------------------------------------------------------
  -- LLC sub-layer (TX)
  ---------------------------------------------------------------------------
  u_llc : entity work.can_llc
    port map(
      clk        => clk,
      rst        => rst,
      llc_user_i => user_tx_i,
      llc_user_o => user_tx_o,
      mac_i      => mac_to_llc,
      mac_o      => llc_to_mac,
      fce_i      => fce_to_llc,
      fce_o      => llc_to_fce
    );

  ---------------------------------------------------------------------------
  -- MAC sub-layer
  ---------------------------------------------------------------------------
  u_mac : entity work.can_mac
    port map(
      clk      => clk,
      rst      => rst,
      tx_llc_i => llc_to_mac,
      tx_llc_o => mac_to_llc,
      rx_llc_i => rx_llc_i,
      rx_llc_o => rx_llc_o,
      pcs_o    => mac_to_pcs,
      pcs_i    => pcs_to_mac,
      fce_i    => fce_to_mac,
      fce_o    => mac_to_fce
    );

  ---------------------------------------------------------------------------
  -- PCS sub-layer
  ---------------------------------------------------------------------------
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
  -- FCE
  ---------------------------------------------------------------------------
  u_fce : entity work.can_fce
    port map(
      clk_i => clk,
      rst_i => rst,
      llc_i => llc_to_fce,
      llc_o => fce_to_llc,
      mac_i => mac_to_fce,
      mac_o => fce_to_mac,
      pcs_i => pcs_to_fce,
      pcs_o => fce_to_pcs
    );

end architecture rtl;

-- eof
