---------------------------------------------------------------------------
-- Copyright 2025 Everllence, Teglholmsgade 41, 2450 Copenhagen SV, Denmark
---------------------------------------------------------------------------
--
-- Requirements:
--
-- Description:   Unified bit stuffer/destuffer for CAN and CAN-FD TX/RX path.
--                Two modes selected by bs_i.fsb_en:
--
--                Dynamic mode (fsb_en='0'): counts consecutive same-polarity
--                bits; inserts an inverse stuff bit after c_stuff_width (5)
--                consecutive identical bits; maintains Gray-coded SBC with
--                parity for FD frames.
--
--                Fixed mode (fsb_en='1'): inserts one fixed stuff bit (FSB)
--                immediately on the rising edge of fsb_en, then one FSB after
--                every 4 real bits. Used for the SBC and CRC fields of CAN-FD
--                frames (ISO 11898-1 Sec. 8.5). FSBs are not counted in SBC.
--
-- Revision log:  Date:       Initial:  JIRA:
--                2026-03-15  TMYAES    Initial implementation
--                2026-04-05  MRDSA     Add fsb_en fixed-stuffing mode
--
---------------------------------------------------------------------------

library ieee;
  use ieee.std_logic_1164.all;
  use ieee.numeric_std.all;
  use work.pk_can_types.all;

entity can_mac_bs is
  port (
    clk_i : in    std_logic;
    rst_i : in    std_logic;
    bs_i  : in    t_can_mac_fsm_bs_if_m2s;
    bs_o  : out   t_can_mac_fsm_bs_if_s2m
  );
end entity can_mac_bs;

architecture rtl of can_mac_bs is

  signal count         : natural range 0 to c_stuff_width;
  signal last_polarity : std_logic;
  signal stuff_count   : unsigned(2 downto 0);
  signal fsb_en_latch : std_logic;

begin

  p_bit_stuffing : process (clk_i) is
    variable v_gray : std_logic_vector(2 downto 0);
  begin

    if rising_edge(clk_i) then
      if (rst_i = '1') then
        count         <= 0;
        last_polarity <= c_recessive;
        stuff_count   <= (others => '0');
        fsb_en_latch  <= '0';
        bs_o          <= c_can_mac_fsm_bs_if_s2m_reset;

      else
        fsb_en_latch <= bs_i.fsb_en; -- Latch fsb_en

        if (bs_i.fsb_en = '1' and fsb_en_latch = '0') then -- Rising edge of fsb_en
          -- Emit initial FSB (ISO 6.6.13.3.1).
          -- If a pending dynamic stuff bit exists, suppress it: the FSB
          -- replaces it ("there shall not be two consecutive stuff bits").
          if (bs_i.valid = '1') then
            last_polarity <= bs_i.data;
            bs_o.data     <= not bs_i.data;
          elsif (bs_o.valid = '1') then
            -- Suppress pending dynamic SB: undo stuff_count, recompute SBC
            last_polarity <= bs_o.data;
            bs_o.data     <= not last_polarity;
            stuff_count   <= stuff_count - 1;
            v_gray        := f_to_gray(std_logic_vector(stuff_count - 1));
            bs_o.sbc      <= v_gray & f_calc_parity(v_gray);
          else
            bs_o.data <= not last_polarity;
          end if;
          bs_o.valid <= '1';
          count      <= 0;

        elsif (bs_i.valid = '1') then
          last_polarity <= bs_i.data;
          bs_o.valid    <= '0';

          if (bs_i.fsb_en = '0') then -- Dynamic stuffing mode
            if (bs_i.data /= last_polarity) then -- Reset count on polarity change
              count <= 1;
            elsif (count = c_stuff_width - 1) then -- 5 consecutive same-polarity bits: insert SB
              count       <= 0;
              bs_o.data   <= not last_polarity;
              bs_o.valid  <= '1';
              stuff_count <= stuff_count + 1;
              v_gray      := f_to_gray(std_logic_vector(stuff_count + 1));
              bs_o.sbc    <= v_gray & f_calc_parity(v_gray);
            else
              count <= count + 1;
            end if;

          else -- Fixed stuffing mode
            if (bs_o.valid = '0') then
              if (count = c_stuff_width - 2) then -- 4 real bits: insert FSB
                bs_o.data  <= not bs_i.data;
                bs_o.valid <= '1';
                count      <= 0;
              else
                count <= count + 1;
              end if;
            end if;
          end if;
        end if;
      end if;
    end if;

  end process p_bit_stuffing;

end architecture rtl;
