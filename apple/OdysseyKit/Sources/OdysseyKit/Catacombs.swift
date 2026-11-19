/// CAVERN APVENTURE, below the wizard's temple: the catacombs, where the High One's
/// Orb may lie on an altar some levels down.
///
/// The original draws the catacombs on the lo-res screen, and the screen is the map:
/// 40 x 40 squares, wrapping at the edges, laid out in 5 x 5 tiles as the party walks
/// into unknown ground. Here the walls are a grid of the same squares.

/// The tile patterns (lines 1100-1210, and the altar room at 1300): HLIN, VLIN and
/// PLOT relative to the tile's corner (K, I).
enum CatacombTiles {
    enum Op { case h(Int, Int, Int), v(Int, Int, Int), p(Int, Int) }   // h: K+a...K+b at I+at; v: I+a...I+b at K+at

    static let patterns: [Int: [Op]] = [
        1100: [.h(0, 1, 0), .h(2, 3, 2), .h(3, 4, 3), .h(3, 4, 4), .h(0, 1, 4), .p(0, 1), .p(4, 0)],
        1110: [.h(0, 4, 0), .h(2, 4, 1), .v(3, 4, 0), .v(3, 4, 3), .v(3, 4, 4), .v(3, 4, 1)],
        1120: [.h(0, 4, 0), .h(0, 4, 1), .v(3, 4, 0), .v(3, 4, 4), .p(1, 4), .p(3, 3)],
        1130: [.v(0, 4, 0), .v(1, 4, 1), .v(0, 4, 4), .p(3, 0), .v(3, 4, 3)],
        1140: [.p(0, 4)],
        1150: [.h(0, 4, 0), .h(0, 2, 1), .h(0, 1, 2), .h(0, 1, 3), .h(0, 4, 4), .p(4, 3)],
        1160: (0..<5).map { .h(0, 4, $0) },
        1170: [.h(0, 4, 0), .h(2, 4, 1), .h(3, 4, 2), .v(3, 4, 4), .v(3, 4, 0), .p(1, 4)],
        1180: [.v(0, 4, 0), .h(1, 4, 4), .h(3, 4, 0), .h(2, 3, 1), .p(2, 2)],
        1190: [.v(0, 4, 0), .h(0, 4, 4), .v(0, 1, 4), .p(3, 1), .p(1, 0), .h(2, 3, 2)],
        1200: [.v(0, 1, 0), .v(0, 1, 1), .v(3, 4, 2), .v(3, 4, 3), .v(0, 4, 4), .h(0, 1, 4), .p(3, 0), .p(0, 3)],
        1210: [.h(0, 1, 0), .v(3, 4, 0), .v(2, 4, 1), .v(0, 4, 4), .p(3, 4), .p(3, 1)],
        1300: [.h(0, 1, 0), .h(3, 9, 0), .h(0, 1, 1), .h(6, 9, 1), .v(3, 9, 0), .v(5, 6, 1), .v(3, 9, 9), .v(6, 9, 8),
               .h(7, 8, 8), .h(3, 7, 9), .p(8, 9), .p(1, 7), .p(8, 3), .p(8, 6), .p(5, 1), .p(5, 4), .p(1, 9)],
    ]

    /// 10002: the tiles that can follow, by the way the party is going (1-12 for 1100-1210).
    static let going: [Int: [Int]] = [
        2: [1, 4, 5, 9, 10, 11, 12],        // south (T)
        1: [1, 2, 3, 5, 8, 11, 12],         // east (LA)
        3: [1, 2, 3, 5, 6, 9, 10],          // west (DR)
        0: [1, 2, 3, 4, 5, 8, 12],          // north (B)
    ]
}

/// Trouble that the right thing can still put right.
public enum CatacombTrouble: Sendable, Equatable, Codable {
    case pit(men: Int)                                  // 655: rope, net or sail
    case caveIn(men: Int, item: Item?, quantity: Int)   // 670: dig them out with a shovel
}

public enum CatacombQuestion: Sendable, Equatable, Codable {
    case teleport                       // 530: are you sure?
    case pitRescue                      // 3120: go down, or bring them up?

