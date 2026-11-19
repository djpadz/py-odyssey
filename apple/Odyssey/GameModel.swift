import OdysseyKit
import Observation
import RealityKit
import SwiftUI

/// The running game: the quest, the 3D world, and the player's input.
@Observable @MainActor
final class GameModel {
    enum Phase { case title, loading, playing }

    private(set) var phase = Phase.title
    private(set) var expedition: Expedition?
    /// The report in the original's words, refreshed whenever the party enters a new cell.
    private(set) var report = ""
    private(set) var siteHere: Site?
    private(set) var loadError: String?
    /// Camera yaw in radians; 0 looks north.
    private(set) var cameraYaw: Float = 0

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
    @ObservationIgnored private var lookingUntil: Double = 0
    @ObservationIgnored private var clock: Double = 0

    func newQuest(seed: UInt64 = .random(in: 1...UInt64(UInt32.max))) {
        phase = .loading
        loadError = nil
        let expedition = Expedition(seed: seed)
        self.expedition = expedition
        Task {
            do {
                world = try await WorldBuilder.build(expedition)
                lastCell = nil
                cameraFocus = nil
                phase = .playing
            } catch {
                loadError = error.localizedDescription
                phase = .title
            }
        }
    }

    /// The L command: also name the terrain round about.
    func look() {
        guard let e = expedition else { return }
        report = e.island.describe(x: e.x, y: e.y, looking: true)
        lookingUntil = clock + 8
    }

    func orbit(by delta: CGSize) {
        cameraYaw -= Float(delta.width) * 0.008
        cameraPitch = min(max(cameraPitch + Float(delta.height) * 0.005, 0.2), 1.35)
    }

    func zoom(by factor: Float) {
        cameraDistance = min(max(cameraDistance / factor, 12), 120)
    }

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
        if simd_length(dir) > 0.05 {
            moved = e.walk(dx: Double(dir.x), dy: Double(dir.y), dt: Double(dt) * Double(simd_length(input)))
            let target = atan2(-dir.x, -dir.y)
            heading += remainder(target - heading, 2 * .pi) * min(1, dt * 10)
            expedition = e
        }

        if e.cell != lastCell {
            lastCell = e.cell
            siteHere = e.site
            report = e.island.describe(x: e.x, y: e.y)
        } else if lookingUntil > 0 && clock > lookingUntil {
            lookingUntil = 0
            report = e.island.describe(x: e.x, y: e.y)
        }

        let p2 = WorldScale.world(x: e.x, y: e.y)
        let ground = world.landscape
        let position = SIMD3<Float>(p2.x, max(ground.height(world: p2), 0.1), p2.y)
        world.party.update(position: position, heading: heading, moving: moved, dt: dt) {
            max(ground.height(world: $0), 0.1)
        }

        // The camera trails the party, easing after it.
        let focus = position + [0, 1.5, 0]
        let eased = cameraFocus.map { simd_mix($0, focus, SIMD3(repeating: min(1, dt * 5))) } ?? focus
        cameraFocus = eased
        let offset = SIMD3<Float>(sin(cameraYaw) * cos(cameraPitch), sin(cameraPitch), cos(cameraYaw) * cos(cameraPitch))
        var eye = eased + offset * cameraDistance
        eye.y = max(eye.y, ground.height(world: [eye.x, eye.z]) + 3)
        camera?.look(at: eased, from: eye, relativeTo: nil)
    }
}
