--------------------------------------------------------------------------------------------------------------------------------------------------------------
-- Copyright 2025 Everllence, Teglholmsgade 41, 2450 Copenhagen SV, Denmark
--------------------------------------------------------------------------------------------------------------------------------------------------------------
--
-- Requirements:  
--
-- Description:   CAN AST to serial converter. Converts the CAN AST frame to a serial bit stream.
--
-- Revision log:  Date:       Initial:  JIRA:
--                2025-04-24  TMYAES:   [TRIT-3880] [FPGA] CAN-bus controller
--                2025-08-08  AFNI:     [TRIT-4042] [FPGA] Integrate can-bus controller into the io_ext
--                2025-09-15  AFNI:     [TRIT-4092] [FPGA] IO-Extender LED, MDIO interface, and link-status
--
--------------------------------------------------------------------------------------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.math_real.log2;
use ieee.math_real.ceil;

use work.pk_man_global.all;
use work.pk_eth_st;
use work.pk_can_bus_controller.all;

entity can_ast_to_serial is
  port(
    clk_i             : in  std_logic;
    reset_i           : in  std_logic;

    -- can_fsm interface
    frame_bit_valid_o : out std_logic;                                          -- Indicate that valid data is available on frame_bit_o
    frame_bit_o       : out std_logic;                                          -- Current bit of the frame
    rtr_bit_o         : out std_logic;                                          -- Frame RTR bit
    ide_bit_o         : out std_logic;                                          -- Frame IDE bit
    dlc_bits_o        : out std_logic_vector(3 downto 0);                       -- Frame DLC bits
    ready_i           : in  std_logic;                                          -- When asserted, the next frame_bit_o is pushed onto frame_bit_o
    is_transmitter_i  : in  std_logic;                                          -- Indicate if the node is a transmitter or receiver (0 = receiver, 1 = transmitter)

    --
    sink_s2d_i        : in  pk_eth_st.t_eth_st_s2d;
    sink_d2s_o        : out pk_eth_st.t_eth_st_d2s
  );
end entity;

architecture rtl of can_ast_to_serial is
  ----------------------------------------------------------------------------
  -- Types
  ----------------------------------------------------------------------------
  type t_ats_fsm_state is (s_idle, s_write_frame_to_ram, s_serialize_frame, s_load_shift_reg, s_shift);

  constant c_addr_l : integer := integer(ceil(log2(real(c_bytes_in_can_llc_frame))));

  ----------------------------------------------------------------------------
  -- Signals
  ----------------------------------------------------------------------------
  -- RAM control signals
  signal addr      : natural range 0 to c_bytes_in_can_llc_frame;
  signal read_data : std_logic_vector(7 downto 0);

  signal ats_fsm_state : t_ats_fsm_state := s_idle;

  -- Shift register control signals
  signal load_shift_reg : boolean;
  signal shift_reg      : std_logic_vector(7 downto 0);
  signal shift_left     : boolean;

  -- Shifter counter
  signal bit_count    : integer range 0 to 7;
  signal padding_bits : integer range 0 to 7;

  signal is_transmitter_i_r : std_logic;                                        -- Previous value of is_transmitter_i to detect changes
  signal dlc_bits           : std_logic_vector(3 downto 0);                     -- Frame DLC bits

