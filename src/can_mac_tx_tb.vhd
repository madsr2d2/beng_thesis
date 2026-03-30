--------------------------------------------------------------------------------------------------------------------------------------------------------------
-- Copyright 2026 Everllence, Teglholmsgade 41, 2450 Copenhagen SV, Denmark
--------------------------------------------------------------------------------------------------------------------------------------------------------------
--
-- Requirements:
--
-- Description:   Testbench for can_mac_tx (ser + fsm + bs + crc).
--                  p_llc_vc           - LLC Avalon-ST source VC (byte driver).
--                  p_pcs_vc           - PCS sink VC (bit-level self-checking, ACK injection).
--                  p_test_ctrl        - Coverage-driven test sequencer with reference model.
--
-- Revision log:  Date:       Initial:  JIRA:
--                2026-03-28  MRDSA     [TRIT-4355] Initial implementation
--                2026-03-28  MRDSA     [TRIT-4355] Refactored: full bus stream reference model
--------------------------------------------------------------------------------------------------------------------------------------------------------------

library ieee;
  use ieee.std_logic_1164.all;
  use ieee.numeric_std.all;
  use work.pk_can_types.all;

library osvvm;
  context osvvm.OsvvmContext;
  use osvvm.ScoreboardPkg_slv.all;
library osvvm_common;
  context osvvm_common.OsvvmCommonContext;

entity can_mac_tx_tb is
  generic (
    gc_TbTimeOut   : time := 500 ms;
    gc_TbClkPeriod : time := 10 ns
  );
end entity can_mac_tx_tb;

