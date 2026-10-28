# Project Nova — Universal Processor

An experimental processor architecture project exploring efficient computing for mobile and desktop devices.

## Current prototype: Nova CPU v0.1

- 8-bit accumulator
- 4-bit program counter
- Immediate addition and subtraction
- Halt instruction
- Automated SystemVerilog simulation testbench using Icarus Verilog

## Run the test locally

```bash
iverilog -g2012 -s tb_nova_cpu -o nova_test rtl/nova_cpu.sv tests/tb_nova_cpu.sv
vvp nova_test
```

Expected result: `PASS: 5 + 3 - 2 = 6`.

## Roadmap

1. Validate the educational CPU.
2. Add registers, memory access, and branching.
3. Develop a 32-bit RISC-V-compatible core.
4. Measure performance, power, and hardware area.
5. Explore FPGA implementation and mobile/desktop configurations.

This is an educational simulation prototype, not a production CPU.