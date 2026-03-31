--------------------------------------------------------------------------------------------------------------------------------------------------------------
-- Copyright 2025 Everllence, Teglholmsgade 41, 2450 Copenhagen SV, Denmark
--------------------------------------------------------------------------------------------------------------------------------------------------------------
--
-- Requirements:
--
-- Description:   Testbench for can_mac_bs. Random stimulus exercises
--                bit counting, stuff bit insertion, and SBC encoding.
--                Checker processes verify reset behavior, stuff bit
--                sufficiency, and SBC parity. Functional coverage tracks
--                input/output bins.
--
-- Revision log:  Date:       Initial:  JIRA:
--                2026-03-15  TMYAES:   Initial implementation
--
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

entity can_mac_bs_tb is
end entity can_mac_bs_tb;

architecture tb of can_mac_bs_tb is

  constant c_clk_period : time    := 10 ns;
  constant c_num_random : integer := 5000;

  -- Input coverage bin IDs
  constant c_bin_idle            : integer := 0;
  constant c_bin_valid_dominant  : integer := 1;
  constant c_bin_valid_recessive : integer := 2;
  constant c_bin_start           : integer := 3;

  -- Output coverage bin IDs
  constant c_bin_no_stuff        : integer := 0;
  constant c_bin_stuff_dominant  : integer := 1;
  constant c_bin_stuff_recessive : integer := 2;

  signal clk_i      : std_logic;
  signal rst_i      : std_logic := '1';
  signal frame_rst  : std_logic := '0';
  signal bs_i       : t_can_mac_fsm_bs_if_m2s;
  signal bs_o       : t_can_mac_fsm_bs_if_s2m;
  signal cov_input  : CoverageIdType;
  signal cov_output : CoverageIdType;
  signal test_done  : resolved_barrier integer := 1;
  shared variable RV : RandomPType;

