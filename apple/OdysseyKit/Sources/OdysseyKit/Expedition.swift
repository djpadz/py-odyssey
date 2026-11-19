/// The adventurer and the men who follow (rolled as in HAIL, lines 32-33).
public struct Party: Sendable {
    public var men = 10
    public var foodPacks = 15
    public var gold: Int
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
        gold = 900 + rng.rnd(300)
        strength = rng.rnd(8) + 3
    }
}

/// A quest in progress: the island, the party, and where the party stands.
public struct Expedition: Sendable {
    public let seed: UInt64
    public let island: Island
    public var party: Party
    public private(set) var x: Double
    public private(set) var y: Double

    public init(seed: UInt64) {
        self.seed = seed
        island = Island(seed: seed)
        var rng = SeededRandom(seed: seed ^ 0xA5A5_A5A5)
        party = Party(rng: &rng)
        (x, y) = island.start
    }

    public var cell: Cell { Cell(x: x, y: y) }
    public var terrain: Terrain { island.terrain(cell) }
    public var site: Site? { island.site(cell) }

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
        let step = Expedition.pace(terrain) * dt
        for (mx, my) in [(dx, dy), (dx, 0), (0, dy)] where mx != 0 || my != 0 {
            let nx = x + mx * step, ny = y + my * step
            if island.terrain(Cell(x: nx, y: ny)) != .ocean {
                x = nx
                y = ny
                return true
            }
        }
        return false
    }
}
