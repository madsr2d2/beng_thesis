--------------------------------------------------------------------------------
-- Title      : CAN Physical Signaling Layer (PCS) with TDC
-- Project    : Implementation and Verification of a CAN-FD Bus Transceiver in VHDL
--------------------------------------------------------------------------------
-- File       : can_pcs_tx.vhd
-- Author     : Mads Richardt
-- Standard   : VHDL-2008
--------------------------------------------------------------------------------
-- Description: Physical Signaling layer implementing bit timing, transmission,
--              and Transmitter Delay Compensation (TDC) per ISO 11898-1:2015
--              Section 7.2 (PCS Services) and 7.3.4 (TDC).
--
-- Responsibilities:
--   - Bit timing generation (nominal and data bit rates)
--   - Serial bit transmission to bus
--   - TDC delay measurement at FDF->res edge
--   - Sample Point (SP) and Secondary Sample Point (SSP) generation
--   - Bus monitoring (RX input for loopback and delay measurement)
--
-- FSM State Transitions:
--   idle -> transmitting_nominal              (mac_to_pcs_i.valid = true)
--   transmitting_nominal -> measuring_delay   (FDF sample point)
--   measuring_delay -> transmitting_data      (BRS bit boundary, BRS recessive)
--   measuring_delay -> transmitting_nominal   (BRS dominant)
--   transmitting_data -> transmitting_nominal (CRC delimiter or error flag)
--   any non-idle -> idle                      (mac_to_pcs_i.valid = false)
--------------------------------------------------------------------------------

library ieee;
  use ieee.std_logic_1164.all;
  use ieee.numeric_std.all;
  use work.can_types_pkg.all;
  use work.can_protocol_pkg.all;
  use work.can_timing_pkg.all;

entity can_pcs_tx is
  generic (
    -- Set generics to middle of ISO specified ranges
    -- Nominal values
    prescaler      : prescaler          := prescaler'high / 2;
    nom_sync_seg   : integer            := sync_seg_c;
    nom_prop_seg   : nominal_prop_seg   := nominal_prop_seg'high / 2;
    nom_phase_seg1 : nominal_phase_seg1 := nominal_phase_seg1'high / 2;
    nom_phase_seg2 : nominal_phase_seg2 := nominal_phase_seg2'high / 2;

    -- Data values
    data_sync_seg   : integer         := nom_sync_seg;
    data_prop_seg   : data_prop_seg   := data_prop_seg'high / 2;
    data_phase_seg1 : data_phase_seg1 := data_phase_seg1'high / 2;
    data_phase_seg2 : data_phase_seg2 := data_phase_seg2'high / 2;
    ssp_offset      : ssp_offset      := ssp_offset'high / 2;
    tdc_enable      : boolean         := true
  );
  port (
    clk : in    std_logic;
    rst : in    std_logic;

    mac_to_pcs_i : in    can_mac_pcs_tx_if_m2s_t;
    pcs_to_mac_o : out   can_mac_pcs_tx_if_s2m_t;

    tx_bus_o : out   std_logic;
    rx_bus_i : in    std_logic;

    -- Debug port (test visibility)
    debug_state_o : out   can_pcs_tx_state_t
  );
end entity can_pcs_tx;

architecture rtl of can_pcs_tx is

  -- Bit timing constants
  constant nom_bit_time     : integer := nom_sync_seg + nom_prop_seg + nom_phase_seg1 + nom_phase_seg2;
  constant data_bit_time    : integer := data_sync_seg + data_prop_seg + data_phase_seg1 + data_phase_seg2;
  constant sp_position      : integer := nom_sync_seg + nom_prop_seg + nom_phase_seg1;
  constant data_sp_position : integer := data_sync_seg + data_prop_seg + data_phase_seg1;

  -- Prescaler must be 1 or 2 (ISO 7.3.4).
  constant tdc_prescaler_valid_c : boolean := (prescaler = 1 or prescaler = 2);
  constant use_tdc_c             : boolean := tdc_enable and tdc_prescaler_valid_c;

  ---------------------------------------------------------------------------
  -- Registered signals
  ---------------------------------------------------------------------------
  signal state           : can_pcs_tx_state_t;
  signal clk_count       : integer range 0 to prescaler - 1;
  signal tq_count        : integer range 0 to nom_bit_time;
  signal current_bit     : mac_frame_bit_t;
  signal delay_count_clk : integer range 0 to max_transmitter_delay_c;
  signal tdc_counting    : boolean;
  signal ssp_position    : integer range 0 to data_bit_time - 1;
  signal fifo_index      : integer range 0 to transmitted_bits_fifo_depth_c - 1;
  signal prev_rx_bus     : std_logic;
  signal prev_tx_bus     : std_logic;

  -- PSL-only: guards assertions from firing before valid state
  signal reset_done : boolean;

