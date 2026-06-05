--------------------------------------------------------------------------------------------------------------------------------------------------------------
-- Copyright 2026 Everllence, Teglholmsgade 41, 2450 Copenhagen SV, Denmark
--------------------------------------------------------------------------------------------------------------------------------------------------------------
--
-- Requirements:  
--
-- Description:   Structural wrapper instantiating CAN MAC FSM, PCS and FSM modules.
--
-- Revision log:  Date:       Initial:  JIRA:
--                2026-03-23  TMYAES:   [TRIT-4355] [FPGA] Controlling FSM form MAC layer in CAN-FD module
--
--------------------------------------------------------------------------------------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use work.pk_can_types.all;

entity can_mac is
  port(
    clk_i    : in  std_logic;
    reset_i  : in  std_logic;

    -- TX LLC interface
    tx_llc_i : in  t_can_llc_mac_tx_if_s2d;
    tx_llc_o : out t_can_llc_mac_tx_if_d2s;

    -- RX LLC interface
    rx_llc_i : in  t_can_llc_mac_rx_if_d2s;
    rx_llc_o : out t_can_llc_mac_rx_if_s2d;

    -- PCS interface
    pcs_i    : in  t_can_mac_pcs_if_s2m;
    pcs_o    : out t_can_mac_pcs_if_m2s;

    -- FCE interface
    fce_i    : in  t_can_mac_fce_if_s2m;
    fce_o    : out t_can_mac_fce_if_m2s
  );
end entity can_mac;

architecture rtl of can_mac is

  ---------------------------------------------------------------------------
  -- Internal signals
  ---------------------------------------------------------------------------
  -- Serializer <-> FSM
  signal ser_to_fsm : t_can_mac_ser_fsm_if_s2d;
  signal fsm_to_ser : t_can_mac_ser_fsm_if_d2s;

  -- FSM <-> Bit stuffer
  signal fsm_to_bs  : t_can_mac_fsm_bs_if_m2s;
  signal bs_to_fsm  : t_can_mac_fsm_bs_if_s2m;
  signal fsm_bs_rst : std_logic;

  -- FSM <-> CRC
  signal fsm_to_crc  : t_can_mac_fsm_crc_if_m2s;
  signal crc_to_fsm  : t_can_mac_fsm_crc_if_s2m;
  signal fsm_crc_rst : std_logic;

begin

  ---------------------------------------------------------------------------
  -- can_mac_ser: LLC byte serializer (TX path)
  ---------------------------------------------------------------------------
  u_can_mac_ser : entity work.can_mac_ser
    port map(
      clk_i        => clk_i,
      reset_i      => reset_i,
      llc_i        => tx_llc_i,
      llc_o        => tx_llc_o,
      tx_mac_fsm_i => fsm_to_ser,
      tx_mac_fsm_o => ser_to_fsm
    );

  ---------------------------------------------------------------------------
  -- can_mac_fsm: combined MAC FSM (handles both TX and RX)
  ---------------------------------------------------------------------------
  u_can_mac_fsm : entity work.can_mac_fsm
    port map(
      clk_i     => clk_i,
      reset_i   => reset_i,
      mac_ser_i => ser_to_fsm,
      mac_ser_o => fsm_to_ser,
      llc_i     => rx_llc_i,
      llc_o     => rx_llc_o,
      pcs_i     => pcs_i,
      pcs_o     => pcs_o,
      bs_i      => bs_to_fsm,
      bs_o      => fsm_to_bs,
      bs_rst    => fsm_bs_rst,
      crc_i     => crc_to_fsm,
      crc_o     => fsm_to_crc,
      crc_rst   => fsm_crc_rst,
      fce_i     => fce_i,
      fce_o     => fce_o
    );

  ---------------------------------------------------------------------------
  -- can_mac_bs: shared bit stuffer (used by both TX and RX modes)
  ---------------------------------------------------------------------------
  u_can_mac_bs : entity work.can_mac_bs
    port map(
      clk_i   => clk_i,
      reset_i => reset_i or fsm_bs_rst,
      bs_i    => fsm_to_bs,
      bs_o    => bs_to_fsm
    );

  ---------------------------------------------------------------------------
  -- can_mac_crc: shared CRC engine (used by both TX and RX modes)
  ---------------------------------------------------------------------------
  u_can_mac_crc : entity work.can_mac_crc
    port map(
      clk_i   => clk_i,
      reset_i => reset_i or fsm_crc_rst,
      crc_i   => fsm_to_crc,
      crc_o   => crc_to_fsm
    );

end architecture rtl;

-- eof
