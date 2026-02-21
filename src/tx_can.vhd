--------------------------------------------------------------------------------
-- Title      : CAN Bus Transmitter Top-Level
-- Project    : CAN Bus Transmitter
--------------------------------------------------------------------------------
-- File       : tx_can.vhd
-- Standard   : VHDL-2008
--------------------------------------------------------------------------------
-- Description: Top-level CAN transmitter integrating all three layers:
--   - tx_llc:  LLC sub-layer (frame buffering, retransmission, Avalon-ST)
--   - mac_tx:  MAC sub-layer (serializer, FSM, bit stuffing, CRC)
--   - tx_pcs:  PCS sub-layer (bit timing, TDC, bus interface)
--------------------------------------------------------------------------------

library ieee;
  use ieee.std_logic_1164.all;
  use ieee.numeric_std.all;
  use work.can_types_pkg.all;
  use work.can_protocol_pkg.all;
  use work.can_timing_pkg.all;

entity tx_can is
  generic (
    nom_prescaler                   : integer := 2;
    nom_sync_seg                    : integer := 1;
    nom_prop_seg                    : integer := 8;
    nom_phase_seg1                  : integer := 8;
    nom_phase_seg2                  : integer := 8;
    data_prescaler                  : integer := 1;
    data_sync_seg                   : integer := 1;
    data_prop_seg                   : integer := 4;
    data_phase_seg1                 : integer := 4;
    data_phase_seg2                 : integer := 4;
    ssp_offset_cfg                  : ssp_offset := 4;
    system_clock_freq_hz            : integer := 100_000_000;
    pcs_to_pma_propagation_delay_ns : integer := 600
  );
  port (
    clk : in    std_logic;
    rst : in    std_logic;

    -- LLC user interface (application-facing)
    llc_user_i : in    llc_user_to_llc_if_t;
    llc_user_o : out   llc_to_llc_user_if_t;

    -- Fault Confinement Entity interface
    fce_i : in    fce_to_mac_if_t;
    fce_o : out   mac_to_fce_if_t;

    -- Physical bus interface
    tx_bus_o : out   std_logic;
    rx_bus_i : in    std_logic;

    -- Debug interface (monitoring internal MAC/PCS handshake and error detection)
    debug_mac_to_pcs_o        : out mac_to_pcs_if_t;
    debug_pcs_to_mac_o        : out pcs_to_mac_if_t;
    debug_strobe_type_o       : out strobe_type_t;
    debug_ack_error_o         : out boolean;     -- ACK error detected
    debug_form_error_o        : out boolean;    -- Form error detected
    debug_current_bit_rate_o  : out std_logic;  -- '0'=nominal, '1'=data
    debug_data_phase_active_o : out boolean;    -- In data phase
    debug_data_phase_exit_o   : out boolean;    -- Data phase exiting at SP
    debug_tdc_state_o         : out tx_pcs_fsm_state_t;
    debug_tdc_delay_o         : out integer;
    debug_ipt_active_o        : out boolean;
    debug_phase_seg2_active_o : out boolean;
    debug_error_at_ssp_o      : out boolean;
    debug_error_at_sp_o       : out boolean
  );
end entity tx_can;

architecture rtl of tx_can is

  ---------------------------------------------------------------------------
  -- Internal signals
  ---------------------------------------------------------------------------
  -- LLC <-> MAC
  signal llc_to_mac : llc_to_mac_if_t;
  signal mac_to_llc : mac_to_llc_if_t;

  -- MAC <-> PCS
  signal mac_to_pcs : mac_to_pcs_if_t;
  signal pcs_to_mac : pcs_to_mac_if_t;

  ---------------------------------------------------------------------------
  -- Debug signals (for test visibility)
  ---------------------------------------------------------------------------
  signal debug_pcs_state : tx_pcs_fsm_state_t;
  signal debug_pcs_delay : integer;
  signal debug_mac_ack_error : boolean;
  signal debug_mac_form_error : boolean;
  signal debug_mac_data_exit : boolean;

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
      debug_data_exit_o  => debug_mac_data_exit
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
      ssp_offset           => ssp_offset_cfg,
      system_clock_freq_hz => system_clock_freq_hz,
      pcs_to_pma_propagation_delay_ns => pcs_to_pma_propagation_delay_ns
    )
    port map (
      clk          => clk,
      rst          => rst,
      mac_to_pcs_i => mac_to_pcs,
      pcs_to_mac_o => pcs_to_mac,
      tx_bus_o     => tx_bus_o,
      rx_bus_i     => rx_bus_i
    );

  -- Wire debug ports
  debug_mac_to_pcs_o <= mac_to_pcs;
  debug_pcs_to_mac_o <= pcs_to_mac;

  -- Access internal PCS states via force-accessible signals (VHDL 2008)
  debug_pcs_state <= << signal tx_pcs_inst.state : tx_pcs_fsm_state_t >>;
  -- TDC delay_count will be exposed in future updates when force-accessible integer ranges stabilize
  debug_pcs_delay <= 0;  -- Placeholder: delay measurement not yet exposed

  -- Wire debug outputs
  debug_strobe_type_o       <= pcs_to_mac.strobe_type;
  debug_current_bit_rate_o  <= '1' when debug_pcs_state = transmitting_data else '0';
  debug_data_phase_active_o <= debug_pcs_state = transmitting_data;
  debug_tdc_state_o         <= debug_pcs_state;
  debug_tdc_delay_o         <= debug_pcs_delay;

  -- Wire error detection signals from mac_tx FSM
  debug_ack_error_o      <= debug_mac_ack_error;
  debug_form_error_o     <= debug_mac_form_error;
  debug_data_phase_exit_o <= debug_mac_data_exit;

  -- Placeholder outputs (will be implemented in Phase 3B-D)
  debug_ipt_active_o        <= false;
  debug_phase_seg2_active_o <= false;
  debug_error_at_ssp_o      <= false;
  debug_error_at_sp_o       <= false;

end architecture rtl;
