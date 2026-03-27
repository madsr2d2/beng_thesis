--------------------------------------------------------------------------------------------------------------------------------------------------------------
-- Copyright 2026 Everllence, Teglholmsgade 41, 2450 Copenhagen SV, Denmark
--------------------------------------------------------------------------------------------------------------------------------------------------------------
--
-- Requirements:
--
-- Description:   Testbench for can_mac_ser_tx. Verifies config byte loading,
--                LLC metadata extraction, data byte serialization, frame
--                termination on transfer status change, and ready/valid
--                handshaking.
--
-- Revision log:  Date:       Initial:  JIRA:
--                2026-03-16  TMYAES    [TRIT-4345] Initial implementation
--                2026-03-20  TMYAES    [TRIT-4345] Added random frame test with aborts and bit-level checks
---               2026-03-20  TMYAES    [TRIT-4345] Check values on falling clk edge
--------------------------------------------------------------------------------------------------------------------------------------------------------------

library ieee;
  use ieee.std_logic_1164.all;
  use ieee.numeric_std.all;
library osvvm;
  context osvvm.OsvvmContext;
library osvvm_common;
  context osvvm_common.OsvvmCommonContext;
use work.pk_can_types.all;
use work.pk_man_global.all;
use work.pk_eth_st.all;
use work.common_register_interface_pkg.all;
use work.common_tb_pkg.all;
use osvvm.ScoreBoardPkg_slv.all; 

entity can_mac_ser_tx_tb is
  generic (
    gc_TbTimeOut   : time := 10 ms;
    gc_TbClkPeriod : time := 10 ns
  );
end entity can_mac_ser_tx_tb;

