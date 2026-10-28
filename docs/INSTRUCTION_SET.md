# Nova v0.4 Instruction Set Notes

All instructions are 16 bits. The opcode is bits [15:12]. Register fields use two bits: r0=0, r1=1, r2=2, r3=3. Addresses are 4-bit absolute instruction or data addresses.

| Opcode | Instruction | Encoding / details |
|---|---|---|
| 0 | NOP | Subfunction bits [11:10] = `00` |
| 0 | XOR Rd, Rs, Rt | Subfunction `01`; Rd=[9:8], Rs=[7:6], Rt=[5:4] |
| 0 | NOT Rd, Rs | Subfunction `10`; Rd=[9:8], Rs=[7:6] |
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
| D | AND Rd, Rs, Rt | `D` plus register fields |
| E | OR Rd, Rs, Rt | `E` plus register fields |
| F | HALT | `F000` |

The initial ROM is a demonstration program. The testbench also replaces the ROM with a short CALL/RET program to exercise subroutines. Stack storage is deliberately small and is not yet a production calling convention.

The data stack and CALL/RET return stack have separate pointers. The small ROM/RAM and stack sizes are prototype limitations.
