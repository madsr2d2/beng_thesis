library ieee;
  use ieee.std_logic_1164.all;
  use ieee.numeric_std.all;
  use work.can_pkg.all;

entity bit_stuffer_fd is
  port (
    bs_fd_i : in    mac_fsm_to_bs_fd_if_t;
    bs_fd_o : out   bs_fd_to_mac_fsm_if_t
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

  -- Signal declarations
  signal count_reg : unsigned(2 downto 0);
  signal wire      : std_logic;

begin

  -- Encodes the stuff bit count in Gray code with parity bit
  p_stuff_bit_count_encode : process (bs_fd_i.clk) is

    variable v_gray_bits  : std_logic_vector(2 downto 0);
    variable v_parity_bit : std_logic;
    variable v_count_temp : unsigned(2 downto 0);

  begin

    if rising_edge(bs_fd_i.clk) then
      if (bs_fd_i.rst = '1') then
        count_reg    <= (others => '0');
        bs_fd_o.sbc  <= (others => '0');
        v_gray_bits  := (others => '0');
        v_parity_bit := '0';
        v_count_temp := (others => '0');
      else
        if (wire = '1') then
          v_count_temp := count_reg + 1;
          v_gray_bits  := to_gray(std_logic_vector(v_count_temp));       -- Gray code count
          v_parity_bit := calc_parity(v_gray_bits);                      -- Calc parity bit

          -- Update registers
          bs_fd_o.sbc <= v_gray_bits & v_parity_bit;
          count_reg   <= v_count_temp;
        end if;
      end if;
    end if;

  end process p_stuff_bit_count_encode;

  -- Bit stuffer FSM
  u_bit_stuffer : entity work.bit_stuffer
    port map (
      clk               => bs_fd_i.clk,
      rst               => bs_fd_i.rst,
      data_i            => bs_fd_i.data,
      valid_i           => bs_fd_i.data_valid,
      stuff_bit_o       => bs_fd_o.stuff_bit,
      stuff_bit_valid_o => wire
    );

  bs_fd_o.stuff_bit_valid <= wire;

end architecture rtl;
