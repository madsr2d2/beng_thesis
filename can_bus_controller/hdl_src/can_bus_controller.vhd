--------------------------------------------------------------------------------------------------------------------------------------------------------------
-- Copyright 2025 Everllence, Teglholmsgade 41, 2450 Copenhagen SV, Denmark
--------------------------------------------------------------------------------------------------------------------------------------------------------------
--
-- Requirements:  
--
-- Description:   
--
-- Revision log:  Date:       Initial:  JIRA:
--                2025-04-03  AFNI:     [TRIT-3892] [FPGA] CAN-bus controller VIP - Initial file.
--                2025-04-24  TMYAES:   [TRIT-3880] [FPGA] CAN-bus controller - added submodules
--                2025-08-08  AFNI:     [TRIT-4042] [FPGA] Integrate can-bus controller into the io_ext
--                2026-02-11  AFNI:     [TRIT-3923] [FPGA] Bring-up of real IO-extender
--
--------------------------------------------------------------------------------------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

use work.pk_man_global.all;
use work.pk_eth_st;
use work.pk_can_bus_controller.all;


entity can_bus_controller is
  generic(
    gc_bit_rate_hz                : integer range 250_000 to 500_000                                         := c_alint_default_bit_rate_hz; -- Desired baud rate in kbps
    gc_default_prop_seg_length    : integer range c_min_phase_prop_seg_length to c_max_phase_prop_seg_length := c_alint_default_prop_seg_length;
    gc_default_phase_seg_1_length : integer range c_min_phase_seg1_length to c_max_phase_seg1_length         := c_alint_default_phase_seg1_length;
    gc_default_phase_seg_2_length : integer range c_min_phase_seg2_length to c_max_phase_seg2_length         := c_alint_default_phase_seg2_length;
    gc_sync_jump_width            : integer range 1 to 4                                                     := c_alint_sync_jump_width
  );
  port(
    clk_i              : in  std_logic;
    reset_i            : in  std_logic;
    can_reset_i        : in  std_logic;
    --
    rx_i               : in  std_logic;
    tx_o               : out std_logic;
    --
    src_s2d_o          : out pk_eth_st.t_eth_st_s2d;
    src_d2s_i          : in  pk_eth_st.t_eth_st_d2s;
    sink_s2d_i         : in  pk_eth_st.t_eth_st_s2d;
    sink_d2s_o         : out pk_eth_st.t_eth_st_d2s;
    ack_o              : out std_logic;
    ns_o               : out std_logic_vector(1 downto 0);

    --
    debug_error_flag_o : out std_logic_vector(c_debug_error_flags_width - 1 downto 0) -- Debug error flag

  );
end entity;

architecture rtl of can_bus_controller is

  ----------------------------------------------------------------------------
  -- Types
  ----------------------------------------------------------------------------

  ----------------------------------------------------------------------------
  -- Constants
  ----------------------------------------------------------------------------
  constant c_crc_width      : integer                       := 15;
  -- This is the 14 downto 0 bits of the crc_poly used in can_bus_vc_p (x"4599")
  constant c_crc_poly       : std_logic_vector(14 downto 0) := b"100_0101_1001_1001"; -- CAN CRC-15 
  constant c_crc_init       : std_logic_vector(14 downto 0) := (others => '0'); -- CRC initialization
  constant c_crc_xor        : std_logic_vector(14 downto 0) := (others => '0'); -- No final XOR
  constant c_crc_data_width : integer                       := 1;


  ----------------------------------------------------------------------------
  -- Signals
  ----------------------------------------------------------------------------
  signal stuff_bit       : std_logic;                                           -- stuff bit signals
  signal stuff_bit_valid : std_logic;                                           -- stuff bit signals

  signal crc       : std_logic_vector(14 downto 0);                             -- crc signals
  signal crc_start : std_logic;                                                 -- crc signals

  signal sta_reset : std_logic;                                                 -- c2a signals
  signal sta_ack   : std_logic;

  signal ats_ready : std_logic;                                                 -- a2c signals
  signal frame_bit : std_logic;                                                 -- a2c signals
  signal ats_valid : std_logic;                                                 -- a2c signals
  signal ats_reset : std_logic;                                                 -- a2c signals
  signal ide       : std_logic;                                                 -- identifier extension signal
  signal rtr       : std_logic;                                                 -- remote transmission request signal
  signal dlc       : std_logic_vector(3 downto 0);                              -- data length code signal

  signal sample_rx_valid : std_logic;

  signal frame_in_progress : std_logic;

  signal sample_rx          : std_logic;                                        -- sample pulse rx
  signal transmit           : std_logic;                                        -- transmit signal
  signal is_transmitter     : std_logic;                                        -- transmitter signal
  signal can_node_clk_reset : std_logic;                                        -- reset signal for CAN node clock
  signal rx_sync            : std_logic;                                        -- synchronized rx signal

