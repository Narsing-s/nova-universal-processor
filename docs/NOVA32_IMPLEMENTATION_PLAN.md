# Nova 32-bit General-Purpose CPU: Implementation Plan

## Scope and compatibility

Keep rtl/nova_cpu.sv as the educational Nova 8-bit v0.x reference. Do not silently change its instruction encoding or claim it is a 32-bit processor. Build the 32-bit architecture as a separate module and directory so the current prototype remains usable.

## Recommended v1 target

- 32-bit integer datapath, 32-bit architectural registers, and a 32-bit program counter.
- A documented instruction-address model and alignment policy.
- 32 general-purpose registers, optionally using a RISC-V-inspired zero register convention.
- Separate instruction and data interfaces; keep program storage, data RAM, and stack storage independent.
- Explicit load/store, arithmetic, logical, shift, compare/branch, jump/link, and illegal-instruction behavior.
- Byte-addressed memory with defined endianness and alignment behavior.
- Specify reset and trap behavior before adding performance features.
- Start with a simple single-cycle reference implementation; optimize only after reference tests pass.
- Later stages may include pipelining, forwarding/stall logic, branch recovery, interrupts, caches, and bus/peripheral interfaces.

## Prioritized delivery plan

### P0 — Stabilize and verify the existing 8-bit reference
1. Give the data stack independent storage instead of aliasing data RAM.
2. Use pointer widths capable of representing every occupancy from 0 through 16.
3. Permit all 16 stack entries and halt safely on the next overflow attempt.
4. Add regression coverage for the demo, CALL/RET, bitwise operations, stack/RAM isolation, and stack capacity.
5. Run simulation in CI on pushes and pull requests.

### P1 — Specify the 32-bit ISA
1. Document register roles, instruction formats, opcode map, flags/traps, branch semantics, memory alignment, and reset contract.
2. Decide whether Nova is a custom ISA or a compatible subset. Prefer a documented RISC-V RV32I subset if compatibility and tooling are priorities.
3. Add assembly encoding/decoding helpers and hand-checked golden vectors.

### P2 — Build a separate 32-bit reference core
1. Add rtl32/nova32_cpu.sv with its own interface and tests.
2. Start with register/immediate operations, loads/stores, branches/jumps, and halt/trap behavior.
3. Test wraparound, signed overflow, alignment, and PC boundaries with explicit-width arithmetic.
4. Keep the 8-bit module and demo behavior intact.

### P3 — Validate before optimizing
- Run simulation and lint in CI; add assertions for reset, illegal instructions, memory boundaries, and control flow.
- Add reproducible benchmarks for simulated instruction count and cycles per test program; measure synthesis area/timing when tools are available.
- Add formal checks or reference-model comparison before pipelining.
- Only then introduce pipeline stages, forwarding, stalls, and branch recovery.

## Acceptance criteria

- Existing 8-bit demonstration passes.
- Data-stack operations cannot alter normal RAM.
- All 16 entries of both stacks are usable; the next push/call stops without an out-of-bounds write.
- CI runs reproducibly from a clean checkout.
- 32-bit work lives in separate files and does not break the 8-bit prototype.
- Performance claims are backed by repeatable benchmarks and synthesis, not inferred from RTL size.

## Limitation

This is an RTL/simulation learning project, not a finished physical processor. Simulation passing is not proof of timing closure, power efficiency, security, or silicon readiness.
