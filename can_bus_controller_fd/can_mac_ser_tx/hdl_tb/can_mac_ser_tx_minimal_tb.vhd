--------------------------------------------------------------------------------------------------------------------------------------------------------------
-- Copyright 2026 Everllence, Teglholmsgade 41, 2450 Copenhagen SV, Denmark
--------------------------------------------------------------------------------------------------------------------------------------------------------------
--
-- Requirements:
--
-- Description:   Minimal testbench to isolate the random-ready deadlock bug.
--                Sends a single basic CAN frame (config + ID bytes).
--
-- Revision log:  Date:       Initial:  JIRA:
--                2026-03-31  MRDSA     Converted to company header format
--------------------------------------------------------------------------------------------------------------------------------------------------------------

library ieee;
  use ieee.std_logic_1164.all;
  use ieee.numeric_std.all;

library osvvm;
  context osvvm.OsvvmContext;
  use osvvm.ScoreboardPkg_slv.all;
library osvvm_common;
  context osvvm_common.OsvvmCommonContext;

use work.pk_man_global.all;
use work.common_register_interface_pkg.all;
use work.common_tb_pkg.all;
use work.pk_can_types.all;

entity can_mac_ser_tx_minimal_tb is
  generic (
    gc_TbTimeOut   : time := 200 ms;
    gc_TbClkPeriod : time := 10 ns
  );
end entity can_mac_ser_tx_minimal_tb;

architecture tb of can_mac_ser_tx_minimal_tb is

  constant c_clk_period : time := gc_TbClkPeriod;

  signal clk   : std_logic;
  signal reset : std_logic := '1';

  signal llc_i        : t_can_llc_mac_tx_if_s2d;
  signal llc_o        : t_can_llc_mac_tx_if_d2s;
  signal tx_mac_fsm_i : t_can_mac_ser_fsm_if_d2s;
  signal tx_mac_fsm_o : t_can_mac_ser_fsm_if_s2d;

  signal test_id   : AlertLogIDType;
  shared variable RV : RandomPType;

  -- Frame: Basic CAN (11-bit ID)
  -- Byte 0 (config): FORMAT=CB(000), FTYP=0, ESI=0, BRS=0
  signal config_byte_0 :std_logic_vector(c_byte_width - 1 downto 0) := x"00";  -- [7:5]=000(CB), [4]=0(data frame), rest=0
  signal config_byte_1 :std_logic_vector(c_byte_width - 1 downto 0) := x"10";  -- [7:4]=0001(DLC=1 byte), rest=0
  signal id_bytes      : t_llc_frame := (x"55", x"55", x"00", x"00", others => x"00");  -- ID = 0x555 (11-bit)
  signal data_byte     :std_logic_vector(c_byte_width - 1 downto 0) := x"AA";  -- 1 data byte = 0xAA

  signal bit_count : natural := 0;
  signal byte_count : natural := 0;

