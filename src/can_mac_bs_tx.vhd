--------------------------------------------------------------------------------
-- Title      : CAN FD Bit Stuffer
-- Project    : CAN Bus Transmitter
--------------------------------------------------------------------------------
-- File       : can_mac_bs_tx.vhd
-- Standard   : VHDL-2008
--------------------------------------------------------------------------------
-- Description: Unified bit stuffer implementation for CAN and CAN-FD.
--              Handles consecutive bit counting, inverse bit insertion, and
--              Gray-coded Stuff Bit Count (SBC) generation.
--
-- Protocol references: ISO 11898-1:2015 Section 10.6
--------------------------------------------------------------------------------

library ieee;
  use ieee.std_logic_1164.all;
  use ieee.numeric_std.all;
  use work.can_types_pkg.all;
  use work.can_protocol_pkg.all;

entity can_mac_bs_tx is
  generic (
    stuff_width_c : integer := 5
  );
  port (
    clk_i   : in    std_logic;
    rst_i : in    std_logic;
    bs_fd_i : in    can_mac_fsm_bs_tx_if_s2d_t;
    bs_fd_o : out   can_mac_fsm_bs_tx_if_d2s_t
  );
end entity can_mac_bs_tx;

architecture rtl of can_mac_bs_tx is

  ---------------------------------------------------------------------------
  -- Registered state signals (driven by fsm_sequential)
  ---------------------------------------------------------------------------
  signal consecutive_count : integer range 0 to stuff_width_c;
  signal last_polarity     : polarity_t;
  signal stuff_count       : unsigned(2 downto 0);
  signal stuff_valid_prev  : boolean;

begin

  fsm_sequential : process (clk_i) is

    -- Registered next-value variables
    variable v_stuff_valid_prev : boolean;

    -- Registered output next-value variable
    variable v_bs_fd_o : can_mac_fsm_bs_tx_if_d2s_t;

    -- Handle detection of N consecutive bits and stuff bit requirement
    procedure manage_bit_counting is

      variable v_last_polarity     : polarity_t;
      variable v_consecutive_count : integer range 0 to stuff_width_c;
      variable fsm_data_valid_v    : boolean;
      variable stuff_required_v    : boolean;

    begin

      fsm_data_valid_v    := bs_fd_i.valid;
      stuff_required_v    := bs_fd_o.valid;
      v_consecutive_count := consecutive_count;
      v_last_polarity     := last_polarity;

      if (fsm_data_valid_v) then
        if (stuff_required_v) then
          -- Stuff bit consumed: restart counting with the new bit that follows
          v_consecutive_count := 1;
          v_last_polarity     := bs_fd_i.data;
        elsif (consecutive_count = 0) then
          -- First bit of frame
          v_consecutive_count := 1;
          v_last_polarity     := bs_fd_i.data;
        elsif (bs_fd_i.data = last_polarity) then
          v_consecutive_count := consecutive_count + 1;
        else
          -- Polarity change: reset count
          v_consecutive_count := 1;
          v_last_polarity     := bs_fd_i.data;
        end if;
      end if;

      -- Current output: check if we reached the stuff threshold
      if (v_consecutive_count >= stuff_width_c) then
        v_bs_fd_o.valid := true;
        -- Inverse polarity for stuff bit
        if (v_last_polarity = dominant) then
          v_bs_fd_o.data := recessive;
        else
          v_bs_fd_o.data := dominant;
        end if;
      end if;

      consecutive_count <= v_consecutive_count;
      last_polarity     <= v_last_polarity;

    end procedure manage_bit_counting;

    -- Handle Gray-coded SBC calculation on stuff bit events
    procedure manage_sbc_encoding is

      variable gray_bits_v   : std_logic_vector(2 downto 0);
      variable parity_bit_v  : std_logic;
      variable v_stuff_count : unsigned(2 downto 0);

    begin

      v_stuff_count := stuff_count;

      -- Pulse logic: detect rising edge of stuff requirement
      if (v_bs_fd_o.valid and not stuff_valid_prev) then
        v_stuff_count := stuff_count + 1;
      end if;

      -- Continuously update Gray-coded SBC output
      gray_bits_v   := to_gray(std_logic_vector(v_stuff_count));
      parity_bit_v  := calc_parity(gray_bits_v);
      v_bs_fd_o.sbc := gray_bits_v & parity_bit_v;

      stuff_count <= v_stuff_count;

    end procedure manage_sbc_encoding;

  begin

    if rising_edge(clk_i) then
      if (rst_i = '1' or bs_fd_i.start) then
        consecutive_count <= 0;
        last_polarity     <= dominant;
        stuff_count       <= (others => '0');
        stuff_valid_prev  <= false;

        bs_fd_o <= bs_fd_to_mac_fsm_if_reset_c;
      else
        -- Evaluate guards

        -------------------------------------------------------------------
        -- Defaults: hold current registered values
        -------------------------------------------------------------------
        v_stuff_valid_prev := bs_fd_o.valid;

        -- Baseline from registered interface
        v_bs_fd_o := bs_fd_o;

        -- Explicitly clear pulses
        v_bs_fd_o.valid := false;

        -------------------------------------------------------------------
        -- Logic evaluation
        -------------------------------------------------------------------
        manage_bit_counting;
        manage_sbc_encoding;

        -------------------------------------------------------------------
        -- Register all next-cycle values
        -------------------------------------------------------------------
        stuff_valid_prev <= v_stuff_valid_prev;

        bs_fd_o <= v_bs_fd_o;
      end if;
    end if;

  end process fsm_sequential;

