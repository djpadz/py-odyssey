import CoreGraphics
import OdysseyKit
import RealityKit
import simd

/// The adventurer, banner aloft, and a file of men behind; on horseback, or all
/// aboard the flying rug.
@MainActor
final class PartyFigure {
    let root = Entity()
    private let leader: Entity
    private var men: [Entity] = []
    /// A horse for each figure, shown when riding.
    private var horses: [Entity] = []
    private let rug: Entity
    private var hover: Float = 0
    /// Where the leader has been, newest first; the men walk in these footsteps.
    private var trail: [SIMD3<Float>] = []
    private var walkPhase: Float = 0

    init() {
        leader = PartyFigure.figure(cloak: [0.62, 0.10, 0.10], banner: true)
        root.addChild(leader)
        for i in 0..<4 {
            let man = PartyFigure.figure(cloak: i % 2 == 0 ? [0.42, 0.30, 0.18] : [0.30, 0.32, 0.22], banner: false)
            men.append(man)
            root.addChild(man)
        }
        for i in 0...men.count {
            let horse = PartyFigure.horse(coat: i % 2 == 0 ? [0.36, 0.22, 0.12] : [0.25, 0.18, 0.12])
            horse.isEnabled = false
            horses.append(horse)
            root.addChild(horse)
        }
        rug = PartyFigure.carpet()
        rug.isEnabled = false
        root.addChild(rug)
    }

    private static func paint(_ c: SIMD3<Float>) -> PhysicallyBasedMaterial {
        var m = PhysicallyBasedMaterial()
        m.baseColor = .init(tint: .init(red: CGFloat(c.x), green: CGFloat(c.y), blue: CGFloat(c.z), alpha: 1))
        m.roughness = 0.8
        return m
    }

    /// A horse, facing -z, its back about 1.1 m up.
    private static func horse(coat: SIMD3<Float>) -> Entity {
        let e = Entity()
        let hide = paint(coat), dark = paint(coat * 0.55)
        let body = ModelEntity(mesh: .generateBox(width: 0.45, height: 0.5, depth: 1.4, cornerRadius: 0.18), materials: [hide])
        body.position = [0, 1.0, 0]
        let neck = ModelEntity(mesh: .generateBox(width: 0.24, height: 0.7, depth: 0.3, cornerRadius: 0.1), materials: [hide])
        neck.position = [0, 1.4, -0.7]
        neck.orientation = simd_quatf(angle: -0.5, axis: [1, 0, 0])
        let head = ModelEntity(mesh: .generateBox(width: 0.2, height: 0.24, depth: 0.5, cornerRadius: 0.08), materials: [hide])
        head.position = [0, 1.7, -0.98]
        head.orientation = simd_quatf(angle: 0.4, axis: [1, 0, 0])
        let tail = ModelEntity(mesh: .generateBox(width: 0.08, height: 0.6, depth: 0.08), materials: [dark])
        tail.position = [0, 0.95, 0.75]
        tail.orientation = simd_quatf(angle: 0.35, axis: [1, 0, 0])
        e.children.append(contentsOf: [body, neck, head, tail])
        for x: Float in [-0.15, 0.15] {
            for z: Float in [-0.55, 0.55] {
                let leg = ModelEntity(mesh: .generateCylinder(height: 0.8, radius: 0.06), materials: [dark])
                leg.position = [x, 0.4, z]
                e.addChild(leg)
            }
        }
        for c in e.children { c.components.set(GroundingShadowComponent(castsShadow: true)) }
        return e
    }

    /// A red and gold carpet, big enough for the party to sit on.
    private static func carpet() -> Entity {
        let e = Entity()
        let cloth = ModelEntity(mesh: .generateBox(width: 2.6, height: 0.08, depth: 3.4, cornerRadius: 0.03),
                                materials: [paint([0.6, 0.1, 0.12])])
        let border = ModelEntity(mesh: .generateBox(width: 2.9, height: 0.06, depth: 3.7, cornerRadius: 0.03),
                                 materials: [paint([0.85, 0.65, 0.2])])
        border.position.y = -0.02
        e.children.append(contentsOf: [cloth, border])
        for c in e.children { c.components.set(GroundingShadowComponent(castsShadow: true)) }
        return e
    }

