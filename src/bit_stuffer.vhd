library ieee;
  use ieee.std_logic_1164.all;

entity bit_stuffer is
  port (
    clk : in    std_logic;
    rst : in    std_logic;

    -- input data stream
    data_i  : in    std_logic;
    valid_i : in    std_logic;

    -- Output data stream
    stuff_bit_o       : out   std_logic;
    stuff_bit_valid_o : out   std_logic
  );
end entity bit_stuffer;

architecture rtl of bit_stuffer is

  type state_t is (idle, count_1, count_2, count_3,  count_4, stuff);

  signal state_reg,    state_next    : state_t;
  signal last_bit_reg, last_bit_next : std_logic;

begin

  -- State register
  p_state_update : process (clk) is
  begin

    if rising_edge(clk) then
      if (rst = '1') then
        state_reg    <= idle;
        last_bit_reg <= '0';
      else
        state_reg    <= state_next;
        last_bit_reg <= last_bit_next;
      end if;
    end if;

  end process p_state_update;

  p_next_state_and_output_logic : process (all) is
  begin

    -- Defaults
    state_next        <= state_reg;
    last_bit_next     <= last_bit_reg;
    stuff_bit_o       <= '0';
    stuff_bit_valid_o <= '0';

    if (valid_i = '1') then
      case state_reg is
        when idle =>
          last_bit_next <= data_i;
          state_next    <= count_1;

        when count_1 =>
          if (data_i = last_bit_reg) then
            state_next <= count_2;
          else
            state_next    <= count_1;
            last_bit_next <= data_i;
          end if;

        when count_2 =>
          if (data_i = last_bit_reg) then
            state_next <= count_3;
          else
            state_next    <= count_1;
            last_bit_next <= data_i;
          end if;

        when count_3 =>
          if (data_i = last_bit_reg) then
            state_next <= count_4;
          else
            state_next    <= count_1;
            last_bit_next <= data_i;
          end if;

        when count_4 =>
          if (data_i = last_bit_reg) then
            state_next <= stuff;
          else
            state_next    <= count_1;
            last_bit_next <= data_i;
          end if;

        when stuff =>
          stuff_bit_o       <= not last_bit_reg;
          stuff_bit_valid_o <= '1';

          state_next    <= count_1;
          last_bit_next <= data_i;
        when others =>

      end case;
    end if;

  end process p_next_state_and_output_logic;

end architecture rtl;
