import CoreGraphics
import OdysseyKit
import RealityKit
import simd

/// Whoever the party is dealing with, stood a little way ahead of it: monsters, a
/// caravan, a wizard and his apprentices, warriors; or a chest to open. Figures
/// fall as the battle goes against them.
@MainActor
final class Cast {
    let root = Entity()
    private let landscape: Landscape
    private let light: Entity

    /// What the current visit shows.
    private struct Sight: Equatable {
        var band: Band?
        var count = 0
        var chest = false
    }

    private var sight = Sight()
    private var figures: [Figure] = []          // standing, the leader first
    private var fallen: [Figure] = []           // toppling, or (if they just went away) fading
    private var chest: Entity?
    /// Where the band stands, and the way it faces (towards the party).
    private var anchor: SIMD3<Float> = .zero
    private var facing: SIMD3<Float> = [0, 0, 1]
    private var clock: Float = 0
    private var lungeUntil: Float = 0
    private var lastRound: [Int] = []

    init(landscape: Landscape, light: Entity) {
        self.landscape = landscape
        self.light = light
    }

    func update(visit: Visit?, party: SIMD3<Float>, heading: Float, dt: Float) {
        clock += dt
        let next = Cast.sight(of: visit)
        let forward = SIMD3<Float>(-sin(heading), 0, -cos(heading))

        if next.band != sight.band {
            dismiss(beaten: Cast.won(visit))
            if let band = next.band {
                anchor = party + forward * (band.isLarge ? 16 : 10)
                facing = -forward
                if band == .merchants { add(Bestiary.wagon(), permanent: true) }
                for i in 0..<next.count { add(Bestiary.figure(band, index: i)) }
                arrange()
            }
        } else if let band = next.band, next.count > sight.count {
            for i in sight.count..<next.count { add(Bestiary.figure(band, index: i)) }
            arrange()
        } else if next.count < sight.count {
            // The last of the band fall first; the leader (and the wagon) stand to the end.
            for f in figures.filter({ !$0.permanent }).suffix(sight.count - next.count) { fall(f) }
        }
        if case let .battle(b)? = visit?.stage {
            let round = [b.ourLosses, b.theirLosses, b.lastRound?.ourTotal ?? -1]
            if !lastRound.isEmpty && round != lastRound { lungeUntil = clock + 0.5 }
            lastRound = round
        } else {
            lastRound = []
        }

        if next.chest && chest == nil {
            let c = Bestiary.chest()
            let p = party + forward * 5 + SIMD3(-forward.z, 0, forward.x) * 1.5
            c.position = [p.x, ground(p), p.z]
            c.orientation = simd_quatf(angle: heading, axis: [0, 1, 0])
            c.scale = .init(repeating: 0.01)
            WorldBuilder.applyLightReceiver(c, light: light)
            root.addChild(c)
            chest = c
        } else if !next.chest, let c = chest {
            c.removeFromParent()
            chest = nil
        }
        if let c = chest, c.scale.x < 1 {
            c.scale = .init(repeating: min(c.scale.x + dt * 3, 1))
        }
        sight = next

        animate(party: party, dt: dt)
    }

    // MARK: What a visit shows

    private static func sight(of visit: Visit?) -> Sight {
        guard let visit else { return Sight() }
        switch visit.stage {
        case let .monstersAhead(m), let .offering(m):
            let band = Band.monsters(m)
            return Sight(band: band, count: band.most)
        case let .battle(b):
            let band = Band(b.foe)
            let full = Double(min(band.most, b.theirNumber))
            let shown = (full * Double(b.theirStanding) / Double(max(b.theirNumber, 1))).rounded(.up)
            return Sight(band: band, count: max(Int(shown), 0))
        case .caravan: return Sight(band: .merchants, count: 3)
        case let .wizard(good): return Sight(band: .wizard(good: good), count: 4)
        case .warriors: return Sight(band: .warriors, count: 5)
        case .chest, .spoils: return Sight(chest: true)
        default: return Sight()
        }
    }

    /// Whether the band just lost the battle (and so should fall, not walk off).
    private static func won(_ visit: Visit?) -> Bool {
        guard let visit else { return false }
        if case .spoils = visit.stage { return true }
        return visit.said.contains { $0.hasPrefix("CONGRATULATIONS") && $0.contains("KILLED ALL") }
    }

