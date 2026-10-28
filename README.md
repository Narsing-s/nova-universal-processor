# Project Nova — Universal Processor

Project Nova is an experimental processor architecture project exploring processor design through simulation. The current RTL is an educational 8-bit prototype, not a production-ready mobile or desktop CPU.

## Current prototype: Nova CPU v0.3

- Four 8-bit general-purpose registers: `r0`–`r3`
- 4-bit program counter and 16-word instruction ROM
- 16-byte data RAM
- 16-bit fixed-width instructions
- Immediate load, ADD, SUB, LOAD, STORE, CMP, BEQ, JMP, NOP and HALT
- Carry, zero and signed-overflow flags
- CALL and RET using a 16-entry return-address stack
- PUSH and POP for byte data
- Stack overflow/underflow and illegal opcode stop protection
- Automated Icarus Verilog simulation on GitHub Actions

## Instruction set

| Opcode | Mnemonic | Behavior |
|---|---|---|
| `0` | NOP | Advance to next instruction |
| `1` | LI | Load 8-bit immediate into register `Rd` |
| `2` | ADD | `Rd = Rs + Rt`; updates carry, zero and overflow |
| `3` | SUB | `Rd = Rs - Rt`; carry means no borrow |
| `4` | LOAD | `Rd = RAM[address]` |
| `5` | STORE | `RAM[address] = Rd` |
| `6` | CMP | Compare `Rd` and `Rt`; updates zero/carry |
| `7` | BEQ | Branch to absolute 4-bit address when zero flag is set |
| `8` | JMP | Jump to absolute 4-bit address |
| `9` | CALL | Push return address and jump |
| `A` | RET | Return to saved address |
| `B` | PUSH | Push register value onto byte stack |
| `C` | POP | Pop byte into register |
| `F` | HALT | Stop execution |

Flags are updated by arithmetic/comparison instructions; zero is also updated by LI and LOAD. PUSH/POP and CALL/RET currently share the same small stack pointer/storage resources, so they should not be mixed in the same live call frame in this prototype. The design is intended for instruction-set learning, not a full ABI or operating-system environment.

## Run tests locally

Install Icarus Verilog, then run:

```bash
iverilog -g2012 -Wall -s tb_nova_cpu -o nova_test rtl/nova_cpu.sv tests/tb_nova_cpu.sv
vvp nova_test
```

GitHub Actions runs the same testbench on pushes and pull requests to `main`.

## Next roadmap

1. Verify the RTL and expand edge-case tests.
2. Separate call-return stack and data stack, and define stack semantics fully.
3. Add logical operations and more branch conditions.
4. Consider a separate 32-bit RISC-V-compatible core as a later milestone.
5. Explore synthesis and FPGA implementation before any physical chip work.

**Limitations:** passing simulation only validates the tested behavior. It does not prove real-world speed, power efficiency, security, or suitability for phones/desktops.