begin

  ----------------------------------------------------------------------------
  -- Shift register with a load and shift left function
  ----------------------------------------------------------------------------
  p_shift_reg : process(clk_i)
  begin
    if rising_edge(clk_i) then
      if reset_i = '1' then
        shift_reg   <= (others => '0');
        frame_bit_o <= '0';
      else

        if load_shift_reg then
          shift_reg   <= read_data;                                             -- Load byte
          frame_bit_o <= read_data(7);

        elsif shift_left or ((ready_i = '1') and (frame_bit_valid_o = '1')) then
          frame_bit_o <= shift_reg(6);
          shift_reg   <= std_logic_vector(unsigned(shift_reg) sll 1);

        end if;
      end if;
    end if;
  end process;

  ----------------------------------------------------------------------------
  -- RAM
  ----------------------------------------------------------------------------
  u_ram_wrap : entity work.ram_wrap
    generic map(
      gc_addr_l => c_addr_l,
      gc_depth  => 2 ** c_addr_l,
      gc_data_l => sink_s2d_i.data'length
    )
    port map(
      clk_i        => clk_i,
      p0_addr_i    => std_logic_vector(to_unsigned(addr, c_addr_l)),
      p0_wr_en_i   => sink_s2d_i.valid and sink_d2s_o.ready,
      p0_wr_data_i => sink_s2d_i.data,
      p0_rd_data_o => read_data
    );

  ----------------------------------------------------------------------------
  -- FSM
  ----------------------------------------------------------------------------
  p_a2c_fsm : process(clk_i)
    variable v_dlc_bits : unsigned(dlc_bits'high + 1 downto 0);
  begin
    if rising_edge(clk_i) then
      if reset_i = '1' then
        sink_d2s_o         <= pk_eth_st.c_eth_st_d2s_idle;
        bit_count          <= 0;
        addr               <= 0;
        ats_fsm_state      <= s_idle;
        frame_bit_valid_o  <= '0';
        ide_bit_o          <= '0';
        load_shift_reg     <= false;
        shift_left         <= false;
        rtr_bit_o          <= '0';
        dlc_bits           <= (others => '0');
        padding_bits       <= 0;
        is_transmitter_i_r <= '0';

      else
        shift_left        <= false;
        load_shift_reg    <= false;
        sink_d2s_o.ready  <= '0';
        frame_bit_valid_o <= '0';

        case ats_fsm_state is
          ----------------------------------------------------------------------------
          -- Idle state, waiting for new frame
          ----------------------------------------------------------------------------
          when s_idle =>
            frame_bit_valid_o <= '0';
            addr              <= 0;
            bit_count         <= 0;
            sink_d2s_o.ready  <= '1';

            if (sink_s2d_i.valid = '1') and (sink_s2d_i.startofpacket = '1') and (sink_d2s_o.ready = '1') then -- New frame available
              addr          <= addr + 1;
              ats_fsm_state <= s_write_frame_to_ram;
            end if;

          ----------------------------------------------------------------------------
          --  This state write ID, DLC and data bytes to ram and set dlc bits, RTR and IDE bits.
          ----------------------------------------------------------------------------
          when s_write_frame_to_ram =>
            sink_d2s_o.ready <= '1';                                            -- Indicate to source that we are ready for next byte
            if sink_s2d_i.valid = '1' then
              addr <= addr + 1;                                                 -- Increment address

              case addr is
                when c_dlc_index_can_llc_frame =>
                  dlc_bits <= sink_s2d_i.data(3 downto 0);                      -- Set DLC bits

                when c_ide_index_can_llc_frame =>
                  ide_bit_o <= sink_s2d_i.data(0);                              -- Set IDE bit

                when c_rtr_index_can_llc_frame =>
                  rtr_bit_o     <= sink_s2d_i.data(0);                          -- Set RTR bit
                  ats_fsm_state <= s_load_shift_reg;

                  -- Set address to MS byte of ID and shift out padding bits
                  if ide_bit_o = '1' then                                       -- Extended ID frame
                    addr         <= 0;
                    padding_bits <= 3;
                  else                                                          -- Standard ID frame
                    addr         <= 2;
                    padding_bits <= 5;
                  end if;

                when others => null;
              end case;
            end if;

          ----------------------------------------------------------------------------
          -- This state loads the shift register with the data on RAM(addr).
          ----------------------------------------------------------------------------
          when s_load_shift_reg =>
            load_shift_reg <= true;
            bit_count      <= padding_bits;                                     -- Set bit counter to the number of padding bits to shift out

            if padding_bits /= 0 then                                           -- Go to shift if we got bits to shift out
              ats_fsm_state <= s_shift;
            else                                                                -- No bits to shift out, go to serialize frame state
              ats_fsm_state <= s_serialize_frame;
            end if;

          ----------------------------------------------------------------------------
          -- This state shifts out the number of bits specified by shift_count
          ----------------------------------------------------------------------------
          when s_shift =>
            if padding_bits = 0 then                                            -- Done shifting out padding bits. frame_bit_o now contains valid data
              ats_fsm_state     <= s_serialize_frame;
              frame_bit_valid_o <= '1';
            else                                                                -- Still got padding bits to shift out
              padding_bits <= padding_bits - 1;
              shift_left   <= true;
            end if;

          ----------------------------------------------------------------------------
          -- This state shifts the next frame bit unto frame_bit_o when ready_i is '1'
          ----------------------------------------------------------------------------
          when s_serialize_frame =>
            frame_bit_valid_o  <= '1';                                          -- Valid data available on frame_bit_o
            is_transmitter_i_r <= is_transmitter_i;

            -- Reset to to MSB of ID if arbitration lost
            if (is_transmitter_i = '0') and (is_transmitter_i_r = '1') then
              addr          <= 2;
              padding_bits  <= 5;
              if ide_bit_o = '1' then
                addr         <= 0;
                padding_bits <= 3;
              end if;
              ats_fsm_state <= s_load_shift_reg;
            elsif (ready_i = '1') and (frame_bit_valid_o = '1') then
              if bit_count = (c_bits_in_byte - 1) then                          -- A full byte was shifted out
                bit_count         <= 0;
                addr              <= addr + 1;
                ats_fsm_state     <= s_load_shift_reg;
                frame_bit_valid_o <= '0';

                if addr = 3 then                                                -- Next byte is DLC, so 4 padding bits to shift out
                  padding_bits <= 4;
                end if;

                v_dlc_bits := resize(unsigned(dlc_bits), v_dlc_bits'length) + 4;
                if (addr = to_integer(v_dlc_bits)) then                         -- Last byte of frame was shifted out so reset to MS byte of ID
                  if ide_bit_o = '1' then
                    addr         <= 0;
                    padding_bits <= 3;
                  else
                    addr         <= 2;
                    padding_bits <= 5;
                  end if;
                  ats_fsm_state <= s_load_shift_reg;
                end if;
              else
                bit_count <= bit_count + 1;
              end if;
            end if;


          --coverage off
          when others =>
            ats_fsm_state <= s_idle;
            --coverage on
        end case;

      end if;
    end if;
  end process;

  dlc_bits_o <= dlc_bits;

end architecture;

-- eof
