import Foundation
import Testing
@testable import OdysseyKit

/// A bot plays whole quests through the public rules, as a player would: outfit the
/// party, raid sites for gold and magic, buy the ship and a crew, sail, win the
/// wizard's favour or Argorion's secret, find the orb, and storm the fortress.
/// Whatever stops it is reported.
struct PlaythroughTests {
    struct Bot {
        var e: Expedition
        var pick: SeededRandom
        var log: [String] = []
        var steps = 0
        var barred: Set<Cell> = []
        var verbose = false

        init(seed: UInt64) {
            e = Expedition(seed: seed)
            pick = SeededRandom(seed: seed &* 101)
        }

        mutating func note(_ s: String) { log.append("[\(steps)] \(s)") }
        var lastWords: [String] = []
        /// Take the news, remembering the last of it (how the party was lost).
        mutating func listen() {
            let n = e.takeNews()
            if !n.isEmpty { lastWords = n }
        }
        var over: Bool { e.isLost || e.ending != nil || steps > 400_000 }
        func has(_ id: Int) -> Int { e.party.inventory[Item(id)] ?? 0 }

        // MARK: The island

        /// Deal with whatever holds the party on the island.
        mutating func settle() {
            var guardCount = 0
            while let v = e.visit, !over, guardCount < 400 {
                guardCount += 1
                steps += 1
                let menBefore = e.party.men
                defer {
                    if e.party.men < menBefore {
                        note("men \(menBefore) -> \(e.party.men) at \(v.site.map { "\($0)" } ?? "road") \("\(v.stage)".prefix(60)): \(e.visit?.said ?? [])")
                    }
                }
                let usable = v.canUseItems
                switch v.stage {
                case .door:
                    if let key = v.opens.first(where: { has($0.id) > 0 }) { e.act(.use(key)) } else { e.act(.leave) }
                case .hutDoor: e.act(.enter)
                case let .hutOffer(item, price):
                    // Magic for the wizard is worth some gold, but not the ship.
                    let magic = (39...47).contains(item.id) && magicCount == 0
                    e.act(magic && e.party.gold - price > 400 ? .accept : .decline)
                case .searching: e.act(e.party.men < 9 || has(7) == 0 && e.party.men < 14 ? .leave : .search)
                case .altar: e.act(.take)
                case .chest, .spoils: e.act(.open)
                case .pit:
                    if let r = [7, 18, 19].first(where: { has($0) > 0 }) { e.act(.use(Item(r))) } else { e.act(.carryOn) }
                case .monstersAhead:
                    e.act(has(26) > 0 && e.party.men >= 12 ? .attack : .slipAway)
                case .offering: e.act(.offerFood)
                case let .battle(b):
                    // Fight on while winning; run when outmatched.
                    let ours = b.ourStanding * (b.ourArms + b.ourStrength)
                    let theirs = b.theirStanding * (b.theirArms + b.theirStrength)
                    e.act(ours >= theirs ? .fight : .run)
                case .caravan: e.act(.ignore)
                case let .wizard(good):
                    let mind = e.party.alignment.signum()
                    e.act(mind == 0 || mind == (good ? 1 : -1) ? .requestAid : .leave)
                case .warriors: e.act(e.party.men < 24 ? .beFriendly : .ignore)
                case let .trapped(trap, _):
                    if let i = trap.frees.first(where: { has($0.id) > 0 }) { e.act(.use(i)) } else { e.act(.carryOn) }
                case let .obstacle(o):
                    if let i = o.clears.first(where: { has($0.id) > 0 }) {
                        e.act(.use(i))
                    } else {
                        barred.insert(v.cell)
                        e.act(.leave)
                    }
                case .readyToSail: e.act(.accept)
                case .finished: e.act(.leave)
                case .amulet: e.act(.decline)
                case .charm: e.act(.saveIt)
                }
                _ = usable
                if e.visit?.stage == v.stage && e.visit?.said == v.said, case .finished = v.stage { e.visit = nil }
            }
            listen()
        }

        var magicCount: Int { (39...47).reduce(0) { $0 + has($1) } }

