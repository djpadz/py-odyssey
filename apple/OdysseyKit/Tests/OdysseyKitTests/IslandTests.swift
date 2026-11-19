import Testing
@testable import OdysseyKit

struct IslandTests {
    @Test func originalMapShape() {
        let island = Island(seed: 1)
        #expect(island.terrain(Cell(col: 0, row: 0)) == .ocean)
        #expect(island.terrain(Cell(col: 4, row: 3)) == .mountains)
        #expect(island.terrain(Cell(col: 8, row: 8)) == .swamp)
        #expect(island.terrain(Cell(col: -1, row: 5)) == .ocean)
        #expect(island.site(Island.shipCity) == .city)
    }

    @Test(arguments: [1, 2, 42, 1980] as [UInt64])
    func sitesArePlaced(seed: UInt64) {
        let island = Island(seed: seed)
        let counts = Dictionary(grouping: island.sites, by: \.site).mapValues(\.count)
        #expect(counts[.city] == 3)
        for site in Site.allCases where site != .city {
            #expect(counts[site] == 3)
        }
        for (cell, _) in island.sites {
            #expect(island.terrain(cell) != .ocean)
        }
    }

    @Test func sameSeedSameIsland() {
        #expect(Island(seed: 7).sites.map(\.cell) == Island(seed: 7).sites.map(\.cell))
        #expect(Island(seed: 7).sites.map(\.cell) != Island(seed: 8).sites.map(\.cell))
    }

    @Test func partyStartsOnLandNearACity() {
        for seed in 0..<50 as Range<UInt64> {
            let e = Expedition(seed: seed)
            #expect(e.terrain != .ocean)
            #expect(e.site == nil)
            let near = e.island.sites.contains { $0.site == .city
                && abs($0.cell.col - e.cell.col) <= 1 && abs($0.cell.row - e.cell.row) <= 2 }
            #expect(near)
        }
    }

    @Test func describesNeighbours() {
        let island = Island(seed: 3)
        let (x, y) = Cell(col: 4, row: 3).center
        let text = island.describe(x: x, y: y)
        #expect(text.hasPrefix("YOU ARE IN THE MOUNTAINS. YOU CAN SEE"))
        #expect(text.contains("A VILLAGE TO THE N."))
    }

    @Test func lookingNamesTheLake() {
        let island = Island(seed: 3)
        let (x, y) = Cell(col: 12, row: 12).center
        #expect(island.describe(x: x, y: y, looking: true).contains("LAKE TO THE E."))
    }

    @Test func menWillNotWadeIntoTheSea() {
        var e = Expedition(seed: 5)
        for _ in 0..<2000 { e.walk(dx: 0, dy: -1, dt: 0.05) }
        #expect(e.terrain != .ocean)
        #expect(e.y > 0)
    }
}
