--------------------------------------------------------------------------------------------------------------------------------------------------------------
-- Copyright 2025 Everllence, Teglholmsgade 41, 2450 Copenhagen SV, Denmark
--------------------------------------------------------------------------------------------------------------------------------------------------------------
--
-- Requirements:  
--
-- Description:   CAN node clock. Generates the rx sample pulse (sample_rx_o) and and transmit bit pulse (transmit_o) and handles the resynchronization.
--                
--                Synchronization is only kept for 1 bit at a time, and not for the rest of the message.
--                
--                Please see http://www.oertel-halle.de/files/cia99paper.pdf for more information
--
-- Revision log:  Date:       Initial:  JIRA:
--                2025-04-24  TMYAES:   [TRIT-3880] [FPGA] CAN-bus controller 
--                2025-08-08  AFNI:     [TRIT-4042] [FPGA] Integrate can-bus controller into the io_ext
--
--------------------------------------------------------------------------------------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

use work.pk_man_global.all;
use work.pk_can_bus_controller.all;

entity can_node_clock is
  generic(
    gc_bit_rate_hz                : integer range 250_000 to 500_000                                         := c_alint_default_bit_rate_hz; -- Desired baud rate in kbps
    gc_default_prop_seg_length    : integer range c_min_phase_prop_seg_length to c_max_phase_prop_seg_length := c_alint_default_prop_seg_length;
    gc_default_phase_seg_1_length : integer range c_min_phase_seg1_length to c_max_phase_seg1_length         := c_alint_default_phase_seg1_length;
    gc_default_phase_seg_2_length : integer range c_min_phase_seg2_length to c_max_phase_seg2_length         := c_alint_default_phase_seg2_length;
    gc_sync_jump_width            : integer range 1 to 4                                                     := c_alint_sync_jump_width
  );
  port(
    clk_i       : in  std_logic;
    reset_i     : in  std_logic;
    rx_i        : in  std_logic;                                                -- RX signal from CAN bus
    sample_rx_o : out std_logic;                                                -- RX sample pulse
    transmit_o  : out std_logic                                                 -- Transmit signal to CAN bus (not used in this module)
  );
end entity;

architecture rtl of can_node_clock is
  ---------------------------------------------------------------------------
  -- Constants
  ---------------------------------------------------------------------------
  type t_segment is (s_hard_sync, s_sync, s_seg_1, s_seg_2);


  constant c_nominal_time_quanta_per_bit : integer := c_sync_seg_length + gc_default_prop_seg_length + gc_default_phase_seg_1_length + gc_default_phase_seg_2_length;

  constant c_bit_period        : time    := 1 sec / gc_bit_rate_hz;
  constant c_bit_quanta        : time    := c_bit_period / c_nominal_time_quanta_per_bit;
  constant c_bit_quanta_cycles : integer := c_bit_quanta / (c_clock_period_ns * 1 ns);

  ----------------------------------------------------------------------------
  -- Signals
  ----------------------------------------------------------------------------
  signal segment : t_segment;

  signal time_quantum_count : integer range 0 to c_max_time_quanta_per_bit;
  signal phase_seg1_length  : integer range c_min_phase_seg1_length to c_max_phase_seg1_length;
  signal phase_seg2_length  : integer range c_min_phase_seg2_length to c_max_phase_seg2_length;
  signal clk_div_counter    : integer range 1 to c_bit_quanta_cycles;
  signal rx_prev            : std_logic;

