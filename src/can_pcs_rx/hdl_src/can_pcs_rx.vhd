--------------------------------------------------------------------------------
-- Title      : CAN PCS RX Sub-layer
-- Project    : Implementation and Verification of a CAN-FD Bus Transceiver in VHDL
--------------------------------------------------------------------------------
-- File       : can_pcs_rx.vhd
-- Author     : Mads Richardt
-- Standard   : VHDL-2008
--------------------------------------------------------------------------------
-- Description: Receiver-side Physical Coding Sub-layer per ISO 11898-1:2015.
--              Bit timing with hard sync and resync (ISO 7.3.5).
--              Nominal/data rate, sample point generation, and bus-off
--              idle condition detection.
--------------------------------------------------------------------------------

library ieee;
  use ieee.std_logic_1164.all;
  use ieee.numeric_std.all;
  use work.pk_can_types.all;

entity can_pcs_rx is
  generic (
    gc_prescaler       : t_prescaler          := t_prescaler'high / 2;
    gc_nom_prop_seg    : t_nominal_prop_seg   := t_nominal_prop_seg'high / 2;
    gc_nom_phase_seg1  : t_nominal_phase_seg1 := t_nominal_phase_seg1'high / 2;
    gc_nom_phase_seg2  : t_nominal_phase_seg2 := t_nominal_phase_seg2'high / 2;
    gc_data_prop_seg   : t_data_prop_seg      := t_data_prop_seg'high / 2;
    gc_data_phase_seg1 : t_data_phase_seg1    := t_data_phase_seg1'high / 2;
    gc_data_phase_seg2 : t_data_phase_seg2    := t_data_phase_seg2'high / 2;
    gc_sjw             : t_sjw                := 1
  );
  port (
    clk_i : in    std_logic;
    rst_i : in    std_logic;
    ---
    mac_i : in    t_can_mac_pcs_rx_if_m2s;
    mac_o : out   t_can_mac_pcs_rx_if_s2m;
    ---
    fce_i : in    t_can_fce_pcs_if_m2s;
    fce_o : out   t_can_pcs_fce_if_s2m;
    ---
    tx_bus_o : out   std_logic;
    rx_bus_i : in    std_logic;
    ---
    debug_phase1_extension_o  : out natural;
    debug_phase2_shortening_o : out natural;
    debug_prescaler_restart_o : out boolean
  );
end entity can_pcs_rx;

architecture rtl of can_pcs_rx is

  ---------------------------------------------------------------------------
  -- Types
  ---------------------------------------------------------------------------
  type t_rate_state is (s_nominal, s_data);
  type t_segment is (s_sync_seg, s_prop_seg, s_phase_seg1, s_phase_seg2);

  ---------------------------------------------------------------------------
  -- Signals
  ---------------------------------------------------------------------------
  signal rate_state        : t_rate_state;
  signal segment           : t_segment;
  signal prescaler_count   : natural range 0 to gc_prescaler - 1;
  signal prescaler_restart : boolean;
  signal seg_count         : natural range 0 to gc_nom_prop_seg + gc_nom_phase_seg1 + gc_sjw;
  signal rx_bus_prev       : std_logic;
  signal sync_inhibit      : boolean;
  signal sampled_polarity  : std_logic;
  signal phase1_extension  : natural range 0 to gc_sjw;
  signal phase2_shortening : natural range 0 to gc_sjw;
  signal recessive_counter : natural range 0 to c_bus_idle_condition_width - 1;
  signal tq_tick           : std_logic;
  signal edge_detected     : boolean;
  signal active_prop_seg   : natural;
  signal active_phase_seg1 : natural;
  signal active_phase_seg2 : natural;
  signal bit_boundary      : boolean;
  signal sample_point      : boolean;

