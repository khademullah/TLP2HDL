# Changelog

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
