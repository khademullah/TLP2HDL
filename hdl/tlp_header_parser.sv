`timescale 1ns/1ps
// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2026 Khadem Ullah
// Parse teaching AXIS-TLP beats (32-bit) into header fields.
// Beat0: type, dir, tag, match_hint
// Beat1: requester, completer
// Beat2: addr[31:0]
// Beat3: payload DWORD  (+ tlast)

module tlp_header_parser (
    input  wire        clk,
    input  wire        rst_n,
    input  wire [31:0] tdata,
    input  wire        tvalid,
    input  wire        tready,
    input  wire        tstart,
    input  wire        tlast,

    output reg         hdr_valid,
    output reg  [7:0]  hdr_type,
    output reg  [7:0]  hdr_dir,
    output reg  [7:0]  hdr_tag,
    output reg  [7:0]  hdr_match_hint,
    output reg  [15:0] hdr_requester,
    output reg  [15:0] hdr_completer,
    output reg  [31:0] hdr_addr,
    output reg  [31:0] hdr_payload,
    output reg         hdr_is_memrd,
    output reg         hdr_is_memwr,
    output reg         hdr_is_cfgrd,
    output reg         hdr_is_cfgwr,
    output reg         hdr_is_cpl,
    output reg         hdr_is_complete,
    output reg         hdr_is_pair
);

    localparam byte TLP_MEM_RD = 8'h00;
    localparam byte TLP_MEM_WR = 8'h01;
    localparam byte TLP_CFG_RD = 8'h04;
    localparam byte TLP_CFG_WR = 8'h05;
    localparam byte TLP_CPL    = 8'h0A;

    reg [1:0] beat;

    wire fire = tvalid && tready;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            beat            <= 2'd0;
            hdr_valid       <= 1'b0;
            hdr_type        <= 8'd0;
            hdr_dir         <= 8'd0;
            hdr_tag         <= 8'd0;
            hdr_match_hint  <= 8'd0;
            hdr_requester   <= 16'd0;
            hdr_completer   <= 16'd0;
            hdr_addr        <= 32'd0;
            hdr_payload     <= 32'd0;
            hdr_is_memrd    <= 1'b0;
            hdr_is_memwr    <= 1'b0;
            hdr_is_cfgrd    <= 1'b0;
            hdr_is_cfgwr    <= 1'b0;
            hdr_is_cpl      <= 1'b0;
            hdr_is_complete <= 1'b0;
            hdr_is_pair     <= 1'b0;
        end else begin
            hdr_valid <= 1'b0;
            if (fire) begin
                if (tstart)
                    beat <= 2'd0;

                case (beat)
                    2'd0: begin
                        hdr_type       <= tdata[7:0];
                        hdr_dir        <= tdata[15:8];
                        hdr_tag        <= tdata[23:16];
                        hdr_match_hint <= tdata[31:24];
                        beat           <= 2'd1;
                    end
                    2'd1: begin
                        hdr_requester <= tdata[15:0];
                        hdr_completer <= tdata[31:16];
                        beat          <= 2'd2;
                    end
                    2'd2: begin
                        hdr_addr <= tdata;
                        beat     <= 2'd3;
                    end
                    2'd3: begin
                        hdr_payload     <= tdata;
                        hdr_is_memrd    <= (hdr_type == TLP_MEM_RD);
                        hdr_is_memwr    <= (hdr_type == TLP_MEM_WR);
                        hdr_is_cfgrd    <= (hdr_type == TLP_CFG_RD);
                        hdr_is_cfgwr    <= (hdr_type == TLP_CFG_WR);
                        hdr_is_cpl      <= (hdr_type == TLP_CPL);
                        hdr_is_complete <= (hdr_match_hint == 8'd1);
                        hdr_is_pair     <= (hdr_match_hint == 8'd2);
                        hdr_valid       <= tlast;
                        beat            <= 2'd0;
                    end
                    default: beat <= 2'd0;
                endcase
            end
        end
    end

endmodule
