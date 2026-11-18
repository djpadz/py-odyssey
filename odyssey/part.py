"""Shared machinery for the three parts of the game (Island, Sea, Cavern).

The original is three Integer BASIC programs that CHAIN to each other and
share every variable.  The port keeps that model: one `State` object holds all
variables under their original BASIC names, so the Python code can be checked
line by line against the listings (see the line-number comments).

Control flow: subroutines are methods.  When the original jumps (GOTO) from
inside a subroutine back to one of the main entry points, the port raises
`Goto(line)`; each part's `run()` loop catches it and continues there.
"""
from .apple import Quit, idiv, imod, sgn  # noqa: F401  (re-exported for the parts)
from . import data


class Goto(Exception):
    def __init__(self, line):
        super().__init__(line)
        self.line = line


class Chain(Exception):
    """PRINT D$;"CHAIN <part>" - switch to another program, keeping variables."""

    def __init__(self, part):
        super().__init__(part)
        self.part = part


class GameOver(Exception):
    """END - the program stopped.

    `died` means the party is lost: the game closes once the message has been
    dismissed (`dismissed` says whether the player has already pressed a key).
    Otherwise the player gets a menu: carry on (if `resume` offers it), start a
    new quest, or leave.
    """

    def __init__(self, died=False, dismissed=False, resume=None):
        super().__init__()
        self.died = died
        self.dismissed = dismissed
        self.resume = resume          # (line, label): an offer to carry on from `line`


ARRAYS = {'LC': 401, 'BG': 71, 'BQ': 71, 'MG': 14, 'QTA': 14, 'CP': 14,
          'DR': 9, 'T': 8, 'LA': 8, 'B': 8}


class State:
    """All BASIC variables.  Unset numeric variables read as 0, strings as ''.

    The arrays QT() and L() are called QTA and LA here, apart from the scalars QT and L.
    Glossary of the important ones:
      FM  men in party       STR strength   CH  charisma   EX  experience
      WS  wisdom             SP  speed      DEX dexterity  AL  alignment
      TOT men ever recruited TEN inhabitants killed        TSH ships sunk
      BG()/BQ() inventory: item code / quantity (slot 1 food, slot 2 gold)
      BN  inventory slots in use               AW  weight carried
      LC() the map of the current part         X,Y / X0,Y0 position
      COLR, SHAPE, ROT, SCALE  hi-res drawing parameters
    """

    def __init__(self):
        for name, size in ARRAYS.items():
            setattr(self, name, [0] * size)

    def __getattr__(self, name):
        if name.startswith('_'):
            raise AttributeError(name)
        return '' if name.endswith('_S') else 0

    def to_dict(self):
        return dict(self.__dict__)

    @classmethod
    def from_dict(cls, d):
        s = cls()
        s.__dict__.update(d)
        return s


def substr(s, a, b):
    """Integer BASIC A$(a,b): characters a..b (1-based, inclusive)."""
    return s[a - 1:b]


def put(s, pos, t):
    """Integer BASIC A$(pos)=T$: replace from position `pos` on, truncating."""
    return s[:pos - 1].ljust(pos - 1) + t


