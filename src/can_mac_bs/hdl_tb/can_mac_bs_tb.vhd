--------------------------------------------------------------------------------------------------------------------------------------------------------------
-- Copyright 2025 Everllence, Teglholmsgade 41, 2450 Copenhagen SV, Denmark
--------------------------------------------------------------------------------------------------------------------------------------------------------------
--
-- Requirements:
--
-- Description:   Testbench for can_mac_bs.
--                  p_stim              - Two-phase driver: directed FSB tests then random dynamic.
--                  p_reset_checker     - Verifies outputs cleared after reset.
--                  p_stuff_bit_checker - Verifies dynamic stuff bit after 5 consecutive same bits.
--                  p_sbc_checker       - Verifies SBC parity, increments on dynamic, holds on FSB.
--                  p_fsb_checker       - Verifies initial and periodic FSB timing and polarity.
--                  p_coverage          - Input/output functional coverage.
--
-- Revision log:  Date:       Initial:  JIRA:
--                2026-03-15  TMYAES    Initial implementation
--                2026-04-05  MRDSA     Add FSB mode directed tests and checkers
--
--------------------------------------------------------------------------------------------------------------------------------------------------------------

library ieee;
  use ieee.std_logic_1164.all;
  use ieee.numeric_std.all;

library osvvm;
  context osvvm.OsvvmContext;

use work.pk_can_types.all;

entity can_mac_bs_tb is
end entity can_mac_bs_tb;

architecture tb of can_mac_bs_tb is

  constant c_clk_period : time    := 10 ns;
  constant c_num_random : natural := 5000;

  signal clk_i      : std_logic;
  signal rst_i      : std_logic := '1';
  signal frame_rst  : std_logic := '0';
  signal bs_i       : t_can_mac_fsm_bs_if_m2s := c_mac_fsm_to_bs_fd_if_reset;
  signal bs_o       : t_can_mac_fsm_bs_if_s2m;
  signal cov_input  : CoverageIdType;
  signal cov_output : CoverageIdType;
  signal test_done  : resolved_barrier natural := 1;
  shared variable RV : RandomPType;
  signal test_id    : AlertLogIDType;
  signal reset_id   : AlertLogIDType;
  signal dsb_id   : AlertLogIDType;