architecture tb of can_mac_ser_tx_tb is

  ----------------------------------------------------------------------------
  -- Constants
  ----------------------------------------------------------------------------
  constant c_frames_to_send : positive := 20;
  constant c_send_config_bytes : std_logic_vector(1 downto 0) := "00";
  constant c_random_pressure : std_logic_vector(1 downto 0) := "00";

  ----------------------------------------------------------------------------
  -- Signals
  ----------------------------------------------------------------------------
  signal clk   : std_logic;
  signal reset : std_logic := '1';

  signal llc_i        : t_can_llc_mac_tx_if_s2d;
  signal llc_o        : t_can_llc_mac_tx_if_d2s;
  signal mac_fsm_tx_i : t_can_mac_ser_fsm_tx_if_m2s;
  signal mac_fsm_tx_o : t_can_mac_ser_fsm_tx_if_s2m;

  signal test_id   : AlertLogIDType;
  signal llc_frame : t_llc_frame;
  signal ser_stream : std_logic_vector((t_llc_frame'high - 3)*8 downto 0) := (others => 'U'); -- Captured serialized bit stream for verification

  signal llc_metadata : t_llc_metadata;

  -- osvvm signals
  signal reset_id : AlertLogIDType;
  signal crc_check_id : AlertLogIDType;
  signal output_stable_id : AlertLogIDType;
  -- Transaction records
  signal tx_llc_rec : StreamRecType(DataToModel (t_byte'high  downto 0), ParamToModel (1 downto 0), DataFromModel (0 downto 0), ParamFromModel (0 downto 0));
  -- signal llc_o_rec : StreamRecType( DataToModel (c_byte_width - 1 downto 0), ParamToModel (0 downto 0), DataFromModel (0 downto 0), ParamFromModel (0 downto 0));
  signal rx_mac_fsm_rec : StreamRecType(DataToModel (c_max_mac_frame_length - 1 downto 0), ParamToModel (1 downto 0), DataFromModel (0 downto 0), ParamFromModel (0 downto 0));

  signal cov  : CoverageIdType;
  shared variable RV : RandomPType;
  ----------------------------------------------------------------------------
  -- Procedures
  ----------------------------------------------------------------------------
  procedure pr_generate_random_llc_frame (signal llc_frame : out t_llc_frame; signal llc_metadata : out t_llc_metadata) is
    variable v_llc_frame : t_llc_frame;
  begin
    for i in v_llc_frame'range loop
      v_llc_frame(i) := RV.RandSlv(8);
    end loop;
    
    llc_metadata.format <= v_llc_frame(0)(c_llc_frame_config_byte_0_format_start downto c_llc_frame_config_byte_0_format_end);
    llc_metadata.ftyp <= v_llc_frame(0)(c_llc_frame_config_byte_0_ftyp);
    llc_metadata.brs <= v_llc_frame(0)(c_llc_frame_config_byte_0_brs);
    llc_metadata.esi <= v_llc_frame(0)(c_llc_frame_config_byte_0_esi);
    llc_metadata.dlc    <= v_llc_frame(1)(c_llc_frame_config_byte_1_dlc_start downto c_llc_frame_config_byte_1_dlc_end);
    llc_frame <= v_llc_frame;
    wait for 0 ns;
  end procedure pr_generate_random_llc_frame;

  procedure pr_avalon_st_send (signal sink : in t_eth_st_d2s; signal source : out t_eth_st_s2d; constant data : in t_byte; constant sop : in std_logic; constant eop : in std_logic) is
  begin
    source.valid         <= '1';
    source.data          <= data;
    source.startofpacket <= sop;
    source.endofpacket   <= eop;

    if sink.ready /= '1' then
        wait until sink.ready = '1';
    end if;
    WaitForClock(clk);
    wait for 0 ns;
  end procedure pr_avalon_st_send;

  procedure random_abort (
    signal   tx_mac_fsm_i : out   t_can_mac_ser_fsm_tx_if_m2s;
    signal   llc_i        : out   t_can_llc_mac_tx_if_s2d;
    signal   llc_o        : in    t_can_llc_mac_tx_if_d2s;
    variable aborted      : out   boolean
  ) is
  begin
    aborted := false;
    if RV.DistBool((false => 98, true => 2)) then
      tx_mac_fsm_i.transfer_status <= c_disturbed;
      llc_i.avalon_st_source.valid <= '0';
      WaitForClock(clk, 2);
      wait for 0 ns;
      AlertIf(test_id, llc_o.avalon_st_sink.ready = '0',
              "ERROR: ready not asserted after abort", FAILURE);
      AlertIf(test_id, llc_o.transfer_status /= c_disturbed,
              "ERROR: transfer status not forwarded after abort", FAILURE);
      aborted := true;
    end if;
  end procedure random_abort;

  procedure verify_llc_metadata (
    signal tx_mac_fsm_o : in t_can_mac_ser_fsm_tx_if_s2m;
    signal llc_frame    : in t_llc_frame
  ) is
  begin
    wait until falling_edge(clk);
    AlertIf(tx_mac_fsm_o.llc_metadata.format /= llc_frame(0)(c_llc_frame_config_byte_0_format_start downto c_llc_frame_config_byte_0_format_end),
            "ERROR: FORMAT mismatch", FAILURE);
    AlertIf(tx_mac_fsm_o.llc_metadata.ftyp /= llc_frame(0)(c_llc_frame_config_byte_0_ftyp),
            "ERROR: ftyp mismatch", FAILURE);
    AlertIf(tx_mac_fsm_o.llc_metadata.esi /= llc_frame(0)(c_llc_frame_config_byte_0_esi),
            "ERROR: ESI mismatch", FAILURE);
    AlertIf(tx_mac_fsm_o.llc_metadata.brs /= llc_frame(0)(c_llc_frame_config_byte_0_brs),
            "ERROR: BRS mismatch", FAILURE);
    AlertIf(tx_mac_fsm_o.llc_metadata.dlc /= llc_frame(1)(c_llc_frame_config_byte_1_dlc_start downto c_llc_frame_config_byte_1_dlc_end),
            "ERROR: DLC mismatch", FAILURE);
  end procedure verify_llc_metadata;


begin

  ----------------------------------------------------------------------------
  -- Initialisation
  ----------------------------------------------------------------------------
  p_init : process is
    variable v_test_id : AlertLogIDType;
  begin
    SetAlertStopCount(ERROR, 10);
    v_test_id := NewId("can_mac_ser_tx");
    test_id   <= v_test_id;
    wait for 0 ns;
    wait;
  end process p_init;

  ----------------------------------------------------------------------------
  -- Clock and timeout
  ----------------------------------------------------------------------------
  CreateClock(clk, gc_TbClkPeriod);
  CreateReset(reset, '1', clk, gc_TbClkPeriod * 10);

  p_timeout : process is
  begin
    wait for gc_TbTimeOut;
    assert false report "ERROR TEST FAILED, due to time out" severity error;
    std.env.stop(1);
  end process p_timeout;

  ----------------------------------------------------------------------------
  -- DUT
  ----------------------------------------------------------------------------
  u_dut : entity work.can_mac_ser_tx
    port map (
      clk_i        => clk,
      rst_i        => reset,
      llc_i        => llc_i,
      llc_o        => llc_o,
      tx_mac_fsm_i => mac_fsm_tx_i,
      tx_mac_fsm_o => mac_fsm_tx_o
    );
  
  ----------------------------------------------------------------------------
  --  can_mac_fsm_tx functional model
  ----------------------------------------------------------------------------

p_can_mac_fsm_tx_m : process is
  variable v_data : std_logic;
begin
  mac_fsm_tx_i.transfer_status <= "000";
  loop
    if mac_fsm_tx_i.ready = '1' and mac_fsm_tx_o.valid = '1' then
      wait until falling_edge(clk);
      ser_stream <= ser_stream(ser_stream'high - 1 downto 0) & mac_fsm_tx_o.data;
    end if;

    -- mac_fsm_tx_i.ready           <= '1' when RV.RandBool else '0';
    mac_fsm_tx_i.ready           <= '1';
    WaitForClock(clk,1);
    -- wait until rising_edge(clk);
  end loop;
end process p_can_mac_fsm_tx_m;
  

  ----------------------------------------------------------------------------
  -- Test sequencer
  ----------------------------------------------------------------------------
  p_test_ctrl : process is
    variable v_params_to_model : std_logic_vector(1 downto 0);
  begin
    wait until reset = '0';
    WaitForClock(clk);

    pr_generate_random_llc_frame(llc_frame, llc_metadata);

    
    for i in 0 to to_integer(unsigned(llc_metadata.dlc)) + 5 loop
      v_params_to_model := "10" when i = 0 else "00";
      Send(tx_llc_rec, Data => llc_frame(i) , Param => v_params_to_model);
    end loop;

  -- Done
  -- AlertIf(crc_check_id, not IsCovered(cov), "Coverage goal not met");
  -- WriteBin(cov); 
  EndOfTestReports(ReportAll => TRUE);
  std.env.finish;
  end process p_test_ctrl;

  ----------------------------------------------------------------------------
  -- llc_tx -> mac_ser_tx verification component
  ----------------------------------------------------------------------------
 p_llc_i_vc : process is
  variable v_sop : std_logic := '1';
  variable v_eop : std_logic := '0';
 begin

    WaitForTransaction(clk, tx_llc_rec.Rdy, tx_llc_rec.Ack);

    case tx_llc_rec.Operation is
      -- when SEND =>
      --     for i in llc_frame'range loop
      --       v_sop := '1' when i = llc_frame'low else '0';
      --       v_eop := '1' when i = llc_frame'high else '0';
      --       avalon_st_send(sink => llc_o.avalon_st_sink, source => llc_i.avalon_st_source, data => llc_frame(i) , sop => v_sop , eop => v_eop);
      --     end loop;
      --     wait for 0 ns;
      when SEND =>
            pr_avalon_st_send(sink => llc_o.avalon_st_sink, source => llc_i.avalon_st_source, data => t_byte(tx_llc_rec.DataToModel) , sop => tx_llc_rec.ParamToModel(1) , eop => tx_llc_rec.ParamToModel(0));
      when others => null;
    end case;
  end process p_llc_i_vc;

  ----------------------------------------------------------------------------
  -- mac_fsm_tx -> mac_ser_tx verification component
  ----------------------------------------------------------------------------
--  p_mac_fsm_o_vc : process is
--  begin
--     wait until llc_rec.Rdy /= llc_rec.Ack; 

--     case llc_rec.Operation is
--       when SEND =>

--         for i in llc_frame'range loop
--           if std_logic_vector(llc_rec.ParamToModel) = c_send_config_bytes then
--             avalon_st_send(sink => llc_o.avalon_st_sink, source => llc_i.avalon_st_source, data => llc_frame(i) , sop => '1', eop => '0');
--           end if;
--         end loop;
--       llc_rec.Ack <= llc_rec.Ack + 1;

--       when others => null;
--     end case;
--   end process p_mac_fsm_o_vc;

  -- -------------------------------------------------------------------------
  -- Main test process
  -- -------------------------------------------------------------------------
  -- main_tb_p : process is
  --   variable v_aborted              : boolean;
  --   variable v_id_bits_remaining    : integer;
  --   variable v_pad_bits_remaining   : integer;
  --   variable v_real_bits_this_byte  : integer;
  -- begin

  --   reset <= '1';
  --   WaitForClock(clk, 5);
  --   wait until falling_edge(clk);

  --   Print("==========================================");
  --   Print("TX MAC Serializer Testbench Started");
  --   Print("==========================================");

  --   -- =====================================================================
  --   -- Test 1: Reset values
  --   -- =====================================================================
  --   Print("-----------");
  --   Print("Test 1: Reset values");
  --   Print("-----------");

  --   -- AlertIf(test_id, mac_fsm_tx_o.valid = '1',
  --   --         "ERROR: valid should be deasserted in reset", FAILURE);
  --   -- AlertIf(test_id, llc_o.avalon_st_sink.ready = '1',
  --   --         "ERROR: ready should be deasserted in reset", FAILURE);

  --   reset <= '0';
  --   WaitForClock(clk);
  --   wait until falling_edge(clk);

  --   AlertIf(test_id, llc_o.avalon_st_sink.ready = '0',
  --           "ERROR: ready should be asserted after reset release", FAILURE);


  --   -- =====================================================================
  --   -- Test 2: Random frames with metadata, bit-level, and abort checks
  --   -- =====================================================================
  --   Print("-----------");
  --   Print("Test 2: Random frames with metadata, bit-level, and abort checks");
  --   Print("-----------");
  --   for frame_idx in 1 to c_frames_to_send loop

  --     mac_fsm_tx_i.transfer_status <= c_ongoing;
  --     WaitForClock(clk);

  --     wait until falling_edge(clk);
  --     AlertIf(test_id, llc_o.avalon_st_sink.ready = '0',
  --             "ERROR: ready should be asserted in idle state", FAILURE);

  --     generate_random_llc_frame(llc_frame);

  --     -- Config bytes
  --     avalon_st_send(sink => llc_o.avalon_st_sink,
  --                    source => llc_i.avalon_st_source,
  --                    data => llc_frame(0), sop => '1', eop => '0');

  --     avalon_st_send(sink => llc_o.avalon_st_sink,
  --                    source => llc_i.avalon_st_source,
  --                    data => llc_frame(1), sop => '0', eop => '0');

  --     llc_i.avalon_st_source.valid <= '0';

  --     -- Verify metadata is correct
  --     verify_llc_metadata(mac_fsm_tx_o, llc_frame);

  --     -- Initialize ID/padding counters (mirror DUT logic)
  --     if (llc_frame(0)(c_llc_frame_config_byte_0_ide) = '1') then
  --       v_id_bits_remaining  := c_base_id_width + c_extended_id_width;
  --       v_pad_bits_remaining := c_llc_id_field_width - (c_base_id_width + c_extended_id_width);
  --     else
  --       v_id_bits_remaining  := c_base_id_width;
  --       v_pad_bits_remaining := c_llc_id_field_width - c_base_id_width;
  --     end if;

  --     -- Data bytes with random backpressure
  --     for i in 2 to c_internal_llc_frame_len - 1 loop

  --       random_abort(mac_fsm_tx_i, llc_i, llc_o, v_aborted);
  --       exit when v_aborted;

  --       -- Calculate how many real (non-padding) bits this byte will produce
  --       if (v_id_bits_remaining > 0) then
  --         v_real_bits_this_byte := minimum(c_byte_width, v_id_bits_remaining);
  --         v_id_bits_remaining   := v_id_bits_remaining - v_real_bits_this_byte;
  --         v_pad_bits_remaining  := v_pad_bits_remaining - (c_byte_width - v_real_bits_this_byte);
  --       elsif (v_pad_bits_remaining > 0) then
  --         v_real_bits_this_byte := 0;
  --         v_pad_bits_remaining  := v_pad_bits_remaining - minimum(c_byte_width, v_pad_bits_remaining);
  --       else
  --         v_real_bits_this_byte := c_byte_width;
  --       end if;

  --       -- Random wait before llc_i valid
  --       WaitForClock(clk, RV.RandInt(1, 10));

  --       avalon_st_send(sink => llc_o.avalon_st_sink,
  --                      source => llc_i.avalon_st_source,
  --                      data => llc_frame(i), sop => '0', eop => '0');
  --       llc_i.avalon_st_source.valid <= '0';

  --       -- Verify only the real bits (padding bits are auto-skipped by serializer)
  --       for bit_idx in 0 to v_real_bits_this_byte - 1 loop

  --         -- Wait for serializer to present this bit
  --         if mac_fsm_tx_o.valid /= '1' then
  --           wait until mac_fsm_tx_o.valid = '1';
  --         end if;
  --         wait until falling_edge(clk);

  --         AlertIf(mac_fsm_tx_o.data /= llc_frame(i)(c_byte_width - 1 - bit_idx),
  --                 "ERROR: byte " & to_string(i) & " bit " & to_string(c_byte_width - 1 - bit_idx) &
  --                 " mismatch: expected " & to_string(llc_frame(i)(c_byte_width - 1 - bit_idx)) &
  --                 " got " & to_string(mac_fsm_tx_o.data), FAILURE);

  --         -- Random wait before fsm_i ready (realistic: FSM takes ~200 clocks per bit)
  --         WaitForClock(clk, RV.RandInt(150, 250));
  --         mac_fsm_tx_i.ready <= '1';
  --         WaitForClock(clk);
  --         mac_fsm_tx_i.ready <= '0';
  --         WaitForClock(clk);
  --         wait for 0 ns;

  --       end loop;

  --     end loop;

  --     mac_fsm_tx_i.transfer_status <= c_transmitted;
  --     WaitForClock(clk, 2);

  --   end loop;

  --   -- =====================================================================
  --   -- Test 3: Transfer status forwarding
  --   -- =====================================================================
  --   Print("-----------");
  --   Print("Test 3: Transfer status forwarding");
  --   Print("-----------");

  --   for status_idx in 0 to 4 loop

  --     case status_idx is
  --       when 0 => mac_fsm_tx_i.transfer_status <= c_ongoing;
  --       when 1 => mac_fsm_tx_i.transfer_status <= c_transmitted;
  --       when 2 => mac_fsm_tx_i.transfer_status <= c_disturbed;
  --       when 3 => mac_fsm_tx_i.transfer_status <= c_lost_arb;
  --       when 4 => mac_fsm_tx_i.transfer_status <= c_aborted;
  --       when others => null;
  --     end case;
  --     WaitForClock(clk);
  --     wait for 0 ns;

  --     AlertIf(test_id, llc_o.transfer_status /= mac_fsm_tx_i.transfer_status,
  --             "ERROR: transfer status not forwarded for index " & to_string(status_idx), FAILURE);

  --   end loop;

  --   -- -----------------------------------------------------------------------
  --   -- Done
  --   -- -----------------------------------------------------------------------
  --   reset <= '1';
  --   WaitForClock(clk, 5);
  --   ReportNonZeroAlerts;
  --   Print("");
  --   Print("==========================================");
  --   Print("All tests completed successfully!");
  --   Print("==========================================");
  --   EndOfTestReports(ReportAll => TRUE);
  --   std.env.finish;

  --   wait;

  -- end process main_tb_p;

end architecture tb;

-- eof
