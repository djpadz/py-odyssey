"""Apple II hi-res screen and the Programmer's Aid #1 shape routines.

The original game ships a relocated copy of Apple's "Programmer's Aid #1" hi-res
package at $0800.  Integer BASIC drives it through CALLs:

    CALL 2048  ($0800)  INIT   - clear the screen to black, show hi-res
    CALL 2865  ($0B31)  BKGND  - fill the screen with COLR
    CALL 2871  ($0B37)  DRAW   - draw shape SHAPE at X0,Y0 in COLR (ROT, SCALE)
    CALL 2884  ($0B44)  DRAW1  - XOR-draw the same shape (erase by drawing twice)

PEEK(810) ($032A) is the collision counter.  It is reproduced exactly because the
Sea part uses it to decide whether the ship has run aground.

The screen is kept as the real 8K byte image so that the colour quirks
and the collision counts behave as they did on the original.
"""

WIDTH, HEIGHT = 280, 192

# $09E3: bit masks for the 7 pixels of a byte (high bit always included)
_MASKS = [0x81, 0x82, 0x84, 0x88, 0x90, 0xA0, 0xC0]
# $09EB: cosine table used for rotation (16 steps per quadrant), plus the
# trailing $FF at $09FB.
_COS = [0xFF, 0xFE, 0xFA, 0xF4, 0xEC, 0xE1, 0xD4, 0xC5,
        0xB4, 0xA1, 0x8D, 0x78, 0x61, 0x49, 0x31, 0x18, 0xFF]


def row_offset(y):
    """Offset of row y within the 8K hi-res page."""
    return (y & 7) * 0x400 + ((y >> 3) & 7) * 0x80 + (y >> 6) * 0x28


ROW = [row_offset(y) for y in range(HEIGHT)]


class RangeError(Exception):
    """Integer BASIC '*** RANGE ERR' raised by the graphics routines."""


def shift_color(c):
    """Colour byte to use in odd byte columns ($08A2)."""
    return c ^ 0x7F if ((c << 1) & 0xFF) - 0xC0 & 0x80 else c


class Hires:
    def __init__(self, shape_table=b'', mem=None):
        # `mem` may be a view into a larger memory image (the Machine's RAM).
        self.mem = mem if mem is not None else memoryview(bytearray(0x2000))
        self.shapes = bytes(shape_table)
        self.collisions = 0       # PEEK(810)
        self.dirty_rows = set(range(HEIGHT))

    @property
    def dirty(self):
        return bool(self.dirty_rows)

    @dirty.setter
    def dirty(self, value):
        if value:
            self.dirty_rows = set(range(HEIGHT))
        else:
            self.dirty_rows = set()

    # --- whole screen -----------------------------------------------------------------
    def load(self, data):
        self.mem[:] = data[:0x2000].ljust(0x2000, b'\0')
        self.dirty = True

    def fill(self, color):
        """BKGND: every byte of the page gets the colour, shifted in odd columns."""
        c0, c1 = color & 0xFF, shift_color(color & 0xFF)
        # Every row starts at an even address, so odd addresses are odd columns.
        self.mem[:] = bytes([c0, c1]) * 0x1000
        self.dirty = True

    def clear(self):
        self.fill(0)

    # --- shapes -----------------------------------------------------------------------
    def _shape_addr(self, n):
        if n == 0 or n > self.shapes[0]:
            raise RangeError('shape %d' % n)
        return self.shapes[2 * n] | self.shapes[2 * n + 1] << 8

    def draw(self, shape, x, y, color, rot=0, scale=1, xor=False):
        """DRAW / DRAW1 at (x, y).  Returns the collision count."""
        if not (0 <= x < WIDTH and 0 <= y < HEIGHT) or not (0 <= color < 256) \
                or not (0 <= rot < 256) or not (0 <= scale < 256):
            raise RangeError('draw parameters')
        p = self._shape_addr(shape)
        r = rot & 15
        sin_step = _COS[r]                       # $50
        cos_step = (_COS[16 - r] + 1) & 0xFF     # $52
        quad = (rot >> 4) & 0x0F                 # $53
        mem = self.mem
        hcolor = color
        self.collisions = 0
        coll = 0
        sh = self.shapes
        touched = self.dirty_rows
        while True:
            b = sh[p]
            if b == 0:
                break
            while True:
                acc1 = acc2 = 0x80
                for _ in range(scale or 256):
                    acc1 += sin_step + 1
                    steps = []
                    if acc1 > 0xFF:
                        acc1 &= 0xFF
                        steps.append(0)
                    acc2 += cos_step
                    if acc2 > 0xFF:
                        acc2 &= 0xFF
                        steps.append(1)
                    for extra in steps:
                        if b & 4:
                            col = x // 7
                            addr = ROW[y] + col
                            mask = _MASKS[x % 7]
                            c = shift_color(hcolor) if col & 1 else hcolor
                            old = mem[addr]
                            touched.add(y)
                            if xor:
                                bit = 0x7F & mask & old
                                if bit:
                                    mem[addr] = old ^ bit
                                else:
                                    coll += 1
                                    mem[addr] = old ^ (0x7F & mask)
                            else:
                                d = (old ^ c) & mask
                                if d:
                                    mem[addr] = old ^ d
                                else:
                                    coll += 1
                        d = (b + quad + extra) & 3
                        if d == 0:
                            y = y - 1 if y else HEIGHT - 1
                        elif d == 1:
                            x = x + 1 if x < WIDTH - 1 else 0
                        elif d == 2:
                            y = y + 1 if y < HEIGHT - 1 else 0
                        else:
                            x = x - 1 if x else WIDTH - 1
                b >>= 3
                if not b:
                    break
            p += 1
        self.collisions = coll & 0xFF
        return self.collisions

    # --- display ----------------------------------------------------------------------
    def render_row(self, y, palette):
        """Colours of the 280 pixels of row y.

        Simple colour model: a lit pixel next to another lit pixel is white;
        an isolated lit pixel takes violet/green (high bit clear) or blue/orange
        (high bit set) by column parity, and a dark pixel between two lit ones
        takes the artefact colour of its neighbours.
        """
        black, white, violet, green, blue, orange = palette
        base = ROW[y]
        bits = []
        hi = []
        for v in self.mem[base:base + 40]:
            h = v & 0x80
            for i in range(7):
                bits.append((v >> i) & 1)
                hi.append(h)
        bits.append(0)
        row = []
        prev = 0
        for x in range(WIDTH):
            on = bits[x]
            nxt = bits[x + 1]
            if on:
                if prev or nxt:
                    row.append(white)
                elif hi[x]:
                    row.append(orange if x & 1 else blue)
                else:
                    row.append(green if x & 1 else violet)
            elif prev and nxt:
                if hi[x]:
                    row.append(blue if x & 1 else orange)
                else:
                    row.append(violet if x & 1 else green)
            else:
                row.append(black)
            prev = on
        return row