        /// Cells on the way from here to `goal`, over land, round known obstacles.
        func route(to goal: Cell) -> [Cell]? {
            var came: [Cell: Cell] = [:]
            var queue = [e.cell]
            var seen: Set<Cell> = [e.cell]
            while !queue.isEmpty {
                let c = queue.removeFirst()
                if c == goal { break }
                for (_, dc, dr) in Island.compass where dc == 0 || dr == 0 {
                    let n = Cell(col: c.col + dc, row: c.row + dr)
                    guard n.isOnMap, !seen.contains(n), e.island.terrain(n) != .ocean,
                          e.island.obstacles[n] == nil, !barred.contains(n) else { continue }
                    seen.insert(n)
                    came[n] = c
                    queue.append(n)
                }
            }
            guard seen.contains(goal) else { return nil }
            var path = [goal]
            while let p = came[path[0]], p != e.cell { path.insert(p, at: 0) }
            return path
        }

        /// Walk to a cell, dealing with what turns up. Returns whether the party got there.
        mutating func walk(to goal: Cell) -> Bool {
            for _ in 0..<6 {
                guard let path = route(to: goal) else { return false }
                var ok = true
                for cell in path {
                    var tries = 0
                    while e.cell != cell && !over && tries < 300 {
                        tries += 1
                        steps += 1
                        let (cx, cy) = cell.center
                        let dx = cx - e.x, dy = cy - e.y
                        let len = (dx * dx + dy * dy).squareRoot()
                        let men = e.party.men
                        e.walk(dx: dx / len, dy: dy / len, dt: 0.2)
                        if e.party.men < men { note("men \(men) -> \(e.party.men) walking: \(e.visit?.question ?? "") \(lastWords)") }
                        listen()
                        settle()
                        if e.market != nil { e.leaveMarket() }
                        if e.island.obstacles[cell] != nil { ok = false; break }
                    }
                    if !ok || e.cell != cell { ok = false; break }
                }
                if ok && e.cell == goal { return true }
                if over { return false }
            }
            return e.cell == goal
        }

        /// Buy up to `n` of an item here, at the asking price.
        @discardableResult
        mutating func buy(_ id: Int, _ n: Int, keep: Int = 0) -> Int {
            guard let m = e.market, let lot = m.lots.first(where: { $0.item.id == id && !$0.withdrawn && $0.quantity > 0 })
            else { return 0 }
            let afford = (e.party.gold - keep) / max(lot.price, 1)
            var q = min(n, lot.quantity, afford)
            while q > 0 {
                if e.buy(lot: lot.id, quantity: q, at: lot.price) == .sold { return q }
                q -= 1
            }
            return 0
        }

        /// A visit to a city's bazaar.
        mutating func shop(city: Cell, final: Bool) {
            guard walk(to: city) else {
                note("couldn't walk to the city at \(city) from \(e.cell) (barred \(barred.count), obstacles \(e.island.obstacles.count))")
                return
            }
            e.visit = nil
            for round in 0..<(final ? 12 : 2) {
                e.enterMarket()
                if has(26) == 0 { buy(26, 1) }                  // a long bow: arms of 6
                if has(2) == 0 { buy(2, 1) }                    // lock pick
                if has(11) == 0 { buy(11, 1) }                  // oil lamp
                if has(8) == 0 { buy(8, 1) }                    // shovel
                if has(7) == 0 { buy(7, 1) }                    // rope
                let wanted = max(30, e.party.men * 2)
                if e.party.foodPacks < wanted { buy(1, wanted - e.party.foodPacks) }
                if final {
                    if has(15) == 0 { buy(15, 1, keep: 2800) }   // compass
                    if has(.ship) == 0 && e.cell == Island.shipCity { buy(Item.ship.id, 1) }
                    if has(.ship) > 0 {
                        for id in [4, 25, 13, 18, 19, 14, 10, 16] where has(id) == 0 { buy(id, 1, keep: 150) }
                        if e.party.men < 22 { buy(5, 22 - e.party.men, keep: 100) }
                    }
                }
                e.leaveMarket()
                if final && has(.ship) > 0 && e.party.men >= 16 && round > 1 { break }
            }
        }

