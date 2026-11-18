"""Parse the Integer BASIC variable table embedded in APVENTURE SETUP ($0C00-$185F).

Entry layout: name bytes (high-bit ASCII; a '$' suffix is the token $40), a 0x00 flag
byte, a 2-byte little-endian pointer to the next entry, then the data.
Numeric data is 16-bit signed words; string data is high-bit ASCII ended by $1E.
"""
import sys

def try_entry(mem, base, p, end):
    q = p - base
    name = ''
    while q < len(mem) and mem[q] >= 0x80:
        name += chr(mem[q] & 0x7F)
        q += 1
    if not name:
        return None
    if mem[q] == 0x40:
        name += '$'
        q += 1
    if mem[q] != 0:
        return None
    q += 1
    nxt = mem[q] | mem[q + 1] << 8
    q += 2
    if not (p < nxt <= end):
        return None
    return name, q + base, nxt


def parse(mem, base, start, end):
    out = {}
    p = start
    while p < end:
        e = try_entry(mem, base, p, end)
        if e is None:
            skip = p
            while e is None and p < end:
                p += 1
                e = try_entry(mem, base, p, end)
            if __name__ == '__main__': print(f'  ; skipped {skip:04X}-{p - 1:04X}', file=sys.stderr)
            if e is None:
                break
        name, dstart, nxt = e
        out[name] = (p, mem[dstart - base:nxt - base])
        p = nxt
    return out


def decode(name, data):
    if name.endswith('$'):
        s = bytearray()
        for c in data:
            if c == 0x1E:
                break
            s.append(c & 0x7F)
        return s.decode('latin-1')
    w = [int.from_bytes(data[i:i + 2], 'little', signed=True) for i in range(0, len(data) - 1, 2)]
    return w


def load_bytes(mem):
    out = {}
    for n, (a, d) in parse(mem, 0x800, 0xC00, 0x185F).items():
        out.setdefault(n, decode(n, d))   # first definition wins (as in the interpreter)
    return out


def load(path):
    return load_bytes(open(path, 'rb').read())


if __name__ == '__main__':
    mem = open(sys.argv[1], 'rb').read()
    for name, (addr, data) in parse(mem, 0x800, 0xC00, 0x185F).items():
        v = decode(name, data)
        if isinstance(v, str):
            print(f'{addr:04X} {name:6} dim={len(data)} {v!r}')
        else:
            print(f'{addr:04X} {name:6} n={len(v)} {v if len(v) < 60 else "..."}')
