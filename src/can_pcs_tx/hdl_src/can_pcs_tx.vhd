--------------------------------------------------------------------------------------------------------------------------------------------------------------
-- Copyright 2026 Everllence, Teglholmsgade 41, 2450 Copenhagen SV, Denmark
--------------------------------------------------------------------------------------------------------------------------------------------------------------
--
-- Requirements:
--
-- Description:   Physical Signaling layer implementing bit timing, transmission,
--                and Transmitter Delay Compensation (TDC) per ISO 11898-1:2015
--                Section 7.2 (PCS Services) and 7.3.4 (TDC).
--                Responsibilities:
--                - Bit timing generation (nominal and data bit rates)
--                - Serial bit transmission to bus
--                - TDC delay measurement (triggered by MAC via start_tdc pulse)
--                - Sample Point (SP) and Secondary Sample Point (SSP) generation
--                - Bus monitoring (RX input for loopback and delay measurement)
--                Interface:
--                MAC tells PCS what to do via level signals, stable before each
--                bit boundary and sampled by PCS at the start of each bit time:
--                polarity      - bit value to transmit
--                valid         - frame active (high during entire frame)
--                use_data_rate - high during data bit rate phase
--                start_tdc     - high during FDF bit (triggers TDC measurement)
--                FSM State Transitions:
--                idle -> transmitting                     (valid = '1')
--                transmitting: nominal or data rate       (use_data_rate selects)
--                transmitting -> measuring_delay          (start_tdc = '1')
--                any non-idle -> idle                     (valid = '0')
--
-- Revision log:  Date:       Initial:  JIRA:
--                2026-03-31  MRDSA     Converted to company header format
--                2026-04-14  MRDSA     Refactored procedures to synchronised processes
--                2026-04-14  MRDSA     SSP blanking per ISO 7.3.4, inlined TDC calc
--------------------------------------------------------------------------------------------------------------------------------------------------------------

library ieee;
  use ieee.std_logic_1164.all;
  use ieee.numeric_std.all;
  use work.pk_can_types.all;

entity can_pcs_tx is
  generic (
    gc_prescaler       : t_prescaler          := t_prescaler'high / 2;
    gc_nom_sync_seg    : natural              := c_sync_seg;
    gc_nom_prop_seg    : t_nominal_prop_seg   := t_nominal_prop_seg'high / 2;
    gc_nom_phase_seg1  : t_nominal_phase_seg1 := t_nominal_phase_seg1'high / 2;
    gc_nom_phase_seg2  : t_nominal_phase_seg2 := t_nominal_phase_seg2'high / 2;
    gc_data_sync_seg   : natural              := c_sync_seg;
    gc_data_prop_seg   : t_data_prop_seg      := t_data_prop_seg'high / 2;
    gc_data_phase_seg1 : t_data_phase_seg1    := t_data_phase_seg1'high / 2;
    gc_data_phase_seg2 : t_data_phase_seg2    := t_data_phase_seg2'high / 2;
    gc_tdc_enable      : std_logic            := '1'
  );
  port (
    clk_i : in    std_logic;
    rst_i : in    std_logic;
    ---
    mac_to_pcs_i : in    t_can_mac_pcs_if_m2s;
    pcs_to_mac_o : out   t_can_mac_pcs_if_s2m;
    ---
    tx_bus_o : out   std_logic;
    rx_bus_i : in    std_logic
  );
end entity can_pcs_tx;