    public var words: String {
        switch self {
        case .teleport:
            "TELEPORTATION IS VERY DANGEROUS, SIRE. IT REQUIRES WISDOM AND LUCK TO DO IT CORRECTLY. ARE YOU SURE YOU WISH TO TRY?"
        case .pitRescue:
            "DO YOU WANT TO GO DOWN OR BRING THEM UP (D OR U)?"
        }
    }
}

public struct Catacombs: Sendable, Codable {
    public static let size = 40

    /// The rock, row by row from the north.
    public internal(set) var walls = [Bool](repeating: false, count: 40 * 40)
    /// Which 5 x 5 tiles have been laid out (the original reads a tile's corner).
    public internal(set) var laid = [Bool](repeating: false, count: 8 * 8)
    public internal(set) var x = 0
    public internal(set) var y = 0
    /// Levels gone down (LEV); the original calls the first level 1.
    public internal(set) var depth = 0
    public internal(set) var light = false                      // LT
    public internal(set) var said: [String] = []
    public internal(set) var stairway = false                   // ST
    public internal(set) var exitHere = false                   // Z10
    /// The altar room's altar (Z1, Z2), once found.
    public internal(set) var altarX: Int?, altarY: Int?
    public internal(set) var atAltar = false                    // Z8 = 1
    /// The swarm of frenzies (X0, Y0) and the way it is heading (SX, SY).
    public internal(set) var frenziesX: Int?, frenziesY: Int?
    var frenzyStep = [1, 0]
    var frenzyClock = 0.0
    /// The borer (X2, Y2), and whether it is half way through boring (DS).
    public internal(set) var borerX: Int?, borerY: Int?
    var boring = false
    /// Turns left in the poison gas (PG).
    public internal(set) var gas: Int?
    /// Things on the floor, by 2 x 2 square (the original's LC), as item x 100 + quantity.
    public internal(set) var floor: [Int: Int] = [:]
    public internal(set) var trouble: CatacombTrouble?
    public internal(set) var question: CatacombQuestion?
    /// The next step goes through rock (Z9, the burrow order).
    public internal(set) var burrowing = false

    static func index(_ x: Int, _ y: Int) -> Int { wrap(y) * size + wrap(x) }
    static func wrap(_ v: Int) -> Int { (v % size + size) % size }

    public func isWall(_ x: Int, _ y: Int) -> Bool { walls[Catacombs.index(x, y)] }

    /// What lies on the floor where the party stands.
    public var onFloor: (item: Item, quantity: Int)? {
        guard let v = floor[Catacombs.floorKey(x, y)], v % 100 > 0, (1...49).contains(v / 100) else { return nil }
        return (Item(v / 100), v % 100)
    }

    static func floorKey(_ x: Int, _ y: Int) -> Int { wrap(x) / 2 * 20 + wrap(y) / 2 }

    public var frenzies: (x: Int, y: Int)? { frenziesX.map { ($0, frenziesY ?? 0) } }
    public var borer: (x: Int, y: Int)? { borerX.map { ($0, borerY ?? 0) } }
    public var altar: (x: Int, y: Int)? { altarX.map { ($0, altarY ?? 0) } }

    /// 500-503: the report.
    public var report: [String] {
        var lines = ["YOU ARE IN THE CATACOMBS."]
        if let (item, n) = onFloor {
            lines.append(n == 1 ? "THERE IS A \(item.name) ON THE FLOOR HERE." : "THERE ARE \(n) \(item.name(quantity: n)) ON THE FLOOR HERE.")
        }
        lines.append("WHAT DO YOU WANT TO DO NOW?")
        return lines
    }

    // MARK: Laying out the maze

    mutating func draw(_ line: Int, k: Int, i: Int, wall: Bool = true) {
        for op in CatacombTiles.patterns[line]! {
            switch op {
            case let .h(a, b, at): for x in (k + a)...(k + b) { set(x, i + at, wall) }
            case let .v(a, b, at): for y in (i + a)...(i + b) { set(k + at, y, wall) }
            case let .p(a, b): set(k + a, i + b, wall)
            }
        }
        laid[Catacombs.wrap(i) / 5 * 8 + Catacombs.wrap(k) / 5] = true
        if line == 1300 {
            for (dk, di) in [(5, 0), (0, 5), (5, 5)] { laid[Catacombs.wrap(i + di) / 5 * 8 + Catacombs.wrap(k + dk) / 5] = true }
        }
    }

