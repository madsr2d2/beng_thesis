library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library osvvm;
context osvvm.OsvvmContext;

use work.can_types_pkg.all;
  use work.can_protocol_pkg.all;
  use work.can_timing_pkg.all;

entity can_mac_bs_tx_tb is
end entity can_mac_bs_tx_tb;

architecture tb of can_mac_bs_tx_tb is

  constant clk_period_c : time := 10 ns;

  signal clk_i : std_logic := '0';
  signal rst_i : std_logic := '0';
  signal bs_fd_i : can_mac_fsm_bs_tx_if_s2d_t;
  signal bs_fd_o : can_mac_fsm_bs_tx_if_d2s_t;

  -- Signals for waveform viewing (unpacked from records)
  signal tb_clk             : std_logic;
  signal tb_rst             : std_logic;
  signal tb_data_i          : polarity_t;
  signal tb_data_valid      : std_logic;
  signal tb_stuff_bit       : polarity_t;
  signal tb_stuff_bit_valid : std_logic;
  signal tb_sbc             : std_logic_vector(3 downto 0);

begin

  -- Clock generation
  clk_i <= not clk_i after clk_period_c / 2;

  -- Unpack records to signals for waveform viewing
  tb_clk             <= clk_i;
  tb_rst             <= rst_i;
  tb_data_i          <= bs_fd_i.data;
  tb_data_valid      <= '1' when bs_fd_i.valid else '0';
  tb_stuff_bit       <= bs_fd_o.data;
  tb_stuff_bit_valid <= '1' when bs_fd_o.valid else '0';
  tb_sbc             <= bs_fd_o.sbc;

  -- DUT instantiation
  u_dut : entity work.can_mac_bs_tx
    port map (
      clk_i   => clk_i,
      rst_i     => rst_i,
      bs_fd_i => bs_fd_i,
      bs_fd_o => bs_fd_o
    );

  -- Main test process
  main_tb_p : process
    variable rnd_bit   : RandomPType;
    variable rnd_valid : RandomPType;
    variable random_polarity : polarity_t;
    variable random_valid    : boolean;
    variable num_bits        : integer;
  begin
    -- Open transcript file for logging
    TranscriptOpen("sim/can_mac_bs_tx_tb.txt");
    SetTranscriptMirror(TRUE);

    Print("=== Bit Stuffer FD Testbench Started ===");

    -- Initialize random generators with different seeds
    rnd_bit.InitSeed(rnd_bit'instance_name & to_string(now));
    rnd_valid.InitSeed(rnd_valid'instance_name & to_string(now));

    num_bits := 300;

    -- Reset for a few cycles
    Print("Applying reset...");
    rst_i <= '1';
    bs_fd_i.valid       <= false;
    bs_fd_i.data        <= dominant;
    bs_fd_i.start       <= false;
    wait for clk_period_c * 5;

    -- Release reset
    rst_i <= '0';
    wait for clk_period_c;
    Print("Reset released");

    -- Test 1: Send 5 dominant bits → stuff_bit_valid should go high
    Print("Test 1: 5 dominant bits triggers stuff bit...");
    for i in 0 to 4 loop
      bs_fd_i.data       <= dominant;
      bs_fd_i.valid      <= true;
      wait for clk_period_c;
    end loop;
    bs_fd_i.valid <= false;
    wait for clk_period_c;
    AffirmIf(bs_fd_o.valid = true, "stuff_bit_valid should be true after 5 dominant");
    AffirmIf(bs_fd_o.data = recessive, "stuff_bit should be recessive after 5 dominant");

    -- Feed the stuff bit back (as FSM would)
    bs_fd_i.data       <= bs_fd_o.data;
    bs_fd_i.valid      <= true;
    wait for clk_period_c;
    bs_fd_i.valid      <= false;
    wait for clk_period_c;
    AffirmIf(bs_fd_o.valid = false, "stuff_bit_valid should clear after stuff bit consumed");
    Print("  PASS: Stuff bit detection and consumption works");

    -- Test 2: Verify SBC incremented after stuff bit
    Print("Test 2: SBC counts stuff bits...");
    AffirmIf(bs_fd_o.sbc /= "0000", "SBC should be non-zero after 1 stuff bit");
    Print("  SBC after 1 stuff bit: " & to_hstring(bs_fd_o.sbc));

    -- Test 3: Frame reset clears everything
    Print("Test 3: Frame reset clears SBC...");
    bs_fd_i.start <= true;
    wait for clk_period_c;
    bs_fd_i.start <= false;
    wait for clk_period_c;
    AffirmIfEqual(bs_fd_o.sbc, "0000", "SBC should be zero after frame reset");
    AffirmIf(bs_fd_o.valid = false, "stuff_bit_valid should be false after reset");
    Print("  PASS: Frame reset clears SBC and stuff state");

    -- Test 4: Alternating bits should not trigger stuffing
    Print("Test 4: Alternating bits (no stuffing)...");
    for i in 0 to 19 loop
      if (i mod 2 = 0) then
        bs_fd_i.data <= dominant;
      else
        bs_fd_i.data <= recessive;
      end if;
      bs_fd_i.valid <= true;
      wait for clk_period_c;
      AffirmIf(bs_fd_o.valid = false, "No stuffing for alternating bits at i=" & to_string(i));
    end loop;
    bs_fd_i.valid <= false;
    Print("  PASS: Alternating bits produce no stuff bits");

    -- Test 5: Multiple stuff events with random patterns
    Print("Test 5: Random bit patterns...");
    bs_fd_i.start <= true;
    wait for clk_period_c;
    bs_fd_i.start <= false;
    wait for clk_period_c;

    for i in 0 to num_bits loop
      random_polarity := dominant when rnd_bit.RandInt(0, 1) = 0 else recessive;
      random_valid    := rnd_valid.RandInt(0, 1) = 0;

      bs_fd_i.data       <= random_polarity;
      bs_fd_i.valid      <= random_valid;
      wait for clk_period_c;

      -- If stuff bit detected, feed it back
      if (bs_fd_o.valid) then
        bs_fd_i.data       <= bs_fd_o.data;
        bs_fd_i.valid      <= true;
        wait for clk_period_c;
      end if;
    end loop;

    -- Test 6: Continuous burst of same polarity
    Print("Test 6: Continuous dominant burst...");
    bs_fd_i.start <= true;
    wait for clk_period_c;
    bs_fd_i.start <= false;
    wait for clk_period_c;

    for i in 0 to 29 loop
      if (bs_fd_o.valid) then
        -- Feed stuff bit
        bs_fd_i.data       <= bs_fd_o.data;
        bs_fd_i.valid      <= true;
        wait for clk_period_c;
      end if;
      bs_fd_i.data       <= dominant;
      bs_fd_i.valid      <= true;
      wait for clk_period_c;
    end loop;
    bs_fd_i.valid <= false;

    -- Stop and wait for cleanup
    Print("Test complete, waiting for outputs to settle...");
    wait for clk_period_c * 20;

    Print("=== Bit Stuffer FD Testbench Finished ===");
    TranscriptClose;

    std.env.finish;

  end process main_tb_p;

  -- Monitor process: display stuff bits and SBC
  monitor_p : process (clk_i)
    variable output_count : integer := 0;
  begin
    if rising_edge(clk_i) then
      if bs_fd_o.valid and bs_fd_i.valid then
        output_count := output_count + 1;
        Print("Stuff #" & to_string(output_count) &
              ": " & polarity_t'image(bs_fd_o.data) &
              " SBC=" & to_hstring(bs_fd_o.sbc) &
              " at " & to_string(now));
      end if;
    end if;
  end process monitor_p;

end architecture tb;
