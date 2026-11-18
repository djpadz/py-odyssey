"""SEA APVENTURE - sailing the Sargalo Sea.

Port of the Integer BASIC program "SEA APVENTURE".  Line numbers in the
comments refer to the original listing.

The ship moves one pixel at a time while the game waits for a key (GOSUB 100):
under sail in the direction the sails are set (Z2), otherwise drifting with the
current (speed Z6, direction Z4).  The sea chart LC() comes from the file LC2:
each cell is DDdss - depth in fathoms (LC/1000), current direction
((LC MOD 1000)/100) and current speed (LC MOD 100); 0 is land.  Running onto
land is detected by the DRAW collision count (PEEK(810)): the ship shape
always collides with itself 33 times, any more means land.

  Z1 anchor down     Z2 sail heading (-1 reefed)    Z3 wind from (-1 calm)
  Z5 have a sextant  Z9 have a compass              Z11 sails in shreds
  Z12 have a spare sail   Z8 have the High One's Orb   LEV scurvy / whirlpool
  PG what is going on: 1,2 ships coming  3 fog  4 pirates  5 rotten sails
     6 aground  7 at the temple  8 storm  9 near the edge  10 whirlpool
     11 flying monsters  12 Argorion  13 sea monster
  X2 set while a message is up: no events and no position read-outs.
"""
from . import data
from .apple import BasicError, BASIC_STATEMENT, NEXT_TIME, PEEK_TERM
from .part import Part, Goto, Chain, GameOver, idiv, imod, sgn, substr, put

GW, AP = data.ITEM_WEIGHT, data.ITEM_PRICE
YES = 217


