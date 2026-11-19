/// What can befall the party between sites (lines 725-3400 of ISLAND APVENTURE):
/// monsters, merchants, wizards and warriors met on the road, traps that catch men,
/// and obstacles that bar the way. Each plays out as a `Visit` with no site.

/// Men caught by the land itself (2000-2350). The right thing pulls them out (U1-U3).
public struct Trap: Hashable, Sendable {
    public let words: String
    let frees: Set<Item>

    /// What the terrain springs on the party.
    static func springs(in terrain: Terrain, rng: inout SeededRandom) -> Trap? {
        switch terrain {
        case .jungle:
            Trap(words: "MEN WERE TRAPPED WHEN A ROTTEN TREE FELL ON THEM", frees: [Item(4), Item(21)])
        case .swamp where rng.rnd(2) == 1:
            Trap(words: "MEN HAVE BEEN OVERCOME BY POISONOUS SWAMP GAS", frees: [Item(43), Item(39), Item(42)])
        case .swamp:
            Trap(words: "MEN HAVE FALLEN INTO SOME QUICKSAND", frees: [Item(7), Item(18), Item(19)])
        case .mountains where rng.rnd(2) == 1:
            Trap(words: "MEN FELL INTO A CREVASSE. THEY MAY HAVE SURVIVED", frees: [Item(7), Item(18), Item(19)])
        case .mountains:
            Trap(words: "MEN WERE CAUGHT IN AN AVALANCHE. THEY ARE BURIED", frees: [Item(8)])
        case .ocean:
            nil
        }
    }
}

/// Something in the way (3000-3400) until the right thing clears it (U1-U3).
public struct Obstacle: Hashable, Sendable {
    public enum Kind: Sendable { case ravine, thicket, bog, crevasse, cliff }

    public let kind: Kind
    public let words: String
    let clears: Set<Item>

    static func across(_ terrain: Terrain, rng: inout SeededRandom) -> Obstacle? {
        switch terrain {
        case .jungle where rng.rnd(2) == 1:
            Obstacle(kind: .ravine, words: "YOU'VE COME TO A DEEP, NARROW RAVINE.", clears: [Item(31), Item(7)])
        case .jungle:
            Obstacle(kind: .thicket, words: "YOU'VE COME TO A DENSE THICKET, TOO TANGLED TO WALK THROUGH.",
                     clears: [Item(4), Item(22), Item(21)])
        case .swamp:
            Obstacle(kind: .bog, words: "YOU'VE COME TO AN AREA OF QUICKSAND AND DEEP BOGS. YOU CAN'T TELL WHERE THE SOLID LAND IS.",
                     clears: [Item(3)])
        case .mountains where rng.rnd(2) == 1:
            Obstacle(kind: .crevasse, words: "YOU'VE COME TO A DEEP CREVASSE.", clears: [Item(21)])
        case .mountains:
            Obstacle(kind: .cliff, words: "YOU'VE COME TO A SHEER CLIFF.", clears: [Item(7)])
        case .ocean:
            nil
        }
    }
}

extension Expedition {
    /// Line 726: after each turn's walk, 1 in 12 brings an encounter, 1 in 60 a trap
    /// and 1 in 60 an obstacle.
    mutating func roadEvent(heading: (dx: Double, dy: Double)) {
        switch rng.rnd(60) {
        case 1: trap()
        case 2: obstacle(heading: heading)
        case 0, 3...6: encounter()
        default: break
        }
    }

    /// 1000: who comes along.
    private mutating func encounter() {
        var v = Visit(cell: cell, stage: .finished)
        switch 1 + rng.rnd(5) {
        case 1: meetMonsters(&v)
        case 2: v.stage = .caravan
        case 3: v.stage = .wizard(good: rng.rnd(2) == 1)
        default:
            v.said = ["YOU'VE COME UPON A PARTY OF WARRIORS."]
            v.stage = .warriors
        }
        visit = v
    }

