--------------------------------------------------------------------------------------------------------------------------------------------------------------
-- Copyright 2025 Everllence, Teglholmsgade 41, 2450 Copenhagen SV, Denmark
--------------------------------------------------------------------------------------------------------------------------------------------------------------
--
-- Requirements:  
--
-- Description:   
--
-- Revision log:  Date:       Initial:  JIRA:
--                2025-04-03  AFNI:     [TRIT-3892] [FPGA] CAN-bus controller VIP
--                2025-07-09  TMYAES:   [TRIT-3880] [FPGA] Added test cases for normal operation, bit stuffing error and CRC error
--                2025-08-08  AFNI:     [TRIT-4042] [FPGA] Integrate can-bus controller into the io_ext
--                2025-10-03  AFNI:     [CPUM2400-726] [FPGA] Correct AXI response
--                2025-12-02  AFNI:     [TRIT-3920] [FPGA] CAN-bus regression test
--                2025-12-15  AFNI:     [TRIT-4195] [FPGA] IO-extender code review
--                2026-02-11  AFNI:     [TRIT-3923] [FPGA] Bring-up of real IO-extender
--
--------------------------------------------------------------------------------------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

use work.pk_man_global.all;

use work.common_register_interface_pkg.all;
use work.common_tb_pkg.all;
use work.pk_eth_st.all;

use work.pk_can_bus_vc.all;
use work.pk_can_bus_controller.all;
use work.pk_llc_frame_scoreboard.all;
use work.pk_eth_st_scoreboard.all;

library osvvm;
context osvvm.OsvvmContext;

library osvvm_common;
context osvvm_common.OsvvmCommonContext;

entity can_bus_controller_tb is
  generic(
    -- Constant Generics which can be set before simulation start to test multiple settings.
    gc_TbTimeOut   : time    := 700 ms;                                         -- Simulator Time out
    gc_TbClkPeriod : time    := 10 ns;                                          -- Set the test clock period, Default 100MHz
    gc_verbose     : boolean := false                                           -- Set to true to enable verbose output
  );
end entity;

architecture tb of can_bus_controller_tb is
  ----------------------------------------------------------------------------
  -- Util functions
  ---------------------------------------------------------------------------
  function real_min(a, b : real) return real is
  begin
    if a < b then
      return a;
    else
      return b;
    end if;
  end function;
  function integer_min(a, b : integer) return integer is
  begin
    if a < b then
      return a;
    else
      return b;
    end if;
  end function;

  ----------------------------------------------------------------------------
  -- Constants
  ----------------------------------------------------------------------------
  constant c_bit_rate          : integer := c_alint_default_bit_rate_hz;
  constant c_phase_seg1_length : integer := 6;
  constant c_phase_seg2_length : integer := 5;
  constant c_prop_seg_length   : integer := 8;
  constant c_sync_jump_width   : integer := 2;

  -- For now earlier sample point, as they are slower.
  constant c_model_phase_seg1_length : integer := 3;
  constant c_slow_phase_seg1_length  : integer := 6;
  constant c_model_phase_seg2_length : integer := 8;
  constant c_slow_phase_seg2_length  : integer := 5;
  constant c_model_prop_seg_length   : integer := 8;
  constant c_model_sync_jump_width   : integer := 2;
  constant c_bit_length              : integer := c_phase_seg1_length + c_phase_seg2_length + c_prop_seg_length + c_sync_seg_length;

  -- Frequency delta tolerance (ISO 11898-1:2024-5, section 7.3.6, eq. 3 and 4)
  constant c_clock_delta_1 : real := real(integer_min(c_phase_seg1_length, c_phase_seg2_length)) / real((2 * (13 * c_bit_length - c_phase_seg2_length)));
  constant c_clock_delta_2 : real := real(c_sync_jump_width) / real((20 * c_bit_length));
  constant c_clock_delta   : real := real_min(c_clock_delta_1, c_clock_delta_2);

  constant c_stuff_bit_in_only_crc : t_llc_frame := (
    id       => 29X"16532243",
    length   => X"6",
    data     => (
      0 => X"D0",
      1 => X"E2",
      2 => X"35",
      3 => X"44",
      4 => X"56",
      5 => X"CE",
      6 => X"00",
      7 => X"00"
    ),
    rtr      => '0',
    extended => '1'
  );


  ----------------------------------------------------------------------------
  -- Signals
  ----------------------------------------------------------------------------
  -- Test ids
  signal test_id  : AlertLogIDType;
  signal reset_id : AlertLogIDType;
  signal gen_id   : AlertLogIDType;

  signal rx_sink_fifo_id   : work.pk_eth_st_scoreboard.ScoreboardIdType;
  signal tx_src_fifo_id    : work.pk_eth_st_scoreboard.ScoreboardIdType;
  signal rx_2_sink_fifo_id : work.pk_eth_st_scoreboard.ScoreboardIdType;
  signal tx_2_src_fifo_id  : work.pk_eth_st_scoreboard.ScoreboardIdType;

  signal rx_sink_received   : integer := 0;
  signal rx_sink_expected   : integer := 0;
  signal rx_2_sink_received : integer := 0;
  signal rx_2_sink_expected : integer := 0;

  signal tx_src_req : integer := 0;
  signal tx_src_ack : integer := 0;

  signal tx_2_src_req : integer := 0;
  signal tx_2_src_ack : integer := 0;

  signal clk   : std_logic := '0';
  signal reset : std_logic := '1';

  signal rx          : std_logic;
  signal tx          : std_logic;
  signal rx_sink_s2d : t_eth_st_s2d;
  signal rx_sink_d2s : t_eth_st_d2s;
  signal tx_src_s2d  : t_eth_st_s2d;
  signal tx_src_d2s  : t_eth_st_d2s;
  signal ack_dut     : std_logic;
  signal ns_dut      : std_logic_vector(1 downto 0);

  signal rx_2          : std_logic;
  signal rx_2i         : std_logic;
  signal tx_2          : std_logic;
  signal tx_2o         : std_logic;
  signal rx_2_sink_s2d : t_eth_st_s2d;
  signal rx_2_sink_d2s : t_eth_st_d2s;
  signal tx_2_src_s2d  : t_eth_st_s2d;
  signal tx_2_src_d2s  : t_eth_st_d2s;
  signal ack_dut_2     : std_logic;
  signal ns_dut_2      : std_logic_vector(1 downto 0);

  signal disconnect_bus : std_logic;

  signal can_bus           : std_logic;
  signal trans_fast_rx_rec : CanBusRecType;
  signal trans_fast_tx_rec : CanBusRecType;
  signal trans_norm_rx_rec : CanBusRecType;
  signal trans_norm_tx_rec : CanBusRecType;
  signal trans_slow_rx_rec : CanBusRecType;
  signal trans_slow_tx_rec : CanBusRecType;
  signal valid_delay       : integer := 0;
  signal ready_chance      : integer := 100;

  signal can_reset : std_logic;

  signal dbg_error_flag : std_logic_vector(c_debug_error_flags_width - 1 downto 0);

  shared variable RV : RandomPType;

    
  alias al_fsm_state            is << signal .can_bus_controller_tb.u_dut.u_fsm.fsm_state : t_fsm_can_state >>;
  alias al_sample_rx            is << signal .can_bus_controller_tb.u_dut.sample_rx : std_logic >>;
  alias al_is_transmitter       is << signal .can_bus_controller_tb.u_dut.u_fsm.is_transmitter : std_logic >>;
  alias al_transmit             is << signal .can_bus_controller_tb.u_dut.transmit : std_logic >>;
  alias al_stuff_bit_valid      is << signal .can_bus_controller_tb.u_dut.stuff_bit_valid : std_logic >>;
  alias al_bit_count            is << signal .can_bus_controller_tb.u_dut.u_fsm.bit_count : natural range 0 to c_bus_off_reintegration_count >>;
  alias al_transmit_error_count is << signal .can_bus_controller_tb.u_dut.u_fsm.transmit_error_count : natural range 0 to c_passive_to_bus_off_transition >>;
  alias al_receive_error_count  is << signal .can_bus_controller_tb.u_dut.u_fsm.receive_error_count : natural range 0 to c_active_to_passive_transition >>;
    


