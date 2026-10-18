# Convolution + Maxpooling + ReLU (3 kernel 3×3)

## Isi
- rtl/        : 8 modul RTL (top-level: cnn_top)
- tb/         : testbench self-checking dan vektor uji (tb vectors/)
- scripts/    : golden model Python
- results/    : log simulasi, waveform (VCD), screenshot, statistik sintesis
- docs/       : diagram datapath dan FSM 

## Cara menjalankan 
    make golden   	    # menghasilkan vektor uji dari golden model
    make sim      		# simulasi dan pemeriksaan, log ke sim sim.log
    make wave    		# membuka waveform di GTKWave
    make lint     		# pemeriksaan RTL dengan Verilator
    make synth    		# sintesis Yosys, statistik ke sim/synth_stat.txt

Perangkat: Icarus Verilog, GTKWave, Python 3, Verilator, Yosys