    /// 2000: some men are caught, at least two, fewer for a dextrous party.
    private mutating func trap() {
        guard let trap = Trap.springs(in: terrain, rng: &rng) else { return }
        let n = min(max(2 + rng.rnd(3) - party.dexterity / 3, 2), party.men)
        party.men -= n
        var v = Visit(cell: cell, stage: .trapped(trap, men: n))
        if isLost { lose(&v) }
        visit = v
    }

    /// 3000: the way ahead is barred. (The original backs the party off and bars the
    /// cell it stood in; here the obstacle is in the cell it was walking into.)
    private mutating func obstacle(heading: (dx: Double, dy: Double)) {
        let length = (heading.dx * heading.dx + heading.dy * heading.dy).squareRoot()
        guard length > 0 else { return }
        let ahead = Cell(x: x + heading.dx / length * Island.cellWidth, y: y + heading.dy / length * Island.cellHeight)
        guard ahead != cell, ahead.isOnMap, island.site(ahead) == nil, island.obstacles[ahead] == nil,
              let obstacle = Obstacle.across(island.terrain(ahead), rng: &rng) else { return }
        island.bar(ahead, with: obstacle)
        seen.insert(ahead)
        visit = Visit(cell: ahead, stage: .obstacle(obstacle))
    }

    /// The road's own stages, from `act`.
    mutating func onTheRoad(_ action: Action, in v: inout Visit) {
        switch (v.stage, action) {

        // A caravan (1400-1430): buying opens its market.
        case (.caravan, .ignore):
            v.stage = .finished
        case (.caravan, .attack):
            party.alignment -= 5
            v.said = ["THE CARAVAN HAD SOME ARMED GUARDS."]
            startBattle(.merchants, theyWereSurprised: true, surprise: rng.rnd(3), in: &v)
        case (.caravan, .buy):
            var caravan = Market(sellsShip: false, men: party.men, rng: &rng)
            caravan.isCaravan = true
            market = caravan
            v.stage = .finished

        // A wizard or a warlock (1600-1650): aid for those of like mind.
        case let (.wizard(good), .attack):
            party.alignment -= good ? 3 : -3
            startBattle(good ? .wizards : .warlocks, theyWereSurprised: true, surprise: 0, in: &v)
        case let (.wizard(good), .requestAid):
            let mind = party.alignment.signum()
            if mind != 0 && mind != (good ? 1 : -1) {
                wizardAttacks(good: good, in: &v)
            } else {
                let item = Item(39 + rng.rnd(8))
                gain(item)
                v.said = ["HE GAVE YOU A \(item.name)."]
                v.stage = .finished
            }
        case let (.wizard(good), .leave):
            if party.alignment.signum() != (good ? 1 : -1) && rng.rnd(2) == 1 {
                wizardAttacks(good: good, in: &v)
            } else {
                v.stage = .finished
            }

        // Warriors (1800-1930): mercenaries to hire, or bandits in disguise.
        case (.warriors, .attack):
            party.alignment -= 3
            startBattle(.warriors, theyWereSurprised: true, surprise: 1, in: &v)
        case (.warriors, .ignore):
            if rng.rnd(2) == 1 {
                warriorsLeave(&v)
            } else {
                ambush(surprise: 2, in: &v)
            }
        case (.warriors, .wait):
            switch rng.rnd(3) {
            case 0: v.said = ["THEY ARE WAITING ALSO."]
            case 1: warriorsLeave(&v)
            default: ambush(surprise: 0, in: &v)
            }
        case (.warriors, .beFriendly):
            party.alignment += 2
            v.said = ["THEY APPEAR TO BE FRIENDLY."]
            if rng.rnd(3) == 0 {
                ambush(surprise: 2, in: &v)
            } else {
                let n = party.charisma + rng.rnd(8)
                v.said += ["THEY ARE WANDERING MERCENARIES AND WILL JOIN YOUR PARTY FOR A SHARE IN THE LOOT.",
                           "THERE ARE \(n) OF THEM, ALL WITH SWORDS."]
                party.men += n
                gain(Item(22), n)
                v.stage = .finished
            }

        // Traps (2100-2350, 8000-8017).
        case let (.trapped(trap, n), .use(item)):
            if trap.frees.contains(item) {
                rescue(n, with: item, in: &v)
                v.stage = .finished
            } else {
                v.said = ["USING YOUR \(item.name) DIDN'T HAVE ANY USEFUL EFFECT."]
            }
        case (.trapped, .carryOn):
            v.stage = .finished

        // Obstacles (3100-3350, 8020).
        case let (.obstacle(obstacle), .use(item)):
            if obstacle.clears.contains(item) {
                island.clear(v.cell)
                v.said = ["CONTINUE WITH YOUR JOURNEY."]
                v.stage = .finished
            } else {
                v.said = ["USING YOUR \(item.name) DIDN'T HAVE ANY USEFUL EFFECT."]
            }
        case (.obstacle, .leave):
            passedObstacle = v.cell
            v.stage = .finished

        default:
            useMagic(action, in: &v)
        }
    }

