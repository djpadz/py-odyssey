/// The adventurer and the men who follow (rolled as in HAIL, lines 32-33).
public struct Party: Sendable {
    public var men = 10
    /// What the party carries, food and quadroons included (the original's BG/BQ).
    public var inventory: [Item: Int]
    public let charisma: Int
    public let dexterity: Int
    public var strength: Int
    public let wisdom: Int
    public let morale: Int
    public let speed: Int
    public var experience = 10
    /// Good above zero, evil below (AL).
    public var alignment = 0

    public init(rng: inout SeededRandom) {
        charisma = rng.rnd(9) + 2
        dexterity = 5 + rng.rnd(4)
        wisdom = 5 + rng.rnd(5)
        morale = 5 + rng.rnd(5)
        inventory = [.foodPack: 15, .quadroon: 900 + rng.rnd(300)]
        strength = rng.rnd(8) + 3
        speed = rng.rnd(4) + 2
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
    public internal(set) var island: Island
    public var party: Party
    public private(set) var x: Double
    public private(set) var y: Double
    public internal(set) var market: Market?
    /// The site the party stands at, if it is dealing with one.
    public internal(set) var visit: Visit?
    var rng: SeededRandom

    /// The original moves 3 pixels a turn; walking that far is one turn here.
    static let turnLength = 3.0
    private var walked = 0.0
    private var turns = 0
    /// Rations missed in a row (Z6); after three, men start to starve.
    var hungryRations = 0
    /// Things that happened that the player should hear about, oldest first.
    public internal(set) var news: [String] = []
    /// Whether anything can befall the party on the road (off for some tests).
    var roadEvents = true
    /// An obstacle the player turned away from, so bumping it again stays quiet.
    var passedObstacle: Cell?

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

    static let allLost = "I AM SORRY TO REPORT, MY LIEGE, THAT ALL THE MEN IN YOUR EXPEDITIONARY PARTY WERE LOST. BETTER LUCK NEXT TIME, SIRE."

    /// Line 609: how the larder looks.
    public var foodWarning: String? {
        let food = party.foodPacks
        if food < 1 { return "YOU ARE OUT OF FOOD" }
        if food < party.men / 5 + 1 { return "YOU ARE LOW ON FOOD" }
        return nil
    }

    /// The report from where the party stands (609-660), opening with the larder
    /// instead of the terrain when food is short.
    public func describe(looking: Bool = false) -> String {
        let text = island.describe(x: x, y: y, looking: looking)
        guard let warning = foodWarning else { return text }
        return warning + text.dropFirst("YOU ARE IN THE \(terrain.name)".count)
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
    /// The men won't wade into the sea, so the party slides along the shore; walking
    /// straight at an obstacle stops and says what is in the way.
    /// Returns true if the party moved.
    @discardableResult
    public mutating func walk(dx: Double, dy: Double, dt: Double) -> Bool {
        guard !isLost, visit?.holdsParty != true, market == nil else { return false }
        let before = cell
        let step = Expedition.pace(terrain) * dt
        var turnsWalked = 0, moved = false
        for (i, (mx, my)) in [(dx, dy), (dx, 0), (0, dy)].enumerated() where mx != 0 || my != 0 {
            let nx = x + mx * step, ny = y + my * step
            let next = Cell(x: nx, y: ny)
            if island.terrain(next) == .ocean { continue }
            if next != cell, let obstacle = island.obstacles[next] {
                if i == 0 && visit == nil && next != passedObstacle {
                    visit = Visit(cell: next, stage: .obstacle(obstacle))
                    return false
                }
                continue
            }
            walked += ((nx - x) * (nx - x) + (ny - y) * (ny - y)).squareRoot()
            x = nx
            y = ny
            while walked >= Expedition.turnLength {
                walked -= Expedition.turnLength
                turnsWalked += 1
            }
            moved = true
            break
        }
        if cell != before {
            visit = nil                   // walked away from a door
            passedObstacle = nil
            arrive()
        }
        for _ in 0..<turnsWalked {
            passTurn(heading: (dx, dy))
        }
        return moved
    }

    /// A turn on the road: rations (602), then perhaps an event (726).
    mutating func passTurn(heading: (dx: Double, dy: Double) = (0, 0)) {
        eat()
        if roadEvents && !isLost && visit == nil && market == nil {
            roadEvent(heading: heading)
        }
    }

    /// Line 602: every fifth turn the men eat a pack per ten of them (rounding up past
    /// five); three missed rations and a man starves each time after.
    private mutating func eat() {
        turns += 1
        guard turns % 5 == 0 else { return }
        let ration = party.men / 10 + (party.men % 10 > 5 ? 1 : 0)
        party.foodPacks = max(party.foodPacks - ration, 0)
        if party.foodPacks == 0 { hungryRations += 1 }
        if hungryRations >= 3 {
            party.men -= 1
            news.append("A MAN STARVED TODAY.")
            if isLost {
                news.append(Expedition.allLost)
            }
        }
    }
}
