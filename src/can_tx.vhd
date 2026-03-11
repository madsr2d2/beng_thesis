--------------------------------------------------------------------------------
-- Title      : CAN Bus Transmitter Top-Level
-- Project    : CAN Bus Transmitter
--------------------------------------------------------------------------------
-- File       : can_tx.vhd
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
  use work.can_types_pkg.all;
  use work.can_protocol_pkg.all;
  use work.can_timing_pkg.all;

entity can_tx is
  generic (
    -- Keep top-level defaults aligned with can_pcs_tx defaults (100 MHz profile).
    nom_prescaler                   : integer := 4;
    nom_sync_seg                    : integer := 1;
    nom_prop_seg                    : integer := 24;
    nom_phase_seg1                  : integer := 15;
    nom_phase_seg2                  : integer := 10;
    data_prescaler                  : integer := 2;
    data_sync_seg                   : integer := 1;
    data_prop_seg                   : integer := 8;
    data_phase_seg1                 : integer := 10;
    data_phase_seg2                 : integer := 6;
    ssp_offset_cfg                  : ssp_offset := 1;
    tdc_enable_cfg                  : boolean := true;
    system_clock_freq_hz            : integer := 100_000_000;
    pcs_to_pma_propagation_delay_ns : integer := 600
  );
  port (
    clk : in    std_logic;
    rst : in    std_logic;

    -- LLC user interface (application-facing)
    llc_user_i : in    can_user_llc_tx_if_s2d_t;
    llc_user_o : out   can_user_llc_tx_if_d2s_t;

    -- Fault Confinement Entity interface
    fce_i : in    can_mac_fce_if_s2m_t;
    fce_o : out   can_mac_fce_if_m2s_t;

    -- Physical bus interface
    tx_bus_o : out   std_logic;
    rx_bus_i : in    std_logic;

    -- Debug interface (monitoring internal MAC/PCS handshake and error detection)
    debug_mac_to_pcs_o        : out can_mac_pcs_tx_if_m2s_t;
    debug_pcs_to_mac_o        : out can_mac_pcs_tx_if_s2m_t;
    debug_strobe_type_o       : out strobe_type_t;
    debug_ack_error_o         : out boolean;     -- ACK error detected
    debug_form_error_o        : out boolean;    -- Form error detected
    debug_current_bit_rate_o  : out std_logic;  -- '0'=nominal, '1'=data
    debug_data_phase_active_o : out boolean;    -- In data phase
    debug_data_phase_exit_o   : out boolean;    -- Data phase exiting at SP
    debug_tdc_state_o         : out can_pcs_tx_state_t;
    debug_tdc_delay_o         : out integer;
    debug_ipt_active_o        : out boolean;
    debug_phase_seg2_active_o : out boolean;
    debug_error_at_ssp_o      : out boolean;
    debug_error_at_sp_o       : out boolean;
    debug_fsm_state_o         : out can_mac_fsm_tx_state_t
  );
end entity can_tx;

architecture rtl of can_tx is

  ---------------------------------------------------------------------------
  -- Internal signals
  ---------------------------------------------------------------------------
  -- LLC <-> MAC
  signal llc_to_mac : can_llc_mac_tx_if_s2d_t;
  signal mac_to_llc : can_llc_mac_tx_if_d2s_t;

  -- MAC <-> PCS
  signal mac_to_pcs : can_mac_pcs_tx_if_m2s_t;
  signal pcs_to_mac : can_mac_pcs_tx_if_s2m_t;

  ---------------------------------------------------------------------------
  -- Debug signals (for test visibility)
  ---------------------------------------------------------------------------
  signal debug_pcs_state : can_pcs_tx_state_t;
  signal debug_mac_ack_error : boolean;
  signal debug_mac_form_error : boolean;
  signal debug_mac_data_exit : boolean;

begin

  -- =========================================================================
  -- can_llc_tx: LLC sub-layer (legacy_rtl accepts 71-byte legacy format directly)
  -- Buffers frames, converts to internal format, streams to MAC, handles retx
  -- =========================================================================
  tx_llc_inst : entity work.can_llc_tx(legacy_rtl)
    port map (
      clk        => clk,
      rst        => rst,
      llc_user_i => llc_user_i,
      llc_user_o => llc_user_o,
      mac_i      => mac_to_llc,
      mac_o      => llc_to_mac
    );

  -- =========================================================================
  -- can_mac_tx: MAC sub-layer
  -- Serializer + FSM + bit stuffer
  -- =========================================================================
  mac_tx_inst : entity work.can_mac_tx
    port map (
      clk              => clk,
      rst              => rst,
      llc_i            => llc_to_mac,
      llc_o            => mac_to_llc,
      pcs_i            => pcs_to_mac,
      pcs_o            => mac_to_pcs,
      fce_i            => fce_i,
      fce_o            => fce_o,
      debug_mac_to_pcs_o => open,
      debug_pcs_to_mac_o => open,
      debug_ack_error_o  => debug_mac_ack_error,
      debug_form_error_o => debug_mac_form_error,
      debug_data_exit_o  => debug_mac_data_exit,
      debug_fsm_state_o  => debug_fsm_state_o
    );

  -- =========================================================================
  -- can_pcs_tx: PCS sub-layer
  -- Bit timing, TDC measurement, bus interface
  -- =========================================================================
  tx_pcs_inst : entity work.can_pcs_tx
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
      ssp_offset           => ssp_offset_cfg,
      tdc_enable           => tdc_enable_cfg,
      system_clock_freq_hz => system_clock_freq_hz,
      pcs_to_pma_propagation_delay_ns => pcs_to_pma_propagation_delay_ns
    )
    port map (
      clk          => clk,
      rst          => rst,
      mac_to_pcs_i => mac_to_pcs,
      pcs_to_mac_o => pcs_to_mac,
      tx_bus_o      => tx_bus_o,
      rx_bus_i      => rx_bus_i,
      debug_state_o => debug_pcs_state
    );

  -- Wire debug ports
  debug_mac_to_pcs_o <= mac_to_pcs;
  debug_pcs_to_mac_o <= pcs_to_mac;

  -- Wire debug outputs
  debug_strobe_type_o       <= pcs_to_mac.strobe_type;
  debug_current_bit_rate_o  <= '1' when debug_pcs_state = transmitting_data else '0';
  debug_data_phase_active_o <= debug_pcs_state = transmitting_data;
  debug_tdc_state_o         <= debug_pcs_state;
  debug_tdc_delay_o         <= 0;  -- Placeholder: TDC delay not yet exposed

  -- Wire error detection signals from can_mac_tx FSM
  debug_ack_error_o      <= debug_mac_ack_error;
  debug_form_error_o     <= debug_mac_form_error;
  debug_data_phase_exit_o <= debug_mac_data_exit;

  -- Placeholder outputs (will be implemented in Phase 3B-D)
  debug_ipt_active_o        <= false;
  debug_phase_seg2_active_o <= false;
  debug_error_at_ssp_o      <= false;
  debug_error_at_sp_o       <= false;

end architecture rtl;
