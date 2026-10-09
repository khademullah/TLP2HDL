`timescale 1ns/1ps
// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2026 Khadem Ullah
//
// Teaching PCIe endpoint DUT (config-space slave) — not a NIC/PHY.
// On CfgWr to dut_bdf: update 256-byte cfg image.
// On PAIR CfgRd to dut_bdf: emit teaching-AXIS Cpl (4 beats).
// On COMPLETE CfgRd: seed cfg image from capture payload.

module tlp_cfg_dut (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        enable,
    input  wire [15:0] dut_bdf,

    input  wire        hdr_valid,
    input  wire        hdr_is_cfgrd,
    input  wire        hdr_is_cfgwr,
    input  wire        hdr_is_pair,
    input  wire        hdr_is_complete,
    input  wire [7:0]  hdr_tag,
    input  wire [15:0] hdr_requester,
    input  wire [15:0] hdr_completer,
    input  wire [31:0] hdr_addr,
    input  wire [31:0] hdr_payload,

    output reg  [31:0] m_tdata,
    output reg         m_tvalid,
    input  wire        m_tready,
    output reg         m_tstart,
    output reg         m_tlast,
    output wire        m_busy,

    output reg  [31:0] cnt_hit_rd,
    output reg  [31:0] cnt_hit_wr,
    output reg  [31:0] cnt_cpl_tx,
    output reg  [31:0] cnt_seed
);

    localparam byte TLP_CPL    = 8'h0A;
    localparam byte DIR_RX     = 8'h02;
    localparam byte MATCH_NONE = 8'h00;
    localparam int  CFG_DWORDS = 64;

    localparam [15:0] DEF_VENDOR  = 16'h1b36;
    localparam [15:0] DEF_DEVICE  = 16'h000c;
    localparam [31:0] DEF_BAR0_SZ = 32'hffff_f000;

    reg [31:0] cfg [0:CFG_DWORDS-1];

    wire        hit    = enable && hdr_valid && (hdr_completer == dut_bdf);
    wire [31:0] dw_idx = {26'd0, hdr_addr[7:2]};

    reg        pend_valid;
    reg [7:0]  pend_tag;
    reg [15:0] pend_req;
    reg [31:0] pend_data;
    reg [31:0] pend_addr;

    reg [2:0]  emit_state; // 0 idle, 1-4 = beats left to issue (4..1)

    assign m_busy = pend_valid || (emit_state != 3'd0) || m_tvalid;

    integer i;

    function automatic [31:0] bar_write(input [31:0] oldv, input [31:0] wr, input [31:0] szmask);
        if (wr == 32'hffff_ffff)
            bar_write = szmask;
        else
            bar_write = (wr & ~32'hF) | (oldv & 32'hF);
    endfunction

    function automatic [31:0] beat_data(input [1:0] b);
        case (b)
            2'd0: beat_data = {MATCH_NONE, pend_tag, DIR_RX, TLP_CPL};
            2'd1: beat_data = {dut_bdf, pend_req};
            2'd2: beat_data = pend_addr;
            2'd3: beat_data = pend_data;
            default: beat_data = 32'd0;
        endcase
    endfunction

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (i = 0; i < CFG_DWORDS; i = i + 1)
                cfg[i] <= 32'd0;
            cfg[0]      <= {DEF_DEVICE, DEF_VENDOR};
            cfg[1]      <= 32'h0010_0000;
            cfg[2]      <= 32'h0200_0000;
            cfg[11]     <= 32'h0000_0040;
            cnt_hit_rd  <= 32'd0;
            cnt_hit_wr  <= 32'd0;
            cnt_cpl_tx  <= 32'd0;
            cnt_seed    <= 32'd0;
            pend_valid  <= 1'b0;
            emit_state  <= 3'd0;
            m_tdata     <= 32'd0;
            m_tvalid    <= 1'b0;
            m_tstart    <= 1'b0;
            m_tlast     <= 1'b0;
            pend_tag    <= 8'd0;
            pend_req    <= 16'd0;
            pend_data   <= 32'd0;
            pend_addr   <= 32'd0;
        end else begin
            if (hit && hdr_is_cfgwr) begin
                cnt_hit_wr <= cnt_hit_wr + 1'b1;
                case (hdr_addr[7:0])
                    8'h04: cfg[1] <= hdr_payload;
                    8'h10: cfg[4] <= bar_write(cfg[4], hdr_payload, DEF_BAR0_SZ);
                    8'h14: cfg[5] <= bar_write(cfg[5], hdr_payload, 32'hffff_ffff);
                    8'h18: cfg[6] <= bar_write(cfg[6], hdr_payload, 32'hffff_ffff);
                    8'h1c: cfg[7] <= bar_write(cfg[7], hdr_payload, 32'hffff_ffff);
                    8'h20: cfg[8] <= bar_write(cfg[8], hdr_payload, 32'hffff_ffff);
                    8'h24: cfg[9] <= bar_write(cfg[9], hdr_payload, 32'hffff_ffff);
                    default: if (dw_idx < CFG_DWORDS)
                        cfg[dw_idx] <= hdr_payload;
                endcase
            end

            if (hit && hdr_is_cfgrd && hdr_is_complete) begin
                cnt_seed <= cnt_seed + 1'b1;
                if (dw_idx < CFG_DWORDS)
                    cfg[dw_idx] <= hdr_payload;
            end

            if (hit && hdr_is_cfgrd && hdr_is_pair && !pend_valid && emit_state == 3'd0 && !m_tvalid) begin
                cnt_hit_rd <= cnt_hit_rd + 1'b1;
                pend_valid <= 1'b1;
                pend_tag   <= hdr_tag;
                pend_req   <= hdr_requester;
                pend_addr  <= hdr_addr;
                pend_data  <= (dw_idx < CFG_DWORDS) ? cfg[dw_idx] : 32'd0;
            end

            // Complete current beat handshake
            if (m_tvalid && m_tready) begin
                m_tvalid <= 1'b0;
                m_tstart <= 1'b0;
                m_tlast  <= 1'b0;
                if (emit_state == 3'd1) begin
                    emit_state <= 3'd0;
                    cnt_cpl_tx <= cnt_cpl_tx + 1'b1;
                end else if (emit_state != 3'd0) begin
                    emit_state <= emit_state - 3'd1;
                end
            end

            // Launch or continue beats when bus free
            if (!m_tvalid) begin
                if (emit_state == 3'd0 && pend_valid) begin
                    pend_valid <= 1'b0;
                    emit_state <= 3'd4;
                    m_tvalid   <= 1'b1;
                    m_tstart   <= 1'b1;
                    m_tlast    <= 1'b0;
                    m_tdata    <= beat_data(2'd0);
                end else if (emit_state == 3'd3) begin
                    m_tvalid <= 1'b1;
                    m_tstart <= 1'b0;
                    m_tlast  <= 1'b0;
                    m_tdata  <= beat_data(2'd1);
                end else if (emit_state == 3'd2) begin
                    m_tvalid <= 1'b1;
                    m_tstart <= 1'b0;
                    m_tlast  <= 1'b0;
                    m_tdata  <= beat_data(2'd2);
                end else if (emit_state == 3'd1) begin
                    m_tvalid <= 1'b1;
                    m_tstart <= 1'b0;
                    m_tlast  <= 1'b1;
                    m_tdata  <= beat_data(2'd3);
                end
            end
        end
    end

endmodule
