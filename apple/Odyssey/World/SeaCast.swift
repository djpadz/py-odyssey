import OdysseyKit
import RealityKit
import simd

/// Whoever comes alongside the ship (the original draws them beside it, line 6000):
/// three ships or pirates, merchantmen, a raft, flying monsters, the octopus, the
/// serpent, or Argorion. Beaten ships sink; the rest go on their way.
@MainActor
final class SeaCast {
    let root = Entity()
    private let light: Entity

    private enum Sight: Equatable {
        case ships(pirates: Bool)
        case merchantman
        case raft(men: Int)
        case flyers(Monster)
        case seaMonster(SeaMonster)
        case argorion
    }

    private var sight: Sight?
    private var visitors: [Entity] = []
    private var flyers: [Figure] = []
    private var leaving: [(entity: Entity, since: Float, sinking: Bool)] = []
    private var clock: Float = 0
    /// Where they gather, beside the ship.
    private var anchor: SIMD3<Float> = .zero

    init(light: Entity) {
        self.light = light
    }

    func update(_ e: Expedition, ship: SIMD3<Float>, dt: Float) {
        clock += dt
        guard let v = e.voyage else { return }
        let next = SeaCast.sight(v, market: e.market)
        // Ships keep their places when they turn out to be pirates.
        let same: Bool = switch (sight, next) {
        case (.ships?, .ships?): true
        default: sight == next
        }
        if !same {
            let sunk = v.said.first?.hasPrefix("YOU DESTROYED THEM") == true
            for e in visitors + flyers.map(\.entity) { leaving.append((e, clock, sunk)) }
            visitors = []
            flyers = []
            if let next { arrive(next, x: v.x, ship: ship) }
        }
        sight = next
        animate(ship: ship, dt: dt)
    }

    private static func sight(_ v: Voyage, market: Market?) -> Sight? {
        switch v.question {
        case .merchants?: return .merchantman
        case let .raft(n)?: return .raft(men: n)
        case .raftChest?: return .raft(men: 0)
        default: break
        }
        if market?.isAtSea == true { return .merchantman }
        switch v.happening {
        case .ships?: return .ships(pirates: false)
        case .pirates?: return .ships(pirates: true)
        case let .flyers(m)?: return .flyers(m)
        case let .seaMonster(m)?: return .seaMonster(m)
        case .argorion?: return .argorion
        default: return nil
        }
    }

    /// 6000: alongside to the east, or to the west once past longitude 120.
    private func arrive(_ s: Sight, x: Int, ship: SIMD3<Float>) {
        let side: Float = x < 120 ? 1 : -1
        anchor = ship + [side * 30, 0, 0]
        switch s {
        case let .ships(pirates):
            for (i, offset) in ([[0, 0, -16], [8, 0, 0], [0, 0, 16]] as [SIMD3<Float>]).enumerated() {
                let ship = pirates
                    ? ShipFigure(sails: [0.12, 0.11, 0.1], flag: [0.05, 0.05, 0.05], scale: 0.9)
                    : ShipFigure(sails: [0.7, 0.7, 0.72], flag: [0.7, 0.1, 0.1], scale: 0.9)
                ship.setSails(true)
                add(ship.root, at: anchor + SIMD3(offset.x * side, 0, offset.z), turn: Float(i) * 0.3)
            }
        case .merchantman:
            let ship = ShipFigure(sails: [0.82, 0.62, 0.36], flag: [0.2, 0.35, 0.7])
            ship.setSails(true)
            add(ship.root, at: anchor, turn: 0)
        case let .raft(n):
            add(SeaCast.raft(men: n), at: ship + [side * 16, 0, 0], turn: 0)
        case let .flyers(m):
            for i in 0..<4 {
                let f = Bestiary.monster(m)
                f.phase = Float(i) * .pi / 2
                f.entity.scale = .init(repeating: 1.6)
                WorldBuilder.applyLightReceiver(f.entity, light: light)
                root.addChild(f.entity)
                flyers.append(f)
            }
        case let .seaMonster(m):
            let beast = m == .octopus ? SeaCast.octopus() : Bestiary.serpent(colour: [0.15, 0.4, 0.3], belly: [0.7, 0.75, 0.5], scale: 4).entity
            add(beast, at: ship + [side * 20, -0.5, 0], turn: side > 0 ? -.pi / 2 : .pi / 2)
        case .argorion:
            add(SeaCast.argorion(), at: ship + [side * 22, -1, 0], turn: side > 0 ? -.pi / 2 : .pi / 2)
        }
    }

    private func add(_ e: Entity, at p: SIMD3<Float>, turn: Float) {
        e.position = p
        e.orientation = simd_quatf(angle: turn, axis: [0, 1, 0])
        WorldBuilder.applyLightReceiver(e, light: light)
        root.addChild(e)
        visitors.append(e)
    }

