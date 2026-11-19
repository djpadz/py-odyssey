import OdysseyKit
import Observation
import RealityKit
import SwiftUI

/// The running game: the quest, the 3D world, and the player's input.
@Observable @MainActor
final class GameModel {
    enum Phase: Equatable { case title, loading, playing, lost(String) }

    private(set) var phase = Phase.title
    private(set) var expedition: Expedition?
    /// The report in the original's words, refreshed whenever the party enters a new cell.
    private(set) var report = ""
    private(set) var siteHere: Site?
    private(set) var loadError: String?
    /// Camera yaw in radians; 0 looks north.
    private(set) var cameraYaw: Float = 0
    /// A passing message, such as a man starving.
    private(set) var toast: String?
    var showingInventory = false
    var inMarket: Bool { expedition?.market != nil }
    var visit: Visit? { expedition?.visit }
    var siteSealed: Bool { expedition.map { $0.island.isSealed($0.cell) } ?? false }
    /// What lies on the ground here, if anything.
    var lyingHere: (item: Item, quantity: Int)? { expedition.flatMap { $0.island.lying($0.cell) } }
    var mount: Mount? { expedition?.mount }
    /// The ground as a picture, for the map.
    var mapImage: CGImage? { world?.map }
    var voyage: Voyage? { expedition?.voyage }
    var atSea: Bool { expedition?.voyage != nil }

    /// Which part of the quest is on screen.
    enum Stage { case island, sea, catacombs, fortress, ended }
    var stage: Stage {
        guard let e = expedition else { return .island }
        if e.ending != nil { return .ended }
        if e.catacombs != nil { return .catacombs }
        if e.fortress != nil { return .fortress }
        return e.voyage != nil ? .sea : .island
    }
    /// The painted sea chart, for the map at sea.
    var chartImage: CGImage? { seaWorld?.map }
    /// Which way the party faces, radians clockwise from north.
    var partyHeading: Float { -heading }

    @ObservationIgnored private(set) var world: World?
    @ObservationIgnored private(set) var seaWorld: SeaWorld?
    /// (Observed, so their scenes appear once built.)
    private(set) var catacombWorld: CatacombWorld?
    private(set) var fortressWorld: FortressWorld?
    @ObservationIgnored private var nextCreep: Double = 0
    @ObservationIgnored var camera: PerspectiveCamera?
    @ObservationIgnored var updates: EventSubscription?

    // Input, sampled every frame.
    enum Move: Hashable { case forward, back, left, right }
    @ObservationIgnored var held: Set<Move> = []
    @ObservationIgnored var stick: SIMD2<Float> = .zero          // x right, y forward, length <= 1
    @ObservationIgnored private var cameraPitch: Float = 0.62
    @ObservationIgnored private var cameraDistance: Float = 34
    @ObservationIgnored private var cameraFocus: SIMD3<Float>?
    @ObservationIgnored private var heading: Float = 0
    @ObservationIgnored private var lastCell: Cell?
    @ObservationIgnored private var lastLying = 0
    @ObservationIgnored private var lookingUntil: Double = 0
    @ObservationIgnored private var toastUntil: Double = 0
    @ObservationIgnored private var clock: Double = 0
    @ObservationIgnored private var nextSave: Double = 0

    /// Start a quest. One started from the command line (`--quest`) is for looking at
    /// things, and doesn't save over the real one.
    func newQuest(seed: UInt64 = .random(in: 1...UInt64(UInt32.max)), meeting: String? = nil, saves: Bool = true) {
        var expedition = Expedition(seed: seed)
        #if DEBUG
        if let meeting { GameModel.rehearse(meeting, in: &expedition) }
        #endif
        start(expedition, saves: saves)
        showingInventory = meeting?.lowercased() == "inventory"
    }

    /// P: take up the saved quest where it was left.
    func continueQuest() {
        do {
            let saved = try JSONDecoder().decode(SavedQuest.self, from: Data(contentsOf: GameModel.saveURL))
            var expedition = saved.quest
            expedition.resume()
            heading = saved.heading
            start(expedition, saves: true)
        } catch {
            loadError = "The saved quest could not be read."
        }
    }

