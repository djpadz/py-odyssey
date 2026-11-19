import Testing
@testable import OdysseyKit

struct RoadTests {
    /// An expedition with something met on the road before it.
    private func meeting(_ stage: Visit.Stage, seed: UInt64 = 7) -> Expedition {
        var e = Expedition(seed: seed)
        e.visit = Visit(cell: e.cell, stage: stage)
        return e
    }

    @Test func theRightThingFreesTrappedMen() {
        var rng = SeededRandom(seed: 1)
        let tree = Trap.springs(in: .jungle, rng: &rng)!
        var e = meeting(.trapped(tree, men: 3))
        e.party.men = 7
        #expect(e.visit?.holdsParty == true)
        #expect(e.visit?.question == "3 MEN WERE TRAPPED WHEN A ROTTEN TREE FELL ON THEM. WHAT DO YOU WANT TO DO?")
        e.act(.use(Item(7)))                             // a rope won't lift a tree
        #expect(e.visit?.said == ["USING YOUR ROPE DIDN'T HAVE ANY USEFUL EFFECT."])
        e.act(.use(Item(4)))                             // a machete will cut them free
        #expect(e.visit?.said.first?.hasPrefix("CONGRATULATIONS! YOU SAVED ") == true)
        #expect(e.party.men >= 9)
        e.act(.leave)
        #expect(e.visit == nil)
    }

    @Test func abandonedMenAreLost() {
        var rng = SeededRandom(seed: 1)
        var e = meeting(.trapped(Trap.springs(in: .mountains, rng: &rng)!, men: 2))
        e.party.men = 8
        e.act(.carryOn)
        #expect(e.visit == nil)                          // nothing to say: the panel closes
        #expect(e.party.men == 8)
    }

    @Test func trapsCatchAtLeastTwo() {
        for seed in 0..<40 as Range<UInt64> {
            var e = Expedition(seed: seed)
            let men = e.party.men
            e.visit = nil
            for _ in 0..<600 where e.visit == nil { e.roadEvent(heading: (1, 0)) }
            if case let .trapped(_, n) = e.visit?.stage {
                #expect(n >= 2)
                #expect(e.party.men == men - n)
            }
        }
    }