class Part:
    """Behaviour common to the parts.  Subclasses override where they differ."""

    plural_from = 2       # 548: IF QT<2 THEN 549 (island); the Sea uses QT=1

    def __init__(self, game):
        self.game = game
        self.m = game.machine
        self.s = game.state

    # --- hi-res shape helpers (CALL 2871 / CALL 2884) ---------------------------------
    def draw(self):
        s = self.s
        s.COLLISION = self.m.draw(s.SHAPE, s.X0, s.Y0, s.COLR, s.ROT, s.SCALE)

    def xdraw(self):
        s = self.s
        s.COLLISION = self.m.draw(s.SHAPE, s.X0, s.Y0, s.COLR, s.ROT, s.SCALE, xor=True)

    def lc(self, i):
        """LC(i), with out-of-range cells reading as open ocean instead of
        stopping the program with a RANGE ERR."""
        return self.s.LC[i] if 0 <= i <= 400 else 30000

    # --- pauses (lines 30-45) ---------------------------------------------------------------
    def wait(self, d):
        """GOSUB 30/35/40: pause D=400/200/100, cut short by a key press."""
        m = self.m
        m.pause(20)
        m.clear_strobe()
        m.delay(d)
        if self.s.V in (141, 160):
            m.clear_strobe()

    def wait30(self):
        self.wait(400)

    def wait35(self):
        self.wait(200)

    def wait40(self):
        self.wait(100)

    # --- sound effects ------------------------------------------------------------------------
    def sound60(self):
        """Poison: a long low buzz."""
        for _ in range(10):
            for _ in range(15):
                self.m.sound(11, 20, 1)
        self.s.M, self.s.L = 11, 16

    def sound65(self):
        """Battle drums."""
        for _ in range(6):
            for _ in range(10):
                self.m.sound(16, 30, 1)
            self.m.pause(5)
        self.s.L, self.s.J, self.s.M = 7, 11, 6

    def sound70(self):
        """Victory fanfare."""
        for i in range(1, 4):
            self.m.sound(10, None, 3)
            self.m.pause(2)
            self.m.sound(8, None, 12 if i == 3 else 5)
            self.m.pause(20)
        self.s.I, self.s.J = 4, 21

    def sound75(self):
        """Running aground / a warning."""
        for _ in range(4):
            for _ in range(4):
                self.m.sound(12, None, 2)
            self.m.pause(10)
        self.s.L, self.s.M, self.s.K = 5, 5, 11

    # --- text helpers -----------------------------------------------------------------------
    def say(self, *items, end='\r'):
        self.m.print(*items, end=end)

    def inverse(self, *items, end=''):
        m = self.m
        m.invflg = 0x3F
        m.print(*items, end=end)
        m.invflg = 0xFF

    def center(self, a=None):
        """GOSUB 500: TAB 20-(LEN(A$)/2): PRINT A$"""
        if a is not None:
            self.s.A_S = a
        a = self.s.A_S
        self.m.tab(20 - idiv(len(a), 2))
        self.m.print(a)

    def announce(self, a=None):
        """GOSUB 499: CALL -936: PRINT: GOSUB 500"""
        self.m.home()
        self.m.print()
        self.center(a)

    # --- inventory --------------------------------------------------------------------------
    def find_item(self, j=None):
        """GOSUB 400: K = the (last) inventory slot holding item J, or 0."""
        s = self.s
        if j is not None:
            s.J = j
        s.K = 0
        for n in range(1, s.BN + 1):
            if s.BG[n] == s.J:
                s.K = n
        s.N = s.BN + 1
        return s.K

    def gain(self):
        """GOSUB 410: add QT of item C1, carrying its weight."""
        s = self.s
        s.AW = s.AW + s.QT * data.ITEM_WEIGHT[s.C1]
        self.stow()

    def stow(self):
        """GOSUB 415: put QT of item C1 in the matching slot, else the first free one."""
        s = self.s
        s.K = 0
        for m in range(1, s.BN + 2):
            if s.BG[m] == s.C1:
                s.K = m
            if s.K == 0 and s.BG[m] == 0:
                s.K = m
        s.M = s.BN + 2
        if s.K == s.BN + 1:
            s.BN += 1
        s.BG[s.K] = s.C1
        s.BQ[s.K] = s.BQ[s.K] + s.QT

    def item_name(self, m=None):
        """GOSUB 542: B$ = the name of item M (pluralised for QT)."""
        s = self.s
        if m is not None:
            s.M = m
        m = s.M
        if m > 50:
            return s.B_S
        if m > 30:
            s.BP = (m - 31) * 10 + 1
            s.B_S = substr(data.G3, s.BP, s.BP + 9)
        elif m > 20:
            s.BP = (m - 21) * 10 + 1
            s.B_S = substr(data.G2, s.BP, s.BP + 9)
        else:
            if m < 1:
                raise Goto(self.abandon_line)   # the original stops with RANGE ERR here
            s.BP = (m - 1) * 10 + 1
            s.B_S = substr(data.G1, s.BP, s.BP + 9)
        if not self._singular(s.QT):
            s.B_S = put(s.B_S, 11, 'ES' if m in (33, 15) else 'S')
        return s.B_S

    def _singular(self, qt):
        return qt < 2

    def slot_name(self):
        """GOSUB 540: M=BG(BI): QT=BQ(BI): GOSUB 542"""
        s = self.s
        s.M = s.BG[s.BI]
        s.QT = s.BQ[s.BI]
        return self.item_name()

    def use_up(self, n=None):
        """GOSUB 550: take I away from slot BI, closing the gap if it empties."""
        s = self.s
        if n is not None:
            s.I = n
        if s.BQ[s.BI] > s.I:
            s.BQ[s.BI] -= s.I
            return
        self.empty_slot()

    def empty_slot(self):
        """Line 560 (island version: food and gold slots are never removed)."""
        s = self.s
        s.BQ[s.BI] = 0
        if s.BI < 3:
            return
        self.close_gap()

    def close_gap(self):
        s = self.s
        i = s.BI + 1
        while True:                # FOR I=BI+1 TO BN (runs at least once)
            s.BG[i - 1] = s.BG[i]
            s.BQ[i - 1] = s.BQ[i]
            i += 1
            if i > s.BN:
                break
        s.I = i
        s.BG[s.BN] = 0
        s.BQ[s.BN] = 0

    def choose_item(self, verb):
        """GOSUB 520: show the inventory nine at a time and let the player pick.

        Sets BI.  RETURN pages through the list; any other key gives up
        (the original jumps to line 599 in the Island, 600 at Sea).
        """
        s, m = self.s, self.m
        m.home()
        self.inverse(self.menu_prefix, verb, ' WHICH ITEM?   (RET=MORE ITEMS)     ')
        m.set_window(top=21)
        pages = idiv(s.BN - 1, 9)
        page = 0
        while True:
            s.I = page
            m.home()
            for j in range(1, 10):
                s.J = j
                s.BI = 9 * page + j
                if s.BG[s.BI] == 0:
                    break
                self.slot_name()
                m.vtab(22 + (j - 1) % 3)
                m.tab(1 + 13 * ((j > 3) + (j > 6)))
                self.inverse(j, '.')
                m.print(s.B_S, end='')
            v = self.getkey()
            if v == 141 and page < pages:
                page += 1
                continue
            if v < 177 or v > 185:
                raise Goto(self.abandon_line)
            s.BI = 9 * page + v - 176
            if s.BG[s.BI] == 0:
                raise Goto(self.abandon_line)   # the original would crash on an empty slot
            m.set_window(top=20)
            return s.BI

    abandon_line = 599
    menu_prefix = '  '
    party_label = '# IN PARTY='

    def getkey(self):
        """GOSUB 100 - overridden by each part."""
        s = self.s
        s.V = self.m.wait_key()
        return s.V

    def key99(self):
        """GOSUB 99: pause, flush the keyboard, then wait for a key."""
        self.wait40()
        self.m.clear_strobe()
        return self.getkey()

    # --- condition report (800) ---------------------------------------------------------
    def status(self):
        s, m = self.s, self.m
        m.home()
        self.inverse('             STATUS REPORT              ')
        m.print(self.party_label, s.FM, end='')
        m.tab(16)
        m.print('STRENGTH=', s.STR, end='')
        m.tab(29)
        m.print('CHARISMA=', s.CH)
        m.print('EXPER.=', s.EX, end='')
        m.tab(16)
        m.print('WISDOM=', s.WS, end='')
        m.tab(29)
        m.print('SPEED=', s.SP)
        m.print('DEXTERITY=', s.DEX, end='')
        m.tab(16)
        m.print('GOLD=', s.BQ[2], end='')
        m.tab(29)
        m.print('ALIGN.=', s.AL, end='')

    # --- quitting ---------------------------------------------------------------------------
    def quit_game(self, part_code):
        """790-797: QUIT GAME? SAVE GAME?  Returns False if the player changed their mind;
        otherwise saves if asked and closes the game (the original ENDed at the BASIC prompt)."""
        s, m = self.s, self.m
        self.announce('QUIT GAME (Y/N)?')
        if self.getkey() != 217:
            return False
        self.announce('SAVE GAME (Y/N)?')
        if self.getkey() == 217:
            self.save_game(part_code)
        raise Quit()

    def save_game(self, part_code):
        s, m = self.s, self.m
        m.home()
        m.print('\rINSERT ANOTHER DISK TO SAVE TO AND PRESSRETURN.')
        m.print('(SAVING TO ' + self.game.save_name() + ')')
        self.getkey()
        s.Z1 = part_code
        self.game.save()

    # --- the main loop ---------------------------------------------------------------------
    def entries(self):
        """Lines that the program can be (re)entered at: {line: method}."""
        return {}

    def run(self, line):
        entries = self.entries()
        while True:
            try:
                line = entries[line]()
            except Goto as g:
                line = g.line
