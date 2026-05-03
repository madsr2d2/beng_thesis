--------------------------------------------------------------------------------------------------------------------------------------------------------------
-- Copyright 2026 Everllence, Teglholmsgade 41, 2450 Copenhagen SV, Denmark
--------------------------------------------------------------------------------------------------------------------------------------------------------------
--
-- Requirements:
--
-- Description: Physical Coding Sub-layer (PCS) per ISO 11898-1:2024 (7.2, 7.3).
--              Handles bit timing, hard sync and resync (ISO 7.3.5), sample point
--              generation, and TDC-based secondary sample point positioning
--              (ISO 7.3.4) for CAN FD nominal and data phases. Generates
--              idle_condition strobes for bus-off recovery counting (ISO 8.1.4.4).
--
-- Revision log:  Date:       Initial:  JIRA:
--                2026-04-16  TMYAES:   [TRIT-4336] [FPGA] CAN FD extensions of TRIT-3880
--                2026-04-27  MRDSA:    Local mirror of company can_pcs.
--
--------------------------------------------------------------------------------------------------------------------------------------------------------------

library ieee;
  use ieee.std_logic_1164.all;
  use ieee.numeric_std.all;
  use work.pk_can_types.all;

entity can_pcs is
  ---------------------------------------------------------------------------
  -- CAN bit timing overview
  ---------------------------------------------------------------------------
  --
  -- CAN bit segment structure -----------------------------------------------
  --
  -- | Sync_Seg (Always 1 TQ) | Prop_Seg | Phase_Seg1 | Phase_Seg2 |
  --                                                  ^
  --                                                  |
  --                                   Sample point (SP) position
  --
  -- TQ = Base time quantum (derived from system clock and a prescaler)
  --
  ---------------------------------------------------------------------------

  -- Bit timing derivations for a 100 Mhz system clock ----------------------
  --
  -- Shared parameters for nominal and data phases:
  --  T_clk (System clock period)                                = 10 ns (System clock period)
  --  Prescaler (Number of system clock cycles per time quantum) =  2
  --  TQ = Prescaler x T_clk                                     = 20 ns
  --  SP (as a fraction of the bit time)                         =  0.8

  -- Nominal phase (0.5 Mbit/s):
  --   bit time = 1s / 0.5e6                         = 2000 ns
  --   N (bit time / TQ)                             =  100 TQ
  --   SP_tq (sample point TQ, N x SP)               =   80 TQ
  --   Sync_Seg (fixed)                              =    1 TQ
  --   Phase_Seg2 (N - SP_tq)                        =   20 TQ
  --   Prop_Seg+Phase_Seg1 (SP_tq - Sync_Seg)        =   79 TQ
  --   Prop_Seg (ceil(Prop_Seg+Phase_Seg1/2))        =   40 TQ
  --   Phase_Seg1 (floor(Prop_Seg+Phase_Seg1/2))     =   39 TQ
  --   SJW (1 <= SJW <= min(Phase_Seg1, Phase_Seg2)) =    4 TQ
  --
  -- Data phase (5.0 Mbit/s):
  --   bit time = 1s / 5e6                           = 200 ns
  --   N (bit time / TQ)                             =  10 TQ
  --   SP_tq (sample point TQ, N x SP)               =   8 TQ
  --   Phase_Seg2 (N - SP_tq)                        =   2 TQ
  --   Prop_Seg+Phase_Seg1 (SP_tq - Sync_Seg)        =   7 TQ
  --   Prop_Seg (ceil(Prop_Seg+Phase_Seg1/2))        =   4 TQ
  --   Phase_Seg1 (floor(Prop_Seg+Phase_Seg1/2))     =   3 TQ
  --   SJW (1 <= SJW <= min(Phase_Seg1, Phase_Seg2)) =   2 TQ
  ---------------------------------------------------------------------------
  generic (
    gc_prescaler       : natural := 2;
    gc_nom_prop_seg    : natural := 40;
    gc_nom_phase_seg1  : natural := 39;
    gc_nom_phase_seg2  : natural := 20;
    gc_data_prop_seg   : natural := 4;
    gc_data_phase_seg1 : natural := 3;
    gc_data_phase_seg2 : natural := 2;
    gc_nom_sjw         : natural := 4;
    gc_data_sjw        : natural := 2
  );
  port (
    clk_i : in    std_logic;
    rst_i : in    std_logic;
    ---
    mac_i : in    t_can_mac_pcs_if_m2s;
    mac_o : out   t_can_mac_pcs_if_s2m;
    ---
    fce_i : in    t_can_fce_pcs_if_m2s;
    fce_o : out   t_can_pcs_fce_if_s2m;
    ---
    tx_o  : out   std_logic;
    rx_i  : in    std_logic
  );