    mutating func set(_ x: Int, _ y: Int, _ wall: Bool) {
        walls[Catacombs.index(x, y)] = wall
    }

    func isLaid(k: Int, i: Int) -> Bool { laid[Catacombs.wrap(i) / 5 * 8 + Catacombs.wrap(k) / 5] }

    /// A fresh level: no rock, nothing found.
    mutating func clear() {
        walls = [Bool](repeating: false, count: 40 * 40)
        laid = [Bool](repeating: false, count: 64)
        floor = [:]
        frenziesX = nil
        frenziesY = nil
        borerX = nil
        borerY = nil
        stairway = false
        exitHere = false
    }
}

extension Expedition {
    // MARK: Going down

    /// 10000-10040: into the catacombs, where it is very dark.
    mutating func enterCatacombs() {
        var c = Catacombs()
        let i = 5 + 5 * rng.rnd(7), k = 5 + 5 * rng.rnd(7)
        c.draw(1150, k: k, i: i)
        c.x = k + 3
        c.y = i + 3
        catacombs = c
    }

    private static let allKilled = "I AM SORRY TO REPORT, MY LEIGE, THAT ALL THE MEMBERS OF YOUR PARTY WERE KILLED. BETTER LUCK NEXT TIME, SIRE."

    private mutating func lose(_ n: Int, _ c: inout Catacombs) {
        party.men = max(party.men - n, 0)
        if isLost { news.append(Expedition.allKilled) }
    }

    private var hasHelmet: Bool { (party.inventory[Item(10)] ?? 0) > 0 }

    // MARK: Moving

    /// 600-640: a step north (0), east (1), south (2) or west (3), laying out the
    /// next tile when the party reaches the edge of what is known. Then the borer
    /// closes in, and perhaps something happens (650-696).
    public mutating func creep(_ direction: Int) {
        guard var c = catacombs, c.question == nil, !isLost else { return }
        defer { catacombs = c }
        c.said = []
        let (dx, dy) = [(0, -1), (1, 0), (0, 1), (-1, 0)][direction & 3]
        let nx = Catacombs.wrap(c.x + dx), ny = Catacombs.wrap(c.y + dy)
        if c.isWall(nx, ny) {
            guard c.burrowing else { return }                     // 710: a bump
            c.said = ["BURROWING"]                                // 705
            c.set(nx, ny, false)
        }
        c.burrowing = false
        c.x = nx
        c.y = ny
        // Moving on leaves the trapped and buried, the stairway and the exit behind.
        c.trouble = nil
        c.stairway = false
        c.exitHere = false
        c.atAltar = false
        layOut(direction, &c)
        if c.borer != nil { borerCloses(&c) }
        if isLost { return }
        // 500: the gas wears off, a turn at a time.
        if let g = c.gas {
            if g - 1 == 8 { c.said.append("THE GAS IS DEFINITELY HAVING SOME EFFECT. THINGS LOOK KIND OF STRANGE.") }
            if g - 1 <= 0 {
                c.gas = nil
                c.said.append("YOU MUST HAVE GOTTEN OUT OF THE GAS. THINGS ARE BEGINNING TO LOOK NORMAL AGAIN. WHAT NOW?")
            } else {
                c.gas = g - 1
            }
        }
        if let a = c.altar, abs(c.x - a.x) + abs(c.y - a.y) < 2 {
            c.atAltar = true                                      // 4500
            c.said.append("YOU ARE AT AN ENORMOUS BLOOD STAINED ALTAR. THERE IS A JEWEL ENCRUSTED ORB ON THE ALTAR. WHAT DO YOU WANT TO DO NOW SIRE?")
            return
        }
        let m = rng.rnd(140)
        if m <= 9 && c.gas == nil && roadEvents { happen(m, &c) }
    }

