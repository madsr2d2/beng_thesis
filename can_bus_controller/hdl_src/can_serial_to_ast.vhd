--------------------------------------------------------------------------------------------------------------------------------------------------------------
-- Copyright 2025 Everllence, Teglholmsgade 41, 2450 Copenhagen SV, Denmark
--------------------------------------------------------------------------------------------------------------------------------------------------------------
--
-- Requirements:  
--
-- Description:   
--
-- Revision log:  Date:       Initial:  JIRA:
--                2025-04-24  TMYAES:   [TRIT-3892] [FPGA] CAN-bus controller - initial file
--                2025-08-08  AFNI:     [TRIT-4042] [FPGA] Integrate can-bus controller into the io_ext
--
--------------------------------------------------------------------------------------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

use work.pk_man_global.all;
use work.pk_eth_st;
use work.pk_can_bus_controller.all;

entity can_serial_to_ast is
  port(
    clk_i     : in  std_logic;
    reset_i   : in  std_logic;

    -- can_fsm interface
    valid_i   : in  std_logic;
    ack_i     : in  std_logic;                                                  -- Acknowledge signal from the CAN FSM

    --
    rx_i      : in  std_logic;

    --
    src_s2d_o : out pk_eth_st.t_eth_st_s2d;
    src_d2s_i : in  pk_eth_st.t_eth_st_d2s
  );
end entity;

architecture rtl of can_serial_to_ast is
  ----------------------------------------------------------------------------
  -- Types
  ----------------------------------------------------------------------------
  type t_state is (s_id, s_control, s_data);


  ----------------------------------------------------------------------------
  -- Constants
  ----------------------------------------------------------------------------
  constant c_max_byte_cnt : integer := 8;

  ----------------------------------------------------------------------------
  -- Signals
  ----------------------------------------------------------------------------
  signal state       : t_state;
  signal bit_count   : integer range 0 to c_max_byte_cnt * c_bits_in_byte;
  signal byte_count  : integer range 0 to c_bytes_in_can_llc_frame;             -- Byte count for the CAN LLC frame
  signal can_frame   : t_can_frame;                                             -- CAN frame buffer
  signal frame_valid : std_logic;                                               -- Flag to indicate waiting for ACK
  signal id          : std_logic_vector(c_bits_in_ext_id - 1 downto 0);         -- Extended ID for the CAN frame

  signal frame_ready : std_logic;
