`timescale 1ns/1ps
// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2026 Khadem Ullah
// TLP2HDL top: replay traces over teaching AXIS, optional cfg endpoint DUT, gate Match.

module tb_tlp_dpi;

    import "DPI-C" function void set_type_filter(input string s);
    import "DPI-C" function void set_dir_filter(input string s);
    import "DPI-C" function void set_max_replay(input int n);
    import "DPI-C" function void set_drop_cpl(input int en);
    import "DPI-C" function void set_completer_filter(input int bdf);
    import "DPI-C" function int open_tlp_trace(input string filename);
    import "DPI-C" function int dump_tlp_csv(input string path);
    import "DPI-C" function int fetch_next_beat();
    import "DPI-C" function int get_beat_start();
    import "DPI-C" function int get_beat_last();
    import "DPI-C" function int unsigned get_beat_data();
    import "DPI-C" function int get_tlp_count();
    import "DPI-C" function int get_c_cfgrd();
    import "DPI-C" function int get_c_cfgwr();
    import "DPI-C" function int get_c_complete();
    import "DPI-C" function int get_c_cpl();
    import "DPI-C" function int get_c_paired();
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
    wire        hdr_is_pair;

    wire [31:0] cnt_cfgrd;
    wire [31:0] cnt_cfgwr;
    wire [31:0] cnt_cpl;
    wire [31:0] cnt_complete;
    wire [31:0] cnt_open;
    wire [31:0] cnt_matched;
    wire [31:0] cnt_unmatched;

    reg         dut_enable;
    reg  [15:0] dut_bdf;
    wire [31:0] dut_tdata;
    wire        dut_tvalid;
    reg         dut_tready;
    wire        dut_tstart;
    wire        dut_tlast;
    wire        dut_busy;
    wire [31:0] dut_hit_rd;
    wire [31:0] dut_hit_wr;
    wire [31:0] dut_cpl_tx;
    wire [31:0] dut_seed;

    integer max_tlps;
    integer beat_count;
    integer tlp_seen;
    integer rc;
    integer is_start;
    integer is_last;
    integer mis;
    integer dut_bdf_i;
    integer guard;
    string  trace_path;
    string  type_filt;
    string  dir_filt;
    string  dump_path;

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
        .hdr_is_complete(hdr_is_complete),
        .hdr_is_pair(hdr_is_pair)
    );

    tlp_match_tracker u_match (
        .clk(clk),
        .rst_n(rst_n),
        .hdr_valid(hdr_valid),
        .hdr_is_cfgrd(hdr_is_cfgrd),
        .hdr_is_cfgwr(hdr_is_cfgwr),
        .hdr_is_cpl(hdr_is_cpl),
        .hdr_is_complete(hdr_is_complete),
        .hdr_is_pair(hdr_is_pair),
        .hdr_tag(hdr_tag),
        .hdr_requester(hdr_requester),
        .hdr_completer(hdr_completer),
        .cnt_cfgrd(cnt_cfgrd),
        .cnt_cfgwr(cnt_cfgwr),
        .cnt_cpl(cnt_cpl),
        .cnt_complete(cnt_complete),
        .cnt_open(cnt_open),
        .cnt_matched(cnt_matched),
        .cnt_unmatched(cnt_unmatched)
    );

    tlp_cfg_dut u_dut (
        .clk(clk),
        .rst_n(rst_n),
        .enable(dut_enable),
        .dut_bdf(dut_bdf),
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
        .m_tdata(dut_tdata),
        .m_tvalid(dut_tvalid),
        .m_tready(dut_tready),
        .m_tstart(dut_tstart),
        .m_tlast(dut_tlast),
        .m_busy(dut_busy),
        .cnt_hit_rd(dut_hit_rd),
        .cnt_hit_wr(dut_hit_wr),
        .cnt_cpl_tx(dut_cpl_tx),
        .cnt_seed(dut_seed)
    );

    initial clk = 1'b0;
    always #5 clk = ~clk;

    always @(posedge clk) begin
        if (rst_n && hdr_valid) begin
            tlp_seen <= tlp_seen + 1;
            if (hdr_is_cfgrd)
                $display("[TLP] #%0d CfgRd  cpl=%04h addr=0x%0h data=0x%08h complete=%0d pair=%0d",
                         tlp_seen, hdr_completer, hdr_addr, hdr_payload, hdr_is_complete, hdr_is_pair);
            else if (hdr_is_cfgwr)
                $display("[TLP] #%0d CfgWr  cpl=%04h addr=0x%0h data=0x%08h complete=%0d",
                         tlp_seen, hdr_completer, hdr_addr, hdr_payload, hdr_is_complete);
            else if (hdr_is_cpl)
                $display("[TLP] #%0d Cpl    req=%04h cpl=%04h tag=%0d data=0x%08h%s",
                         tlp_seen, hdr_requester, hdr_completer, hdr_tag, hdr_payload,
                         dut_enable ? "  (DUT)" : "");
            else if (hdr_is_pair)
                $display("[TLP] #%0d MemRd  req=%04h tag=%0d addr=0x%0h pair=1",
                         tlp_seen, hdr_requester, hdr_tag, hdr_addr);
            else
                $display("[TLP] #%0d type=0x%02h addr=0x%0h",
                         tlp_seen, hdr_type, hdr_addr);
        end
    end

    task automatic drive_beat(input [31:0] d, input st, input lt);
        begin
            @(negedge clk);
            tdata  <= d;
            tstart <= st;
            tlast  <= lt;
            tvalid <= 1'b1;
            @(posedge clk);
            while (!tready) @(posedge clk);
            beat_count = beat_count + 1;
            @(negedge clk);
            tvalid <= 1'b0;
            tstart <= 1'b0;
            tlast  <= 1'b0;
        end
    endtask

    task automatic drain_dut;
        begin
            if (!dut_enable)
                return;
            // Allow DUT to see hdr_valid and queue
            repeat (2) @(posedge clk);
            guard = 0;
            while ((dut_busy || dut_tvalid) && guard < 64) begin
                guard = guard + 1;
                dut_tready = 1'b1;
                if (dut_tvalid) begin
                    drive_beat(dut_tdata, dut_tstart, dut_tlast);
                end else begin
                    @(posedge clk);
                end
            end
            dut_tready = 1'b0;
        end
    endtask

    initial begin
        $dumpfile("simulation_trace.vcd");
        $dumpvars(0, tb_tlp_dpi);

        rst_n      = 1'b0;
        tvalid     = 1'b0;
        tready     = 1'b1;
        tstart     = 1'b0;
        tlast      = 1'b0;
        tdata      = 32'd0;
        dut_tready = 1'b0;
        dut_enable = 1'b0;
        dut_bdf    = 16'd0;
        beat_count = 0;
        tlp_seen   = 0;
        mis        = 0;
        type_filt  = "";
        dir_filt   = "";
        dump_path  = "";
        dut_bdf_i  = -1;

        if (!$value$plusargs("TRACE=%s", trace_path))
            trace_path = "traces/golden_cfg_sample.log";
        if (!$value$plusargs("MAX_TLPS=%d", max_tlps))
            max_tlps = 64;
        if ($value$plusargs("TYPE=%s", type_filt))
            set_type_filter(type_filt);
        if ($value$plusargs("DIR=%s", dir_filt))
            set_dir_filter(dir_filt);
        void'($value$plusargs("DUMP=%s", dump_path));
        if ($value$plusargs("DUT_BDF=%h", dut_bdf_i)) begin
            dut_enable = 1'b1;
            dut_bdf    = dut_bdf_i[15:0];
            set_drop_cpl(1);
            set_completer_filter(dut_bdf_i);
        end
        set_max_replay(max_tlps);

        repeat (4) @(posedge clk);
        rst_n = 1'b1;
        repeat (2) @(posedge clk);

        rc = open_tlp_trace(trace_path);
        if (rc != 0) begin
            $display("[TB] FAIL open_tlp_trace(%s)", trace_path);
            $finish;
        end
        if (dump_path.len() != 0)
            void'(dump_tlp_csv(dump_path));

        $display("[TB] TRACE=%s MAX_TLPS=%0d TYPE=%s DIR=%s DUT_BDF=%s loaded=%0d",
                 trace_path, max_tlps,
                 (type_filt.len() != 0) ? type_filt : "*",
                 (dir_filt.len() != 0) ? dir_filt : "*",
                 dut_enable ? $sformatf("%04h", dut_bdf) : "off",
                 get_tlp_count());

        while (fetch_next_beat() != 0) begin
            is_start = get_beat_start();
            is_last  = get_beat_last();
            drive_beat(get_beat_data(), is_start[0], is_last[0]);
            if (is_last[0])
                drain_dut();
        end

        // Final drain
        drain_dut();
        repeat (8) @(posedge clk);

        $display("[SUM] beats=%0d tlps_seen=%0d", beat_count, tlp_seen);
        $display("[SUM] HDL  CfgRd=%0d CfgWr=%0d Cpl=%0d complete=%0d open=%0d matched=%0d unmatched=%0d",
                 cnt_cfgrd, cnt_cfgwr, cnt_cpl, cnt_complete, cnt_open, cnt_matched, cnt_unmatched);
        $display("[SUM] C    CfgRd=%0d CfgWr=%0d Cpl=%0d complete=%0d pair=%0d",
                 get_c_cfgrd(), get_c_cfgwr(), get_c_cpl(), get_c_complete(), get_c_paired());
        if (dut_enable)
            $display("[DUT] bdf=%04h hit_rd=%0d hit_wr=%0d cpl_tx=%0d seed=%0d",
                     dut_bdf, dut_hit_rd, dut_hit_wr, dut_cpl_tx, dut_seed);

        if (cnt_cfgrd !== get_c_cfgrd()) begin
            $display("[MIS] CfgRd HDL=%0d C=%0d", cnt_cfgrd, get_c_cfgrd());
            mis = mis + 1;
        end
        if (cnt_cfgwr !== get_c_cfgwr()) begin
            $display("[MIS] CfgWr HDL=%0d C=%0d", cnt_cfgwr, get_c_cfgwr());
            mis = mis + 1;
        end
        if (!dut_enable) begin
            if (cnt_cpl !== get_c_cpl()) begin
                $display("[MIS] Cpl HDL=%0d C=%0d", cnt_cpl, get_c_cpl());
                mis = mis + 1;
            end
            if (cnt_matched !== get_c_paired()) begin
                $display("[MIS] matched HDL=%0d C_pair=%0d", cnt_matched, get_c_paired());
                mis = mis + 1;
            end
        end else begin
            // Capture Cpls dropped; DUT must close every PAIR
            if (cnt_cpl !== dut_cpl_tx) begin
                $display("[MIS] Cpl HDL=%0d DUT_tx=%0d", cnt_cpl, dut_cpl_tx);
                mis = mis + 1;
            end
            if (cnt_matched !== get_c_paired()) begin
                $display("[MIS] matched HDL=%0d C_pair=%0d", cnt_matched, get_c_paired());
                mis = mis + 1;
            end
            if (dut_cpl_tx !== get_c_paired()) begin
                $display("[MIS] DUT cpl_tx=%0d C_pair=%0d", dut_cpl_tx, get_c_paired());
                mis = mis + 1;
            end
            if (dut_hit_rd !== get_c_paired()) begin
                $display("[MIS] DUT hit_rd=%0d C_pair=%0d", dut_hit_rd, get_c_paired());
                mis = mis + 1;
            end
        end
        if (cnt_complete !== get_c_complete()) begin
            $display("[MIS] complete HDL=%0d C=%0d", cnt_complete, get_c_complete());
            mis = mis + 1;
        end
        if (cnt_unmatched !== 0) begin
            $display("[MIS] unmatched=%0d", cnt_unmatched);
            mis = mis + 1;
        end
        if (cnt_open !== 0) begin
            $display("[MIS] open=%0d (dangling requests)", cnt_open);
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
