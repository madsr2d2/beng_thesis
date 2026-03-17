--------------------------------------------------------------------------------------------------------------------------------------------------------------
-- Copyright 2026 Everllence, Teglholmsgade 41, 2450 Copenhagen SV, Denmark
--------------------------------------------------------------------------------------------------------------------------------------------------------------
--
-- Requirements:  
--
-- Description:
--
-- Revision log:  Date:       Initial:  JIRA:
--                2026-03-16  TMYAES    Initial implementation
--
--------------------------------------------------------------------------------------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.pk_can_types.all;
use work.pk_man_global.all;
use work.pk_eth_st.all;

use work.common_register_interface_pkg.all;
use work.common_tb_pkg.all;

library osvvm;
context osvvm.OsvvmContext;


entity can_mac_ser_tx_tb is  generic (
    gc_TbTimeOut   : time := 2 ms;
    gc_TbClkPeriod : time := 10 ns
  );
end entity can_mac_ser_tx_tb;

architecture tb of can_mac_ser_tx_tb is

  signal clk : std_logic := '0';
  signal reset : std_logic := '0';

  -- LLC interface signals
  signal llc_i : t_can_llc_mac_tx_if_s2d := (avalon_st_source => c_eth_st_s2d_zero_idle );
  signal llc_o : t_can_llc_mac_tx_if_d2s := (avalon_st_sink => c_eth_st_d2s_idle, transfer_status => c_transmitted);

  -- can_mac_fsm_tx interface signals
  signal tx_mac_fsm_i : t_can_mac_ser_fsm_tx_if_m2s;
  signal tx_mac_fsm_o : t_can_mac_ser_fsm_tx_if_s2m;

