library ieee;
  use ieee.std_logic_1164.all;
  use ieee.numeric_std.all;

package can_pkg is

  -- =================================================================
  -- Constants
  -- =================================================================
  constant dominant_bit               : std_logic                     := '0';
  constant recessive_bit              : std_logic                     := '1';
  constant max_static_form_bits       : integer                       := 8;
  constant sof_bit_position           : integer                       := 0;
  constant crc_poly_15_vec            : std_logic_vector(14 downto 0) := x"4599";
  constant crc_poly_17_vec            : std_logic_vector(16 downto 0) := x"3685B";
  constant crc_poly_21_vec            : std_logic_vector(20 downto 0) := x"302899";
  constant cc_basic_data_start_pos    : integer                       := 19;
  constant cc_extended_data_start_pos : integer                       := 39;
  constant fd_basic_data_start_pos    : integer                       := 22;
  constant fd_extended_data_start_pos : integer                       := 41;
  -- can classic  form bit positions
  constant cc_basic_rtr_pos : integer := 12;
  constant cc_basic_ide_pos : integer := 13;
  constant cc_basic_r0_pos  : integer := 14;
  -- can extended form bit positions
  constant cc_extended_srr_pos : integer := 12;
  constant cc_extended_ide_pos : integer := 13;
  constant cc_extended_rtr_pos : integer := 32;
  constant cc_extended_r1_pos  : integer := 33;
  constant cc_extended_r0_pos  : integer := 34;
  -- can FD basic form bit positions
  constant fd_basic_rss_pos : integer := 12;
  constant fd_basic_ide_pos : integer := 13;
  constant fd_basic_fdf_pos : integer := 14;
  constant fd_basic_res_pos : integer := 15;
  constant fd_basic_brs_pos : integer := 16;
  constant fd_basic_esi_pos : integer := 17;
  -- can FD extended form bit positions
  constant fd_extended_srr_pos : integer := 12;
  constant fd_extended_ide_pos : integer := 13;
  constant fd_extended_rrs_pos : integer := 32;
  constant fd_extended_fdf_pos : integer := 33;
  constant fd_extended_res_pos : integer := 34;
  constant fd_extended_brs_pos : integer := 35;
  constant fd_extended_esi_pos : integer := 36;

  -- =================================================================
  -- Types
  -- =================================================================

  -- CAN frame format types

  type can_format_t is (
    cc_basic,
    cc_extended,
    fd_basic,
    fd_extended
  );

  -- Node type (for ACK slot polarity)

  type can_node_type_t is (
    transmitter, -- ACK slot = recessive (waiting for ACK)
    receiver     -- ACK slot = dominant (acknowledging)
  );

  -- Frame type (data vs remote)

  type frame_type_t is (
    data_frame,
    remote_frame
  );

  -- Form bit entry

  type form_bit_entry_t is record
    position : integer;
    polarity : std_logic;
  end record form_bit_entry_t;

  -- Return type

  type form_bit_info_t is record
    is_form_bit : boolean;
    polarity    : std_logic;
  end record form_bit_info_t;

  -- Table types

  type form_bit_table_t is array (0 to max_static_form_bits - 1) of form_bit_entry_t;

  -- LLC (Logical Link Control) Interface

  type llc_to_mac_if_t is record
    data  : std_logic_vector(7 downto 0);
    valid : std_logic;
    sop   : std_logic;
    eop   : std_logic;
  end record llc_to_mac_if_t;

  type mac_to_llc_if_t is record
    valid  : std_logic;
    ready  : std_logic;
    status : std_logic_vector(2 downto 0);
  end record mac_to_llc_if_t;

  -- PCS (Physical Coding Sublayer) Interface

  type mac_pcs_if_t is record
    mac_frame_bit   : std_logic;
    mac_frame_valid : std_logic;
    transmit_status : std_logic;
    receive_status  : std_logic;
  end record mac_pcs_if_t;

  type pcs_mac_if_t is record
    mac_frame_bit   : std_logic;
    mac_frame_valid : std_logic;
  end record pcs_mac_if_t;

  -- Bit Stuffer FD Interface

  type mac_fsm_to_bs_fd_if_t is record
    clk        : std_logic;
    rst        : std_logic;
    data       : std_logic;
    data_valid : std_logic;
  end record mac_fsm_to_bs_fd_if_t;

  type bs_fd_to_mac_fsm_if_t is record
    stuff_bit       : std_logic;
    stuff_bit_valid : std_logic;
    sbc             : std_logic_vector(3 downto 0);
  end record bs_fd_to_mac_fsm_if_t;

  -- CRC Interface

  type mac_fsm_to_crc_if_t is record
    clk             : std_logic;
    rst             : std_logic;
    crc_poly_select : std_logic_vector(1 downto 0);
    shift           : std_logic;
    data            : std_logic;
  end record mac_fsm_to_crc_if_t;

  type crc_to_mac_fsm_if_t is record
    data       : std_logic;
    data_valid : std_logic;
  end record crc_to_mac_fsm_if_t;

  -- Shift Register Interface

  type shift_reg_in_if_t is record
    clk       : std_logic;
    rst       : std_logic;
    shift     : std_logic;
    load      : std_logic;
    data_in   : std_logic_vector(7 downto 0);
    serial_in : std_logic;
  end record shift_reg_in_if_t;

  type shift_reg_out_t is record
    empty      : std_logic;
    data_out   : std_logic_vector(7 downto 0);
    serial_out : std_logic;
  end record shift_reg_out_t;

  -- =================================================================
  -- STATIC FORM BIT TABLES
  -- =================================================================

  -- CAN Classic Basic (11-bit ID)
  constant cc_basic_static_form_bits : form_bit_table_t :=
  (
    0      => (position => sof_bit_position, polarity => dominant_bit), -- SOF
    1      => (position => cc_basic_ide_pos, polarity => dominant_bit), -- IDE
    2      => (position => cc_basic_r0_pos, polarity => dominant_bit),  -- r0
    others => (position => -1, polarity => recessive_bit)
  );

  -- CAN Classic Extended (29-bit ID)
  constant cc_extended_static_form_bits : form_bit_table_t :=
  (
    0      => (position => sof_bit_position, polarity => dominant_bit),     -- SOF
    1      => (position => cc_extended_srr_pos, polarity => recessive_bit), -- SRR
    2      => (position => cc_extended_ide_pos, polarity => recessive_bit), -- IDE
    3      => (position => cc_extended_r1_pos, polarity => dominant_bit),   -- r1
    4      => (position => cc_extended_r0_pos,  polarity => dominant_bit),  -- r0
    others => (position => -1, polarity => recessive_bit)
  );

  -- CAN FD Basic (11-bit ID)
  constant fd_basic_static_form_bits : form_bit_table_t :=
  (
    0      => (position => sof_bit_position, polarity => dominant_bit),  -- SOF
    1      => (position => fd_basic_rss_pos, polarity => dominant_bit),  -- RRS
    2      => (position => fd_basic_ide_pos, polarity => dominant_bit),  -- IDE
    3      => (position => fd_basic_fdf_pos, polarity => recessive_bit), -- FDF
    4      => (position => fd_basic_res_pos,  polarity => dominant_bit), -- RES
    others => (position => -1, polarity => recessive_bit)
  );

  -- CAN FD Extended (29-bit ID)
  constant fd_extended_static_form_bits : form_bit_table_t :=
  (
    0      => (position => sof_bit_position, polarity => dominant_bit),     -- SOF
    1      => (position => fd_extended_srr_pos, polarity => recessive_bit), -- SRR
    2      => (position => fd_extended_ide_pos, polarity => recessive_bit), -- IDE
    3      => (position => fd_extended_rrs_pos, polarity => dominant_bit),  -- RRS
    4      => (position => fd_extended_fdf_pos, polarity => recessive_bit), -- FDF
    5      => (position => fd_extended_res_pos, polarity => dominant_bit),  -- RES
    others => (position => -1, polarity => recessive_bit)
  );

  -- =================================================================
  -- FUNCTION DECLARATION
  -- =================================================================
  function check_form_bit (
    bit_count    : integer;
    can_format   : can_format_t;
    frame_type   : frame_type_t;
    dlc          : integer range 0 to 15;
    brs_enable   : boolean;
    esi_flag     : boolean;
    node_type    : can_node_type_t
  ) return form_bit_info_t;

