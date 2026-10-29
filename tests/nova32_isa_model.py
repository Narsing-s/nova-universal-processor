"""Independent executable reference semantics for the implemented Nova32 integer subset.

This is a software oracle, not a complete RISC-V emulator. It intentionally models
architectural 32-bit results and byte-lane memory behavior without importing RTL.
"""
from __future__ import annotations

MASK32 = 0xFFFF_FFFF
MASK5 = 0x1F


def u32(value: int) -> int:
    return value & MASK32


def s32(value: int) -> int:
    value = u32(value)
    return value - (1 << 32) if value & 0x8000_0000 else value


def sign_extend(value: int, bits: int) -> int:
    mask = (1 << bits) - 1
    value &= mask
    sign = 1 << (bits - 1)
    return u32(value - (1 << bits) if value & sign else value)


def alu_r(funct7: int, funct3: int, a: int, b: int) -> int:
    """Return the result for a legal Nova32 R-type ALU encoding."""
    a, b = u32(a), u32(b)
    shamt = b & MASK5
    key = (funct7 & 0x7F, funct3 & 0x7)
    if key == (0x00, 0): return u32(a + b)
    if key == (0x20, 0): return u32(a - b)
    if key == (0x00, 1): return u32(a << shamt)
    if key == (0x00, 2): return int(s32(a) < s32(b))
    if key == (0x00, 3): return int(a < b)
    if key == (0x00, 4): return a ^ b
    if key == (0x00, 5): return a >> shamt
    if key == (0x20, 5): return u32(s32(a) >> shamt)
    if key == (0x00, 6): return a | b
    if key == (0x00, 7): return a & b
    raise ValueError(f"unsupported R-type encoding funct7={funct7:#x}, funct3={funct3:#x}")


def alu_i(funct3: int, imm12: int, a: int, shamt: int | None = None,
          funct7: int = 0) -> int:
    """Return result for the implemented I-type arithmetic operations."""
    a = u32(a)
    imm = sign_extend(imm12, 12)
    if funct3 == 0: return u32(a + imm)                 # ADDI
    if funct3 == 2: return int(s32(a) < s32(imm))       # SLTI
    if funct3 == 3: return int(a < u32(imm))             # SLTIU
    if funct3 == 4: return a ^ imm                      # XORI
    if funct3 == 6: return a | imm                      # ORI
    if funct3 == 7: return a & imm                      # ANDI
    amount = (imm12 & MASK5) if shamt is None else (shamt & MASK5)
    if funct3 == 1 and funct7 == 0: return u32(a << amount)  # SLLI
    if funct3 == 5 and funct7 == 0: return a >> amount       # SRLI
    if funct3 == 5 and funct7 == 0x20: return u32(s32(a) >> amount)  # SRAI
    raise ValueError(f"unsupported I-type encoding funct7={funct7:#x}, funct3={funct3:#x}")


def branch_taken(funct3: int, a: int, b: int) -> bool:
    """Evaluate BEQ/BNE/BLT/BGE/BLTU/BGEU."""
    a, b = u32(a), u32(b)
    if funct3 == 0: return a == b
    if funct3 == 1: return a != b
    if funct3 == 4: return s32(a) < s32(b)
    if funct3 == 5: return s32(a) >= s32(b)
    if funct3 == 6: return a < b
    if funct3 == 7: return a >= b
    raise ValueError(f"unsupported branch funct3={funct3:#x}")


def load_value(word: int, byte_offset: int, funct3: int) -> int:
    """Extract and extend LB/LH/LW/LBU/LHU from an aligned little-endian word."""
    word, byte_offset = u32(word), byte_offset & 3
    if funct3 in (0, 4):  # byte
        raw = (word >> (8 * byte_offset)) & 0xFF
        return sign_extend(raw, 8) if funct3 == 0 else raw
    if funct3 in (1, 5):  # halfword
        if byte_offset & 1: raise ValueError("misaligned halfword load")
        raw = (word >> (8 * byte_offset)) & 0xFFFF
        return sign_extend(raw, 16) if funct3 == 1 else raw
    if funct3 == 2:
        if byte_offset != 0: raise ValueError("misaligned word load")
        return word
    raise ValueError(f"unsupported load funct3={funct3:#x}")


def store_lanes(value: int, byte_offset: int, funct3: int) -> tuple[int, int]:
    """Return (byte strobe, lane-positioned write data) for SB/SH/SW."""
    value, byte_offset = u32(value), byte_offset & 3
    if funct3 == 0:
        return 1 << byte_offset, u32((value & 0xFF) << (8 * byte_offset))
    if funct3 == 1:
        if byte_offset & 1: raise ValueError("misaligned halfword store")
        return 0b0011 << byte_offset, u32((value & 0xFFFF) << (8 * byte_offset))
    if funct3 == 2:
        if byte_offset != 0: raise ValueError("misaligned word store")
        return 0b1111, value
    raise ValueError(f"unsupported store funct3={funct3:#x}")
