--------------------------------------------------------------------------------
-- Title      : CAN MAC Receiver Top-Level
-- Project    : Implementation and Verification of a CAN-FD Bus Transceiver in VHDL
--------------------------------------------------------------------------------
-- File       : can_mac_rx.vhd
-- Author     : Mads Richardt
-- Standard   : VHDL-2008
--------------------------------------------------------------------------------
-- Description: Top-level MAC receiver wrapper. Instantiates and wires:
--   - can_mac_deser_rx: Serial-to-byte deserializer (serial -> LLC bytes)
--   - can_mac_fsm_rx:   Frame reception FSM (coordinator)
--   - can_mac_bs:        CAN FD bit stuffer (reused for destuffing)
--   - can_mac_crc:       CRC engine (reused for CRC checking)
--------------------------------------------------------------------------------

library ieee;
  use ieee.std_logic_1164.all;
  use ieee.numeric_std.all;
  use work.pk_can_types.all;

entity can_mac_rx is
  port (
    clk : in    std_logic;
    rst : in    std_logic;

    -- LLC interface (MAC is Avalon-ST source, LLC RX is sink)
    llc_i : in    t_can_llc_mac_tx_if_d2s;
    llc_o : out   t_can_llc_mac_tx_if_s2d;

    -- PCS interface (bidirectional - receives bits, sends ACK/error flags)
    pcs_i : in    t_can_mac_pcs_if_s2m;
    pcs_o : out   t_can_mac_pcs_if_m2s;

    -- Fault Confinement Entity interface
    fce_i : in    t_can_mac_fce_if_s2m;
    fce_o : out   t_can_mac_fce_if_m2s
  );
end entity can_mac_rx;

architecture rtl of can_mac_rx is

  ---------------------------------------------------------------------------
  -- Internal signals
  ---------------------------------------------------------------------------
  -- Deserializer <-> FSM (FSM is source, deser is destination)
  signal fsm_to_deser : t_can_mac_fsm_deser_if_s2d;
  signal deser_to_fsm : t_can_mac_fsm_deser_if_d2s;

  -- FSM <-> bit stuffer (destuffing)
  signal fsm_to_bs  : t_can_mac_fsm_bs_if_m2s;
  signal bs_to_fsm  : t_can_mac_fsm_bs_if_s2m;
  signal fsm_bs_rst : std_logic;

  -- FSM <-> CRC
  signal fsm_to_crc  : t_can_mac_fsm_crc_if_m2s;
  signal crc_to_fsm  : t_can_mac_fsm_crc_if_s2m;
  signal fsm_crc_rst : std_logic;

begin

  -- =========================================================================
  -- can_mac_deser_rx: Serial-to-byte deserializer
  -- =========================================================================
  rx_mac_deser_inst : entity work.can_mac_deser_rx
    port map (
      clk_i        => clk,
      rst_i        => rst,
      rx_mac_fsm_i => fsm_to_deser,
      rx_mac_fsm_o => deser_to_fsm,
      llc_i        => llc_i,
      llc_o        => llc_o
    );

  -- =========================================================================
  -- can_mac_fsm_rx: Frame reception FSM
  -- =========================================================================
  rx_mac_fsm_inst : entity work.can_mac_fsm_rx
    port map (
      clk_i       => clk,
      rst_i       => rst,
      mac_deser_i => deser_to_fsm,
      mac_deser_o => fsm_to_deser,
      pcs_i       => pcs_i,
      pcs_o       => pcs_o,
      bs_i        => bs_to_fsm,
      bs_o        => fsm_to_bs,
      bs_rst      => fsm_bs_rst,
      crc_i       => crc_to_fsm,
      crc_o       => fsm_to_crc,
      crc_rst     => fsm_crc_rst,
      fce_i       => fce_i,
      fce_o       => fce_o
    );

  -- =========================================================================
  -- can_mac_bs: CAN FD bit stuffer (reused for destuffing)
  -- =========================================================================
  bit_stuffer_inst : entity work.can_mac_bs
    port map (
      clk_i => clk,
      rst_i => rst or fsm_bs_rst,
      bs_i  => fsm_to_bs,
      bs_o  => bs_to_fsm
    );

  -- =========================================================================
  -- can_mac_crc: CRC engine (reused for CRC checking)
  -- =========================================================================
  crc_inst : entity work.can_mac_crc
    port map (
      clk_i => clk,
      rst_i => rst or fsm_crc_rst,
      crc_i => fsm_to_crc,
      crc_o => crc_to_fsm
    );

end architecture rtl;