begin
  assert (c_bit_quanta_cycles * (c_clock_period_ns * 1 ns)) = c_bit_quanta report "c_bit_quanta_cycles is not a multiple of the clock cycles" severity failure;

  ----------------------------------------------------------------------------
  -- This process generates the rx_sample pulse. Hard synchronization is performed 
  -- on the first recessive to dominant edge detected after reset = '0'.
  --
  -- Re-synchronization process. When a receive to dominant edge is detected
  -- outside the sync segment, the phase segment lengths are adjusted to keep 
  -- the sample point in the desired position. (ISO 11898-1:2024, Sec.: 7.3.5)
  ----------------------------------------------------------------------------
  p_rx_sample_pulse_gen : process(clk_i)
    variable v_phase_error       : integer range 0 to c_max_time_quanta_per_bit;
    variable v_phase_seg1_length : integer range c_min_phase_seg1_length to c_max_phase_seg1_length + gc_sync_jump_width + gc_default_prop_seg_length;
    variable v_phase_seg2_length : integer range c_min_phase_seg2_length - gc_sync_jump_width to c_max_phase_seg2_length;
  begin
    if rising_edge(clk_i) then
      if reset_i = '1' then
        time_quantum_count <= 0;
        clk_div_counter    <= 1;
        rx_prev            <= '1';
        sample_rx_o        <= '0';
        transmit_o         <= '0';                                              -- Transmit signal is not used in this module
        phase_seg1_length  <= gc_default_phase_seg_1_length;
        phase_seg2_length  <= gc_default_phase_seg_2_length;
        segment            <= s_hard_sync;
      else
        -- Default value
        sample_rx_o <= '0';
        transmit_o  <= '0';                                                     -- Transmit signal is not used in this module

        -- Bit time counter.
        if (clk_div_counter = c_bit_quanta_cycles) then
          clk_div_counter <= 1;
          rx_prev         <= rx_i;                                              -- for this module we are sampling rx at every end of a bit time.
        else
          clk_div_counter <= clk_div_counter + 1;
        end if;

        case segment is

          ----------------------------------------------------------------------------  
          -- Hard sync Sync to the first failing edge.
          ----------------------------------------------------------------------------  
          when s_hard_sync =>
            if (rx_i = '0') and (rx_prev = '1') then                            -- Detect edge
              rx_prev            <= rx_i;
              clk_div_counter    <= 1;
              segment            <= s_seg_1;
              time_quantum_count <= 0;

            elsif (clk_div_counter = c_bit_quanta_cycles) then
              time_quantum_count <= time_quantum_count + 1;
              if time_quantum_count = (gc_default_prop_seg_length + gc_default_phase_seg_1_length) then
                sample_rx_o <= '1';
              elsif time_quantum_count = (gc_default_prop_seg_length + gc_default_phase_seg_1_length + gc_default_phase_seg_2_length) then
                transmit_o         <= '1';                                      -- Transmit signal is not used in this module
                time_quantum_count <= 0;
              end if;
            end if;

          ----------------------------------------------------------------------------  
          -- Sync segment, is rather simple as we just need to do nothing for 1 bit time
          ----------------------------------------------------------------------------  
          when s_sync =>
            if (clk_div_counter = c_bit_quanta_cycles) then
              segment <= s_seg_1;
            end if;

          ----------------------------------------------------------------------------  
          -- Propagation segment and segment 1.
          -- They are combined as they have the logic, as 
          ----------------------------------------------------------------------------  
          when s_seg_1 =>
            if (clk_div_counter = c_bit_quanta_cycles) then
              v_phase_seg1_length := phase_seg1_length;                         -- Default to handle the synchronization

              if (rx_i = '0') and (rx_prev = '1') then
                v_phase_error := time_quantum_count + 1;
                if v_phase_error >= gc_sync_jump_width then                     -- greater or equal to it to easier hit the statements.
                  v_phase_error := gc_sync_jump_width;
                end if;
                -- Compute new phase length
                v_phase_seg1_length := phase_seg1_length + v_phase_error;

                -- Cap phase_seg length (ISO 11898-1:2024, Sec.: 7.3.3, Table 11)
                if v_phase_seg1_length >= c_max_phase_seg1_length then
                  phase_seg1_length <= c_max_phase_seg1_length;
                else
                  phase_seg1_length <= v_phase_seg1_length;
                end if;
              end if;

              time_quantum_count  <= time_quantum_count + 1;
              v_phase_seg1_length := (gc_default_prop_seg_length + v_phase_seg1_length) - 1; -- Uses the variable to compare where we are in time.
              if time_quantum_count = v_phase_seg1_length then
                time_quantum_count <= 0;
                sample_rx_o        <= '1';
                segment            <= s_seg_2;
                phase_seg1_length  <= gc_default_phase_seg_1_length;
              end if;
            end if;

          ----------------------------------------------------------------------------  
          -- Segment 2.
          -- If the falling edge is detected here, it will check if the phase error
          -- is over the sync jump width or not, if it was over the SJW, it will save
          -- the value and wait for the end.
          -- If it was under it will simply jump back to segment 1.
          -- It will then skip the sync stage if synchronisation happens here.
          ----------------------------------------------------------------------------  
          when s_seg_2 =>
            if (clk_div_counter = c_bit_quanta_cycles) then
              v_phase_seg2_length := phase_seg2_length;                         -- Default to handle the synchronization

              if (rx_i = '0') and (rx_prev = '1') then
                v_phase_error := (phase_seg2_length - time_quantum_count);
                if v_phase_error >= gc_sync_jump_width then                     -- greater or equal to it to easier hit the statements.
                  v_phase_error := gc_sync_jump_width;
                end if;
                -- Compute new phase length
                v_phase_seg2_length := phase_seg2_length - v_phase_error;

                -- Cap phase_seg length (ISO 11898-1:2024, Sec.: 7.3.3, Table 11)
                if v_phase_seg2_length <= c_min_phase_seg2_length then
                  phase_seg2_length <= c_min_phase_seg2_length;
                else
                  phase_seg2_length <= v_phase_seg2_length;
                end if;
              end if;

              time_quantum_count  <= time_quantum_count + 1;
              v_phase_seg2_length := v_phase_seg2_length - 1;                   -- Uses the variable to compare where we are in time.
              if time_quantum_count >= v_phase_seg2_length then
                segment            <= s_sync;
                transmit_o         <= '1';
                time_quantum_count <= 0;
                phase_seg2_length  <= gc_default_phase_seg_2_length;
                -- it skips the sync stage, if the second segment was shorten.
                if (v_phase_seg2_length /= (gc_default_phase_seg_2_length - 1)) then
                  segment <= s_seg_1;
                end if;
              end if;
            end if;

          --coverage off
          when others =>
            segment <= s_hard_sync;
            --coverage on
        end case;

      end if;
    end if;
  end process;

end architecture;

-- eof