    /// 610-630: at the edge of a tile, the next one is laid out if it isn't yet.
    private mutating func layOut(_ direction: Int, _ c: inout Catacombs) {
        let k = c.x - c.x % 5, i = c.y - c.y % 5
        var next: (k: Int, i: Int)?
        switch direction {
        case 1 where c.x % 5 == 4: next = (k + 5, i)
        case 2 where c.y % 5 == 4: next = (k, i + 5)
        case 3 where c.x % 5 == 0: next = (k - 5, i)
        case 0 where c.y % 5 == 0: next = (k, i - 5)
        default: break
        }
        guard let (nk, ni) = next, !c.isLaid(k: nk, i: ni) else { return }
        let j = 1 + rng.rnd(8)
        let line = j == 8 ? 1160 : 1090 + 10 * CatacombTiles.going[direction]![j - 1]
        c.draw(line, k: Catacombs.wrap(nk), i: Catacombs.wrap(ni))
    }

    /// 650-696
    private mutating func happen(_ n: Int, _ c: inout Catacombs) {
        switch n {
        case 0, 2:
            // Frenzies (650) or a borer (660); whichever is already about brings the
            // other, and with both about, a stairway.
            let f = c.frenzies != nil, b = c.borer != nil
            if f && b {
                stairs(&c)
            } else if n == 0 ? !f : b {
                frenziesBreakIn(&c)
            } else {
                borerArrives(&c)
            }
        case 1:
            pitTrap(&c)
        case 3:
            break
        case 4:
            caveIn(&c)
        case 5, 6:
            // 680: something lying about (a battle axe to a scroll, by the original's
            // numbering), if there is anything at all.
            let q = rng.rnd(3), item = 21 + rng.rnd(20)
            if q > 0 { c.floor[Catacombs.floorKey(c.x, c.y)] = item * 100 + q }
        case 7:
            c.said.append("THE AIR SMELLS FUNNY HERE. I THINK YOU MAY HAVE WANDERED INTO SOME POISONOUS GAS. WHAT NOW?")
            c.gas = 10
            // (The original's EN=4 forgets the frenzies and the borer.)
            c.frenziesX = nil
            c.frenziesY = nil
            c.borerX = nil
            c.borerY = nil
        default:
            stairs(&c)
        }
    }

    private mutating func frenziesBreakIn(_ c: inout Catacombs) {
        var fx: Int, fy: Int
        repeat {
            fx = rng.rnd(40)
            fy = rng.rnd(40)
        } while c.isWall(fx, fy) || (fx == c.x && fy == c.y)
        c.frenziesX = fx
        c.frenziesY = fy
        c.frenzyStep = [1, 0]
        c.said.append("A SWARM OF FRENZIES HAS BROKEN INTO THE CAVERNS! WHAT NOW?")
    }

    private mutating func borerArrives(_ c: inout Catacombs) {
        c.borerX = rng.rnd(40)
        c.borerY = rng.rnd(40)
        c.said.append("A BORER HAS GOTTEN YOUR SCENT. WHAT DO YOU WANT TO DO NOW?")
    }

    /// 655-657
    private mutating func pitTrap(_ c: inout Catacombs) {
        let n = min(2 + rng.rnd(4), party.men)
        c.said += ["PIT TRAP!", "\(n) MEN FELL INTO THE PIT. THEY MAY HAVE SURVIVED. WHAT NOW?"]
        c.trouble = .pit(men: n)
        lose(n, &c)
    }

    /// 670-674: rock falls all about; the light goes out, and some men and gear are buried.
    private mutating func caveIn(_ c: inout Catacombs) {
        if c.y < 2 || c.y > 37 {
            pitTrap(&c)
            return
        }
        for l in -2...2 {
            for x in max(c.x - 3 + abs(l), 0)...min(c.x + 3 - abs(l), 39) { c.set(x, c.y + l, true) }
        }
        c.set(c.x, c.y, false)
        c.light = false
        let n = min(1 + rng.rnd(3), party.men)
        c.said += ["CAVEIN", "\(n) MEN APPEAR TO BE BURIED."]
        // 5000-5010: and some of the gear, not food, gold, contracts or the ship.
        let gear = party.belongings.filter { $0.quantity >= 2 && $0.item != .contract && $0.item != .ship }
        var lost: (Item, Int)?
        if !gear.isEmpty {
            let (item, have) = gear[rng.rnd(gear.count)]
            let q = 1 + rng.rnd(have - 1)
            party.inventory[item] = have - q
            lost = (item, q)
            c.said.append("YOU ALSO LOST \(q) \(item.name(quantity: q)).")
        }
        c.said.append("WHAT DO YOU WANT TO DO?")
        c.trouble = .caveIn(men: n, item: lost?.0, quantity: lost?.1 ?? 0)
        lose(n, &c)
    }

