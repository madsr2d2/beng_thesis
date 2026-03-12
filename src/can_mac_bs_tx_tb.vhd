--------------------------------------------------------------------------------
-- Title      : CAN FD Bit Stuffer Testbench
-- Project    : Implementation and Verification of a CAN-FD Bus Transceiver
--              in VHDL
--------------------------------------------------------------------------------
-- File       : can_mac_bs_tx_tb.vhd
-- Author     : Mads Richardt
-- Standard   : VHDL-2008
--------------------------------------------------------------------------------
-- Description: Stimulus-only testbench for can_mac_bs_tx. Behavioral
--              correctness is verified by formal assertions embedded in the
--              DUT (see psl_1 through psl_7). This testbench exercises the
--              DUT with varied patterns so the assertions fire during
--              simulation (check results via --psl-report JSON output).
--------------------------------------------------------------------------------

library ieee;
  use ieee.std_logic_1164.all;
  use ieee.numeric_std.all;

library osvvm;
  context osvvm.OsvvmContext;

use work.can_types_pkg.all;

entity can_mac_bs_tx_tb is
end entity can_mac_bs_tx_tb;

architecture tb of can_mac_bs_tx_tb is

  constant clk_period_c : time    := 10 ns;
  constant num_random_c : integer := 300;

  signal clk_i   : std_logic := '0';
  signal rst_i   : std_logic := '0';
  signal bs_fd_i : can_mac_fsm_bs_tx_if_m2s_t;
  signal bs_fd_o : can_mac_fsm_bs_tx_if_s2m_t;

begin

  clk_i <= not clk_i after clk_period_c / 2;

  u_dut : entity work.can_mac_bs_tx
    port map (
      clk_i => clk_i,
      rst_i => rst_i,
      bs_i  => bs_fd_i,
      bs_o  => bs_fd_o
    );

  main_tb_p : process
    variable rnd : RandomPType;
  begin
    rnd.InitSeed(rnd'instance_name & to_string(now));

    -- Reset
    rst_i         <= '1';
    bs_fd_i.valid <= false;
    bs_fd_i.data  <= dominant;
    bs_fd_i.start <= false;
    wait for clk_period_c * 5;
    rst_i <= '0';
    wait for clk_period_c;

    -- Pattern 1: 5 dominant bits (triggers stuff bit)
    for i in 0 to 4 loop
      bs_fd_i.data  <= dominant;
      bs_fd_i.valid <= true;
      wait for clk_period_c;
    end loop;
    -- Feed stuff bit back
    bs_fd_i.data  <= bs_fd_o.data;
    bs_fd_i.valid <= true;
    wait for clk_period_c;
    bs_fd_i.valid <= false;
    wait for clk_period_c;

    -- Pattern 2: Frame reset
    bs_fd_i.start <= true;
    wait for clk_period_c;
    bs_fd_i.start <= false;
    wait for clk_period_c;

    -- Pattern 3: Alternating bits (no stuffing expected)
    for i in 0 to 19 loop
      bs_fd_i.data  <= dominant when i mod 2 = 0 else recessive;
      bs_fd_i.valid <= true;
      wait for clk_period_c;
    end loop;
    bs_fd_i.valid <= false;
    wait for clk_period_c;

    -- Pattern 4: Random patterns with stuff bit feedback
    bs_fd_i.start <= true;
    wait for clk_period_c;
    bs_fd_i.start <= false;
    wait for clk_period_c;

    for i in 0 to num_random_c loop
      bs_fd_i.data  <= dominant when rnd.RandInt(0, 1) = 0 else recessive;
      bs_fd_i.valid <= rnd.RandInt(0, 1) = 0;
      wait for clk_period_c;

      if bs_fd_o.valid then
        bs_fd_i.data  <= bs_fd_o.data;
        bs_fd_i.valid <= true;
        wait for clk_period_c;
      end if;
    end loop;

    -- Pattern 5: Continuous dominant burst (multiple stuff events)
    bs_fd_i.start <= true;
    wait for clk_period_c;
    bs_fd_i.start <= false;
    wait for clk_period_c;

    for i in 0 to 29 loop
      if bs_fd_o.valid then
        bs_fd_i.data  <= bs_fd_o.data;
        bs_fd_i.valid <= true;
        wait for clk_period_c;
      end if;
      bs_fd_i.data  <= dominant;
      bs_fd_i.valid <= true;
      wait for clk_period_c;
    end loop;
    bs_fd_i.valid <= false;

    wait for clk_period_c * 10;
    std.env.finish;

  end process main_tb_p;

end architecture tb;
