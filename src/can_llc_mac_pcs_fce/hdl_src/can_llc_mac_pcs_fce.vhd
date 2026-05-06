--------------------------------------------------------------------------------
-- Title      : LLC + MAC + PCS + FCE structural wrapper
-- Project    : Implementation and Verification of a CAN-FD Bus Transceiver in VHDL
--------------------------------------------------------------------------------
-- File       : can_llc_mac_pcs_fce.vhd
-- Author     : Mads Richardt
-- Standard   : VHDL-2008
--------------------------------------------------------------------------------
-- Description: Structural wrapper that instantiates can_llc, can_mac, can_fce,
--              and can_pcs as peer-level instances and wires them together.
--              Exposes the user TX interface (71-byte legacy frames), the MAC
--              RX LLC interface, and a physical bus interface (tx_o / rx_i).
--              The LLC-FCE interface is fully internal; debug_bus_off_o exposes
--              the FCE bus_off flag for testbench observability.
--------------------------------------------------------------------------------

library ieee;
  use ieee.std_logic_1164.all;
  use ieee.numeric_std.all;
  use work.pk_can_types.all;

entity can_llc_mac_pcs_fce is
  port(
    clk_i   : in  std_logic;
    reset_i : in  std_logic;
    -- User TX interface (71-byte legacy frames)
    user_tx_i : in  t_can_user_llc_tx_if_s2d;
    user_tx_o : out t_can_user_llc_tx_if_d2s;
    -- RX LLC interface (internal format, passed through from MAC)
    rx_llc_i : in  t_can_llc_mac_rx_if_d2s;
    rx_llc_o : out t_can_llc_mac_rx_if_s2d;
    -- Physical bus
    tx_o : out std_logic;
    rx_i : in  std_logic;
    -- Debug: FCE bus_off status for testbench observability (trimmed in synthesis)
    debug_bus_off_o : out std_logic
  );
end entity can_llc_mac_pcs_fce;

architecture rtl of can_llc_mac_pcs_fce is

  -- LLC <-> MAC TX interface -------------------------------------------------
  signal llc_to_mac : t_can_llc_mac_tx_if_s2d;
  signal mac_to_llc : t_can_llc_mac_tx_if_d2s;
  -- LLC <-> FCE interface ----------------------------------------------------
  signal llc_to_fce : t_can_llc_fce_if_m2s;
  signal fce_to_llc : t_can_fce_llc_if_s2m;
  -- MAC <-> FCE interface ----------------------------------------------------
  signal mac_to_fce : t_can_mac_fce_if_m2s;
  signal fce_to_mac : t_can_mac_fce_if_s2m;
  -- PCS <-> FCE interface ----------------------------------------------------
  signal pcs_to_fce : t_can_pcs_fce_if_s2m;
  signal fce_to_pcs : t_can_fce_pcs_if_m2s;
  -- MAC <-> PCS interface ----------------------------------------------------
  signal mac_to_pcs : t_can_mac_pcs_if_m2s;
  signal pcs_to_mac : t_can_mac_pcs_if_s2m;

begin

  debug_bus_off_o <= fce_to_llc.bus_off;

  -- LLC entity ---------------------------------------------------------------
  u_llc : entity work.can_llc
    port map(
      clk_i      => clk_i,
      reset_i    => reset_i,
      llc_user_i => user_tx_i,
      llc_user_o => user_tx_o,
      tx_mac_i   => mac_to_llc,
      tx_mac_o   => llc_to_mac,
      fce_i      => fce_to_llc,
      fce_o      => llc_to_fce
    );
  ---------------------------------------------------------------------------

  -- MAC entity ---------------------------------------------------------------
  u_mac : entity work.can_mac
    port map(
      clk_i    => clk_i,
      reset_i  => reset_i,
      tx_llc_i => llc_to_mac,
      tx_llc_o => mac_to_llc,
      rx_llc_i => rx_llc_i,
      rx_llc_o => rx_llc_o,
      pcs_i    => pcs_to_mac,
      pcs_o    => mac_to_pcs,
      fce_i    => fce_to_mac,
      fce_o    => mac_to_fce
    );
  ---------------------------------------------------------------------------

  -- FCE entity ---------------------------------------------------------------
  u_fce : entity work.can_fce
    port map(
      clk_i   => clk_i,
      reset_i => reset_i,
      llc_i   => llc_to_fce,
      llc_o   => fce_to_llc,
      mac_i   => mac_to_fce,
      mac_o   => fce_to_mac,
      pcs_i   => pcs_to_fce,
      pcs_o   => fce_to_pcs
    );
  ---------------------------------------------------------------------------

  -- PCS entity ---------------------------------------------------------------
  u_pcs : entity work.can_pcs
    port map(
      clk_i   => clk_i,
      reset_i => reset_i,
      mac_i   => mac_to_pcs,
      mac_o   => pcs_to_mac,
      fce_i   => fce_to_pcs,
      fce_o   => pcs_to_fce,
      tx_o    => tx_o,
      rx_i    => rx_i
    );
  ---------------------------------------------------------------------------

end architecture rtl;
