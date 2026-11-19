/// SEA APVENTURE: sailing the Sargalo Sea in search of the High One's Orb and the
/// Isle of Lapour.
///
/// Positions are the original's chart pixels: x (longitude) 0..<280 west to east,
/// y (latitude) 0..<160 north to south. The ship moves a pixel at a time, under sail
/// in the direction the sails are set, otherwise drifting with the current.

/// The eight points of the compass, as the original numbers them (0 is north,
/// clockwise).
public enum CompassPoint {
    public static let names = ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]

    /// Lines 110-112: one pixel's step towards a point (diagonals step both ways).
    public static func step(_ d: Int) -> (dx: Int, dy: Int) {
        ((d > 0 && d < 4 ? 1 : 0) - (d > 4 ? 1 : 0), (d > 2 && d < 6 ? 1 : 0) - ([0, 1, 7].contains(d) ? 1 : 0))
    }
}

/// The sea chart: the picture's land and reefs, and the LC2 chart's depths and currents.
public enum SeaChart {
    public static let width = 280
    public static let height = 160

    public enum Ground: Sendable { case sea, reef, land }

    private static let grid: [[Ground]] = SeaChartData.picture.map { row in
        row.map { $0 == "#" ? .land : $0 == "%" ? .reef : .sea }
    }

    /// What lies at a chart pixel; off the chart is open sea.
    public static func ground(x: Int, y: Int) -> Ground {
        guard (0..<height).contains(y), (0..<width).contains(x) else { return .sea }
        return grid[y][x]
    }

    /// LC2 at a pixel: depth in fathoms and the current; nil over the chart's land.
    public static func water(x: Int, y: Int) -> (depth: Int, direction: Int, speed: Int)? {
        let col = min(max(x / 14, 0), 19), row = min(max(y / 8, 0), 19)
        let v = SeaChartData.cells[col * 20 + row + 1]
        guard v != 0 else { return nil }
        return (v / 1000, v % 1000 / 100, v % 100)
    }
}

/// Something going on at sea (the original's PG).
public enum Happening: Sendable, Equatable, Codable {
    case ships                          // 1, 2: three ships bearing down
    case fog                            // 3
    case pirates                        // 4
    case rottenSails                    // 5
    case aground                        // 6
    case temple                         // 7: ashore, at the wizard's temple
    case storm                          // 8
    case nearEdge                       // 9
    case whirlpool                      // 10
    case flyers(Monster)                // 11
    case argorion                       // 12
    case seaMonster(SeaMonster)         // 13
}

public enum SeaMonster: Sendable, Equatable, Codable {
    case octopus, serpent

    public var name: String { self == .octopus ? "GIANT OCTOPUS" : "SEA SERPENT" }
}

/// A question that waits on an answer before anything else.
public enum SeaQuestion: Sendable, Equatable, Codable {
    case merchants                      // buy, ignore or attack
    case raft(men: Int)                 // take aboard, ignore or kill
    case raftChest                      // open or dump
    case hail                           // friendly or challenge
    case fishermen                      // how much will you pay?
    case lapour                         // go on without the orb?

    public var words: String {
        switch self {
        case .merchants:
            "YOU'VE COME UPON SOME MERCHANTMEN. THEY ARE LIGHTLY ARMED. DO YOU WISH TO BUY SOMETHING, IGNORE THEM, OR ATTACK?"
        case let .raft(n):
            "YOU'VE COME UPON A RAFT WITH \(n) MEN ON IT. THEY HAVE A LARGE CHEST ON THEIR BOAT. WILL YOU TAKE THEM ABOARD, IGNORE THEM, OR KILL THEM?"
        case .raftChest: "DO YOU WANT TO OPEN THE CHEST OR DUMP IT OVER THE SIDE?"
        case .hail: "FRIENDLY OR CHALLENGE?"
        case .fishermen: "HOW MUCH ARE YOU WILLING TO PAY?"
        case .lapour:
            "BUT SIR, THIS IS THE ISLE OF LAPOUR. WITHOUT THE HIGH ONE'S ORB, WE WON'T STAND A CHANCE. SHALL WE STILL GO ON?"
        }
    }

    public var answers: [SeaAnswer] {
        switch self {
        case .merchants: [.buy, .ignore, .attack]
        case .raft: [.takeAboard, .ignore, .kill]
        case .raftChest: [.open, .dump]
        case .hail: [.friendly, .challenge]
        case .fishermen: []                     // answered with `pay`
        case .lapour: [.yes, .no]
        }
    }
}

public enum SeaAnswer: Sendable, Hashable {
    case buy, ignore, attack, takeAboard, kill, open, dump, friendly, challenge, yes, no
}

/// The captain's orders (the original's keys).
public enum SeaCommand: Sendable, Hashable {
    case watch                          // W: the bridge report
    case anchor                         // A: raise or drop it; or attack what's alongside
    case setSails(Int)                  // S and a direction
    case reef                           // R
    case fire                           // F: the cannon
    case land                           // L
    case divers                         // D
    case hail                           // H
    case get                            // G
}

/// Where a landing party has gone: somewhere this port doesn't reach yet.
public enum Shore: Sendable, Equatable, Codable {
    case catacombs                      // under the wizard's temple
    case fortress                       // the Caliph's, on Lapour
}