    // MARK: Staging

    private func add(_ f: Figure, permanent: Bool = false) {
        f.permanent = permanent
        f.entity.scale = .init(repeating: 0.01)
        WorldBuilder.applyLightReceiver(f.entity, light: light)
        root.addChild(f.entity)
        figures.append(f)
    }

    private func fall(_ f: Figure) {
        f.fallen = clock
        f.fallFrom = f.entity.orientation
        fallen.append(f)
        figures.removeAll { $0 === f }
    }

    /// Clear the band away: beaten, they fall where they stand; otherwise they fade.
    private func dismiss(beaten: Bool) {
        for f in figures {
            if beaten && !f.permanent {
                fall(f)
            } else {
                f.leaving = true
                fallen.append(f)
            }
        }
        figures = []
    }

    /// Spread the band in a loose rank across the party's path, the leader in the
    /// middle; a caravan's wagon stands behind.
    private func arrange() {
        let side = SIMD3<Float>(facing.z, 0, -facing.x)
        let walkers = figures.filter { !$0.flies && !$0.permanent }
        let spacing = walkers.map(\.width).max() ?? 1.5
        for (i, f) in walkers.enumerated() {
            // 0, 1, -1, 2, -2...
            let rank = Float((i + 1) / 2) * (i % 2 == 0 ? 1 : -1)
            f.home = anchor + side * rank * spacing - facing * Float(i % 3) * 0.7
        }
        for f in figures where f.permanent {
            f.home = anchor - facing * 4
        }
        let flyers = figures.filter(\.flies)
        for (i, f) in flyers.enumerated() {
            f.home = anchor
            f.phase = Float(i) * 2 * .pi / Float(flyers.count)
        }
    }

    private func ground(_ p: SIMD3<Float>) -> Float {
        max(landscape.height(world: [p.x, p.z]), 0.1)
    }

    private func animate(party: SIMD3<Float>, dt: Float) {
        let lunge = clock < lungeUntil ? sin((lungeUntil - clock) / 0.5 * .pi) : 0
        for f in figures {
            if f.entity.scale.x < 1 {
                f.entity.scale = .init(repeating: min(f.entity.scale.x + dt * 2.5, 1))
            }
            var p: SIMD3<Float>
            if f.flies {
                // Wheel overhead, swooping low when they strike.
                let a = clock * 0.6 + f.phase
                p = f.home + [cos(a) * 7, 0, sin(a) * 7]
                p.y = ground(p) + 6 + sin(clock * 1.7 + f.phase) - lunge * 3.5
                // Flying anticlockwise seen from above: the way ahead is along the tangent.
                f.entity.orientation = simd_quatf(angle: atan2(-sin(a), cos(a)) + .pi, axis: [0, 1, 0])
            } else if f.permanent {
                p = f.home
                p.y = ground(p)
                f.entity.orientation = simd_quatf(angle: atan2(-facing.x, -facing.z) + .pi / 2, axis: [0, 1, 0])
            } else {
                p = f.home + simd_normalize(party - f.home) * lunge * 2
                p.y = ground(p) + abs(sin(clock * 2.2 + f.phase)) * 0.08
                let toward = party - p
                f.entity.orientation = simd_quatf(angle: atan2(-toward.x, -toward.z), axis: [0, 1, 0])
            }
            f.entity.position = p
            f.move(clock)
        }
        for f in fallen {
            if f.leaving {
                // Gone on their way.
                let s = f.entity.scale.x - dt * 2
                f.entity.scale = .init(repeating: max(s, 0.01))
                if s <= 0.01 { f.entity.removeFromParent() }
                continue
            }
            // Topple, lie a while, then sink away.
            let t = clock - (f.fallen ?? clock)
            var p = f.entity.position
            if f.flies && p.y > ground(p) {
                p.y = max(p.y - dt * 14, ground(p))
            } else if t > 1.5 {
                p.y -= dt * 0.8
            }
            f.entity.position = p
            f.entity.orientation = f.fallFrom * simd_quatf(angle: min(t / 0.6, 1) * .pi / 2, axis: [1, 0, 0])
            if t > 4 { f.entity.removeFromParent() }
        }
        fallen.removeAll { $0.entity.parent == nil }
    }
}

/// Who stands in a band.
enum Band: Equatable {
    case monsters(Monster), merchants, wizard(good: Bool), warriors

