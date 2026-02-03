library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library osvvm;
context osvvm.OsvvmContext;

use work.can_pkg.all;

entity bit_stuffer_fd_tb is
end entity bit_stuffer_fd_tb;

architecture tb of bit_stuffer_fd_tb is

  constant CLK_PERIOD : time := 10 ns;
  constant RUN_TIME : time := 100 us;

  signal clk_i : std_logic := '0';
  signal bs_fd_i : mac_fsm_to_bs_fd_if_t;
  signal bs_fd_o : bs_fd_to_mac_fsm_if_t;

  -- Signals for waveform viewing (unpacked from records)
  signal tb_clk : std_logic;
  signal tb_rst : std_logic;
  signal tb_data_i : std_logic;
  signal tb_data_valid : std_logic;
  signal tb_stuff_bit : std_logic;
  signal tb_stuff_bit_valid : std_logic;
  signal tb_sbc : std_logic_vector(3 downto 0);

begin

  -- Clock generation
  clk_i <= not clk_i after CLK_PERIOD / 2;
  bs_fd_i.clk <= clk_i;

  -- Unpack records to signals for waveform viewing
  tb_clk <= bs_fd_i.clk;
  tb_rst <= bs_fd_i.rst;
  tb_data_i <= bs_fd_i.data;
  tb_data_valid <= bs_fd_i.data_valid;
  tb_stuff_bit <= bs_fd_o.stuff_bit;
  tb_stuff_bit_valid <= bs_fd_o.stuff_bit_valid;
  tb_sbc <= bs_fd_o.sbc;

  -- DUT instantiation
  u_dut : entity work.bit_stuffer_fd
    port map (
      bs_fd_i => bs_fd_i,
      bs_fd_o => bs_fd_o
    );

  -- Main test process
  main_tb_p : process
    variable rnd_bit : RandomPType;
    variable rnd_valid : RandomPType;
    variable random_bit : std_logic;
    variable random_valid : boolean;
    variable num_bits : integer;
  begin
    -- Open transcript file for logging
    TranscriptOpen("sim/bit_stuffer_fd_tb.txt");
    SetTranscriptMirror(TRUE);

    Print("=== Bit Stuffer FD Testbench Started ===");

    -- Note: VCD waveform captures all signals automatically.
    -- View with: gtkwave sim/bit_stuffer_fd_tb.vcd
    -- Expand hierarchy to see record fields and internal signals

    -- Initialize random generators with different seeds
    rnd_bit.InitSeed(rnd_bit'instance_name & to_string(now));
    rnd_valid.InitSeed(rnd_valid'instance_name & to_string(now));

    -- Initialize test parameters
    num_bits := 300;  -- Number of bits to send in each test pattern

    -- Reset for a few cycles
    Print("Applying reset...");
    bs_fd_i.rst <= '1';
    bs_fd_i.data_valid <= '0';
    bs_fd_i.data <= '0';
    wait for CLK_PERIOD * 5;

    -- Release reset
    bs_fd_i.rst <= '0';
    wait for CLK_PERIOD;
    Print("Reset released");

    -- Test 1: Send known patterns that trigger bit stuffing (5 consecutive identical bits)
    Print("Sending pattern to trigger bit stuffing: 00000...");
    for i in 0 to 9 loop
      bs_fd_i.data <= '0';
      bs_fd_i.data_valid <= '1';
      wait for CLK_PERIOD;
    end loop;

    Print("Sending pattern: 11111...");
    for i in 0 to 9 loop
      bs_fd_i.data <= '1';
      bs_fd_i.data_valid <= '1';
      wait for CLK_PERIOD;
    end loop;

    -- Test 2: Random bit pattern with random valid signal
    Print("Sending random bit pattern with variable valid timing...");
    for i in 0 to num_bits loop
      random_bit := '0' when rnd_bit.RandInt(0, 1) = 0 else '1';
      random_valid := rnd_valid.RandInt(0, 1) = 0;  -- ~50% chance of valid

      bs_fd_i.data <= random_bit;
      bs_fd_i.data_valid <= '1' when random_valid else '0';
      wait for CLK_PERIOD;
    end loop;

    -- Random burst of valid data
    Print("Sending random burst...");
    for i in 0 to num_bits loop
      random_bit := '0' when rnd_bit.RandInt(0, 1) = 0 else '1';
      bs_fd_i.data <= random_bit;
      bs_fd_i.data_valid <= '1';
      wait for CLK_PERIOD;
    end loop;

    -- Stop and wait for cleanup
    Print("Test complete, waiting for outputs to settle...");
    bs_fd_i.data_valid <= '0';
    wait for CLK_PERIOD * 20;

    Print("=== Bit Stuffer FD Testbench Finished ===");
    TranscriptClose;

    std.env.finish;

  end process main_tb_p;

  -- Simple monitor - display stuff bits and Gray code with parity
  monitor_p : process (clk_i)
    variable output_count : integer := 0;
  begin
    if rising_edge(clk_i) then
      if bs_fd_o.stuff_bit_valid = '1' then
        output_count := output_count + 1;
        Print("Output #" & to_string(output_count) & ": " & to_string(bs_fd_o.stuff_bit) &
              " Gray+Parity=" & to_hstring(bs_fd_o.sbc) &
              " at time " & to_string(now));
      end if;
    end if;
  end process monitor_p;

end architecture tb;