public struct Voyage: Sendable, Codable {
    /// The ship's position: the original's X0 and Y0, the point at its waterline.
    public internal(set) var x = 205
    public internal(set) var y = 117
    /// How far towards the next pixel the ship has come (for smooth motion).
    public internal(set) var progress = 0.0
    public internal(set) var anchored = true                   // Z1
    public internal(set) var sails: Int?                       // Z2; nil when reefed
    public internal(set) var wind: Int? = 3                    // Z3, where it blows from; nil when calm
    public internal(set) var currentDirection = 0              // Z4
    public internal(set) var currentSpeed = 2                  // Z6
    public internal(set) var sailsTorn = false                 // Z11
    /// Steps since scurvy broke out (LEV), if it has.
    public internal(set) var scurvy: Int?
    public internal(set) var happening: Happening?
    public internal(set) var question: SeaQuestion?
    /// Where Argorion said the orb lies (SR, UT).
    public internal(set) var orbAt: (x: Int, y: Int)? {
        get { orbX.map { ($0, orbY ?? 0) } }
        set { orbX = newValue?.x; orbY = newValue?.y }
    }
    private var orbX: Int?, orbY: Int?
    /// Over the edge of the world.
    public internal(set) var lost = false
    /// Ashore somewhere the port doesn't reach yet.
    public internal(set) var ashore: Shore?
    /// What has just been said, oldest first.
    public internal(set) var said: [String] = []
    /// Lightning flashes so far in the storm (for the scene to show).
    public internal(set) var flashes = 0
    /// Deserted islands landed on (Z21): after three, the temple.
    var landings = 0
    /// The ship's wake: where it last floated free, newest last (x, y pairs), for the
    /// fishermen to tow it back along.
    var afloat: [Int] = [205, 117]
    /// Seconds in the whirlpool (the original counts its polling loop to 300).
    var whirled = 0.0
    var ticks = 0.0

    init() {}

    /// Whether the sails can catch the wind (line 105).
    public var underSail: Bool {
        guard let s = sails, let w = wind else { return false }
        return s != w && (s + 1) % 8 != w && (w + 1) % 8 != s
    }

    /// Lines 610-640 (latitude and longitude only with a sextant).
    public func report(sextant: Bool) -> [String] {
        var lines: [String] = []
        if sextant { lines.append("LATITUDE IS \(y) AND LONGITUDE IS \(x).") }
        lines.append(wind.map { "THE WIND IS OUT OF THE \(CompassPoint.names[$0])." } ?? "THERE IS NO WIND AT ALL.")
        lines.append("CURRENT IS \(currentSpeed) KNOTS TO THE \(CompassPoint.names[currentDirection]).")
        lines.append("ANCHOR IS \(anchored ? "DOWN" : "UP"). SAILS " + (sails.map { "SET FOR \(CompassPoint.names[$0])." } ?? "REEFED."))
        return lines
    }

    /// The ship's hull: what runs aground (see `aground`).
    static let hull = 4
}

extension Expedition {
    // MARK: Setting sail

    /// 7000-7050: the ship sails only from the city where it was bought, with 15 men.
    mutating func useShip(_ v: inout Visit) {
        if abs(x - 63) + abs(y - 16) >= 20 {
            v.said = ["YOU OWN THE SHIP, BUT IT IS DOCKED AT THE CITY WHERE YOU BOUGHT IT. YOU MUST SET SAIL FROM THERE."]
        } else if party.men <= 14 {
            v.said = ["YOU DON'T HAVE ENOUGH MEN TO MAN SUCH A SHIP. IT REQUIRES AT LEAST 15."]
        } else {
            v.stage = .readyToSail
        }
    }

    mutating func embark() {
        visit = nil
        mount = nil
        voyage = Voyage()
    }

    var atSea: Bool { voyage != nil }
    var hasCompass: Bool { (party.inventory[Item(15)] ?? 0) > 0 }
    public var hasSextant: Bool { (party.inventory[Item(16)] ?? 0) > 0 }
    var hasSpareSail: Bool { (party.inventory[Item(19)] ?? 0) > 0 }

    private static let allLostAtSea = "I AM SORRY TO REPORT, MY LEIGE, THAT ALL THE MEMBERS OF YOUR EXPEDITIONARY PARTY WERE LOST. BETTER LUCK NEXT TIME, SIRE."

    // MARK: Time passing

    /// Let `dt` seconds pass at sea. The original polls the keyboard fifteen times a
    /// second or so; under sail the ship moves a pixel every third poll, adrift every
    /// 28 - current speed.
    public mutating func sail(dt: Double) {
        guard var v = voyage, !v.lost, v.ashore == nil, v.question == nil, market == nil, !isLost else { return }
        defer { voyage = v }
        if v.happening == .whirlpool {
            v.whirled += dt
            if v.whirled > 20 { tossedFree(&v) }
            return
        }
        if v.anchored {
            // 103: at anchor, the wind may still shift.
            v.ticks += dt * 15
            while v.ticks >= 1 {
                v.ticks -= 1
                if rng.rnd(10) == 0 { windShift(&v) }
                // With the sails in shreds and no spare, merchantmen happen by now and
                // then even at anchor. (The original sends them only to a ship under
                // way, which may be drifting onto a shoal it can't get off.)
                if v.sailsTorn && !hasSpareSail && roadEvents && v.question == nil && rng.rnd(450) == 0 {
                    v.question = .merchants
                }
            }
            return
        }
        let rate = v.underSail ? 5.0 : v.currentSpeed > 0 ? 15 / Double(28 - v.currentSpeed) : 0
        v.progress += rate * dt
        while v.progress >= 1 && !v.anchored && !v.lost && v.question == nil {
            v.progress -= 1
            step(&v)
            if isLost { return }
        }
        if v.anchored { v.progress = 0 }
    }

