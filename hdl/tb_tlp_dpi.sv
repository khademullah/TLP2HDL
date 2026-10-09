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
    import "DPI-C" function void set_completer_filters(input string bdfs);
    import "DPI-C" function int get_bdf_filter_count();
    import "DPI-C" function int get_bdf_filter(input int idx);
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

    localparam int DUT_N = 8;

    reg         dut_enable;
    reg  [DUT_N-1:0]    ep_enable;
    reg  [16*DUT_N-1:0] ep_bdf_pack;
    integer             ep_n;
    string              dut_bdfs_str;
    string              dut_label;

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
    wire [3:0]  dut_ep_count;
    wire [15:0] dut_hit_bdf;
    wire        dut_hit_any;
    wire [15:0] dut_vendor_id;
    wire [15:0] dut_device_id;
    wire [15:0] dut_command;
    wire [15:0] dut_status;
    wire [7:0]  dut_revision_id;
    wire [7:0]  dut_prog_if;
    wire [7:0]  dut_subclass;
    wire [7:0]  dut_class_code;
    wire [7:0]  dut_header_type;
    wire [31:0] dut_bar0;
    wire [31:0] dut_bar1;
    wire [15:0] dut_subsys_ven;
    wire [15:0] dut_subsys_id;
    wire [7:0]  dut_cap_ptr;
    wire [7:0]  dut_int_line;
    wire [7:0]  dut_int_pin;
    wire        dut_cmd_io;
    wire        dut_cmd_mem;
    wire        dut_cmd_bme;

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

    tlp_cfg_fabric #(.N(DUT_N)) u_fabric (
        .clk(clk),
        .rst_n(rst_n),
        .ep_enable(ep_enable),
        .ep_bdf_pack(ep_bdf_pack),
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
        .hit_bdf(dut_hit_bdf),
        .hit_any(dut_hit_any),
        .hit_vendor_id(dut_vendor_id),
        .hit_device_id(dut_device_id),
        .hit_command(dut_command),
        .hit_status(dut_status),
        .hit_revision_id(dut_revision_id),
        .hit_prog_if(dut_prog_if),
        .hit_subclass(dut_subclass),
        .hit_class_code(dut_class_code),
        .hit_header_type(dut_header_type),
        .hit_bar0(dut_bar0),
        .hit_bar1(dut_bar1),
        .hit_subsys_ven(dut_subsys_ven),
        .hit_subsys_id(dut_subsys_id),
        .hit_cap_ptr(dut_cap_ptr),
        .hit_int_line(dut_int_line),
        .hit_int_pin(dut_int_pin),
        .hit_cmd_io(dut_cmd_io),
        .hit_cmd_mem(dut_cmd_mem),
        .hit_cmd_bme(dut_cmd_bme),
        .cnt_hit_rd(dut_hit_rd),
        .cnt_hit_wr(dut_hit_wr),
        .cnt_cpl_tx(dut_cpl_tx),
        .cnt_seed(dut_seed),
        .ep_count(dut_ep_count)
    );

    initial clk = 1'b0;
    always #5 clk = ~clk;

    function automatic string cfg_reg_name(input [7:0] off);
        case (off)
            8'h00: cfg_reg_name = "VendorID/DeviceID";
            8'h04: cfg_reg_name = "Command/Status";
            8'h08: cfg_reg_name = "ClassCode/Revision";
            8'h0c: cfg_reg_name = "BIST/Header/Lat/Cache";
            8'h10: cfg_reg_name = "BAR0";
            8'h14: cfg_reg_name = "BAR1";
            8'h18: cfg_reg_name = "BAR2";
            8'h1c: cfg_reg_name = "BAR3";
            8'h20: cfg_reg_name = "BAR4";
            8'h24: cfg_reg_name = "BAR5";
            8'h2c: cfg_reg_name = "SubsystemID";
            8'h30: cfg_reg_name = "ExpROM";
            8'h34: cfg_reg_name = "CapabilitiesPtr";
            8'h3c: cfg_reg_name = "IntLine/IntPin";
            default: cfg_reg_name = "CfgDWORD";
        endcase
    endfunction

    function automatic string decode_cfg_dword(input [7:0] off, input [31:0] data);
        string s;
        case (off)
            8'h00: $sformat(s, "VendorID=0x%04h DeviceID=0x%04h", data[15:0], data[31:16]);
            8'h04: $sformat(s, "Command=0x%04h (IO=%0d Mem=%0d BME=%0d) Status=0x%04h",
                            data[15:0], data[0], data[1], data[2], data[31:16]);
            8'h08: $sformat(s, "Class=0x%02h Sub=0x%02h ProgIF=0x%02h Rev=0x%02h",
                            data[31:24], data[23:16], data[15:8], data[7:0]);
            8'h10, 8'h14, 8'h18, 8'h1c, 8'h20, 8'h24:
                if (data == 32'hffff_ffff)
                    $sformat(s, "%s size-probe", cfg_reg_name(off));
                else if (data[0])
                    $sformat(s, "%s=0x%08h (IO)", cfg_reg_name(off), data);
                else if (data[2] && data[3])
                    $sformat(s, "%s=0x%08h (Mem 64-bit pref)", cfg_reg_name(off), data);
                else if (data[2])
                    $sformat(s, "%s=0x%08h (Mem 64-bit)", cfg_reg_name(off), data);
                else if (data[3])
                    $sformat(s, "%s=0x%08h (Mem 32-bit pref)", cfg_reg_name(off), data);
                else
                    $sformat(s, "%s=0x%08h (Mem 32-bit)", cfg_reg_name(off), data);
            8'h2c: $sformat(s, "SubVendor=0x%04h Subsystem=0x%04h", data[15:0], data[31:16]);
            8'h34: $sformat(s, "CapPtr=0x%02h", data[7:0]);
            8'h3c: $sformat(s, "IntLine=%0d IntPin=%0d", data[7:0], data[15:8]);
            default: $sformat(s, "%s=0x%08h", cfg_reg_name(off), data);
        endcase
        return s;
    endfunction

    // Value the DUT image holds / will return for this offset (before WR/SEED update)
    function automatic [31:0] dut_image_dword(input [7:0] off);
        case (off)
            8'h00: dut_image_dword = {dut_device_id, dut_vendor_id};
            8'h04: dut_image_dword = {dut_status, dut_command};
            8'h08: dut_image_dword = {dut_class_code, dut_subclass, dut_prog_if, dut_revision_id};
            8'h10: dut_image_dword = dut_bar0;
            8'h14: dut_image_dword = dut_bar1;
            8'h2c: dut_image_dword = {dut_subsys_id, dut_subsys_ven};
            8'h34: dut_image_dword = {24'd0, dut_cap_ptr};
            8'h3c: dut_image_dword = {16'd0, dut_int_pin, dut_int_line};
            default: dut_image_dword = 32'd0;
        endcase
    endfunction

    always @(posedge clk) begin
        if (rst_n && hdr_valid) begin
            tlp_seen <= tlp_seen + 1;
            // Host / bus TLP first, then DUT decode (causal log order)
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

            if (dut_enable && dut_hit_any) begin
                // Prefix bdf= when fabric has >1 EP so multi-BDF demos stay readable
                if (hdr_is_cfgwr) begin
                    if (dut_ep_count > 4'd1)
                        $display("[DUT] WR   bdf=%04h @0x%02h  %s", dut_hit_bdf, hdr_addr[7:0],
                                 decode_cfg_dword(hdr_addr[7:0], hdr_payload));
                    else
                        $display("[DUT] WR   @0x%02h  %s", hdr_addr[7:0],
                                 decode_cfg_dword(hdr_addr[7:0], hdr_payload));
                end else if (hdr_is_cfgrd && hdr_is_complete) begin
                    if (dut_ep_count > 4'd1)
                        $display("[DUT] SEED bdf=%04h @0x%02h  %s", dut_hit_bdf, hdr_addr[7:0],
                                 decode_cfg_dword(hdr_addr[7:0], hdr_payload));
                    else
                        $display("[DUT] SEED @0x%02h  %s", hdr_addr[7:0],
                                 decode_cfg_dword(hdr_addr[7:0], hdr_payload));
                end else if (hdr_is_cfgrd && hdr_is_pair) begin
                    if (dut_ep_count > 4'd1)
                        $display("[DUT] RD   bdf=%04h @0x%02h  %s", dut_hit_bdf, hdr_addr[7:0],
                                 decode_cfg_dword(hdr_addr[7:0], dut_image_dword(hdr_addr[7:0])));
                    else
                        $display("[DUT] RD   @0x%02h  %s", hdr_addr[7:0],
                                 decode_cfg_dword(hdr_addr[7:0], dut_image_dword(hdr_addr[7:0])));
                end
            end
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
        ep_enable  = '0;
        ep_bdf_pack = '0;
        ep_n       = 0;
        beat_count = 0;
        tlp_seen   = 0;
        mis        = 0;
        type_filt  = "";
        dir_filt   = "";
        dump_path  = "";
        dut_bdfs_str = "";
        dut_label  = "off";
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

        // Multi-BDF: +DUT_BDFS=0100,0200,0300  (takes precedence)
        // Single-BDF: +DUT_BDF=0300  (unchanged demo path)
        if ($value$plusargs("DUT_BDFS=%s", dut_bdfs_str) && dut_bdfs_str.len() != 0) begin
            automatic int n;
            automatic int bi;
            automatic int bv;
            dut_enable = 1'b1;
            set_drop_cpl(1);
            set_completer_filters(dut_bdfs_str);
            n = get_bdf_filter_count();
            if (n > DUT_N) n = DUT_N;
            for (bi = 0; bi < n; bi++) begin
                bv = get_bdf_filter(bi);
                ep_enable[bi] = 1'b1;
                ep_bdf_pack[16*bi +: 16] = bv[15:0];
            end
            ep_n = n;
            dut_label = dut_bdfs_str;
        end else if ($value$plusargs("DUT_BDF=%h", dut_bdf_i)) begin
            dut_enable = 1'b1;
            ep_enable  = '0;
            ep_enable[0] = 1'b1;
            ep_bdf_pack[15:0] = dut_bdf_i[15:0];
            ep_n = 1;
            set_drop_cpl(1);
            set_completer_filter(dut_bdf_i);
            dut_label = $sformatf("%04h", dut_bdf_i[15:0]);
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

        $display("[TB] TRACE=%s MAX_TLPS=%0d TYPE=%s DIR=%s DUT_BDF=%s eps=%0d loaded=%0d",
                 trace_path, max_tlps,
                 (type_filt.len() != 0) ? type_filt : "*",
                 (dir_filt.len() != 0) ? dir_filt : "*",
                 dut_label, ep_n, get_tlp_count());

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
        if (dut_enable) begin
            $display("[DUT] bdfs=%s eps=%0d hit_rd=%0d hit_wr=%0d cpl_tx=%0d seed=%0d",
                     dut_label, dut_ep_count, dut_hit_rd, dut_hit_wr, dut_cpl_tx, dut_seed);
            if (ep_n == 1) begin
                $display("[DUT] VendorID=0x%04h DeviceID=0x%04h Class=0x%02h:%02h:%02h Rev=0x%02h",
                         dut_vendor_id, dut_device_id, dut_class_code, dut_subclass,
                         dut_prog_if, dut_revision_id);
                $display("[DUT] Command=0x%04h (IO=%0d Mem=%0d BME=%0d) Status=0x%04h HeaderType=0x%02h",
                         dut_command, dut_cmd_io, dut_cmd_mem, dut_cmd_bme, dut_status, dut_header_type);
                $display("[DUT] BAR0=0x%08h BAR1=0x%08h Subsys=0x%04h:0x%04h CapPtr=0x%02h Int=%0d/%0d",
                         dut_bar0, dut_bar1, dut_subsys_ven, dut_subsys_id,
                         dut_cap_ptr, dut_int_line, dut_int_pin);
            end else begin
                begin : dump_eps
                    integer ei;
                    for (ei = 0; ei < DUT_N; ei = ei + 1) begin
                        if (ep_enable[ei])
                            $display("[DUT] ep[%0d] bdf=%04h", ei, ep_bdf_pack[16*ei +: 16]);
                    end
                end
            end
        end

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
