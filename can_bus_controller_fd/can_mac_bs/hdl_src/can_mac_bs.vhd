---------------------------------------------------------------------------
-- Copyright 2025 Everllence, Teglholmsgade 41, 2450 Copenhagen SV, Denmark
---------------------------------------------------------------------------
--
-- Requirements:
--
-- Description:   Unified bit stuffer for CAN and CAN-FD TX path.
--                Counts consecutive same-polarity bits, inserts inverse stuff
--                bits at the configurable threshold (c_stuff_width), and
--                maintains a Gray-coded Stuff Bit Count (SBC) with parity.
--
-- Revision log:  Date:       Initial:  JIRA:
--                2026-03-15  TMYAES:   [TRIT-4338] Initial implementation
--                2026-03-20  TMYAES:   [TRIT-4342] Updated JIRA ID
---------------------------------------------------------------------------

library ieee;
  use ieee.std_logic_1164.all;
  use ieee.numeric_std.all;

  use work.pk_man_global.all;
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
  signal fsb_en_latch  : std_logic;
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
        fsb_en_latch <= bs_i.fsb_en; -- latch used to detect the rising edge

        -----------------------------------------------------------------
        -- Rising edge of fsb_en: emit initial FSB
        -----------------------------------------------------------------
        if (bs_i.fsb_en and  not fsb_en_latch) then
          if (bs_i.valid = '1') then
            last_polarity <= bs_i.data;
            bs_o.data     <= not bs_i.data;
          elsif (bs_o.valid = '1') then
            -----------------------------------------------------------------
            -- ISO 6.6.13.3.1: pending dynamic SB at fsb_en boundary is suppressed
            -----------------------------------------------------------------
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

          if (bs_i.fsb_en = '0') then
            -----------------------------------------------------------------
            -- Dynamic stuffing: stuff bit after 5 consecutive same-polarity
            -----------------------------------------------------------------
            if (bs_i.data /= last_polarity) then
              count <= 1;
            elsif count = (c_stuff_width - 1) then
              count       <= 0;
              bs_o.data   <= not last_polarity;
              bs_o.valid  <= '1';
              stuff_count <= stuff_count + 1;
              v_gray      := f_to_gray(std_logic_vector(stuff_count + 1));
              bs_o.sbc    <= v_gray & f_calc_parity(v_gray);
            else
              count <= count + 1;
            end if;

          else
            -----------------------------------------------------------------
            -- Fixed stuffing: 1 FSB every 4 real bits (ISO 6.6.13.3.1)
            -----------------------------------------------------------------
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