    /// Which way the ship is moving, if it is: under sail, or with the current.
    public var drift: Int? {
        guard let v = voyage, !v.anchored, v.happening != .whirlpool else { return nil }
        if v.underSail { return v.sails }
        return v.currentSpeed > 0 ? v.currentDirection : nil
    }

    /// 110-119: one pixel.
    private mutating func step(_ v: inout Voyage) {
        guard let d = drift else { return }
        let (dx, dy) = CompassPoint.step(d)
        let nx = v.x + dx, ny = v.y + dy
        // 117: the edge of the world.
        if nx == 16 || nx == 264 || ny == 16 || ny == 153 {
            if v.happening == .nearEdge {
                v.happening = nil
            } else {
                v.said.append("DANGER! DANGER! DANGER! WE'RE APPROACHING THE EDGE OF THE WORLD. WE MUST TURN BACK SIRE!")
                if v.happening == nil { v.happening = .nearEdge }
            }
        }
        if nx < 8 || nx > 272 || ny < 8 || ny > 157 {
            overTheEdge(&v)
            return
        }
        if !Expedition.aground(x: v.x, y: v.y) {
            v.afloat = Array((v.afloat + [v.x, v.y]).suffix(12))
        }
        v.x = nx
        v.y = ny
        if Expedition.aground(x: nx, y: ny) {
            runAground(&v)
            return
        }
        underway(&v)
    }

    /// Whether the hull, a few pixels about the waterline, touches land or reef. (The
    /// original tests the whole picture of the ship, sails and all.)
    static func aground(x: Int, y: Int) -> Bool {
        let r = Voyage.hull
        for py in (y - r)...(y + r) {
            for px in (x - r)...(x + r) where (px - x) * (px - x) + (py - y) * (py - y) <= r * r {
                if SeaChart.ground(x: px, y: py) != .sea { return true }
            }
        }
        return false
    }

    /// 90-96: what happens as the ship goes.
    private mutating func underway(_ v: inout Voyage) {
        let roll = rng.rnd(100)
        if roll <= 6 && v.happening == nil && roadEvents {
            switch roll {
            case 1: weather(&v)
            case 2: calamity(&v)
            default: encounter(&v)
            }
            return
        }
        if let w = SeaChart.water(x: v.x, y: v.y) {
            v.currentSpeed = w.speed
            v.currentDirection = w.direction
        }
        if v.sailsTorn && !hasSpareSail && rng.rnd(7) == 0 && roadEvents {
            v.anchored = true
            v.question = .merchants                     // 93: someone to sell a sail
            return
        }
        if v.happening == .fog && rng.rnd(20) == 0 {
            v.said.append("IT LOOKS LIKE THE FOG IS CLEARING UP.")
            v.happening = nil
        }
        if v.happening == .storm && rng.rnd(10) == 0 { v.flashes += 1 }
        if v.happening == .storm && rng.rnd(45) == 0 {
            stormLoss(&v)
            return
        }
        if let days = v.scurvy {
            v.scurvy = days + 1
            if (days + 1) % 7 == 0 {
                v.said.append("A MAN DIED OF SCURVEY TODAY.")
                loseMen(1)
                return
            }
        }
        windShift(&v)
    }

    /// 95: now and then the wind veers or backs, and set sails follow it round.
    private mutating func windShift(_ v: inout Voyage) {
        guard roadEvents, rng.rnd(30) == 0 else { return }
        let turn = 2 * rng.rnd(2) - 1
        let wind = ((v.wind ?? -1) + turn + 8) % 8
        v.wind = wind
        if let s = v.sails, s != wind, (s + 1) % 8 != wind, (wind + 1) % 8 != s {
            v.sails = (s + turn + 8) % 8
        }
    }

    private mutating func loseMen(_ n: Int) {
        party.men = max(party.men - n, 0)
        if isLost { news.append(Expedition.allLostAtSea) }
    }

    // MARK: Things met at sea (1000-1920)

    private mutating func encounter(_ v: inout Voyage) {
        v.anchored = true
        switch rng.rnd(4) {
        case 0:
            switch rng.rnd(4) {
            case 0:
                let m = Monster(kind: 17 + rng.rnd(4))
                v.happening = .flyers(m)
                v.said += ["TAKE COVER! A BUNCH OF \(m.name) ARE FLYING THIS WAY!",
                           "THEY ARE JUST HOVERING THERE, SIR. WHAT SHALL WE DO?"]
            case 1:
                v.happening = .seaMonster(.octopus)
                v.said.append("IT'S A GIANT OCTOPUS, CAP'N. WHAT SHALL WE DO?")
            case 2:
                v.happening = .seaMonster(.serpent)
                v.said.append("IT'S A SEA SERPENT, CAP'N. WHAT SHALL WE DO?")
            default:
                guard !hasOrb else { return }
                v.happening = .argorion
                v.said.append("IT'S ARGORION, SIR. MAYBE WE CAN GET HIM TO HELP US. WHAT SHALL WE DO?")
            }
        case 1:
            v.question = .merchants
        case 2:
            v.question = .raft(men: 3 + rng.rnd(4))
        default:
            v.happening = .ships
            v.said += ["THE LOOKOUT HAS SIGHTED SHIPS COMING UP ON US. PREPARE FOR ACTION.",
                       "THEY ARE LIGHTLY ARMED, BUT THERE ARE 3 OF THEM. WHAT DO YOU WANT TO DO?"]
        }
    }

