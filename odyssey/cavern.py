"""CAVERN APVENTURE - the catacombs beneath the temple, and the Caliph's fortress.

Port of the Integer BASIC program "CAVERN APVENTURE".  Line numbers in the
comments refer to the original listing.

The catacombs are drawn on the lo-res screen, and the screen *is* the map: a
40x40 maze of 5x5 tiles, generated tile by tile as the party walks off the
edge of the known area.  A tile counts as explored once its bottom-left
pixel is set (every tile pattern sets it).  Walls are colour 2, the party is
colour C (9), frenzies 8 and the borer 4; BKG is the floor colour, which the
poison gas keeps changing.

With the light off the display shows text page 2, which holds a snapshot of
the screen taken on arrival, so the party gropes about in the dark.

  EN  0 nothing  1 frenzies  2 borer  3 both  4 in poison gas
  PG  gas timer  ST on a stairway  Z10 an exit has been found
  Z1,Z2 the altar   Z8 1 at the orb, 2 carrying the High One's Orb
  Z15 set while at the fortress on the Isle of Lapour (line 20000 on)
"""
from . import data
from .apple import BasicError, Quit
from .part import Part, Goto, Chain, GameOver, idiv, imod, sgn, substr, put

GW, AP = data.ITEM_WEIGHT, data.ITEM_PRICE
YES = 217
N_, S_, E_, W_ = 206, 211, 197, 215
WALL = 2

# Tile patterns (lines 1100-1210), as (kind, a, b, at) with offsets from (K, I):
# 'h' = HLIN K+a,K+b AT I+at; 'v' = VLIN I+a,I+b AT K+at; 'p' = PLOT K+a,I+b.
TILES = {
    1100: [('h', 0, 1, 0), ('h', 2, 3, 2), ('h', 3, 4, 3), ('h', 3, 4, 4), ('h', 0, 1, 4),
           ('p', 0, 1), ('p', 4, 0)],
    1110: [('h', 0, 4, 0), ('h', 2, 4, 1), ('v', 3, 4, 0), ('v', 3, 4, 3), ('v', 3, 4, 4),
           ('v', 3, 4, 1)],
    1120: [('h', 0, 4, 0), ('h', 0, 4, 1), ('v', 3, 4, 0), ('v', 3, 4, 4), ('p', 1, 4), ('p', 3, 3)],
    1130: [('v', 0, 4, 0), ('v', 1, 4, 1), ('v', 0, 4, 4), ('p', 3, 0), ('v', 3, 4, 3)],
    1140: [('p', 0, 4)],
    1150: [('h', 0, 4, 0), ('h', 0, 2, 1), ('h', 0, 1, 2), ('h', 0, 1, 3), ('h', 0, 4, 4), ('p', 4, 3)],
    1160: [('h', 0, 4, r) for r in range(5)],
    1170: [('h', 0, 4, 0), ('h', 2, 4, 1), ('h', 3, 4, 2), ('v', 3, 4, 4), ('v', 3, 4, 0), ('p', 1, 4)],
    1180: [('v', 0, 4, 0), ('h', 1, 4, 4), ('h', 3, 4, 0), ('h', 2, 3, 1), ('p', 2, 2)],
    1190: [('v', 0, 4, 0), ('h', 0, 4, 4), ('v', 0, 1, 4), ('p', 3, 1), ('p', 1, 0), ('h', 2, 3, 2)],
    1200: [('v', 0, 1, 0), ('v', 0, 1, 1), ('v', 3, 4, 2), ('v', 3, 4, 3), ('v', 0, 4, 4), ('h', 0, 1, 4),
           ('p', 3, 0), ('p', 0, 3)],
    1210: [('h', 0, 1, 0), ('v', 3, 4, 0), ('v', 2, 4, 1), ('v', 0, 4, 4), ('p', 3, 4), ('p', 3, 1)],
    # 1300-1320: the 10x10 altar room
    1300: [('h', 0, 1, 0), ('h', 3, 9, 0), ('h', 0, 1, 1), ('h', 6, 9, 1), ('v', 3, 9, 0), ('v', 5, 6, 1),
           ('v', 3, 9, 9), ('v', 6, 9, 8), ('h', 7, 8, 8), ('h', 3, 7, 9), ('p', 8, 9), ('p', 1, 7),
           ('p', 8, 3), ('p', 8, 6), ('p', 5, 1), ('p', 5, 4), ('p', 1, 9)],
}