    /// 695-696: a way down, or, with the orb, a way out.
    private func stairs(_ c: inout Catacombs) {
        if hasOrb {
            c.said.append("THERE APPEARS TO BE AN EXIT HERE. WHAT DO YOU WANT TO DO?")
            c.exitHere = true
        } else {
            c.said.append("THERE'S A STAIRWAY GOING DOWN HERE. WHAT DO YOU WANT TO DO?")
            c.stairway = true
        }
    }

    /// 698-699, 1300-1330: down a level. From the second level down, half the time the
    /// party comes out in the altar room.
    private mutating func descend(_ c: inout Catacombs) {
        c.depth += 1
        let room = c.depth > 1 && c.altar == nil && !hasOrb ? rng.rnd(2) : 0
        let k = min(c.x - c.x % 5, 30), i = min(c.y - c.y % 5, 30)
        c.clear()
        c.x = k + room + 1
        c.y = i + room + 1
        if room == 1 {
            c.draw(1300, k: k, i: i)
            c.said.append("YOU'VE ENTERED A LARGE MUSTY ROOM. THERE IS A LARGE ALTAR IN THE CENTER OF THE ROOM.")
            c.altarX = k + 5
            c.altarY = i + 4
        } else {
            c.draw(1100, k: k, i: i)
            c.set(c.x, c.y, false)
            c.said.append("YOU HAVE DESCENDED TO LEVEL \(c.depth + 1)")
        }
    }

    // MARK: The frenzies and the borer

    /// 22-60: in their own time the frenzies dart about, homing on the party.
    public mutating func catacombsTick(dt: Double) {
        guard var c = catacombs, c.question == nil, var fx = c.frenziesX, var fy = c.frenziesY, !isLost else { return }
        c.frenzyClock += dt
        defer { catacombs = c }
        while c.frenzyClock >= 0.15 {
            c.frenzyClock -= 0.15
            let nx = Catacombs.wrap(fx + c.frenzyStep[0]), ny = Catacombs.wrap(fy + c.frenzyStep[1])
            if nx == c.x && ny == c.y {
                c.said = ["THE FRENZIES GOT YOU. TWO MEN WERE KILLED AND MANY HURT. WHAT DO YOU WANT TO DO?"]
                c.frenziesX = nil
                c.frenziesY = nil
                lose(2, &c)
                return
            }
            if c.isWall(nx, ny) || rng.rnd(2) == 1 {
                let r = rng.rnd(4)
                var step = [[0, -1], [0, 1], [1, 0], [-1, 0]][r]
                if rng.rnd(2) == 1 {
                    if r < 2 { step[1] = (c.y - fy).signum() } else { step[0] = (c.x - fx).signum() }
                }
                c.frenzyStep = step
                continue
            }
            fx = nx
            fy = ny
            c.frenziesX = fx
            c.frenziesY = fy
        }
    }

    /// 160-185: with each step the borer closes in, boring through the rock (a square
    /// every other turn), and strikes when it reaches the party.
    private mutating func borerCloses(_ c: inout Catacombs) {
        guard var bx = c.borerX, var by = c.borerY else { return }
        if bx == c.x && by == c.y {
            borerStrikes(&c)
            return
        }
        if c.x != bx && !(c.y != by && rng.rnd(2) == 1) {
            let dx = (c.x - bx).signum()
            if c.isWall(bx + dx, by) {
                c.boring.toggle()
                if !c.boring {
                    c.set(bx + dx, by, false)
                    bx += dx
                }
            } else {
                bx += dx * (abs(c.x - bx) > 1 ? 2 : 1)
            }
        } else {
            let dy = (c.y - by).signum()
            if c.isWall(bx, by + dy) {
                c.boring.toggle()
                if !c.boring {
                    c.set(bx, by + dy, false)
                    by += dy
                }
            } else {
                by += dy * (abs(c.y - by) > 1 ? 2 : 1)
            }
        }
        c.set(bx, by, false)
        c.borerX = bx
        c.borerY = by
        if abs(c.x - bx) + abs(c.y - by) < 2 {
            borerStrikes(&c)
        }
    }

