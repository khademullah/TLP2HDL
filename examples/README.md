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

Match (pcieshark): posted Wr → `complete`; request **with** payload → `complete`; empty Rd → `pair` (open); `Cpl` closes by tag.

**Richer Gen3/4/5 TLP coverage (MemRd/Wr)** from real traces — see [§04](#04--richer-gen345-tlp-coverage-from-real-traces-memrdwr). Types: `MemRd` `MemWr` `CfgRd` `CfgWr` `Cpl`.

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

## 04 — Richer Gen3/4/5 TLP coverage from real traces (MemRd/Wr)

Teaching-AXIS Mem + cfg TLPs from built-in samples **and** live QEMU / pcieshark captures.

Supported types: `MemRd` `MemWr` `CfgRd` `CfgWr` `Cpl`.

### Built-in samples

```bash
cd /home/khadem/TLP2HDL
make stress      # MemRd↔Cpl OOO + posted MemWr · matched=7 mis=0
make mem-gate    # fabric MemRd/MemWr/Cpl · matched=5 mis=0
make mem-mmio    # QEMU memory_region_ops_* one-liners · complete=6 mis=0
```

### Live capture via pcieshark scripts

```bash
cd /home/khadem/pcieshark
# cfg + MMIO Mem (filters UART/GIC; keeps pcie/nvme/e1000 names)
CAPTURE_MEM=1 RUN_TIMEOUT_SECONDS=10 bash scripts/run_to_tlp2hdl.sh

# Export-only from an existing log:
python3 scripts/export_trace_csv.py out/fabric_trace.log -o out/fabric_cfg.csv \
  --types CfgRd,CfgWr,Cpl
python3 scripts/export_trace_csv.py out/fabric_trace.log -o out/fabric_mem.csv \
  --types MemRd,MemWr --name-filter pcie,nvme,e1000 --exclude-name pl011,gicv3

cd /home/khadem/TLP2HDL
make gate TRACE=/home/khadem/pcieshark/out/fabric_cfg.csv MAX_TLPS=2000
make gate TRACE=/home/khadem/pcieshark/out/fabric_mem.csv MAX_TLPS=2000
make TRACE=/home/khadem/pcieshark/out/fabric_mem.csv TYPE=MemRd,MemWr MAX_TLPS=2000 gate
```

Zephyr / Linux runners:

```bash
cd /home/khadem/pcieshark
CAPTURE_MEM=0 bash scripts/run_zephyr_ai_topology.sh          # pci_cfg_* only
CAPTURE_MEM=1 RUN_TIMEOUT_SECONDS=15 bash scripts/run_zephyr_ai_topology.sh
CAPTURE_MEM=1 QEMU_TRACE='pci_cfg_*,memory_region_ops_read' \
  bash scripts/run_linux_ai_topology.sh
```

---

## 05 — Type / direction filter

```bash
cd /home/khadem/TLP2HDL
make TRACE=traces/golden_cfg_sample.log TYPE=CfgRd MAX_TLPS=64 gate
make TRACE=/home/khadem/pcieshark/pcie_trace.csv TYPE=CfgRd,Cpl DIR=TX MAX_TLPS=4000
make TRACE=/home/khadem/pcieshark/out/fabric_mem.csv TYPE=MemRd,MemWr MAX_TLPS=2000 gate
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

## 07 — Endpoint DUT

Teaching PCIe **endpoint** (cfg space), not a NIC. Drops capture Cpls; DUT answers PAIR `CfgRd`.

```bash
cd /home/khadem/TLP2HDL
make dut
# expected: DUT cpl_tx=6 matched=6 mis=0
```

Against a fabric capture (one BDF):

```bash
make TRACE=/home/khadem/pcieshark/pcie_trace.csv DUT_BDF=0e01 MAX_TLPS=4000
grep -E '\[DUT\]|\[GATE\]|\[SUM\]' simulation.log
```

Multi-BDF fabric demo (two EPs, DeviceID `0x000c` / `0x000d`):

```bash
make dut-multi
# expected: eps=2 hit_rd=10 cpl_tx=10 mis=0
```

Against a real capture (up to 8 EPs):

```bash
make TRACE=/home/khadem/pcieshark/pcie_trace.csv DUT_BDFS=0100,0200 MAX_TLPS=4000
grep -E '\[DUT\]|\[GATE\]' simulation.log
```

Wave: host `CfgRd` (pair) then DUT `Cpl` with `data=` (VID/DID, BAR size mask, …).

---

## 08 — Full Zephyr trace

```bash
cd /home/khadem/TLP2HDL
make TRACE=/home/khadem/pcieshark/zephyr_ai_topology_trace.log MAX_TLPS=200
grep -E '\[GATE\]|\[SUM\]|\[C-DPI\]' simulation.log
```

---

## 09 — Short wave walk

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
make clean && make gate && make stress && make mem-gate && make mem-mmio && make csv-gate
```

## Supported make / plusarg cheat sheet

| Command | What it covers |
|---------|----------------|
| `make gate` | Default cfg sample |
| `make stress` | MemRd↔Cpl + MemWr |
| `make mem-gate` | Fabric Mem sample |
| `make mem-mmio` | QEMU MMIO Mem log |
| `make csv-gate` | Real `pcie_trace.csv` cfg Match |
| `make dut` / `make dut-multi` | Cfg endpoint DUT |
| `TRACE=… TYPE=MemRd,MemWr` | Type filter |
| `TRACE=… DIR=TX` | Direction filter |
| `DUT_BDF=` / `DUT_BDFS=` | Single / multi EP |
| `DUMP=out.csv` | Replay dump |
