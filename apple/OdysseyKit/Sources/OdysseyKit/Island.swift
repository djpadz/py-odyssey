/// The island of the Sargalo Sea, as laid out by HAIL (lines 135-139 of the original).
///
/// Positions are in the original's map pixels: x 0..<280 west to east, y 0..<160
/// north to south. Each cell is 14 x 8 pixels; the grid is 20 x 20.
public enum Terrain: Int, Sendable, CaseIterable {
    case jungle, swamp, mountains, ocean

    public var name: String { ["JUNGLE", "SWAMP", "MOUNTAINS", "OCEAN"][rawValue] }
}

public enum Site: Int, Sendable, CaseIterable {
    case temple = 51, ruin, castle, tomb, hut, city

    /// How the site is named when seen from a neighbouring cell (the original's O$).
    public var distantName: String {
        ["TEMPLE", "RUIN", "CASTLE", "TOMB", "HUT", "VILLAGE"][rawValue - 51]
    }

    /// The text shown on arriving at the site (9010-9600).
    public var entrance: String {
        switch self {
        case .temple:
            "YOU ARE AT THE ENTRANCE TO AN ANCIENT TEMPLE. YOUR WAY IS BARRED BY TWO MASSIVE BRONZE DOORS WITH A LARGE LOCK ON THEM."
        case .ruin:
            "YOU ARE AT THE ENTRANCE TO AN ANCIENT RUIN. IT IS TOO DARK INSIDE TO ENTER SAFELY."
        case .castle:
            "YOU ARE AT THE ENTRANCE TO AN ANCIENT CASTLE. THE WAY IS BARRED BY A STOUT IRON DOOR WITH A SMALL LOCK ON IT."
        case .tomb:
            "YOU ARE AT THE ENTRANCE TO AN ANCIENT TOMB. YOUR WAY IS BLOCKED BY A MASSIVE STONE DOOR. THERE IS NO VISIBLE LOCK OR LATCH."
        case .hut:
            "YOU ARE AT THE ENTRANCE TO AN ANCIENT AND DECREPIT HUT."
        case .city:
            "YOU ARE AT THE ENTRANCE TO AN ANCIENT CITY."
        }
    }
}

public struct Cell: Hashable, Sendable {
    public let col: Int
    public let row: Int

    public init(col: Int, row: Int) {
        self.col = col
        self.row = row
    }

    /// The cell holding a map position.
    public init(x: Double, y: Double) {
        self.init(col: Int((x / Island.cellWidth).rounded(.down)), row: Int((y / Island.cellHeight).rounded(.down)))
    }

    /// LC() index: column major, 1-based.
    var index: Int { col * Island.size + row + 1 }

    /// Map position of the cell's centre.
    public var center: (x: Double, y: Double) {
        ((Double(col) + 0.5) * Island.cellWidth, (Double(row) + 0.5) * Island.cellHeight)
    }

    public var isOnMap: Bool { (0..<Island.size).contains(col) && (0..<Island.size).contains(row) }
}

public struct Island: Sendable {
    public static let size = 20
    public static let cellWidth = 14.0
    public static let cellHeight = 8.0
    public static let width = cellWidth * Double(size)
    public static let height = cellHeight * Double(size)

    /// The ship city where the quest's ship is sold (63,16 in the original).
    public static let shipCity = Cell(col: 4, row: 2)

    private(set) var lc: [Int]
    public let start: (x: Double, y: Double)
    /// Cells barred until the right thing clears the way (the original adds 99 to LC).
    public private(set) var obstacles: [Cell: Obstacle] = [:]

    /// Lay out a new island: the fixed ship city, two more cities and three of
    /// every other site, then put the party beside the last city.
    public init(seed: UInt64) {
        var rng = SeededRandom(seed: seed)
        var lc = IslandData.cells
        var x = 0, y = 0
        for i in 1...2 {
            var m: Int
            repeat {
                let x0 = 70 + rng.rnd(50) + 70 * (i == 2 ? 1 : 0)
                let y0 = 20 + rng.rnd(120)
                m = x0 / 14 * 20 + y0 / 8 + 1
            } while lc[m] != 0
            x = 14 * (m / 20) + 7
            y = 8 * (m % 20 - 1)
            lc[m] += Site.city.rawValue
        }
        for _ in 0..<3 {
            for site in Site.allCases where site != .city {
                var m: Int
                repeat {
                    m = 1 + rng.rnd(399)
                } while lc[m] / 10000 == 3 || lc[m - 1] / 10000 == 3 || lc[m + 1] / 10000 == 3
                    || lc[m] % 10000 != 0
                lc[m] += site.rawValue
            }
        }
        var sx = 0, sy = 0
        repeat {
            sx = x + (2 * rng.rnd(2) - 1) * 10
            sy = y + (2 * rng.rnd(2) - 1) * 10
        } while lc[sx / 14 * 20 + sy / 8 + 1] != 0
        self.lc = lc
        start = Cell(col: sx / 14, row: sy / 8).center
    }