    /// 180-185. (The original takes the two men from a misspelt variable, so nobody dies.)
    private mutating func borerStrikes(_ c: inout Catacombs) {
        c.said.append("THE BORERS CAUGHT YOU! THEY KILLED TWO MEN AND WOUNDED SEVERAL MORE BEFORE THEY WERE KILLED.")
        c.borerX = nil
        c.borerY = nil
        party.strength = max(party.strength - 3, 1)
        lose(2, &c)
    }

    // MARK: Orders

    public enum CatacombCommand: Sendable, Hashable {
        case light, down, out, teleport, burrow, get
    }

    /// The catacomb's orders. In the dark only the light can be seen to (520).
    public mutating func order(_ o: CatacombCommand) {
        guard var c = catacombs, c.question == nil, !isLost else { return }
        guard c.light || o == .light else { return }
        if o == .out && c.exitHere {
            returnToShip()
            news.append("WE MADE IT OUT WITH THE ORB, SIRE.")
            return
        }
        c.said = []
        defer { catacombs = c }
        switch o {
        case .light:
            c.light.toggle()
            if c.light { c.said = ["OK, YOUR LIGHT IS ON. NOW WHAT?"] }
        case .down:
            if c.stairway {
                descend(&c)
            } else {
                c.said = ["OK, YOU'RE LYING DOWN. NOW WHAT?"]
            }
        case .out:
            c.said = ["THERE IS NO WAY OUT RIGHT HERE, SIR. PERHAPS A LITTLE FURTHER ON..."]
        case .teleport:
            c.question = .teleport
        case .burrow:
            if (party.inventory[Item(8)] ?? 0) > 0 {
                c.said = ["WHICH DIRECTION, SIRE?"]
                c.burrowing = true
            } else {
                c.said = ["WE DON'T HAVE A SHOVEL, M'LORD."]
            }
        case .get:
            if c.atAltar {
                c.said = ["YOU HAVE GOTTEN THE HIGH ONE'S ORB. WHAT NOW MY LIEGE?"]
                hasOrb = true
                c.atAltar = false
                c.altarX = nil
                c.altarY = nil
            } else if let (item, n) = c.onFloor {
                c.floor[Catacombs.floorKey(c.x, c.y)] = nil
                party.inventory[item, default: 0] += n
                c.said = ["OK, YOU GOT \(n) \(item.name(quantity: n)).", "WHAT NOW?"]
            } else {
                c.said = ["OK, YOU GOT SOME SPIDER WEBS AND A HANDFUL OF SLIMY MUCK FROM THE FLOOR.", "WHAT NOW?"]
            }
        }
    }

    /// Answer a question in the catacombs: yes or no to teleporting; down (true) or up
    /// (false) for the men in the pit.
    public mutating func answerBelow(_ yes: Bool) {
        guard var c = catacombs, let q = c.question else { return }
        c.question = nil
        c.said = []
        defer { catacombs = c }
        switch q {
        case .teleport:
            guard yes else { return }
            teleport(&c)
        case .pitRescue:
            guard case let .pit(n) = c.trouble else { return }
            c.trouble = nil
            let killed = min(rng.rnd(3), n)
            c.said = ["YOU MANAGED TO SAVE \(n - killed) \(n - killed == 1 ? "MAN." : "MEN.")",
                      "\(killed) \(killed == 1 ? "WAS" : "WERE") ACTUALLY KILLED IN THE FALL."]
            party.men += n - killed
            if yes { descend(&c) }
        }
    }