begin

  CreateClock(clk_i, c_clk_period);
  CreateReset(rst_i, '1', clk_i, c_clk_period * 5);

  u_dut : entity work.can_mac_bs
    port map (
      clk_i => clk_i,
      reset_i => rst_i or frame_rst,
      bs_i  => bs_i,
      bs_o  => bs_o
    );

  p_init : process
    variable v_test_id    : AlertLogIDType;
    variable v_reset_id   : AlertLogIDType;
    variable v_dsb_id     : AlertLogIDType;
  begin
    SetAlertStopCount(ERROR, 10);
    v_test_id := NewID("can_mac_bs");
    v_reset_id   := NewID("Reset check", v_test_id);
    v_dsb_id     := NewID("Dynamic stuff bit check", v_test_id);
    test_id <= v_test_id;
    reset_id <= v_reset_id;
    dsb_id <= v_dsb_id;
    wait;
  end process p_init;

  p_timeout : process
  begin
    WaitForClock(clk_i, 500 us / c_clk_period);
    Alert("Testbench timeout", FAILURE);
    std.env.finish;
  end process p_timeout;

  -- -------------------------------------------------------------------------
  -- Stimulus: directed FSB tests (phase 1), then random dynamic (phase 2)
  -- -------------------------------------------------------------------------
  p_stim : process

    variable stim_id   : AlertLogIDType;
    variable saved_sbc : std_logic_vector(c_sbc_field_width - 1 downto 0);

    procedure send_bit (data : std_logic; fsb_en : std_logic := '0') is
    begin
      bs_i.data   <= data;
      bs_i.valid  <= '1';
      bs_i.fixed_bit_stuffing_en <= fsb_en;
      WaitForClock(clk_i);
      bs_i.valid  <= '0';
      WaitForClock(clk_i);
    end procedure;

    procedure ack_stuff_bit is
    begin
      bs_i.data  <= bs_o.data;
      bs_i.valid <= '1';
      WaitForClock(clk_i);
      bs_i.valid <= '0';
      WaitForClock(clk_i);
    end procedure;

  begin

    stim_id := GetAlertLogID("FSB Directed Tests");

    wait until rst_i = '0';
    WaitForClock(clk_i);

    -- FSB-1: initial FSB on rising edge of fsb_en
    send_bit(c_dominant);
    bs_i.fixed_bit_stuffing_en <= '1';
    WaitForClock(clk_i, 2);

    AffirmIf(stim_id, bs_o.valid = '1', "FSB-1: initial FSB not asserted after fsb_en rising edge");
    AffirmIf(stim_id, bs_o.data = c_recessive, "FSB-1: initial FSB polarity wrong (expected recessive)");
    ack_stuff_bit;

    -- FSB-2: periodic FSB after 4 dominant bits
    for j in 1 to 4 loop
      send_bit(c_dominant, '1');
    end loop;

    AffirmIf(stim_id, bs_o.valid = '1', "FSB-2: no FSB after 4 dominant bits");
    AffirmIf(stim_id, bs_o.data = c_recessive, "FSB-2: FSB polarity wrong (expected recessive)");
    ack_stuff_bit;

    -- FSB-3: periodic FSB after 4 recessive bits
    for j in 1 to 4 loop
      send_bit(c_recessive, '1');
    end loop;

    AffirmIf(stim_id, bs_o.valid = '1', "FSB-3: no FSB after 4 recessive bits");
    AffirmIf(stim_id, bs_o.data = c_dominant, "FSB-3: FSB polarity wrong (expected dominant)");
    ack_stuff_bit;

    -- FSB-4: mixed D-R-D-R, FSB polarity tracks 4th bit
    send_bit(c_dominant, '1');
    send_bit(c_recessive, '1');
    send_bit(c_dominant, '1');
    send_bit(c_recessive, '1');

    AffirmIf(stim_id, bs_o.valid = '1', "FSB-4: no FSB after D-R-D-R sequence");
    AffirmIf(stim_id, bs_o.data = c_dominant, "FSB-4: FSB polarity wrong (expected dominant)");
    ack_stuff_bit;

    -- FSB-5: SBC invariant across FSB groups
    saved_sbc := bs_o.stuff_bit_count;

    for grp in 0 to 1 loop
      for j in 1 to 4 loop
        send_bit(c_dominant, '1');
      end loop;
      ack_stuff_bit;
    end loop;

    AffirmIf(stim_id, bs_o.stuff_bit_count = saved_sbc, "FSB-5: SBC changed during FSB mode");

    -- FSB-6: transition back to dynamic stuffing
    bs_i.fixed_bit_stuffing_en <= '0';
    WaitForClock(clk_i);

    for j in 1 to 5 loop
      send_bit(c_dominant);
    end loop;

    AffirmIf(stim_id, bs_o.valid = '1', "FSB-6: no dynamic stuff bit after 5 dominant bits");
    AffirmIf(stim_id, bs_o.data = c_recessive, "FSB-6: stuff bit polarity wrong (expected recessive)");

    ack_stuff_bit;
    WaitForClock(clk_i, 3);

    -- Phase 2: random dynamic stimulus
    for i in 0 to c_num_random loop

      if (RV.DistBool((false => 95, true => 5))) then
        frame_rst  <= '1';
        bs_i.valid <= '0';
        WaitForClock(clk_i);
        frame_rst  <= '0';
        WaitForClock(clk_i);
      end if;

      bs_i.data   <= c_dominant when RV.DistBool((false => 50, true => 50)) else c_recessive;
      bs_i.valid  <= '1' when RV.DistBool((false => 25, true => 75)) else '0';
      bs_i.fixed_bit_stuffing_en <= '0';
      WaitForClock(clk_i);

      if (bs_o.valid = '1') then
        bs_i.data  <= bs_o.data;
        bs_i.valid <= '1';
        WaitForClock(clk_i);
      end if;

    end loop;

    bs_i.valid  <= '0';
    bs_i.fixed_bit_stuffing_en <= '0';
    WaitForClock(clk_i, 5);
    WaitForBarrier(test_done);

  end process p_stim;

  -- -------------------------------------------------------------------------
  -- Checker: reset clears outputs
  -- -------------------------------------------------------------------------
  p_reset_checker : process
  begin
    wait until rst_i = '0';
    WaitForClock(clk_i);

    loop
      WaitForClock(clk_i);

      if (rst_i = '1' or frame_rst = '1') then
        WaitForClock(clk_i);
        AffirmIf(reset_id, bs_o = c_can_mac_fsm_bs_if_s2m_reset, "Not reset correctly");
      end if;
    end loop;
  end process p_reset_checker;

  ---------------------------------------------------------------------------
  -- Checker: dynamic stuff bit after 5 consecutive same-polarity bits
  ---------------------------------------------------------------------------
  p_stuff_bit_checker : process
    variable consecutive  : natural range 0 to c_stuff_width := 0;
    variable polarity     : std_logic := c_recessive;
    variable expect_stuff : boolean   := false;
    variable fsb_en_prev  : std_logic := '0';
  begin
    wait until rst_i = '0';
    WaitForClock(clk_i);

    loop
      WaitForClock(clk_i);

      -- Check expectation from previous cycle
      if (expect_stuff) then
        -- REQ-038: transmitter inserts complement stuff bit after 5 consecutive identical bits
        AffirmIf(dsb_id, bs_o.valid = '1', "Expected bs_o.valid = '1', was '0'");
        if (bs_o.valid = '1') then
          AffirmIf(dsb_id, bs_o.data /= polarity, "Wrong stuff bit polarity");
        end if;
        expect_stuff := false;
      end if;

      -- Reset tracking
      if (rst_i = '1' or frame_rst = '1') then
        consecutive := 0;
        polarity    := c_recessive;
        fsb_en_prev := '0';
      else
        -- Falling edge of fsb_en: restart tracking for dynamic mode
        if (bs_i.fixed_bit_stuffing_en = '0' and fsb_en_prev = '1') then
          consecutive := 0;
          polarity    := c_recessive;
        end if;
        fsb_en_prev := bs_i.fixed_bit_stuffing_en;

        -- Count consecutive same-polarity bits (dynamic mode only)
        if (bs_i.valid = '1' and bs_i.fixed_bit_stuffing_en = '0') then
          if (bs_i.data /= polarity) then
            consecutive := 1;
            polarity    := bs_i.data;
          else
            consecutive := consecutive + 1;
          end if;

          if (consecutive = c_stuff_width) then
            expect_stuff := true;
            consecutive  := 0;
          end if;
        end if;
      end if;
    end loop;
  end process p_stuff_bit_checker;

  ---------------------------------------------------------------------------
  -- Checker: SBC parity, increments on dynamic stuff, holds on FSB
  ---------------------------------------------------------------------------
  p_sbc_checker : process
    variable id         : AlertLogIDType;
    variable prev_sbc   : std_logic_vector(c_sbc_field_width - 1 downto 0) := "0000";
    variable prev_valid : std_logic := '0';
  begin
    id := GetAlertLogID("SBC Checker");
    wait until rst_i = '0';
    WaitForClock(clk_i);

    loop
      WaitForClock(clk_i);

      -- REQ-032: SBC Gray-coded with parity SBC0 = xor(SBC3, SBC2, SBC1); count increments on dynamic stuff bit, holds on FSB
      AffirmIf(id, bs_o.stuff_bit_count(0) = (bs_o.stuff_bit_count(3) xor bs_o.stuff_bit_count(2) xor bs_o.stuff_bit_count(1)), "SBC parity bit incorrect");

      if (rst_i = '1' or frame_rst = '1') then
        prev_sbc   := "0000";
        prev_valid := '0';
      elsif (bs_o.valid = '1' and prev_valid = '0') then
        -- Rising edge of bs_o.valid: new stuff bit event
        if (bs_i.fixed_bit_stuffing_en = '0') then
          AffirmIf(id, bs_o.stuff_bit_count /= prev_sbc, "SBC did not change after dynamic stuff bit");
        else
          AffirmIf(id, bs_o.stuff_bit_count = prev_sbc, "SBC incorrectly changed after FSB");
        end if;
        prev_sbc := bs_o.stuff_bit_count;
      elsif (bs_o.valid = '0') then
        AffirmIf(id, bs_o.stuff_bit_count = prev_sbc, "SBC changed without a stuff bit event");
      end if;
      prev_valid := bs_o.valid;
    end loop;
  end process p_sbc_checker;

  ---------------------------------------------------------------------------
  -- Checker: FSB timing and polarity
  ---------------------------------------------------------------------------
  p_fsb_checker : process
    variable id             : AlertLogIDType;
    variable fsb_en_prev    : std_logic := '0';
    variable last_polarity  : std_logic := c_recessive;
    variable real_bit_count : natural   := 0;
    variable expect_fsb     : boolean   := false;
    variable expected_data  : std_logic := c_dominant;
  begin
    id := GetAlertLogID("FSB Checker");
    wait until rst_i = '0';
    WaitForClock(clk_i);

    loop
      WaitForClock(clk_i);

      -- Check pending FSB expectation from previous cycle
      if (expect_fsb) then
        -- REQ-039: initial FSB before first SBC bit; FSB after each 4th CRC bit; FSB value inverse of preceding bit
        AffirmIf(id, bs_o.valid = '1', "Expected FSB not asserted");
        if (bs_o.valid = '1') then
          AffirmIf(id, bs_o.data = expected_data, "FSB polarity wrong: expected " & std_logic'image(expected_data));
        end if;
        expect_fsb     := false;
        real_bit_count := 0;
      end if;

      if (rst_i = '1' or frame_rst = '1') then
        fsb_en_prev    := '0';
        last_polarity  := c_recessive;
        real_bit_count := 0;
        expect_fsb     := false;

      elsif (bs_i.fixed_bit_stuffing_en = '1') then
        -- Rising edge: expect initial FSB
        if (fsb_en_prev = '0') then
          expect_fsb     := true;
          expected_data  := not last_polarity;
          real_bit_count := 0;
        end if;

        -- Count real bits (skip FSB acknowledges where bs_o.valid='1')
        if (bs_i.valid = '1' and bs_o.valid = '0') then
          last_polarity  := bs_i.data;
          real_bit_count := real_bit_count + 1;
          if (real_bit_count = 4) then
            expect_fsb     := true;
            expected_data  := not bs_i.data;
            real_bit_count := 0;
          end if;
        end if;

      else
        -- Dynamic mode: track polarity for next fsb_en edge
        if (bs_i.valid = '1') then
          last_polarity := bs_i.data;
        end if;
        if (fsb_en_prev = '1') then
          real_bit_count := 0;
        end if;
      end if;

      fsb_en_prev := bs_i.fixed_bit_stuffing_en;
    end loop;
  end process p_fsb_checker;

  ---------------------------------------------------------------------------
  -- Functional coverage
  ---------------------------------------------------------------------------
  p_coverage : process
    variable v_in  : natural;
    variable v_out : natural;
  begin
    cov_input  <= NewID("Input Coverage");
    cov_output <= NewID("Output Coverage");
    wait for 0 ns;

    AddBins(cov_input, "idle",              50, GenBin(0));
    AddBins(cov_input, "valid_dominant",   100, GenBin(1));
    AddBins(cov_input, "valid_recessive",  100, GenBin(2));
    AddBins(cov_input, "frame_rst",         10, GenBin(3));
    AddBins(cov_input, "fsb_dominant",      10, GenBin(4));
    AddBins(cov_input, "fsb_recessive",     10, GenBin(5));

    AddBins(cov_output, "no_stuff_bit",    100, GenBin(0));
    AddBins(cov_output, "stuff_dominant",    5, GenBin(1));
    AddBins(cov_output, "stuff_recessive",   5, GenBin(2));
    AddBins(cov_output, "fsb_dominant",      3, GenBin(3));
    AddBins(cov_output, "fsb_recessive",     3, GenBin(4));

    wait until rst_i = '0';

    loop
      WaitForClock(clk_i);

      -- Classify input
      if (frame_rst = '1') then                                           v_in := 3;
      elsif (bs_i.fixed_bit_stuffing_en = '1' and bs_i.valid = '1') then
        if (bs_i.data = c_dominant) then                                  v_in := 4;
        else                                                              v_in := 5;
        end if;
      elsif (bs_i.valid = '1') then
        if (bs_i.data = c_dominant) then                                  v_in := 1;
        else                                                              v_in := 2;
        end if;
      else                                                                v_in := 0;
      end if;
      ICover(cov_input, v_in);

      -- Classify output
      if (bs_o.valid = '1') then
        if (bs_i.fixed_bit_stuffing_en = '1') then
          if (bs_o.data = c_dominant) then                                v_out := 3;
          else                                                            v_out := 4;
          end if;
        else
          if (bs_o.data = c_dominant) then                                v_out := 1;
          else                                                            v_out := 2;
          end if;
        end if;
      else                                                                v_out := 0;
      end if;
      ICover(cov_output, v_out);

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

    WriteBin(cov_input);
    WriteBin(cov_output);
    AffirmIf(GetAlertLogID("Input Coverage"), IsCovered(cov_input), "All input bins covered", "Input coverage goal not met: " & to_string(GetCov(cov_input), 1) & "%");
    AffirmIf(GetAlertLogID("Output Coverage"), IsCovered(cov_output), "All output bins covered", "Output coverage goal not met: " & to_string(GetCov(cov_output), 1) & "%");

    EndOfTestReports(ReportAll => TRUE);
    std.env.finish;
  end process p_test_done;

end architecture tb;