architecture tb of can_mac_tx_tb is

  ----------------------------------------------------------------------------
  -- Constants
  ----------------------------------------------------------------------------
  constant c_sp_interval     : integer := 10;
  constant c_config_bytes    : integer := 2;
  constant c_first_data_byte : integer := c_config_bytes + c_llc_id_byte_count;
  constant c_cb_cov_bin      : integer := to_integer(unsigned(c_llc_fmt_cb));
  constant c_ce_cov_bin      : integer := to_integer(unsigned(c_llc_fmt_ce));
  constant c_fb_cov_bin      : integer := to_integer(unsigned(c_llc_fmt_fb));
  constant c_fe_cov_bin      : integer := to_integer(unsigned(c_llc_fmt_fe));
  constant c_bin_num         : integer := 5;
  constant c_max_bus_bits    : integer := 1024;
  constant c_rec_width       : integer := 16;

  -- Error injection position coverage range.
  -- Min: smallest reachable position (CB arb_end with no stuff bits) = 13.
  -- Max: safe ack_pos - 2 for FE DLC=15 with any data pattern ~ 580.
  constant c_min_err_pos  : integer := 13;
  constant c_max_err_pos  : integer := 580;
  constant c_pos_bin_num  : integer := 50;

  -- PCS VC subtypes / injection coverage bins (unified integer encoding).
  -- 0 = activate SP strobe (not an injection type).
  constant c_pcs_active              : integer := 0;
  constant c_inj_ack                 : integer := 1;
  constant c_inj_ack_error           : integer := 2;
  constant c_inj_error               : integer := 3;
  constant c_inj_lost_arb            : integer := 4;
  constant c_inj_overload            : integer := 5;
  constant c_inj_reactive_overload   : integer := 6;
  constant c_inj_error_delim_too_late : integer := 7;

  -- Offset from ack_pos to first intermission bit in the bus stream.
  -- ACK slot + ACK delimiter + EOF(7) = 1 + 1 + 7 = 9
  constant c_ifs_offset : integer := 1 + 1 + c_eof_field_width;

  -- Offset from error inject position to last error delimiter bit.
  -- Error starts at inject_pos+1: flag(6) + delimiter(8) = 14 bits.
  constant c_error_seq_offset : integer := 1 + c_error_flag_width + c_error_delimiter_width - 1;

  -- FCE state coverage bins (integer encoding)
  constant c_fce_active  : integer := 0;
  constant c_fce_passive : integer := 1;

  -- FCE latch bit positions (pulse events from fce_o)
  constant c_fce_successful_transfer   : integer := 0;
  constant c_fce_error                 : integer := 1;
  constant c_fce_primary_error         : integer := 2;
  constant c_fce_counters_unchanged    : integer := 3;
  constant c_fce_error_delim_too_late  : integer := 4;
  constant c_fce_latch_width           : integer := 5;

  ----------------------------------------------------------------------------
  -- Types
  ----------------------------------------------------------------------------
  type t_bus_stream is record
    bits             : std_logic_vector(0 to c_max_bus_bits - 1);
    len              : integer;
    ack_pos          : integer;
    arb_end          : integer;  -- first bus-stream index past the arbitration field
    fdf_pos          : integer;  -- stuffed index of FDF bit (-1 for CC)
    data_phase_start : integer;  -- stuffed index of ESI bit (-1 if no data phase)
    data_phase_end   : integer;  -- last stuffed index in data phase (-1 if no data phase)
  end record t_bus_stream;

  ----------------------------------------------------------------------------
  -- Signals
  ----------------------------------------------------------------------------
  signal clk   : std_logic;
  signal reset : std_logic;

  -- DUT interface
  signal llc_i : t_can_llc_mac_tx_if_s2d;
  signal llc_o : t_can_llc_mac_tx_if_d2s;
  signal pcs_i : t_can_mac_pcs_tx_if_s2m := c_pcs_to_mac_if_reset;
  signal pcs_o : t_can_mac_pcs_tx_if_m2s;
  signal fce_i : t_can_mac_fce_if_s2m    := c_fce_to_mac_if_reset;
  signal fce_o : t_can_mac_fce_if_m2s;

  signal bus_override    : std_logic := c_recessive;
  signal bus_override_en : boolean   := false;
  signal status_latch    : std_logic_vector(2 downto 0) := c_ongoing;
  signal fce_latch       : std_logic_vector(c_fce_latch_width - 1 downto 0) := (others => '0');

  -- Data-phase info for PCS VC (set by test sequencer before each frame)
  signal pcs_fdf_pos          : integer := -1;
  signal pcs_data_phase_start : integer := -1;
  signal pcs_data_phase_end   : integer := -1;

  -- OSVVM signals
  shared variable RV  : RandomPType;
  signal test_id         : AlertLogIDType;
  signal reset_check_id  : AlertLogIDType;
  signal status_check_id : AlertLogIDType;
  signal stream_check_id : AlertLogIDType;
  signal fce_check_id    : AlertLogIDType;
  signal fmt_cov      : CoverageIDType;
  signal dlc_cov      : CoverageIDType;
  signal inj_cov      : CoverageIDType;
  signal pos_cov      : CoverageIDType;
  signal fce_cov      : CoverageIDType;
  signal init_barrier : std_logic := '0';

  signal llc_rec : StreamRecType(
    DataToModel    (c_rec_width - 1 downto 0),
    ParamToModel   (c_rec_width - 1 downto 0),
    DataFromModel  (c_rec_width - 1 downto 0),
    ParamFromModel (c_rec_width - 1 downto 0)
  );
  signal pcs_rec : StreamRecType(
    DataToModel    (c_rec_width - 1 downto 0),
    ParamToModel   (c_rec_width - 1 downto 0),
    DataFromModel  (c_rec_width - 1 downto 0),
    ParamFromModel (c_rec_width - 1 downto 0)
  );
  signal fce_rec : StreamRecType(
    DataToModel    (c_rec_width - 1 downto 0),
    ParamToModel   (c_rec_width - 1 downto 0),
    DataFromModel  (c_rec_width - 1 downto 0),
    ParamFromModel (c_rec_width - 1 downto 0)
  );


  ----------------------------------------------------------------------------
  -- Utility functions
  ----------------------------------------------------------------------------
  function to_slv (b : std_logic) return std_logic_vector is
  begin
    return (0 downto 0 => b);
  end function to_slv;

  function to_gray (v : std_logic_vector) return std_logic_vector is
    variable r : std_logic_vector(v'range);
  begin
    r(v'left) := v(v'left);
    for i in v'left - 1 downto v'right loop
      r(i) := v(i) xor v(i + 1);
    end loop;
    return r;
  end function to_gray;

  function calc_parity (v : std_logic_vector) return std_logic is
    variable p : std_logic := '0';
  begin
    for i in v'range loop
      p := p xor v(i);
    end loop;
    return p;
  end function calc_parity;

  -- ISO 11898-1: 6.6.4.4 CRC calculation
  function f_calc_can_crc (
    data     : std_logic_vector;
    init_vec : std_logic_vector;
    poly     : std_logic_vector
  ) return std_logic_vector is
    variable crc      : std_logic_vector(init_vec'length - 1 downto 0);
    variable crc_next : std_logic;
  begin
    crc := init_vec;
    for i in data'range loop
      crc_next := data(i) xor crc(crc'high);
      crc      := crc sll 1;
      if crc_next then
        crc := crc xor poly;
      end if;
    end loop;
    return crc;
  end function f_calc_can_crc;

  function extract_metadata (
    config_byte_0 : t_byte;
    config_byte_1 : t_byte
  ) return t_llc_metadata is
    variable result : t_llc_metadata;
  begin
    result.format := config_byte_0(c_llc_frame_config_byte_0_format_start downto c_llc_frame_config_byte_0_format_end);
    result.ftyp   := config_byte_0(c_llc_frame_config_byte_0_ftyp);
    result.esi    := config_byte_0(c_llc_frame_config_byte_0_esi);
    result.brs    := config_byte_0(c_llc_frame_config_byte_0_brs);
    result.dlc    := config_byte_1(c_llc_frame_config_byte_1_dlc_start downto c_llc_frame_config_byte_1_dlc_end);
    return result;
  end function extract_metadata;

  ----------------------------------------------------------------------------
  -- Reference model
  --
  -- build_expected_bus_stream composes the full expected bus stream:
  --   1. build_raw_frame  - LLC frame -> raw unstuffed bit stream
  --   2. Dynamic stuffing + CRC input accumulation
  --   3. CRC region (CC: stuffed CRC-15; FD: FSB-interleaved SBC + CRC)
  --   4. Post-CRC: delimiter, ACK slot, delimiter, EOF
  --   5. Inter-frame space: intermission (3) + suspend (8 if passive)
  ----------------------------------------------------------------------------

  -- ========================================================================
  -- Step 1: Build the raw (unstuffed) frame bit stream by concatenating
  -- protocol fields directly from the LLC frame content.
  --
  -- ISO 11898-1 frame formats (SOF through last data bit):
  --   CB: SOF | BaseID(10:0) | RTR | IDE=0 | r0=0 | DLC(3:0) | Data
  --   CE: SOF | BaseID(10:0) | SRR=1 | IDE=1 | ExtID(17:0) | RTR | r1=0 | r0=0 | DLC(3:0) | Data
  --   FB: SOF | BaseID(10:0) | RRS=0 | IDE=0 | FDF=1 | res=0 | BRS | ESI | DLC(3:0) | Data
  --   FE: SOF | BaseID(10:0) | SRR=1 | IDE=1 | ExtID(17:0) | RRS=0 | FDF=1 | res=0 | BRS | ESI | DLC(3:0) | Data
  -- ========================================================================
  function build_raw_frame (
    frame    : t_llc_frame;
    metadata : t_llc_metadata
  ) return t_bus_stream is
    constant c_base_hi : integer := c_llc_id_stream_width - 1;
    constant c_base_lo : integer := c_llc_id_stream_width - c_base_id_width;
    constant c_ext_hi  : integer := c_base_lo - 1;
    constant c_ext_lo  : integer := c_base_lo - c_extended_id_width;

    variable r          : t_bus_stream;
    variable id_stream  : std_logic_vector(c_llc_id_stream_width - 1 downto 0);
    variable data_bytes : integer;

    procedure append (pol : std_logic) is
    begin
      r.bits(r.len) := pol;
      r.len         := r.len + 1;
    end procedure append;

    procedure append_vec (v : std_logic_vector) is
    begin
      for i in v'range loop
        append(v(i));
      end loop;
    end procedure append_vec;

    procedure append_data is
    begin
      for byte_idx in c_first_data_byte to c_first_data_byte + data_bytes - 1 loop
        for bit_idx in c_byte_width - 1 downto 0 loop
          append(frame(byte_idx)(bit_idx));
        end loop;
      end loop;
    end procedure append_data;

  begin
    r.len := 0;

    -- Flatten ID bytes (2-5) into a 32-bit vector, MSB first
    id_stream := frame(c_config_bytes)(c_byte_width - 1 downto 0)
               & frame(c_config_bytes + 1)(c_byte_width - 1 downto 0)
               & frame(c_config_bytes + 2)(c_byte_width - 1 downto 0)
               & frame(c_config_bytes + 3)(c_byte_width - 1 downto 0);

    -- Data byte count (RTR frames have no data field, CC only)
    data_bytes := dlc_to_data_length(
                    t_dlc(to_integer(unsigned(metadata.dlc))), metadata.format);
    if (metadata.format(1) = '0' and metadata.ftyp = '1') then
      data_bytes := 0;
    end if;

    -- SOF (always dominant)
    append(c_dominant);

    -- Base ID (11 bits, MSB first)
    append_vec(id_stream(c_base_hi downto c_base_lo));

    case metadata.format is
      when c_llc_fmt_cb =>
        append(metadata.ftyp);   -- RTR
        append(c_dominant);      -- IDE = 0
        append(c_dominant);      -- r0 = 0
        append_vec(metadata.dlc);
        append_data;

      when c_llc_fmt_ce =>
        append(c_recessive);     -- SRR = 1
        append(c_recessive);     -- IDE = 1
        append_vec(id_stream(c_ext_hi downto c_ext_lo));
        append(metadata.ftyp);   -- RTR
        append(c_dominant);      -- r1 = 0
        append(c_dominant);      -- r0 = 0
        append_vec(metadata.dlc);
        append_data;

      when c_llc_fmt_fb =>
        append(c_dominant);      -- RRS = 0
        append(c_dominant);      -- IDE = 0
        append(c_recessive);     -- FDF = 1
        append(c_dominant);      -- res = 0
        append(metadata.brs);    -- BRS
        append(metadata.esi);    -- ESI
        append_vec(metadata.dlc);
        append_data;

      when c_llc_fmt_fe =>
        append(c_recessive);     -- SRR = 1
        append(c_recessive);     -- IDE = 1
        append_vec(id_stream(c_ext_hi downto c_ext_lo));
        append(c_dominant);      -- RRS = 0
        append(c_recessive);     -- FDF = 1
        append(c_dominant);      -- res = 0
        append(metadata.brs);    -- BRS
        append(metadata.esi);    -- ESI
        append_vec(metadata.dlc);
        append_data;

      when others =>
        null;
    end case;

    return r;
  end function build_raw_frame;

 -- ========================================================================
  -- Build the complete expected bus stream for one LLC frame.
  --
  -- Dynamic stuffer: 5-consecutive-same rule, inserts complement bit.
  --   CC: CRC input = unstuffed raw bits only
  --   FD: CRC input = stuffed stream (raw + dynamic stuff bits + SBC)
  --
  -- CRC region:
  --   CC: CRC-15 bits fed through dynamic stuffer (continues from data)
  --   FD: SBC + CRC bits with a fixed stuff bit (FSB) every 4 data bits
  --
  -- Post-CRC: CRC delimiter + ACK slot + ACK delimiter + 7-bit EOF
  -- Phase 5: Inter-frame space (intermission + optional suspend)
  -- ========================================================================
  function build_expected_bus_stream (
    frame      : t_llc_frame;
    metadata   : t_llc_metadata;
    is_passive : boolean := false
  ) return t_bus_stream is
    variable raw    : t_bus_stream;
    variable result : t_bus_stream;
    variable is_fd  : boolean;

    -- Dynamic stuffer state
    variable consec   : integer range 0 to c_stuff_width := 0;
    variable last_pol : std_logic := c_recessive;
    variable ds_count : unsigned(2 downto 0) := (others => '0');

    -- CRC accumulator and result
    variable crc_in     : std_logic_vector(0 to c_max_bus_bits - 1);
    variable crc_in_len : integer := 0;
    variable crc        : t_crc_vector;
    variable crc_len    : integer;

    -- Append one bit to the bus stream
    procedure emit (pol : std_logic) is
    begin
      result.bits(result.len) := pol;
      result.len              := result.len + 1;
    end procedure emit;

    -- Append one bit to CRC input
    procedure crc_feed (pol : std_logic) is
    begin
      crc_in(crc_in_len) := pol;
      crc_in_len         := crc_in_len + 1;
    end procedure crc_feed;

    -- Feed one bit through the dynamic stuffer.
    -- FD: stuff bits feed CRC input. CC: they do not.
    procedure ds_feed (pol : std_logic) is
    begin
      emit(pol);
      if (is_fd) then
        crc_feed(pol);
      end if;

      if (pol = last_pol) then
        consec := consec + 1;
        if (consec = c_stuff_width) then
          emit(not pol);
          if (is_fd) then
            crc_feed(not pol);
          end if;
          consec   := 1;
          last_pol := not pol;
          ds_count := ds_count + 1;
        end if;
      else
        consec   := 1;
        last_pol := pol;
      end if;
    end procedure ds_feed;

    -- FD CRC region variables
    variable sbc            : t_sbc;
    variable gray           : std_logic_vector(2 downto 0);
    variable crc_region     : std_logic_vector(0 to c_sbc_field_width + c_crc_21_length - 1);
    variable crc_region_len : integer;
    variable fsb_counter    : integer;

    -- Raw bit count of the arbitration field (last arb bit + 1).
    -- Lost arb triggers on: base_id, rtr, and (extended only) srr, ide, ext_id.
    variable raw_arb_len : integer;

    -- Raw (unstuffed) positions of FDF and ESI bits (-1 for CC formats)
    variable raw_fdf : integer;
    variable raw_esi : integer;

  begin
    result.len              := 0;
    result.fdf_pos          := -1;
    result.data_phase_start := -1;
    result.data_phase_end   := -1;
    raw                     := build_raw_frame(frame, metadata);
    is_fd                   := metadata.format(1) = '1';

    -- Arbitration field length in raw (unstuffed) bits
    -- FDF and ESI raw positions (0-indexed):
    --   FB: SOF(0) BaseID(1-11) RRS(12) IDE(13) FDF(14) res(15) BRS(16) ESI(17)
    --   FE: SOF(0) BaseID(1-11) SRR(12) IDE(13) ExtID(14-31) RRS(32) FDF(33) res(34) BRS(35) ESI(36)
    case metadata.format is
      when c_llc_fmt_cb => raw_arb_len := 13; raw_fdf := -1; raw_esi := -1;
      when c_llc_fmt_fb => raw_arb_len := 12; raw_fdf := 14; raw_esi := 17;
      when c_llc_fmt_ce => raw_arb_len := 33; raw_fdf := -1; raw_esi := -1;
      when c_llc_fmt_fe => raw_arb_len := 32; raw_fdf := 33; raw_esi := 36;
      when others       => raw_arb_len := 13; raw_fdf := -1; raw_esi := -1;
    end case;

    -- CRC length: CC = 15, FD = 17 (data <= 16 bytes) or 21
    if (not is_fd) then
      crc_len := c_crc_15_length;
    elsif (dlc_to_data_length(t_dlc(to_integer(unsigned(metadata.dlc))),
                              metadata.format) < c_crc_17_length) then
      crc_len := c_crc_17_length;
    else
      crc_len := c_crc_21_length;
    end if;

    -- ----------------------------------------------------------------
    -- Phase 1: Dynamic-stuff the raw (pre-CRC) bits
    --   CC: raw bits feed CRC, stuff bits do not
    --   FD: both raw and stuff bits feed CRC (handled inside ds_feed)
    -- ----------------------------------------------------------------
    result.arb_end := 0;
    for i in 0 to raw.len - 1 loop
      if (not is_fd) then
        crc_feed(raw.bits(i));
      end if;
      ds_feed(raw.bits(i));

      -- Capture stuffed position AFTER ds_feed: the actual bit is
      -- always the last emitted (result.len - 1); any preceding stuff
      -- bit is at result.len - 2.
      if (i = raw_fdf) then
        result.fdf_pos := result.len - 1;
      end if;
      if (i = raw_esi and metadata.brs = '1') then
        result.data_phase_start := result.len - 1;
      end if;
      if (i = raw_arb_len - 1) then
        result.arb_end := result.len;
      end if;
    end loop;

    -- ----------------------------------------------------------------
    -- Phase 2: SBC (FD only) + CRC computation
    -- ----------------------------------------------------------------
    if (is_fd) then
      gray := to_gray(std_logic_vector(ds_count));
      sbc  := gray & calc_parity(gray);

      -- SBC feeds CRC input (FSBs do not)
      for i in c_sbc_field_width - 1 downto 0 loop
        crc_feed(sbc(i));
      end loop;
    end if;

    -- CRC computation (ISO 11898-1: Sec. 6.6.4.4)
    crc := (others => '0');
    case crc_len is
      when c_crc_17_length =>
        crc(c_crc_21_length - 1 downto c_crc_21_length - c_crc_17_length) :=
          f_calc_can_crc(crc_in(0 to crc_in_len - 1), c_crc_init_17_vec, c_crc_poly_17_vec);
      when c_crc_21_length =>
        crc := f_calc_can_crc(crc_in(0 to crc_in_len - 1), c_crc_init_21_vec, c_crc_poly_21_vec);
      when others =>
        crc(c_crc_21_length - 1 downto c_crc_21_length - c_crc_15_length) :=
          f_calc_can_crc(crc_in(0 to crc_in_len - 1), c_crc_init_15_vec, c_crc_poly_15_vec);
    end case;

    -- ----------------------------------------------------------------
    -- Phase 3: CRC region emission
    --   FD: FSB-interleaved SBC + CRC data (no dynamic stuffing)
    --   CC: CRC-15 bits fed through dynamic stuffer
    -- ----------------------------------------------------------------
    if (is_fd) then
      -- Build flat CRC region data: SBC(MSB first) & CRC(MSB first)
      crc_region_len := c_sbc_field_width + crc_len;
      for i in 0 to c_sbc_field_width - 1 loop
        crc_region(i) := sbc(c_sbc_field_width - 1 - i);
      end loop;
      for i in 0 to crc_len - 1 loop
        crc_region(c_sbc_field_width + i) := crc(c_crc_21_length - 1 - i);
      end loop;

      -- Emit with FSB every 4 data bits
      fsb_counter := 0;
      for i in 0 to crc_region_len - 1 loop
        if (fsb_counter = 0) then
          emit(not result.bits(result.len - 1));
        end if;
        emit(crc_region(i));
        fsb_counter := fsb_counter + 1;
        if (fsb_counter = c_stuff_width - 1) then
          fsb_counter := 0;
        end if;
      end loop;
    else
      for i in 0 to crc_len - 1 loop
        ds_feed(crc(c_crc_21_length - 1 - i));
      end loop;
    end if;

    -- Data phase ends just before CRC delimiter (first post-CRC bit)
    if (result.data_phase_start >= 0) then
      result.data_phase_end := result.len - 1;
    end if;

    -- ----------------------------------------------------------------
    -- Phase 4: Post-CRC (all recessive from TX perspective)
    -- ----------------------------------------------------------------
    result.ack_pos := result.len + c_ack_slot_offset;
    for i in 0 to 2 + c_eof_field_width - 1 loop
      emit(c_recessive);
    end loop;

    -- ----------------------------------------------------------------
    -- Phase 5: Inter-frame space (ISO 11898-1: 6.6.7)
    --   Intermission: 3 recessive bits
    --   Suspend:      8 recessive bits (error-passive transmitters only)
    -- ----------------------------------------------------------------
    for i in 0 to c_intermission_width - 1 loop
      emit(c_recessive);
    end loop;
    if (is_passive) then
      for i in 0 to c_suspend_transmission_width - 1 loop
        emit(c_recessive);
      end loop;
    end if;

    return result;
  end function build_expected_bus_stream;

  ----------------------------------------------------------------------------
  -- Generate a random, LLC frame and expected bus stream
  ----------------------------------------------------------------------------
  procedure generate_frame_and_stream (
    variable frame      : out t_llc_frame;
    variable metadata   : out t_llc_metadata;
    variable last_byte  : out integer;
    variable stream     : out t_bus_stream;
    constant is_passive : in  boolean := false
  ) is
  begin
    for i in frame'range loop
      frame(i) := RV.RandSlv(8);
    end loop;

    -- Coverage-driven format and DLC
    frame(0)(c_llc_frame_config_byte_0_format_start downto c_llc_frame_config_byte_0_format_end) :=
      std_logic_vector(to_unsigned(GetRandPoint(fmt_cov), 3));
    frame(1)(c_llc_frame_config_byte_1_dlc_start downto c_llc_frame_config_byte_1_dlc_end) :=
      std_logic_vector(to_unsigned(GetRandPoint(dlc_cov), 4));

    -- Keep ftyp consistent with DLC (FD ignores ftyp)
    if (frame(1)(c_llc_frame_config_byte_1_dlc_start downto c_llc_frame_config_byte_1_dlc_end) = "0000") then
      frame(0)(c_llc_frame_config_byte_0_ftyp) := '1';
    else
      frame(0)(c_llc_frame_config_byte_0_ftyp) := '0';
    end if;

    metadata  := extract_metadata(frame(0), frame(1));
    last_byte := c_first_data_byte + dlc_to_data_length(
                   t_dlc(to_integer(unsigned(metadata.dlc))), metadata.format) - 1;
    stream    := build_expected_bus_stream(frame, metadata, is_passive);
  end procedure generate_frame_and_stream;

  ----------------------------------------------------------------------------
  -- Truncate stream at inject_pos and append error flag + delimiter.
  -- Active: 6 dominant + 8 recessive. Passive: 6 recessive + 8 recessive.
  ----------------------------------------------------------------------------
  procedure apply_error_response (
    variable stream     : inout t_bus_stream;
    constant inject_pos : in    integer;
    constant is_passive : in    boolean := false
  ) is
    variable idx       : integer   := inject_pos;
    variable flag_pol  : std_logic;
  begin
    if (is_passive) then
      flag_pol := c_recessive;
    else
      flag_pol := c_dominant;
    end if;

    -- Error flag: 6 bits (dominant for active, recessive for passive)
    for i in 0 to c_error_flag_width - 1 loop
      stream.bits(idx) := flag_pol;
      idx := idx + 1;
    end loop;

    -- Error delimiter: 8 recessive bits
    for i in 0 to c_error_delimiter_width - 1 loop
      stream.bits(idx) := c_recessive;
      idx := idx + 1;
    end loop;

    -- Inter-frame space: intermission (3) + suspend (8 if passive)
    for i in 0 to c_intermission_width - 1 loop
      stream.bits(idx) := c_recessive;
      idx := idx + 1;
    end loop;
    if (is_passive) then
      for i in 0 to c_suspend_transmission_width - 1 loop
        stream.bits(idx) := c_recessive;
        idx := idx + 1;
      end loop;
    end if;

    stream.len := idx;
  end procedure apply_error_response;

  ----------------------------------------------------------------------------
  -- Append overload response at inject_pos (an intermission bit).
  -- The TX still outputs recessive at inject_pos (bus shows dominant from
  -- injection). Starting at inject_pos+1: overload flag (6 dominant) +
  -- delimiter (8 recessive) + new intermission (3) + optional suspend (8).
  ----------------------------------------------------------------------------
  procedure apply_overload_response (
    variable stream     : inout t_bus_stream;
    constant inject_pos : in    integer;
    constant is_passive : in    boolean := false
  ) is
    variable idx : integer := inject_pos + 1;
  begin
    -- Overload flag: 6 dominant bits
    for i in 0 to c_error_flag_width - 1 loop
      stream.bits(idx) := c_dominant;
      idx := idx + 1;
    end loop;

    -- Overload delimiter: 8 recessive bits
    for i in 0 to c_error_delimiter_width - 1 loop
      stream.bits(idx) := c_recessive;
      idx := idx + 1;
    end loop;

    -- New inter-frame space: intermission (3) + suspend (8 if passive)
    for i in 0 to c_intermission_width - 1 loop
      stream.bits(idx) := c_recessive;
      idx := idx + 1;
    end loop;
    if (is_passive) then
      for i in 0 to c_suspend_transmission_width - 1 loop
        stream.bits(idx) := c_recessive;
        idx := idx + 1;
      end loop;
    end if;

    stream.len := idx;
  end procedure apply_overload_response;

  ----------------------------------------------------------------------------
  -- Truncate stream at inject_pos and append error flag + delimiter +
  -- reactive overload flag + delimiter + IFS.
  -- Used for: c_inj_reactive_overload and c_inj_error_delim_too_late
  -- (both trigger overload via dominant at last error delimiter bit).
  ----------------------------------------------------------------------------
  procedure apply_reactive_overload_response (
    variable stream     : inOut t_bus_stream;
    constant inject_pos : in    integer;
    constant is_passive : in    boolean := false
  ) is
    variable idx      : integer   := inject_pos + 1;
    variable flag_pol : std_logic;
  begin
    flag_pol := c_recessive when is_passive else c_dominant;

    -- Error flag: 6 bits
    for i in 0 to c_error_flag_width - 1 loop
      stream.bits(idx) := flag_pol;
      idx := idx + 1;
    end loop;

    -- Error delimiter: 8 recessive (TX perspective; bus may show dominant)
    for i in 0 to c_error_delimiter_width - 1 loop
      stream.bits(idx) := c_recessive;
      idx := idx + 1;
    end loop;

    -- Overload flag: 6 dominant (triggered by dominant at last delimiter bit)
    for i in 0 to c_error_flag_width - 1 loop
      stream.bits(idx) := c_dominant;
      idx := idx + 1;
    end loop;

    -- Overload delimiter: 8 recessive
    for i in 0 to c_error_delimiter_width - 1 loop
      stream.bits(idx) := c_recessive;
      idx := idx + 1;
    end loop;

    -- IFS: intermission (3) + suspend (8 if passive)
    for i in 0 to c_intermission_width - 1 loop
      stream.bits(idx) := c_recessive;
      idx := idx + 1;
    end loop;
    if (is_passive) then
      for i in 0 to c_suspend_transmission_width - 1 loop
        stream.bits(idx) := c_recessive;
        idx := idx + 1;
      end loop;
    end if;

    stream.len := idx;
  end procedure apply_reactive_overload_response;

begin

  ----------------------------------------------------------------------------
  -- Infrastructure
  ----------------------------------------------------------------------------
  CreateClock(clk, gc_TbClkPeriod);
  CreateReset(reset, '1', clk, gc_TbClkPeriod * 10);

  p_timeout : process is
  begin
    wait for gc_TbTimeOut;
    assert false report "ERROR TEST FAILED, due to time out" severity error;
    std.env.stop(1);
  end process p_timeout;

  p_init : process is
    variable v_test_id     : AlertLogIDType;
    variable v_reset_id    : AlertLogIDType;
    variable v_status_id   : AlertLogIDType;
    variable v_stream_id   : AlertLogIDType;
    variable v_fce_chk_id  : AlertLogIDType;
    variable v_fmt_cov : CoverageIDType;
    variable v_dlc_cov : CoverageIDType;
    variable v_inj_cov : CoverageIDType;
    variable v_pos_cov : CoverageIDType;
    variable v_fce_cov : CoverageIDType;
  begin
    SetAlertStopCount(ERROR, 10);
    SetLogEnable(INFO, false);
    SetLogEnable(DEBUG, false);
    v_test_id := NewID("can_mac_tx");
    v_reset_id   := NewID("Reset check", v_test_id);
    v_status_id  := NewID("Transfer Status check", v_test_id);
    v_stream_id  := NewID("Bus stream check", v_test_id);
    v_fce_chk_id := NewID("FCE event check", v_test_id);

    v_fmt_cov := NewID("Format Coverage", v_test_id);
    v_dlc_cov := NewID("DLC Coverage", v_test_id);
    v_inj_cov := NewID("Error Injection Coverage", v_test_id);
    v_pos_cov := NewID("Error Injection Position Coverage", v_test_id);
    v_fce_cov := NewID("FCE State Coverage", v_test_id);
    pcs_rec.BurstFifo <= NewID("PCS VC Burst fifo");

    AddBins(v_fmt_cov, GenBin(c_bin_num, (c_cb_cov_bin, c_ce_cov_bin, c_fb_cov_bin, c_fe_cov_bin)));
    AddBins(v_dlc_cov, GenBin(c_bin_num, 0, c_dlc_max, c_dlc_max + 1));
    AddBins(v_inj_cov, GenBin(c_bin_num, (c_inj_ack, c_inj_ack_error, c_inj_error, c_inj_lost_arb,
                                         c_inj_overload, c_inj_reactive_overload,
                                         c_inj_error_delim_too_late)));
    AddBins(v_pos_cov, GenBin(1, c_min_err_pos, c_max_err_pos, c_pos_bin_num));
    AddBins(v_fce_cov, GenBin(c_bin_num, (c_fce_active, c_fce_passive)));

    test_id         <= v_test_id;
    reset_check_id  <= v_reset_id;
    status_check_id <= v_status_id;
    stream_check_id <= v_stream_id;
    fce_check_id    <= v_fce_chk_id;
    fmt_cov <= v_fmt_cov;
    dlc_cov <= v_dlc_cov;
   inj_cov <= v_inj_cov;
    pos_cov <= v_pos_cov;
    fce_cov <= v_fce_cov;

    WaitForBarrier(init_barrier);
    wait;
  end process p_init;

  ----------------------------------------------------------------------------
  -- DUT
  ----------------------------------------------------------------------------
  u_dut : entity work.can_mac_tx
    port map (
      clk   => clk,
      rst   => reset,
      llc_i => llc_i,
      llc_o => llc_o,
      pcs_i => pcs_i,
      pcs_o => pcs_o,
      fce_i => fce_i,
      fce_o => fce_o
    );

  ----------------------------------------------------------------------------
  -- FCE Verification Component
  -- SEND:  DataToModel(0) = error_passive_request, DataToModel(1) = error_active_request,
  --        DataToModel(2) = bus_off. Sets level signals on fce_i.
  -- CHECK: DataToModel(4:0) = expected fce_latch (sticky-OR of pulse events).
  --        Waits for status_latch to settle (frame complete), then compares.
  ----------------------------------------------------------------------------
  p_fce_vc : process is
  begin
    fce_i.error_passive_request <= '0';
    fce_i.error_active_request  <= '1';
    fce_i.bus_off               <= '0';
    WaitForBarrier(init_barrier);

    fce_vc_loop : loop
      WaitForTransaction(fce_rec.Rdy, fce_rec.Ack);
      case fce_rec.Operation is
        when SEND =>
          fce_i.error_passive_request <= fce_rec.DataToModel(0);
          fce_i.error_active_request  <= fce_rec.DataToModel(1);
          fce_i.bus_off               <= fce_rec.DataToModel(2);
        when CHECK =>
          wait until rising_edge(clk) and status_latch /= c_ongoing;
          AffirmIfEqual(fce_check_id, fce_latch, std_logic_vector(fce_rec.DataToModel(c_fce_latch_width - 1 downto 0)), "FCE events");
        when others => null;
      end case;
    end loop;
  end process p_fce_vc;

  ----------------------------------------------------------------------------
  -- Transfer status latch:
  -- Captures non-ongoing pulses; clears on SOP handshake
  ----------------------------------------------------------------------------
  p_status_latch : process (clk) is
  begin
    if rising_edge(clk) then
      if (reset = '1') then
        status_latch <= c_ongoing;
      elsif (llc_i.avalon_st_source.startofpacket = '1' and llc_o.avalon_st_sink.ready = '1') then
        status_latch <= llc_o.transfer_status;
      elsif (llc_o.transfer_status /= c_ongoing) then
        status_latch <= llc_o.transfer_status;
      end if;
    end if;
  end process p_status_latch;

  ----------------------------------------------------------------------------
  -- FCE event latch:
  -- Sticky-OR captures pulse events from fce_o; clears on SOP handshake
  ----------------------------------------------------------------------------
  p_fce_latch : process (clk) is
  begin
    if rising_edge(clk) then
      if (reset = '1') then
        fce_latch <= (others => '0');
      elsif (llc_i.avalon_st_source.startofpacket = '1' and llc_o.avalon_st_sink.ready = '1') then
        fce_latch <= (others => '0');
      else
        if (fce_o.successful_transfer = '1') then
          fce_latch(c_fce_successful_transfer) <= '1';
        end if;
        if (fce_o.error = '1') then
          fce_latch(c_fce_error) <= '1';
        end if;
        if (fce_o.primary_error = '1') then
          fce_latch(c_fce_primary_error) <= '1';
        end if;
        if (fce_o.counters_unchanged = '1') then
          fce_latch(c_fce_counters_unchanged) <= '1';
        end if;
        if (fce_o.error_delimiter_too_late = '1') then
          fce_latch(c_fce_error_delim_too_late) <= '1';
        end if;
      end if;
    end if;
  end process p_fce_latch;

  ----------------------------------------------------------------------------
  -- LLC Verification Component
  ----------------------------------------------------------------------------
  p_llc_vc : process is
  begin
    WaitForBarrier(init_barrier);

    llc_vc_loop : loop
      WaitForTransaction(llc_rec.Rdy, llc_rec.Ack);
      case llc_rec.Operation is
        when SEND =>
          -- Avalon-ST send
          llc_i.avalon_st_source.valid         <= '1';
          llc_i.avalon_st_source.data          <= std_logic_vector(llc_rec.DataToModel(t_byte'range));
          llc_i.avalon_st_source.startofpacket <= llc_rec.ParamToModel(1);
          llc_i.avalon_st_source.endofpacket   <= llc_rec.ParamToModel(0);
          wait until rising_edge(clk) and llc_o.avalon_st_sink.ready = '1';
          llc_i.avalon_st_source.valid <= '0';

        when CHECK =>
          wait until rising_edge(clk) and status_latch /= c_ongoing;
          AffirmIfEqual(status_check_id, status_latch, std_logic_vector(llc_rec.DataToModel(2 downto 0)), "Transfer status");

        when others => null;
      end case;
    end loop;
  end process p_llc_vc;

  ----------------------------------------------------------------------------
  -- PCS Verification Component
  ----------------------------------------------------------------------------
  p_pcs_vc : process is
    variable v_bus_idx      : integer;
    variable v_inject_pos   : integer;
    variable v_inject_pos_2 : integer;
    variable v_inject_end_2 : integer;
    variable v_subtype      : integer;
    variable v_sp_active           : boolean := false;
    variable v_checking            : boolean := false;
    variable v_burst_check_pending : boolean := false;
    variable v_sp_count            : integer range 0 to c_sp_interval - 1 := 0;

    -- Data-phase info (latched from signals at SEND_ASYNC)
    variable v_fdf_pos          : integer := -1;
    variable v_data_phase_start : integer := -1;
    variable v_data_phase_end   : integer := -1;

    -- Subtypes that use SP-time polarity flip for bit error injection
    function is_sp_error_subtype (st : integer) return boolean is
    begin
      return st = c_inj_error or st = c_inj_reactive_overload or st = c_inj_error_delim_too_late;
    end function is_sp_error_subtype;

    -------------------------------------------------------------------
    -- Inject: arm/disarm bus override at the programmed position(s).
    -- SP-error subtypes flip bus_polarity at SP time (handled in SP block).
    -- Dominant subtypes (ACK, lost_arb, overload) override to c_dominant.
    -- Secondary injection: range [v_inject_pos_2, v_inject_end_2].
    -------------------------------------------------------------------
    procedure inject is
    begin
      -- Primary injection position
      if (v_bus_idx = v_inject_pos) then
        if (v_subtype = c_inj_ack or v_subtype = c_inj_lost_arb or v_subtype = c_inj_overload) then
          bus_override <= c_dominant;
        end if;
        if (v_subtype /= c_inj_ack_error) then
          bus_override_en <= true;
        end if;

      elsif (v_bus_idx = v_inject_pos + 1) then
        bus_override_en <= false;
      end if;

      -- Secondary injection: range [v_inject_pos_2, v_inject_end_2]
      if (v_inject_pos_2 > 0) then
        if (v_bus_idx = v_inject_pos_2) then
          bus_override    <= c_dominant;
          bus_override_en <= true;
        elsif (v_bus_idx = v_inject_end_2 + 1) then
          bus_override_en <= false;
        end if;
      end if;
    end procedure inject;

  begin
    pcs_i.sp           <= '0';
    pcs_i.ssp          <= '0';
    pcs_i.tdc_delay    <= (others => '0');
    pcs_i.bus_polarity <= c_recessive;
    bus_override_en    <= false;
    WaitForBarrier(init_barrier);
    FinishTransaction(pcs_rec.Ack);

    pcs_vc_loop : loop
      wait until rising_edge(clk);

      ---------------------------------------------------------------
      -- Continuous: SP strobe generation with bus loopback
      ---------------------------------------------------------------
      pcs_i.sp <= '0';
      if (v_sp_active) then
        if (v_sp_count = c_sp_interval - 1) then
          if (bus_override_en and is_sp_error_subtype(v_subtype)) then
            pcs_i.bus_polarity <= not pcs_o.polarity;
          elsif (bus_override_en) then
            pcs_i.bus_polarity <= bus_override;
          else
            pcs_i.bus_polarity <= pcs_o.polarity;
          end if;
          pcs_i.sp <= '1';
          v_sp_count := 0;
        else
          v_sp_count := v_sp_count + 1;
        end if;
      end if;

      -- SSP strobe generation is NOT modelled at the MAC level.
      -- The FSM's TDC/SSP path requires the PCS's TDC FIFO to
      -- correctly correlate polarity_history(tdc_delay) with
      -- bus_polarity.  SSP-based error detection is tested at the
      -- can_tx_tb integration level where the full PCS is present.
      pcs_i.ssp <= '0';

      ---------------------------------------------------------------
      -- Bit checking: pop-and-compare on SP, finish when FIFO empty.
      -- First pop waits for valid='1' (frame start). After that,
      -- checks every SP including inter-frame space (valid='0').
      -- Also checks use_data_rate and start_tdc at each SP.
      ---------------------------------------------------------------
      if (v_checking) then
        if (pcs_i.sp = '1' and (pcs_o.valid = '1' or v_bus_idx > 0)) then
          AffirmIfEqual(stream_check_id, to_slv(pcs_o.polarity), Pop(pcs_rec.BurstFifo),
                        "PCS bit " & to_string(v_bus_idx));

          -- Check use_data_rate
          if (v_data_phase_start >= 0 and v_bus_idx >= v_data_phase_start
              and v_bus_idx <= v_data_phase_end) then
            AffirmIfEqual(stream_check_id, pcs_o.use_data_rate, '1',
                          "use_data_rate=1 at bit " & to_string(v_bus_idx));
          else
            AffirmIfEqual(stream_check_id, pcs_o.use_data_rate, '0',
                          "use_data_rate=0 at bit " & to_string(v_bus_idx));
          end if;

          -- Check start_tdc (single pulse at FDF bit)
          if (v_fdf_pos >= 0 and v_bus_idx = v_fdf_pos) then
            AffirmIfEqual(stream_check_id, pcs_o.start_tdc, '1',
                          "start_tdc=1 at FDF bit " & to_string(v_bus_idx));
          else
            AffirmIfEqual(stream_check_id, pcs_o.start_tdc, '0',
                          "start_tdc=0 at bit " & to_string(v_bus_idx));
          end if;

          v_bus_idx := v_bus_idx + 1;
          inject;
        end if;

        if (v_bus_idx > 0 and GetFifoCount(pcs_rec.BurstFifo) = 0) then
          bus_override_en <= false;
          v_checking      := false;
          if (v_burst_check_pending) then
            v_burst_check_pending := false;
            FinishTransaction(pcs_rec.Ack);
          end if;
        end if;
      end if;

      ---------------------------------------------------------------
      -- Transaction dispatch
      ---------------------------------------------------------------
      if (TransactionPending(pcs_rec.Rdy, pcs_rec.Ack)) then
        case pcs_rec.Operation is
          when SEND_ASYNC =>
            v_subtype := to_integer(unsigned(pcs_rec.DataToModel));

            if (v_subtype = c_pcs_active) then
              v_sp_active := true;
              v_sp_count  := 0;
              v_bus_idx   := 0;

            else
              v_inject_pos   := to_integer(unsigned(pcs_rec.ParamToModel));
              v_inject_pos_2 := 0;
              v_inject_end_2 := 0;

              -- Latch data-phase info from signals
              v_fdf_pos          := pcs_fdf_pos;
              v_data_phase_start := pcs_data_phase_start;
              v_data_phase_end   := pcs_data_phase_end;

              -- Compute secondary injection positions per subtype
              if (v_subtype = c_inj_overload) then
                v_inject_pos_2 := v_inject_pos + c_ifs_offset;
                v_inject_end_2 := v_inject_pos_2;
              elsif (v_subtype = c_inj_reactive_overload) then
                v_inject_pos_2 := v_inject_pos + c_error_seq_offset;
                v_inject_end_2 := v_inject_pos_2;
              elsif (v_subtype = c_inj_error_delim_too_late) then
                v_inject_pos_2 := v_inject_pos + 1 + c_error_flag_width;
                v_inject_end_2 := v_inject_pos_2 + c_error_delimiter_width - 1;
              end if;

              v_checking := true;
            end if;
            FinishTransaction(pcs_rec.Ack);

          when CHECK_BURST =>
            if (v_checking) then
              v_burst_check_pending := true;
            else
              FinishTransaction(pcs_rec.Ack);
            end if;

          when others =>
            FinishTransaction(pcs_rec.Ack);
        end case;
      end if;
    end loop;
  end process p_pcs_vc;

  ----------------------------------------------------------------------------
  -- Test sequencer
  ----------------------------------------------------------------------------
  p_test_ctrl : process is
    variable v_frame       : t_llc_frame;
    variable v_metadata    : t_llc_metadata;
    variable v_last_byte   : integer;
    variable v_frame_count : integer := 0;
    variable v_stream      : t_bus_stream;
    variable v_inj_type    : integer;
    variable v_inj_pos     : integer;
    variable v_candidate   : integer;
    variable v_inj_subtype : integer;
    variable v_exp_status  : std_logic_vector(2 downto 0);
    variable v_exp_fce     : std_logic_vector(c_fce_latch_width - 1 downto 0);
    variable v_fce_state   : integer;
    variable v_is_passive  : boolean;
  begin
    WaitForBarrier(init_barrier);
    wait until reset = '0';
    WaitForClock(clk, 5);

    Print("----------------------------------------------------------------------------");
    Print("Test 1: Reset");
    Print("----------------------------------------------------------------------------");
    AffirmIfEqual(reset_check_id, llc_o.transfer_status, c_ongoing, "LLC transfer_status");
    AffirmIfEqual(reset_check_id, llc_o.avalon_st_sink.ready, '1', "LLC ready");
    AffirmIfEqual(reset_check_id, pcs_o.polarity, c_recessive, "PCS polarity");
    AffirmIfEqual(reset_check_id, pcs_o.valid, '0', "PCS valid");
    AffirmIfEqual(reset_check_id, pcs_o.use_data_rate, '0', "PCS use_data_rate");
    AffirmIfEqual(reset_check_id, pcs_o.start_tdc, '0', "PCS start_tdc");
    AffirmIfEqual(reset_check_id, fce_o.transmitting, '0', "FCE transmitting");
    AffirmIfEqual(reset_check_id, fce_o.error, '0', "FCE error");
    AffirmIfEqual(reset_check_id, fce_o.primary_error, '0', "FCE primary_error");
    AffirmIfEqual(reset_check_id, fce_o.sending_error_overload_flag, '0', "FCE sending_error_overload_flag");
    AffirmIfEqual(reset_check_id, fce_o.counters_unchanged, '0', "FCE counters_unchanged");
    AffirmIfEqual(reset_check_id, fce_o.error_delimiter_too_late, '0', "FCE error_delimiter_too_late");
    AffirmIfEqual(reset_check_id, fce_o.successful_transfer, '0', "FCE successful_transfer");

    -- ======================================================================
    -- Test 2: Bus reintegration (11 recessive SPs before bus_idle)
    -- ======================================================================
    Print("----------------------------------------------------------------------------");
    Print("Test 2: Bus reintegration (11 recessive SPs before bus_idle)");
    Print("----------------------------------------------------------------------------");
    -- Activate SP strobes; FSM should remain in s_bus_reintegration for 11 SPs
    SendAsync(pcs_rec, std_logic_vector(to_unsigned(c_pcs_active, c_rec_width)));
    for sp_idx in 0 to c_bus_idle_condition_width - 2 loop
      wait until rising_edge(clk) and pcs_i.sp = '1';
      AffirmIfEqual(reset_check_id, pcs_o.valid, '0',
                    "Reintegration: valid=0 at SP " & to_string(sp_idx));
    end loop;
    -- After the 11th SP the FSM transitions to s_bus_idle (still valid='0')
    wait until rising_edge(clk) and pcs_i.sp = '1';
    AffirmIfEqual(reset_check_id, pcs_o.valid, '0',
                  "Bus idle: valid=0 (no pending frame)");

    -- ======================================================================
    -- Test 3: Drive random LLC frames and check BUS stream until coverage met
    -- ======================================================================
    Print("----------------------------------------------------------------------------");
    Print("Test 3: Drive random LLC frames and check BUS stream until coverage met");
    Print("----------------------------------------------------------------------------");
    frame_loop : while not (IsCovered(fmt_cov) and IsCovered(dlc_cov) and
                            IsCovered(inj_cov) and IsCovered(pos_cov) and
                            IsCovered(fce_cov)) loop
      v_frame_count := v_frame_count + 1;

      -- Coverage-driven FCE state (must precede stream generation for suspend bits)
      v_fce_state  := GetRandPoint(fce_cov);
      v_is_passive := v_fce_state = c_fce_passive;

      generate_frame_and_stream(v_frame, v_metadata, v_last_byte, v_stream, v_is_passive);

      if (v_is_passive) then
        Send(fce_rec, x"0001");  -- error_passive=1, error_active=0, bus_off=0
      else
        Send(fce_rec, x"0002");  -- error_passive=0, error_active=1, bus_off=0
      end if;

      -- Coverage-driven injection type.
      -- Once inj_cov is met, focus on position coverage.
      if (IsCovered(inj_cov) and not IsCovered(pos_cov)) then
        v_inj_type := c_inj_error;
      else
        v_inj_type := GetRandPoint(inj_cov);
      end if;

      v_exp_fce := (others => '0');

      case v_inj_type is
        when c_inj_ack =>
          v_inj_subtype := c_inj_ack;
          v_inj_pos     := v_stream.ack_pos;
          v_exp_status  := c_transmitted;
          v_exp_fce(c_fce_successful_transfer) := '1';

        when c_inj_ack_error =>
          v_inj_subtype := c_inj_ack_error;
          v_inj_pos     := v_stream.ack_pos;
          v_exp_status  := c_disturbed;
          v_exp_fce(c_fce_error) := '1';
          if (v_is_passive) then
            -- ISO 8.1.4.2 rule c) Exception 1: passive TX ACK error,
            -- no dominant seen during passive EF -> counters_unchanged
            v_exp_fce(c_fce_counters_unchanged) := '1';
          else
            -- Active error flag transmits dominant -> primary_error fires
            v_exp_fce(c_fce_primary_error) := '1';
          end if;
          -- ACK error detected at ACK delimiter (ack_pos + 1), error flag
          -- starts at bit after that: ack_pos + 2
          apply_error_response(v_stream, v_stream.ack_pos + 2, v_is_passive);

        when c_inj_error =>
          v_inj_subtype := c_inj_error;
          -- Coverage-driven position: try uncovered bins that fit within
          -- this frame's valid range [arb_end, ack_pos-2].
          -- Arb field excluded (ISO 6.6.21.2.a Exception 1).
          v_inj_pos := RV.RandInt(v_stream.arb_end, v_stream.ack_pos - 2);
          for attempt in 0 to 9 loop
            v_candidate := GetRandPoint(pos_cov);
            if (v_candidate >= v_stream.arb_end and v_candidate <= v_stream.ack_pos - 2) then
              v_inj_pos := v_candidate;
              exit;
            end if;
          end loop;
          v_exp_status  := c_disturbed;
          v_exp_fce(c_fce_error) := '1';
          if (not v_is_passive) then
            v_exp_fce(c_fce_primary_error) := '1';
          end if;
          apply_error_response(v_stream, v_inj_pos + 1, v_is_passive);

        when c_inj_lost_arb =>
          v_inj_subtype := c_inj_lost_arb;
          v_exp_status  := c_lost_arb;
          v_frame(c_config_bytes)(c_byte_width - 1) := c_recessive;
          v_metadata := extract_metadata(v_frame(0), v_frame(1));
          v_stream   := build_expected_bus_stream(v_frame, v_metadata, v_is_passive);
          v_inj_pos    := 1;
          v_stream.len := v_inj_pos + 1;

        when c_inj_overload =>
          v_inj_subtype := c_inj_overload;
          v_inj_pos     := v_stream.ack_pos;
          v_exp_status  := c_transmitted;
          v_exp_fce(c_fce_successful_transfer) := '1';
          apply_overload_response(v_stream, v_stream.ack_pos + c_ifs_offset, v_is_passive);

        when c_inj_reactive_overload =>
          -- Bit error + dominant at last error delimiter bit -> reactive OF
          v_inj_subtype := c_inj_reactive_overload;
          v_inj_pos     := RV.RandInt(v_stream.arb_end, v_stream.ack_pos - 2);
          v_exp_status  := c_disturbed;
          v_exp_fce(c_fce_error) := '1';
          if (not v_is_passive) then
            v_exp_fce(c_fce_primary_error) := '1';
          end if;
          apply_reactive_overload_response(v_stream, v_inj_pos, v_is_passive);

        when c_inj_error_delim_too_late =>
          -- Bit error + 8 dominant during error delimiter
          v_inj_subtype := c_inj_error_delim_too_late;
          v_inj_pos     := RV.RandInt(v_stream.arb_end, v_stream.ack_pos - 2);
          v_exp_status  := c_disturbed;
          v_exp_fce(c_fce_error) := '1';
          v_exp_fce(c_fce_error_delim_too_late) := '1';
          if (not v_is_passive) then
            v_exp_fce(c_fce_primary_error) := '1';
          end if;
          -- Same TX output as reactive overload (overload triggered by
          -- dominant at last delimiter bit)
          apply_reactive_overload_response(v_stream, v_inj_pos, v_is_passive);

        when others =>
          null;
      end case;

      Log(test_id, "Frame " & to_string(v_frame_count) &
          " fmt=" & to_hstring(v_metadata.format) &
          " dlc=" & to_hstring(v_metadata.dlc) &
          " inj=" & to_string(v_inj_type) &
          " pos=" & to_string(v_inj_pos) &
          " fce=" & to_string(v_fce_state) &
          " len=" & to_string(v_stream.len) &
          " fdf=" & to_string(v_stream.fdf_pos) &
          " dp_start=" & to_string(v_stream.data_phase_start) &
          " dp_end=" & to_string(v_stream.data_phase_end) &
          " ack=" & to_string(v_stream.ack_pos) &
          " arb_end=" & to_string(v_stream.arb_end), DEBUG);

      -- Compute effective data-phase bounds for PCS VC checks.
      -- Error injection during data phase truncates the data-phase end.
      -- Lost arb truncates before any FD fields.
      pcs_fdf_pos          <= v_stream.fdf_pos;
      pcs_data_phase_start <= v_stream.data_phase_start;
      pcs_data_phase_end   <= v_stream.data_phase_end;
      case v_inj_type is
        when c_inj_lost_arb =>
          pcs_fdf_pos          <= -1;
          pcs_data_phase_start <= -1;
          pcs_data_phase_end   <= -1;
        when c_inj_error | c_inj_reactive_overload | c_inj_error_delim_too_late =>
          if (v_stream.fdf_pos >= 0 and v_inj_pos < v_stream.fdf_pos) then
            pcs_fdf_pos <= -1;
          end if;
          if (v_stream.data_phase_start >= 0 and v_inj_pos < v_stream.data_phase_start) then
            pcs_data_phase_start <= -1;
            pcs_data_phase_end   <= -1;
          elsif (v_stream.data_phase_start >= 0 and v_inj_pos <= v_stream.data_phase_end) then
            pcs_data_phase_end <= v_inj_pos;
          end if;
        when c_inj_ack_error =>
          -- Error after ACK delimiter; full data phase already complete
          null;
        when others =>
          null;
      end case;

      -- Configure PCS VC
      SendAsync(pcs_rec, std_logic_vector(to_unsigned(c_pcs_active, c_rec_width)));
      SendAsync(pcs_rec, std_logic_vector(to_unsigned(v_inj_subtype, c_rec_width)),
                         std_logic_vector(to_unsigned(v_inj_pos, c_rec_width)));

      -- Push expected bus stream before driving bytes (PCS VC pops on SP)
      for i in 0 to v_stream.len - 1 loop
        Push(pcs_rec.BurstFifo, to_slv(v_stream.bits(i)));
      end loop;

      -- Drive frame through DUT (PCS VC checks concurrently)
      Send(llc_rec, v_frame(0), "10");
      Send(llc_rec, v_frame(1), "00");

      for i in c_config_bytes to v_last_byte loop
        Send(llc_rec, v_frame(i), "00");
      end loop;

      -- Check received bit stream
      CheckBurst(pcs_rec, GetFifoCount(pcs_rec.BurstFifo));

      -- Check transfer status via latch (handles transient statuses)
      Check(llc_rec, v_exp_status);

      -- Check FCE events via latch (waits for status_latch to settle)
      Check(fce_rec, std_logic_vector(resize(unsigned(v_exp_fce), c_rec_width)));

      -- Only sample coverage on successful transmission
      if (v_inj_type = c_inj_ack or v_inj_type = c_inj_overload) then
        ICover(fmt_cov, to_integer(unsigned(v_metadata.format)));
        ICover(dlc_cov, to_integer(unsigned(v_metadata.dlc)));
      end if;
      ICover(inj_cov, v_inj_type);
      ICover(fce_cov, v_fce_state);
      if (v_inj_type = c_inj_error) then
        ICover(pos_cov, v_inj_pos);
      end if;

      -- No explicit recovery wait needed: the expected stream now includes
      -- inter-frame space (intermission + suspend), so CheckBurst blocks
      -- until the PCS VC has verified all bits including recovery.

    end loop frame_loop;

    AffirmIf(GetAlertLogID(fmt_cov), IsCovered(fmt_cov), "Format coverage met");
    AffirmIf(GetAlertLogID(dlc_cov), IsCovered(dlc_cov), "DLC coverage met");
    AffirmIf(GetAlertLogID(inj_cov), IsCovered(inj_cov), "Injection coverage met");
    AffirmIf(GetAlertLogID(pos_cov), IsCovered(pos_cov), "Position coverage met");
    AffirmIf(GetAlertLogID(fce_cov), IsCovered(fce_cov), "FCE State coverage met");

    Print("----------------------------------------------------------------------------");
    Print("Test done!");
    Print("----------------------------------------------------------------------------");
    WriteBin(fmt_cov);
    WriteBin(dlc_cov);
    WriteBin(inj_cov);
    WriteBin(pos_cov);
    WriteBin(fce_cov);
    EndOfTestReports(ReportAll => true);
    std.env.finish;
    wait;

  end process p_test_ctrl;

end architecture tb;
