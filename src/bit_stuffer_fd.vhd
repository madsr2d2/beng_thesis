library ieee;
  use ieee.std_logic_1164.all;
  use ieee.numeric_std.all;
  use work.can_types_pkg.all;
  use work.can_protocol_pkg.all;
  use work.can_timing_pkg.all;

--------------------------------------------------------------------------------
-- Title      : CAN FD Bit Stuffer
-- Project    : CAN Bus Transmitter
--------------------------------------------------------------------------------
-- File       : bit_stuffer_fd.vhd
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
  use work.can_timing_pkg.all;

entity bit_stuffer_fd is
  generic (
    stuff_width_c : integer := 5
  );
  port (
    clk_i   : in    std_logic;
    rst_i   : in    std_logic;
    bs_fd_i : in    mac_fsm_to_bs_fd_if_t;
    bs_fd_o : out   bs_fd_to_mac_fsm_if_t
  );
end entity bit_stuffer_fd;

architecture rtl of bit_stuffer_fd is

  ---------------------------------------------------------------------------
  -- Registered signals (driven by state_update)
  ---------------------------------------------------------------------------
  signal consecutive_count : integer range 0 to stuff_width_c;
  signal last_polarity     : polarity_t;
  signal stuff_count       : unsigned(2 downto 0);
  signal stuff_valid_prev  : boolean;

  ---------------------------------------------------------------------------
  -- Combinational next-cycle signals (driven by output_logic)
  ---------------------------------------------------------------------------
  signal next_consecutive_count : integer range 0 to stuff_width_c;
  signal next_last_polarity     : polarity_t;
  signal next_stuff_count       : unsigned(2 downto 0);
  signal next_stuff_valid_prev  : boolean;

  -- Intermediate signals for registered outputs
  signal next_bs_fd_o : bs_fd_to_mac_fsm_if_t;

begin

  ---------------------------------------------------------------------------
  -- Process 1: output_logic
  ---------------------------------------------------------------------------
  output_logic : process (all) is

    -- Named guards
    variable fsm_data_valid_v : boolean;
    variable stuff_required_v : boolean;

    -- Handle detection of N consecutive bits and stuff bit requirement
    procedure manage_bit_counting is
    begin

      if (fsm_data_valid_v) then
        if (stuff_required_v) then
          -- Stuff bit consumed: restart counting with the new bit that follows
          next_consecutive_count <= 1;
          next_last_polarity     <= bs_fd_i.data;
        elsif (consecutive_count = 0) then
          -- First bit of frame
          next_consecutive_count <= 1;
          next_last_polarity     <= bs_fd_i.data;
        elsif (bs_fd_i.data = last_polarity) then
          next_consecutive_count <= consecutive_count + 1;
        else
          -- Polarity change: reset count
          next_consecutive_count <= 1;
          next_last_polarity     <= bs_fd_i.data;
        end if;
      end if;

      -- Current output: check if we reached the stuff threshold
      if (next_consecutive_count >= stuff_width_c) then
        next_bs_fd_o.valid <= true;
        -- Inverse polarity for stuff bit
        if (next_last_polarity = dominant) then
          next_bs_fd_o.data <= recessive;
        else
          next_bs_fd_o.data <= dominant;
        end if;
      end if;

    end procedure manage_bit_counting;

    -- Handle Gray-coded SBC calculation on stuff bit events
    procedure manage_sbc_encoding is

      variable gray_bits_v  : std_logic_vector(2 downto 0);
      variable parity_bit_v : std_logic;

    begin

      -- Pulse logic: detect rising edge of stuff requirement
      if (next_bs_fd_o.valid and not stuff_valid_prev) then
        next_stuff_count <= stuff_count + 1;
      end if;

      -- Continously update Gray-coded SBC output
      gray_bits_v      := to_gray(std_logic_vector(next_stuff_count));
      parity_bit_v     := calc_parity(gray_bits_v);
      next_bs_fd_o.sbc <= gray_bits_v & parity_bit_v;

    end procedure manage_sbc_encoding;

  begin

    -- Evaluate guards
    fsm_data_valid_v := bs_fd_i.valid;
    stuff_required_v := bs_fd_o.valid;

    -------------------------------------------------------------------------
    -- Output defaults: hold current registered values
    -------------------------------------------------------------------------
    next_consecutive_count <= consecutive_count;
    next_last_polarity     <= last_polarity;
    next_stuff_count       <= stuff_count;
    next_stuff_valid_prev  <= bs_fd_o.valid;

    -- Baseline from registered interface
    next_bs_fd_o <= bs_fd_o;

    -- Explicitly clear pulses
    next_bs_fd_o.valid <= false;

    -------------------------------------------------------------------------
    -- Logic evaluation
    -------------------------------------------------------------------------
    manage_bit_counting;
    manage_sbc_encoding;

  end process output_logic;

  ---------------------------------------------------------------------------
  -- Process 2: state_update (clocked)
  ---------------------------------------------------------------------------
  state_update : process (clk_i) is
  begin

    if rising_edge(clk_i) then
      if (rst_i = '1' or bs_fd_i.start) then
        consecutive_count <= 0;
        last_polarity     <= dominant;
        stuff_count       <= (others => '0');
        stuff_valid_prev  <= false;

        bs_fd_o <= bs_fd_to_mac_fsm_if_reset_c;
      else
        consecutive_count <= next_consecutive_count;
        last_polarity     <= next_last_polarity;
        stuff_count       <= next_stuff_count;
        stuff_valid_prev  <= next_stuff_valid_prev;

        bs_fd_o <= next_bs_fd_o;
      end if;
    end if;

  end process state_update;

end architecture rtl;
