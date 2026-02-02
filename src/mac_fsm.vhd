library ieee;
  use ieee.std_logic_1164.all;
  use ieee.numeric_std.all;
  use work.can_package.all;

entity fsm_mac is
  port (
    clk : in    std_logic;
    rst : in    std_logic;

    -- LLC interface (Logical Link Control)
    llc_i : in    llc_to_mac_t;
    llc_o : out   mac_to_llc_t;

    -- PCS interface (Physical Coding Sublayer)
    pcs_i : in    pcs_mac_t;
    pcs_o : out   mac_pcs_t;

    -- BS_FD interface (Bit Stuffer FD)
    bs_fd_i : in    bs_fd_to_mac_fsm_t;
    bs_fd_o : out   mac_fsm_to_bs_fd_t;

    -- CRC interface
    crc_i : in    crc_to_mac_fsm_t;
    crc_o : out   mac_fsm_to_crc_t
  );
end entity fsm_mac;
