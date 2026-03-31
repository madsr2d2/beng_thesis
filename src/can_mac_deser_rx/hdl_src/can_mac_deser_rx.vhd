--------------------------------------------------------------------------------
-- Title      : CAN MAC Receiver Deserializer
-- Project    : Implementation and Verification of a CAN-FD Bus Transceiver in VHDL
--------------------------------------------------------------------------------
-- File       : can_mac_deser_rx.vhd
-- Author     : Mads Richardt
-- Standard   : VHDL-2008
--------------------------------------------------------------------------------
-- Description: Serial-to-byte deserializer for the RX MAC path. Receives
--              destuffed bits from the FSM, assembles them into bytes, and
--              presents the reconstructed frame to the LLC layer via
--              Avalon-ST source interface.
--------------------------------------------------------------------------------

library ieee;
  use ieee.std_logic_1164.all;
  use ieee.numeric_std.all;
  use work.pk_can_types.all;

entity can_mac_deser_rx is
  port (
    clk_i : in    std_logic;
    rst_i : in    std_logic;

    -- FSM interface (FSM is source, deser is destination)
    rx_mac_fsm_i : in    t_can_mac_fsm_deser_if_s2d;
    rx_mac_fsm_o : out   t_can_mac_fsm_deser_if_d2s;

    -- LLC interface (Avalon-ST source - deser pushes bytes to LLC RX)
    llc_i : in    t_can_llc_mac_tx_if_d2s;
    llc_o : out   t_can_llc_mac_tx_if_s2d
  );
end entity can_mac_deser_rx;

architecture rtl of can_mac_deser_rx is

begin

  -- TODO: implement RX deserializer

end architecture rtl;
