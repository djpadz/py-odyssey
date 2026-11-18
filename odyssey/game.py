"""The game driver: the HAIL title program, CHAIN between parts, save and restore.

On the original disk the program "HAIL" BLOADs the variable table and the
graphics package, rolls the party's characteristics, sets up the island and
CHAINs to "ISLAND APVENTURE".  The parts then CHAIN to each other:

    ISLAND --(sail away in your ship)--> SEA --(land on Lapour)--> CAVERN
       CAVERN --(back to the ship / out with the orb)--> SEA

A saved game ("OLD GAME") is the variable table plus the hi-res page; here it
is a JSON file holding the same two things.
"""
import base64
import json
import os
from importlib import resources

from . import data
from .apple import Machine, BasicError, Quit
from .part import State, Chain, GameOver, Goto
from .island import Island
from .sea import Sea
from .cavern import Cavern

PARTS = {'island': Island, 'sea': Sea, 'cavern': Cavern}
PICTURES = ('logo', 'island1', 'island2', 'seamap')
FIRST_LINE = {'island': 600, 'sea': 10, 'cavern': 10}   # where each program starts


def asset(name):
    return resources.files(__package__).joinpath('assets', name).read_bytes()


class Game:
    asset = staticmethod(asset)
    def __init__(self, frontend, save_path='odyssey-old-game.json', rng=None):
        self.machine = Machine(asset('shapes.bin'), asset('setup.bin'), rng=rng)
        self.machine.attach(frontend)
        self.save_path = save_path
        self.state = self.fresh_state()

    @staticmethod
    def fresh_state():
        s = State()
        for k, v in data.INITIAL_VARS.items():
            setattr(s, k, list(v) if isinstance(v, list) else v)
        return s

    # --- saving -----------------------------------------------------------------------
    def save_name(self):
        return os.path.basename(self.save_path).upper()

    def save(self):
        doc = {'state': self.state.to_dict(),
               'memory': base64.b64encode(bytes(self.machine.ram[0x2000:0x4000])).decode()}
        with open(self.save_path, 'w') as f:
            json.dump(doc, f)

    def load(self):
        with open(self.save_path) as f:
            doc = json.load(f)
        self.state = State.from_dict(doc['state'])
        self.machine.ram[0x2000:0x4000] = base64.b64decode(doc['memory'])
        self.machine.hires.dirty = True
        self.machine.hires.picture = self.identify_picture()
        if self.machine.hires.picture:
            self.machine.hires.rebuild_layer(asset(self.machine.hires.picture + '.hgr'))

    def identify_picture(self):
        """Which original picture the restored hi-res page shows (for enhanced display)."""
        mem = bytes(self.machine.ram[0x2000:0x4000])
        best, score = None, 0.0
        for name in PICTURES:
            ref = asset(name + '.hgr')
            same = sum(a == b for a, b in zip(mem, ref)) / len(ref)
            if same > score:
                best, score = name, same
        return best if score > 0.7 else None

    # --- HAIL ---------------------------------------------------------------------------
    def hail(self):
        """Title screen and new-game setup.  Returns the part to start with."""
        m = self.machine
        m.text()
        m.home()
        m.hgr_load(asset('logo.hgr'), 'logo')
        m.switch(-16304)
        m.switch(-16297)
        m.switch(-16302)
        m.pause(500)
        s = self.state = self.fresh_state()
        s.CH = m.rnd(9) + 2                                            # 32
        s.DEX = 5 + m.rnd(4)
        s.SP = m.rnd(4) + 2
        s.WT = 2500
        s.EX = 10
        s.FM = 10
        s.WS = 5 + m.rnd(5)
        s.MRL = 5 + m.rnd(5)
        s.TOT = 10
        s.BQ[2] = 900 + m.rnd(300)                                     # 33
        s.STR = m.rnd(8) + 3
        s.BQ[1] = 15
        s.BG[1] = 12
        s.BG[2] = 48
        s.AW = s.TR + 30
        m.switch(-16301)                                               # 34
        m.set_window(top=20)
        m.invflg = 0x3F
        m.home()
        m.print('  HAIL WANDERER. ART EMBARKING ON A NEW   QUEST IN THE DREAD SARGALO, OR BUT    ', end='')
        m.print('  CONTINUING A PRIOR ONE (N OR P)?                                             ', end='')
        m.ram[2039] = 0x20
        m.invflg = 0xFF
        while True:                                                    # 40
            v = m.peek_kbd()
            if v in (206, 208):
                break
            m.tick(0.01)
        s.V = v
        m.clear_strobe()
        m.switch(-16302)
        m.home()
        m.print()
        m.hires.clear()                                                # CALL 2048
        m.switch(-16297)
        m.switch(-16304)
        if v == 208:
            return self.restore()
        return self.new_island()

    def restore(self):
        """50-150: continue a saved game."""
        m = self.machine
        m.text()
        m.home()
        m.print("\r\r\r\r\rINSERT THE MYSTICAL TALISMAN KNOWN AS:\r\r\r         'DISK WITH OLD GAME'\r\r\r")
        m.print('WHEN YOU RETURN, THE QUEST WILL\rCONTINUE.')
        m.wait_key()
        try:
            self.load()
        except (OSError, ValueError, KeyError):
            m.home()
            m.print('\r\r\r\r\rI CANNOT FIND ' + self.save_name() + '.\r\rPRESS ANY KEY.')
            m.wait_key()
            raise Restart()
        m.home()
        m.print('\r\r\r\rNOW, AGAIN MAKE USE OF THE POWERFUL\rCHARM TITLED:\r\r\r')
        m.print("   'ODYSSEY: THE COMPLEAT APVENTURE'\r\r\rAND AGAIN RETURN.")
        m.wait_key()
        s = self.state
        if s.Z1 == 1:
            return 'island'
        if s.Z1 == 2:
            return 'sea'
        s.Z2 = 20                                                      # 120
        return 'cavern'

    def new_island(self):
        """135-139: lay out the island."""
        s, m = self.state, self.machine
        s.LC = list(data.ISLAND_MAP)
        s.BG[1] = 1
        s.Z20 = s.STR
        m.hgr_load(asset('island1.hgr'), 'island1')
        island = Island(self)
        island.draw()                     # the city at 63,16 (SHAPE 16 = city)
        for i in (1, 2):                  # two more cities
            s.I = i
            while True:
                s.X0 = 70 + m.rnd(50) + 70 * (i == 2)
                s.Y0 = 20 + m.rnd(120)
                s.M = s.X0 // 14 * 20 + s.Y0 // 8 + 1
                if s.LC[s.M] == 0:
                    break
            s.X0 = 14 * (s.M // 20) + 7
            s.Y0 = 8 * (s.M % 20 - 1)
            s.LC[s.M] += 56
            island.draw()
        s.X, s.Y = s.X0, s.Y0
        for _ in range(3):                # three of each site
            for j in range(51, 56):
                while True:
                    s.M = 1 + m.rnd(399)
                    lc = s.LC
                    if not (lc[s.M] // 10000 == 3 or lc[s.M - 1] // 10000 == 3
                            or lc[s.M + 1] // 10000 == 3 or lc[s.M] % 10000 != 0):
                        break
                s.LC[s.M] += j
        while True:                       # the party starts next to the city
            s.I = 2 * m.rnd(2) - 1
            s.J = 2 * m.rnd(2) - 1
            s.X0 = s.X + s.I * 10
            s.Y0 = s.Y + s.J * 10
            s.M = s.X0 // 14 * 20 + s.Y0 // 8 + 1
            if s.LC[s.M] == 0:
                break
        s.SHAPE = 2
        s.SCALE = 1
        s.X = s.X0
        island.xdraw()
        return 'island'

    # --- running -------------------------------------------------------------------------
    def run(self):
        while True:
            try:
                part = self.hail()
                self.play(part, FIRST_LINE[part])
            except Restart:
                continue

    def play(self, name, line):
        while True:
            p = PARTS[name](self)
            try:
                p.run(line)
            except Chain as c:
                name, line = c.part, FIRST_LINE[c.part]
                continue
            except GameOver as g:
                if g.died:                       # the party is lost: close the game
                    if not g.dismissed:
                        self.machine.wait_key()
                    raise Quit()
                line = self.end_menu(g.resume)
            except BasicError as e:
                self.machine.print()
                self.machine.print('*** %s ERR' % e)
                line = self.end_menu((32000, 'CONTINUE THE QUEST'))

    def end_menu(self, resume=None):
        """What next, when the program has ENDed (the original left you at the
        BASIC '>' prompt to type GOTO 31000/32000 or RUN).  `resume` is an
        optional (line, label) for carrying on.  Returns the line to resume at."""
        m = self.machine
        m.set_window(top=0, bottom=24)
        m.invflg = 0xFF
        choices = ([resume] if resume else []) + [(None, 'START A NEW QUEST'), ('quit', 'LEAVE THE GAME')]
        m.print()
        for n, (_, label) in enumerate(choices, 1):
            m.tab(4)
            m.print(n, '. ', label)
        m.tab(4)
        m.print('WHICH (1-%d)?' % len(choices), end='')
        m.clear_strobe()
        while True:
            k = m.wait_key() - 176
            if 1 <= k <= len(choices):
                break
        what = choices[k - 1][0]
        if what == 'quit':
            raise Quit()
        if what is None:
            raise Restart()
        return what


class Restart(Exception):
    pass
