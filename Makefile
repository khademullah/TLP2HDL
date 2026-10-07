# TLP2HDL — pcieshark / QEMU TLP traces → Verilator teaching AXIS + Match gate

VERILATOR   = verilator
TOP_MODULE  = tb_tlp_dpi
WAVE_VIEWER = gtkwave

HDL_DIR = hdl
DPI_DIR = dpi

SV_SOURCES = \
	$(HDL_DIR)/tb_tlp_dpi.sv \
	$(HDL_DIR)/tlp_header_parser.sv \
	$(HDL_DIR)/tlp_match_tracker.sv

C_SOURCES = $(DPI_DIR)/tlp_reader.c

WAVE_FILE = simulation_trace.vcd
LOG_FILE  = simulation.log

TRACE    ?= traces/golden_cfg_sample.log
MAX_TLPS ?= 64

VERILATOR_FLAGS = --binary --timing --trace -j 0 --top-module $(TOP_MODULE) \
	-Wno-INITIALDLY

.PHONY: all compile run wave clean gate

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
	@echo "[MAKE] TRACE=$(TRACE) MAX_TLPS=$(MAX_TLPS)"
	./obj_dir/V$(TOP_MODULE) +TRACE="$(TRACE)" +MAX_TLPS=$(MAX_TLPS) | tee $(LOG_FILE)

gate: run
	@grep -q '\[GATE\] mis=0  PASS' $(LOG_FILE)

wave:
	@test -f $(WAVE_FILE) || { echo "Run make first"; exit 1; }
	$(WAVE_VIEWER) $(WAVE_FILE) &

clean:
	rm -rf obj_dir $(LOG_FILE) $(WAVE_FILE)
