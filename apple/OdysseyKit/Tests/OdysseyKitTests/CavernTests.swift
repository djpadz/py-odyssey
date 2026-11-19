import Foundation
import Testing
@testable import OdysseyKit

struct CavernTests {
    /// A party just let into the catacombs by the wizard.
    private func below(_ seed: UInt64 = 5, events: Bool = false) -> Expedition {
        var e = Expedition(seed: seed)
        e.roadEvents = events
        e.party.men = 30
        e.embark()
        e.voyage!.happening = .temple
        e.party.inventory[Item(47)] = 1
        e.useAtSea(Item(47), offering: true)
        return e
    }

    @Test func theWizardLetsThemIn() {
        let e = below()
        let c = try! #require(e.catacombs)
        #expect(e.voyage?.ashore == .catacombs)
        #expect(!c.isWall(c.x, c.y))
        #expect(!c.light)
        #expect(c.report.first == "YOU ARE IN THE CATACOMBS.")
    }

    @Test func inTheDarkOnlyTheLight() {
        var e = below()
        e.catacombs!.floor[Catacombs.floorKey(e.catacombs!.x, e.catacombs!.y)] = 3302
        e.order(.get)
        #expect(e.catacombs?.said == [])
        #expect(e.party.inventory[Item(33)] == nil)
        e.order(.light)
        #expect(e.catacombs?.said == ["OK, YOUR LIGHT IS ON. NOW WHAT?"])
        e.order(.get)
        #expect(e.party.inventory[Item(33)] == 2)
    }

    @Test func wallsStopAndNewGroundIsLaidOut() {
        var e = below()
        let (sx, sy) = (e.catacombs!.x, e.catacombs!.y)                   // (K+3, I+3) of tile 1150
        e.creep(1)                                                        // east is rock
        #expect(e.catacombs!.x == sx)
        e.creep(0)                                                        // north, then east to the edge
        e.creep(1)
        let c = e.catacombs!
        #expect(c.x == sx + 1 && c.y == sy - 1)
        #expect(c.isLaid(k: c.x - c.x % 5 + 5, i: c.y - c.y % 5))         // and the next tile is laid out
        e.creep(0)
        e.creep(0)                                                        // the tile's top row is rock
        #expect(e.catacombs!.y == sy - 2)
    }

    @Test func magicBanishesFrenziesAndBorers() {
        var e = below()
        e.order(.light)
        e.catacombs!.frenziesX = 1
        e.catacombs!.frenziesY = 1
        e.catacombs!.borerX = 2
        e.catacombs!.borerY = 2
        e.party.inventory[Item(39)] = 1
        e.party.inventory[Item(42)] = 1
        e.useBelow(Item(39))
        #expect(e.catacombs?.frenzies == nil)
        #expect(e.party.inventory[Item(39)] == 0)
        e.useBelow(Item(42))
        #expect(e.catacombs?.borer == nil)
        #expect(e.catacombs?.said.first?.hasPrefix("THE BORERS WERE BANISHED") == true)
    }

    @Test func theBorerStrikesOnce() {
        var e = below()
        e.order(.light)
        let c = e.catacombs!
        e.catacombs!.borerX = c.x
        e.catacombs!.borerY = c.y
        let men = e.party.men
        e.creep(0)
        e.creep(2)
        e.creep(0)
        #expect(e.catacombs?.borer == nil)
        #expect(e.party.men == men - 2)
    }

    @Test func theFrenziesFindTheParty() {
        var hits = 0
        for seed in 0..<20 as Range<UInt64> {
            var e = below(seed)
            let c = e.catacombs!
            e.catacombs!.frenziesX = c.x + 1
            e.catacombs!.frenziesY = c.y
            e.catacombs!.frenzyStep = [-1, 0]
            let men = e.party.men
            for _ in 0..<400 where e.catacombs?.frenzies != nil { e.catacombsTick(dt: 0.05) }
            if e.party.men == men - 2 { hits += 1 }
        }
        #expect(hits > 10)
    }

