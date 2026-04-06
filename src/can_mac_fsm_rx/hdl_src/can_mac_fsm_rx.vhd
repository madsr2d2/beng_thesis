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
--                2026-03-31  TMYAES    Converted to company header format
--                2026-04-05  TMYAES    Remove deser, add LLC byte streaming
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
  -----------------------------------------------------------------
  -- Types
  -----------------------------------------------------------------
  type t_fsm_state is ( s_bus_reintegration, s_idle, s_id, s_rtr_srr_rrs, s_ide, s_fdf_r1_r0, s_res_r0, s_brs, s_esi, s_dlc, s_data, s_sbc, s_crc, s_ack, s_eof, s_interframe, s_error_overload);

  -----------------------------------------------------------------
  -- Signals
  -----------------------------------------------------------------
  signal fsm_state : t_fsm_state;
  signal bit_count     : natural range 0 to c_max_mac_frame_length;
  signal byte_index    : natural range 0 to c_internal_llc_frame_len - 1;
  signal bit_index     : natural range 0 to c_byte_width - 1;
  signal data_len      : natural range 0 to c_max_data_bytes;
  signal crc_length    : natural range 0 to c_crc_21_length;
  signal crc_mismatch  : std_logic;
  signal llc_frame     : t_llc_frame; -- Stores received frame
  signal llc_frame_len : natural range 0 to c_internal_llc_frame_len;
  signal llc_streaming : std_logic; -- When set, the received frame is streamed to the LLC
