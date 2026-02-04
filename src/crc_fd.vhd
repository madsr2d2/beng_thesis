library ieee;
  use ieee.std_logic_1164.all;
  use work.can_pkg.all;

entity crc_fd is
  port (
    crc_i : in    mac_fsm_to_crc_if_t;
    crc_o : out   crc_to_mac_fsm_if_t
  );
end entity crc_fd;

architecture rtl of crc_fd is

begin

-- TODO: Implement CRC calculation logic

end architecture rtl;