begin

  CreateClock(clk, c_clk_period);
  CreateReset(reset, '1', clk, c_clk_period * 10);

  p_timeout : process is
  begin
    wait for gc_TbTimeOut;
    assert false report "ERROR: TEST TIMED OUT" severity error;
    std.env.stop(1);
  end process p_timeout;

  u_dut : entity work.can_mac_ser_tx
    port map (
      clk_i        => clk,
      rst_i        => reset,
      llc_i        => llc_i,
      llc_o        => llc_o,
      tx_mac_fsm_i => tx_mac_fsm_i,
      tx_mac_fsm_o => tx_mac_fsm_o
    );

  -- Random ready: 40% chance ready=1, 60% chance ready=0 each cycle
  p_random_ready : process is
  begin
    tx_mac_fsm_i.ready <= '0';
    wait until reset = '0';
    loop
      tx_mac_fsm_i.ready <= '1' when RV.DistBool((false => 60, true => 40)) else '0';
      WaitForClock(clk);
    end loop;
  end process p_random_ready;

  -- Stimulus: send 1 byte frame (config + ID + data)
  p_stimulus : process is
  begin
    wait until reset = '0';
    WaitForClock(clk, 5);

    Print("=== Minimal Test: Send Config Bytes ===");
    tx_mac_fsm_i.transfer_status <= c_ongoing;
    WaitForClock(clk);

    -- Byte 0: Config
    llc_i.avalon_st_source.valid         <= '1';
    llc_i.avalon_st_source.data          <= config_byte_0;
    llc_i.avalon_st_source.startofpacket <= '1';
    llc_i.avalon_st_source.endofpacket   <= '0';
    wait until (llc_o.avalon_st_sink.ready = '1') or (clk'event and clk = '1');
    WaitForClock(clk);
    llc_i.avalon_st_source.valid <= '0';

    Print("Config byte 0 sent, waiting for byte 1 handshake");
    wait until llc_o.avalon_st_sink.ready = '1';
    WaitForClock(clk);
    wait for 0 ns;

    -- Byte 1: Config
    llc_i.avalon_st_source.valid         <= '1';
    llc_i.avalon_st_source.data          <= config_byte_1;
    llc_i.avalon_st_source.startofpacket <= '0';
    llc_i.avalon_st_source.endofpacket   <= '0';
    wait until (llc_o.avalon_st_sink.ready = '1') or (clk'event and clk = '1');
    WaitForClock(clk);
    llc_i.avalon_st_source.valid <= '0';

    Print("Config byte 1 sent, metadata extracted. Now sending ID bytes");
    wait until llc_o.avalon_st_sink.ready = '1';
    WaitForClock(clk);

    -- ID bytes 0-3
    for i in 0 to 3 loop
      llc_i.avalon_st_source.valid         <= '1';
      llc_i.avalon_st_source.data          <= id_bytes(i);
      llc_i.avalon_st_source.startofpacket <= '0';
      llc_i.avalon_st_source.endofpacket   <= '0';
      wait until (llc_o.avalon_st_sink.ready = '1') or (clk'event and clk = '1');
      WaitForClock(clk);
      llc_i.avalon_st_source.valid <= '0';
      Print("ID byte " & to_string(i) & " sent");
      wait until llc_o.avalon_st_sink.ready = '1';
      WaitForClock(clk);
    end loop;

    -- Data byte
    llc_i.avalon_st_source.valid         <= '1';
    llc_i.avalon_st_source.data          <= data_byte;
    llc_i.avalon_st_source.startofpacket <= '0';
    llc_i.avalon_st_source.endofpacket   <= '1';
    wait until (llc_o.avalon_st_sink.ready = '1') or (clk'event and clk = '1');
    WaitForClock(clk);
    llc_i.avalon_st_source.valid <= '0';
    Print("Data byte sent");

    -- Wait for all bits to be consumed and mark transfer complete
    Print("Waiting for serializer to finish transmitting bits...");
    wait for 10 us;
    tx_mac_fsm_i.transfer_status <= c_transmitted;
    WaitForClock(clk, 5);

    Print("SUCCESS: Frame transmitted without deadlock");
    EndOfTestReports(ReportAll => TRUE);
    std.env.finish;

    wait;
  end process p_stimulus;

  -- Monitor: count bits and detect stalls
  p_monitor : process is
    variable v_last_bit : std_logic := '0';
    variable v_stall_count : natural := 0;
  begin
    wait until reset = '0';
    loop
      if (tx_mac_fsm_o.valid = '1' and tx_mac_fsm_i.ready = '1') then
        bit_count <= bit_count + 1;
        v_stall_count := 0;
        Print("BIT " & to_string(bit_count) & ": " & to_string(tx_mac_fsm_o.data) &
              " (ready=" & to_string(tx_mac_fsm_i.ready) & ")");
      elsif (tx_mac_fsm_o.valid = '1' and tx_mac_fsm_i.ready = '0') then
        v_stall_count := v_stall_count + 1;
        if (v_stall_count mod 1000 = 0) then
          Print("STALL: valid=1, ready=0 for " & to_string(v_stall_count) & " cycles");
        end if;
      end if;
      WaitForClock(clk);
    end loop;
  end process p_monitor;

end architecture tb;

-- eof
