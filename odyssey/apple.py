"""A small model of the parts of an Apple II that Odyssey uses.

The game logic talks to a `Machine`, which provides what Integer BASIC and the
monitor provided on the original:

* 40x24 text output with a scroll window (POKE 34/35), cursor (36/37) and
  inverse/flash text (POKE 50), plus HOME, CLREOL, CLREOP, TAB and VTAB.
* The display switches: text/graphics, mixed, page 1/2, lo-res/hi-res.
* Lo-res plotting (COLOR=, PLOT, HLIN, VLIN, SCRN) on text page 1.
* The hi-res page with the Programmer's Aid shape routines (see hires.py).
* The keyboard latch (PEEK(-16384) / POKE -16368,0).
* The speaker (the SOUND routine at $0342 and raw clicks).

Screen memory is kept as real Apple II memory (a 64K bytearray).  That keeps
the game's own memory-copy tricks working: the Cavern part saves and restores
its lo-res map with the monitor MOVE routine.

The machine has no knowledge of how it is shown; a frontend (pygame window or
headless transcript) is attached to it.
"""
import random
import time

from .hires import Hires, RangeError

TEXT1, TEXT2, HIRES1 = 0x400, 0x800, 0x2000

# Base address offsets of the 24 text rows inside a text page.
TEXT_ROW = [(r & 7) * 0x80 + (r >> 3) * 0x28 for r in range(24)]

NORMAL, INVERSE, FLASH = 0xFF, 0x3F, 0x7F

# Integer BASIC runs roughly this many simple statements per second.  Busy
# loops in the original (FOR C=1 TO D: NEXT C) are converted to real time with it.
STATEMENT_TIME = 0.0006

# The Apple II's 6502 runs at 1.0227 MHz.  Sound timing is worked out from
# cycle counts, and the BASIC statements around a sound (POKE ...: CALL 834)
# take about a millisecond each - the gaps they leave are part of the sound.
CPU_HZ = 1_022_727
BASIC_STATEMENT = 0.0011
PEEK_TERM = 0.00045            # one more PEEK(-16336) inside an expression
NEXT_TIME = 0.0013             # NEXT, round the loop


class BasicError(Exception):
    """An Integer BASIC run-time error (the original would stop with '*** ... ERR')."""


class ScriptEnd(Exception):
    """Headless runs: the scripted keystrokes ran out."""


class Quit(Exception):
    """The player closed the window."""


def idiv(a, b):
    """Integer BASIC division (truncates toward zero)."""
    if b == 0:
        raise BasicError('>32767')
    q = abs(a) // abs(b)
    return q if (a >= 0) == (b >= 0) else -q


def imod(a, b):
    """Integer BASIC MOD (the result takes the sign of the dividend)."""
    if b == 0:
        raise BasicError('>32767')
    return a - idiv(a, b) * b


def sgn(a):
    return (a > 0) - (a < 0)


def clip16(v):
    """Integer BASIC numbers are 16-bit signed."""
    if not -32767 <= v <= 32767:
        raise BasicError('>32767')
    return v


class Frontend:
    """Interface the machine uses to show itself and get keys."""
    machine = None

    def poll(self):
        pass

    def wait(self, seconds):
        pass

    def echo(self, c):
        pass

    def clicks(self, intervals):
        pass


