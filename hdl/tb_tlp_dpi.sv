`timescale 1ns/1ps
// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2026 Khadem Ullah
// TLP2HDL top: replay pcieshark / QEMU TLP traces over teaching AXIS, gate Match.

module tb_tlp_dpi;

    import "DPI-C" function int open_tlp_trace(input string filename);
    import "DPI-C" function int fetch_next_beat();
    import "DPI-C" function int get_beat_start();
    import "DPI-C" function int get_beat_last();
    import "DPI-C" function int unsigned get_beat_data();
    import "DPI-C" function int get_tlp_count();
    import "DPI-C" function int get_c_cfgrd();
    import "DPI-C" function int get_c_cfgwr();
    import "DPI-C" function int get_c_complete();
    import "DPI-C" function int get_c_cpl();
    import "DPI-C" function void close_tlp_trace();

    reg         clk;
    reg         rst_n;
    reg  [31:0] tdata;
    reg         tvalid;
    reg         tready;
    reg         tstart;
    reg         tlast;

    wire        hdr_valid;
    wire [7:0]  hdr_type;
    wire [7:0]  hdr_dir;
    wire [7:0]  hdr_tag;
    wire [7:0]  hdr_match_hint;
    wire [15:0] hdr_requester;
    wire [15:0] hdr_completer;
    wire [31:0] hdr_addr;
    wire [31:0] hdr_payload;
    wire        hdr_is_cfgrd;
    wire        hdr_is_cfgwr;
    wire        hdr_is_cpl;
    wire        hdr_is_complete;

    wire [31:0] cnt_cfgrd;
    wire [31:0] cnt_cfgwr;
    wire [31:0] cnt_cpl;
    wire [31:0] cnt_complete;
    wire [31:0] cnt_open;
    wire [31:0] cnt_matched;
    wire [31:0] cnt_unmatched;

    integer max_tlps;
    integer beat_count;
    integer tlp_seen;
    integer rc;
    integer is_start;
    integer is_last;
    integer mis;
    string  trace_path;

    tlp_header_parser u_parser (
        .clk(clk),
        .rst_n(rst_n),
        .tdata(tdata),
        .tvalid(tvalid),
        .tready(tready),
        .tstart(tstart),
        .tlast(tlast),
        .hdr_valid(hdr_valid),
        .hdr_type(hdr_type),
        .hdr_dir(hdr_dir),
        .hdr_tag(hdr_tag),
        .hdr_match_hint(hdr_match_hint),
        .hdr_requester(hdr_requester),
        .hdr_completer(hdr_completer),
        .hdr_addr(hdr_addr),
        .hdr_payload(hdr_payload),
        .hdr_is_cfgrd(hdr_is_cfgrd),
        .hdr_is_cfgwr(hdr_is_cfgwr),
        .hdr_is_cpl(hdr_is_cpl),
        .hdr_is_complete(hdr_is_complete)
    );

    tlp_match_tracker u_match (
        .clk(clk),
        .rst_n(rst_n),
        .hdr_valid(hdr_valid),
        .hdr_is_cfgrd(hdr_is_cfgrd),
        .hdr_is_cfgwr(hdr_is_cfgwr),
        .hdr_is_cpl(hdr_is_cpl),
        .hdr_is_complete(hdr_is_complete),
        .hdr_tag(hdr_tag),
        .hdr_requester(hdr_requester),
        .cnt_cfgrd(cnt_cfgrd),
        .cnt_cfgwr(cnt_cfgwr),
        .cnt_cpl(cnt_cpl),
        .cnt_complete(cnt_complete),
        .cnt_open(cnt_open),
        .cnt_matched(cnt_matched),
        .cnt_unmatched(cnt_unmatched)
    );

    initial clk = 1'b0;
    always #5 clk = ~clk; // 10 ns period

    always @(posedge clk) begin
        if (rst_n && hdr_valid) begin
            tlp_seen <= tlp_seen + 1;
            if (hdr_is_cfgrd)
                $display("[TLP] #%0d CfgRd  cpl=%04h addr=0x%0h data=0x%08h complete=%0d",
                         tlp_seen, hdr_completer, hdr_addr, hdr_payload, hdr_is_complete);
            else if (hdr_is_cfgwr)
                $display("[TLP] #%0d CfgWr  cpl=%04h addr=0x%0h data=0x%08h complete=%0d",
                         tlp_seen, hdr_completer, hdr_addr, hdr_payload, hdr_is_complete);
            else if (hdr_is_cpl)
                $display("[TLP] #%0d Cpl    req=%04h tag=%0d",
                         tlp_seen, hdr_requester, hdr_tag);
            else
                $display("[TLP] #%0d type=0x%02h addr=0x%0h",
                         tlp_seen, hdr_type, hdr_addr);
        end
    end

    initial begin
        $dumpfile("simulation_trace.vcd");
        $dumpvars(0, tb_tlp_dpi);

        rst_n      = 1'b0;
        tvalid     = 1'b0;
        tready     = 1'b1;
        tstart     = 1'b0;
        tlast      = 1'b0;
        tdata      = 32'd0;
        beat_count = 0;
        tlp_seen   = 0;
        mis        = 0;

        if (!$value$plusargs("TRACE=%s", trace_path))
            trace_path = "traces/golden_cfg_sample.log";
        if (!$value$plusargs("MAX_TLPS=%d", max_tlps))
            max_tlps = 64;

        repeat (4) @(posedge clk);
        rst_n = 1'b1;
        repeat (2) @(posedge clk);

        rc = open_tlp_trace(trace_path);
        if (rc != 0) begin
            $display("[TB] FAIL open_tlp_trace(%s)", trace_path);
            $finish;
        end
        $display("[TB] TRACE=%s MAX_TLPS=%0d loaded=%0d",
                 trace_path, max_tlps, get_tlp_count());

        while (fetch_next_beat() != 0) begin
            is_start = get_beat_start();
            is_last  = get_beat_last();
            @(negedge clk);
            tdata  <= get_beat_data();
            tstart <= is_start[0];
            tlast  <= is_last[0];
            tvalid <= 1'b1;
            @(posedge clk);
            while (!tready) @(posedge clk);
            beat_count = beat_count + 1;
            @(negedge clk);
            tvalid <= 1'b0;
            tstart <= 1'b0;
            tlast  <= 1'b0;

            if ((beat_count / 4) >= max_tlps)
                break;
        end

        repeat (8) @(posedge clk);

        $display("[SUM] beats=%0d tlps_seen=%0d", beat_count, tlp_seen);
        $display("[SUM] HDL  CfgRd=%0d CfgWr=%0d Cpl=%0d complete=%0d open=%0d matched=%0d unmatched=%0d",
                 cnt_cfgrd, cnt_cfgwr, cnt_cpl, cnt_complete, cnt_open, cnt_matched, cnt_unmatched);
        $display("[SUM] C    CfgRd=%0d CfgWr=%0d Cpl=%0d complete=%0d",
                 get_c_cfgrd(), get_c_cfgwr(), get_c_cpl(), get_c_complete());

        if (cnt_cfgrd !== get_c_cfgrd()) begin
            $display("[MIS] CfgRd HDL=%0d C=%0d", cnt_cfgrd, get_c_cfgrd());
            mis = mis + 1;
        end
        if (cnt_cfgwr !== get_c_cfgwr()) begin
            $display("[MIS] CfgWr HDL=%0d C=%0d", cnt_cfgwr, get_c_cfgwr());
            mis = mis + 1;
        end
        if (cnt_complete !== get_c_complete()) begin
            $display("[MIS] complete HDL=%0d C=%0d", cnt_complete, get_c_complete());
            mis = mis + 1;
        end
        if (cnt_unmatched !== 0) begin
            $display("[MIS] unmatched=%0d", cnt_unmatched);
            mis = mis + 1;
        end

        if (mis == 0)
            $display("[GATE] mis=0  PASS");
        else
            $display("[GATE] mis=%0d  FAIL", mis);

        close_tlp_trace();
        $finish;
    end

endmodule
