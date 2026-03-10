--------------------------------------------------------------------------------
-- Title      : CAN MAC Transmitter Top-Level
-- Project    : CAN Bus Transmitter
--------------------------------------------------------------------------------
-- File       : tx_mac.vhd
-- Standard   : VHDL-2008
--------------------------------------------------------------------------------
-- Description: Top-level MAC transmitter wrapper. Instantiates and wires:
--   - can_mac_ser_tx:    LLC byte serializer (LLC → polarity_t stream)
--   - can_mac_fsm_tx: Frame transmission FSM (coordinator)
--   - can_mac_bs_tx: CAN FD bit stuffing with SBC generation
--   - can_mac_crc_tx: CRC engine interface
--------------------------------------------------------------------------------

library ieee;
  use ieee.std_logic_1164.all;
  use ieee.numeric_std.all;
  use work.can_types_pkg.all;
  use work.can_protocol_pkg.all;
  use work.can_timing_pkg.all;

entity can_mac_tx is
  port (
    clk : in    std_logic;
    rst : in    std_logic;

    -- LLC interface (Logical Link Control)
    llc_i : in    can_llc_mac_tx_if_s2d_t;
    llc_o : out   can_llc_mac_tx_if_d2s_t;

    -- PCS interface (Physical Coding Sublayer)
    pcs_i : in    can_mac_pcs_tx_if_d2s_t;
    pcs_o : out   can_mac_pcs_tx_if_s2d_t;

    -- Fault Confinement Entity interface
    fce_i : in    can_mac_fce_if_d2s_t;
    fce_o : out   can_mac_fce_if_s2d_t;

    -- Debug interface (monitoring internal MAC/PCS handshake)
    debug_mac_to_pcs_o  : out can_mac_pcs_tx_if_s2d_t;
    debug_pcs_to_mac_o  : out can_mac_pcs_tx_if_d2s_t;
    debug_ack_error_o   : out boolean;
    debug_form_error_o  : out boolean;
    debug_data_exit_o   : out boolean;
    debug_fsm_state_o   : out can_mac_fsm_tx_state_t
  );
end entity can_mac_tx;

architecture rtl of can_mac_tx is

  ---------------------------------------------------------------------------
  -- Internal signals
  ---------------------------------------------------------------------------
  -- Serializer <-> FSM
  signal ser_to_fsm : can_mac_ser_fsm_tx_if_s2d_t;
  signal fsm_to_ser : can_mac_ser_fsm_tx_if_d2s_t;

  -- FSM <-> bit stuffer FD
  signal fsm_to_bs_fd : can_mac_fsm_bs_tx_if_s2d_t;
  signal bs_fd_to_fsm : can_mac_fsm_bs_tx_if_d2s_t;

  -- FSM <-> CRC
  signal fsm_to_crc : can_mac_fsm_crc_tx_if_s2d_t;
  signal crc_to_fsm : can_mac_fsm_crc_tx_if_d2s_t;


begin

  -- =========================================================================
  -- can_mac_ser_tx: LLC byte serializer
  -- Converts Avalon-ST LLC bytes to serial polarity_t stream + frame_params
  -- =========================================================================
  tx_mac_ser_inst : entity work.can_mac_ser_tx
    port map (
      clk_i        => clk,
      rst_i        => rst,
      llc_i        => llc_i,
      llc_o        => llc_o,
      tx_mac_fsm_i => fsm_to_ser,
      tx_mac_fsm_o => ser_to_fsm
    );

  -- =========================================================================
  -- can_mac_fsm_tx: Frame transmission FSM
  -- Coordinates serializer, bit stuffer, and PCS
  -- =========================================================================
  tx_mac_fsm_inst : entity work.can_mac_fsm_tx
    port map (
      clk_i     => clk,
      rst_i     => rst,
      mac_ser_i => ser_to_fsm,
      mac_ser_o => fsm_to_ser,
      pcs_i     => pcs_i,
      pcs_o     => pcs_o,
      bs_fd_i   => bs_fd_to_fsm,
      bs_fd_o   => fsm_to_bs_fd,
      crc_i     => crc_to_fsm,
      crc_o     => fsm_to_crc,
      fce_i              => fce_i,
      fce_o              => fce_o,
      debug_ack_error_o  => debug_ack_error_o,
      debug_form_error_o => debug_form_error_o,
      debug_data_exit_o  => debug_data_exit_o,
      debug_fsm_state_o  => debug_fsm_state_o
    );

  -- =========================================================================
  -- can_mac_bs_tx: CAN FD bit stuffing with SBC generation
  -- Inserts stuff bits per CAN protocol rules
  -- =========================================================================
  bit_stuffer_fd_inst : entity work.can_mac_bs_tx
    port map (
      clk_i   => clk,
      rst_i     => rst,
      bs_fd_i => fsm_to_bs_fd,
      bs_fd_o => bs_fd_to_fsm
    );

  -- =========================================================================
  -- can_mac_crc_tx: CRC engine
  -- =========================================================================
  crc_fd_inst : entity work.can_mac_crc_tx
    port map (
      clk_i => clk,
      rst_i => rst,
      crc_i => fsm_to_crc,
      crc_o => crc_to_fsm
    );

  -- Wire debug ports
  debug_mac_to_pcs_o <= pcs_o;
  debug_pcs_to_mac_o <= pcs_i;

  -- debug_ack_error_o, debug_form_error_o, debug_data_exit_o are wired
  -- directly via the tx_mac_fsm_inst port map above.

end architecture rtl;
