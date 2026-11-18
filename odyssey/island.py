"""ISLAND APVENTURE - the overland part: wandering the island of the Sargalo Sea.

Port of the Integer BASIC program "ISLAND APVENTURE".  Line numbers in the
comments refer to the original listing.

The island map LC() is 20x20 cells of 14x8 pixels, column major:
LC(col*20 + row + 1).  A cell value is TTQQII:
  TT = LC/10000      terrain (0 jungle, 1 swamp, 2 mountains, 3 ocean)
  QQ = (LC MOD 10000)/100   quantity of the object lying there
  II = LC MOD 100    object: 1-49 an item, 51-56 a site (temple, ruin,
                     castle, tomb, hut, city), 99 a passage already blocked
A sealed site gets 100 added, so LC MOD 1000 is no longer 51-56.
"""
from . import data
from .apple import BasicError, BASIC_STATEMENT, NEXT_TIME
from .part import Part, Goto, Chain, GameOver, idiv, imod, sgn, substr, put

GW, AP = data.ITEM_WEIGHT, data.ITEM_PRICE

N_, S_, E_, W_ = 206, 211, 197, 215     # key codes (high bit set)
RETURN = 'RETURN'                       # a subroutine's RETURN reached through GOTOs
YES, RET, ESC = 217, 141, 155


