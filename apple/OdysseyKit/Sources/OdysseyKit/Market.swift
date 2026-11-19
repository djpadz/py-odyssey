/// A city bazaar (lines 1500-1598 of ISLAND APVENTURE).
public struct Market: Sendable {
    public struct Lot: Sendable, Identifiable {
        public let id: Int                   // the number on the price board, from 1
        public let item: Item
        public var price: Int
        public var quantity: Int
        /// Withdrawn after an insulting offer.
        public var withdrawn = false
    }

    public private(set) var lots: [Lot]
    /// A caravan met on the road rather than a city's bazaar.
    public internal(set) var isCaravan = false
    /// Merchantmen met at sea.
    public internal(set) var isAtSea = false

    /// Stock a market (1500-1515): food always, the ship at the ship city, then
    /// whatever else the caravans brought in.
    init(sellsShip: Bool, men: Int, rng: inout SeededRandom) {
        var lots = [Lot(id: 1, item: .foodPack, price: 10 + rng.rnd(5), quantity: 5 + men / 2 + rng.rnd(30))]
        if sellsShip {
            lots.append(Lot(id: 2, item: .ship, price: 2400 + rng.rnd(300), quantity: 1))
        }
        for _ in lots.count..<13 {
            let m = rng.rnd(36) - 5
            guard m >= 1, !lots.contains(where: { $0.item.id == m }) else { continue }
            let quantity = m == Item.contract.id ? 1 + rng.rnd(4) : 5 + rng.rnd(20)
            let item = Item(m)
            lots.append(Lot(id: lots.count + 1, item: item, price: item.listPrice + rng.rnd(20), quantity: quantity))
        }
        self.lots = lots
    }

    /// The merchantmen's stock (1500-1515 of SEA APVENTURE): more food, and no
    /// contracts or ships.
    init(atSeaWith men: Int, rng: inout SeededRandom) {
        var lots = [Lot(id: 1, item: .foodPack, price: 10 + rng.rnd(5), quantity: 15 + rng.rnd(30))]
        for _ in 2...13 {
            let m = rng.rnd(36) - 5
            guard m >= 1, m != Item.contract.id, !lots.contains(where: { $0.item.id == m }) else { continue }
            let item = Item(m)
            lots.append(Lot(id: lots.count + 1, item: item, price: item.listPrice + rng.rnd(20), quantity: 5 + rng.rnd(20)))
        }
        self.lots = lots
        isAtSea = true
    }

    public subscript(id: Int) -> Lot {
        get { lots[id - 1] }
        set { lots[id - 1] = newValue }
    }
}

/// The merchant's answer to an offer.
public enum Reply: Sendable, Equatable {
    /// The offer stands: buy at this price.
    case accepted(price: Int)
    /// A counter-offer; answer yes to buy at `price`, or make another offer.
    case counter(price: Int, words: String)
    /// Haggling is over and the price goes back to normal.
    case broken(words: String)
    /// The item has been withdrawn from sale.
    case insulted(words: String)
}

public enum Purchase: Sendable, Equatable {
    case sold
    case notEnoughGold
    case onlyHave(Int)
    case tooHeavy(canCarry: Int)
}

/// Bargaining for one lot. `lastOffer` is the original's Z7.
public struct Haggle: Sendable {
    public let lot: Int
    var lastOffer = 1

    public init(lot: Int) { self.lot = lot }
}

extension Expedition {
    /// Walk into the bazaar at the city here.
    public mutating func enterMarket() {
        market = Market(sellsShip: cell == Island.shipCity, men: party.men, rng: &rng)
    }

    public mutating func leaveMarket() {
        market = nil
    }

    /// Lines 1561-1585: make an offer for a lot.
    public mutating func offer(_ amount: Int, in haggle: inout Haggle) -> Reply {
        guard var market else { return .broken(words: "") }
        defer { self.market = market }
        var lot = market[haggle.lot]
        defer { market[haggle.lot] = lot }
        let list = lot.item.listPrice
        if amount >= lot.price - 1 {
            return .accepted(price: amount)
        }
        if amount < haggle.lastOffer || (amount == haggle.lastOffer && rng.rnd(2) == 1) {
            let words = "YOU OFFERED \(haggle.lastOffer) LAST TIME. LET'S JUST FORGET THE WHOLE THING."
            lot.price = list + rng.rnd(5)
            return .broken(words: words)
        }
        haggle.lastOffer = amount
        // (The original compares against the list price of the item numbered like the
        // lot, AP(I); this uses the lot's own item.)
        if !(amount >= list || rng.rnd(3) != 0) {
            lot.price = list + rng.rnd(5)
            return .broken(words: "NOT INTERESTED.")
        }
        if amount < list / 2 && rng.rnd(3) != 0 {
            lot.withdrawn = true
            return .insulted(words: "YOUR OFFER IS AN INSULT! THAT ITEM IS NO LONGER FOR SALE.")
        }
        let asking = lot.price
        var cut = (asking - amount) / 3 + 1
        if asking < list - 10 { cut = (asking - amount) / 5 + 1 }
        if cut > asking / 10 { cut = asking / 10 + 1 }
        lot.price = asking - cut
        let p = lot.price
        let words = switch rng.rnd(4) {
        case 0: "YOU MUST BE JESTING, M'LORD. I COULDN'T CONSIDER SELLING FOR LESS THAN \(p). WHAT DO YOU SAY?"
        case 1: "I PAID MORE FOR IT MYSELF SIRE. HOW ABOUT MAKING IT \(p)?"
        case 2: "YOU LOOK LIKE A GOOD SORT SIR. I'LL TELL YOU WHAT. I'LL MAKE IT \(p) JUST FOR YOU. WHAT DO YOU SAY?"
        default: "IT WOULD BE A STEAL AT \(p) QUADROONS. I CAN AFFORD NO LESS. DO YOU WANT IT OR NOT?"
        }
        return .counter(price: p, words: words)
    }

    /// Lines 1564-1590: buy `quantity` of a lot at the agreed price.
    public mutating func buy(lot id: Int, quantity: Int, at price: Int) -> Purchase {
        guard var market else { return .notEnoughGold }
        var lot = market[id]
        if quantity > lot.quantity { return .onlyHave(lot.quantity) }
        if price * quantity > party.gold { return .notEnoughGold }
        // The original sells anything and then makes you dump the excess; here the men refuse.
        // (Quadroons weigh 1 apiece, so paying lightens the load.)
        let change = lot.item.weight * quantity - price * quantity
        if lot.item != .contract, party.load + change > party.capacity {
            return .tooHeavy(canCarry: party.capacity - party.load)
        }
        lot.quantity -= quantity
        lot.price = lot.item.listPrice + rng.rnd(5)
        market[id] = lot
        self.market = market
        party.gold -= price * quantity
        if lot.item == .contract {
            party.men += quantity
        } else {
            party.inventory[lot.item, default: 0] += quantity
        }
        if lot.item == .foodPack { hungryRations = 0 }
        return .sold
    }
}
