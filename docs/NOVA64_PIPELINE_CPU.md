# Nova64 five-stage pipeline prototype

This branch introduces a separate, experimental pipeline core in `rtl64/nova64_pipeline_cpu.sv`. It is intended to evolve toward the classic IF/ID/EX/MEM/WB organization. The original single-cycle `nova64_cpu` remains unchanged as the reference.

## Verification target

The directed test covers dependent integer operations, register forwarding, a 64-bit store/load sequence, a load-use dependency, x0 preservation, and draining the HALT instruction through the pipeline. GitHub Actions runs Icarus simulation and Verilator lint.

## Scope and limitations

This is an early RTL prototype, not a production-ready RV64 implementation. It currently supports only a subset of integer operations, has no cache/MMU/privilege/interrupt/atomic/vector support, and has not been synthesized or benchmarked. Branch, jump, byte/halfword/word memory operations, all illegal encodings, and corner-case timing require additional directed/randomized tests before considering the pipeline stable.

No claim of beating Snapdragon or any commercial mobile/laptop processor is made. Such a comparison requires a fully specified SoC, toolchain/firmware, comparable workloads, synthesis/timing/power analysis, and repeatable measurements.
