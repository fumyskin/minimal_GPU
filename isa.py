"""Single source of truth for the instruction set: opcode table, encode/decode,
and a two-pass assembler. The simulator (and later the RTL decoder) must agree
with encode()/decode() here. No opcode enum is duplicated anywhere else."""

import fixedpoint as fp

OPCODES = {
    "NOP": 0x00, 
    "LI": 0x01, 
    "LANEID": 0x02, 
    "MOV": 0x03,
    "ADD": 0x04, 
    "SUB": 0x05, 
    "MUL": 0x06, 
    "ESCAPE": 0x07,
    "MASKALL": 0x08, 
    "SETLOOP": 0x09, 
    "ENDLOOP": 0x0A,
    "STORE": 0x0B, 
    "HALT": 0x0C,
}
MNEMONIC = {v: k for k, v in OPCODES.items()}


def _fit(value, bits, what):
    if not (0 <= value < (1 << bits)):
        raise ValueError(f"{what}: {value} does not fit in unsigned {bits} bits")
    return value


def encode(op, rd=0, ra=0, rb=0, imm=0):
    """Fields placed by masking -- never by adding shifted values, which would
    let an oversized/negative field carry into its neighbor."""
    return (((OPCODES[op] & 0x3F) << 26) | ((rd & 0xF) << 22) |
            ((ra & 0xF) << 18) | ((rb & 0xF) << 14) | (imm & 0x3FFF)) & 0xFFFFFFFF


def encode_li(rd, raw18):
    """LI carries a full 18-bit word: value[17:14] -> rb, value[13:0] -> imm."""
    raw = raw18 & 0x3FFFF
    return encode("LI", rd=rd, ra=0, rb=(raw >> 14) & 0xF, imm=raw & 0x3FFF)


def decode(word):
    return ((word >> 26) & 0x3F, (word >> 22) & 0xF, (word >> 18) & 0xF,
            (word >> 14) & 0xF, word & 0x3FFF)


def decode_li_raw(word):
    """Reassemble the 18-bit signed LI constant from {rb, imm}."""
    _, _, _, rb, imm = decode(word)
    raw = (rb << 14) | imm
    return raw - (1 << 18) if (raw & (1 << 17)) else raw


def patch(code, index, value):
    """Rebind a per-launch immediate (host behaviour). LI -> rewrite the 18-bit
    constant; small-immediate ops -> rewrite the 14-bit imm field."""
    op, rd, ra, rb, imm = decode(code[index])
    if op == OPCODES["LI"]:
        code[index] = encode_li(rd, value & 0x3FFFF)
    else:
        code[index] = encode(MNEMONIC[op], rd=rd, ra=ra, rb=rb,
                             imm=_fit(value & 0x3FFF, 14, f"patch @{index}"))


def assemble(source, defines=None):
    """Return (code, params, labels). `defines` resolves assemble-time symbols
    (e.g. MAX_ITER, DX). Any remaining unknown symbol becomes a per-launch
    parameter: the instruction is emitted with a 0 placeholder and its index is
    recorded so the loader can patch() it."""
    defines = dict(defines or {})
    labels, program = {}, []
    addr = 0
    for lineno, line in enumerate(source.splitlines(), 1):
        line = line.split(";", 1)[0].strip()
        if not line:
            continue
        if line.split()[0].endswith(":"):
            lbl, _, rest = line.partition(":")
            labels[lbl.strip()] = addr
            line = rest.strip()
            if not line:
                continue
        program.append((lineno, addr, line))
        addr += 1

    code, params = [0] * addr, {}
    for lineno, a, line in program:
        parts = line.replace(",", " ").split()
        op, args = parts[0].upper(), parts[1:]
        if op not in OPCODES:
            raise ValueError(f"line {lineno}: unknown opcode '{op}'")
        code[a] = _encode_line(op, args, a, defines, labels, params, lineno)
    return code, params, labels


def _encode_line(op, args, index, defines, labels, params, lineno):
    def reg(tok):
        if not tok.upper().startswith("V") or not tok[1:].isdigit():
            raise ValueError(f"line {lineno}: expected register, got '{tok}'")
        r = int(tok[1:])
        if not 0 <= r <= 15:
            raise ValueError(f"line {lineno}: register {tok} out of range")
        return r

    def li_raw(tok):
        # 18-bit raw word for an LI operand: #int / float / define / parameter
        if tok.startswith("#"):
            return int(tok[1:], 0) & 0x3FFFF
        if tok in defines:
            v = defines[tok]
            return (fp.to_fixed(v) if isinstance(v, float) else int(v)) & 0x3FFFF
        if "." in tok:
            return fp.to_fixed(float(tok)) & 0x3FFFF
        try:
            return int(tok, 0) & 0x3FFFF
        except ValueError:
            params[tok] = index          # undefined -> per-launch parameter
            return 0

    def uimm(tok):
        # unsigned 14-bit for SETLOOP / ENDLOOP / STORE
        if tok in defines:
            val = int(defines[tok])
        elif tok in labels:
            val = labels[tok]
        else:
            try:
                val = int(tok, 0)
            except ValueError:
                params[tok] = index
                val = 0
        return _fit(val, 14, f"line {lineno} immediate")

    if op in ("NOP", "MASKALL", "HALT"):
        return encode(op)
    if op == "LANEID":
        return encode(op, rd=reg(args[0]))
    if op == "LI":
        return encode_li(reg(args[0]), li_raw(args[1]))
    if op == "MOV":
        return encode(op, rd=reg(args[0]), ra=reg(args[1]))
    if op in ("ADD", "SUB", "MUL"):
        return encode(op, rd=reg(args[0]), ra=reg(args[1]), rb=reg(args[2]))
    if op == "ESCAPE":
        return encode(op, ra=reg(args[0]), rb=reg(args[1]))
    if op in ("SETLOOP", "ENDLOOP"):
        return encode(op, imm=uimm(args[0]))
    if op == "STORE":
        return encode(op, ra=reg(args[0]), imm=uimm(args[1]))
    raise ValueError(f"line {lineno}: unhandled opcode '{op}'")