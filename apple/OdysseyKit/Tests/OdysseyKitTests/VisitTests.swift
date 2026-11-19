import Testing
@testable import OdysseyKit

struct VisitTests {
    /// An expedition standing at the first site of a kind.
    private func at(_ site: Site, seed: UInt64 = 21) -> Expedition {
        var e = Expedition(seed: seed)
        e.teleport(to: e.island.sites.first { $0.site == site }!.cell)
        e.arrive()
        return e
    }

    @Test func theRightToolOpensTheDoor() {
        var e = at(.temple)
        #expect(e.visit?.stage == .door)
        #expect(e.visit?.canUseItems == true)
        e.party.inventory[Item(35)] = 1                  // a crowbar won't open a temple
        e.act(.use(Item(35)))
        #expect(e.visit?.said == ["USING YOUR CROWBAR DIDN'T HAVE ANY USEFUL EFFECT."])
        #expect(e.visit?.isInside == false)
        e.party.inventory[Item(2)] = 1                   // a lock pick will
        e.act(.use(Item(2)))
        #expect(e.visit?.said == ["YOU GOT IN. IT LOOKS DESERTED."])
        #expect(e.visit?.stage == .searching)
        #expect(e.visit?.isInside == true)
    }

    @Test func doorsAndTheirKeys() {
        for (site, keys) in [(Site.ruin, [11, 33]), (.castle, [37, 2]), (.tomb, [35, 8])] {
            for key in keys {
                var e = at(site)
                e.act(.use(Item(key)))
                #expect(e.visit?.isInside == true, "\(site) with \(Item(key))")
            }
        }
    }

    @Test func leavingTheDoorDoesNotSeal() {
        var e = at(.tomb)
        let cell = e.visit!.cell
        e.act(.leave)
        #expect(e.visit == nil)
        #expect(!e.island.isSealed(cell))
    }

    @Test func cannotWalkOffWhileInside() {
        var e = at(.castle)
        e.act(.use(Item(37)))
        let (x, y) = (e.x, e.y)
        let moved = e.walk(dx: 1, dy: 0, dt: 1)
        #expect(!moved)
        #expect(e.x == x && e.y == y)
    }

    @Test func walkingAwayFromADoorForgetsIt() {
        var e = at(.ruin)
        for _ in 0..<40 where e.visit != nil {
            e.walk(dx: 1, dy: 0.3, dt: 0.5)
            e.walk(dx: -0.3, dy: 1, dt: 0.5)
        }
        #expect(e.visit == nil || e.visit!.cell == e.cell)
    }

    @Test func hutSellsItsWares() {
        var bought = 0
        for seed in 0..<20 as Range<UInt64> {
            var e = at(.hut, seed: seed)
            e.party.gold = 1000
            e.act(.enter)
            guard case let .hutOffer(item, price) = e.visit?.stage else {
                Issue.record("no offer")
                continue
            }
            #expect((300..<600).contains(price))
            e.act(.accept)
            #expect(e.party.gold == 1000 - price)
            #expect(e.party.inventory[item] == 1)
            #expect(e.visit?.stage == .finished)
            let cell = e.visit!.cell
            e.act(.leave)
            #expect(e.island.isSealed(cell))
            let news = e.takeNews()
            #expect(news == ["THE ENTRANCE SEALED BEHIND YOU AS YOU LEFT."])
            bought += 1
        }
        #expect(bought == 20)
    }

    @Test func aPoorCustomerPaysWhatHeHas() {
        var outcomes = Set<String>()
        for seed in 0..<40 as Range<UInt64> {
            var e = at(.hut, seed: seed)
            e.party.gold = 250
            e.act(.enter)
            e.act(.accept)
            outcomes.insert(e.party.gold == 0 ? "paid all" : "turned away")
            #expect(e.party.gold == 0 || e.party.gold == 250)
        }
        #expect(outcomes == ["paid all", "turned away"])
    }

    @Test func aStrongPartyWins() {
        var rng = SeededRandom(seed: 4)
        var party = Party(rng: &rng)
        party.inventory[Item(26)] = 10                   // long bows
        party.inventory[Item(30)] = 10                   // plate mail
        party.strength = 10
        var b = Battle(monster: Monster(kind: 8), party: party, theyWereSurprised: true, surprise: 2, rng: &rng)
        for _ in 0..<50 where !b.isWon && !b.isLost { b.round(rng: &rng) }
        #expect(b.isWon)
        #expect(b.sizeUp.hasPrefix("THERE ARE \(b.theirNumber) OF THEM."))
    }

    /// Random play through hundreds of visits: every one ends, and nothing goes negative.
    @Test(arguments: [Site.temple, .ruin, .castle, .tomb])
    func randomVisitsEnd(site: Site) {
        var stages = Set<String>()
        for seed in 0..<150 as Range<UInt64> {
            var e = at(site, seed: seed)
            var pick = SeededRandom(seed: seed &* 31)
            e.party.inventory[Item(7)] = 1               // a rope for the pits
            e.act(.use(e.visit!.opens.first!))
            let cell = e.cell
            var steps = 0
            while let v = e.visit, steps < 200 {
                stages.insert("\(v.stage)".prefix { $0 != "(" }.description)
                var choices = v.actions
                if v.canUseItems { choices.append(.use(Item(7))) }
                e.act(choices[pick.rnd(choices.count)])
                #expect(e.party.men >= 0)
                #expect(e.party.gold >= 0)
                steps += 1
            }
            #expect(e.visit == nil, "visit to \(site) with seed \(seed) never ended")
            #expect(e.island.isSealed(cell) || e.isLost)
        }
        #expect(stages.isSuperset(of: ["searching", "altar", "chest", "pit", "battle", "spoils", "finished"]))
    }
}