begin

  ---------------------------------------------------------------------------
  -- FSM process
  ---------------------------------------------------------------------------
  fsm : process (clk) is

    variable v_state      : can_pcs_tx_state_t;
    variable v_pcs_to_mac : can_mac_pcs_tx_if_s2m_t;

    -- Guard variables
    variable frame_active_v    : boolean;
    variable tq_tick_v         : boolean;
    variable bit_boundary_v    : boolean;
    variable fdf_at_sp_v       : boolean;
    variable brs_at_boundary_v : boolean;
    variable exit_data_phase_v : boolean;

    ---------------------------------------------------------------------------
    -- Advance clk_count and set tq_tick_v.
    ---------------------------------------------------------------------------
    procedure tick_prescaler is

    begin

      tq_tick_v := false;
      if (clk_count = prescaler - 1) then
        tq_tick_v := true;
        clk_count <= 0;
      else
        clk_count <= clk_count + 1;
      end if;

    end procedure tick_prescaler;

    ---------------------------------------------------------------------------
    -- Advance TQ counter and latch next bit boundary.
    ---------------------------------------------------------------------------
    procedure latch_next_bit (
      bit_time : in integer
    ) is

    begin

      bit_boundary_v := tq_tick_v and (tq_count = bit_time - 1);

      if (bit_boundary_v) then
        current_bit <= mac_to_pcs_i.data;
        tq_count    <= 0;
        tx_bus_o    <= polarity_to_std_logic(mac_to_pcs_i.data.polarity);
      elsif (tq_tick_v) then
        tq_count <= tq_count + 1;
      end if;

    end procedure latch_next_bit;

    ---------------------------------------------------------------------------
    -- Emit sample point strobe at the given TQ position.
    ---------------------------------------------------------------------------
    procedure emit_sp (
      sp_pos : in integer
    ) is
    begin

      if (tq_tick_v and tq_count = sp_pos - 1) then
        v_pcs_to_mac.sample_strobe := '1';
        v_pcs_to_mac.strobe_type   := sp_strobe;
      end if;

    end procedure emit_sp;

    ---------------------------------------------------------------------------
    -- Emit secondary sample point strobe (TDC monitoring).
    ---------------------------------------------------------------------------
    procedure emit_ssp is

      variable ssp_due_v : boolean;

    begin

      ssp_due_v := use_tdc_c and
                   tq_tick_v and tq_count = ssp_position and
                   (current_bit.bit_name = esi_bit or
                    current_bit.bit_name = data_bit or
                    current_bit.bit_name = stuff_bit or
                    current_bit.bit_name = fixed_stuff_bit or
                    current_bit.bit_name = sbs_bit or
                    current_bit.bit_name = dlc_bit or
                    current_bit.bit_name = crc_bit);

      if (ssp_due_v) then
        v_pcs_to_mac.sample_strobe := '1';
        v_pcs_to_mac.strobe_type   := ssp_strobe;
        v_pcs_to_mac.fifo_index    := fifo_index;
      end if;

    end procedure emit_ssp;

    ---------------------------------------------------------------------------
    -- TDC delay measurement (ISO 11898-1: 7.3.4).
    ---------------------------------------------------------------------------
    procedure measure_tdc is

      variable tx_rising_edge_v : boolean;
      variable rx_rising_edge_v : boolean;
      variable delay_tq_v       : integer;

    begin

      tx_rising_edge_v := (prev_tx_bus = recessive_bit_c and tx_bus_o = dominant_bit_c);
      rx_rising_edge_v := (prev_rx_bus = recessive_bit_c and rx_bus_i = dominant_bit_c);

      -- Start counter on TX output edge
      if (use_tdc_c and not tdc_counting and tx_rising_edge_v) then
        tdc_counting    <= true;
        delay_count_clk <= 0;
      elsif (tdc_counting and not rx_rising_edge_v and
             delay_count_clk < max_transmitter_delay_c) then
        delay_count_clk <= delay_count_clk + 1;
      end if;

      -- Latch on registered RX recessive->dominant edge
      if (rx_rising_edge_v and tdc_counting) then
        delay_tq_v   := (delay_count_clk + prescaler - 1) / prescaler + ssp_offset;
        fifo_index   <= calculate_fifo_delay_index(delay_tq_v, data_bit_time);
        ssp_position <= delay_tq_v mod data_bit_time;
        tdc_counting <= false;
      end if;

    end procedure measure_tdc;

  begin

    if rising_edge(clk) then
      if (rst = '1') then
        state           <= idle;
        clk_count       <= 0;
        tq_count        <= 0;
        current_bit     <= reset_mac_frame_bit_c;
        delay_count_clk <= 0;
        tdc_counting    <= false;
        ssp_position    <= 0;
        fifo_index      <= 0;
        prev_rx_bus     <= recessive_bit_c;
        prev_tx_bus     <= recessive_bit_c;
        pcs_to_mac_o    <= pcs_to_mac_if_reset_c;
        tx_bus_o        <= recessive_bit_c;
      else
        -- Evaluate guards
        frame_active_v := mac_to_pcs_i.valid;
        fdf_at_sp_v    := current_bit.bit_name = fdf_bit and
                          clk_count = prescaler - 1 and tq_count = sp_position - 1;

        -- Initialize state variable from register
        v_state := state;

        -- Output defaults
        v_pcs_to_mac.bus_polarity  := std_logic_to_polarity(rx_bus_i);
        v_pcs_to_mac.sample_strobe := '0';
        v_pcs_to_mac.strobe_type   := sp_strobe;
        v_pcs_to_mac.fifo_index    := 0;

        case state is

          when idle =>
            tick_prescaler;
            latch_next_bit(nom_bit_time);
            emit_sp(sp_position);
            -- Transition: latch first bit on valid
            if (frame_active_v) then
              current_bit <= mac_to_pcs_i.data;
              tq_count    <= 0;
              tx_bus_o    <= polarity_to_std_logic(mac_to_pcs_i.data.polarity);
              v_state     := transmitting_nominal;
            end if;

          when transmitting_nominal =>
            tick_prescaler;
            latch_next_bit(nom_bit_time);
            emit_sp(sp_position);
            -- Transition to measuring_delay at FDF bit sample point.
            if (fdf_at_sp_v) then
              tdc_counting    <= false;
              delay_count_clk <= 0;
              v_state         := measuring_delay;
            end if;

          when measuring_delay =>
            tick_prescaler;
            latch_next_bit(nom_bit_time);
            emit_sp(sp_position);
            measure_tdc;
            -- Transition at BRS bit boundary
            brs_at_boundary_v := bit_boundary_v and current_bit.bit_name = brs_bit;
            if (brs_at_boundary_v) then
              if (current_bit.polarity = recessive) then
                v_state := transmitting_data;
              else
                v_state := transmitting_nominal;
              end if;
            end if;

          when transmitting_data =>
            tick_prescaler;
            latch_next_bit(data_bit_time);
            emit_sp(data_sp_position);
            emit_ssp;
            -- Return to nominal on error flag or CRC delimiter
            exit_data_phase_v := bit_boundary_v and
                                 (mac_to_pcs_i.data.bit_name = active_error_flag_bit or
                                  mac_to_pcs_i.data.bit_name = passive_error_flag_bit or
                                  mac_to_pcs_i.data.bit_name = crc_delimiter_bit);
            if (exit_data_phase_v) then
              v_state := transmitting_nominal;
            end if;

        end case;

        -- Return to idle when frame ends (overrides any state transition).
        if (not frame_active_v) then
          v_state      := idle;
          tdc_counting <= false;
        end if;

        -- Register remaining updates
        state        <= v_state;
        pcs_to_mac_o <= v_pcs_to_mac;

        -- Edge detection registers
        prev_rx_bus <= rx_bus_i;
        prev_tx_bus <= tx_bus_o;
      end if;
    end if;

  end process fsm;

  debug_state_o <= state;

  ---------------------------------------------------------------------------
  -- PSL-only shadow signals (optimized away by synthesis)
  ---------------------------------------------------------------------------
  -- PSL-only: one cycle after reset deasserts
  psl_reset_done : process (clk) is
  begin

    if rising_edge(clk) then
      if (rst = '1') then
        reset_done <= false;
      else
        reset_done <= true;
      end if;
    end if;

  end process psl_reset_done;

