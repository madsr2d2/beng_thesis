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
    clk_i : in    std_logic;
    rst_i : in    std_logic;
    bs_i  : in    can_mac_fsm_bs_tx_if_m2s_t;
    bs_o  : out   can_mac_fsm_bs_tx_if_s2m_t
  );
end entity can_mac_bs_tx;

architecture rtl of can_mac_bs_tx is

  ---------------------------------------------------------------------------
  -- Registered state signals
  ---------------------------------------------------------------------------
  signal consecutive_count : integer range 0 to stuff_width_c;
  signal last_polarity     : polarity_t;
  signal stuff_count       : unsigned(2 downto 0);
  signal stuff_valid_prev  : boolean;
  signal reset_done        : boolean; -- Formal-only: true one cycle after reset deasserts

begin

  bit_stuffing_process : process (clk_i) is

    -- Used for stuff_valid edge detection
    variable v_stuff_valid_prev : boolean;
    -- Next output variable
    variable v_bs_o : can_mac_fsm_bs_tx_if_s2m_t;

    ---------------------------------------------------------------------------
    -- Detection of N consecutive bits and drive stuff bit output
    ---------------------------------------------------------------------------
    procedure manage_bit_counting is

      variable v_last_polarity     : polarity_t;
      variable v_consecutive_count : integer range 0 to stuff_width_c;
      variable same_polarity_run_v : boolean;

    begin

      v_consecutive_count := consecutive_count;
      v_last_polarity     := last_polarity;
      same_polarity_run_v := consecutive_count /= stuff_width_c
                             and consecutive_count /= 0
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

    end procedure manage_bit_counting;

    ---------------------------------------------------------------------------
    -- Update Gray-coded SBC calculation on stuff bit events
    ---------------------------------------------------------------------------
    procedure manage_sbc_encoding is

      variable gray_bits_v   : std_logic_vector(2 downto 0);
      variable parity_bit_v  : std_logic;
      variable v_stuff_count : unsigned(2 downto 0);

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

    end procedure manage_sbc_encoding;

  begin

    if rising_edge(clk_i) then
      if (rst_i = '1' or bs_i.start) then
        consecutive_count <= 0;
        last_polarity     <= recessive;
        stuff_count       <= (others => '0');
        stuff_valid_prev  <= false;
        reset_done        <= false;

        -- Reset interface
        bs_o <= can_mac_fsm_bs_tx_if_s2m_reset_c;
      else
        reset_done <= true;
        -------------------------------------------------------------------
        -- Defaults: hold current registered values
        -------------------------------------------------------------------
        v_stuff_valid_prev := bs_o.valid;
        v_bs_o             := bs_o;
        -- Clear pulses
        v_bs_o.valid := false;

        -------------------------------------------------------------------
        -- Logic evaluation
        -------------------------------------------------------------------
        manage_bit_counting;
        manage_sbc_encoding;

        -------------------------------------------------------------------
        -- Register next-cycle values
        -------------------------------------------------------------------
        stuff_valid_prev  <= v_stuff_valid_prev;
        bs_o              <= v_bs_o;
      end if;
    end if;

  end process bit_stuffing_process;

-- psl default clock is rising_edge(clk_i);

-- Environment assumptions
-- psl assume_no_unknown_data  : assume always (bs_i.data = dominant or bs_i.data = recessive);
-- psl assume_reset_init       : assume {rst_i = '1'};
-- psl assume_reset_done_init  : assume {not reset_done};

-- Check reset on rst_i and bs_i.start
-- psl reset_behavior : assert always {rst_i = '1' or bs_i.start} |=> {consecutive_count = 0 and last_polarity = recessive and stuff_count = "000" and not stuff_valid_prev and not bs_o.valid and bs_o.data = recessive and bs_o.sbc = "0000"};

-- #REQ-MAC-063:
-- psl req_mac_063_count_bounded : assert always (reset_done -> (consecutive_count <= stuff_width_c));
-- psl req_mac_063_stuff_pol_dominant  : assert always ((reset_done and bs_o.valid and last_polarity = dominant)  -> bs_o.data = recessive);
-- psl req_mac_063_stuff_pol_recessive : assert always ((reset_done and bs_o.valid and last_polarity = recessive) -> bs_o.data = dominant);
-- psl req_mac_063_valid_only_at_threshold : assert always ((reset_done and bs_o.valid) -> consecutive_count = stuff_width_c);

-- psl req_mac_063_inc_on_same_pol : assert always {reset_done and rst_i = '0' and not bs_i.start and bs_i.valid and consecutive_count /= stuff_width_c and consecutive_count /= 0 and bs_i.data = last_polarity} |=> {consecutive_count = prev(consecutive_count) + 1};
-- psl req_mac_063_rst_on_pol_change : assert always {reset_done and rst_i = '0' and not bs_i.start and bs_i.valid and not (consecutive_count /= stuff_width_c and consecutive_count /= 0 and bs_i.data = last_polarity)} |=> {consecutive_count = 1};
-- psl req_mac_063_hold_no_input : assert always {reset_done and rst_i = '0' and not bs_i.start and not bs_i.valid} |=> {consecutive_count = prev(consecutive_count)};

-- #REQ-MAC-056:
-- psl req_mac_056_sbc_parity_correct : assert always (reset_done -> (bs_o.sbc(0) = (bs_o.sbc(3) xor bs_o.sbc(2) xor bs_o.sbc(1))));
-- psl req_mac_056_sbc_inc_on_stuff : assert always (reset_done and bs_o.valid and not stuff_valid_prev -> stuff_count = prev(stuff_count) + 1);
-- psl req_mac_056_sbc_hold_no_stuff : assert always (reset_done and not (bs_o.valid and not stuff_valid_prev) -> stuff_count = prev(stuff_count));

end architecture rtl;
