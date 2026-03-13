--------------------------------------------------------------------------------
-- Title      : CAN FD Bit Stuffer
-- Project    : Implementation and Verification of a CAN-FD Bus Transceiver in VHDL
--------------------------------------------------------------------------------
-- File       : can_mac_bs_tx.vhd
-- Author     : Mads Richardt
-- Standard   : VHDL-2008
--------------------------------------------------------------------------------
-- Description: Unified bit stuffer for CAN and CAN-FD transmit path.
--              Counts consecutive same-polarity bits, inserts inverse stuff
--              bits at the configurable threshold (stuff_width_c), and
--              maintains a Gray-coded Stuff Bit Count (SBC) with parity.
--              Formal assertions at the end of the architecture provide
--              dual-flow verification (GHDL simulation and SymbiYosys proving).
--------------------------------------------------------------------------------

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
  constant consecutive_count_init_c : integer       := 0;
  constant last_polarity_init_c     : polarity_t    := recessive;
  constant stuff_count_init_c       : stuff_count_t := (others => '0');
  constant stuff_valid_prev_init_c  : boolean       := false;
  constant reset_done_init_c        : boolean       := false;

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

  bit_stuffing_process : process (clk_i) is

    -- Used for stuff_valid edge detection
    variable v_stuff_valid_prev : boolean;
    -- Next output variable
    variable v_bs_o : can_mac_fsm_bs_tx_if_s2m_t;

    ---------------------------------------------------------------------------
    -- Detection of N consecutive bits and drive stuff bit output
    ---------------------------------------------------------------------------
    procedure bit_counting is

      variable v_last_polarity     : polarity_t;
      variable v_consecutive_count : integer range 0 to stuff_width_c;
      variable same_polarity_run_v : boolean;

    begin

      v_consecutive_count := consecutive_count;
      v_last_polarity     := last_polarity;
      same_polarity_run_v := consecutive_count /= stuff_width_c
                             and bs_i.data = last_polarity;

      if (bs_i.valid) then
        if (same_polarity_run_v) then
          -- Same polarity continues: increment count
          v_consecutive_count := consecutive_count + 1;
        else
          -- First bit, stuff bit consumed, or polarity change: restart count
          v_consecutive_count := 1;
          v_last_polarity     := bs_i.data;
        end if;

        -- Check if we reached the stuff threshold
        if (v_consecutive_count >= stuff_width_c) then
          v_bs_o.valid := true;
          v_bs_o.data  := recessive when v_last_polarity = dominant else dominant;
        end if;
      end if;

      -- Update registers
      consecutive_count <= v_consecutive_count;
      last_polarity     <= v_last_polarity;

    end procedure bit_counting;

    ---------------------------------------------------------------------------
    -- Update Gray-coded SBC calculation on stuff bit events
    ---------------------------------------------------------------------------
    procedure sbc_encoding is

      variable gray_bits_v   : std_logic_vector(2 downto 0);
      variable parity_bit_v  : std_logic;
      variable v_stuff_count : stuff_count_t;

    begin

      v_stuff_count := stuff_count;

      -- Detect rising edge of stuff requirement
      if (v_bs_o.valid and not stuff_valid_prev) then
        v_stuff_count := stuff_count + 1;
      end if;

      -- Continuously update Gray-coded SBC output
      gray_bits_v  := to_gray(std_logic_vector(v_stuff_count));
      parity_bit_v := calc_parity(gray_bits_v);
      v_bs_o.sbc   := gray_bits_v & parity_bit_v;

      -- Update register
      stuff_count <= v_stuff_count;

    end procedure sbc_encoding;

  begin

    if rising_edge(clk_i) then
      if (rst_i = '1' or bs_i.start) then
        consecutive_count      <= consecutive_count_init_c;
        consecutive_count_prev <= consecutive_count_init_c;
        stuff_count            <= stuff_count_init_c;
        stuff_count_prev       <= stuff_count_init_c;
        last_polarity          <= last_polarity_init_c;
        stuff_valid_prev       <= stuff_valid_prev_init_c;
        reset_done             <= reset_done_init_c;

        -- Reset interface
        bs_o <= can_mac_fsm_bs_tx_if_s2m_reset_c;
      else
        reset_done <= true;

        -------------------------------------------------------------------
        -- Defaults
        -------------------------------------------------------------------
        v_stuff_valid_prev := bs_o.valid;
        v_bs_o             := bs_o;
        v_bs_o.valid       := false;
        v_bs_o.data        := recessive;

        -------------------------------------------------------------------
        -- Logic evaluation
        -------------------------------------------------------------------
        bit_counting;
        sbc_encoding;

        -------------------------------------------------------------------
        -- Register next-cycle values
        -------------------------------------------------------------------
        stuff_count_prev       <= stuff_count;
        consecutive_count_prev <= consecutive_count;
        stuff_valid_prev       <= v_stuff_valid_prev;
        bs_o                   <= v_bs_o;
      end if;
    end if;

  end process bit_stuffing_process;

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
--------------------------------------------------------------