    /// 532-542: somewhere else at random, leaving men behind (fewer for the wise).
    private mutating func teleport(_ c: inout Catacombs) {
        var tx: Int, ty: Int
        repeat {
            tx = rng.rnd(40)
            ty = rng.rnd(40)
        } while c.isWall(tx, ty)
        let k = tx - tx % 5, i = ty - ty % 5
        if !c.isLaid(k: k, i: i) {
            c.draw(1100 + 10 * rng.rnd(5), k: k, i: i)
            tx = k + 1
            ty = i + 1
            c.set(tx, ty, false)
        }
        c.x = tx
        c.y = ty
        c.trouble = nil
        c.stairway = false
        c.exitHere = false
        let left = 1 + (party.wisdom < 7 ? 1 : 0) + (party.wisdom < 4 ? 1 : 0)
        if c.gas != nil {
            c.gas = nil
            c.said = ["WE TELEPORTED OUT OF THE GAS, SIRE."]
        } else {
            c.said = ["WE TELEPORTED SUCCESSFULLY, SIR."]
        }
        c.said.append(left == 1 ? "1 MAN WAS LEFT BEHIND THOUGH. WHAT NOW?" : "\(left) MEN WERE LEFT BEHIND THOUGH. WHAT NOW?")
        lose(left, &c)
    }

    /// 2300-2310, 3000-3350: use something. The right thing puts the trouble right.
    public mutating func useBelow(_ item: Item) {
        guard var c = catacombs, c.question == nil, c.light, (party.inventory[item] ?? 0) > 0 else { return }
        c.said = []
        defer { catacombs = c }
        let pit = { if case .pit = c.trouble { true } else { false } }()
        let buried = { if case .caveIn = c.trouble { true } else { false } }()
        switch item.id {
        case _ where [39, 46].contains(item.id) && c.frenzies != nil:
            c.said = [item.id == 39 ? "USING THE AMULET HAS BANISHED THE FRENZIES FROM THE CATACOMBS. WHAT NOW?"
                                    : "THE FRENZIES WERE DESTROYED BY THE MAGIC WAND. WHAT NOW?"]
            c.frenziesX = nil
            c.frenziesY = nil
            useUpBelow(item)
        case _ where [41, 42].contains(item.id) && c.borer != nil:
            c.said = [item.id == 41 ? "THE BORERS WERE DESTROYED BY THE MAGIC LAMP. WHAT NOW?"
                                    : "THE BORERS WERE BANISHED FROM THE CATACOMBS BY THE SCEPTER. WHAT NOW?"]
            c.borerX = nil
            c.borerY = nil
            useUpBelow(item)
        case _ where [7, 18, 19].contains(item.id) && pit:
            c.said = ["OK, YOU ARE GOING TO USE YOUR \(item.name)."]
            c.question = .pitRescue
        case 8 where buried:
            guard case let .caveIn(men, buried, q) = c.trouble else { return }
            c.trouble = nil
            if let buried {
                party.inventory[buried, default: 0] += q
                c.said.append("OK, YOU SAVED THE \(q) \(buried.name(quantity: q)).")
            }
            if hasHelmet {
                c.said.append("THE MEN WERE PROTECTED BY THEIR HELMETS AND WERE ALSO SAVED.")
                party.men += men
            } else {
                c.said.append("UNFORTUNATELY, THE MEN WERE ALL KILLED BY THE FALLING ROCKS (NO HELMETS).")
            }
        default:
            c.said = ["USING YOUR \(item.name) SERVED NO USEFUL PURPOSE. NOW WHAT?"]
        }
    }

    private mutating func useUpBelow(_ item: Item) {
        party.inventory[item] = max((party.inventory[item] ?? 0) - 1, 0)
    }

    /// 2340-2370, 2110: leave some of something on the floor here. The floor holds one
    /// kind of thing (the original's last put wins).
    @discardableResult
    public mutating func putDown(_ item: Item, quantity: Int) -> Bool {
        guard var c = catacombs, c.light, quantity >= 1, quantity <= (party.inventory[item] ?? 0) else { return false }
        let key = Catacombs.floorKey(c.x, c.y)
        let there = c.floor[key].map { ($0 / 100, $0 % 100) }
        if let there, there.0 != item.id { return false }
        let n = min((there?.1 ?? 0) + quantity, 99)
        c.floor[key] = item.id * 100 + n
        party.inventory[item] = (party.inventory[item] ?? 0) - (n - (there?.1 ?? 0))
        c.said = []
        catacombs = c
        return true
    }
}
