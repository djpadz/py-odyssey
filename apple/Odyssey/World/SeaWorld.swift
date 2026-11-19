import CoreGraphics
import Foundation
import ImageIO
import OdysseyKit
import RealityKit
import simd

/// The Sargalo Sea from the chart: the picture's islands and reefs rising from a
/// seabed that deepens with the chart's soundings, and drops away past the edge of
/// the world. Chart pixels map to metres as the island's map pixels do.
struct Seascape: Sendable {
    static let step = 2.0
    static let texelsPerPixel = 2
    let originX = -WorldScale.margin, originY = -WorldScale.margin
    let columns: Int, rows: Int
    private(set) var heights: [Float] = []
    /// How much land and reef there is about each sample, 0...1.
    private(set) var land: [Float] = []
    private(set) var reef: [Float] = []
    let noise: Noise

    init(seed: UInt64) {
        noise = Noise(seed: UInt32(truncatingIfNeeded: seed ^ 0x5EA))
        columns = Int((Double(SeaChart.width) + 2 * WorldScale.margin) / Seascape.step) + 1
        rows = Int((Double(SeaChart.height) + 2 * WorldScale.margin) / Seascape.step) + 1
        for r in 0..<rows {
            for c in 0..<columns {
                let x = originX + Double(c) * Seascape.step, y = originY + Double(r) * Seascape.step
                let (l, f) = Seascape.blur(x: Int(x), y: Int(y))
                land.append(l)
                reef.append(f)
                heights.append(height(x: Float(x), y: Float(y), land: l, reef: f))
            }
        }
    }

    /// Land and reef about a pixel, weighted to soften the picture's edges.
    private static func blur(x: Int, y: Int) -> (Float, Float) {
        var l: Float = 0, f: Float = 0, total: Float = 0
        for dy in -3...3 {
            for dx in -3...3 {
                let k = exp(-Float(dx * dx + dy * dy) / 4.5)
                switch SeaChart.ground(x: x + dx, y: y + dy) {
                case .land: l += k
                case .reef: f += k
                case .sea: break
                }
                total += k
            }
        }
        return (l / total, f / total)
    }

    private func height(x: Float, y: Float, land l: Float, reef f: Float) -> Float {
        let onChart = x >= 8 && x <= 272 && y >= 8 && y <= 157
        let depth = Float(SeaChart.water(x: Int(x), y: Int(y))?.depth ?? 6)
        var bed = onChart ? -(1.5 + depth * 0.25) : -60               // the edge of the world
        bed += (noise.fbm(x / 9, y / 9) - 0.5) * 1.2
        var h = simd_mix(bed, 0.4, smoothstep(0.05, 0.45, l))
        if l > 0.45 {
            h += smoothstep(0.45, 1, l) * (2.5 + 7 * noise.fbm(x / 14 + 20, y / 14)) + noise.fbm(x / 3, y / 3) * 0.6
        }
        if f > 0.05 { h = max(h, simd_mix(bed, -0.3, smoothstep(0.05, 0.4, f))) }
        return h
    }

    private func sample(_ grid: [Float], x: Double, y: Double) -> Float {
        let fx = min(max((x - originX) / Seascape.step, 0), Double(columns - 1) - 0.001)
        let fy = min(max((y - originY) / Seascape.step, 0), Double(rows - 1) - 0.001)
        let c = Int(fx), r = Int(fy)
        let tx = Float(fx - Double(c)), ty = Float(fy - Double(r))
        let i = r * columns + c
        return simd_mix(simd_mix(grid[i], grid[i + 1], tx), simd_mix(grid[i + columns], grid[i + columns + 1], tx), ty)
    }

    func height(x: Double, y: Double) -> Float { sample(heights, x: x, y: y) }

    func height(world p: SIMD2<Float>) -> Float {
        let m = WorldScale.map(p)
        return height(x: m.x, y: m.y)
    }

    func meshData() -> Landscape.MeshData {
        Landscape.mesh(heights, columns: columns, rows: rows, originX: originX, originY: originY, step: Seascape.step)
    }

    func texture() -> (width: Int, height: Int, pixels: [UInt8]) {
        let per = Seascape.texelsPerPixel
        let w = (columns - 1) * Int(Seascape.step) * per, h = (rows - 1) * Int(Seascape.step) * per
        var px = [UInt8](repeating: 255, count: w * h * 4)
        for ty in 0..<h {
            for tx in 0..<w {
                let x = originX + Double(tx) / Double(per), y = originY + Double(ty) / Double(per)
                let c = colour(x: x, y: y)
                let o = (ty * w + tx) * 4
                px[o] = UInt8(min(max(c.x, 0), 1) * 255)
                px[o + 1] = UInt8(min(max(c.y, 0), 1) * 255)
                px[o + 2] = UInt8(min(max(c.z, 0), 1) * 255)
            }
        }
        return (w, h, px)
    }

