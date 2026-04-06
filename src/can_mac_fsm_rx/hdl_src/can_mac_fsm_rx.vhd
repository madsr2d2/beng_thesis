--------------------------------------------------------------------------------------------------------------------------------------------------------------
-- Copyright 2026 Everllence, Teglholmsgade 41, 2450 Copenhagen SV, Denmark
--------------------------------------------------------------------------------------------------------------------------------------------------------------
--
-- Requirements:
--
-- Description:   Frame reception FSM. Tracks incoming frame state, drives ACK
--                and error/overload flags onto the bus via PCS, coordinates
--                bit destuffing (via shared can_mac_bs) and CRC checking
--                (via shared can_mac_crc). Stores received frame in llc_frame
--                and streams it byte-by-byte to the LLC during the quiet phase
--                (EOF + interframe space) using Avalon-ST handshake.
--
-- Revision log:  Date:       Initial:  JIRA:
--                2026-03-31  MRDSA     Converted to company header format
--                2026-04-05  MRDSA     Remove deser, add LLC byte streaming
--
--------------------------------------------------------------------------------------------------------------------------------------------------------------

library ieee;
  use ieee.std_logic_1164.all;
  use ieee.numeric_std.all;
  use work.pk_can_types.all;

entity can_mac_fsm_rx is
  port (
    clk_i : in    std_logic;
    rst_i : in    std_logic;

    -- LLC interface (MAC is source, LLC is destination)
    llc_i : in    t_can_llc_mac_rx_if_d2s;
    llc_o : out   t_can_llc_mac_rx_if_s2d;

    -- PCS interface (bidirectional - RX receives and sends ACK/error flags)
    pcs_i : in    t_can_mac_pcs_if_s2m;
    pcs_o : out   t_can_mac_pcs_if_m2s;

    -- Bit stuffer interface (reused for destuffing)
    bs_i   : in    t_can_mac_fsm_bs_if_s2m;
    bs_o   : out   t_can_mac_fsm_bs_if_m2s;
    bs_rst : out   std_logic;

    -- CRC interface (reused for CRC checking)
    crc_i   : in    t_can_mac_fsm_crc_if_s2m;
    crc_o   : out   t_can_mac_fsm_crc_if_m2s;
    crc_rst : out   std_logic;

    -- Fault Confinement Entity interface
    fce_i : in    t_can_mac_fce_if_s2m;
    fce_o : out   t_can_mac_fce_if_m2s
  );
end entity can_mac_fsm_rx;

architecture rtl of can_mac_fsm_rx is

  type t_fsm_state is (
    s_idle, s_id, s_ftyp, s_ide, s_fdf, s_res, s_brs, s_esi,
    s_dlc, s_data, s_sbc, s_crc, s_ack, s_eof, s_interframe, s_error_overload
  );

  signal fsm_state : t_fsm_state;

  signal bit_count  : natural range 0 to c_max_mac_frame_length;
  signal byte_index : natural range 0 to c_internal_llc_frame_len - 1;
  signal bit_index  : natural range 0 to c_byte_width - 1;
  signal data_len   : natural range 0 to c_max_data_bytes;

  signal crc_length   : natural range 0 to c_crc_21_length;
  signal crc_mismatch : std_logic;

  signal llc_frame : t_llc_frame;

  -- LLC byte streaming during quiet phase
  signal llc_streaming  : std_logic;
  signal llc_byte_index : natural range 0 to c_internal_llc_frame_len - 1;
  signal llc_frame_len  : natural range 0 to c_internal_llc_frame_len;

