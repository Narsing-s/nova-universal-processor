# Project Nova — Universal Processor

Project Nova is an experimental processor architecture project exploring a path toward efficient computing for mobile and desktop devices.

## Current prototype: Nova CPU v0.2

This is a small educational 8-bit CPU model written in SystemVerilog. It is not yet a 32-bit processor or a production-ready mobile/desktop CPU.

### Implemented

- Four 8-bit general-purpose registers (`r0`–`r3`)
- 4-bit program counter, addressing a 16-word instruction ROM
- 16-byte data RAM
- Immediate load (`LI`)
- Register arithmetic (`ADD`, `SUB`)
- Memory access (`LOAD`, `STORE`)
- Equality comparison (`CMP`) and zero flag
- Conditional branch (`BEQ`) and absolute jump (`JMP`)
- `NOP` and `HALT`
- Automated simulation with Icarus Verilog in GitHub Actions

### Instruction summary

| Opcode | Instruction | Purpose |
|---|---|---|
| `0` | `NOP` | Do nothing |
| `1` | `LI` | Load an 8-bit immediate into a register |
| `2` | `ADD` | Add two registers |
| `3` | `SUB` | Subtract one register from another |
| `4` | `LOAD` | Read data RAM into a register |
| `5` | `STORE` | Write a register to data RAM |
| `6` | `CMP` | Compare two registers for equality |
| `7` | `BEQ` | Branch when the zero/equal flag is set |
| `8` | `JMP` | Jump to an instruction address |
| `F` | `HALT` | Stop execution |

Instructions are 16 bits wide. The current prototype uses a small fixed demo program in ROM to test arithmetic, memory operations, and branching.

## Run the test

Install Icarus Verilog, then run:

```bash
iverilog -g2012 -Wall -s tb_nova_cpu -o nova_test rtl/nova_cpu.sv tests/tb_nova_cpu.sv
vvp nova_test
```

The test checks that the CPU:
- computes `5 + 3 = 8`
- stores and reloads `8` through RAM
- compares values and takes a conditional branch
- computes `8 - 3 = 5`
- halts without timing out

GitHub Actions runs this simulation automatically on pushes and pull requests to `main`.

## Roadmap

1. Keep validating the current RTL and instruction encoding.
2. Add more tests, including non-taken branches, jumps, and arithmetic edge cases.
3. Design a clean 32-bit RISC-V-compatible core as a separate milestone.
4. Measure performance, power, and hardware area using simulation and later FPGA tools.
5. Explore FPGA implementation before considering any physical chip design.

**Important:** passing this simulation validates only the tested behavior of this educational prototype. It does not establish real-world speed, power efficiency, security, or suitability for phones and desktop computers.
