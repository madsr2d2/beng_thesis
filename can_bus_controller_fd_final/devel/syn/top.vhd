--------------------------------------------------------------------------------------------------------------------------------------------------------------
-- Copyright 2026 Everllence, Teglholmsgade 41, 2450 Copenhagen SV, Denmark
--------------------------------------------------------------------------------------------------------------------------------------------------------------
--
-- Requirements:
--
-- Description:   Synthesis wrapper for can_mac_pcs_fce.
--                Flattens record-typed ports into individual std_logic /
--                std_logic_vector signals so Quartus accepts the entity as
--                the top-level.  All ports are marked VIRTUAL_PIN in the
--                .qsf (synthesis / timing check only, not for programming).
--
-- Revision log:  Date:       Initial:  JIRA:
--                2026-05-18  TMYAES:   [TRIT-4355] Initial synthesis wrapper
--
--------------------------------------------------------------------------------------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use work.pk_eth_st.all;
use work.pk_can_types.all;


entity can_mac_pcs_fce_top is
  port(
    -- Clock and reset
    clk_i             : in  std_logic;
    reset_i           : in  std_logic;
    -- TX LLC – source side (LLC → MAC)
    tx_llc_valid_i    : in  std_logic;
    tx_llc_sop_i      : in  std_logic;
    tx_llc_eop_i      : in  std_logic;
    tx_llc_data_i     : in  std_logic_vector(7 downto 0);
    -- TX LLC – destination side (MAC → LLC)
    tx_llc_ready_o    : out std_logic;
    tx_llc_status_o   : out std_logic_vector(2 downto 0);
    -- RX LLC – destination side / backpressure (LLC → MAC)
    rx_llc_ready_i    : in  std_logic;
    -- RX LLC – source side (MAC → LLC)
    rx_llc_valid_o    : out std_logic;
    rx_llc_sop_o      : out std_logic;
    rx_llc_eop_o      : out std_logic;
    rx_llc_data_o     : out std_logic_vector(7 downto 0);
    -- LLC-FCE interface
    fce_normal_mode_i : in  std_logic;
    fce_bus_off_o     : out std_logic;
    -- Physical bus
    tx_o              : out std_logic;
    rx_i              : in  std_logic
  );
end entity can_mac_pcs_fce_top;


architecture rtl of can_mac_pcs_fce_top is

  signal tx_llc_s : t_can_llc_mac_tx_if_s2d;
  signal tx_llc_d : t_can_llc_mac_tx_if_d2s;
  signal rx_llc_d : t_can_llc_mac_rx_if_d2s;
  signal rx_llc_s : t_can_llc_mac_rx_if_s2d;
  signal llc_fce  : t_can_llc_fce_if_m2s;
  signal fce_llc  : t_can_fce_llc_if_s2m;

begin

  -- Assemble TX LLC record from flat input ports
  tx_llc_s.avalon_st_source.valid         <= tx_llc_valid_i;
  tx_llc_s.avalon_st_source.startofpacket <= tx_llc_sop_i;
  tx_llc_s.avalon_st_source.endofpacket   <= tx_llc_eop_i;
  tx_llc_s.avalon_st_source.data          <= tx_llc_data_i;

  -- Unpack TX LLC record to flat output ports
  tx_llc_ready_o  <= tx_llc_d.avalon_st_sink.ready;
  tx_llc_status_o <= tx_llc_d.transfer_status;

  -- Assemble RX LLC backpressure record from flat input port
  rx_llc_d.avalon_st_sink.ready <= rx_llc_ready_i;

  -- Unpack RX LLC source record to flat output ports
  rx_llc_valid_o <= rx_llc_s.avalon_st_source.valid;
  rx_llc_sop_o   <= rx_llc_s.avalon_st_source.startofpacket;
  rx_llc_eop_o   <= rx_llc_s.avalon_st_source.endofpacket;
  rx_llc_data_o  <= rx_llc_s.avalon_st_source.data;

  -- FCE interface
  llc_fce.normal_mode <= fce_normal_mode_i;
  fce_bus_off_o       <= fce_llc.bus_off;

  u_dut : entity work.can_mac_pcs_fce
    port map(
      clk_i     => clk_i,
      reset_i   => reset_i,
      tx_llc_i  => tx_llc_s,
      tx_llc_o  => tx_llc_d,
      rx_llc_i  => rx_llc_d,
      rx_llc_o  => rx_llc_s,
      llc_fce_i => llc_fce,
      llc_fce_o => fce_llc,
      tx_o      => tx_o,
      rx_i      => rx_i
    );

end architecture rtl;


--#############################################################################
-- EOF
