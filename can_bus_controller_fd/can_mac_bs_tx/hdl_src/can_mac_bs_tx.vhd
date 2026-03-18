---------------------------------------------------------------------------
-- Copyright 2025 Everllence, Teglholmsgade 41, 2450 Copenhagen SV, Denmark
---------------------------------------------------------------------------
--
-- Requirements:
--
-- Description:   Unified bit stuffer for CAN and CAN-FD TX path.
--                Counts consecutive same-polarity bits, inserts inverse stuff
--                bits at the configurable threshold (stuff_width_c), and
--                maintains a Gray-coded Stuff Bit Count (SBC) with parity.
--
-- Revision log:  Date:       Initial:  JIRA:
--                2026-03-15  TMYAES:   [TRIT-4336] Initial implementation
--
---------------------------------------------------------------------------

library ieee;
  use ieee.std_logic_1164.all;
  use ieee.numeric_std.all;
  use work.pk_can_types.all;

entity can_mac_bs_tx is
  port (
    clk_i : in    std_logic;
    rst_i : in    std_logic;
    bs_i  : in    t_can_mac_fsm_bs_tx_if_m2s;
    bs_o  : out   t_can_mac_fsm_bs_tx_if_s2m
  );
end entity can_mac_bs_tx;

architecture rtl of can_mac_bs_tx is

  signal count       : integer range 0 to c_stuff_width;
  signal last_polarity    : std_logic;
  signal stuff_count : t_stuff_count;

  function f_calc_parity (
    v : std_logic_vector
  ) return std_logic is
    variable v_parity : std_logic := '0';
  begin
    for i in v'range loop
      v_parity := v_parity xor v(i);
    end loop;
    return v_parity;
  end function f_calc_parity;

  function f_to_gray (
    v : std_logic_vector
  ) return std_logic_vector is
    variable v_result : std_logic_vector(v'range);
  begin
    v_result(v'left) := v(v'left);
    for i in v'left - 1 downto v'right loop
      v_result(i) := v(i) xor v(i + 1);
    end loop;
    return v_result;
  end function f_to_gray;

begin

  p_bit_stuffing : process (clk_i) is
  begin

    if rising_edge(clk_i) then
      if ((rst_i = '1') or (bs_i.start = '1')) then
        count       <= 0;
        last_polarity    <= c_recessive;
        stuff_count <= (others => '0');
        bs_o        <= c_can_mac_fsm_bs_tx_if_s2m_reset;

      elsif (bs_i.valid) then
        bs_o.valid <= '0';
        count      <= 1;
        last_polarity   <= bs_i.data;

        if (bs_i.data = last_polarity) then
          count <= count + 1;
          if (count = c_stuff_width - 1) then
            count       <= 0;
            bs_o.data   <= not last_polarity;
            bs_o.valid  <= '1';
            stuff_count <= stuff_count + 1;
            bs_o.sbc    <= f_to_gray(std_logic_vector(stuff_count + 1))
                         & f_calc_parity(f_to_gray(std_logic_vector(stuff_count + 1)));
          end if;
        end if;

      else
        bs_o.valid <= '0';
      end if;
    end if;

  end process p_bit_stuffing;

end architecture rtl;
