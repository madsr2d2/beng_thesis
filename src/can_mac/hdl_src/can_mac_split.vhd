--------------------------------------------------------------------------------
-- Title      : MAC layer split-path architecture for CAN/CAN-FD
-- Project    : Implementation and Verification of a CAN-FD Bus Transceiver in VHDL
--------------------------------------------------------------------------------
-- File       : can_mac_split.vhd
-- Author     : Mads Richardt
-- Standard   : VHDL-2008
--------------------------------------------------------------------------------
-- Description: Second architecture of can_mac (architecture split_rtl) that
--              wires the legacy split TX/RX FSMs (can_mac_tx + can_mac_rx)
--              with dominant-wins PCS merging and OR-based FCE merging.
--
--              Used to verify that the bugs found in the split FSMs are real
--              and that fixing them makes the split path pass the same test
--              suite as the combined FSM (architecture rtl in can_mac.vhd).
--
--              Key differences vs rtl architecture:
--                - Two independent BS and CRC engines (one per TX, one per RX)
--                - fce_o.transmitting from can_mac_tx drives transmitting_i of
--                  can_mac_rx to gate RX ACK drive and LLC frame delivery
--                - PCS outputs merged with dominant-wins on tx_data, OR on
--                  control/timing strobes (both sides may request a phase switch)
--                - FCE outputs merged with OR (any error from either side is real)
--------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use work.pk_can_types.all;

architecture split_rtl of can_mac is

  signal tx_pcs_o : t_can_mac_pcs_if_m2s;
  signal rx_pcs_o : t_can_mac_pcs_if_m2s;
  signal tx_fce_o : t_can_mac_fce_if_m2s;
  signal rx_fce_o : t_can_mac_fce_if_m2s;

begin

  ---------------------------------------------------------------------------
  -- can_mac_tx: LLC serializer + TX FSM + BS + CRC (TX path)
  ---------------------------------------------------------------------------
  u_can_mac_tx : entity work.can_mac_tx
    port map(
      clk   => clk,
      rst   => rst,
      llc_i => tx_llc_i,
      llc_o => tx_llc_o,
      pcs_i => pcs_i,
      pcs_o => tx_pcs_o,
      fce_i => fce_i,
      fce_o => tx_fce_o
    );

  ---------------------------------------------------------------------------
  -- can_mac_rx: RX FSM + BS + CRC (RX path)
  -- transmitting_i gated by TX FSM's fce_o.transmitting so the RX side
  -- suppresses ACK drive and LLC delivery while TX owns the bus.
  ---------------------------------------------------------------------------
  u_can_mac_rx : entity work.can_mac_rx
    port map(
      clk            => clk,
      rst            => rst,
      llc_i          => rx_llc_i,
      llc_o          => rx_llc_o,
      pcs_i          => pcs_i,
      pcs_o          => rx_pcs_o,
      fce_i          => fce_i,
      fce_o          => rx_fce_o,
      transmitting_i => tx_fce_o.transmitting
    );

  ---------------------------------------------------------------------------
  -- PCS merge: dominant-wins for tx_data, OR for all control signals.
  -- c_dominant='0' so AND implements dominant-wins.
  ---------------------------------------------------------------------------
  pcs_o.tx_data         <= tx_pcs_o.tx_data and rx_pcs_o.tx_data;
  pcs_o.transmitting    <= tx_pcs_o.transmitting    or rx_pcs_o.transmitting;
  pcs_o.next_bit_is_res <= tx_pcs_o.next_bit_is_res or rx_pcs_o.next_bit_is_res;
  pcs_o.next_bit_is_brs <= tx_pcs_o.next_bit_is_brs or rx_pcs_o.next_bit_is_brs;
  pcs_o.data_phase_stop <= tx_pcs_o.data_phase_stop or rx_pcs_o.data_phase_stop;
  pcs_o.do_hard_sync    <= tx_pcs_o.do_hard_sync    or rx_pcs_o.do_hard_sync;

  ---------------------------------------------------------------------------
  -- FCE merge: OR all fields.
  -- passive_tx_ack_error_exempt_1 is TX-only; RX always drives '0'.
  ---------------------------------------------------------------------------
  fce_o.transmitting                  <= tx_fce_o.transmitting                  or rx_fce_o.transmitting;
  fce_o.error                         <= tx_fce_o.error                         or rx_fce_o.error;
  fce_o.primary_error                 <= tx_fce_o.primary_error                 or rx_fce_o.primary_error;
  fce_o.sending_error_overload_flag   <= tx_fce_o.sending_error_overload_flag   or rx_fce_o.sending_error_overload_flag;
  fce_o.passive_tx_ack_error_exempt_1 <= tx_fce_o.passive_tx_ack_error_exempt_1;
  fce_o.error_delimiter_too_late      <= tx_fce_o.error_delimiter_too_late      or rx_fce_o.error_delimiter_too_late;
  fce_o.successful_transfer           <= tx_fce_o.successful_transfer           or rx_fce_o.successful_transfer;

end architecture split_rtl;

-- eof
