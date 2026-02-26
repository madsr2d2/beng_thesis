--------------------------------------------------------------------------------------------------------------------------------------------------------------
-- Copyright 2025 Everllence, Teglholmsgade 41, 2450 Copenhagen SV, Denmark
--------------------------------------------------------------------------------------------------------------------------------------------------------------
--
-- Requirements:  
--
-- Description:   Utility package for CAN-bus controller
--
-- Revision log:  Date:       Initial:  JIRA:
--                2025-04-24  TMYAES:   [TRIT-3880] [FPGA] CAN-bus controller
--                2025-08-08  AFNI:     [TRIT-4042] [FPGA] Integrate can-bus controller into the io_ext
--                2025-12-02  AFNI:     [TRIT-3920] [FPGA] CAN-bus regression test
--                2025-12-15  AFNI:     [TRIT-4195] [FPGA] IO-extender code review
--                2026-02-11  AFNI:     [TRIT-3923] [FPGA] Bring-up of real IO-extender
--
--------------------------------------------------------------------------------------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

use work.pk_eth_st.all;
use work.pk_man_global.all;

package pk_can_bus_controller is
  ------------------------------------------------------------------------------
  -- Types
  ------------------------------------------------------------------------------
  type t_can_frame is array (0 to 14) of std_logic_vector(7 downto 0);

  -- Used in the fsm and the tb to hit some edge cases.
  type t_fsm_can_state is (s_bus_off, s_error_frame_dominant_delimiter, s_error_frame_delimiter, s_to_error_frame, s_error_frame, s_error_passive_wait,
                           s_error_frame_check, s_bus_reintegration, s_intermission, s_suspend_transmission, s_idle, s_to_arbitration,
                           s_arbitration, s_control, s_data, s_crc, s_ack, s_end_of_frame);
  type t_node_state    is (s_bus_off_node_state, s_error_active, s_error_passive);
  
  
  ------------------------------------------------------------------------------
  -- Constants
  ------------------------------------------------------------------------------
  constant c_bits_in_std_id    : integer := 11;
  constant c_bits_in_ext_id    : integer := c_bits_in_std_id + 18;
  constant c_bits_in_dlc       : integer := c_bytes_per_word;
  constant c_bits_in_ext_frame : integer := c_bits_in_ext_id + c_bits_in_dlc + c_64_bit_data_length + 2;

  -- Used for alint, please look at some calculations before using it in a design
  constant c_alint_default_bit_rate_hz       : integer := 500_000;
  constant c_alint_default_prop_seg_length   : integer := 3;
  constant c_alint_default_phase_seg1_length : integer := 3;
  constant c_alint_default_phase_seg2_length : integer := 3;
  constant c_alint_sync_jump_width           : integer := 2;

  constant c_max_phase_prop_seg_length : integer := 8;
  constant c_min_phase_prop_seg_length : integer := 1;
  constant c_max_phase_seg1_length     : integer := 8;
  constant c_min_phase_seg1_length     : integer := 1;
  constant c_max_phase_seg2_length     : integer := 8;
  constant c_min_phase_seg2_length     : integer := 2;

  constant c_sync_seg_length         : integer := 1;
  constant c_max_time_quanta_per_bit : integer := 25;

  constant c_error_activate_ns : std_logic_vector(1 downto 0) := B"00";
  constant c_error_passive_ns  : std_logic_vector(1 downto 0) := B"01";
  constant c_bus_off_ns        : std_logic_vector(1 downto 0) := B"11";

  constant c_clock_freq_khz : integer := c_clock_freq_mhz * 1000;

  constant c_max_data_count : integer := 8;

  constant c_bytes_in_can_llc_frame          : integer := 15;
  constant c_rtr_index_can_llc_frame         : integer := 14;
  constant c_ide_index_can_llc_frame         : integer := 13;
  constant c_dlc_index_can_llc_frame         : integer := 4;
  constant c_data_index_can_llc_frame        : integer := 5;
  constant c_std_id_byte_index_can_llc_frame : integer := 2;
  constant c_std_id_bit_index_can_llc_frame  : integer := 2;
  constant c_ext_id_byte_index_can_llc_frame : integer := 0;
  constant c_ext_id_bit_index_can_llc_frame  : integer := 4;

  constant c_active_to_passive_transition  : natural := 128;
  constant c_passive_to_bus_off_transition : natural := 256;
  constant c_bus_off_reintegration_count   : natural := 128;                    -- 128 consecutive of 11 recessive bits.

  -- Bit positions/indexes of fields in standard CAN frame
  constant c_std_sof_index       : natural := 0;                                -- Start Of Frame
  constant c_std_arb_id_index    : natural := 1;                                -- Arbitration ID
  constant c_std_rtr_index       : natural := 12;                               -- Remote Transmission Request
  constant c_std_ide_index       : natural := 13;                               -- Identifier Extension Bit
  constant c_std_r0_index        : natural := 14;                               -- Reserved Bit 0 (dominant zero)
  constant c_std_dlc_index       : natural := 15;                               -- Data Length Code
  constant c_std_data_index      : natural := 19;                               -- Data
  constant c_crc_delimiter_index : integer := 16;

  -- Bit positions/indexes of fields in extended CAN frame
  constant c_ext_sof_index      : natural := 0;                                 -- Start Of Frame
  constant c_ext_arb_id_a_index : natural := 1;                                 -- Arbitration ID A
  constant c_ext_srr_index      : natural := 12;                                -- Substitute Remote Request
  constant c_ext_ide_index      : natural := 13;                                -- Identifier Extension Bit
  constant c_ext_arb_id_b_index : natural := 14;                                -- Arbitration ID A
  constant c_ext_rtr_index      : natural := 32;                                -- Remote Transmission Request
  constant c_ext_r0_index       : natural := 33;                                -- Reserved Bit 0 (dominant zero)
  constant c_ext_r1_index       : natural := 34;                                -- Reserved Bit 1 (dominant zero)
  constant c_ext_dlc_index      : natural := 35;                                -- Data Length Code
  constant c_ext_data_index     : natural := 39;                                -- Data
  

  constant c_debug_error_flags_width : integer                                                  := 3;
  constant c_debug_error_no_error    : std_logic_vector(c_debug_error_flags_width - 1 downto 0) := (others => '0');
  constant c_debug_error_crc         : integer                                                  := 0;
  constant c_debug_error_stuff_bit   : integer                                                  := 1;
  constant c_debug_error_ack_bit     : integer                                                  := 2;

  constant c_bit_count_error_to_idle  : integer := 11;                          -- Transition to idle state after 11/1408 recessive bits for error_(active/passive) / bus_off nodes
  constant c_bit_count_long_suspended : integer := 16;                          -- Longer than error to idle, to allow clock difference from the other nodes.

  -- Bit positions for some checks.
  constant c_bit_to_jump_out_off_suspension     : integer := 8;                 -- Suspend transmission state. (6.6.7.4)[1]
  constant c_recessive_bits_in_error_delimiter  : integer := 8;                 -- A node samples a dominant bit.
  constant c_dominant_bit_in_error              : integer := 8;                 -- A node samples a dominant bit.
  constant c_dominant_bit_at_2_bit_intermission : integer := 2;                 -- A node samples a dominant bit at either first two bits of the intermission
  constant c_ack_pos                            : integer := 1;
  constant c_ack_delimiter_pos                  : integer := 2;
  constant c_eof_length                         : integer := 7;
  constant c_intermission_length                : integer := 3;
  constant c_error_count_8                      : integer := 8;
  constant c_error_count_1                      : integer := 1;
  constant c_error_count_decrement              : integer := -1;
  constant c_error_frame_count                  : integer := 6;

end package pk_can_bus_controller;