end entity can_pcs;

architecture rtl of can_pcs is

  ---------------------------------------------------------------------------
  -- Types
  ---------------------------------------------------------------------------
  type t_segment is (s_sync_seg, s_prop_seg, s_phase_seg1, s_phase_seg2);

  ---------------------------------------------------------------------------
  -- Signals
  ---------------------------------------------------------------------------
  signal segment                      : t_segment;
  signal clk_count                    : natural range 0 to gc_prescaler - 1;
  signal seg_count                    : natural range 0 to gc_nom_prop_seg + gc_nom_phase_seg1 + gc_nom_sjw;
  signal rx_bus_prev                  : std_logic;
  signal sync_applied                 : std_logic;
  signal phase1_extension             : natural range 0 to gc_nom_sjw;
  signal phase2_shortening            : natural range 0 to gc_nom_sjw;
  signal recessive_counter            : natural range 0 to c_bus_idle_condition_width - 1;
  signal active_prop_seg              : natural range nom_prop_seg_min to nom_prop_seg_max;
  signal active_phase_seg1            : natural range nom_phase_seg1_min to nom_phase_seg1_max;
  signal active_phase_seg2            : natural range nom_phase_seg2_min to nom_phase_seg2_max;
  signal active_sjw                   : natural range sjw_min to sjw_max;
  signal tdc_count_active             : std_logic;
  signal delay_count_tq               : natural range 0 to c_max_transmitter_delay;
  signal ssp_active                   : std_logic;
  signal ssp_seen                     : std_logic;
  signal tdc_delay                    : natural range 0 to c_tdc_polarity_depth - 1;
  signal bit_boundary                 : std_logic;                              -- Pulses one cycle at end of phase_seg2 (forwarded to MAC)
  signal ssp_standoff_active          : std_logic;
  signal first_data_bit_boundary_seen : std_logic;
  signal data_phase_active            : std_logic;
