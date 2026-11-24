VERILATOR ?= verilator
PY        ?= python3
BUILD     := build

RTL := rtl/fft_pkg.sv rtl/fft_agu.sv rtl/twiddle_rom.sv rtl/cmul.sv \
       rtl/butterfly.sv rtl/fft_mem.sv rtl/fft64_top.sv
VFLAGS := --binary --timing --assert -Wno-fatal -Wno-WIDTH -Wno-UNUSED -Wno-DECLFILENAME \
          -Wno-INITIALDLY -Wno-STMTDLY -Wno-IMPORTSTAR -Wno-BLKSEQ

UNIT_TBS := tb_twiddle_rom tb_agu tb_cmul tb_butterfly 

CONFIGS  := 100_100 50_100 100_30 40_40

.PHONY: all test unit sys vectors lint model clean
all: test

vectors:
	@mkdir -p $(BUILD)
	$(PY) golden/gen_vectors.py --out $(BUILD)

model:
	$(PY) golden/fft_model.py

lint:
	$(VERILATOR) --lint-only -Wall -Wno-UNUSEDPARAM -Wno-UNUSEDSIGNAL --top-module fft64_top $(RTL)

define BUILD_TB
$(BUILD)/obj_$(1)/V$(1): $(RTL) tb/$(1).sv
	$(VERILATOR) $(VFLAGS) --top-module $(1) -Mdir $(BUILD)/obj_$(1) $(RTL) tb/$(1).sv > $(BUILD)/build_$(1).log 2>&1
endef
$(foreach t,$(UNIT_TBS) tb_fft64,$(eval $(call BUILD_TB,$(t))))

unit: vectors $(foreach t,$(UNIT_TBS),$(BUILD)/obj_$(t)/V$(t))
	@for t in $(UNIT_TBS); do (cd $(BUILD) && ./obj_$$t/V$$t) || exit 1; done

sys: vectors $(BUILD)/obj_tb_fft64/Vtb_fft64
	@for c in $(CONFIGS); do \
	  ip=$${c%_*}; op=$${c#*_}; \
	  (cd $(BUILD) && ./obj_tb_fft64/Vtb_fft64 +IN_PROB=$$ip +OUT_PROB=$$op +SEED=7 \
	      +OUTFILE=output_$$c.hex +SNAPFILE=snap_$$c.txt) || exit 1; \
	  $(PY) golden/compare.py --dir $(BUILD) --out output_$$c.hex --snap snap_$$c.txt \
	      $$( [ $$c = 100_100 ] && echo --plot ) || exit 1; \
	done

test: unit sys
	@echo "ALL TESTS PASSED"

clean:
	rm -rf $(BUILD)
