import CoreGraphics
import RealityKit
import simd

/// The adventurer, banner aloft, and a file of men behind.
@MainActor
final class PartyFigure {
    let root = Entity()
    private let leader: Entity
    private var men: [Entity] = []
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
    func update(position: SIMD3<Float>, heading: Float, moving: Bool, dt: Float, ground: (SIMD2<Float>) -> Float) {
        if moving { walkPhase += dt * 11 }
        let bob = moving ? abs(sin(walkPhase)) * 0.12 : 0
        leader.position = position + [0, bob, 0]
        leader.orientation = simd_quatf(angle: heading, axis: [0, 1, 0])

        if trail.isEmpty || simd_distance(trail[0], position) > 0.25 {
            trail.insert(position, at: 0)
            if trail.count > 80 { trail.removeLast() }
        }
        for (i, man) in men.enumerated() {
            let target = trail[min((i + 1) * 7, trail.count - 1)]
            let jitter = SIMD3<Float>(i % 2 == 0 ? 0.5 : -0.5, 0, 0)
            var p = target + simd_quatf(angle: heading, axis: [0, 1, 0]).act(jitter)
            p.y = ground([p.x, p.z])
            let toward = position - p
            let manBob = moving ? abs(sin(walkPhase + Float(i) * 1.3)) * 0.1 : 0
            man.position = p + [0, manBob, 0]
            if simd_length(SIMD2(toward.x, toward.z)) > 0.1 {
                man.orientation = simd_quatf(angle: atan2(-toward.x, -toward.z), axis: [0, 1, 0])
            }
        }
    }
}