        func has(_ item: Item) -> Int { e.party.inventory[item] ?? 0 }

        /// Raid the sites, nearest first, for gold and magic.
        mutating func raid(until gold: Int) {
            var tried: Set<Cell> = []
            while e.party.gold < gold || magicCount == 0, !over {
                let open = e.island.sites.filter {
                    $0.site != .city && !e.island.isSealed($0.cell) && !tried.contains($0.cell)
                }
                guard let next = open.min(by: { dist($0.cell) < dist($1.cell) }) else { break }
                tried.insert(next.cell)
                guard walk(to: next.cell) else { continue }
                e.arrive()
                settle()
                if e.party.foodPacks < e.party.men * 2, let city = nearestCity() { shop(city: city, final: false) }
            }
        }

        func dist(_ c: Cell) -> Int { abs(c.col - e.cell.col) + abs(c.row - e.cell.row) }
        func nearestCity() -> Cell? {
            e.island.sites.filter { $0.site == .city }.map(\.cell).min { dist($0) < dist($1) }
        }

        // MARK: At sea

        mutating func answerAtSea() {
            guard let v = e.voyage else { return }
            if let q = v.question {
                switch q {
                case .merchants:
                    if v.sailsTorn || has(19) == 0 {
                        e.answer(.buy)
                        if has(19) == 0 { buy(19, 1) }
                        if has(14) < 10 { buy(14, 10) }
                        e.leaveMarket()
                    } else {
                        e.answer(.ignore)
                    }
                case .raft: e.answer(.takeAboard)
                case .raftChest: e.answer(.open)
                case .hail: e.answer(.friendly)
                case .fishermen: e.pay(max(e.party.gold / 3 + 1, 0))
                case .lapour: e.answer(e.hasOrb ? .yes : .no)
                }
                return
            }
            switch v.happening {
            case .ships?, .pirates?: e.command(.fire)
            case .flyers?:
                if let m = [41, 42, 46, 47].first(where: { has($0) > 0 && magicCount > 1 }) { e.useAtSea(Item(m)) } else { e.command(.fire) }
            case .seaMonster?: e.useAtSea(.foodPack)
            case .argorion?: e.putOver(.foodPack, quantity: 1)
            case .aground?: e.useAtSea(.quadroon)
            case .rottenSails?: if has(19) > 0 { e.useAtSea(Item(19)) }
            case .whirlpool?: if let m = [40, 39, 46].first(where: { has($0) > 0 && magicCount > 1 }) { e.useAtSea(Item(m)) }
            case .temple?:
                if let m = (39...47).first(where: { has($0) > 0 }) {
                    e.useAtSea(Item(m), offering: true)
                } else {
                    e.templeLeave()
                }
            default: break
            }
            if v.scurvy != nil && has(14) > 0 { e.useAtSea(Item(14)) }
            if v.sailsTorn && has(19) > 0 { e.useAtSea(Item(19)) }
            if let w = e.voyage, w.sailsTorn, has(19) == 0, !w.anchored, w.question == nil { e.command(.anchor) }
        }

        /// A way through open water from here to a chart position, as waypoints 4 pixels
        /// apart, clear of the shallows.
        func seaRoute(toX tx: Int, y ty: Int) -> [(Int, Int)]? {
            guard let v = e.voyage else { return nil }
            func key(_ x: Int, _ y: Int) -> Int { y / 4 * 100 + x / 4 }
            func clear(_ x: Int, _ y: Int) -> Bool {
                (14...266).contains(x) && (14...150).contains(y) && !Expedition.aground(x: x, y: y)
                    && !Expedition.aground(x: x + 2, y: y) && !Expedition.aground(x: x, y: y + 2)
                    && !Expedition.aground(x: x - 2, y: y) && !Expedition.aground(x: x, y: y - 2)
            }
            let start = (v.x / 4 * 4 + 2, v.y / 4 * 4 + 2), goal = key(tx, ty)
            var came: [Int: (Int, Int)] = [key(start.0, start.1): start]
            var queue = [start], at: (Int, Int)?
            var head = 0
            while head < queue.count {
                let c = queue[head]
                head += 1
                if key(c.0, c.1) == goal || (abs(c.0 - tx) <= 4 && abs(c.1 - ty) <= 4) { at = c; break }
                for (dx, dy) in [(4, 0), (-4, 0), (0, 4), (0, -4), (4, 4), (-4, 4), (4, -4), (-4, -4)] {
                    let n = (c.0 + dx, c.1 + dy)
                    guard came[key(n.0, n.1)] == nil, clear(n.0, n.1) else { continue }
                    came[key(n.0, n.1)] = c
                    queue.append(n)
                }
            }
            guard var c = at else { return nil }
            var path = [c]
            while let p = came[key(c.0, c.1)], key(p.0, p.1) != key(c.0, c.1) {
                path.insert(p, at: 0)
                c = p
            }
            return path
        }