    /// 2000: storm, scurvy or fog.
    private mutating func weather(_ v: inout Voyage) {
        switch rng.rnd(4) {
        case 0:
            v.happening = .storm
            v.said += ["IT LOOKS LIKE A THUNDER STORM IS BREWING CAP'N. WE BETTER LASH EVERYTHING DOWN.",
                       "IT'S BLACK AS PITCH, SIR! I'LL HAVE THE LOOKOUT WATCH FOR ROCKS WHENEVER THE LIGHTNING FLASHES!"]
        case 1:
            v.scurvy = 1
            v.said.append("THE MEN ARE COMING DOWN WITH SCURVEY. WHAT WILL YOU DO?")
        default:
            v.happening = .fog
            v.said.append("IT LOOKS LIKE A FOG BANK IS ROLLING IN. WHAT DO YOU WANT TO DO?")
        }
    }

    /// 3000: becalmed, rotten sails, or a whirlpool.
    private mutating func calamity(_ v: inout Voyage) {
        switch rng.rnd(3) {
        case 0:
            v.wind = nil
            v.sails = nil
            v.said.append("THE WIND HAS DIED. YOU ARE BECALMED. THE MEN HAVE REEFED THE SAILS UNTIL THE WIND RETURNS.")
        case 1:
            v.happening = .rottenSails
            v.sails = nil
            v.sailsTorn = true
            v.said.append("YOUR SAILS HAVE ROTTED AND ARE TEARING. WHAT WILL YOU DO?")
        default:
            v.happening = .whirlpool
            v.whirled = 0
            v.said += ["A GIANT WHIRLPOOL!", "WE'RE GETTING SUCKED IN! WHAT SHALL WE DO, CAP'N?"]
        }
    }

    /// 2250-2270: the storm breaks, taking some of what the party carries with it.
    private mutating func stormLoss(_ v: inout Voyage) {
        stormOver(&v)
        let things = party.belongings
        guard !things.isEmpty else { return }
        let (item, have) = things[rng.rnd(things.count)]
        let n = min(3 + rng.rnd(max(have - 3, 1)), have)
        party.inventory[item] = have - n
        v.said.append("THE ONLY LOSSES WERE \(n) \(item.name(quantity: n)) WASHED OVERBOARD.")
    }

    private func stormOver(_ v: inout Voyage) {
        v.happening = nil
        v.said.append("IT LOOKS LIKE THE STORM HAS BROKEN, SIR.")
    }

    /// 3620
    private func tossedFree(_ v: inout Voyage) {
        v.said += ["WE WERE TOSSED FREE SOMEHOW.", "OUR SAILS ARE RUINED THOUGH. WHAT NOW?"]
        v.sails = nil
        v.sailsTorn = true
        v.happening = nil
    }

    /// 120-135
    private func runAground(_ v: inout Voyage) {
        v.said.append("YOU'VE RUN AGROUND IN THE SHALLOWS.")
        v.anchored = true
        if v.happening == .fog { v.said.append("IT LOOKS LIKE THE FOG IS CLEARING UP.") }
        if v.happening == .storm { stormOver(&v) }
        v.said.append("SOME LOCAL FISHERMEN WILL HELP PULL YOU FREE IF YOU PAY THEM. WHAT WILL YOU DO?")
        v.happening = .aground
    }

    /// 5100-5120
    private func overTheEdge(_ v: inout Voyage) {
        v.said += ["WE'RE GOING OVERRRR.....",
                   "YOUR SHIP WAS LOST. IT HAS FALLEN INTO LIMBO. PERHAPS NEXT TIME, YOU SHOULD BRING ALONG A GOOD NAVIGATOR. BETTER LUCK THEN."]
        v.lost = true
        v.anchored = true
        v.happening = nil
    }

    /// 31000: fish the ship out of limbo, and set it down mid-sea at anchor.
    public mutating func recoverShip() {
        guard var v = voyage, v.lost else { return }
        v.lost = false
        v.x = 150
        v.y = 80
        v.afloat = [150, 80]
        v.anchored = true
        v.said = []
        voyage = v
    }

    // MARK: The captain's orders

