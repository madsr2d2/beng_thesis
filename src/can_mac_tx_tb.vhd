--------------------------------------------------------------------------------
-- Title      : CAN MAC TX Integration Testbench
-- Project    : Implementation and Verification of a CAN-FD Bus Transceiver in VHDL
--------------------------------------------------------------------------------
-- File       : can_mac_tx_tb.vhd
-- Author     : Mads Richardt
-- Standard   : VHDL-2008
--------------------------------------------------------------------------------
-- Description: Black-box integration testbench for can_mac_tx. Instantiates the
--              full MAC wrapper (ser + fsm + bs + crc) with a simple PCS model
--              (free-running SP counter + zero-delay loopback) and drives the
--              Avalon-ST interface directly. A bus monitor tracks stuff bits to
--              maintain the logical frame position for ACK injection.
--------------------------------------------------------------------------------

library ieee;
  use ieee.std_logic_1164.all;
  use ieee.numeric_std.all;

library osvvm;
  context osvvm.osvvmcontext;

  use work.pk_can_types.all;

entity can_mac_tx_tb is
end entity can_mac_tx_tb;

architecture tb of can_mac_tx_tb is

  -- Constants
  constant c_clk_period           : time    := 10 ns;
  constant c_pcs_model_clks_per_sp : integer := 10;

  -- DUT ports
  signal clk   : std_logic;
  signal rst   : std_logic := '1';
  signal llc_i : t_can_llc_mac_tx_if_s2d;
  signal llc_o : t_can_llc_mac_tx_if_d2s;
  signal pcs_i : t_can_mac_pcs_tx_if_s2m := c_pcs_to_mac_if_reset;
  signal pcs_o : t_can_mac_pcs_tx_if_m2s;
  signal fce_i : t_can_mac_fce_if_s2m    := c_fce_to_mac_if_reset;
  signal fce_o : t_can_mac_fce_if_m2s;

  -- PCS model
  signal sp_strobe : std_logic := '0';

  -- FCE model
  signal fce_is_error_passive : boolean := false;

  -- Bus monitor (observation only)
  signal monitor_frame_pos  : integer := -1;
  signal monitor_stuff_stop : integer := c_max_mac_frame_length;

  -- Bus override
  type t_override_kind is (idle, ack_inject, bit_error, force_dominant);
  signal override_kind   : t_override_kind := idle;
  signal override_pos    : integer         := 0;
  signal override_active : boolean         := false;