        /// Sail along a sea route to a chart position.
        mutating func voyage(toX tx: Int, y ty: Int, near: Int) -> Bool {
            for _ in 0..<5 {
                guard let v = e.voyage else { return false }
                if abs(v.x - tx) + abs(v.y - ty) <= near { return true }
                guard let route = seaRoute(toX: tx, y: ty) else { note("no sea route from \(v.x),\(v.y) to \(tx),\(ty)"); return false }
                var ok = true
                for (i, w) in route.enumerated() where i % 3 == 2 || i == route.count - 1 {
                    if !sail(toX: w.0, y: w.1, near: i == route.count - 1 ? near : 3) { ok = false; break }
                }
                if ok { return true }
                if over || e.voyage?.ashore != nil { return false }
            }
            return false
        }

        /// Sail towards a chart position; returns when within `near` pixels, or stuck.
        mutating func sail(toX tx: Int, y ty: Int, near: Int) -> Bool {
            var tack = 1, best = Int.max, since = 0
            for _ in 0..<1500 where !over {
                steps += 1
                guard let v = e.voyage, v.ashore == nil else { return false }
                if v.lost { e.recoverShip(); note("lost over the edge; recovered"); return false }
                if e.market != nil { e.leaveMarket() }
                if v.question != nil || (v.happening != nil && v.happening != .fog && v.happening != .storm
                                          && v.happening != .nearEdge) {
                    answerAtSea()
                    // Torn sails and no spare: wait at anchor for merchantmen.
                    if let w = e.voyage, w.sailsTorn, !w.anchored, w.question == nil, has(19) == 0 { e.command(.anchor) }
                    e.sail(dt: 0.5)
                    continue
                }
                let d = abs(v.x - tx) + abs(v.y - ty)
                if verbose && steps % 5 == 0 {
                    note("at \(v.x),\(v.y) -> \(tx),\(ty) sails \(v.sails.map(String.init) ?? "-") wind \(v.wind.map(String.init) ?? "-") anchored \(v.anchored) said \(v.said)")
                }
                if d <= near { return true }
                if d < best { best = d; since = 0 } else { since += 1 }
                if since > 60 { tack = -tack; since = 0; best = d }
                // The point of the compass nearest the target, off the wind if need be.
                let bearing = atan2(Double(tx - v.x), Double(v.y - ty))
                let ideal = bearing / (.pi / 4)
                // The sailable point nearest the bearing whose next pixels are open water.
                let candidates = (0..<8).filter { p in
                    guard let w = v.wind, p != w, (w + 1) % 8 != p, (w + 7) % 8 != p else { return false }
                    let s = CompassPoint.step(p)
                    return (1...8).allSatisfy { !Expedition.aground(x: v.x + s.dx * $0, y: v.y + s.dy * $0) }
                }
                func off(_ p: Int) -> Double {
                    let d = abs(Double(p) - ideal).truncatingRemainder(dividingBy: 8)
                    return min(d, 8 - d) + (tack > 0 ? 0.01 * Double(p) : -0.01 * Double(p))
                }
                guard let point = candidates.min(by: { off($0) < off($1) }) else {
                    // Nowhere to go with this wind: wait at anchor for it to change.
                    if e.voyage?.anchored == false { e.command(.anchor) }
                    e.sail(dt: 0.5)
                    continue
                }
                if v.sails != point && !v.sailsTorn { e.command(.setSails(point)) }
                if e.voyage?.anchored == true { e.command(.anchor) }
                e.sail(dt: 0.5)
                if e.voyage?.happening == .aground { answerAtSea() }
            }
            if let v = e.voyage {
                note("sailing to \(tx),\(ty) stuck at \(v.x),\(v.y): sails \(v.sails.map(String.init) ?? "reefed"), wind \(v.wind.map(String.init) ?? "calm"), torn \(v.sailsTorn), anchored \(v.anchored), \(v.happening.map { "\($0)" } ?? "") \(v.question.map { "\($0)" } ?? "") current \(v.currentDirection)/\(v.currentSpeed)")
            }
            return false
        }