    /// Give an order.
    public mutating func command(_ c: SeaCommand) {
        // At the temple there is only attacking, using, offering or leaving (21020).
        guard var v = voyage, !v.lost, v.ashore == nil, v.question == nil, v.happening != .temple, !isLost
        else { return }
        v.said = []
        defer { landingParty() }
        defer { voyage = v }
        switch c {
        case .watch:
            break
        case .anchor:
            anchor(&v)
        case let .setSails(d):
            setSails(d, &v)
        case .reef:
            v.sails = nil
        case .fire:
            fire(&v)
        case .land:
            land(&v)
        case .divers:
            divers(&v)
        case .hail:
            if [.ships, .pirates].contains(v.happening) {
                v.question = .hail
            } else {
                v.said = ["EXCUSE ME, SIR. EXACTLY WHO WERE YOU CALLING TO? THERE'S NO ONE HERE BUT US."]
            }
        case .get:
            v.said = ["OK, YOU GOT A FISTFUL OF SEAWEED. NOW WHAT?"]
        }
    }

    /// 820-826: A raises or drops the anchor, or goes for whatever is alongside.
    private mutating func anchor(_ v: inout Voyage) {
        switch v.happening {
        case .seaMonster: monsterFrightened(&v)
        case .flyers: flyersAttack(&v)
        case .ships: shipsPass(&v)
        case .argorion:
            // 6020: he sinks out of sight, and the anchor comes up with him.
            v.happening = nil
            v.anchored = false
        case .pirates: pirates(&v)
        case .aground: v.said = ["THAT'S NOT YOUR ANCHOR ON THE BOTTOM, ITS YOUR SHIP."]
        case .temple: break
        default:
            let depth = SeaChart.water(x: v.x, y: v.y)?.depth ?? 0
            // The anchor reaches where the orb lies, deep as it is. (The original
            // compares latitude with longitude here.)
            let atOrb = v.orbAt.map { abs(v.x - $0.x) + abs(v.y - $0.y) < 4 } ?? false
            if depth > 20 && !v.anchored && !atOrb {
                v.said = ["SOUNDINGS INDICATE DEPTH IS \(depth) FATHOMS AND THE ANCHOR ONLY REACHES 20."]
            } else {
                v.anchored.toggle()
            }
        }
    }

    /// 828-839
    private mutating func setSails(_ d: Int, _ v: inout Voyage) {
        guard let wind = v.wind else {
            v.said = ["THERE IS STILL NO WIND SIR."]
            return
        }
        if v.sailsTorn {
            v.said = ["THE SAILS ARE IN SHREDS, SIR. THEY WON'T CATCH THE WIND."]
            return
        }
        let d = (d % 8 + 8) % 8
        if d == wind || (wind + 1) % 8 == d || (wind + 7) % 8 == d {
            v.said = ["THE WIND IS OUT OF THE \(CompassPoint.names[wind]).", "YOU CANNOT SAIL TO THE \(CompassPoint.names[d])."]
            return
        }
        // Without a compass, two times in three the helmsman guesses.
        v.sails = !hasCompass && rng.rnd(3) != 0 ? rng.rnd(8) : d
    }

    /// 860-868
    private mutating func fire(_ v: inout Voyage) {
        switch v.happening {
        case .ships, .pirates:
            seaBattle(&v)
        case .flyers:
            if rng.rnd(2) == 1 {
                flyersAttack(&v)
            } else {
                v.said = ["THEY WERE STARTLED CAP'N AND FLEW AWAY. WHAT NOW?"]
                v.happening = nil
            }
        case .argorion:
            v.said = ["I THINK HE WAS RATHER ANNOYED, SIR. WE HAD BETTER BE CAREFUL FROM NOW ON. WHAT NOW?"]
            v.happening = nil
        case .seaMonster:
            monsterFrightened(&v)
        default:
            v.said = ["THE NATIVE FISHERMEN WERE VERY IMPRESSED SIR. WHAT NOW?"]
        }
    }

    /// 840-845
    private mutating func divers(_ v: inout Voyage) {
        if let orb = v.orbAt, abs(v.x - orb.x) + abs(v.y - orb.y) < 4 {
            v.said = ["THE DIVERS HAVE RECOVERED A JEWEL ENCRUSTED ORB, CAP'N. WHAT SHALL WE DO NOW?"]
            v.orbAt = nil
            hasOrb = true
        } else if rng.rnd(2) == 1 {
            v.said = ["SHARKS!!! ONE MAN WAS KILLED BUT I GOT THE OTHERS OUT SAFELY SIR. I DON'T THINK WE SHOULD DIVE HERE."]
            loseMen(1)
        } else {
            v.said = ["THE MEN REALLY ENJOYED THE SWIM SIR. WHAT SHALL WE DO NOW?"]
        }
    }

    /// 850-852, 20900-20925: land, if there is land within reach.
    private mutating func land(_ v: inout Voyage) {
        let near = stride(from: -20, through: 20, by: 2).contains { dy in
            stride(from: -20, through: 20, by: 2).contains { dx in
                dx * dx + dy * dy <= 400 && SeaChart.ground(x: v.x + dx, y: v.y + dy) == .land
            }
        }
        guard near else {
            v.said = ["'BEG PARDON SIR, BUT WHAT SHALL WE LAND ON? THE NEAREST LAND IS STILL SOME LEAGUES AWAY."]
            return
        }
        if v.x <= 50 && v.y <= 55 {                                    // the Isle of Lapour
            if hasOrb {
                goToLapour(&v)
            } else {
                v.question = .lapour
            }
            return
        }
        if v.x >= 150 && v.y >= 100 {                                  // home
            v.said = ["SORRY, THE LOCAL SHIPBUILDERS UNION WILL NOT ALLOW YOU TO LAND HERE."]
            return
        }
        if v.happening == .storm { v.happening = nil }
        v.said = ["LANDING PARTY ASHORE."]
        v.anchored = true
        if rng.rnd(4) == 0 || v.landings > 2 {
            v.happening = .temple
            v.said.append("YOU'VE MADE YOUR WAY TO A GIGANTIC OLD TEMPLE. A POWERFUL WIZARD GUARDS THE CATACOMBS BENEATH THE TEMPLE. HE REFUSES TO LET YOU IN. WHAT WILL YOU DO?")
        } else {
            v.landings += 1
            v.said.append("THE ISLAND WAS DESERTED, SIRE, BUT WE DID STOCK UP ON FRUIT AND WATER.")
            party.inventory[Item(14), default: 0] += 40
        }
    }