begin

  CreateClock(clk, c_clk_period);
  CreateReset(rst, '1', clk, c_clk_period * 5);

  u_dut : entity work.can_mac_tx
    port map (
      clk   => clk,
      rst   => rst,
      llc_i => llc_i,
      llc_o => llc_o,
      pcs_i => pcs_i,
      pcs_o => pcs_o,
      fce_i => fce_i,
      fce_o => fce_o
    );

  -- PCS model: free-running SP counter + bus loopback with priority overrides
  p_pcs_sp_counter : process (clk) is

    variable sp_count : integer range 0 to c_pcs_model_clks_per_sp - 1 := 0;

  begin

    if rising_edge(clk) then
      sp_strobe <= '0';
      if (rst = '1') then
        sp_count := 0;
      elsif (sp_count = c_pcs_model_clks_per_sp - 1) then
        sp_strobe <= '1';
        sp_count  := 0;
      else
        sp_count := sp_count + 1;
      end if;
    end if;

  end process p_pcs_sp_counter;

  pcs_i.sp           <= sp_strobe;
  pcs_i.ssp          <= '0';
  pcs_i.tdc_delay    <= (others => '0');
  pcs_i.bus_polarity <= (not pcs_o.polarity) when (override_active and override_kind = bit_error)
                        else c_dominant when override_active
                        else pcs_o.polarity;

  fce_i.error_passive_request <= '1' when fce_is_error_passive else '0';
  fce_i.error_active_request  <= '0' when fce_is_error_passive else '1';
  fce_i.bus_off               <= '0';

  -- Bus monitor: tracks stuff bits, publishes logical frame position
  p_bus_monitor : process is

    variable consec        : integer   := 0;
    variable frame_pos     : integer   := -1;
    variable prev_polarity : std_logic := c_recessive;

  begin

    loop

    WaitForClock(clk);

    if (fce_o.transmitting = '0') then
      frame_pos         := -1;
      consec            := 0;
      monitor_frame_pos <= -1;
    end if;

    if (fce_o.transmitting = '1' and sp_strobe = '1') then
      -- Stuff bit: skip frame_pos so logical position stays aligned
      if (consec >= c_stuff_width and frame_pos < monitor_stuff_stop) then
        consec := 1;
      else
        frame_pos := frame_pos + 1;
        -- SOF is not fed to the stuffer; begin consec tracking from pos 1
        if (frame_pos > 0) then
          if (pcs_o.polarity = prev_polarity) then
            consec := consec + 1;
          else
            consec := 1;
          end if;
        end if;
      end if;

      monitor_frame_pos <= frame_pos;
      prev_polarity     := pcs_o.polarity;
    end if;

    end loop;

  end process p_bus_monitor;

  -- Bus override: drives override_active based on override_kind
  p_override : process is
  begin

    loop

    WaitForClock(clk);

    case override_kind is

      when idle =>
        override_active <= false;

      when ack_inject | bit_error =>
        if (fce_o.transmitting = '0') then
          override_active <= false;
        elsif (monitor_frame_pos = override_pos - 1) then
          override_active <= true;
        elsif (monitor_frame_pos /= override_pos - 1) then
          override_active <= false;
        end if;

      when force_dominant =>
        override_active <= true;

    end case;

    end loop;

  end process p_override;

  p_timeout : process is
  begin

    wait for 50 ms;
    Alert("Testbench timeout", FAILURE);
    std.env.finish;

  end process p_timeout;

  p_init : process is
  begin

    SetTestName("can_mac_tx_tb");
    SetAlertStopCount(ERROR, 5);
    wait;

  end process p_init;

  p_stim : process is

    variable tid       : AlertLogIDType;
    variable saw_pulse : boolean;
    variable rnd       : RandomPType;
    variable v_format  : std_logic_vector(2 downto 0);
    variable v_dlc     : std_logic_vector(3 downto 0);
    variable v_brs     : std_logic;
    variable v_id      : std_logic_vector(28 downto 0);
    variable v_meta    : t_llc_metadata;
    variable v_fp      : t_frame_params;
    variable v_pos     : integer;

    procedure send_byte (
      data : in std_logic_vector(7 downto 0);
      sop  : in std_logic := '0'
    ) is
    begin

      llc_i.avalon_st_source.data          <= data;
      llc_i.avalon_st_source.valid         <= '1';
      llc_i.avalon_st_source.startofpacket <= sop;
      WaitForClock(clk);
      while (llc_o.avalon_st_sink.ready /= '1') loop
        WaitForClock(clk);
      end loop;

    end procedure send_byte;

    procedure submit_mac_frame (
      id         : in std_logic_vector(28 downto 0);
      format     : in std_logic_vector(2 downto 0);
      dlc        : in std_logic_vector(3 downto 0);
      ftyp       : in std_logic := '0';
      brs        : in std_logic := '0';
      esi        : in std_logic := '0';
      data_value : in std_logic_vector(7 downto 0) := x"AA"
    ) is

      variable id_bytes   : std_logic_vector(31 downto 0);
      variable data_count : integer;

    begin

      id_bytes   := pack_llc_id_bytes(id, format);
      data_count := dlc_to_data_length(t_dlc(to_integer(unsigned(dlc))), format);
      if (ftyp = '1') then
        data_count := 0;
      end if;

      send_byte(format & ftyp & esi & brs & "00", sop => '1');
      send_byte(dlc & "0000");

      for i in 3 downto 0 loop
        send_byte(id_bytes((i + 1) * 8 - 1 downto i * 8));
      end loop;

      for i in 0 to data_count - 1 loop
        send_byte(data_value);
      end loop;

      llc_i.avalon_st_source.valid <= '0';
      llc_i.avalon_st_source.data  <= (others => '0');

    end procedure submit_mac_frame;

    procedure wait_n_sp (
      n : in integer
    ) is
    begin

      for i in 1 to n loop
        WaitForClock(clk);
        while (sp_strobe /= '1') loop
          WaitForClock(clk);
        end loop;
      end loop;

    end procedure wait_n_sp;

    procedure wait_for_frame_entry (
      timeout_sp : in integer := 200
    ) is
    begin

      for i in 1 to timeout_sp * c_pcs_model_clks_per_sp loop
        WaitForClock(clk);
        if (fce_o.transmitting = '1') then
          return;
        end if;
      end loop;
      Alert(tid, "wait_for_frame_entry timeout", ERROR);

    end procedure wait_for_frame_entry;

    procedure wait_for_transfer_status (
      expected   : in std_logic_vector(2 downto 0);
      timeout_sp : in integer := 500;
      msg        : in string
    ) is
    begin

      for i in 1 to timeout_sp * c_pcs_model_clks_per_sp loop
        WaitForClock(clk);
        if (llc_o.transfer_status = expected) then
          return;
        elsif (llc_o.transfer_status /= c_ongoing and llc_o.transfer_status /= expected) then
          Alert(tid, "transfer_status unexpected: got " & to_hstring(llc_o.transfer_status) &
                " expected " & to_hstring(expected) & " - " & msg, ERROR);
          return;
        end if;
      end loop;
      Alert(tid, "transfer_status timeout (still ongoing): " & msg, ERROR);

    end procedure wait_for_transfer_status;

    procedure wait_for_error_flag_entry (
      timeout_sp : in integer := 500
    ) is
    begin

      for i in 1 to timeout_sp * c_pcs_model_clks_per_sp loop
        WaitForClock(clk);
        if (fce_o.sending_error_overload_flag = '1') then
          return;
        end if;
      end loop;
      Alert(tid, "wait_for_error_flag_entry timeout", ERROR);

    end procedure wait_for_error_flag_entry;

    procedure wait_for_error_recovery is
    begin

      wait_n_sp(c_error_sequence_width + c_intermission_width + c_bus_idle_condition_width + 5);

    end procedure wait_for_error_recovery;

    procedure poll_for_pulse (
      signal sig   : in std_logic;
      timeout_clks : in integer
    ) is
    begin

      saw_pulse := false;
      for i in 1 to timeout_clks loop
        WaitForClock(clk);
        if (sig = '1') then
          saw_pulse := true;
        end if;
      end loop;

    end procedure poll_for_pulse;

    procedure setup_ack_injection (
      format : in std_logic_vector(2 downto 0);
      dlc    : in std_logic_vector(3 downto 0);
      ftyp   : in std_logic := '0';
      brs    : in std_logic := '0';
      esi    : in std_logic := '0'
    ) is

      variable meta : t_llc_metadata;
      variable v_fp : t_frame_params;

    begin

      meta               := (format => format, dlc => dlc, ftyp => ftyp, brs => brs, esi => esi);
      v_fp               := get_frame_params(meta);
      override_kind      <= ack_inject;
      override_pos       <= v_fp.crc_delimiter + c_ack_slot_offset;
      monitor_stuff_stop <= v_fp.dynamic_stuff_stop;

    end procedure setup_ack_injection;

    procedure transmit_and_verify (
      id     : in std_logic_vector(28 downto 0);
      format : in std_logic_vector(2 downto 0);
      dlc    : in std_logic_vector(3 downto 0);
      ftyp   : in std_logic := '0';
      brs    : in std_logic := '0';
      esi    : in std_logic := '0';
      msg    : in string
    ) is
    begin

      setup_ack_injection(format => format, dlc => dlc, ftyp => ftyp, brs => brs, esi => esi);
      submit_mac_frame(id => id, format => format, dlc => dlc, ftyp => ftyp, brs => brs, esi => esi);

      wait_for_frame_entry;
      wait_for_transfer_status(c_transmitted, 500, msg);
      AffirmIf(tid, true, msg);

      override_kind <= idle;
      wait_n_sp(c_intermission_width + c_bus_idle_condition_width + 5);

    end procedure transmit_and_verify;

  begin

    wait for 0 ns;
    tid := GetAlertLogID("can_mac_tx_tb");
    rnd.InitSeed(rnd'instance_name & to_string(now));

    llc_i.avalon_st_source.data          <= (others => '0');
    llc_i.avalon_st_source.valid         <= '0';
    llc_i.avalon_st_source.startofpacket <= '0';

    wait until rst = '0';
    WaitForClock(clk);

    -- T1: Dominant during reintegration resets the recessive counter
    wait_n_sp(5);
    override_kind <= force_dominant;
    wait_n_sp(1);
    override_kind <= idle;
    wait_n_sp(c_bus_idle_condition_width);

    transmit_and_verify(
      id     => 29x"555",
      format => c_llc_fmt_cb,
      dlc    => x"1",
      msg    => "T1: dominant resets reintegration counter"
    );

    -- T2-T5: Happy path for all four frame formats
    transmit_and_verify(
      id     => 29x"555",
      format => c_llc_fmt_cb,
      dlc    => x"1",
      msg    => "T2: CB happy path"
    );

    transmit_and_verify(
      id     => 29x"1555555",
      format => c_llc_fmt_ce,
      dlc    => x"1",
      msg    => "T3: CE happy path"
    );

    transmit_and_verify(
      id     => 29x"555",
      format => c_llc_fmt_fb,
      dlc    => x"1",
      brs    => '1',
      msg    => "T4: FB happy path"
    );

    transmit_and_verify(
      id     => 29x"1555555",
      format => c_llc_fmt_fe,
      dlc    => x"1",
      brs    => '1',
      msg    => "T5: FE happy path"
    );

    -- T6: ACK error (no ACK injected)
    submit_mac_frame(id => 29x"555", format => c_llc_fmt_cb, dlc => x"1");
    wait_for_frame_entry;
    wait_for_transfer_status(c_disturbed, 500, "T6: ACK error");
    AffirmIf(tid, true, "T6: ACK error detected");
    wait_for_error_recovery;

    -- T7: Bit error -> active error flag
    submit_mac_frame(id => 29x"555", format => c_llc_fmt_cb, dlc => x"1");
    wait_for_frame_entry;
    override_kind <= bit_error;
    override_pos  <= 5;
    wait_for_error_flag_entry(50);
    override_kind <= idle;
    wait_for_transfer_status(c_disturbed, 50, "T7: bit error active EF");
    AffirmIf(tid, true, "T7: bit error -> active error flag");
    wait_for_error_recovery;

    -- T8: Bit error -> passive error flag (recessive polarity)
    fce_is_error_passive <= true;

    submit_mac_frame(id => 29x"555", format => c_llc_fmt_cb, dlc => x"1");
    wait_for_frame_entry;
    override_kind <= bit_error;
    override_pos  <= 5;
    wait_for_error_flag_entry(50);
    override_kind <= idle;
    wait until falling_edge(clk);
    AffirmIf(tid, pcs_o.polarity = c_recessive, "T8: passive EF recessive polarity");
    wait_for_transfer_status(c_disturbed, 50, "T8: transfer disturbed");

    fce_is_error_passive <= false;
    wait_n_sp(c_error_sequence_width + c_intermission_width +
              c_suspend_transmission_width + c_bus_idle_condition_width + 5);

    -- T9: Arbitration loss -> verify recovery with follow-up frame
    override_kind <= force_dominant;
    submit_mac_frame(id => 29x"1FFFFFFF", format => c_llc_fmt_cb, dlc => x"1", data_value => x"FF");
    override_kind <= idle;
    wait_n_sp(c_intermission_width + c_bus_idle_condition_width + 5);

    transmit_and_verify(
      id     => 29x"555",
      format => c_llc_fmt_cb,
      dlc    => x"1",
      msg    => "T9: recovery after arb loss"
    );

    -- T10: Overload flag (dominant during 1st intermission bit)
    setup_ack_injection(format => c_llc_fmt_cb, dlc => x"1");
    submit_mac_frame(id => 29x"555", format => c_llc_fmt_cb, dlc => x"1");
    wait_for_frame_entry;
    wait_for_transfer_status(c_transmitted, 500, "T10: setup frame");
    override_kind <= idle;

    wait_n_sp(1);
    override_kind <= force_dominant;
    wait_n_sp(1);
    override_kind <= idle;

    wait_for_error_flag_entry(50);
    AffirmIf(tid, true, "T10: overload flag triggered");
    wait_for_error_recovery;

    -- T11: Error delimiter too late (dominant held during delimiter)
    submit_mac_frame(id => 29x"555", format => c_llc_fmt_cb, dlc => x"1");
    wait_for_frame_entry;
    wait_for_error_flag_entry(500);
    wait_n_sp(c_error_flag_width);

    override_kind <= force_dominant;
    poll_for_pulse(fce_o.error_delimiter_too_late, c_error_delimiter_width * c_pcs_model_clks_per_sp + 5);
    override_kind <= idle;

    AffirmIf(tid, saw_pulse, "T11: error delimiter too late");
    wait_for_error_recovery;

    -- T12: Primary error during active error flag
    submit_mac_frame(id => 29x"555", format => c_llc_fmt_cb, dlc => x"1");
    wait_for_frame_entry;
    override_kind <= bit_error;
    override_pos  <= 5;
    wait_for_error_flag_entry(50);
    override_kind <= idle;
    poll_for_pulse(fce_o.primary_error, c_error_flag_width * c_pcs_model_clks_per_sp + 5);

    AffirmIf(tid, saw_pulse, "T12: primary error during active EF");
    wait_for_error_recovery;

    -- T13: Random bit errors across all formats and frame positions
    for i in 1 to 100 loop

      case rnd.RandInt(0, 3) is
        when 0      => v_format := c_llc_fmt_cb;
        when 1      => v_format := c_llc_fmt_ce;
        when 2      => v_format := c_llc_fmt_fb;
        when others => v_format := c_llc_fmt_fe;
      end case;
      v_dlc := std_logic_vector(to_unsigned(rnd.RandInt(0, 15), 4));
      if (v_format(1) = '1') then v_brs := '1'; else v_brs := '0'; end if;

      v_id(28 downto 16) := std_logic_vector(to_unsigned(rnd.RandInt(0, 8191), 13));
      v_id(15 downto 0)  := std_logic_vector(to_unsigned(rnd.RandInt(0, 65535), 16));
      v_meta             := (format => v_format, dlc => v_dlc, ftyp => '0', brs => v_brs, esi => '0');
      v_fp               := get_frame_params(v_meta);
      -- Start after DLC to avoid arbitration field (where inversion = arb loss, not bit error)
      v_pos              := rnd.RandInt(v_fp.dlc_start, v_fp.crc_delimiter - 1);
      monitor_stuff_stop <= v_fp.dynamic_stuff_stop;

      submit_mac_frame(
        id => v_id, format => v_format, dlc => v_dlc, brs => v_brs
      );
      wait_for_frame_entry;
      override_kind <= bit_error;
      override_pos  <= v_pos;
      wait_for_error_flag_entry(500);
      override_kind <= idle;
      wait_for_transfer_status(c_disturbed, 50,
        "T13." & to_string(i) & ": bit error at pos " & to_string(v_pos) &
        " fmt=" & to_hstring(v_format) & " dlc=" & to_hstring(v_dlc));
      wait_for_error_recovery;

    end loop;
    AffirmIf(tid, true, "T13: 100 random bit error frames");

    Log(tid, "All tests complete");
    EndOfTestReports(ReportAll => TRUE);
    std.env.finish;

  end process p_stim;

end architecture tb;
