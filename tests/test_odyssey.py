"""Scenario tests for the Odyssey port.  Run with:  python3 -m unittest discover tests"""
import os
import random
import tempfile
import unittest

from odyssey import data
from odyssey.apple import Headless, Quit, ScriptEnd
from odyssey.game import Game, asset
from odyssey.hires import Hires
from odyssey.part import GameOver

RET = 0x0D


def make_game(keys, seed=1, save_path=None):
    fe = Headless(keys, idle_limit=3000)
    g = Game(fe, save_path=save_path or os.path.join(tempfile.mkdtemp(), 'old-game.json'),
             rng=random.Random(seed))
    return g, fe


def outfit(g, men=25, extra=()):
    """A party ready for the sea: food, gold, ship, compass, sextant..."""
    s = g.state = Game.fresh_state()
    s.CH, s.DEX, s.SP, s.WS, s.STR, s.EX = 6, 7, 4, 7, 6, 10
    s.FM = s.TOT = men
    items = [(1, 40), (48, 1500), (9, 2), (17, 10), (49, 1), (15, 1), (16, 1)] + list(extra)
    for i, (c, q) in enumerate(items, 1):
        s.BG[i], s.BQ[i] = c, q
    s.BN = len(items)
    return s


def run(g, part=None, line=None):
    try:
        if part:
            g.play(part, line)
        else:
            g.run()
    except (ScriptEnd, GameOver):
        pass


def text(fe):
    return ''.join(fe.log)


class Graphics(unittest.TestCase):
    def test_ship_collides_with_itself_33_times(self):
        # The Sea part decides "aground" by PEEK(810) != 33 after drawing the ship.
        h = Hires(asset('shapes.bin'))
        self.assertEqual(h.draw(17, 100, 80, 127), 33)

    def test_ship_over_land_collides_more(self):
        h = Hires(asset('shapes.bin'))
        h.load(asset('seamap.hgr'))
        self.assertGreater(h.draw(17, 50, 20, 127), 33)

    def test_xdraw_twice_restores_screen(self):
        h = Hires(asset('shapes.bin'))
        h.load(asset('island1.hgr'))
        before = bytes(h.mem)
        h.draw(2, 120, 90, 85, xor=True)
        self.assertNotEqual(before, bytes(h.mem))
        h.draw(2, 120, 90, 85, xor=True)
        self.assertEqual(before, bytes(h.mem))


class Data(unittest.TestCase):
    def test_tables(self):
        self.assertEqual(len(data.ISLAND_MAP), 401)
        self.assertEqual(len(data.SEA_MAP), 401)
        self.assertEqual(data.G1[:10], 'FOOD PACK\x01')
        self.assertEqual(data.ITEM_PRICE[49], 2500)          # the ship
        self.assertEqual(data.ISLAND_MAP[83], 56)             # the city at 63,16