    init(_ foe: Foe) {
        switch foe {
        case let .monsters(m): self = .monsters(m)
        case .merchants: self = .merchants
        case .wizards: self = .wizard(good: true)
        case .warlocks: self = .wizard(good: false)
        case .warriors: self = .warriors
        }
    }

    /// The most figures shown: a few of the great beasts, more of the rest.
    var most: Int {
        guard case let .monsters(m) = self else { return 5 }
        switch m.kind {
        case 13, 16, 17: return 2              // dragons, allosaurs, rocs
        case 3, 9, 14: return 3                // ogres, cyclops, minotaurs
        default: return 6
        }
    }

    /// The great beasts stand further off.
    var isLarge: Bool {
        if case .monsters = self { most < 6 } else { false }
    }
}

/// One figure in a band: its model, and how it moves.
@MainActor
final class Figure {
    let entity: Entity
    let flies: Bool
    /// About how wide it stands, for spacing the rank.
    let width: Float
    var home: SIMD3<Float> = .zero
    var phase = Float.random(in: 0...6)
    var permanent = false
    var fallen: Float?
    var fallFrom = simd_quatf(angle: 0, axis: [0, 1, 0])
    var leaving = false
    /// Parts that move: wings flap, serpents' coils ripple.
    var wings: [Entity] = []
    var coils: [Entity] = []

    init(_ entity: Entity, flies: Bool = false, width: Float = 1.5) {
        self.entity = entity
        self.flies = flies
        self.width = width
    }

    func move(_ t: Float) {
        for (i, w) in wings.enumerated() {
            let side: Float = i % 2 == 0 ? 1 : -1
            w.orientation = simd_quatf(angle: side * (0.15 + sin(t * (flies ? 5 : 1.5) + phase) * (flies ? 0.6 : 0.15)),
                                       axis: [0, 0, 1])
        }
        for (i, c) in coils.enumerated() {
            c.position.x = sin(t * 3 + phase - Float(i) * 0.7) * 0.35 * Float(i) / Float(max(coils.count, 1)) * 2
        }
    }
}

// MARK: - The figures

/// Low-poly figures built from RealityKit's primitives. Every figure faces -z.
@MainActor
enum Bestiary {
    private static var paints: [String: PhysicallyBasedMaterial] = [:]

    static func paint(_ c: SIMD3<Float>, metal: Float = 0, glow: Bool = false) -> PhysicallyBasedMaterial {
        let key = "\(c)\(metal)\(glow)"
        if let m = paints[key] { return m }
        var m = PhysicallyBasedMaterial()
        let (r, g, b) = (CGFloat(c.x), CGFloat(c.y), CGFloat(c.z))
        m.baseColor = .init(tint: .init(red: r, green: g, blue: b, alpha: 1))
        m.roughness = metal > 0 ? 0.35 : 0.85
        m.metallic = .init(floatLiteral: metal)
        if glow {
            m.emissiveColor = .init(color: .init(red: r, green: g, blue: b, alpha: 1))
            m.emissiveIntensity = 2.5
        }
        paints[key] = m
        return m
    }

    private static func part(_ mesh: MeshResource, _ colour: SIMD3<Float>, at p: SIMD3<Float>,
                             turn: simd_quatf? = nil, scale: SIMD3<Float>? = nil, metal: Float = 0, glow: Bool = false,
                             in parent: Entity) -> ModelEntity {
        let e = ModelEntity(mesh: mesh, materials: [paint(colour, metal: metal, glow: glow)])
        e.position = p
        if let turn { e.orientation = turn }
        if let scale { e.scale = scale }
        e.components.set(GroundingShadowComponent(castsShadow: true))
        parent.addChild(e)
        return e
    }

    private static let pointForward = simd_quatf(angle: -.pi / 2, axis: [1, 0, 0])

    /// A pair of wings hinged at the shoulders, each a pivot to flap.
    private static func addWings(to f: Figure, at shoulder: SIMD3<Float>, span: Float, chord: Float, colour: SIMD3<Float>) {
        for side: Float in [1, -1] {
            let pivot = Entity()
            pivot.position = shoulder + [side * 0.1, 0, 0]
            f.entity.addChild(pivot)
            _ = part(.generateBox(width: span, height: 0.06, depth: chord, cornerRadius: 0.03), colour,
                     at: [side * span / 2, 0, chord * 0.15], in: pivot)
            f.wings.append(pivot)
        }
    }