--------------------------------------------------------------
-- REQ-PCS-001: D_Transmit active/passive at data phase boundaries
-- REQ-PCS-004: FD data bit time only in FD data phase
-- REQ-PCS-005: Time quantum derived from prescaler
-- REQ-PCS-008: Sample point at end of Phase_Seg1
-- REQ-PCS-017: TDC mechanism support
-- REQ-PCS-018: TDC only with BRS recessive and prescaler in {1,2}
-- REQ-PCS-022: SSP = measured delay + ssp_offset
-- REQ-PCS-034: Output symbol on Output_Unit from MAC
--------------------------------------------------------------

--------------------------------------------------------------
-- Default clock
--------------------------------------------------------------
-- psl default clock is rising_edge(clk);
--------------------------------------------------------------

--------------------------------------------------------------
-- Environment assumptions
--------------------------------------------------------------
-- psl assume_reset_init : assume (rst = '1');
-- psl assume_reset_done_init : assume (not reset_done);
--------------------------------------------------------------
-- psl assume_no_unknown_polarity : assume always
-- (mac_to_pcs_i.data.polarity = dominant or
-- mac_to_pcs_i.data.polarity = recessive);
--------------------------------------------------------------

--------------------------------------------------------------
-- Assertions
--------------------------------------------------------------
-- psl psl_1 : assert always
-- { rst = '1' }
-- |=>
-- { state = idle and
-- clk_count = 0 and
-- tq_count = 0 and
-- delay_count_clk = 0 and
-- not tdc_counting and
-- ssp_position = 0 and
-- fifo_index = 0 and
-- tx_bus_o = recessive_bit_c and
-- pcs_to_mac_o.sample_strobe = '0' }
-- report "Reset did not clear all registers to default values";
--------------------------------------------------------------
-- psl psl_2 : assert always
-- { reset_done }
-- |->
-- { clk_count <= prescaler - 1 and
-- tq_count <= nom_bit_time and
-- delay_count_clk <= max_transmitter_delay_c }
-- report "Counter out of valid range";
--------------------------------------------------------------
-- psl psl_3 : assert always
-- { reset_done and
-- state /= idle and
-- not mac_to_pcs_i.valid }
-- |=>
-- { state = idle and
-- not tdc_counting }
-- report "REQ-PCS-001: Did not return to idle when frame ended";
--------------------------------------------------------------
-- psl psl_4 : assert always
-- { reset_done and
-- state = transmitting_data }
-- |->
-- { use_tdc_c or
-- pcs_to_mac_o.strobe_type = sp_strobe }
-- report "REQ-PCS-018: Data phase SSP without TDC enabled";
--------------------------------------------------------------
-- psl psl_5 : assert always
-- { reset_done and
-- state = idle and
-- mac_to_pcs_i.valid }
-- |=>
-- { state = transmitting_nominal and
-- tq_count = 0 }
-- report "Frame start did not transition to transmitting_nominal";
--------------------------------------------------------------
-- psl psl_6 : assert always
-- { reset_done and
-- state = transmitting_nominal and
-- current_bit.bit_name = fdf_bit and
-- clk_count = prescaler - 1 and
-- tq_count = sp_position - 1 }
-- |=>
-- { state = measuring_delay and
-- not tdc_counting and
-- delay_count_clk = 0 }
-- report "REQ-PCS-017: FDF sample point did not trigger TDC measurement";
--------------------------------------------------------------
-- psl psl_7 : assert always
-- { reset_done and
-- pcs_to_mac_o.sample_strobe = '1' }
-- |=>
-- { pcs_to_mac_o.sample_strobe = '0' }
-- report "REQ-PCS-008: Sample strobe not single-cycle pulse";
--------------------------------------------------------------

--------------------------------------------------------------
-- Cover points
--------------------------------------------------------------
-- psl cover_1 : cover { state = transmitting_nominal };
-- psl cover_2 : cover { state = measuring_delay };
-- psl cover_3 : cover { state = transmitting_data };
-- psl cover_4 : cover { pcs_to_mac_o.sample_strobe = '1' and pcs_to_mac_o.strobe_type = sp_strobe };
-- psl cover_5 : cover { pcs_to_mac_o.sample_strobe = '1' and pcs_to_mac_o.strobe_type = ssp_strobe };
-- psl cover_6 : cover { tdc_counting };
-- psl cover_7 : cover { state = transmitting_data and pcs_to_mac_o.sample_strobe = '1' };
--------------------------------------------------------------

end architecture rtl;
