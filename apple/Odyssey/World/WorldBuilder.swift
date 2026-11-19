import CoreGraphics
import Foundation
import OdysseyKit
import RealityKit
import simd

/// Everything the scene needs, built for one island, and the parts that change as
/// the quest goes on: sealed sites, obstacles, and whoever the party is dealing with.
@MainActor
final class World {
    let root: Entity
    let party: PartyFigure
    let landscape: Landscape
    let cast: Cast
    /// The island from above, for the map: map pixels -`WorldScale.mapMargin` to the far edge
    /// plus the margin, a texel per pixel.
    let map: CGImage?
    private let materials: [Paint: PhysicallyBasedMaterial]
    private let seals: [Cell: Entity]
    private var obstacles: [Cell: Entity] = [:]
    /// What lies about, keyed by cell, with the item and quantity it shows.
    private var lying: [Cell: (key: Int, entity: Entity)] = [:]

    init(root: Entity, party: PartyFigure, landscape: Landscape, materials: [Paint: PhysicallyBasedMaterial],
         seals: [Cell: Entity], map: CGImage?) {
        self.map = map
        self.root = root
        self.party = party
        self.landscape = landscape
        self.materials = materials
        self.seals = seals
        cast = Cast(landscape: landscape, light: root)
        root.addChild(cast.root)
    }

    /// Bring the scenery into line with the quest.
    func sync(_ expedition: Expedition) {
        for (cell, seal) in seals where !seal.isEnabled && expedition.island.isSealed(cell) {
            seal.isEnabled = true
        }
        let barred = expedition.island.obstacles
        for (cell, entity) in obstacles where barred[cell] == nil {
            entity.removeFromParent()
            obstacles[cell] = nil
        }
        for (cell, obstacle) in barred where obstacles[cell] == nil {
            let props = Props.obstacle(obstacle.kind, in: cell, landscape: landscape,
                                       seed: Int(expedition.seed) &+ cell.col * 31 &+ cell.row)
            guard let e = try? WorldBuilder.entity(for: props, materials: materials) else { continue }
            e.name = "obstacle-\(cell.col)-\(cell.row)"
            WorldBuilder.applyLightReceiver(e, light: root)
            root.addChild(e)
            obstacles[cell] = e
        }
        // Things lying about: a sack at the middle of the cell.
        var now: [Cell: Int] = [:]
        for (cell, item, n) in expedition.island.lyingAbout { now[cell] = item.id * 1000 + n }
        for (cell, marker) in lying where now[cell] != marker.key {
            marker.entity.removeFromParent()
            lying[cell] = nil
        }
        for (cell, key) in now where lying[cell] == nil {
            let c = cell.center
            let p = WorldScale.world(x: c.x, y: c.y)
            let sack = Bestiary.sack()
            sack.position = [p.x, max(landscape.height(world: p), 0.1), p.y]
            WorldBuilder.applyLightReceiver(sack, light: root)
            root.addChild(sack)
            lying[cell] = (key, sack)
        }
    }
}

/// The parts of the world that can be computed off the main thread.
private struct Blueprint: Sendable {
    let landscape: Landscape
    let mesh: Landscape.MeshData
    let texture: (width: Int, height: Int, pixels: [UInt8])
    let vegetation: Props
    let sites: [(position: SIMD3<Float>, cell: Cell, site: Site, model: Props, seal: Props)]
    let map: (width: Int, height: Int, pixels: [UInt8])
}