class Island(Part):
    abandon_line = 599

    def entries(self):
        return {
            26: self.L600, 598: self.L598, 599: self.L599, 600: self.L600, 700: self.L700,
            725: self.L725, 900: self.L900, 9010: self.L9010, 9710: self.L9710,
            9761: self.L9761, 9890: self.L9890, 9900: self.L9900, 32000: self.L600,
        }

    # ----------------------------------------------------------------------------------
    # Keyboard (100-130).  While waiting, the party blinks; when riding or flying
    # it keeps moving in the chosen direction.
    # ----------------------------------------------------------------------------------
    def getkey(self):
        s, m = self.s, self.m
        while True:
            s.V = m.peek_kbd()
            if s.V >= 128:
                m.clear_strobe()
                if s.V == ESC:
                    raise Goto(600)
                if s.DS and s.TF == 0:
                    self.xdraw()
                s.DS = 0
                return s.V
            if not s.TF:                                            # 110
                # One pass of the 100/110 polling loop.  The party toggles every
                # 10 passes; 25 ms a pass gives a leisurely blink.
                m.tick(0.025)
                s.CT += 1
                if s.CT % 10:
                    continue
                self.xdraw()
                s.CT = 0
                s.DS = int(not s.DS)
                continue
            m.statements(10)                                        # 120
            self.xdraw()
            s.X0 = imod(s.X0 + s.TDX + 279, 279)
            s.Y0 = imod(s.Y0 + s.TDY + 191, 191)
            self.xdraw()
            if s.TF == 2:
                continue
            if idiv(self.lc(idiv(s.X0, 14) * 20 + idiv(s.Y0, 8) + 1), 10000) != 3:
                continue
            self.xdraw()                                            # 125
            if s.TF:
                s.X0 = imod(s.X0 + 6, 279)
            s.SHAPE = 2
            s.X0 = imod(s.X0 - s.TDX + 279, 279)
            s.X = s.X0
            s.Y0 = imod(s.Y0 - s.TDY + 191, 191)
            s.Y = s.Y0
            self.xdraw()
            s.TF = 0
            m.home()                                                # 130
            self.say('NOT ONE OF YOUR BETTER MOVES, SIRE. YOU DROWNED 2 HORSES.')
            self.wait40()
            self.find_item(20)
            s.BQ[s.K] -= 2
            raise Goto(600)

    # ----------------------------------------------------------------------------------
    # 55: is anybody left?
    # ----------------------------------------------------------------------------------
    def check_alive(self):
        s, m = self.s, self.m
        if s.FM > 0:
            return
        self.wait40()
        m.home()
        self.say('I AM SORRY TO REPORT, MY LIEGE, THAT ALLTHE MEN IN YOUR EXPEDITIONARY PARTY WERE', end='')
        self.say('LOST. BETTER LUCK NEXT TIME, SIRE.', end='')
        s.X0 = s.X
        s.SHAPE = 2
        self.xdraw()
        s.SHAPE = 4
        s.COLR = 127
        self.xdraw()
        self.key99()
        raise GameOver(died=True, dismissed=True)

    # ----------------------------------------------------------------------------------
    # 300: work out where we are.  TT = terrain, C1/QT = object here, DR() = the
    # eight neighbouring cells.  Neighbouring sites get drawn on the map.
    # ----------------------------------------------------------------------------------
    def locate(self):
        s = self.s
        s.I = idiv(s.X0, 14) + 1
        s.J = idiv(s.Y0, 8) + 1
        s.PTR = (s.I - 1) * 20 + s.J
        s.K = self.lc(s.PTR)
        s.TT = idiv(s.K, 10000)
        if s.TT == 3:
            self.walked_into_sea()                                   # 370
        s.C1 = 0                                                     # 305
        if s.K % 10000 != 0:
            self.object_here()                                       # 310
        if s.C1 == 0 and not self.m.rnd(30):                        # 320: something turns up
            s.I = 31 + self.m.rnd(7)
            s.LC[s.PTR] += 100 + s.I
            s.K = s.LC[s.PTR]
            self.object_here()
        p = s.PTR                                                    # 325
        s.DR[1:9] = [self.lc(p - 1), self.lc(p + 19), self.lc(p + 20), self.lc(p + 21),
                     self.lc(p + 1), self.lc(p - 19), self.lc(p - 20), self.lc(p - 21)]
        for i in range(1, 9):                                        # 340
            s.I = i
            s.J = s.DR[i] % 1000
            if s.J < 50 or s.J > 55:
                continue
            s.X, s.Y = s.X0, s.Y0
            s.X0 = 14 * (idiv(p, 20) + 1) + 14 * (i in (2, 3, 4)) - 14 * (i in (6, 7, 8)) - 7
            s.Y0 = 8 * (imod(p, 20) - 1) + 8 * (i in (4, 5, 6)) - 8 * (i in (8, 1, 2))
            s.SHAPE = s.J - 40
            s.COLR = 42
            self.safe_draw()
            s.X0, s.Y0 = s.X, s.Y
            s.SHAPE = 2
        s.I = 9

    def safe_draw(self):
        try:
            self.draw()
        except BasicError:
            pass          # a site just off the edge of the map: the original stops here

    def object_here(self):
        """310: what is lying in this cell?"""
        s = self.s
        s.C1 = s.K % 1000
        if 50 < s.C1 < 57:
            self.at_site()                                           # 9000
        s.C1 = s.K % 100
        if s.C1 < 51:
            s.QT = idiv(s.K % 10000, 100)
        if s.C1 == 99:
            raise Goto(self.blocked_again())                         # 3010

    def walked_into_sea(self):
        """370: back off the water."""
        s, m = self.s, self.m
        self.xdraw()
        s.X0 = imod(s.X0 - 3 * s.DX + 279, 279)
        s.X = s.X0
        s.Y0 = imod(s.Y0 - 3 * s.DY + 191, 191)
        self.xdraw()
        m.home()
        self.say('I AM SORRY, MY LIEGE. YOUR MEN DO NOT\rAPPEAR TO HAVE YOUR ABILITY TO WALK ON\rWATER.')
        raise Goto(700)

    # ----------------------------------------------------------------------------------
    # Inventory bookkeeping
    # ----------------------------------------------------------------------------------
    def drop(self):
        """430: drop QT of slot BI here (if the ground is clear)."""
        s = self.s
        s.AW = s.AW - s.QT * GW[s.BG[s.BI]]
        s.I = s.QT                                                   # 435
        self.use_up()
        if s.QT > 99:
            s.QT = 50 + self.m.rnd(50)
        if s.LC[s.PTR] % 10000 == 0:
            # Note: if the slot was emptied the list has already moved up, so
            # BG(BI) is now the *next* item - as in the original.
            s.LC[s.PTR] += s.QT * 100 + s.BG[s.BI]

    def direction(self):
        """490: DX,DY from the key in V."""
        s = self.s
        s.DX = s.DY = 0
        if s.V == 200:
            return
        if s.V == N_:
            s.DY = -1
        if s.V == S_:
            s.DY = 1
        if s.V == E_:
            s.DX = 1
        if s.V == W_:
            s.DX = -1

    def ask_direction(self):
        """512: wait for a direction key (or H)."""
        s = self.s
        while True:
            self.getkey()
            self.direction()
            if s.V == 200:
                return
            if s.DX + s.DY != 0:
                return

    def birds(self):
        """570: a flock of flying monsters swoops in on the party."""
        s, m = self.s, self.m
        m.home()
        self.say('\x07TAKE COVER! A \x07BUNCH OF ', s.A_S)
        self.say('ARE \x07FLYING THIS \x07WAY!\r')
        s.X2, s.Y2 = s.X0, s.Y0
        s.I = m.rnd(2)
        s.J = m.rnd(2)
        s.X0 = 270 * s.I
        s.Y0 = 160 * s.J
        s.SHAPE = 20
        self.xdraw()
        while abs(s.X0 - s.X2) + abs(s.Y0 - s.Y2) >= 3:
            s.I = s.X0 - 2 * sgn(s.X0 - s.X2)
            s.J = s.Y0 - 2 * sgn(s.Y0 - s.Y2)
            self.xdraw()
            s.X0, s.Y0 = s.I, s.J
            self.xdraw()
            m.statements(8)
        self.xdraw()
        s.X0, s.Y0 = s.X2, s.Y2
        m.home()

    # ----------------------------------------------------------------------------------
    # The turn: 598 / 599 / 600 / 609-660 / 700
    # ----------------------------------------------------------------------------------
    def L598(self):
        self.s.Z1 = 0
        self.weight_check()
        return self.L599()

    def L599(self):
        s, m = self.s, self.m
        m.gr()
        m.home()
        if s.Z3 and s.TM:
            return 9761
        if s.Z3:
            return 9710
        if s.Z1:
            return 9010
        return 600

    def L600(self):
        s, m = self.s, self.m
        s.Z7 = 0
        s.Z4 = s.Z4 - (s.Z4 > 0)
        s.Z3 = s.Z2 = s.Z1 = 0
        m.switch(-16304)
        m.switch(-16301)
        m.switch(-16297)
        m.set_window(top=20)
        s.U1 = s.U2 = s.U3 = 0
        s.TM = 0
        s.Z9 = 0                                                    # 602
        s.Z5 = (s.Z5 + 1) % 5
        if not s.Z5:
            s.J = s.BQ[1] - idiv(s.FM, 10) - ((s.FM % 10) > 5)
            if s.J < 0:
                s.J = 0
            if s.J == 0:
                s.Z6 += 1
            s.BQ[1] = s.J
            if s.Z6 >= 3:                                            # 603
                m.home()
                self.say('\r     A MAN STARVED TODAY.')
                s.FM -= 1
                self.weight_check()
                return 700
        return self.describe()

    def describe(self):
        """609-660: where are we and what can we see?"""
        s, m = self.s, self.m
        if s.X != s.X0:
            self.xdraw()
        s.X0 = s.X
        s.SHAPE = 2
        m.home()
        s.C1 = 0
        self.locate()
        s.I = 9 * s.TT + 1
        s.A_S = substr(data.T, s.I, s.I + 8)
        if s.BQ[1] > idiv(s.FM, 5):
            self.say('YOU ARE IN THE ', s.A_S, end='')
        if s.BQ[1] < 1:                                              # 610
            self.say('YOU ARE OUT OF FOOD', end='')
        if 0 < s.BQ[1] < idiv(s.FM, 5) + 1:
            self.say('YOU ARE LOW ON FOOD', end='')
        self.say('. YOU CAN SEE')                                    # 611
        if not (s.C1 == 0 or s.C1 > 50):
            s.M = s.C1                                               # 612
            self.item_name()
            self.say(s.QT, ' ', s.B_S, ' HERE.')
            return 700
        s.M = s.J = s.F = 0                                          # 615
        for i in range(1, 9):
            s.I = i
            s.K = s.DR[i] % 100
            s.L = idiv(s.DR[i], 10000)
            if s.L != s.TT:
                s.M = 1
            if s.K == 0 and (s.V != 204 or s.L == s.TT):
                continue
            dr = substr(data.DR, (i - 1) * 2 + 1, (i - 1) * 2 + 2)
            if s.K != 0:
                s.K -= 50                                            # 620
                if s.K > 10:
                    continue
                if s.K < 0 and s.K != -50:
                    s.K = 7
                s.K = s.K * 7 - 6
                s.J = 1
                if s.K != 43:                                        # 630
                    self.say('A ', substr(data.O, s.K, s.K + 6), end='')
                if s.K == 43:
                    self.say('AN OBJECT', end='')
                self.say(' TO THE ', dr, '. ', end='')
            else:                                                    # 635
                s.L += (160 < s.X0 < 225 and 75 < s.Y0 < 130 and s.L == 3)
                s.L = s.L * 9 + 1
                self.say(substr(data.T, s.L, s.L + 8), end='')
                self.say(' TO THE ', dr, '. ', end='')
            if s.F and i < 8 and m.ch > 5:                           # 645
                self.say()
            s.F = int(not s.F)
            if m.ch < 5:
                m.ch = 0
        s.I = 9
        if s.J == 0 and s.M == 0:                                    # 650
            self.say('NOTHING BUT ', s.A_S, ' IN ALL DIRECTIONS.')  # 660
            return 700
        if s.J or s.V == 204:
            return 700
        self.say('NOTHING OF INTEREST IN THE VICINITY.')             # 655
        return 700

    def L700(self):
        """700-750: read a command."""
        s, m = self.s, self.m
        self.check_alive()
        v = self.getkey()
        if v == 204 and s.Z1:                                        # 701
            return 9010
        if v == 204:
            return 600
        if v == 196:
            return self.cmd_drop()
        if v == 213:
            return self.cmd_use()
        if v == 199:
            return self.cmd_get()
        if v == 209:
            return self.cmd_quit()
        if v == 195:
            self.status()
            return 700
        if v in (N_, S_, E_, W_):                                    # 705
            self.direction()
            return 725
        if v == 201:                                                 # 710
            return 900
        if v == RET:
            return 725
        if v == 210:
            return self.cmd_ride()
        if v == 200:
            self.announce('YOU ARE HALTED.')
            return 700
        m.home()
        self.inverse(' COMMANDS ARE: ')
        self.say(' LOOK, USE, DROP, GET,\rHALT, CONDITION, NORTH, SOUTH, EAST,    WEST, RIDE, INVENTORY, AND QUIT',
                 end='')
        return 700

    def L725(self):
        """725: take a step (bigger when leaving a site), then maybe an event."""
        s, m = self.s, self.m
        self.xdraw()
        s.SHAPE = 2
        s.X0 = imod(s.X0 + 3 * s.DX + 279 + 10 * s.Z1 * s.DX, 279)
        s.X = s.X0
        s.Y0 = imod(s.Y0 + 3 * s.DY + 191 + 5 * s.Z1 * s.DY, 191)
        self.xdraw()
        s.Z1 = 0
        s.I = m.rnd(60)                                              # 726
        if s.I > 6:
            return 600
        if s.I > 2:
            s.I = 0
        return [self.encounter, self.trap, self.obstacle][s.I]()     # 750

    # ----------------------------------------------------------------------------------
    # Commands
    # ----------------------------------------------------------------------------------
    def cmd_use(self):
        """760"""
        s, m = self.s, self.m
        self.choose_item(' USE')
        s.I = s.BG[s.BI]
        if s.I in (s.U1, s.U2, s.U3):
            return self.used_right_thing()                           # 8000
        m.home()                                                     # 762
        if s.I == 49:
            return self.use_ship()                                   # 7000
        if 38 < s.I < 48:
            return self.use_magic(s.I)                               # 8100+
        self.slot_name()                                             # 765
        self.say('\rUSING YOUR ', s.B_S, " DIDN'T HAVE\rANY USEFUL EFFECT.")
        self.wait35()
        if s.Z3 == 0 and s.U1 and s.TM:
            return self.trapped()                                    # 2010
        return 599

    def cmd_drop(self):
        """770-777"""
        s, m = self.s, self.m
        self.choose_item('DROP')
        self.slot_name()
        a = put('DROP YOUR ', 11, s.B_S)
        s.A_S = put(a, 21, ' (Y/N)?')
        self.announce()
        if self.getkey() != YES:
            return 600
        while True:
            m.home()                                                 # 775
            self.say('YOU HAVE ', s.BQ[s.BI], ' OF THEM.')
            self.say('TOTAL WEIGHT IS ', s.BQ[s.BI] * GW[s.BG[s.BI]],
                     ' AND VALUE IS ', s.BQ[s.BI] * AP[s.BG[s.BI]])
            s.QT = m.input_number('HOW MANY WILL YOU DROP')
            if s.QT < 1:
                return 600
            if s.QT <= s.BQ[s.BI]:
                break
        self.drop()
        return 600

    def cmd_get(self):
        """780-782: pick up what the last look showed."""
        s, m = self.s, self.m
        m.home()
        if not (0 < s.C1 < 50):
            self.say('\rOK, YOU GOT TWO HANDFULS OF MUD. NOW    WHAT?')
            return 700
        self.say('\r   OK, YOU GOT ', s.QT, ' ', s.B_S, '. NOW WHAT?')
        self.gain()
        s.LC[s.PTR] = s.LC[s.PTR] - 100 * s.QT - s.C1
        return 700

    def cmd_quit(self):
        """790-797"""
        self.quit_game(1)
        return 600

    def cmd_ride(self):
        """820-828: ride the horses (or, from 8160, fly the rug)."""
        s = self.s
        self.find_item(20)
        if not (s.K > 0 and s.BQ[s.K] >= idiv(s.FM, 2)):
            self.announce('NOT ENOUGH HORSES')
            return 700
        s.TF = 1                                                     # 825
        s.A_S = '      RIDE      '
        self.xdraw()
        s.SHAPE = 3
        return self.travel()

    def travel(self):
        """826-828"""
        s, m = self.s, self.m
        s.TDX = s.TDY = 0
        m.invflg = 0x3F
        s.X0 = imod(s.X0 - 6 + 279, 279)
        self.xdraw()
        self.announce()                                              # 827
        m.invflg = 0xFF
        m.vtab(23)                                                   # 510
        self.center('WHICH DIRECTION?')
        self.ask_direction()
        while True:
            s.TDX, s.TDY = s.DX, s.DY                                # 828
            self.ask_direction()
            if s.V == 200:
                break
        s.TF = 0
        self.xdraw()
        s.SHAPE = 2
        s.X0 = imod(s.X0 + 6, 279)
        s.X = s.X0
        self.xdraw()
        return 600

    # ----------------------------------------------------------------------------------
    # Inventory screens and weight (900-998)
    # ----------------------------------------------------------------------------------
    def L900(self):
        self.inventory_dialog()
        return 599          # only reached through a stray RETURN

    def inventory_dialog(self):
        """900-953.  Returns (RETURN) to a caller only when Z2/Z9/Z7 say so;
        otherwise ends by jumping back into the game."""
        s, m = self.s, self.m
        while True:
            m.text()                                                 # 900
            s.AW = 0
            self.listing()
            if s.Z7 and s.AW < s.FM * 250 + 1:
                return
            while True:
                m.set_window(top=21)                                 # 920
                s.WT = 250 * s.FM
                s.W1 = (s.AW - s.WT) * (s.AW > s.WT)
                m.home()
                self.say('YOUR ', s.FM, ' MEN CAN CARRY ', s.WT, '.\rYOU HAVE ', s.AW, '. ', end='')
                if s.W1 < 1:
                    self.say('WILL YOU DUMP ANY (Y/N)?')             # 932
                    m.clear_strobe()                                 # 940
                    if self.getkey() != YES:
                        m.gr()
                        m.home()
                        if s.Z2 or s.Z9:
                            return
                        if s.Z1:
                            raise Goto(9010)
                        raise Goto(599)
                else:
                    self.say('YOU MUST DUMP ', s.W1, '.')            # 930
                self.say('WHICH ITEM WILL YOU DUMP', end='')         # 931
                s.BI = m.input_number()                              # 950
                if s.BI < 1 or s.BI > s.BN:
                    continue
                s.QT = m.input_number('HOW MANY WILL YOU DUMP')
                if s.QT > s.BQ[s.BI]:
                    self.say("YOU DON'T HAVE THAT MANY OF ITEM ", s.BI)
                    self.wait40()
                    continue
                if s.QT < 1:                                         # 953
                    continue
                self.drop()
                break

    def weight_check(self):
        """959: too heavy?  Then off to the inventory to dump something."""
        s = self.s
        s.WT = 250 * s.FM
        s.AW = 0
        s.BI = 1
        self.sum_weight()
        if s.AW > s.WT:
            s.Z9 = 1
            self.inventory_dialog()

    def sum_weight(self):
        """960: add up the weight from slot BI until the first empty slot."""
        s = self.s
        while s.BG[s.BI] != 0:
            s.AW = s.AW + GW[s.BG[s.BI]] * s.BQ[s.BI]
            s.BI += 1

    def listing(self):
        """970-998: the equipment inventory screen."""
        s, m = self.s, self.m
        m.home()
        self.inverse('          EQUIPMENT INVENTORY           ')
        self.inverse(' ITEM     NAME    QTY   WEIGHT    VALUE ')
        m.vtab(23)
        self.say('PRESS ANY KEY TO HALT LISTING.')
        m.set_window(top=2, bottom=22)
        m.home()
        s.BI = 1
        while s.BI <= s.BN:                                          # 985
            if s.BG[s.BI] != 0:                                      # 990
                if s.BI < 10:
                    self.say(' ', end='')
                self.say(' ', s.BI, '. ', end='')
                s.H = s.BG[s.BI]
                self.slot_name()
                self.say(s.B_S, end='')
                m.tab(19)                                            # 995
                self.say(s.BQ[s.BI], end='')
                m.tab(27)
                s.J = GW[s.H] * s.BQ[s.BI]
                self.say(s.J, end='')
                s.AW += s.J
                m.tab(36)
                self.say(AP[s.H] * s.BQ[s.BI])
            if m.peek_kbd() > 127:                                   # 996
                m.set_window(bottom=24)                              # 997
                m.clear_strobe()
                s.C = m.cv
                m.vtab(23)
                m.clreol()
                m.tab(11)
                self.say('CONTINUE LISTING?', end='')
                self.getkey()
                m.tab(1)
                m.clreol()
                if s.V == N_:
                    s.BI += 1
                    self.sum_weight()
                    return
                self.say('   PRESS ANY KEY TO HALT LISTING.')         # 998
                m.vtab(s.C + 1)
                m.set_window(bottom=22)
                m.tab(1)
            s.BI += 1
        m.set_window(top=0, bottom=24)

    # ----------------------------------------------------------------------------------
    # 1000-1930: encounters
    # ----------------------------------------------------------------------------------
    def encounter(self):
        s, m = self.s, self.m
        s.MT = 0
        m.home()
        self.say()
        s.EN = 1 + m.rnd(5)
        if s.EN == 1:
            return self.monsters()
        s.X0 -= 20
        s.SHAPE = 18
        self.xdraw()
        m.sound(20, None, 2)
        return {2: self.merchants, 3: self.wizard, 4: self.warriors, 5: self.warriors}[s.EN]()

    def monsters(self):
        """1200-1370: a band of monsters."""
        s, m = self.s, self.m
        s.MT = 1 + m.rnd(16 + 4 * (s.Z3 == 0))
        if not s.Z3:
            s.X = s.X0
            s.X0 -= 20
            if 9 < s.MT < 17:
                s.X0 -= 10
            s.SHAPE = 1
            if s.MT < 10:                                            # 1205
                s.SHAPE = 6
            if s.MT in (11, 12):
                s.SHAPE = 7
        s.A_S = substr(data.MN, s.MT * 12 - 11, s.MT * 12)           # 1210
        if s.MT > 16:
            self.birds()
        self.xdraw()
        if not m.rnd(2):
            self.say("YOU'VE BEEN ATTACKED BY ", s.A_S, '!')
            s.UT = 0
            return self.battle()                                    # 6000
        self.say('YOU CAN SEE SOME ', s.A_S, ' AHEAD.')             # 1300
        self.say("THEY HAVEN'T SEEN YOU YET.  DO YOU WANT TO ATTACK, LEAVE, OR OFFER SOMETHING?", end='')
        self.key99()
        s.UT = 1
        m.home()
        if s.V == 193:                                              # 1310
            return self.battle()
        if s.V != 207:
            if m.rnd(4):
                return 599
            self.wait40()
            self.say("YOU MADE SOME NOISE. THEY'RE ATTACKING!")
            s.UT = s.SR = 0
            return self.fight()
        self.say('\rDO YOU WANT TO OFFER GOLD OR FOOD?')              # 1320
        self.getkey()
        m.home()
        if s.V == 199 and s.I < 11 and s.AL < 0:
            s.I = idiv(s.CH, 2) + m.rnd(3)                          # 1350
            s.FM += s.I
            s.BQ[2] -= 50
            if s.BQ[2] < 0:
                s.BQ[2] = 0
            s.TOT += s.I
            self.say(s.I, ' OF THEM ACCEPTED YOUR OFFER.\rFINDING YOUR GROUP TO BE KINDRED SOULS, THEY WILL JOIN IN YOUR QUEST.')
            self.wait35()
            return 599
        if s.V == 199 and s.I < 11 and s.AL >= 0:                   # 1325
            self.say('THEY TOOK THE GOLD AND ARE ATTACKING\rANYWAY!')  # 1370
            s.UT = 0
            s.SR = 1
            s.BQ[2] -= 50
            if s.BQ[2] < 0:
                s.BQ[2] = 0
            return self.fight()
        if s.V == 199:
            self.say('THEY ARE TOO STUPID TO BE INTERESTED IN')
            self.say('TREASURE. THEY ARE ATTACKING.')
            s.SR = 1
            s.UT = 0
            return self.fight()
        if s.I < 11:                                                 # 1330
            self.say('THEY WERE ENRAGED BY YOUR INSULTING\rOFFER AND ARE ATTACKING!\r')
            s.UT = 0
            s.SR = 1
            return self.fight()
        self.say('THEY ATE THE FOOD AND WANDERED OFF.')
        s.BQ[1] -= 5
        if s.BQ[1] < 0:
            s.BQ[1] = 0
        self.wait35()
        return 599

    def merchants(self):
        """1400-1430"""
        s, m = self.s, self.m
        self.say('YOU HAVE ENCOUNTERED A SMALL CARAVAN OF MERCHANTS. WILL YOU IGNORE THEM, ATTACK THEM, '
                 'OR BUY SOMETHING FROM THEM?')
        s.A_S = 'MERCHANTS'
        self.key99()
        m.home()
        if s.V == 193:
            s.AL -= 5
            self.say('THE CARAVAN HAD SOME ARMED GUARDS.')
            s.UT = 1
            return self.battle()
        if s.V != 194:
            return 600
        return self.market()

    def wizard(self):
        """1600-1650"""
        s, m = self.s, self.m
        s.HA = 2 * m.rnd(2) - 1
        if s.HA > 0:
            s.A_S = ' WIZARD'
        if s.HA < 0:
            s.A_S = 'WARLOCK'
        self.say("YOU'VE COME UPON A WANDERING ", s.A_S, '.')
        self.say('HE IS ACCOMPANIED BY SEVERAL\rAPPRENTICES. WILL YOU ATTACK, REQUEST\rAID, OR LEAVE.', end='')
        self.key99()
        m.home()
        s.A_S = put(s.A_S, 8, 'S')                                  # 1620
        if s.V == 193:
            s.AL -= 3 * s.HA
            s.UT = 1
            s.SR = 0
            return self.fight()
        if s.V == 210:                                              # 1630
            if sgn(s.AL) and sgn(s.AL) != sgn(s.HA):
                return self.wizard_angry()
            m.home()
            self.wait40()
            s.QT = 1
            s.M = 39 + m.rnd(8)
            self.item_name()
            self.say('\rHE GAVE YOU A ', s.B_S, '.')                   # 1635
            s.C1 = s.M
            self.gain()
            self.wait40()
            return 600
        if sgn(s.AL) != sgn(s.HA) and m.rnd(2):                     # 1650
            return self.wizard_angry()
        return 600

    def wizard_angry(self):
        """1640"""
        s, m = self.s, self.m
        m.home()
        self.say("HE DOESN'T LIKE YOUR STYLE. HE'S\rCOMMANDING HIS MEN TO ATTACK.")
        s.UT = s.SR = 0
        self.wait40()
        self.say()
        return self.fight()

    def warriors(self):
        """1800-1930"""
        s, m = self.s, self.m
        s.A_S = 'WARRIORS'
        self.say("\rYOU'VE COME UPON A PARTY OF ", s.A_S, '.')
        while True:
            self.say('DO YOU WANT TO ATTACK, BE FRIENDLY,\rIGNORE THEM, OR WAIT CAUTIOUSLY?')  # 1815
            self.key99()                                             # 1820
            m.home()
            s.UT = s.SR = 1
            if s.V == 193:
                s.AL -= 3
                return self.fight()
            if s.V == 201:                                           # 1880
                if m.rnd(2):
                    return self.warriors_leave()
                s.UT = 0
                s.SR = 2
                return self.ambush()
            if s.V == 215:                                           # 1900
                self.wait40()
                r = m.rnd(3)
                if r == 0:
                    self.say('THEY ARE WAITING ALSO.')               # 1910
                    continue
                if r == 1:
                    return self.warriors_leave()                     # 1920
                s.UT = s.SR = 0                                      # 1930
                return self.ambush()
            break
        s.AL += 2                                                    # 1850
        self.say('\rTHEY APPEAR TO BE FRIENDLY.')
        self.wait40()
        if not m.rnd(3):
            s.UT = 0
            s.SR = 2
            return self.ambush()
        self.say('\rTHEY ARE WANDERING MERCENARIES AND WILL JOIN YOUR PARTY FOR A SHARE IN THE LOOT.', end='')
        s.QT = s.CH + m.rnd(8)                                       # 1865
        self.say('THERE ARE ', s.QT, ' OF THEM, ALL WITH SWORDS.', end='')
        s.FM += s.QT
        s.C1 = 22
        self.gain()
        s.TOT += s.QT
        self.xdraw()
        s.X0 = s.X
        s.SHAPE = 2
        return 700

    def ambush(self):
        """1855"""
        s, m = self.s, self.m
        self.say('THE FIENDS WAITED UNTIL THEY GOT CLOSE  AND THEN ATTACKED.')
        self.wait40()
        m.home()
        self.say('THEY ARE ', end='')
        if s.AL > -1:
            self.say('BANDITS!!!')
        if s.AL < 0:
            self.say('RANGERS!!!')
        return self.fight()

    def warriors_leave(self):
        self.say('\r     THEY HURRIEDLY LEFT THE AREA.')
        self.wait35()
        return 600

    # ----------------------------------------------------------------------------------
    # 1500-1598: buying from a caravan (Z3=0) or the city bazaar (Z3=2)
    # ----------------------------------------------------------------------------------
    def market(self):
        s, m = self.s, self.m
        if not (s.Z4 and s.Z3):
            for i in range(1, 14):
                s.MG[i] = 0
            s.MG[1] = 1
            s.QTA[1] = 5 + idiv(s.FM, 2) + m.rnd(30)
            s.CP[1] = 10 + m.rnd(5)
            s.I = 2
            if s.X0 == 63 and s.Y0 == 16:                            # the city sells a ship
                s.I = 3                                              # 1504
                s.MG[2] = 49
                s.QTA[2] = 1
                s.CP[2] = 2400 + m.rnd(300)
            for k in range(s.I, 14):                                 # 1506
                s.K = k
                s.M = m.rnd(36) - 5
                if s.M < 1:
                    continue
                if any(s.M == s.MG[j] for j in range(1, max(s.I - 1, 1) + 1)):
                    continue
                s.MG[s.I] = s.M
                s.QTA[s.I] = 5 + m.rnd(20)                           # 1510
                if s.MG[s.I] == 5:
                    s.QTA[s.I] = 1 + m.rnd(4)
                s.CP[s.I] = AP[s.MG[s.I]] + m.rnd(20)
                s.I += 1
            s.LAST = s.I - 1                                         # 1515
        return self.market_board()

    def market_board(self):
        """1520-1540: the price list."""
        s, m = self.s, self.m
        while True:
            s.Z9 = 0
            m.text()
            m.home()
            m.invflg = 0x3F
            for _ in range(19):
                self.say('                                       ')
            m.vtab(2)
            m.tab(11)
            if s.Z3 == 0:
                self.say('CARAVAN SALE ITEMS')
            if s.Z3:
                self.say('BAZAAR SALE ITEMS')
            self.say('\r  #    ITEM      PRICE  WEIGHT   QTY.\r')
            for i in range(1, s.LAST + 1):
                s.I = i
                m.tab(2)
                if i < 10:
                    self.say(' ', end='')
                self.say(i, '. ', end='')
                if s.MG[i] > 0:                                      # 1537
                    s.M = s.MG[i]
                    s.QT = s.QTA[i]
                    self.item_name()
                    self.say(s.B_S, end='')
                    m.tab(20)
                    self.say(s.CP[i], end='')
                    m.tab(27)
                    self.say(GW[s.MG[i]], end='')
                    m.tab(34)
                    self.say(s.QTA[i])
                else:
                    self.say()
            s.Z7 = 1
            self.weight_check()
            if not s.Z9:
                break
        return self.market_menu()

    def market_menu(self):
        """1543-1596"""
        s, m = self.s, self.m
        while True:
            s.Z7 = 1
            m.set_window(top=19)
            m.home()
            m.invflg = 0xFF
            self.say('YOU CAN CARRY ', s.WT - s.AW, ' MORE UNITS.')
            self.say('YOU HAVE ', s.BQ[2], ' QUADROONS TO SPEND.\rDO YOU WANT TO BUY, LEAVE, OR CHECK\rYOUR INVENTORY?')
            while True:                                              # 1552
                self.getkey()
                if s.V == 194:
                    break
                if s.V in (195, 201):
                    s.Z2 = 1                                         # 1596
                    self.inventory_dialog()
                    m.vtab(23)
                    m.clreol()
                    m.tab(8)
                    self.say('PRESS ANY KEY TO RETURN')
                    self.getkey()
                    return self.market_board()
                if s.V == 204:
                    self.weight_check()
                    if s.Z3:
                        return
                    return 600
            if self.haggle():
                continue

    def haggle(self):
        """1558-1590: pick an item and bargain for it."""
        s, m = self.s, self.m
        m.home()
        s.I = m.input_number("\rWHICH PRODUCT INTERESTS YOU M'LORD")
        if s.I < 1 or s.I > s.LAST or s.MG[s.I] == -1:
            return True
        s.M = s.MG[s.I]
        s.QT = 1
        self.item_name()
        while True:
            m.home()                                                 # 1561
            self.say('\rWHAT DO YOU OFFER FOR OUR FINE\r', s.B_S, 'S', end='')
            s.L = m.input_number()
            m.home()
            if s.L < 1:
                return True
            if s.L < s.CP[s.I] - 1:
                r = self.counter_offer()                             # 1573
                if r == 'again':
                    continue
                if r == 'done':
                    return True
            break
        return self.how_many()

    def counter_offer(self):
        """1573-1585"""
        s, m = self.s, self.m
        if s.L < s.Z7 or (s.L == s.Z7 and m.rnd(2)):
            self.say('\rYOU OFFERED ', s.Z7, " LAST TIME. LET'S JUST\rFORGET THE WHOLE THING.")   # 1574
            self.wait35()
            s.CP[s.I] = AP[s.MG[s.I]] + m.rnd(5)                    # 1575
            return 'done'
        s.Z7 = s.L
        s.M = s.CP[s.I]
        if not (s.L >= AP[s.I] or m.rnd(3)):
            self.announce('NOT INTERESTED.')
            self.wait40()
            s.CP[s.I] = AP[s.MG[s.I]] + m.rnd(5)
            return 'done'
        if s.L < idiv(AP[s.MG[s.I]], 2) and m.rnd(3):               # 1576
            self.say('\rYOUR OFFER IS AN INSULT! THAT ITEM IS NOLONGER FOR SALE.')   # 1582
            m.vtab(s.I + 5)
            m.invflg = 0x7F
            s.MG[s.I] = -1
            self.wait40()                                            # 1585
            for _ in range(39):
                self.say(' ', end='')
                m.pause(10)
            m.invflg = 0xFF
            return 'done'
        s.C = idiv(s.M - s.L, 3) + 1
        if s.M < AP[s.MG[s.I]] - 10:
            s.C = idiv(s.M - s.L, 5) + 1
        if s.C > idiv(s.M, 10):
            s.C = idiv(s.M, 10) + 1
        s.CP[s.I] = s.M - s.C
        r = m.rnd(4)
        cp = s.CP[s.I]
        if r == 0:
            self.say("\rYOU MUST BE JESTING, M'LORD. I COULDN'T CONSIDER SELLING FOR LESS THAN ", cp)
            self.say('WHAT DO YOU SAY?')
        elif r == 1:
            self.say('\rI PAID MORE FOR IT MYSELF SIRE. HOW     ABOUT MAKING IT ', cp, '?')
        elif r == 2:
            self.say("\rYOU LOOK LIKE A GOOD SORT SIR. I'LL TELLYOU WHAT. I'LL MAKE IT ", cp,
                     ' JUST FOR\rYOU. WHAT DO YOU SAY?')
        else:
            self.say('\rIT WOULD BE A STEAL AT ', cp, ' QUADROONS.\rI CAN AFFORD NO LESS. DO YOU WANT IT OR NOT?')
        self.getkey()                                                # 1581
        if s.V != YES:
            return 'again'
        s.L = s.CP[s.I]
        return 'agreed'

    def how_many(self):
        """1564-1590"""
        s, m = self.s, self.m
        m.home()
        self.say()
        while True:
            self.say('AT ', s.L, ' QUADROONS PER ', s.B_S, ',\rHOW MANY WOULD YOU LIKE', end='')   # 1565
            s.N = m.input_number()
            m.home()
            if s.N == 0:
                return True
            if s.N < 0:
                self.say("\rSORRY, WE'RE SELLING, NOT BUYING.")
                continue
            if s.N > s.QTA[s.I]:
                self.say('\rSORRY, WE ONLY HAVE ', s.QTA[s.I], ' ', s.B_S, 'S.')
                continue
            break
        if s.L * s.N >= s.BQ[2] + 1:
            self.not_enough_gold()
            return True
        self.sold()                                                  # 1588
        s.QTA[s.I] -= s.N
        m.vtab(5 + s.I)
        m.tab(33)
        self.say(' ', s.QTA[s.I], ' ', end='')
        if s.I == 1:
            s.Z6 = 0
        s.C1 = s.MG[s.I]                                             # 1589
        self.wait40()
        m.invflg = 0x3F
        m.tab(33)
        self.say(' ', s.QTA[s.I], ' ')
        m.invflg = 0xFF
        s.BQ[2] -= s.L * s.N
        s.QT = s.N
        if s.C1 != 5:
            self.gain()
        if s.C1 == 5:                                                # 1590: a contract hires men
            s.FM += s.N
        s.AW -= s.L * s.N
        s.CP[s.I] = AP[s.MG[s.I]] + m.rnd(5)                         # 1575
        return True

    def sold(self):
        """1594: the big SOLD banner."""
        m = self.m
        m.home()
        m.invflg = 0x7F
        for row in (' XXX XXX X   XXX  ', ' X   X X X   X  X ', ' XXX X X X   X  X ', '   X X X X   X  X '):
            m.tab(11)
            self.say(row)
        m.tab(11)
        self.say(' XXX XXX XXX XXX  ', end='')
        m.invflg = 0xFF

    def not_enough_gold(self):
        """1598"""
        self.m.invflg = 0x7F
        self.announce('NOT ENOUGH GOLD')
        self.m.invflg = 0xFF
        self.wait40()

    # ----------------------------------------------------------------------------------
    # 2000-2350: traps.  The trapped men can be saved with the right item (U1-U3).
    # ----------------------------------------------------------------------------------
    def trap(self):
        s = self.s
        s.TM = 2 + self.m.rnd(3) - idiv(s.DEX, 3)
        if s.TM < 2:
            s.TM = 2
        s.FM -= s.TM
        return self.trapped()

    def trapped(self):
        """2010"""
        s, m = self.s, self.m
        m.home()
        self.say()
        t = idiv(s.LC[s.PTR], 10000)
        if t == 0:
            s.U1, s.U2 = 4, 21
            self.say(s.TM, ' MEN WERE TRAPPED WHEN A ROTTEN TREE\rFELL ON THEM', end='')
        elif t == 1:
            if m.rnd(2):
                s.U1, s.U2, s.U3 = 43, 39, 42
                self.say(s.TM, ' MEN HAVE BEEN OVERCOME BY POISONOUS\rSWAMP GAS', end='')
            else:
                s.U1, s.U2, s.U3 = 7, 18, 19
                self.say(s.TM, ' MEN HAVE FALLEN INTO SOME\rQUICKSAND', end='')
        elif t == 2:
            if (s.U1 == 7 or m.rnd(2)) and s.U1 != 8:
                s.U1, s.U2, s.U3 = 7, 18, 19
                self.say(s.TM, ' MEN FELL INTO A CREVASSE. THEY MAY\rHAVE SURVIVED', end='')
            else:
                s.U1 = 8
                self.say(s.TM, ' MEN WERE CAUGHT IN AN AVALANCHE.\rTHEY ARE BURIED', end='')
        else:
            # Only after trying to walk on water (PTR is still the ocean cell): the
            # original jumps to a missing line 2400.  Treat it like 3400 - no trap.
            s.FM += s.TM
            s.TM = 0
            return 600
        self.say('. WHAT DO YOU WANT TO DO?', end='')               # 2120
        return 700

    # ----------------------------------------------------------------------------------
    # 3000-3400: obstacles.  The way is blocked until the right item is used.
    # ----------------------------------------------------------------------------------
    def obstacle(self):
        s = self.s
        while True:                                                  # 3000
            s.I = idiv(self.lc(idiv(s.X0 - 6 * s.DX, 14) * 20 + idiv(s.Y0 - 6 * s.DY, 8) + 1), 10000)
            if s.I != 3:
                break
            s.DX = 2 * self.m.rnd(2) - 1
            s.DY = 2 * self.m.rnd(2) - 1
        return self.blocked_again()

    def blocked_again(self):
        """3010: back up and describe what is in the way."""
        s, m = self.s, self.m
        self.xdraw()
        s.X0 = imod(s.X0 - 6 * s.DX + 279, 279)
        s.X = s.X0
        s.Y0 = imod(s.Y0 - 6 * s.DY + 191, 191)
        self.xdraw()
        m.home()
        self.say()
        s.I = idiv(s.LC[s.PTR], 10000)
        if s.I == 0:
            if m.rnd(2):
                self.say("YOU'VE COME TO A DEEP, NARROW RAVINE.")
                s.U1, s.U2 = 31, 7
            else:
                self.say("YOU'VE COME TO A DENSE THICKET, TOO\rTANGLED TO WALK THROUGH.")
                s.U1, s.U2, s.U3 = 4, 22, 21
        elif s.I == 1:
            self.say("YOU'VE COME TO AN AREA OF QUICKSAND AND DEEP BOGS. YOU CAN'T TELL WHERE THE\rSOLID LAND IS.")
            s.U1 = 3
        elif s.I == 2:
            if m.rnd(2):
                self.say("YOU'VE COME TO A DEEP CREVASSE.")
                s.U1 = 21
            else:
                self.say("YOU'VE COME TO A SHEER CLIFF.")
                s.U1 = 7
        elif s.I == 3:
            return 600                                               # 3400
        else:
            raise BasicError('no line %d' % (3100 + 100 * s.I))
        self.say('WHAT DO YOU WANT TO DO?', end='')                  # 3120
        if s.C1 != 99:
            s.LC[s.PTR] += 99
        return 700

    # ----------------------------------------------------------------------------------
    # 4000-4065: a monster's treasure chest.  4800: the spoils of a caravan.
    # ----------------------------------------------------------------------------------
    def chest(self):
        s, m = self.s, self.m
        m.home()
        self.wait40()
        if not m.rnd(5):
            self.say('SOME POISONOUS SPORES WERE RELEASED FROMTHE CHEST. YOUR PARTY WAS WEAKENED, BUT')
            self.say('NO ONE WAS KILLED.')                           # 4020
            self.wait30()
            s.STR -= 1
            if m.rnd(4) == 0:
                return self.chest_empty()
        if (m.rnd(5) and s.EN != 3) or m.rnd(2):                     # 4025
            return self.chest_gold()
        m.home()                                                     # 4030
        if m.rnd(4):
            return self.chest_gold()
        s.M = 39 + m.rnd(9)
        s.QT = 1
        self.item_name()
        self.say('\rTHE CHEST CONTAINED A ', s.B_S, '.')
        s.C1 = s.M
        self.gain()
        if m.rnd(3):
            s.QT = 700 + m.rnd(1000)                                 # 4050
            self.say('THERE IS ALSO ', s.QT, ' QUADROONS OF GOLD!')
            return self.chest_take_gold()
        self.sound70()
        return self.chest_empty()

    def chest_empty(self):
        self.say('THERE IS NOTHING ELSE IN THE CHEST.')              # 4040
        self.wait35()
        return 598

    def chest_gold(self):
        s = self.s
        s.QT = 500 + self.m.rnd(500)                                 # 4060
        self.say('THERE ARE ', s.QT, ' QUADROONS OF GOLD\rIN THE CHEST!')
        self.sound70()
        return self.chest_take_gold()

    def chest_take_gold(self):
        s = self.s
        s.C1 = 48                                                    # 4065
        self.gain()
        self.wait40()
        return 598

    def caravan_spoils(self):
        """4800-4850"""
        s, m = self.s, self.m
        m.text()
        m.home()
        self.say("\r\r\rCONGRATULATIONS, YOU KILLED ALL OF THE  MERCHANT'S MEN.")
        self.say("\r\rMUCH OF THE CARAVAN'S GOODS WERE RUINED.WHAT'S LEFT INCLUDES:\r\r")
        for i in range(1, 8):
            s.MG[i] = 0
        for i in range(1, 8):
            s.I = i
            while True:                                              # 4806
                s.C1 = m.rnd(30)
                if s.C1 != 5:
                    break
            for j in range(1, i + 1):
                if s.MG[j] == s.C1:
                    s.C1 = 0
            if m.rnd(4) == 0:
                s.C1 = 0
            s.MG[i] = s.C1
        for i in range(1, 8):                                        # 4808
            s.I = i
            if s.MG[i] == 0:
                continue
            s.QT = 3 + m.rnd(12)                                     # 4810
            s.C1 = s.MG[i]
            s.M = s.C1
            self.item_name()
            m.tab(5)
            self.say(s.QT, end='')
            m.tab(10)
            self.say(s.B_S)
            self.gain()
        self.wait30()
        return 598

    # ----------------------------------------------------------------------------------
    # 6000-6980: battle
    # ----------------------------------------------------------------------------------
    def battle(self):
        """6000: a fight where surprise is decided by chance."""
        self.s.SR = self.m.rnd(3)
        return self.fight()

    def fight(self):
        """6020"""
        s, m = self.s, self.m
        self.sound65()
        s.MN = s.FM + m.rnd(10) - 5                                  # 6050
        s.MK = s.CK = 0
        s.MW = 2 + m.rnd(4)
        s.MSP = 2 + m.rnd(6)
        s.ST = s.STR + idiv(s.EX, s.FM)
        s.MST = 3 + m.rnd(s.ST - 1)
        s.K = s.CW = 0                                               # 6060
        for i in range(1, s.BN + 1):
            s.I = i
            s.J = s.BG[i]
            if 20 < s.J < 27:
                s.CW += s.BQ[i] * (s.J - 20)
            if 26 < s.J < 31:
                s.CW += s.BQ[i] * (s.J - 26)
            if 20 < s.J < 31:
                s.K += s.BQ[i]
        if s.K == 0:                                                 # 6070
            s.K = 1
        s.CW = idiv(s.CW, s.K)
        self.say('THERE ARE ', s.MN, ' OF THEM. THEY HAVE')          # 6100
        if s.MST == 3:
            self.say('NO ARMOR OR WEAPONS TO SPEAK OF.')
        if s.MT > 9:
            if s.MST == 3:                                           # 6130
                self.say('LIGHT ARMOR AND WEAPONS.')
            if s.MST == 4:
                self.say('MODERATE ARMOR AND WEAPONS.')
            if s.MST == 5:                                           # 6132
                self.say('HEAVY SCALE ARMOR AND WEAPONS.')
            if s.MST > 5:
                self.say('MASSIVE ARMOR AND POWERFUL WEAPONS!')
        else:
            if s.MST == 4:                                           # 6110
                self.say('LEATHER ARMOR AND SHORT SWORDS.')
            if s.MST == 5:
                self.say('LIGHT ARMOR AND BROAD SWORDS.')
            if s.MST == 6:                                           # 6120
                self.say('CHAIN MAIL, SPEARS, AND AXES.')
            if s.MST > 6:                                            # 6125
                self.say('PLATE ARMOR, BROAD SWORDS, AND SPEARS.')
        if s.UT:                                                     # 6140
            self.say('THEY', end='')
        if s.UT == 0:
            self.say('YOU', end='')
        if s.SR == 0:                                                # 6150
            self.say(' WERE READY FOR THE ATTACK.', end='')
        if s.SR == 1:
            self.say(' WERE SURPRISED BY THE ATTACK.', end='')
        if s.SR == 2:                                                # 6160
            self.say(' WERE COMPLETELY UNPREPARED.', end='')
        self.getkey()                                                # 6200
        while True:
            if s.FM - s.CK < 1:                                      # 6210
                return self.wiped_out()
            if s.MN - s.MK < 1:
                return self.victory()
            m.home()                                                 # 6212
            self.inverse(' YOU ')
            m.invflg = 0x7F
            self.say('     WILL YOU RUN OR FIGHT ', end='')
            m.invflg = 0x3F
            self.say('   THEM ', end='')
            m.tab(7)                                                 # 6215
            self.say('      ORIGINAL  NUMBER       ')
            m.tab(7)
            self.say('         CASUALTIES          ')                         # 6220
            m.tab(7)
            self.say('       CURRENT NUMBER        ', end='')
            m.invflg = 0xFF
            m.vtab(22)
            m.tab(3)
            self.say(s.FM, end='')                                   # 6230
            m.tab(37)
            self.say(s.MN)
            m.tab(3)
            self.say(s.CK, end='')
            m.tab(37)
            self.say(s.MK)
            m.tab(3)
            self.say(s.FM - s.CK, end='')
            m.tab(37)
            self.say(s.MN - s.MK, end='')
            self.getkey()                                            # 6235
            if s.V == 210:
                r = self.run_away()
                if r is not None:
                    return r
            self.round()

    def round(self):
        """6240-6280: one round of fighting."""
        s, m = self.s, self.m
        m.home()
        m.invflg = 0x3F
        m.tab(9)
        self.say(' <- WEAPONS & ARMOR  -> ')
        m.tab(9)                                                     # 6245
        self.say(' EXPERIENCE & STRENGTH  ')
        m.tab(9)
        self.say('          LUCK          ')                                   # 6250
        m.tab(9)
        self.say('         TOTALS         ', end='')
        m.invflg = 0xFF
        m.vtab(21)
        m.tab(3)
        self.say(s.CW * (s.FM - s.CK), end='')                       # 6255
        m.tab(36)
        self.say(s.MW * (s.MN - s.MK))
        m.tab(3)                                                     # 6260
        self.say((s.FM - s.CK) * s.ST, end='')
        m.tab(36)
        self.say((s.MN - s.MK) * s.MST)
        while True:                                                  # 6270: spin the luck dice
            s.I = m.rnd(20)
            s.J = m.rnd(20)
            if s.SR and s.UT:
                s.J = 5
            if s.SR and s.UT == 0:
                s.I = 5
            m.tab(3)                                                 # 6272
            self.say(s.I, ' ', end='')
            m.tab(36)
            self.say(s.J, ' ', end='')
            m.statements(8)
            if m.peek_kbd() >= 127:
                break
        m.clear_strobe()
        self.say()
        m.tab(3)
        if s.SR:                                                     # 6275
            s.SR -= 1
        s.I = s.I + (s.FM - s.CK) * (s.CW + s.ST)
        s.J = s.J + (s.MN - s.MK) * (s.MW + s.MST)
        s.K = idiv(s.I - s.J, 3)
        if s.K > 3 and s.K > idiv(s.MN - s.MK, 2) and s.MN - s.MK > 2:
            s.K = idiv(s.MN - s.MK, 2)
        if s.I > s.J and s.K == 0:                                   # 6277
            s.K = 1
        if s.K > 0:
            s.MK += s.K
        if s.K > 0 and m.rnd(3) == 0:
            s.CK += 1
        if s.K < 0 and s.K > -4:
            s.K = -1
        if s.K < -3:
            s.K = -2
        if s.K < 0:
            s.CK -= s.K
        if s.K < 0 and m.rnd(2):                                     # 6280
            s.MK += 2
        if s.MK > s.MN:
            s.MK = s.MN
        if s.CK > s.FM:
            s.CK = s.FM
        self.say(s.I, end='')
        m.tab(36)
        self.say(s.J, end='')
        self.getkey()

    def run_away(self):
        """6800-6830.  Returns the next line, or None to keep fighting."""
        s, m = self.s, self.m
        m.home()
        self.say('\rYOUR SPEED IS ', s.SP, ' WHILE THEIRS IS ', s.MSP, '.')
        self.wait40()
        if s.SP > s.MSP:
            return self.got_away()
        if s.SP == s.MSP and m.rnd(2):                               # 6820
            return self.got_away()
        if not m.rnd(4):
            self.say("THEY DIDN'T CHASE YOU FOR SOME REASON.")
            return self.got_away()
        self.say("YOU DIDN'T GET AWAY.")                             # 6830
        self.wait40()
        return None

    def got_away(self):
        """6815"""
        s = self.s
        self.say('YOU GOT AWAY!')
        s.FM -= s.CK
        s.TEN += s.MK
        self.wait35()
        if s.Z3:
            return RETURN          # back to the search of a ruin (GOSUB 1200 at 9740)
        self.xdraw()
        s.X0 = s.X
        s.SHAPE = 2
        return 598

    def wiped_out(self):
        """6900"""
        self.s.FM = 0
        self.check_alive()

    def victory(self):
        """6950-6980"""
        s, m = self.s, self.m
        s.EX += 5
        s.TEN += s.MN
        m.home()
        if s.A_S == 'MERCHANTS':
            return self.caravan_spoils()
        self.say('CONGRATULATIONS! YOU KILLED ALL OF THE')
        self.say(s.A_S, '. ', end='')
        self.sound70()
        s.FM -= s.CK                                                 # 6955
        if not s.Z3:
            self.xdraw()
            s.X0 = s.X
            s.SHAPE = 2
            if m.rnd(2) == 0:
                self.say('IT LOOKS LIKE THEY HAD NO\rTREASURE.')       # 6980
                self.wait35()
                return 598
        self.say('IT LOOKS LIKE THEY HAVE A\rCHEST OF SOME SORT. WILL YOU OPEN IT OR LEAVE?', end='')   # 6960
        while True:
            self.key99()                                             # 6970
            if s.V == 207:
                return self.chest()
            if s.V == 204:
                return 598

    # ----------------------------------------------------------------------------------
    # 7000-7060: the ship.  8000-8180: using items.
    # ----------------------------------------------------------------------------------
    def use_ship(self):
        s, m = self.s, self.m
        if abs(s.X0 - 63) + abs(s.Y0 - 16) >= 20:
            self.say('YOU OWN THE SHIP, BUT IT IS DOCKED AT\rTHE CITY WHERE YOU BOUGHT IT. YOU MUST\rSET SAIL FROM THERE.')
            self.wait30()
            return 600
        if s.FM <= 14:                                               # 7030
            self.say("YOU DON'T HAVE ENOUGH MEN TO MAN SUCH A SHIP. IT REQUIRES AT LEAST 15.")
            self.wait35()
            return 600
        self.say("\rYOU'RE READY TO LEAVE THIS ISLAND (Y/N)?")         # 7050
        self.getkey()
        if s.V != YES:
            return 600
        s.X0, s.Y0 = 205, 117
        raise Chain('sea')

    def used_right_thing(self):
        """8000-8020"""
        s, m = self.s, self.m
        m.home()
        if s.TM:
            self.slot_name()
            s.I = m.rnd(s.TM) + 2
            if s.I > s.TM:
                s.I = s.TM
            s.FM += s.I
            self.say('\rCONGRATULATIONS!  YOU SAVED ', s.I, '\rMEN WITH YOUR ', s.B_S, '.')   # 8015
            if s.TM - s.I > 0:
                self.say('THE OTHER ', s.TM - s.I, ' DIED, HOWEVER.', end='')
            self.wait35()                                            # 8017
            s.TM = 0
            return 599
        if s.Z1:                                                     # 8020
            return self.L9700()
        s.LC[s.PTR] = 10000 * idiv(s.LC[s.PTR], 10000)
        self.say('\r     CONTINUE WITH YOUR JOURNEY.')
        return 700

    def use_magic(self, i):
        """8100-8180: amulet, scroll, magic lamp, scepter, potions, rug, wand, staff."""
        s, m = self.s, self.m
        if i == 39:                                                  # 8100 amulet
            self.say('THE AMULET HAS THE POWER TO HEAL WOUNDS AND RESTORE STRENGTH. IT CAN BE USED\rONLY ONCE. SHALL WE USE IT NOW (Y/N)?')
            self.getkey()
            if s.V == N_:
                return 600
            s.STR = s.Z20
            self.use_up(1)
            return 600
        if i == 40:                                                  # 8110 scroll
            self.say('THE SCROLL CONTAINS A SPELL WRITTEN IN\rANCIENT HIERGLYPHS.')
            self.wait40()
            if s.WS > 8:
                self.say('YOU TRANSLATED MOST OF IT....')            # 8119
                s.QT = 2000
            elif s.WS > 4:
                self.say('YOU DECIPHERED SOME OF IT....')            # 8115
                s.QT = 1000
            else:
                self.say("YOU CAN'T FIGURE OUT WHAT IT SAYS.")       # 8112
                return 700
            self.wait40()                                            # 8116
            m.switch(-16299)
            m.clicks([BASIC_STATEMENT + NEXT_TIME], idiv(s.QT, 10))     # J=PEEK(-16336): NEXT I
            m.switch(-16300)
            m.home()                                                 # 8117
            self.say('\rSOME ROCKS NEARBY WERE TRANSMUTED INTO\rGOLD. ', s.QT, ' QUADROONS WORTH!')
            s.BQ[2] += s.QT
            self.say('THE SCROLL DISAPPEARED, THOUGH.')              # 8118
            self.use_up(1)
            self.wait30()
            return 598
        if i in (41, 42, 47):                                        # 8120/8130/8180
            if s.WS + m.rnd(10) <= 8:
                self.wait40()
                self.say("\rIT BLEW UP!!! I DON'T THINK YOU KNOW    HOW TO USE IT CORRECTLY, SIRE.")
                self.use_up(1)
                return 700
            self.say('YOU MAY:  1)INCREASE SPEED')                    # 8131
            m.tab(11)
            self.say('2)INCREASE CHARISMA')
            m.tab(11)
            self.say('3)INCREASE WISDOM')
            m.tab(11)
            self.say('4)SAVE IT.     WHICH?', end='')                  # 8132
            self.getkey()
            if s.V < 177 or s.V > 179:
                return 600
            if s.V == 177:
                s.SP += 3
            if s.V == 178:
                s.CH += 3
            if s.V == 179:                                           # 8135
                s.WS += 3
            self.use_up(1)
            self.status()
            return 700
        if i in (43, 44):                                            # 8140/8150 potions
            self.wait40()
            if not m.rnd(2):
                self.say('\rIT WAS A STRENGTH POTION!')
                self.wait40()
                s.STR += 3
                self.use_up(1)
                self.status()
                return 700
            self.say("WHATEVER THE POTION WAS, IT'S GONE BAD. TWO MEN DIED AND SEVERAL OTHERS ARE\rSICK. WHAT NOW, SIR?")
            s.FM -= 2
            self.use_up(1)
            return 700
        if i == 45:                                                  # 8160 flying rug
            s.TF = 2
            s.A_S = '      FLY       '
            self.xdraw()
            s.SHAPE = 5
            return self.travel()
        if i == 46:                                                  # 8170 (no effect)
            return self.use_magic(47)
        return 700

    # ----------------------------------------------------------------------------------
    # 9000-9915: sites - temple, ruin, castle, tomb, hut and the city
    # ----------------------------------------------------------------------------------
    def at_site(self):
        """9000: we have walked onto a site (reached from inside locate())."""
        s = self.s
        self.xdraw()
        s.X0 = 14 * (idiv(s.PTR, 20) + 1) - 7
        s.Y0 = 8 * (imod(s.PTR, 20) - 1)
        s.SHAPE = s.C1 - 40
        raise Goto(9010)

    def L9010(self):
        s, m = self.s, self.m
        m.gr()
        m.home()
        self.say('YOU ARE AT THE ENTRANCE TO AN ANCIENT')
        s.Z1 = 1                                                     # 9020
        site = s.C1 - 50
        if site == 1:
            self.say('TEMPLE. YOUR WAY IS BARRED BY TWO\rMASSIVE BRONZE DOORS WITH A LARGE LOCK\rON THEM. WHAT WILL YOU DO?', end='')
            s.U1 = 2
            return 700
        if site == 2:
            self.say('RUIN. IT IS TOO DARK INSIDE TO ENTER\rSAFELY. WHAT WILL YOU DO?')
            s.U1, s.U2 = 11, 33
            return 700
        if site == 3:
            self.say('CASTLE. THE WAY IS BARRED BY A STOUT\rIRON DOOR WITH A SMALL LOCK ON IT. WHAT WILL YOU DO?',
                     end='')
            s.U1, s.U2 = 37, 2
            return 700
        if site == 4:
            self.say('TOMB. YOUR WAY IS BLOCKED BY A MASSIVE\rSTONE DOOR. THERE IS NO VISIBLE LOCK\rOR LATCH. WHAT WILL YOU DO?', end='')
            s.U1, s.U2 = 35, 8
            return 700
        if site == 5:
            return self.hut()
        if site == 6:
            return self.city()
        raise BasicError('no line %d' % (9000 + 100 * site))

    def hut(self):
        """9500-9570"""
        s, m = self.s, self.m
        self.say('AND DECREPIT HUT. DO YOU WISH TO ENTER\rOR LEAVE?')
        self.getkey()
        if s.V != E_:
            return self.L9915()
        s.I = 300 + m.rnd(300)
        r = m.rnd(3)
        if r == 0:
            self.say('THE HUT IS INHABITED BY AN OLD CRONE WHOCLAIMS TO BE A POWERFUL WITCH. SHE HAS  OFFERED TO SELL YOU A MAGIC LAMP')
            s.C1 = 11                                                # 9522
            if m.rnd(2):
                s.C1 = 41
        elif r == 1:
            self.say('A FILTHY HERMIT LIVES IN THE HUT. HE\rCLAIMS TO BE AN ORACLE. HE OFFERS TO\rSELL YOU A POWERFUL MAGIC POTION')
            s.C1 = 13                                                # 9532
            s.J = m.rnd(4)
            if s.J > 1:
                s.C1 = 41 + s.J
        else:
            self.say('A MONK LIVES IN THE HUT. HE CLAIMS TO\rHAVE A BOOK OR SCROLL CONTAINING ANCIENTAND MIGHTY SPELLS THAT HE WILL SELL YOU')
            s.C1 = 12                                                # 9542
            if m.rnd(2):
                s.C1 = 40
        self.say('FOR ', s.I, ' GOLD PIECES. INTERESTED (Y/N)?', end='')   # 9550
        self.getkey()
        if s.V != YES:
            return 9890
        while True:
            s.QT = 1                                                 # 9555
            if s.BQ[2] >= s.I:
                self.gain()
                s.BQ[2] -= s.I
                s.AW = s.AW - s.I + GW[s.C1]
                return 9890
            m.home()                                                 # 9560
            if s.BQ[2] < idiv(s.I, 2):
                self.say('YOU ONLY HAVE ', s.BQ[2], ' GOLD PIECES!\rI THINK YOU HAD BETTER LEAVE.')   # 9570
                self.wait35()
                return 9900
            self.say('YOU ONLY HAVE ', s.BQ[2], ' GOLD PIECES.')
            self.wait40()
            self.say('I GUESS THAT WILL DO.')
            s.I = s.BQ[2]

    def city(self):
        """9600-9610"""
        s = self.s
        s.Z3 = 2
        self.say('CITY. DO YOU WISH TO GO TO THE MARKET\rOR LEAVE?')
        self.getkey()
        if s.V == 204:
            return 9900
        r = self.market()
        if r is not None:
            return r
        s.Z4 = 6
        return 9900

    def L9700(self):
        """9700: the right key/tool opened the way in."""
        s, m = self.s, self.m
        s.Z3 = 1
        s.Z1 = 6
        m.home()
        self.say('    YOU GOT IN. IT LOOKS DESERTED.', end='')
        self.wait35()
        return 9710

    def L9710(self):
        """9710-9762: searching inside (Z1 counts the searches left)."""
        s, m = self.s, self.m
        while True:
            s.Z1 -= 1
            if s.Z1 < 0:
                return 9890
            self.say("\rYOU HAVEN'T FOUND ANYTHING.  DO YOU WANTTO SEARCH FURTHER OR LEAVE NOW?")   # 9715
            self.getkey()
            if s.V == 204 and m.rnd(3):
                return 9900
            if s.V == 204:
                return self.pit_trap()
            m.home()                                                 # 9720
            m.invflg = 0x3F
            self.say()
            m.tab(15)
            self.say('SEARCHING')
            m.invflg = 0xFF
            self.wait35()
            m.home()
            if m.rnd(2):
                continue
            r = m.rnd(4)
            if r == 0:                                               # 9730 altar
                self.say("YOU'VE COME INTO A ROOM WITH AN ALTAR\rIN IT. ON THE ALTAR IS A ", end='')
                s.M = 39 + m.rnd(9)
                s.QT = 1
                self.item_name()
                self.say(s.B_S, '.')
                self.say('DO YOU WANT TO GET IT OR LEAVE IT?')       # 9731
                self.key99()
                if s.V != 199:
                    continue
                s.C1 = s.M                                           # 9732
                s.QT = 1
                self.gain()
                m.home()
                self.say('\rOK, YOU GOT THE ', s.B_S)
                self.wait40()
                return 9890
            if r == 1:                                               # 9740 monsters
                r = self.monsters()
                return 9890 if r is RETURN else r
            if r == 2:                                               # 9750 chest
                while True:
                    self.say("\rYOU'VE \x07FOUND A LARGE WOODEN CHEST. DO\rYOU \x07WANT TO OPEN IT OR GO ON?")
                    self.getkey()
                    m.home()
                    if s.V == 199:
                        break
                    if s.V == 207:
                        break
                if s.V == 199:
                    continue
                if not m.rnd(4):                                     # 9752
                    if m.rnd(2):
                        self.say('A POISONED NEEDLE WAS EJECTED FROM THE  LOCK. THE MAN OPENING IT WAS KILLED.')
                        self.sound60()
                        s.FM -= 1
                    else:
                        self.say('WHEN IT WAS OPENED, THE CHEST RELEASED  A CLOUD OF POISONOUS VAPOR. NO ONE WAS')
                        self.say('KILLED, BUT YOU WERE ALL WEAKENED.')
                        self.sound60()
                        continue
                m.home()                                             # 9755
                s.QT = 500 + m.rnd(500)
                self.say('\rCONGRATULATIONS! THE CHEST CONTAINED')
                self.say(s.QT, ' GOLD QUADROONS.')
                self.sound70()
                s.C1 = 48                                            # 9756
                self.gain()
                return 9890
            return self.pit_trap()                                   # 9760

    def pit_trap(self):
        """9760"""
        s, m = self.s, self.m
        m.invflg = 0x7F
        self.announce('PIT TRAP!')
        m.invflg = 0xFF
        self.sound60()
        s.TM = 1 + m.rnd(3)
        m.home()
        self.say()
        s.FM -= s.TM
        self.check_alive()
        return self.L9761()

    def L9761(self):
        s, m = self.s, self.m
        self.say(s.TM, ' OF YOUR MEN FELL INTO THE PIT.\rWHAT DO YOU WANT TO DO?')
        self.getkey()
        m.home()
        if s.V == 213:
            s.U1, s.U2, s.U3 = 7, 19, 18                             # 9762
            return self.cmd_use()
        self.wait35()
        m.home()
        return 9710

    def L9890(self):
        s, m = self.s, self.m
        self.weight_check()
        m.home()
        self.say("\rIT LOOKS LIKE THERE IS NOTHING ELSE IN  HERE.  YOU'D BETTER LEAVE NOW.")
        self.wait35()
        return self.L9900()

    def L9900(self):
        """9900-9915: leave the site; a ruin etc. seals itself behind us."""
        s, m = self.s, self.m
        s.COLR = 85
        if s.Z3 <= 1:
            m.home()
            self.say('\rTHE ENTRANCE SEALED BEHIND YOU AS YOU\rLEFT.')
            self.wait40()
            s.COLR = 170                                             # 9905
            s.LC[s.PTR] += 100
        self.draw()                                                  # 9910
        return self.L9915()

    def L9915(self):
        s = self.s
        s.SHAPE = 2
        s.Y0 += 8
        s.X0 = s.X
        self.xdraw()
        s.Z3 = 0
        return 598
