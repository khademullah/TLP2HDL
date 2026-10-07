# Examples

Copy-paste recipes for TLP2HDL. Run from the repository root unless noted.

```bash
cd /home/khadem/TLP2HDL
```

Reference logs:

| File | Command | Result |
|------|---------|--------|
| [`gate_sample.txt`](gate_sample.txt) | `make MAX_TLPS=64` | `mis=0` PASS |
| [`gate_short_fail.txt`](gate_short_fail.txt) | `make MAX_TLPS=8` | `mis=3` FAIL (expected) |

`MAX_TLPS` caps HDL replay only; C tallies the whole file. Use `MAX_TLPS ≥` loaded TLP count for a passing gate.

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
make MAX_TLPS=64
# or: make gate
grep -E '\[GATE\]|\[SUM\]|\[C-DPI\]' simulation.log
```

Expected (full log: [`gate_sample.txt`](gate_sample.txt)):

```text
[C-DPI] loaded 26 TLPs from traces/golden_cfg_sample.log
[C-DPI] CfgRd=25 CfgWr=1 MemRd=0 MemWr=0 Cpl=0 complete=26
[TB] TRACE=traces/golden_cfg_sample.log MAX_TLPS=64 loaded=26
...
[SUM] beats=104 tlps_seen=26
[SUM] HDL  CfgRd=25 CfgWr=1 Cpl=0 complete=26 open=0 matched=0 unmatched=0
[SUM] C    CfgRd=25 CfgWr=1 Cpl=0 complete=26
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

Gate FAIL is expected here — HDL stops at 8 TLPs while C still reports 26. Full log: [`gate_short_fail.txt`](gate_short_fail.txt).

```text
[SUM] beats=32 tlps_seen=8
[SUM] HDL  CfgRd=8 CfgWr=0 Cpl=0 complete=8 ...
[SUM] C    CfgRd=25 CfgWr=1 Cpl=0 complete=26
[MIS] CfgRd HDL=8 C=25
[MIS] CfgWr HDL=0 C=1
[MIS] complete HDL=8 C=26
[GATE] mis=3  FAIL
```

---

## 03 — Full Zephyr trace

Replay a full pcieshark Zephyr golden fabric capture.

```bash
cd /home/khadem/TLP2HDL
make TRACE=/home/khadem/pcieshark/zephyr_ai_topology_trace.log MAX_TLPS=200
grep -E '\[GATE\]|\[SUM\]|\[C-DPI\]' simulation.log
```

---

## 04 — CSV replay

QEMU log → pcieshark-style CSV → Verilator replay.

```bash
cd /home/khadem/TLP2HDL
python3 scripts/gen_tlp_csv.py traces/golden_cfg_sample.log -o /tmp/tlp2hdl_sample.csv -n 32
make TRACE=/tmp/tlp2hdl_sample.csv MAX_TLPS=32
grep -E '\[GATE\]|\[SUM\]' simulation.log
```

---

## 05 — Short wave walk

Eight TLPs for L2AxisBr-style beat reading in GTKWave (same as §02; gate FAIL expected).

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
5. Follow `hdr_valid` for decoded CfgRd/CfgWr  

---

## Clean rebuild

```bash
cd /home/khadem/TLP2HDL
make clean && make gate
```