        /// The nearest land pixel to a point, off Lapour and the home island.
        func landing(from x: Int, _ y: Int, lapour: Bool) -> (Int, Int)? {
            var best: (Int, Int)?, bd = Int.max
            for py in stride(from: 8, to: 157, by: 2) {
                for px in stride(from: 8, to: 272, by: 2) where SeaChart.ground(x: px, y: py) == .land {
                    let isLapour = px <= 50 && py <= 55, home = px >= 150 && py >= 100
                    guard lapour ? isLapour : (!isLapour && !home) else { continue }
                    // A spot of open sea within reach of this land.
                    for (ox, oy) in [(0, 14), (0, -14), (14, 0), (-14, 0)] {
                        let sx = px + ox, sy = py + oy
                        guard !Expedition.aground(x: sx, y: sy), (12...268).contains(sx), (12...150).contains(sy) else { continue }
                        let d = abs(sx - x) + abs(sy - y)
                        if d < bd, !lapour || (sx <= 50 && sy <= 55) { bd = d; best = (sx, sy) }
                    }
                }
            }
            return best
        }

        // MARK: Below

        mutating func explore() {
            var tries = 0
            while let c = e.catacombs, !over, tries < 20000 {
                tries += 1
                steps += 1
                if let q = c.question { e.answerBelow(q == .teleport); continue }
                if !c.light { e.order(.light); continue }
                if c.atAltar { e.order(.get); note("took the orb"); continue }
                if c.exitHere { e.order(.out); note("out of the catacombs"); return }
                if c.stairway { e.order(.down); continue }
                if let t = c.trouble {
                    switch t {
                    case .pit: if has(7) > 0 { e.useBelow(Item(7)); continue }
                    case .caveIn: if has(8) > 0 { e.useBelow(Item(8)); continue }
                    }
                }
                if c.frenzies != nil, let m = [39, 46].first(where: { has($0) > 0 }) { e.useBelow(Item(m)); continue }
                if c.borer != nil, let m = [41, 42].first(where: { has($0) > 0 }) { e.useBelow(Item(m)); continue }
                if let said = e.catacombs?.said, e.party.men < c.said.count + 1000, said.contains(where: { $0.contains("KILLED") || $0.contains("PIT TRAP") || $0.contains("CAVEIN") || $0.contains("LEFT BEHIND") }) {
                    note("below: \(said) men \(e.party.men)")
                }
                if let a = c.altar {
                    // Head for the altar.
                    let dx = a.x - c.x, dy = a.y - c.y
                    let d = abs(dx) > abs(dy) || pick.rnd(3) == 0 ? (dx > 0 ? 1 : 3) : (dy > 0 ? 2 : 0)
                    e.creep(pick.rnd(4) == 0 ? pick.rnd(4) : d)
                } else {
                    e.creep(pick.rnd(4))
                }
                // Walled in after a cave-in with no way through: burrow, or teleport.
                let walls = [(0, -1), (1, 0), (0, 1), (-1, 0)].filter { e.catacombs?.isWall(c.x + $0.0, c.y + $0.1) ?? false }
                if walls.count == 4 { e.order(has(8) > 0 ? .burrow : .teleport) }
                let men = e.party.men
                e.catacombsTick(dt: 0.2)
                if e.party.men < men { note("below: men \(men) -> \(e.party.men): \(e.catacombs?.said ?? [])") }
                listen()
            }
        }