    struct Look {
        var skin: SIMD3<Float>
        var cloth: SIMD3<Float>
        var scale: Float = 1
        var snout = false
        var ears = false
        var horns = false
        var oneEye = false
        var snakeHair = false
        var club = false
        var blade = false
        var shield = false
        var helm = false
        var eyes: SIMD3<Float>?
        var glow = false
        var hunch: Float = 0
    }

    /// Two legs, a body, arms and a head, with whatever marks the kind.
    static func humanoid(_ look: Look) -> Figure {
        let root = Entity()
        let body = Entity()
        body.scale = .init(repeating: look.scale)
        root.addChild(body)
        let f = Figure(root, width: 1.2 * look.scale + 0.4)
        let dark = look.cloth * 0.7
        for x: Float in [-0.14, 0.14] {
            _ = part(.generateCylinder(height: 0.75, radius: 0.09), dark, at: [x, 0.37, 0], in: body)
        }
        let torso = Entity()
        torso.position = [0, 0.75, 0]
        torso.orientation = simd_quatf(angle: -look.hunch, axis: [1, 0, 0])
        body.addChild(torso)
        _ = part(.generateBox(width: 0.56, height: 0.72, depth: 0.32, cornerRadius: 0.1), look.cloth, at: [0, 0.36, 0],
                 glow: look.glow, in: torso)
        for x: Float in [-0.36, 0.36] {
            _ = part(.generateCylinder(height: 0.68, radius: 0.075), look.skin, at: [x, 0.3, -0.05],
                     turn: simd_quatf(angle: x > 0 ? 0.15 : -0.15, axis: [0, 0, 1]), glow: look.glow, in: torso)
        }
        let head = Entity()
        head.position = [0, 0.92, 0]
        torso.addChild(head)
        _ = part(.generateSphere(radius: 0.21), look.skin, at: .zero, glow: look.glow, in: head)
        if look.snout {
            _ = part(.generateCone(height: 0.32, radius: 0.11), look.skin, at: [0, -0.04, -0.28], turn: pointForward, in: head)
        }
        if look.ears {
            for x: Float in [-0.12, 0.12] {
                _ = part(.generateCone(height: 0.16, radius: 0.06), look.skin, at: [x, 0.22, 0], in: head)
            }
        }
        if look.horns {
            for x: Float in [-1, 1] {
                _ = part(.generateCone(height: 0.32, radius: 0.06), [0.9, 0.86, 0.75], at: [x * 0.16, 0.2, 0],
                         turn: simd_quatf(angle: -x * 0.7, axis: [0, 0, 1]), in: head)
            }
        }
        if look.oneEye {
            _ = part(.generateSphere(radius: 0.08), [0.95, 0.95, 0.9], at: [0, 0.04, -0.17], in: head)
            _ = part(.generateSphere(radius: 0.035), [0.05, 0.05, 0.05], at: [0, 0.04, -0.24], in: head)
        } else if let eyes = look.eyes {
            for x: Float in [-0.08, 0.08] {
                _ = part(.generateSphere(radius: 0.035), eyes, at: [x, 0.04, -0.18], glow: true, in: head)
            }
        }
        if look.snakeHair {
            for i in 0..<9 {
                let a = Float(i) / 9 * 2 * .pi
                _ = part(.generateCone(height: 0.26, radius: 0.04), [0.25, 0.45, 0.2], at: [cos(a) * 0.15, 0.12, sin(a) * 0.15],
                         turn: simd_quatf(angle: 0.9, axis: [sin(a), 0, -cos(a)]), in: head)
            }
        }
        if look.helm {
            _ = part(.generateCone(height: 0.3, radius: 0.24), [0.7, 0.7, 0.72], at: [0, 0.2, 0], metal: 1, in: head)
        }
        if look.club {
            _ = part(.generateCylinder(height: 1.1, radius: 0.09), [0.4, 0.28, 0.16], at: [0.45, 0.1, -0.25],
                     turn: simd_quatf(angle: -0.6, axis: [1, 0, 0]), in: torso)
        }
        if look.blade {
            _ = part(.generateBox(width: 0.06, height: 1.0, depth: 0.02), [0.8, 0.8, 0.82], at: [0.42, 0.3, -0.35],
                     turn: simd_quatf(angle: -0.5, axis: [1, 0, 0]), metal: 1, in: torso)
        }
        if look.shield {
            _ = part(.generateCylinder(height: 0.05, radius: 0.32), [0.55, 0.15, 0.1], at: [-0.42, 0.3, -0.2],
                     turn: simd_quatf(angle: .pi / 2, axis: [0, 0, 1]) * simd_quatf(angle: .pi / 2, axis: [1, 0, 0]),
                     in: torso)
        }
        return f
    }