    private func goToLapour(_ v: inout Voyage) {
        v.happening = nil
        v.said = ["LANDING PARTY ASHORE!"]
        v.ashore = .fortress
    }

    /// The landing party goes where it has got to: into the catacombs, or up Lapour.
    private mutating func landingParty() {
        switch voyage?.ashore {
        case .catacombs? where catacombs == nil: enterCatacombs()
        case .fortress? where fortress == nil: landOnLapour()
        default: break
        }
    }

    /// Back aboard from the catacombs or Lapour (20055, 2520).
    public mutating func returnToShip() {
        catacombs = nil
        fortress = nil
        guard var v = voyage, v.ashore != nil else { return }
        v.ashore = nil
        v.happening = nil
        v.said = []
        voyage = v
    }

    // MARK: Encounters played out

    /// 1240: they shred the sails.
    private func flyersAttack(_ v: inout Voyage) {
        v.said = ["THEY WERE STARTLED AND ATTACKED THE SHIP. THE SAILS ARE SHREDDED. WHAT NOW?"]
        v.sails = nil
        v.sailsTorn = true
        v.happening = nil
    }

    /// 1270
    private mutating func monsterFrightened(_ v: inout Voyage) {
        v.happening = nil
        v.said = ["HE WAS FRIGHTENED AWAY, SIR, BUT HE TOOK TWO MEN WITH HIM."]
        loseMen(2)
    }

    /// 1860-1870
    private mutating func shipsPass(_ v: inout Voyage) {
        if rng.rnd(2) == 1 {
            pirates(&v)
        } else {
            v.said = ["SINCE YOU ARE JUST SAILING AWAY, THEY TOO WENT ON THEIR WAY."]
            sailOff(&v)
        }
    }

    /// 1880
    private func pirates(_ v: inout Voyage) {
        v.happening = .pirates
        v.said.append("THE SHIPS ARE PIRATES! THEY COMMAND YOU TO PUT ALL OF YOUR TREASURE OVER THE SIDE ONTO ONE OF THEIR BOATS. WHAT WILL YOU DO?")
    }

    /// 595: whoever it was sails off, leaving the ship at anchor.
    private func sailOff(_ v: inout Voyage) {
        v.happening = nil
        v.anchored = true
    }

    /// 20050-20076: three of them sink, but not before landing some shots.
    private mutating func seaBattle(_ v: inout Voyage) {
        var hits = 0
        for _ in 1...3 {
            while rng.rnd(5) >= 2 { hits += 1 }
        }
        shipsSunk += 3
        let cost = min(50 * hits, party.gold)
        party.gold -= cost
        v.happening = nil
        v.said = ["YOU DESTROYED THEM, BUT YOUR SHIP IS DAMAGED. IT COST YOU \(cost) QUADROONS TO GET THE NECESSARY REPAIR MATERIALS FROM SOME FISHERMEN."]
        wreckage(&v)
    }

    /// 4500-4850
    private mutating func wreckage(_ v: inout Voyage) {
        guard rng.rnd(2) == 1 else {
            v.said.append("IT LOOKS LIKE EVERYTHING OF VALUE WENT DOWN WITH THE SHIPS. WHAT DO YOU WANT TO DO?")
            return
        }
        v.said.append("MUCH OF THE WRECKAGE STAYED AFLOAT FOR AWHILE. YOU MANAGED TO SAVE THE FOLLOWING ITEMS:")
        var found: [Int] = []
        for _ in 1...7 {
            var c = rng.rnd(30)
            if found.contains(c) { c = 0 }
            if rng.rnd(4) == 0 { c = 0 }
            if c == Item.contract.id { c = Item.quadroon.id }
            found.append(c)
        }
        for id in found where id != 0 {
            let n = id == Item.quadroon.id ? 400 + rng.rnd(1000) : 3 + rng.rnd(10)
            party.inventory[Item(id), default: 0] += n
            v.said.append("\(n) \(Item(id).name(quantity: n))")
        }
    }

    // MARK: Answers