    private func colour(x: Double, y: Double) -> SIMD3<Float> {
        let h = height(x: x, y: y), l = sample(land, x: x, y: y), f = sample(reef, x: x, y: y)
        let fx = Float(x), fy = Float(y)
        let grain = noise.fbm(fx / 1.3, fy / 1.3, octaves: 2)
        let patch = noise.fbm(fx / 8 + 7, fy / 8)
        let jungle = simd_mix(SIMD3<Float>(0.12, 0.32, 0.12), [0.24, 0.44, 0.15], SIMD3(repeating: patch)) * (0.85 + 0.3 * grain)
        let sand = SIMD3<Float>(0.84, 0.76, 0.55) * (0.92 + 0.16 * grain)
        let rock = SIMD3<Float>(0.45, 0.33, 0.22) * (0.8 + 0.4 * grain)
        let bed = simd_mix(SIMD3<Float>(0.62, 0.58, 0.42), [0.12, 0.2, 0.26], SIMD3(repeating: smoothstep(-1, -7, h)))
        var c = simd_mix(bed, jungle, SIMD3(repeating: smoothstep(0.45, 0.6, l)))
        c = simd_mix(c, sand, SIMD3(repeating: smoothstep(0.35, 0.48, l) * (1 - smoothstep(0.55, 0.7, l))))
        return simd_mix(c, rock, SIMD3(repeating: smoothstep(0.05, 0.35, f)))
    }
}

/// The sea scene: the seascape, the ship, and whatever comes alongside.
@MainActor
final class SeaWorld {
    let root = Entity()
    let seascape: Seascape
    let ship = ShipFigure(sails: [0.93, 0.9, 0.82], flag: [0.85, 0.68, 0.18])
    let cast: SeaCast
    /// The painted chart, for the map.
    let map: CGImage?
    /// The whirlpool's swirl, shown when the ship is caught in one.
    let whirl: Entity

    private init(seascape: Seascape, ground: Entity, sky: (entity: Entity, environment: EnvironmentResource)) throws {
        self.seascape = seascape
        root.addChild(sky.entity)
        root.addChild(ground)
        root.addChild(try WorldBuilder.makeWater())
        let sun = DirectionalLight()
        sun.light.intensity = 3000
        sun.light.color = .init(red: 1, green: 0.95, blue: 0.85, alpha: 1)
        sun.shadow = DirectionalLightComponent.Shadow(maximumDistance: 160, depthBias: 2)
        sun.look(at: .zero, from: [180, 260, 120], relativeTo: nil)
        root.addChild(sun)
        root.addChild(ship.root)
        cast = SeaCast(light: root)
        root.addChild(cast.root)
        whirl = SeaWorld.swirl()
        whirl.isEnabled = false
        root.addChild(whirl)
        map = SeaWorld.chartImage()
        root.components.set(ImageBasedLightComponent(source: .single(sky.environment), intensityExponent: 0.6))
        WorldBuilder.applyLightReceiver(root, light: root)
    }

    static func build(seed: UInt64) async throws -> SeaWorld {
        let (seascape, mesh, texture) = await Task.detached(priority: .userInitiated) {
            let s = Seascape(seed: seed)
            return (s, s.meshData(), s.texture())
        }.value
        let ground = try await WorldBuilder.makeGround(mesh: mesh, texture: texture)
        let sky = try await WorldBuilder.makeSky()
        return try SeaWorld(seascape: seascape, ground: ground, sky: sky)
    }

    /// Where a chart position is in the scene, at the water.
    func place(x: Double, y: Double) -> SIMD3<Float> {
        let p = WorldScale.world(x: x, y: y)
        return [p.x, 0.05, p.y]
    }

    /// The Python port's painted chart, cut to the 160 rows the ship sails.
    private static func chartImage() -> CGImage? {
        guard let url = Bundle.main.url(forResource: "seamap", withExtension: "jpg"),
              let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }
        let scale = image.height / 192
        return image.cropping(to: CGRect(x: 0, y: 0, width: image.width, height: 160 * scale))
    }

    /// Dark rings turning on the water.
    private static func swirl() -> Entity {
        let e = Entity()
        for i in 0..<5 {
            var m = UnlitMaterial(color: .init(red: 0.03, green: 0.12, blue: 0.2, alpha: 1))
            m.blending = .transparent(opacity: .init(floatLiteral: 0.5 - Float(i) * 0.08))
            let ring = ModelEntity(mesh: .generateCylinder(height: 0.02, radius: 6 + Float(i) * 5), materials: [m])
            ring.position.y = 0.08 + Float(i) * 0.002
            e.addChild(ring)
        }
        return e
    }
}

