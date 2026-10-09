# Changelog

## 0.2.1 — 2026-10-09

- Teaching PCIe **endpoint DUT** (`tlp_cfg_dut.sv`): 256-byte cfg space, BAR sizing, Cpl on PAIR CfgRd
- Type-0 header decode: Vendor/Device ID, Command (IO/Mem/BME), Class/Rev, BARs, CapPtr, Int — live wires + `[DUT] RD/WR/SEED` logs
- Plusarg / make var `DUT_BDF=` — drop capture Cpls, filter to one completer, DUT closes Match
- **Multi-BDF fabric** (`tlp_cfg_fabric.sv`, up to 8 EPs): `DUT_BDFS=0100,0200` — single-BDF `make dut` unchanged
- `make dut` → `traces/dut_ep_sample.csv` + `DUT_BDF=0300` → `mis=0`
- `make dut-multi` → `traces/dut_multi_sample.csv` + `DUT_BDFS=0100,0200` → `mis=0`
- Terminal GIFs: `dut-terminal-demo.gif`, `dut-multi-terminal-demo.gif`

## 0.2.0 — 2026-10-07

- Match mirrors pcieshark: request with payload → `complete`; empty → `pair`; `Cpl` closes by tag
- `pcie_trace.csv` gates clean: `matched=192` `unmatched=0` (`make csv-gate`)
- MemRd↔Cpl out-of-order stress trace (`make stress`)
- Plusargs / make vars: `TYPE=`, `DIR=`, `DUMP=`
- `MAX_TLPS` truncates before C and HDL tallies (short wave also `mis=0`)
- CSV dump round-trip (`make dump-roundtrip`)
- Tracker depth 64; scoreboard checks Cpl, matched↔pair, open==0

## 0.1.0 — 2026-10-07

- License: **AGPL-3.0-only** (strong copyleft; replaces MIT)
- Initial Verilator path: DPI-C TLP reader (QEMU `pci_cfg_*` + CSV)
- Teaching AXI-Stream (4 beats / TLP, 32-bit)
- `tlp_header_parser` and `tlp_match_tracker` (QEMU one-line → complete)
- C vs HDL scoreboard with `make gate` → `mis=0`
- Sample trace from pcieshark Zephyr golden fabric
- VCD dump for GTKWave (`make wave`)
- Examples recipes documented in `examples/README.md`
- Professional logo (PNG + SVG) in `docs/assets/`
- Full GitHub Pages site: `docs/index.html`, `architecture.html`, `run.html`
