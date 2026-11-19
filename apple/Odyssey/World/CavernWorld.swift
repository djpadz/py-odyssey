import CoreGraphics
import OdysseyKit
import RealityKit
import simd

/// The catacombs in 3D: the 40 x 40 squares, two metres each, walls standing on the
/// tiles laid out so far. With the light out there is next to nothing to see; with it
/// lit, a torch flickers about the party.
@MainActor
final class CatacombWorld {
    static let square: Float = 2

    let root = Entity()
    let party = PartyFigure()
    private let maze = Entity()
    private let torch = PointLight()
    private let frenzies = CatacombWorld.swarm()
    private let borer = Bestiary.serpent(colour: [0.42, 0.3, 0.2], belly: [0.6, 0.5, 0.35], scale: 0.9).entity
    private let altar = CatacombWorld.altarStone()
    private let stairs = CatacombWorld.stairway()
    private let exit = CatacombWorld.daylight()
    private var sacks: [Int: (key: Int, entity: Entity)] = [:]
    private let materials: [Paint: PhysicallyBasedMaterial]
    private var builtWalls: [Bool] = []
    private var builtLaid: [Bool] = []
    private var shown: SIMD3<Float>?
    private var heading: Float = 0
    private var clock: Float = 0

    init(light environment: EnvironmentResource?) {
        materials = Dictionary(uniqueKeysWithValues: Paint.allCases.map { ($0, WorldBuilder.material($0)) })
        root.addChild(maze)
        root.addChild(party.root)
        torch.light.color = .init(red: 1, green: 0.72, blue: 0.4, alpha: 1)
        torch.light.intensity = 60000
        torch.light.attenuationRadius = 18
        root.addChild(torch)
        for e in [frenzies, borer, altar, stairs, exit] {
            e.isEnabled = false
            root.addChild(e)
        }
        // Only the faintest light from anywhere else.
        if let environment {
            root.components.set(ImageBasedLightComponent(source: .single(environment), intensityExponent: -2.5))
        }
    }

    static func place(_ x: Double, _ y: Double) -> SIMD3<Float> {
        [(Float(x) - 19.5) * square, 0, (Float(y) - 19.5) * square]
    }

    func update(_ c: Catacombs, hasOrb: Bool, dt: Float) {
        clock += dt
        if c.walls != builtWalls || c.laid != builtLaid { rebuild(c) }

        // The party steps square to square; a wrap, a fall or a teleport is a jump.
        let target = CatacombWorld.place(Double(c.x), Double(c.y))
        var moving = false
        if let s = shown, simd_distance(s, target) < CatacombWorld.square * 3 {
            let to = target - s
            if simd_length(to) > 0.02 {
                moving = true
                heading = atan2(-to.x, -to.z)
            }
            shown = s + to * min(1, dt * 9)
        } else {
            shown = target
        }
        let at = shown!
        party.update(position: at, heading: heading, moving: moving, mount: nil, dt: dt) { _ in 0 }

        torch.isEnabled = c.light
        torch.position = at + [0, 3.2, 0]
        torch.light.intensity = 52000 + sin(clock * 13) * 5000 + sin(clock * 7.3) * 4000

        show(frenzies, at: c.frenzies, lift: 1.2 + sin(clock * 9) * 0.2)
        frenzies.orientation = simd_quatf(angle: clock * 6, axis: [0, 1, 0])
        show(borer, at: c.borer, lift: 0)
        show(altar, at: c.altar.map { ($0.x, $0.y) }, lift: 0)
        altar.findEntity(named: "orb")?.isEnabled = !hasOrb
        stairs.isEnabled = c.stairway
        stairs.position = at + [1.2, 0, 0]
        exit.isEnabled = c.exitHere
        exit.position = at + [1.2, 0, 0]
        syncSacks(c)
    }

    private func show(_ e: Entity, at p: (Int, Int)?, lift: Float) {
        e.isEnabled = p != nil
        if let p { e.position = CatacombWorld.place(Double(p.0), Double(p.1)) + [0, lift, 0] }
    }

