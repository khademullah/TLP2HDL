`timescale 1ns/1ps
// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2026 Khadem Ullah
// Match tracker: QEMU one-line cfg → complete; MemRd opens; Cpl closes.
// Mirrors pcieshark Match semantics for the teaching AXIS-TLP stream.

module tlp_match_tracker (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        hdr_valid,
    input  wire        hdr_is_cfgrd,
    input  wire        hdr_is_cfgwr,
    input  wire        hdr_is_cpl,
    input  wire        hdr_is_complete,
    input  wire [7:0]  hdr_tag,
    input  wire [15:0] hdr_requester,

    output reg  [31:0] cnt_cfgrd,
    output reg  [31:0] cnt_cfgwr,
    output reg  [31:0] cnt_cpl,
    output reg  [31:0] cnt_complete,
    output reg  [31:0] cnt_open,
    output reg  [31:0] cnt_matched,
    output reg  [31:0] cnt_unmatched
);

    localparam int DEPTH = 16;
    reg        slot_valid [0:DEPTH-1];
    reg [7:0]  slot_tag   [0:DEPTH-1];
    reg [15:0] slot_req   [0:DEPTH-1];
    integer i;
    integer free_i;
    integer hit_i;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            cnt_cfgrd     <= 32'd0;
            cnt_cfgwr     <= 32'd0;
            cnt_cpl       <= 32'd0;
            cnt_complete  <= 32'd0;
            cnt_open      <= 32'd0;
            cnt_matched   <= 32'd0;
            cnt_unmatched <= 32'd0;
            for (i = 0; i < DEPTH; i = i + 1) begin
                slot_valid[i] <= 1'b0;
                slot_tag[i]   <= 8'd0;
                slot_req[i]   <= 16'd0;
            end
        end else if (hdr_valid) begin
            if (hdr_is_cfgrd) begin
                cnt_cfgrd <= cnt_cfgrd + 1'b1;
                if (hdr_is_complete)
                    cnt_complete <= cnt_complete + 1'b1;
            end
            if (hdr_is_cfgwr) begin
                cnt_cfgwr <= cnt_cfgwr + 1'b1;
                if (hdr_is_complete)
                    cnt_complete <= cnt_complete + 1'b1;
            end
            if (hdr_is_cpl) begin
                cnt_cpl <= cnt_cpl + 1'b1;
                hit_i = -1;
                for (i = 0; i < DEPTH; i = i + 1) begin
                    if (slot_valid[i] && slot_tag[i] == hdr_tag && slot_req[i] == hdr_requester)
                        hit_i = i;
                end
                if (hit_i >= 0) begin
                    slot_valid[hit_i] <= 1'b0;
                    cnt_matched <= cnt_matched + 1'b1;
                    if (cnt_open != 0)
                        cnt_open <= cnt_open - 1'b1;
                end else begin
                    cnt_unmatched <= cnt_unmatched + 1'b1;
                end
            end
            // Non-complete reads that need a later Cpl (teaching MemRd path)
            if (!hdr_is_cfgrd && !hdr_is_cfgwr && !hdr_is_cpl && !hdr_is_complete) begin
                free_i = -1;
                for (i = 0; i < DEPTH; i = i + 1)
                    if (!slot_valid[i] && free_i < 0)
                        free_i = i;
                if (free_i >= 0) begin
                    slot_valid[free_i] <= 1'b1;
                    slot_tag[free_i]   <= hdr_tag;
                    slot_req[free_i]   <= hdr_requester;
                    cnt_open           <= cnt_open + 1'b1;
                end
            end
        end
    end

endmodule
