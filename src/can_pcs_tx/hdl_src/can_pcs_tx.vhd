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
--------------------------------------------------------------------------------------------------------------------------------------------------------------

library ieee;
  use ieee.std_logic_1164.all;
  use ieee.numeric_std.all;
  use work.pk_can_types.all;
  use work.can_timing_pkg.all;

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
    gc_ssp_offset      : t_ssp_offset         := t_ssp_offset'high / 2;
    gc_tdc_enable      : std_logic            := '1'
  );
  port (
    clk_i : in    std_logic;
    rst_i : in    std_logic;

    mac_to_pcs_i : in    t_can_mac_pcs_if_m2s;
    pcs_to_mac_o : out   t_can_mac_pcs_if_s2m;

    tx_bus_o : out   std_logic;
    rx_bus_i : in    std_logic
  );
end entity can_pcs_tx;

architecture rtl of can_pcs_tx is

  -- Local state encoding
  constant c_st_idle       : std_logic_vector(1 downto 0) := "00";
  constant c_st_nominal    : std_logic_vector(1 downto 0) := "01";
  constant c_st_measuring  : std_logic_vector(1 downto 0) := "10";
  constant c_st_data       : std_logic_vector(1 downto 0) := "11";

  -- Bit timing constants
  constant c_nom_bit_time     : natural := gc_nom_sync_seg + gc_nom_prop_seg + gc_nom_phase_seg1 + gc_nom_phase_seg2;
  constant c_data_bit_time    : natural := gc_data_sync_seg + gc_data_prop_seg + gc_data_phase_seg1 + gc_data_phase_seg2;
  constant c_sp_position      : natural := gc_nom_sync_seg + gc_nom_prop_seg + gc_nom_phase_seg1;
  constant c_data_sp_position : natural := gc_data_sync_seg + gc_data_prop_seg + gc_data_phase_seg1;

  -- TDC requires prescaler = 1 or 2 (ISO 7.3.4)
  constant c_tdc_prescaler_valid : boolean := (gc_prescaler = 1 or gc_prescaler = 2);
  constant c_use_tdc             : boolean := gc_tdc_enable = '1' and c_tdc_prescaler_valid;

  ---------------------------------------------------------------------------
  -- Registered signals
  ---------------------------------------------------------------------------
  signal state           : std_logic_vector(1 downto 0);
  signal clk_count       : natural range 0 to gc_prescaler - 1;
  signal tq_count        : natural range 0 to c_nom_bit_time;
  signal delay_count_clk : natural range 0 to c_max_transmitter_delay;
  signal tdc_counting    : std_logic;
  signal ssp_position    : natural range 0 to c_data_bit_time - 1;
  signal tdc_delay       : natural range 0 to c_tdc_polarity_depth - 1;
  signal prev_rx_bus     : std_logic;
  signal prev_tx_bus     : std_logic;
  signal in_data_phase   : std_logic;

