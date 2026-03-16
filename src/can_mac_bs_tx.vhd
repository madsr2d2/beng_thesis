---------------------------------------------------------------------------
-- Copyright 2025 Everllence, Teglholmsgade 41, 2450 Copenhagen SV, Denmark
---------------------------------------------------------------------------
--
-- Requirements:
--
-- Description:   Unified bit stuffer for CAN and CAN-FD TX path.
--                Counts consecutive same-polarity bits, inserts inverse stuff
--                bits at the configurable threshold (c_stuff_width), and
--                maintains a Gray-coded Stuff Bit Count (SBC) with parity.
--                Contains PSL assertions for formal verification.
--
-- Revision log:  Date:       Initial:  JIRA:
--                2026-03-15  TMYAES:     Initial implementation
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

  signal count        : integer range 0 to c_stuff_width;
  signal last_polarity : std_logic;
  signal stuff_count  : t_stuff_count;

  -- PSL-only: shadow registers for formal verification
  signal reset_done        : std_logic;
  signal stuff_count_prev  : t_stuff_count;
  signal count_prev        : integer range 0 to c_stuff_width;

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
        count          <= 0;
        count_prev     <= 0;
        last_polarity  <= c_recessive;
        stuff_count    <= (others => '0');
        stuff_count_prev <= (others => '0');
        reset_done     <= '0';
        bs_o           <= c_can_mac_fsm_bs_tx_if_s2m_reset;

      elsif (bs_i.valid = '1') then
        reset_done <= '1';
        bs_o.valid <= '0';
        count      <= 1;
        last_polarity <= bs_i.data;

        -- PSL-only: shadow previous values
        count_prev       <= count;
        stuff_count_prev <= stuff_count;

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
        reset_done <= '1';
        bs_o.valid <= '0';

        -- PSL-only: shadow previous values
        count_prev       <= count;
        stuff_count_prev <= stuff_count;
      end if;
    end if;

  end process p_bit_stuffing;

--------------------------------------------------------------
-- REQ-MAC-063 and REQ-MAC-056: Bit counting and SBC generation
--------------------------------------------------------------

--------------------------------------------------------------
-- Default clock
--------------------------------------------------------------
-- psl default clock is rising_edge(clk_i);
--------------------------------------------------------------

--------------------------------------------------------------
-- Environment assumptions
--------------------------------------------------------------
-- psl assume_no_unknown_data : assume always
-- (bs_i.data = c_dominant or bs_i.data = c_recessive);
-- psl assume_reset_init : assume (rst_i = '1');
-- psl assume_reset_done_init : assume (reset_done = '0');
-- psl assume_no_reset_during_valid : assume always
-- { bs_i.valid = '1' }
-- |->
-- { rst_i /= '1' and bs_i.start /= '1' };
--------------------------------------------------------------

--------------------------------------------------------------
-- Assertions
--------------------------------------------------------------
-- psl psl_1 : assert always
-- { rst_i = '1' or bs_i.start = '1' }
-- |=>
-- { bs_o.valid = '0' and
-- bs_o.data = c_recessive and
-- bs_o.sbc = "0000" }
-- report "Reset did not clear outputs to default values";
--------------------------------------------------------------
-- psl psl_2 : assert always
-- { reset_done = '1' }
-- |->
-- { bs_o.sbc(0) = ( bs_o.sbc(3) xor bs_o.sbc(2) xor bs_o.sbc(1) ) }
-- report "SBC parity bit incorrect";
--------------------------------------------------------------
-- psl psl_2a : assert always
-- { reset_done = '1' }
-- |->
-- { count <= c_stuff_width }
-- report "Induction helper: count out of bounds";
--------------------------------------------------------------
-- psl psl_3 : assert always
-- { reset_done = '1' and
-- bs_o.valid = '1' }
-- |->
-- { count_prev = c_stuff_width - 1 and
-- bs_o.data /= last_polarity and
-- stuff_count = ( stuff_count_prev + 1 ) }
-- report "Stuff bit fired at wrong count, wrong polarity, or SBC not incremented";
--------------------------------------------------------------
-- psl psl_4 : assert always
-- { bs_i.valid = '1' and bs_i.data = c_recessive ;
-- ( bs_i.valid = '1' and bs_i.data = c_dominant )[*5] }
-- |=>
-- { bs_o.valid = '1' and bs_o.data = c_recessive }
-- report "No stuff bit after 5 consecutive dominant bits";
--------------------------------------------------------------
-- psl psl_5 : assert always
-- { bs_i.valid = '1' and bs_i.data = c_dominant ;
-- ( bs_i.valid = '1' and bs_i.data = c_recessive )[*5] }
-- |=>
-- { bs_o.valid = '1' and bs_o.data = c_dominant }
-- report "No stuff bit after 5 consecutive recessive bits";
--------------------------------------------------------------

end architecture rtl;
