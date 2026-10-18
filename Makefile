RTL     = $(wildcard rtl/*.v)
TB      = tb/tb_cnn_top.v
TOP     = tb_cnn_top
DUT     = cnn_top
SIM_DIR = sim

.PHONY: all compile sim wave golden lint synth clean

all: sim

compile:
	mkdir -p $(SIM_DIR)
	iverilog -g2012 -Wall -s $(TOP) -o $(SIM_DIR)/$(TOP).vvp $(RTL) $(TB)

sim: compile
	vvp $(SIM_DIR)/$(TOP).vvp | tee $(SIM_DIR)/sim.log

wave:
	gtkwave $(SIM_DIR)/$(TOP).vcd &

golden:
	python3 scripts/golden_model.py

lint:
	verilator --lint-only -Wall -Wno-DECLFILENAME --top-module $(DUT) $(RTL)

synth:
	mkdir -p $(SIM_DIR)
	yosys -q -p "read_verilog -sv $(RTL); synth -top $(DUT); tee -o $(SIM_DIR)/synth_stat.txt stat"

clean:
	rm -rf $(SIM_DIR)