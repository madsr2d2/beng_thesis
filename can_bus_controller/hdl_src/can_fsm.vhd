--------------------------------------------------------------------------------------------------------------------------------------------------------------
-- Copyright 2025 Everllence, Teglholmsgade 41, 2450 Copenhagen SV, Denmark
--------------------------------------------------------------------------------------------------------------------------------------------------------------
--
-- Requirements:  
--
-- Description:   Ref. [1]: ISO 11898-1:2024-5 Road vehicles - Controller Area Network (CAN) - Part 1: Data link layer and physical signalling
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


use work.pk_man_global.all;
use work.pk_eth_st;
use work.pk_can_bus_controller.all;

entity can_fsm is
  port(
    clk_i                : in  std_logic;
    reset_i              : in  std_logic;
    can_reset_i          : in  std_logic;
    --
    rx_i                 : in  std_logic;
    tx_o                 : out std_logic;
    --
    ack_o                : out std_logic;
    ns_o                 : out std_logic_vector(1 downto 0);             

    -- stuff bit interface
    stuff_bit_i          : in  std_logic;
    stuff_bit_valid_i    : in  std_logic;

    -- General frame values
    frame_in_progress_o  : out std_logic;

    -- CRC interface
    crc_i                : in  std_logic_vector(14 downto 0);
    crc_start_o          : out std_logic;                                     

    -- CAN node clock interface
    sample_rx_i          : in  std_logic;
    transmit_i           : in  std_logic;
    can_node_clk_reset_o : out std_logic;                

    -- can_serial_to_ast interface
    sta_reset_o          : out std_logic;
    sta_ack_o            : out std_logic;

    -- can_ast_to_serial interface
    ast_ready_o          : out std_logic;
    is_transmitter_o     : out std_logic;
    frame_bit_i          : in  std_logic;
    frame_bit_valid_i    : in  std_logic;
    ide_i                : in  std_logic;
    rtr_i                : in  std_logic;
    dlc_i                : in  std_logic_vector(3 downto 0);
    ats_reset_o          : out std_logic;

    -- Debug error flag
    debug_error_flag_o   : out std_logic_vector(c_debug_error_flags_width - 1 downto 0)
  );

end entity;

architecture rtl of can_fsm is
  ----------------------------------------------------------------------------
  -- Types 
  ----------------------------------------------------------------------------
  type t_error_count is (none, count_up_1, count_up_8, count_down_1);

  ----------------------------------------------------------------------------
  -- Constants 
  ----------------------------------------------------------------------------
  constant c_bit_count_into_crc : integer := 1;
  constant c_bit_count_into_arb : integer := 1;


  ----------------------------------------------------------------------------
  -- Signals
  ----------------------------------------------------------------------------
  signal fsm_state                : t_fsm_can_state;
  signal node_error_state         : t_node_state;
  signal transmit_error_count     : natural range 0 to c_passive_to_bus_off_transition; -- Counts errors in transmitting nodes
  signal receive_error_count      : natural range 0 to c_active_to_passive_transition; -- Counts errors in receiving nodes
  signal bus_off_re_int_count     : integer range 0 to c_bus_off_reintegration_count;
  signal bit_count                : natural range 0 to c_bus_off_reintegration_count; -- Keeps track of sent bits. c_bus_off_reintegration_count is the maximum amount is should count to.
  signal transmit_ack             : std_logic;
  signal is_transmitter           : std_logic;                                  -- Indicates if the node is transmitter or receiver
  signal go_to_suspended          : std_logic;
  signal dlc_shift                : std_logic_vector(3 downto 0);               -- Register holding the DLC value in bytes
  signal rtr_bit                  : std_logic;                                  -- Register holding the RTR bit value
  --
  signal crc_error                : std_logic;                                  -- Flag set by receiving nodes indicating a CRC error has occurred
  signal stuff_bit_error          : std_logic;
  signal do_not_count_stuff_error : std_logic;
  signal ack_error                : std_logic;
  --
  signal tec_control              : t_error_count;
  signal rec_control              : t_error_count;


  signal rx_r : std_logic;                                                      -- edge case with the rx falling at the same time as the sample_rx_i is 1, so we need to know that if rx_i in the last CC was 1 or 0. If it was 1, 
  -- we know hard sync have not happened yet, so we need to wait on it.
