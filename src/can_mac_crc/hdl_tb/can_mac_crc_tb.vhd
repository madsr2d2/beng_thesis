--------------------------------------------------------------------------------------------------------------------------------------------------------------
-- Copyright 2026 Everllence, Teglholmsgade 41, 2450 Copenhagen SV, Denmark
--------------------------------------------------------------------------------------------------------------------------------------------------------------
--
-- Requirements:
--
-- Description:   Testbench for can_mac_crc.
--                  p_input_vc          - Feeds random bit streams to DUT.
--                  p_output_vc         - Checks CRC output against reference model.
--                  p_reset_checker     - Verifies reset zeroes CRC output.
--                  p_output_stable_checker - Verifies CRC holds when valid deasserted.
--                  p_test_ctrl         - Coverage-driven test sequencer.
--
-- Revision log:  Date:       Initial:  JIRA:
--                2026-03-15  TMYAES    [TRIT-4341] Initial implementation
--                2026-03-31  MRDSA     [TRIT-4346] Adapted for local GHDL/OSVVM flow
--------------------------------------------------------------------------------------------------------------------------------------------------------------

library ieee;
  use ieee.std_logic_1164.all;
  use ieee.numeric_std.all;

  use work.pk_can_types.all;

library osvvm;
context osvvm.OsvvmContext;
library osvvm_common;
context osvvm_common.OsvvmCommonContext;

entity can_mac_crc_tb is
  generic (
    gc_TbTimeOut   : time := 2 ms;
    gc_TbClkPeriod : time := 10 ns
  );
end entity;

