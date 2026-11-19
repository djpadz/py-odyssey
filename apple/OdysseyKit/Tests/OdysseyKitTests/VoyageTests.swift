import Foundation
import Testing
@testable import OdysseyKit

struct VoyageTests {
    /// An expedition just put to sea.
    private func atSea(_ seed: UInt64 = 3, events: Bool = false) -> Expedition {
        var e = Expedition(seed: seed)
        e.roadEvents = events
        e.party.men = 20
        e.party.inventory[.ship] = 1
        e.party.inventory[Item(15)] = 1                  // a compass, so the sails go where they're set
        e.embark()
        return e
    }

    @Test func theShipSailsFromItsCityWithFifteenMen() {
        var e = Expedition(seed: 3)
        e.party.inventory[.ship] = 1
        e.use(.ship)
        #expect(e.visit?.said.first?.hasPrefix("YOU OWN THE SHIP, BUT IT IS DOCKED") == true)
        e.act(.leave)
        e.teleport(to: Island.shipCity)
        e.visit = nil
        e.use(.ship)
        #expect(e.visit?.said == ["YOU DON'T HAVE ENOUGH MEN TO MAN SUCH A SHIP. IT REQUIRES AT LEAST 15."])
        e.act(.leave)
        e.visit = nil
        e.party.men = 15
        e.use(.ship)
        #expect(e.visit?.stage == .readyToSail)
        e.act(.accept)
        #expect(e.visit == nil)
        let v = try! #require(e.voyage)
        #expect(v.x == 205 && v.y == 117)
        #expect(v.anchored && v.sails == nil && v.wind == 3)
        #expect(!Expedition.aground(x: v.x, y: v.y))
    }

    @Test func theChartHasLandReefsAndCurrents() {
        #expect(SeaChart.ground(x: 205, y: 124) == .land)
        #expect(SeaChart.ground(x: 205, y: 117) == .sea)
        #expect(SeaChart.ground(x: 30, y: 130) == .sea)               // the compass rose is no rock
        #expect(SeaChart.ground(x: -5, y: 40) == .sea)
        let w = SeaChart.water(x: 140, y: 80)
        #expect(w != nil && w!.depth > 20)
    }

    @Test func noSailingIntoTheWind() {
        var e = atSea()
        e.command(.setSails(3))                                       // the wind is out of the SE
        #expect(e.voyage?.said == ["THE WIND IS OUT OF THE SE.", "YOU CANNOT SAIL TO THE SE."])
        e.command(.setSails(4))
        #expect(e.voyage?.sails == nil)
        e.command(.setSails(7))
        #expect(e.voyage?.sails == 7)
        #expect(e.voyage?.underSail == true)
    }

    @Test func underSailAPixelAThirdOfAPoll() {
        var e = atSea()
        e.command(.setSails(6))                                       // west, the wind on the quarter
        e.command(.anchor)
        #expect(e.voyage?.anchored == false)
        for _ in 0..<20 { e.sail(dt: 0.1) }                           // two seconds
        #expect(e.voyage?.x == 195)
        #expect(e.voyage?.y == 117)
    }

    @Test func theAnchorReachesOnlyTwentyFathoms() {
        var e = atSea()
        e.voyage!.x = 140
        e.voyage!.y = 80
        e.voyage!.anchored = false
        e.command(.anchor)
        #expect(e.voyage?.said.first?.hasPrefix("SOUNDINGS INDICATE DEPTH IS") == true)
        #expect(e.voyage?.anchored == false)
    }

    @Test func agroundAndPulledOff() {
        var e = atSea()
        e.voyage!.wind = 0                                            // out of the north
        e.command(.setSails(4))
        e.command(.anchor)
        for _ in 0..<60 where e.voyage?.happening != .aground { e.sail(dt: 0.1) }
        let v = try! #require(e.voyage)
        #expect(v.happening == .aground)
        #expect(v.anchored)
        #expect(v.said.last == "SOME LOCAL FISHERMEN WILL HELP PULL YOU FREE IF YOU PAY THEM. WHAT WILL YOU DO?")
        e.useAtSea(.quadroon)
        #expect(e.voyage?.question == .fishermen)
        let gold = e.party.gold
        e.pay(1)
        #expect(e.voyage?.happening == .aground)                      // a joke of an offer
        e.useAtSea(.quadroon)
        e.pay(200)
        #expect(e.voyage?.happening == nil)
        #expect(e.party.gold == gold - 200)
        #expect(!Expedition.aground(x: e.voyage!.x, y: e.voyage!.y))
    }

    @Test func overTheEdgeAndBack() {
        var e = atSea()
        e.voyage!.x = 20
        e.voyage!.y = 90
        e.voyage!.wind = 2                                            // out of the east
        e.command(.setSails(6))
        e.command(.anchor)
        for _ in 0..<100 where e.voyage?.lost == false { e.sail(dt: 0.1) }
        #expect(e.voyage?.lost == true)
        #expect(e.voyage?.said.contains { $0.hasPrefix("DANGER!") } == true)
        e.recoverShip()
        #expect(e.voyage?.lost == false)
        #expect(e.voyage?.x == 150 && e.voyage?.y == 80)
    }

