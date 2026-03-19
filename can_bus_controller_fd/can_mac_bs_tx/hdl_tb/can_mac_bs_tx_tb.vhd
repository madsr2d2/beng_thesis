--------------------------------------------------------------------------------------------------------------------------------------------------------------
-- Copyright 2025 Everllence, Teglholmsgade 41, 2450 Copenhagen SV, Denmark
--------------------------------------------------------------------------------------------------------------------------------------------------------------
--
-- Requirements:
--
-- Description:   Testbench for can_mac_bs_tx. Random stimulus exercises
--                bit counting, stuff bit insertion, and SBC encoding.
--                Checker processes verify reset behavior, stuff bit
--                sufficiency, and SBC parity. Functional coverage tracks
--                input/output bins.
--
-- Revision log:  Date:       Initial:  JIRA:
--                2026-03-15  TMYAES:   [TRIT-4338] Initial implementation
--
--------------------------------------------------------------------------------------------------------------------------------------------------------------

library ieee;
  use ieee.std_logic_1164.all;
  use ieee.numeric_std.all;
  use work.pk_man_global.all;
  use work.common_register_interface_pkg.all;
  use work.common_tb_pkg.all;
  use work.pk_can_types.all;

library osvvm;
context osvvm.OsvvmContext;

entity can_mac_bs_tx_tb is
  generic (
    gc_TbTimeOut   : time := 2 ms;
    gc_TbClkPeriod : time := 10 ns
    --
  );
end entity;

architecture tb of can_mac_bs_tx_tb is
  ----------------------------------------------------------------------------
  -- Constants
  ----------------------------------------------------------------------------

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

  ----------------------------------------------------------------------------
  -- Signals
  ----------------------------------------------------------------------------
  signal bs_i       : t_can_mac_fsm_bs_tx_if_m2s;
  signal bs_o       : t_can_mac_fsm_bs_tx_if_s2m;
  signal cov_input  : CoverageIdType;
  signal cov_output : CoverageIdType;
  signal test_done  : std_logic;

  -- Test ids
  signal test_id          : AlertLogIDType;
  signal reset_id         : AlertLogIDType;

  signal clk   : std_logic := '0';
  signal reset : std_logic := '1';


  shared variable RV : RandomPType;

