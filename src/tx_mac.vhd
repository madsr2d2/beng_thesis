--------------------------------------------------------------------------------
-- Title      : CAN MAC Transmitter Top-Level
-- Project    : CAN Bus Transmitter
--------------------------------------------------------------------------------
-- File       : tx_mac.vhd
-- Standard   : VHDL-2008
--------------------------------------------------------------------------------
-- Description: Top-level MAC transmitter wrapper. Instantiates and wires:
--   - tx_mac_ser:    LLC byte serializer (LLC → polarity_t stream)
--   - tx_mac_fsm:    Frame transmission FSM (coordinator)
--   - bit_stuffer_fd: CAN FD bit stuffing with SBC generation
--
-- External interfaces:
--   - LLC (Logical Link Control): Avalon-ST byte stream input
--   - PCS (Physical Coding Sublayer): mac_frame_bit_t output + timing strobes
--------------------------------------------------------------------------------

library ieee;
  use ieee.std_logic_1164.all;
  use ieee.numeric_std.all;
  use work.can_pkg.all;

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
    fce_o : out   mac_to_fce_if_t
  );
end entity mac_tx;

architecture rtl of mac_tx is

  -- Internal signals: serializer <-> FSM
  signal ser_to_fsm : tx_mac_ser_to_fsm_if_t;
  signal fsm_to_ser : tx_mac_fsm_to_ser_if_t;

  -- Internal signals: FSM <-> bit stuffer FD
  signal fsm_to_bs_fd : mac_fsm_to_bs_fd_if_t;
  signal bs_fd_to_fsm : bs_fd_to_mac_fsm_if_t;

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
      clk       => clk,
      rst       => rst,
      mac_ser_i => ser_to_fsm,
      mac_ser_o => fsm_to_ser,
      pcs_i     => pcs_i,
      pcs_o     => pcs_o,
      bs_fd_i   => bs_fd_to_fsm,
      bs_fd_o   => fsm_to_bs_fd,
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
      rst_i   => rst,
      bs_fd_i => fsm_to_bs_fd,
      bs_fd_o => bs_fd_to_fsm
    );

end architecture rtl;
