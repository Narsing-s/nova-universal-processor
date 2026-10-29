# Nova64 pipeline edge regressions

The edge regression complements the basic pipeline smoke test with signed and unsigned byte/halfword/word loads, nonzero byte-lane stores, a taken dependent BEQ, a JAL redirect and link-address validation, x0 invariance, and pipeline HALT drain.

The workflow compiles and runs the dedicated Icarus Verilog testbench and performs Verilator lint on the pipeline CPU. Passing these directed tests does not constitute full ISA compliance; randomized differential testing and broader control-flow/memory cases remain necessary.
