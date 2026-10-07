# Examples

Copy-paste recipes for TLP2HDL. Run from the repository root unless noted.

```bash
cd /home/khadem/TLP2HDL
```

Expected gate output: [`gate_sample.txt`](gate_sample.txt).

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
grep -E '\[GATE\]|\[SUM\]' simulation.log
```

---

## 02 — Wave

Short replay, then open GTKWave on `simulation_trace.vcd`.

```bash
cd /home/khadem/TLP2HDL
make MAX_TLPS=8
make wave
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

Eight TLPs for L2AxisBr-style beat reading in GTKWave.

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
