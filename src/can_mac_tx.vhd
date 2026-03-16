--------------------------------------------------------------------------------
-- Title      : CAN MAC Transmitter Top-Level
-- Project    : Implementation and Verification of a CAN-FD Bus Transceiver in VHDL
--------------------------------------------------------------------------------
-- File       : can_mac_tx.vhd
-- Author     : Mads Richardt
-- Standard   : VHDL-2008
--------------------------------------------------------------------------------
-- Description: Top-level MAC transmitter wrapper. Instantiates and wires:
--   - can_mac_ser_tx:  LLC byte serializer (LLC -> serial bit stream)
--   - can_mac_fsm_tx:  Frame transmission FSM (coordinator)
--   - can_mac_bs_tx:   CAN FD bit stuffing with SBC generation
--   - can_mac_crc_tx:  CRC engine interface
--------------------------------------------------------------------------------

library ieee;
  use ieee.std_logic_1164.all;
  use ieee.numeric_std.all;
  use work.pk_can_types.all;
  use work.can_protocol_pkg.all;

entity can_mac_tx is
  port (
    clk : in    std_logic;
    rst : in    std_logic;

    -- LLC interface (Logical Link Control)
    llc_i : in    t_can_llc_mac_tx_if_s2d;
    llc_o : out   t_can_llc_mac_tx_if_d2s;

    -- PCS interface (Physical Coding Sublayer)
    pcs_i : in    t_can_mac_pcs_tx_if_s2m;
    pcs_o : out   t_can_mac_pcs_tx_if_m2s;

    -- Fault Confinement Entity interface
    fce_i : in    t_can_mac_fce_if_s2m;
    fce_o : out   t_can_mac_fce_if_m2s;

    -- Debug interface
    debug_mac_to_pcs_o  : out t_can_mac_pcs_tx_if_m2s;
    debug_pcs_to_mac_o  : out t_can_mac_pcs_tx_if_s2m;
    debug_ack_error_o   : out std_logic;
    debug_form_error_o  : out std_logic;
    debug_data_exit_o   : out std_logic;
    debug_fsm_state_o   : out std_logic_vector(2 downto 0);
    debug_bit_name_o    : out t_mac_frame_bit_name
  );
end entity can_mac_tx;

architecture rtl of can_mac_tx is

  ---------------------------------------------------------------------------
  -- Internal signals
  ---------------------------------------------------------------------------
  -- Serializer <-> FSM
  signal ser_to_fsm : t_can_mac_ser_fsm_tx_if_s2m;
  signal fsm_to_ser : t_can_mac_ser_fsm_tx_if_m2s;

  -- FSM <-> bit stuffer FD
  signal fsm_to_bs_fd : t_can_mac_fsm_bs_tx_if_m2s;
  signal bs_fd_to_fsm : t_can_mac_fsm_bs_tx_if_s2m;

  -- FSM <-> CRC
  signal fsm_to_crc : t_can_mac_fsm_crc_tx_if_m2s;
  signal crc_to_fsm : t_can_mac_fsm_crc_tx_if_s2m;

begin

  -- =========================================================================
  -- can_mac_ser_tx: LLC byte serializer
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
  -- =========================================================================
  tx_mac_fsm_inst : entity work.can_mac_fsm_tx
    port map (
      clk_i              => clk,
      rst_i              => rst,
      mac_ser_i          => ser_to_fsm,
      mac_ser_o          => fsm_to_ser,
      pcs_i              => pcs_i,
      pcs_o              => pcs_o,
      bs_fd_i            => bs_fd_to_fsm,
      bs_fd_o            => fsm_to_bs_fd,
      crc_i              => crc_to_fsm,
      crc_o              => fsm_to_crc,
      fce_i              => fce_i,
      fce_o              => fce_o,
      debug_ack_error_o  => debug_ack_error_o,
      debug_form_error_o => debug_form_error_o,
      debug_data_exit_o  => debug_data_exit_o,
      debug_fsm_state_o  => debug_fsm_state_o,
      debug_bit_name_o   => debug_bit_name_o
    );

  -- =========================================================================
  -- can_mac_bs_tx: CAN FD bit stuffing with SBC generation
  -- =========================================================================
  bit_stuffer_fd_inst : entity work.can_mac_bs_tx
    port map (
      clk_i => clk,
      rst_i => rst,
      bs_i  => fsm_to_bs_fd,
      bs_o  => bs_fd_to_fsm
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

end architecture rtl;