begin
  p_init : process
    variable v_test_id : AlertLogIDType;
  begin
    RV.InitSeed(random_seed);
    SetAlertStopCount(ERROR, 10);

    v_test_id := NewId("can_mac_bs_tx");
    test_id   <= v_test_id;
    reset_id  <= NewId("Reset at Output", v_test_id);

    wait for 0 ns;

    wait;
  end process;

  ----------------------------------------------------
  -- Clock gen
  ----------------------------------------------------
  CreateClock(clk, gc_TbClkPeriod);
  CreateReset(reset, '1', clk, gc_TbClkPeriod * 5);

  ----------------------------------------------------
  -- Simulation Time out monitor.
  -- Terminates the simulation when a timeout event is detected
  ----------------------------------------------------
  p_timeout : process
  begin
    WaitForClock(clk, gc_TbTimeOut);

    WaitForClock(clk, 1 us);

    report "Time Out detected";
    assert (false) report "ERROR TEST FAILED, due to time out" severity error;

    std.env.stop(1);
  end process p_timeout;

  ----------------------------------------------------
  -- Dut
  ----------------------------------------------------

  u_dut : entity work.can_mac_bs_tx
    port map (
      clk_i => clk,
      rst_i => reset,
      bs_i  => bs_i,
      bs_o  => bs_o
    );

  
  -- -------------------------------------------------------------------------
  -- Drive DUT random stimulus
  -- -------------------------------------------------------------------------
  p_stim : process

    variable rnd : RandomPType;

  begin

    rnd.InitSeed(rnd'instance_name & to_string(now));

    wait until reset = '0';
    WaitForClock(clk);

    -- Random stimulus with stuff bit feedback and occasional start pulses
    for i in 0 to c_num_random loop

      -- Occasional start pulse
      if (rnd.DistBool((false => 95, true => 5))) then
        bs_i.start <= '1';
        bs_i.valid <= '0';
        WaitForClock(clk);
        bs_i.start <= '0';
        WaitForClock(clk);
      end if;

      -- Random valid/data
      bs_i.data  <= c_dominant when rnd.DistBool((false => 50, true => 50)) else c_recessive;
      bs_i.valid <= '1' when rnd.DistBool((false => 25, true => 75)) else '0';
      WaitForClock(clk);

      -- Feed stuff bit back when asserted
      if (bs_o.valid = '1') then
        bs_i.data  <= bs_o.data;
        bs_i.valid <= '1';
        WaitForClock(clk);
      end if;

    end loop;

    bs_i.valid <= '0';
    WaitForClock(clk, 5);
    WaitForBarrier(test_done);

  end process p_stim;

  -- -------------------------------------------------------------------------
  -- Checker: reset clears outputs to defaults
  -- -------------------------------------------------------------------------
  p_reset_checker : process

  begin

    wait until reset = '0';
    WaitForClock(clk);

    loop

      WaitForClock(clk);

      if (reset = '1' or bs_i.start = '1') then
        WaitForClock(clk);
        AffirmIf(reset_id, bs_o.valid = '0',
                 "valid not cleared after reset/start");
        AffirmIf(reset_id, bs_o.data = c_recessive,
                 "data not recessive after reset/start");
        AffirmIf(reset_id, bs_o.sbc = "0000",
                 "sbc not cleared after reset/start");
      end if;

    end loop;

  end process p_reset_checker;

  -- -------------------------------------------------------------------------
  -- Checker: stuff bit insertion after 5 consecutive same-polarity bits
  -- -------------------------------------------------------------------------
  p_stuff_bit_checker : process

    variable consecutive      : integer range 0 to c_stuff_width := 0;
    variable tracked_polarity : std_logic                       := c_recessive;
    variable expect_stuff     : boolean                          := false;

  begin


    wait until reset = '0';
    WaitForClock(clk);

    loop

      WaitForClock(clk);

      -- Verify pending stuff bit expectation from previous cycle
      if (expect_stuff) then
        AffirmIf(test_id, bs_o.valid = '1',
                 "No stuff bit after " & integer'image(c_stuff_width) &
                 " consecutive " & std_logic'image(tracked_polarity) & " bits");
        if (bs_o.valid = '1') then
          AffirmIf(test_id, bs_o.data /= tracked_polarity,
                   "Stuff bit has wrong polarity: expected " &
                   std_logic'image(tracked_polarity) & " inversion");
        end if;
        expect_stuff := false;
      end if;

      -- Track consecutive same-polarity bits
      if (reset = '1' or bs_i.start = '1') then
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

    variable prev_sbc   : std_logic_vector(c_sbc_field_width - 1 downto 0) := "0000";

  begin

    wait until reset = '0';
    WaitForClock(clk);

    loop

      WaitForClock(clk);

      -- Parity is always correct
      AffirmIf(test_id,
               bs_o.sbc(0) = (bs_o.sbc(3) xor bs_o.sbc(2) xor bs_o.sbc(1)),
               "SBC parity bit incorrect");

      -- SBC must change on stuff bit events, hold otherwise
      if (reset = '1' or bs_i.start='1') then
        prev_sbc := "0000";
      elsif (bs_o.valid = '1') then
        AffirmIf(test_id, bs_o.sbc /= prev_sbc,
                 "SBC did not change after stuff bit");
        prev_sbc := bs_o.sbc;
      else
        AffirmIf(test_id, bs_o.sbc = prev_sbc,
                 "SBC changed without stuff bit");
      end if;

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
    AddBins(cov_input, "start",            10,  GenBin(c_bin_start));

    -- Output bins
    AddBins(cov_output, "no_stuff_bit",     100, GenBin(c_bin_no_stuff));
    AddBins(cov_output, "stuff_dominant",   5,   GenBin(c_bin_stuff_dominant));
    AddBins(cov_output, "stuff_recessive",  5,   GenBin(c_bin_stuff_recessive));

    wait until reset = '0';

    loop

      WaitForClock(clk);

      -- Sample inputs
      if (bs_i.start = '1') then
        ICover(cov_input, c_bin_start);
      elsif (bs_i.valid ='1' and bs_i.data = c_dominant) then
        ICover(cov_input, c_bin_valid_dominant);
      elsif (bs_i.valid = '1' and bs_i.data = c_recessive) then
        ICover(cov_input, c_bin_valid_recessive);
      else
        ICover(cov_input, c_bin_idle);
      end if;

      -- Sample outputs
      if (bs_o.valid='1' and bs_o.data = c_dominant) then
        ICover(cov_output, c_bin_stuff_dominant);
      elsif (bs_o.valid='1' and bs_o.data = c_recessive) then
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

-- eof
