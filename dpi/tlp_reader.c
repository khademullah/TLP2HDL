/*
 * SPDX-License-Identifier: AGPL-3.0-only
 * Copyright (c) 2026 Khadem Ullah
 *
 * TLP2HDL — DPI-C reader for pcieshark / QEMU traces.
 *
 * Accepts:
 *   - QEMU pci_cfg_* logs (one-line CfgRd/CfgWr with returned DWORD)
 *   - CSV: timestamp,direction,type,requester,completer,tag,length,addr,payload
 *
 * Emits a teaching AXI-Stream of 32-bit TLP beats (not full PCIe PHY).
 */
#include <ctype.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>
#include "svdpi.h"

#ifdef __cplusplus
extern "C" {
#endif

enum {
    TLP_MEM_RD = 0x00,
    TLP_MEM_WR = 0x01,
    TLP_CFG_RD = 0x04,
    TLP_CFG_WR = 0x05,
    TLP_CPL    = 0x0A
};

enum {
    DIR_TX = 1,
    DIR_RX = 2
};

enum {
    MATCH_NONE     = 0,
    MATCH_COMPLETE = 1, /* QEMU one-line cfg access */
    MATCH_PAIR     = 2
};

#define MAX_TLPS 4096
#define BEATS_PER_TLP 4

typedef struct {
    uint8_t  type;
    uint8_t  dir;
    uint8_t  tag;
    uint8_t  match_hint;
    uint16_t requester;
    uint16_t completer;
    uint16_t length;
    uint64_t addr;
    uint32_t payload;
} tlp_rec_t;

static tlp_rec_t tlps[MAX_TLPS];
static int tlp_count;
static int tlp_idx;
static int beat_idx;
static int open_ok;

static int c_cfgrd, c_cfgwr, c_memrd, c_memwr, c_cpl, c_complete, c_other;

static uint16_t parse_bdf(const char *s)
{
    unsigned bus = 0, dev = 0, fn = 0;
    const char *p = s;
    /* strip domain if present */
    if (strchr(s, ':') && strchr(strchr(s, ':') + 1, ':'))
        p = strchr(s, ':') + 1;
    if (sscanf(p, "%x:%x.%x", &bus, &dev, &fn) == 3)
        return (uint16_t)(((bus & 0xff) << 8) | ((dev & 0x1f) << 3) | (fn & 0x7));
    return 0;
}

static uint8_t parse_type(const char *s)
{
    if (!s) return 0xff;
    if (!strcasecmp(s, "CfgRd") || !strcasecmp(s, "CfgRead") || !strcmp(s, "4"))
        return TLP_CFG_RD;
    if (!strcasecmp(s, "CfgWr") || !strcasecmp(s, "CfgWrite") || !strcmp(s, "5"))
        return TLP_CFG_WR;
    if (!strcasecmp(s, "MemRd") || !strcasecmp(s, "MemRead") || !strcmp(s, "0"))
        return TLP_MEM_RD;
    if (!strcasecmp(s, "MemWr") || !strcasecmp(s, "MemWrite") || !strcmp(s, "1"))
        return TLP_MEM_WR;
    if (!strcasecmp(s, "Cpl") || !strcasecmp(s, "CplD") || !strcasecmp(s, "Completion") || !strcmp(s, "10"))
        return TLP_CPL;
    return 0xff;
}

static uint32_t parse_payload_dword(const char *s)
{
    unsigned b0 = 0, b1 = 0, b2 = 0, b3 = 0;
    if (!s || !*s) return 0;
    if (strncmp(s, "0x", 2) == 0 || strncmp(s, "0X", 2) == 0)
        return (uint32_t)strtoul(s, NULL, 0);
    if (sscanf(s, "%x %x %x %x", &b0, &b1, &b2, &b3) >= 1)
        return (uint32_t)(b0 | (b1 << 8) | (b2 << 16) | (b3 << 24));
    return (uint32_t)strtoul(s, NULL, 16);
}

static void tally(const tlp_rec_t *t)
{
    switch (t->type) {
    case TLP_CFG_RD: c_cfgrd++; break;
    case TLP_CFG_WR: c_cfgwr++; break;
    case TLP_MEM_RD: c_memrd++; break;
    case TLP_MEM_WR: c_memwr++; break;
    case TLP_CPL:    c_cpl++; break;
    default:         c_other++; break;
    }
    if (t->match_hint == MATCH_COMPLETE)
        c_complete++;
}

static int push_tlp(tlp_rec_t *t)
{
    if (tlp_count >= MAX_TLPS)
        return -1;
    tlps[tlp_count++] = *t;
    tally(t);
    return 0;
}

static int load_qemu_log(FILE *fp)
{
    char line[512];
    int n = 0;
    while (fgets(line, sizeof(line), fp)) {
        char *p = line;
        while (*p && isspace((unsigned char)*p)) p++;
        if (strncmp(p, "pci_cfg_", 8) != 0)
            continue;

        int is_write = (strncmp(p, "pci_cfg_write", 13) == 0);
        char dev[64] = {0};
        char bdf[32] = {0};
        unsigned long offset = 0;
        unsigned long value = 0;
        char arrow[4] = {0};

        /* pci_cfg_read DEV BDF @OFF -> VAL   or write ... <- VAL */
        if (sscanf(p, "pci_cfg_%*s %63s %31s @%lx %3s %lx",
                   dev, bdf, &offset, arrow, &value) < 5)
            continue;

        tlp_rec_t t;
        memset(&t, 0, sizeof(t));
        t.type = is_write ? TLP_CFG_WR : TLP_CFG_RD;
        t.dir = is_write ? DIR_TX : DIR_RX;
        t.tag = 0;
        t.match_hint = MATCH_COMPLETE; /* QEMU one-line access */
        t.requester = 0; /* host / RC side — keep numeric 0; name in log only */
        t.completer = parse_bdf(bdf);
        t.length = 4;
        t.addr = offset;
        t.payload = (uint32_t)value;
        (void)dev;
        if (push_tlp(&t) == 0)
            n++;
    }
    return n;
}

static int load_csv(FILE *fp)
{
    char line[1024];
    int n = 0;
    if (!fgets(line, sizeof(line), fp))
        return 0;
    /* skip header if present */
    if (strncmp(line, "timestamp", 9) != 0) {
        /* first data line already consumed conceptually — rewind parse below */
        rewind(fp);
    }

    while (fgets(line, sizeof(line), fp)) {
        char *save = NULL;
        char *ts = strtok_r(line, ",", &save);
        char *dir = strtok_r(NULL, ",", &save);
        char *type = strtok_r(NULL, ",", &save);
        char *req = strtok_r(NULL, ",", &save);
        char *cpl = strtok_r(NULL, ",", &save);
        char *tag = strtok_r(NULL, ",", &save);
        char *len = strtok_r(NULL, ",", &save);
        char *addr = strtok_r(NULL, ",", &save);
        char *payload = strtok_r(NULL, "\n", &save);
        (void)ts;
        if (!dir || !type)
            continue;

        tlp_rec_t t;
        memset(&t, 0, sizeof(t));
        t.type = parse_type(type);
        if (t.type == 0xff)
            continue;
        t.dir = (!strcasecmp(dir, "TX") || !strcmp(dir, "1")) ? DIR_TX : DIR_RX;
        t.tag = (uint8_t)strtoul(tag ? tag : "0", NULL, 0);
        t.requester = parse_bdf(req ? req : "0");
        t.completer = parse_bdf(cpl ? cpl : "0");
        t.length = (uint16_t)strtoul(len ? len : "4", NULL, 0);
        t.addr = strtoull(addr ? addr : "0", NULL, 0);
        t.payload = parse_payload_dword(payload);
        if (t.type == TLP_CFG_RD || t.type == TLP_CFG_WR)
            t.match_hint = MATCH_COMPLETE;
        else if (t.type == TLP_MEM_RD)
            t.match_hint = MATCH_PAIR;
        else
            t.match_hint = MATCH_NONE;
        if (push_tlp(&t) == 0)
            n++;
    }
    return n;
}

int open_tlp_trace(const char *filename)
{
    FILE *fp;
    const char *ext;

    tlp_count = tlp_idx = beat_idx = 0;
    c_cfgrd = c_cfgwr = c_memrd = c_memwr = c_cpl = c_complete = c_other = 0;
    open_ok = 0;

    if (!filename || !*filename) {
        fprintf(stderr, "[C-DPI] empty TRACE path\n");
        return -1;
    }
    fp = fopen(filename, "r");
    if (!fp) {
        fprintf(stderr, "[C-DPI] cannot open %s\n", filename);
        return -1;
    }

    ext = strrchr(filename, '.');
    if (ext && (!strcasecmp(ext, ".csv")))
        load_csv(fp);
    else
        load_qemu_log(fp);
    fclose(fp);

    open_ok = 1;
    printf("[C-DPI] loaded %d TLPs from %s\n", tlp_count, filename);
    printf("[C-DPI] CfgRd=%d CfgWr=%d MemRd=%d MemWr=%d Cpl=%d complete=%d\n",
           c_cfgrd, c_cfgwr, c_memrd, c_memwr, c_cpl, c_complete);
    return tlp_count > 0 ? 0 : -1;
}

/* Returns 1 if a beat is available, 0 at end of stream. */
int fetch_next_beat(void)
{
    if (!open_ok || tlp_idx >= tlp_count)
        return 0;
    if (beat_idx >= BEATS_PER_TLP) {
        tlp_idx++;
        beat_idx = 0;
        if (tlp_idx >= tlp_count)
            return 0;
    }
    return 1;
}

int get_beat_start(void)
{
    return beat_idx == 0;
}

int get_beat_last(void)
{
    return beat_idx == (BEATS_PER_TLP - 1);
}

unsigned get_beat_data(void)
{
    const tlp_rec_t *t;
    unsigned d = 0;
    if (!open_ok || tlp_idx >= tlp_count)
        return 0;
    t = &tlps[tlp_idx];
    switch (beat_idx) {
    case 0:
        d = (unsigned)t->type
          | ((unsigned)t->dir << 8)
          | ((unsigned)t->tag << 16)
          | ((unsigned)t->match_hint << 24);
        break;
    case 1:
        d = (unsigned)t->requester | ((unsigned)t->completer << 16);
        break;
    case 2:
        d = (unsigned)(t->addr & 0xffffffffu);
        break;
    case 3:
        d = t->payload;
        break;
    default:
        d = 0;
        break;
    }
    beat_idx++;
    return d;
}

int get_tlp_count(void) { return tlp_count; }
int get_c_cfgrd(void) { return c_cfgrd; }
int get_c_cfgwr(void) { return c_cfgwr; }
int get_c_complete(void) { return c_complete; }
int get_c_cpl(void) { return c_cpl; }

void close_tlp_trace(void)
{
    open_ok = 0;
    tlp_count = tlp_idx = beat_idx = 0;
}

#ifdef __cplusplus
}
#endif