    /// Long explorations with random orders: down the stairs, to the altar, out with
    /// the orb.
    @Test func randomExplorationsFindTheOrb() {
        var seen = Set<String>(), orbs = 0, outs = 0
        for seed in 0..<60 as Range<UInt64> {
            var e = below(seed, events: true)
            e.party.inventory[Item(7)] = 1                               // a rope
            e.party.inventory[Item(8)] = 1                               // a shovel
            e.party.inventory[Item(10)] = 1                              // a helmet
            e.party.men = 200
            var pick = SeededRandom(seed: seed &* 13)
            for _ in 0..<4000 where !e.isLost {
                guard let c = e.catacombs else { break }
                if c.frenzies != nil { seen.insert("frenzies") }
                if c.borer != nil { seen.insert("borer") }
                if c.gas != nil { seen.insert("gas") }
                if c.stairway { seen.insert("stairs") }
                if c.altar != nil { seen.insert("altar") }
                if let t = c.trouble { seen.insert("\(t)".prefix { $0 != "(" }.description) }
                if c.question != nil {
                    e.answerBelow(pick.rnd(2) == 0)
                    continue
                }
                if !c.light { e.order(.light); continue }
                if c.atAltar { e.order(.get); orbs += 1; continue }
                if c.stairway || c.exitHere { e.order(c.exitHere ? .out : .down); continue }
                if c.trouble != nil { e.useBelow(pick.rnd(2) == 0 ? Item(7) : Item(8)); continue }
                if pick.rnd(40) == 0 { e.order(.burrow) }
                e.creep(pick.rnd(4))
                e.catacombsTick(dt: 0.1)
                #expect(e.party.men >= 0)
            }
            if e.catacombs == nil && e.hasOrb && !e.isLost {
                outs += 1
                #expect(e.voyage?.ashore == nil)
            }
        }
        #expect(seen.isSuperset(of: ["frenzies", "borer", "gas", "stairs", "altar", "pit", "caveIn"]))
        #expect(orbs > 0)
        #expect(outs > 0)
    }

    // MARK: The fortress

    private func onLapour(_ seed: UInt64 = 2, orb: Bool) -> Expedition {
        var e = Expedition(seed: seed)
        e.party.men = 40
        e.embark()
        e.hasOrb = orb
        e.voyage!.x = 40
        e.voyage!.y = 30
        e.command(.land)
        if !orb { e.answer(.yes) }
        return e
    }

    @Test func threeHazardsThenTheFortress() {
        var e = onLapour(orb: true)
        let f = try! #require(e.fortress)
        #expect(Set(f.hazards).count == 3)
        for h in f.hazards {
            e.approach()
            #expect(e.fortress?.hazard == h)
            #expect(e.fortress?.said.first == "WE MADE IT THIS FAR, BUT WE'RE BLOCKED BY \(h.words)")
            let item = Item(h.clean[0])
            e.party.inventory[item, default: 0] += 1
            e.party.inventory[Item(5)] = 0
            e.useAtFortress(Item(5 == h.clean[0] ? 6 : 1))               // food doesn't help
            #expect(e.fortress?.said.first?.hasSuffix("SERVED NO USEFUL PURPOSE. NOW WHAT?") == true)
            e.useAtFortress(item)
            #expect(e.fortress?.said == [h.passed])
            #expect(e.fortress?.blocked == false)
        }
        e.approach()
        let end = try! #require(e.ending)
        #expect(end.won)
        #expect(end.words.first == "YOU MADE IT!!!!!")
        #expect(end.men == 40)
        let goods = e.party.inventory.reduce(0) { $0 + $1.value * $1.key.listPrice / 10 }
        #expect(end.score == e.party.gold / 10 + goods + 0 - (e.recruited - 40) * 20 + 0)
    }

    @Test func forcingAHazardCostsHalfTheMen() {
        var e = onLapour(orb: false)
        e.approach()
        e.approach()
        #expect(e.party.men == 20)
        #expect(e.fortress?.said.first == "WE MADE IT PAST THE HAZARD, SIR, BUT 20 MEN WERE KILLED.")
        e.approach(); e.approach(); e.approach(); e.approach()
        e.approach()
        let end = try! #require(e.ending)
        #expect(!end.won)
        #expect(end.men == 0)
    }

    @Test func retreatingToTheShip() {
        var e = onLapour(orb: true)
        e.retreat()
        #expect(e.fortress?.askingRetreat == true)
        e.confirmRetreat(true)
        #expect(e.fortress == nil)
        #expect(e.voyage?.ashore == nil)
        #expect(e.voyage?.said == ["BACK TO THE SHIP!"])
    }

    @Test func belowGroundSavesToo() throws {
        var e = below()
        e.order(.light)
        e.creep(1)
        let back = try JSONDecoder().decode(Expedition.self, from: JSONEncoder().encode(e))
        #expect(back.catacombs?.x == e.catacombs?.x)
        #expect(back.catacombs?.walls == e.catacombs?.walls)
        #expect(back.catacombs?.light == true)
    }
}
