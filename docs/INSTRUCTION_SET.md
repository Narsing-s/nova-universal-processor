# Nova v0.3 Instruction Set Notes

All instructions are 16 bits. The opcode is bits [15:12]. Register fields use two bits: r0=0, r1=1, r2=2, r3=3. Addresses are 4-bit absolute instruction or data addresses.

| Opcode | Instruction | Encoding / details |
|---|---|---|
| 0 | NOP | `0000` |
| 1 | LI Rd, imm8 | `1 Rd imm8`; immediate is bits [7:0] |
| 2 | ADD Rd, Rs, Rt | `2 Rd Rs Rt`; low byte written, carry and signed overflow recorded |
| 3 | SUB Rd, Rs, Rt | `3 Rd Rs Rt`; carry flag is 1 when no unsigned borrow occurs |
| 4 | LOAD Rd, [addr] | `4 Rd addr` |
| 5 | STORE Rd, [addr] | `5 Rd addr` |
| 6 | CMP Rd, Rt | `6 Rd Rt`; equality sets zero |
| 7 | BEQ addr | `7 addr`; branches when zero flag is 1 |
| 8 | JMP addr | `8 addr` |
| 9 | CALL addr | `9 addr`; saves next PC then jumps |
| A | RET | `A000`; restores saved PC |
| B | PUSH Rd | `B Rd`; pushes register byte |
| C | POP Rd | `C Rd`; pops register byte |
| F | HALT | `F000` |

The initial ROM is a demonstration program. The testbench also replaces the ROM with a short CALL/RET program to exercise subroutines. Stack storage is deliberately small and is not yet a production calling convention.
