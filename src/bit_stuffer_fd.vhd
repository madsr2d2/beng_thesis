library ieee;
  use ieee.std_logic_1164.all;
  use ieee.numeric_std.all;

entity bit_stuffer_fd is
  port (
    clk : in    std_logic;
    rst : in    std_logic;

    -- input data stream
    data_i  : in    std_logic;
    valid_i : in    std_logic;

    -- Output data stream
    stuff_bit_o       : out   std_logic;
    stuff_bit_valid_o : out   std_logic;
    bsc_and_parity_o  : out   std_logic_vector(3 downto 0)
  );
end entity bit_stuffer_fd;

architecture rtl of bit_stuffer_fd is

  -- Function calculates the parity bit of a std_logic_vector

  function calc_parity (
    v : std_logic_vector
  ) return std_logic is

    variable v_parity : std_logic := '0';

  begin

    for i in v'range loop

      v_parity := v_parity xor v(i);

    end loop;

    return v_parity;

  end function calc_parity;

  -- Function Gray encodes a std_logic_vector

  function to_gray (
    v : std_logic_vector
  ) return std_logic_vector is

    variable result : std_logic_vector(v'range);

  begin

    result(v'left) := v(v'left);

    for i in v'left - 1 downto v'right loop

      result(i) := v(i) xor v(i + 1);

    end loop;

    return result;

  end function to_gray;

  signal count_reg : unsigned(2 downto 0);
  signal wire      : std_logic;

begin

  -- Encodes the stuff bit count in Gray code with parity bit
  p_stuff_bit_count_encode : process (clk) is

    variable v_gray_bits  : std_logic_vector(2 downto 0);
    variable v_parity_bit : std_logic;
    variable v_count_temp : unsigned(2 downto 0);

  begin

    if rising_edge(clk) then
      if (rst = '1') then
        count_reg        <= (others => '0');
        bsc_and_parity_o <= (others => '0');
        v_gray_bits      := (others => '0');
        v_parity_bit     := '0';
        v_count_temp     := (others => '0');
      else
        if (wire = '1') then
          v_count_temp := count_reg + 1;
          v_gray_bits  := to_gray(std_logic_vector(v_count_temp));       -- Gray code count
          v_parity_bit := calc_parity(v_gray_bits);                      -- Calc parity bit

          -- Update registers
          bsc_and_parity_o <= v_gray_bits & v_parity_bit;
          count_reg        <= v_count_temp;
        end if;
      end if;
    end if;

  end process p_stuff_bit_count_encode;

  -- Bit stuffer FSM
  u_bit_stuffer : entity work.bit_stuffer
    port map (
      clk               => clk,
      rst               => rst,
      data_i            => data_i,
      valid_i           => valid_i,
      stuff_bit_o       => stuff_bit_o,
      stuff_bit_valid_o => wire
    );

  stuff_bit_valid_o <= wire;

end architecture rtl;
