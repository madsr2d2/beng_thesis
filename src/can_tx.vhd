--------------------------------------------------------------------------------
-- Title      : CAN Bus Transmitter Top-Level
-- Project    : Implementation and Verification of a CAN-FD Bus Transceiver in VHDL
--------------------------------------------------------------------------------
-- File       : can_tx.vhd
-- Author     : Mads Richardt
-- Standard   : VHDL-2008
--------------------------------------------------------------------------------
-- Description: Top-level CAN transmitter integrating all three layers:
--   - can_llc_tx:  LLC sub-layer (frame buffering, retransmission, Avalon-ST)
--   - can_mac_tx:  MAC sub-layer (serializer, FSM, bit stuffing, CRC)
--   - can_pcs_tx:  PCS sub-layer (bit timing, TDC, bus interface)
--------------------------------------------------------------------------------

library ieee;
  use ieee.std_logic_1164.all;
  use ieee.numeric_std.all;
  use work.pk_can_types.all;
  use work.can_protocol_pkg.all;

entity can_tx is
  generic (
    gc_prescaler       : t_prescaler          := 4;
    gc_nom_sync_seg    : integer              := c_sync_seg;
    gc_nom_prop_seg    : t_nominal_prop_seg   := 24;
    gc_nom_phase_seg1  : t_nominal_phase_seg1 := 15;
    gc_nom_phase_seg2  : t_nominal_phase_seg2 := 10;
    gc_data_sync_seg   : integer              := c_sync_seg;
    gc_data_prop_seg   : t_data_prop_seg      := 8;
    gc_data_phase_seg1 : t_data_phase_seg1    := 4;
    gc_data_phase_seg2 : t_data_phase_seg2    := 4;
    gc_ssp_offset      : t_ssp_offset         := 1;
    gc_tdc_enable      : std_logic            := '1'
  );
  port (
    clk_i : in    std_logic;
    rst_i : in    std_logic;

    -- LLC user interface (application-facing)
    llc_user_i : in    t_can_user_llc_tx_if_s2d;
    llc_user_o : out   t_can_user_llc_tx_if_d2s;

    -- Fault Confinement Entity interface
    fce_i : in    t_can_mac_fce_if_s2m;
    fce_o : out   t_can_mac_fce_if_m2s;

    -- Physical bus interface
    tx_bus_o : out   std_logic;
    rx_bus_i : in    std_logic;

    -- Debug interface
    debug_mac_to_pcs_o : out t_can_mac_pcs_tx_if_m2s;
    debug_pcs_to_mac_o : out t_can_mac_pcs_tx_if_s2m;
    debug_ack_error_o  : out std_logic;
    debug_form_error_o : out std_logic;
    debug_data_exit_o  : out std_logic;
    debug_pcs_state_o  : out std_logic_vector(1 downto 0);
    debug_fsm_state_o  : out std_logic_vector(2 downto 0);
    debug_bit_name_o   : out t_mac_frame_bit_name
  );
end entity can_tx;

architecture rtl of can_tx is

  ---------------------------------------------------------------------------
  -- Internal signals
  ---------------------------------------------------------------------------
  -- LLC <-> MAC
  signal llc_to_mac : t_can_llc_mac_tx_if_s2d;
  signal mac_to_llc : t_can_llc_mac_tx_if_d2s;

  -- MAC <-> PCS
  signal mac_to_pcs : t_can_mac_pcs_tx_if_m2s;
  signal pcs_to_mac : t_can_mac_pcs_tx_if_s2m;

begin

  -- =========================================================================
  -- can_llc_tx: LLC sub-layer (legacy_rtl accepts 71-byte legacy format)
  -- =========================================================================
  tx_llc_inst : entity work.can_llc_tx(legacy_rtl)
    port map (
      clk        => clk_i,
      rst        => rst_i,
      llc_user_i => llc_user_i,
      llc_user_o => llc_user_o,
      mac_i      => mac_to_llc,
      mac_o      => llc_to_mac
    );

  -- =========================================================================
  -- can_mac_tx: MAC sub-layer
  -- =========================================================================
  mac_tx_inst : entity work.can_mac_tx
    port map (
      clk                => clk_i,
      rst                => rst_i,
      llc_i              => llc_to_mac,
      llc_o              => mac_to_llc,
      pcs_i              => pcs_to_mac,
      pcs_o              => mac_to_pcs,
      fce_i              => fce_i,
      fce_o              => fce_o,
      debug_mac_to_pcs_o => open,
      debug_pcs_to_mac_o => open,
      debug_ack_error_o  => debug_ack_error_o,
      debug_form_error_o => debug_form_error_o,
      debug_data_exit_o  => debug_data_exit_o,
      debug_fsm_state_o  => debug_fsm_state_o,
      debug_bit_name_o   => debug_bit_name_o
    );

  -- =========================================================================
  -- can_pcs_tx: PCS sub-layer
  -- =========================================================================
  tx_pcs_inst : entity work.can_pcs_tx
    generic map (
      gc_prescaler       => gc_prescaler,
      gc_nom_sync_seg    => gc_nom_sync_seg,
      gc_nom_prop_seg    => gc_nom_prop_seg,
      gc_nom_phase_seg1  => gc_nom_phase_seg1,
      gc_nom_phase_seg2  => gc_nom_phase_seg2,
      gc_data_sync_seg   => gc_data_sync_seg,
      gc_data_prop_seg   => gc_data_prop_seg,
      gc_data_phase_seg1 => gc_data_phase_seg1,
      gc_data_phase_seg2 => gc_data_phase_seg2,
      gc_ssp_offset      => gc_ssp_offset,
      gc_tdc_enable      => gc_tdc_enable
    )
    port map (
      clk_i         => clk_i,
      rst_i         => rst_i,
      mac_to_pcs_i  => mac_to_pcs,
      pcs_to_mac_o  => pcs_to_mac,
      tx_bus_o      => tx_bus_o,
      rx_bus_i      => rx_bus_i,
      debug_state_o => debug_pcs_state_o
    );

  -- Wire debug ports
  debug_mac_to_pcs_o <= mac_to_pcs;
  debug_pcs_to_mac_o <= pcs_to_mac;

end architecture rtl;
