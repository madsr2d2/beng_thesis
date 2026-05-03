--------------------------------------------------------------------------------------------------------------------------------------------------------------
-- Copyright 2025 Everllence, Teglholmsgade 41, 2450 Copenhagen SV, Denmark
--------------------------------------------------------------------------------------------------------------------------------------------------------------
--
-- Requirements:  
--
-- Description: Unified bit stuffer for CAN/CAN-FD TX and RX paths.
--              Dynamic mode (fsb_en='0'): inserts an inverse stuff bit after
--              c_stuff_width (5) consecutive identical bits.
--              Fixed mode (fsb_en='1'): inserts one FSB on the rising edge of
--              fsb_en, then one FSB every 4 real bits. Maintains Gray-coded
--              SBC with parity. ISO 11898-1 Sec. 8.5.
--
-- Revision log:  Date:       Initial:  JIRA:
--                2026-03-15  TMYAES:   [TRIT-4342] [FPGA] Bit stuffer module for the CAN-FD module
--
--------------------------------------------------------------------------------------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

use work.pk_man_global.all;
use work.pk_can_types.all;

entity can_mac_bs is
  port(
    clk_i : in  std_logic;
    rst_i : in  std_logic;
    bs_i  : in  t_can_mac_fsm_bs_if_m2s;
    bs_o  : out t_can_mac_fsm_bs_if_s2m
  );
end entity can_mac_bs;

architecture rtl of can_mac_bs is
  signal count         : natural range 0 to c_stuff_width;
  signal last_polarity : std_logic;
  signal stuff_count   : unsigned(2 downto 0);
  signal fsb_en_latch  : std_logic;
begin
  p_bit_stuffing : process(clk_i) is
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
        fsb_en_latch <= bs_i.fixed_bit_stuffing_en;

        -- Falling edge of fsb_en cancel any pending FSB
        if (fsb_en_latch = '1') and (bs_i.fixed_bit_stuffing_en = '0') then
          bs_o.valid <= '0';
        end if;

        -- Rising edge of fsb_en: emit the initial FSB
        if (bs_i.fixed_bit_stuffing_en = '1') and (fsb_en_latch = '0') then
          if (bs_i.valid = '1') then
            last_polarity <= bs_i.data;
            bs_o.data     <= not bs_i.data;
            bs_o.valid    <= '1';
            count         <= 0;
          elsif (bs_o.valid = '1') then
            null;
          else
            bs_o.data  <= not last_polarity;
            bs_o.valid <= '1';
            count      <= 0;
          end if;

        elsif (bs_i.valid = '1') then
          last_polarity <= bs_i.data;
          bs_o.valid    <= '0';

          if (bs_i.fixed_bit_stuffing_en = '0') then
            -- Dynamic stuffing: SB after 5 consecutive same-polarity bits.
            if (bs_i.data /= last_polarity) then
              count <= 1;
            elsif count = (c_stuff_width - 1) then
              count                <= 0;
              bs_o.data            <= not last_polarity;
              bs_o.valid           <= '1';
              stuff_count          <= stuff_count + 1;
              v_gray               := f_to_gray(std_logic_vector(stuff_count + 1));
              bs_o.stuff_bit_count <= v_gray & f_calc_parity(v_gray);
            else
              count <= count + 1;
            end if;

          else
            -- Fixed stuffing: one FSB every 4 real bits (ISO 6.6.13.3.1).
            if (bs_o.valid = '0') then
              if count = (c_stuff_width - 2) then
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

-- eof
