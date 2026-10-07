# Examples

Copy-paste recipes for TLP2HDL. Run from the repository root unless noted.

```bash
cd /home/khadem/TLP2HDL
```

Reference logs:

| File | Command | Result |
|------|---------|--------|
| [`gate_sample.txt`](gate_sample.txt) | `make gate` | `mis=0` PASS |
| [`gate_short.txt`](gate_short.txt) | `make MAX_TLPS=8` | `mis=0` PASS |
| [`gate_csv_sample.txt`](gate_csv_sample.txt) | `make csv-gate` | `mis=0` PASS (192 matched) |

`MAX_TLPS` truncates the loaded set **before** C and HDL tallies, so short and full gates agree.

Match (pcieshark): request **with** payload → `complete`; request **without** → `pair` (open); `Cpl` closes by tag.

---

## Install (once)

```bash
sudo apt install build-essential verilator gtkwave
```

---

## 01 — Gate

Default QEMU sample → C vs HDL Match gate (`mis=0`).

```bash
cd /home/khadem/TLP2HDL
make gate
grep -E '\[GATE\]|\[SUM\]|\[C-DPI\]' simulation.log
```

Expected (full log: [`gate_sample.txt`](gate_sample.txt)):

```text
[C-DPI] CfgRd=25 CfgWr=1 MemRd=0 MemWr=0 Cpl=0 complete=26 pair=0
[SUM] HDL  CfgRd=25 CfgWr=1 Cpl=0 complete=26 open=0 matched=0 unmatched=0
[SUM] C    CfgRd=25 CfgWr=1 Cpl=0 complete=26 pair=0
[GATE] mis=0  PASS
```

---

## 02 — Wave

Short replay, then open GTKWave on `simulation_trace.vcd`.

```bash
cd /home/khadem/TLP2HDL
make MAX_TLPS=8
make wave
```

Gate PASS expected ([`gate_short.txt`](gate_short.txt)).

---

## 03 — pcieshark CSV (CfgRd↔Cpl Match)

```bash
cd /home/khadem/TLP2HDL
make csv-gate
# or:
make TRACE=/home/khadem/pcieshark/pcie_trace.csv MAX_TLPS=4000
```

Expected: `matched=192` `unmatched=0` ([`gate_csv_sample.txt`](gate_csv_sample.txt)).

---

## 04 — MemRd↔Cpl stress

Out-of-order completions + mixed CfgRd pair / complete.

```bash
cd /home/khadem/TLP2HDL
make stress
grep -E '\[GATE\]|\[SUM\]' simulation.log
```

Expected: `matched=6` `pair=6` `mis=0`.

---

## 05 — Type / direction filter

```bash
cd /home/khadem/TLP2HDL
make TRACE=traces/golden_cfg_sample.log TYPE=CfgRd MAX_TLPS=64 gate
make TRACE=/home/khadem/pcieshark/pcie_trace.csv TYPE=CfgRd,Cpl DIR=TX MAX_TLPS=4000
```

---

## 06 — CSV dump round-trip

```bash
cd /home/khadem/TLP2HDL
make dump-roundtrip
# equivalent:
make TRACE=traces/memrd_cpl_stress.csv DUMP=/tmp/tlp2hdl_roundtrip.csv
make TRACE=/tmp/tlp2hdl_roundtrip.csv gate
```

---

## 07 — Full Zephyr trace

```bash
cd /home/khadem/TLP2HDL
make TRACE=/home/khadem/pcieshark/zephyr_ai_topology_trace.log MAX_TLPS=200
grep -E '\[GATE\]|\[SUM\]|\[C-DPI\]' simulation.log
```

---

## 08 — Short wave walk

```bash
cd /home/khadem/TLP2HDL
make MAX_TLPS=8
make wave
```

**After the VCD opens:**

1. Zoom until one 10 ns clock is one column  
2. Group `tdata`, `tvalid`, `tready`, `tstart`, `tlast`  
3. A transfer is `tvalid && tready` both high  
4. One TLP is `tstart` … `tlast` (four beats)  
5. Follow `hdr_valid` / `hdr_is_pair` / `cnt_matched`  

---

## Clean rebuild

```bash
cd /home/khadem/TLP2HDL
make clean && make gate && make stress && make csv-gate
```
