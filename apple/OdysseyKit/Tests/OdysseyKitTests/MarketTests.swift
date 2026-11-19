import Testing
@testable import OdysseyKit

struct MarketTests {
    /// An expedition standing in a city's market.
    private func atMarket(seed: UInt64 = 11, shipCity: Bool = false) -> Expedition {
        var e = Expedition(seed: seed)
        let city = shipCity ? Island.shipCity : e.island.sites.first { $0.site == .city && $0.cell != Island.shipCity }!.cell
        e.teleport(to: city)
        e.enterMarket()
        return e
    }

    @Test func itemTable() {
        #expect(Item.foodPack.name == "FOOD PACK")
        #expect(Item(33).name(quantity: 2) == "TORCHES")
        #expect(Item(22).name(quantity: 3) == "BROADSWORDS")
        #expect(Item(22).name(quantity: 1) == "BROADSWORD")
        #expect(Item.ship.listPrice == 2500)
        #expect(Item(30).weight == 150)
    }

    @Test(arguments: 0..<30 as Range<UInt64>)
    func stock(seed: UInt64) {
        let e = atMarket(seed: seed)
        let lots = e.market!.lots
        #expect(lots[0].item == .foodPack)
        #expect((10...14).contains(lots[0].price))
        #expect(!lots.contains { $0.item == .ship })
        #expect(Set(lots.map(\.item)).count == lots.count)
        #expect(lots.allSatisfy { (1...30).contains($0.item.id) })
        #expect(lots.map(\.id) == Array(1...lots.count))
    }

    @Test func shipCitySellsTheShip() {
        let lot = atMarket(shipCity: true).market![2]
        #expect(lot.item == .ship)
        #expect((2400..<2700).contains(lot.price))
        #expect(lot.quantity == 1)
    }

    @Test func fullPriceIsAccepted() {
        var e = atMarket()
        var h = Haggle(lot: 1)
        let price = e.market![1].price
        #expect(e.offer(price - 1, in: &h) == .accepted(price: price - 1))
    }

    @Test func haggling() {
        // Over many quests, low offers draw every kind of answer, and counters come down.
        var seen = Set<String>()
        for seed in 0..<200 as Range<UInt64> {
            var e = atMarket(seed: seed)
            let lot = e.market!.lots.first { $0.item.listPrice >= 20 }!.id
            var h = Haggle(lot: lot)
            let asking = e.market![lot].price
            switch e.offer(4, in: &h) {
            case .accepted: Issue.record("accepted a lowball")
            case let .counter(price, words):
                #expect(price < asking && price > 4)
                #expect(words.contains("\(price)"))
                seen.insert("counter")
                if case .broken = e.offer(3, in: &h) { seen.insert("forget") }
            case .broken: seen.insert("broken")
            case .insulted:
                #expect(e.market![lot].withdrawn)
                seen.insert("insulted")
            }
        }
        #expect(seen == ["counter", "forget", "broken", "insulted"])
    }

    @Test func buyingFoodAndMen() {
        var e = atMarket()
        let gold = e.party.gold, food = e.party.foodPacks
        #expect(e.buy(lot: 1, quantity: 3, at: 12) == .sold)
        #expect(e.party.gold == gold - 36)
        #expect(e.party.foodPacks == food + 3)
        #expect(e.buy(lot: 1, quantity: 1000, at: 12) == .onlyHave(e.market![1].quantity))
        #expect(e.buy(lot: 1, quantity: 5, at: 100_000) == .notEnoughGold)

        if let contract = e.market!.lots.first(where: { $0.item == .contract }) {
            #expect(e.buy(lot: contract.id, quantity: 1, at: 1) == .sold)
            #expect(e.party.men == 11)
        }
    }

    @Test func menRefuseTooMuch() {
        var e = atMarket(seed: 3)
        e.party.men = 1                                  // can carry 250; the gold alone weighs more
        #expect(e.buy(lot: 1, quantity: 1, at: 1) == .tooHeavy(canCarry: 250 - e.party.load))
    }

    @Test func eatingAndStarving() {
        var e = Expedition(seed: 2)
        e.party.foodPacks = 2
        for _ in 0..<10 { e.passTurn() }                  // two rations
        #expect(e.party.foodPacks == 0)
        #expect(e.foodWarning == "YOU ARE OUT OF FOOD")
        for _ in 0..<10 { e.passTurn() }
        #expect(e.party.men == 9)
        #expect(e.takeNews() == ["A MAN STARVED TODAY."])
        #expect(e.takeNews().isEmpty)
    }
}