end package can_pkg;

-- =================================================================
-- PACKAGE BODY
-- =================================================================

package body can_pkg is

  --  Convert DLC to actual data length in bytes
  function dlc_to_data_length (
    dlc        : integer range 0 to 15;
    can_format : can_format_t
  ) return integer is
  begin

    case can_format is

      when cc_basic | cc_extended =>

        -- CAN Classic: DLC 0-8 = actual bytes, 9-15 = 8 bytes
        if (dlc <= 8) then
          return dlc;
        else
          return 8;  -- Invalid DLC treated as 8
        end if;

      when fd_basic | fd_extended =>

        -- CAN FD: Extended DLC encoding
        case dlc is

          when 0 to 8 =>

            return dlc;

          when 9 =>

            return 12;

          when 10 =>

            return 16;

          when 11 =>

            return 20;

          when 12 =>

            return 24;

          when 13 =>

            return 32;

          when 14 =>

            return 48;

          when 15 =>

            return 64;

          when others =>

            return 0;

        end case;

    end case;

  end function dlc_to_data_length;

  -- Helper function to get CRC length based on CAN format and data length
  function get_crc_length (
    can_format  : can_format_t;
    data_length : integer
  ) return integer is
  begin

    case can_format is

      when cc_basic | cc_extended =>

        return crc_poly_15_vec'left + 1;

      when fd_basic | fd_extended =>

        if (data_length <= crc_poly_17_vec'left) then
          return crc_poly_17_vec'left + 1;
        else
          return crc_poly_21_vec'left + 1;
        end if;

    end case;

  end function get_crc_length;

  -- Helper function to get data start position based on CAN format
  function get_data_start_position (
    can_format : can_format_t
  ) return integer is
  begin

    case can_format is

      when cc_basic =>

        return cc_basic_data_start_pos;

      when cc_extended =>

        return cc_extended_data_start_pos;

      when fd_basic =>

        return fd_basic_data_start_pos;

      when fd_extended =>

        return fd_extended_data_start_pos;

    end case;

  end function get_data_start_position;

  -- Helper function to check if format is FD
  function is_fd_format (
    can_format : can_format_t
  ) return boolean is
  begin

    case can_format is

      when fd_basic | fd_extended =>

        return true;

      when others =>

        return false;

    end case;

  end function is_fd_format;

  -- Function calculates the form bit info
  function check_form_bit (
    bit_count    : integer;
    can_format   : can_format_t;
    frame_type   : frame_type_t;
    dlc          : integer range 0 to 15;
    brs_enable   : boolean;
    esi_flag     : boolean;
    node_type    : can_node_type_t
  ) return form_bit_info_t is

    variable result         : form_bit_info_t;
    variable static_table   : form_bit_table_t;
    variable data_start_pos : integer;
    variable data_length    : integer;
    variable data_bits      : integer;
    variable sbc_bits       : integer;
    variable crc_length     : integer;
    variable crc_delim_pos  : integer;
    variable ack_slot_pos   : integer;
    variable ack_delim_pos  : integer;
    variable eof_start_pos  : integer;
    variable rtr_position   : integer;
    variable rtr_polarity   : std_logic;
    variable brs_position   : integer;
    variable brs_polarity   : std_logic;
    variable esi_position   : integer;
    variable esi_polarity   : std_logic;
    variable ack_polarity   : std_logic;

  begin

    -- Initialize
    result.is_form_bit := false;
    result.polarity    := recessive_bit;

    -- Convert DLC to actual data length
    data_length := dlc_to_data_length(dlc, can_format);

    -- Select static table, RTR, BRS, and ESI positions based on format
    case can_format is

      when cc_basic =>

        static_table := cc_basic_static_form_bits;
        rtr_position := cc_basic_rtr_pos;
        brs_position := -1; -- No BRS in Classic CAN
        esi_position := -1; -- No ESI in Classic CAN

      when cc_extended =>

        static_table := cc_extended_static_form_bits;
        rtr_position := cc_extended_rtr_pos;
        brs_position := -1; -- No BRS in Classic CAN
        esi_position := -1; -- No ESI in Classic CAN

      when fd_basic =>

        static_table := fd_basic_static_form_bits;
        rtr_position := -1; -- No RTR in FD
        brs_position := fd_basic_brs_pos;
        esi_position := fd_basic_esi_pos;

      when fd_extended =>

        static_table := fd_extended_static_form_bits;
        rtr_position := -1;  -- No RTR in FD
        brs_position := fd_extended_brs_pos;
        esi_position := fd_extended_esi_pos;

    end case;

    -- Determine RTR polarity (CAN Classic only)
    case frame_type is

      when data_frame =>

        rtr_polarity := dominant_bit;

      when remote_frame =>

        rtr_polarity := recessive_bit;

    end case;

    -- Determine BRS polarity (CAN FD only)
    if (brs_enable) then
      brs_polarity := recessive_bit;  -- Recessive = bit rate switching enabled
    else
      brs_polarity := dominant_bit;  -- Dominant = no bit rate switching
    end if;

    -- Determine ESI polarity (CAN FD only)
    if (esi_flag) then
      esi_polarity := recessive_bit;  -- Recessive = error passive
    else
      esi_polarity := dominant_bit;  -- Dominant = error active
    end if;

    -- Determine ACK slot polarity based on node type
    case node_type is

      when transmitter =>

        ack_polarity := recessive_bit;

      when receiver =>

        ack_polarity := dominant_bit;

    end case;

    -- Check RTR bit (CAN Classic only)
    if (rtr_position /= -1 and bit_count = rtr_position) then
      result.is_form_bit := true;
      result.polarity    := rtr_polarity;
      return result;
    end if;

    -- Check BRS bit (CAN FD only)
    if (brs_position /= -1 and bit_count = brs_position) then
      result.is_form_bit := true;
      result.polarity    := brs_polarity;
      return result;
    end if;

    -- Check ESI bit (CAN FD only)
    if (esi_position /= -1 and bit_count = esi_position) then
      result.is_form_bit := true;
      result.polarity    := esi_polarity;
      return result;
    end if;

    -- Check static form bits
    for i in static_table'range loop

      if (static_table(i).position = -1) then
        exit;
      end if;

      if (bit_count = static_table(i).position) then
        result.is_form_bit := true;
        result.polarity    := static_table(i).polarity;
        return result;
      end if;

    end loop;

    -- Calculate dynamic positions
    data_start_pos := get_data_start_position(can_format);
    data_bits      := data_length * 8;

    -- Assign SBC field length
    if is_fd_format(can_format) then
      sbc_bits := 4;  -- CAN FD: 3-bit count + 1-bit parity
    else
      sbc_bits := 0;  -- CAN Classic: no SBC field
    end if;

    crc_length := get_crc_length(can_format, data_length);

    -- calculate dynamic form bits
    crc_delim_pos := data_start_pos + data_bits + sbc_bits + crc_length;
    ack_slot_pos  := crc_delim_pos + 1;
    ack_delim_pos := ack_slot_pos + 1;
    eof_start_pos := ack_delim_pos + 1;

    -- CRC Delimiter
    if (bit_count = crc_delim_pos) then
      result.is_form_bit := true;
      result.polarity    := recessive_bit;
      return result;
    end if;

    --  ACK Slot
    if (bit_count = ack_slot_pos) then
      result.is_form_bit := true;
      result.polarity    := ack_polarity;
      return result;
    end if;

    -- ACK Delimiter
    if (bit_count = ack_delim_pos) then
      result.is_form_bit := true;
      result.polarity    := recessive_bit;
      return result;
    end if;

    -- EOF (7 bits)
    if (bit_count >= eof_start_pos and bit_count < eof_start_pos + 7) then
      result.is_form_bit := true;
      result.polarity    := recessive_bit;
      return result;
    end if;

    return result;

  end function check_form_bit;

end package body can_pkg;