begin

  ---------------------------------------------------------------------------
  -- Process: can_serial_to_ast
  ----------------------------------------------------------------------------
  p_fsm : process(clk_i)
    variable v_next_bit_index  : integer range 0 to c_bits_in_byte - 1;
    variable v_byte_index      : integer range c_data_index_can_llc_frame to c_data_index_can_llc_frame + c_max_data_count;
    variable v_next_byte_count : integer range 0 to c_bytes_in_can_llc_frame;
  begin
    if rising_edge(clk_i) then
      if reset_i = '1' then
        state       <= s_id;
        bit_count   <= 1;
        byte_count  <= 0;
        src_s2d_o   <= pk_eth_st.c_eth_st_s2d_zero_idle;
        frame_ready <= '1';
        can_frame   <= (others => (others => '0'));
        id          <= (others => '0');
        frame_valid <= '0';                                                     -- Reset ACK seen flag
      else
        -- Acknowledgment was seen so frame is valid 
        if ack_i = '1' then
          frame_valid <= '1';
        end if;

        -- A frame is ready to be sent out. Wait for the frame_valid signal to be set before sending the frame.  
        if (not frame_ready) and frame_valid then

          if src_d2s_i.ready = '1' then
            src_s2d_o.valid <= '1';

            if byte_count < c_bytes_in_can_llc_frame then
              src_s2d_o.data <= can_frame(byte_count);
            end if;

            if byte_count = 0 then
              src_s2d_o.startofpacket <= '1';
            else
              src_s2d_o.startofpacket <= '0';
            end if;

            if byte_count = (c_bytes_in_can_llc_frame - 1) then
              src_s2d_o.endofpacket <= '1';
            else
              src_s2d_o.endofpacket <= '0';
            end if;

            if byte_count = (c_bytes_in_can_llc_frame) then
              src_s2d_o   <= pk_eth_st.c_eth_st_s2d_zero_idle;
              frame_ready <= '1';
              frame_valid <= '0';
              byte_count  <= 0;
              can_frame   <= (others => (others => '0'));
              id          <= (others => '0');
            else
              byte_count <= byte_count + 1;
            end if;
          end if;

        elsif valid_i then
          bit_count <= bit_count + 1;

          case state is
            ----------------------------------------------------------------------------
            -- Sample the id bits for the can frame.
            --
            -- If the 13 in is '0' it is a extended and therefore it needs to load
            -- more bits before it transmit them.
            ----------------------------------------------------------------------------
            when s_id =>
              case bit_count is
                when c_std_rtr_index =>
                  can_frame(c_rtr_index_can_llc_frame)(0) <= rx_i;              -- Set RTR bit

                when c_std_ide_index =>
                  can_frame(c_ide_index_can_llc_frame)(0) <= rx_i;              -- Set IDE bit
                  if rx_i = '0' then                                            -- Standard frame format detected
                    state                                            <= s_control;
                    bit_count                                        <= 2;
                    -- Set the standard frame ID
                    can_frame(c_std_id_byte_index_can_llc_frame + 1) <= id(7 downto 0);
                    can_frame(c_std_id_byte_index_can_llc_frame)     <= B"00000" & id(c_bits_in_std_id - 1 downto 8);
                  end if;

                when c_ext_rtr_index =>
                  can_frame(c_rtr_index_can_llc_frame)(0)          <= rx_i;     -- Set RTR bit
                  state                                            <= s_control;
                  bit_count                                        <= 1;
                  -- Set the extended frame ID
                  can_frame(c_ext_id_byte_index_can_llc_frame + 3) <= id(7 downto 0);
                  can_frame(c_ext_id_byte_index_can_llc_frame + 2) <= id(15 downto 8);
                  can_frame(c_ext_id_byte_index_can_llc_frame + 1) <= id(23 downto 16);
                  can_frame(c_ext_id_byte_index_can_llc_frame)     <= B"000" & id(28 downto 24);

                when others =>
                  id    <= std_logic_vector(unsigned(id) sll 1);
                  id(0) <= rx_i;
              end case;

            ----------------------------------------------------------------------------
            -- It is now time to get the control data length bits. If it was remote
            -- request frame, go back to id and wait for a new frame. 
            ----------------------------------------------------------------------------
            when s_control =>
              if bit_count = 6 then
                state     <= s_data;                                            -- Move to data state
                bit_count <= 0;

                if can_frame(c_rtr_index_can_llc_frame)(0) = '1' then           -- RTR frame detected
                  state       <= s_id;
                  bit_count   <= 1;
                  frame_ready <= '0';
                end if;
              end if;
              if bit_count > 2 then
                can_frame(c_dlc_index_can_llc_frame) <= can_frame(c_dlc_index_can_llc_frame)(can_frame(c_dlc_index_can_llc_frame)'high - 1 downto 0) & rx_i;
              end if;

            ----------------------------------------------------------------------------
            -- It is now time to get all the data.
            ----------------------------------------------------------------------------
            when s_data =>
              v_next_bit_index           := (bit_count + 1) mod c_bits_in_byte;
              v_byte_index               := byte_count + c_data_index_can_llc_frame;
              can_frame(v_byte_index)    <= std_logic_vector(unsigned(can_frame(v_byte_index)) sll 1);
              can_frame(v_byte_index)(0) <= rx_i;                               -- Set data byte
              if v_next_bit_index = 0 then
                v_next_byte_count := byte_count + 1;
                if v_next_byte_count = to_integer(unsigned(can_frame(c_dlc_index_can_llc_frame)(3 downto 0))) then
                  state       <= s_id;
                  frame_ready <= '0';
                  bit_count   <= 1;                                             -- Reset bit count for the next frame
                  byte_count  <= 0;
                else
                  byte_count <= v_next_byte_count;
                end if;
              end if;

            --coverage off
            when others =>
              state <= s_id;
              --coverage on
          end case;
        end if;
      end if;
    end if;
  end process p_fsm;

end architecture;


-- eof
