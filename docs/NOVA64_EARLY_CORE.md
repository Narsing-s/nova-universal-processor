# Nova64 experimental core

RTL: `rtl64/nova64_cpu.sv`
Testbench: `tests/tb_nova64_cpu.sv`

This experimental single-cycle 64-bit core has 64-bit integer registers, PC, ALU and address arithmetic; a 64-bit data interface with eight byte strobes; and a subset inspired by RV64I: integer arithmetic/logical operations, shifts, comparisons, byte/halfword/word/doubleword loads and stores, branches, JAL/JALR, LUI and AUIPC.

## Verification

The Nova64 GitHub Actions workflow compiles and runs the directed testbench and lints the RTL with Verilator. The test covers 64-bit arithmetic, SD/LD, LW/LWU extension, a shift by 40, branch/jump behavior and x0.

## Important limits

This is not complete RV64I, not a synthesized mobile/laptop SoC, and not evidence of speed superiority over Snapdragon or laptop processors. It currently lacks a pipeline, caches, MMU, privilege modes, interrupts, atomics, vector extensions, OS boot support, power modeling and physical implementation. Competitive performance requires synthesis, timing/area/power analysis, and reproducible hardware benchmarks. Mobile and laptop targets should eventually use separate microarchitecture configurations over a shared ISA.
