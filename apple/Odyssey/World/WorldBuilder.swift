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
    private let materials: [Paint: PhysicallyBasedMaterial]
    private let seals: [Cell: Entity]
    private var obstacles: [Cell: Entity] = [:]

    init(root: Entity, party: PartyFigure, landscape: Landscape, materials: [Paint: PhysicallyBasedMaterial],
         seals: [Cell: Entity]) {
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
    }
}

/// The parts of the world that can be computed off the main thread.
private struct Blueprint: Sendable {
    let landscape: Landscape
    let mesh: Landscape.MeshData
    let texture: (width: Int, height: Int, pixels: [UInt8])
    let vegetation: Props
    let sites: [(position: SIMD3<Float>, cell: Cell, site: Site, model: Props, seal: Props)]
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
            return Blueprint(landscape: landscape, mesh: landscape.meshData(), texture: landscape.texture(),
                             vegetation: Props.vegetation(island: island, landscape: landscape, clear: clear, seed: seed),
                             sites: sites)
        }.value

        let root = Entity()
        let sky = try await makeSky()
        root.addChild(sky.entity)

        let ground = try await makeGround(blueprint)
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

        let world = World(root: root, party: party, landscape: blueprint.landscape, materials: materials, seals: seals)
        world.sync(expedition)
        return world
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

    private static func makeGround(_ b: Blueprint) async throws -> ModelEntity {
        var d = MeshDescriptor(name: "ground")
        d.positions = MeshBuffers.Positions(b.mesh.positions)
        d.normals = MeshBuffers.Normals(b.mesh.normals)
        d.textureCoordinates = MeshBuffers.TextureCoordinates(b.mesh.uvs)
        d.primitives = .triangles(b.mesh.indices)
        let mesh = try await MeshResource(from: [d])

        let image = try cgImage(width: b.texture.width, height: b.texture.height, pixels: b.texture.pixels)
        let texture = try await TextureResource(image: image, options: .init(semantic: .color))
        var m = PhysicallyBasedMaterial()
        m.baseColor = .init(texture: .init(texture))
        m.roughness = 0.95
        return ModelEntity(mesh: mesh, materials: [m])
    }

    private static func makeWater() throws -> ModelEntity {
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
    private static func makeSky() async throws -> (entity: Entity, environment: EnvironmentResource) {
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
