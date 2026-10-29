# Nova32 ISA subset (early reference)

Nova32 uses 32-bit fixed-width instructions with RV32I-inspired encodings and a byte-addressed 32-bit PC. Instructions are fetched from an external instruction-memory interface. Data memory is external and separate from instruction storage. The core is single-cycle.

## Architectural state

- x0 reads as zero; writes to x0 are discarded.
- x1–x31 are 32-bit general-purpose registers.
- PC starts at 0 on reset and normally advances by 4 bytes.
- There is no compressed-instruction support. Control-flow targets must be 4-byte aligned.
- Memory is little-endian. The data interface presents the aligned 32-bit word containing the byte address; \`data_wstrb\` selects byte lanes.
- Reset clears registers, PC, halted and illegal_instruction.
- Illegal encodings and unsupported/misaligned accesses halt the core and set \`illegal_instruction\`.

## Implemented instruction subset

| Family | Operations |
|---|---|
| U-type | LUI, AUIPC |
| I-type arithmetic | ADDI, SLTI, SLTIU, XORI, ORI, ANDI, SLLI, SRLI, SRAI |
| R-type arithmetic | ADD, SUB, SLL, SLT, SLTU, XOR, SRL, SRA, OR, AND |
| Loads | LB, LH, LW, LBU, LHU |
| Stores | SB, SH, SW |
| Branches | BEQ, BNE, BLT, BGE, BLTU, BGEU |
| Jumps | JAL, JALR (funct3 must be zero) |
| Nova custom | HALT: exact instruction word \`0x0000000B\` |

## Memory interface contract

- \`data_addr\` is the effective byte address.
- \`data_rdata\` must contain the aligned 32-bit word at address \`{data_addr[31:2], 2'b00}\`.
- For stores, \`data_wstrb[n]\` enables byte lane n of \`data_wdata\`. The memory system writes enabled lanes at the aligned word address.
- Byte accesses may use any byte offset. Halfword accesses require bit 0 = 0. Word accesses require bits [1:0] = 0.
- The core does not include a bus protocol, wait states, caches, MMU, interrupts, privilege modes, atomics, CSRs or exception-vector mechanism.

## Status

This subset is intentionally incomplete and is not yet a formally validated or fully compliant RISC-V implementation. Add differential tests and lint before expanding the ISA or optimizing the microarchitecture.
