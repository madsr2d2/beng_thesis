library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library osvvm;
context osvvm.OsvvmContext;

entity bit_stuffer_fd_tb is
end entity bit_stuffer_fd_tb;

architecture tb of bit_stuffer_fd_tb is

  constant CLK_PERIOD : time := 10 ns;
  constant RUN_TIME : time := 100 us;

  signal clk_i   : std_logic := '0';
  signal rst_i   : std_logic := '1';
  signal valid_i : std_logic := '0';
  signal data_i  : std_logic := '0';
  signal stuff_bit_o  : std_logic;
  signal stuff_bit_valid_o : std_logic;
  signal bsc_and_parity_o : std_logic_vector(3 downto 0);

begin

  -- Clock generation
  clk_i <= not clk_i after CLK_PERIOD / 2;

  -- DUT instantiation
  u_dut : entity work.bit_stuffer_fd
    port map (
      clk   => clk_i,
      rst   => rst_i,
      data_i  => data_i,
      valid_i => valid_i,
      stuff_bit_o  => stuff_bit_o,
      stuff_bit_valid_o => stuff_bit_valid_o,
      bsc_and_parity_o => bsc_and_parity_o
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

    -- Initialize random generators with different seeds
    rnd_bit.InitSeed(rnd_bit'instance_name & to_string(now));
    rnd_valid.InitSeed(rnd_valid'instance_name & to_string(now));

    -- Reset for a few cycles
    Print("Applying reset...");
    rst_i <= '1';
    valid_i <= '0';
    data_i <= '0';
    wait for CLK_PERIOD * 5;

    -- Release reset
    rst_i <= '0';
    wait for CLK_PERIOD;
    Print("Reset released");

    -- Random bit pattern with random valid signal
    Print("Sending random bit pattern with variable valid timing...");
    for i in 0 to num_bits loop
      random_bit := '0' when rnd_bit.RandInt(0, 1) = 0 else '1';
      random_valid := rnd_valid.RandInt(0, 1) = 0;  -- ~50% chance of valid

      data_i <= random_bit;
      valid_i <= '1' when random_valid else '0';
      wait for CLK_PERIOD;
    end loop;

    -- Random burst of valid data
    Print("Sending random burst...");
    for i in 0 to num_bits loop
      random_bit := '0' when rnd_bit.RandInt(0, 1) = 0 else '1';
      data_i <= random_bit;
      valid_i <= '1';
      wait for CLK_PERIOD;
    end loop;

    -- Stop and wait for cleanup
    Print("Test complete, waiting for outputs to settle...");
    valid_i <= '0';
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
      if stuff_bit_valid_o = '1' then
        output_count := output_count + 1;
        Print("Output #" & to_string(output_count) & ": " & to_string(stuff_bit_o) &
              " Gray+Parity=" & to_hstring(bsc_and_parity_o) &
              " at time " & to_string(now));
      end if;
    end if;
  end process monitor_p;

end architecture tb;