    /// 1640
    private mutating func wizardAttacks(good: Bool, in v: inout Visit) {
        v.said = ["HE DOESN'T LIKE YOUR STYLE. HE'S COMMANDING HIS MEN TO ATTACK."]
        startBattle(good ? .wizards : .warlocks, theyWereSurprised: false, surprise: 0, in: &v)
    }

    /// 1855: bandits to the good, rangers to the wicked.
    private mutating func ambush(surprise: Int, in v: inout Visit) {
        v.said += ["THE FIENDS WAITED UNTIL THEY GOT CLOSE AND THEN ATTACKED.",
                   party.alignment > -1 ? "THEY ARE BANDITS!!!" : "THEY ARE RANGERS!!!"]
        startBattle(.warriors, theyWereSurprised: false, surprise: surprise, in: &v)
    }

    /// 1920
    private mutating func warriorsLeave(_ v: inout Visit) {
        v.said = ["THEY HURRIEDLY LEFT THE AREA."]
        v.stage = .finished
    }

    /// 4800-4850: what survives of a caravan's goods, up to seven kinds.
    mutating func caravanSpoils(_ v: inout Visit) {
        v.said += ["CONGRATULATIONS, YOU KILLED ALL OF THE MERCHANT'S MEN.",
                   "MUCH OF THE CARAVAN'S GOODS WERE RUINED. WHAT'S LEFT INCLUDES:"]
        var found: [Int] = []
        for _ in 1...7 {
            var c: Int
            repeat { c = rng.rnd(30) } while c == Item.contract.id
            if found.contains(c) || rng.rnd(4) == 0 { c = 0 }
            found.append(c)
        }
        for id in found where id != 0 {
            let n = 3 + rng.rnd(12)
            gain(Item(id), n)
            v.said.append("\(n) \(Item(id).name(quantity: n))")
        }
        v.stage = .finished
    }
}

#if DEBUG
extension Expedition {
    /// For looking at things in the app: something met here and now.
    public mutating func rehearse(_ stage: Visit.Stage) {
        visit = Visit(cell: cell, stage: stage)
    }

    /// For looking at things: an obstacle across the cell to the north (or wherever is open).
    public mutating func rehearseObstacle(_ kind: Obstacle.Kind) {
        let obstacle = Obstacle(kind: kind, words: "", clears: [])
        for (_, dc, dr) in Island.compass {
            let c = Cell(col: cell.col + dc, row: cell.row + dr)
            if island.terrain(c) != .ocean && island.site(c) == nil {
                island.bar(c, with: obstacle)
                return
            }
        }
    }

    /// For looking at things: something lying where the party stands.
    public mutating func rehearseLying(_ item: Item, _ quantity: Int) {
        island.lay(item, quantity, in: cell)
    }

    /// For looking at things: every site sealed, and the party just south of the first
    /// of a kind (whose door faces south).
    public mutating func sealEverySite(standingBy kind: Site? = nil) {
        for (cell, _) in island.sites { island.seal(cell) }
        guard let kind else { return }
        for (cell, site) in island.sites where site == kind {
            let south = Cell(col: cell.col, row: cell.row + 1)
            if island.terrain(south) != .ocean && island.site(south) == nil {
                teleport(to: south)
                return
            }
        }
    }
}
#endif