class Sea(Part):
    abandon_line = 600
    menu_prefix = '    '

    def entries(self):
        return {
            10: self.L10, 120: self.L120, 580: self.L580, 581: self.L581, 590: self.L590,
            595: self.L595, 600: self.L600, 690: self.L690, 700: self.L700,
            1000: self.encounter, 1400: self.merchants, 2000: self.weather_event,
            2250: self.storm_loss, 2820: self.fog_clears, 3000: self.calamity,
            3620: self.tossed_free, 5100: self.over_the_edge, 31000: self.L31000,
            32000: self.L600,
        }

    def dr(self, d):
        return substr(data.DR, d * 2 + 1, d * 2 + 2)

    def lc(self, i):
        return self.s.LC[i] if 0 <= i <= 400 else 0

    # ----------------------------------------------------------------------------------
    # 10-12: arrival
    # ----------------------------------------------------------------------------------
    def L10(self):
        s, m = self.s, self.m
        m.hgr_load(self.game.asset('seamap.hgr'), 'seamap')
        if s.EN == 10:
            return 600
        s.LC = list(data.SEA_MAP)
        s.COLR = 127
        s.SHAPE = 17
        s.ROT = 0
        self.draw()
        s.Z3, s.Z4, s.Z1, s.Z2, s.LEV = 3, 0, 1, -1, 0
        s.Z9 = 0                                                     # 12
        if self.find_item(15):
            s.Z9 = 1                                                 # compass
        s.Z5 = 0
        if self.find_item(16):
            s.Z5 = 1                                                 # sextant
        s.Z6 = 2
        s.Z12 = 0
        if self.find_item(19):
            s.Z12 = 1                                                # spare sail
        return 600

    # ----------------------------------------------------------------------------------
    # Pauses and sounds
    # ----------------------------------------------------------------------------------
    def wait(self, d):
        """45: the Sea's pause always swallows the key that cut it short."""
        m = self.m
        m.pause(20)
        m.delay(d)
        m.clear_strobe()

    def wait30(self):
        self.wait(350)

    def sound77(self):
        """Lightning bolt."""
        for _ in range(10):
            for j in range(1, 11):
                self.m.sound(j, 10, 1)
            for j in range(10, 0, -1):
                self.m.sound(j, 10, 1)
        self.s.I, self.s.J = 11, 0

    def sound80(self):
        self.m.sound(30, None, 2)
        self.m.sound(40, None, 2)

    def cannon(self):
        """865 / 20051, one pass: C=PEEK(-16336)+...(5 times): A=PEEK(-16336)+PEEK(-16336): NEXT I"""
        p = PEEK_TERM
        self.m.clicks([p, p, p, p, BASIC_STATEMENT - p, p, NEXT_TIME + BASIC_STATEMENT - p])

    # ----------------------------------------------------------------------------------
    # 55: is anybody left?
    # ----------------------------------------------------------------------------------
    def check_alive(self):
        s, m = self.s, self.m
        if s.FM > 0:
            return
        self.wait40()
        m.home()
        self.say('I AM SORRY TO REPORT, MY LEIGE, THAT ALLTHE MEMBERS OF YOUR EXPEDITIONARY PARTY')
        self.say('WERE LOST. BETTER LUCK NEXT TIME, SIRE.', end='')
        self.xdraw()
        s.SHAPE = 4
        s.COLR = 127
        self.xdraw()
        self.key99()
        raise GameOver(died=True, dismissed=True)

    # ----------------------------------------------------------------------------------
    # 90-150: the ship under way (all of this runs inside GOSUB 100)
    # ----------------------------------------------------------------------------------
    def getkey(self):
        s, m = self.s, self.m
        while True:
            s.V = m.peek_kbd()
            if s.V >= 128:
                m.clear_strobe()
                return s.V
            if s.PG == 10:                                           # 102: whirlpool
                s.LEV += 1
                self.spin()
                if s.LEV > 300:
                    raise Goto(3620)
                m.statements(4)
                continue
            if s.Z1:                                                 # 103: at anchor
                m.statements(4)
                if m.rnd(10) == 0:
                    self.wind_shift()
                continue
            s.J = 1                                                  # 105
            if (s.Z2 == -1 or s.Z3 == -1 or (s.Z2 + 1) % 8 == s.Z3
                    or (s.Z3 + 1) % 8 == s.Z2 or s.Z3 == s.Z2):
                s.J = 0
            s.CT = imod(s.CT + 1, 3 + (25 - s.Z6) * (s.J == 0))      # 107
            m.statements(5)
            if (s.J == 0 and s.Z6 == 0) or s.CT:
                continue
            self.step()

    def step(self):
        """110-119: move the ship one pixel."""
        s, m = self.s, self.m
        s.COLR = 0
        if s.PG == 3:
            s.COLR = 127
        s.I = s.Z4
        if s.J:
            s.I = s.Z2
        s.X = s.X0 + (0 < s.I < 4) - (s.I > 4)
        s.Y = s.Y0 + (2 < s.I < 6) - (s.I in (1, 0, 7))
        self.draw()
        if not (s.Z5 == 0 or s.X2):                                  # 115
            m.vtab(21)
            m.tab(13)
            m.clreol()
            self.say(s.Y, ' AND LONGITUDE IS ', s.X, '.')
        s.COLR = 127                                                 # 116
        if s.PG == 3:
            s.COLR = 0
        s.X0, s.Y0 = s.X, s.Y
        self.draw()
        m.statements(12)
        if s.X in (16, 264) or s.Y in (16, 153):                     # 117
            self.edge_warning()
        if s.X < 8 or s.X > 272 or s.Y < 8 or s.Y > 157:             # 118
            raise Goto(5100)
        if s.COLLISION != 33:
            raise Goto(120)
        s.PTR = self.lc(idiv(s.X, 14) * 20 + idiv(s.Y, 8))           # 119
        self.underway()
        if not s.PTR:
            raise Goto(120)

    def underway(self):
        """90-96: random events, the current, scurvy and the wind."""
        s, m = self.s, self.m
        s.I = m.rnd(100)
        if not (s.I > 6 or s.PG or s.X2):
            if s.I > 2:
                s.I = 0
            raise Goto(1000 + s.I * 1000)
        s.Z6 = s.PTR % 100                                           # 92
        s.Z4 = idiv(s.PTR % 1000, 100)
        m.vtab(22 + s.Z5)
        m.tab(12)
        if s.X2 == 0:
            self.say(s.Z6, ' KNOTS TO THE ', self.dr(s.Z4), '. ')
        if s.Z11 and s.Z12 == 0 and m.rnd(7) == 0:                   # 93
            raise Goto(1400)
        if s.PG == 3 and m.rnd(20) == 0:
            raise Goto(2820)
        if s.PG == 8 and m.rnd(10) == 0:
            self.lightning()
        if s.PG == 8 and m.rnd(45) == 0:                             # 94
            raise Goto(2250)
        if s.LEV != 0:
            s.LEV += 1
            if not (s.LEV % 7 or s.X2):
                m.home()
                self.say('\rA MAN DIED OF \x07SCURVEY TODAY.')
                raise Goto(581)
        self.wind_shift()

    def wind_shift(self):
        """95: now and then the wind veers or backs, and the sails follow it."""
        s, m = self.s, self.m
        if m.rnd(30) or s.X2:
            return
        s.I = 2 * m.rnd(2) - 1
        s.Z3 = imod(s.Z3 + s.I + 8, 8)
        if (s.Z2 != -1 and (s.Z2 + 1) % 8 != s.Z3 and (s.Z3 + 1) % 8 != s.Z2
                and s.Z2 != s.Z3):
            s.Z2 = imod(s.Z2 + s.I + 8, 8)
        self.say('\x07')
        raise Goto(600)

    def L120(self):
        """120-135: aground."""
        s, m = self.s, self.m
        m.home()
        self.say("\r   YOU'VE RUN AGROUND IN THE SHALLOWS.")
        self.sound75()
        s.Z1 = 1
        if s.PG == 3:
            s.PG = 6
            return self.fog_clears(home=False)
        return self.fishermen()

    def fishermen(self):
        """135"""
        s = self.s
        if s.PG == 8:
            self.storm_over()
        self.say('SOME LOCAL FISHERMEN WILL HELP PULL YOU FREE IF YOU PAY THEM. WHAT WILL YOU DO?')
        s.PG = 6
        return 690

    def spin(self):
        """23000: the whirlpool turns the ship."""
        s = self.s
        s.COLR = 0
        self.draw()
        s.ROT = (s.ROT + 8) % 64
        s.COLR = 127
        self.draw()
        self.m.statements(8)                 # two rotated DRAWs take a while

    def lightning(self):
        """30000: a flash shows the chart for a moment."""
        m = self.m
        m.switch(-16297)
        p, st = PEEK_TERM, BASIC_STATEMENT          # C=PEEK+PEEK: C=PEEK: C=PEEK+PEEK+PEEK: NEXT I
        m.clicks([p, st, st, p, p, NEXT_TIME + st - p], 10)
        m.switch(-16298)

    def edge_warning(self):
        """5000-5010"""
        s, m = self.s, self.m
        if s.PG == 9:
            s.PG = 0
            return
        m.home()
        self.say("\r    \x07DANGER!    \x07DANGER!   \x07DANGER!\rWE'RE APPROACHING THE EDGE OF THE WORLD."
                 "WE MUST TURN BACK SIRE!", end='')
        s.PG = 9
        self.wait40()
        s.X2 = 1

    def over_the_edge(self):
        """5100-5120"""
        s, m = self.s, self.m
        m.home()
        self.say("\r       WE'RE GOING OVERRRR.....")
        self.sound80()
        s.COLR = 0
        self.draw()
        self.wait40()
        s.SHAPE = 9
        s.COLR = 127
        s.X0, s.Y0 = 150, 80
        self.draw()
        self.say('\rYOUR SHIP WAS LOST. IT HAS FALLEN INTO')
        self.say('LIMBO. PERHAPS NEXT TIME, YOU SHOULD\rBRING ALONG A GOOD NAVIGATOR. BETTER\rLUCK THEN.', end='')
        s.Z1 = 1
        s.X2 = 1
        self.getkey()
        m.text()
        m.home()
        m.vtab(10)
        raise GameOver(resume=(31000, 'RECOVER YOUR SHIP'))      # (was: TYPE 'GOTO 31000')

    def L31000(self):
        s = self.s
        s.COLR = 0
        self.draw()
        s.SHAPE = 17
        s.COLR = 127
        self.draw()
        s.Z1 = 1
        return 600

    # ----------------------------------------------------------------------------------
    # Inventory helpers that differ from the Island
    # ----------------------------------------------------------------------------------
    def _singular(self, qt):
        return qt == 1                                               # 548: IF QT=1

    def empty_slot(self):
        """560: the Sea closes the gap even for the food and gold slots."""
        self.close_gap()

    def choose_item(self, verb):
        self.s.X2 = 1                                                # 520
        return super().choose_item(verb)

    def birds(self):
        """570: flying monsters swoop down beside the ship."""
        s, m = self.s, self.m
        m.home()
        self.say('\r\x07TAKE COVER! A \x07BUNCH OF ', s.A_S, '\rARE \x07FLYING THIS \x07WAY!')
        s.X, s.Y = s.X0, s.Y0
        s.I = m.rnd(2)
        s.J = m.rnd(2)
        s.X0 = 270 * s.I
        s.Y0 = 160 * s.J
        s.SHAPE = 20
        self.xdraw()
        while abs(s.X0 - s.X + 20) + abs(s.Y0 - s.Y) >= 3:
            s.I = s.X0 - 2 * sgn(s.X0 - s.X + 20)
            s.J = s.Y0 - 2 * sgn(s.Y0 - s.Y)
            self.xdraw()
            s.X0, s.Y0 = s.I, s.J
            self.xdraw()
            m.statements(8)
        self.xdraw()
        s.X0, s.Y0 = s.X - 20, s.Y
        self.xdraw()

    # ----------------------------------------------------------------------------------
    # 580-640: the bridge report
    # ----------------------------------------------------------------------------------
    def L580(self):
        self.wait35()
        return self.L581()

    def L581(self):
        self.wait40()
        return 600

    def L590(self):
        self.wait30()
        return self.L595()

    def L595(self):
        """595: the other ships sail off."""
        s = self.s
        s.SHAPE = 21
        s.X0 = s.ST
        s.Z1 = 1
        s.PG = 0
        s.COLR = 0
        self.draw()
        s.X0 += 2
        self.draw()
        s.SHAPE = 17
        s.X0 = s.X
        return 600

    def L600(self):
        s, m = self.s, self.m
        if s.PG != 8:
            m.switch(-16304)
            m.switch(-16301)
            m.switch(-16297)
        m.set_window(top=20)                                         # 602
        s.U1 = s.U2 = s.U3 = 0
        s.TM = s.X2 = s.EN = s.Z7 = 0
        s.PTR = self.lc(idiv(s.X0, 14) * 20 + idiv(s.Y0, 8) - 1)     # 605
        m.home()                                                     # 610
        if s.Z5:
            self.say('LATITUDE IS ', s.Y0, ' AND LONGITUDE IS ', s.X0, '.')
        if s.Z3 > -1:                                                # 615
            self.say('THE WIND IS OUT OF THE ', self.dr(s.Z3), '.')
        if s.Z3 == -1:
            self.say('THERE IS NO WIND AT ALL.')
        self.say('CURRENT IS ', s.Z6, ' KNOTS TO THE ', self.dr(s.Z4), '.')   # 620
        self.say('ANCHOR IS ', end='')
        if s.Z1:
            self.say('DOWN', end='')
        if s.Z1 == 0:                                                # 630
            self.say('UP', end='')
        self.say('. SAILS ', end='')
        if s.Z2 > -1:
            self.say('SET FOR ', self.dr(s.Z2), '.', end='')          # 640
        else:
            self.say('REEFED.', end='')
        return 700

    def L690(self):
        self.s.X2 = 1
        return self.L700()

    def L700(self):
        s, m = self.s, self.m
        self.check_alive()
        v = self.getkey()
        s.X2 = 1
        table = {215: 600, 208: self.cmd_put, 213: self.cmd_use, 199: self.cmd_get,
                 209: self.cmd_quit, 195: self.cmd_status, 193: self.cmd_anchor,
                 211: self.cmd_sails, 196: self.cmd_divers, 204: self.cmd_land,
                 198: self.cmd_fire, 210: self.cmd_reef, 207: self.cmd_offer,
                 200: self.cmd_hail, 201: self.cmd_inventory}
        action = table.get(v)
        if action is None:                                           # 710
            m.home()
            self.inverse(' COMMANDS ARE: ')
            self.say(' WATCH, USE, PUT, GET,\rCONDITION, ANCHOR, SET SAILS, REEF\rSAILS, FIRE CANNON, LAND, DIVERS,')
            self.say('HAIL, OFFER, INVENTORY AND QUIT.', end='')
            return 690
        return action if isinstance(action, int) else action()

    # ----------------------------------------------------------------------------------
    # Commands
    # ----------------------------------------------------------------------------------
    def cmd_use(self, verb='  USE'):
        """760-765"""
        s, m = self.s, self.m
        self.choose_item(verb)
        s.I = s.BG[s.BI]
        if s.I in (s.U1, s.U2, s.U3):
            return self.used_right_thing()                           # 8000
        if not (s.Z11 == 0 or s.I != 19):                            # a spare sail
            s.Z11 = 0
            self.use_up(1)
            return 600
        i = s.I
        if s.LEV and i == 14:                                        # 762
            return self.fruit()
        if s.PG == 6 and i == 48:
            return self.pay_fishermen()
        if s.PG == 11 and i in (41, 42, 46, 47):
            return self.blast_flyers()
        if s.PG == 10 and i in (40, 39, 46):                         # 763
            m.home()
            self.say('THAT SEEMS TO HAVE DONE IT, SIR. THE\rWATERS ARE CALMING AND WE ARE FREE. WHATNOW?')
            return self.whirlpool_over()
        if s.PG == 13 and i in (39, 42, 46, 1):
            return self.monster_leaves()
        self.slot_name()                                             # 765
        m.home()
        self.say('\rUSING YOUR ', s.B_S, ' SERVED NO USEFUL\rPURPOSE. NOW WHAT?')
        return 690

    def cmd_offer(self):
        """767"""
        s = self.s
        if s.PG in (12, 4):
            return self.cmd_put('OFFER')
        return self.cmd_use('OFFER')

    def cmd_put(self, verb='  PUT'):
        """770-778: put something over the side."""
        s, m = self.s, self.m
        self.choose_item(verb)
        self.slot_name()
        m.home()
        self.say('\r    PUT YOUR ', s.B_S, ' OVER (Y/N)?')
        if self.getkey() != YES:
            return 600
        while True:
            m.home()                                                 # 775
            self.say('\rYOU HAVE ', s.BQ[s.BI], ' OF THEM.')
            self.say('TOTAL WEIGHT IS ', s.BQ[s.BI] * GW[s.BG[s.BI]],
                     ' AND VALUE IS ', s.BQ[s.BI] * AP[s.BG[s.BI]])
            s.QT = m.input_number('HOW MANY WILL YOU DROP')
            if s.QT < 1:                                             # 778
                return 600
            if s.QT <= s.BQ[s.BI]:
                break
        s.AW = s.AW - s.QT * GW[s.BG[s.BI]]
        if s.PG == 4 and s.BI == 2:
            return self.pay_pirates()
        self.use_up(s.QT)
        if s.PG == 12:
            return self.argorion_helps()
        if s.PG == 13 and s.BI == 1:
            return self.monster_leaves()
        return 600

    def cmd_get(self):
        """780"""
        self.m.home()
        self.say('\rOK, YOU GOT A FISTFUL OF SEAWEED. NOW   WHAT?')
        return 690

    def cmd_quit(self):
        """790-797"""
        self.s.X2 = 1
        self.quit_game(2)
        return 600

    def cmd_status(self):
        """800-812"""
        s, m = self.s, self.m
        m.home()
        self.inverse('             STATUS REPORT              ')
        self.say('# IN PARTY=', s.FM, end='')
        m.tab(16)
        self.say('STRENGTH=', s.STR, end='')
        m.tab(29)
        self.say('CHARISMA=', s.CH, '\rEXPER.=', s.EX, end='')
        m.tab(16)
        self.say('WISDOM=', s.WS, end='')
        m.tab(29)
        self.say('SPEED=', s.SP, '\rDEXTERITY=', s.DEX, end='')
        m.tab(16)
        self.say('GOLD=', s.BQ[2], end='')
        m.tab(29)
        self.say('ALIGN.=', s.AL, end='')
        return 700

    def cmd_anchor(self):
        """820-826 (also 'attack' when something is alongside)"""
        s, m = self.s, self.m
        m.home()
        if s.PG == 13:
            return self.monster_frightened()
        if s.PG == 11:
            return self.flyers_attack()
        if s.PG in (1, 2):
            return self.ships_pass()
        if s.PG == 12:
            return self.L6020()
        if s.PG == 4:                                                # 822
            return self.pirates()
        if s.PG == 6:
            self.say("\rTHAT'S NOT YOUR ANCHOR ON THE BOTTOM,\rITS YOUR SHIP.")   # 150
            s.X2 = 1
            return 581
        s.I = idiv(s.PTR, 1000)
        if s.I > 20 and s.Z1 == 0 and (s.X0 != s.SR or s.Y0 != s.UT):
            self.say('\rSOUNDINGS INDICATE DEPTH IS ', s.I, ' FATHOMS')   # 825
            self.say('AND THE ANCHOR ONLY REACHES 20.')
            return 580
        s.Z1 = int(not s.Z1)
        return 600

    def cmd_sails(self):
        """828-839"""
        s, m = self.s, self.m
        m.home()
        if s.Z3 == -1:
            self.say('\r      THERE IS STILL NO WIND SIR.')
            return 581
        if s.Z11:                                                    # 829
            self.say("\rTHE SAILS ARE IN SHREDS, SIR. THEY WON'TCATCH THE WIND.")
            return 580
        m.home()                                                     # 830
        self.inverse('   WHICH DIRECTION?   (WIND FROM ', self.dr(s.Z3), ')   ')
        m.tab(15)
        self.say('NW  NO  NE')
        m.tab(16)
        self.say('W  --  E')                                         # 831
        m.tab(15)
        self.say('SW  SO  SE', end='')
        s.X2 = 1
        self.getkey()
        if s.V in (141, 160):
            return 600
        s.J = -1
        if s.V == 197:
            s.J = 2
        if s.V == 215:
            s.J = 6
        if not s.J > 0:
            s.C = s.V                                                # 832
            self.getkey()
            if s.V == 207:
                s.J = 4 * (s.C == 211)                               # 834
            else:
                if s.C == 206 and s.V == 197:
                    s.J = 1
                if s.C == 206 and s.V == 215:
                    s.J = 7
                if s.C == 211 and s.V == 197:
                    s.J = 3
                if s.C == 211 and s.V == 215:
                    s.J = 5
        if (s.Z3 + 1) % 8 == s.J or (s.Z3 + 7) % 8 == s.J or s.Z3 == s.J:   # 835
            m.home()                                                 # 838
            self.say()
            m.tab(7)
            self.say('THE WIND IS OUT OF THE ', self.dr(s.Z3), '.')
            m.tab(7)
            self.say('YOU CANNOT SAIL TO THE ', self.dr(s.J), '.')   # 839
            self.wait40()
            return 600
        s.Z2 = s.J
        if s.Z9 == 0 and m.rnd(3):                                   # no compass
            s.Z2 = m.rnd(8)
        return 600

    def cmd_divers(self):
        """840-845"""
        s, m = self.s, self.m
        m.home()
        if abs(s.X0 - s.UT) + abs(s.Y0 - s.SR) < 4:
            m.home()                                                 # 845
            self.wait40()
            self.say("\rTHE DIVERS HAVE RECOVERED A JEWEL\rENCRUSTED ORB, CAP'N. WHAT SHALL\rWE DO NOW?")
            s.SR = s.UT = -1
            s.Z8 = 1
            return 690
        if m.rnd(2):
            self.say("\r\x07SHARKS\x07!!! ONE MAN WAS \x07KILLED BUT I GOT\rTHE OTHERS OUT SAFELY SIR. I DON'T "
                     "THINKWE SHOULD DIVE HERE.")                    # 843
            s.FM -= 1
            return 690
        self.say('\rTHE MEN REALLY ENJOYED THE SWIM SIR.\rWHAT SHALL WE DO NOW?')
        return 581

    def cmd_land(self):
        """850-852"""
        s, m = self.s, self.m
        m.home()
        for x in range(s.X0 - 15, s.X0 + 36, 5):
            s.X = x
            for y in range(s.Y0 - 20, s.Y0 + 21, 5):
                s.Y = y
                if self.lc(idiv(x, 14) * 20 + idiv(y, 8) - 1) == 0:
                    return self.go_ashore()                          # 20900
        self.say("'BEG PARDON SIR, BUT WHAT SHALL WE LAND\rON? THE NEAREST LAND IS STILL SOME\rLEAGUES AWAY.")
        return 580

    def cmd_fire(self):
        """860-868"""
        s, m = self.s, self.m
        if s.PG in (1, 2, 4):
            return self.sea_battle()
        for _ in range(2):
            for _ in range(15):
                self.cannon()
            m.pause(60)
        m.home()
        if s.PG == 11:
            if m.rnd(2):
                return self.flyers_attack()
            self.say("\rTHEY WERE STARTLED CAP'N AND FLEW AWAY. WHAT NOW?")   # 1230
            return self.flyers_gone()
        if s.PG == 12:
            return self.argorion_annoyed()
        if s.PG in (13, 14):
            return self.monster_frightened()
        self.say('\rTHE NATIVE FISHERMEN WERE VERY IMPRESSEDSIR. WHAT NOW?')
        return 690

    def cmd_reef(self):
        self.s.Z2 = -1
        return 600

    def cmd_hail(self):
        """880-886"""
        s, m = self.s, self.m
        m.home()
        if s.PG not in (1, 2, 4):
            self.say("\rEXCUSE ME, SIR. EXACTLY WHO WERE YOU\rCALLING TO? THERE'S NO ONE HERE BUT US.")
            return 580
        self.announce('FRIENDLY OR CHALLENGE?')
        s.X2 = 1
        self.getkey()
        if s.V == 195:
            s.AL -= 2
            if m.rnd(3) == 0:
                return self.pirates()
            if m.rnd(2):
                self.say('\rTHEY WERE MERCENARIES BUT WERE ANNOYED\rBY OUR UNFRIENDLY ATTITUDE.')   # 883
                return 590
            self.say('\rTHEY WERE PIRATES, BUT WERE FRIGHTENED  OFF BY OUR ALERT AND AGGRESSIVE ATTITUDE.')
            return 590
        if m.rnd(2):                                                 # 885
            return self.pirates()
        s.I = s.CH + m.rnd(10)
        self.say('\rTHEY ARE MERCENARIES. ', s.I, ' OF THEM WISH\rTO JOIN YOUR FORCE, SIR. THEY ARE ALL\rARMED.')
        s.FM += s.I                                                  # 886
        s.QT = s.I
        s.C1 = 22
        self.gain()
        return 590

    # ----------------------------------------------------------------------------------
    # 900-999: the inventory
    # ----------------------------------------------------------------------------------
    def cmd_inventory(self):
        self.inventory()
        return 600

    def inventory(self):
        """900-956.  Returns (to a GOSUB 900 caller) only when Z7 is set."""
        s, m = self.s, self.m
        while True:
            m.text()
            s.AW = 0
            self.listing()
            if s.Z7:
                return
            m.set_window(top=21)                                     # 920
            while True:
                m.home()                                             # 930
                s.WT = s.FM * 250
                self.say('ON LAND, YOU CAN CARRY ', s.WT, ' UNITS. YOU')
                self.say('CURRENTLY HAVE ', s.AW, '. DUMP ANY (Y/N)?')
                m.clear_strobe()                                     # 940
                self.getkey()
                if s.V != YES:
                    if s.PG in (8, 3):
                        m.gr()
                    raise Goto(600)
                m.home()                                             # 950
                self.say()
                m.tab(10)
                s.BI = m.input_number('WHICH ONE')
                if s.BI < 1 or s.BI > s.BN:
                    continue
                m.tab(10)
                s.I = m.input_number('HOW MANY')
                if s.I <= s.BQ[s.BI]:
                    break
                self.say("YOU DON'T HAVE THAT MANY OF ITEM ", s.BI)
                self.wait40()          # the original says GOSUB 140, a line the Sea doesn't have
            self.use_up()                                            # 956
            s.AW = s.AW - s.I * GW[s.BG[s.BI]]

    def sum_weight(self):
        """960"""
        s = self.s
        self.m.set_window(bottom=24)
        while s.BG[s.BI] != 0:
            s.AW = s.AW + GW[s.BG[s.BI]] * s.BQ[s.BI]
            s.BI += 1

    def listing(self):
        """970-999"""
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
            if s.BG[s.BI] != 0:                                      # 990
                if s.BI < 10:
                    self.say(' ', end='')
                self.say(' ', s.BI, '.  ', end='')
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
                self.say('CONTINUE LISTING?', end='')
                self.getkey()
                m.tab(1)
                m.clreop()
                if s.V == 206:
                    s.BI += 1                                        # 998
                    self.sum_weight()
                    return
                self.say('PRESS ANY KEY TO HALT LISTING.')           # 999
                m.vtab(s.C + 1)
                m.set_window(bottom=22)
            s.BI += 1
        m.set_window(top=0, bottom=24)

    # ----------------------------------------------------------------------------------
    # 1000-1395: things met at sea
    # ----------------------------------------------------------------------------------
    def encounter(self):
        """1000"""
        s, m = self.s, self.m
        s.Z1 = 1
        s.X2 = 1
        m.home()
        s.EN = m.rnd(4)
        return [self.creature, self.merchants, self.raft, self.ships][s.EN]()

    def creature(self):
        """1200"""
        return [self.flyers, self.octopus, self.serpent, self.argorion][self.m.rnd(4)]()

    def flyers(self):
        """1210-1215"""
        s, m = self.s, self.m
        s.Z1 = 1
        s.PG = 11
        s.MT = 17 + m.rnd(4)
        s.I = s.MT * 12 - 11
        s.A_S = substr(data.MN, s.I, s.I + 11)
        self.birds()
        self.wait40()
        m.home()
        self.say('\rTHEY ARE JUST HOVERING THERE, SIR. WHAT SHALL WE DO?')
        return 690

    def flyers_gone(self):
        """1235"""
        s = self.s
        self.xdraw()
        s.PG = 0
        s.SHAPE = 17
        s.X0 = s.X
        return 690

    def flyers_attack(self):
        """1240"""
        s = self.s
        self.say('\rTHEY WERE STARTLED AND ATTACKED THE\rSHIP. THE SAILS ARE SHREDDED. WHAT NOW?')
        s.U1 = 19
        s.Z2 = -1
        s.Z11 = 1
        return self.flyers_gone()

    def blast_flyers(self):
        """1250-1255"""
        s, m = self.s, self.m
        s.M = s.I
        s.QT = 1
        self.item_name()
        m.home()
        self.say('THAT SEEMS TO HAVE TAKEN CARE OF THEM,\rSIR. THEY WERE BLASTED INTO ASHES!')
        self.wait40()
        self.say('UNFORTUNATELY, THE ', s.B_S, ' WAS TOO.\rWHAT NOW, SIR?')
        self.use_up(1)
        return self.flyers_gone()

    def octopus(self):
        """1260-1267"""
        self.say("\rIT'S \x07A GIANT OCTOPU\x07S, CAP'N. WHAT SHA\x07LL WE DO?")
        self.place_beside()
        self.s.SHAPE = 10
        return self.monster_appears()

    def serpent(self):
        """1310"""
        self.say("\rIT'S A SEA SERPENT, CAP'N. WHAT SHALL WEDO?")
        self.place_beside()
        self.s.SHAPE = 8
        return self.monster_appears()

    def monster_appears(self):
        """1267"""
        s = self.s
        s.X0 = s.ST
        s.COLR = 127
        self.draw()
        s.Z1 = 1
        s.PG = 13
        self.wait40()
        return 690

    def monster_frightened(self):
        """1270"""
        s, m = self.s, self.m
        s.PG = 0
        s.FM -= 2
        m.home()
        self.say('\rHE WAS FRIGHTENED AWAY, SIR, BUT HE TOOKTWO MEN WITH HIM.')
        return self.L6010()

    def monster_leaves(self):
        """1280"""
        s = self.s
        s.PG = 0
        if s.I == 1:
            s.BQ[s.I] -= (s.BQ[s.I] > 0)
        self.announce('HE LEFT, SIR!')
        return self.L6010()

    def argorion(self):
        """1360-1370"""
        s = self.s
        if s.Z8:
            return 600
        s.PG = 12
        self.place_beside()
        s.X0 = s.ST
        s.SHAPE = 9
        s.COLR = 127
        self.draw()
        s.Z1 = 1
        self.say("\rIT'S ARGORION, SIR. MAYBE WE CAN GET HIMTO HELP US. WHAT SHALL WE DO?")
        return 690

    def argorion_helps(self):
        """1380-1385: whatever you give him, he tells you where the orb lies."""
        s, m = self.s, self.m
        s.UT = 100 + m.rnd(100)
        s.SR = 50 + m.rnd(50)
        m.home()
        self.say('\rA RARE TREASURE CAN BE FOUND ON THE SEA FLOOR AT LATITUDE ', s.SR, ' AND LONGITUDE ', s.UT, '.')
        self.wait40()
        s.PG = 0
        return self.L6010()

    def argorion_annoyed(self):
        """1390-1395"""
        s, m = self.s, self.m
        self.wait40()
        s.COLR = 0
        self.draw()
        s.SHAPE = 17
        s.X0 = s.X
        m.home()
        self.say('I THINK HE WAS RATHER ANNOYED, SIR. WE  HAD BETTER BE CAREFUL FROM NOW ON. WHAT NOW?')
        s.PG = 0
        return 690

    def merchants(self):
        """1400-1410"""
        s = self.s
        self.say("\x07YOU'VE COME UPON SOME MERCHANTMEN. THEY ARE \x07LIGHTLY ARMED. DO YOU WISH TO BUY\r"
                 "\x07SOMETHING, IGNORE THEM, OR ATTACK?")
        s.Z1 = 1
        self.place_beside()
        s.X0 = s.ST
        s.COLR = 213
        self.draw()
        self.key99()
        if s.V == 194:
            return self.market()
        if s.V != 193:
            return 595
        s.AL -= 5
        return self.sea_battle()

    # ----------------------------------------------------------------------------------
    # 1500-1598: buying from the merchantmen
    # ----------------------------------------------------------------------------------
    def market(self):
        s, m = self.s, self.m
        for i in range(1, 14):
            s.MG[i] = 0
        s.MG[1] = 1
        s.QTA[1] = 15 + m.rnd(30)
        s.CP[1] = 10 + m.rnd(5)
        s.I = 2
        for k in range(2, 14):                                       # 1506
            s.K = k
            s.M = m.rnd(36) - 5
            if s.M < 1 or s.M == 5:
                continue
            if any(s.M == s.MG[j] for j in range(1, s.I)):
                continue
            s.MG[s.I] = s.M
            s.QTA[s.I] = 5 + m.rnd(20)                               # 1510
            s.CP[s.I] = AP[s.MG[s.I]] + m.rnd(20)
            s.I += 1
        s.LAST = s.I - 1
        while True:
            self.market_board()
            r = self.market_menu()
            if r != 'board':
                return r

    def market_board(self):
        """1520-1540"""
        s, m = self.s, self.m
        m.text()
        m.home()
        m.invflg = 0x3F
        for _ in range(19):
            self.say('                                       ')
        m.vtab(2)
        m.tab(8)
        self.say('MERCHANT SHIP SALE ITEMS')
        self.say('\r  #    ITEM      PRICE  WEIGHT   QTY.\r')
        for i in range(1, s.LAST + 1):
            s.I = i
            m.tab(2)
            if i < 10:
                self.say(' ', end='')
            self.say(i, '. ', end='')
            if s.MG[i] > 0:
                s.H = s.MG[i]                                        # 1537
                s.QT = s.QTA[i]
                self.item_name(s.H)                                  # 1570
                self.say(s.B_S, end='')
                m.tab(20)
                self.say(s.CP[i], end='')
                m.tab(27)
                self.say(GW[s.MG[i]], end='')
                m.tab(34)
                self.say(s.QTA[i])
            else:
                self.say()

    def market_menu(self):
        """1543-1598.  Returns 'board' to redraw the price list, else the next line."""
        s, m = self.s, self.m
        while True:
            s.Z7 = 0                                                 # 1543
            m.set_window(top=19)
            m.home()
            s.WT = s.FM * 200
            m.invflg = 0xFF
            self.say('YOU CAN CARRY ', s.WT - s.AW, ' MORE UNITS ON LAND.')
            self.say('YOU HAVE ', s.BQ[2], ' QUADROONS TO SPEND.')
            self.say('DO YOU WANT TO BUY, LEAVE, OR CHECK     YOUR INVENTORY?')
            while True:                                              # 1552
                self.getkey()
                if s.V == 194:
                    break
                if s.V in (195, 201):
                    s.Z7 = 1                                         # 1596
                    self.inventory()
                    m.vtab(23)
                    m.clreol()
                    m.tab(8)
                    self.say('PRESS ANY KEY TO RETURN')
                    self.getkey()
                    return 'board'
                if s.V == 204:
                    return 595
            while True:
                m.home()                                             # 1558
                self.say("\rWHICH OF OUR FINE GOODS DO YOU WISH TO  PURCHASE, SIRE", end='')
                s.I = m.input_number()
                if 1 <= s.I <= s.LAST and s.MG[s.I] != -1:
                    break
            s.M = s.MG[s.I]                                          # 1560
            s.QT = 1
            self.item_name()
            self.bargain()

    def bargain(self):
        """1561-1589"""
        s, m = self.s, self.m
        while True:
            m.home()                                                 # 1561
            self.say("\rWHAT DO YOU OFFER FOR OUR ", s.B_S, "S\rM'LORD", end='')
            s.L = m.input_number()                                   # 1562
            m.home()
            if s.L < 1:
                return
            if s.L < s.Z7 or (s.L == s.Z7 and m.rnd(2)):
                self.say('\rYOU OFFERED ', s.Z7, " LAST TIME. LET'S JUST\rFORGET THE WHOLE THING.")   # 1574
                return self.price_back()
            s.Z7 = s.L
            if s.L < s.CP[s.I] - 1:
                if not (s.L >= AP[s.MG[s.I]] or m.rnd(3)):          # 1573
                    self.announce('NOT INTERESTED.')
                    return self.price_back()
                s.M = s.CP[s.I]                                      # 1576
                if s.L < idiv(AP[s.MG[s.I]], 2) and m.rnd(3):
                    m.home()                                         # 1582
                    self.say('\rYOUR OFFER IS AN INSULT. THAT ITEM IS NOLONGER FOR SALE.')
                    m.vtab(s.I + 5)
                    m.invflg = 0x7F
                    s.MG[s.I] = -1
                    self.wait40()                                    # 1585
                    for _ in range(39):
                        self.say(' ', end='')
                        m.pause(10)
                    return
                s.C = idiv(s.M - s.L, 3)
                if s.C > idiv(s.M, 10):
                    s.C = idiv(s.M, 10)
                if s.C == 0 or s.L < AP[s.MG[s.I]] - 10:
                    s.C = 1
                s.CP[s.I] = s.M - s.C
                cp = s.CP[s.I]
                r = m.rnd(4)
                if r == 0:
                    self.say("\rYOU MUST BE JESTING, M'LORD. I COULDN'T CONSIDER SELLING FOR LESS THAN ", cp,
                             '.\rWHAT DO YOU SAY?')
                elif r == 1:
                    self.say('\rI PAID MORE FOR IT MYSELF SIRE. HOW     ABOUT MAKING IT ', cp, '?')
                elif r == 2:
                    self.say("\rYOU LOOK LIKE A GOOD SORT SIR. I'LL TELLYOU WHAT. I'LL MAKE IT ", cp,
                             ' JUST FOR\rYOU. WHAT DO YOU SAY?')
                else:
                    self.say('\rIT WOULD BE A STEAL AT ', cp,
                             ' QUADROONS.\rI CAN AFFORD NO LESS. DO YOU WANT IT OR NOT?')
                self.getkey()                                        # 1581
                if s.V != YES:
                    continue
                s.L = s.CP[s.I]
            break
        while True:
            m.home()                                                 # 1564
            self.say('\rHOW MANY ', s.B_S, "S WOULD YOU LIKE\rTO PURCHASE AT ", s.L,
                     " QUADROONS EACH\rCAP'N", end='')
            while True:
                s.N = m.input_number()                               # 1567
                m.home()
                if s.N >= 0:
                    break
                self.say()                                           # 1569
                m.tab(7)
                self.say("SORRY, WE'RE SELLING, NOT BUYING.")
                self.say('\rHOW MANY ', s.B_S, "S WOULD YOU LIKE\rTO PURCHASE AT ", s.L,
                         " QUADROONS EACH\rCAP'N", end='')
            if s.N == 0:
                return
            if s.N > s.QTA[s.I]:
                self.say("\r\rI'M SORRY SIR,, BUT WE ONLY HAVE\r", s.QTA[s.I], ' ', s.B_S, 'S.')   # 1568
                self.wait40()
                continue
            break
        if s.L * s.N >= s.BQ[2] + 1:
            m.invflg = 0x7F                                          # 1598
            self.announce('NOT ENOUGH GOLD')
            m.invflg = 0xFF
            self.wait40()
            return
        self.sold()                                                  # 1588
        s.QTA[s.I] -= s.N
        m.vtab(5 + s.I)
        m.tab(33)
        self.say(' ', s.QTA[s.I], ' ', end='')
        s.C1 = s.MG[s.I]                                             # 1589
        self.wait40()
        m.invflg = 0x3F
        m.tab(33)
        self.say(' ', s.QTA[s.I], ' ')
        m.invflg = 0xFF
        s.BQ[2] -= s.L * s.N
        s.QT = s.N
        self.gain()

    def price_back(self):
        """1575"""
        s = self.s
        s.CP[s.I] = AP[s.I] + self.m.rnd(5)
        self.wait40()

    def sold(self):
        """1594-1595"""
        m = self.m
        m.home()
        m.invflg = 0x7F
        for row in (' XXX XXX X   XXX  ', ' X   X X X   X  X ', ' XXX X X X   X  X ', '   X X X X   X  X '):
            m.tab(11)
            self.say(row)
        m.tab(11)
        self.say(' XXX XXX XXX XXX  ', end='')
        m.invflg = 0xFF

    # ----------------------------------------------------------------------------------
    # 1600-1920: a raft; other ships; pirates
    # ----------------------------------------------------------------------------------
    def raft(self):
        """1600-1675"""
        s, m = self.s, self.m
        s.I = 3 + m.rnd(4)
        self.say("YOU'VE COME UPON A RAFT WITH ", s.I, ' MEN')
        self.say('ON IT. THEY HAVE A LARGE CHEST ON THEIR')
        self.say('BOAT. WILL YOU TAKE THEM ABOARD, IGNORE THEM, OR KILL THEM?', end='')   # 1610
        self.key99()
        m.home()
        if s.V == 201:
            s.AL -= 2
            return 600
        if s.V == 203:                                               # 1630
            s.AL -= 4
            if not m.rnd(3):
                self.say('\rTHEY WERE WEAK FROM EXPOSURE AND WERE\rEASILY MURDERED.')
                self.wait40()
                return self.raft_chest()
            s.I = 1 + m.rnd(4)                                       # 1640
            if s.I > s.FM:
                s.I = s.FM - 1
            self.say('THEY PUT UP A GOOD FIGHT BUT FINALLY\rWERE ALL KILLED. YOU LOST ', s.I, ' MEN IN THE')
            self.say('FIGHT.')                                       # 1642
            self.wait35()
            s.FM -= s.I
            return self.raft_chest()
        s.AL += 2                                                    # 1650
        if not m.rnd(2):
            self.say('\rTHEY ARE MERCENARIES AND WILL JOIN YOUR QUEST. THEY ALL HAVE SWORDS.')
            self.wait35()
            s.QT = s.I
            s.C1 = 22
            self.gain()
            s.FM += s.I                                              # 1660
            s.TOT += s.I
            return self.raft_chest()
        m.home()                                                     # 1670
        self.say('IT WAS A RUSE!\x07 THEY JUST WANTED TO\r\x07DISTRACT YOU WHILE THEIR SHIPS CAME\r\x07ALONGSIDE.')
        s.COLR = 85
        s.X = s.X0                                                   # 1675
        s.ST = s.X - 42
        if s.X < 119:
            s.ST = s.X + 20
        s.X0 = s.ST
        s.SHAPE = 21
        self.draw()
        s.X0 = s.X
        self.wait35()
        s.PG = 2
        return self.pirates()

    def ships(self):
        """1800-1850: three ships bear down on us."""
        s, m = self.s, self.m
        s.PG = 1 + m.rnd(2)
        self.say('\x07\rTHE LOOKOUT HAS \x07SIGHTED SHIPS COMING UP ON US. \x07PREPARE FOR ACTION.')
        s.K = 90                                                     # 1820
        self.place_beside()
        s.Y0 = 75
        s.M = 2 * sgn(s.ST - s.K)
        i = s.K
        while True:                                                  # FOR I=K TO ST STEP M
            s.I = i
            s.X0 = i                                                 # 1830
            s.L = sgn(s.Y - s.Y0)
            s.COLR = 0
            self.draw()
            s.X0 += s.M
            s.Y0 += s.L
            s.COLR = 85
            self.draw()
            m.pause(10)
            i += s.M
            if s.M == 0 or (s.M > 0 and i > s.ST) or (s.M < 0 and i < s.ST):
                break
        while s.Y != s.Y0:                                           # 1840
            s.COLR = 0
            self.draw()
            s.Y0 += s.L
            s.COLR = 85
            self.draw()
            m.pause(10)
        s.COLR = 0                                                   # 1845
        self.draw()
        s.X0 = s.ST
        s.COLR = 85
        self.draw()
        m.home()                                                     # 1850
        self.say('\rTHEY ARE LIGHTLY ARMED, BUT THERE ARE 3 OF THEM.  WHAT DO YOU WANT TO DO?')
        return 700

    def ships_pass(self):
        """1860-1870"""
        if self.m.rnd(2):
            return self.pirates()
        self.say('\rSINCE YOU ARE JUST SAILING AWAY, THEY\rTOO WENT ON THEIR WAY.')
        return 590

    def pirates(self):
        """1880-1885"""
        s, m = self.s, self.m
        s.PG = 4
        m.home()
        self.say('THE SHIPS ARE PIRATES! THEY COMMAND YOU TO PUT ALL OF YOUR TREASURE OVER THE')
        self.say('SIDE ONTO ONE OF THEIR BOATS. WHAT WILL YOU DO?', end='')
        return 690

    def pay_pirates(self):
        """1890-1920: you put QT quadroons over the side for the pirates."""
        s, m = self.s, self.m
        m.home()
        if s.QT < idiv(s.BQ[2], 2):
            self.say("THEY'RE LAUGHING CAPTAIN. I DON'T THINK THEY WERE FOOLED. WHAT SHALL WE DO?")
            return 690
        if s.BQ[2] < 200:
            self.say("THEY'RE LAUGHING CAPTAIN. THEY ARE GOINGOFF TO LOOK FOR RICHER PREY. THEY SAID  TO "
                     "KEEP OUR MEASLY ", s.QT, ' QUADROONS.')
            return 590
        s.BQ[2] -= s.QT
        if s.BQ[2] == 0:
            self.say("THEY SEEM SATISFIED SIR. DON'T YOU THINKWE COULD HAVE TRIED SAVING A LITTLE OF\r"
                     "IT FOR AN EMERGENCY THOUGH?")
            return 590
        self.say("THEY WERE COMPLETELY FOOLED, CAP'N. WE")
        self.say('STILL HAVE ', s.BQ[2], " QUADROONS LEFT AND\rTHEY'VE GONE.")
        return 590

    # ----------------------------------------------------------------------------------
    # 2000-3630: weather and other calamities
    # ----------------------------------------------------------------------------------
    def weather_event(self):
        """2000"""
        s, m = self.s, self.m
        m.home()
        r = m.rnd(4)
        if r == 0:                                                   # 2200 storm
            m.home()
            self.say("\rIT LOOKS LIKE A THUNDER STORM IS BREWINGCAP'N. WE BETTER LASH EVERYTHING DOWN.")
            self.wait35()
            m.switch(-16298)
            m.gr()
            m.home()                                                 # 2210
            self.say("\rIT'S BLACK AS PITCH, SIR! I'LL HAVE THE LOOKOUT WATCH FOR ROCKS WHENEVER THE\r"
                     "LIGHTNING FLASHES!")
            s.PG = 8
            return 690
        if r == 1:                                                   # 2400 scurvy
            self.say('\rTHE MEN ARE COMING DOWN WITH SCURVEY.\rWHAT WILL YOU DO?')
            self.sound80()
            s.LEV = 1
            return 690
        self.say('\rIT LOOKS LIKE A FOG BANK IS ROLLING IN. WHAT DO YOU WANT TO DO?')   # 2800
        s.COLR = 127
        m.hires.fill(s.COLR)
        s.COLR = 0
        self.draw()
        s.PG = 3
        return 690

    def storm_loss(self):
        """2250-2270"""
        s, m = self.s, self.m
        self.say()
        self.storm_over()
        s.BI = 3 + m.rnd(s.BN - 3)                                   # 2260
        s.I = 3 + m.rnd(s.BQ[s.BI] - 3)
        if s.I > s.BQ[s.BI]:
            s.I = s.BQ[s.BI]
        self.slot_name()
        self.say('THE ONLY LOSSES WERE ', s.I, ' ', s.B_S)
        self.say('WASHED OVERBOARD.')
        self.use_up()                                                # 2270
        return 580

    def storm_over(self):
        """7000"""
        s, m = self.s, self.m
        m.switch(-16297)
        m.home()
        s.PG = 0
        self.say('\rIT LOOKS LIKE THE STORM HAS BROKEN, SIR.')
        self.wait35()

    def fog_clears(self, home=True):
        """2820-2825"""
        s, m = self.s, self.m
        if home:
            m.home()
        self.say('\rIT LOOKS LIKE THE FOG IS CLEARING UP.')
        m.hgr_load(self.game.asset('seamap.hgr'), 'seamap')
        s.COLR = 127
        self.draw()
        if s.PG == 6:
            return self.fishermen()
        s.PG = 0
        return 581

    def calamity(self):
        """3000"""
        s, m = self.s, self.m
        self.sound80()
        m.home()
        r = m.rnd(3)
        if r == 0:                                                   # 3200
            s.Z3 = s.Z2 = -1
            self.say('\rTHE WIND HAS DIED. YOU ARE BECALMED.\rTHE MEN HAVE REEFED THE SAILS UNTIL THE WIND RETURNS.')
            self.wait30()
            return 600
        if r == 1:                                                   # 3400
            s.PG = 5
            s.Z2 = -1
            self.say('\rYOUR SAILS HAVE ROTTED AND ARE TEARING. WHAT WILL YOU DO?')
            s.U1 = 19
            s.Z11 = 1
            return 690
        s.LEV = 0                                                    # 3600
        self.say('         A GIANT WHIRLPOOL!')
        self.wait40()
        self.say("WE'RE GETTING SUCKED IN! WHAT SHALL WE  DO, CAP'N?")
        s.PG = 10
        return 690

    def tossed_free(self):
        """3620"""
        s, m = self.s, self.m
        m.home()
        self.say('\rWE WERE TOSSED FREE SOMEHOW.')
        self.wait40()
        self.say('OUR SAILS ARE RUINED THOUGH. WHAT NOW?')
        s.Z2 = -1
        s.Z11 = 1
        return self.whirlpool_over()

    def whirlpool_over(self):
        """3630"""
        s = self.s
        s.LEV = 0
        s.PG = 0
        s.COLR = 0
        self.draw()
        s.ROT = 0
        s.COLR = 127
        self.draw()
        return 690

    # ----------------------------------------------------------------------------------
    # 4000-4850: chests and wreckage
    # ----------------------------------------------------------------------------------
    def raft_chest(self):
        """4000-4050"""
        s, m = self.s, self.m
        m.home()
        self.say('\rDO YOU WANT TO OPEN THE CHEST OR DUMP ITOVER THE SIDE?')
        self.getkey()
        if s.V == 196:
            return 600
        self.wait40()                                                # 4010
        m.home()
        return self.chest_contents(m.rnd(4))

    def chest_contents(self, r):
        s, m = self.s, self.m
        if r == 0:                                                   # 4020
            s.I = 500 + m.rnd(500)
            self.say('\rCONGRATULATIONS! THE CHEST CONTAINED\r', s.I, ' QUADROONS OF GOLD.')
            s.BQ[2] += s.I
            self.sound70()
            return 581
        if r == 1:                                                   # 4030
            self.say('\rTHE CHEST IS FULL OF SODDEN MILDEWED\rCLOTHES. TOTALLY WORTHLESS.')
            return 580
        if r == 2:                                                   # 4040
            self.say('THE MAN OPENING THE CHEST GOT A SPLINTEROF IT IN HIS HAND AND DIED INSTANTLY. ITMUST '
                     'TO BE POISONED OR ENCHANTED.')
            self.wait30()                                            # 4045
            m.home()
        s.QT = 1                                                     # 4050
        s.M = 39 + m.rnd(9)
        self.item_name()
        self.say('THE CHEST CONTAINS A ', s.B_S, '.')
        s.C1 = s.M
        self.gain()
        return 581

    def wreckage(self):
        """4500-4850"""
        s, m = self.s, self.m
        self.wait30()
        m.home()
        if not m.rnd(2):
            self.say('IT LOOKS LIKE EVERYTHING OF VALUE WENT\rDOWN WITH THE SHIPS. WHAT DO YOU WANT TODO?')
            return 690
        m.text()                                                     # 4700
        m.home()
        self.say('\r\rMUCH OF THE WRECKAGE STAYED AFLOAT FOR  AWHILE. YOU MANAGED TO SAVE THE         '
                 'FOLLOWING ITEMS:\r\r')
        for i in range(1, 8):
            s.MG[i] = 0
        for i in range(1, 8):
            s.I = i
            s.C1 = m.rnd(30)                                         # 4806
            for j in range(1, i + 1):
                if s.MG[j] == s.C1:
                    s.C1 = 0
            if m.rnd(4) == 0:
                s.C1 = 0
            if s.C1 == 5:
                s.C1 = 48
            s.MG[i] = s.C1
        for i in range(1, 8):
            s.I = i
            if s.MG[i] == 0:
                continue
            s.QT = 3 + m.rnd(10)                                     # 4810
            s.C1 = s.MG[i]
            s.M = s.C1
            if s.M == 48:
                s.QT = 400 + m.rnd(1000)
            self.item_name()
            m.tab(5)
            self.say(s.QT, end='')
            m.tab(8)
            self.say(s.B_S)
            self.gain()
        m.clear_strobe()
        return 590

    # ----------------------------------------------------------------------------------
    # 6000-8230
    # ----------------------------------------------------------------------------------
    def place_beside(self):
        """6000: ST = where to draw something alongside the ship."""
        s = self.s
        s.X, s.Y = s.X0, s.Y0
        s.SHAPE = 21
        if s.X < 120:
            s.K = 180
        s.ST = s.X + (30 + 10 * (s.PG == 12)) * (s.X < 120) - 42 * (s.X > 119)

    def L6010(self):
        s = self.s
        s.COLR = 0
        self.draw()
        s.SHAPE = 17
        s.X0 = s.X
        return 690

    def L6020(self):
        s = self.s
        s.PG = 0
        s.Z1 = 0
        return self.L6010()

    def used_right_thing(self):
        """8000-8010"""
        s, m = self.s, self.m
        m.home()
        if s.U1 == 48:
            return self.pay_fishermen()
        if s.U1 == 21 and s.U2 == 4 and s.U3 == 35:
            return self.chest_contents(m.rnd(3))
        if s.U1 != 19:
            raise BasicError('no line 8020')
        self.use_up(1)
        self.say('\r         CONTINUE YOUR JOURNEY.')
        s.U1 = 0
        s.Z11 = 0
        return 700

    def fruit(self):
        """8100-8110: fruit cures scurvy."""
        s, m = self.s, self.m
        m.home()
        self.say('\rTHE FRUIT SEEMS TO HAVE TAKEN CARE OF\rTHE SCURVEY PROBLEM.')
        self.use_up(idiv(s.FM, 10) + 1)
        s.I = s.BQ[s.BI]
        if s.BG[s.BI] != 14:
            s.I = 0
        self.say('THERE ARE ONLY ', s.I, ' OF THEM LEFT THOUGH.', end='')
        s.LEV = 0
        return 580

    def pay_fishermen(self):
        """8200-8230 (you pay them nothing - they only want to hear a fair offer)."""
        s, m = self.s, self.m
        m.set_window(top=20)
        m.home()
        s.I = m.input_number('\rHOW MUCH ARE YOU WILLING TO PAY')
        s.J = s.BQ[2]
        if s.I > 199 or s.I >= idiv(s.J, 3):
            s.PG = 0                                                 # 8230
            m.home()
            self.wait40()
            self.say('\rTHEY GOT YOU FREE. WHAT NOW CAPTAIN?')
            return 690
        self.say("\rYOU'VE GOT TO BE KIDDING. IT'S NOT EASY PULLING A SHIP OFF THE MUD FLATS.\r"
                 "THE FISHERMEN ARE SAILING AWAY.")
        return 580

    # ----------------------------------------------------------------------------------
    # 20050-20076: a sea battle
    # ----------------------------------------------------------------------------------
    def sea_battle(self):
        s, m = self.s, self.m
        s.K = 0
        for mm in range(1, 4):
            s.M = mm
            while True:
                for _ in range(15):                                  # 20051
                    self.cannon()
                if m.rnd(5) < 2:                                     # 20055: a hit!
                    break
                s.K += 1                                             # they hit us
                m.pause(100)
                s.X0 = s.X + 2 * m.rnd(5) - 5
                s.Y0 = s.Y - 10 + m.rnd(2) - 2 * m.rnd(2)
                s.SHAPE = 20
                s.COLR = 0
                self.draw()
            if mm == 1:                                              # 20057
                s.X0, s.Y0 = s.ST, s.Y
            if mm == 2:
                s.X0, s.Y0 = s.ST + 20, s.Y + 3
            if mm == 3:
                s.X0, s.Y0 = s.ST + 16, s.Y + 14
            m.clicks([BASIC_STATEMENT])                              # 20060: the explosion
            s.COLR = 85
            s.SHAPE = 11
            self.draw()
            s.SHAPE = 16
            self.xdraw()
            m.pause(35)
            s.SHAPE = 12                                             # 20065
            s.COLR = 170
            self.draw()
            s.SHAPE = 15
            self.xdraw()
            s.SHAPE = 16
            self.draw()
            m.pause(35)
            s.COLR = 85                                              # 20067
            s.SHAPE = 15
            self.draw()
            s.COLR = 0
            m.clicks([BASIC_STATEMENT, PEEK_TERM, BASIC_STATEMENT])
            m.pause(20)
            s.SHAPE = 9                                              # 20070: she sinks
            s.Y0 += 3
            s.X0 += 10
            for _ in range(9):
                self.draw()
                s.X0 = imod(s.X0 - 1 + 279, 279)
                m.pause(4)
        s.X0, s.Y0 = s.X, s.Y
        s.SHAPE = 17
        s.PG = 0
        s.TSH += 3
        s.I = 50 * s.K                                               # 20075
        if s.I > s.BQ[2]:
            s.I = s.BQ[2]
        s.BQ[2] -= s.I
        m.home()
        self.say('YOU DESTROYED THEM, BUT YOUR SHIP IS')
        self.say('DAMAGED. IT COST YOU ', s.I, ' QUADROONS\rTO GET THE NECESSARY REPAIR MATERIALS   FROM SOME '
                 'FISHERMEN.', end='')
        return self.wreckage()

    # ----------------------------------------------------------------------------------
    # 20900-22000: going ashore
    # ----------------------------------------------------------------------------------
    def go_ashore(self):
        s, m = self.s, self.m
        s.X3, s.Y3 = s.X0, s.Y0
        m.home()
        if not (s.X0 > 50 or s.Y0 > 55):                             # the Isle of Lapour
            m.home()
            if not s.Z8:
                self.say('\rBUT SIR, THIS IS THE ISLE OF LAPOUR.')
                self.say("WITHOUT THE HIGH ONE'S ORB, WE WON'T\rSTAND A CHANCE. SHALL WE STILL GO ON?")
                if self.getkey() != YES:
                    return 600
            s.PG = 0                                                 # 20903
            m.invflg = 0x7F
            self.announce('LANDING PARTY ASHORE!')
            m.invflg = 0xFF
            m.switch(-16297)                                         # 20905
            s.Z15 = 1
            self.say()
            raise Chain('cavern')
        if not (s.X0 < 150 or s.Y0 < 100):                           # 20910: home island
            self.say('\rSORRY, THE LOCAL SHIPBUILDERS UNION\rWILL NOT ALLOW YOU TO LAND HERE.')
            return 580
        if s.PG == 8:                                                # 20920
            s.PG = 0
        m.invflg = 0x7F
        self.announce('LANDING PARTY ASHORE.')
        m.invflg = 0xFF
        self.wait35()
        if m.rnd(4) == 0 or s.Z21 > 2:
            return self.temple()
        s.Z21 += 1                                                   # 20925
        self.say('\rTHE ISLAND WAS DESERTED, SIRE, BUT WE\rDID STOCK UP ON FRUIT AND WATER.')
        s.C1 = 14
        s.QT = 40
        self.gain()
        return 581

    def temple(self):
        """21000-22000: the wizard who guards the catacombs."""
        s, m = self.s, self.m
        s.Z1 = 1
        s.PG = 7
        m.home()
        self.say('YOU\'VE MADE YOUR WAY TO A GIGANTIC OLD\rTEMPLE. A POWERFUL WIZARD GUARDS THE')
        s.U1 = s.U2 = s.U3 = 0
        self.say('CATACOMBS BENEATH THE TEMPLE. HE REFUSESTO LET YOU IN. WHAT WILL YOU DO?', end='')
        while True:
            self.getkey()                                            # 21020
            if s.V == 193:
                m.home()                                             # 21040
                self.sound77()
                s.I = 2 + m.rnd(3)
                self.say('THE ATTACK WAS ILL ADVISED, SIRE. HE\rBLASTED ', s.I, ' MEN WITH A LIGHTNING BOLT')
                self.say('AND WAS COMPLETELY UNHARMED HIMSELF.\rWHAT NOW?', end='')
                s.FM -= s.I
                self.check_alive()
            elif s.V == 213:                                         # 22000
                self.choose_item('USE')
                m.gr()
                m.home()
                self.slot_name()
                self.say('\rOK, YOU USED YOUR ', s.B_S, ".\rYOU STILL CAN'T GET IN. NOW WHAT?")
            elif s.V == 207:                                         # 21060
                self.choose_item('OFFER')
                s.M = s.BG[s.BI]
                s.QT = 1
                self.item_name()
                m.home()
                self.say('\rARE YOU SURE YOU WISH TO GIVE HIM A\r', s.B_S, '?')
                self.getkey()
                if s.V != YES:
                    m.home()
                    self.say('WELL THEN, WHAT DO YOU WANT TO DO?')
                    continue
                s.QT = 2                                             # 21080
                self.item_name()
                s.BQ[s.BI] -= 1
                if s.BQ[s.BI] == 0:
                    self.close_gap()
                m.home()
                self.wait40()
                self.say('HE ACCEPTED ONE OF YOUR ', s.B_S)
                if 38 < s.M < 48:                                    # something magic
                    m.home()                                         # 21100
                    self.say('\rHE WILL LET YOU ENTER THE CATACOMBS.')
                    self.wait40()
                    m.switch(-16298)
                    m.gr()
                    self.say("IT'S VERY DARK IN THERE.")
                    s.PG = 0                                         # 21105
                    raise Chain('cavern')
                self.say("HE STILL WON'T LET YOU IN THOUGH. WHAT  NOW?")
            elif s.V == 204:                                         # 21110
                self.announce('BACK TO THE SHIP!')
                self.wait40()
                s.PG = 0
                return 600
            else:
                m.home()                                             # 21030
                self.inverse(' COMMANDS ARE: ')
                self.say(' ATTACK, USE, OFFER,\rOR LEAVE.')