    /// A great snake, its coils trailing behind its raised head.
    static func serpent(colour: SIMD3<Float>, belly: SIMD3<Float>, scale: Float) -> Figure {
        let root = Entity()
        root.scale = .init(repeating: scale)
        let f = Figure(root, width: 1.4 * scale)
        for i in 0..<10 {
            let t = Float(i) / 9
            let r = 0.32 - t * 0.2
            let seg = part(.generateSphere(radius: r), i % 2 == 0 ? colour : colour * 0.85, at: [0, r, 0.15 + Float(i) * 0.42],
                           in: root)
            f.coils.append(seg)
        }
        _ = part(.generateCylinder(height: 1.2, radius: 0.24), colour, at: [0, 0.75, -0.2],
                 turn: simd_quatf(angle: -0.4, axis: [1, 0, 0]), in: root)
        _ = part(.generateBox(width: 0.42, height: 0.26, depth: 0.6, cornerRadius: 0.1), colour, at: [0, 1.38, -0.55], in: root)
        _ = part(.generateBox(width: 0.3, height: 0.08, depth: 0.5, cornerRadius: 0.03), belly, at: [0, 1.22, -0.55], in: root)
        for x: Float in [-0.12, 0.12] {
            _ = part(.generateSphere(radius: 0.045), [0.95, 0.8, 0.1], at: [x, 1.48, -0.75], glow: true, in: root)
        }
        return f
    }

    static func dragon() -> Figure {
        let root = Entity()
        let f = Figure(root, width: 7)
        let red: SIMD3<Float> = [0.55, 0.1, 0.07], belly: SIMD3<Float> = [0.85, 0.62, 0.25]
        _ = part(.generateSphere(radius: 1), red, at: [0, 2.6, 0], scale: [1.6, 1.3, 2.6], in: root)
        _ = part(.generateSphere(radius: 1), belly, at: [0, 2.2, -0.2], scale: [1.3, 0.9, 2.2], in: root)
        for i in 0..<4 {
            let t = Float(i + 1) / 4
            _ = part(.generateSphere(radius: 0.55 - 0.08 * Float(i)), red, at: [0, 3 + t * 2.2, -2.2 - t * 1.4], in: root)
        }
        _ = part(.generateBox(width: 0.8, height: 0.7, depth: 1.6, cornerRadius: 0.2), red, at: [0, 5.3, -4.1], in: root)
        for x: Float in [-0.25, 0.25] {
            _ = part(.generateCone(height: 0.6, radius: 0.1), [0.9, 0.86, 0.75], at: [x, 5.8, -3.6],
                     turn: simd_quatf(angle: 0.6, axis: [1, 0, 0]), in: root)
            _ = part(.generateSphere(radius: 0.08), [1, 0.85, 0.2], at: [x, 5.45, -4.6], glow: true, in: root)
        }
        for i in 0..<6 {
            _ = part(.generateSphere(radius: 0.6 - Float(i) * 0.08), red, at: [0, 2.4 - Float(i) * 0.3, 2.6 + Float(i) * 0.9],
                     in: root)
        }
        for x: Float in [-1.1, 1.1] {
            for z: Float in [-1.2, 1.4] {
                _ = part(.generateCylinder(height: 2, radius: 0.32), red * 0.8, at: [x, 1, z], in: root)
            }
        }
        addWings(to: f, at: [0, 3.6, -0.4], span: 6, chord: 2.6, colour: [0.42, 0.08, 0.06])
        return f
    }

