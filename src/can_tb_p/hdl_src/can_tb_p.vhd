--------------------------------------------------------------------------------------------------------------------------------------------------------------
-- Copyright 2026 Everllence, Teglholmsgade 41, 2450 Copenhagen SV, Denmark
--------------------------------------------------------------------------------------------------------------------------------------------------------------
--
-- Requirements:
--
-- Description: Testbench utility package for the CAN/CAN-FD design.
--              CRC calculation, metadata extraction, and bus stream
--              reference model for simulation verification.
--
-- Revision log:  Date:       Initial:  JIRA:
--                2026-04-10  MRDSA     Extracted from pk_can_types (TB-only utilities)
--------------------------------------------------------------------------------------------------------------------------------------------------------------

library ieee;
  use ieee.std_logic_1164.all;
  use ieee.numeric_std.all;
  use work.pk_can_types.all;

package pk_can_tb is

  -- CRC calculation per ISO 11898-1: 6.6.4.4 (Galois LFSR)
  function f_calc_can_crc (data : std_logic_vector; init_vec : std_logic_vector; poly : std_logic_vector) return std_logic_vector;

  -- Extract LLC metadata from config bytes 0 and 1
  function extract_metadata (config_byte_0 :std_logic_vector; config_byte_1 :std_logic_vector) return t_llc_metadata;

  -- Bus stream reference model: generates expected CAN bus bitstream from LLC frame
  constant c_max_bus_bits : natural := 1024;

  type t_bus_stream is record
    bits             : std_logic_vector(0 to c_max_bus_bits - 1);
    len              : integer;
    ack_pos          : integer;
    arb_end          : integer;
    fdf_pos          : integer;
    data_phase_start : integer;
    data_phase_end   : integer;
  end record t_bus_stream;

  function build_cc_stream (frame : t_llc_frame; metadata : t_llc_metadata; is_passive : boolean := false) return t_bus_stream;
  function build_fd_stream (frame : t_llc_frame; metadata : t_llc_metadata; is_passive : boolean := false) return t_bus_stream;
  function build_bus_stream (frame : t_llc_frame; metadata : t_llc_metadata; is_passive : boolean := false) return t_bus_stream;

end package pk_can_tb;

