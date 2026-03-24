--------------------------------------------------------------------------------
-- Title      : CAN MAC TX Integration Testbench
-- Project    : Implementation and Verification of a CAN-FD Bus Transceiver in VHDL
--------------------------------------------------------------------------------
-- File       : can_mac_tx_tb.vhd
-- Author     : Mads Richardt
-- Standard   : VHDL-2008
--------------------------------------------------------------------------------
-- Description: Black-box integration testbench for can_mac_tx.
--              Each test scenario runs c_num_random iterations with randomized
--              frame parameters (format, DLC, ID) drawn from the full CAN/FD
--              frame space.
--
--              Architecture (5 processes + concurrent bus mux):
--                p_pcs_model   - PCS model (SP strobe generation)
--                p_stuff_model - Stuff-bit tracking (frame_pos, consec, next_is_stuff)
--                p_monitor     - DUT event latching (mon_rec)
--                p_stim        - Test sequencer with inline LLC driving
--                p_timeout     - Watchdog
--                bus_polarity  - Concurrent signal assignment for bus loopback
--                                with override (ACK inject, bit error, force dominant)
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

  constant c_clk_period            : time    := 10 ns;
  constant c_pcs_model_clks_per_sp : integer := 10;
  constant c_bus_loopback_delay    : time    := 20 ns;  -- must be < SP period (100 ns)
  constant c_num_random            : integer := 100;
  constant c_idle_recovery_sp      : integer := c_intermission_width
                                              + c_bus_idle_condition_width + 5;
  constant c_error_recovery_sp     : integer := c_error_sequence_width
                                              + c_idle_recovery_sp;

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
  signal sp_count           : integer range 0 to c_pcs_model_clks_per_sp - 1 := 0;

  -- Stuff-bit model
  signal stuff_stop : integer := c_max_mac_frame_length;

  -- Bus override
  type t_override_kind is (idle, ack_inject, bit_error, force_dominant);
  signal override_kind  : t_override_kind := idle;
  signal override_pos   : integer         := 0;
  signal frame_pos  : integer         := -1;
  signal consec     : integer         := 0;
  signal prev_pol   : std_logic       := c_recessive;
  signal next_is_stuff  : boolean         := false;

  -- Monitor edge-detection
  signal prev_transmitting  : std_logic := '0';
  signal prev_error_flag    : std_logic := '0';
  signal prev_fce_error     : std_logic := '0';
  signal prev_start_tdc     : std_logic := '0';
  signal prev_use_data_rate : std_logic := '0';

  -- Monitor transaction record
  type t_mon_rec is record
    frame_started       : boolean;
    transfer_done       : boolean;
    transfer_status     : std_logic_vector(2 downto 0);
    error_flag          : boolean;
    error_flag_pol      : std_logic;
    error_flag_pos      : integer;
    err_delim_late      : boolean;
    err_delim_late_pol  : std_logic;
    primary_error       : boolean;
    primary_error_pol   : std_logic;
    fce_error           : boolean;
    fce_error_pol       : std_logic;
    fce_error_pos       : integer;
    successful_transfer : boolean;
    start_tdc           : boolean;
    start_tdc_pos       : integer;
    use_data_rate       : boolean;
    use_data_rate_pos   : integer;
  end record t_mon_rec;

  constant c_mon_rec_reset : t_mon_rec := (
    frame_started       => false,
    transfer_done       => false,
    transfer_status     => c_ongoing,
    error_flag          => false,
    error_flag_pol      => c_recessive,
    error_flag_pos      => 0,
    err_delim_late      => false,
    err_delim_late_pol  => c_recessive,
    primary_error       => false,
    primary_error_pol   => c_recessive,
    fce_error           => false,
    fce_error_pol       => c_recessive,
    fce_error_pos       => 0,
    successful_transfer => false,
    start_tdc           => false,
    start_tdc_pos       => 0,
    use_data_rate       => false,
    use_data_rate_pos   => 0
  );

  signal mon_rec   : t_mon_rec := c_mon_rec_reset;
  signal mon_clear : boolean   := false;

  -- Bus content verification
  type t_data_array is array (0 to c_max_data_bytes - 1) of std_logic_vector(7 downto 0);
  type t_bus_array  is array (0 to c_max_mac_frame_length - 1) of std_logic;
  signal captured_bus : t_bus_array := (others => c_recessive);
  signal capture_en     : boolean     := false;

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

  ---------------------------------------------------------------------------
  -- PCS
  ---------------------------------------------------------------------------
  p_pcs_model : process (clk) is
  begin

    if rising_edge(clk) then
      pcs_i.sp  <= '0';
      pcs_i.ssp <= '0';
      pcs_i.tdc_delay <= (others => '0');

      if (rst = '1') then
        sp_count <= 0;
      elsif (sp_count = c_pcs_model_clks_per_sp - 1) then
        pcs_i.sp <= '1';
        sp_count <= 0;
      else
        sp_count <= sp_count + 1;
      end if;

    end if;

  end process p_pcs_model;

  ---------------------------------------------------------------------------
  -- Stuff-bit tracking model
  ---------------------------------------------------------------------------
  p_stuff_model : process (clk) is
  begin

    if rising_edge(clk) then
      if (fce_o.transmitting = '0') then
        frame_pos     <= -1;  -- becomes 0 (SOF) on first SP
        consec        <= 0;
        prev_pol      <= c_recessive;
        next_is_stuff <= false;
      elsif (pcs_i.sp = '1') then
        if (next_is_stuff) then
          consec        <= 1;
          next_is_stuff <= false;
        else
          frame_pos <= frame_pos + 1;
          if (capture_en) then
            captured_bus(frame_pos + 1) <= pcs_o.polarity;
          end if;
          if (pcs_o.polarity = prev_pol) then
            consec <= consec + 1;
            if (consec = c_stuff_width - 1 and frame_pos + 1 < stuff_stop) then
              next_is_stuff <= true;
            end if;
          else
            consec        <= 1;
            next_is_stuff <= false;
          end if;
        end if;
        prev_pol <= pcs_o.polarity;
      end if;
    end if;

  end process p_stuff_model;

  ---------------------------------------------------------------------------
  -- Bus model (loopback with override mux)
  ---------------------------------------------------------------------------
  p_bus_model : process (all) is
  begin

    if (override_kind = force_dominant) then
      pcs_i.bus_polarity <= c_dominant after c_bus_loopback_delay;
    elsif (override_kind = ack_inject and
           frame_pos = override_pos - 1 and not next_is_stuff) then
      pcs_i.bus_polarity <= c_dominant after c_bus_loopback_delay;
    elsif (override_kind = bit_error and
           frame_pos = override_pos - 1 and not next_is_stuff) then
      pcs_i.bus_polarity <= not pcs_o.polarity after c_bus_loopback_delay;
    else
      pcs_i.bus_polarity <= pcs_o.polarity after c_bus_loopback_delay;
    end if;

  end process p_bus_model;

  ---------------------------------------------------------------------------
  -- Unified monitor
  ---------------------------------------------------------------------------
  p_monitor : process is
  begin

    loop

    WaitForClock(clk);

    if (mon_clear) then
      mon_rec <= c_mon_rec_reset;
    end if;

    -- Event latching
    if (fce_o.transmitting = '1' and prev_transmitting = '0') then
      mon_rec.frame_started <= true;
    end if;

    if (llc_o.transfer_status /= c_ongoing and not mon_rec.transfer_done) then
      mon_rec.transfer_done   <= true;
      mon_rec.transfer_status <= llc_o.transfer_status;
    end if;

    if (fce_o.sending_error_overload_flag = '1' and prev_error_flag = '0') then
      mon_rec.error_flag     <= true;
      mon_rec.error_flag_pol <= pcs_o.polarity;
      mon_rec.error_flag_pos <= frame_pos;
    end if;

    if (fce_o.error_delimiter_too_late = '1') then
      mon_rec.err_delim_late     <= true;
      mon_rec.err_delim_late_pol <= pcs_o.polarity;
    end if;

    if (fce_o.primary_error = '1') then
      mon_rec.primary_error     <= true;
      mon_rec.primary_error_pol <= pcs_o.polarity;
    end if;

    if (fce_o.error = '1' and prev_fce_error = '0') then
      mon_rec.fce_error     <= true;
      mon_rec.fce_error_pol <= pcs_o.polarity;
      mon_rec.fce_error_pos <= frame_pos;
    end if;

    if (fce_o.successful_transfer = '1') then
      mon_rec.successful_transfer <= true;
    end if;

    if (pcs_o.start_tdc = '1' and prev_start_tdc = '0') then
      mon_rec.start_tdc     <= true;
      mon_rec.start_tdc_pos <= frame_pos;
    end if;

    if (pcs_o.use_data_rate = '1' and prev_use_data_rate = '0') then
      mon_rec.use_data_rate     <= true;
      mon_rec.use_data_rate_pos <= frame_pos;
    end if;

    prev_transmitting  <= fce_o.transmitting;
    prev_error_flag    <= fce_o.sending_error_overload_flag;
    prev_fce_error     <= fce_o.error;
    prev_start_tdc     <= pcs_o.start_tdc;
    prev_use_data_rate <= pcs_o.use_data_rate;

    end loop;

  end process p_monitor;

  ---------------------------------------------------------------------------
  -- Watchdog
  ---------------------------------------------------------------------------
  p_timeout : process is
  begin

    wait for 500 ms;
    Alert("Testbench timeout", FAILURE);
    std.env.finish;

  end process p_timeout;

  ---------------------------------------------------------------------------
  -- Test sequencer
  ---------------------------------------------------------------------------
  p_stim : process is

    variable tid      : AlertLogIDType;
    variable rnd      : RandomPType;
    variable v_format : std_logic_vector(2 downto 0);
    variable v_dlc    : std_logic_vector(3 downto 0);
    variable v_brs    : std_logic;
    variable v_id     : std_logic_vector(28 downto 0);
    variable v_meta   : t_llc_metadata;
    variable v_fp     : t_frame_params;
    variable v_pos      : integer;
    variable v_data     : t_data_array := (others => (others => '0'));
    variable v_expected : t_bus_array;
    variable v_exp_len  : integer;

    procedure randomize_frame is

      variable v_dc : integer;

    begin

      case rnd.RandInt(0, 3) is
        when 0      => v_format := c_llc_fmt_cb;
        when 1      => v_format := c_llc_fmt_ce;
        when 2      => v_format := c_llc_fmt_fb;
        when others => v_format := c_llc_fmt_fe;
      end case;
      v_dlc              := std_logic_vector(to_unsigned(rnd.RandInt(0, 15), 4));
      v_brs              := v_format(1);
      v_id(28 downto 16) := std_logic_vector(to_unsigned(rnd.RandInt(0, 8191), 13));
      v_id(15 downto 0)  := std_logic_vector(to_unsigned(rnd.RandInt(0, 65535), 16));
      v_meta             := (format => v_format, dlc => v_dlc, ftyp => '0', brs => v_brs, esi => '0');
      v_fp               := get_frame_params(v_meta);
      stuff_stop         <= v_fp.dynamic_stuff_stop;

      v_dc := dlc_to_data_length(t_dlc(to_integer(unsigned(v_dlc))), v_format);
      for j in 0 to v_dc - 1 loop
        v_data(j) := std_logic_vector(to_unsigned(rnd.RandInt(0, 255), 8));
      end loop;

    end procedure randomize_frame;

    procedure submit_frame (
      id     : in std_logic_vector(28 downto 0);
      format : in std_logic_vector(2 downto 0);
      dlc    : in std_logic_vector(3 downto 0);
      ftyp   : in std_logic := '0';
      brs    : in std_logic := '0';
      esi    : in std_logic := '0'
    ) is

      variable id_bytes   : std_logic_vector(31 downto 0);
      variable data_count : integer;

      type t_byte_array is array (natural range <>) of std_logic_vector(7 downto 0);
      variable frame_bytes : t_byte_array(0 to 69);
      variable byte_count  : integer := 0;

    begin

      id_bytes   := pack_llc_id_bytes(id, format);
      data_count := dlc_to_data_length(t_dlc(to_integer(unsigned(dlc))), format);
      if (ftyp = '1') then
        data_count := 0;
      end if;

      frame_bytes(0) := format & ftyp & esi & brs & "00";
      frame_bytes(1) := dlc & "0000";
      frame_bytes(2) := id_bytes(31 downto 24);
      frame_bytes(3) := id_bytes(23 downto 16);
      frame_bytes(4) := id_bytes(15 downto 8);
      frame_bytes(5) := id_bytes(7 downto 0);
      byte_count := 6;
      for i in 0 to data_count - 1 loop
        frame_bytes(byte_count) := v_data(i);
        byte_count := byte_count + 1;
      end loop;

      for i in 0 to byte_count - 1 loop
        llc_i.avalon_st_source.data          <= frame_bytes(i);
        llc_i.avalon_st_source.valid         <= '1';
        llc_i.avalon_st_source.startofpacket <= '1' when i = 0 else '0';
        loop
          WaitForClock(clk);
          exit when llc_o.avalon_st_sink.ready = '1';
        end loop;
        llc_i.avalon_st_source.valid         <= '0';
        llc_i.avalon_st_source.startofpacket <= '0';
        WaitForClock(clk);
      end loop;

      llc_i.avalon_st_source.data <= (others => '0');

    end procedure submit_frame;

    procedure wait_n_sp (n : in integer) is
    begin

      for i in 1 to n loop
        WaitForClock(clk);
        while (pcs_i.sp /= '1') loop
          WaitForClock(clk);
        end loop;
      end loop;

    end procedure wait_n_sp;

    procedure clear_events is
    begin

      mon_clear <= true;
      WaitForClock(clk);
      mon_clear <= false;

    end procedure clear_events;

    procedure wait_for_mon (
      check_error_flag : in boolean := false;
      timeout_sp       : in integer := 500
    ) is
    begin

      for i in 1 to timeout_sp * c_pcs_model_clks_per_sp loop
        WaitForClock(clk);
        if (check_error_flag) then
          if (mon_rec.error_flag) then return; end if;
        else
          if (mon_rec.frame_started) then return; end if;
        end if;
      end loop;
      if (check_error_flag) then
        Alert(tid, "wait_for_mon(error_flag) timeout", ERROR);
      else
        Alert(tid, "wait_for_mon(frame_started) timeout", ERROR);
      end if;

    end procedure wait_for_mon;

    procedure wait_for_transfer_status (
      expected   : in std_logic_vector(2 downto 0);
      timeout_sp : in integer := 500;
      msg        : in string
    ) is
    begin

      for i in 1 to timeout_sp * c_pcs_model_clks_per_sp loop
        WaitForClock(clk);
        if (mon_rec.transfer_done) then
          if (mon_rec.transfer_status = expected) then
            return;
          else
            Alert(tid, msg & ": got " & to_hstring(mon_rec.transfer_status) &
                  " expected " & to_hstring(expected), ERROR);
            return;
          end if;
        end if;
      end loop;
      Alert(tid, msg & ": timeout", ERROR);

    end procedure wait_for_transfer_status;

    procedure build_expected is

      variable v_bit       : t_mac_frame_bit;
      variable v_ser       : std_logic;
      variable v_prev_pol  : std_logic := c_recessive;
      variable v_crc       : t_crc_vector;
      variable v_byte_idx  : integer;
      variable v_bit_idx   : integer;
      variable v_data_fld  : integer;

    begin

      case v_fp.crc_poly_select is
        when "00"   => v_crc := c_crc_poly_15_vec & (c_crc_21_length - c_crc_15_length - 1 downto 0 => '0');
        when "01"   => v_crc := c_crc_poly_17_vec &
                                (c_crc_21_length - c_crc_17_length - 1 downto 0 => '0');
        when "10"   => v_crc := c_crc_poly_21_vec;
        when others => v_crc := (others => '0');
      end case;

      v_exp_len  := v_fp.crc_delimiter + c_eof_start_offset + c_eof_field_width;
      v_data_fld := v_fp.dlc_start + c_dlc_field_width;

      for pos in 0 to v_exp_len - 1 loop
        v_ser := '0';

        -- Base ID
        if (pos >= c_cb_base_id_start and pos <= c_cb_base_id_stop) then
          if (v_format(2) = '1') then
            v_ser := v_id(28 - (pos - c_cb_base_id_start));
          else
            v_ser := v_id(10 - (pos - c_cb_base_id_start));
          end if;
        end if;

        -- Extended ID (CE)
        if (v_format = c_llc_fmt_ce and
            pos >= c_ce_extended_id_start and pos <= c_ce_extended_id_stop) then
          v_ser := v_id(17 - (pos - c_ce_extended_id_start));
        end if;

        -- Extended ID (FE)
        if (v_format = c_llc_fmt_fe and
            pos >= c_fe_extended_id_start and pos <= c_fe_extended_id_stop) then
          v_ser := v_id(17 - (pos - c_fe_extended_id_start));
        end if;

        -- Data
        if (pos >= v_data_fld and pos < v_fp.data_stop) then
          v_byte_idx := (pos - v_data_fld) / 8;
          v_bit_idx  := 7 - ((pos - v_data_fld) mod 8);
          v_ser      := v_data(v_byte_idx)(v_bit_idx);
        end if;

        v_bit := get_mac_frame_bit(
                   bit_count         => pos,
                   ser_data          => v_ser,
                   metadata          => v_meta,
                   frame_params      => v_fp,
                   previous_polarity => v_prev_pol,
                   sbc               => (others => '0'),
                   crc               => v_crc
                 );

        v_expected(pos) := v_bit.polarity;
        v_prev_pol      := v_bit.polarity;
      end loop;

    end procedure build_expected;

    procedure check_bus_content (
      msg : in string
    ) is

      variable v_match : boolean := true;

    begin

      -- Compare captured vs expected, skip SBC + CRC (dummy engine)
      for pos in 0 to v_exp_len - 1 loop
        if (pos < v_fp.data_stop or pos >= v_fp.crc_delimiter) then
          if (captured_bus(pos) /= v_expected(pos)) then
            v_match := false;
            Log(tid, msg & " MISMATCH pos=" & to_string(pos) &
              " exp=" & to_string(v_expected(pos)) &
              " got=" & to_string(captured_bus(pos)));
          end if;
        end if;
      end loop;

      AffirmIf(tid, v_match, msg & " bus content OK");

    end procedure check_bus_content;

  begin

    wait for 0 ns;
    SetTestName("can_mac_tx_tb");
    tid := GetAlertLogID("can_mac_tx_tb");
    rnd.InitSeed(rnd'instance_name & to_string(now));

    llc_i.avalon_st_source.data          <= (others => '0');
    llc_i.avalon_st_source.valid         <= '0';
    llc_i.avalon_st_source.startofpacket <= '0';

    wait until rst = '0';
    WaitForClock(clk);

    -- Reintegration preamble (one-time)
    wait_n_sp(5);
    override_kind <= force_dominant;
    wait_n_sp(1);
    override_kind <= idle;
    wait_n_sp(c_bus_idle_condition_width);

    ---------------------------------------------------------------------------
    -- T1: Happy path (random frames, ACK injected)
    ---------------------------------------------------------------------------
    for i in 1 to c_num_random loop
      randomize_frame;
      build_expected;
      clear_events;
      capture_en         <= true;
      override_kind      <= ack_inject;
      override_pos       <= v_fp.crc_delimiter + c_ack_slot_offset;
      submit_frame(v_id, v_format, v_dlc, brs => v_brs);
      wait_for_mon;
      wait_for_transfer_status(c_transmitted, 500,
        "T1." & to_string(i) & " fmt=" & to_hstring(v_format) & " dlc=" & to_hstring(v_dlc));
      capture_en    <= false;
      override_kind <= idle;
      wait_n_sp(c_idle_recovery_sp);

      check_bus_content("T1." & to_string(i));

      AffirmIf(tid, mon_rec.successful_transfer,
        "T1." & to_string(i) & " successful_transfer");
      AffirmIf(tid, not mon_rec.fce_error,
        "T1." & to_string(i) & " no fce error");

      -- TDC and BRS checks
      if (v_format = c_llc_fmt_fb or v_format = c_llc_fmt_fe) then
        AffirmIf(tid, mon_rec.start_tdc,
          "T1." & to_string(i) & " start_tdc asserted for FD frame");
        if (v_format = c_llc_fmt_fb) then
          AffirmIf(tid, mon_rec.start_tdc_pos = c_fb_fdf - 1,
            "T1." & to_string(i) & " start_tdc at IDE pos " &
            to_string(c_fb_fdf - 1) & " got " & to_string(mon_rec.start_tdc_pos));
        else
          AffirmIf(tid, mon_rec.start_tdc_pos = c_fe_fdf - 1,
            "T1." & to_string(i) & " start_tdc at RRS pos " &
            to_string(c_fe_fdf - 1) & " got " & to_string(mon_rec.start_tdc_pos));
        end if;

        AffirmIf(tid, mon_rec.use_data_rate,
          "T1." & to_string(i) & " use_data_rate asserted for BRS frame");
        if (v_format = c_llc_fmt_fb) then
          AffirmIf(tid, mon_rec.use_data_rate_pos = c_fb_esi - 1,
            "T1." & to_string(i) & " use_data_rate at BRS pos " &
            to_string(c_fb_esi - 1) & " got " & to_string(mon_rec.use_data_rate_pos));
        else
          AffirmIf(tid, mon_rec.use_data_rate_pos = c_fe_esi - 1,
            "T1." & to_string(i) & " use_data_rate at BRS pos " &
            to_string(c_fe_esi - 1) & " got " & to_string(mon_rec.use_data_rate_pos));
        end if;
      else
        AffirmIf(tid, not mon_rec.start_tdc,
          "T1." & to_string(i) & " no start_tdc for classic frame");
        AffirmIf(tid, not mon_rec.use_data_rate,
          "T1." & to_string(i) & " no use_data_rate for classic frame");
      end if;
    end loop;
    AffirmIf(tid, true, "T1: happy path (" & to_string(c_num_random) & " random frames)");

    ---------------------------------------------------------------------------
    -- T2: ACK error (no ACK injected)
    ---------------------------------------------------------------------------
    for i in 1 to c_num_random loop
      randomize_frame;
      clear_events;
      submit_frame(v_id, v_format, v_dlc, brs => v_brs);
      wait_for_mon;
      wait_for_mon(check_error_flag => true);
      AffirmIf(tid, mon_rec.error_flag,
        "T2." & to_string(i) & " error flag after ACK error");
      AffirmIf(tid, mon_rec.error_flag_pol = c_dominant,
        "T2." & to_string(i) & " active EF drives dominant");
      wait_for_transfer_status(c_disturbed, 500,
        "T2." & to_string(i) & " fmt=" & to_hstring(v_format) & " dlc=" & to_hstring(v_dlc));
      AffirmIf(tid, mon_rec.fce_error,
        "T2." & to_string(i) & " fce error after ACK error");
      wait_n_sp(c_error_recovery_sp);
    end loop;
    AffirmIf(tid, true, "T2: ACK error (" & to_string(c_num_random) & " random frames)");

    ---------------------------------------------------------------------------
    -- T3: Passive error flag (recessive polarity)
    ---------------------------------------------------------------------------
    fce_i.error_passive_request <= '1';
    fce_i.error_active_request  <= '0';
    for i in 1 to c_num_random loop
      randomize_frame;
      clear_events;
      override_kind <= bit_error;
      override_pos  <= v_fp.dlc_start;
      submit_frame(v_id, v_format, v_dlc, brs => v_brs);
      wait_for_mon(check_error_flag => true);
      override_kind <= idle;
      AffirmIf(tid, mon_rec.error_flag_pol = c_recessive,
        "T3." & to_string(i) & ": passive EF recessive polarity");
      wait_for_transfer_status(c_disturbed, 50,
        "T3." & to_string(i) & " fmt=" & to_hstring(v_format));
      AffirmIf(tid, mon_rec.fce_error,
        "T3." & to_string(i) & " fce error after passive EF");
      AffirmIf(tid, mon_rec.error_flag_pos = v_fp.dlc_start,
        "T3." & to_string(i) & " error_flag_pos=" & to_string(mon_rec.error_flag_pos) &
        " expected " & to_string(v_fp.dlc_start));
      wait_n_sp(c_error_recovery_sp + c_suspend_transmission_width);
    end loop;
    fce_i.error_passive_request <= '0';
    fce_i.error_active_request  <= '1';
    AffirmIf(tid, true, "T3: passive EF (" & to_string(c_num_random) & " random frames)");

    ---------------------------------------------------------------------------
    -- T4: Arbitration loss -> recovery with follow-up happy path
    ---------------------------------------------------------------------------
    for i in 1 to c_num_random loop
      randomize_frame;
      clear_events;
      override_kind <= force_dominant;
      submit_frame(v_id, v_format, v_dlc, brs => v_brs);
      override_kind <= idle;
      wait_n_sp(c_idle_recovery_sp);

      -- Verify recovery: next frame must succeed
      randomize_frame;
      clear_events;
      override_kind <= ack_inject;
      override_pos  <= v_fp.crc_delimiter + c_ack_slot_offset;
      submit_frame(v_id, v_format, v_dlc, brs => v_brs);
      wait_for_mon;
      wait_for_transfer_status(c_transmitted, 500,
        "T4." & to_string(i) & ": recovery frame");
      override_kind <= idle;
      wait_n_sp(c_idle_recovery_sp);
      AffirmIf(tid, mon_rec.successful_transfer,
        "T4." & to_string(i) & " recovery successful_transfer");
    end loop;
    AffirmIf(tid, true, "T4: arb loss + recovery (" & to_string(c_num_random) & " random frames)");

    ---------------------------------------------------------------------------
    -- T5: Overload flag (dominant during 1st intermission bit)
    ---------------------------------------------------------------------------
    for i in 1 to c_num_random loop
      -- First transmit a successful frame
      randomize_frame;
      clear_events;
      override_kind      <= ack_inject;
      override_pos       <= v_fp.crc_delimiter + c_ack_slot_offset;
      submit_frame(v_id, v_format, v_dlc, brs => v_brs);
      wait_for_mon;
      wait_for_transfer_status(c_transmitted, 500, "T5." & to_string(i) & ": setup");
      override_kind <= idle;

      -- Inject dominant during 1st intermission bit
      clear_events;
      wait_n_sp(1);
      override_kind <= force_dominant;
      wait_n_sp(1);
      override_kind <= idle;
      wait_for_mon(check_error_flag => true, timeout_sp => 50);
      AffirmIf(tid, mon_rec.error_flag,
        "T5." & to_string(i) & ": overload flag");
      wait_n_sp(c_error_recovery_sp);
    end loop;
    AffirmIf(tid, true, "T5: overload (" & to_string(c_num_random) & " random frames)");

    ---------------------------------------------------------------------------
    -- T6: Error delimiter too late (dominant held during delimiter)
    ---------------------------------------------------------------------------
    for i in 1 to c_num_random loop
      randomize_frame;
      clear_events;
      submit_frame(v_id, v_format, v_dlc, brs => v_brs);
      wait_for_mon;
      wait_for_mon(check_error_flag => true);
      wait_n_sp(c_error_flag_width);
      override_kind <= force_dominant;
      wait_n_sp(c_error_delimiter_width + 1);
      override_kind <= idle;
      AffirmIf(tid, mon_rec.err_delim_late,
        "T6." & to_string(i) & ": error delimiter too late");
      AffirmIf(tid, mon_rec.err_delim_late_pol = c_recessive,
        "T6." & to_string(i) & ": MAC sends recessive during delimiter");
      wait_n_sp(c_error_recovery_sp);
    end loop;
    AffirmIf(tid, true, "T6: err delim late (" & to_string(c_num_random) & " random frames)");

    ---------------------------------------------------------------------------
    -- T7: Primary error during active error flag
    ---------------------------------------------------------------------------
    for i in 1 to c_num_random loop
      randomize_frame;
      clear_events;
      override_kind <= bit_error;
      override_pos  <= v_fp.dlc_start;
      submit_frame(v_id, v_format, v_dlc, brs => v_brs);
      wait_for_mon(check_error_flag => true);
      override_kind <= idle;
      AffirmIf(tid, mon_rec.error_flag_pos = v_fp.dlc_start,
        "T7." & to_string(i) & " error_flag_pos=" & to_string(mon_rec.error_flag_pos) &
        " expected " & to_string(v_fp.dlc_start));
      wait_n_sp(c_error_flag_width + 1);
      AffirmIf(tid, mon_rec.primary_error,
        "T7." & to_string(i) & ": primary error during active EF");
      AffirmIf(tid, mon_rec.primary_error_pol = c_dominant,
        "T7." & to_string(i) & ": MAC sends dominant during active EF");
      wait_n_sp(c_error_recovery_sp);
    end loop;
    AffirmIf(tid, true, "T7: primary error (" & to_string(c_num_random) & " random frames)");

    ---------------------------------------------------------------------------
    -- T8: Random bit errors at random positions
    ---------------------------------------------------------------------------
    for i in 1 to c_num_random loop
      randomize_frame;
      v_pos := rnd.RandInt(v_fp.dlc_start, v_fp.crc_delimiter - 1);

      clear_events;
      override_kind <= bit_error;
      override_pos  <= v_pos;
      submit_frame(v_id, v_format, v_dlc, brs => v_brs);
      wait_for_mon(check_error_flag => true);
      override_kind <= idle;
      wait_for_transfer_status(c_disturbed, 50,
        "T8." & to_string(i) & ": pos " & to_string(v_pos) &
        " fmt=" & to_hstring(v_format) & " dlc=" & to_hstring(v_dlc));
      AffirmIf(tid, mon_rec.fce_error,
        "T8." & to_string(i) & " fce error after bit error");
      AffirmIf(tid, mon_rec.fce_error_pol = c_dominant,
        "T8." & to_string(i) & " active EF drives dominant");
      AffirmIf(tid, mon_rec.error_flag_pos = v_pos,
        "T8." & to_string(i) & " error_flag_pos=" & to_string(mon_rec.error_flag_pos) &
        " expected " & to_string(v_pos));
      wait_n_sp(c_error_recovery_sp);
    end loop;
    AffirmIf(tid, true, "T8: random bit errors (" & to_string(c_num_random) & " random frames)");

    Log(tid, "All tests complete");
    EndOfTestReports(ReportAll => TRUE);
    std.env.finish;

  end process p_stim;

end architecture tb;
