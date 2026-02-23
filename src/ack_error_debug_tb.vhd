--------------------------------------------------------------------------------
-- Title      : ACK Error Debug Testbench
-- Project    : CAN Bus Transmitter
--------------------------------------------------------------------------------
-- File       : ack_error_debug_tb.vhd
-- Standard   : VHDL-2008
--------------------------------------------------------------------------------
-- Description: Diagnostic testbench to verify ACK error detection is working
-- and understand why debug signal may not be visible in waveforms
--------------------------------------------------------------------------------

library ieee;
  use ieee.std_logic_1164.all;
  use ieee.numeric_std.all;

  use work.can_types_pkg.all;
  use work.can_protocol_pkg.all;
  use work.can_timing_pkg.all;

library osvvm;
  use osvvm.AlertLogPkg.all;

entity ack_error_debug_tb is
end entity ack_error_debug_tb;

architecture testbench of ack_error_debug_tb is

  constant clk_period : time := 10 ns;

  -- Clock and reset
  signal clk : std_logic := '0';
  signal rst : std_logic := '1';

  -- LLC user interface
  signal llc_user_i : llc_user_to_llc_if_t;
  signal llc_user_o : llc_to_llc_user_if_t;

  -- Fault Confinement Entity
  signal fce_i : fce_to_mac_if_t;
  signal fce_o : mac_to_fce_if_t;

  -- Physical bus
  signal tx_bus : std_logic;
  signal rx_bus : std_logic := '1';  -- Recessive (open drain)

  -- Debug interface
  signal debug_mac_to_pcs : mac_to_pcs_if_t;
  signal debug_pcs_to_mac : pcs_to_mac_if_t;
  signal debug_ack_error : boolean;
  signal debug_strobe_type : strobe_type_t;

  -- Test state
  signal ack_error_count : integer := 0;
  signal sample_count : integer := 0;
  signal in_ack_slot : boolean := false;
  signal ack_slot_start_cycle : integer := 0;

begin

  -- Instantiate DUT
  dut : entity work.tx_can
    port map (
      clk                => clk,
      rst                => rst,
      llc_user_i         => llc_user_i,
      llc_user_o         => llc_user_o,
      fce_i              => fce_i,
      fce_o              => fce_o,
      tx_bus_o           => tx_bus,
      rx_bus_i           => rx_bus,
      debug_mac_to_pcs_o => debug_mac_to_pcs,
      debug_pcs_to_mac_o => debug_pcs_to_mac,
      debug_strobe_type_o => debug_strobe_type,
      debug_ack_error_o  => debug_ack_error,
      others             => open
    );

  -- Clock generation
  clk <= not clk after clk_period / 2;

  -- Main test process
  test_proc : process
  begin

    log("=== ACK Error Debug Testbench ===", ALWAYS);
    log("Purpose: Verify ACK error detection logic and debug signal visibility", ALWAYS);
    log("", ALWAYS);

    -- Reset
    rst <= '1';
    wait for 20 * clk_period;
    rst <= '0';
    wait for 20 * clk_period;

    fce_i.error_passive <= false;
    llc_user_i.avalon_st_source.valid <= '0';
    rx_bus <= '1';  -- Keep bus recessive (no ACKs from receivers)

    log("TEST: Send CC Basic frame with recessive rx_bus (should trigger ACK error)", ALWAYS);
    log("", ALWAYS);

    -- Send config byte 0: CC Basic format
    llc_user_i.avalon_st_source.data(7 downto 0) <= x"00";  -- Format: CC Basic
    llc_user_i.avalon_st_source.data(15 downto 8) <= x"08";  -- DLC: 8 bytes
    llc_user_i.avalon_st_source.sop <= '1';
    llc_user_i.avalon_st_source.valid <= '1';
    wait until rising_edge(clk);
    wait until llc_user_o.avalon_st_sink.ready = '1';

    -- Send one data byte
    llc_user_i.avalon_st_source.data <= x"AA";
    llc_user_i.avalon_st_source.sop <= '0';
    llc_user_i.avalon_st_source.eop <= '1';
    llc_user_i.avalon_st_source.valid <= '1';
    wait until rising_edge(clk);
    wait until llc_user_o.avalon_st_sink.ready = '1';

    llc_user_i.avalon_st_source.valid <= '0';

    -- Wait for frame transmission and error response
    log("Frame transmission started, monitoring for ACK error...", ALWAYS);
    wait for 100 us;

    log("", ALWAYS);
    log("DIAGNOSTIC RESULTS:", ALWAYS);
    log("  ACK error pulses detected: " & integer'image(ack_error_count), ALWAYS);
    if (ack_error_count > 0) then
      log("  Status: [PASS] ACK error signal was observed", ALWAYS);
    else
      log("  Status: [FAIL] ACK error signal never pulsed", ALWAYS);
      log("  ", ALWAYS);
      log("  Possible causes:", ALWAYS);
      log("    1. ACK error condition not met (ack_success_seen != false at delimiter)", ALWAYS);
      log("    2. Debug signal pulse only 1 cycle - check waveform at exact delimiter cycle", ALWAYS);
      log("    3. Debug signal wiring issue through layers", ALWAYS);
    end if;
    log("  Sample point count: " & integer'image(sample_count), ALWAYS);

    log("", ALWAYS);
    log("=== Test Complete ===", ALWAYS);
    wait;

  end process test_proc;

  -- Monitor ACK error signal
  ack_error_monitor : process (clk) is
  begin
    if rising_edge(clk) then
      if debug_ack_error then
        ack_error_count <= ack_error_count + 1;
        log("[ACK ERROR DETECTED] debug_ack_error_o pulsed at cycle " &
            integer'image(sample_count), ALWAYS);
        log("  bit_name: " & mac_frame_bit_name_t'image(debug_mac_to_pcs.data.bit_name), ALWAYS);
      end if;

      -- Track sample points
      if debug_pcs_to_mac.sample_strobe = '1' then
        sample_count <= sample_count + 1;

        -- Detect ACK slot
        if (debug_mac_to_pcs.data.bit_name = ack_bit) then
          if not in_ack_slot then
            in_ack_slot <= true;
            ack_slot_start_cycle <= sample_count;
            log("[FRAME] Entered ACK slot at sample " & integer'image(sample_count), ALWAYS);
          end if;
        elsif (debug_mac_to_pcs.data.bit_name = ack_delimiter_bit) then
          if in_ack_slot then
            in_ack_slot <= false;
            log("[FRAME] At ACK delimiter (sample " & integer'image(sample_count) &
                ") - duration: " & integer'image(sample_count - ack_slot_start_cycle) &
                " samples", ALWAYS);
          end if;
        end if;
      end if;
    end if;
  end process ack_error_monitor;

  -- Diagnostic: Report current state on each sample
  diagnostic_monitor : process (clk) is
    variable last_bit_name : mac_frame_bit_name_t := unknown;
  begin
    if rising_edge(clk) then
      if debug_pcs_to_mac.sample_strobe = '1' then
        if (debug_mac_to_pcs.data.bit_name /= last_bit_name) then
          log("  Sample " & integer'image(sample_count) & ": bit_name=" &
              mac_frame_bit_name_t'image(debug_mac_to_pcs.data.bit_name) &
              ", polarity=" & polarity_t'image(debug_mac_to_pcs.data.polarity) &
              ", bus=" & std_logic'image(debug_pcs_to_mac.bus_polarity) &
              ", ack_error=" & boolean'image(debug_ack_error), ALWAYS);
          last_bit_name := debug_mac_to_pcs.data.bit_name;
        end if;
      end if;
    end if;
  end process diagnostic_monitor;

end architecture testbench;
