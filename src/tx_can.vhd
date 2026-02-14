--------------------------------------------------------------------------------
-- Title      : CAN Transmitter Top-Level
-- Project    : CAN Bus Transmitter
--------------------------------------------------------------------------------
-- File       : tx_can.vhd
-- Standard   : VHDL-2008
--------------------------------------------------------------------------------
-- Description: Top-level CAN transmitter integrating all three layers:
--   - tx_llc:  LLC sub-layer (frame buffering, retransmission, Avalon-ST streaming)
--   - mac_tx:  MAC sub-layer (serializer, FSM, bit stuffing)
--   - tx_pcs:  PCS sub-layer (bit timing, TDC, bus interface)
--
-- Signal flow:
--   llc_user -> tx_llc -> mac_tx -> tx_pcs -> bus
--
-- The FCE (Fault Confinement Entity) interface is passed through from
-- mac_tx to the external FCE module.
--------------------------------------------------------------------------------

library ieee;
  use ieee.std_logic_1164.all;
  use ieee.numeric_std.all;
  use work.can_pkg.all;

entity tx_can is
  generic (
    -- PCS bit timing (passed through to tx_pcs)
    nom_prescaler        : integer := 2;
    nom_sync_seg         : integer := 1;
    nom_prop_seg         : integer := 8;
    nom_phase_seg1       : integer := 8;
    nom_phase_seg2       : integer := 8;
    data_prescaler       : integer := 1;
    data_sync_seg        : integer := 1;
    data_prop_seg        : integer := 4;
    data_phase_seg1      : integer := 4;
    data_phase_seg2      : integer := 4;
    ssp_offset           : integer := ssp_offset_c
  );
  port (
    clk : in    std_logic;
    rst : in    std_logic;

    -- LLC user interface (application-facing)
    llc_user_i : in    llc_user_to_llc_if_t;
    llc_user_o : out   llc_to_llc_user_if_t;

    -- Fault Confinement Entity interface (passed through to MAC)
    fce_i : in    fce_to_mac_if_t;
    fce_o : out   mac_to_fce_if_t;

    -- Physical bus interface
    tx_bus_o : out   polarity_t;
    rx_bus_i : in    polarity_t
  );
end entity tx_can;

architecture rtl of tx_can is

  -- LLC <-> MAC internal signals
  signal llc_to_mac : llc_to_mac_if_t;
  signal mac_to_llc : mac_to_llc_if_t;

  -- MAC <-> PCS internal signals
  signal mac_to_pcs : mac_to_pcs_if_t;
  signal pcs_to_mac : pcs_to_mac_if_t;

begin

  -- =========================================================================
  -- tx_llc: LLC sub-layer
  -- Buffers frames, streams config+data to MAC, handles retransmission
  -- =========================================================================
  tx_llc_inst : entity work.tx_llc
    port map (
      clk        => clk,
      rst        => rst,
      llc_user_i => llc_user_i,
      llc_user_o => llc_user_o,
      mac_i      => mac_to_llc,
      mac_o      => llc_to_mac
    );

  -- =========================================================================
  -- mac_tx: MAC sub-layer
  -- Serializer + FSM + bit stuffer
  -- =========================================================================
  mac_tx_inst : entity work.mac_tx
    port map (
      clk   => clk,
      rst   => rst,
      llc_i => llc_to_mac,
      llc_o => mac_to_llc,
      pcs_i => pcs_to_mac,
      pcs_o => mac_to_pcs,
      fce_i => fce_i,
      fce_o => fce_o
    );

  -- =========================================================================
  -- tx_pcs: PCS sub-layer
  -- Bit timing, TDC measurement, bus interface
  -- =========================================================================
  tx_pcs_inst : entity work.tx_pcs
    generic map (
      nom_prescaler        => nom_prescaler,
      nom_sync_seg         => nom_sync_seg,
      nom_prop_seg         => nom_prop_seg,
      nom_phase_seg1       => nom_phase_seg1,
      nom_phase_seg2       => nom_phase_seg2,
      data_prescaler       => data_prescaler,
      data_sync_seg        => data_sync_seg,
      data_prop_seg        => data_prop_seg,
      data_phase_seg1      => data_phase_seg1,
      data_phase_seg2      => data_phase_seg2,
      ssp_offset           => ssp_offset
    )
    port map (
      clk          => clk,
      rst          => rst,
      mac_to_pcs_i => mac_to_pcs,
      pcs_to_mac_o => pcs_to_mac,
      tx_bus_o     => tx_bus_o,
      rx_bus_i     => rx_bus_i
    );

end architecture rtl;