begin

  p_fsm : process (clk_i) is

    variable v_data_len : natural;
    variable v_dlc_vec  : std_logic_vector(c_llc_frame_dlc_start downto c_llc_frame_dlc_end);

    -- Guard predicates
    variable v_in_dynamic_stuff        : boolean;
    variable v_in_fixed_stuff        : boolean;
    -- Bit reception results
    variable v_real_bit      : boolean;
    variable v_stuff_error   : boolean;
    -- Error flag entry
    variable v_protocol_error : boolean;

  begin

    if rising_edge(clk_i) then
      if (rst_i = '1') then
        bs_rst         <= '1';
        crc_rst        <= '1';
        bit_count      <= 0;
        byte_index     <= 0;
        bit_index      <= 0;
        data_len       <= 0;
        fsm_state      <= s_idle;
        crc_length     <= c_crc_15_length;
        crc_mismatch   <= '0';
        llc_streaming  <= '0';
        llc_byte_index <= 0;
        llc_frame_len  <= 0;
        llc_frame      <= (others => (others => '0'));
        pcs_o          <= c_mac_to_pcs_if_reset;
        bs_o           <= c_mac_fsm_to_bs_fd_if_reset;
        crc_o          <= c_mac_fsm_to_crc_if_reset;
        fce_o          <= c_mac_to_fce_if_reset;
        llc_o          <= c_mac_rx_to_llc_if_reset;
      else
        -----------------------------------------------------------------
        -- Pulse defaults (cleared every cycle, set only when active)
        -----------------------------------------------------------------
        bs_o.valid          <= '0';
        bs_o.fsb_en         <= '0';
        crc_o.valid_cc      <= '0';
        crc_o.valid_fd      <= '0';
        bs_rst              <= '0';
        crc_rst             <= '0';
        fce_o               <= c_mac_to_fce_if_reset;
        pcs_o.valid         <= '0';
        pcs_o.polarity      <= c_recessive;
        pcs_o.start_tdc     <= '0';
        pcs_o.use_data_rate <= llc_frame(c_conf_0_offset)(c_llc_frame_brs);

        llc_o.avalon_st_source.valid         <= '0';
        llc_o.avalon_st_source.startofpacket <= '0';
        llc_o.avalon_st_source.endofpacket   <= '0';

        -----------------------------------------------------------------
        -- Guard predicates
        -----------------------------------------------------------------
        v_in_dynamic_stuff := fsm_state = s_id or fsm_state = s_ftyp or
                              fsm_state = s_ide or fsm_state = s_fdf or
                              fsm_state = s_res or fsm_state = s_brs or
                              fsm_state = s_esi or fsm_state = s_dlc or
                              fsm_state = s_data;
        v_in_fixed_stuff := fsm_state = s_sbc or fsm_state = s_crc;

        v_real_bit       := false;
        v_stuff_error    := false;
        v_protocol_error := false;

        -----------------------------------------------------------------
        -- FSB mode for SBC and FD CRC fields
        -----------------------------------------------------------------
        if (fsm_state = s_sbc) then
          bs_o.fsb_en <= '1';
        elsif (fsm_state = s_crc and crc_length /= c_crc_15_length) then
          bs_o.fsb_en <= '1';
        end if;

        -----------------------------------------------------------------
        -- Common bit reception: BS feed, stuff check, CRC feed.
        -- Applies to all states between SOF and CRC delimiter.
        -----------------------------------------------------------------
        if (pcs_i.sp = '1' and (v_in_dynamic_stuff or v_in_fixed_stuff)) then
          bs_o.valid <= '1';
          bs_o.data  <= pcs_i.bus_polarity;

          if (bs_i.valid = '1') then
            -- Stuff bit: feed FD CRC in arb region (ISO 6.6.4.4), check polarity
            if (v_in_dynamic_stuff) then
              crc_o.valid_fd <= '1';
              crc_o.data_fd  <= pcs_i.bus_polarity;
            end if;
            if (bs_i.data /= pcs_i.bus_polarity) then
              v_stuff_error := true;
            end if;
          else
            v_real_bit := true;
            -- Real bit CRC feed depends on region
            if (v_in_dynamic_stuff) then
              crc_o.valid_cc <= '1';
              crc_o.valid_fd <= '1';
              crc_o.data_cc  <= pcs_i.bus_polarity;
              crc_o.data_fd  <= pcs_i.bus_polarity;
            elsif (fsm_state = s_sbc) then
              crc_o.valid_fd <= '1';
              crc_o.data_fd  <= pcs_i.bus_polarity;
            end if;
          end if;
        end if;

        -----------------------------------------------------------------
        -- LLC byte streaming: runs during EOF and interframe space.
        -----------------------------------------------------------------
        if (llc_streaming = '1') then
          llc_o.avalon_st_source.data  <= llc_frame(llc_byte_index);
          llc_o.avalon_st_source.valid <= '1';

          if (llc_byte_index = 0) then
            llc_o.avalon_st_source.startofpacket <= '1';
          end if;

          if (llc_byte_index = llc_frame_len - 1) then
            llc_o.avalon_st_source.endofpacket <= '1';
          end if;

          if (llc_i.avalon_st_sink.ready = '1') then
            if (llc_byte_index = llc_frame_len - 1) then
              llc_streaming <= '0';
            else
              llc_byte_index <= llc_byte_index + 1;
            end if;
          end if;
        end if;

        -----------------------------------------------------------------
        -- State machine
        -----------------------------------------------------------------
        case fsm_state is

        -----------------------------------------------------------------
        -- s_idle : Waits for SOF and resets state variables
        -----------------------------------------------------------------
          when s_idle =>

            pcs_o.use_data_rate <= '0';
            crc_mismatch        <= '0';
            if (pcs_i.sp = '1' and pcs_i.bus_polarity = c_dominant) then
              crc_o.valid_cc <= '1';
              crc_o.valid_fd <= '1';
              crc_o.data_cc  <= c_dominant;
              crc_o.data_fd  <= c_dominant;
              bs_o.valid     <= '1';
              bs_o.data      <= c_dominant;
              bit_count      <= 0;
              byte_index     <= 0;
              bit_index      <= 0;
              llc_frame      <= (others => (others => '0'));
              fsm_state      <= s_id;
            end if;

        -----------------------------------------------------------------
        -- s_id : Stores received ID bits in the LLC frame
        -----------------------------------------------------------------
          when s_id =>
            if (v_real_bit) then
              -- Store ID bit
              llc_frame(c_id_offset + byte_index)((c_byte_width - 1) - bit_index) <= pcs_i.bus_polarity;
              -- Increment counters
              bit_index  <= 0 when bit_index = (c_byte_width - 1) else (bit_index + 1);
              byte_index <= (byte_index + 1) when bit_index = (c_byte_width - 1);
              bit_count  <= (bit_count + 1);
              -- Go to s_ftyp when last base or extended ID bit has been received
              if (bit_count = (c_base_id_width - 1) or bit_count = (c_base_id_width + c_extended_id_width - 1)) then
                fsm_state <= s_ftyp;
              end if;
            end if;

        -----------------------------------------------------------------
        -- s_ftyp : Sets the frame type bit (Remote or DATA) in the LLC
        -- frame configuration byte 0
        -----------------------------------------------------------------
          when s_ftyp =>
            if (v_real_bit) then
              llc_frame(c_conf_0_offset)(c_llc_frame_ftyp) <= pcs_i.bus_polarity;
              if (llc_frame(c_conf_0_offset)(c_llc_frame_ide) = '1') then
                fsm_state <= s_fdf;
              else
                fsm_state <= s_ide;
              end if;
            end if;

        -----------------------------------------------------------------
        -- s_ide : Sets the IDE bit ('0' = base ID, '1' = extended ID) 
        -- in the LLC frame configuration byte 0
        -----------------------------------------------------------------
          when s_ide =>
            if (v_real_bit) then
              llc_frame(c_conf_0_offset)(c_llc_frame_ide) <= pcs_i.bus_polarity; -- Set IDE bit
              if (pcs_i.bus_polarity = c_recessive) then 
                fsm_state <= s_id; -- Extended ID frame format: Go back to s_id to grab the extended ID bits
              else
                fsm_state <= s_fdf;
              end if;
            end if;

        -----------------------------------------------------------------
        -- s_fdf : Sets the FDF bit ('0' = CC format, '1' = FD format) in
        -- the LLC frame configuration byte 0
        -----------------------------------------------------------------
          when s_fdf =>
            if (v_real_bit) then
              llc_frame(c_conf_0_offset)(c_llc_frame_fdf) <= pcs_i.bus_polarity; -- Set FDF bit
              if (pcs_i.bus_polarity = c_recessive) then
                fsm_state <= s_res; -- Format is FD: Go to s_res
              elsif (llc_frame(c_conf_0_offset)(c_llc_frame_ide) = '1' and bit_count < c_base_id_width + c_extended_id_width) then
                fsm_state <= s_id;
              elsif (llc_frame(c_conf_0_offset)(c_llc_frame_ide) = '1') then
                fsm_state <= s_res;
              else
                fsm_state <= s_dlc;
                bit_count <= 0;
              end if;
            end if;

          -- -----------------------------------------------------------
          when s_res =>

            if (v_real_bit) then
              if (llc_frame(c_conf_0_offset)(c_llc_frame_fdf) = '1') then
                if (pcs_i.bus_polarity = c_dominant) then
                  fsm_state <= s_brs;
                else
                  fsm_state <= s_error_overload; -- This is a form error
                end if;
              else
                fsm_state <= s_dlc;
                bit_count <= 0;
              end if;
            end if;

          -- -----------------------------------------------------------
          when s_brs =>

            if (v_real_bit) then
              pcs_o.use_data_rate                         <= pcs_i.bus_polarity;
              llc_frame(c_conf_0_offset)(c_llc_frame_brs) <= pcs_i.bus_polarity;
              fsm_state                                   <= s_esi;
            end if;

          -- -----------------------------------------------------------
          when s_esi =>

            if (v_real_bit) then
              llc_frame(c_conf_0_offset)(c_llc_frame_esi) <= pcs_i.bus_polarity;
              fsm_state                                   <= s_dlc;
              bit_count                                   <= 0;
            end if;

          -- -----------------------------------------------------------
          when s_dlc =>

            if (v_real_bit) then
              llc_frame(c_conf_1_offset)(c_llc_frame_dlc_start - bit_count) <= pcs_i.bus_polarity;

              if (bit_count = c_dlc_field_width - 1) then
                v_dlc_vec := llc_frame(c_conf_1_offset)(c_llc_frame_dlc_start downto c_llc_frame_dlc_end);
                v_dlc_vec(c_llc_frame_dlc_start - bit_count) := pcs_i.bus_polarity;
                v_data_len := dlc_to_data_length(
                  to_integer(unsigned(v_dlc_vec)),
                  llc_frame(c_conf_0_offset)(c_llc_frame_fdf)
                );
                bit_count  <= 0;
                bit_index  <= 0;
                byte_index <= 0;
                data_len   <= v_data_len;

                if (llc_frame(c_conf_0_offset)(c_llc_frame_fdf) = '0') then
                  crc_length            <= c_crc_15_length;
                  crc_o.crc_poly_select <= c_crc_poly_15_sel;
                elsif (v_data_len < c_crc_17_length) then
                  crc_length            <= c_crc_17_length;
                  crc_o.crc_poly_select <= c_crc_poly_17_sel;
                else
                  crc_length            <= c_crc_21_length;
                  crc_o.crc_poly_select <= c_crc_poly_21_sel;
                end if;

                if (v_data_len > 0) then
                  fsm_state <= s_data;
                elsif (llc_frame(c_conf_0_offset)(c_llc_frame_fdf) = '1') then
                  fsm_state <= s_sbc;
                else
                  fsm_state <= s_crc;
                end if;
              else
                bit_count <= bit_count + 1;
              end if;
            end if;

          -- -----------------------------------------------------------
          when s_data =>

            if (v_real_bit) then
              llc_frame(c_data_offset + byte_index)((c_byte_width - 1) - bit_index) <= pcs_i.bus_polarity;

              if (byte_index = data_len - 1 and bit_index = c_byte_width - 1) then
                if (llc_frame(c_conf_0_offset)(c_llc_frame_fdf) = '1') then
                  fsm_state <= s_sbc;
                else
                  fsm_state <= s_crc;
                end if;
                bit_count <= 0;
              else
                bit_index  <= 0 when bit_index = (c_byte_width - 1) else (bit_index + 1);
                byte_index <= (byte_index + 1) when bit_index = (c_byte_width - 1);
              end if;
            end if;

          -- -----------------------------------------------------------
          -- SBC field (ISO 8.5, FD only). FSB mode handled above.
          -- -----------------------------------------------------------
          when s_sbc =>

            if (v_real_bit) then
              if (bit_count = c_sbc_field_width - 1) then
                fsm_state <= s_crc;
                bit_count <= 0;
              else
                bit_count <= bit_count + 1;
              end if;
            end if;

          -- -----------------------------------------------------------
          -- CRC field. FSB mode for FD handled above.
          -- -----------------------------------------------------------
          when s_crc =>

            if (v_real_bit) then
              if (pcs_i.bus_polarity /= crc_i.crc((c_crc_21_length - 1) - bit_count)) then
                crc_mismatch <= '1';
              end if;

              if (bit_count + 1 = crc_length) then
                fsm_state <= s_ack;
                bit_count <= 0;
              else
                bit_count <= bit_count + 1;
              end if;
            end if;

          -- -----------------------------------------------------------
          -- ACK field (ISO 6.6.10.6, 6.6.11.6).
          -- bit_count 0: CRC delimiter, 1: ACK slot, 2: ACK delimiter.
          -- -----------------------------------------------------------
          when s_ack =>

            pcs_o.use_data_rate <= '0';

            if (bit_count = 1) then
              pcs_o.valid    <= '1';
              pcs_o.polarity <= c_dominant;
            end if;

            if (pcs_i.sp = '1') then
              if (bit_count = 0) then
                if (pcs_i.bus_polarity = c_dominant or crc_mismatch = '1') then
                  v_protocol_error := true;
                else
                  pcs_o.valid    <= '1';
                  pcs_o.polarity <= c_dominant;
                  bit_count      <= 1;
                end if;
              elsif (bit_count = 1) then
                bit_count <= 2;
              elsif (bit_count = 2) then
                if (pcs_i.bus_polarity = c_dominant) then
                  v_protocol_error := true;
                else
                  fce_o.successful_transfer <= '1';
                  llc_streaming             <= '1';
                  llc_byte_index            <= 0;
                  llc_frame_len             <= c_data_offset + data_len;
                  fsm_state                 <= s_eof;
                  bit_count                 <= 0;
                end if;
              end if;
            end if;

          -- -----------------------------------------------------------
          -- EOF: 7 recessive bits (ISO 6.6.10.7, 6.6.11.7).
          -- -----------------------------------------------------------
          when s_eof =>

            if (pcs_i.sp = '1') then
              if (pcs_i.bus_polarity = c_dominant) then
                v_protocol_error := true;
              elsif (bit_count = c_eof_field_width - 1) then
                fsm_state <= s_interframe;
                bit_count <= 0;
              else
                bit_count <= bit_count + 1;
              end if;
            end if;

          -- -----------------------------------------------------------
          -- Interframe space: 3 recessive bits (ISO 6.6.7.2).
          -- -----------------------------------------------------------
          when s_interframe =>

            if (pcs_i.sp = '1') then
              if (bit_count = c_intermission_width - 1) then
                bs_rst    <= '1';
                crc_rst   <= '1';
                fsm_state <= s_idle;
                bit_count <= 0;
              elsif (pcs_i.bus_polarity = c_dominant and llc_streaming = '1') then
                fce_o.sending_error_overload_flag <= '1';
                llc_streaming                     <= '0';
                pcs_o.valid                       <= '1';
                pcs_o.polarity <= c_recessive when fce_i.error_passive_request = '1' else c_dominant;
                fsm_state      <= s_error_overload;
                bit_count      <= 0;
              else
                bit_count <= bit_count + 1;
              end if;
            end if;

          -- -----------------------------------------------------------
          -- Error / overload flag (ISO 6.6.5.2, 6.6.5.3).
          -- -----------------------------------------------------------
          when s_error_overload =>

            fce_o.transmitting                <= '1';
            fce_o.sending_error_overload_flag <= '1';
            pcs_o.valid                       <= '1';

            if (bit_count < c_error_flag_width and fce_i.error_passive_request = '0') then
              pcs_o.polarity <= c_dominant;
            else
              pcs_o.polarity <= c_recessive;
            end if;

            if (pcs_i.sp = '1') then
              if (bit_count = c_error_sequence_width - 1) then
                pcs_o.valid <= '0';
                fsm_state   <= s_interframe;
                bit_count   <= 0;
              else
                bit_count <= bit_count + 1;
              end if;
            end if;

          when others =>

            null;

        end case;

        -----------------------------------------------------------------
        -- Stuff error entry (bit reception states)
        -----------------------------------------------------------------
        if (v_stuff_error) then
          fce_o.error         <= '1';
          fce_o.primary_error <= '1';
          fsm_state           <= s_error_overload;
          bit_count           <= 0;
        end if;

        -----------------------------------------------------------------
        -- Protocol error entry (s_ack, s_eof: form error or CRC mismatch)
        -----------------------------------------------------------------
        if (v_protocol_error) then
          fce_o.error         <= '1';
          fce_o.primary_error <= '1';
          pcs_o.valid         <= '1';
          pcs_o.polarity      <= c_recessive when fce_i.error_passive_request = '1' else c_dominant;
          llc_streaming       <= '0';
          fsm_state           <= s_error_overload;
          bit_count           <= 0;
        end if;

      end if;
    end if;

  end process p_fsm;

end architecture rtl;