    /// Answer the question put.
    public mutating func answer(_ a: SeaAnswer) {
        guard var v = voyage, let q = v.question, q.answers.contains(a) else { return }
        v.question = nil
        v.said = []
        defer { landingParty() }
        defer { voyage = v }
        switch (q, a) {
        case (.merchants, .buy):
            market = Market(atSeaWith: party.men, rng: &rng)
        case (.merchants, .attack):
            party.alignment -= 5
            seaBattle(&v)
        case (.merchants, _):
            sailOff(&v)

        // A raft (1600-1675).
        case (.raft, .ignore):
            party.alignment -= 2
        case (.raft, .kill):
            party.alignment -= 4
            if rng.rnd(3) == 0 {
                v.said = ["THEY WERE WEAK FROM EXPOSURE AND WERE EASILY MURDERED."]
            } else {
                let lost = min(1 + rng.rnd(4), party.men - 1)
                v.said = ["THEY PUT UP A GOOD FIGHT BUT FINALLY WERE ALL KILLED. YOU LOST \(lost) MEN IN THE FIGHT."]
                loseMen(lost)
            }
            v.question = .raftChest
        case let (.raft(n), _):
            party.alignment += 2
            if rng.rnd(2) == 0 {
                v.said = ["THEY ARE MERCENARIES AND WILL JOIN YOUR QUEST. THEY ALL HAVE SWORDS."]
                party.men += n
                recruited += n
                party.inventory[Item(22), default: 0] += n
                v.question = .raftChest
            } else {
                v.said = ["IT WAS A RUSE! THEY JUST WANTED TO DISTRACT YOU WHILE THEIR SHIPS CAME ALONGSIDE."]
                pirates(&v)
            }
        case (.raftChest, .open):
            chest(rng.rnd(4), &v)
        case (.raftChest, _):
            break

        // Hailing (880-886).
        case (.hail, .challenge):
            party.alignment -= 2
            if rng.rnd(3) == 0 {
                pirates(&v)
            } else {
                v.said = [rng.rnd(2) == 1
                    ? "THEY WERE MERCENARIES BUT WERE ANNOYED BY OUR UNFRIENDLY ATTITUDE."
                    : "THEY WERE PIRATES, BUT WERE FRIGHTENED OFF BY OUR ALERT AND AGGRESSIVE ATTITUDE."]
                sailOff(&v)
            }
        case (.hail, _):
            if rng.rnd(2) == 1 {
                pirates(&v)
            } else {
                let n = party.charisma + rng.rnd(10)
                v.said = ["THEY ARE MERCENARIES. \(n) OF THEM WISH TO JOIN YOUR FORCE, SIR. THEY ARE ALL ARMED."]
                party.men += n
                recruited += n
                party.inventory[Item(22), default: 0] += n
                sailOff(&v)
            }

        case (.lapour, .yes):
            goToLapour(&v)
        default:
            break
        }
    }

    /// 4010-4050: what a raft's chest holds.
    private mutating func chest(_ r: Int, _ v: inout Voyage) {
        switch r {
        case 0:
            let gold = 500 + rng.rnd(500)
            party.gold += gold
            v.said.append("CONGRATULATIONS! THE CHEST CONTAINED \(gold) QUADROONS OF GOLD.")
        case 1:
            v.said.append("THE CHEST IS FULL OF SODDEN MILDEWED CLOTHES. TOTALLY WORTHLESS.")
        default:
            if r == 2 {
                v.said.append("THE MAN OPENING THE CHEST GOT A SPLINTER OF IT IN HIS HAND AND DIED INSTANTLY. IT MUST BE POISONED OR ENCHANTED.")
                loseMen(1)                              // (the original forgets to count him)
            }
            let item = Item(39 + rng.rnd(9))
            party.inventory[item, default: 0] += 1
            v.said.append("THE CHEST CONTAINS A \(item.name).")
        }
    }

    /// 8200-8230: offer the fishermen something to pull the ship off. They take it
    /// if it's over 199 or a third of what the party has. (The original lets them
    /// work for the offer alone.)
    public mutating func pay(_ amount: Int) {
        guard var v = voyage, v.question == .fishermen else { return }
        v.question = nil
        defer { voyage = v }
        if amount > 199 || amount >= party.gold / 3 {
            party.gold -= min(max(amount, 0), party.gold)
            v.said = ["THEY GOT YOU FREE. WHAT NOW CAPTAIN?"]
            v.happening = nil
            // Towed back along the wake, well clear of the shoal.
            v.x = v.afloat[0]
            v.y = v.afloat[1]
            v.afloat = [v.x, v.y]
        } else {
            v.said = ["YOU'VE GOT TO BE KIDDING. IT'S NOT EASY PULLING A SHIP OFF THE MUD FLATS. THE FISHERMEN ARE SAILING AWAY."]
        }
    }

    // MARK: Using things at sea

