--------------------------------------------------------------------------------
-- Title      : CAN MAC Transmitter Top-Level
-- Project    : CAN Bus Transmitter
--------------------------------------------------------------------------------
-- File       : tx_mac.vhd
-- Standard   : VHDL-2008
--------------------------------------------------------------------------------
-- Description: Top-level MAC transmitter wrapper. Instantiates and wires:
--   - tx_mac_ser:    LLC byte serializer (LLC → polarity_t stream)
--   - tx_mac_fsm: Frame transmission FSM (coordinator)
--   - bit_stuffer_fd: CAN FD bit stuffing with SBC generation
--   - crc_fd: CRC engine interface
--------------------------------------------------------------------------------

library ieee;
  use ieee.std_logic_1164.all;
  use ieee.numeric_std.all;
  use work.can_types_pkg.all;
  use work.can_protocol_pkg.all;
  use work.can_timing_pkg.all;

entity mac_tx is
  port (
    clk : in    std_logic;
    rst : in    std_logic;

    -- LLC interface (Logical Link Control)
    llc_i : in    llc_to_mac_if_t;
    llc_o : out   mac_to_llc_if_t;

    -- PCS interface (Physical Coding Sublayer)
    pcs_i : in    pcs_to_mac_if_t;
    pcs_o : out   mac_to_pcs_if_t;

    -- Fault Confinement Entity interface
    fce_i : in    fce_to_mac_if_t;
    fce_o : out   mac_to_fce_if_t;

    -- Debug interface (monitoring internal MAC/PCS handshake)
    debug_mac_to_pcs_o  : out mac_to_pcs_if_t;
    debug_pcs_to_mac_o  : out pcs_to_mac_if_t;
    debug_ack_error_o   : out boolean;
    debug_form_error_o  : out boolean;
    debug_data_exit_o   : out boolean
  );
end entity mac_tx;

architecture rtl of mac_tx is

  ---------------------------------------------------------------------------
  -- Internal signals
  ---------------------------------------------------------------------------
  -- Serializer <-> FSM
  signal ser_to_fsm : tx_mac_ser_to_fsm_if_t;
  signal fsm_to_ser : tx_mac_fsm_to_ser_if_t;

  -- FSM <-> bit stuffer FD
  signal fsm_to_bs_fd : mac_fsm_to_bs_fd_if_t;
  signal bs_fd_to_fsm : bs_fd_to_mac_fsm_if_t;

  -- FSM <-> CRC
  signal fsm_to_crc : mac_fsm_to_crc_if_t;
  signal crc_to_fsm : crc_to_mac_fsm_if_t;

begin

  -- =========================================================================
  -- tx_mac_ser: LLC byte serializer
  -- Converts Avalon-ST LLC bytes to serial polarity_t stream + frame_params
  -- =========================================================================
  tx_mac_ser_inst : entity work.tx_mac_ser
    port map (
      clk_i        => clk,
      rst_i        => rst,
      llc_i        => llc_i,
      llc_o        => llc_o,
      tx_mac_fsm_i => fsm_to_ser,
      tx_mac_fsm_o => ser_to_fsm
    );

  -- =========================================================================
  -- tx_mac_fsm: Frame transmission FSM
  -- Coordinates serializer, bit stuffer, and PCS
  -- =========================================================================
  tx_mac_fsm_inst : entity work.tx_mac_fsm
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
      fce_i     => fce_i,
      fce_o     => fce_o
    );

  -- =========================================================================
  -- bit_stuffer_fd: CAN FD bit stuffing with SBC generation
  -- Inserts stuff bits per CAN protocol rules
  -- =========================================================================
  bit_stuffer_fd_inst : entity work.bit_stuffer_fd
    port map (
      clk_i   => clk,
      reset_i   => rst,
      bs_fd_i => fsm_to_bs_fd,
      bs_fd_o => bs_fd_to_fsm
    );

  -- =========================================================================
  -- crc_fd: CRC engine
  -- =========================================================================
  crc_fd_inst : entity work.crc_fd
    port map (
      clk_i => clk,
      rst_i => rst,
      crc_i => fsm_to_crc,
      crc_o => crc_to_fsm
    );

  -- Wire debug ports
  debug_mac_to_pcs_o <= pcs_o;
  debug_pcs_to_mac_o <= pcs_i;

  -- Access FSM debug signals via force-accessible attributes (VHDL 2008)
  debug_ack_error_o  <= << signal tx_mac_fsm_inst.ack_error_detected : boolean >>;
  debug_form_error_o <= << signal tx_mac_fsm_inst.form_error_detected : boolean >>;
  debug_data_exit_o  <= << signal tx_mac_fsm_inst.data_phase_exit_strobe : boolean >>;

end architecture rtl;
