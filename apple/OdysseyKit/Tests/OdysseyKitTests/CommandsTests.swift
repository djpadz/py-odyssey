import Testing
@testable import OdysseyKit

struct CommandsTests {
    private func quiet(_ seed: UInt64 = 9) -> Expedition {
        var e = Expedition(seed: seed)
        e.roadEvents = false
        return e
    }

    @Test func dropAndGetAgain() {
        var e = quiet()
        e.party.inventory[Item(33)] = 3
        let r317 = e.get()
        #expect(r317 == "OK, YOU GOT TWO HANDFULS OF MUD. NOW WHAT?")
        let d414 = e.drop(Item(33), quantity: 2)
        #expect(d414)
        #expect(e.party.inventory[Item(33)] == 1)
        #expect(e.describe().hasSuffix("YOU CAN SEE 2 TORCHES HERE."))
        #expect(e.room(for: Item(7)) == 0)                 // the ground holds one kind of thing
        let d679 = e.drop(Item(7), quantity: 1)
        #expect(!d679)
        let d726 = e.drop(Item(33), quantity: 1)             // ...but takes more of the same
        #expect(d726)
        let r794 = e.get()
        #expect(r794 == "OK, YOU GOT 3 TORCHES. NOW WHAT?")
        #expect(e.party.inventory[Item(33)] == 3)
        #expect(e.island.lying(e.cell) == nil)
    }

    @Test func nothingDropsAtASite() {
        var e = quiet()
        e.teleport(to: e.island.sites.first { $0.site == .temple }!.cell)
        e.party.inventory[Item(33)] = 3
        #expect(e.room(for: Item(33)) == 0)
        let d1230 = e.drop(Item(33), quantity: 1)
        #expect(!d1230)
    }

    @Test func thingsTurnUp() {
        var e = quiet()
        for _ in 0..<500 where e.island.lying(e.cell) == nil { e.turnUpSomething() }
        let found = e.island.lying(e.cell)
        #expect(found?.quantity == 1)
        #expect((31...37).contains(found?.item.id ?? 0))
    }

    @Test func ridingNeedsHorsesAndEatsNothing() {
        var e = quiet()
        let r1598 = e.ride()
        #expect(r1598 == "NOT ENOUGH HORSES")
        e.party.inventory[Item(20)] = 5                     // one for every two of ten men
        let r1739 = e.ride()
        #expect(r1739 == nil)
        #expect(e.mount == .horses)
        let food = e.party.foodPacks
        for _ in 0..<300 {
            e.walk(dx: 0.3, dy: 0.2, dt: 0.1)
            e.walk(dx: -0.3, dy: -0.2, dt: 0.1)
        }
        #expect(e.party.foodPacks == food)
        let r2019 = e.halt()
        #expect(r2019 == nil)
        #expect(e.mount == nil)
        let r2084 = e.halt()
        #expect(r2084 == "YOU ARE HALTED.")
    }

    @Test func ridingIntoTheSeaDrownsHorses() {
        var e = quiet(5)
        e.party.inventory[Item(20)] = 6
        _ = e.ride()
        for _ in 0..<2000 where e.mount != nil { e.walk(dx: 0, dy: -1, dt: 0.05) }
        #expect(e.mount == nil)
        #expect(e.party.inventory[Item(20)] == 4)
        #expect(e.takeNews() == ["NOT ONE OF YOUR BETTER MOVES, SIRE. YOU DROWNED 2 HORSES."])
        #expect(e.terrain != .ocean)
    }

    @Test func theRugFliesOverWater() {
        var e = quiet(5)
        e.party.inventory[Item(45)] = 1
        e.use(Item(45))
        #expect(e.mount == .rug)
        #expect(e.party.inventory[Item(45)] == 1)           // not used up
        for _ in 0..<400 where e.terrain != .ocean { e.walk(dx: 0, dy: -1, dt: 0.05) }
        #expect(e.terrain == .ocean)
        let r2937 = e.halt()
        #expect(r2937?.hasPrefix("I AM SORRY, MY LIEGE.") == true)
        #expect(e.mount == .rug)
        for _ in 0..<400 where e.terrain == .ocean { e.walk(dx: 0, dy: 1, dt: 0.05) }
        let r3126 = e.halt()
        #expect(r3126 == nil)
    }

    @Test func theAmuletRestoresStrength() {
        var e = quiet()
        e.party.inventory[Item(39)] = 1
        e.party.strength = 1
        e.use(Item(39))
        #expect(e.visit?.stage == .amulet)
        e.act(.accept)
        #expect(e.visit == nil)
        #expect(e.party.strength == e.party.rolledStrength)
        #expect(e.party.inventory[Item(39)] == 0)
    }

    @Test func theStaffRaisesOrBlowsUp() {
        var raised = 0, blown = 0
        for seed in 0..<40 as Range<UInt64> {
            var e = quiet(seed)
            e.party.inventory[Item(47)] = 1
            let wisdom = e.party.wisdom
            e.use(Item(47))
            if e.visit?.stage == .charm(Item(47)) {
                e.act(.increaseWisdom)
                #expect(e.party.wisdom == wisdom + 3)
                raised += 1
            } else {
                #expect(e.visit?.said.first?.hasPrefix("IT BLEW UP!!!") == true)
                blown += 1
            }
            #expect(e.party.inventory[Item(47)] == 0)
        }
        #expect(raised > 0 && blown > 0)
    }

    @Test func theScrollNeedsWisdom() {
        var e = quiet()
        e.party.inventory[Item(40)] = 1
        e.party.wisdom = 4
        e.use(Item(40))
        #expect(e.visit?.said.last == "YOU CAN'T FIGURE OUT WHAT IT SAYS.")
        #expect(e.party.inventory[Item(40)] == 1)
        e.act(.leave)
        e.party.wisdom = 9
        let gold = e.party.gold
        e.use(Item(40))
        #expect(e.party.gold == gold + 2000)
        #expect(e.party.inventory[Item(40)] == 0)
    }

    @Test func ordinaryThingsDoNothingOnTheRoad() {
        var e = quiet()
        e.party.inventory[Item(7)] = 1
        e.use(Item(7))
        #expect(e.visit?.said == ["USING YOUR ROPE DIDN'T HAVE ANY USEFUL EFFECT."])
        e.act(.leave)
        #expect(e.visit == nil)
    }

    @Test func theMapRemembersSitesSeen() {
        let e = quiet()
        let near = e.island.sites.filter { abs($0.cell.col - e.cell.col) <= 1 && abs($0.cell.row - e.cell.row) <= 1 }
        #expect(!near.isEmpty)                               // the party starts beside a city
        #expect(near.allSatisfy { e.seen.contains($0.cell) })
        #expect(e.seen.count == near.count)
    }
}
