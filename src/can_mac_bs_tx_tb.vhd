--------------------------------------------------------------------------------
-- Title      : CAN FD Bit Stuffer Testbench
-- Project    : Implementation and Verification of a CAN-FD Bus Transceiver
--              in VHDL
--------------------------------------------------------------------------------
-- File       : can_mac_bs_tx_tb.vhd
-- Author     : Mads Richardt
-- Standard   : VHDL-2008
--------------------------------------------------------------------------------
-- Description: OSVVM-based random stimulus testbench for can_mac_bs_tx.
--              Random stimulus exercises bit counting, stuff bit insertion,
--              and SBC encoding. PSL assertions verify reset behavior and
--              stuff bit sufficiency conditions.
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

  constant c_clk_period : time    := 10 ns;
  constant c_num_random : integer := 1000;

  signal clk_i   : std_logic;
  signal rst_i   : std_logic := '1';
  signal bs_fd_i : can_mac_fsm_bs_tx_if_m2s_t;
  signal bs_fd_o : can_mac_fsm_bs_tx_if_s2m_t;

begin

  CreateClock(clk_i, c_clk_period);
  CreateReset(rst_i, '1', clk_i, c_clk_period * 3);

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

    wait until rst_i = '0';
    WaitForClock(clk_i);

    -- Random stimulus with stuff bit feedback and occasional start pulses
    for i in 0 to c_num_random loop

      -- Occasional start pulse
      if (rnd.DistBool((false => 95, true => 5))) then
        bs_fd_i.start <= true;
        bs_fd_i.valid <= false;
        WaitForClock(clk_i);
        bs_fd_i.start <= false;
        WaitForClock(clk_i);
      end if;

      -- Random valid/data
      bs_fd_i.data  <= dominant when rnd.DistBool((false => 50, true => 50)) else recessive;
      bs_fd_i.valid <= rnd.DistBool((false => 25, true => 75));
      WaitForClock(clk_i);

      -- Feed stuff bit back when asserted
      if (bs_fd_o.valid) then
        bs_fd_i.data  <= bs_fd_o.data;
        bs_fd_i.valid <= true;
        WaitForClock(clk_i);
      end if;

    end loop;

    bs_fd_i.valid <= false;
    WaitForClock(clk_i, 5);
    std.env.finish;

  end process main_tb_p;

--------------------------------------------------------------
-- PSL assertions
--------------------------------------------------------------
-- psl default clock is rising_edge(clk_i);
--------------------------------------------------------------
-- psl psl_1 : assert always
-- { rst_i = '1' or bs_fd_i.start }
-- |=>
-- { not bs_fd_o.valid and
-- bs_fd_o.data = recessive and
-- bs_fd_o.sbc = "0000" }
-- report "Reset did not clear outputs to default values";
--------------------------------------------------------------
-- psl psl_2 : assert always
-- { bs_fd_i.valid and bs_fd_i.data = recessive ;
-- ( bs_fd_i.valid and bs_fd_i.data = dominant )[*5] }
-- |=>
-- { bs_fd_o.valid and bs_fd_o.data = recessive }
-- report "No stuff bit after 5 consecutive dominant bits";
--------------------------------------------------------------
-- psl psl_3 : assert always
-- { bs_fd_i.valid and bs_fd_i.data = dominant ;
-- ( bs_fd_i.valid and bs_fd_i.data = recessive )[*5] }
-- |=>
-- { bs_fd_o.valid and bs_fd_o.data = dominant }
-- report "No stuff bit after 5 consecutive recessive bits";
--------------------------------------------------------------

end architecture tb;