class Island(unittest.TestCase):
    def test_new_game(self):
        g, fe = make_game(['N', 'C', 'L'])
        run(g)
        t = text(fe)
        self.assertIn('YOU ARE IN THE', t)
        self.assertIn('STATUS REPORT', t)
        self.assertEqual(g.state.FM, 10)
        self.assertIn(g.state.BQ[2] // 100, range(9, 12))   # 900-1199 quadroons

    def test_quit_without_saving_closes(self):
        path = os.path.join(tempfile.mkdtemp(), 'old.json')
        g, fe = make_game(['N', 'Q', 'Y', 'N'], save_path=path)
        with self.assertRaises(Quit):
            g.run()
        self.assertFalse(os.path.exists(path))

    def test_sail_away(self):
        g, fe = make_game(['U', '5', 'Y'], seed=3)
        s = outfit(g, men=20)
        s.LC = list(data.ISLAND_MAP)
        g.machine.hgr_load(asset('island1.hgr'))
        s.X = s.X0, s.Y0 = 63, 16
        s.X = 63
        s.SHAPE, s.COLR, s.SCALE = 2, 85, 1
        run(g, 'island', 700)
        t = text(fe)
        self.assertIn("YOU'RE READY TO LEAVE THIS ISLAND", t)
        self.assertIn('THE WIND IS OUT OF THE SE', t)          # now at sea
        self.assertIn('LATITUDE IS 117 AND LONGITUDE IS 205', t)

    def test_quit_save_restore(self):
        path = os.path.join(tempfile.mkdtemp(), 'old.json')
        g, fe = make_game(['N', 'Q', 'Y', 'Y', RET], save_path=path)
        with self.assertRaises(Quit):              # quitting closes the game
            g.run()
        self.assertTrue(os.path.exists(path))
        saved_gold = g.state.BQ[2]
        g2, fe2 = make_game(['P', RET, RET, 'C'], seed=99, save_path=path)
        run(g2)
        self.assertEqual(g2.state.BQ[2], saved_gold)
        self.assertIn('GOLD=%d' % saved_gold, text(fe2))


class Sea(unittest.TestCase):
    def find_spot(self, cond):
        lc = data.SEA_MAP
        for y0 in range(10, 150, 2):
            for x0 in range(10, 270, 2):
                if not lc[x0 // 14 * 20 + y0 // 8 - 1] or not cond(x0, y0):
                    continue
                for x in range(x0 - 15, x0 + 36, 5):
                    for y in range(y0 - 20, y0 + 21, 5):
                        i = x // 14 * 20 + y // 8 - 1 if x >= 0 and y >= 0 else -1
                        if 0 <= i <= 400 and lc[i] == 0:
                            return x0, y0
        raise AssertionError('no spot')

    def test_land_on_lapour_reaches_fortress(self):
        g, fe = make_game(['L', 'Y'])
        s = outfit(g)
        s.X0, s.Y0 = self.find_spot(lambda x, y: x <= 50 and y <= 55)
        run(g, 'sea', 10)
        t = text(fe)
        self.assertIn('ISLE OF LAPOUR', t)
        self.assertIn('LANDING PARTY ASHORE!', t)
        self.assertIn('WHAT DO YOU WANT TO DO NOW?', t)
        self.assertEqual(g.state.Z15, 1)

    def test_temple_wizard_lets_you_into_catacombs(self):
        # Land on an ordinary island until the temple turns up, offer the amulet.
        keys = ['L'] * 6 + ['O', '8', 'Y']
        g, fe = make_game(keys, seed=5)
        s = outfit(g, extra=[(39, 1)])
        s.Z21 = 3                                   # the island is not deserted
        s.X0, s.Y0 = self.find_spot(lambda x, y: (x > 50 or y > 55) and (x < 150 or y < 100))
        run(g, 'sea', 10)
        t = text(fe)
        self.assertIn('POWERFUL WIZARD GUARDS', t)
        self.assertIn('HE WILL LET YOU ENTER THE CATACOMBS', t)
        self.assertIn('YOU ARE IN THE CATACOMBS', t)

    def test_cannot_sail_into_the_wind(self):
        g, fe = make_game(['A', 'S', 'S', 'E'])           # wind from the SE
        outfit(g).X0, g.state.Y0 = 205, 117
        run(g, 'sea', 10)
        self.assertIn('YOU CANNOT SAIL TO THE SE', text(fe))


class Fortress(unittest.TestCase):
    def test_win(self):
        g, fe = make_game(['A'] * 7, seed=2)
        s = outfit(g, men=200)
        s.Z15, s.Z8 = 1, 2                          # at Lapour, with the orb
        run(g, 'cavern', 10)
        t = text(fe)
        self.assertIn('YOU MADE IT!!!!!', t)
        self.assertIn('YOUR COMPOSITE SCORE IS', t)

    def test_without_the_orb(self):
        g, fe = make_game(['A'] * 7 + [RET], seed=2)
        s = outfit(g, men=200)
        s.Z15, s.Z8 = 1, 0
        with self.assertRaises(Quit):              # the force is lost: a key, then the game closes
            g.play('cavern', 10)
        self.assertIn("WITHOUT THEHIGH ONE'S ORB", text(fe))
        self.assertEqual(g.state.FM, 0)

    def test_win_offers_new_quest_or_leave(self):
        g, fe = make_game(['A'] * 7 + ['2', '2'], seed=2)   # (a key pressed early is discarded)
        s = outfit(g, men=200)
        s.Z15, s.Z8 = 1, 2
        with self.assertRaises(Quit):              # 2 = leave
            g.play('cavern', 10)
        t = text(fe)
        self.assertIn('1. START A NEW QUEST', t)
        self.assertIn('2. LEAVE THE GAME', t)


class Menu(unittest.TestCase):
    def test_recover_ship_after_falling_off_the_world(self):
        g, fe = make_game([RET, '1', '1'], seed=1)
        s = outfit(g)
        s.X0, s.Y0 = 205, 117
        s.X, s.Y = 300, 117                         # past the eastern edge
        sea_part = __import__('odyssey.sea', fromlist=['Sea']).Sea(g)
        g.machine.hgr_load(asset('seamap.hgr'), 'seamap')
        s.SHAPE, s.COLR, s.SCALE = 17, 127, 1
        with self.assertRaises(ScriptEnd):
            g.play('sea', 5100)
        t = text(fe)
        self.assertIn('YOUR SHIP WAS LOST', t)
        self.assertIn('1. RECOVER YOUR SHIP', t)
        self.assertIn('THE WIND IS OUT OF THE', t)   # back at sea after choosing 1


class Death(unittest.TestCase):
    def test_island_death_closes_after_key(self):
        g, fe = make_game(['C', RET, RET, RET], seed=1)   # (the pause before it eats keys)
        s = outfit(g)
        s.FM = 0
        s.LC = list(data.ISLAND_MAP)
        g.machine.hgr_load(asset('island1.hgr'), 'island1')
        s.X = s.X0, s.Y0 = 100, 80
        s.X, s.SHAPE, s.COLR, s.SCALE = 100, 2, 85, 1
        with self.assertRaises(Quit):
            g.play('island', 700)
        self.assertIn('BETTER LUCK NEXT TIME', text(fe))

    def test_catacombs_death_waits_for_a_key(self):
        g, fe = make_game([], seed=4)
        outfit(g).FM = 0
        with self.assertRaises(ScriptEnd):         # message up, waiting for the key
            g.play('cavern', 10)
        self.assertIn('BETTER LUCK NEXT TIME', text(fe))
        g2, fe2 = make_game([RET], seed=4)
        outfit(g2).FM = 0
        with self.assertRaises(Quit):
            g2.play('cavern', 10)


class Catacombs(unittest.TestCase):
    def test_light_and_walk(self):
        g, fe = make_game(['L', 'N', 'N', 'E', 'C'], seed=4)
        s = outfit(g)
        run(g, 'cavern', 10)
        t = text(fe)
        self.assertIn('OK, YOUR LIGHT IS ON', t)
        self.assertIn('YOU ARE IN THE CATACOMBS', t)
        self.assertIn('STATUS REPORT', t)
        self.assertEqual(g.machine.scrn(s.X, s.Y), 9)   # the party is on the map


if __name__ == '__main__':
    unittest.main()
