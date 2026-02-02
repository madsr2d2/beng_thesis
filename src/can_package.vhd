library ieee;
  use ieee.std_logic_1164.all;
  use ieee.numeric_std.all;

package can_package is

  -- =========================================================================
  -- LLC (Logical Link Control) Interface
  -- =========================================================================

  type llc_to_mac_t is record
    data  : std_logic_vector(7 downto 0);
    valid : std_logic;
    sop   : std_logic;
    eop   : std_logic;
  end record llc_to_mac_t;

  type mac_to_llc_t is record
    valid  : std_logic;
    ready  : std_logic;
    status : std_logic_vector(2 downto 0);
  end record mac_to_llc_t;

  -- =========================================================================
  -- PCS (Physical Coding Sublayer) Interface
  -- =========================================================================

  type mac_pcs_t is record
    mac_frame_bit   : std_logic;
    mac_frame_valid : std_logic;
    transmit_status : std_logic;
    receive_status  : std_logic;
  end record mac_pcs_t;

  type pcs_mac_t is record
    mac_frame_bit   : std_logic;
    mac_frame_valid : std_logic;
  end record pcs_mac_t;

  -- =========================================================================
  -- Bit Stuffer FD Interface
  -- =========================================================================

  type mac_fsm_to_bs_fd_t is record
    clk        : std_logic;
    rst        : std_logic;
    data       : std_logic;
    data_valid : std_logic;
  end record mac_fsm_to_bs_fd_t;

  type bs_fd_to_mac_fsm_t is record
    stuff_bit       : std_logic;
    stuff_bit_valid : std_logic;
    sbc             : std_logic_vector(3 downto 0);
  end record bs_fd_to_mac_fsm_t;

  -- =========================================================================
  -- CRC Interface
  -- =========================================================================

  type mac_fsm_to_crc_t is record
    clk             : std_logic;
    rst             : std_logic;
    crc_poly_select : std_logic_vector(1 downto 0);
    shift           : std_logic;
    data            : std_logic;
  end record mac_fsm_to_crc_t;

  type crc_to_mac_fsm_t is record
    data       : std_logic;
    data_valid : std_logic;
  end record crc_to_mac_fsm_t;

end package can_package;