architecture rtl of can_pcs_tx is

  ---------------------------------------------------------------------------
  -- Types
  ---------------------------------------------------------------------------
  type t_state is (s_nominal, s_measuring, s_data);

  ---------------------------------------------------------------------------
  -- Constants
  ---------------------------------------------------------------------------
  -- Bit timing constants
  constant c_nom_bit_time        : natural := gc_nom_sync_seg + gc_nom_prop_seg + gc_nom_phase_seg1 + gc_nom_phase_seg2;
  constant c_data_bit_time       : natural := gc_data_sync_seg + gc_data_prop_seg + gc_data_phase_seg1 + gc_data_phase_seg2;
  constant c_sp_position         : natural := gc_nom_sync_seg + gc_nom_prop_seg + gc_nom_phase_seg1;
  constant c_data_sp_position    : natural := gc_data_sync_seg + gc_data_prop_seg + gc_data_phase_seg1;
  constant c_tdc_prescaler_valid : boolean := (gc_prescaler = 1 or gc_prescaler = 2); -- TDC requires prescaler = 1 or 2 (ISO 7.3.4)
  constant c_use_tdc             : boolean := gc_tdc_enable = '1' and c_tdc_prescaler_valid;
  constant c_max_ssp_pos         : natural := c_max_transmitter_delay + t_ssp_offset'high; -- Max SSP position in TQs: worst-case delay + max offset

  ---------------------------------------------------------------------------
  -- Signals
  ---------------------------------------------------------------------------
  signal state              : t_state;
  signal clk_count          : natural range 0 to gc_prescaler - 1;
  signal tq_count           : natural range 0 to c_nom_bit_time;
  signal delay_count_clk    : natural range 0 to c_max_transmitter_delay;
  signal tdc_counting       : boolean;
  signal ssp_position       : natural range 0 to c_data_bit_time - 1;
  signal tdc_delay          : natural range 0 to c_tdc_polarity_depth - 1;
  signal prev_rx_bus        : std_logic;
  signal prev_tx_bus        : std_logic;
  signal ssp_delay          : natural range 0 to c_max_ssp_pos;
  signal ssp_standoff_start : boolean;
  signal ssp_active         : std_logic;
  signal tq_tick            : std_logic;
  signal bit_boundary       : std_logic;
  signal active_bit_time    : natural range 0 to c_nom_bit_time;
  signal active_sp          : natural range 0 to c_sp_position;