    @Test func anObstacleBarsTheWayUntilCleared() throws {
        var e = Expedition(seed: 11)
        e.roadEvents = false
        // Find a heading whose next cell is open land with no site.
        let (dx, dy) = try #require([(1.0, 0.0), (-1, 0), (0, 1), (0, -1)].first { d in
            let c = Cell(x: e.x + d.0 * Island.cellWidth, y: e.y + d.1 * Island.cellHeight)
            return e.island.terrain(c) != .ocean && e.island.site(c) == nil
        })
        let ahead = Cell(x: e.x + dx * Island.cellWidth, y: e.y + dy * Island.cellHeight)
        let thicket = Obstacle(kind: .thicket, words: "YOU'VE COME TO A DENSE THICKET, TOO TANGLED TO WALK THROUGH.",
                               clears: [Item(4), Item(22), Item(21)])
        e.island.bar(ahead, with: thicket)

        // Walking into it stops the party and says what is in the way.
        for _ in 0..<200 where e.visit == nil { e.walk(dx: dx, dy: dy, dt: 0.1) }
        #expect(e.cell != ahead)
        #expect(e.visit?.stage == .obstacle(thicket))
        #expect(e.visit?.holdsParty == false)

        // Turning away keeps it quiet, and it still bars the way.
        e.act(.leave)
        #expect(e.visit == nil)
        for _ in 0..<200 { e.walk(dx: dx, dy: dy, dt: 0.1) }
        #expect(e.visit == nil)
        #expect(e.cell != ahead)

        // A machete cuts through.
        e.visit = Visit(cell: ahead, stage: .obstacle(thicket))
        e.act(.use(Item(4)))
        #expect(e.visit?.said == ["CONTINUE WITH YOUR JOURNEY."])
        e.act(.leave)
        #expect(e.island.obstacles[ahead] == nil)
        for _ in 0..<200 where e.cell != ahead { e.walk(dx: dx, dy: dy, dt: 0.1) }
        #expect(e.cell == ahead)
    }

    @Test func caravanSellsOnTheRoad() {
        var e = meeting(.caravan)
        e.act(.buy)
        #expect(e.visit == nil)
        #expect(e.market?.isCaravan == true)
        #expect(e.market?.lots.contains { $0.item == .ship } == false)
    }

    @Test func mercenariesJoinWithSwords() {
        var joined = 0
        for seed in 0..<30 as Range<UInt64> {
            var e = meeting(.warriors, seed: seed)
            let men = e.party.men
            e.act(.beFriendly)
            #expect(e.party.alignment == 2)
            if e.visit?.stage == .finished {
                let n = e.party.men - men
                #expect(n >= e.party.charisma)
                #expect(e.party.inventory[Item(22)] == n)
                joined += 1
            } else {
                guard case .battle = e.visit?.stage else {
                    Issue.record("friendly warriors neither joined nor attacked")
                    continue
                }
                #expect(e.visit?.said.contains("THEY ARE BANDITS!!!") == true)
            }
        }
        #expect(joined > 10)
    }

    @Test func wizardsAidTheLikeMinded() {
        var e = meeting(.wizard(good: true))
        e.party.alignment = 4
        e.act(.requestAid)
        #expect(e.visit?.said.first?.hasPrefix("HE GAVE YOU A ") == true)
        #expect(e.party.inventory.keys.contains { (39...46).contains($0.id) })

        var w = meeting(.wizard(good: false))
        w.party.alignment = 4
        w.act(.requestAid)
        #expect(w.visit?.said.first == "HE DOESN'T LIKE YOUR STYLE. HE'S COMMANDING HIS MEN TO ATTACK.")
        guard case let .battle(b) = w.visit?.stage else {
            Issue.record("the warlock didn't attack")
            return
        }
        #expect(b.foe == .warlocks)
    }

    @Test func beatingACaravanLeavesItsGoods() {
        for seed in 0..<40 as Range<UInt64> {
            var e = meeting(.caravan, seed: seed)
            e.party.men = 60                             // an army
            e.party.strength = 12
            e.party.inventory[Item(30)] = 60
            e.act(.attack)
            #expect(e.party.alignment == -5)
            for _ in 0..<50 {
                guard case .battle = e.visit?.stage else { break }
                e.act(.fight)
            }
            if e.visit?.stage == .finished {
                #expect(e.visit?.said.contains("CONGRATULATIONS, YOU KILLED ALL OF THE MERCHANT'S MEN.") == true)
                return
            }
        }
        Issue.record("never beat a caravan")
    }

    /// Long walks with random answers: every encounter ends, nothing goes negative,
    /// and everything the road holds turns up.
    @Test func randomRoadsEnd() {
        var stages = Set<String>()
        for seed in 0..<60 as Range<UInt64> {
            var e = Expedition(seed: seed)
            e.party.foodPacks = 500
            e.party.inventory[Item(7)] = 1
            var pick = SeededRandom(seed: seed &* 17)
            var heading = (dx: 1.0, dy: 0.0)
            for _ in 0..<3000 where !e.isLost {
                if e.market != nil { e.leaveMarket() }
                if let v = e.visit, v.holdsParty || pick.rnd(4) == 0 {
                    stages.insert("\(v.stage)".prefix { $0 != "(" }.description)
                    var choices = v.actions
                    if v.canUseItems { choices.append(.use(Item(7))) }
                    e.act(choices[pick.rnd(choices.count)])
                } else if !e.walk(dx: heading.dx, dy: heading.dy, dt: 0.3) || pick.rnd(30) == 0 {
                    let d = Island.compass[pick.rnd(8)]
                    heading = (Double(d.dc), Double(d.dr))
                }
                #expect(e.party.men >= 0)
                #expect(e.party.gold >= 0)
                #expect(e.party.foodPacks >= 0)
            }
            #expect(e.isLost || !(e.visit?.holdsParty ?? false) || e.visit?.site != nil)
        }
        #expect(stages.isSuperset(of: ["caravan", "wizard", "warriors", "trapped", "obstacle",
                                       "monstersAhead", "battle", "spoils", "finished"]))
    }
}