/// A sailing ship: hull, two masts, sails that set or furl, a flag. Faces -z.
@MainActor
final class ShipFigure {
    let root = Entity()
    private let sails = Entity()
    private let furled = Entity()
    private var yaw: Float = 0
    private var clock: Float = Float.random(in: 0...6)

    init(sails colour: SIMD3<Float>, flag: SIMD3<Float>, scale: Float = 1) {
        let wood = Bestiary.paint([0.42, 0.27, 0.14]), dark = Bestiary.paint([0.25, 0.16, 0.09])
        let body = Entity()
        body.scale = .init(repeating: scale)
        root.addChild(body)
        let hull = ModelEntity(mesh: .generateBox(width: 4, height: 2.2, depth: 13, cornerRadius: 0.9), materials: [wood])
        hull.position.y = 0.6
        let bow = ModelEntity(mesh: .generateCone(height: 3.4, radius: 1.6), materials: [wood])
        bow.position = [0, 0.9, -7.4]
        bow.orientation = simd_quatf(angle: -.pi / 2, axis: [1, 0, 0])
        bow.scale = [1.2, 1, 0.7]
        let deck = ModelEntity(mesh: .generateBox(width: 3.6, height: 0.2, depth: 12), materials: [Bestiary.paint([0.6, 0.45, 0.28])])
        deck.position.y = 1.75
        let stern = ModelEntity(mesh: .generateBox(width: 3.8, height: 1.6, depth: 3, cornerRadius: 0.3), materials: [dark])
        stern.position = [0, 2.5, 5]
        body.children.append(contentsOf: [hull, bow, deck, stern])
        body.addChild(sails)
        body.addChild(furled)
        let cloth = Bestiary.paint(colour)
        for (z, height) in [(-2.5, 11.0), (2.0, 9.0)] as [(Float, Float)] {
            let mast = ModelEntity(mesh: .generateCylinder(height: height, radius: 0.16), materials: [dark])
            mast.position = [0, 1.8 + height / 2, z]
            body.addChild(mast)
            for (i, w) in [(0, 5.4), (1, 4.2)] as [(Int, Float)] {
                let y = 1.8 + height * (i == 0 ? 0.42 : 0.75)
                let sail = ModelEntity(mesh: .generateBox(width: w, height: height * 0.3, depth: 0.12, cornerRadius: 0.05),
                                       materials: [cloth])
                sail.position = [0, y, z + 0.25]
                sails.addChild(sail)
                let roll = ModelEntity(mesh: .generateCylinder(height: w, radius: 0.22), materials: [cloth])
                roll.position = [0, y + height * 0.15, z + 0.2]
                roll.orientation = simd_quatf(angle: .pi / 2, axis: [0, 0, 1])
                furled.addChild(roll)
            }
        }
        let flagpole = Entity()
        let banner = ModelEntity(mesh: .generateBox(width: 0.05, height: 0.8, depth: 1.4), materials: [Bestiary.paint(flag)])
        banner.position = [0, 13.2, -3.2]
        flagpole.addChild(banner)
        body.addChild(flagpole)
        for c in body.children { c.components.set(GroundingShadowComponent(castsShadow: true)) }
        setSails(false)
    }

    func setSails(_ set: Bool) {
        sails.isEnabled = set
        furled.isEnabled = !set
    }

    /// Stand the ship at `position`, turning towards `heading` (yaw, radians) if
    /// given, and rocking on the swell; `spin` turns it on the spot (the whirlpool).
    func update(position: SIMD3<Float>, heading: Float?, spin: Bool, dt: Float) {
        clock += dt
        if spin {
            yaw += dt * 2.2
        } else if let heading {
            yaw += remainder(heading - yaw, 2 * .pi) * min(1, dt * 1.5)
        }
        root.position = position + [0, sin(clock * 1.3) * 0.15 - 0.4, 0]
        root.orientation = simd_quatf(angle: yaw, axis: [0, 1, 0])
            * simd_quatf(angle: sin(clock * 0.9) * 0.04, axis: [0, 0, 1])
            * simd_quatf(angle: sin(clock * 1.1) * 0.025, axis: [1, 0, 0])
    }
}