class Cavern(Part):
    abandon_line = 500
    menu_prefix = '    '
    party_label = '# IN PARTY '

    def entries(self):
        return {10: self.L10, 490: self.L490, 500: self.L500, 510: self.L510,
                20000: self.L20000, 20010: self.L20010, 20011: self.L20011,
                20012: self.L20012, 32000: self.L32000}

    # ----------------------------------------------------------------------------------
    # 10, 200-230, 490, 10000-10040: arriving, and the screen-saving MOVEs
    # ----------------------------------------------------------------------------------
    def L10(self):
        s = self.s
        self.say()
        if s.Z15:
            return 20000
        self.save_dark_screen()
        if s.Z2 == 20:
            return 490
        return self.new_catacombs()

    def save_screen(self):
        """200: copy text/lo-res page 1 to $2000"""
        self.m.move(0x400, 0x7FF, 0x2000)

    def restore_screen(self):
        """210: copy it back"""
        self.m.move(0x2000, 0x23FF, 0x400)

    def save_dark_screen(self):
        """220: keep the graphics package safe at $2C00, then make page 2 a
        copy of the (blank) screen with the command list on it."""
        m = self.m
        m.move(0x800, 0xBFF, 0x2C00)
        m.gr()
        self.commands()
        m.move(0x400, 0x7FF, 0x800)

    def L490(self):
        m = self.m
        m.gr()
        m.switch(-16298)
        self.restore_screen()
        m.switch(-16304)
        return 500

    def L32000(self):
        return 20000 if self.s.Z15 else 490

    def new_catacombs(self):
        """10000-10040"""
        s, m = self.s, self.m
        m.home()
        s.Z9 = s.Z10 = s.Z3 = 0
        s.Z1 = s.Z2 = -1
        s.C1, s.C2 = 9216, 9219
        self.say()
        self.say()
        for i in range(1, s.BN + 1):
            if s.BG[i] == 10:
                s.Z3 = 1                                             # a helmet
        s.LC = [0] * 401                                             # 10002
        s.T[1:8] = [1, 4, 5, 9, 10, 11, 12]                          # tiles that fit going S
        s.LA[1:8] = [1, 2, 3, 5, 8, 11, 12]                           # ... going E
        s.DR[1:8] = [1, 2, 3, 5, 6, 9, 10]                           # ... going W
        s.B[1:8] = [1, 2, 3, 4, 5, 8, 12]                            # ... going N
        s.C = 9                                                      # 10030
        s.LT = 0
        m.switch(-16299)
        s.I = 5 + 5 * m.rnd(7)                                       # 10040
        s.K = 5 + 5 * m.rnd(7)
        m.gr()
        m.switch(-16298)
        m.home()
        m.set_color(WALL)
        self.tile(1150)
        s.X = s.K + 3
        s.Y = s.I + 3
        m.set_color(s.C)
        m.plot(s.X, s.Y)
        return 500

    def tile(self, line):
        """GOSUB 1100-1210 / 1300: draw a tile at (K, I) in the current colour."""
        s, m = self.s, self.m
        k, i = s.K, s.I
        for op in TILES[line]:
            if op[0] == 'h':
                m.hlin(k + op[1], k + op[2], i + op[3])
            elif op[0] == 'v':
                m.vlin(i + op[1], i + op[2], k + op[3])
            else:
                m.plot(k + op[1], i + op[2])

    # ----------------------------------------------------------------------------------
    # Sounds and pauses
    # ----------------------------------------------------------------------------------
    def wait139(self):
        self.m.pause(600)

    def wait140(self):
        self.m.pause(300)

    def key99(self):
        self.wait140()
        self.m.clear_strobe()
        return self.getkey()

    def sound142(self):
        self.sound60()

    def sound143(self):
        """The borer flashes as it arrives."""
        s, m = self.s, self.m
        for k in range(1, 7):
            m.set_color(4 * ((k % 2) + 1))
            m.plot(s.X2, s.Y2)
            m.clicks(25, 0.002)
        s.M, s.L = 7, 26

    def sound145(self):
        self.sound65()

    def sound147(self):
        """Triumph."""
        m = self.m
        for i in range(1, 4):
            m.pause(15)
            m.sound(8, None, 2)
            m.pause(5)
            m.sound(10, None, 8 if i == 3 else 4)
        for _ in range(12):
            m.sound(10, None, 2)

    def sound150(self):
        for i in range(9, 1, -1):
            self.m.sound(i, None, 2)

    def sound155(self):
        for _ in range(4):
            for _ in range(6):
                self.m.sound(12, None, 2)

    # ----------------------------------------------------------------------------------
    # 100-110: waiting for a key, while frenzies swarm and the gas plays tricks
    # ----------------------------------------------------------------------------------
    def getkey(self):
        s, m = self.s, self.m
        while True:
            s.V = m.peek_kbd()
            if s.V >= 127:
                m.clear_strobe()
                return s.V
            m.statements(3)
            if s.EN in (1, 3):
                if s.PC == 0:
                    self.frenzies()
            elif s.EN == 4:
                s.CT += 1                                            # 108
                if s.CT == 0 or s.PG > 8:
                    continue
                self.hallucinate()

    def hallucinate(self):
        """110: the floor turns a random colour."""
        s, m = self.s, self.m
        while True:
            s.NEW = 1 + m.rnd(15)
            if s.NEW not in (s.C, WALL):
                break
        m.recolor(s.BKG, s.NEW)
        s.BKG = s.NEW
        m.tick(0.024)           # the COL routine takes about 24 ms

    def frenzies(self):
        """22-60: the frenzies dart about, homing in on the party."""
        s, m = self.s, self.m
        while True:
            m.clicks(1, 0.0005)
            nx, ny = (s.X0 + s.SX + 40) % 40, (s.Y0 + s.SY + 40) % 40
            s.V = m.scrn(nx, ny)
            if s.V == s.C:
                return self.frenzies_strike()
            if s.V != s.BKG or m.rnd(2):
                r = m.rnd(4)                                         # 30-60: turn
                s.SX, s.SY = [(0, -1), (0, 1), (1, 0), (-1, 0)][r]
                if m.rnd(2):
                    if r < 2:
                        s.SY = sgn(s.Y - s.Y0)
                    else:
                        s.SX = sgn(s.X - s.X0)
                return
            m.set_color(s.BKG)                                       # 25
            m.plot(s.X0, s.Y0)
            m.set_color(8)
            s.X0, s.Y0 = nx, ny
            m.plot(s.X0, s.Y0)
            m.statements(10)

    def frenzies_strike(self):
        """26-28"""
        s, m = self.s, self.m
        m.home()
        self.say('THE FRENZIES GOT YOU. TWO MEN WERE\rKILLED AND MANY HURT. WHAT DO YOU WANT\rTO DO?')
        s.EN -= 1
        s.U1 = s.U2 = 0
        s.FM -= 2
        m.set_color(s.BKG)
        m.plot(s.X0, s.Y0)
        m.clicks(100, 0.002)

    # ----------------------------------------------------------------------------------
    # 160-185: the borer creeps toward the party, boring through walls
    # ----------------------------------------------------------------------------------
    def borer(self):
        s, m = self.s, self.m
        if s.X == s.X2 and s.Y == s.Y2:
            return self.borer_strikes()
        if s.X != s.X2 and not (s.Y != s.Y2 and m.rnd(2)):
            s.DX = sgn(s.X - s.X2)
            if m.scrn(s.X2 + s.DX, s.Y2) != s.BKG:                   # 165: boring
                s.DS = int(not s.DS)
                if s.DS:
                    return
                m.set_color(s.BKG)
                m.plot(s.X2, s.Y2)
                m.set_color(4)
                s.X2 += s.DX
                m.plot(s.X2, s.Y2)
                return
            m.set_color(s.BKG)
            m.plot(s.X2, s.Y2)
            m.set_color(4)
            s.X2 += s.DX * (1 + (abs(s.X - s.X2) > 1))               # 162
            m.plot(s.X2, s.Y2)
        else:
            s.DY = sgn(s.Y - s.Y2)                                   # 170
            if m.scrn(s.X2, s.Y2 + s.DY) != s.BKG:                   # 175
                s.DS = int(not s.DS)
                if s.DS:
                    return
                m.set_color(s.BKG)
                m.plot(s.X2, s.Y2)
                m.set_color(4)
                s.Y2 += s.DY
                m.plot(s.X2, s.Y2)
                return
            m.set_color(s.BKG)
            m.plot(s.X2, s.Y2)
            m.set_color(4)                                           # 172
            s.Y2 += s.DY * (1 + (abs(s.Y - s.Y2) > 1))
            m.plot(s.X2, s.Y2)
        if abs(s.X - s.X2) + abs(s.Y - s.Y2) < 2:
            return self.borer_strikes()

    def borer_strikes(self):
        """180-185 (the men "killed" are subtracted from NUM, not FM, as in the original)"""
        s, m = self.s, self.m
        m.set_color(s.BKG)
        s.U1 = s.U2 = 0
        m.plot(s.X2, s.Y2)
        m.set_color(4)
        m.plot(s.X, s.Y)
        m.home()
        self.say('THE BORERS CAUGHT YOU! THEY KILLED TWO')
        self.say('MEN AND WOUNDED SEVERAL MORE BEFORE THEYWERE KILLED.')
        s.NUM -= 2
        s.STR -= 3
        self.sound155()
        m.set_color(s.C)
        m.plot(s.X, s.Y)
        s.EN -= 2
        raise Goto(510)

    # ----------------------------------------------------------------------------------
    # 500-579: the turn
    # ----------------------------------------------------------------------------------
    def L500(self):
        s, m = self.s, self.m
        s.C = 9
        s.PC = 0
        if abs(s.X - s.Z1) + abs(s.Y - s.Z2) < 2:
            return self.altar()                                      # 4500
        s.ST = 0
        s.I = s.Y - s.Y % 5
        s.K = s.X - s.X % 5
        s.TM = 0                                                     # 501
        m.set_window(top=20)
        m.home()
        self.say('\rYOU ARE IN THE CATACOMBS.')
        s.N = idiv(s.X, 2)
        s.M = s.LC[s.N * 20 + idiv(s.Y, 2)]
        if s.M:
            s.L = idiv(s.M, 100)
            s.QT = s.M % 100
            self.item_name2()
            if s.QT == 1:                                            # 502
                self.say('THERE IS A ', s.B_S, ' ON THE FLOOR HERE.')
            if s.QT > 1:
                self.say('THERE ARE ', s.QT, ' ', s.B_S, ' ON THE\rFLOOR HERE. ', end='')
        self.say('WHAT DO YOU WANT TO DO NOW?', end='')              # 503
        if s.FM < 1:                                                 # 504
            return self.all_dead()
        if s.EN == 4:                                                # 505
            if s.PG:
                s.PG -= 1
                if s.PG == 8:
                    m.home()
                    self.say('\rTHE GAS IS DEFINITELY HAVING SOME\rEFFECT. THINGS LOOK KIND OF STRANGE.')
                    self.wait140()
            if s.PG == 0 and s.EN == 4:                              # 507
                s.EN = 0
                m.recolor(s.BKG, 0)
                s.BKG = 0
                m.home()                                             # 508
                self.say('YOU MUST HAVE GOTTEN OUT OF THE GAS.\rTHINGS ARE BEGINNING TO LOOK NORMAL\rAGAIN. WHAT NOW?')
                self.key99()
                return self.L511()
        return 510

    def L510(self):
        self.m.clear_strobe()
        self.getkey()
        return self.L511()

    def L511(self):
        s, m = self.s, self.m
        if s.V in (N_, S_, E_, W_):
            return self.move()
        m.home()
        return self.L512()

    def L512(self):
        s, m = self.s, self.m
        v = s.V
        if v == 204:                                                 # 512: the light
            self.say()
            if s.LT:
                m.switch(-16299)
                s.LT = 0
                return 510
            m.switch(-16300)
            s.LT = 1
            self.say('    OK, YOUR LIGHT IS ON. NOW WHAT?')
            return 510
        if s.LT == 0:                                                # 520: too dark for anything else
            return 510
        if v == 201:
            self.save_screen()
            m.switch(-16303)
            self.inventory()
            self.restore_screen()
            m.switch(-16304)
            return 500
        if v == 196:                                                 # 525
            return self.down()
        if v == 213:
            return self.cmd_use()
        s.U1 = s.U2 = s.U3 = 0
        if v == 208:
            return self.cmd_put()
        if v == 199:
            return self.cmd_get()
        if v == 209:
            return self.cmd_quit()
        if v == 195:
            self.status()
            return 510
        if v == 194:                                                 # 527: burrow
            s.C = 0
            for j in range(1, s.BN + 1):
                if s.BG[j] == 8:
                    s.C = 1
            if not s.C:
                self.say("\rWE DON'T HAVE A SHOVEL, M'LORD.")
                return 510
            self.announce('WHICH DIRECTION, SIRE?')                  # 528
            s.Z9 = 1
            return 510
        if v == 207:                                                 # 530
            return self.cmd_out()
        if v == 212:
            return self.teleport()
        self.commands()                                              # 579
        return 510

    def commands(self):
        """580-590"""
        self.inverse(' COMMANDS ARE: ')
        self.say(' NORTH, SOUTH, EAST,')
        self.say('WEST, USE, PUT, GET, LIGHT, DOWN,\rCONDITION, INVENTORY, OUT, TELEPORT,\rBURROW, AND QUIT', end='')

    def teleport(self):
        """530-542"""
        s, m = self.s, self.m
        self.say('TELEPORTATION IS VERY DANGEROUS, SIRE.\rIT REQUIRES WISDOM AND LUCK TO DO IT')
        self.say('CORRECTLY. ARE YOU SURE YOU WISH TO TRY?', end='')
        self.getkey()
        if s.V != YES:
            return 500
        m.set_color(s.BKG)                                           # 532
        m.plot(s.X, s.Y)
        self.sound150()
        while True:                                                  # 533
            s.X = m.rnd(40)
            s.Y = m.rnd(40)
            if m.scrn(s.X, s.Y) == s.BKG:
                break
        s.K = s.X - s.X % 5
        s.I = s.Y - s.Y % 5
        if m.scrn(s.K, s.I + 4) != WALL:
            m.set_color(WALL)
            self.tile(1100 + 10 * m.rnd(5))
            s.X = s.K + 1
            s.Y = s.I + 1
        m.set_color(s.C)                                             # 534
        m.plot(s.X, s.Y)
        s.TM = 1 + (s.WS < 7) + (s.WS < 4)
        s.FM -= s.TM
        m.home()
        if s.FM < 1:
            return self.all_dead()
        if s.EN == 4:                                                # 540
            self.say('\rWE TELEPORTED OUT OF THE GAS, SIRE.')        # 541
            s.EN = s.PG = 0
            if s.BKG != 0:
                m.recolor(s.BKG, 0)
                s.BKG = 0
        else:
            self.say('\rWE TELEPORTED SUCCESSFULLY, SIR.')
        m.vtab(23)                                                   # 542
        if s.TM < 2:
            self.say('1 MAN WAS', end='')
        if s.TM > 1:
            self.say(s.TM, ' MEN WERE', end='')
        self.say(' LEFT BEHIND THOUGH. WHAT NOW?', end='')
        return 510

    # ----------------------------------------------------------------------------------
    # 600-710: walking, and what happens on the way
    # ----------------------------------------------------------------------------------
    def move(self):
        s, m = self.s, self.m
        s.DX = s.DY = 0
        v = s.V
        new = None
        if v == E_:
            s.DX = 1
            self.step()
            if s.X % 5 == 4 and m.scrn((s.K + 5) % 40, s.I + 4) == s.BKG:
                s.K = (s.K + 5) % 40
                new = s.LA
        elif v == S_:
            s.DY = 1
            self.step()
            if s.Y % 5 == 4 and m.scrn(s.K, (s.I + 9) % 40) == s.BKG:
                s.I = (s.I + 5) % 40
                new = s.T
        elif v == W_:
            s.DX = -1
            self.step()
            if s.X % 5 == 0 and m.scrn((s.K - 5 + 40) % 40, s.I + 4) == s.BKG:
                s.K = (s.K - 5 + 40) % 40
                new = s.DR
        else:
            s.DY = -1
            self.step()
            if s.Y % 5 == 0 and m.scrn(s.K, (s.I - 1 + 40) % 40) == s.BKG:
                s.I = (s.I - 5 + 40) % 40
                new = s.B
        if new is not None:                                          # explore a new tile
            m.set_color(WALL)
            s.J = 1 + m.rnd(8)
            self.tile(1160 if s.J == 8 else 1090 + 10 * new[s.J])
        if s.EN in (2, 3):                                           # 640
            self.borer()
        s.M = m.rnd(140)
        if s.M > 9 or s.EN == 4:
            return 500
        m.home()
        self.say()
        return self.event(s.M)

    def step(self):
        """700-710: one square; with the burrow order, through rock."""
        s, m = self.s, self.m
        nx, ny = (s.X + s.DX + 40) % 40, (s.Y + s.DY + 40) % 40
        if m.scrn(nx, ny) != s.BKG:
            if s.Z9 == 0:
                self.say('\x07')                                     # 710
                raise Goto(500)
            m.invflg = 0x7F                                          # 705
            self.announce('BURROWING')
            m.invflg = 0xFF
            self.wait139()
        else:
            s.Z9 = 0
        m.set_color(s.BKG)                                           # 702
        m.plot(s.X, s.Y)
        s.X, s.Y = nx, ny
        m.set_color(s.C)
        m.plot(s.X, s.Y)

    def event(self, n):
        """650-696"""
        s, m = self.s, self.m
        while True:
            if n == 0:                                               # 650: frenzies
                if s.EN == 1:
                    n = 2
                    continue
                if s.EN == 3:
                    return self.stairs()
                while True:
                    s.X0 = m.rnd(40)
                    s.Y0 = m.rnd(40)
                    if m.scrn(s.X0, s.Y0) == s.BKG:
                        break
                m.set_color(8)
                m.plot(s.X0, s.Y0)
                s.EN += 1
                s.SX = 1
                s.U1, s.U2 = 39, 46
                self.say('A SWARM OF FRENZIES HAS BROKEN INTO THE CAVERNS! WHAT NOW?')
                self.sound142()
                return 510
            if n == 1:                                               # 655
                return self.pit_trap()
            if n == 2:                                               # 660: a borer
                if s.EN == 2:
                    n = 0
                    continue
                if s.EN == 3:
                    return self.stairs()
                s.X2 = m.rnd(40)
                s.Y2 = m.rnd(40)
                s.EN += 2
                m.set_color(4)
                m.plot(s.X2, s.Y2)
                s.U1, s.U2 = 41, 42
                self.say('A BORER HAS GOTTEN YOUR SCENT. WHAT DO\rYOU WANT TO DO NOW?')
                self.sound143()
                return 510
            if n == 3:                                               # 665
                return 500
            if n == 4:                                               # 670
                return self.cave_in()
            if n in (5, 6):                                          # 680: something on the floor
                s.QT = m.rnd(3)
                s.N = 1 + m.rnd(20)
                s.M = idiv(s.X, 2)
                s.LC[s.M * 20 + idiv(s.Y, 2)] = (s.N + 20) * 100 + s.QT
                return 500
            if n == 7:                                               # 685
                self.say('\x07THE AIR SMELLS FUNNY HERE. I THINK YOU\rMAY HAVE WANDERED INTO SOME POISONOUS\rGAS. WHAT NOW?')
                s.PG = 10
                s.EN = 4
                self.wait140()
                return 510
            return self.stairs()                                     # 690/695

    def pit_trap(self):
        """655-657"""
        s, m = self.s, self.m
        m.home()
        self.say()
        m.tab(14)
        m.invflg = 0x7F
        self.say('  PIT TRAP!  ')
        self.sound145()
        m.invflg = 0xFF
        s.TM = 2 + m.rnd(4)
        self.say(s.TM, ' MEN FELL INTO THE PIT. THEY MAY HAVE\rSURVIVED. WHAT NOW?', end='')
        s.U1, s.U2, s.U3 = 7, 18, 19
        s.FM -= s.TM
        self.wait140()
        return 510

    def cave_in(self):
        """670-674"""
        s, m = self.s, self.m
        if s.Y < 2 or s.Y > 37:
            return self.pit_trap()
        m.set_color(WALL)
        for l in range(-2, 3):
            j = max(s.X - 3 + abs(l), 0)
            k = min(s.X + 3 - abs(l), 39)
            m.hlin(j, k, s.Y + l)
        s.J = j
        m.set_color(s.C)
        m.plot(s.X, s.Y)
        m.set_color(s.BKG)                                           # 671
        if s.EN in (1, 3):
            m.plot(s.X0, s.Y0)
        self.save_screen()
        m.gr()
        self.say()
        m.invflg = 0x7F
        m.tab(15)
        self.say('  CAVEIN  ')
        m.invflg = 0xFF
        self.sound145()
        m.home()                                                     # 672
        s.TM = 1 + m.rnd(3)
        self.say(s.TM, ' MEN APPEAR TO BE BURIED.')
        self.lose_something()
        self.say('WHAT DO YOU WANT TO DO?')
        s.FM -= s.TM
        while True:
            self.key99()                                             # 673
            if s.V == 204:
                break
            m.home()
            self.say("\r    IT'S TOO DARK TO DO THAT.")
        self.restore_screen()
        s.LT = 0
        s.U1 = 8
        return self.L512()

    def lose_something(self):
        """5000-5010: the cave-in buries some of the gear too."""
        s, m = self.s, self.m
        for _ in range(1000):            # (the original loops forever if nothing qualifies)
            s.BI = 3 + m.rnd(s.BN - 2)
            if not (s.BQ[s.BI] < 2 or s.BG[s.BI] in (5, 49)):
                break
        else:
            return
        s.QT = 1 + m.rnd(s.BQ[s.BI] - 1)
        s.L = s.BG[s.BI]                                             # 5010
        self.item_name2()
        self.say('YOU ALSO LOST ', s.QT, ' ', s.B_S, '.')
        s.M = s.QT
        s.Z5 = s.BI
        s.Z6 = s.M
        self.take_away()

    def stairs(self):
        """695-696"""
        s, m = self.s, self.m
        m.home()
        if s.Z8:
            self.say('\r\x07THERE APPEARS TO BE AN EXIT HERE. WHAT  DO YOU WANT TO DO?')
            s.Z10 = 1
        else:
            self.say("\x07\rTHERE'S A STAIRWAY GOING DOWN HERE. WHATDO YOU WANT TO DO?")
            s.ST = 1
        self.wait140()
        return 510

    def down(self):
        """697-699"""
        s, m = self.s, self.m
        m.home()
        if not s.ST:
            self.say("\r   OK, YOU'RE LYING DOWN. NOW WHAT?")
            return 510
        return self.descend()

    def descend(self):
        """698-699, 1300-1330"""
        s, m = self.s, self.m
        m.gr()
        m.set_color(s.C)
        s.LEV += 1
        s.J = m.rnd(2) * (s.LEV > 1)
        if s.K > 30:
            s.K = 30
        if s.I > 30:
            s.I = 30
        s.X = s.K + s.J + 1
        s.Y = s.I + s.J + 1
        m.plot(s.X, s.Y)
        s.ST = s.EN = 0
        m.set_color(WALL)
        if s.J:
            self.tile(1300)
            m.home()                                                 # 1330
            self.say("YOU'VE ENTERED A LARGE MUSTY ROOM. THEREIS A LARGE ALTAR IN THE CENTER OF THE   ROOM.")
            s.Z1 = s.K + 5
            s.Z2 = s.I + 4
            return 510
        self.tile(1100)
        self.say('YOU HAVE DESCENDED TO LEVEL ', s.LEV + 1)
        return 510

    # ----------------------------------------------------------------------------------
    # 2000-2807: menus and inventory (the Cavern's own versions)
    # ----------------------------------------------------------------------------------
    def item_name2(self):
        """2082-2105: B$ = the name of item L, pluralised for QT."""
        s = self.s
        s.BP = (s.L - 1) * 10 + 1
        if s.L > 30:
            s.BP -= 300
            s.B_S = substr(data.G3, s.BP, s.BP + 9)
        elif s.L > 20:
            s.BP -= 200
            s.B_S = substr(data.G2, s.BP, s.BP + 9)
        else:
            if s.L < 1:
                raise BasicError('RANGE')
            s.B_S = substr(data.G1, s.BP, s.BP + 9)
        if s.QT > 1:
            s.B_S = put(s.B_S, 11, 'ES' if s.L in (33, 15) else 'S')
        return s.B_S

    def slot_name(self):
        """2080"""
        s = self.s
        s.QT = s.BQ[s.BI]
        s.L = s.BG[s.BI]
        return self.item_name2()

    def choose_item(self, verb):
        """2040-2075"""
        s, m = self.s, self.m
        m.home()
        self.inverse(self.menu_prefix, verb, ' WHICH ITEM?   (RET=MORE ITEMS)     ')
        m.set_window(top=21)
        pages = idiv(s.BN - 1, 9)
        page = 0
        while True:
            s.N = page
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
                self.say(s.B_S, end='')
            self.getkey()
            if s.V == 141 and page < pages:
                page += 1
                continue
            if s.V < 177 or s.V > 185 or s.BG[9 * page + s.V - 176] == 0:
                if s.Z15:
                    return None
                raise Goto(500)
            s.BI = 9 * page + s.V - 176
            m.set_window(top=20)
            return s.BI

    def put_down(self):
        """2110-2120: leave M of slot BI on the floor here."""
        s = self.s
        s.N = idiv(s.X, 2)
        if s.BQ[s.BI] < s.M:
            s.M = s.BQ[s.BI]
        s.LC[s.N * 20 + idiv(s.Y, 2)] = 100 * s.BG[s.BI] + s.M
        self.take_away()

    def take_away(self):
        """2115"""
        s = self.s
        s.BQ[s.BI] -= s.M
        if s.BQ[s.BI] < 1 and s.BI > 2:
            self.remove_slot()

    def remove_slot(self):
        """2120"""
        s = self.s
        m = s.BI + 1
        while True:
            s.BG[m - 1] = s.BG[m]
            s.BQ[m - 1] = s.BQ[m]
            m += 1
            if m > s.BN:
                break
        s.M = m
        s.BG[s.BN] = 0
        s.BQ[s.BN] = 0
        s.BN -= 1

    def cmd_use(self):
        """2300-2310"""
        s, m = self.s, self.m
        self.choose_item(' USE')
        s.N = s.BG[s.BI]
        if s.N in (s.U1, s.U2, s.U3):
            return self.used_right_thing()
        self.slot_name()
        m.home()
        self.say('\rUSING YOUR ', s.B_S, ' SERVED NO USEFUL\rPURPOSE. NOW WHAT?')
        return 510

    def cmd_put(self):
        """2340-2370"""
        s, m = self.s, self.m
        self.choose_item('PUT')
        self.slot_name()
        a = put('PUT DOWN YOUR ', 15, s.B_S)
        self.announce(put(a, 25, ' (Y/N)?'))
        self.getkey()
        if s.V != YES:
            return 500
        while True:
            m.home()                                                 # 2350
            self.say('\rYOU HAVE ', s.BQ[s.BI], ' OF THEM.')
            self.say('TOTAL WEIGHT IS ', s.BQ[s.BI] * GW[s.BG[s.BI]],
                     ' AND VALUE IS ', s.BQ[s.BI] * AP[s.BG[s.BI]])
            s.M = m.input_number('HOW MANY WILL YOU DROP')
            if s.M <= s.BQ[s.BI]:
                break
        if s.M < 1:
            return 500
        self.put_down()
        return 500

    def cmd_get(self):
        """2380-2385"""
        s, m = self.s, self.m
        if s.Z8 == 1:
            m.home()                                                 # 4530
            self.say("\rYOU HAVE GOTTEN THE HIGH ONE'S ORB.\rWHAT NOW MY LIEGE?")
            s.Z8 = 2
            s.Z1 = s.Z2 = -1
            return 510
        s.M = idiv(s.X, 2)
        s.N = s.M * 20 + idiv(s.Y, 2)
        if not s.LC[s.N]:
            m.home()
            self.say('\rOK, YOU GOT SOME SPIDER WEBS AND A\rHANDFUL OF SLIMY MUCK FROM THE FLOOR.')
            self.say('WHAT NOW?')
            return 510
        s.M = s.LC[s.N]                                              # 2383
        s.LC[s.N] = 0
        s.L = idiv(s.M, 100)
        s.QT = s.M % 100
        s.BI = s.BN                                                  # 2384
        for j in range(1, s.BN + 1):
            if s.BG[j] == s.L:
                s.BI = j
        s.BG[s.BI] = s.L
        s.BQ[s.BI] += s.QT
        if s.BI == s.BN:
            s.BN += 1
        m.home()                                                     # 2385
        self.item_name2()
        self.say('\rOK, YOU GOT ', s.QT, ' ', s.B_S, '.')
        self.say('WHAT NOW?')
        return 510

    def cmd_quit(self):
        """2400-2420"""
        r = self.quit_question()
        if r is not None:
            return r
        return 500

    def quit_question(self):
        s, m = self.s, self.m
        self.save_screen()
        self.announce('QUIT GAME (Y/N)?')
        self.getkey()
        if s.V != YES:
            return None
        self.announce('SAVE GAME (Y/N)?')                            # 2407
        self.getkey()
        if s.V == YES:
            self.save_game(3)
        raise Quit()

    def cmd_out(self):
        """2510-2520"""
        s, m = self.s, self.m
        if not s.Z10:
            m.home()
            self.say('\rTHERE IS NO WAY OUT RIGHT HERE, SIR.\rPERHAPS A LITTLE FURTHER ON...')
            return 510
        m.home()
        self.say('\rWE MADE IT OUT WITH THE ORB, SIRE.')
        self.wait140()
        self.m.move(0x2C00, 0x2FFF, 0x800)                           # 230
        return self.back_to_ship()

    def inventory(self):
        """2630-2700"""
        s, m = self.s, self.m
        while True:
            s.PC = 1
            m.text()
            s.AW = 0
            self.listing()
            m.set_window(top=21)                                     # 2640
            while True:
                m.home()                                             # 2650
                self.say('YOUR ', s.FM, ' MEN CAN CARRY ', s.FM * 250, '.')
                self.say('YOU HAVE ', s.AW, '. THE EXCESS BAGGAGE\rWAS LEFT ON THE SHIP. DUMP ANY (Y/N)?', end='')
                m.clear_strobe()
                self.getkey()
                if s.V != YES:
                    return
                m.home()                                             # 2679
                self.say()
                m.tab(10)
                s.BI = m.input_number('DUMP WHICH ITEM')
                if s.BI < 1 or s.BI > s.BN:
                    continue
                m.tab(10)
                s.M = m.input_number('HOW MANY')
                if s.M <= s.BQ[s.BI]:
                    break
                self.say("YOU DON'T HAVE THAT MANY OF ITEM ", s.BI)
                self.wait140()
            self.put_down()                                          # 2700

    def listing(self):
        """2740-2807"""
        s, m = self.s, self.m
        m.home()
        self.inverse('          EQUIPMENT INVENTORY           ')
        self.inverse(' ITEM     NAME    QTY   WEIGHT    VALUE ')
        m.vtab(23)
        self.say('PRESS ANY KEY TO HALT LISTING.')
        m.set_window(top=2, bottom=22)
        m.home()
        s.BI = 1
        while s.BI <= s.BN:
            if s.BG[s.BI] != 0:                                      # 2770
                if s.BI < 10:
                    self.say(' ', end='')
                self.say(' ', s.BI, '.  ', end='')
                s.H = s.BG[s.BI]
                self.slot_name()
                self.say(s.B_S, end='')
                m.tab(19)
                self.say(s.BQ[s.BI], end='')
                m.tab(27)
                s.J = GW[s.H] * s.BQ[s.BI]
                self.say(s.J, end='')
                s.AW += s.J
                m.tab(36)
                self.say(AP[s.H] * s.BQ[s.BI])
            if m.peek_kbd() >= 127:                                  # 2800
                m.clear_strobe()
                s.ROT = m.cv
                m.vtab(23)
                m.clreol()
                self.say('CONTINUE LISTING (Y/N)?', end='')
                m.tab(1)
                while True:                                          # 2804
                    s.V = m.peek_kbd()
                    if s.V >= 127:
                        break
                    m.tick(0.01)
                m.clreol()
                m.clear_strobe()
                if s.V == N_:
                    s.BI += 1
                    m.set_window(bottom=24)
                    while s.BG[s.BI] != 0:                           # 2730
                        s.AW += GW[s.BG[s.BI]] * s.BQ[s.BI]
                        s.BI += 1
                    return
                self.say('PRESS ANY KEY TO HALT LISTING.', end='')   # 2805
                m.tab(1)
                m.vtab(s.ROT + 1)
            s.BI += 1
        m.set_window(top=0, bottom=24)

    def status(self):
        """2440-2460"""
        s, m = self.s, self.m
        m.home()
        self.inverse('             STATUS REPORT              ')
        self.say(self.party_label, s.FM, end='')
        m.tab(16)
        self.say('STRENGTH=', s.STR, end='')
        m.tab(29)
        self.say('CHARISMA=', s.CH)
        self.say('EXPER.=', s.EX, end='')
        m.tab(16)
        self.say('WISDOM=', s.WS, end='')
        m.tab(29)
        self.say('SPEED=', s.SP)
        self.say('DEXTERITY=', s.DEX, end='')
        m.tab(16)
        self.say('GOLD=', s.BQ[2], end='')
        m.tab(29)
        self.say('ALIGN.=', s.AL, end='')

    # ----------------------------------------------------------------------------------
    # 3000-3350: using the right thing
    # ----------------------------------------------------------------------------------
    def used_right_thing(self):
        s, m = self.s, self.m
        s.U1 = s.U2 = s.U3 = 0
        m.home()
        n = s.N
        if n in (7, 19, 18):                                         # 3100: rope, net, sail
            self.slot_name()
            self.say('OK, YOU ARE GOING TO USE YOUR ', s.B_S, '.')
            while True:
                self.say('DO YOU WANT TO GO DOWN OR BRING THEM UP (D 0R U)?')   # 3120
                self.getkey()
                m.home()
                if s.V in (213, 196):
                    break
            self.wait140()                                           # 3130
            s.N = m.rnd(3)
            if s.N > s.TM:
                s.N = s.TM
            self.say('YOU MANAGED TO SAVE ', s.TM - s.N, end='')
            if s.TM - s.N == 1:
                self.say(' MAN.')
            if s.TM - s.N != 1:
                self.say(' MEN.')
            self.say(s.N, end='')                                    # 3135
            if s.N > 1:
                self.say(' WERE', end='')
            if s.N == 1:
                self.say(' WAS', end='')
            self.say(' ACTUALLY KILLED IN THE FALL.')
            s.FM = s.FM + s.TM - s.N
            if s.V == 213:
                return 510
            self.wait140()
            return self.descend()
        if n == 41:                                                  # 3350
            self.say('THE BORERS WERE DESTROYED BY THE MAGIC\rLAMP. WHAT NOW?')
            s.EN -= 2
            return self.banished_borer(False)
        if n == 42:                                                  # 3300
            self.say('THE BORERS WERE BANISHED FROM THE\rCATACOMBS BY THE SCEPTER. WHAT NOW?')
            return self.banished_borer(True)
        if n == 39:                                                  # 3200
            self.say('USING THE AMULET HAS BANISHED THE\rFRENZIES FROM THE CATACOMBS. WHAT NOW?')
            return self.banished_frenzies()
        if n == 46:                                                  # 3250
            self.say('THE FRENZIES WERE DESTROYED BY THE\rMAGIC WAND. WHAT NOW?')
            return self.banished_frenzies()
        s.BI = s.Z5                                                  # 3020: dug out
        s.QT = s.Z6
        self.slot_name()
        self.say('OK, YOU SAVED THE ', s.QT, ' ', s.B_S, '.')
        s.BQ[s.BI] += s.QT
        if s.Z3:                                                     # 3035
            self.say('THE MEN WERE PROTECTED BY THEIR HELMETS AND WERE ALSO SAVED.')
            s.FM += s.TM
        else:
            self.say('UNFORTUNATELY,THE MEN WERE ALL KILLED BYTHE FALLING ROCKS (NO HELMETS).')
        return 510

    def banished_frenzies(self):
        """3220"""
        s, m = self.s, self.m
        s.EN -= 1
        m.set_color(s.BKG)
        m.plot(s.X0, s.Y0)
        return self.used_up_magic()

    def banished_borer(self, count_down):
        """3320 (3350 jumps to a line 3325 that does not exist; it is taken to
        mean the rest of 3320)"""
        s, m = self.s, self.m
        if count_down:
            s.EN -= 2
        m.set_color(s.BKG)
        m.plot(s.X2, s.Y2)
        return self.used_up_magic()

    def used_up_magic(self):
        """3225: one of the magic items is used up.  (The original looks the item
        up with BG(BI) instead of BG(M), finds nothing, and stops with an error;
        the port does what was meant.)"""
        s = self.s
        s.BI = 0
        for k in range(1, s.BN + 1):
            if s.BG[k] == s.N:
                s.BI = k
        if s.BQ[s.BI] < 2:
            self.remove_slot()
            return 510
        s.BQ[s.BI] -= 1
        self.sound150()
        return 510

    # ----------------------------------------------------------------------------------
    # 4000, 4500: the end of the party; the altar
    # ----------------------------------------------------------------------------------
    def all_dead(self):
        m = self.m
        m.text()
        m.home()
        m.vtab(5)
        self.say('I AM SORRY TO REPORT, MY LEIGE, THAT ALLTHE MEMBERS OF YOUR PARTY WERE KILLED.')
        self.say('\r\rBETTER LUCK NEXT TIME, SIRE.')
        raise GameOver()

    def altar(self):
        s, m = self.s, self.m
        m.home()
        self.say('YOU ARE AT AN ENORMOUS BLOOD STAINED    ALTAR. THERE IS A JEWEL ENCRUSTED ORB ON', end='')
        self.say('THE ALTAR. WHAT DO YOU WANT TO DO NOW   SIRE?', end='')
        s.Z8 = 1
        return 510

    # ----------------------------------------------------------------------------------
    # 20000-23010: the Caliph's fortress on the Isle of Lapour
    # ----------------------------------------------------------------------------------
    def L20000(self):
        s, m = self.s, self.m
        s.U1 = s.U2 = s.U3 = s.U4 = s.J = 0
        s.Z15 = 1
        m.hgr_load(self.game.asset('island2.hgr'))
        s.X0, s.Y0 = 150, 150
        s.SHAPE = 2
        self.xdraw()
        s.Z6 = 21000 + 100 * m.rnd(9)                                # three hazards
        while True:
            s.Z7 = 21000 + 100 * m.rnd(9)
            if s.Z6 != s.Z7:
                break
        s.Z9 = 21000 + 100 * m.rnd(9)    # (20007 compares Z8 by mistake, so no retry)
        return 20010

    def L20010(self):
        s, m = self.s, self.m
        m.set_window(top=20)
        s.LN = 19990
        m.home()
        self.say()
        return self.L20011()

    def L20011(self):
        self.say('\r     WHAT DO YOU WANT TO DO NOW?', end='')
        return 20012

    def L20012(self):
        s, m = self.s, self.m
        while True:
            self.getkey()
            if s.V == 210:
                return self.retreat()
            if s.V == 193:
                return self.advance()
            if s.V == 213:
                return self.fortress_use()
            if s.V == 201:
                self.inventory()
                s.ROT = 0
                m.gr()
                return 20010
            if s.V == 195:
                self.status()
                continue
            if s.V == 209:
                self.quit_question()
                return 20010
            m.home()                                                 # 20015
            self.inverse(' COMMANDS ARE: ')
            self.say(' APPROACH THE FORTRESS,\rRETURN TO THE SHIP, CONDITION,\rINVENTORY, ', end='')
            self.say('OR USE SOMETHING.')

    def retreat(self):
        """20050"""
        s, m = self.s, self.m
        m.home()
        self.announce('YOU WISH TO RETREAT?')
        self.getkey()
        if s.V != YES:
            return 20010
        return self.back_to_ship()

    def back_to_ship(self):
        """20055"""
        s = self.s
        self.announce('BACK TO THE SHIP!')
        s.X0, s.Y0 = s.X3, s.Y3
        s.Z15 = 0
        raise Chain('sea')

    def advance(self):
        """20020-20024"""
        s, m = self.s, self.m
        if s.U1:
            m.home()                                                 # 20900: force the way
            s.I = idiv(s.FM, 2)
            if s.I < 5:
                s.I = 5
            s.FM -= s.I
            if s.FM < 1:
                return self.all_dead()
            self.say('WE MADE IT PAST THE HAZARD, SIR, BUT\r', s.I, ' MEN WERE KILLED.')
            s.U1 = 0                                                 # 20910
            return 20011
        self.xdraw()
        if s.Y0 == 125:
            s.X0, s.Y0, s.LN = 175, 100, s.Z7
        elif s.Y0 == 100:
            s.X0, s.Y0, s.LN = 170, 80, s.Z9
        elif s.Y0 == 80:
            return self.the_end()
        else:
            s.X0, s.Y0, s.LN = 150, 125, s.Z6
        self.xdraw()
        m.home()
        self.say("WE MADE IT THIS FAR, BUT WE'RE BLOCKED\rBY ", end='')
        return self.hazard(s.LN)

    HAZARDS = {
        21000: ('A STREAM OF LAVA IN A NARROW FISSURE.FLAMES AND FUMES ARE RISING FROM IT.', False,
                (45, 0, 31, 0)),
        21100: ('A RIVER OF CORROSIVE GREEN SLIME.', True, (45, 0, 3, 0)),
        21200: ('A DENSE FOREST OF POISONOUS THORNS.', True, (33, 11, 4, 0)),
        21300: ('AN ENORMOUS STONE GATE WITH A SMALL\rWINDOW IN IT.', False, (32, 0, 35, 0)),
        21400: ('A MEDUSAE UP AHEAD. TO LOOK\rUPON ONE UP CLOSE IS DEATH.', False, (34, 0, 25, 26)),
        21500: ('A SHIMMERING CURTAIN OF FIRE.', True, (46, 47, 13, 0)),
        21600: ('A SPIKE STUDDED, IRON SHEATHED PORTALWITH SEVERAL LARGE LOCKS.', False, (38, 0, 2, 0)),
        21700: ('A LABYRINTH WITH NUMEROUS TRAPS.', True, (36, 40, 0, 0)),
        21800: ('SEVERAL GIGANTIC SPIDERS AHEAD IN A\rNARROW PASSAGE, TOO CONFINED TO FIGHT.', False,
                (43, 44, 18, 0)),
    }
    SUCCESS = {
        21000: '\rWE MADE IT ACROSS, SIRE, BUT THE CARPET CAUGHT FIRE AND BURNED.',
        21100: '\rWE MADE IT ACROSS, SIR, BUT THE CARPET  DISSOLVED AS WE LANDED.',
        21200: '\rTHE THORN FOREST BURNED NICELY.',
        21300: '\rTHE MONKEY GOT THE DOOR OPEN.',
        21400: '\rWITH THE MIRRORS, WE GOT CLOSE ENOUGH\rTO KILL IT.',
        21500: '\rTHE FIRE WAS BLOWN AWAY.',
        21600: '\rTHE PORTAL SILENTLY OPENED.',
        21700: '\r      WE MADE IT THROUGH SAFELY.',
        21800: '\rTHE POTION TEMPORARILY TURNED EVERYONE  INVISIBLE AND WE GOT BY.',
    }
    COSTLY = {
        21000: 'SUCCUMBED TO THE FUMES\rAND FELL IN.',
        21100: 'FELL IN AS THE BOAT DISSOLVED.',
        21200: 'WERE STABBED AND DIED IN AGONY.',
        21300: 'WERE CRUSHED WHEN THE DOOR FELL.',
        21400: 'WERE TURNED TO STONE AS HER\rGAZE CAUGHT THEM WHILE THEY FIRED.',
        21500: 'WERE BURNED.',
        21600: 'WERE IMPALED WHEN THE PORTAL FELL OPEN.',
        21700: 'WERE KILLED BY THE TRAPS.',
        21800: 'WERE STUNG AND DIED HORRIBLY.',
    }

    def hazard(self, ln):
        """21000-21800: what blocks the way, and what will get past it."""
        s = self.s
        text, newline, (u1, u2, u3, u4) = self.HAZARDS[ln]
        self.say(text, end='\r' if newline else '')
        s.U1 = u1                       # (a 0 here means the line leaves it alone)
        if u2:
            s.U2 = u2
        if u3:
            s.U3 = u3
        if u4:
            s.U4 = u4
        return 20011

    def fortress_use(self):
        """20070-20090"""
        s, m = self.s, self.m
        self.choose_item(' USE')
        m.gr()
        if s.V < 177 or s.V > 185:
            return 20010
        m.home()
        s.N = s.BG[s.BI]
        if s.LN == 19990 and s.N in (s.U1, s.U2, s.U3, s.U4):
            # No hazard in the way, but a leftover U2-U4 matches: the original's
            # GOTO LN+20 / LN+30 then lands on line 20010 / 20020.
            if s.N in (s.U1, s.U2):
                return 20010
            s.I = 2 + m.rnd(3)
            s.FM -= s.I
            if s.FM < 1:
                return self.all_dead()
            self.say('\rMOST OF THE TROOP MADE IT, SIRE.\r', s.I, ' MEN ', end='')
            return self.advance()
        if s.N in (s.U1, s.U2):
            self.say(self.SUCCESS[s.LN])
            return self.hazard_passed()
        if s.N in (s.U3, s.U4):
            s.I = 2 + m.rnd(3)                                       # 20090
            s.FM -= s.I
            if s.FM < 1:
                return self.all_dead()
            self.say('\rMOST OF THE TROOP MADE IT, SIRE.\r', s.I, ' MEN ', end='')
            # (21030 continues at a non-existent line 20025; 21025 is meant)
            self.say(self.COSTLY[s.LN], end='' if s.LN == 21000 else '\r')
            if s.LN == 21400:
                self.wait140()
            return self.hazard_passed()
        m.home()
        self.slot_name()
        self.say('\rUSING YOUR ', s.B_S, ' SERVED NO USEFUL\rPURPOSE. NOW WHAT?')
        return 20012

    def hazard_passed(self):
        """21025"""
        s = self.s
        s.M = 1
        self.take_away()
        s.U1 = s.U2 = s.U3 = 0
        self.wait139()
        return 20010

    def the_end(self):
        """22000-23010"""
        s, m = self.s, self.m
        m.home()
        if s.Z8:
            self.say('\r          YOU MADE IT!!!!!')
            self.sound147()
            self.say("SINCE YOU HAVE THE HIGH ONE'S ORB, THE")
            self.say("CALIPH'S MEN HAVE DESERTED TO YOUR SIDE.THE CALIPH HAS FLED. YOU ARE THE NEW\r"
                     "HIGH ONE OF THE REALM.", end='')
            self.wait139()
        else:
            self.say("YOU MADE IT INTO THE CASTLE. WITHOUT THEHIGH ONE'S ORB, HOWEVER, THE CALIPH'S\r"
                     "MEN FOUGHT AND DESTROYED YOUR FORCE.", end='')
            self.wait139()
            self.wait139()
            s.FM = 0
        s.I = 0                                                      # 22005: the score
        for j in range(1, s.BN + 1):
            s.I += idiv(s.BQ[j] * AP[s.BG[j]], 10)
        s.J = idiv(s.BQ[2], 10) + s.I + s.TEN * 10 - (s.TOT - s.FM) * 20 + s.TSH * 5
        m.text()
        m.home()
        self.say('\r\r\rYOU ENDED THE QUEST WITH:\r\r   - ', s.FM, ' MEN OUT OF ', s.TOT, ' RECRUITED.\r   - ',
                 s.BQ[2], ' GOLD QUADROONS.')
        self.say('   - ', s.I, "0 QUADROONS WORTH OF GOODS.\r   - YOU ALSO KILLED ", s.TEN,
                 " OF THE REALM'S\r     INHABITANTS.")
        self.say('   - AND SANK ', s.TSH, ' SHIPS.')
        self.say('\r\rYOUR COMPOSITE SCORE IS ', s.J, "0\r\r\r(INCIDENTALLY, YOUR ALIGNMENT FACTOR\rINDICATES YOU'RE ",
                 end='')
        if s.AL <= -30:
            self.say('A BLACKHEARTED FIEND.)')
        elif s.AL <= -20:
            self.say('QUITE EVIL MINDED.)')
        elif s.AL <= 20:
            self.say('BALANCED BETWEEN GOOD\rAND EVIL.)')
        elif s.AL <= 40:
            self.say('A KIND AND GENEROUS\rLEADER.)')
        else:
            self.say('A VIRTUAL SAINT AMONG\rMEN.)')
        raise GameOver()