begin

  ---------------------------------------------------------------------------
  -- Concurrent assignments
  ---------------------------------------------------------------------------
  -- Active segment lengths switched by rate state (ISO 7.3.2)
  active_prop_seg   <= gc_data_prop_seg when rate_state = s_data else gc_nom_prop_seg;
  active_phase_seg1 <= gc_data_phase_seg1 when rate_state = s_data else gc_nom_phase_seg1;
  active_phase_seg2 <= gc_data_phase_seg2 when rate_state = s_data else gc_nom_phase_seg2;
  tq_tick           <= '1' when prescaler_count = gc_prescaler - 1 else '0';
  edge_detected     <= rx_bus_prev = c_recessive and rx_bus_i = c_dominant;
  bit_boundary      <= tq_tick = '1' and segment = s_phase_seg2 and seg_count = active_phase_seg2 - phase2_shortening - 1;
  sample_point      <= tq_tick = '1' and segment = s_phase_seg1 and seg_count = active_phase_seg1 + phase1_extension - 1;

  ---------------------------------------------------------------------------
  -- Edge detection and bus polarity registration on the tq_tick
  ---------------------------------------------------------------------------
  p_edge_detect : process (clk_i) is
  begin
    if rising_edge(clk_i) then
      if rst_i = '1' then
        rx_bus_prev        <= c_recessive;
        mac_o.bus_polarity <= c_recessive;
      elsif tq_tick = '1' then
        rx_bus_prev        <= rx_bus_i;
        mac_o.bus_polarity <= rx_bus_i;
      end if;
    end if;
  end process p_edge_detect;

  ---------------------------------------------------------------------------
  -- Pre-scaler counter (ISO 7.3.3)
  ---------------------------------------------------------------------------
  p_prescaler : process (clk_i) is
  begin
    if rising_edge(clk_i) then
      if rst_i = '1' or prescaler_restart then
        prescaler_count <= 0;
      elsif prescaler_count = gc_prescaler - 1 then
        prescaler_count <= 0;
      else
        prescaler_count <= prescaler_count + 1;
      end if;
    end if;
  end process p_prescaler;

  ---------------------------------------------------------------------------
  -- Bit timing and synchronization FSM (ISO 7.3.5)
  -- Tracks current bit time segment: Sync_Seg -> Prop_Seg -> Phase_Seg1 -> Phase_Seg2.
  -- Applies hard synchronization (ISO 7.3.5.3) or resynchronization (ISO 7.3.5.4)
  -- on valid edges, depending on the hard_sync_en signal from the MAC FSM.
  ---------------------------------------------------------------------------
  p_bit_timing : process (clk_i) is
    variable v_sync_allowed : boolean;
    variable v_phase_error  : natural;
    variable v_seg_end      : natural;
  begin
    if rising_edge(clk_i) then
      if rst_i = '1' then
        segment            <= s_sync_seg;
        seg_count          <= 0;
        sync_inhibit       <= false;
        phase1_extension   <= 0;
        phase2_shortening  <= 0;
        prescaler_restart  <= false;
      else
        -- Default: no prescaler restart this cycle
        prescaler_restart <= false;

        ---------------------------------------------------------------------------
        -- Synchronization guard (ISO 7.3.5.1 rules a, b)
        -- Rule a: only one sync per bit time (between two sample points)
        -- Rule b: only sync if previous sample point read recessive
        ---------------------------------------------------------------------------
        v_sync_allowed := edge_detected and not sync_inhibit and sampled_polarity = c_recessive;

        if v_sync_allowed then
          sync_inhibit <= true; -- ISO 7.3.5.1 rule a: disable further syncs this bit

          ---------------------------------------------------------------------------
          -- Hard synchronization (ISO 7.3.5.3-4): restart bit time
          -- Either requested by can_mac_fsm_rx or sync error = 0 (edge detected while in s_sync_seg).
          ---------------------------------------------------------------------------
          if mac_i.hard_sync_en = '1' or segment = s_sync_seg then
            -- e = 0: edge within Sync_Seg, same effect as hard sync (ISO 7.3.5.4)
            segment           <= s_sync_seg;
            seg_count         <= 0;
            prescaler_restart <= true;
            phase1_extension  <= 0;
            phase2_shortening <= 0;
          else
            ---------------------------------------------------------------------------
            -- Bit resynchronization (ISO : 7.3.5.4)
            ---------------------------------------------------------------------------
            case segment is
              when s_prop_seg | s_phase_seg1 =>
                  -- e > 0: edge before sample point (ISO 7.3.5.4)
                  v_phase_error := seg_count + 1 when segment = s_prop_seg else active_prop_seg + seg_count + 1; -- Phase error relative to last s_sync_seg
                  if v_phase_error <= gc_sjw then
                    -- |e| <= SJW: restart bit time
                    segment           <= s_sync_seg;
                    seg_count         <= 0;
                    prescaler_restart <= true;
                  else
                    phase1_extension <= gc_sjw; -- |e| > SJW: lengthen Phase_Seg1 by SJW TQs
                  end if;
              when s_phase_seg2 =>
                  -- e < 0: edge after sample point (ISO 7.3.5.4)
                  v_phase_error := (active_phase_seg2 - phase2_shortening) - (seg_count + 1); -- Phase error relative to next s_sync_seg (remaining TQs in phase_seg2)
                  if v_phase_error <= gc_sjw then
                    -- |e| <= SJW: restart bit time
                    segment           <= s_sync_seg;
                    seg_count         <= 0;
                    prescaler_restart <= true;
                    phase2_shortening <= 0;
                  else
                    phase2_shortening <= gc_sjw; -- |e| > SJW: shorten Phase_Seg2 by SJW TQs
                  end if;
              when others =>
                segment <= s_sync_seg;
            end case;
          end if;
        elsif tq_tick = '1' then
          ---------------------------------------------------------------------------
          -- Normal segment progression on TQ tick
          ---------------------------------------------------------------------------
          case segment is
            when s_sync_seg =>
              -- Sync_Seg is always 1 TQ
              segment   <= s_prop_seg;
              seg_count <= 0;
            when s_prop_seg =>
              if seg_count = active_prop_seg - 1 then
                segment   <= s_phase_seg1;
                seg_count <= 0;
              else
                seg_count <= seg_count + 1;
              end if;
            when s_phase_seg1 =>
              -- Phase_Seg1 length may be extended by resynchronization (ISO 7.3.5.4)
              v_seg_end := active_phase_seg1 + phase1_extension - 1;
              if seg_count = v_seg_end then
                segment          <= s_phase_seg2;
                seg_count        <= 0;
                phase1_extension <= 0;
              else
                seg_count <= seg_count + 1;
              end if;
            when s_phase_seg2 =>
              -- Phase_Seg2 length may be shortened by resynchronization (ISO 7.3.5.4)
              v_seg_end := active_phase_seg2 - phase2_shortening - 1;
              if seg_count = v_seg_end then
                -- Bit boundary: start new bit
                segment           <= s_sync_seg;
                seg_count         <= 0;
                phase2_shortening <= 0;
                sync_inhibit      <= false; -- Allow sync in next bit
              else
                seg_count <= seg_count + 1;
              end if;
          end case;
        end if;
      end if;
    end if;
  end process p_bit_timing;

  ---------------------------------------------------------------------------
  -- Sample point strobe and bus-off idle detection
  ---------------------------------------------------------------------------
  p_sample_point : process (clk_i) is
  begin
    if rising_edge(clk_i) then
      if rst_i = '1' then
        mac_o.sample_point   <= '0';
        sampled_polarity     <= c_recessive;
        fce_o.idle_condition <= '0';
        recessive_counter    <= 0;
      else
        -- Default
        mac_o.sample_point   <= '0';
        fce_o.idle_condition <= '0';

        if sample_point then
          sampled_polarity <= rx_bus_i; -- Latch polarity for sync rule b (ISO 7.3.5.1)
          if fce_i.bus_off = '0' then
            mac_o.sample_point <= '1'; -- Sample point strobe
          else
            -- Bus-off idle condition counting (this strobe is used by the FCE to count up to the bus release condition)
            if rx_bus_i = c_dominant then
              recessive_counter <= 0;
            elsif recessive_counter = c_bus_idle_condition_width - 1 then
              fce_o.idle_condition <= '1';
              recessive_counter    <= 0;
            else
              recessive_counter <= recessive_counter + 1;
            end if;
          end if;
        end if;
      end if;
    end if;
  end process p_sample_point;

  ---------------------------------------------------------------------------
  -- TX bus output latched at bit boundaries
  ---------------------------------------------------------------------------
  p_tx_output : process (clk_i) is
  begin
    if rising_edge(clk_i) then
      if rst_i = '1' then
        tx_bus_o <= c_recessive;
      else
        if bit_boundary then
          tx_bus_o <= mac_i.polarity when fce_i.bus_off = '1' else c_recessive;
        end if;
      end if;
    end if;
  end process p_tx_output;

  ---------------------------------------------------------------------------
  -- Rate switching FSM: Switches between nominal and data bit timing at bit boundaries
  ---------------------------------------------------------------------------
  p_rate_switch : process (clk_i) is
  begin
    if rising_edge(clk_i) then
      if rst_i = '1' then
        rate_state <= s_nominal;
      else
        if bit_boundary then
          case rate_state is
            when s_nominal =>
              rate_state <= s_data when mac_i.use_data_rate = '1';
            when s_data =>
              rate_state <= s_nominal when mac_i.use_data_rate = '0';
          end case;
        end if;
      end if;
    end if;
  end process p_rate_switch;

  ---------------------------------------------------------------------------
  -- Debug port assignments (simulation-only, optimized away in synthesis)
  ---------------------------------------------------------------------------
  debug_phase1_extension_o  <= phase1_extension;
  debug_phase2_shortening_o <= phase2_shortening;
  debug_prescaler_restart_o <= prescaler_restart;

end architecture rtl;
-- eof
