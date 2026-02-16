library ieee;
  use ieee.std_logic_1164.all;
  use work.can_types_pkg.all;
  use work.can_protocol_pkg.all;
  use work.can_timing_pkg.all;

entity bit_stuffer is
  port (
    clk : in    std_logic;
    rst : in    std_logic;

    -- Input data stream
    data_i  : in    polarity_t;
    valid_i : in    boolean;

    -- Stuff bit indication (combinational, level-based)
    stuff_bit_o       : out   polarity_t;
    stuff_bit_valid_o : out   boolean
  );
end entity bit_stuffer;

architecture rtl of bit_stuffer is

  signal consecutive_count : integer range 0 to 5;
  signal last_polarity_reg : polarity_t;

begin

  -- Combinational outputs: signal stuff bit needed when 5 consecutive detected
  -- Level-based: stays high until the stuff bit is consumed (valid_i with count=5)
  stuff_bit_valid_o <= true when consecutive_count >= 5 else
                       false;
  stuff_bit_o       <= dominant when last_polarity_reg = recessive else
                       recessive;

  p_count : process (clk) is
  begin

    if rising_edge(clk) then
      if (rst = '1') then
        consecutive_count <= 0;
        last_polarity_reg <= dominant;
      elsif (valid_i = true) then
        if (consecutive_count >= 5) then
          -- Stuff bit consumed: restart counting with new bit
          consecutive_count <= 1;
          last_polarity_reg <= data_i;
        elsif (consecutive_count = 0) then
          -- First bit after reset
          consecutive_count <= 1;
          last_polarity_reg <= data_i;
        elsif (data_i = last_polarity_reg) then
          consecutive_count <= consecutive_count + 1;
        else
          consecutive_count <= 1;
          last_polarity_reg <= data_i;
        end if;
      end if;
    end if;

  end process p_count;

end architecture rtl;