begin

  ---------------------------------------------------------------------------
  -- Active bit time and sample point
  ---------------------------------------------------------------------------
  active_bit_time <= c_data_bit_time when state = s_data else c_nom_bit_time;
  active_sp <= c_data_sp_position when state = s_data else c_sp_position;

  ---------------------------------------------------------------------------
  -- Prescaler tick
  ---------------------------------------------------------------------------
  tq_tick <= '1' when clk_count = gc_prescaler - 1 else '0';

  ---------------------------------------------------------------------------
  -- Bit boundary flag
  ---------------------------------------------------------------------------
  bit_boundary <= '1' when tq_tick = '1' and tq_count = active_bit_time - 1 else '0';

  ---------------------------------------------------------------------------
  -- Prescaler counter process
  ---------------------------------------------------------------------------
  p_prescaler_counter : process (clk_i) is
  begin
    if rising_edge(clk_i) then
      if (rst_i = '1') then
        clk_count <= 0;
      else
        clk_count <= 0 when clk_count = gc_prescaler - 1 else clk_count + 1;
      end if;
    end if;
  end process p_prescaler_counter;

  ---------------------------------------------------------------------------
  -- Bit counter and TX output
  ---------------------------------------------------------------------------
  p_tq_counter : process (clk_i) is
  begin
    if rising_edge(clk_i) then
      if (rst_i = '1') then
        tq_count <= 0;
        tx_bus_o <= c_recessive;
      elsif bit_boundary = '1' then
        tq_count <= 0;
        tx_bus_o <= mac_to_pcs_i.polarity;
      else
        tq_count <= tq_count + 1 when tq_tick = '1';
      end if;
    end if;
  end process p_tq_counter;

  ---------------------------------------------------------------------------
  -- Sample point generation
  ---------------------------------------------------------------------------
  p_sample_point : process (clk_i) is
  begin
    if rising_edge(clk_i) then
      if (rst_i = '1') then
        pcs_to_mac_o.sample_point <= '0';
      elsif (tq_tick = '1' and tq_count = active_sp - 1) then
        pcs_to_mac_o.sample_point <= '1';
      else
        pcs_to_mac_o.sample_point <= '0';
      end if;
    end if;
  end process p_sample_point;

  ---------------------------------------------------------------------------
  -- SSP standoff counter (ISO 7.3.4: first SSP after TDCV + ssp_offset TQs)
  ---------------------------------------------------------------------------
  p_ssp_standoff : process (clk_i) is
  begin
    if rising_edge(clk_i) then
      if (rst_i = '1' or state /= s_data) then
        ssp_delay <= 0;
        ssp_active<= '0';
      elsif ssp_standoff_start then
        ssp_delay  <= tdc_delay;
        ssp_active <= '0';
      elsif (ssp_delay > 0 and bit_boundary = '1') then
        ssp_delay <= ssp_delay - 1;
      elsif (ssp_delay = 0 and ssp_active = '0') then
        ssp_active <= '1';
      end if;
    end if;
  end process p_ssp_standoff;

  ---------------------------------------------------------------------------
  -- Secondary sample point generation (ISO 7.3.4)
  ---------------------------------------------------------------------------
  p_ssp : process (clk_i) is
  begin
    if rising_edge(clk_i) then
      if (rst_i = '1' or state /= s_data) then
        pcs_to_mac_o.secondary_sample_point <= '0';
        pcs_to_mac_o.tdc_delay              <= (others => '0');
      elsif (c_use_tdc and ssp_active = '1' and tq_tick = '1' and tq_count = ssp_position) then
        pcs_to_mac_o.secondary_sample_point <= '1';
        pcs_to_mac_o.tdc_delay              <= std_logic_vector(to_unsigned(tdc_delay, pcs_to_mac_o.tdc_delay'length));
      else
        pcs_to_mac_o.secondary_sample_point <= '0';
      end if;
    end if;
  end process p_ssp;

  ---------------------------------------------------------------------------
  -- Bus polarity passthrough
  ---------------------------------------------------------------------------
  p_bus_polarity : process (clk_i) is
  begin
    if rising_edge(clk_i) then
      if (rst_i = '1') then
        pcs_to_mac_o.bus_polarity <= c_recessive;
      else
        pcs_to_mac_o.bus_polarity <= rx_bus_i;
      end if;
    end if;
  end process p_bus_polarity;

  ---------------------------------------------------------------------------
  -- TDC delay measurement (ISO 7.3.4)
  -- Measures transmitter delay in clocks, converts to TQs, computes:
  --   ssp_position  = (TDC value + ssp_offset) mod data_bit_time
j  --   tdc_delay     = ceil(TDC value / data_bit_time)
  ---------------------------------------------------------------------------
  p_tdc : process (clk_i) is
    variable v_delay_tq   : natural;
    variable v_ssp_offset : natural;
  begin
    if rising_edge(clk_i) then
      if (rst_i = '1' or state = s_nominal) then
        delay_count_clk    <= 0;
        tdc_counting       <= false;
        ssp_position       <= 0;
        tdc_delay          <= 0;
        ssp_standoff_start <= false;
        prev_rx_bus        <= c_recessive;
        prev_tx_bus        <= c_recessive;
      else
        -- Latch bus for dominant edge detection
        prev_rx_bus <= rx_bus_i;
        prev_tx_bus <= tx_bus_o;

        -- Default delay
        ssp_standoff_start <= false; 

        -- Start counting on TX dominant edge during measurement state
        if (c_use_tdc and not tdc_counting and (prev_tx_bus = c_recessive and tx_bus_o = c_dominant) and state = s_measuring) then
          tdc_counting    <= true;
          delay_count_clk <= 0;
        elsif (tdc_counting and not (prev_rx_bus = c_recessive and rx_bus_i = c_dominant) and delay_count_clk < c_max_transmitter_delay) then
          delay_count_clk <= delay_count_clk + 1;
        end if;

        -- Latch delay on RX dominant edge
        if (prev_rx_bus = c_recessive and rx_bus_i = c_dominant) and tdc_counting then
          v_delay_tq := (delay_count_clk + gc_prescaler - 1) / gc_prescaler; -- Convert clock count to TQs (ceiling)
          tdc_delay <= (v_delay_tq + c_data_bit_time - 1) / c_data_bit_time; -- tdc_delay = ceil(v_delay_tq / c_data_bit_time)
          v_ssp_offset := c_data_sp_position - 1; -- This sets the SSP position right before the SP position (gives the delayed bit max time to stabilize before). 
          ssp_position <= (v_delay_tq + v_ssp_offset) mod c_data_bit_time; -- Calculate the SSP position
          ssp_standoff_start <= true; -- Signal p_ssp_standoff to start counting
          -- Reset/re-arm counter
          tdc_counting <= false;
          delay_count_clk <= 0;
        end if;
      end if;
    end if;
  end process p_tdc;

  ---------------------------------------------------------------------------
  -- FSM process
  ---------------------------------------------------------------------------
  p_fsm : process (clk_i) is
  begin
    if rising_edge(clk_i) then
      if (rst_i = '1') then
        state <= s_nominal;
      else
        case state is
          when s_nominal =>
            if (bit_boundary = '1' and mac_to_pcs_i.start_tdc = '1') then
              state <= s_measuring;
            end if;
            if (bit_boundary = '1' and mac_to_pcs_i.use_data_rate = '1') then
              state <= s_data;
            end if;
          when s_measuring =>
            if (bit_boundary = '1' and mac_to_pcs_i.use_data_rate = '1') then
              state <= s_data;
            end if;
          when s_data =>
            if (bit_boundary = '1' and mac_to_pcs_i.use_data_rate = '0') then
              state <= s_nominal;
            end if;
          when others =>
            state <= s_nominal;
        end case;
      end if;
    end if;
  end process p_fsm;

end architecture rtl;

-- eof