begin

  debug_error_flag_o <= (
    c_debug_error_crc       => crc_error,
    c_debug_error_stuff_bit => stuff_bit_error,
    c_debug_error_ack_bit   => ack_error
  );


  ------------------------------------------------------------------------------
  -- Process keeping track of the current node error state
  ------------------------------------------------------------------------------
  p_node_error_state : process(all)
  begin
    if rising_edge(clk_i) then
      if reset_i = '1' then
        node_error_state <= s_error_active;
        ns_o             <= (others => '0');

      else
        if (sample_rx_i = '1') then
          ------------------------------------------------------------------------------
          -- Update the node error state 
          ------------------------------------------------------------------------------
          case node_error_state is
            when s_bus_off_node_state =>
              ns_o <= c_bus_off_ns;
              if fsm_state = s_idle then
                node_error_state <= s_error_active;
              end if;

            when s_error_active =>
              ns_o <= c_error_activate_ns;
              if (transmit_error_count >= c_active_to_passive_transition) or (receive_error_count >= c_active_to_passive_transition) then
                node_error_state <= s_error_passive;
              end if;

            when s_error_passive =>
              ns_o <= c_error_passive_ns;
              if transmit_error_count >= c_passive_to_bus_off_transition then
                node_error_state <= s_bus_off_node_state;
              elsif (transmit_error_count < c_active_to_passive_transition) and (receive_error_count < c_active_to_passive_transition) then
                node_error_state <= s_error_active;
              end if;

            --coverage off
            when others =>
              node_error_state <= s_error_active;
              --coverage on
          end case;
        end if;
      end if;
    end if;
  end process;

  ------------------------------------------------------------------------------
  -- Used to increment or decrement the error counts.
  -- Only one of the error counts can be used.
  ------------------------------------------------------------------------------
  p_error_count : process(clk_i)
    variable v_next_transmit_error_count : integer range c_error_count_decrement to c_passive_to_bus_off_transition + c_error_count_8;
    variable v_next_receive_error_count  : integer range c_error_count_decrement to c_active_to_passive_transition + c_error_count_8;
  begin
    if rising_edge(clk_i) then
      if (reset_i = '1') or (can_reset_i = '1') then
        receive_error_count  <= 0;
        transmit_error_count <= 0;
      else
        case tec_control is
          when count_up_8 =>
            v_next_transmit_error_count := transmit_error_count + c_error_count_8;
          when count_down_1 =>
            v_next_transmit_error_count := transmit_error_count + c_error_count_decrement;
          when others =>                                                        -- Count 1 up is not used for transmission
            v_next_transmit_error_count := transmit_error_count;
        end case;
        if v_next_transmit_error_count >= c_passive_to_bus_off_transition then
          v_next_transmit_error_count := c_passive_to_bus_off_transition;
        elsif v_next_transmit_error_count <= 0 then
          v_next_transmit_error_count := 0;
        end if;
        transmit_error_count <= v_next_transmit_error_count;

        case rec_control is
          when count_up_8 =>
            v_next_receive_error_count := receive_error_count + c_error_count_8;
          when count_up_1 =>
            v_next_receive_error_count := receive_error_count + c_error_count_1;
          when count_down_1 =>
            v_next_receive_error_count := receive_error_count + c_error_count_decrement;
          when others =>
            v_next_receive_error_count := receive_error_count;
        end case;
        if v_next_receive_error_count >= c_active_to_passive_transition then
          v_next_receive_error_count := c_active_to_passive_transition;
        elsif v_next_receive_error_count <= 0 then
          v_next_receive_error_count := 0;
        end if;
        receive_error_count <= v_next_receive_error_count;
      end if;
    end if;
  end process;

  ------------------------------------------------------------------------------
  --  Controlling FSM
  ------------------------------------------------------------------------------
  --@alint rule_state off STARC_VHDL.2.7.3.1_a
  --  The number of nests for 'if-if' should be seven or less.
  --  AFNI(2025-07-11): Kept this way to increase readability
  p_fsm_can : process(all)
    variable v_crc_index : integer range 0 to crc_i'high;
  begin
    if rising_edge(clk_i) then
      if (reset_i = '1') or (can_reset_i = '1') then
        fsm_state                <= s_bus_reintegration;
        is_transmitter           <= '0';
        go_to_suspended          <= '0';
        bit_count                <= 1;
        dlc_shift                <= (others => '0');
        rx_r                     <= rx_i;
        ack_o                    <= '0';
        tx_o                     <= '1';
        sta_reset_o              <= '1';
        frame_in_progress_o      <= '0';
        sta_ack_o                <= '0';
        ast_ready_o              <= '0';
        ats_reset_o              <= '1';
        crc_start_o              <= '1';
        can_node_clk_reset_o     <= '1';
        is_transmitter_o         <= '0';
        rtr_bit                  <= '0';
        crc_error                <= '0';
        stuff_bit_error          <= '0';
        bus_off_re_int_count     <= 0;
        transmit_ack             <= '0';
        ack_error                <= '0';
        tec_control              <= none;
        rec_control              <= none;
        do_not_count_stuff_error <= '0';
      else
        ats_reset_o          <= '0';
        sta_reset_o          <= '0';
        crc_start_o          <= '0';
        ast_ready_o          <= '0';
        ack_o                <= '0';
        can_node_clk_reset_o <= '0';
        sta_ack_o            <= '0';
        is_transmitter_o     <= is_transmitter;
        tec_control          <= none;
        rec_control          <= none;

        if sample_rx_i = '1' then
          rx_r <= rx_i;                                                         -- Some states needs it on our clock basis, and is handled there.
        end if;

        -- Per default the tx should be recessives.
        if transmit_i = '1' then
          tx_o <= '1';
        end if;

        case fsm_state is
          ------------------------------------------------------------------------------
          -- Initial state. Bit count is reset every time bus is sampled dominant
          ------------------------------------------------------------------------------
          when s_bus_reintegration =>
            if sample_rx_i = '1' then
              bit_count <= bit_count + 1;
              if rx_i = '0' then
                bit_count            <= 1;
                bus_off_re_int_count <= 1;
              elsif bit_count = c_bit_count_error_to_idle then
                bit_count <= 1;
                if node_error_state = s_bus_off_node_state then
                  if bus_off_re_int_count = c_bus_off_reintegration_count then
                    fsm_state            <= s_idle;
                    bus_off_re_int_count <= 0;
                  else
                    bus_off_re_int_count <= bus_off_re_int_count + 1;
                  end if;
                else
                  fsm_state <= s_idle;
                end if;
              end if;
            end if;

          ------------------------------------------------------------------------------
          -- Suspend transmission state. (6.6.7.4)[1]
          -- Homemade to allow other nodes to be re-integrated if they were bus off.
          ------------------------------------------------------------------------------
          when s_suspend_transmission =>
            rx_r <= rx_i;
            if sample_rx_i = '1' then
              bit_count <= bit_count + 1;
              -- SOF bit was detected so jump to arbitration state and set bit count to 2
              if (rx_i = '0') and (rx_r = '0') then
                fsm_state <= s_to_arbitration;
              elsif bit_count = c_bit_count_long_suspended then
                bit_count <= 1;
                if bus_off_re_int_count = c_bus_off_reintegration_count then
                  fsm_state            <= s_idle;
                  bus_off_re_int_count <= 0;
                else
                  bus_off_re_int_count <= bus_off_re_int_count + 1;
                end if;
              end if;
            end if;

          ------------------------------------------------------------------------------
          -- Idle state. Wait for SOF bit or arrival of new can frame in can_ats module
          ------------------------------------------------------------------------------
          when s_idle =>
            rx_r <= rx_i;
            if transmit_i = '1' then
              if frame_bit_valid_i = '1' then                                   -- If we are the transmitter we need to send the SOF.
                tx_o           <= '0';
                is_transmitter <= '1';
              end if;
            elsif sample_rx_i = '1' then
              if (is_transmitter = '1') and (rx_i /= tx_o) then                 -- Something is wrong with the bus.
                fsm_state <= s_to_error_frame;
              elsif (rx_i = '0') and (rx_r = '0') then
                fsm_state <= s_to_arbitration;
              end if;
            end if;

          ------------------------------------------------------------------------------
          -- Before going into the arbitration it needs to set the right bit count
          -- and start the crc module.
          ------------------------------------------------------------------------------
          when s_to_arbitration =>
            crc_start_o <= '1';
            bit_count   <= c_bit_count_into_arb;
            fsm_state   <= s_arbitration;
            dlc_shift   <= (others => '0');

          ------------------------------------------------------------------------------
          -- Arbitration state. Transmit / receive ID bits
          ------------------------------------------------------------------------------
          when s_arbitration =>
            frame_in_progress_o <= '1';

            if transmit_i = '1' then
              if is_transmitter = '1' then
                -- Check if its time for a stuff bit
                if (stuff_bit_valid_i = '1') then
                  tx_o <= stuff_bit_i;
                -- Extended frame format
                elsif ide_i = '1' then
                  case bit_count is
                    when c_ext_srr_index =>
                      tx_o <= '1';                                              -- Transmit SSR bit
                    when c_ext_ide_index =>
                      tx_o <= ide_i;                                            -- Transmit IDE bit
                    when c_ext_rtr_index =>
                      tx_o <= rtr_i;                                            -- Transmit RTR bit
                    when others =>
                      tx_o        <= frame_bit_i;                               -- Transmit frame bit
                      ast_ready_o <= '1';
                  end case;
                -- Standard frame format
                else
                  case bit_count is
                    when c_std_rtr_index =>
                      tx_o <= rtr_i;                                            -- Transmit RTR bit
                    when c_std_ide_index =>
                      tx_o <= ide_i;                                            -- Transmit IDE bit
                    when others =>
                      tx_o        <= frame_bit_i;                               -- Transmit frame bit
                      ast_ready_o <= '1';
                  end case;
                end if;
              end if;

            elsif sample_rx_i = '1' then
              bit_count <= bit_count + 1;

              if (stuff_bit_valid_i = '1') then
                bit_count <= bit_count;
                if (stuff_bit_i /= rx_i) then                                   -- Stuff error (6.6.21.2.b)[1]
                  if (stuff_bit_i = '1') and (is_transmitter = '1') then        -- 8.1.4.2.c.ex2
                    do_not_count_stuff_error <= '1';
                  end if;
                  stuff_bit_error <= '1';
                  fsm_state       <= s_to_error_frame;
                end if;
              else
                -- It will assume that the arbitration can be lost until the last extended bit.
                if bit_count = c_std_rtr_index then
                  rtr_bit <= rx_i;                                              -- Register RTR bit
                elsif (bit_count = c_std_ide_index) and (rx_i = '0') then       -- It is a standard frame.
                  fsm_state <= s_control;
                  bit_count <= 2;
                elsif bit_count = c_ext_rtr_index then
                  fsm_state <= s_control;
                  bit_count <= 1;
                  rtr_bit   <= rx_i;                                            -- Register RTR bit
                end if;

                if is_transmitter = '1' then
                  if (rx_i /= tx_o) then                                        -- No bit error in arbitration phase
                    is_transmitter <= '0';
                  elsif (ide_i = '0') and (bit_count = c_std_ide_index) then
                    bit_count <= 2;
                    fsm_state <= s_control;
                  end if;
                end if;
              end if;
            end if;

          ------------------------------------------------------------------------------
          -- Control state. Transmit / receive control bits
          ------------------------------------------------------------------------------
          when s_control =>
            if transmit_i = '1' then
              if is_transmitter = '1' then
                -- Check if its time for a stuff bit
                tx_o <= stuff_bit_i;
                if (stuff_bit_valid_i = '0') then
                  -- This part of the frame is identical for both standard and extended frames
                  tx_o <= '0';                                                  -- Transmit r0 bit
                  if bit_count > 2 then
                    tx_o        <= frame_bit_i;                                 -- Transmit frame bit
                    ast_ready_o <= '1';
                  end if;
                end if;
              end if;

            elsif sample_rx_i = '1' then
              bit_count <= bit_count + 1;

              if (stuff_bit_valid_i = '1') then
                bit_count <= bit_count;
                if (stuff_bit_i /= rx_i) then                                   -- Stuff error (6.6.21.2.b)[1]
                  stuff_bit_error <= '1';
                  fsm_state       <= s_to_error_frame;
                end if;
              elsif is_transmitter = '1' then
                if rx_i /= tx_o then
                  fsm_state <= s_to_error_frame;
                elsif (bit_count = 6) then
                  fsm_state <= s_data;
                  bit_count <= 1;
                  dlc_shift <= dlc_i;
                  if (rtr_i = '1') then
                    sta_reset_o <= '1';
                    fsm_state   <= s_crc;
                    bit_count   <= c_bit_count_into_crc;
                  end if;
                end if;
              else
                if bit_count > 2 then
                  dlc_shift <= dlc_shift(dlc_shift'high - 1 downto 0) & rx_i;   -- Shift in DLC bits
                  if bit_count = 6 then
                    bit_count <= 1;
                    if rtr_bit = '1' then
                      fsm_state <= s_crc;
                      bit_count <= c_bit_count_into_crc;
                    else
                      fsm_state <= s_data;
                    end if;
                  end if;
                end if;
              end if;
            end if;

          ------------------------------------------------------------------------------
          -- Data state. Transmit / receive data payload bits
          ------------------------------------------------------------------------------
          when s_data =>
            if transmit_i = '1' then
              if is_transmitter = '1' then
                tx_o <= stuff_bit_i;
                if (stuff_bit_valid_i = '0') then
                  tx_o        <= frame_bit_i;
                  ast_ready_o <= '1';
                end if;
              end if;
            elsif sample_rx_i = '1' then
              bit_count <= bit_count + 1;

              if (stuff_bit_valid_i = '1') then
                bit_count <= bit_count;
                if (stuff_bit_i /= rx_i) then                                   -- Stuff error (6.6.21.2.b)[1]
                  stuff_bit_error <= '1';
                  fsm_state       <= s_to_error_frame;
                end if;
              elsif (is_transmitter = '1') and (rx_i /= tx_o) then
                fsm_state <= s_to_error_frame;
              elsif (bit_count = (to_integer(unsigned(dlc_shift) & b"000"))) then
                fsm_state <= s_crc;
                bit_count <= c_bit_count_into_crc;
              end if;
            end if;

          ------------------------------------------------------------------------------
          -- CRC state. Transmit / receive CRC bits and CRC delimiter bit
          ------------------------------------------------------------------------------
          when s_crc =>
            frame_in_progress_o <= '0';
            if transmit_i = '1' then
              if is_transmitter = '1' then
                -- Check if its time for a stuff bit
                tx_o <= stuff_bit_i;
                if (stuff_bit_valid_i = '0') then
                  tx_o <= '1';
                  if bit_count < c_crc_delimiter_index then
                    -- Transmit next CRC bit
                    v_crc_index := crc_i'length - bit_count;
                    tx_o        <= crc_i(v_crc_index);
                  end if;
                end if;
              end if;
            elsif sample_rx_i = '1' then
              bit_count <= bit_count + 1;

              if (stuff_bit_valid_i = '1') then
                bit_count <= bit_count;
                if (stuff_bit_i /= rx_i) then
                  stuff_bit_error <= '1';
                  fsm_state       <= s_to_error_frame;
                end if;
              elsif is_transmitter = '1' then
                if rx_i /= tx_o then
                  fsm_state <= s_to_error_frame;
                elsif bit_count = c_crc_delimiter_index then
                  fsm_state <= s_ack;
                  bit_count <= 1;
                end if;
              else
                -- Frame CRC error (6.6.21.2.c)[1]
                -- The error frame will be sent at the first bit of the EOF filed (6.6.21.3.1)[1]
                if (bit_count < c_crc_delimiter_index) then
                  v_crc_index := crc_i'length - bit_count;
                  if (crc_i(v_crc_index) /= rx_i) then
                    crc_error <= '1';
                  end if;
                else
                  if (rx_i = '0') then
                    crc_error <= '1';
                    fsm_state <= s_to_error_frame;
                  else
                    fsm_state <= s_ack;
                    bit_count <= 1;
                    if crc_error = '0' then
                      -- Receiver node has reached the ACK slot with no errors - it now becomes transmitter of the ACK bit.
                      transmit_ack <= '1';
                    end if;
                  end if;
                end if;
              end if;
            end if;

          ------------------------------------------------------------------------------
          -- ACK state. Transmit / receive ACK bit and ACK delimiter bit
          ------------------------------------------------------------------------------
          when s_ack =>
            if transmit_i = '1' then
              if transmit_ack = '1' then
                tx_o         <= '0';                                            -- Transmit ACK bit
                transmit_ack <= '0';
              end if;
            elsif sample_rx_i = '1' then
              bit_count <= bit_count + 1;
              if (is_transmitter = '1') and (bit_count = c_ack_pos) and (rx_i = '1') then -- ACK error (6.6.21.2.e)[1]
                -- Transmitter samples a recessive ACK bit
                fsm_state <= s_to_error_frame;
                ack_error <= '1';
              elsif (bit_count = c_ack_delimiter_pos) then
                if (crc_error = '1') or (rx_i = '0') then                       -- Check ACK delimiter
                  fsm_state <= s_to_error_frame;
                else
                  fsm_state <= s_end_of_frame;
                  bit_count <= 1;
                end if;
              end if;
            end if;

          ------------------------------------------------------------------------------
          -- End of frame state. Transmit / receive EOF bits
          ------------------------------------------------------------------------------
          when s_end_of_frame =>
            if sample_rx_i = '1' then
              bit_count <= bit_count + 1;
              if rx_i = '0' then                                                -- Check for form (6.6.21.2.d) and overload (6.6.21.3.2)
                fsm_state <= s_to_error_frame;
              elsif bit_count = c_eof_length then
                if is_transmitter = '1' then
                  ats_reset_o <= '1';
                  sta_reset_o <= '1';
                  -- Ack that frame was received
                  ack_o       <= '1';
                  -- Decrement error count
                  tec_control <= count_down_1;                                  -- 8.1.4.2.g
                else
                  sta_ack_o   <= '1';
                  rec_control <= count_down_1;                                  -- 8.1.4.2.h
                end if;
                fsm_state <= s_intermission;
                bit_count <= 1;
              end if;
            end if;

          ------------------------------------------------------------------------------
          -- Intermission state. (6.6.7.2)[1] 
          ------------------------------------------------------------------------------
          when s_intermission =>
            rx_r <= rx_i;
            if transmit_i = '1' then
              if bit_count = 1 then
                can_node_clk_reset_o <= '1';
              end if;
            elsif sample_rx_i = '1' then
              bit_count <= bit_count + 1;
              if (rx_i = '0') and (rx_r = '0') and (bit_count <= c_dominant_bit_at_2_bit_intermission) then -- Check for overload (6.6.21.3.2)
                is_transmitter <= '0';
                fsm_state      <= s_to_error_frame;
              else
                if bit_count = c_intermission_length then
                  go_to_suspended <= '0';
                  is_transmitter  <= '0';
                  fsm_state       <= s_idle;
                  bit_count       <= 1;
                  if (rx_i = '0') and (rx_r = '0') then
                    fsm_state <= s_to_arbitration;
                  else
                    if (go_to_suspended = '1') then
                      fsm_state <= s_suspend_transmission;
                    end if;
                  end if;
                end if;
              end if;
            end if;

          ------------------------------------------------------------------------------
          -- A single step stage to set the values for the error stage.
          ------------------------------------------------------------------------------
          when s_to_error_frame =>
            fsm_state                <= s_error_frame;
            bit_count                <= 1;
            frame_in_progress_o      <= '0';
            -- Reset the can_sta module (The incoming frame is not valid)
            sta_reset_o              <= '1';
            crc_start_o              <= '1';
            do_not_count_stuff_error <= '0';
            -- Clear error flags. Ack is cleared later.
            crc_error                <= '0';
            stuff_bit_error          <= '0';

            if (is_transmitter = '1') and (node_error_state = s_error_passive) then
              go_to_suspended <= '1';
            end if;

            if is_transmitter = '1' then
              if (not ((node_error_state = s_error_passive) and (ack_error = '1'))) and (do_not_count_stuff_error = '0') then -- 8.1.4.2.c.ex1: Do not count on ack error. The ack error will be counted if another node is sending an error flag.
                tec_control <= count_up_8;
              end if;
            else                                                                -- 8.1.4.2.a
              rec_control <= count_up_1;
            end if;

            -- If passive receiver, it should just wait for 6 equal bits.
            if (node_error_state = s_error_passive) and (is_transmitter = '0') then
              fsm_state <= s_error_passive_wait;
            end if;

          ------------------------------------------------------------------------------
          -- Send out 6 dominant bits, this will induce a stuff bit error at all 
          -- other controllers.
          ------------------------------------------------------------------------------
          when s_error_frame =>
            if transmit_i = '1' then
              if node_error_state = s_error_active then
                tx_o <= '0';                                                    -- In error passive it "sends" 1 bits.
              end if;

            elsif sample_rx_i = '1' then
              bit_count <= bit_count + 1;
              if (node_error_state = s_error_passive) then
                if (ack_error = '1') and (rx_i = '0') and (is_transmitter = '1') then -- 8.1.4.2.c.ex1 -- If rx_i is dominant we know there was an error.
                  tec_control <= count_up_8;
                  ack_error   <= '0';
                end if;
              elsif node_error_state = s_error_active then
                if rx_i = '1' then
                  if is_transmitter = '1' then                                  -- 8.1.4.2.d
                    tec_control <= count_up_8;
                  else                                                          -- 8.1.4.2.e
                    rec_control <= count_up_8;
                  end if;
                end if;
              end if;

              if bit_count = c_error_frame_count then
                fsm_state <= s_error_frame_check;
                bit_count <= 1;
                if node_error_state = s_bus_off_node_state then
                  fsm_state <= s_bus_off;
                end if;
              end if;
            end if;

          ------------------------------------------------------------------------------
          -- Receivers in error passive must wait for 6 recessive.
          -- 6.6.5.2 Last paragraph.
          ------------------------------------------------------------------------------
          when s_error_passive_wait =>
            if sample_rx_i = '1' then
              bit_count <= 1;
              if rx_i = rx_r then
                bit_count <= bit_count + 1;
                if bit_count = c_error_frame_count then
                  bit_count <= 1;
                  fsm_state <= s_error_frame_check;
                end if;
              end if;
            end if;

          ------------------------------------------------------------------------------
          -- Check if the bit after the error flag is dominant. That means it
          -- was the first to detect the error.
          ------------------------------------------------------------------------------
          when s_error_frame_check =>
            -- Clear error flags
            ack_error <= '0';
            if sample_rx_i = '1' then
              fsm_state <= s_error_frame_delimiter;
              bit_count <= 2;                                                   -- Either we have counted a dominant or recessive bit, so we only need to count from 2.
              if rx_i = '0' then
                fsm_state <= s_error_frame_dominant_delimiter;
                if is_transmitter = '0' then                                    -- 8.1.4.2.b
                  rec_control <= count_up_8;
                end if;
              end if;
            end if;

          ------------------------------------------------------------------------------
          -- Wait for the bus to recessive.
          -- 8.1.4.2.f - We can tolerate up to 7 consecutive dominant bits after sending 
          -- an active error flag or overload flag. or 14 if passive error flag.
          -- And after that every 8 should count up in error count.
          ------------------------------------------------------------------------------
          when s_error_frame_dominant_delimiter =>
            if sample_rx_i = '1' then
              if rx_i = '0' then                                                -- 8.1.4.2.f
                bit_count <= bit_count + 1;
                if bit_count = c_dominant_bit_in_error then
                  bit_count <= 1;
                  if is_transmitter = '1' then
                    tec_control <= count_up_8;
                  else
                    rec_control <= count_up_8;
                  end if;
                end if;
              else
                fsm_state <= s_error_frame_delimiter;
                bit_count <= 1;
              end if;
            end if;

          ------------------------------------------------------------------------------
          -- We also need to wait for 8 recessive bits. We have already sent 1, so we
          -- need to wait for 7 more. 6.6.5.3
          ------------------------------------------------------------------------------
          when s_error_frame_delimiter =>
            if sample_rx_i = '1' then
              bit_count <= bit_count + 1;
              if rx_i = '1' then
                if bit_count = c_recessive_bits_in_error_delimiter then
                  fsm_state <= s_intermission;
                  bit_count <= 1;
                end if;
              else                                                              -- Form error and overload (6.6.21.3.2)
                is_transmitter <= '0';
                fsm_state      <= s_to_error_frame;
              end if;
            end if;

          ------------------------------------------------------------------------------
          -- Bus off state. Stay here until node is reset
          ------------------------------------------------------------------------------
          when s_bus_off =>
            null;

          --coverage off
          when others =>
            fsm_state <= s_bus_reintegration;
            --coverage on
        end case;

      end if;
    end if;
  end process;
  --@alint rule_state on STARC_VHDL.2.7.3.1_a

end architecture;

-- eof
