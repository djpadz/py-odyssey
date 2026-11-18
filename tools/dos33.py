"""Minimal Apple DOS 3.3 disk image reader (DOS-order .dsk)."""
import sys, os

TYPES = {0: 'T', 1: 'I', 2: 'A', 4: 'B', 8: 'S', 0x10: 'R', 0x20: 'a', 0x40: 'b'}


class Disk:
    def __init__(self, path):
        self.data = open(path, 'rb').read()

    def sector(self, t, s):
        o = (t * 16 + s) * 256
        return self.data[o:o + 256]

    def catalog(self):
        vtoc = self.sector(17, 0)
        t, s = vtoc[1], vtoc[2]
        out = []
        seen = set()
        while t and (t, s) not in seen:
            seen.add((t, s))
            sec = self.sector(t, s)
            for i in range(7):
                e = sec[0x0B + i * 35: 0x0B + (i + 1) * 35]
                if e[0] in (0, 0xFF):
                    continue
                name = bytes(c & 0x7F for c in e[3:33]).decode('ascii').rstrip()
                ftype = e[2]
                length = e[33] | (e[34] << 8)
                out.append((name, ftype, e[0], e[1], length))
            t, s = sec[1], sec[2]
        return out

    def read_file(self, ts_t, ts_s):
        data = bytearray()
        seen = set()
        while ts_t and (ts_t, ts_s) not in seen:
            seen.add((ts_t, ts_s))
            ts = self.sector(ts_t, ts_s)
            for i in range(122):
                t, s = ts[0x0C + i * 2], ts[0x0D + i * 2]
                if t == 0 and s == 0:
                    # sparse / end
                    data += bytes(256)
                    continue
                data += self.sector(t, s)
            ts_t, ts_s = ts[1], ts[2]
        return bytes(data)


def extract(path, outdir):
    d = Disk(path)
    os.makedirs(outdir, exist_ok=True)
    for name, ft, t, s, ln in d.catalog():
        raw = d.read_file(t, s)
        typ = TYPES.get(ft & 0x7F, '?')
        if typ in 'AI':
            n = raw[0] | raw[1] << 8
            body = raw[2:2 + n]
        elif typ == 'B':
            addr = raw[0] | raw[1] << 8
            n = raw[2] | raw[3] << 8
            body = raw[4:4 + n]
            typ = 'B_%04X' % addr
        else:
            body = raw.rstrip(b'\0')
        safe = name.replace('/', '_').replace(' ', '_')
        open(os.path.join(outdir, f'{safe}.{typ}'), 'wb').write(body)
        print(f'{typ:8} {ln:4} {name!r} {len(body)}')


if __name__ == '__main__':
    extract(sys.argv[1], sys.argv[2])