    static func allosaur() -> Figure {
        let root = Entity()
        let f = Figure(root, width: 5)
        let hide: SIMD3<Float> = [0.36, 0.40, 0.2]
        _ = part(.generateSphere(radius: 1), hide, at: [0, 2.8, 0], turn: simd_quatf(angle: 0.15, axis: [1, 0, 0]),
                 scale: [1, 1.1, 2.2], in: root)
        _ = part(.generateBox(width: 0.9, height: 1, depth: 1.7, cornerRadius: 0.25), hide, at: [0, 3.9, -2.6], in: root)
        _ = part(.generateBox(width: 0.7, height: 0.3, depth: 1.4, cornerRadius: 0.1), [0.7, 0.3, 0.25], at: [0, 3.35, -2.6],
                 in: root)
        for i in 0..<6 {
            _ = part(.generateSphere(radius: 0.6 - Float(i) * 0.09), hide, at: [0, 2.9 - Float(i) * 0.25, 2 + Float(i) * 0.8],
                     in: root)
        }
        for x: Float in [-0.6, 0.6] {
            _ = part(.generateCylinder(height: 2.2, radius: 0.35), hide * 0.85, at: [x, 1.1, 0.3], in: root)
            _ = part(.generateCylinder(height: 0.7, radius: 0.1), hide, at: [x * 0.8, 2.6, -1.6],
                     turn: simd_quatf(angle: -0.8, axis: [1, 0, 0]), in: root)
            _ = part(.generateSphere(radius: 0.08), [0.9, 0.7, 0.1], at: [x * 0.6, 4.2, -3.2], glow: true, in: root)
        }
        return f
    }

    /// The flyers: a body slung between two great wings.
    static func flyer(body: SIMD3<Float>, wings: SIMD3<Float>, span: Float, beak: Bool, crest: Bool) -> Figure {
        let root = Entity()
        let f = Figure(root, flies: true, width: span)
        _ = part(.generateSphere(radius: 0.5), body, at: .zero, scale: [0.8, 0.7, 1.8], in: root)
        _ = part(.generateSphere(radius: 0.3), body, at: [0, 0.25, -0.95], in: root)
        if beak {
            _ = part(.generateCone(height: 0.5, radius: 0.12), [0.85, 0.7, 0.2], at: [0, 0.2, -1.4], turn: pointForward, in: root)
        }
        if crest {
            _ = part(.generateCone(height: 0.9, radius: 0.08), body, at: [0, 0.4, -0.6],
                     turn: simd_quatf(angle: 1.2, axis: [1, 0, 0]), in: root)
            _ = part(.generateCone(height: 0.9, radius: 0.07), body, at: [0, 0.2, -1.6], turn: pointForward, in: root)
        }
        _ = part(.generateCone(height: 1, radius: 0.25), body, at: [0, 0, 1.2],
                 turn: simd_quatf(angle: .pi / 2, axis: [1, 0, 0]), in: root)
        addWings(to: f, at: [0, 0.15, -0.1], span: span / 2, chord: span / 5, colour: wings)
        return f
    }

    /// Winged humanoids that fly: harpies and gargoyles.
    private static func wingedOne(_ look: Look, wings: SIMD3<Float>) -> Figure {
        let f = humanoid(look)
        let flying = Figure(f.entity, flies: true, width: 3)
        addWings(to: flying, at: [0, 1.45, 0.2], span: 1.8, chord: 0.8, colour: wings)
        return flying
    }

