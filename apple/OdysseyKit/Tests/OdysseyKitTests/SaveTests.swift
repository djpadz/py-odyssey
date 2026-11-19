import Foundation
import Testing
@testable import OdysseyKit

struct SaveTests {
    private func roundTrip(_ e: Expedition) throws -> Expedition {
        try JSONDecoder().decode(Expedition.self, from: JSONEncoder().encode(e))
    }

    private func json(_ e: Expedition) throws -> String {
        String(decoding: try JSONEncoder().encode(e), as: UTF8.self)
    }

    /// Whether two quests stand the same. (Their JSON may differ: dictionaries and sets
    /// encode in hash order.)
    private func same(_ a: Expedition, _ b: Expedition) -> Bool {
        var ra = a.rng, rb = b.rng
        let p = a.party, q = b.party
        return a.x == b.x && a.y == b.y && a.island.lc == b.island.lc && a.island.obstacles == b.island.obstacles
            && a.seen == b.seen && a.mount == b.mount && a.hungryRations == b.hungryRations && ra.next() == rb.next()
            && p.inventory == q.inventory && p.men == q.men && p.strength == q.strength && p.charisma == q.charisma
            && p.wisdom == q.wisdom && p.speed == q.speed && p.experience == q.experience && p.alignment == q.alignment
    }

    /// A quest some way along: walked, things dropped, a site sealed, an obstacle met.
    private func underway() -> Expedition {
        var e = Expedition(seed: 31)
        e.roadEvents = false
        for _ in 0..<200 { e.walk(dx: 0.7, dy: 0.4, dt: 0.1) }
        e.roadEvents = true
        e.visit = nil
        e.teleport(to: e.island.allCells.first { e.island.isBare($0) && e.island.terrain($0) != .ocean }!)
        e.party.inventory[Item(33)] = 2
        e.drop(Item(33), quantity: 1)
        e.island.seal(e.island.sites.first { $0.site == .tomb }!.cell)
        e.island.bar(Cell(col: 10, row: 10), with: Obstacle(kind: .bog, words: "BOG.", clears: [Item(3)]))
        e.seen.insert(Cell(col: 10, row: 10))
        e.party.alignment = -4
        e.party.wisdom += 3
        e.hungryRations = 2
        return e
    }

    @Test func aQuestComesBackAsItWas() throws {
        let e = underway()
        let back = try roundTrip(e)
        #expect(same(back, e))
        #expect(back.x == e.x && back.y == e.y)
        #expect(back.party.inventory == e.party.inventory)
        #expect(back.party.rolledStrength == e.party.rolledStrength)
        #expect(back.island.lying(e.cell)?.item == Item(33))
        #expect(back.island.obstacles[Cell(col: 10, row: 10)]?.kind == .bog)
        #expect(back.seen == e.seen)
        #expect(back.island.start == e.island.start)
    }

    @Test func aResumedQuestPlaysOnTheSame() throws {
        var a = underway()
        var b = try roundTrip(a)
        for i in 0..<400 {
            let d = Island.compass[(i / 40) % 8]
            a.walk(dx: Double(d.dc), dy: Double(d.dr), dt: 0.2)
            b.walk(dx: Double(d.dc), dy: Double(d.dr), dt: 0.2)
            if a.visit?.holdsParty == true { a.act(a.visit!.actions[0]); b.act(b.visit!.actions[0]) }
            if a.market != nil { a.leaveMarket(); b.leaveMarket() }
        }
        #expect(a.x == b.x && a.y == b.y)
        #expect(same(a, b))
    }

    @Test func resumingAtADoorStepsUpToIt() throws {
        var e = Expedition(seed: 21)
        e.teleport(to: e.island.sites.first { $0.site == .castle }!.cell)
        e.arrive()
        var back = try roundTrip(e)
        #expect(back.visit == nil)
        back.resume()
        #expect(back.visit?.stage == .door)
    }

    @Test func aDamagedSaveIsRefused() throws {
        let text = try json(Expedition(seed: 1))
        let shortMap = text.replacingOccurrences(of: "\"lc\":[0,", with: "\"lc\":[")
        #expect(throws: DecodingError.self) { try JSONDecoder().decode(Expedition.self, from: Data(shortMap.utf8)) }
        let badItem = text.replacingOccurrences(of: "\"inventory\":[", with: "\"inventory\":[77,1,")
        #expect(throws: DecodingError.self) { try JSONDecoder().decode(Expedition.self, from: Data(badItem.utf8)) }
    }
}
