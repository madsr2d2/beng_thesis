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
    s_idle, s_id, s_format, s_dlc, s_sbc, s_rtr_srr_rrs, s_ide, s_fdf_r1_r0, s_res, s_brs, s_esi,
    s_error_overload, s_data, s_crc, s_ack, s_eof, s_interframe
  );

  signal fsm_state : t_fsm_state;

  signal bit_count  : natural range 0 to c_max_mac_frame_length;
  signal byte_index : natural range 0 to c_internal_llc_frame_len - 1;
  signal bit_index  : natural range 0 to c_byte_width - 1;
  signal data_len   : natural range 0 to c_max_data_bytes;

  signal crc_length   : natural range 0 to c_crc_21_length;
  signal crc_mismatch : std_logic;

  -- synthesis translate_off
  signal dbg_crc_bit_count    : natural := 0;
  signal dbg_crc_fd_bit_count : natural := 0;
  -- synthesis translate_on

  signal llc_frame : t_llc_frame;

  -- LLC byte streaming during quiet phase
  signal llc_streaming  : std_logic;
  signal llc_byte_index : natural range 0 to c_internal_llc_frame_len - 1;
  signal llc_frame_len  : natural range 0 to c_internal_llc_frame_len;

begin

  -- -------------------------------------------------------------------------
  -- Frame reception FSM: tracks frame state, feeds BS/CRC, drives ACK/error.
  -- -------------------------------------------------------------------------
  p_fsm : process (clk_i) is

    variable v_data_len : natural;
    variable v_dlc_vec  : std_logic_vector(c_llc_frame_dlc_start downto c_llc_frame_dlc_end);

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
        -- Defaults cleared each cycle; case branches override as needed
        bs_o.valid          <= '0';
        bs_o.fsb_en         <= '0';
        crc_o.valid_cc         <= '0';
        crc_o.valid_fd      <= '0';
        bs_rst              <= '0';
        crc_rst             <= '0';
        fce_o               <= c_mac_to_fce_if_reset;
        pcs_o.valid         <= '0';
        pcs_o.polarity      <= c_recessive;
        pcs_o.start_tdc     <= '0';
        pcs_o.use_data_rate <= llc_frame(c_conf_0_offset)(c_llc_frame_brs);

        -- LLC streaming defaults (cleared each cycle, set by streaming logic below)
        llc_o.avalon_st_source.valid         <= '0';
        llc_o.avalon_st_source.startofpacket <= '0';
        llc_o.avalon_st_source.endofpacket   <= '0';

        -- -------------------------------------------------------------------
        -- LLC byte streaming: runs during EOF and interframe space.
        -- Transfers one byte per clock cycle when ready is asserted.
        -- -------------------------------------------------------------------
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
            -- Debug: LLC byte trace (disabled for speed)
            if (llc_byte_index = llc_frame_len - 1) then
              llc_streaming <= '0';
            else
              llc_byte_index <= llc_byte_index + 1;
            end if;
          end if;
        end if;

        -- Debug: per-SP bit trace (disabled for speed)
        -- if (pcs_i.sp = '1' and (fsm_state = s_sbc or fsm_state = s_crc)) then
        --   report "BIT bus=" & to_string(pcs_i.bus_polarity) &
        --     " bs_valid=" & to_string(bs_i.valid) &
        --     " bs_data=" & to_string(bs_i.data) &
        --     " bc=" & integer'image(bit_count) &
        --     " state=" & to_string(fsm_state);
        -- end if;

        case fsm_state is

          -- -----------------------------------------------------------------
          when s_idle =>

            pcs_o.use_data_rate <= '0';
            crc_mismatch        <= '0';
            if (pcs_i.sp = '1' and pcs_i.bus_polarity = c_dominant) then
              -- SOF detected: feed BS and CRC with SOF bit
              crc_o.valid_cc    <= '1';
              crc_o.valid_fd <= '1';
              crc_o.data_cc  <= c_dominant;
              crc_o.data_fd  <= c_dominant;
              bs_o.valid    <= '1';
              bs_o.data     <= c_dominant;
              bit_count     <= 0;
              byte_index    <= 0;
              bit_index     <= 0;
              llc_frame     <= (others => (others => '0'));
              fsm_state     <= s_id;
            end if;

          when s_id =>

            if (pcs_i.sp = '1') then
              bs_o.valid  <= '1';

              if (bs_i.valid = '1') then
                -- Stuff bit: feed FD CRC only (CC CRC excludes stuff bits)
                crc_o.valid_fd <= '1';
                crc_o.data_fd  <= pcs_i.bus_polarity;
                bs_o.data      <= pcs_i.bus_polarity;
              else
                -- Fill ID field in LLC frame
                llc_frame(c_id_offset + byte_index)((c_byte_width - 1) - bit_index) <= pcs_i.bus_polarity;

                crc_o.valid_cc    <= '1';
                crc_o.valid_fd <= '1';
                crc_o.data_cc  <= pcs_i.bus_polarity;
                crc_o.data_fd  <= pcs_i.bus_polarity;
                bs_o.data      <= pcs_i.bus_polarity;

                -- Always advance counters
                bit_index  <= 0 when bit_index = (c_byte_width - 1) else (bit_index + 1);
                byte_index <= (byte_index + 1) when bit_index = (c_byte_width - 1);
                bit_count  <= (bit_count + 1);

                if (bit_count = (c_base_id_width - 1) or
                    bit_count = (c_base_id_width + c_extended_id_width - 1)) then
                  fsm_state <= s_rtr_srr_rrs;
                end if;
              end if;
            end if;

          when s_rtr_srr_rrs =>

            if (pcs_i.sp = '1') then
              bs_o.valid  <= '1';

              if (bs_i.valid = '1') then
                crc_o.valid_fd <= '1';
                crc_o.data_fd  <= pcs_i.bus_polarity;
                bs_o.data      <= pcs_i.bus_polarity;
                -- Stuff error detected
                if (bs_i.data /= pcs_i.bus_polarity) then
                  fce_o.error         <= '1';
                  fce_o.primary_error <= '1';
                  fsm_state           <= s_error_overload;
                  bit_count           <= 0;
                end if;
              else
                -- Set the FTYP bit in LLC frame configuration byte 0
                llc_frame(c_conf_0_offset)(c_llc_frame_ftyp) <= pcs_i.bus_polarity;

                crc_o.valid_cc    <= '1';
                crc_o.valid_fd <= '1';
                crc_o.data_cc  <= pcs_i.bus_polarity;
                crc_o.data_fd  <= pcs_i.bus_polarity;
                bs_o.data      <= pcs_i.bus_polarity;

                -- State transition
                if (llc_frame(c_conf_0_offset)(c_llc_frame_ide) = '1') then
                  fsm_state <= s_fdf_r1_r0;
                else
                  fsm_state <= s_ide;
                end if;
              end if;
            end if;

          when s_ide =>

            if (pcs_i.sp = '1') then
              bs_o.valid  <= '1';
              if (bs_i.valid = '1') then
                crc_o.valid_fd <= '1';
                crc_o.data_fd  <= pcs_i.bus_polarity;
                bs_o.data      <= pcs_i.bus_polarity;
                if (bs_i.data /= pcs_i.bus_polarity) then
                  fce_o.error         <= '1';
                  fce_o.primary_error <= '1';
                  fsm_state           <= s_error_overload;
                  bit_count           <= 0;
                end if;
              else
                -- Set the IDE bit in LLC frame configuration byte 0
                llc_frame(c_conf_0_offset)(c_llc_frame_ide) <= pcs_i.bus_polarity;
                crc_o.valid_cc                                 <= '1';
                crc_o.valid_fd                              <= '1';
                crc_o.data_cc                               <= pcs_i.bus_polarity;
                crc_o.data_fd                               <= pcs_i.bus_polarity;
                bs_o.data                                   <= pcs_i.bus_polarity;

                if (pcs_i.bus_polarity = c_recessive) then
                  -- IDE=1: extended frame, receive 18-bit extended ID next
                  fsm_state <= s_id;
                else
                  -- IDE=0: basic frame, next bit is FDF/r0
                  fsm_state <= s_fdf_r1_r0;
                end if;
              end if;
            end if;

          when s_fdf_r1_r0 =>

            if (pcs_i.sp = '1') then
              bs_o.valid  <= '1';
              if (bs_i.valid = '1') then
                crc_o.valid_fd <= '1';
                crc_o.data_fd  <= pcs_i.bus_polarity;
                bs_o.data      <= pcs_i.bus_polarity;
                if (bs_i.data /= pcs_i.bus_polarity) then
                  fce_o.error         <= '1';
                  fce_o.primary_error <= '1';
                  fsm_state           <= s_error_overload;
                  bit_count           <= 0;
                end if;
              else
                -- Set the FDF bit in LLC frame configuration byte 0
                llc_frame(c_conf_0_offset)(c_llc_frame_fdf) <= pcs_i.bus_polarity;
                crc_o.valid_cc                                 <= '1';
                crc_o.valid_fd                              <= '1';
                crc_o.data_cc                               <= pcs_i.bus_polarity;
                crc_o.data_fd                               <= pcs_i.bus_polarity;
                bs_o.data                                   <= pcs_i.bus_polarity;
                -- State transition
                if (pcs_i.bus_polarity = c_recessive) then
                  -- FDF=1: FD frame, next is reserved bit (s_res)
                  fsm_state <= s_res;
                elsif (llc_frame(c_conf_0_offset)(c_llc_frame_ide) = '1' and
                       bit_count < c_base_id_width + c_extended_id_width) then
                  -- Extended frame, first pass: return to s_id for 18-bit extended ID
                  fsm_state <= s_id;
                elsif (llc_frame(c_conf_0_offset)(c_llc_frame_ide) = '1') then
                  -- CC extended, second pass: consume r0 via s_res
                  fsm_state <= s_res;
                else
                  -- CC basic: go directly to DLC
                  fsm_state <= s_dlc;
                  bit_count <= 0;
                end if;
              end if;
            end if;

          when s_res =>

            if (pcs_i.sp = '1') then
              bs_o.valid  <= '1';
              if (bs_i.valid = '1') then
                crc_o.valid_fd <= '1';
                crc_o.data_fd  <= pcs_i.bus_polarity;
                bs_o.data      <= pcs_i.bus_polarity;
                if (bs_i.data /= pcs_i.bus_polarity) then
                  fce_o.error         <= '1';
                  fce_o.primary_error <= '1';
                  fsm_state           <= s_error_overload;
                  bit_count           <= 0;
                end if;
              else
                crc_o.valid_cc    <= '1';
                crc_o.valid_fd <= '1';
                crc_o.data_cc  <= pcs_i.bus_polarity;
                crc_o.data_fd  <= pcs_i.bus_polarity;
                bs_o.data      <= pcs_i.bus_polarity;
                if (llc_frame(c_conf_0_offset)(c_llc_frame_fdf) = '1') then
                  -- FD frame: reserved bit, then BRS
                  if (pcs_i.bus_polarity = c_dominant) then
                    fsm_state <= s_brs;
                  else
                    fsm_state <= s_error_overload;
                  end if;
                else
                  -- CC extended: r0 consumed, go to DLC
                  fsm_state <= s_dlc;
                  bit_count <= 0;
                end if;
              end if;
            end if;

          when s_brs =>

            if (pcs_i.sp = '1') then
              bs_o.valid  <= '1';
              if (bs_i.valid = '1') then
                crc_o.valid_fd <= '1';
                crc_o.data_fd  <= pcs_i.bus_polarity;
                bs_o.data      <= pcs_i.bus_polarity;
                if (bs_i.data /= pcs_i.bus_polarity) then
                  fce_o.error         <= '1';
                  fce_o.primary_error <= '1';
                  fsm_state           <= s_error_overload;
                  bit_count           <= 0;
                end if;
              else
                pcs_o.use_data_rate                         <= pcs_i.bus_polarity;
                llc_frame(c_conf_0_offset)(c_llc_frame_brs) <= pcs_i.bus_polarity;
                crc_o.valid_cc                                 <= '1';
                crc_o.valid_fd                              <= '1';
                crc_o.data_cc                               <= pcs_i.bus_polarity;
                crc_o.data_fd                               <= pcs_i.bus_polarity;
                bs_o.data                                   <= pcs_i.bus_polarity;
                fsm_state                                   <= s_esi;
              end if;
            end if;

          when s_esi =>

            if (pcs_i.sp = '1') then
              bs_o.valid  <= '1';
              if (bs_i.valid = '1') then
                crc_o.valid_fd <= '1';
                crc_o.data_fd  <= pcs_i.bus_polarity;
                bs_o.data      <= pcs_i.bus_polarity;
                if (bs_i.data /= pcs_i.bus_polarity) then
                  fce_o.error         <= '1';
                  fce_o.primary_error <= '1';
                  fsm_state           <= s_error_overload;
                  bit_count           <= 0;
                end if;
              else
                llc_frame(c_conf_0_offset)(c_llc_frame_esi) <= pcs_i.bus_polarity;
                crc_o.valid_cc                                 <= '1';
                crc_o.valid_fd                              <= '1';
                crc_o.data_cc                               <= pcs_i.bus_polarity;
                crc_o.data_fd                               <= pcs_i.bus_polarity;
                bs_o.data                                   <= pcs_i.bus_polarity;
                fsm_state                                   <= s_dlc;
                bit_count                                   <= 0;
              end if;
            end if;

          when s_dlc =>

            if (pcs_i.sp = '1') then
              bs_o.valid  <= '1';
              if (bs_i.valid = '1') then
                crc_o.valid_fd <= '1';
                crc_o.data_fd  <= pcs_i.bus_polarity;
                bs_o.data      <= pcs_i.bus_polarity;
                if (bs_i.data /= pcs_i.bus_polarity) then
                  fce_o.error         <= '1';
                  fce_o.primary_error <= '1';
                  fsm_state           <= s_error_overload;
                  bit_count           <= 0;
                end if;
              else
                -- Set DLC bits in LLC frame config byte 1
                llc_frame(c_conf_1_offset)(c_llc_frame_dlc_start - bit_count) <= pcs_i.bus_polarity;
                crc_o.valid_cc                                                   <= '1';
                crc_o.valid_fd                                                <= '1';
                crc_o.data_cc                                                 <= pcs_i.bus_polarity;
                crc_o.data_fd                                                 <= pcs_i.bus_polarity;
                bs_o.data                                                     <= pcs_i.bus_polarity;

                if (bit_count = c_dlc_field_width - 1) then
                  -- Build complete DLC vector including current bit (signal not yet updated)
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

                  -- Select CRC polynomial for this frame
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

                  -- Determine next state
                  if (v_data_len > 0) then
                    fsm_state <= s_data;
                  else
                    if (llc_frame(c_conf_0_offset)(c_llc_frame_fdf) = '1') then
                      fsm_state <= s_sbc;
                    else
                      fsm_state <= s_crc;
                    end if;
                  end if;
                else
                  bit_count <= bit_count + 1;
                end if;
              end if;
            end if;

          -- -----------------------------------------------------------------
          when s_data =>

            if (pcs_i.sp = '1') then
              bs_o.valid  <= '1';
              if (bs_i.valid = '1') then
                crc_o.valid_fd <= '1';
                crc_o.data_fd  <= pcs_i.bus_polarity;
                bs_o.data      <= pcs_i.bus_polarity;
                if (bs_i.data /= pcs_i.bus_polarity) then
                  fce_o.error         <= '1';
                  fce_o.primary_error <= '1';
                  fsm_state           <= s_error_overload;
                  bit_count           <= 0;
                end if;
              else
                -- Fill data field in LLC frame
                llc_frame(c_data_offset + byte_index)((c_byte_width - 1) - bit_index) <= pcs_i.bus_polarity;

                crc_o.valid_cc    <= '1';
                crc_o.valid_fd <= '1';
                crc_o.data_cc  <= pcs_i.bus_polarity;
                crc_o.data_fd  <= pcs_i.bus_polarity;
                bs_o.data      <= pcs_i.bus_polarity;

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
            end if;

          -- -----------------------------------------------------------------
          -- SBC field (ISO 11898-1 Sec. 8.5, FD frames only).
          -- Fixed stuffing active: one FSB before the field (scheduled by the
          -- BS module on the rising edge of fsb_en), then one FSB after every
          -- 4 real SBC bits. FSBs are form-checked but not fed to the CRC.
          -- -----------------------------------------------------------------
          when s_sbc =>

            bs_o.fsb_en <= '1';

            if (pcs_i.sp = '1') then
              bs_o.valid <= '1';
              bs_o.data  <= pcs_i.bus_polarity;

              if (bs_i.valid = '1') then
                -- Stuff bit in SBC region: form-check polarity.
                -- Note: dynamic stuff bits at the DLC/SBC boundary are
                -- absorbed by BS on the fsb_en rising edge, so their
                -- polarity is already accounted for in the initial FSB.
                if (bs_i.data /= pcs_i.bus_polarity) then
                  fce_o.error         <= '1';
                  fce_o.primary_error <= '1';
                  fsm_state           <= s_error_overload;
                  bit_count           <= 0;
                end if;
              else
                -- Real SBC bit: feed to FD CRC only (SBC is covered by CRC)
                crc_o.valid_fd <= '1';
                crc_o.data_fd  <= pcs_i.bus_polarity;

                if (bit_count = c_sbc_field_width - 1) then
                  fsm_state <= s_crc;
                  bit_count <= 0;
                else
                  bit_count <= bit_count + 1;
                end if;
              end if;
            end if;

          -- -----------------------------------------------------------------
          -- CRC field reception.
          -- -----------------------------------------------------------------
          when s_crc =>

            -- Debug: CRC check trace (disabled for speed)
            -- synthesis translate_off
            -- if (bit_count = 0 and pcs_i.sp = '1' and bs_i.valid = '0') then
            --   report "CRC CHECK: crc_i.crc=" & to_hstring(crc_i.crc)
            --     & " crc_length=" & integer'image(crc_length)
            --     & " dbg_cc_bits=" & integer'image(dbg_crc_bit_count)
            --     & " dbg_fd_bits=" & integer'image(dbg_crc_fd_bit_count);
            -- end if;
            -- synthesis translate_on

            -- FD frames use fixed stuffing in the CRC field
            if (crc_length /= c_crc_15_length) then
              bs_o.fsb_en <= '1';
            end if;

            if (pcs_i.sp = '1') then
              bs_o.valid <= '1';
              bs_o.data  <= pcs_i.bus_polarity;

              if (bs_i.valid = '1') then
                -- Fixed stuff bit (FD only): polarity must match BS expectation
                if (bs_i.data /= pcs_i.bus_polarity) then
                  fce_o.error         <= '1';
                  fce_o.primary_error <= '1';
                  fsm_state           <= s_error_overload;
                  bit_count           <= 0;
                end if;
              else
                -- Real CRC bit: compare MSB-first against left-aligned computed CRC
                -- synthesis translate_off
                -- report "CRC BIT " & integer'image(bit_count) & ": bus=" & to_string(pcs_i.bus_polarity)
                --   & " exp=" & to_string(crc_i.crc((c_crc_21_length - 1) - bit_count))
                --   & " crc=" & to_hstring(crc_i.crc);
                -- synthesis translate_on
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
            end if;

          -- -----------------------------------------------------------------
          -- ACK field (ISO 6.6.10.6, 6.6.11.6).
          -- bit_count=0: CRC delimiter (check form error and CRC residual)
          -- bit_count=1: ACK slot (drive dominant continuously until sp)
          -- bit_count=2: ACK delimiter (check form error, signal success)
          -- -----------------------------------------------------------------
          when s_ack =>

            pcs_o.use_data_rate <= '0';

            -- Maintain dominant throughout the ACK slot bit time
            if (bit_count = 1) then
              pcs_o.valid    <= '1';
              pcs_o.polarity <= c_dominant;
            end if;

            if (pcs_i.sp = '1') then
              if (bit_count = 0) then
                if (pcs_i.bus_polarity = c_dominant) then
                  fce_o.error         <= '1';
                  fce_o.primary_error <= '1';
                  if (fce_i.error_passive_request = '1') then
                    pcs_o.polarity <= c_recessive;
                  else
                    pcs_o.polarity <= c_dominant;
                  end if;
                  pcs_o.valid <= '1';
                  fsm_state   <= s_error_overload;
                  bit_count   <= 0;
                elsif (crc_mismatch = '1') then
                  fce_o.error         <= '1';
                  fce_o.primary_error <= '1';
                  if (fce_i.error_passive_request = '1') then
                    pcs_o.polarity <= c_recessive;
                  else
                    pcs_o.polarity <= c_dominant;
                  end if;
                  pcs_o.valid <= '1';
                  fsm_state   <= s_error_overload;
                  bit_count   <= 0;
                else
                  pcs_o.valid    <= '1';
                  pcs_o.polarity <= c_dominant;
                  bit_count      <= 1;
                end if;
              elsif (bit_count = 1) then
                bit_count <= 2;
              elsif (bit_count = 2) then
                if (pcs_i.bus_polarity = c_dominant) then
                  fce_o.error         <= '1';
                  fce_o.primary_error <= '1';
                  if (fce_i.error_passive_request = '1') then
                    pcs_o.polarity <= c_recessive;
                  else
                    pcs_o.polarity <= c_dominant;
                  end if;
                  pcs_o.valid <= '1';
                  fsm_state   <= s_error_overload;
                  bit_count   <= 0;
                else
                  -- Frame accepted: start LLC streaming and enter EOF
                  fce_o.successful_transfer <= '1';
                  llc_streaming             <= '1';
                  llc_byte_index            <= 0;
                  llc_frame_len             <= c_data_offset + data_len;
                  fsm_state                 <= s_eof;
                  bit_count                 <= 0;
                end if;
              end if;
            end if;

          -- -----------------------------------------------------------------
          -- EOF: 7 consecutive recessive bits (ISO 6.6.10.7, 6.6.11.7).
          -- LLC streaming runs concurrently (above the case statement).
          -- -----------------------------------------------------------------
          when s_eof =>

            if (pcs_i.sp = '1') then
              if (pcs_i.bus_polarity = c_dominant) then
                fce_o.error         <= '1';
                fce_o.primary_error <= '1';
                if (fce_i.error_passive_request = '1') then
                  pcs_o.polarity <= c_recessive;
                else
                  pcs_o.polarity <= c_dominant;
                end if;
                pcs_o.valid   <= '1';
                llc_streaming <= '0';
                fsm_state     <= s_error_overload;
                bit_count     <= 0;
              elsif (bit_count = c_eof_field_width - 1) then
                fsm_state <= s_interframe;
                bit_count <= 0;
              else
                bit_count <= bit_count + 1;
              end if;
            end if;

          -- -----------------------------------------------------------------
          -- Interframe space: 3 recessive bits (ISO 6.6.7.2).
          -- LLC streaming may still be in progress. If a dominant bit (SOF)
          -- arrives before the LLC transfer completes, signal overload.
          -- -----------------------------------------------------------------
          when s_interframe =>

            if (pcs_i.sp = '1') then
              if (bit_count = c_intermission_width - 1) then
                bs_rst    <= '1';
                crc_rst   <= '1';
                fsm_state <= s_idle;
                bit_count <= 0;
              elsif (pcs_i.bus_polarity = c_dominant and llc_streaming = '1') then
                -- Overload: SOF arrived before LLC transfer completed
                fce_o.sending_error_overload_flag <= '1';
                llc_streaming                     <= '0';
                pcs_o.valid                       <= '1';
                if (fce_i.error_passive_request = '1') then
                  pcs_o.polarity <= c_recessive;
                else
                  pcs_o.polarity <= c_dominant;
                end if;
                fsm_state <= s_error_overload;
                bit_count <= 0;
              else
                bit_count <= bit_count + 1;
              end if;
            end if;

          -- -----------------------------------------------------------------
          -- Error / overload flag (ISO 6.6.5.2, 6.6.5.3).
          -- Active error:  6 dominant + 8 recessive delimiter = 14 bits total.
          -- Passive error: 6 recessive + 8 recessive delimiter = 14 bits total.
          -- -----------------------------------------------------------------
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

      end if;
    end if;

  end process p_fsm;

  -- synthesis translate_off
  p_debug : process (clk_i) is
    variable v_prev_state : t_fsm_state := s_idle;
  begin
    if rising_edge(clk_i) then
      if (fsm_state /= v_prev_state) then
        report "RX FSM: " & t_fsm_state'image(v_prev_state) & " -> " & t_fsm_state'image(fsm_state)
          & " bit_count=" & integer'image(bit_count)
          & " crc_mismatch=" & std_logic'image(crc_mismatch);
        v_prev_state := fsm_state;
      end if;
    end if;
  end process p_debug;
  -- synthesis translate_on

end architecture rtl;