begin

  CreateClock(clk_i, c_clk_period);
  CreateReset(rst_i, '1', clk_i, c_clk_period * 5);

  u_dut : entity work.can_mac_bs
    port map (
      clk_i => clk_i,
      rst_i => rst_i or frame_rst,
      bs_i  => bs_i,
      bs_o  => bs_o
    );

  p_init : process
  begin
    RV.InitSeed(random_seed);
    SetTestName("can_mac_bs_tb");
    SetAlertStopCount(ERROR, 10);
    wait;
  end process p_init;

  p_timeout : process
  begin
    WaitForClock(clk_i, 200 us / c_clk_period);
    Alert("Testbench timeout", FAILURE);
    std.env.finish;
  end process p_timeout;

  -- -------------------------------------------------------------------------
  -- Drive DUT random stimulus
  -- -------------------------------------------------------------------------
  p_stim : process

  begin

    wait until rst_i = '0';
    WaitForClock(clk_i);

    -- Random stimulus with stuff bit feedback and occasional start pulses
    for i in 0 to c_num_random loop

      -- Occasional frame reset (simulates FSM resetting bit stuffer at SOF)
      if (RV.DistBool((false => 95, true => 5))) then
        frame_rst  <= '1';
        bs_i.valid <= '0';
        WaitForClock(clk_i);
        frame_rst  <= '0';
        WaitForClock(clk_i);
      end if;

      -- Random valid/data
      bs_i.data  <= c_dominant when RV.DistBool((false => 50, true => 50)) else c_recessive;
      bs_i.valid <= '1' when RV.DistBool((false => 25, true => 75)) else '0';
      WaitForClock(clk_i);

      -- Feed stuff bit back when asserted
      if (bs_o.valid = '1') then
        bs_i.data  <= bs_o.data;
        bs_i.valid <= '1';
        WaitForClock(clk_i);
      end if;

    end loop;

    bs_i.valid <= '0';
    WaitForClock(clk_i, 5);
    WaitForBarrier(test_done);

  end process p_stim;

  -- -------------------------------------------------------------------------
  -- Checker: reset clears outputs to defaults
  -- -------------------------------------------------------------------------
  p_reset_checker : process

    variable checker_id : AlertLogIDType;

  begin

    checker_id := GetAlertLogID("Reset Checker");

    wait until rst_i = '0';
    WaitForClock(clk_i);

    loop

      WaitForClock(clk_i);

      if (rst_i = '1' or frame_rst = '1') then
        WaitForClock(clk_i);
        AffirmIf(checker_id, bs_o.valid = '0',
                 "valid not cleared after reset");
        AffirmIf(checker_id, bs_o.data = c_recessive,
                 "data not recessive after reset");
        AffirmIf(checker_id, bs_o.sbc = "0000",
                 "sbc not cleared after reset");
      end if;

    end loop;

  end process p_reset_checker;

  -- -------------------------------------------------------------------------
  -- Checker: stuff bit insertion after 5 consecutive same-polarity bits
  -- -------------------------------------------------------------------------
  p_stuff_bit_checker : process

    variable checker_id       : AlertLogIDType;
    variable consecutive      : integer range 0 to c_stuff_width := 0;
    variable tracked_polarity : std_logic                        := c_recessive;
    variable expect_stuff     : boolean                          := false;

  begin

    checker_id := GetAlertLogID("Stuff Bit Checker");

    wait until rst_i = '0';
    WaitForClock(clk_i);

    loop

      WaitForClock(clk_i);

      -- Verify pending stuff bit expectation from previous cycle
      if (expect_stuff) then
        AffirmIf(checker_id, bs_o.valid = '1',
                 "No stuff bit after " & integer'image(c_stuff_width) &
                 " consecutive " & std_logic'image(tracked_polarity) & " bits");
        if (bs_o.valid = '1') then
          AffirmIf(checker_id, bs_o.data /= tracked_polarity,
                   "Stuff bit has wrong polarity: expected " &
                   std_logic'image(tracked_polarity) & " inversion");
        end if;
        expect_stuff := false;
      end if;

      -- Track consecutive same-polarity bits
      if (rst_i = '1' or frame_rst = '1') then
        consecutive      := 0;
        tracked_polarity := c_recessive;
      elsif (bs_i.valid = '1') then
        if (bs_i.data /= tracked_polarity) then
          consecutive      := 1;
          tracked_polarity := bs_i.data;
        else
          consecutive := consecutive + 1;
        end if;

        if (consecutive = c_stuff_width) then
          expect_stuff := true;
          consecutive  := 0;
        end if;
      end if;

    end loop;

  end process p_stuff_bit_checker;

  -- -------------------------------------------------------------------------
  -- Checker: SBC change and parity
  -- -------------------------------------------------------------------------
  p_sbc_checker : process

    variable checker_id : AlertLogIDType;
    variable prev_sbc   : std_logic_vector(c_sbc_field_width - 1 downto 0) := "0000";
    variable prev_valid : std_logic := '0';

  begin

    checker_id := GetAlertLogID("SBC Checker");

    wait until rst_i = '0';
    WaitForClock(clk_i);

    loop

      WaitForClock(clk_i);

      -- Parity is always correct
      AffirmIf(checker_id,
               bs_o.sbc(0) = (bs_o.sbc(3) xor bs_o.sbc(2) xor bs_o.sbc(1)),
               "SBC parity bit incorrect");

      -- SBC must change on the rising edge of valid (stuff bit event), hold otherwise.
      -- stuff_pending may hold valid high across multiple cycles; only check on the
      -- first cycle valid goes high.
      if (rst_i = '1' or frame_rst = '1') then
        prev_sbc   := "0000";
        prev_valid := '0';
      elsif (bs_o.valid = '1' and prev_valid = '0') then
        AffirmIf(checker_id, bs_o.sbc /= prev_sbc,
                 "SBC did not change after stuff bit");
        prev_sbc := bs_o.sbc;
      elsif (bs_o.valid = '0') then
        AffirmIf(checker_id, bs_o.sbc = prev_sbc,
                 "SBC changed without stuff bit");
      end if;
      prev_valid := bs_o.valid;

    end loop;

  end process p_sbc_checker;

  -- -------------------------------------------------------------------------
  -- Functional coverage
  -- -------------------------------------------------------------------------
  p_coverage : process
  begin

    cov_input  <= NewID("Input Coverage");
    cov_output <= NewID("Output Coverage");
    wait for 0 ns;

    -- Input bins
    AddBins(cov_input, "idle",             50,  GenBin(c_bin_idle));
    AddBins(cov_input, "valid_dominant",   100, GenBin(c_bin_valid_dominant));
    AddBins(cov_input, "valid_recessive",  100, GenBin(c_bin_valid_recessive));
    AddBins(cov_input, "frame_rst",         10,  GenBin(c_bin_start));

    -- Output bins
    AddBins(cov_output, "no_stuff_bit",     100, GenBin(c_bin_no_stuff));
    AddBins(cov_output, "stuff_dominant",   5,   GenBin(c_bin_stuff_dominant));
    AddBins(cov_output, "stuff_recessive",  5,   GenBin(c_bin_stuff_recessive));

    wait until rst_i = '0';

    loop

      WaitForClock(clk_i);

      -- Sample inputs
      if (frame_rst = '1') then
        ICover(cov_input, c_bin_start);
      elsif (bs_i.valid = '1' and bs_i.data = c_dominant) then
        ICover(cov_input, c_bin_valid_dominant);
      elsif (bs_i.valid = '1' and bs_i.data = c_recessive) then
        ICover(cov_input, c_bin_valid_recessive);
      else
        ICover(cov_input, c_bin_idle);
      end if;

      -- Sample outputs
      if (bs_o.valid = '1' and bs_o.data = c_dominant) then
        ICover(cov_output, c_bin_stuff_dominant);
      elsif (bs_o.valid = '1' and bs_o.data = c_recessive) then
        ICover(cov_output, c_bin_stuff_recessive);
      else
        ICover(cov_output, c_bin_no_stuff);
      end if;

      exit when IsCovered(cov_input) and IsCovered(cov_output);

    end loop;

    WaitForBarrier(test_done);

  end process p_coverage;

  -- -------------------------------------------------------------------------
  -- Test finalization
  -- -------------------------------------------------------------------------
  p_test_done : process
  begin
    WaitForBarrier(test_done);

    -- Coverage reports
    WriteBin(cov_input);
    WriteBin(cov_output);
    AffirmIf(GetAlertLogID("Input Coverage"), IsCovered(cov_input),
             "All input bins covered",
             "Input coverage goal not met: " & to_string(GetCov(cov_input), 1) & "%");
    AffirmIf(GetAlertLogID("Output Coverage"), IsCovered(cov_output),
             "All output bins covered",
             "Output coverage goal not met: " & to_string(GetCov(cov_output), 1) & "%");

    EndOfTestReports(ReportAll => TRUE);
    std.env.finish;
  end process p_test_done;

end architecture tb;