architecture tb of can_mac_crc_tb is

  ----------------------------------------------------------------------------
  -- Constants
  ----------------------------------------------------------------------------
  constant c_bin_crc_15_sel : natural := 0;
  constant c_bin_crc_17_sel : natural := 1;
  constant c_bin_crc_21_sel : natural := 2;
  constant c_num_frames     : natural := 1000;

  ----------------------------------------------------------------------------
  -- Signals
  ----------------------------------------------------------------------------
  -- DUT interface signals
  signal crc_i : t_can_mac_fsm_crc_if_m2s := c_mac_fsm_to_crc_if_reset;
  signal crc_o : t_can_mac_fsm_crc_if_s2m;

  -- Clock and reset
  signal clk       : std_logic;
  signal reset     : std_logic := '1';
  signal frame_rst : std_logic := '0';
  signal dut_rst   : std_logic;

  -- OSVVM signals
  signal reset_id        : AlertLogIDType;
  signal crc_check_id    : AlertLogIDType;
  signal output_stable_id : AlertLogIDType;
  signal tx_rec : StreamRecType(
    DataToModel(2 * c_max_mac_frame_length - 1 downto 0),
    ParamToModel(1 downto 0),
    DataFromModel(0 downto 0),
    ParamFromModel(0 downto 0)
  );
  signal rx_rec : StreamRecType(
    DataToModel(c_crc_21_length - 1 downto 0),
    ParamToModel(0 downto 0),
    DataFromModel(0 downto 0),
    ParamFromModel(0 downto 0)
  );
  signal cov : CoverageIdType;
  shared variable rv : RandomPType;

  ----------------------------------------------------------------------------
  -- Functions
  ----------------------------------------------------------------------------
  function f_calc_can_crc (data : std_logic_vector; init_vec : std_logic_vector; poly : std_logic_vector) return std_logic_vector is
    variable v_crc      : std_logic_vector(init_vec'length - 1 downto 0);
    variable v_crc_next : std_logic;
  begin
    v_crc := init_vec;
    for i in data'range loop
      v_crc_next := data(i) xor v_crc(v_crc'high);
      v_crc      := v_crc sll 1;
      if (v_crc_next) then
        v_crc := v_crc xor poly;
      end if;
    end loop;
    return v_crc;
  end function f_calc_can_crc;

  -- Left-justifies the CRC output for comparison with DUT.
  function f_calc_can_crc_aligned (
    dat        : std_logic_vector;
    poly_select : std_logic_vector(1 downto 0)
  ) return std_logic_vector is
    variable v_result : std_logic_vector(c_crc_21_length - 1 downto 0) := (others => '0');
  begin
    case poly_select is
      when "00" =>
        v_result := f_calc_can_crc(dat, c_crc_init_15_vec, c_crc_poly_15_vec)
                    & ((c_crc_21_length - 1) - c_crc_15_length downto 0 => '0');
      when "01" =>
        v_result := f_calc_can_crc(dat, c_crc_init_17_vec, c_crc_poly_17_vec)
                    & ((c_crc_21_length - 1) - c_crc_17_length downto 0 => '0');
      when "10" =>
        v_result := f_calc_can_crc(dat, c_crc_init_21_vec, c_crc_poly_21_vec);
      when others =>
        null;
    end case;
    return v_result;
  end function;

begin

  ----------------------------------------------------------------------------
  -- Initialisation
  ----------------------------------------------------------------------------
  p_init : process
    variable v_cov : CoverageIdType;
  begin
    SetAlertStopCount(ERROR, 10);

    reset_id         <= NewId("Reset");
    crc_check_id     <= NewId("CRC Check");
    output_stable_id <= NewId("Output stable check");

    v_cov := NewID("CRC Coverage");
    AddBins(v_cov, "crc_15", 100, GenBin(c_bin_crc_15_sel));
    AddBins(v_cov, "crc_17", 100, GenBin(c_bin_crc_17_sel));
    AddBins(v_cov, "crc_21", 100, GenBin(c_bin_crc_21_sel));
    cov <= v_cov;
    wait;
  end process;

  ----------------------------------------------------------------------------
  -- Clock / reset
  ----------------------------------------------------------------------------
  CreateClock(clk, gc_TbClkPeriod);
  CreateReset(reset, '1', clk, gc_TbClkPeriod * 10);

  ----------------------------------------------------------------------------
  -- Timeout watchdog
  ----------------------------------------------------------------------------
  p_timeout : process
  begin
    WaitForClock(clk, gc_TbTimeOut);
    WaitForClock(clk, 10 ms);
    report "Time Out detected";
    assert false report "ERROR TEST FAILED, due to time out" severity error;
    std.env.stop(1);
  end process p_timeout;

  -- Frame reset OR'd with main reset for CRC re-initialisation between frames
  dut_rst <= reset or frame_rst;

  ----------------------------------------------------------------------------
  -- DUT
  ----------------------------------------------------------------------------
  u_dut : entity work.can_mac_crc
    port map (
      clk_i => clk,
      reset_i => dut_rst,
      crc_i => crc_i,
      crc_o => crc_o
    );

  ----------------------------------------------------------------------------
  -- Test sequencer
  ----------------------------------------------------------------------------
  p_test_ctrl : process is
    variable v_data_cc     : std_logic_vector(c_max_mac_frame_length - 1 downto 0);
    variable v_data_fd     : std_logic_vector(c_max_mac_frame_length - 1 downto 0);
    variable v_expected    : std_logic_vector(c_max_mac_frame_length - 1 downto 0);
    variable v_poly_select : std_logic_vector(1 downto 0);
  begin
    wait until reset = '0';
    WaitForClock(clk);

    for i in 0 to c_num_frames loop
      -- Random data for both streams
      v_data_cc     := rv.RandSlv(c_max_mac_frame_length);
      v_data_fd     := rv.RandSlv(c_max_mac_frame_length);
      v_poly_select := std_logic_vector(to_unsigned(RandCovPoint(cov), 2));

      -- Determine which data stream the DUT should be calculating CRC from
      if v_poly_select = c_crc_poly_15_sel then
        v_expected := v_data_cc;
      else
        v_expected := v_data_fd;
      end if;

      Send(tx_rec, Data => v_data_cc & v_data_fd, Param => v_poly_select);
      Check(rx_rec, Data => f_calc_can_crc_aligned(v_expected, v_poly_select));
      ICover(cov, to_integer(unsigned(v_poly_select)));
      WaitForClock(clk, rv.RandInt(2, 100));
    end loop;

    -- Done
    AlertIf(crc_check_id, not IsCovered(cov), "Coverage goal not met");
    WriteBin(cov);
    EndOfTestReports(ReportAll => TRUE);
    std.env.finish;
  end process p_test_ctrl;

  ----------------------------------------------------------------------------
  -- Input VC: feeds bits serially to DUT
  ----------------------------------------------------------------------------
  p_input_vc : process is
  begin
    wait until tx_rec.Rdy /= tx_rec.Ack;

    case tx_rec.Operation is
      when SEND =>
        -- Pulse frame reset to clear CRC state before each frame
        frame_rst <= '1';
        WaitForClock(clk);
        frame_rst <= '0';
        WaitForClock(clk);
        -- Feed both streams in parallel, one bit per clock
        for i in c_max_mac_frame_length - 1 downto 0 loop
          crc_i.crc_poly_select <= SafeResize(tx_rec.ParamToModel, crc_i.crc_poly_select'length);
          crc_i.data_cc <= tx_rec.DataToModel(i + c_max_mac_frame_length);
          crc_i.data_fd <= tx_rec.DataToModel(i);
          crc_i.valid_cc   <= '1';
          crc_i.valid_fd   <= '1';
          WaitForClock(clk);
        end loop;
        crc_i.valid_cc <= '0';
        crc_i.valid_fd <= '0';
        WaitForClock(clk);
        tx_rec.Ack <= tx_rec.Ack + 1;
      when others => null;
    end case;
  end process p_input_vc;

  ----------------------------------------------------------------------------
  -- Output VC
  ----------------------------------------------------------------------------
  p_output_vc : process is
  begin
    wait until rx_rec.Rdy /= rx_rec.Ack;

    case rx_rec.Operation is
      when CHECK =>
        -- REQ-007: CRC polynomial selection (CRC_15/17/21) and receiver verification
        AffirmIf(crc_check_id, std_logic_vector(crc_o.crc) = std_logic_vector(rx_rec.DataToModel), "Got : " & to_string(crc_o.crc) & ", expected: " & to_string(std_logic_vector(rx_rec.DataToModel)));
        rx_rec.Ack <= rx_rec.Ack + 1;
      when others => null;
    end case;
  end process p_output_vc;

  ---------------------------------------------------------------------------
  -- Checker: Check reset
  ---------------------------------------------------------------------------
  p_reset_checker : process is
    variable v_expected : std_logic_vector(c_crc_21_length - 1 downto 0);
  begin
    loop
      wait until rising_edge(clk) and dut_rst = '1';
      WaitForClock(clk);
      case crc_i.crc_poly_select is
        when c_crc_poly_15_sel =>
          v_expected := c_crc_init_15_vec & (c_crc_21_length - 1 - c_crc_15_length downto 0 => '0');
        when c_crc_poly_17_sel =>
          v_expected := c_crc_init_17_vec & (c_crc_21_length - 1 - c_crc_17_length downto 0 => '0');
        when c_crc_poly_21_sel =>
          v_expected := c_crc_init_21_vec;
        when others =>
          v_expected := (others => '0');
      end case;
      -- REQ-007: CRC_INIT_VECTOR = (0,...,0) for CRC_15; (1,0,...,0) for CRC_17 and CRC_21
      AffirmIf(reset_id, crc_o.crc = v_expected, "CRC output not reset to init value");
    end loop;
  end process p_reset_checker;

  ---------------------------------------------------------------------------
  -- Checker: Check that CRC output is stable when valid is not asserted.
  ---------------------------------------------------------------------------
  p_output_stable_checker : process is
    variable v_crc_snap : std_logic_vector(crc_o.crc'range);
  begin
    wait until reset = '0';
    loop
      wait until rising_edge(clk);
      if crc_i.valid_cc = '0' and dut_rst = '0' then
        WaitForClock(clk);
        loop
          exit when crc_i.valid_cc = '1' or dut_rst = '1';
          v_crc_snap := crc_o.crc;
          WaitForClock(clk);
          AffirmIf(output_stable_id, crc_o.crc = v_crc_snap, "CRC output changed without valid");
        end loop;
      end if;
    end loop;
  end process p_output_stable_checker;

end architecture tb;

-- eof