    private func value(_ cell: Cell) -> Int {
        cell.isOnMap ? lc[cell.index] : 30000
    }

    /// Off the map is open ocean.
    public func terrain(_ cell: Cell) -> Terrain {
        Terrain(rawValue: value(cell) / 10000) ?? .ocean
    }

    public func site(_ cell: Cell) -> Site? {
        Site(rawValue: value(cell) % 100)
    }

    /// A site whose entrance sealed behind the party (the original adds 100).
    public func isSealed(_ cell: Cell) -> Bool {
        site(cell) != nil && value(cell) % 1000 > 100
    }

    mutating func seal(_ cell: Cell) {
        guard cell.isOnMap, !isSealed(cell) else { return }
        lc[cell.index] += 100
    }

    mutating func bar(_ cell: Cell, with obstacle: Obstacle) {
        obstacles[cell] = obstacle
    }

    mutating func clear(_ cell: Cell) {
        obstacles[cell] = nil
    }

    /// What lies on the ground in a cell (QQ of item II, for II below 51).
    public func lying(_ cell: Cell) -> (item: Item, quantity: Int)? {
        let v = value(cell) % 10000, id = v % 100
        guard cell.isOnMap, (1...49).contains(id), v / 100 > 0 else { return nil }
        return (Item(id), v / 100)
    }

    /// Everything lying about the island.
    public var lyingAbout: [(cell: Cell, item: Item, quantity: Int)] {
        allCells.compactMap { c in lying(c).map { (c, $0.item, $0.quantity) } }
    }

    /// Whether nothing (no site, no item) occupies the cell.
    func isBare(_ cell: Cell) -> Bool {
        cell.isOnMap && value(cell) % 10000 == 0
    }

    mutating func lay(_ item: Item, _ quantity: Int, in cell: Cell) {
        guard cell.isOnMap else { return }
        lc[cell.index] = lc[cell.index] / 10000 * 10000 + quantity * 100 + item.id
    }

    mutating func clearGround(_ cell: Cell) {
        guard cell.isOnMap else { return }
        lc[cell.index] = lc[cell.index] / 10000 * 10000
    }

    public var sites: [(cell: Cell, site: Site)] {
        allCells.compactMap { cell in site(cell).map { (cell, $0) } }
    }

    public var allCells: [Cell] {
        (0..<Island.size).flatMap { col in (0..<Island.size).map { Cell(col: col, row: $0) } }
    }

    /// The neighbouring cells in the original's DR() order, with their compass names.
    static let compass: [(name: String, dc: Int, dr: Int)] = [
        ("N", 0, -1), ("NE", 1, -1), ("E", 1, 0), ("SE", 1, 1),
        ("S", 0, 1), ("SW", -1, 1), ("W", -1, 0), ("NW", -1, -1),
    ]

    /// What the party sees from a position (lines 609-660). `looking` is the L
    /// command, which also names neighbouring terrain.
    public func describe(x: Double, y: Double, looking: Bool = false) -> String {
        let here = Cell(x: x, y: y)
        let tt = terrain(here)
        var text = "YOU ARE IN THE \(tt.name). YOU CAN SEE "
        var sawSite = false, terrainChanges = false
        for (dir, dc, dr) in Island.compass {
            let cell = Cell(col: here.col + dc, row: here.row + dr)
            let l = terrain(cell)
            if l != tt { terrainChanges = true }
            if let site = site(cell) {
                sawSite = true
                text += "A \(site.distantName) TO THE \(dir). "
            } else if looking && l != tt {
                // The ocean inside the island is called a lake.
                let name = (l == .ocean && 160 < x && x < 225 && 75 < y && y < 130) ? "LAKE" : l.name
                text += "\(name) TO THE \(dir). "
            }
        }
        if let (item, n) = lying(here) {
            // Line 612: what lies here is all the report says.
            return "YOU ARE IN THE \(tt.name). YOU CAN SEE \(n) \(item.name(quantity: n)) HERE."
        }
        if !sawSite && !terrainChanges {
            text += "NOTHING BUT \(tt.name) IN ALL DIRECTIONS."
        } else if !sawSite && !looking {
            text += "NOTHING OF INTEREST IN THE VICINITY."
        }
        return text.trimmingSuffix(" ")
    }
}

extension String {
    func trimmingSuffix(_ c: Character) -> String {
        var s = self
        while s.last == c { s.removeLast() }
        return s
    }
}
