# Project Nova — Universal Processor

Project Nova is an experimental processor architecture project exploring processor design through simulation. The existing 8-bit RTL remains an educational prototype, not a production-ready mobile or desktop CPU. A separate 32-bit general-purpose architecture is planned so the prototype remains reproducible and compatible.

## Current prototype: Nova CPU v0.4 (8-bit)

- Four 8-bit general-purpose registers: r0–r3
- 4-bit program counter and 16-word instruction ROM
- 16-byte data RAM and an independent 16-byte data stack
- 16-bit fixed-width instructions
- Immediate load, ADD, SUB, LOAD, STORE, CMP, BEQ, JMP, NOP and HALT
- Carry, zero and signed-overflow flags
- CALL/RET using a dedicated 16-entry return-address stack
- Bitwise AND, OR, XOR and NOT
- Safe stop on stack overflow/underflow and unsupported opcode encodings
- Icarus Verilog regression simulation in GitHub Actions

## Instruction set

| Opcode | Mnemonic | Behavior |
|---|---|---|
| 0 | NOP/XOR/NOT | Opcode 0 subfunction selects NOP, XOR or NOT |
| 1 | LI | Load 8-bit immediate into Rd |
| 2 | ADD | Rd = Rs + Rt; updates carry, zero and overflow |
| 3 | SUB | Rd = Rs - Rt; carry means no borrow |
| 4 | LOAD | Rd = RAM[address] |
| 5 | STORE | RAM[address] = Rd |
| 6 | CMP | Compare Rd and Rt; updates zero/carry |
| 7 | BEQ | Branch to absolute 4-bit address when zero flag is set |
| 8 | JMP | Jump to absolute 4-bit address |
| 9 | CALL | Push return address and jump |
| A | RET | Return to saved address |
| B | PUSH | Push register value onto independent byte stack |
| C | POP | Pop byte into a register |
| D | AND | Bitwise AND of two registers |
| E | OR | Bitwise OR of two registers |
| F | HALT | Stop execution |

## Run tests locally

Install Icarus Verilog, then run:

\`\`\`bash
iverilog -g2012 -Wall -s tb_nova_cpu -o nova_test rtl/nova_cpu.sv tests/tb_nova_cpu.sv
vvp nova_test
\`\`\`

## 32-bit general-purpose architecture

See docs/NOVA32_IMPLEMENTATION_PLAN.md. The 32-bit core is planned as a separate module and ISA; it is not yet implemented. The recommended sequence is to stabilize and test the 8-bit reference, specify the ISA, build a simple 32-bit reference core, then optimize using reproducible measurements.

## Limitations

Passing simulation validates only tested behavior. It does not prove real-world speed, power efficiency, security, timing closure, or suitability for phones/desktops.