    @Test func argorionShowsTheWayToTheOrb() {
        var e = atSea()
        e.voyage!.happening = .argorion
        e.party.inventory[Item(33)] = 1
        e.putOver(Item(33), quantity: 1)
        let orb = try! #require(e.voyage?.orbAt)
        #expect(e.voyage?.said.first?.hasPrefix("A RARE TREASURE CAN BE FOUND ON THE SEA FLOOR AT LATITUDE \(orb.y)") == true)
        #expect(!Expedition.aground(x: orb.x, y: orb.y))
        e.voyage!.x = orb.x + 1
        e.voyage!.y = orb.y + 1
        e.command(.divers)
        #expect(e.hasOrb)
        #expect(e.voyage?.orbAt == nil)
    }

    @Test func piratesWantHalfAtLeast() {
        var e = atSea()
        e.party.gold = 1000
        e.voyage!.happening = .pirates
        e.putOver(.quadroon, quantity: 100)
        #expect(e.voyage?.said == ["THEY'RE LAUGHING CAPTAIN. I DON'T THINK THEY WERE FOOLED. WHAT SHALL WE DO?"])
        #expect(e.party.gold == 1000)
        e.putOver(.quadroon, quantity: 600)
        #expect(e.party.gold == 400)
        #expect(e.voyage?.happening == nil)
    }

    @Test func theWizardTakesMagic() {
        var e = atSea()
        e.voyage!.happening = .temple
        e.party.inventory[Item(33)] = 1
        e.party.inventory[Item(47)] = 1
        e.command(.setSails(6))                                       // nothing but his choices here
        #expect(e.voyage?.sails == nil)
        e.useAtSea(Item(47))
        #expect(e.voyage?.said == ["OK, YOU USED YOUR STAFF. YOU STILL CAN'T GET IN. NOW WHAT?"])
        e.useAtSea(Item(33), offering: true)
        #expect(e.voyage?.said.last == "HE STILL WON'T LET YOU IN THOUGH. WHAT NOW?")
        e.useAtSea(Item(47), offering: true)
        #expect(e.voyage?.ashore == .catacombs)
        e.returnToShip()
        #expect(e.voyage?.ashore == nil)
    }

    @Test func aVoyageSavesAndComesBack() throws {
        var e = atSea()
        e.voyage!.happening = .flyers(Monster(kind: 18))
        e.voyage!.orbAt = (120, 70)
        e.hasOrb = false
        let back = try JSONDecoder().decode(Expedition.self, from: JSONEncoder().encode(e))
        #expect(back.voyage?.happening == .flyers(Monster(kind: 18)))
        #expect(back.voyage?.orbAt?.x == 120)
        #expect(back.voyage?.x == e.voyage?.x)
    }

    /// Long voyages with random orders: nothing goes negative, everything is met.
    @Test func randomVoyages() {
        var seenHappenings = Set<String>(), seenQuestions = Set<String>()
        for seed in 0..<80 as Range<UInt64> {
            var e = atSea(seed, events: true)
            e.party.inventory[Item(14)] = 30
            e.party.inventory[Item(19)] = 2
            e.party.inventory[Item(47)] = 1
            var pick = SeededRandom(seed: seed &* 7)
            for _ in 0..<1500 where !e.isLost {
                guard var v = e.voyage else { break }
                if let h = v.happening { seenHappenings.insert("\(h)".prefix { $0 != "(" }.description) }
                if e.market != nil { e.leaveMarket(); continue }
                if v.lost { e.recoverShip(); continue }
                if v.ashore != nil { e.returnToShip(); continue }
                if let q = v.question {
                    seenQuestions.insert("\(q)".prefix { $0 != "(" }.description)
                    if q == .fishermen { e.pay(pick.rnd(400)) } else { e.answer(q.answers[pick.rnd(q.answers.count)]) }
                    continue
                }
                if v.happening == .temple {
                    pick.rnd(2) == 0 ? e.templeLeave() : e.templeAttack()
                    continue
                }
                switch pick.rnd(12) {
                case 0: e.command(.anchor)
                case 1: e.command(.setSails(pick.rnd(8)))
                case 2: e.command(.fire)
                case 3: e.command(.land)
                case 4: e.command(.divers)
                case 5: e.command(.hail)
                case 6: e.useAtSea([Item(14), Item(19), .quadroon, Item(47)][pick.rnd(4)])
                case 7: e.putOver(.quadroon, quantity: max(e.party.gold / 2, 1))
                default:
                    if v.anchored && v.happening == nil { e.command(.anchor) }
                    if v.sails == nil, let w = v.wind { e.command(.setSails((w + 4) % 8)) }
                    e.sail(dt: 0.5)
                }
                v = e.voyage ?? v
                #expect(e.party.men >= 0)
                #expect(e.party.gold >= 0)
                #expect(e.party.inventory.values.allSatisfy { $0 >= 0 })
            }
        }
        #expect(seenHappenings.isSuperset(of: ["ships", "fog", "pirates", "storm", "whirlpool", "flyers", "seaMonster",
                                               "aground"]))
        #expect(seenQuestions.isSuperset(of: ["merchants", "raft", "raftChest", "hail", "fishermen"]))
    }
}