    private func animate(ship: SIMD3<Float>, dt: Float) {
        // Everything rides the swell; the great beasts sit lower in the water.
        for (i, e) in visitors.enumerated() {
            e.position.y = (e.name == "argorion" ? -1 : e.name == "beast" ? -0.5 : -0.3) + sin(clock * 1.2 + Float(i)) * 0.2
        }
        for f in flyers {
            let a = clock * 0.7 + f.phase
            f.entity.position = ship + [cos(a) * 18, 14 + sin(clock * 1.5 + f.phase) * 1.5, sin(a) * 18]
            f.entity.orientation = simd_quatf(angle: -a + .pi, axis: [0, 1, 0])
            f.move(clock)
        }
        for item in leaving {
            let t = clock - item.since
            if item.sinking {
                // Down by the bow, and under.
                item.entity.orientation = item.entity.orientation * simd_quatf(angle: dt * 0.25, axis: [1, 0, 0])
                item.entity.position.y -= dt * (0.5 + t)
            } else {
                // Off they go, out of sight.
                item.entity.position += SIMD3(item.entity.position.x - ship.x, 0, item.entity.position.z - ship.z) * dt * 0.4
                item.entity.scale = .init(repeating: max(item.entity.scale.x - dt * 0.35, 0.01))
            }
            if t > 4 { item.entity.removeFromParent() }
        }
        leaving.removeAll { $0.entity.parent == nil }
    }

    // MARK: Models

    private static func raft(men: Int) -> Entity {
        let e = Entity()
        let wood = Bestiary.paint([0.5, 0.36, 0.2])
        for i in 0..<6 {
            let log = ModelEntity(mesh: .generateCylinder(height: 6, radius: 0.4), materials: [wood])
            log.position = [Float(i) * 0.8 - 2, 0.3, 0]
            log.orientation = simd_quatf(angle: .pi / 2, axis: [1, 0, 0])
            e.addChild(log)
        }
        for i in 0..<men {
            let man = Bestiary.humanoid(Bestiary.Look(skin: [0.75, 0.58, 0.45], cloth: [0.6, 0.55, 0.45]))
            man.entity.position = [Float(i % 3) * 1.2 - 1.2, 0.7, Float(i / 3) * 1.4 - 0.7]
            e.addChild(man.entity)
        }
        let chest = Bestiary.chest()
        chest.position = [1.4, 0.7, 1.8]
        e.addChild(chest)
        return e
    }

    private static func octopus() -> Entity {
        let e = Entity()
        e.name = "beast"
        let skin: SIMD3<Float> = [0.55, 0.18, 0.3]
        let head = ModelEntity(mesh: .generateSphere(radius: 2.4), materials: [Bestiary.paint(skin)])
        head.position.y = 3
        head.scale = [1, 1.3, 1]
        e.addChild(head)
        for x: Float in [-0.9, 0.9] {
            let eye = ModelEntity(mesh: .generateSphere(radius: 0.4), materials: [Bestiary.paint([1, 0.85, 0.2], glow: true)])
            eye.position = [x, 3.2, -2.1]
            e.addChild(eye)
        }
        for i in 0..<8 {
            let a = Float(i) / 8 * 2 * .pi
            let arm = Entity()
            arm.orientation = simd_quatf(angle: a, axis: [0, 1, 0])
            // Up out of the water and curling over, in overlapping segments.
            for j in 0..<16 {
                let t = Float(j) / 15
                let seg = ModelEntity(mesh: .generateSphere(radius: 0.75 - t * 0.5), materials: [Bestiary.paint(skin * 0.9)])
                seg.position = [0, 0.6 + sin(t * .pi * 0.9) * 5, -2 - t * 7]
                arm.addChild(seg)
            }
            e.addChild(arm)
        }
        return e
    }

    /// The old man of the sea, waist-deep, crowned, with his trident.
    private static func argorion() -> Entity {
        let e = Entity()
        e.name = "argorion"
        let skin = Bestiary.paint([0.45, 0.65, 0.6]), gold = Bestiary.paint([0.95, 0.75, 0.3], metal: 1)
        let torso = ModelEntity(mesh: .generateBox(width: 5, height: 6, depth: 3, cornerRadius: 1.2), materials: [skin])
        torso.position.y = 3
        let head = ModelEntity(mesh: .generateSphere(radius: 1.8), materials: [skin])
        head.position.y = 7.6
        let beard = ModelEntity(mesh: .generateCone(height: 3.2, radius: 1.5), materials: [Bestiary.paint([0.88, 0.92, 0.9])])
        beard.position = [0, 6, -1]
        beard.orientation = simd_quatf(angle: .pi, axis: [1, 0, 0])
        e.children.append(contentsOf: [torso, head, beard])
        for i in 0..<5 {
            let spike = ModelEntity(mesh: .generateCone(height: 1.2, radius: 0.3), materials: [gold])
            spike.position = [Float(i - 2) * 0.6, 9.4, -0.6]
            e.addChild(spike)
        }
        for x: Float in [-1, 1] {
            let arm = ModelEntity(mesh: .generateCylinder(height: 5, radius: 0.6), materials: [skin])
            arm.position = [x * 3.2, 4, -0.5]
            arm.orientation = simd_quatf(angle: x * 0.35, axis: [0, 0, 1])
            e.addChild(arm)
        }
        let shaft = ModelEntity(mesh: .generateCylinder(height: 14, radius: 0.2), materials: [gold])
        shaft.position = [4, 5, -1]
        e.addChild(shaft)
        for dx: Float in [-0.6, 0, 0.6] {
            let prong = ModelEntity(mesh: .generateCone(height: 1.4, radius: 0.18), materials: [gold])
            prong.position = [4 + dx, 12.5, -1]
            e.addChild(prong)
        }
        return e
    }
}
