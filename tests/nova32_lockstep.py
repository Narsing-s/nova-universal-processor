#!/usr/bin/env python3
"""Generate a deterministic Nova32 program and instruction-by-instruction golden trace.

The architectural model below is deliberately separate from the SystemVerilog RTL.
It models only the documented Nova32 subset and emits hex files consumed by
 tb_nova32_lockstep.sv. Run from the repository root:
  python3 tests/nova32_lockstep.py --out build/nova32_lockstep
"""
from __future__ import annotations

import argparse
from pathlib import Path

MASK = 0xFFFF_FFFF
HALT = 0x0000000B
OP_LOAD, OP_IMM, OP_AUIPC, OP_STORE = 0x03, 0x13, 0x17, 0x23
OP_REG, OP_LUI, OP_BRANCH, OP_JALR, OP_JAL = 0x33, 0x37, 0x63, 0x67, 0x6F


def u32(v): return v & MASK
def s32(v):
    v = u32(v)
    return v - (1 << 32) if v & 0x80000000 else v
def sext(v, bits):
    v &= (1 << bits) - 1
    return u32(v - (1 << bits) if v & (1 << (bits - 1)) else v)

def enc_i(imm, rs1, f3, rd, op=OP_IMM):
    return (((imm & 0xFFF) << 20) | (rs1 << 15) | (f3 << 12) | (rd << 7) | op) & MASK
def enc_r(f7, rs2, rs1, f3, rd):
    return (f7 << 25) | (rs2 << 20) | (rs1 << 15) | (f3 << 12) | (rd << 7) | OP_REG
def enc_s(imm, rs2, rs1, f3):
    imm &= 0xFFF
    return ((imm >> 5) << 25) | (rs2 << 20) | (rs1 << 15) | (f3 << 12) | ((imm & 31) << 7) | OP_STORE
def enc_b(imm, rs2, rs1, f3):
    imm &= 0x1FFF
    return (((imm >> 12) & 1) << 31) | (((imm >> 5) & 0x3F) << 25) | (rs2 << 20) | (rs1 << 15) | (f3 << 12) | (((imm >> 1) & 15) << 8) | (((imm >> 11) & 1) << 7) | OP_BRANCH
def enc_u(imm20, rd, op):
    return ((imm20 & 0xFFFFF) << 12) | (rd << 7) | op
def enc_j(imm, rd):
    imm &= 0x1FFFFF
    return (((imm >> 20) & 1) << 31) | (((imm >> 1) & 0x3FF) << 21) | (((imm >> 11) & 1) << 20) | (((imm >> 12) & 0xFF) << 12) | (rd << 7) | OP_JAL
def nop(): return enc_i(0, 0, 0, 0)

def make_program():
    p = []
    # Base arithmetic, signed immediates, all R-type ALU operations.
    p += [enc_i(-15,0,0,1), enc_i(7,0,0,2)]
    for f7,f3,rd in [(0,0,3),(0x20,0,4),(0,1,5),(0,2,6),(0,3,7),
                      (0,4,8),(0,5,9),(0x20,5,10),(0,6,11),(0,7,12)]:
        p.append(enc_r(f7,2,1,f3,rd))
    # I-type arithmetic and shift operations.
    p += [enc_i(-1,1,0,13), enc_i(1,1,2,14), enc_i(1,1,3,15),
          enc_i(0x55,1,4,16), enc_i(0x20,1,6,17), enc_i(0x0F,1,7,18),
          enc_i((0<<5)|1,1,1,19), enc_i((0x20<<5)|1,1,5,20),
          enc_i((0<<5)|1,1,5,21)]
    # U-type.
    p += [enc_u(0x12345,22,OP_LUI), enc_u(0x00001,23,OP_AUIPC)]
    # Store/load lane behavior using base x0 and data x22.
    p += [enc_s(0,22,0,2), enc_i(0,0,2,24,OP_LOAD),
          enc_s(1,22,0,0), enc_i(1,0,0,25), enc_i(1,25,0,25),
          enc_i(1,0,0,26), enc_i(1,26,0,26),
          enc_i(1,0,0,27), enc_i(1,27,0,27),
          enc_i(0,0,0,28,OP_LOAD), enc_i(1,0,4,29,OP_LOAD),
          enc_i(2,0,1,30,OP_LOAD), enc_i(2,0,5,31,OP_LOAD)]
    # Branches: taken branch skips the poison write, then not-taken branch falls through.
    p += [enc_b(8,2,2,0), enc_i(99,0,0,5), enc_i(42,0,0,5),
          enc_b(8,1,2,0), enc_i(17,0,0,6), enc_i(0,0,0,6)]
    # JAL skips poison write; JALR targets address computed in x1 via AUIPC/ADDI.
    jal_index = len(p)
    p += [enc_j(8,7), enc_i(111,0,0,8), enc_i(77,0,0,8)]
    # JALR target set to the instruction after the skipped instruction.
    jalr_pc = len(p) * 4
    target_pc = jalr_pc + 12
    p += [enc_i(target_pc,0,0,9), enc_i(0,9,0,10,OP_JALR),
          enc_i(123,0,0,11), enc_i(88,0,0,11)]
    p += [HALT]
    return p

