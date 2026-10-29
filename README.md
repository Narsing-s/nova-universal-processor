# Project Nova — Universal Processor

Project Nova is an experimental processor architecture project exploring processor design through RTL simulation. It now contains two deliberately separate designs: the original educational 8-bit prototype and a new 32-bit general-purpose reference core. Neither is claimed to be production-ready silicon.

## Nova 8-bit prototype (v0.x)

- Four 8-bit registers, 4-bit PC, 16-word ROM and 16-byte data RAM
- 16-bit fixed-width instruction encoding
- Arithmetic, memory, compare/branch, jump/call/return, stack and bitwise instructions
- Independent 16-byte data stack and 16-entry return-address stack
- Regression testbench in `tests/tb_nova_cpu.sv`

## Nova32 reference core (early implementation)

File: `rtl32/nova32_cpu.sv`

- 32-bit datapath and byte-addressed program counter
- 32 integer registers with x0 hardwired to zero
- Separate instruction and data-memory interfaces
- RV32I-inspired arithmetic, logical, shift, load/store, branch, JAL/JALR, LUI and AUIPC operations
- Byte/halfword/word load/store support with byte strobes and alignment checks
- Custom `32'h0000000B` HALT instruction
- Unsupported encodings and misaligned accesses stop execution and assert `illegal_instruction`
- Single-cycle reference implementation; no pipeline, caches, interrupts, MMU, privilege modes or full RV32I compatibility yet

This is a documented subset, not a claim of full RISC-V compliance. See [docs/NOVA32_ISA.md](docs/NOVA32_ISA.md) for the implemented subset and [docs/NOVA32_IMPLEMENTATION_PLAN.md](docs/NOVA32_IMPLEMENTATION_PLAN.md) for the roadmap.

## Run simulations locally

Install Icarus Verilog, then run both regression suites:

```bash
iverilog -g2012 -Wall -s tb_nova_cpu -o nova8_test rtl/nova_cpu.sv tests/tb_nova_cpu.sv
vvp nova8_test
iverilog -g2012 -Wall -s tb_nova32_cpu -o nova32_test rtl32/nova32_cpu.sv tests/tb_nova32_cpu.sv
vvp nova32_test
```

GitHub Actions runs both suites on pushes and pull requests.

## Important limitations

The core is a starting point for learning and iterative verification. Simulation passing only proves tested behavior. It does not establish timing closure, physical performance, power efficiency, security, full ISA compliance, or suitability for a phone/desktop CPU. A pipeline, benchmark suite, synthesis evaluation and broader compliance tests are future work.
