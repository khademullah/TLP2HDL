`timescale 1ns/1ps
// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2026 Khadem Ullah
//
// Multi-BDF teaching fabric: up to N config-space endpoints on one AXIS.
// Muxes DUT Cpl beats; aggregates hit/cpl counters. Single-BDF is N=1.

module tlp_cfg_fabric #(
    parameter int N = 8
) (
    input  wire        clk,
    input  wire        rst_n,

    input  wire [N-1:0]    ep_enable,
    input  wire [16*N-1:0] ep_bdf_pack, // {bdf[N-1], …, bdf[0]}

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

    output wire [31:0] m_tdata,
    output wire        m_tvalid,
    input  wire        m_tready,
    output wire        m_tstart,
    output wire        m_tlast,
    output wire        m_busy,

    // Muxed decode of the EP matching hdr_completer (for logs)
    output wire [15:0] hit_bdf,
    output wire        hit_any,
    output wire [15:0] hit_vendor_id,
    output wire [15:0] hit_device_id,
    output wire [15:0] hit_command,
    output wire [15:0] hit_status,
    output wire [7:0]  hit_revision_id,
    output wire [7:0]  hit_prog_if,
    output wire [7:0]  hit_subclass,
    output wire [7:0]  hit_class_code,
    output wire [7:0]  hit_header_type,
    output wire [31:0] hit_bar0,
    output wire [31:0] hit_bar1,
    output wire [15:0] hit_subsys_ven,
    output wire [15:0] hit_subsys_id,
    output wire [7:0]  hit_cap_ptr,
    output wire [7:0]  hit_int_line,
    output wire [7:0]  hit_int_pin,
    output wire        hit_cmd_io,
    output wire        hit_cmd_mem,
    output wire        hit_cmd_bme,

    output wire [31:0] cnt_hit_rd,
    output wire [31:0] cnt_hit_wr,
    output wire [31:0] cnt_cpl_tx,
    output wire [31:0] cnt_seed,
    output wire [3:0]  ep_count
);

    wire [15:0] ep_bdf      [0:N-1];
    wire [31:0] ep_tdata    [0:N-1];
    wire        ep_tvalid   [0:N-1];
    wire        ep_tready   [0:N-1];
    wire        ep_tstart   [0:N-1];
    wire        ep_tlast    [0:N-1];
    wire        ep_busy     [0:N-1];
    wire [31:0] ep_hit_rd   [0:N-1];
    wire [31:0] ep_hit_wr   [0:N-1];
    wire [31:0] ep_cpl_tx   [0:N-1];
    wire [31:0] ep_seed     [0:N-1];
    wire [15:0] ep_vendor   [0:N-1];
    wire [15:0] ep_device   [0:N-1];
    wire [15:0] ep_command  [0:N-1];
    wire [15:0] ep_status   [0:N-1];
    wire [7:0]  ep_rev      [0:N-1];
    wire [7:0]  ep_progif   [0:N-1];
    wire [7:0]  ep_subcls   [0:N-1];
    wire [7:0]  ep_class    [0:N-1];
    wire [7:0]  ep_hdrtype  [0:N-1];
    wire [31:0] ep_bar0     [0:N-1];
    wire [31:0] ep_bar1     [0:N-1];
    wire [15:0] ep_ssven    [0:N-1];
    wire [15:0] ep_ssid     [0:N-1];
    wire [7:0]  ep_capptr   [0:N-1];
    wire [7:0]  ep_intline  [0:N-1];
    wire [7:0]  ep_intpin   [0:N-1];
    wire        ep_io       [0:N-1];
    wire        ep_mem      [0:N-1];
    wire        ep_bme      [0:N-1];

    genvar gi;
    generate
        for (gi = 0; gi < N; gi = gi + 1) begin : g_ep
            assign ep_bdf[gi] = ep_bdf_pack[16*gi +: 16];
            tlp_cfg_dut u_ep (
                .clk(clk),
                .rst_n(rst_n),
                .enable(ep_enable[gi]),
                .dut_bdf(ep_bdf[gi]),
                .init_device_id(16'h000c + gi[15:0]),
                .hdr_valid(hdr_valid),
                .hdr_is_cfgrd(hdr_is_cfgrd),
                .hdr_is_cfgwr(hdr_is_cfgwr),
                .hdr_is_pair(hdr_is_pair),
                .hdr_is_complete(hdr_is_complete),
                .hdr_tag(hdr_tag),
                .hdr_requester(hdr_requester),
                .hdr_completer(hdr_completer),
                .hdr_addr(hdr_addr),
                .hdr_payload(hdr_payload),
                .m_tdata(ep_tdata[gi]),
                .m_tvalid(ep_tvalid[gi]),
                .m_tready(ep_tready[gi]),
                .m_tstart(ep_tstart[gi]),
                .m_tlast(ep_tlast[gi]),
                .m_busy(ep_busy[gi]),
                .vendor_id(ep_vendor[gi]),
                .device_id(ep_device[gi]),
                .command(ep_command[gi]),
                .status(ep_status[gi]),
                .revision_id(ep_rev[gi]),
                .prog_if(ep_progif[gi]),
                .subclass(ep_subcls[gi]),
                .class_code(ep_class[gi]),
                .header_type(ep_hdrtype[gi]),
                .bar0(ep_bar0[gi]),
                .bar1(ep_bar1[gi]),
                .subsystem_vendor_id(ep_ssven[gi]),
                .subsystem_id(ep_ssid[gi]),
                .capabilities_ptr(ep_capptr[gi]),
                .interrupt_line(ep_intline[gi]),
                .interrupt_pin(ep_intpin[gi]),
                .cmd_io_space(ep_io[gi]),
                .cmd_mem_space(ep_mem[gi]),
                .cmd_bus_master(ep_bme[gi]),
                .cnt_hit_rd(ep_hit_rd[gi]),
                .cnt_hit_wr(ep_hit_wr[gi]),
                .cnt_cpl_tx(ep_cpl_tx[gi]),
                .cnt_seed(ep_seed[gi])
            );
        end
    endgenerate

    // Priority mux: lowest index with tvalid wins
    integer i;
    integer sel;
    reg        sel_valid;
    reg [31:0] sum_rd, sum_wr, sum_cpl, sum_seed;
    reg [3:0]  n_ep;
    reg        any_busy;
    reg        any_valid;
    reg [31:0] mux_tdata;
    reg        mux_tstart;
    reg        mux_tlast;
    reg [15:0] mux_hit_bdf;
    reg        mux_hit_any;
    reg [15:0] mux_ven, mux_dev, mux_cmd, mux_sts;
    reg [7:0]  mux_rev, mux_pif, mux_sub, mux_cls, mux_ht;
    reg [31:0] mux_b0, mux_b1;
    reg [15:0] mux_ssv, mux_ssi;
    reg [7:0]  mux_cp, mux_il, mux_ip;
    reg        mux_io, mux_mem, mux_bm;

    always @(*) begin
        sel = 0;
        sel_valid = 1'b0;
        any_valid = 1'b0;
        any_busy  = 1'b0;
        mux_tdata = 32'd0;
        mux_tstart = 1'b0;
        mux_tlast  = 1'b0;
        for (i = 0; i < N; i = i + 1) begin
            if (ep_enable[i] && ep_busy[i])
                any_busy = 1'b1;
            if (ep_enable[i] && ep_tvalid[i] && !sel_valid) begin
                sel = i;
                sel_valid = 1'b1;
                any_valid = 1'b1;
                mux_tdata  = ep_tdata[i];
                mux_tstart = ep_tstart[i];
                mux_tlast  = ep_tlast[i];
            end
        end

        sum_rd = 0; sum_wr = 0; sum_cpl = 0; sum_seed = 0; n_ep = 0;
        for (i = 0; i < N; i = i + 1) begin
            if (ep_enable[i]) begin
                n_ep = n_ep + 4'd1;
                sum_rd   = sum_rd   + ep_hit_rd[i];
                sum_wr   = sum_wr   + ep_hit_wr[i];
                sum_cpl  = sum_cpl  + ep_cpl_tx[i];
                sum_seed = sum_seed + ep_seed[i];
            end
        end

        // Decode mux for current completer
        mux_hit_any = 1'b0;
        mux_hit_bdf = 16'd0;
        mux_ven = 0; mux_dev = 0; mux_cmd = 0; mux_sts = 0;
        mux_rev = 0; mux_pif = 0; mux_sub = 0; mux_cls = 0; mux_ht = 0;
        mux_b0 = 0; mux_b1 = 0; mux_ssv = 0; mux_ssi = 0;
        mux_cp = 0; mux_il = 0; mux_ip = 0;
        mux_io = 0; mux_mem = 0; mux_bm = 0;
        for (i = 0; i < N; i = i + 1) begin
            if (ep_enable[i] && (ep_bdf[i] == hdr_completer)) begin
                mux_hit_any = 1'b1;
                mux_hit_bdf = ep_bdf[i];
                mux_ven = ep_vendor[i];
                mux_dev = ep_device[i];
                mux_cmd = ep_command[i];
                mux_sts = ep_status[i];
                mux_rev = ep_rev[i];
                mux_pif = ep_progif[i];
                mux_sub = ep_subcls[i];
                mux_cls = ep_class[i];
                mux_ht  = ep_hdrtype[i];
                mux_b0  = ep_bar0[i];
                mux_b1  = ep_bar1[i];
                mux_ssv = ep_ssven[i];
                mux_ssi = ep_ssid[i];
                mux_cp  = ep_capptr[i];
                mux_il  = ep_intline[i];
                mux_ip  = ep_intpin[i];
                mux_io  = ep_io[i];
                mux_mem = ep_mem[i];
                mux_bm  = ep_bme[i];
            end
        end
    end

    assign m_tdata  = mux_tdata;
    assign m_tvalid = any_valid;
    assign m_tstart = mux_tstart;
    assign m_tlast  = mux_tlast;
    assign m_busy   = any_busy || any_valid;

    generate
        for (gi = 0; gi < N; gi = gi + 1) begin : g_rdy
            assign ep_tready[gi] = m_tready && sel_valid && (sel == gi);
        end
    endgenerate

    assign cnt_hit_rd = sum_rd;
    assign cnt_hit_wr = sum_wr;
    assign cnt_cpl_tx = sum_cpl;
    assign cnt_seed   = sum_seed;
    assign ep_count   = n_ep;

    assign hit_bdf         = mux_hit_bdf;
    assign hit_any         = mux_hit_any;
    assign hit_vendor_id   = mux_ven;
    assign hit_device_id   = mux_dev;
    assign hit_command     = mux_cmd;
    assign hit_status      = mux_sts;
    assign hit_revision_id = mux_rev;
    assign hit_prog_if     = mux_pif;
    assign hit_subclass    = mux_sub;
    assign hit_class_code  = mux_cls;
    assign hit_header_type = mux_ht;
    assign hit_bar0        = mux_b0;
    assign hit_bar1        = mux_b1;
    assign hit_subsys_ven  = mux_ssv;
    assign hit_subsys_id   = mux_ssi;
    assign hit_cap_ptr     = mux_cp;
    assign hit_int_line    = mux_il;
    assign hit_int_pin     = mux_ip;
    assign hit_cmd_io      = mux_io;
    assign hit_cmd_mem     = mux_mem;
    assign hit_cmd_bme     = mux_bm;

endmodule