begin

  ---------------------------------------------------------------------------
  -- FSM process
  ---------------------------------------------------------------------------
  fsm : process (clk_i) is

    variable v_state      : std_logic_vector(1 downto 0);
    variable v_pcs_to_mac : t_can_mac_pcs_if_s2m;

    -- Guard variables
    variable v_frame_active : boolean;
    variable v_tq_tick      : boolean;
    variable v_bit_boundary : boolean;
    variable v_active_bt    : natural;
    variable v_active_sp    : natural;

    ---------------------------------------------------------------------------
    procedure tick_prescaler is
    begin

      v_tq_tick := false;
      if (clk_count = gc_prescaler - 1) then
        v_tq_tick := true;
        clk_count <= 0;
      else
        clk_count <= clk_count + 1;
      end if;

    end procedure tick_prescaler;

    ---------------------------------------------------------------------------
    procedure latch_next_bit (
      bit_time : in natural
    ) is
    begin

      v_bit_boundary := v_tq_tick and (tq_count = bit_time - 1);

      if (v_bit_boundary) then
        tq_count <= 0;
        tx_bus_o <= mac_to_pcs_i.polarity;
      elsif (v_tq_tick) then
        tq_count <= tq_count + 1;
      end if;

    end procedure latch_next_bit;

    ---------------------------------------------------------------------------
    procedure emit_sp (
      sp_pos : in natural
    ) is
    begin

      if (v_tq_tick and tq_count = sp_pos - 1) then
        v_pcs_to_mac.sp := '1';
      end if;

    end procedure emit_sp;

    ---------------------------------------------------------------------------
    procedure emit_ssp is
    begin

      if (c_use_tdc and in_data_phase = '1' and
          v_tq_tick and tq_count = ssp_position) then
        v_pcs_to_mac.ssp       := '1';
        v_pcs_to_mac.tdc_delay := std_logic_vector(to_unsigned(tdc_delay, v_pcs_to_mac.tdc_delay'length));
      end if;

    end procedure emit_ssp;

    ---------------------------------------------------------------------------
    procedure measure_tdc is

      variable v_tx_rising_edge : boolean;
      variable v_rx_rising_edge : boolean;
      variable v_delay_tq       : natural;

    begin

      v_tx_rising_edge := (prev_tx_bus = c_recessive and tx_bus_o = c_dominant);
      v_rx_rising_edge := (prev_rx_bus = c_recessive and rx_bus_i = c_dominant);

      if (c_use_tdc and tdc_counting = '0' and v_tx_rising_edge) then
        tdc_counting    <= '1';
        delay_count_clk <= 0;
      elsif (tdc_counting = '1' and not v_rx_rising_edge and
             delay_count_clk < c_max_transmitter_delay) then
        delay_count_clk <= delay_count_clk + 1;
      end if;

      if (v_rx_rising_edge and tdc_counting = '1') then
        v_delay_tq   := (delay_count_clk + gc_prescaler - 1) / gc_prescaler + gc_ssp_offset;
        tdc_delay    <= calculate_tdc_delay(v_delay_tq, c_data_bit_time);
        ssp_position <= v_delay_tq mod c_data_bit_time;
        tdc_counting <= '0';
      end if;

    end procedure measure_tdc;

  begin

    if rising_edge(clk_i) then
      if (rst_i = '1') then
        state           <= c_st_idle;
        clk_count       <= 0;
        tq_count        <= 0;
        delay_count_clk <= 0;
        tdc_counting    <= '0';
        ssp_position    <= 0;
        tdc_delay       <= 0;
        prev_rx_bus     <= c_recessive;
        prev_tx_bus     <= c_recessive;
        in_data_phase   <= '0';
        pcs_to_mac_o    <= c_pcs_to_mac_if_reset;
        tx_bus_o        <= c_recessive;
      else
        -- Evaluate guards
        v_frame_active := mac_to_pcs_i.valid = '1';

        v_state := state;

        -- Output defaults
        v_pcs_to_mac.bus_polarity := rx_bus_i;
        v_pcs_to_mac.sp           := '0';
        v_pcs_to_mac.ssp          := '0';
        v_pcs_to_mac.tdc_delay    := (others => '0');

        -- Select active bit time and SP position based on data phase
        if (in_data_phase = '1') then
          v_active_bt := c_data_bit_time;
          v_active_sp := c_data_sp_position;
        else
          v_active_bt := c_nom_bit_time;
          v_active_sp := c_sp_position;
        end if;

        case state is

          -----------------------------------------------------------------
          -- Bus idle. Tick prescaler and emit SP for bus monitoring.
          -----------------------------------------------------------------
          when c_st_idle =>
            tick_prescaler;
            latch_next_bit(c_nom_bit_time);
            emit_sp(c_sp_position);
            if (v_frame_active) then
              clk_count <= 0;
              tq_count  <= 0;
              tx_bus_o  <= mac_to_pcs_i.polarity;
              v_state   := c_st_nominal;
            end if;

          -----------------------------------------------------------------
          -- Nominal bit rate transmission.
          -----------------------------------------------------------------
          when c_st_nominal =>
            tick_prescaler;
            latch_next_bit(c_nom_bit_time);
            emit_sp(c_sp_position);
            -- At bit boundary: check start_tdc (FDF bit latched)
            if (v_bit_boundary and mac_to_pcs_i.start_tdc = '1') then
              tdc_counting    <= '0';
              delay_count_clk <= 0;
              v_state         := c_st_measuring;
            end if;
            -- At bit boundary: check use_data_rate
            if (v_bit_boundary and mac_to_pcs_i.use_data_rate = '1') then
              in_data_phase <= '1';
              v_state       := c_st_data;
            end if;

          -----------------------------------------------------------------
          -- TDC delay measurement at nominal rate.
          -----------------------------------------------------------------
          when c_st_measuring =>
            tick_prescaler;
            latch_next_bit(c_nom_bit_time);
            emit_sp(c_sp_position);
            measure_tdc;
            -- At bit boundary: MAC asserts use_data_rate when BRS is recessive
            if (v_bit_boundary and mac_to_pcs_i.use_data_rate = '1') then
              in_data_phase <= '1';
              v_state       := c_st_data;
            end if;

          -----------------------------------------------------------------
          -- Data bit rate transmission with SSP generation.
          -----------------------------------------------------------------
          when c_st_data =>
            tick_prescaler;
            latch_next_bit(c_data_bit_time);
            emit_sp(c_data_sp_position);
            emit_ssp;
            -- At bit boundary: MAC drops use_data_rate at CRC delimiter or error flag
            if (v_bit_boundary and mac_to_pcs_i.use_data_rate = '0') then
              in_data_phase <= '0';
              v_state       := c_st_nominal;
            end if;

          when others =>
            v_state := c_st_idle;

        end case;

        -- Return to idle when frame ends
        if (not v_frame_active) then
          v_state       := c_st_idle;
          tdc_counting  <= '0';
          in_data_phase <= '0';
        end if;

        -- Register updates
        state        <= v_state;
        pcs_to_mac_o <= v_pcs_to_mac;

        prev_rx_bus <= rx_bus_i;
        prev_tx_bus <= tx_bus_o;
      end if;
    end if;

  end process fsm;


end architecture rtl;
