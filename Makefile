# TLP2HDL — pcieshark / QEMU TLP traces → Verilator teaching AXIS + Match gate

VERILATOR   = verilator
TOP_MODULE  = tb_tlp_dpi
WAVE_VIEWER = gtkwave

HDL_DIR = hdl
DPI_DIR = dpi

SV_SOURCES = \
	$(HDL_DIR)/tb_tlp_dpi.sv \
	$(HDL_DIR)/tlp_header_parser.sv \
	$(HDL_DIR)/tlp_match_tracker.sv \
	$(HDL_DIR)/tlp_cfg_dut.sv

C_SOURCES = $(DPI_DIR)/tlp_reader.c

WAVE_FILE = simulation_trace.vcd
LOG_FILE  = simulation.log

TRACE    ?= traces/golden_cfg_sample.log
MAX_TLPS ?= 64
TYPE     ?=
DIR      ?=
DUMP     ?=
DUT_BDF  ?=

VERILATOR_FLAGS = --binary --timing --trace -j 0 --top-module $(TOP_MODULE) \
	-Wno-INITIALDLY -Wno-WIDTHEXPAND

PLUSARGS = +TRACE="$(TRACE)" +MAX_TLPS=$(MAX_TLPS)
ifneq ($(strip $(TYPE)),)
PLUSARGS += +TYPE=$(TYPE)
endif
ifneq ($(strip $(DIR)),)
PLUSARGS += +DIR=$(DIR)
endif
ifneq ($(strip $(DUMP)),)
PLUSARGS += +DUMP="$(DUMP)"
endif
ifneq ($(strip $(DUT_BDF)),)
PLUSARGS += +DUT_BDF=$(DUT_BDF)
endif

.PHONY: all compile run wave clean gate stress dump-roundtrip csv-gate dut

all: run

compile: $(SV_SOURCES) $(C_SOURCES)
	@if [ -f obj_dir/.src_w ] && [ "$$(cat obj_dir/.src_w)" != "$(C_SOURCES) $(SV_SOURCES)" ]; then \
		echo "[MAKE] sources changed; rebuilding..."; \
		rm -rf obj_dir; \
	fi
	@echo "[MAKE] Verilating TLP2HDL..."
	$(VERILATOR) $(VERILATOR_FLAGS) $(SV_SOURCES) $(C_SOURCES)
	@echo "$(C_SOURCES) $(SV_SOURCES)" > obj_dir/.src_w

run: compile
	@echo "[MAKE] TRACE=$(TRACE) MAX_TLPS=$(MAX_TLPS) TYPE=$(TYPE) DIR=$(DIR) DUMP=$(DUMP) DUT_BDF=$(DUT_BDF)"
	./obj_dir/V$(TOP_MODULE) $(PLUSARGS) | tee $(LOG_FILE)

gate: run
	@grep -q '\[GATE\] mis=0  PASS' $(LOG_FILE)

stress:
	$(MAKE) gate TRACE=traces/memrd_cpl_stress.csv MAX_TLPS=64

csv-gate:
	$(MAKE) gate TRACE=/home/khadem/pcieshark/pcie_trace.csv MAX_TLPS=4000

# Teaching endpoint DUT: drop capture Cpls, DUT answers PAIR CfgRd for one BDF
dut:
	$(MAKE) gate TRACE=traces/dut_ep_sample.csv MAX_TLPS=64 DUT_BDF=0300

dump-roundtrip: compile
	@rm -f /tmp/tlp2hdl_roundtrip.csv
	$(MAKE) run TRACE=traces/memrd_cpl_stress.csv MAX_TLPS=64 DUMP=/tmp/tlp2hdl_roundtrip.csv
	@grep -q '\[GATE\] mis=0  PASS' $(LOG_FILE)
	$(MAKE) gate TRACE=/tmp/tlp2hdl_roundtrip.csv MAX_TLPS=64

wave:
	@test -f $(WAVE_FILE) || { echo "Run make first"; exit 1; }
	$(WAVE_VIEWER) $(WAVE_FILE) &

clean:
	rm -rf obj_dir $(LOG_FILE) $(WAVE_FILE)