    /// The walls and the floors of the tiles laid out, as two meshes.
    private func rebuild(_ c: Catacombs) {
        builtWalls = c.walls
        builtLaid = c.laid
        maze.children.removeAll()
        var stone = MeshBuilder(), floor = MeshBuilder()
        let s = CatacombWorld.square
        for y in 0..<Catacombs.size {
            for x in 0..<Catacombs.size where c.isWall(x, y) {
                let jitter = Float((x * 7 + y * 13) % 5) * 0.12
                stone.addBox(base: CatacombWorld.place(Double(x), Double(y)), size: [s, 3 + jitter, s])
            }
        }
        for t in 0..<64 where c.laid[t] {
            let k = t % 8 * 5, i = t / 8 * 5
            floor.addBox(base: CatacombWorld.place(Double(k) + 2, Double(i) + 2) - [0, 0.2, 0], size: [5 * s, 0.2, 5 * s])
        }
        for (builder, paint) in [(stone, Paint.stone), (floor, Paint.darkStone)] where !builder.isEmpty {
            if let e = try? builder.entity(materials[paint]!) { maze.addChild(e) }
        }
    }

    private func syncSacks(_ c: Catacombs) {
        for (k, sack) in sacks where c.floor[k] != sack.key {
            sack.entity.removeFromParent()
            sacks[k] = nil
        }
        for (k, v) in c.floor where sacks[k] == nil && v % 100 > 0 {
            let e = Bestiary.sack()
            e.scale = .init(repeating: 0.7)
            e.position = CatacombWorld.place(Double(k / 20 * 2) + 0.5, Double(k % 20 * 2) + 0.5)
            root.addChild(e)
            sacks[k] = (v, e)
        }
    }

    // MARK: Models

    /// A cloud of darting red-eyed things.
    private static func swarm() -> Entity {
        let e = Entity()
        var r = SeededRandom(seed: 77)
        for _ in 0..<18 {
            let bat = ModelEntity(mesh: .generateSphere(radius: 0.14), materials: [Bestiary.paint([0.5, 0.08, 0.1], glow: true)])
            bat.position = [Float.random(in: -0.9...0.9, using: &r), Float.random(in: -0.5...0.5, using: &r),
                            Float.random(in: -0.9...0.9, using: &r)]
            e.addChild(bat)
        }
        return e
    }

    private static func altarStone() -> Entity {
        let e = Entity()
        let slab = ModelEntity(mesh: .generateBox(width: 2.6, height: 1.1, depth: 1.6, cornerRadius: 0.1),
                               materials: [Bestiary.paint([0.45, 0.2, 0.18])])
        slab.position.y = 0.55
        let orb = ModelEntity(mesh: .generateSphere(radius: 0.38), materials: [Bestiary.paint([0.95, 0.8, 0.35], metal: 1, glow: true)])
        orb.name = "orb"
        orb.position.y = 1.5
        let glow = PointLight()
        glow.light.color = .init(red: 1, green: 0.85, blue: 0.5, alpha: 1)
        glow.light.intensity = 8000
        glow.light.attenuationRadius = 6
        glow.position.y = 2
        orb.addChild(glow)
        e.children.append(contentsOf: [slab, orb])
        return e
    }

    /// Steps going down into the dark.
    private static func stairway() -> Entity {
        let e = Entity()
        for i in 0..<5 {
            let step = ModelEntity(mesh: .generateBox(width: 1.6, height: 0.2, depth: 0.5),
                                   materials: [Bestiary.paint([0.3, 0.28, 0.26])])
            step.position = [0, -Float(i) * 0.25, Float(i) * 0.45 - 1]
            e.addChild(step)
        }
        return e
    }

    /// A shaft of daylight from a way out.
    private static func daylight() -> Entity {
        let e = Entity()
        var m = UnlitMaterial(color: .init(red: 1, green: 0.95, blue: 0.75, alpha: 1))
        m.blending = .transparent(opacity: 0.35)
        let shaft = ModelEntity(mesh: .generateCylinder(height: 8, radius: 0.9), materials: [m])
        shaft.position.y = 4
        let light = PointLight()
        light.light.intensity = 20000
        light.light.attenuationRadius = 8
        light.position.y = 3
        e.children.append(contentsOf: [shaft, light])
        return e
    }
}

/// The way up to the Caliph's fortress on Lapour: a path climbing north to the castle,
/// and at three places along it, whatever bars the way.
@MainActor
final class FortressWorld {
    let root = Entity()
    let party = PartyFigure()
    private var hazards: [Entity] = []
    private var shown: SIMD3<Float>?
    private var heading: Float = .pi

    /// Where along the path each hazard stands, south to north.
    static let hazardZ: [Float] = [22, -2, -26]
    static let startZ: Float = 46
    static let gateZ: Float = -44

