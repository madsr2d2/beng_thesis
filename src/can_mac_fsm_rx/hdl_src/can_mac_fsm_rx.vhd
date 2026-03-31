--------------------------------------------------------------------------------------------------------------------------------------------------------------
-- Copyright 2026 Everllence, Teglholmsgade 41, 2450 Copenhagen SV, Denmark
--------------------------------------------------------------------------------------------------------------------------------------------------------------
--
-- Requirements:
--
-- Description:   Frame reception FSM. Tracks incoming frame state, drives ACK
--                and error/overload flags onto the bus via PCS, coordinates
--                bit destuffing (via shared can_mac_bs) and CRC checking
--                (via shared can_mac_crc), and signals the deserializer.
--
-- Revision log:  Date:       Initial:  JIRA:
--                2026-03-31  MRDSA     Converted to company header format
--------------------------------------------------------------------------------------------------------------------------------------------------------------

library ieee;
  use ieee.std_logic_1164.all;
  use ieee.numeric_std.all;
  use work.pk_can_types.all;

entity can_mac_fsm_rx is
  port (
    clk_i : in    std_logic;
    rst_i : in    std_logic;

    -- Deserializer interface (FSM is source, deser is destination)
    mac_deser_i : in    t_can_mac_fsm_deser_if_d2s;
    mac_deser_o : out   t_can_mac_fsm_deser_if_s2d;

    -- PCS interface (bidirectional - RX receives and sends ACK/error flags)
    pcs_i : in    t_can_mac_pcs_if_s2m;
    pcs_o : out   t_can_mac_pcs_if_m2s;

    -- Bit stuffer interface (reused for destuffing)
    bs_i   : in    t_can_mac_fsm_bs_if_s2m;
    bs_o   : out   t_can_mac_fsm_bs_if_m2s;
    bs_rst : out   std_logic;

    -- CRC interface (reused for CRC checking)
    crc_i   : in    t_can_mac_fsm_crc_if_s2m;
    crc_o   : out   t_can_mac_fsm_crc_if_m2s;
    crc_rst : out   std_logic;

    -- Fault Confinement Entity interface
    fce_i : in    t_can_mac_fce_if_s2m;
    fce_o : out   t_can_mac_fce_if_m2s
  );
end entity can_mac_fsm_rx;

architecture rtl of can_mac_fsm_rx is

begin

-- TODO: implement RX FSM

end architecture rtl;