class Machine:
    def __init__(self, shape_table=b'', low_memory=b'', rng=None):
        self.ram = bytearray(0x10000)
        if low_memory:
            # APVENTURE SETUP occupies $0800-$1FFF; text page 2 is shown in the
            # Cavern as "darkness" and on the island as a magic flash.
            self.ram[0x800:0x800 + len(low_memory)] = low_memory
        self.hires = Hires(shape_table, memoryview(self.ram)[HIRES1:HIRES1 + 0x2000])
        self.rng = rng or random.Random()
        self.frontend = Frontend()
        # soft switches
        self.text_mode = True
        self.mixed = False
        self.page2 = False
        self.hires_mode = False
        # text window (zero page $20-$25) and inverse flag ($32)
        self.wndtop, self.wndbtm = 0, 24
        self.ch, self.cv = 0, 0
        self.invflg = NORMAL
        self.color = 0            # lo-res COLOR= (stored as both nibbles)
        self.kbd = 0              # keyboard latch $C000
        self.text_dirty = True
        self.clock = 0.0          # seconds of emulated time spent waiting
        self.home()

    # --- frontend plumbing ---------------------------------------------------------
    def attach(self, frontend):
        self.frontend = frontend
        frontend.machine = self

    def tick(self, seconds=0.0):
        """Let `seconds` of time pass, keeping the window alive and reading keys."""
        self.clock += seconds
        self.frontend.wait(seconds)

    def statements(self, n):
        """Time taken by `n` simple BASIC statements."""
        self.tick(n * STATEMENT_TIME)

    def rnd(self, n):
        """RND(n): 0..n-1 (and 0..n+1 for negative n, as Integer BASIC does)."""
        if n == 0:
            return 0
        if n > 0:
            return self.rng.randrange(n)
        return -self.rng.randrange(-n)

    # --- keyboard -------------------------------------------------------------------
    def key_pressed(self, ascii_code):
        """Called by the frontend when a key goes down."""
        self.kbd = (ascii_code & 0x7F) | 0x80

    def peek_kbd(self):
        """PEEK(-16384).  Polling is how the game waits, so let a little time pass."""
        self.frontend.poll()
        return self.kbd

    def clear_strobe(self):
        """POKE -16368,0"""
        self.kbd &= 0x7F

    def wait_key(self):
        """Wait for a key press and return its code (>= 128); strobe cleared."""
        while True:
            v = self.peek_kbd()
            if v >= 128:
                self.clear_strobe()
                return v
            self.tick(0.01)

    def delay(self, iterations, per_iteration=3):
        """FOR C=1 TO n: IF PEEK(-16384)<128 THEN NEXT C - a pause cut short by a key.

        Returns True if a key ended the pause early.
        """
        step = per_iteration * STATEMENT_TIME
        left = iterations
        while left > 0:
            if self.peek_kbd() >= 128:
                return True
            chunk = min(left, 25)
            self.tick(chunk * step)
            left -= chunk
        return False

    def pause(self, iterations):
        """FOR C=1 TO n: NEXT C - a plain busy-wait."""
        self.tick(iterations * 2 * STATEMENT_TIME)

    # --- display switches (POKE -16304..-16297, TEXT, GR) ---------------------------------
    def switch(self, address):
        if address in (-16304, 0xC050):
            self.text_mode = False
        elif address in (-16303, 0xC051):
            self.text_mode = True
        elif address in (-16302, 0xC052):
            self.mixed = False
        elif address in (-16301, 0xC053):
            self.mixed = True
        elif address in (-16300, 0xC054):
            self.page2 = False
        elif address in (-16299, 0xC055):
            self.page2 = True
        elif address in (-16298, 0xC056):
            self.hires_mode = False
        elif address in (-16297, 0xC057):
            self.hires_mode = True
        self.text_dirty = True

    def text(self):
        """TEXT: text mode, page 1, full-screen window, cursor to the bottom line."""
        self.text_mode = True
        self.page2 = False
        self.wndtop, self.wndbtm = 0, 24
        self.vtab(24)
        self.text_dirty = True

    def gr(self):
        """GR: mixed lo-res graphics, clear the graphics area, window rows 20-23."""
        self.text_mode = False
        self.mixed = True
        for row in range(20):
            a = TEXT1 + TEXT_ROW[row]
            self.ram[a:a + 40] = bytes(40)
        self.wndtop = 20
        self.vtab(24)
        self.color = 0
        self.text_dirty = True

    # --- text output ---------------------------------------------------------------------
    def set_window(self, top=None, bottom=None):
        if top is not None:
            self.wndtop = top
        if bottom is not None:
            self.wndbtm = bottom
        if self.cv < self.wndtop:
            self.cv = self.wndtop

    def _row_addr(self, row):
        return TEXT1 + TEXT_ROW[row % 24]

    def home(self):
        """CALL -936"""
        for r in range(self.wndtop, self.wndbtm):
            a = self._row_addr(r)
            self.ram[a:a + 40] = b'\xa0' * 40
        self.ch, self.cv = 0, self.wndtop
        self.text_dirty = True

    def clreol(self):
        """CALL -868"""
        a = self._row_addr(self.cv)
        self.ram[a + self.ch:a + 40] = b'\xa0' * (40 - self.ch)
        self.text_dirty = True

    def clreop(self):
        """CALL -958"""
        self.clreol()
        for r in range(self.cv + 1, self.wndbtm):
            a = self._row_addr(r)
            self.ram[a:a + 40] = b'\xa0' * 40

    def vtab(self, n):
        if not 1 <= n <= 24:
            raise BasicError('RANGE')
        self.cv = n - 1

    def tab(self, n):
        if not 1 <= n <= 255:
            raise BasicError('RANGE')
        self.ch = (n - 1) % 40 if n > 40 else n - 1

    def _scroll(self):
        for r in range(self.wndtop, self.wndbtm - 1):
            src, dst = self._row_addr(r + 1), self._row_addr(r)
            self.ram[dst:dst + 40] = self.ram[src:src + 40]
        a = self._row_addr(self.wndbtm - 1)
        self.ram[a:a + 40] = b'\xa0' * 40

    def _linefeed(self):
        self.cv += 1
        if self.cv >= self.wndbtm:
            self.cv = self.wndbtm - 1
            self._scroll()

    def cout(self, c):
        """Monitor COUT for one character code (0-127)."""
        c &= 0x7F
        self.frontend.echo(c)
        if c == 0x0D:
            self.ch = 0
            self._linefeed()
        elif c == 0x0A:
            self._linefeed()
        elif c == 0x08:
            if self.ch:
                self.ch -= 1
            else:
                self.ch = 39
                if self.cv > self.wndtop:
                    self.cv -= 1
        elif c == 0x07:
            self.beep()
        elif c >= 0x20:
            ch = c | 0x80
            if c >= 0x60:
                ch &= 0xDF          # no lower case on the original
            self.ram[self._row_addr(self.cv) + self.ch] = ch & self.invflg
            self.ch += 1
            if self.ch >= 40:
                self.ch = 0
                self._linefeed()
        self.text_dirty = True

    def write(self, s):
        for c in s:
            self.cout(ord(c))

    def print(self, *items, end='\r'):
        """PRINT a;b;c - numbers print with no padding in Integer BASIC."""
        for it in items:
            self.write(str(it))
        if end:
            self.write(end)

    def center(self, s):
        """The game's GOSUB 500: TAB 20-LEN(A$)/2: PRINT A$."""
        self.tab(20 - len(s) // 2)
        self.print(s)

    # --- line input ------------------------------------------------------------------------
    def getln(self, prompt='?'):
        self.write(prompt)
        buf = []
        while True:
            k = self.wait_key() & 0x7F
            if k == 0x0D:
                self.cout(0x0D)
                return ''.join(buf)
            if k in (0x08, 0x7F):
                if buf:
                    buf.pop()
                    self.cout(0x08)
            elif k == 0x18:          # CTRL-X cancels the line
                self.write('\\')
                self.cout(0x0D)
                buf = []
                self.write(prompt)
            elif k >= 0x20 and len(buf) < 239:
                ch = chr(k).upper()
                buf.append(ch)
                self.cout(ord(ch))

    def input_number(self, prompt=''):
        """INPUT "PROMPT",N"""
        self.write(prompt)
        while True:
            line = self.getln('?').strip()
            try:
                v = int(line)
                return clip16(v)
            except (ValueError, BasicError):
                self.print('RETYPE LINE')

    def input_string(self, prompt=''):
        self.write(prompt)
        return self.getln('')

    # --- lo-res -----------------------------------------------------------------------------
    def set_color(self, c):
        self.color = c & 15

    def plot(self, x, y):
        if not (0 <= x < 40 and 0 <= y < 48):
            raise BasicError('RANGE')
        a = self._row_addr(y >> 1) + x
        if y & 1:
            self.ram[a] = (self.ram[a] & 0x0F) | (self.color << 4)
        else:
            self.ram[a] = (self.ram[a] & 0xF0) | self.color
        self.text_dirty = True

    def hlin(self, x1, x2, y):
        for x in range(x1, x2 + 1):
            self.plot(x, y)

    def vlin(self, y1, y2, x):
        for y in range(y1, y2 + 1):
            self.plot(x, y)

    def scrn(self, x, y):
        if not (0 <= x < 40 and 0 <= y < 48):
            raise BasicError('RANGE')
        v = self.ram[self._row_addr(y >> 1) + x]
        return (v >> 4) if y & 1 else (v & 15)

    def recolor(self, old, new):
        """The COL routine at $2400: every lo-res pixel of colour `old` in the
        graphics area becomes `new` (CALL C1 with COLOR=old, then CALL C2 with COLOR=new)."""
        for row in range(self.wndtop):
            a = self._row_addr(row)
            for x in range(40):
                v = self.ram[a + x]
                if v & 15 == old:
                    v = (v & 0xF0) | new
                if v >> 4 == old:
                    v = (v & 0x0F) | (new << 4)
                self.ram[a + x] = v
        self.text_dirty = True

    def move(self, start, end, dest):
        """Monitor MOVE (CALL -468): copy start..end inclusive to dest."""
        n = end - start + 1
        self.ram[dest:dest + n] = self.ram[start:start + n]
        self.text_dirty = True
        self.hires.dirty = True

    # --- hi-res -----------------------------------------------------------------------------
    def hgr_load(self, data, name=None):
        """BLOAD a picture into hi-res page 1; `name` lets a frontend show redrawn art for it."""
        self.hires.load(data)
        self.hires.picture = name

    def draw(self, shape, x, y, color, rot=0, scale=1, xor=False):
        try:
            return self.hires.draw(shape, x, y, color, rot, scale, xor)
        except RangeError as e:
            raise BasicError('RANGE') from e

    # --- sound ------------------------------------------------------------------------------
    def sound(self, pitch, length=None, repeats=1):
        """POKE 832,pitch: [POKE 833,length:] POKE 860,repeats: CALL 834.

        The routine at $0342 clicks the speaker, waits WAIT(pitch), and counts
        $0341 down; each time it reaches zero it counts $035C down and keeps
        going (so $0341 wraps to 255).  $0341 is left at zero afterwards, so a
        later call that does not POKE 833 plays 256 clicks per repeat.
        """
        self.ram[0x340] = pitch & 0xFF
        if length is not None:
            self.ram[0x341] = length & 0xFF
        self.ram[0x35C] = repeats & 0xFF
        n = self.ram[0x341] + 1 + 256 * ((self.ram[0x35C] - 1) & 0xFF)
        self.ram[0x341] = 0
        self.ram[0x35C] = 0
        a = self.ram[0x340] or 256
        # Each click: LDA $C030, LDA/JSR WAIT, LDA/BNE, DEC, JMP = 30 cycles,
        # plus the monitor's WAIT itself, 2.5A^2 + 13.5A + 7 cycles.
        half = (2.5 * a * a + 13.5 * a + 37) / CPU_HZ
        self.tick((3 + (length is not None)) * BASIC_STATEMENT + NEXT_TIME)   # POKEs, CALL, NEXT
        self.frontend.clicks([half] * n)
        self.tick(half * n)

    def clicks(self, intervals, repeat=1):
        """Speaker clicks from a PEEK(-16336) loop: `intervals` are the seconds
        between successive clicks (one loop pass), played `repeat` times."""
        pattern = list(intervals) * repeat
        self.frontend.clicks(pattern)
        self.tick(sum(pattern))

    def beep(self):
        self.sound(12, 200, 1)


class Headless(Frontend):
    """Runs the game without a window: keys come from a script, text goes to a log.

    Used for automated testing.  When the script runs out the game stops with ScriptEnd.
    """

    def __init__(self, keys, out=None, idle_limit=20000):
        self.keys = list(keys)
        self.out = out
        self.idle = 0
        self.idle_limit = idle_limit
        self.log = []

    def poll(self):
        m = self.machine
        if m.kbd < 128 and self.keys:
            k = self.keys.pop(0)
            if isinstance(k, str):
                k = ord(k)
            m.key_pressed(k)
            self.idle = 0
        elif m.kbd < 128:
            self.idle += 1
            if self.idle > self.idle_limit:
                raise ScriptEnd()

    def wait(self, seconds):
        self.poll()

    def echo(self, c):
        ch = '\n' if c == 0x0D else chr(c) if c >= 0x20 else ''
        self.log.append(ch)
        if self.out is not None:
            self.out.write(ch)

    def screen_text(self):
        m = self.machine
        lines = []
        for r in range(24):
            a = m._row_addr(r)
            s = ''
            for b in m.ram[a:a + 40]:
                c = b & 0x3F if b < 0x80 else b & 0x7F
                if b < 0x80:
                    c = c | 0x40 if c < 0x20 else c
                s += chr(c)
            lines.append(s)
        return '\n'.join(lines)


class RealTime(Frontend):
    """Base for interactive frontends: maps emulated waits to wall-clock time."""

    def wait(self, seconds):
        end = time.monotonic() + seconds
        while True:
            self.poll()
            left = end - time.monotonic()
            if left <= 0:
                break
            time.sleep(min(left, 1 / 120))
