library ieee;
  use ieee.std_logic_1164.all;
  use work.can_types_pkg.all;
  use work.can_protocol_pkg.all;
  use work.can_timing_pkg.all;

entity crc_fd is
  port (
    crc_i : in    mac_fsm_to_crc_if_t;
    crc_o : out   crc_to_mac_fsm_if_t
  );
end entity crc_fd;

architecture rtl of crc_fd is

begin

  -- Temporary wrapper placeholder:
  -- output deterministic, selectable fixed sequences so integration/debug
  -- can validate CRC-type selection and fixed-stuff behavior without the
  -- collaborator CRC cores wired in yet.
  crc_placeholder_p : process (all) is
    variable crc_v : crc_vector_t;
  begin
    crc_v := (others => '0');
    case crc_i.crc_poly_select is
      when "00" => -- CRC-15 mode
        crc_v(crc_v'left downto crc_v'left - crc_poly_15_vec_c'length + 1) := crc_poly_15_vec_c;
      when "01" => -- CRC-17 mode
        crc_v(crc_v'left downto crc_v'left - crc_poly_17_vec_c'length + 1) := crc_poly_17_vec_c;
      when "10" => -- CRC-21 mode
        crc_v := crc_poly_21_vec_c;
      when others =>
        null;
    end case;
    crc_o.crc <= crc_v;
  end process crc_placeholder_p;

end architecture rtl;