--------------------------------------------------------------
-- Assertions
--------------------------------------------------------------
-- psl psl_1 : assert always
-- { rst_i = '1' or bs_i.start }
-- |=>
-- { consecutive_count = 0 and
-- last_polarity = recessive and
-- stuff_count = "000" and
-- bs_o.data = recessive and
-- bs_o.sbc = "0000" and
-- not stuff_valid_prev and
-- not bs_o.valid }
-- report "Reset did not clear all registers to default values";
--------------------------------------------------------------
-- psl psl_2 : assert always
-- { reset_done }
-- |->
-- { consecutive_count <= stuff_width_c and
-- bs_o.sbc(0) = ( bs_o.sbc(3) xor bs_o.sbc(2) xor bs_o.sbc(1) ) }
-- report "Invariant violated: count bounded or SBC parity";
--------------------------------------------------------------
-- psl psl_3 : assert always
-- { reset_done and
-- bs_o.valid }
-- |->
-- { consecutive_count = stuff_width_c and
-- bs_o.data /= last_polarity and
-- stuff_count = ( stuff_count_prev + 1 ) }
-- report "Stuff bit invalid: wrong polarity, count, or SBC not incremented";
--------------------------------------------------------------
-- psl psl_4 : assert always
-- { reset_done and
-- rst_i /= '1' and
-- not bs_i.start and
-- bs_i.valid and
-- consecutive_count /= stuff_width_c and
-- bs_i.data = last_polarity }
-- |=>
-- { consecutive_count = (consecutive_count_prev + 1) }
-- report "Consecutive count did not increment on same-polarity input";
--------------------------------------------------------------
-- psl psl_5 : assert always
-- { reset_done and
-- rst_i /= '1' and
-- not bs_i.start and
-- bs_i.valid and
-- bs_i.data /= last_polarity }
-- |=>
-- { consecutive_count = 1 }
-- report "Consecutive count did not reset to 1 on non-same-polarity input";
--------------------------------------------------------------
-- psl psl_6 : assert always
-- { reset_done and
-- not bs_i.valid }
-- |=>
-- { consecutive_count = consecutive_count_prev }
-- report "Consecutive count changed without valid input";
--------------------------------------------------------------
-- psl psl_7 : assert always
-- { reset_done and
-- not bs_o.valid }
-- |->
-- { stuff_count = stuff_count_prev }
-- report "Stuff count changed without stuff bit event";
--------------------------------------------------------------
-- psl psl_8 : assert always
-- { bs_o.valid }
-- |=>
-- { not bs_o.valid }
-- report "Back-to-back stuff events detected";
--------------------------------------------------------------

--------------------------------------------------------------
-- Cover points
--------------------------------------------------------------
-- psl cover_1 : cover { bs_o.valid };
-- psl cover_2 : cover { bs_i.valid and bs_i.data = last_polarity };
-- psl cover_3 : cover { bs_i.valid and bs_i.data /= last_polarity };
-- psl cover_4 : cover { bs_i.start };
-- psl cover_5 : cover { not bs_i.valid and not bs_i.start and rst_i = '0' };
-- psl cover_6 : cover { stuff_count = "111" };
-- psl cover_7 : cover { stuff_count = "000" and reset_done };
--------------------------------------------------------------

end architecture rtl;
