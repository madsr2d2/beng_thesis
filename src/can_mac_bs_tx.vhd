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
--                2026-03-15  TMYAES:     Initial implementation
--
---------------------------------------------------------------------------

library ieee;
  use ieee.std_logic_1164.all;
  use ieee.numeric_std.all;
  use work.can_types_pkg.all;

entity can_mac_bs_tx is
  port (
    clk_i : in    std_logic;
    rst_i : in    std_logic;
    bs_i  : in    can_mac_fsm_bs_tx_if_m2s_t;
    bs_o  : out   can_mac_fsm_bs_tx_if_s2m_t
  );
end entity can_mac_bs_tx;

architecture rtl of can_mac_bs_tx is

  ---------------------------------------------------------------------------
  -- Reset-value constants
  ---------------------------------------------------------------------------
  constant c_consecutive_count_init : integer       := 0;
  constant c_last_polarity_init     : polarity_t    := recessive;
  constant c_stuff_count_init       : stuff_count_t := (others => '0');
  constant c_stuff_valid_prev_init  : boolean       := false;
  constant c_reset_done_init        : boolean       := false;

  ---------------------------------------------------------------------------
  -- Registered state signals
  ---------------------------------------------------------------------------
  signal consecutive_count : integer range 0 to stuff_width_c;
  signal last_polarity     : polarity_t;
  signal stuff_count       : stuff_count_t;
  signal stuff_valid_prev  : boolean;

  -- Verification-only signals: not used in logic, only for formal assertions
  signal reset_done             : boolean;
  signal stuff_count_prev       : stuff_count_t;
  signal consecutive_count_prev : integer range 0 to stuff_width_c;

  ---------------------------------------------------------------------------
  -- Calculates parity bit for as std_logic_vector
  ---------------------------------------------------------------------------
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

  ---------------------------------------------------------------------------
  -- Gray encode a std_logic_vector
  ---------------------------------------------------------------------------
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

begin

  p_bit_stuffing : process (clk_i) is

    variable v_consecutive_count : integer range 0 to stuff_width_c;
    variable v_last_polarity     : polarity_t;
    variable v_stuff_count       : stuff_count_t;
    variable v_stuff_valid       : boolean;
    variable v_stuff_data        : polarity_t;
    variable v_gray_bits         : std_logic_vector(2 downto 0);
    variable same_polarity_run   : boolean;

  begin

    if rising_edge(clk_i) then
      if (rst_i = '1' or bs_i.start) then
        consecutive_count      <= c_consecutive_count_init;
        consecutive_count_prev <= c_consecutive_count_init;
        stuff_count            <= c_stuff_count_init;
        stuff_count_prev       <= c_stuff_count_init;
        last_polarity          <= c_last_polarity_init;
        stuff_valid_prev       <= c_stuff_valid_prev_init;
        reset_done             <= c_reset_done_init;
        bs_o                   <= can_mac_fsm_bs_tx_if_s2m_reset_c;
      else
        reset_done <= true;

        -----------------------------------------------------------------
        -- 1. Bit counting: track consecutive same-polarity bits
        -----------------------------------------------------------------
        v_consecutive_count := consecutive_count;
        v_last_polarity     := last_polarity;
        v_stuff_valid       := false;
        v_stuff_data        := recessive;

        same_polarity_run := consecutive_count /= stuff_width_c
                             and bs_i.data = last_polarity;

        if (bs_i.valid) then
          if (same_polarity_run) then
            v_consecutive_count := consecutive_count + 1;
          else
            v_consecutive_count := 1;
            v_last_polarity     := bs_i.data;
          end if;

          if (v_consecutive_count >= stuff_width_c) then
            v_stuff_valid := true;
            v_stuff_data  := recessive when v_last_polarity = dominant else dominant;
          end if;
        end if;

        -----------------------------------------------------------------
        -- 2. SBC encoding: Gray-coded stuff bit count with parity
        -----------------------------------------------------------------
        v_stuff_count := stuff_count;

        if (v_stuff_valid and not stuff_valid_prev) then
          v_stuff_count := stuff_count + 1;
        end if;

        v_gray_bits := to_gray(std_logic_vector(v_stuff_count));

        -----------------------------------------------------------------
        -- 3. Drive outputs and update registers
        -----------------------------------------------------------------
        bs_o.valid <= v_stuff_valid;
        bs_o.data  <= v_stuff_data;
        bs_o.sbc   <= v_gray_bits & calc_parity(v_gray_bits);

        consecutive_count      <= v_consecutive_count;
        consecutive_count_prev <= consecutive_count;
        last_polarity          <= v_last_polarity;
        stuff_count            <= v_stuff_count;
        stuff_count_prev       <= stuff_count;
        stuff_valid_prev       <= bs_o.valid;
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
-- psl assume_no_unknown_data : assume always (bs_i.data = dominant or bs_i.data = recessive);
-- psl assume_reset_init : assume (rst_i = '1');
-- psl assume_reset_done_init : assume (not reset_done);
-- psl assume_no_reset_during_valid : assume always
-- { bs_i.valid }
-- |->
-- { rst_i /= '1' and not bs_i.start };
--------------------------------------------------------------

--------------------------------------------------------------
-- Assertions
--------------------------------------------------------------
-- psl psl_1 : assert always
-- { rst_i = '1' or bs_i.start }
-- |=>
-- { not bs_o.valid and
-- bs_o.data = recessive and
-- bs_o.sbc = "0000" }
-- report "Reset did not clear outputs to default values";
--------------------------------------------------------------
-- psl psl_2 : assert always
-- { reset_done }
-- |->
-- { bs_o.sbc(0) = ( bs_o.sbc(3) xor bs_o.sbc(2) xor bs_o.sbc(1) ) }
-- report "SBC parity bit incorrect";
--------------------------------------------------------------
-- psl psl_2a : assert always
-- { reset_done }
-- |->
-- { consecutive_count <= stuff_width_c }
-- report "Induction helper: count out of bounds";
--------------------------------------------------------------
-- psl psl_3 : assert always
-- { reset_done and
-- bs_o.valid }
-- |->
-- { consecutive_count = stuff_width_c and
-- bs_o.data /= last_polarity and
-- stuff_count = ( stuff_count_prev + 1 ) }
-- report "Stuff bit fired at wrong count, wrong polarity, or SBC not incremented";
--------------------------------------------------------------
-- psl psl_4 : assert always
-- { bs_i.valid and bs_i.data = recessive ;
-- ( bs_i.valid and bs_i.data = dominant )[*5] }
-- |=>
-- { bs_o.valid and bs_o.data = recessive }
-- report "No stuff bit after 5 consecutive dominant bits";
--------------------------------------------------------------
-- psl psl_5 : assert always
-- { bs_i.valid and bs_i.data = dominant ;
-- ( bs_i.valid and bs_i.data = recessive )[*5] }
-- |=>
-- { bs_o.valid and bs_o.data = dominant }
-- report "No stuff bit after 5 consecutive recessive bits";
--------------------------------------------------------------

end architecture rtl;