    /// 760-765: use something. Offering (767) is the same, except to Argorion and to
    /// pirates, who are offered things over the side.
    public mutating func useAtSea(_ item: Item, offering: Bool = false) {
        guard var v = voyage, v.question == nil, !v.lost, (party.inventory[item] ?? 0) > 0 else { return }
        v.said = []
        defer { landingParty() }
        defer { voyage = v }
        let id = item.id
        if v.happening == .temple {
            templeUse(item, offering: offering, &v)
            return
        }
        switch v.happening {
        case _ where id == 19 && v.sailsTorn:
            useUp(item, 1)
            v.sailsTorn = false
            if v.happening == .rottenSails { v.happening = nil }
            v.said = ["CONTINUE YOUR JOURNEY."]
        case _ where id == 14 && v.scurvy != nil:
            let n = min(party.men / 10 + 1, party.inventory[item] ?? 0)
            useUp(item, n)
            v.scurvy = nil
            v.said = ["THE FRUIT SEEMS TO HAVE TAKEN CARE OF THE SCURVEY PROBLEM.",
                      "THERE ARE ONLY \(party.inventory[item] ?? 0) OF THEM LEFT THOUGH."]
        case .aground? where item == .quadroon:
            v.question = .fishermen
        case .flyers? where [41, 42, 46, 47].contains(id):
            useUp(item, 1)
            v.happening = nil
            v.said = ["THAT SEEMS TO HAVE TAKEN CARE OF THEM, SIR. THEY WERE BLASTED INTO ASHES!",
                      "UNFORTUNATELY, THE \(item.name) WAS TOO. WHAT NOW, SIR?"]
        case .whirlpool? where [40, 39, 46].contains(id):
            v.happening = nil
            v.said = ["THAT SEEMS TO HAVE DONE IT, SIR. THE WATERS ARE CALMING AND WE ARE FREE. WHAT NOW?"]
        case .seaMonster? where [39, 42, 46, 1].contains(id):
            if item == .foodPack { useUp(item, 1) }
            v.happening = nil
            v.said = ["HE LEFT, SIR!"]
        default:
            v.said = ["USING YOUR \(item.name) SERVED NO USEFUL PURPOSE. NOW WHAT?"]
        }
    }

    /// 770-778: put some of something over the side: for pirates, for Argorion, for a
    /// hungry monster, or just to be rid of it.
    public mutating func putOver(_ item: Item, quantity: Int) {
        guard var v = voyage, v.question == nil, !v.lost, quantity >= 1, quantity <= (party.inventory[item] ?? 0)
        else { return }
        v.said = []
        defer { voyage = v }
        if v.happening == .pirates && item == .quadroon {
            payPirates(quantity, &v)
            return
        }
        useUp(item, quantity)
        switch v.happening {
        case .argorion?:
            // 1380-1385: whatever he is given, he tells where the orb lies; here never
            // on land, where no diver could reach it.
            var orb: (x: Int, y: Int)
            repeat {
                orb = (100 + rng.rnd(100), 50 + rng.rnd(50))
            } while Expedition.aground(x: orb.x, y: orb.y)
            v.orbAt = orb
            v.happening = nil
            v.said = ["A RARE TREASURE CAN BE FOUND ON THE SEA FLOOR AT LATITUDE \(orb.y) AND LONGITUDE \(orb.x)."]
        case .seaMonster? where item == .foodPack:
            v.happening = nil
            v.said = ["HE LEFT, SIR!"]
        default:
            break
        }
    }

    /// 1890-1920
    private mutating func payPirates(_ n: Int, _ v: inout Voyage) {
        let gold = party.gold
        if n < gold / 2 {
            v.said = ["THEY'RE LAUGHING CAPTAIN. I DON'T THINK THEY WERE FOOLED. WHAT SHALL WE DO?"]
            return
        }
        defer { sailOff(&v) }
        if gold < 200 {
            v.said = ["THEY'RE LAUGHING CAPTAIN. THEY ARE GOING OFF TO LOOK FOR RICHER PREY. THEY SAID TO KEEP OUR MEASLY \(n) QUADROONS."]
            return
        }
        party.gold -= n
        if party.gold == 0 {
            v.said = ["THEY SEEM SATISFIED SIR. DON'T YOU THINK WE COULD HAVE TRIED SAVING A LITTLE OF IT FOR AN EMERGENCY THOUGH?"]
        } else {
            v.said = ["THEY WERE COMPLETELY FOOLED, CAP'N. WE STILL HAVE \(party.gold) QUADROONS LEFT AND THEY'VE GONE."]
        }
    }

    // MARK: The wizard's temple (21000-22000)

    private mutating func templeUse(_ item: Item, offering: Bool, _ v: inout Voyage) {
        guard offering else {
            v.said = ["OK, YOU USED YOUR \(item.name). YOU STILL CAN'T GET IN. NOW WHAT?"]
            return
        }
        useUp(item, 1)
        v.said = ["HE ACCEPTED ONE OF YOUR \(item.name(quantity: 2))"]
        if (39...47).contains(item.id) {
            v.said += ["HE WILL LET YOU ENTER THE CATACOMBS.", "IT'S VERY DARK IN THERE."]
            v.happening = nil
            v.ashore = .catacombs
        } else {
            v.said.append("HE STILL WON'T LET YOU IN THOUGH. WHAT NOW?")
        }
    }

    /// At the temple: A attacks the wizard (21040), L leaves (21110).
    public mutating func templeAttack() {
        guard var v = voyage, v.happening == .temple else { return }
        let n = 2 + rng.rnd(3)
        v.said = ["THE ATTACK WAS ILL ADVISED, SIRE. HE BLASTED \(n) MEN WITH A LIGHTNING BOLT AND WAS COMPLETELY UNHARMED HIMSELF. WHAT NOW?"]
        voyage = v
        loseMen(n)
    }

    public mutating func templeLeave() {
        guard var v = voyage, v.happening == .temple else { return }
        v.said = ["BACK TO THE SHIP!"]
        v.happening = nil
        voyage = v
    }

    private mutating func useUp(_ item: Item, _ n: Int) {
        party.inventory[item] = max((party.inventory[item] ?? 0) - n, 0)
    }
}
