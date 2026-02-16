library ieee;
  use ieee.std_logic_1164.all;
  use ieee.numeric_std.all;
  use work.can_types_pkg.all;
  use work.can_protocol_pkg.all;
  use work.can_timing_pkg.all;

entity bit_stuffer_fd is
  port (
    clk_i   : in    std_logic;
    rst_i   : in    std_logic;
    bs_fd_i : in    mac_fsm_to_bs_fd_if_t;
    bs_fd_o : out   bs_fd_to_mac_fsm_if_t
  );
end entity bit_stuffer_fd;

architecture rtl of bit_stuffer_fd is

  signal count_reg                : unsigned(2 downto 0);
  signal stuff_bit_valid_internal : boolean;
  signal stuff_valid_prev         : boolean;
  signal start_internal : std_logic;

begin

  -- SBC counting: increment on rising edge of stuff_bit_valid
  -- (stuff_bit_valid is level-based, so edge-detect avoids multiple counts)
  p_stuff_bit_count_encode : process (clk_i) is

    variable v_gray_bits  : std_logic_vector(2 downto 0);
    variable v_parity_bit : std_logic;
    variable v_count_temp : unsigned(2 downto 0);

  begin

    if rising_edge(clk_i) then
      if (rst_i = '1' or bs_fd_i.start = true) then
        count_reg        <= (others => '0');
        bs_fd_o.sbc      <= (others => '0');
        stuff_valid_prev <= false;
        v_gray_bits      := (others => '0');
        v_parity_bit     := '0';
        v_count_temp     := (others => '0');
      else
        stuff_valid_prev <= stuff_bit_valid_internal;

        -- Rising edge: stuff_bit_valid just went high → count this stuff bit
        if (stuff_bit_valid_internal = true and stuff_valid_prev = false) then
          v_count_temp := count_reg + 1;
          v_gray_bits  := to_gray(std_logic_vector(v_count_temp));
          v_parity_bit := calc_parity(v_gray_bits);

          bs_fd_o.sbc <= v_gray_bits & v_parity_bit;
          count_reg   <= v_count_temp;
        end if;
      end if;
    end if;

  end process p_stuff_bit_count_encode;

  -- Bit stuffer: combinational stuff bit detection
  start_internal <= '1' when bs_fd_i.start else '0';
  u_bit_stuffer : entity work.bit_stuffer
    port map (
      clk               => clk_i,
      rst               => rst_i or start_internal,
      data_i            => bs_fd_i.data,
      valid_i           => bs_fd_i.valid,
      stuff_bit_o       => bs_fd_o.data,
      stuff_bit_valid_o => stuff_bit_valid_internal
    );

  bs_fd_o.valid <= stuff_bit_valid_internal;

end architecture rtl;