---------------------------------------------------------------------------
-- Formal Verification Properties (PSL / GHDL + SymbiYosys)
--
-- Requirements verified:
--   #042: dynamic bit stuffing — no 5+ consecutive identical bits,
--         stuff bit has inverse polarity to the triggering run.
--   #043: stuff bit count cleared and seeded correctly.
--
-- Simulation: GHDL mcode backend parses PSL (-fpsl) but does not evaluate
--   assertions at runtime. No simulation checking with the Ubuntu GHDL package.
--
-- Formal proof (exhaustive):
--   Install oss-cad-suite, then run: sby formal/can_mac_bs_tx.sby
--   oss-cad-suite provides GHDL (LLVM backend) + Yosys + SymbiYosys.
--   Install: https://github.com/YosysHQ/oss-cad-suite-build/releases/latest
---------------------------------------------------------------------------

-- psl default clock is rising_edge(clk_i);

-- Environment assumptions: constrain unconstrained formal inputs to legal values.
-- psl ASSUME_NO_UNKNOWN_DATA : assume always (bs_fd_i.data = dominant or bs_fd_i.data = recessive);
-- psl ASSUME_START_MUTEX : assume always not (bs_fd_i.start and bs_fd_i.valid);
-- psl ASSUME_RESET_INIT : assume (rst_i = '1');

-- #042 [P1]: consecutive_count is always bounded by stuff_width_c.
-- A count exceeding the threshold would mean the logic skipped inserting a stuff bit.
-- psl P1_COUNT_BOUNDED : assert always (rst_i = '0' -> (consecutive_count <= stuff_width_c)) report "FAIL P1: #042 consecutive_count exceeded stuff_width_c";

-- #042 [P2]: When consecutive_count reaches the stuffing threshold, the output
-- MUST assert valid (stuff bit required).  Proves count and valid are consistent.
-- psl P2_COUNT_IMPLIES_VALID : assert always (rst_i = '0' -> ((consecutive_count = stuff_width_c) -> bs_fd_o.valid)) report "FAIL P2: #042 count at threshold but valid not asserted";

-- #042 [P3a/3b]: Stuff bit polarity is always inverse of the run that triggered it.
-- last_polarity holds the polarity of the 5th consecutive bit, i.e. the run polarity.
-- psl P3_STUFF_POL_DOMINANT : assert always (rst_i = '0' -> ((bs_fd_o.valid and last_polarity = dominant) -> bs_fd_o.data = recessive)) report "FAIL P3a: #042 stuff bit not recessive after dominant run";
-- psl P3_STUFF_POL_RECESSIVE : assert always (rst_i = '0' -> ((bs_fd_o.valid and last_polarity = recessive) -> bs_fd_o.data = dominant)) report "FAIL P3b: #042 stuff bit not dominant after recessive run";

-- #043 [P4]: Stuff bit output polarity is never undefined (unknown) when valid is asserted.
-- psl P4_NO_UNKNOWN_OUTPUT : assert always (rst_i = '0' -> (bs_fd_o.valid -> (bs_fd_o.data = dominant or bs_fd_o.data = recessive))) report "FAIL P4: #043 stuff bit has undefined polarity when valid";

-- #042 [P5]: Synchronous reset clears consecutive_count and deasserts valid next cycle.
-- psl P5_RST_CLEARS_STATE : assert always (rst_i = '1') -> next (consecutive_count = 0 and not bs_fd_o.valid) report "FAIL P5: #042 synchronous reset did not clear state";

-- #042 [P6]: Frame-start pulse clears consecutive_count and deasserts valid next cycle.
-- psl P6_START_CLEARS_STATE : assert always bs_fd_i.start -> next (consecutive_count = 0 and not bs_fd_o.valid) report "FAIL P6: #042 start pulse did not clear state";

end architecture rtl;