@MainActor
enum WorldBuilder {
    static func build(_ expedition: Expedition) async throws -> World {
        let island = expedition.island, seed = expedition.seed
        let start = WorldScale.world(x: expedition.x, y: expedition.y)
        let blueprint = await Task.detached(priority: .userInitiated) {
            let landscape = Landscape(island: island, seed: seed)
            let sites = island.sites.enumerated().map { i, entry in
                let c = entry.cell.center
                let p = WorldScale.world(x: c.x, y: c.y)
                // Stand the site on the lowest ground under its middle so it never floats.
                let h = [(-8.0, 0.0), (8, 0), (0, -5), (0, 5), (0, 0)].map {
                    landscape.height(world: p + [Float($0.0), Float($0.1)])
                }.min()!
                return (position: SIMD3<Float>(p.x, max(h, 0.6), p.y), cell: entry.cell, site: entry.site,
                        model: Props.model(of: entry.site, seed: Int(seed) &+ i),
                        seal: Props.seal(of: entry.site, seed: Int(seed) &+ i))
            }
            let clear = sites.map { SIMD2<Float>($0.position.x, $0.position.z) } + [start]
            let texture = landscape.texture()
            return Blueprint(landscape: landscape, mesh: landscape.meshData(), texture: texture,
                             vegetation: Props.vegetation(island: island, landscape: landscape, clear: clear, seed: seed),
                             sites: sites, map: mapPixels(texture, landscape: landscape))
        }.value

        let root = Entity()
        let sky = try await makeSky()
        root.addChild(sky.entity)

        let ground = try await makeGround(mesh: blueprint.mesh, texture: blueprint.texture)
        root.addChild(ground)
        root.addChild(try makeWater())

        let materials = Dictionary(uniqueKeysWithValues: Paint.allCases.map { ($0, material($0)) })
        let vegetation = try entity(for: blueprint.vegetation, materials: materials)
        vegetation.name = "vegetation"
        root.addChild(vegetation)
        var seals: [Cell: Entity] = [:]
        for site in blueprint.sites {
            let e = try entity(for: site.model, materials: materials)
            e.name = "site-\(site.site)"
            e.position = site.position
            let seal = try entity(for: site.seal, materials: materials)
            seal.isEnabled = false
            e.addChild(seal)
            seals[site.cell] = seal
            root.addChild(e)
        }

        let sun = DirectionalLight()
        sun.light.intensity = 3200
        sun.light.color = .init(red: 1, green: 0.95, blue: 0.85, alpha: 1)
        sun.shadow = DirectionalLightComponent.Shadow(maximumDistance: 140, depthBias: 2)
        sun.look(at: .zero, from: [180, 260, 120], relativeTo: nil)
        root.addChild(sun)

        let party = PartyFigure()
        root.addChild(party.root)

        // Light everything with the sky.
        root.components.set(ImageBasedLightComponent(source: .single(sky.environment), intensityExponent: 0.6))
        applyLightReceiver(root, light: root)

        let map = try? cgImage(width: blueprint.map.width, height: blueprint.map.height, pixels: blueprint.map.pixels)
        let world = World(root: root, party: party, landscape: blueprint.landscape, materials: materials, seals: seals,
                          map: map)
        world.sync(expedition)
        return world
    }

    /// The ground texture cut down to the island and its margin, with the sea painted
    /// in, deepening offshore.
    nonisolated static func mapPixels(_ t: (width: Int, height: Int, pixels: [UInt8]),
                                      landscape: Landscape) -> (width: Int, height: Int, pixels: [UInt8]) {
        let m = WorldScale.mapMargin
        let w = Int(Island.width + 2 * m), h = Int(Island.height + 2 * m)
        let per = Landscape.texelsPerPixel
        var px = [UInt8](repeating: 255, count: w * h * 4)
        let shallow = SIMD3<Float>(0.28, 0.55, 0.62), deep = SIMD3<Float>(0.07, 0.24, 0.40)
        for y in 0..<h {
            for x in 0..<w {
                let mx = Double(x) - m + 0.5, my = Double(y) - m + 0.5
                let tx = Int((mx - landscape.originX) * Double(per)), ty = Int((my - landscape.originY) * Double(per))
                let ti = (min(max(ty, 0), t.height - 1) * t.width + min(max(tx, 0), t.width - 1)) * 4
                var c = SIMD3<Float>(Float(t.pixels[ti]), Float(t.pixels[ti + 1]), Float(t.pixels[ti + 2])) / 255
                let ground = landscape.height(x: mx, y: my)
                if ground < 0 {
                    let sea = simd_mix(shallow, deep, SIMD3(repeating: smoothstep(0, 3, -ground)))
                    c = simd_mix(c, sea, SIMD3(repeating: smoothstep(0, 0.5, -ground)))
                }
                let o = (y * w + x) * 4
                px[o] = UInt8(c.x * 255)
                px[o + 1] = UInt8(c.y * 255)
                px[o + 2] = UInt8(c.z * 255)
            }
        }
        return (w, h, px)
    }