begin

  ----------------------------------------------------------------------------
  -- Clock
  ----------------------------------------------------------------------------
  CreateClock(clk, gc_TbClkPeriod);

  -- DUT instantiation
  u_dut : entity work.can_mac_ser_tx
    port map (
      clk_i        => clk,
      rst_i        => reset,
      llc_i        => llc_i,
      llc_o        => llc_o,
      tx_mac_fsm_i => tx_mac_fsm_i,
      tx_mac_fsm_o => tx_mac_fsm_o
    );

  -- Main test process
  main_tb_p : process is

    variable v_test_data : std_logic_vector(7 downto 0);

  begin


    Message("TX MAC Serializer Testbench Started");
    Message("==========================================");

    -- Initial reset
    reset <= '1';
    WaitForClock(clk, 5);
    reset <= '0';
    WaitForClock(clk);

    -- =====================================================================
    -- Test 1: Config byte loading (2 bytes with SOP)
    -- =====================================================================
    Message("");
    Message("Test 1: Load two config bytes when MAC FSM is idle");
    Message("-----------");

    tx_mac_fsm_i.transfer_status  <= c_ongoing;
    WaitForClock(clk);

    AlertIf(llc_o.avalon_st_sink.ready = '0', "ERROR: ready should be asserted in idle state", FAILURE);

    -- Send config byte 0 with SOP
    llc_i.avalon_st_source.data  <= x"C8";
    llc_i.avalon_st_source.valid <= '1';
    llc_i.avalon_st_source.startofpacket   <= '1';
    llc_i.avalon_st_source.endofpacket   <= '0';
    WaitForClock(clk);

    llc_i.avalon_st_source.valid <= '0';
    WaitForClock(clk);

    Message("  Config byte 0 loaded: x""C8""");

    AlertIf(llc_o.avalon_st_sink.ready = '0', "ERROR: ready should be asserted waiting for config byte 1", FAILURE);

    -- Send config byte 1
    llc_i.avalon_st_source.data  <= x"50";
    llc_i.avalon_st_source.valid <= '1';
    llc_i.avalon_st_source.startofpacket   <= '0';
    llc_i.avalon_st_source.endofpacket   <= '0';
    WaitForClock(clk);

    llc_i.avalon_st_source.valid <= '0';
    WaitForClock(clk);

    Message("  Config byte 1 loaded: x""50""");

    -- Verify frame_params extraction
    -- Byte 0: x"C8" = 11001000 -> FORMAT[7:5]=110(FE), FTYP[4]=0, ESI[3]=1, BRS[2]=0
    -- Byte 1: x"50" = 01010000 -> DLC[7:4]=0101=5
    Message("  Verifying frame_params extraction:");
    AlertIf(tx_mac_fsm_o.frame_params.format /= c_llc_fmt_fe, "ERROR: FORMAT should be FE (110)", FAILURE);
    AlertIf(tx_mac_fsm_o.frame_params.is_remote_frame /= '0', "ERROR: is_remote_frame should be 0", FAILURE);
    AlertIf(tx_mac_fsm_o.frame_params.esi_enable /= '1', "ERROR: ESI should be 1", FAILURE);
    AlertIf(tx_mac_fsm_o.frame_params.has_brs /= '0', "ERROR: BRS should be 0", FAILURE);
    AlertIf(to_integer(unsigned(tx_mac_fsm_o.frame_params.dlc_vector)) /= 5, "ERROR: DLC should be 5", FAILURE);
    Message("    FORMAT: FE [PASS]");
    Message("    FTYP: data_frame [PASS]");
    Message("    ESI: 1 [PASS]");
    Message("    BRS: 0 [PASS]");
    Message("    DLC: 5 [PASS]");
    Message("PASS: Both config bytes loaded successfully");

    -- =====================================================================
    -- Test 2: First data byte loading and bit shifting
    -- =====================================================================
    Message("");
    Message("Test 2: Data byte loading and bit shifting (8 bits)");
    Message("-----------");

    v_test_data := x"F0";

    AlertIf(llc_o.avalon_st_sink.ready = '0', "ERROR: ready should be asserted in load_llc_frame_byte state", FAILURE);

    llc_i.avalon_st_source.data  <= v_test_data;
    llc_i.avalon_st_source.valid <= '1';
    llc_i.avalon_st_source.startofpacket   <= '0';
    llc_i.avalon_st_source.endofpacket   <= '0';
    WaitForClock(clk);
    llc_i.avalon_st_source.valid <= '0';
    WaitForClock(clk);
    AlertIf(tx_mac_fsm_o.valid = '0', "ERROR: frame_bit_valid should be asserted", FAILURE);
    AlertIf(tx_mac_fsm_o.data /= v_test_data(7), "ERROR: first bit should be " & to_string(v_test_data(7)) &
            " but got " & to_string(tx_mac_fsm_o.data), FAILURE);
    Message("  Bit 0: " & to_string(tx_mac_fsm_o.data) & " (Expected: " & to_string(v_test_data(7)) & ")");

    for i in 6 downto 0 loop
      tx_mac_fsm_i.ready <= '1';
      WaitForClock(clk);
      tx_mac_fsm_i.ready <= '0';
      WaitForClock(clk);
      AlertIf(tx_mac_fsm_o.valid = '0', "ERROR: bit " & to_string(i) & " not valid", FAILURE);
      AlertIf(tx_mac_fsm_o.data /= v_test_data(i), "ERROR: bit " & to_string(i) & " mismatch", FAILURE);
      Message("  Bit " & to_string(7 - i) & ": " & to_string(tx_mac_fsm_o.data) & " (Expected: " & to_string(v_test_data(i)) & ")");
    end loop;

    Message("PASS: All 8 bits shifted correctly");

    -- =====================================================================
    -- Test 3: Multiple data bytes
    -- =====================================================================
    Message("");
    Message("Test 3: Multiple data bytes transmission");
    Message("-----------");

    reset <= '1';
    WaitForClock(clk);
    reset <= '0';
    WaitForClock(clk);

    tx_mac_fsm_i.transfer_status  <= c_ongoing;

    llc_i.avalon_st_source.data  <= x"C0";
    llc_i.avalon_st_source.valid <= '1';
    llc_i.avalon_st_source.startofpacket   <= '1';
    WaitForClock(clk);

    llc_i.avalon_st_source.data  <= x"30";
    llc_i.avalon_st_source.startofpacket   <= '0';
    llc_i.avalon_st_source.endofpacket   <= '0';
    WaitForClock(clk);
    llc_i.avalon_st_source.valid <= '0';
    WaitForClock(clk);
     WaitForClock(clk);

    -- Byte 0: x"C0" = 11000000 -> FORMAT[7:5]=110(FE), FTYP[4]=0, ESI[3]=0, BRS[2]=0
    -- Byte 1: x"30" = 00110000 -> DLC[7:4]=0011=3
    Message("  Verifying frame_info extraction:");
    AlertIf(tx_mac_fsm_o.frame_params.format /= c_llc_fmt_fe, "ERROR: FORMAT should be FE (110)", FAILURE);
    AlertIf(tx_mac_fsm_o.frame_params.is_remote_frame /= '0', "ERROR: FTYP should be 0", FAILURE);
    AlertIf(tx_mac_fsm_o.frame_params.esi_enable /= '0', "ERROR: ESI should be 0", FAILURE);
    AlertIf(tx_mac_fsm_o.frame_params.has_brs /= '0', "ERROR: BRS should be 0", FAILURE);
    AlertIf(to_integer(unsigned(tx_mac_fsm_o.frame_params.dlc_vector)) /= 3, "ERROR: DLC should be 3", FAILURE);
    Message("    FORMAT: FE [PASS]");
    Message("    FTYP: data_frame [PASS]");
    Message("    ESI: 0 [PASS]");
    Message("    BRS: 0 [PASS]");
    Message("    DLC: 3 [PASS]");

    for byte_idx in 0 to 2 loop
      v_test_data                    := std_logic_vector(to_unsigned(byte_idx * 16 + 1, 8));
      llc_i.avalon_st_source.data  <= v_test_data;
      llc_i.avalon_st_source.valid <= '1';

      if (byte_idx = 2) then
        llc_i.avalon_st_source.endofpacket <= '1';
      end if;

      WaitForClock(clk);
      llc_i.avalon_st_source.valid <= '0';
      WaitForClock(clk);

      Message("  Byte " & to_string(byte_idx) & ": " & to_hex_string(v_test_data));

      AlertIf(tx_mac_fsm_o.valid = '0', "ERROR: First bit not valid for byte " & to_string(byte_idx), FAILURE);
      AlertIf(tx_mac_fsm_o.data /= v_test_data(7), "ERROR: First bit (MSB) mismatch for byte " & to_string(byte_idx), FAILURE);

      for bit_idx in 6 downto 0 loop
        tx_mac_fsm_i.ready <= '1';
        WaitForClock(clk);
        tx_mac_fsm_i.ready <= '0';
        WaitForClock(clk);
        WaitForClock(clk);
        AlertIf(tx_mac_fsm_o.valid = '0', "ERROR: Bit not valid for byte " & to_string(byte_idx) & " bit " & to_string(bit_idx), FAILURE);
        AlertIf(tx_mac_fsm_o.data /= v_test_data(bit_idx),
                "ERROR: Bit mismatch for byte " & to_string(byte_idx) & " bit " & to_string(bit_idx) &
                " (expected " & to_string(v_test_data(bit_idx)) & " got " & to_string(tx_mac_fsm_o.data) & ")", FAILURE);
      end loop;

      tx_mac_fsm_i.ready <= '1';
      WaitForClock(clk);
      tx_mac_fsm_i.ready <= '0';
      WaitForClock(clk);

    end loop;

    Message("PASS: Multiple bytes transmitted successfully");

    -- =====================================================================
    -- Test 4: Frame termination (transfer status changes)
    -- =====================================================================
    Message("");
    Message("Test 4: Frame termination on transfer_status change");
    Message("-----------");

    reset <= '1';
    WaitForClock(clk);
    reset <= '0';
    WaitForClock(clk);

    tx_mac_fsm_i.transfer_status  <= c_ongoing;

    llc_i.avalon_st_source.data  <= x"5F";
    llc_i.avalon_st_source.valid <= '1';
    llc_i.avalon_st_source.startofpacket   <= '1';
    WaitForClock(clk);

    llc_i.avalon_st_source.data  <= x"F0";
    llc_i.avalon_st_source.startofpacket   <= '0';
    WaitForClock(clk);
    llc_i.avalon_st_source.valid <= '0';
    WaitForClock(clk);

    -- Byte 0: x"5F" = 01011111 -> FORMAT[7:5]=010 (FB), FTYP[4]=1, ESI[3]=1, BRS[2]=1
    -- Byte 1: x"F0" = 11110000 -> DLC[7:4]=1111=15
    Print("  Verifying frame_info extraction:");
    AlertIf(tx_mac_fsm_o.frame_params.format /= c_llc_fmt_fb, "ERROR: FORMAT should be FB (010) but got " & to_hex_string(tx_mac_fsm_o.frame_params.format), FAILURE);
    AlertIf(tx_mac_fsm_o.frame_params.is_remote_frame /= '1', "ERROR: FTYP should be 1", FAILURE);
    AlertIf(tx_mac_fsm_o.frame_params.esi_enable /= '1', "ERROR: ESI should be 1", FAILURE);
    AlertIf(tx_mac_fsm_o.frame_params.has_brs /= '1', "ERROR: BRS should be 1", FAILURE);
    AlertIf(to_integer(unsigned(tx_mac_fsm_o.frame_params.dlc_vector)) /= 15, "ERROR: DLC should be 15", FAILURE);
    Message("    FORMAT: FB [PASS]");
    Message("    FTYP: remote_frame [PASS]");
    Message("    ESI: 1 [PASS]");
    Message("    BRS: 1 [PASS]");
    Message("    DLC: 15 [PASS]");

    llc_i.avalon_st_source.data  <= x"33";
    llc_i.avalon_st_source.valid <= '1';
    WaitForClock(clk);
    llc_i.avalon_st_source.valid <= '0';
    WaitForClock(clk);

    tx_mac_fsm_i.ready <= '1';
    WaitForClock(clk,3);

    Message("  Changing transfer_status to transmitted mid-transmission...");
    tx_mac_fsm_i.transfer_status <= c_transmitted;
    WaitForClock(clk);
    WaitForClock(clk);

    AlertIf(tx_mac_fsm_o.valid = '1', "ERROR: bit_valid should be deasserted after status change", FAILURE);
    Message("PASS: Frame terminated correctly on status change");

    -- =====================================================================
    -- Test 5: Ready/Valid handshaking
    -- =====================================================================
    Message("");
    Message("Test 5: Ready/Valid handshaking");
    Message("-----------");

    reset <= '1';
    WaitForClock(clk);
    reset <= '0';
    WaitForClock(clk);

    tx_mac_fsm_i.transfer_status  <= c_ongoing;
    WaitForClock(clk);

    AlertIf(llc_o.avalon_st_sink.ready = '0', "ERROR: ready should be asserted in idle state", FAILURE);
    Message("  Idle state ready asserted: PASS");

    llc_i.avalon_st_source.data  <= x"BB";
    llc_i.avalon_st_source.valid <= '1';
    llc_i.avalon_st_source.startofpacket   <= '1';
    WaitForClock(clk);

    llc_i.avalon_st_source.valid <= '0';
    WaitForClock(clk);

    AlertIf(llc_o.avalon_st_sink.ready = '0', "ERROR: ready should be asserted in load_config_byte_1 state", FAILURE);
    Message("  Config byte 1 state ready asserted: PASS");

    llc_i.avalon_st_source.data  <= x"44";
    llc_i.avalon_st_source.valid <= '1';
    llc_i.avalon_st_source.startofpacket   <= '0';
    llc_i.avalon_st_source.endofpacket   <= '0';
    WaitForClock(clk);

    llc_i.avalon_st_source.valid <= '0';
    WaitForClock(clk);

    AlertIf(llc_o.avalon_st_sink.ready = '0', "ERROR: ready should be asserted in load_llc_frame_byte state", FAILURE);
    Message("  Data state ready asserted: PASS");

    Message("PASS: Ready/Valid handshaking correct");

    -- -----------------------------------------------------------------------
    -- Done
    -- -----------------------------------------------------------------------
    reset <= '1';
    WaitForClock(clk, 5);
    ReportNonZeroAlerts;
    Message("");
    Message("==========================================");
    Message("All tests completed successfully!");
    Message("==========================================");
    EndOfTestReports(ReportAll => TRUE);
    std.env.finish;

    wait;

  end process main_tb_p;

end architecture tb;