def run_model(program):
    regs = [0] * 32
    mem = [0] * 64
    pc, halted, illegal = 0, False, False
    trace = []
    max_steps = 256
    for _ in range(max_steps):
        if pc & 3:
            illegal, halted = True, True
        if pc // 4 >= len(program):
            raise RuntimeError(f"program escaped instruction image at PC {pc:#x}")
        ins = program[pc // 4]
        op, rd, f3 = ins & 0x7F, (ins >> 7) & 31, (ins >> 12) & 7
        rs1, rs2, f7 = (ins >> 15) & 31, (ins >> 20) & 31, (ins >> 25) & 127
        a, b = regs[rs1], regs[rs2]
        ii = sext(ins >> 20, 12)
        si = sext(((ins >> 25) << 5) | ((ins >> 7) & 31), 12)
        bi = sext((((ins >> 31) & 1) << 12) | (((ins >> 7) & 1) << 11) |
                  (((ins >> 25) & 0x3F) << 5) | (((ins >> 8) & 15) << 1), 13)
        ui = ins & 0xFFFFF000
        ji = sext((((ins >> 31) & 1) << 20) | (((ins >> 12) & 0xFF) << 12) |
                  (((ins >> 20) & 1) << 11) | (((ins >> 21) & 0x3FF) << 1), 21)
        npc, write = u32(pc + 4), None
        if ins == HALT:
            halted = True
        elif op == OP_LUI: write = (rd, ui)
        elif op == OP_AUIPC: write = (rd, u32(pc + ui))
        elif op == OP_IMM:
            sh = (ins >> 20) & 31
            if f3 == 0: result = u32(a + ii)
            elif f3 == 2: result = int(s32(a) < s32(ii))
            elif f3 == 3: result = int(a < u32(ii))
            elif f3 == 4: result = u32(a ^ ii)
            elif f3 == 6: result = u32(a | ii)
            elif f3 == 7: result = u32(a & ii)
            elif f3 == 1 and f7 == 0: result = u32(a << sh)
            elif f3 == 5 and f7 == 0: result = a >> sh
            elif f3 == 5 and f7 == 0x20: result = u32(s32(a) >> sh)
            else: illegal = halted = True; result = 0
            if not halted: write = (rd, result)
        elif op == OP_REG:
            sh = b & 31
            ops = {(0,0):u32(a+b),(0x20,0):u32(a-b),(0,1):u32(a<<sh),
                   (0,2):int(s32(a)<s32(b)),(0,3):int(a<b),(0,4):u32(a^b),
                   (0,5):a>>sh,(0x20,5):u32(s32(a)>>sh),(0,6):u32(a|b),(0,7):u32(a&b)}
            key = (f7,f3)
            if key not in ops: illegal = halted = True
            else: write = (rd, ops[key])
        elif op == OP_LOAD or op == OP_STORE:
            imm = si if op == OP_STORE else ii
            ea = u32(a + imm)
            offset, index = ea & 3, (ea >> 2) & 63
            if op == OP_LOAD:
                word = mem[index]
                if f3 in (0,4):
                    raw = (word >> (offset*8)) & 255
                    val = sext(raw,8) if f3 == 0 else raw
                elif f3 in (1,5) and not (offset & 1):
                    raw = (word >> (offset*8)) & 65535
                    val = sext(raw,16) if f3 == 1 else raw
                elif f3 == 2 and offset == 0: val = word
                else: illegal = halted = True; val = 0
                if not halted: write = (rd, val)
            else:
                if f3 == 0:
                    strobe, data = 1 << offset, u32(b << (offset*8))
                elif f3 == 1 and not (offset & 1):
                    strobe, data = 3 << offset, u32(b << (offset*8))
                elif f3 == 2 and offset == 0: strobe, data = 15, b
                else: illegal = halted = True; strobe = data = 0
                if not halted:
                    for lane in range(4):
                        if strobe & (1 << lane):
                            mask = 255 << (lane*8)
                            mem[index] = u32((mem[index] & ~mask) | (data & mask))
        elif op == OP_BRANCH:
            take = {0:a==b,1:a!=b,4:s32(a)<s32(b),5:s32(a)>=s32(b),6:a<b,7:a>=b}.get(f3)
            if take is None: illegal = halted = True
            elif take:
                npc = u32(pc + bi)
                if npc & 3: illegal = halted = True
        elif op == OP_JAL:
            write = (rd, u32(pc+4)); npc = u32(pc+ji)
            if npc & 3: illegal = halted = True
        elif op == OP_JALR and f3 == 0:
            write = (rd, u32(pc+4)); npc = u32(a+ii) & 0xFFFF_FFFE
            if npc & 3: illegal = halted = True
        else:
            illegal = halted = True
        if write and not halted and write[0] != 0: regs[write[0]] = u32(write[1])
        regs[0] = 0
        if not halted or ins == HALT:
            # A valid HALT leaves PC unchanged in this RTL.
            if ins != HALT: pc = npc
        trace.append((pc, int(halted), int(illegal), regs.copy(), mem.copy()))
        if halted: return trace
    raise RuntimeError("reference program exceeded step limit")

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--out", default="build/nova32_lockstep")
    args = parser.parse_args()
    out = Path(args.out)
    out.mkdir(parents=True, exist_ok=True)
    program = make_program()
    trace = run_model(program)
    (out / "program.hex").write_text("".join(f"{ins:08x}\n" for ins in program), encoding="ascii")
    fields_per_step = 3 + 32 + 64
    width = fields_per_step * 32
    with (out / "trace.hex").open("w", encoding="ascii") as stream:
        for pc, halted, illegal, regs, mem in trace:
            fields = [pc, halted, illegal] + regs + mem
            stream.write("".join(f"{u32(v):08x}" for v in fields) + "\n")
    (out / "trace_length.txt").write_text(str(len(trace)) + "\n", encoding="ascii")
    print(f"Generated {len(program)} instructions and {len(trace)} expected architectural checkpoints in {out}")

if __name__ == "__main__":
    main()