    static func applyLightReceiver(_ e: Entity, light: Entity) {
        if e.components.has(ModelComponent.self) {
            e.components.set(ImageBasedLightReceiverComponent(imageBasedLight: light))
        }
        for child in e.children { applyLightReceiver(child, light: light) }
    }

    static func material(_ paint: Paint) -> PhysicallyBasedMaterial {
        var m = PhysicallyBasedMaterial()
        let c = paint.colour
        m.baseColor = .init(tint: .init(red: CGFloat(c.x), green: CGFloat(c.y), blue: CGFloat(c.z), alpha: 1))
        m.roughness = .init(floatLiteral: paint.roughness)
        m.metallic = .init(floatLiteral: paint.metallic)
        m.faceCulling = paint == .palm || paint == .abyss ? .none : .back
        return m
    }

    static func entity(for props: Props, materials: [Paint: PhysicallyBasedMaterial]) throws -> Entity {
        let e = Entity()
        for (paint, builder) in props.builders where !builder.isEmpty {
            let model = try builder.entity(materials[paint]!)
            model.components.set(GroundingShadowComponent(castsShadow: true))
            e.addChild(model)
        }
        return e
    }

    /// The ground: a heightfield mesh wearing its painted texture.
    static func makeGround(mesh m: Landscape.MeshData, texture t: (width: Int, height: Int, pixels: [UInt8])) async throws
        -> ModelEntity {
        var d = MeshDescriptor(name: "ground")
        d.positions = MeshBuffers.Positions(m.positions)
        d.normals = MeshBuffers.Normals(m.normals)
        d.textureCoordinates = MeshBuffers.TextureCoordinates(m.uvs)
        d.primitives = .triangles(m.indices)
        let mesh = try await MeshResource(from: [d])

        let image = try cgImage(width: t.width, height: t.height, pixels: t.pixels)
        let texture = try await TextureResource(image: image, options: .init(semantic: .color))
        var m = PhysicallyBasedMaterial()
        m.baseColor = .init(texture: .init(texture))
        m.roughness = 0.95
        return ModelEntity(mesh: mesh, materials: [m])
    }

    static func makeWater() throws -> ModelEntity {
        var m = PhysicallyBasedMaterial()
        m.baseColor = .init(tint: .init(red: 0.08, green: 0.32, blue: 0.45, alpha: 1))
        m.roughness = 0.12
        m.specular = 0.8
        m.blending = .transparent(opacity: 0.82)
        let water = ModelEntity(mesh: .generatePlane(width: 4000, depth: 4000), materials: [m])
        water.position.y = 0.05
        return water
    }

    /// A gradient sky dome, which also lights the scene.
    static func makeSky() async throws -> (entity: Entity, environment: EnvironmentResource) {
        let w = 64, h = 32
        var px = [UInt8](repeating: 255, count: w * h * 4)
        for y in 0..<h {
            let t = Float(y) / Float(h - 1)                  // 0 = zenith, 1 = nadir
            let zenith = SIMD3<Float>(0.22, 0.45, 0.80), horizon = SIMD3<Float>(0.80, 0.88, 0.95)
            let below = SIMD3<Float>(0.18, 0.30, 0.36)
            let c = t < 0.5 ? simd_mix(zenith, horizon, SIMD3(repeating: pow(t * 2, 1.6)))
                            : simd_mix(horizon, below, SIMD3(repeating: min((t - 0.5) * 6, 1)))
            for x in 0..<w {
                let o = (y * w + x) * 4
                px[o] = UInt8(c.x * 255)
                px[o + 1] = UInt8(c.y * 255)
                px[o + 2] = UInt8(c.z * 255)
            }
        }
        let image = try cgImage(width: w, height: h, pixels: px)
        let environment = try await EnvironmentResource(equirectangular: image)
        let texture = try await TextureResource(image: image, options: .init(semantic: .color))
        var m = UnlitMaterial()
        m.color = .init(texture: .init(texture))
        m.faceCulling = .front
        let dome = ModelEntity(mesh: .generateSphere(radius: 1800), materials: [m])
        return (dome, environment)
    }

    struct ImageError: Error {}

    static func cgImage(width: Int, height: Int, pixels: [UInt8]) throws -> CGImage {
        let data = Data(pixels) as CFData
        guard let provider = CGDataProvider(data: data),
              let image = CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
                                  bytesPerRow: width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
                                  provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
        else { throw ImageError() }
        return image
    }
}