        mutating func storm() {
            while let f = e.fortress, !over, e.ending == nil {
                steps += 1
                if let h = f.hazard {
                    if let i = (h.clean + h.costly).first(where: { has($0) > 0 }) {
                        e.useAtFortress(Item(i))
                        note("used \(Item(i).name) on \(h)")
                    } else {
                        note("forced \(h)")
                        e.approach()
                    }
                } else {
                    e.approach()
                }
            }
        }

        // MARK: The quest

        mutating func play() {
            // Outfit, raid for gold and magic, then buy the ship and crew.
            if let city = nearestCity() { shop(city: city, final: false) }
            raid(until: 3600)
            note("raided: gold \(e.party.gold), men \(e.party.men), magic \(magicCount)")
            shop(city: Island.shipCity, final: true)
            if has(.ship) == 0 {
                note("couldn't afford the ship (gold \(e.party.gold))")
                raid(until: 4500)
                shop(city: Island.shipCity, final: true)
            }
            guard has(.ship) > 0, !over else { note("no ship"); return }
            e.visit = nil
            e.use(.ship)
            settle()
            guard e.voyage != nil else {
                note("couldn't sail: men \(e.party.men), at \(e.cell), visit \(String(describing: e.visit?.said))")
                return
            }
            note("at sea with \(e.party.men) men, gold \(e.party.gold), magic \(magicCount)")

            // Find the wizard's temple (or Argorion's secret), and the orb.
            var landings = 0
            while !e.hasOrb && !over && landings < 30 {
                if let orb = e.voyage?.orbAt {
                    if voyage(toX: orb.x, y: orb.y, near: 2) {
                        e.command(.divers)
                        if e.hasOrb { note("divers found the orb") }
                    }
                    continue
                }
                guard let v = e.voyage, let (lx, ly) = landing(from: v.x, v.y, lapour: false) else { note("nowhere to land"); return }
                guard voyage(toX: lx, y: ly, near: 3) else {
                    note("couldn't reach \(lx),\(ly) from \(e.voyage.map { "\($0.x),\($0.y)" } ?? "?")")
                    return
                }
                for _ in 0..<6 where e.catacombs == nil && !over {
                    landings += 1
                    e.command(.land)
                    if e.voyage?.happening == .temple {
                        note("the temple, with \(magicCount) magic")
                        answerAtSea()
                        if e.catacombs == nil { note("the wizard wouldn't let us in"); e.templeLeave() }
                        break
                    }
                }
                if e.catacombs != nil {
                    note("into the catacombs")
                    explore()
                }
            }
            guard e.hasOrb, !over else { note("no orb (men \(e.party.men))"); return }
            note("have the orb; men \(e.party.men)")

            // To Lapour.
            guard let v = e.voyage, let (lx, ly) = landing(from: v.x, v.y, lapour: true) else { note("can't find Lapour"); return }
            guard voyage(toX: lx, y: ly, near: 3) else { note("couldn't reach Lapour"); return }
            e.command(.land)
            if e.voyage?.question == .lapour { e.answer(.yes) }
            guard e.fortress != nil else { note("couldn't land on Lapour: \(e.voyage?.said ?? [])"); return }
            note("on Lapour with \(e.party.men) men")
            storm()
        }
    }

    @Test func wholeQuests() {
        var won = 0, reports: [String] = []
        for seed in 1...24 as ClosedRange<UInt64> {
            var bot = Bot(seed: seed)
            bot.play()
            let outcome = bot.e.ending.map { $0.won ? "WON score \($0.score)0" : "destroyed" }
                ?? (bot.e.isLost ? "all lost: \(bot.lastWords.last ?? "")" : "stopped")
            if bot.e.ending?.won == true { won += 1 }
            reports.append("seed \(seed): \(outcome)\n  " + bot.log.joined(separator: "\n  "))
        }
        // The quest is hard, as it was: most bots die on the island. Some should win.
        if won == 0 { print(reports.joined(separator: "\n")) }
        #expect(won >= 3)
    }
}
