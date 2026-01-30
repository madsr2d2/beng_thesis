library ieee;
  use ieee.std_logic_1164.all;
  use ieee.numeric_std.all;

entity shift_reg_with_empty_tb is
end entity shift_reg_with_empty_tb;

architecture sim of shift_reg_with_empty_tb is

  -- Constants
  constant width_c    : integer := 4; -- Use a smaller width for simulation
  constant clk_period : time    := 10 ns;

  -- Signals
  signal clk      : std_logic                              := '0';
  signal rst      : std_logic                              := '0';
  signal ctrl     : std_logic_vector(1 downto 0)           := "00";
  signal d        : std_logic_vector(width_c - 1 downto 0) := (others => '0');
  signal q        : std_logic_vector(width_c - 1 downto 0);
  signal max_tick : std_logic;

begin

  -- DUT Instantiation
  u_dut : entity work.shift_reg_with_empty
    generic map (
      width => width_c
    )
    port map (
      clk      => clk,
      rst      => rst,
      ctrl     => ctrl,
      d        => d,
      q        => q,
      max_tick => max_tick
    );

  -- Clock Process
  clk_proc : process is
  begin

    while true loop

      clk <= '0';
      wait for clk_period / 2;
      clk <= '1';
      wait for clk_period / 2;

    end loop;

  end process clk_proc;

  -- Stimulus Process
  stim_proc : process is
  begin

    report "Simulation Start";

    -- 1. Reset
    rst <= '1';
    wait for clk_period * 2;
    rst <= '0';
    wait for clk_period;

    -- 2. Load Data ("1011")
    report "Test Case 1: Load Data";
    d    <= "1011";
    ctrl <= "11";                                                        -- Load
    wait for clk_period;

    -- Check Output
    assert q = "1011"
      report "Error: Load failed. Expected 1011, got " & to_string(q)
      severity error;
    assert max_tick = '0'
      report "Error: max_tick high after load"
      severity error;

    -- 3. Shift Sequence (Left Shift, shifting in '0')
    report "Test Case 2: Shift Sequence";
    ctrl <= "01";                                                        -- Shift '0' in from right (Left Shift)
    d    <= (others => '0');                                             -- Clear d to ensure we aren't loading it

    -- Shift 1
    wait for clk_period;
    -- Expected: 1011 << 1 = 0110
    assert q = "0110"
      report "Error: Shift 1 failed. Expected 0110, got " & to_string(q)
      severity error;
    assert max_tick = '0'
      report "Error: max_tick high at shift 1"
      severity error;

    -- Shift 2
    wait for clk_period;
    -- Expected: 0110 << 1 = 1100
    assert q = "1100"
      report "Error: Shift 2 failed. Expected 1100, got " & to_string(q)
      severity error;
    assert max_tick = '0'
      report "Error: max_tick high at shift 2"
      severity error;

    -- Shift 3
    wait for clk_period;
    -- Expected: 1100 << 1 = 1000
    assert q = "1000"
      report "Error: Shift 3 failed. Expected 1000, got " & to_string(q)
      severity error;
    assert max_tick = '0'
      report "Error: max_tick high at shift 3"
      severity error;

    -- Shift 4 (Max Count)
    wait for clk_period;
    -- Expected: 1000 << 1 = 0000
    assert q = "0000"
      report "Error: Shift 4 failed. Expected 0000, got " & to_string(q)
      severity error;
    assert max_tick = '1'
      report "Error: max_tick failed to assert at max count (4 shifts)"
      severity error;

    -- Shift 5 (Wrap around)
    wait for clk_period;
    ctrl <= "00";                                                        -- Shift '0' in from right (Left Shift)
    assert max_tick = '0'
      report "Error: max_tick failed to clear after wrap"
      severity error;

    report "Simulation Finished Successfully";
    wait;

  end process stim_proc;

end architecture sim;