    static func monster(_ m: Monster) -> Figure {
        switch m.kind {
        case 1: humanoid(Look(skin: [0.55, 0.6, 0.5], cloth: [0.25, 0.24, 0.22], eyes: [0.6, 0.9, 0.4], hunch: 0.35))    // ghouls
        case 2: humanoid(Look(skin: [0.42, 0.32, 0.22], cloth: [0.35, 0.26, 0.18], snout: true, ears: true, eyes: [0.9, 0.7, 0.1], hunch: 0.25))
        case 3: humanoid(Look(skin: [0.62, 0.5, 0.36], cloth: [0.4, 0.3, 0.2], scale: 2.2, club: true))                   // ogres
        case 4: humanoid(Look(skin: [0.45, 0.6, 0.38], cloth: [0.55, 0.5, 0.3], snakeHair: true, eyes: [1, 0.9, 0.3]))     // gorgons
        case 5: humanoid(Look(skin: [0.85, 0.83, 0.8], cloth: [0.08, 0.06, 0.08], eyes: [0.9, 0.1, 0.1]))                 // vampires
        case 6: humanoid(Look(skin: [0.45, 0.45, 0.45], cloth: [0.38, 0.38, 0.38], snout: true, ears: true, eyes: [0.9, 0.8, 0.2], hunch: 0.3))
        case 7: humanoid(Look(skin: [0.78, 0.72, 0.58], cloth: [0.74, 0.68, 0.54], eyes: [0.3, 0.6, 1], hunch: 0.1))       // mummies
        case 8: humanoid(Look(skin: [0.35, 0.45, 0.25], cloth: [0.3, 0.3, 0.32], blade: true, shield: true))               // orcs
        case 9: humanoid(Look(skin: [0.7, 0.58, 0.45], cloth: [0.45, 0.35, 0.22], scale: 2.6, oneEye: true, club: true))   // cyclops
        case 10: humanoid(Look(skin: [0.55, 0.6, 0.25], cloth: [0.35, 0.28, 0.2], scale: 0.7, ears: true, blade: true, eyes: [1, 0.8, 0.1]))
        case 11: serpent(colour: [0.2, 0.42, 0.18], belly: [0.7, 0.7, 0.4], scale: 1.8)                                    // giant snakes
        case 12: serpent(colour: [0.72, 0.6, 0.38], belly: [0.9, 0.82, 0.6], scale: 1.6)                                   // sandserpents
        case 13: dragon()
        case 14: humanoid(Look(skin: [0.38, 0.25, 0.16], cloth: [0.3, 0.2, 0.12], scale: 1.8, snout: true, horns: true, club: true))
        case 15: humanoid(Look(skin: [0.95, 0.3, 0.08], cloth: [0.7, 0.12, 0.04], scale: 1.4, horns: true, eyes: [1, 1, 0.5], glow: true))
        case 16: allosaur()
        case 17: flyer(body: [0.4, 0.28, 0.16], wings: [0.32, 0.22, 0.12], span: 9, beak: true, crest: false)             // rocs
        case 18: flyer(body: [0.55, 0.5, 0.42], wings: [0.5, 0.42, 0.36], span: 6, beak: false, crest: true)              // pterodactyls
        case 19: wingedOne(Look(skin: [0.8, 0.65, 0.55], cloth: [0.4, 0.3, 0.25], eyes: [0.9, 0.2, 0.2]), wings: [0.45, 0.35, 0.25])
        default: wingedOne(Look(skin: [0.5, 0.5, 0.48], cloth: [0.45, 0.45, 0.43], horns: true, eyes: [1, 0.4, 0.1], hunch: 0.3),
                           wings: [0.4, 0.4, 0.38])                                                                         // gargoyles
        }
    }

    static func figure(_ band: Band, index i: Int) -> Figure {
        switch band {
        case let .monsters(m):
            return monster(m)
        case .merchants:
            let robes: [SIMD3<Float>] = [[0.2, 0.3, 0.6], [0.7, 0.5, 0.15], [0.25, 0.45, 0.3], [0.5, 0.2, 0.35]]
            let f = humanoid(Look(skin: [0.7, 0.52, 0.38], cloth: robes[i % robes.count], blade: i > 0))
            _ = part(.generateSphere(radius: 0.26), [0.92, 0.9, 0.82], at: [0, 1.82, 0], scale: [1, 0.6, 1], in: f.entity)
            return f
        case let .wizard(good):
            return i == 0 ? wizard(good: good) : apprentice(good: good)
        case .warriors:
            return humanoid(Look(skin: [0.72, 0.55, 0.4], cloth: [0.42, 0.3, 0.18], blade: i % 2 == 0, shield: true, helm: true))
        }
    }

    private static func wizard(good: Bool) -> Figure {
        let root = Entity()
        let f = Figure(root, width: 1.4)
        let robe: SIMD3<Float> = good ? [0.18, 0.22, 0.6] : [0.12, 0.05, 0.14]
        _ = part(.generateCone(height: 1.6, radius: 0.5), robe, at: [0, 0.8, 0], in: root)
        _ = part(.generateSphere(radius: 0.21), [0.85, 0.7, 0.58], at: [0, 1.7, 0], in: root)
        _ = part(.generateCone(height: 0.32, radius: 0.15), [0.9, 0.9, 0.9], at: [0, 1.48, -0.12],
                 turn: simd_quatf(angle: .pi, axis: [1, 0, 0]), in: root)                                     // a beard
        _ = part(.generateCone(height: 0.8, radius: 0.3), robe, at: [0, 2.15, 0],
                 turn: simd_quatf(angle: 0.15, axis: [1, 0, 0]), in: root)
        _ = part(.generateCylinder(height: 2.2, radius: 0.04), [0.4, 0.28, 0.16], at: [0.5, 1.1, -0.2], in: root)
        _ = part(.generateSphere(radius: 0.12), good ? [0.5, 0.8, 1] : [0.7, 0.2, 0.9], at: [0.5, 2.25, -0.2], glow: true,
                 in: root)
        return f
    }