    init(_ f: Fortress, sky: (entity: Entity, environment: EnvironmentResource)) {
        let materials = Dictionary(uniqueKeysWithValues: Paint.allCases.map { ($0, WorldBuilder.material($0)) })
        root.addChild(sky.entity)
        var ground = MeshBuilder(), path = MeshBuilder(), rocks = MeshBuilder(), trees = MeshBuilder()
        ground.addBox(base: [0, -1, 0], size: [240, 1, 240])
        for i in 0..<12 {
            let z = FortressWorld.startZ + 8 - Float(i) * 9
            path.addBox(base: [Float(i % 2) * 0.8 - 0.4, 0, z], size: [5, 0.05, 9.5])
        }
        var r = SeededRandom(seed: 1980)
        for _ in 0..<70 {
            let side: Float = Bool.random(using: &r) ? 1 : -1
            let p = SIMD3<Float>(side * .random(in: 9...90, using: &r), 0, .random(in: -90...80, using: &r))
            if Bool.random(using: &r) {
                rocks.addSpindle(center: p, radius: .random(in: 1...3, using: &r), up: .random(in: 1...4, using: &r),
                                 down: 0.5, sides: 5, yaw: .random(in: 0...6, using: &r))
            } else {
                trees.addFrustum(base: p, bottomRadius: 2.2, topRadius: 0, height: .random(in: 6...10, using: &r), sides: 7)
            }
        }
        for (b, paint) in [(ground, Paint.leaves), (path, Paint.thatch), (rocks, Paint.rock), (trees, Paint.leavesDark)] {
            if let e = try? b.entity(materials[paint]!) { root.addChild(e) }
        }
        let castle = (try? WorldBuilder.entity(for: Props.model(of: .castle, seed: 7), materials: materials)) ?? Entity()
        castle.scale = .init(repeating: 1.6)
        castle.position = [0, 0, FortressWorld.gateZ - 14]
        root.addChild(castle)
        for (i, h) in f.hazards.enumerated() {
            let e = FortressWorld.model(h)
            e.position = [0, 0, FortressWorld.hazardZ[i]]
            e.isEnabled = false
            root.addChild(e)
            hazards.append(e)
        }
        root.addChild(party.root)
        let sun = DirectionalLight()
        sun.light.intensity = 3000
        sun.shadow = DirectionalLightComponent.Shadow(maximumDistance: 120, depthBias: 2)
        sun.look(at: .zero, from: [80, 140, 60], relativeTo: nil)
        root.addChild(sun)
        root.components.set(ImageBasedLightComponent(source: .single(sky.environment), intensityExponent: 0.6))
        WorldBuilder.applyLightReceiver(root, light: root)
    }

    /// Where the party stands: at the landing, before the hazard barring the way, just
    /// past one overcome, or at the gate.
    static func spot(_ f: Fortress, ended: Bool) -> SIMD3<Float> {
        if ended { return [0, 0, gateZ] }
        guard f.stage > 0 else { return [0, 0, startZ] }
        let z = hazardZ[f.stage - 1]
        return [0, 0, f.blocked ? z + 7 : z - 5]
    }

    func update(_ f: Fortress, ended: Bool, dt: Float) {
        for (i, e) in hazards.enumerated() {
            // Each shows once reached, and goes once passed.
            let reached = f.stage > i, passed = f.stage > i + 1 || (f.stage == i + 1 && !f.blocked) || ended
            e.isEnabled = reached && !passed
        }
        let target = FortressWorld.spot(f, ended: ended)
        var moving = false
        if let s = shown {
            let to = target - s
            if simd_length(to) > 0.05 {
                moving = true
                heading = atan2(-to.x, -to.z)
                shown = s + simd_normalize(to) * min(simd_length(to), dt * 6)
            }
        } else {
            shown = target
        }
        party.update(position: shown!, heading: heading, moving: moving, mount: nil, dt: dt) { _ in 0 }
    }

    var partyPosition: SIMD3<Float> { shown ?? [0, 0, FortressWorld.startZ] }

    // MARK: The hazards

    private static func glowing(_ c: SIMD3<Float>, opacity: Float = 1) -> any Material {
        var m = UnlitMaterial(color: .init(red: CGFloat(c.x), green: CGFloat(c.y), blue: CGFloat(c.z), alpha: 1))
        if opacity < 1 { m.blending = .transparent(opacity: .init(floatLiteral: opacity)) }
        return m
    }