package body pk_can_tb is

  -- Algorithm from ISO 6.6.4.4
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

  function extract_metadata (config_byte_0 :std_logic_vector; config_byte_1 :std_logic_vector) return t_llc_metadata is
    variable v_result : t_llc_metadata;
  begin
    v_result.ide  := config_byte_0(c_llc_frame_ide);
    v_result.fdf  := config_byte_0(c_llc_frame_fdf);
    v_result.ftyp := config_byte_0(c_llc_frame_ftyp);
    v_result.esi  := config_byte_0(c_llc_frame_esi);
    v_result.brs  := config_byte_0(c_llc_frame_brs);
    v_result.dlc  := config_byte_1(c_llc_frame_dlc_start downto c_llc_frame_dlc_end);
    return v_result;
  end function extract_metadata;

  -----------------------------------------------------------------
  -- Bus stream reference model: generates the expected bus bit
  -- sequence for a CAN/CAN-FD frame.
  -----------------------------------------------------------------

  -- Append a multi-bit field MSB-first
  procedure append (v : std_logic_vector; raw : inout std_logic_vector; raw_len : inOut natural) is
    variable va : std_logic_vector(v'length - 1 downto 0) := v;
  begin
    for i in va'length - 1 downto 0 loop
      raw(raw_len) := va(i);
      raw_len      := raw_len + 1;
    end loop;
  end procedure append;

  -- Append a single bit
  procedure append_bit (b : std_logic; raw : inOut std_logic_vector; raw_len : inOut natural) is
  begin
    raw(raw_len) := b;
    raw_len      := raw_len + 1;
  end procedure append_bit;

  -- Convenience record keeping track of the stuff state
  type t_stuff_state is record
    consec         : natural;              -- consecutive same-polarity bits (dynamic)
    last_pol       : std_logic;            -- last bit on the wire
    ds_count       : unsigned(2 downto 0); -- dynamic stuff bit count (for SBC)
    bits_since_fsb : natural;              -- real bits since last FSB (fixed)
    just_stuffed   : boolean;              -- last dyn call inserted a stuff bit
  end record;

  constant c_stuff_state_init : t_stuff_state := (
    consec         => 0,
    last_pol       => c_recessive,
    ds_count       => (others => '0'),
    bits_since_fsb => 0,
    just_stuffed   => false
  );

  -- Bit stuffing procedure
  -- fixed=false: 5-in-a-row (dynamic bit stuffing)
  -- fixed=true: 1 FSB per 4 real bits (fixed bit stuffing).
  procedure stuff_feed (pol : std_logic; fixed : boolean; st : inout t_stuff_state; stream : inout t_bus_stream) is
  begin
    if fixed then
      if st.bits_since_fsb mod (c_stuff_width - 1) = 0 then
        append_bit(not st.last_pol, stream.bits, stream.len);
        st.last_pol := not st.last_pol;
      end if;
      append_bit(pol, stream.bits, stream.len);
      st.last_pol       := pol;
      st.bits_since_fsb := st.bits_since_fsb + 1;
    else
      append_bit(pol, stream.bits, stream.len);
      if pol = st.last_pol then
        st.consec := st.consec + 1;
        if st.consec = c_stuff_width then
          append_bit(not pol, stream.bits, stream.len);
          st.consec       := 1;
          st.last_pol     := not pol;
          st.ds_count     := st.ds_count + 1;
          st.just_stuffed := true;
          return;
        end if;
      else
        st.consec   := 1;
        st.last_pol := pol;
      end if;
      st.just_stuffed := false;
    end if;
  end procedure stuff_feed;

  -- Dynamic->fixed boundary (ISO 6.6.13.3.1): drop a trailing dynamic stuff bit
  procedure enter_fixed_mode (st : inout t_stuff_state; stream : inout t_bus_stream) is
  begin
    if st.just_stuffed then
      stream.len  := stream.len - 1;
      st.ds_count := st.ds_count - 1;
      st.last_pol := stream.bits(stream.len - 1);
    end if;
  end procedure enter_fixed_mode;

  -- Classic CAN reference stream (ISO Figure 2):
  function build_cc_stream (frame : t_llc_frame; metadata : t_llc_metadata; is_passive : boolean := false) return t_bus_stream is
    type t_idx_map is array (natural range <>) of natural;
    variable raw         : std_logic_vector(0 to c_max_bus_bits - 1);
    variable raw_len     : natural := 0;
    variable arb_end_raw : natural;
    variable stream_idx  : t_idx_map(0 to c_max_bus_bits - 1);
    variable id_full     : std_logic_vector(c_base_id_width + c_extended_id_width - 1 downto 0);
    variable crc         : std_logic_vector(c_crc_15_length - 1 downto 0);
    variable result      : t_bus_stream;
    variable st          : t_stuff_state := c_stuff_state_init;
    variable tail_len    : natural;
  begin
    result.len              := 0;
    result.ack_pos          := 0;
    result.arb_end          := 0;
    result.fdf_pos          := -1;
    result.data_phase_start := -1;
    result.data_phase_end   := -1;

    id_full := frame(2) & frame(3) & frame(4) & frame(5)(c_byte_width - 1 downto c_byte_width - 5);

    -- SOF + base ID
    append_bit(c_dominant, raw, raw_len);
    append(id_full(id_full'high downto c_extended_id_width), raw, raw_len);

    if metadata.ide = '0' then
      -- CBFF: RTR, IDE=0, r0
      append_bit(metadata.ftyp, raw, raw_len);
      append_bit(c_dominant, raw, raw_len);
      arb_end_raw := raw_len - 1;
      append_bit(c_dominant, raw, raw_len);
    else
      -- CEFF: SRR, IDE=1, ext ID, RTR, r1, r0
      append_bit(c_recessive, raw, raw_len);
      append_bit(c_recessive, raw, raw_len);
      append(id_full(c_extended_id_width - 1 downto 0), raw, raw_len);
      append_bit(metadata.ftyp, raw, raw_len);
      arb_end_raw := raw_len - 1;
      append_bit(c_dominant, raw, raw_len);
      append_bit(c_dominant, raw, raw_len);
    end if;

    -- DLC + data
    append(frame(1)(c_llc_frame_dlc_start downto c_llc_frame_dlc_end), raw, raw_len);
    for i in 0 to dlc_to_data_length(to_integer(unsigned(metadata.dlc)), '0') - 1 loop
      append(frame(c_llc_frame_data_byte + i), raw, raw_len);
    end loop;

    -- CRC-15 over SOF..data
    crc := f_calc_can_crc(raw(0 to raw_len - 1), c_crc_init_15_vec, c_crc_poly_15_vec);
    append(crc, raw, raw_len);

    -- Stuff raw, recording raw->stream index mapping
    for i in 0 to raw_len - 1 loop
      stuff_feed(raw(i), false, st, result);
      stream_idx(i) := result.len - 1;
    end loop;

    -- Remap bookmarks into stream index
    result.arb_end := stream_idx(arb_end_raw);

    -- Tail: CRC delim(1) + ACK slot(1) + ACK delim(1) + EOF + IFS [+ suspend]
    result.ack_pos := result.len + c_ack_slot_offset;
    tail_len := c_cc_eof_start_offset + c_eof_field_width + c_intermission_width;
    if is_passive then
      tail_len := tail_len + c_suspend_transmission_width;
    end if;
    for i in 0 to tail_len - 1 loop
      append_bit(c_recessive, result.bits, result.len);
    end loop;

    return result;
  end function build_cc_stream;

  -- CAN-FD CAN reference stream (ISO Figure 2):
  function build_fd_stream (frame : t_llc_frame; metadata : t_llc_metadata; is_passive : boolean := false) return t_bus_stream is
    type t_idx_map is array (natural range <>) of natural;
    variable v_raw          : std_logic_vector(0 to c_max_bus_bits - 1);
    variable v_raw_len      : natural := 0;
    variable v_arb_end_raw  : natural;
    variable v_fdf_raw      : natural;
    variable v_brs_raw      : natural;
    variable v_stream_idx   : t_idx_map(0 to c_max_bus_bits - 1);
    variable v_id_full      : std_logic_vector(c_base_id_width + c_extended_id_width - 1 downto 0);
    variable v_fixed_raw    : std_logic_vector(0 to c_sbc_field_width + c_crc_21_length - 1);
    variable v_fixed_len    : natural;
    variable v_sbc          : std_logic_vector(c_sbc_field_width - 1 downto 0);
    variable v_result       : t_bus_stream;
    variable v_st           : t_stuff_state := c_stuff_state_init;
    variable v_tail_len     : natural;
  begin
    v_result.len              := 0;
    v_result.ack_pos          := 0;
    v_result.arb_end          := 0;
    v_result.fdf_pos          := -1;
    v_result.data_phase_start := -1;
    v_result.data_phase_end   := -1;

    v_id_full := frame(2) & frame(3) & frame(4) & frame(5)(c_byte_width - 1 downto c_byte_width - 5);

    -- SOF + base ID
    append_bit(c_dominant, v_raw, v_raw_len);
    append(v_id_full(v_id_full'high downto c_extended_id_width), v_raw, v_raw_len);

    if metadata.ide = '0' then
      -- FBFF: RRS, IDE=0, FDF=1, RES=0, BRS, ESI
      append_bit(c_dominant, v_raw, v_raw_len);   -- RRS
      append_bit(c_dominant, v_raw, v_raw_len);   -- IDE
      v_arb_end_raw := v_raw_len - 1;
      v_fdf_raw := v_raw_len;
      append_bit(c_recessive, v_raw, v_raw_len);  -- FDF
      append_bit(c_dominant, v_raw, v_raw_len);   -- RES
      v_brs_raw := v_raw_len;
      append_bit(metadata.brs, v_raw, v_raw_len); -- BRS
      append_bit(metadata.esi, v_raw, v_raw_len); -- ESI
    else
      -- FEFF: SRR, IDE=1, ext ID, RRS, FDF=1, RES=0, BRS, ESI
      append_bit(c_recessive, v_raw, v_raw_len);  -- SRR
      append_bit(c_recessive, v_raw, v_raw_len);  -- IDE
      append(v_id_full(c_extended_id_width - 1 downto 0), v_raw, v_raw_len);
      append_bit(c_dominant, v_raw, v_raw_len);   -- RRS
      v_arb_end_raw := v_raw_len - 1;
      v_fdf_raw := v_raw_len;
      append_bit(c_recessive, v_raw, v_raw_len);  -- FDF
      append_bit(c_dominant, v_raw, v_raw_len);   -- RES
      v_brs_raw := v_raw_len;
      append_bit(metadata.brs, v_raw, v_raw_len); -- BRS
      append_bit(metadata.esi, v_raw, v_raw_len); -- ESI
    end if;

    -- DLC + data
    append(frame(1)(c_llc_frame_dlc_start downto c_llc_frame_dlc_end), v_raw, v_raw_len);
    for i in 0 to dlc_to_data_length(to_integer(unsigned(metadata.dlc)), '1') - 1 loop
      append(frame(c_llc_frame_data_byte + i), v_raw, v_raw_len);
    end loop;

    -- Stuff SOF..data onto the wire, recording raw->stream index mapping
    for i in 0 to v_raw_len - 1 loop
      stuff_feed(v_raw(i), false, v_st, v_result);
      v_stream_idx(i) := v_result.len - 1;
    end loop;

    -- Remap bookmarks into stream index
    v_result.arb_end := v_stream_idx(v_arb_end_raw);
    v_result.fdf_pos := v_stream_idx(v_fdf_raw);
    if metadata.brs = '1' then
      v_result.data_phase_start := v_stream_idx(v_brs_raw);
    end if;

    -- Consume preceding stuff bit (ISO 6.6.13.3.1)
    enter_fixed_mode(v_st, v_result);

    -- SBC (6.6.11.5): Gray(ds_count) and parity
    v_sbc(c_sbc_field_width - 1 downto 1) := f_to_gray(std_logic_vector(v_st.ds_count));
    v_sbc(0)                               := f_calc_parity(v_sbc(c_sbc_field_width - 1 downto 1));

    -- Build fixed-region raw vector: SBC (MSB-first) & CRC (MSB-first).
    -- CRC-17 for < 16 data bytes, else CRC-21.
    v_fixed_len := 0;
    append(v_sbc, v_fixed_raw, v_fixed_len);
    if dlc_to_data_length(to_integer(unsigned(metadata.dlc)), metadata.fdf) < c_crc_17_length then
      append(f_calc_can_crc(v_result.bits(0 to v_result.len - 1) & v_sbc, c_crc_init_17_vec, c_crc_poly_17_vec), v_fixed_raw, v_fixed_len);
    else
      append(f_calc_can_crc(v_result.bits(0 to v_result.len - 1) & v_sbc, c_crc_init_21_vec, c_crc_poly_21_vec), v_fixed_raw, v_fixed_len);
    end if;

    -- Fixed stuffing of SBC & CRC (initial FSB + 1 FSB per 4 real bits)
    for i in 0 to v_fixed_len - 1 loop
      stuff_feed(v_fixed_raw(i), true, v_st, v_result);
    end loop;

    if v_result.data_phase_start >= 0 then
      v_result.data_phase_end := v_result.len - 1;
    end if;

    -- Tail: CRC delim(1) + ACK slot(2) + ACK delim(1) + EOF + IFS [+ suspend]
    -- FD ACK slot is 2 bit times (ISO 6.6.11.6).
    v_result.ack_pos := v_result.len + c_ack_slot_offset;
    v_tail_len := c_fd_eof_start_offset + c_eof_field_width + c_intermission_width;
    if is_passive then
      v_tail_len := v_tail_len + c_suspend_transmission_width;
    end if;
    for i in 0 to v_tail_len - 1 loop
      append_bit(c_recessive, v_result.bits, v_result.len);
    end loop;

    return v_result;
  end function build_fd_stream;

  -- Dispatcher: pick CC vs FD based on metadata.fdf
  function build_bus_stream (frame : t_llc_frame; metadata : t_llc_metadata; is_passive : boolean := false) return t_bus_stream is
  begin
    if metadata.fdf = '1' then
      return build_fd_stream(frame, metadata, is_passive);
    else
      return build_cc_stream(frame, metadata, is_passive);
    end if;
  end function build_bus_stream;

end package body pk_can_tb;

-- eof