    private static func apprentice(good: Bool) -> Figure {
        let root = Entity()
        let f = Figure(root, width: 1.1)
        let robe: SIMD3<Float> = good ? [0.5, 0.48, 0.42] : [0.25, 0.2, 0.22]
        _ = part(.generateCone(height: 1.3, radius: 0.4), robe, at: [0, 0.65, 0], in: root)
        _ = part(.generateSphere(radius: 0.24), robe * 0.85, at: [0, 1.4, 0.03], in: root)                // the hood
        _ = part(.generateSphere(radius: 0.16), [0.8, 0.64, 0.5], at: [0, 1.38, -0.08], in: root)
        return f
    }

    static func wagon() -> Figure {
        let root = Entity()
        let wood: SIMD3<Float> = [0.45, 0.31, 0.18]
        _ = part(.generateBox(width: 1.8, height: 0.6, depth: 3, cornerRadius: 0.05), wood, at: [0, 0.9, 0], in: root)
        _ = part(.generateBox(width: 1.7, height: 1.2, depth: 2.6, cornerRadius: 0.6), [0.88, 0.84, 0.72], at: [0, 1.75, 0],
                 in: root)
        for x: Float in [-0.95, 0.95] {
            for z: Float in [-1, 1] {
                _ = part(.generateCylinder(height: 0.12, radius: 0.55), wood * 0.7, at: [x, 0.55, z],
                         turn: simd_quatf(angle: .pi / 2, axis: [0, 0, 1]), in: root)
            }
        }
        for (i, c) in ([[0.6, 0.2, 0.15], [0.3, 0.45, 0.6], [0.75, 0.62, 0.25]] as [SIMD3<Float>]).enumerated() {
            _ = part(.generateBox(width: 0.5, height: 0.5, depth: 0.5, cornerRadius: 0.05), c,
                     at: [Float(i - 1) * 0.6, 0.25, -2], in: root)
        }
        return Figure(root, width: 3)
    }

    /// Something left lying on the ground.
    static func sack() -> Entity {
        let root = Entity()
        _ = part(.generateSphere(radius: 0.5), [0.72, 0.6, 0.38], at: [0, 0.4, 0], scale: [1, 0.85, 1], in: root)
        _ = part(.generateCone(height: 0.35, radius: 0.22), [0.72, 0.6, 0.38], at: [0, 0.85, 0], in: root)
        _ = part(.generateCylinder(height: 0.08, radius: 0.12), [0.4, 0.25, 0.12], at: [0, 0.82, 0], in: root)
        _ = part(.generateBox(width: 0.5, height: 0.4, depth: 0.1), [0.45, 0.31, 0.18], at: [0.6, 0.2, 0.1],
                 turn: simd_quatf(angle: 0.6, axis: [0, 1, 0]), in: root)
        return root
    }

    static func chest() -> Entity {
        let root = Entity()
        let wood: SIMD3<Float> = [0.42, 0.27, 0.14], iron: SIMD3<Float> = [0.3, 0.3, 0.32]
        _ = part(.generateBox(width: 1.1, height: 0.6, depth: 0.7, cornerRadius: 0.03), wood, at: [0, 0.3, 0], in: root)
        _ = part(.generateBox(width: 1.12, height: 0.28, depth: 0.72, cornerRadius: 0.12), wood * 0.9, at: [0, 0.68, 0],
                 in: root)
        for x: Float in [-0.35, 0.35] {
            _ = part(.generateBox(width: 0.08, height: 0.84, depth: 0.74), iron, at: [x, 0.42, 0], metal: 0.8, in: root)
        }
        _ = part(.generateBox(width: 0.16, height: 0.2, depth: 0.04), [0.95, 0.75, 0.3], at: [0, 0.55, -0.37], metal: 1, in: root)
        return root
    }
}
