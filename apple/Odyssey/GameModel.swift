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
    /// Which way the party faces, radians clockwise from north.
    var partyHeading: Float { -heading }

    @ObservationIgnored private(set) var world: World?
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

    func newQuest(seed: UInt64 = .random(in: 1...UInt64(UInt32.max)), meeting: String? = nil) {
        phase = .loading
        loadError = nil
        var expedition = Expedition(seed: seed)
        #if DEBUG
        if let meeting { GameModel.rehearse(meeting, in: &expedition) }
        #endif
        self.expedition = expedition
        Task {
            do {
                world = try await WorldBuilder.build(expedition)
                lastCell = nil
                cameraFocus = nil
                toast = nil
                showingInventory = meeting?.lowercased() == "inventory"
                phase = .playing
            } catch {
                loadError = error.localizedDescription
                phase = .title
            }
        }
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
        guard phase == .playing, var e = expedition, let world else { return }
        clock += Double(dt)
        let dt = min(dt, 0.1)

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
        if toast != nil && clock > toastUntil { toast = nil }

        // Something may turn up underfoot without the party leaving the cell.
        let lying = e.island.lying(e.cell).map { $0.item.id * 1000 + $0.quantity } ?? 0
        if e.cell != lastCell || lying != lastLying {
            lastCell = e.cell
            lastLying = lying
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
        let eased = cameraFocus.map { simd_mix($0, focus, SIMD3(repeating: min(1, dt * 3))) } ?? focus
        cameraFocus = eased
        let offset = SIMD3<Float>(sin(cameraYaw) * cos(cameraPitch), sin(cameraPitch), cos(cameraYaw) * cos(cameraPitch))
        var eye = eased + offset * distance
        eye.y = max(eye.y, ground.height(world: [eye.x, eye.z]) + 3)
        camera?.look(at: eased, from: eye, relativeTo: nil)
    }
}
