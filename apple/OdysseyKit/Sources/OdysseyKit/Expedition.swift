/// The adventurer and the men who follow (rolled as in HAIL, lines 32-33).
public struct Party: Sendable {
    public var men = 10
    /// What the party carries, food and quadroons included (the original's BG/BQ).
    public var inventory: [Item: Int]
    public let charisma: Int
    public let dexterity: Int
    public let strength: Int
    public let wisdom: Int
    public let morale: Int

    public init(rng: inout SeededRandom) {
        charisma = rng.rnd(9) + 2
        dexterity = 5 + rng.rnd(4)
        wisdom = 5 + rng.rnd(5)
        morale = 5 + rng.rnd(5)
        inventory = [.foodPack: 15, .quadroon: 900 + rng.rnd(300)]
        strength = rng.rnd(8) + 3
    }

    public var foodPacks: Int {
        get { inventory[.foodPack] ?? 0 }
        set { inventory[.foodPack] = newValue }
    }

    public var gold: Int {
        get { inventory[.quadroon] ?? 0 }
        set { inventory[.quadroon] = newValue }
    }

    /// Everything but food and gold, in the original's item order.
    public var belongings: [(item: Item, quantity: Int)] {
        inventory.filter { $0.key != .foodPack && $0.key != .quadroon && $0.value > 0 }
            .sorted { $0.key < $1.key }
            .map { ($0.key, $0.value) }
    }

    /// Total weight carried (line 960) and what the men can carry (250 each).
    public var load: Int { inventory.reduce(0) { $0 + $1.key.weight * $1.value } }
    public var capacity: Int { 250 * men }
}

/// A quest in progress: the island, the party, and where the party stands.
public struct Expedition: Sendable {
    public let seed: UInt64
    public let island: Island
    public var party: Party
    public private(set) var x: Double
    public private(set) var y: Double
    public internal(set) var market: Market?
    var rng: SeededRandom

    /// The original moves 3 pixels a turn; walking that far is one turn here.
    static let turnLength = 3.0
    private var walked = 0.0
    private var turns = 0
    /// Rations missed in a row (Z6); after three, men start to starve.
    var hungryRations = 0
    /// Things that happened that the player should hear about, oldest first.
    public private(set) var news: [String] = []

    public init(seed: UInt64) {
        self.seed = seed
        island = Island(seed: seed)
        var rng = SeededRandom(seed: seed ^ 0xA5A5_A5A5)
        party = Party(rng: &rng)
        self.rng = rng
        (x, y) = island.start
    }

    public var cell: Cell { Cell(x: x, y: y) }
    public var terrain: Terrain { island.terrain(cell) }
    public var site: Site? { island.site(cell) }
    public var isLost: Bool { party.men <= 0 }

    /// Line 609: how the larder looks.
    public var foodWarning: String? {
        let food = party.foodPacks
        if food < 1 { return "YOU ARE OUT OF FOOD" }
        if food < party.men / 5 + 1 { return "YOU ARE LOW ON FOOD" }
        return nil
    }

    mutating func teleport(to cell: Cell) {
        (x, y) = cell.center
    }

    public mutating func takeNews() -> [String] {
        defer { news = [] }
        return news
    }

    /// Walking pace in map pixels per second; the hills and bogs slow the party.
    public static func pace(_ terrain: Terrain) -> Double {
        switch terrain {
        case .jungle: 9
        case .swamp: 5
        case .mountains: 4
        case .ocean: 0
        }
    }

    /// Walk in direction (dx, dy) (map axes, roughly unit length) for dt seconds.
    /// The men won't wade into the sea, so the party slides along the shore.
    /// Returns true if the party moved.
    @discardableResult
    public mutating func walk(dx: Double, dy: Double, dt: Double) -> Bool {
        guard !isLost else { return false }
        let step = Expedition.pace(terrain) * dt
        for (mx, my) in [(dx, dy), (dx, 0), (0, dy)] where mx != 0 || my != 0 {
            let nx = x + mx * step, ny = y + my * step
            if island.terrain(Cell(x: nx, y: ny)) != .ocean {
                walked += ((nx - x) * (nx - x) + (ny - y) * (ny - y)).squareRoot()
                x = nx
                y = ny
                while walked >= Expedition.turnLength {
                    walked -= Expedition.turnLength
                    passTurn()
                }
                return true
            }
        }
        return false
    }

    /// Line 602: every fifth turn the men eat a pack per ten of them (rounding up past
    /// five); three missed rations and a man starves each time after.
    mutating func passTurn() {
        turns += 1
        guard turns % 5 == 0 else { return }
        let ration = party.men / 10 + (party.men % 10 > 5 ? 1 : 0)
        party.foodPacks = max(party.foodPacks - ration, 0)
        if party.foodPacks == 0 { hungryRations += 1 }
        if hungryRations >= 3 {
            party.men -= 1
            news.append("A MAN STARVED TODAY.")
            if isLost {
                news.append("I AM SORRY TO REPORT, MY LIEGE, THAT ALL THE MEN IN YOUR EXPEDITIONARY PARTY WERE LOST. BETTER LUCK NEXT TIME, SIRE.")
            }
        }
    }
}