    private static func figure(cloak: SIMD3<Float>, banner: Bool) -> Entity {
        func paint(_ c: SIMD3<Float>, metal: Float = 0) -> PhysicallyBasedMaterial {
            var m = PhysicallyBasedMaterial()
            m.baseColor = .init(tint: .init(red: CGFloat(c.x), green: CGFloat(c.y), blue: CGFloat(c.z), alpha: 1))
            m.roughness = metal > 0 ? 0.35 : 0.8
            m.metallic = .init(floatLiteral: metal)
            return m
        }
        let e = Entity()
        let body = ModelEntity(mesh: .generateCone(height: 1.3, radius: 0.42), materials: [paint(cloak)])
        body.position.y = 0.65
        let head = ModelEntity(mesh: .generateSphere(radius: 0.22), materials: [paint([0.85, 0.66, 0.50])])
        head.position.y = 1.45
        let helm = ModelEntity(mesh: .generateCone(height: 0.3, radius: 0.24), materials: [paint([0.7, 0.7, 0.72], metal: 1)])
        helm.position.y = 1.65
        e.children.append(contentsOf: [body, head, helm])
        if banner {
            let pole = ModelEntity(mesh: .generateCylinder(height: 3.2, radius: 0.04), materials: [paint([0.35, 0.24, 0.14])])
            pole.position = [0.45, 1.6, 0]
            let flag = ModelEntity(mesh: .generateBox(width: 0.9, height: 0.6, depth: 0.03), materials: [paint([0.85, 0.68, 0.18])])
            flag.position = [0.92, 2.85, 0]
            e.children.append(contentsOf: [pole, flag])
        }
        for c in e.children { c.components.set(GroundingShadowComponent(castsShadow: true)) }
        return e
    }

    /// Place the party: `position` on the ground, `heading` the yaw it faces, `moving` whether it walked this frame.
    func update(position: SIMD3<Float>, heading: Float, moving: Bool, mount: Mount?, dt: Float,
                ground: (SIMD2<Float>) -> Float) {
        let facing = simd_quatf(angle: heading, axis: [0, 1, 0])
        rug.isEnabled = mount == .rug
        for h in horses { h.isEnabled = mount == .horses }

        // Aboard the rug, everyone sits together and it rises and floats.
        hover += ((mount == .rug ? 4.5 : 0) - hover) * min(1, dt * 2)
        if mount == .rug || hover > 0.05 {
            walkPhase += dt * 1.5
            let deck = position + [0, hover + sin(walkPhase) * 0.15 + 0.1, 0]
            rug.position = deck
            rug.orientation = facing * simd_quatf(angle: sin(walkPhase * 0.8) * 0.04, axis: [0, 0, 1])
            leader.position = deck + facing.act([0, 0.05, -0.9])
            leader.orientation = facing
            let seats: [SIMD3<Float>] = [[-0.7, 0.05, 0.2], [0.7, 0.05, 0.2], [-0.6, 0.05, 1.1], [0.6, 0.05, 1.1]]
            for (man, seat) in zip(men, seats) {
                man.position = deck + facing.act(seat)
                man.orientation = facing
            }
            trail = []
            return
        }

        // On horseback each figure sits a horse's back higher, and the file spreads out.
        let saddle: Float = mount == .horses ? 1.05 : 0
        if moving { walkPhase += dt * (mount == .horses ? 14 : 11) }
        let bob = moving ? abs(sin(walkPhase)) * (mount == .horses ? 0.18 : 0.12) : 0
        leader.position = position + [0, bob + saddle, 0]
        leader.orientation = facing
        if mount == .horses {
            horses[0].position = position + facing.act([0, bob * 0.6, 0.15])
            horses[0].orientation = facing
        }

        if trail.isEmpty || simd_distance(trail[0], position) > 0.25 {
            trail.insert(position, at: 0)
            if trail.count > 80 { trail.removeLast() }
        }
        for (i, man) in men.enumerated() {
            let target = trail[min((i + 1) * (mount == .horses ? 10 : 7), trail.count - 1)]
            let jitter = SIMD3<Float>(i % 2 == 0 ? 0.5 : -0.5, 0, 0)
            var p = target + simd_quatf(angle: heading, axis: [0, 1, 0]).act(jitter)
            p.y = ground([p.x, p.z])
            let toward = position - p
            let manBob = moving ? abs(sin(walkPhase + Float(i) * 1.3)) * 0.1 : 0
            man.position = p + [0, manBob + saddle, 0]
            if simd_length(SIMD2(toward.x, toward.z)) > 0.1 {
                man.orientation = simd_quatf(angle: atan2(-toward.x, -toward.z), axis: [0, 1, 0])
            }
            if mount == .horses {
                horses[i + 1].position = p + man.orientation.act([0, manBob * 0.6, 0.15])
                horses[i + 1].orientation = man.orientation
            }
        }
    }
}