begin

  p_can_pcs : process (clk_i) is
    variable v_phase_error : natural range 0 to gc_nom_prop_seg + gc_nom_phase_seg1 + gc_nom_phase_seg2;
    variable v_do_sync     : boolean;
  begin
    if rising_edge(clk_i) then
      if rst_i = '1' then
        mac_o                        <= c_pcs_to_mac_if_reset;
        fce_o                        <= c_pcs_to_fce_if_reset;
        tx_o                         <= c_recessive;
        --
        seg_count                    <= 0;
        clk_count                    <= 0;
        delay_count_tq               <= 0;
        tdc_delay                    <= 0;
        recessive_counter            <= 0;
        phase1_extension             <= 0;
        phase2_shortening            <= 0;
        --
        active_prop_seg              <= gc_nom_prop_seg;
        active_phase_seg1            <= gc_nom_phase_seg1;
        active_phase_seg2            <= gc_nom_phase_seg2;
        active_sjw                   <= gc_nom_sjw;
        segment                      <= s_sync_seg;
        --
        sync_applied                 <= '0';
        tdc_count_active             <= '0';
        ssp_seen                     <= '0';
        ssp_active                   <= '0';
        ssp_standoff_active          <= '0';
        rx_bus_prev                  <= c_recessive;
        data_phase_active            <= '0';
        first_data_bit_boundary_seen <= '0';
        bit_boundary                 <= '0';
      else

        -- Clear strobe signals
        mac_o.sample_point           <= '0';
        mac_o.secondary_sample_point <= '0';
        fce_o.idle_condition         <= '0';
        bit_boundary                 <= '0';
        -- Pipeline bit_boundary by one clock so the tx_o latch (below)
        -- happens after the MAC FSM has had time to update mac_i.tx_data
        -- in response to drive_bit (= sample_point + 2 clocks in MAC).
        -- Latch bus on clock
        mac_o.rx_data                <= rx_i;

        -- Time quantum (TQ) boundary -----------------------------------------------
        if clk_count = (gc_prescaler - 1) then
          -- Reset prescaler counter
          clk_count   <= 0;
          -- Latch current bus state for edge detection
          rx_bus_prev <= rx_i;

          -- Evaluate synchronization condition
          -- v_do_sync := (rx_bus_prev = c_recessive) and (rx_i = c_dominant) and (sync_applied = '0') and (mac_i.transmitting = '0');
          v_do_sync := (rx_bus_prev = c_recessive) and (rx_i = c_dominant) and (sync_applied = '0') and (mac_i.transmitting = '0');

          -- Transmitter delay counter --------------------------------------------
          if mac_i.transmitting = '1' then
            if tdc_count_active then
              if (rx_i = c_recessive) and (delay_count_tq < c_max_transmitter_delay) then
                delay_count_tq <= delay_count_tq + 1;
              else
                tdc_count_active <= '0';
              end if;
            end if;

            if ssp_standoff_active = '1' then
              if delay_count_tq > 0 then
                delay_count_tq <= delay_count_tq - 1;
              else
                ssp_active          <= '1';
                ssp_standoff_active <= '0';
              end if;
            end if;
          end if;
          ---------------------------------------------------------------------------

          ---------------------------------------------------------------------------
          -- Hard synchronization (ISO 7.3.5.3-4): Restart bit time at end of sync_seg
          ---------------------------------------------------------------------------
          if v_do_sync and (mac_i.do_hard_sync = '1') then
            sync_applied      <= '1';
            clk_count         <= 0;
            seg_count         <= 0;
            phase1_extension  <= 0;
            phase2_shortening <= 0;
            segment           <= s_prop_seg;
          else
            ---------------------------------------------------------------------------
            -- Segment progression + synchronization (ISO 7.3.5.3)
            ---------------------------------------------------------------------------
            case segment is
              when s_sync_seg =>
                segment   <= s_prop_seg;
                seg_count <= 0;

              when s_prop_seg =>
                -- Increment segment counter
                seg_count <= seg_count + 1;

                -- Bit synchronization  ---------------------------------------------------
                if v_do_sync then
                  sync_applied  <= '1';
                  -- Phase error relative to the sync_seg
                  v_phase_error := seg_count + 1;
                  if v_phase_error > active_sjw then
                    -- If the magnitude of the phase error is larger than the SJW we lengthen Phase_Seg1 by the SJW (ISO : 7.3.5.4)
                    phase1_extension <= active_sjw;
                  -- Only 1 sync per bit time allowed, so inhibit further sync until next sample point (ISO : 7.3.5.1.a)
                  else
                    -- If the magnitude of the phase error is smaller that the SJW we do a hard sync on the edge (ISO : 7.3.5.3)
                    -- This forces the synchronizing edge to lie within the sync_seg.
                    clk_count         <= 0;
                    seg_count         <= 0;
                    phase1_extension  <= 0;
                    phase2_shortening <= 0;
                    segment           <= s_prop_seg;
                  end if;
                ---------------------------------------------------------------------------
                elsif seg_count >= (active_prop_seg - 1) then
                  segment   <= s_phase_seg1;
                  seg_count <= 0;
                end if;

              when s_phase_seg1 =>
                -- Increment segment counter
                seg_count <= seg_count + 1;

                -- Bit synchronization  ---------------------------------------------------
                if v_do_sync then
                  sync_applied  <= '1';
                  -- Phase error relative to the sync_seg
                  v_phase_error := active_prop_seg + seg_count + 1;
                  if v_phase_error > active_sjw then
                    -- If the magnitude of the phase error is larger than the SJW we lengthen Phase_Seg1 by the SJW (ISO : 7.3.5.4)
                    phase1_extension <= active_sjw;
                  -- Only 1 sync per bit time allowed, so inhibit further sync until next sample point (ISO : 7.3.5.1.a)
                  else
                    -- If the magnitude of the phase error is smaller that the SJW we do a hard sync on the edge (ISO : 7.3.5.3)
                    -- This forces the synchronizing edge to lie within the sync_seg.
                    clk_count         <= 0;
                    seg_count         <= 0;
                    phase1_extension  <= 0;
                    phase2_shortening <= 0;
                    segment           <= s_prop_seg;
                  end if;
                ---------------------------------------------------------------------------

                -- Sample point (SP) ------------------------------------------------------
                elsif seg_count >= ((active_phase_seg1 - 1) + phase1_extension) then
                  segment          <= s_phase_seg2;
                  seg_count        <= 0;
                  -- Reset phase1 extension after applying it for this bit time
                  phase1_extension <= 0;
                  -- Allow sync again for the next bit time
                  sync_applied     <= '0';

                  if fce_i.bus_off = '0' then
                    -- Strobe sample point
                    mac_o.sample_point <= '1';
                    -- Latch bus polarity to MAC output
                    mac_o.rx_data      <= rx_i;

                    -- The MAC sets current_bit_is_brs = '1' at the sample point (SP) of BRS bit (ISO : 7.3.2 Figure 32).
                    -- If the BRS bit is transmitted/received recessive then the current frame shall
                    -- use the data bit timing from the BRS bit SP until the CRC delimiter bit SP.
                    if mac_i.next_bit_is_brs = '1' then
                      if mac_i.transmitting = '1' then
                        if mac_i.tx_data = c_recessive then                     -- Check the value from MAC when transmitting
                          active_prop_seg   <= gc_data_prop_seg;
                          active_phase_seg1 <= gc_data_phase_seg1;
                          active_phase_seg2 <= gc_data_phase_seg2;
                          active_sjw        <= gc_data_sjw;
                          data_phase_active <= '1';
                        end if;
                      else
                        if rx_i = c_recessive then                              -- Check the value on the bus when receiving
                          active_prop_seg   <= gc_data_prop_seg;
                          active_phase_seg1 <= gc_data_phase_seg1;
                          active_phase_seg2 <= gc_data_phase_seg2;
                          active_sjw        <= gc_data_sjw;
                          data_phase_active <= '1';
                        end if;
                      end if;
                    elsif mac_i.data_phase_stop = '1' then
                      -- Switch back to nominal timing when use_data_rate = '0'
                      active_prop_seg              <= gc_nom_prop_seg;
                      active_phase_seg1            <= gc_nom_phase_seg1;
                      active_phase_seg2            <= gc_nom_phase_seg2;
                      active_sjw                   <= gc_nom_sjw;
                      tdc_delay                    <= 0;
                      data_phase_active            <= '0';
                      first_data_bit_boundary_seen <= '0';
                      ssp_seen                     <= '0';
                      ssp_active                   <= '0';
                      delay_count_tq               <= 0;
                      tdc_count_active             <= '0';
                    end if;

                  else
                    -- Bus-off idle condition counting (this strobe is used by the FCE to count up to the bus release condition)
                    if rx_i = c_dominant then
                      recessive_counter <= 0;
                    elsif (recessive_counter = (c_bus_idle_condition_width - 1)) then
                      fce_o.idle_condition <= '1';
                      recessive_counter    <= 0;
                    else
                      recessive_counter <= recessive_counter + 1;
                    end if;
                  end if;
                ---------------------------------------------------------------------------

                -- Secondary sample point (SSP) -------------------------------------------
                -- At the SP, the MAC must react to errors detected at the SSP.
                -- Therefore the SSP must precede the SP in the bit time.
                elsif (ssp_active = '1') and (seg_count = (((active_phase_seg1 - 1) + phase1_extension) - 1)) and (mac_i.transmitting = '1') then
                  mac_o.secondary_sample_point <= '1';
                  mac_o.rx_data                <= rx_i;
                  ssp_seen                     <= '1';

                  -- tdc_delay register holds the count of complete data-phase
                  -- bit boundaries elapsed since first_data_bit_boundary_seen
                  -- was set (incremented once per boundary while ssp_seen=0,
                  -- not incremented at boundary 0 itself). When SSP fires
                  -- inside bit M, the register equals M, and the bus polarity
                  -- being sampled reflects the TX drive from M bits ago in
                  -- the polarity_history shift register convention where
                  -- polarity_history(0) = the drive placed at the most
                  -- recent MAC-SP. The FSM therefore wants
                  -- polarity_history(tdc_delay) for its bit-error compare,
                  -- so we report tdc_delay directly with no offset.
                  mac_o.tdc_delay <= std_logic_vector(to_unsigned(tdc_delay, mac_o.tdc_delay'length));
                end if;
              ---------------------------------------------------------------------------

              when s_phase_seg2 =>
                -- Increment segment counter
                seg_count <= seg_count + 1;

                -- Bit synchronization  ---------------------------------------------------
                if v_do_sync then
                  sync_applied  <= '1';
                  v_phase_error := (active_phase_seg2 - 1) - seg_count;
                  if v_phase_error > gc_nom_sjw then
                    -- If the magnitude of the phase error is larger than the SJW we shorten Phase_Seg2 by the SJW (ISO : 7.3.5.4)
                    phase2_shortening <= gc_nom_sjw;
                  -- Only 1 sync per bit time allowed, so inhibit further sync until next sample point (ISO : 7.3.5.1.a)
                  else
                    -- If the magnitude of the phase error is smaller that the SJW we do a hard sync on the edge (ISO : 7.3.5.3)
                    -- This forces the synchronizing edge to lie within the sync_seg.
                    clk_count         <= 0;
                    seg_count         <= 0;
                    phase1_extension  <= 0;
                    phase2_shortening <= 0;
                    segment           <= s_prop_seg;
                  end if;
                ---------------------------------------------------------------------------

                -- Bit boundary -----------------------------------------------------------
                elsif seg_count >= ((active_phase_seg2 - 1) - phase2_shortening) then
                  tx_o <= mac_i.tx_data;
                  bit_boundary       <= '1';
                  segment            <= s_sync_seg;
                  seg_count          <= 0;
                  phase2_shortening  <= 0;
                  -- Allow sync again now that we've reached the next bit boundary
                  sync_applied       <= '0';

                  if fce_i.bus_off = '0' then
                    if mac_i.transmitting = '1' then
                      -- Transmitter Delay Compensation (TDC) logic (ISO 7.3.4) ----------
                      if ssp_seen = '0' then
                        if data_phase_active = '1' then
                          if first_data_bit_boundary_seen = '0' then
                            -- First data bit boundary: start the standoff countdown
                            first_data_bit_boundary_seen <= '1';
                            ssp_standoff_active          <= '1';
                          else
                            -- Subsequent boundaries before SSP fires: count up tdc_delay
                            tdc_delay <= tdc_delay + 1;
                          end if;
                        end if;
                      end if;

                      -- Start the TDC value counter.
                      if mac_i.next_bit_is_res = '1' then
                        tdc_count_active <= '1';
                      end if;
                    end if;
                  end if;
                end if;
                ---------------------------------------------------------------------------
            end case;
          end if;
        else
          clk_count <= clk_count + 1;
        end if;

      end if;
    end if;
  end process p_can_pcs;

end architecture rtl;