begin

  p_fsm : process (clk_i) is
    variable v_data_len       : natural;
    variable v_dlc_vec        : std_logic_vector(c_llc_frame_dlc_start downto c_llc_frame_dlc_end);
    variable v_in_dsb_field   : boolean; -- In dynamic stuff bit guard
    variable v_in_fsb_field   : boolean; -- In fixed stuff bit guard
    variable v_real_bit       : boolean; -- Real bit received flag (not stuff bit)
  begin
    if rising_edge(clk_i) then
      if (rst_i = '1') then
        bs_rst         <= '1';
        crc_rst        <= '1';
        bit_count      <= 0;
        byte_index     <= 0;
        bit_index      <= 0;
        data_len       <= 0;
        fsm_state      <= s_bus_reintegration;
        crc_length     <= c_crc_15_length;
        crc_mismatch   <= '0';
        llc_streaming  <= '0';
        llc_frame_len  <= 0;
        llc_frame      <= (others => (others => '0'));
        pcs_o          <= c_mac_to_pcs_if_reset;
        bs_o           <= c_mac_fsm_to_bs_fd_if_reset;
        crc_o          <= c_mac_fsm_to_crc_if_reset;
        fce_o          <= c_mac_to_fce_if_reset;
        llc_o          <= c_mac_rx_to_llc_if_reset;
      else

        -----------------------------------------------------------------
        -- Defaults
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
        -- Evaluate guards
        -----------------------------------------------------------------
        v_in_dsb_field := fsm_state = s_id or fsm_state = s_rtr_srr_rrs or
                              fsm_state = s_ide or fsm_state = s_fdf_r1_r0 or
                              fsm_state = s_res_r0 or fsm_state = s_brs or
                              fsm_state = s_esi or fsm_state = s_dlc or
                              fsm_state = s_data;
        v_in_fsb_field := fsm_state = s_sbc or fsm_state = s_crc;
        v_real_bit := false;

        -----------------------------------------------------------------
        -- Enable fixed stuff bit (FSB) mode for SBC and CRC fields in
        -- FD frames (ISO 11898-1: 6.6.13.3)
        -----------------------------------------------------------------
        if (fsm_state = s_sbc) then
          bs_o.fsb_en <= '1';
        -- Only CC frames use c_crc_15_length
        elsif (fsm_state = s_crc and crc_length /= c_crc_15_length) then
          bs_o.fsb_en <= '1';
        end if;

        -----------------------------------------------------------------
        -- Bit reception: BS/CRC feed, stuff error check.
        -- Applies to all states between SOF and CRC delimiter.
        -----------------------------------------------------------------
        if (pcs_i.sp = '1' and (v_in_dsb_field or v_in_fsb_field)) then
          -- Feed BS
          bs_o.valid <= '1';
          bs_o.data  <= pcs_i.bus_polarity;
          if (bs_i.valid = '1') then
            -- Stuff bit: feed FD CRC in arb region (ISO 11898-1: 6.6.4.4), check polarity
            if (v_in_dsb_field) then
              crc_o.valid_fd <= '1';
              crc_o.data_fd  <= pcs_i.bus_polarity;
            end if;
            if (bs_i.data /= pcs_i.bus_polarity) then
              -- Stuff error (ISO 11898-1: 6.6.5.1)
              -------------------------------------------------------------
              fce_o.error         <= '1';
              fce_o.primary_error <= '1';
              pcs_o.valid         <= '1';
              pcs_o.polarity      <= c_recessive when fce_i.error_passive_request = '1' else c_dominant;
              fsm_state           <= s_error_overload;
              bit_count           <= 0;
              -------------------------------------------------------------
            end if;
          else
            v_real_bit := true;
            -- Real bit CRC feed depends on region
            if (v_in_dsb_field) then
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
        -- Stream frame to LLC
        -----------------------------------------------------------------
        if (llc_streaming = '1') then
          llc_o.avalon_st_source.data  <= llc_frame(byte_index);
          llc_o.avalon_st_source.valid <= '1';

          if (byte_index = 0) then
            llc_o.avalon_st_source.startofpacket <= '1';
          end if;

          if (byte_index = llc_frame_len - 1) then
            llc_o.avalon_st_source.endofpacket <= '1';
          end if;

          if (llc_i.avalon_st_sink.ready = '1') then
            if (byte_index = llc_frame_len - 1) then
              llc_streaming <= '0';
            else
              byte_index <= byte_index + 1;
            end if;
          end if;
        end if;

        -----------------------------------------------------------------
        -- State machine
        -----------------------------------------------------------------
        case fsm_state is

          -----------------------------------------------------------------
          -- s_bus_reintegration : Wait for 11 consecutive recessive bits
          -- before participating on the bus (ISO 11898-1: 6.6.7.5)
          -----------------------------------------------------------------
          when s_bus_reintegration =>
            if (pcs_i.sp = '1') then
              if (pcs_i.bus_polarity = c_recessive) then if (bit_count = c_bus_idle_condition_width - 1) then
                  fsm_state <= s_idle;
                  bit_count <= 0;
                else
                  bit_count <= bit_count + 1;
                end if;
              else
                bit_count <= 0;
              end if;
            end if;

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
                fsm_state <= s_rtr_srr_rrs;
              end if;
            end if;

          -----------------------------------------------------------------
          -- s_rtr_srr_rrs : Sets the frame type bit (Remote or DATA) in 
          -- the LLC frame configuration byte 0
          -----------------------------------------------------------------
          when s_rtr_srr_rrs =>
            if (v_real_bit) then
              llc_frame(c_conf_0_offset)(c_llc_frame_ftyp) <= pcs_i.bus_polarity;
              if (llc_frame(c_conf_0_offset)(c_llc_frame_ide) = '1') then
                fsm_state <= s_fdf_r1_r0;
              else
                fsm_state <= s_ide;
              end if;
            end if;

          -----------------------------------------------------------------
          -- s_ide : Sets the IDE bit ('0' = base ID, '1' = extended ID)
          -----------------------------------------------------------------
          when s_ide =>
            if (v_real_bit) then
              llc_frame(c_conf_0_offset)(c_llc_frame_ide) <= pcs_i.bus_polarity; -- Set IDE bit
              if (pcs_i.bus_polarity = c_recessive) then 
                fsm_state <= s_id; -- Extended ID frame format: Go back to s_id to grab the extended ID bits
              else
                fsm_state <= s_fdf_r1_r0;
              end if;
            end if;

          -----------------------------------------------------------------
          -- s_fdf_r1_r0 : Sets the FDF bit ('0' = CC format, '1' = FD format)
          -----------------------------------------------------------------
          when s_fdf_r1_r0 =>
            if (v_real_bit) then
              llc_frame(c_conf_0_offset)(c_llc_frame_fdf) <= pcs_i.bus_polarity; -- Set FDF bit
              if (pcs_i.bus_polarity = c_recessive or llc_frame(c_conf_0_offset)(c_llc_frame_ide) = '1') then
                -- FDF=1 (FD frame) or CC extended: consume r1 bit
                fsm_state <= s_res_r0;
              else
                -- CC base: consume r0 and go to DLC
                fsm_state <= s_dlc;
                bit_count <= 0;
              end if;
            end if;

          -----------------------------------------------------------------
          -- s_res : Consumes reserved bit(s) in FD or CC extended frames
          -----------------------------------------------------------------
          when s_res_r0 =>
            if (v_real_bit) then
              if (llc_frame(c_conf_0_offset)(c_llc_frame_fdf) = '1') then
                if (pcs_i.bus_polarity = c_dominant) then
                  fsm_state <= s_brs;
                else
                  -- Form error: res bit must be dominant in FD (ISO 11898-1: 6.6.11.3)
                  fce_o.error         <= '1';
                  fce_o.primary_error <= '1';
                  fsm_state           <= s_error_overload;
                  bit_count           <= 0;
                end if;
              else
                -- CC extended frame: Just here to consume the r0 bit
                fsm_state <= s_dlc;
                bit_count <= 0;
              end if;
            end if;

          -----------------------------------------------------------------
          -- s_brs : Sets the BRS bit in the LLC frame and pass the bit to
          -- the PCS.
          -----------------------------------------------------------------
          when s_brs =>
            if (v_real_bit) then
              pcs_o.use_data_rate                         <= pcs_i.bus_polarity;
              llc_frame(c_conf_0_offset)(c_llc_frame_brs) <= pcs_i.bus_polarity;
              fsm_state                                   <= s_esi;
            end if;

          -----------------------------------------------------------------
          -- s_esi : Sets the ESI bit in the LLC frame
          -----------------------------------------------------------------
          when s_esi =>
            if (v_real_bit) then
              llc_frame(c_conf_0_offset)(c_llc_frame_esi) <= pcs_i.bus_polarity;
              fsm_state                                   <= s_dlc;
              bit_count                                   <= 0;
            end if;

          -----------------------------------------------------------------
          -- s_dlc : Sets the DLC field in the LLC frame. When all bits are
          -- received, the data length is calculated and the corresponding CRC 
          -- polynomial is selected.
          -----------------------------------------------------------------
          when s_dlc =>
            if (v_real_bit) then
              -- Store DLC bit and increment bit count
              llc_frame(c_conf_1_offset)(c_llc_frame_dlc_start - bit_count) <= pcs_i.bus_polarity;
              bit_count <= bit_count + 1;
              if (bit_count = c_dlc_field_width - 1) then
                -- Calculate and set data length
                v_dlc_vec := llc_frame(c_conf_1_offset)(c_llc_frame_dlc_start downto c_llc_frame_dlc_end);
                v_dlc_vec(c_llc_frame_dlc_start - bit_count) := pcs_i.bus_polarity;
                v_data_len := dlc_to_data_length(to_integer(unsigned(v_dlc_vec)), llc_frame(c_conf_0_offset)(c_llc_frame_fdf));
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
                  fsm_state <= s_sbc; -- FD format: Go to s_sbc
                else
                  fsm_state <= s_crc; -- CC format: Go to s_crc
                end if;
              else
              end if;
            end if;

          -----------------------------------------------------------------
          -- s_data : Stores received data bits in the LLC frame.
          -----------------------------------------------------------------
          when s_data =>
            if (v_real_bit) then
              -- Store data bit
              llc_frame(c_data_offset + byte_index)((c_byte_width - 1) - bit_index) <= pcs_i.bus_polarity;
              if (byte_index = data_len - 1 and bit_index = c_byte_width - 1) then
              -- Last bit received
                if (llc_frame(c_conf_0_offset)(c_llc_frame_fdf) = '1') then
                  fsm_state <= s_sbc; -- FD format: Go to s_sbc
                else
                  fsm_state <= s_crc; -- CC format: Go to s_crc
                end if;
                bit_count <= 0;
              else
                -- Increment bit/byte index counters
                bit_index  <= 0 when bit_index = (c_byte_width - 1) else (bit_index + 1);
                byte_index <= (byte_index + 1) when bit_index = (c_byte_width - 1);
              end if;
            end if;

          -----------------------------------------------------------------
          -- s_sbc : Receive and verify SBC field (ISO 11898-1: 6.6.11.5).
          -----------------------------------------------------------------
          when s_sbc =>
            if (v_real_bit) then
              if (pcs_i.bus_polarity /= bs_i.sbc((c_sbc_field_width - 1) - bit_count)) then
                -- Form error : SBC mismatch (ISO 11898-1: 6.6.12.3)
                -------------------------------------------------------------
                fce_o.error         <= '1';
                fce_o.primary_error <= '1';
                pcs_o.valid         <= '1';
                pcs_o.polarity      <= c_recessive when fce_i.error_passive_request = '1' else c_dominant;
                fsm_state           <= s_error_overload;
                bit_count           <= 0;
                -------------------------------------------------------------
              elsif (bit_count = c_sbc_field_width - 1) then
                fsm_state <= s_crc;
                bit_count <= 0;
              else
                bit_count <= bit_count + 1;
              end if;
            end if;

          -----------------------------------------------------------------
          -- s_crc : Receive and verify CRC field.
          -- ISO 11898-1: 6.6.10.5, 6.6.11.5
          -----------------------------------------------------------------
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
          -- s_ack : Handle CRC delimiter, ACK slot and ACK delimiter
          -- ISO 11898-1: 6.6.10.6, 6.6.11.6.
          -- bit_count 0: CRC delimiter, 1: ACK slot, 2: ACK delimiter.
          -- -----------------------------------------------------------
          when s_ack =>
            if (pcs_i.sp = '1') then
              if (bit_count = 0) then -- CRC delimiter
                pcs_o.use_data_rate <= '0'; -- exit data rate (ISO 11898-1: 6.6.11.5). 

                if (pcs_i.bus_polarity = c_dominant or crc_mismatch = '1') then
                  -- Form error: CRC delimiter must be recessive, or CRC mismatch (ISO 11898-1: 6.6.5.1)
                  -------------------------------------------------------------
                  fce_o.error         <= '1';
                  fce_o.primary_error <= '1';
                  pcs_o.valid         <= '1';
                  pcs_o.polarity      <= c_recessive when fce_i.error_passive_request = '1' else c_dominant;
                  fsm_state           <= s_error_overload;
                  bit_count           <= 0;
                  -------------------------------------------------------------
                else
                  -- Send ACK bit
                  pcs_o.valid    <= '1';
                  pcs_o.polarity <= c_dominant;
                  bit_count      <= 1;
                end if;
              elsif (bit_count = 1) then -- ACK slot
                bit_count <= 2;
              elsif (bit_count = 2) then -- ACK delimiter
                if (pcs_i.bus_polarity = c_dominant) then
                  -- Form error: ACK delimiter must be recessive (ISO 11898-1: 6.6.5.1)
                  -------------------------------------------------------------
                  fce_o.error         <= '1';
                  fce_o.primary_error <= '1';
                  pcs_o.valid         <= '1';
                  pcs_o.polarity      <= c_recessive when fce_i.error_passive_request = '1' else c_dominant;
                  fsm_state           <= s_error_overload;
                  bit_count           <= 0;
                  -------------------------------------------------------------
                else
                  fsm_state <= s_eof;
                  bit_count <= 0;
                end if;
              end if;
            end if;

          -------------------------------------------------------------
          -- EOF: 7 recessive bits (ISO 11898-1: 6.6.10.7, 6.6.11.7).
          -------------------------------------------------------------
          -- TODO: you are here checking the error logic in this state
          when s_eof =>
            if (pcs_i.sp = '1') then
              if (pcs_i.bus_polarity = c_dominant) then
                -- ISO 6.6.15.2: last EOF bit dominant is overload, not form error
                if (bit_count = c_eof_field_width - 1) then
                  fce_o.sending_error_overload_flag <= '1';
                  fsm_state  <= s_error_overload;
                  bit_count  <= 0;
                else
                  -- Form error: EOF bits must be recessive (ISO 11898-1: 6.6.5.1)
                  -------------------------------------------------------------
                  fce_o.error         <= '1';
                  fce_o.primary_error <= '1';
                  pcs_o.valid         <= '1';
                  pcs_o.polarity      <= c_recessive when fce_i.error_passive_request = '1' else c_dominant;
                  fsm_state           <= s_error_overload;
                  bit_count           <= 0;
                  -------------------------------------------------------------
                end if;
              else
                -- ISO 6.6.15.2: frame valid at last but one bit of EOF
                if (bit_count = c_eof_field_width - 2) then
                  fce_o.successful_transfer <= '1';
                  llc_streaming             <= '1'; -- Start streaming frame to LLC
                  byte_index                <= 0;
                  llc_frame_len             <= c_data_offset + data_len;
                end if;
                if (bit_count = c_eof_field_width - 1) then
                  fsm_state <= s_interframe;
                  bit_count <= 0;
                else
                  bit_count <= bit_count + 1;
                end if;
              end if;
            end if;

          -- -----------------------------------------------------------
          -- Interframe space: 3 recessive bits (ISO 11898-1: 6.6.7.2).
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
          -- Error / overload flag (ISO 11898-1: 6.6.5.2, 6.6.5.3).
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
            fsm_state <= s_bus_reintegration;
        end case;
      end if;
    end if;

  end process p_fsm;

end architecture rtl;