begin
  
  
  p_init : process
    variable v_test_id : AlertLogIDType;
  begin
    RV.InitSeed(random_seed);
    SetAlertStopCount(ERROR, 10);

    v_test_id         := NewId("can_bus_controller");
    test_id           <= v_test_id;
    reset_id          <= NewId("Reset at Output", v_test_id);
    gen_id            <= NewId("Generating frame", v_test_id);
    rx_sink_fifo_id   <= NewId("RX fifo", v_test_id);
    tx_src_fifo_id    <= NewId("TX fifo", v_test_id);
    rx_2_sink_fifo_id <= NewId("RX 2 fifo", v_test_id);
    tx_2_src_fifo_id  <= NewId("TX 2 fifo", v_test_id);
    wait for 0 ns;

    SetLogEnable(test_id, INFO, gc_verbose);
    SetLogEnable(gen_id, INFO, gc_verbose);

    wait for 0 ns;

    wait;
  end process;

  ----------------------------------------------------
  -- Clock gen
  ----------------------------------------------------
  clk <= not clk after gc_TbClkPeriod / 2;

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
  u_dut : entity work.can_bus_controller
    generic map(
      gc_bit_rate_hz                => c_bit_rate,
      gc_default_prop_seg_length    => c_prop_seg_length,
      gc_default_phase_seg_1_length => c_phase_seg1_length,
      gc_default_phase_seg_2_length => c_phase_seg2_length,
      gc_sync_jump_width            => c_sync_jump_width
    )
    port map(
      clk_i              => clk,
      reset_i            => reset,
      can_reset_i        => can_reset,
      rx_i               => rx,
      tx_o               => tx,
      src_s2d_o          => rx_sink_s2d,
      src_d2s_i          => rx_sink_d2s,
      sink_s2d_i         => tx_src_s2d,
      sink_d2s_o         => tx_src_d2s,
      ack_o              => ack_dut,
      ns_o               => ns_dut,
      debug_error_flag_o => dbg_error_flag
    );

  u_dut_2 : entity work.can_bus_controller
    generic map(
      gc_bit_rate_hz                => c_bit_rate,
      gc_default_prop_seg_length    => c_prop_seg_length,
      gc_default_phase_seg_1_length => c_phase_seg1_length,
      gc_default_phase_seg_2_length => c_phase_seg2_length,
      gc_sync_jump_width            => c_sync_jump_width
    )
    port map(
      clk_i              => clk,
      reset_i            => reset,
      can_reset_i        => can_reset,
      rx_i               => rx_2i,
      tx_o               => tx_2o,
      src_s2d_o          => rx_2_sink_s2d,
      src_d2s_i          => rx_2_sink_d2s,
      sink_s2d_i         => tx_2_src_s2d,
      sink_d2s_o         => tx_2_src_d2s,
      ack_o              => ack_dut_2,
      ns_o               => ns_dut_2,
      debug_error_flag_o => open
    );

  rx_2i <= rx_2 when disconnect_bus = '0' else tx_2o;
  tx_2  <= tx_2o when disconnect_bus = '0' else '1';

  ----------------------------------------------------
  -- Helper modules
  ----------------------------------------------------
  can_bus <= 'H';
  u_transceiver_dut : entity work.can_bus_transceiver
    port map(
      rx_o       => rx,
      tx_i       => tx,
      can_bus_io => can_bus
    );

  u_transceiver_dut_2 : entity work.can_bus_transceiver
    port map(
      rx_o       => rx_2,
      tx_i       => tx_2,
      can_bus_io => can_bus
    );

  u_can_bus_node_fast : entity work.can_bus_vc
    generic map(
      gc_model_id_name => "Fast can",
      gc_clk_period    => gc_TbClkPeriod,
      gc_clock_delta   => -c_clock_delta
    )
    port map(
      can_bus_io      => can_bus,
      trans_rx_rec_io => trans_fast_rx_rec,
      trans_tx_rec_io => trans_fast_tx_rec
    );

  u_can_bus_node : entity work.can_bus_vc
    generic map(
      gc_model_id_name => "Norm can",
      gc_clk_period    => gc_TbClkPeriod,
      gc_clock_delta   => 0.0
    )
    port map(
      can_bus_io      => can_bus,
      trans_rx_rec_io => trans_norm_rx_rec,
      trans_tx_rec_io => trans_norm_tx_rec
    );

  u_can_bus_node_slow : entity work.can_bus_vc
    generic map(
      gc_model_id_name => "Slow can",
      gc_clk_period    => gc_TbClkPeriod,
      gc_clock_delta   => c_clock_delta
    )
    port map(
      can_bus_io      => can_bus,
      trans_rx_rec_io => trans_slow_rx_rec,
      trans_tx_rec_io => trans_slow_tx_rec
    );
  

  p_src : process(clk)
  begin
    if rising_edge(clk) then
      if reset = '1' then
        rx_sink_d2s <= c_eth_st_d2s_idle;
      else
        if RV.DistBool((100 - ready_chance, ready_chance)) then
          rx_sink_d2s <= c_eth_st_d2s_ready;
        else
          rx_sink_d2s <= c_eth_st_d2s_idle;
        end if;
        if (rx_sink_s2d.valid = '1') and (rx_sink_d2s = c_eth_st_d2s_ready) then
          Check(rx_sink_fifo_id, rx_sink_s2d);
          if rx_sink_s2d.endofpacket = '1' then
            rx_sink_received <= rx_sink_received + 1;
          end if;
        end if;
      end if;
    end if;
  end process;

  p_sink : process
  begin
    tx_src_s2d <= c_eth_st_s2d_zero_idle;
    wait for 0 ns;
    wait for 0 ns;

    loop
      if tx_src_ack >= tx_src_req then
        WaitForToggle(tx_src_req);
        WaitForClock(clk);
      end if;

      while tx_src_s2d.endofpacket = '0' loop
        tx_src_s2d       <= Pop(tx_src_fifo_id);
        wait until rising_edge(clk) and tx_src_d2s.ready = '1';
        tx_src_s2d.valid <= '0';
        tx_src_s2d.data  <= RV.RandSlv(8);
        WaitForClock(clk, RV.RandInt(0, valid_delay));
      end loop;
      Increment(tx_src_ack);
      tx_src_s2d <= c_eth_st_s2d_zero_idle;
      wait for 0 ns;
    end loop;
  end process;

  p_src_2 : process(clk)
  begin
    if rising_edge(clk) then
      if reset = '1' then
        rx_2_sink_d2s <= c_eth_st_d2s_idle;
      else
        if RV.DistBool((100 - ready_chance, ready_chance)) then
          rx_2_sink_d2s <= c_eth_st_d2s_ready;
        else
          rx_2_sink_d2s <= c_eth_st_d2s_idle;
        end if;
        if (rx_2_sink_s2d.valid = '1') and (rx_2_sink_d2s = c_eth_st_d2s_ready) then
          Check(rx_2_sink_fifo_id, rx_2_sink_s2d);
          if rx_2_sink_s2d.endofpacket = '1' then
            rx_2_sink_received <= rx_2_sink_received + 1;
          end if;
        end if;
      end if;
    end if;
  end process;

  p_sink_2 : process
  begin
    tx_2_src_s2d <= c_eth_st_s2d_zero_idle;
    wait for 0 ns;
    wait for 0 ns;

    loop
      if tx_2_src_ack >= tx_2_src_req then
        WaitForToggle(tx_2_src_req);
        WaitForClock(clk);
      end if;

      while tx_2_src_s2d.endofpacket = '0' loop
        tx_2_src_s2d       <= Pop(tx_2_src_fifo_id);
        wait until rising_edge(clk) and tx_2_src_d2s.ready = '1';
        tx_2_src_s2d.valid <= '0';
        tx_2_src_s2d.data  <= RV.RandSlv(8);
        WaitForClock(clk, RV.RandInt(0, valid_delay));
      end loop;
      Increment(tx_2_src_ack);
      tx_2_src_s2d <= c_eth_st_s2d_zero_idle;
      wait for 0 ns;
    end loop;
  end process;

  ----------------------------------------------------
  -- Main test process
  ----------------------------------------------------
  p_main_tester : process
    variable v_ast_frame         : t_slv_array(0 to 14)(7 downto 0);
    variable v_llc_frame         : t_llc_frame;
    variable v_llc_w_frame       : t_llc_frame;                                 -- Will win the arbitration.
    variable v_delay             : time;
    variable v_loop_counter      : integer;
    variable v_error_counter     : integer := 0;
    variable v_exp_error_counter : integer := 0;
    variable v_error_chance      : integer;


    ------------------------------------------------------------------------------------------------------------------
    ------------------------------------------------------------------------------------------------------------------
    procedure gen_frame(
      variable v_frame            : out t_llc_frame;
      constant c_force_extended   :     boolean := false;
      constant c_force_data_frame :     boolean := false
    ) is
      variable v_length : integer;
    begin
      v_frame          := c_llc_frame_idle;
      if c_force_data_frame then
        v_length := RV.RandInt(1, 8);
      else
        v_length := RV.RandInt(0, 8);
      end if;
      v_frame.length   := std_logic_vector(to_unsigned(v_length, 4));
      for i in 0 to v_length - 1 loop
        v_frame.data(i) := RV.RandSlv(8);
      end loop;
      v_frame.id       := RV.RandSlv(29);
      if v_length = 0 then
        v_frame.rtr := '1';
      end if;
      v_frame.extended := '1';
      if (RV.RandBool) and (not c_force_extended) then
        v_frame.id(28 downto 11) := (others => '0');
        v_frame.extended         := '0';
      end if;
    end procedure;

    ------------------------------------------------------------------------------------------------------------------
    -- Will generate a id that makes the v_llc_w_frame win the arbitration rounds
    ------------------------------------------------------------------------------------------------------------------
    procedure find_id_win_arbitration(
      constant c_by_extended : boolean := false
    ) is
      variable random_index : integer;
    begin
      gen_frame(v_llc_frame, c_by_extended);
      gen_frame(v_llc_w_frame, v_llc_frame.extended = '1');
      if not c_by_extended then
        v_llc_w_frame                  := v_llc_frame;
        if v_llc_frame.extended = '1' then
          random_index := RV.RandInt(0, 28);
        else
          random_index := RV.RandInt(0, 10);
        end if;
        v_llc_w_frame.id(random_index) := '0';
        v_llc_frame.id(random_index)   := '1';
      else
        v_llc_w_frame.id(10 downto 0)  := v_llc_frame.id(28 downto 18);         -- Share same id to make it easier
        v_llc_w_frame.extended         := '0';
        v_llc_w_frame.id(28 downto 11) := (others => '0');
      end if;
    end procedure;

    ------------------------------------------------------------------------------------------------------------------
    ------------------------------------------------------------------------------------------------------------------
    procedure frame_2_ast(
      constant c_frame : in t_llc_frame;
      constant c_fifo  : in work.pk_eth_st_scoreboard.ScoreboardIdType
    ) is
      variable v_frame_st : t_eth_st_s2d;
    begin

      -- Construct can_frame array
      v_frame_st.valid         := '1';
      v_frame_st.endofpacket   := '0';
      v_frame_st.startofpacket := '1';
      v_frame_st.data          := "000" & c_frame.id(28 downto 24);
      v_ast_frame(0)           := v_frame_st.data;
      Push(c_fifo, v_frame_st);
      v_frame_st.startofpacket := '0';
      v_frame_st.data          := c_frame.id(23 downto 16);
      v_ast_frame(1)           := v_frame_st.data;
      Push(c_fifo, v_frame_st);
      v_frame_st.data          := c_frame.id(15 downto 8);
      v_ast_frame(2)           := v_frame_st.data;
      Push(c_fifo, v_frame_st);
      v_frame_st.data          := c_frame.id(7 downto 0);
      v_ast_frame(3)           := v_frame_st.data;
      Push(c_fifo, v_frame_st);
      v_frame_st.data          := "0000" & c_frame.length;
      v_ast_frame(4)           := v_frame_st.data;
      Push(c_fifo, v_frame_st);

      for i in 0 to 7 loop
        v_frame_st.data    := c_frame.data(i);
        v_ast_frame(5 + i) := v_frame_st.data;
        Push(c_fifo, v_frame_st);
      end loop;

      v_frame_st.data    := (others => '0');
      v_frame_st.data(0) := c_frame.extended;
      v_ast_frame(13)    := v_frame_st.data;
      Push(c_fifo, v_frame_st);

      v_frame_st.data        := (others => '0');
      v_frame_st.data(0)     := c_frame.rtr;
      v_ast_frame(14)        := v_frame_st.data;
      v_frame_st.endofpacket := '1';
      Push(c_fifo, v_frame_st);
    end procedure;

    ------------------------------------------------------------------------------------------------------------------
    ------------------------------------------------------------------------------------------------------------------
    procedure prepare_frame_and_model is
    begin
      -- Generate a random CAN frame
      gen_frame(v_llc_frame);

      -- Set randomized model behavior parameters
      ready_chance <= RV.RandInt(40, 100);
      valid_delay  <= RV.RandInt(0, 10);
      v_delay      := RV.RandInt(1, 100) * 1 us;
      SetModelOptions(trans_fast_tx_rec, DELAY_OP, v_delay);
      SetModelOptions(trans_slow_tx_rec, DELAY_OP, v_delay);
      SetModelOptions(trans_norm_tx_rec, DELAY_OP, v_delay);
    end procedure;

    ------------------------------------------------------------------------------------------------------------------
    ------------------------------------------------------------------------------------------------------------------
    procedure normal_operation_rx_0 is
    begin
      -- Generate frame and set random model parameters
      prepare_frame_and_model;

      Log(gen_id, "Receiving normal frame", INFO);

      -- Push frame to source fifo and send frame from VC
      frame_2_ast(v_llc_frame, rx_sink_fifo_id);
      Increment(rx_sink_expected);
      Send(trans_fast_tx_rec, v_llc_frame, gc_verbose);

      -- Wait for frame to arrive at DUT
      if rx_sink_expected /= rx_sink_received then
        wait until rx_sink_expected = rx_sink_received for 1 ms;
      end if;
      AffirmIf(test_id, dbg_error_flag = c_debug_error_no_error, "Stuffing error is " & to_hstring(dbg_error_flag), "but there was");
      AffirmIf(test_id, rx_sink_expected = rx_sink_received, "sink_expected = " & integer'image(rx_sink_expected) & ", but sink_received = " & integer'image(rx_sink_received), "Expected frame not received at sink");

      -- checking and emptying the other can bus node receive queue.
      Check(trans_norm_rx_rec, v_llc_frame, gc_verbose);
      Check(trans_slow_rx_rec, v_llc_frame, gc_verbose);
      WaitForTransaction(trans_fast_tx_rec);
    end procedure;

    ------------------------------------------------------------------------------------------------------------------
    ------------------------------------------------------------------------------------------------------------------
    procedure normal_operation_rx_1 is
    begin
      -- Generate frame and set random model parameters
      prepare_frame_and_model;

      Log(gen_id, "Receiving normal frame", INFO);

      -- Push frame to source fifo and send frame from VC
      frame_2_ast(v_llc_frame, rx_sink_fifo_id);
      Increment(rx_sink_expected);
      Send(trans_norm_tx_rec, v_llc_frame, gc_verbose);

      -- Wait for frame to arrive at DUT
      if rx_sink_expected /= rx_sink_received then
        wait until rx_sink_expected = rx_sink_received for 1 ms;
      end if;
      AffirmIf(test_id, dbg_error_flag = c_debug_error_no_error, "Stuffing error is " & to_hstring(dbg_error_flag), "but there was");
      AffirmIf(test_id, rx_sink_expected = rx_sink_received, "sink_expected = " & integer'image(rx_sink_expected) & ", but sink_received = " & integer'image(rx_sink_received), "Expected frame not received at sink");

      -- checking and emptying the other can bus node receive queue.
      Check(trans_fast_rx_rec, v_llc_frame, gc_verbose);
      Check(trans_slow_rx_rec, v_llc_frame, gc_verbose);
      WaitForTransaction(trans_norm_tx_rec);
    end procedure;

    ------------------------------------------------------------------------------------------------------------------
    ------------------------------------------------------------------------------------------------------------------
    procedure normal_operation_tx is
    begin
      -- Generate frame and set random model parameters
      prepare_frame_and_model;

      Log(gen_id, "Sending normal frame", INFO);

      -- send a frame from the dut to the vc's
      frame_2_ast(v_llc_frame, tx_src_fifo_id);
      Increment(tx_src_req);
      wait for 0 ns;
      wait until tx_src_req = tx_src_ack;

      -- Check arrival of frame at the other nodes
      Check(trans_fast_rx_rec, v_llc_frame, gc_verbose);
      Check(trans_norm_rx_rec, v_llc_frame, gc_verbose);
      Check(trans_slow_rx_rec, v_llc_frame, gc_verbose);
    end procedure;

    ------------------------------------------------------------------------------------------------------------------
    ------------------------------------------------------------------------------------------------------------------
    procedure normal_operation is
    begin
      if RV.RandBool then
        normal_operation_rx_0;
      else
        normal_operation_rx_1;
      end if;
      normal_operation_tx;
    end procedure;

    ------------------------------------------------------------------------------------------------------------------
    ------------------------------------------------------------------------------------------------------------------
    procedure stuff_error_test is
    begin
      SetModelOptions(trans_fast_rx_rec, DISABLE_RX_OP, true);
      -- Generate frame and set random model parameters
      prepare_frame_and_model;

      Log(gen_id, "Sending stuff error frame", INFO);
      -- Make sure the frame needs bit stuffing
      if v_llc_frame.rtr = '1' then
        v_llc_frame.id(4 downto 0) := (others => '1');
      else
        v_llc_frame.data(0)(4 downto 0) := (others => '1');
      end if;

      -- Send frame and wait for dbg error flag at DUT
      SendAsync(trans_fast_tx_rec, v_llc_frame, c_can_bus_bit_stuffing_error, gc_verbose);

      wait until dbg_error_flag(c_debug_error_stuff_bit) = '1' for 1 ms;
      AffirmIf(test_id, dbg_error_flag(c_debug_error_stuff_bit) = '1', "Stuffing error is " & std_logic'image(dbg_error_flag(c_debug_error_stuff_bit)), "but it should have been '1'.");

      -- Check that the receiving VC node got a stuff error
      Check(trans_norm_rx_rec, v_llc_frame, c_can_bus_bit_stuffing_error, gc_verbose);
      Check(trans_slow_rx_rec, v_llc_frame, c_can_bus_bit_stuffing_error, gc_verbose);

      WaitForTransaction(trans_fast_tx_rec);
      wait for 100 us;
      SetModelOptions(trans_fast_rx_rec, DISABLE_RX_OP, false);
    end procedure;

    ------------------------------------------------------------------------------------------------------------------
    ------------------------------------------------------------------------------------------------------------------
    procedure crc_error_test is
    begin
      SetModelOptions(trans_fast_rx_rec, DISABLE_RX_OP, true);
      -- Generate frame and set random model parameters
      prepare_frame_and_model;

      Log(gen_id, "Sending crc error frame", INFO);

      -- Send frame and wait for dbg error flag at DUT
      SendAsync(trans_fast_tx_rec, v_llc_frame, c_can_bus_crc_error, gc_verbose);

      wait until dbg_error_flag(c_debug_error_crc) = '1' for 1 ms;
      AffirmIf(test_id, dbg_error_flag(c_debug_error_crc) = '1', "crc error is " & std_logic'image(dbg_error_flag(c_debug_error_crc)), "but it should have been '1'.");

      -- Check that the receiving VC node got a crc error
      WaitForTransaction(trans_norm_rx_rec);
      Check(trans_norm_rx_rec, v_llc_frame, c_can_bus_crc_error, gc_verbose);
      Check(trans_slow_rx_rec, v_llc_frame, c_can_bus_crc_error, gc_verbose);

      WaitForTransaction(trans_fast_tx_rec);
      wait for 100 us;
      SetModelOptions(trans_fast_rx_rec, DISABLE_RX_OP, false);
    end procedure;

    ------------------------------------------------------------------------------------------------------------------
    ------------------------------------------------------------------------------------------------------------------
    procedure crc_stuff_error_test is
    begin
      SetModelOptions(trans_fast_rx_rec, DISABLE_RX_OP, true);
      -- Generate frame and set random model parameters
      prepare_frame_and_model;
      v_llc_frame := c_stuff_bit_in_only_crc;

      Log(gen_id, "Sending Stuffing error crc error frame", INFO);

      -- Send frame and wait for dbg error flag at DUT
      SendAsync(trans_fast_tx_rec, v_llc_frame, c_can_bus_bit_stuffing_error, gc_verbose);

      wait until dbg_error_flag(c_debug_error_stuff_bit) = '1' for 1 ms;
      AffirmIf(test_id, dbg_error_flag(c_debug_error_stuff_bit) = '1', "stuff bit error is " & std_logic'image(dbg_error_flag(c_debug_error_stuff_bit)), "but it should have been '1'.");

      -- Check that the receiving VC node got a crc error
      WaitForTransaction(trans_norm_rx_rec);
      Check(trans_norm_rx_rec, v_llc_frame, c_can_bus_bit_stuffing_error, gc_verbose);
      Check(trans_slow_rx_rec, v_llc_frame, c_can_bus_bit_stuffing_error, gc_verbose);

      WaitForTransaction(trans_fast_tx_rec);
      wait for 100 us;
      SetModelOptions(trans_fast_rx_rec, DISABLE_RX_OP, false);
    end procedure;

    ------------------------------------------------------------------------------------------------------------------
    ------------------------------------------------------------------------------------------------------------------
    procedure crc_delimiter_error_test is
    begin
      SetModelOptions(trans_fast_rx_rec, DISABLE_RX_OP, true);
      -- Generate frame and set random model parameters
      prepare_frame_and_model;

      Log(gen_id, "Sending crc delimiter error frame", INFO);

      -- Send frame and wait for dbg error flag at DUT
      SendAsync(trans_fast_tx_rec, v_llc_frame, c_can_bus_crc_delimiter_error, gc_verbose);

      wait until dbg_error_flag(c_debug_error_crc) = '1' for 1 ms;
      AffirmIf(test_id, dbg_error_flag(c_debug_error_crc) = '1', "crc error is " & std_logic'image(dbg_error_flag(c_debug_error_crc)), "but it should have been '1'.");

      -- Check that the receiving VC node got a crc error
      WaitForTransaction(trans_norm_rx_rec);
      Check(trans_norm_rx_rec, v_llc_frame, c_can_bus_crc_delimiter_error, gc_verbose);
      Check(trans_slow_rx_rec, v_llc_frame, c_can_bus_crc_delimiter_error, gc_verbose);

      WaitForTransaction(trans_fast_tx_rec);
      wait for 100 us;
      SetModelOptions(trans_fast_rx_rec, DISABLE_RX_OP, false);
    end procedure;

    ------------------------------------------------------------------------------------------------------------------
    ------------------------------------------------------------------------------------------------------------------
    procedure win_arb(
      constant c_by_extended : boolean := false
    ) is
    begin
      SetModelOptions(trans_norm_rx_rec, DISABLE_RX_OP, true);
      find_id_win_arbitration(c_by_extended);

      Log(gen_id, "DUT Wins arbitration", INFO);

      SendAsync(trans_norm_tx_rec, v_llc_frame, c_can_bus_arbitration_error);
      frame_2_ast(v_llc_w_frame, tx_src_fifo_id);
      Increment(tx_src_req);
      wait for 0 ns;
      wait until tx_src_req = tx_src_ack;

      Check(trans_slow_rx_rec, v_llc_w_frame);
      Check(trans_fast_rx_rec, v_llc_w_frame);
      WaitForTransaction(trans_norm_tx_rec);
      wait for 100 us;
      SetModelOptions(trans_norm_rx_rec, DISABLE_RX_OP, false);
    end procedure;

    ------------------------------------------------------------------------------------------------------------------
    ------------------------------------------------------------------------------------------------------------------
    procedure loss_arb(
      constant c_by_extended : boolean := false
    ) is
    begin
      SetModelOptions(trans_norm_rx_rec, DISABLE_RX_OP, true);
      find_id_win_arbitration(c_by_extended);

      Log(gen_id, "DUT Losses arbitration", INFO);

      SendAsync(trans_norm_tx_rec, v_llc_w_frame, c_can_bus_arbitration_error);
      frame_2_ast(v_llc_frame, tx_src_fifo_id);
      frame_2_ast(v_llc_w_frame, rx_sink_fifo_id);
      Increment(rx_sink_expected);
      Increment(tx_src_req);
      wait for 0 ns;
      wait until tx_src_req = tx_src_ack;

      Check(trans_slow_rx_rec, v_llc_w_frame);
      Check(trans_fast_rx_rec, v_llc_w_frame);
      AffirmIf(test_id, rx_sink_received = rx_sink_expected, "Have received: " & integer'image(rx_sink_received) & " frames", "Expected: " & integer'image(rx_sink_expected) & " frames");
      Check(trans_fast_rx_rec, v_llc_frame);
      Check(trans_slow_rx_rec, v_llc_frame);

      WaitForTransaction(trans_norm_tx_rec);
      wait for 100 us;
      SetModelOptions(trans_norm_rx_rec, DISABLE_RX_OP, false);
    end procedure;

  begin
    reset          <= '0';
    can_reset      <= '0';
    disconnect_bus <= '1';
    wait for 0 ns;
    wait for 0 ns;
    WaitForClock(clk, 1);

    Message("################################################################################");
    Message("Output at Reset");
    Message("################################################################################");
    reset <= '1';
    WaitForClock(clk, 200);
    AffirmIf(reset_id, tx = '1', "tx ", " was incorrect");
    AffirmIf(reset_id, rx_sink_s2d = c_eth_st_s2d_zero_idle, "src_s2d ", " was incorrect");
    AffirmIf(reset_id, tx_src_d2s = c_eth_st_d2s_idle, "sink_d2s ", " was incorrect");
    AffirmIf(reset_id, ack_dut = '0', "ack_dut ", " was incorrect");
    AffirmIf(reset_id, ns_dut = c_error_activate_ns, "ns_dut ", " was incorrect");

    reset <= '0';
    Message("################################################################################");
    Message("TEST Start");
    Message("################################################################################");

    -- Set model options. Bit rate and phase segment lengths must be the same for all nodes on the bus
    SetModelOptions(trans_fast_tx_rec, BIT_RATE_OP, c_bit_rate);
    SetModelOptions(trans_fast_rx_rec, BIT_RATE_OP, c_bit_rate);
    SetModelOptions(trans_fast_tx_rec, PHASE_SEG_1_OP, c_model_phase_seg1_length);
    SetModelOptions(trans_fast_tx_rec, PHASE_SEG_2_OP, c_model_phase_seg2_length);
    SetModelOptions(trans_fast_tx_rec, PROP_SEG_OP, c_model_prop_seg_length);
    SetModelOptions(trans_fast_rx_rec, PHASE_SEG_1_OP, c_model_phase_seg1_length);
    SetModelOptions(trans_fast_rx_rec, PHASE_SEG_2_OP, c_model_phase_seg2_length);
    SetModelOptions(trans_fast_rx_rec, PROP_SEG_OP, c_model_prop_seg_length);

    SetModelOptions(trans_norm_tx_rec, BIT_RATE_OP, c_bit_rate);
    SetModelOptions(trans_norm_rx_rec, BIT_RATE_OP, c_bit_rate);
    SetModelOptions(trans_norm_tx_rec, PHASE_SEG_1_OP, c_model_phase_seg1_length);
    SetModelOptions(trans_norm_tx_rec, PHASE_SEG_2_OP, c_model_phase_seg2_length);
    SetModelOptions(trans_norm_tx_rec, PROP_SEG_OP, c_model_prop_seg_length);
    SetModelOptions(trans_norm_rx_rec, PHASE_SEG_1_OP, c_model_phase_seg1_length);
    SetModelOptions(trans_norm_rx_rec, PHASE_SEG_2_OP, c_model_phase_seg2_length);
    SetModelOptions(trans_norm_rx_rec, PROP_SEG_OP, c_model_prop_seg_length);

    SetModelOptions(trans_slow_tx_rec, BIT_RATE_OP, c_bit_rate);
    SetModelOptions(trans_slow_rx_rec, BIT_RATE_OP, c_bit_rate);
    SetModelOptions(trans_slow_tx_rec, PHASE_SEG_1_OP, c_slow_phase_seg1_length);
    SetModelOptions(trans_slow_tx_rec, PHASE_SEG_2_OP, c_slow_phase_seg2_length);
    SetModelOptions(trans_slow_tx_rec, PROP_SEG_OP, c_model_prop_seg_length);
    SetModelOptions(trans_slow_rx_rec, PHASE_SEG_1_OP, c_slow_phase_seg1_length);
    SetModelOptions(trans_slow_rx_rec, PHASE_SEG_2_OP, c_slow_phase_seg2_length);
    SetModelOptions(trans_slow_rx_rec, PROP_SEG_OP, c_model_prop_seg_length);

    Message("###############################");
    Message("Startup");
    Message("###############################");
    normal_operation_tx;                                                        -- This will let the dut start up in its own tempo

    Message("###############################");
    Message("Normal operation");
    Message("###############################");
    for i in 0 to 3 loop
      normal_operation;
    end loop;

    Message("###############################");
    Message("Stuffing error");
    Message("###############################");
    v_error_counter := 0;
    for i in 0 to 5 loop
      v_error_counter := v_error_counter + 1;
      stuff_error_test;
    end loop;

    Message("###############################");
    Message("CRC error");
    Message("###############################");
    for i in 0 to 5 loop
      v_error_counter := v_error_counter + 1;
      crc_error_test;
    end loop;

    Message("###############################");
    Message("CRC delimiter error");
    Message("###############################");
    for i in 0 to 5 loop
      v_error_counter := v_error_counter + 1;
      crc_delimiter_error_test;
    end loop;

    Message("###############################");
    Message("Stuffing error in crc");
    Message("###############################");
    v_error_counter := v_error_counter + 1;
    crc_stuff_error_test;

    Message("###############################");
    Message("Arbitration won");
    Message("###############################");
    for i in 0 to 5 loop
      win_arb;
      win_arb(true);
    end loop;

    Message("###############################");
    Message("Arbitration lost");
    Message("###############################");
    for i in 0 to 5 loop
      loss_arb;
      loss_arb(true);
    end loop;

    Message("###############################");
    Message("Random");
    Message("###############################");
    for i in 0 to 200 loop
      v_error_chance := 2;
      if v_error_counter > c_active_to_passive_transition / 2 then
        v_error_chance := 0;
      end if;
      case RV.DistInt((v_error_chance, v_error_chance, v_error_chance, 2, 1, 10)) is
        when 0 =>
          v_error_counter := v_error_counter + 1;
          crc_error_test;
        when 1 =>
          v_error_counter := v_error_counter + 1;
          stuff_error_test;
        when 2 =>
          v_error_counter := v_error_counter + 1;
          crc_delimiter_error_test;
        when 3 =>
          win_arb(RV.RandBool);
        when 4 =>
          loss_arb(RV.RandBool);
        when others =>
          if v_error_counter > 0 then
            v_error_counter := v_error_counter - 1;
          end if;
          normal_operation;
      end case;
    end loop;

    Message("###############################");
    Message("Only stuffing error frames");
    Message("###############################");
    -- Removing all the sending errors from the state machine.
    for i in 0 to v_error_counter * 2 + 5 loop
      normal_operation_rx_0;
    end loop;

    v_loop_counter := 0;
    while (ns_dut = c_error_activate_ns) and (v_loop_counter < (c_active_to_passive_transition + 10)) loop
      stuff_error_test;
      v_loop_counter := v_loop_counter + 1;
    end loop;
    AffirmIf(test_id, ns_dut = c_error_passive_ns, "The module should be in error passive", "however it was not");
    AffirmIf(test_id, v_loop_counter = c_active_to_passive_transition, "The module is in passive after " & integer'image(v_loop_counter) & " errors", "however should have been after " & integer'image(c_active_to_passive_transition) & " errors");

    stuff_error_test;
    AffirmIf(test_id, ns_dut = c_error_passive_ns, "The module should be in error passive", "however it was not");

    normal_operation_rx_0;
    AffirmIf(test_id, ns_dut = c_error_activate_ns, "The module should be in error activate", "but was not");
    stuff_error_test;
    AffirmIf(test_id, ns_dut = c_error_passive_ns, "The module should be in error passive", "however it was not");
    for i in 0 to c_active_to_passive_transition - 1 loop
      normal_operation_rx_0;
      AffirmIf(test_id, ns_dut = c_error_activate_ns, "The module should be in error activate", "but was not");
    end loop;
    stuff_error_test;
    AffirmIf(test_id, ns_dut = c_error_activate_ns, "The module should be in error activate", "but was not");
    for i in 0 to 5 loop                                                        -- 6 normal mode after the test
      normal_operation_rx_0;
    end loop;

    Message("###############################");
    Message("Only CRC error frames");
    Message("###############################");
    v_loop_counter := 0;
    while (ns_dut = c_error_activate_ns) and (v_loop_counter < (c_active_to_passive_transition + 10)) loop
      crc_error_test;
      v_loop_counter := v_loop_counter + 1;
    end loop;
    AffirmIf(test_id, ns_dut = c_error_passive_ns, "The module should be in error passive", "however it was not");
    AffirmIf(test_id, v_loop_counter = c_active_to_passive_transition, "The module is in passive after " & integer'image(v_loop_counter) & " errors", "however should have been after " & integer'image(c_active_to_passive_transition) & " errors");

    normal_operation_rx_1;
    AffirmIf(test_id, ns_dut = c_error_activate_ns, "The module should be in error activate", "but was not");
    crc_error_test;
    AffirmIf(test_id, ns_dut = c_error_passive_ns, "The module should be in error passive", "however it was not");
    for i in 0 to c_active_to_passive_transition - 1 loop
      normal_operation_rx_1;
      AffirmIf(test_id, ns_dut = c_error_activate_ns, "The module should be in error activate", "but was not");
    end loop;
    crc_error_test;
    AffirmIf(test_id, ns_dut = c_error_activate_ns, "The module should be in error activate", "but was not");
    for i in 0 to 5 loop                                                        -- 6 normal mode after the test
      normal_operation_rx_1;
    end loop;

    
    Message("###############################");
    Message("Testing no response on transmission");
    Message("###############################");
    SetModelOptions(trans_norm_rx_rec, DISABLE_RX_OP, true);
    SetModelOptions(trans_slow_rx_rec, DISABLE_RX_OP, true);
    SetModelOptions(trans_fast_rx_rec, NACK_PACKAGES_OP, true);

    gen_frame(v_llc_frame);
    frame_2_ast(v_llc_frame, tx_src_fifo_id);
    Increment(tx_src_req);
    wait for 0 ns;
    wait until tx_src_req = tx_src_ack;

    for i in 0 to (c_active_to_passive_transition / 8) - 2 loop
      -- Check arrival of frame at the other nodes
      Get(trans_fast_rx_rec, v_llc_frame, gc_verbose);
      AffirmIf(test_id, ns_dut = c_error_activate_ns, "The module should be in error activate", "but was not");
    end loop;
    for i in 0 to ((c_passive_to_bus_off_transition - c_active_to_passive_transition) / 8) loop
      Get(trans_fast_rx_rec, v_llc_frame, gc_verbose);
      AffirmIf(test_id, ns_dut = c_error_passive_ns, "The module should be in error passive", "however it was not");
    end loop;

    Message(" - Edge case: Ack error, another node sends an active flag - 8.1.4.2.c.ex1"); -- It should count the error count up with 8.
    wait until al_fsm_state = s_error_frame;
    wait until al_transmit = '0';
    rx                  <= force '0';
    v_exp_error_counter := al_transmit_error_count;
    AffirmIf(test_id, v_exp_error_counter = al_transmit_error_count, "Error count: " & integer'image(al_transmit_error_count), "/= " & integer'image(v_exp_error_counter));
    v_exp_error_counter := v_exp_error_counter + 8;
    for i in 0 to 5 loop
      wait until al_sample_rx = '1';
      WaitForClock(clk, 3);
      AffirmIf(test_id, v_exp_error_counter = al_transmit_error_count, "Error count: " & integer'image(al_transmit_error_count), "/= " & integer'image(v_exp_error_counter));
    end loop;
    rx                  <= release;

    Get(trans_fast_rx_rec, v_llc_frame, gc_verbose);
    SetModelOptions(trans_fast_rx_rec, NACK_PACKAGES_OP, false);

    Message(" - Recover");
    wait until ack_dut = '1' for 5 ms;
    AffirmIf(test_id, ack_dut = '1', "Ack is " & std_logic'image(ack_dut), "Expected it to be '1'");
    Check(trans_fast_rx_rec, v_llc_frame, gc_verbose);

    SetModelOptions(trans_norm_rx_rec, DISABLE_RX_OP, false);
    SetModelOptions(trans_slow_rx_rec, DISABLE_RX_OP, false);

    for i in 0 to c_active_to_passive_transition + 16 loop
      normal_operation_tx;
    end loop;
    AffirmIf(test_id, ns_dut = c_error_activate_ns, "The module should be in error activate", "but was not");
    

    Message("###############################");
    Message("Error in transmission needs to get to bus off");
    Message("###############################");

    SetModelOptions(trans_slow_rx_rec, DISABLE_RX_OP, true);
    SetModelOptions(trans_norm_rx_rec, DISABLE_RX_OP, true);
    SetModelOptions(trans_fast_rx_rec, ERROR_IN_FRAME_AS_RECEIVER_OP, true);

    gen_frame(v_llc_frame);
    frame_2_ast(v_llc_frame, tx_src_fifo_id);
    Increment(tx_src_req);
    wait for 0 ns;
    wait until tx_src_req = tx_src_ack;

    for i in 0 to (c_active_to_passive_transition / 8) - 2 loop
      -- Check arrival of frame at the other nodes
      Get(trans_fast_rx_rec, v_llc_frame, gc_verbose);
      AffirmIf(test_id, ns_dut = c_error_activate_ns, "The module should be in error activate. " & integer'image(i), "but was not");
    end loop;
    Get(trans_fast_rx_rec, v_llc_frame, gc_verbose);
    AffirmIf(test_id, ns_dut = c_error_passive_ns, "The module should be in error passive", "however it was not");

    for i in 0 to ((c_passive_to_bus_off_transition - c_active_to_passive_transition) / 8) - 2 loop
      -- Check arrival of frame at the other nodes
      Get(trans_fast_rx_rec, v_llc_frame, gc_verbose);
      AffirmIf(test_id, ns_dut = c_error_passive_ns, "The module should be in error passive", "however it was not");
    end loop;
    Get(trans_fast_rx_rec, v_llc_frame, gc_verbose);
    AffirmIf(test_id, ns_dut = c_bus_off_ns, "The module should be in bus off", "however it was not");

    SetModelOptions(trans_slow_rx_rec, DISABLE_RX_OP, false);
    SetModelOptions(trans_norm_rx_rec, DISABLE_RX_OP, false);
    SetModelOptions(trans_fast_rx_rec, ERROR_IN_FRAME_AS_RECEIVER_OP, false);

    Message("No signals from the dut");

    gen_frame(v_llc_frame);
    Send(trans_norm_tx_rec, v_llc_frame, gc_verbose);
    Check(trans_fast_rx_rec, v_llc_frame, gc_verbose);
    Check(trans_slow_rx_rec, v_llc_frame, gc_verbose);

    wait for 100 us;                                                            -- Nothing should come from the dut.

    Message("Recovery");
    WaitForClock(clk, 1);
    can_reset <= '1';
    WaitForClock(clk, 1);
    can_reset <= '0';

    WaitForClock(clk, 100);
    Message("Interrupted while in bus re-integration");

    Send(trans_norm_tx_rec, v_llc_frame, gc_verbose);
    Check(trans_fast_rx_rec, v_llc_frame, gc_verbose);
    Check(trans_slow_rx_rec, v_llc_frame, gc_verbose);

    normal_operation_tx;



    Message("###############################");
    Message("Edge case: Start Receiving in:");
    Message("###############################");
    SetModelOptions(trans_norm_rx_rec, DISABLE_RX_OP, true);
    SetModelOptions(trans_slow_rx_rec, DISABLE_RX_OP, true);

    -------------------------------------------------------------------------------------------
    -------------------------------------------------------------------------------------------
    Message(" - Intermission");
    -- Normal frame first
    gen_frame(v_llc_frame);
    frame_2_ast(v_llc_frame, tx_src_fifo_id);
    Increment(tx_src_req);
    wait for 0 ns;
    wait until tx_src_req = tx_src_ack;

    
    wait until al_fsm_state = s_intermission;
    wait until al_bit_count = 3;
    SetModelOptions(trans_norm_rx_rec, DISABLE_RX_OP, false);
    SetModelOptions(trans_slow_rx_rec, DISABLE_RX_OP, false);
    SetModelOptions(trans_fast_rx_rec, DISABLE_RX_OP, true);                    -- It will not end it self, before the next message starts.

    gen_frame(v_llc_w_frame);
    frame_2_ast(v_llc_w_frame, rx_sink_fifo_id);
    Send(trans_fast_tx_rec, v_llc_w_frame);
    Increment(rx_sink_expected);

    Check(trans_fast_rx_rec, v_llc_frame, gc_verbose);
    Check(trans_norm_rx_rec, v_llc_w_frame, gc_verbose);
    Check(trans_slow_rx_rec, v_llc_w_frame, gc_verbose);

    SetModelOptions(trans_fast_rx_rec, DISABLE_RX_OP, false);

    -------------------------------------------------------------------------------------------
    -------------------------------------------------------------------------------------------
    Message(" - Suspended");
    SetModelOptions(trans_fast_rx_rec, DISABLE_RX_OP, true);
    SetModelOptions(trans_norm_rx_rec, DISABLE_RX_OP, true);
    SetModelOptions(trans_slow_rx_rec, DISABLE_RX_OP, true);
    -- Normal frame first
    gen_frame(v_llc_frame);
    frame_2_ast(v_llc_frame, tx_src_fifo_id);
    Increment(tx_src_req);
    wait for 0 ns;
    wait until tx_src_req = tx_src_ack;
    -- It needs to fail and go to suspended mode.
    -- When it is in suspended mode, it must start receiving as normal.

    wait until al_fsm_state = s_suspend_transmission;
    wait until al_bit_count = 3;
    SetModelOptions(trans_norm_rx_rec, DISABLE_RX_OP, false);
    SetModelOptions(trans_slow_rx_rec, DISABLE_RX_OP, false);
    SetModelOptions(trans_fast_rx_rec, DISABLE_RX_OP, false);

    gen_frame(v_llc_w_frame);
    frame_2_ast(v_llc_w_frame, rx_sink_fifo_id);
    Send(trans_fast_tx_rec, v_llc_w_frame);
    Increment(rx_sink_expected);

    Check(trans_norm_rx_rec, v_llc_w_frame, gc_verbose);
    Check(trans_slow_rx_rec, v_llc_w_frame, gc_verbose);
    Check(trans_fast_rx_rec, v_llc_frame, gc_verbose);
    Check(trans_norm_rx_rec, v_llc_frame, gc_verbose);
    Check(trans_slow_rx_rec, v_llc_frame, gc_verbose);

    Message("###############################");
    Message("Edge case: Incorrect bus in:");
    Message("###############################");
    -------------------------------------------------------------------------------------------
    -------------------------------------------------------------------------------------------
    Message(" - Idle");
    -- Generate frame and set random model parameters
    gen_frame(v_llc_frame);
    v_exp_error_counter := al_transmit_error_count + 8;

    -- send a frame from the dut to the vc's
    frame_2_ast(v_llc_frame, tx_src_fifo_id);
    Increment(tx_src_req);
    wait for 0 ns;
    wait until tx_src_req = tx_src_ack;

    wait until al_is_transmitter = '1';
    rx <= force not tx;

    wait until al_sample_rx = '1';
    WaitForClock(clk, 3);
    rx <= release;

    Check(trans_fast_rx_rec, v_llc_frame, c_can_bus_bit_stuffing_error, gc_verbose);
    Check(trans_norm_rx_rec, v_llc_frame, c_can_bus_bit_stuffing_error, gc_verbose);
    Check(trans_slow_rx_rec, v_llc_frame, c_can_bus_bit_stuffing_error, gc_verbose);
    AffirmIf(test_id, v_exp_error_counter = al_transmit_error_count, "Error count: " & integer'image(al_transmit_error_count), "/= " & integer'image(v_exp_error_counter));
    v_exp_error_counter := al_transmit_error_count - 1;
    Check(trans_fast_rx_rec, v_llc_frame, gc_verbose);
    Check(trans_norm_rx_rec, v_llc_frame, gc_verbose);
    Check(trans_slow_rx_rec, v_llc_frame, gc_verbose);

    AffirmIf(test_id, v_exp_error_counter = al_transmit_error_count, "Error count: " & integer'image(al_transmit_error_count), "/= " & integer'image(v_exp_error_counter));

    -------------------------------------------------------------------------------------------
    -------------------------------------------------------------------------------------------
    Message(" - Arbitration - 8.1.4.2.c.ex2");
    gen_frame(v_llc_frame);
    v_llc_frame.id       := (others => '0');
    v_llc_frame.extended := '1';
    v_exp_error_counter  := al_transmit_error_count;

    -- send a frame from the dut to the vc's
    frame_2_ast(v_llc_frame, tx_src_fifo_id);
    Increment(tx_src_req);
    wait for 0 ns;
    wait until tx_src_req = tx_src_ack;

    wait until al_fsm_state = s_arbitration;
    wait until al_stuff_bit_valid = '1';
    wait until al_transmit = '0';
    rx <= force '0';

    wait until al_sample_rx = '1';
    WaitForClock(clk, 3);
    rx <= release;

    Check(trans_fast_rx_rec, v_llc_frame, c_can_bus_bit_stuffing_error, gc_verbose);
    Check(trans_norm_rx_rec, v_llc_frame, c_can_bus_bit_stuffing_error, gc_verbose);
    Check(trans_slow_rx_rec, v_llc_frame, c_can_bus_bit_stuffing_error, gc_verbose);
    AffirmIf(test_id, v_exp_error_counter = al_transmit_error_count, "Error count: " & integer'image(al_transmit_error_count), "/= " & integer'image(v_exp_error_counter));
    v_exp_error_counter := al_transmit_error_count - 1;
    Check(trans_fast_rx_rec, v_llc_frame, gc_verbose);
    Check(trans_norm_rx_rec, v_llc_frame, gc_verbose);
    Check(trans_slow_rx_rec, v_llc_frame, gc_verbose);
    AffirmIf(test_id, v_exp_error_counter = al_transmit_error_count, "Error count: " & integer'image(al_transmit_error_count), "/= " & integer'image(v_exp_error_counter));


    -------------------------------------------------------------------------------------------
    -------------------------------------------------------------------------------------------
    Message(" - Control");
    -- Generate frame and set random model parameters
    gen_frame(v_llc_frame);

    v_exp_error_counter := al_transmit_error_count + 8;

    -- send a frame from the dut to the vc's
    frame_2_ast(v_llc_frame, tx_src_fifo_id);
    Increment(tx_src_req);
    wait for 0 ns;
    wait until tx_src_req = tx_src_ack;

    wait until al_fsm_state = s_control;
    wait until al_transmit = '0';
    if al_stuff_bit_valid = '1' then
      wait until al_transmit = '0';
    end if;
    rx <= force not tx;

    wait until al_sample_rx = '1';
    WaitForClock(clk, 3);
    rx <= release;

    Check(trans_fast_rx_rec, v_llc_frame, c_can_bus_bit_stuffing_error, gc_verbose);
    Check(trans_norm_rx_rec, v_llc_frame, c_can_bus_bit_stuffing_error, gc_verbose);
    Check(trans_slow_rx_rec, v_llc_frame, c_can_bus_bit_stuffing_error, gc_verbose);
    AffirmIf(test_id, v_exp_error_counter = al_transmit_error_count, "Error count: " & integer'image(al_transmit_error_count), "/= " & integer'image(v_exp_error_counter));
    v_exp_error_counter := al_transmit_error_count - 1;
    Check(trans_fast_rx_rec, v_llc_frame, gc_verbose);
    Check(trans_norm_rx_rec, v_llc_frame, gc_verbose);
    Check(trans_slow_rx_rec, v_llc_frame, gc_verbose);

    AffirmIf(test_id, v_exp_error_counter = al_transmit_error_count, "Error count: " & integer'image(al_transmit_error_count), "/= " & integer'image(v_exp_error_counter));

    -------------------------------------------------------------------------------------------
    -------------------------------------------------------------------------------------------
    Message(" - Data");
    -- Generate frame and set random model parameters
    gen_frame(v_llc_frame, c_force_data_frame => true);
    v_exp_error_counter := al_transmit_error_count + 8;

    -- send a frame from the dut to the vc's
    frame_2_ast(v_llc_frame, tx_src_fifo_id);
    Increment(tx_src_req);
    wait for 0 ns;
    wait until tx_src_req = tx_src_ack;

    wait until al_fsm_state = s_data;
    wait until al_transmit = '0';
    if al_stuff_bit_valid = '1' then
      wait until al_transmit = '0';
    end if;
    rx <= force not tx;

    wait until al_sample_rx = '1';
    WaitForClock(clk, 3);
    rx <= release;

    Check(trans_fast_rx_rec, v_llc_frame, c_can_bus_bit_stuffing_error, gc_verbose);
    Check(trans_norm_rx_rec, v_llc_frame, c_can_bus_bit_stuffing_error, gc_verbose);
    Check(trans_slow_rx_rec, v_llc_frame, c_can_bus_bit_stuffing_error, gc_verbose);
    AffirmIf(test_id, v_exp_error_counter = al_transmit_error_count, "Error count: " & integer'image(al_transmit_error_count), "/= " & integer'image(v_exp_error_counter));
    v_exp_error_counter := al_transmit_error_count - 1;
    Check(trans_fast_rx_rec, v_llc_frame, gc_verbose);
    Check(trans_norm_rx_rec, v_llc_frame, gc_verbose);
    Check(trans_slow_rx_rec, v_llc_frame, gc_verbose);

    AffirmIf(test_id, v_exp_error_counter = al_transmit_error_count, "Error count: " & integer'image(al_transmit_error_count), "/= " & integer'image(v_exp_error_counter));

    -------------------------------------------------------------------------------------------
    -------------------------------------------------------------------------------------------
    Message(" - Crc");
    -- Generate frame and set random model parameters
    gen_frame(v_llc_frame);
    v_exp_error_counter := al_transmit_error_count + 8;

    -- send a frame from the dut to the vc's
    frame_2_ast(v_llc_frame, tx_src_fifo_id);
    Increment(tx_src_req);
    wait for 0 ns;
    wait until tx_src_req = tx_src_ack;

    wait until al_fsm_state = s_crc;
    wait until al_transmit = '0';
    if al_stuff_bit_valid = '1' then
      wait until al_transmit = '0';
    end if;
    rx <= force not tx;

    wait until al_sample_rx = '1';
    WaitForClock(clk, 3);
    rx <= release;

    Check(trans_fast_rx_rec, v_llc_frame, c_can_bus_bit_stuffing_error, gc_verbose);
    Check(trans_norm_rx_rec, v_llc_frame, c_can_bus_bit_stuffing_error, gc_verbose);
    Check(trans_slow_rx_rec, v_llc_frame, c_can_bus_bit_stuffing_error, gc_verbose);
    AffirmIf(test_id, v_exp_error_counter = al_transmit_error_count, "Error count: " & integer'image(al_transmit_error_count), "/= " & integer'image(v_exp_error_counter));
    v_exp_error_counter := al_transmit_error_count - 1;
    Check(trans_fast_rx_rec, v_llc_frame, gc_verbose);
    Check(trans_norm_rx_rec, v_llc_frame, gc_verbose);
    Check(trans_slow_rx_rec, v_llc_frame, gc_verbose);

    AffirmIf(test_id, v_exp_error_counter = al_transmit_error_count, "Error count: " & integer'image(al_transmit_error_count), "/= " & integer'image(v_exp_error_counter));

    -------------------------------------------------------------------------------------------
    -------------------------------------------------------------------------------------------
    Message(" - Error Frame delimiter");
    -- Generate frame and set random model parameters
    gen_frame(v_llc_frame);
    SetModelOptions(trans_slow_rx_rec, DISABLE_RX_OP, true);
    SetModelOptions(trans_fast_rx_rec, DISABLE_RX_OP, true);

    v_exp_error_counter := al_receive_error_count + 1;

    SendAsync(trans_fast_tx_rec, v_llc_frame, c_can_bus_crc_error);
    wait until al_fsm_state = s_error_frame_delimiter;

    wait until al_sample_rx = '1';
    rx <= force '0';
    WaitForClock(clk, 3);
    rx <= release;

    Check(trans_norm_rx_rec, v_llc_frame, c_can_bus_crc_error, gc_verbose);
    SetModelOptions(trans_slow_rx_rec, DISABLE_RX_OP, false);
    SetModelOptions(trans_fast_rx_rec, DISABLE_RX_OP, false);

    AffirmIf(test_id, v_exp_error_counter = al_receive_error_count, "Error count: " & integer'image(al_receive_error_count), "/= " & integer'image(v_exp_error_counter));

    wait for 100 us;

    Message(" - Normal mode to reset the counts");
    for i in 0 to v_exp_error_counter loop
      normal_operation_rx_0;
    end loop;
    v_exp_error_counter := al_transmit_error_count;
    for i in 0 to v_exp_error_counter loop
      normal_operation_tx;
    end loop;

    Message("###############################");
    Message("Edge case: Zero rx in end of frame");
    Message("###############################");

    SetModelOptions(trans_norm_rx_rec, DISABLE_RX_OP, true);
    SetModelOptions(trans_slow_rx_rec, DISABLE_RX_OP, true);
    SetModelOptions(trans_fast_rx_rec, DISABLE_RX_OP, true);
    gen_frame(v_llc_w_frame);
    v_exp_error_counter := al_receive_error_count + 1;

    SendAsync(trans_norm_tx_rec, v_llc_w_frame);
    wait until al_fsm_state = s_end_of_frame;
    wait until al_transmit = '0';
    wait until al_transmit = '0';
    rx <= force '0';

    wait until al_sample_rx = '1';
    WaitForClock(clk, 3);
    rx <= release;

    wait for 100 us;
    SetModelOptions(trans_norm_rx_rec, DISABLE_RX_OP, false);
    SetModelOptions(trans_slow_rx_rec, DISABLE_RX_OP, false);
    SetModelOptions(trans_fast_rx_rec, DISABLE_RX_OP, false);
    AffirmIf(test_id, v_exp_error_counter = al_receive_error_count, "Error count: " & integer'image(al_receive_error_count), "/= " & integer'image(v_exp_error_counter));

    Message("###############################");
    Message("Edge case: Error flag to long as ");
    Message("###############################");
    Message(" - Receiver");
    SetModelOptions(trans_norm_rx_rec, DISABLE_RX_OP, true);
    SetModelOptions(trans_slow_rx_rec, DISABLE_RX_OP, true);
    SetModelOptions(trans_fast_rx_rec, DISABLE_RX_OP, true);
    gen_frame(v_llc_w_frame);
    SendAsync(trans_norm_tx_rec, v_llc_w_frame, c_can_bus_crc_error);
    v_exp_error_counter := al_receive_error_count + 1;

    wait until al_fsm_state = s_error_frame_check;
    wait until al_transmit = '0';
    AffirmIf(test_id, v_exp_error_counter = al_receive_error_count, "Error count: " & integer'image(al_receive_error_count), "/= " & integer'image(v_exp_error_counter));
    v_exp_error_counter := v_exp_error_counter + 8;
    rx                  <= force '0';
    wait until al_sample_rx = '1';
    WaitForClock(clk, 3);
    AffirmIf(test_id, v_exp_error_counter = al_receive_error_count, "in s_error_frame_check. Error count: " & integer'image(al_receive_error_count), "/= " & integer'image(v_exp_error_counter));
    for byte_count in 1 to 7 loop
      wait until al_sample_rx = '1';
      AffirmIf(test_id, v_exp_error_counter = al_receive_error_count, "byte_count: " & integer'image(byte_count) & " Error count: " & integer'image(al_receive_error_count), "/= " & integer'image(v_exp_error_counter));
    end loop;
    WaitForClock(clk, 3);
    v_exp_error_counter := v_exp_error_counter + 8;
    AffirmIf(test_id, v_exp_error_counter = al_receive_error_count, "Error count: " & integer'image(al_receive_error_count), "/= " & integer'image(v_exp_error_counter));
    for run in 0 to 2 loop
      for byte_count in 0 to 7 loop
        wait until al_sample_rx = '1';
        AffirmIf(test_id, v_exp_error_counter = al_receive_error_count, "run: " & integer'image(run) & "." & integer'image(byte_count) & " Error count: " & integer'image(al_receive_error_count), "/= " & integer'image(v_exp_error_counter));
      end loop;
      WaitForClock(clk, 3);
      v_exp_error_counter := v_exp_error_counter + 8;
      AffirmIf(test_id, v_exp_error_counter = al_receive_error_count, "run: " & integer'image(run) & " Error count: " & integer'image(al_receive_error_count), "/= " & integer'image(v_exp_error_counter));
    end loop;
    rx                  <= release;

    wait until al_fsm_state = s_idle;

    SetModelOptions(trans_norm_rx_rec, DISABLE_RX_OP, false);
    SetModelOptions(trans_slow_rx_rec, DISABLE_RX_OP, false);
    SetModelOptions(trans_fast_rx_rec, DISABLE_RX_OP, false);
    for i in 0 to v_exp_error_counter + 2 loop
      normal_operation_rx_0;
    end loop;


    Message(" - Transmitter");
    gen_frame(v_llc_frame);
    v_exp_error_counter := al_transmit_error_count + 8;

    SetModelOptions(trans_norm_rx_rec, DISABLE_RX_OP, true);
    SetModelOptions(trans_slow_rx_rec, DISABLE_RX_OP, true);
    SetModelOptions(trans_fast_rx_rec, DISABLE_RX_OP, true);

    -- send a frame from the dut to the vc's
    frame_2_ast(v_llc_frame, tx_src_fifo_id);
    Increment(tx_src_req);

    wait until al_fsm_state = s_error_frame_check;
    AffirmIf(test_id, v_exp_error_counter = al_transmit_error_count, "Error count: " & integer'image(al_transmit_error_count), "/= " & integer'image(v_exp_error_counter));
    wait until al_transmit = '0';
    rx                  <= force '0';
    for byte_count in 0 to 7 loop
      wait until al_sample_rx = '1';
      AffirmIf(test_id, v_exp_error_counter = al_transmit_error_count, "byte_count: " & integer'image(byte_count) & " Error count: " & integer'image(al_transmit_error_count), "/= " & integer'image(v_exp_error_counter));
    end loop;
    WaitForClock(clk, 3);
    v_exp_error_counter := v_exp_error_counter + 8;
    AffirmIf(test_id, v_exp_error_counter = al_transmit_error_count, "Error count: " & integer'image(al_transmit_error_count), "/= " & integer'image(v_exp_error_counter));
    for run in 0 to 2 loop
      for byte_count in 0 to 7 loop
        wait until al_sample_rx = '1';
        AffirmIf(test_id, v_exp_error_counter = al_transmit_error_count, "run: " & integer'image(run) & "." & integer'image(byte_count) & " Error count: " & integer'image(al_transmit_error_count), "/= " & integer'image(v_exp_error_counter));
      end loop;
      WaitForClock(clk, 3);
      v_exp_error_counter := v_exp_error_counter + 8;
      AffirmIf(test_id, v_exp_error_counter = al_transmit_error_count, "run: " & integer'image(run) & " Error count: " & integer'image(al_transmit_error_count), "/= " & integer'image(v_exp_error_counter));
    end loop;

    rx <= release;
    wait until al_fsm_state = s_idle;

    SetModelOptions(trans_norm_rx_rec, DISABLE_RX_OP, false);
    SetModelOptions(trans_slow_rx_rec, DISABLE_RX_OP, false);
    SetModelOptions(trans_fast_rx_rec, DISABLE_RX_OP, false);
    Get(trans_norm_rx_rec, v_llc_frame);
    Get(trans_slow_rx_rec, v_llc_frame);
    Get(trans_fast_rx_rec, v_llc_frame);
    for i in 0 to v_exp_error_counter + 2 loop
      normal_operation_tx;
    end loop;

    Message("###############################");
    Message("Edge case: Recessive bits in active error flag as ");
    Message("###############################");
    Message(" - Receiver");
    SetModelOptions(trans_norm_rx_rec, DISABLE_RX_OP, true);
    SetModelOptions(trans_slow_rx_rec, DISABLE_RX_OP, true);
    SetModelOptions(trans_fast_rx_rec, DISABLE_RX_OP, true);
    gen_frame(v_llc_w_frame);
    SendAsync(trans_norm_tx_rec, v_llc_w_frame, c_can_bus_crc_error);
    v_exp_error_counter := al_receive_error_count + 1;

    wait until al_fsm_state = s_error_frame;
    wait until al_transmit = '0';
    AffirmIf(test_id, v_exp_error_counter = al_receive_error_count, "Error count: " & integer'image(al_receive_error_count), "/= " & integer'image(v_exp_error_counter));
    rx <= force '1';
    for i in 0 to 3 loop
      wait until al_sample_rx = '1';
      WaitForClock(clk, 3);
      v_exp_error_counter := v_exp_error_counter + 8;
      AffirmIf(test_id, v_exp_error_counter = al_receive_error_count, "Error count: " & integer'image(al_receive_error_count), "/= " & integer'image(v_exp_error_counter));
    end loop;
    rx <= release;

    wait until al_fsm_state = s_idle;

    SetModelOptions(trans_norm_rx_rec, DISABLE_RX_OP, false);
    SetModelOptions(trans_slow_rx_rec, DISABLE_RX_OP, false);
    SetModelOptions(trans_fast_rx_rec, DISABLE_RX_OP, false);
    for i in 0 to v_exp_error_counter + 2 loop
      normal_operation_rx_0;
    end loop;

    Message(" - Transmitter");
    gen_frame(v_llc_frame);
    v_exp_error_counter := al_transmit_error_count + 8;

    SetModelOptions(trans_norm_rx_rec, DISABLE_RX_OP, true);
    SetModelOptions(trans_slow_rx_rec, DISABLE_RX_OP, true);
    SetModelOptions(trans_fast_rx_rec, DISABLE_RX_OP, true);

    -- send a frame from the dut to the vc's
    frame_2_ast(v_llc_frame, tx_src_fifo_id);
    Increment(tx_src_req);

    wait until al_fsm_state = s_error_frame;
    wait until al_transmit = '0';
    AffirmIf(test_id, v_exp_error_counter = al_transmit_error_count, "Error count: " & integer'image(al_transmit_error_count), "/= " & integer'image(v_exp_error_counter));
    rx <= force '1';
    for byte_count in 0 to 3 loop
      wait until al_sample_rx = '1';
      WaitForClock(clk, 3);
      v_exp_error_counter := v_exp_error_counter + 8;
      AffirmIf(test_id, v_exp_error_counter = al_transmit_error_count, "byte_count : " & integer'image(byte_count) & " Error count: " & integer'image(al_transmit_error_count), "/= " & integer'image(v_exp_error_counter));
    end loop;
    rx <= release;

    wait until al_fsm_state = s_idle;

    SetModelOptions(trans_norm_rx_rec, DISABLE_RX_OP, false);
    SetModelOptions(trans_slow_rx_rec, DISABLE_RX_OP, false);
    SetModelOptions(trans_fast_rx_rec, DISABLE_RX_OP, false);
    Get(trans_norm_rx_rec, v_llc_frame);
    Get(trans_slow_rx_rec, v_llc_frame);
    Get(trans_fast_rx_rec, v_llc_frame);
    for i in 0 to v_exp_error_counter + 2 loop
      normal_operation_tx;
    end loop;

    Message("###############################");
    Message("Edge case: Overload in ");
    Message("###############################");
    -------------------------------------------------------------------------------------------
    -------------------------------------------------------------------------------------------
    Message(" - Error frame delimiter");

    SetModelOptions(trans_norm_rx_rec, DISABLE_RX_OP, true);
    SetModelOptions(trans_slow_rx_rec, DISABLE_RX_OP, true);
    SetModelOptions(trans_fast_rx_rec, DISABLE_RX_OP, true);
    gen_frame(v_llc_w_frame);
    v_exp_error_counter := al_receive_error_count + 1;

    SendAsync(trans_norm_tx_rec, v_llc_w_frame);
    wait until al_fsm_state = s_end_of_frame;
    wait until al_transmit = '0';
    wait until al_transmit = '0';
    rx <= force '0';

    wait until al_sample_rx = '1';
    WaitForClock(clk, 3);
    rx                  <= release;
    WaitForClock(clk, 1);
    AffirmIf(test_id, v_exp_error_counter = al_receive_error_count, "Error count: " & integer'image(al_receive_error_count), "/= " & integer'image(v_exp_error_counter));
    v_exp_error_counter := v_exp_error_counter + 1;

    wait until al_fsm_state = s_error_frame_delimiter;
    wait until al_bit_count = c_dominant_bit_in_error;
    rx <= force '0';

    wait until al_sample_rx = '1';
    WaitForClock(clk, 3);
    rx <= release;

    wait for 100 us;
    SetModelOptions(trans_norm_rx_rec, DISABLE_RX_OP, false);
    SetModelOptions(trans_slow_rx_rec, DISABLE_RX_OP, false);
    SetModelOptions(trans_fast_rx_rec, DISABLE_RX_OP, false);
    AffirmIf(test_id, v_exp_error_counter = al_receive_error_count, "Error count: " & integer'image(al_receive_error_count), "/= " & integer'image(v_exp_error_counter));

    -------------------------------------------------------------------------------------------
    -------------------------------------------------------------------------------------------
    Message(" - Error frame intermission");

    SetModelOptions(trans_norm_rx_rec, DISABLE_RX_OP, true);
    SetModelOptions(trans_slow_rx_rec, DISABLE_RX_OP, true);
    SetModelOptions(trans_fast_rx_rec, DISABLE_RX_OP, true);
    gen_frame(v_llc_w_frame);

    frame_2_ast(v_llc_w_frame, rx_sink_fifo_id);
    Increment(rx_sink_expected);

    SendAsync(trans_norm_tx_rec, v_llc_w_frame);

    wait until al_fsm_state = s_intermission;
    wait until al_bit_count = c_dominant_bit_at_2_bit_intermission;
    rx <= force '0';

    wait until al_sample_rx = '1';
    WaitForClock(clk, 3);
    rx <= release;

    wait for 100 us;
    SetModelOptions(trans_norm_rx_rec, DISABLE_RX_OP, false);
    SetModelOptions(trans_slow_rx_rec, DISABLE_RX_OP, false);
    SetModelOptions(trans_fast_rx_rec, DISABLE_RX_OP, false);
    wait for 100 us;


    Message("###############################");
    Message("Bus disconnected and reconnected in (single bit timing) (Error Active)");
    Message("###############################");
    SetModelOptions(trans_norm_rx_rec, DISABLE_RX_OP, true);
    SetModelOptions(trans_slow_rx_rec, DISABLE_RX_OP, true);
    SetModelOptions(trans_fast_rx_rec, DISABLE_RX_OP, true);
    Message(" - Arbitration");
    for run in 2 to 32 loop
      gen_frame(v_llc_frame, true, true);
      v_llc_frame.id(0) := '1';
      frame_2_ast(v_llc_frame, tx_src_fifo_id);
      frame_2_ast(v_llc_frame, rx_2_sink_fifo_id);
      v_llc_frame.id(0) := '0';
      frame_2_ast(v_llc_frame, tx_2_src_fifo_id);
      frame_2_ast(v_llc_frame, rx_sink_fifo_id);
      Increment(tx_src_req);
      Increment(tx_2_src_req);
      Increment(rx_sink_expected);
      Increment(rx_2_sink_expected);

      wait until al_fsm_state = s_arbitration;
      wait until al_bit_count = run;
      disconnect_bus <= '1';
      wait until al_sample_rx = '1';
      WaitForClock(clk, 2);
      disconnect_bus <= '0';

      wait until (rx_2_sink_expected = rx_2_sink_received) and (rx_sink_expected = rx_sink_received);
    end loop;

    Message("###############################");
    Message("Bus disconnected before and reconnected in (Error Active)");
    Message("###############################");
    Message(" - Arbitration");
    for run in 2 to 32 loop
      disconnect_bus    <= '1';
      gen_frame(v_llc_frame, true, true);
      v_llc_frame.id(0) := '1';
      frame_2_ast(v_llc_frame, tx_src_fifo_id);
      frame_2_ast(v_llc_frame, rx_2_sink_fifo_id);
      v_llc_frame.id(0) := '0';
      frame_2_ast(v_llc_frame, tx_2_src_fifo_id);
      frame_2_ast(v_llc_frame, rx_sink_fifo_id);
      Increment(tx_src_req);
      Increment(tx_2_src_req);
      Increment(rx_sink_expected);
      Increment(rx_2_sink_expected);
      wait until al_fsm_state = s_arbitration;
      wait until al_bit_count = run;
      wait until al_sample_rx = '1';
      disconnect_bus    <= '0';
      wait until (rx_2_sink_expected = rx_2_sink_received) and (rx_sink_expected = rx_sink_received);
    end loop;

    Message(" - Control");
    disconnect_bus    <= '1';
    gen_frame(v_llc_frame, true, true);
    v_llc_frame.id(0) := '1';
    frame_2_ast(v_llc_frame, tx_src_fifo_id);
    frame_2_ast(v_llc_frame, rx_2_sink_fifo_id);
    v_llc_frame.id(0) := '0';
    frame_2_ast(v_llc_frame, tx_2_src_fifo_id);
    frame_2_ast(v_llc_frame, rx_sink_fifo_id);
    Increment(tx_src_req);
    Increment(tx_2_src_req);
    Increment(rx_sink_expected);
    Increment(rx_2_sink_expected);
    wait until al_fsm_state = s_control;
    wait until al_sample_rx = '1';
    wait until al_sample_rx = '1';
    disconnect_bus    <= '0';
    wait until (rx_2_sink_expected = rx_2_sink_received) and (rx_sink_expected = rx_sink_received);

    Message(" - Data");
    disconnect_bus    <= '1';
    gen_frame(v_llc_frame, true, true);
    v_llc_frame.id(0) := '1';
    frame_2_ast(v_llc_frame, tx_src_fifo_id);
    frame_2_ast(v_llc_frame, rx_2_sink_fifo_id);
    v_llc_frame.id(0) := '0';
    frame_2_ast(v_llc_frame, tx_2_src_fifo_id);
    frame_2_ast(v_llc_frame, rx_sink_fifo_id);
    Increment(tx_src_req);
    Increment(tx_2_src_req);
    Increment(rx_sink_expected);
    Increment(rx_2_sink_expected);
    wait until al_fsm_state = s_data;
    wait until al_sample_rx = '1';
    wait until al_sample_rx = '1';
    disconnect_bus    <= '0';
    wait until (rx_2_sink_expected = rx_2_sink_received) and (rx_sink_expected = rx_sink_received);

    Message(" - CRC");
    disconnect_bus    <= '1';
    gen_frame(v_llc_frame, true, true);
    v_llc_frame.id(0) := '1';
    frame_2_ast(v_llc_frame, tx_src_fifo_id);
    frame_2_ast(v_llc_frame, rx_2_sink_fifo_id);
    v_llc_frame.id(0) := '0';
    frame_2_ast(v_llc_frame, tx_2_src_fifo_id);
    frame_2_ast(v_llc_frame, rx_sink_fifo_id);
    Increment(tx_src_req);
    Increment(tx_2_src_req);
    Increment(rx_sink_expected);
    Increment(rx_2_sink_expected);
    wait until al_fsm_state = s_crc;
    wait until al_sample_rx = '1';
    wait until al_sample_rx = '1';
    disconnect_bus    <= '0';
    wait until (rx_2_sink_expected = rx_2_sink_received) and (rx_sink_expected = rx_sink_received); 
    
    
    
    Message("###############################");
    Message("Bus disconnected and reconnected in (single bit timing) (Error Passive)");
    Message("###############################");
    SetModelOptions(trans_norm_rx_rec, DISABLE_RX_OP, true);
    SetModelOptions(trans_slow_rx_rec, DISABLE_RX_OP, true);
    SetModelOptions(trans_fast_rx_rec, DISABLE_RX_OP, true);
    Message(" - Arbitration");
    disconnect_bus    <= '1';
    gen_frame(v_llc_frame, true, true);
    v_llc_frame.id(0) := '1';
    frame_2_ast(v_llc_frame, tx_src_fifo_id);
    frame_2_ast(v_llc_frame, rx_2_sink_fifo_id);
    v_llc_frame.id(0) := '0';
    frame_2_ast(v_llc_frame, tx_2_src_fifo_id);
    frame_2_ast(v_llc_frame, rx_sink_fifo_id);
    Increment(tx_src_req);
    Increment(tx_2_src_req);
    Increment(rx_sink_expected);
    Increment(rx_2_sink_expected);
    wait until ns_dut = c_error_passive_ns and ns_dut_2 = c_error_passive_ns and rising_edge(clk);
    wait until al_fsm_state = s_idle;
    disconnect_bus    <= '0';

    wait until al_fsm_state = s_arbitration;
    disconnect_bus <= '1';
    wait until al_bit_count = 10;
    wait until al_sample_rx = '1';
    disconnect_bus <= '0';
    wait until (rx_2_sink_expected = rx_2_sink_received) and (rx_sink_expected = rx_sink_received);
    
    
    Message("###############################");
    Message("Bus disconnected before and reconnected in (Error Passive)");
    Message("###############################");

    Message(" - Arbitration");
    disconnect_bus    <= '1';
    gen_frame(v_llc_frame, true, true);
    v_llc_frame.id(0) := '1';
    frame_2_ast(v_llc_frame, tx_src_fifo_id);
    frame_2_ast(v_llc_frame, rx_2_sink_fifo_id);
    v_llc_frame.id(0) := '0';
    frame_2_ast(v_llc_frame, tx_2_src_fifo_id);
    frame_2_ast(v_llc_frame, rx_sink_fifo_id);
    Increment(tx_src_req);
    Increment(tx_2_src_req);
    Increment(rx_sink_expected);
    Increment(rx_2_sink_expected);
    wait until ns_dut = c_error_passive_ns and ns_dut_2 = c_error_passive_ns and rising_edge(clk);
    wait until al_fsm_state = s_arbitration;
    wait until al_sample_rx = '1';
    wait until al_sample_rx = '1';
    disconnect_bus    <= '0';
    wait until (rx_2_sink_expected = rx_2_sink_received) and (rx_sink_expected = rx_sink_received);

    Message(" - Control");
    disconnect_bus    <= '1';
    gen_frame(v_llc_frame, true, true);
    v_llc_frame.id(0) := '1';
    frame_2_ast(v_llc_frame, tx_src_fifo_id);
    frame_2_ast(v_llc_frame, rx_2_sink_fifo_id);
    v_llc_frame.id(0) := '0';
    frame_2_ast(v_llc_frame, tx_2_src_fifo_id);
    frame_2_ast(v_llc_frame, rx_sink_fifo_id);
    Increment(tx_src_req);
    Increment(tx_2_src_req);
    Increment(rx_sink_expected);
    Increment(rx_2_sink_expected);
    wait until ns_dut = c_error_passive_ns and ns_dut_2 = c_error_passive_ns and rising_edge(clk);
    wait until al_fsm_state = s_control;
    wait until al_sample_rx = '1';
    wait until al_sample_rx = '1';
    disconnect_bus    <= '0';
    wait until (rx_2_sink_expected = rx_2_sink_received) and (rx_sink_expected = rx_sink_received);

    Message(" - Data");
    disconnect_bus    <= '1';
    gen_frame(v_llc_frame, true, true);
    v_llc_frame.id(0) := '1';
    frame_2_ast(v_llc_frame, tx_src_fifo_id);
    frame_2_ast(v_llc_frame, rx_2_sink_fifo_id);
    v_llc_frame.id(0) := '0';
    frame_2_ast(v_llc_frame, tx_2_src_fifo_id);
    frame_2_ast(v_llc_frame, rx_sink_fifo_id);
    Increment(tx_src_req);
    Increment(tx_2_src_req);
    Increment(rx_sink_expected);
    Increment(rx_2_sink_expected);
    wait until ns_dut = c_error_passive_ns and ns_dut_2 = c_error_passive_ns and rising_edge(clk);
    wait until al_fsm_state = s_data;
    wait until al_sample_rx = '1';
    wait until al_sample_rx = '1';
    disconnect_bus    <= '0';
    wait until (rx_2_sink_expected = rx_2_sink_received) and (rx_sink_expected = rx_sink_received);

    Message(" - CRC");
    disconnect_bus    <= '1';
    gen_frame(v_llc_frame, true, true);
    v_llc_frame.id(0) := '1';
    frame_2_ast(v_llc_frame, tx_src_fifo_id);
    frame_2_ast(v_llc_frame, rx_2_sink_fifo_id);
    v_llc_frame.id(0) := '0';
    frame_2_ast(v_llc_frame, tx_2_src_fifo_id);
    frame_2_ast(v_llc_frame, rx_sink_fifo_id);
    Increment(tx_src_req);
    Increment(tx_2_src_req);
    Increment(rx_sink_expected);
    Increment(rx_2_sink_expected);
    wait until ns_dut = c_error_passive_ns and ns_dut_2 = c_error_passive_ns and rising_edge(clk);
    wait until al_fsm_state = s_crc;
    wait until al_sample_rx = '1';
    wait until al_sample_rx = '1';
    disconnect_bus    <= '0';
    wait until (rx_2_sink_expected = rx_2_sink_received) and (rx_sink_expected = rx_sink_received); 
    
    
    disconnect_bus <= '1';
    SetModelOptions(trans_norm_rx_rec, DISABLE_RX_OP, false);
    SetModelOptions(trans_slow_rx_rec, DISABLE_RX_OP, false);
    SetModelOptions(trans_fast_rx_rec, DISABLE_RX_OP, false);

    wait for 100 us;

    Message("###############################");
    Message("Last normal mode");
    Message("###############################");
    for i in 0 to 4 loop
      normal_operation;
    end loop;

    wait for 10 us;
    ReportNonZeroAlerts;
    Message("################################################################################");
    if GetAlertCount = 0 then
      Message("TEST PASSED!!");
    else
      Message("TEST FAILED :(");
    end if;
    Message("################################################################################");
    wait for 100 us;
    std.env.stop;
    wait;
  end process;
end architecture;

-- eof
