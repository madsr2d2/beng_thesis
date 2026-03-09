--------------------------------------------------------------------------------
-- Title      : LLC Frame Adapter Testbench
-- Project    : CAN Bus Transmitter
--------------------------------------------------------------------------------
-- File       : llc_frame_adapter_tb.vhd
-- Standard   : VHDL-2008
--------------------------------------------------------------------------------
-- Description: Tests for the legacy LLC frame format adapter.
--   Tests verify that a 71-byte legacy frame is correctly translated to the
--   internal streaming format expected by tx_llc.
--
--   Test cases:
--     1. Classic Basic (CB): 11-bit ID, 1 byte data
--     2. Classic Extended (CE): 29-bit ID, 8 bytes data
--     3. FD Basic (FB) with BRS=1, ESI=0, 64 bytes data
--     4. FD Extended (FE) with BRS=1, ESI=1, RTR=1, 0 bytes data
--     5. Back-pressure: downstream ready deasserted mid-emit
--     6. Transfer status pass-through from tx_llc to user
--------------------------------------------------------------------------------

library ieee;
  use ieee.std_logic_1164.all;
  use ieee.numeric_std.all;

library osvvm;
  context osvvm.osvvmcontext;
  use work.can_types_pkg.all;
  use work.can_protocol_pkg.all;

entity llc_frame_adapter_tb is
end entity llc_frame_adapter_tb;

architecture tb of llc_frame_adapter_tb is

  constant clk_period : time := 10 ns;

  signal clk : std_logic := '0';
  signal rst : std_logic := '0';

  -- DUT ports
  signal legacy_llc_i : llc_user_to_llc_if_t;
  signal legacy_llc_o : llc_to_llc_user_if_t;
  signal llc_o        : llc_user_to_llc_if_t;
  signal llc_i        : llc_to_llc_user_if_t;

  -- legacy_frame_t and its index constants are defined in can_types_pkg