    private func start(_ expedition: Expedition, saves: Bool) {
        phase = .loading
        loadError = nil
        saving = saves
        self.expedition = expedition
        if !saves { heading = 0 }
        Task {
            do {
                if expedition.voyage != nil {
                    seaWorld = try await SeaWorld.build(seed: expedition.seed)
                    world = nil
                    cameraDistance = 70
                } else {
                    world = try await WorldBuilder.build(expedition)
                    seaWorld = nil
                }
                lastCell = nil
                cameraFocus = nil
                toast = nil
                showingInventory = false
                prepareStage()
                phase = .playing
            } catch {
                loadError = error.localizedDescription
                phase = .title
            }
        }
    }

    // MARK: Saving

    /// What goes in the save file.
    private struct SavedQuest: Codable {
        var version = 1
        var quest: Expedition
        var heading: Float
    }

    private static var saveURL: URL {
        URL.applicationSupportDirectory.appending(components: "Odyssey", "quest.json")
    }

    /// Whether there is a quest to continue.
    private(set) var hasSavedQuest = FileManager.default.fileExists(atPath: GameModel.saveURL.path)
    @ObservationIgnored private var saving = true

    /// Save the quest, if the party is free to be left: not haggling, not in the
    /// middle of something.
    func save() {
        guard saving, phase == .playing, let e = expedition, e.isFree else { return }
        do {
            try FileManager.default.createDirectory(at: GameModel.saveURL.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
            try JSONEncoder().encode(SavedQuest(quest: e, heading: heading)).write(to: GameModel.saveURL, options: .atomic)
            hasSavedQuest = true
        } catch {
            print("Couldn't save the quest: \(error)")
        }
    }

    /// The quest is over: there is nothing to continue.
    private func forgetSave() {
        guard saving else { return }
        try? FileManager.default.removeItem(at: GameModel.saveURL)
        hasSavedQuest = false
    }

    #if DEBUG
    /// `--meet <what>`, for looking at things: a monster by name or number (add `!` to
    /// attack it), caravan, wizard, warlock, warriors, chest, an obstacle's kind, or sealed.
    private static func rehearse(_ what: String, in e: inout Expedition) {
        var name = what.uppercased()
        let attack = name.hasSuffix("!")
        if attack { name.removeLast() }
        switch name {
        case "CARAVAN": e.rehearse(.caravan)
        case "WIZARD": e.rehearse(.wizard(good: true))
        case "WARLOCK": e.rehearse(.wizard(good: false))
        case "WARRIORS": e.rehearse(.warriors)
        case "CHEST": e.rehearse(.chest)
        case "HORSES":
            e.party.inventory[Item(20)] = 10
            _ = e.ride()
        case "RUG":
            e.party.inventory[Item(45)] = 1
            e.use(Item(45))
        case "STAFF":
            e.party.inventory[Item(47)] = 1
            e.party.wisdom = 9                   // so it doesn't blow up
            e.use(Item(47))
        case "TORCHES": e.rehearseLying(Item(33), 4)
        case "SEA": e.rehearseVoyage()
        case "SHIPS": e.rehearseVoyage(.ships)
        case "PIRATES": e.rehearseVoyage(.pirates)
        case "OCTOPUS": e.rehearseVoyage(.seaMonster(.octopus))
        case "SERPENT": e.rehearseVoyage(.seaMonster(.serpent))
        case "ARGORION": e.rehearseVoyage(.argorion)
        case "FLYERS": e.rehearseVoyage(.flyers(Monster(kind: 18)))
        case "FOG": e.rehearseVoyage(.fog)
        case "STORM": e.rehearseVoyage(.storm)
        case "WHIRLPOOL": e.rehearseVoyage(.whirlpool)
        case "RAFT": e.rehearseVoyage(question: .raft(men: 4))
        case "MERCHANTMEN": e.rehearseVoyage(question: .merchants)
        case "TEMPLE": e.rehearseVoyage(.temple)
        case "CATACOMBS": e.rehearseBelow()
        case "ALTAR": e.rehearseBelow(altar: true)
        case "LAPOUR": e.rehearseLapour()
        case "END":
            e.party.men = 40
            e.rehearseLapour(orb: true)
            for _ in 0..<8 { e.approach() }
        case "INVENTORY":
            for id in [20, 39, 40, 45, 47] { e.party.inventory[Item(id)] = 1 }
        case "SEALED": e.sealEverySite()
        case "TEMPLE", "RUIN", "CASTLE", "TOMB", "HUT":
            e.sealEverySite(standingBy: Site.allCases.first { $0.distantName == name })
        case "THICKET": e.rehearseObstacle(.thicket)
        case "RAVINE": e.rehearseObstacle(.ravine)
        case "BOG": e.rehearseObstacle(.bog)
        case "CREVASSE": e.rehearseObstacle(.crevasse)
        case "CLIFF": e.rehearseObstacle(.cliff)
        default:
            guard let kind = Int(name) ?? (1...20).first(where: { Monster(kind: $0).name.hasPrefix(name) }) else { return }
            e.rehearse(.monstersAhead(Monster(kind: kind)))
        }
        if attack { e.act(.attack) }
    }
    #endif

    func backToTitle() {
        phase = .title
        expedition = nil
        world = nil
        seaWorld = nil
        catacombWorld = nil
        fortressWorld = nil
    }

    /// The L command: also name the terrain round about.
    func look() {
        guard let e = expedition, !inMarket else { return }
        report = e.describe(looking: true)
        lookingUntil = clock + 8
    }

    // MARK: The market

    func enterMarket() {
        guard siteHere == .city else { return }
        held.removeAll()
        stick = .zero
        showingInventory = false
        expedition?.enterMarket()
    }

    func leaveMarket() {
        expedition?.leaveMarket()
        lastCell = nil                     // say where we are again
    }

    func offer(_ amount: Int, in haggle: inout Haggle) -> Reply? {
        expedition?.offer(amount, in: &haggle)
    }

    func buy(lot: Int, quantity: Int, at price: Int) -> Purchase? {
        defer { lastCell = nil }           // the larder may have changed
        return expedition?.buy(lot: lot, quantity: quantity, at: price)
    }

    // MARK: Sites

    func act(_ action: Action) {
        guard var e = expedition else { return }
        held.removeAll()
        e.act(action)
        expedition = e
        if e.market != nil {               // buying from a caravan
            stick = .zero
            showingInventory = false
        }
        hear(e.takeNews(), lost: e.isLost)
        lastCell = nil
        if e.voyage != nil && seaWorld == nil { setSail() }
    }

    /// 7050: away from the island; the sea is charted while the men cast off.
    private func setSail() {
        guard let e = expedition else { return }
        phase = .loading
        Task {
            do {
                seaWorld = try await SeaWorld.build(seed: e.seed)
                world = nil
                cameraFocus = nil
                cameraDistance = 70
                showingInventory = false
                save()
                phase = .playing
            } catch {
                loadError = error.localizedDescription
                phase = .title
            }
        }
    }

    // MARK: At sea

    /// Do something to the quest at sea, and hear what came of it.
    private func voyaging(_ change: (inout Expedition) -> Void) {
        guard var e = expedition else { return }
        change(&e)
        expedition = e
        if e.market != nil { showingInventory = false }
        hear(e.takeNews(), lost: e.isLost)
        prepareStage()
        save()
    }

    /// Build (or let go of) the scenes for the catacombs and the fortress as the
    /// landing party comes and goes; the quest's end leaves nothing to continue.
    private func prepareStage() {
        guard let e = expedition else { return }
        if e.catacombs != nil, catacombWorld == nil {
            catacombWorld = CatacombWorld(light: nil)
            cameraFocus = nil
        } else if e.catacombs == nil {
            catacombWorld = nil
        }
        if let f = e.fortress, fortressWorld == nil {
            Task {
                guard let sky = try? await WorldBuilder.makeSky() else { return }
                fortressWorld = FortressWorld(f, sky: sky)
                cameraFocus = nil
            }
        } else if e.fortress == nil {
            fortressWorld = nil
        }
        if e.ending != nil { forgetSave() }
    }

    // MARK: Below ground and on Lapour

    func creep(_ direction: Int) { voyaging { $0.creep(direction) } }
    func orderBelow(_ o: Expedition.CatacombCommand) { voyaging { $0.order(o) } }
    func answerBelow(_ yes: Bool) { voyaging { $0.answerBelow(yes) } }
    func approach() { voyaging { $0.approach() } }
    func retreat() { voyaging { $0.retreat() } }
    func confirmRetreat(_ yes: Bool) { voyaging { $0.confirmRetreat(yes) } }

    func useBelow(_ item: Item) {
        showingInventory = false
        voyaging { $0.useBelow(item) }
    }

    func putDown(_ item: Item, quantity: Int) {
        voyaging { $0.putDown(item, quantity: quantity) }
    }

    func useAtFortress(_ item: Item) {
        showingInventory = false
        voyaging { $0.useAtFortress(item) }
    }

    /// The compass point (0 north, 1 east, 2 south, 3 west) nearest a way from the camera.
    private func quarter(_ move: Move) -> Int {
        let v: SIMD2<Float> = switch move {
        case .forward: [0, 1]
        case .back: [0, -1]
        case .left: [-1, 0]
        case .right: [1, 0]
        }
        let dir = SIMD2<Float>(-sin(cameraYaw), -cos(cameraYaw)) * v.y + SIMD2<Float>(cos(cameraYaw), -sin(cameraYaw)) * v.x
        return (Int((atan2(dir.x, -dir.y) / (.pi / 2)).rounded()) % 4 + 4) % 4
    }

    /// An arrow key steps that way from the camera, and keeps stepping while held.
    func creep(toward move: Move, down: Bool) {
        if down {
            held.insert(move)
            creep(quarter(move))
            nextCreep = clock + 0.3
        } else {
            held.remove(move)
        }
    }

    func order(_ c: SeaCommand) { voyaging { $0.command(c) } }
    func answer(_ a: SeaAnswer) { voyaging { $0.answer(a) } }
    func pay(_ amount: Int) { voyaging { $0.pay(amount) } }
    func templeAttack() { voyaging { $0.templeAttack() } }
    func templeLeave() { voyaging { $0.templeLeave() } }
    func recoverShip() { voyaging { $0.recoverShip() } }
    func returnToShip() { voyaging { $0.returnToShip() } }

    func useAtSea(_ item: Item, offering: Bool = false) {
        showingInventory = false
        voyaging { $0.useAtSea(item, offering: offering) }
    }

    func putOver(_ item: Item, quantity: Int) {
        showingInventory = false
        voyaging { $0.putOver(item, quantity: quantity) }
    }

    /// An arrow key sets the sails for the point of the compass nearest that way from
    /// the camera.
    func sail(toward move: Move) {
        let v: SIMD2<Float> = switch move {
        case .forward: [0, 1]
        case .back: [0, -1]
        case .left: [-1, 0]
        case .right: [1, 0]
        }
        let forward = SIMD2<Float>(-sin(cameraYaw), -cos(cameraYaw))
        let right = SIMD2<Float>(cos(cameraYaw), -sin(cameraYaw))
        let dir = forward * v.y + right * v.x                     // map axes: x east, y south
        let bearing = atan2(dir.x, -dir.y)
        let point = (Int((bearing / (.pi / 4)).rounded()) % 8 + 8) % 8
        order(.setSails(point))
    }

    // MARK: Commands

    /// G: pick up what lies here.
    func get() {
        guard var e = expedition, e.isFree else { return }
        say(e.get())
        expedition = e
        lastCell = nil
    }

    func drop(_ item: Item, quantity: Int) {
        guard var e = expedition else { return }
        e.drop(item, quantity: quantity)
        expedition = e
        lastCell = nil
    }

    /// R mounts the horses; R or H again comes down (as does landing the rug).
    func rideOrHalt() {
        guard var e = expedition, e.isFree else { return }
        say(e.mount == nil ? e.ride() : e.halt())
        expedition = e
        lastCell = nil
    }

    func use(_ item: Item) {
        guard var e = expedition else { return }
        held.removeAll()
        showingInventory = false
        e.use(item)
        expedition = e
        hear(e.takeNews(), lost: e.isLost)
        lastCell = nil
    }

    private func say(_ words: String?) {
        guard let words else { return }
        toast = words
        toastUntil = clock + 4
    }

    /// Pass news on as a toast, or end the quest.
    private func hear(_ news: [String], lost: Bool) {
        guard let last = news.last else { return }
        if lost {
            phase = .lost(last)
            forgetSave()
        } else {
            toast = news.joined(separator: " ")
            toastUntil = clock + 5
        }
    }

    // MARK: The camera

    func orbit(by delta: CGSize) {
        cameraYaw -= Float(delta.width) * 0.008
        cameraPitch = min(max(cameraPitch + Float(delta.height) * 0.005, 0.2), 1.35)
    }

    func zoom(by factor: Float) {
        cameraDistance = min(max(cameraDistance / factor, 12), 120)
    }

    // MARK: The frame

    /// One frame of the world.
    func tick(dt: Float) {
        guard phase == .playing, let e = expedition else { return }
        clock += Double(dt)
        let dt = min(dt, 0.1)
        if toast != nil && clock > toastUntil { toast = nil }
        switch stage {
        case .catacombs: tickCatacombs(e, dt: dt)
        case .fortress: tickFortress(e, dt: dt)
        case .sea: tickSea(e, dt: dt)
        case .island: if let world { tickIsland(e, world: world, dt: dt) }
        case .ended: break
        }
    }

    /// A frame in the catacombs: the frenzies dart about, the party creeps on while
    /// an arrow is held, and the camera looks down from above.
    private func tickCatacombs(_ e: Expedition, dt: Float) {
        guard let w = catacombWorld else { return }
        var e = e
        e.catacombsTick(dt: Double(dt))
        expedition = e
        let news = e.takeNews()
        if !news.isEmpty {
            hear(news, lost: e.isLost)
            if e.isLost { return }
        }
        if let move = held.first, clock > nextCreep {
            creep(quarter(move))
            nextCreep = clock + 0.18
        }
        guard let c = expedition?.catacombs else { return }
        w.update(c, hasOrb: e.hasOrb, dt: dt)
        placeCamera(focus: CatacombWorld.place(Double(c.x), Double(c.y)), distance: min(cameraDistance, 30), dt: dt,
                    pitch: max(cameraPitch, 1.05)) { _ in 0 }
    }

    /// A frame on Lapour: the party walks up to wherever it has got to.
    private func tickFortress(_ e: Expedition, dt: Float) {
        guard let w = fortressWorld, let f = e.fortress else { return }
        w.update(f, ended: false, dt: dt)
        placeCamera(focus: w.partyPosition + [0, 2, 0], distance: max(cameraDistance, 40), dt: dt) { _ in 0 }
    }

    /// A frame at sea: time passes, the ship sails, and the camera follows it.
    private func tickSea(_ e: Expedition, dt: Float) {
        guard let sea = seaWorld else { return }
        var e = e
        e.sail(dt: Double(dt))
        expedition = e
        let news = e.takeNews()
        if !news.isEmpty {
            hear(news, lost: e.isLost)
            if e.isLost { return }
        }
        guard let v = e.voyage else { return }
        if clock > nextSave {
            save()
            nextSave = clock + 5
        }

        // Between pixels the ship glides; it turns to the way it is going.
        var x = Double(v.x), y = Double(v.y)
        var yaw: Float?
        if let d = e.drift {
            let s = CompassPoint.step(d)
            x += Double(s.dx) * v.progress
            y += Double(s.dy) * v.progress
            yaw = atan2(Float(-s.dx), Float(-s.dy))
            heading = yaw!
        }
        let position = sea.place(x: x, y: y)
        sea.ship.setSails(v.sails != nil && !v.sailsTorn)
        sea.ship.update(position: position, heading: yaw, spin: v.happening == .whirlpool, dt: dt)
        sea.whirl.isEnabled = v.happening == .whirlpool
        sea.whirl.position = position
        sea.whirl.orientation = simd_quatf(angle: Float(clock) * 1.5, axis: [0, 1, 0])
        sea.cast.update(e, ship: position, dt: dt)
        placeCamera(focus: position + [0, 4, 0], distance: cameraDistance, dt: dt) {
            max(sea.seascape.height(world: $0), 0.1)
        }
    }

    /// A frame on the island.
    private func tickIsland(_ e: Expedition, world: World, dt: Float) {
        var e = e

        // Input is relative to the camera: forward is away from it.
        var input = stick
        if held.contains(.forward) { input.y += 1 }
        if held.contains(.back) { input.y -= 1 }
        if held.contains(.right) { input.x += 1 }
        if held.contains(.left) { input.x -= 1 }
        if simd_length(input) > 1 { input = simd_normalize(input) }
        let forward = SIMD2<Float>(-sin(cameraYaw), -cos(cameraYaw))
        let right = SIMD2<Float>(cos(cameraYaw), -sin(cameraYaw))
        let dir = forward * input.y + right * input.x

        var moved = false
        if simd_length(dir) > 0.05 && !inMarket {
            moved = e.walk(dx: Double(dir.x), dy: Double(dir.y), dt: Double(dt) * Double(simd_length(input)))
            let target = atan2(-dir.x, -dir.y)
            heading += remainder(target - heading, 2 * .pi) * min(1, dt * 10)
            let news = e.takeNews()
            expedition = e
            if !news.isEmpty {
                hear(news, lost: e.isLost)
                lastCell = nil
                if e.isLost { return }
            }
        }

        // Something may turn up underfoot without the party leaving the cell.
        let lying = e.island.lying(e.cell).map { $0.item.id * 1000 + $0.quantity } ?? 0
        if e.cell != lastCell || lying != lastLying {
            lastCell = e.cell
            lastLying = lying
            save()
            siteHere = e.mount == nil ? e.site : nil      // sites wait until the party halts
            report = e.describe()
        } else if lookingUntil > 0 && clock > lookingUntil {
            lookingUntil = 0
            report = e.describe()
        }

        let p2 = WorldScale.world(x: e.x, y: e.y)
        let ground = world.landscape
        let position = SIMD3<Float>(p2.x, max(ground.height(world: p2), 0.1), p2.y)
        world.party.update(position: position, heading: heading, moving: moved, mount: e.mount, dt: dt) {
            max(ground.height(world: $0), 0.1)
        }
        world.sync(e)
        world.cast.update(visit: e.visit, party: position, heading: heading, dt: dt)

        // The camera trails the party, easing after it; in the bazaar it circles the city.
        var focus = position + [0, 1.5, 0]
        var distance = cameraDistance
        if inMarket {
            let c = e.cell.center
            let p = WorldScale.world(x: c.x, y: c.y)
            focus = [p.x, ground.height(world: p) + 3, p.y]
            distance = 26
            cameraYaw += dt * 0.12
        }
        placeCamera(focus: focus, distance: distance, dt: dt) { max(ground.height(world: $0), 0.1) }
    }

    /// The camera trails its focus, easing after it, never below the ground.
    private func placeCamera(focus: SIMD3<Float>, distance: Float, dt: Float, pitch: Float? = nil,
                             ground: (SIMD2<Float>) -> Float) {
        let eased = cameraFocus.map { simd_mix($0, focus, SIMD3(repeating: min(1, dt * 3))) } ?? focus
        cameraFocus = eased
        let pitch = pitch ?? cameraPitch
        let offset = SIMD3<Float>(sin(cameraYaw) * cos(pitch), sin(pitch), cos(cameraYaw) * cos(pitch))
        var eye = eased + offset * distance
        eye.y = max(eye.y, ground([eye.x, eye.z]) + 3)
        camera?.look(at: eased, from: eye, relativeTo: nil)
    }
}