    static func model(_ h: Hazard) -> Entity {
        let e = Entity()
        func add(_ m: MeshResource, _ material: any Material, _ p: SIMD3<Float>, turn: simd_quatf? = nil) {
            let part = ModelEntity(mesh: m, materials: [material])
            part.position = p
            if let turn { part.orientation = turn }
            part.components.set(GroundingShadowComponent(castsShadow: true))
            e.addChild(part)
        }
        switch h {
        case .lava:
            add(.generateBox(width: 30, height: 0.4, depth: 3.4), Bestiary.paint([0.08, 0.06, 0.05]), [0, 0, 0])
            add(.generateBox(width: 28, height: 0.3, depth: 1.6), glowing([1, 0.45, 0.08]), [0, 0.1, 0])
            for x in stride(from: -12, through: 12, by: 4) {
                add(.generateSphere(radius: 1.2), glowing([0.35, 0.33, 0.32], opacity: 0.4), [Float(x), 2.5, 0])
            }
        case .slime:
            add(.generateBox(width: 34, height: 0.3, depth: 6), glowing([0.35, 0.85, 0.2], opacity: 0.85), [0, 0.1, 0])
        case .thorns:
            var r = SeededRandom(seed: 3)
            for _ in 0..<60 {
                let p = SIMD3<Float>(.random(in: -14...14, using: &r), 0, .random(in: -2.5...2.5, using: &r))
                add(.generateCone(height: .random(in: 1.5...3.5, using: &r), radius: 0.25), Bestiary.paint([0.18, 0.22, 0.1]),
                    p + [0, 1, 0], turn: simd_quatf(angle: .random(in: -0.5...0.5, using: &r), axis: [1, 0, 0]))
            }
        case .gate:
            add(.generateBox(width: 30, height: 9, depth: 2), Bestiary.paint([0.62, 0.6, 0.55]), [0, 4.5, 0])
            add(.generateBox(width: 6, height: 7, depth: 2.2), Bestiary.paint([0.35, 0.34, 0.33]), [0, 3.5, 0])
            add(.generateBox(width: 0.8, height: 0.8, depth: 2.4), Bestiary.paint([0.05, 0.05, 0.05]), [0, 5.5, 0])
        case .medusa:
            let gorgon = Bestiary.monster(Monster(kind: 4)).entity
            gorgon.scale = .init(repeating: 2.2)
            gorgon.orientation = simd_quatf(angle: .pi, axis: [0, 1, 0])
            e.addChild(gorgon)
        case .fire:
            for x in stride(from: -14, through: 14, by: 2) {
                add(.generateBox(width: 2.2, height: 7, depth: 0.4, cornerRadius: 0.2), glowing([1, 0.55, 0.1], opacity: 0.6),
                    [Float(x), 3.5, Float(x % 4 == 0 ? 0.3 : -0.3)])
            }
        case .portal:
            add(.generateBox(width: 30, height: 8, depth: 1.6), Bestiary.paint([0.5, 0.48, 0.45]), [0, 4, 0])
            add(.generateBox(width: 5, height: 6.5, depth: 1.8), Bestiary.paint([0.25, 0.25, 0.27], metal: 1), [0, 3.25, 0])
            for x: Float in [-1.6, 0, 1.6] {
                for y: Float in [1.5, 3.5, 5.5] {
                    add(.generateCone(height: 0.6, radius: 0.15), Bestiary.paint([0.4, 0.4, 0.42], metal: 1), [x, y, 1.1],
                        turn: simd_quatf(angle: .pi / 2, axis: [1, 0, 0]))
                }
            }
        case .labyrinth:
            for (x, z, w, d) in [(-8, 0, 14, 1), (8, 0, 14, 1), (0, -3, 1, 6), (-4, 3, 8, 1), (5, -5, 10, 1), (-10, -4, 1, 8)]
                as [(Float, Float, Float, Float)] {
                add(.generateBox(width: w, height: 3, depth: d), Bestiary.paint([0.12, 0.3, 0.12]), [x, 1.5, z])
            }
        case .spiders:
            for (i, x) in ([-4, 0, 4] as [Float]).enumerated() {
                let spider = Entity()
                let black = Bestiary.paint([0.08, 0.07, 0.07])
                let body = ModelEntity(mesh: .generateSphere(radius: 1.2), materials: [black])
                body.position.y = 1.6
                body.scale = [1, 0.8, 1.3]
                spider.addChild(body)
                for leg in 0..<8 {
                    let a = Float(leg) / 8 * 2 * .pi
                    let l = ModelEntity(mesh: .generateCylinder(height: 2.6, radius: 0.08), materials: [black])
                    l.position = [cos(a) * 1.3, 1.1, sin(a) * 1.3]
                    l.orientation = simd_quatf(angle: 0.9, axis: [-sin(a), 0, cos(a)])
                    spider.addChild(l)
                }
                spider.position = [x, 0, Float(i % 2) * 1.5]
                e.addChild(spider)
            }
        }
        return e
    }
}
