# Nova64 pipeline control foundation

This change adds a separately verified control block for a future five-stage Nova64 pipeline. It does not modify or replace the existing single-cycle `nova64_cpu`.

## Included behavior

- Load-use interlock: holds IF/ID and inserts an ID/EX bubble when an EX-stage load's destination is used by the instruction in ID.
- EX/MEM and MEM/WB forwarding selectors for both execute operands. EX/MEM wins when both stages match, and register x0 is never forwarded.
- Redirect flush signals for IF/ID and ID/EX. A resolved redirect takes priority over a younger load-use stall.
- Explicit source-use inputs prevent false stalls for instruction fields that are not actually source operands.

Forwarding selector encoding: `00` register file, `10` EX/MEM, `01` MEM/WB.

## Verification

`tests/tb_nova64_pipeline_control.sv` checks no-hazard behavior, both load-use operands, unused source suppression, forwarding priority/fallback, x0 handling, independent operand forwarding, and redirect priority. GitHub Actions runs Icarus simulation and Verilator lint.

## Important limitation

This is a control primitive, not a complete pipelined CPU and not yet connected to instruction fetch, decode, execute, memory, or writeback stages. The next integration step is to add pipeline registers and connect these controls to a separately tested pipeline core while retaining `nova64_cpu` as a reference model.