begin
  ------------------------------------------------------------------------------
  --  Controlling FSM (FSM_CAN in documentation)
  ------------------------------------------------------------------------------
  u_fsm : entity work.can_fsm
    port map(

      clk_i                => clk_i,
      reset_i              => reset_i,
      can_reset_i          => can_reset_i,
      --
      rx_i                 => rx_sync,
      tx_o                 => tx_o,
      --
      ack_o                => ack_o,
      ns_o                 => ns_o,

      -- General frame values
      frame_in_progress_o  => frame_in_progress,

      -- can_stuff_bit_gen interface
      stuff_bit_i          => stuff_bit,
      stuff_bit_valid_i    => stuff_bit_valid,

      -- gen_crc interface
      crc_i                => crc,
      crc_start_o          => crc_start,

      -- can_node_clock interface
      sample_rx_i          => sample_rx,
      can_node_clk_reset_o => can_node_clk_reset,
      transmit_i           => transmit, 

      -- can_serial_to_ast interface
      sta_reset_o          => sta_reset,
      sta_ack_o            => sta_ack,

      -- can_ast_to_serial interface
      ast_ready_o          => ats_ready,
      frame_bit_i          => frame_bit,
      frame_bit_valid_i    => ats_valid,
      ats_reset_o          => ats_reset,
      is_transmitter_o     => is_transmitter,
      ide_i                => ide,
      rtr_i                => rtr,
      dlc_i                => dlc,
      --

      -- debug error signals
      debug_error_flag_o   => debug_error_flag_o
      

    );

  ------------------------------------------------------------------------------
  --  Synchronise rx
  ------------------------------------------------------------------------------
  u_synchronizer : entity work.synchronizer
    generic map(
      gc_width => 1,                                                            -- Width of the input signal
      gc_depth => c_no_of_sync_clks                                             -- Depth of the synchronizer
    )
    port map(
      clk_i      => clk_i,
      async_i(0) => rx_i,
      sync_o(0)  => rx_sync
    );

  ------------------------------------------------------------------------------
  --  CAN node clock
  ------------------------------------------------------------------------------
  u_can_node_clock : entity work.can_node_clock
    generic map(
      gc_bit_rate_hz                => gc_bit_rate_hz,
      gc_default_prop_seg_length    => gc_default_prop_seg_length,
      gc_default_phase_seg_1_length => gc_default_phase_seg_1_length,
      gc_default_phase_seg_2_length => gc_default_phase_seg_2_length,
      gc_sync_jump_width            => gc_sync_jump_width
    )
    port map(
      clk_i       => clk_i,
      reset_i     => can_node_clk_reset or reset_i,
      rx_i        => rx_sync,
      sample_rx_o => sample_rx,
      transmit_o  => transmit
    );

  ------------------------------------------------------------------------------
  --  Avalon-st frame to serial
  ------------------------------------------------------------------------------
  u_can_ast_to_serial : entity work.can_ast_to_serial
    port map(
      clk_i             => clk_i,
      reset_i           => ats_reset or reset_i,
      frame_bit_valid_o => ats_valid,
      frame_bit_o       => frame_bit,
      rtr_bit_o         => rtr,
      ide_bit_o         => ide,
      dlc_bits_o        => dlc,
      ready_i           => ats_ready,
      is_transmitter_i  => is_transmitter,
      sink_s2d_i        => sink_s2d_i,
      sink_d2s_o        => sink_d2s_o
    );


  ------------------------------------------------------------------------------
  -- serial to Avalon-st frame 
  ------------------------------------------------------------------------------

  sample_rx_valid <= sample_rx and (not stuff_bit_valid) and frame_in_progress;

  u_can_serial_to_ast : entity work.can_serial_to_ast
    port map(
      clk_i     => clk_i,
      reset_i   => sta_reset or reset_i,
      valid_i   => sample_rx_valid,
      ack_i     => sta_ack,
      rx_i      => rx_sync,
      src_s2d_o => src_s2d_o,
      src_d2s_i => src_d2s_i
    );

  ------------------------------------------------------------------------------
  --  Stuff bit generator
  ------------------------------------------------------------------------------
  u_can_stuff_bit_gen : entity work.can_stuff_bit_gen
    port map(
      clk_i             => clk_i,
      reset_i           => reset_i,
      rx_i              => rx_sync,

      sample_rx_i       => sample_rx,
      stuff_bit_o       => stuff_bit,
      stuff_bit_valid_o => stuff_bit_valid
    );

  ------------------------------------------------------------------------------
  --  crc_gen
  ------------------------------------------------------------------------------
  u_can_crc_gen : entity work.gen_crc
    generic map(
      gc_data_width => c_crc_data_width,
      gc_crc_width  => c_crc_width,
      gc_crc_poly   => c_crc_poly,
      gc_xor_value  => c_crc_xor,
      gc_crc_init   => c_crc_init,
      gc_ref_input  => 0,
      gc_ref_output => false
    )
    port map(
      clk_i        => clk_i,
      reset_i      => reset_i,
      start_crc_i  => crc_start,
      data_i(0)    => rx_sync,
      data_valid_i => sample_rx_valid,
      crc_o        => crc
    );

end architecture;

-- eof