begin

  clk <= not clk after clk_period / 2;

  u_dut : entity work.llc_frame_adapter
    port map (
      clk_i        => clk,
      rst_i        => rst,
      legacy_llc_i => legacy_llc_i,
      legacy_llc_o => legacy_llc_o,
      llc_o        => llc_o,
      llc_i        => llc_i
    );

  ---------------------------------------------------------------------------
  -- Main test process
  ---------------------------------------------------------------------------
  main_tb_p : process is

    variable frame : legacy_frame_t;

    ---------------------------------------------------------------------------
    -- Send all 71 bytes of a legacy frame (blocks on ready handshake)
    ---------------------------------------------------------------------------
    procedure send_frame (frame_v : in legacy_frame_t) is
    begin

      for i in 0 to legacy_frame_len_c - 1 loop
        legacy_llc_i.avalon_st_source.data  <= frame_v(i);
        legacy_llc_i.avalon_st_source.valid <= '1';
        legacy_llc_i.avalon_st_source.sop   <= '1' when i = 0 else '0';
        legacy_llc_i.avalon_st_source.eop   <= '1' when i = legacy_frame_len_c - 1 else '0';
        loop
          wait until rising_edge(clk);
          exit when legacy_llc_o.avalon_st_sink.ready = '1';
        end loop;
      end loop;
      legacy_llc_i.avalon_st_source.valid <= '0';
      legacy_llc_i.avalon_st_source.sop   <= '0';
      legacy_llc_i.avalon_st_source.eop   <= '0';

    end procedure send_frame;

    ---------------------------------------------------------------------------
    -- Wait for the next valid byte from the adapter (downstream always ready)
    ---------------------------------------------------------------------------
    procedure wait_byte is
    begin
      loop
        wait until rising_edge(clk);
        exit when llc_o.avalon_st_source.valid = '1';
      end loop;
    end procedure wait_byte;

    ---------------------------------------------------------------------------
    -- Wait for the next valid byte and check expected data
    ---------------------------------------------------------------------------
    procedure check_byte (
      expected : in byte_t;
      tag      : in string
    ) is
    begin
      wait_byte;
      AffirmIfEqual(llc_o.avalon_st_source.data, expected, tag);
    end procedure check_byte;

  begin

    TranscriptOpen("sim/llc_frame_adapter_tb.txt");
    SetTranscriptMirror(TRUE);

    Print("==========================================");
    Print("LLC Frame Adapter Testbench Started");
    Print("==========================================");

    -- Initialise
    rst                                 <= '1';
    legacy_llc_i.avalon_st_source.data  <= (others => '0');
    legacy_llc_i.avalon_st_source.valid <= '0';
    legacy_llc_i.avalon_st_source.sop   <= '0';
    legacy_llc_i.avalon_st_source.eop   <= '0';
    legacy_llc_i.abort_request          <= '0';
    llc_i.avalon_st_sink.ready          <= '1';
    llc_i.transfer_status               <= ongoing;
    wait for clk_period * 5;

    rst <= '0';
    wait for clk_period;
    Print("Reset released");

    -- =========================================================================
    -- Test 1: Classic Basic (CB) frame - 11-bit ID=0x555, 1 byte data=0xAB
    -- =========================================================================
    Print("");
    Print("Test 1: Classic Basic (CB) - 11-bit ID=0x555, 1 byte data");
    Print("-----------");

    frame := (others => (others => '0'));
    -- CB 11-bit ID=0x555: byte2=00000_101, byte3=0x55
    frame(2)                      := "00000101";
    frame(3)                      := x"55";
    frame(legacy_fmt_dlc_byte_c)  := "0" & llc_fmt_cb_c & "0001";  -- FMT=CB, DLC=1
    frame(legacy_data_offset_c)   := x"AB";
    frame(legacy_flags_byte_c)    := (others => '0');

    send_frame(frame);

    -- config_byte_0: FMT=000, FTYP=0, ESI=0, BRS=0, pad=00 -> 0x00
    wait_byte;
    AffirmIfEqual(llc_o.avalon_st_source.sop,  '1', "T1: SOP on config_0");
    AffirmIfEqual(llc_o.avalon_st_source.data, x"00", "T1: config_byte_0");
    AffirmIfEqual(llc_o.avalon_st_source.eop,  '0', "T1: no EOP on config_0");

    -- config_byte_1: DLC=1 -> 0001_0000 = 0x10
    check_byte(x"10", "T1: config_byte_1");
    AffirmIfEqual(llc_o.avalon_st_source.sop, '0', "T1: no SOP on config_1");

    -- ID bytes: CB 11-bit ID=0x555 left-aligned in 32 bits
    -- 0x555 = 0101_0101_0101 (11 bits)
    -- id_buf[31:21] = 0x555 -> id_buf = 0b 0101_0101_0101 & 21 zeros
    -- Byte 0: bits[31:24] = 0b10101010 = 0xAA
    -- Byte 1: bits[23:16] = 0b10100000 = 0xA0
    -- Byte 2: bits[15:8]  = 0x00
    -- Byte 3: bits[7:0]   = 0x00
    check_byte(x"AA", "T1: ID byte 0");
    check_byte(x"A0", "T1: ID byte 1");
    check_byte(x"00", "T1: ID byte 2");
    check_byte(x"00", "T1: ID byte 3");

    -- Data byte (only 1, so EOP=1)
    wait_byte;
    AffirmIfEqual(llc_o.avalon_st_source.data, x"AB", "T1: data byte");
    AffirmIfEqual(llc_o.avalon_st_source.eop,  '1', "T1: EOP on last data byte");

    Print("Test 1: PASS");

    -- =========================================================================
    -- Test 2: Classic Extended (CE) - 29-bit ID=0x1AC05A55, 8 bytes data
    -- =========================================================================
    Print("");
    Print("Test 2: Classic Extended (CE) - 29-bit ID=0x1AC05A55, 8 bytes data");
    Print("-----------");

    frame := (others => (others => '0'));
    -- CE 29-bit ID=0x1AC05A55: byte0[4:0]=11010, byte1=0xC0, byte2=0x5A, byte3=0x55
    frame(0)                     := "00011010";
    frame(1)                     := x"C0";
    frame(2)                     := x"5A";
    frame(3)                     := x"55";
    frame(legacy_fmt_dlc_byte_c) := "0" & llc_fmt_ce_c & "1000";  -- FMT=CE, DLC=8
    for i in 0 to 7 loop
      frame(legacy_data_offset_c + i) := std_logic_vector(to_unsigned(i + 1, 8));
    end loop;
    frame(legacy_flags_byte_c) := (others => '0');

    send_frame(frame);

    -- config_byte_0: FMT=100, FTYP=0, ESI=0, BRS=0 -> 1000_0000 = 0x80
    wait_byte;
    AffirmIfEqual(llc_o.avalon_st_source.sop,  '1', "T2: SOP on config_0");
    AffirmIfEqual(llc_o.avalon_st_source.data, x"80", "T2: config_byte_0 (CE)");

    -- config_byte_1: DLC=8 -> 1000_0000 = 0x80
    check_byte(x"80", "T2: config_byte_1 (DLC=8)");

    -- CE ID: 29-bit ID=0x1AC05A55 packed left-aligned (bits[31:3])
    -- id_buf = 0x1AC05A55 << 3 = 0xD602D2A8
    -- Bytes: D6, 02, D2, A8
    check_byte(x"D6", "T2: ID byte 0");
    check_byte(x"02", "T2: ID byte 1");
    check_byte(x"D2", "T2: ID byte 2");
    check_byte(x"A8", "T2: ID byte 3");

    -- 8 data bytes: 0x01..0x08, EOP on last
    for i in 0 to 7 loop
      wait_byte;
      AffirmIfEqual(llc_o.avalon_st_source.data,
                    std_logic_vector(to_unsigned(i + 1, 8)),
                    "T2: data byte " & integer'image(i));
      if (i = 7) then
        AffirmIfEqual(llc_o.avalon_st_source.eop, '1', "T2: EOP on last data byte");
      else
        AffirmIfEqual(llc_o.avalon_st_source.eop, '0', "T2: no EOP mid-data");
      end if;
    end loop;

    Print("Test 2: PASS");

    -- =========================================================================
    -- Test 3: FD Basic (FB) - BRS=1, ESI=0, 64 bytes data (DLC=15)
    -- =========================================================================
    Print("");
    Print("Test 3: FD Basic (FB) - BRS=1, ESI=0, ID=0x123, DLC=15 (64 bytes)");
    Print("-----------");

    frame := (others => (others => '0'));
    -- FB 11-bit ID=0x123: byte2[2:0]=001, byte3=0x23
    frame(2)                     := "00000001";
    frame(3)                     := x"23";
    frame(legacy_fmt_dlc_byte_c) := "0" & llc_fmt_fb_c & "1111";  -- FMT=FB, DLC=15
    for i in 0 to 63 loop
      frame(legacy_data_offset_c + i) := std_logic_vector(to_unsigned(i, 8));
    end loop;
    frame(legacy_flags_byte_c) := "00000100";  -- BRS=1 (bit 2)

    send_frame(frame);

    -- config_byte_0: FMT=010, FTYP=0, ESI=0, BRS=1 -> 0100_0100 = 0x44
    wait_byte;
    AffirmIfEqual(llc_o.avalon_st_source.sop,  '1', "T3: SOP");
    AffirmIfEqual(llc_o.avalon_st_source.data, x"44", "T3: config_byte_0 (FB, BRS=1)");

    -- config_byte_1: DLC=15 -> 1111_0000 = 0xF0
    check_byte(x"F0", "T3: config_byte_1 (DLC=15)");

    -- FB 11-bit ID=0x123=0001_0010_0011 left-aligned
    -- Byte 0: id_buf[31:24]: raw_id[10:3] = 0b00010010 = 0x12... wait
    -- raw_id(10 downto 0) = "00100100011" = 0x123
    -- id_buf(31 downto 21) = raw_id(10 downto 0)
    -- id_buf(31) = raw_id(10) = 0
    -- id_buf(30) = raw_id(9)  = 0
    -- id_buf(29) = raw_id(8)  = 1
    -- id_buf(28) = raw_id(7)  = 0
    -- id_buf(27) = raw_id(6)  = 0
    -- id_buf(26) = raw_id(5)  = 1
    -- id_buf(25) = raw_id(4)  = 0
    -- id_buf(24) = raw_id(3)  = 0
    -- Byte 0 = 0b00100100 = 0x24
    -- id_buf(23) = raw_id(2) = 0
    -- id_buf(22) = raw_id(1) = 1
    -- id_buf(21) = raw_id(0) = 1
    -- id_buf(20:16) = 0
    -- Byte 1 = 0b01100000 = 0x60
    -- Bytes 2-3 = 0x00
    check_byte(x"24", "T3: ID byte 0");
    check_byte(x"60", "T3: ID byte 1");
    check_byte(x"00", "T3: ID byte 2");
    check_byte(x"00", "T3: ID byte 3");

    -- 64 data bytes: 0x00..0x3F, EOP on last
    for i in 0 to 63 loop
      wait_byte;
      AffirmIfEqual(llc_o.avalon_st_source.data,
                    std_logic_vector(to_unsigned(i, 8)),
                    "T3: data byte " & integer'image(i));
    end loop;
    AffirmIfEqual(llc_o.avalon_st_source.eop, '1', "T3: EOP on last data byte");

    Print("Test 3: PASS");

    -- =========================================================================
    -- Test 4: FD Extended (FE) - BRS=1, ESI=1, RTR=1, 0 bytes data
    -- =========================================================================
    Print("");
    Print("Test 4: FD Extended (FE) - BRS=1, ESI=1, RTR=1, DLC=0 (no data)");
    Print("-----------");

    frame := (others => (others => '0'));
    -- FE 29-bit ID=0x00000001
    frame(3)                     := x"01";
    frame(legacy_fmt_dlc_byte_c) := "0" & llc_fmt_fe_c & "0000";  -- FMT=FE, DLC=0
    frame(legacy_flags_byte_c)   := "00000111";  -- BRS=1, ESI=1, RTR=1

    send_frame(frame);

    -- config_byte_0: FMT=110, FTYP=1(RTR), ESI=1, BRS=1 -> 1101_1100 = 0xDC
    wait_byte;
    AffirmIfEqual(llc_o.avalon_st_source.sop,  '1', "T4: SOP");
    AffirmIfEqual(llc_o.avalon_st_source.data, x"DC", "T4: config_byte_0 (FE, all flags)");

    -- config_byte_1: DLC=0 -> 0x00
    check_byte(x"00", "T4: config_byte_1 (DLC=0)");

    -- FE 29-bit ID=1 -> id_buf[31:3] = 1 -> id_buf = 0x00000008
    check_byte(x"00", "T4: ID byte 0");
    check_byte(x"00", "T4: ID byte 1");
    check_byte(x"00", "T4: ID byte 2");

    -- Last ID byte: EOP=1 because no data
    wait_byte;
    AffirmIfEqual(llc_o.avalon_st_source.data, x"08", "T4: ID byte 3");
    AffirmIfEqual(llc_o.avalon_st_source.eop,  '1', "T4: EOP on last ID byte (no data)");

    Print("Test 4: PASS");

    -- =========================================================================
    -- Test 5: Back-pressure - downstream deasserts ready mid-emit
    -- =========================================================================
    Print("");
    Print("Test 5: Back-pressure - deassert downstream ready during ID emit");
    Print("-----------");

    frame := (others => (others => '0'));
    frame(2)                     := "00000001";
    frame(3)                     := x"00";
    frame(legacy_fmt_dlc_byte_c) := "0" & llc_fmt_cb_c & "0001";  -- CB, DLC=1
    frame(legacy_data_offset_c)  := x"FF";
    frame(legacy_flags_byte_c)   := (others => '0');

    send_frame(frame);

    -- Accept config_0 and config_1 with ready
    wait_byte;  -- config_0
    wait_byte;  -- config_1

    -- Now deassert downstream ready and verify adapter stalls
    llc_i.avalon_st_sink.ready <= '0';
    wait for clk_period * 3;
    wait until rising_edge(clk);
    AffirmIfEqual(llc_o.avalon_st_source.valid, '1', "T5: adapter holds valid during back-pressure");

    -- Re-enable and drain remaining bytes (4 ID + 1 data)
    llc_i.avalon_st_sink.ready <= '1';
    for i in 0 to 4 loop
      wait_byte;
    end loop;

    Print("Test 5: PASS");

    -- =========================================================================
    -- Test 6: Transfer status pass-through
    -- =========================================================================
    Print("");
    Print("Test 6: Transfer status pass-through");
    Print("-----------");

    llc_i.transfer_status <= transmitted;
    -- Wait 2 cycles: 1 for the signal to be sampled on the rising edge, and 1
    -- for the registered output (legacy_llc_o <= v_legacy_llc_o) to be visible
    -- on the port.  Checking after only 1 cycle reads the pre-update register.
    wait for clk_period * 2;
    AffirmIf(legacy_llc_o.transfer_status = transmitted, "T6: transmitted passthrough");

    llc_i.transfer_status <= ongoing;
    wait for clk_period * 2;
    AffirmIf(legacy_llc_o.transfer_status = ongoing, "T6: ongoing passthrough");

    Print("Test 6: PASS");

    -- =========================================================================
    -- Report
    -- =========================================================================
    Print("");
    Print("==========================================");
    ReportAlerts;
    Print("==========================================");

    std.env.stop;

  end process main_tb_p;

end architecture tb;
