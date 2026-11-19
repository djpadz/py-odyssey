import RealityKit
import simd

/// Accumulates flat-shaded low-poly shapes into one mesh, so a whole forest is a
/// single draw call instead of thousands of entities.
struct MeshBuilder {
    private(set) var positions: [SIMD3<Float>] = []
    private(set) var normals: [SIMD3<Float>] = []
    private(set) var indices: [UInt32] = []

    var isEmpty: Bool { indices.isEmpty }

    mutating func addTriangle(_ a: SIMD3<Float>, _ b: SIMD3<Float>, _ c: SIMD3<Float>) {
        let n = simd_normalize(simd_cross(b - a, c - a))
        guard n.x.isFinite else { return }
        let base = UInt32(positions.count)
        positions += [a, b, c]
        normals += [n, n, n]
        indices += [base, base + 1, base + 2]
    }

    mutating func addQuad(_ a: SIMD3<Float>, _ b: SIMD3<Float>, _ c: SIMD3<Float>, _ d: SIMD3<Float>) {
        addTriangle(a, b, c)
        addTriangle(a, c, d)
    }

    /// A prism or (with `topRadius` 0) a cone standing on `base`, optionally tilted by `rotation`.
    mutating func addFrustum(base: SIMD3<Float>, bottomRadius: Float, topRadius: Float, height: Float,
                             sides: Int, yaw: Float = 0, rotation: simd_quatf = simd_quatf(angle: 0, axis: [0, 1, 0]),
                             caps: Bool = true) {
        func ring(_ r: Float, _ y: Float) -> [SIMD3<Float>] {
            (0..<sides).map { i in
                let a = yaw + Float(i) / Float(sides) * 2 * .pi
                return base + rotation.act([r * cos(a), y, -r * sin(a)])
            }
        }
        let bottom = ring(bottomRadius, 0), top = ring(topRadius, height)
        let topCenter = base + rotation.act([0, height, 0])
        for i in 0..<sides {
            let j = (i + 1) % sides
            if topRadius > 0 {
                addQuad(bottom[i], bottom[j], top[j], top[i])
                if caps { addTriangle(topCenter, top[i], top[j]) }
            } else {
                addTriangle(bottom[i], bottom[j], topCenter)
            }
            if caps { addTriangle(base, bottom[j], bottom[i]) }
        }
    }

    /// Two cones base to base: a low-poly blob for foliage and boulders.
    mutating func addSpindle(center: SIMD3<Float>, radius: Float, up: Float, down: Float, sides: Int, yaw: Float = 0) {
        addFrustum(base: center, bottomRadius: radius, topRadius: 0, height: up, sides: sides, yaw: yaw, caps: false)
        addFrustum(base: center, bottomRadius: radius, topRadius: 0, height: down, sides: sides, yaw: yaw,
                   rotation: simd_quatf(angle: .pi, axis: [1, 0, 0]), caps: false)
    }

    /// A box sitting on `base` (the centre of its bottom face).
    mutating func addBox(base: SIMD3<Float>, size: SIMD3<Float>, yaw: Float = 0) {
        let r = simd_quatf(angle: yaw, axis: [0, 1, 0])
        let h = size / 2
        func p(_ x: Float, _ y: Float, _ z: Float) -> SIMD3<Float> { base + r.act([x * h.x, y * size.y, z * h.z]) }
        addQuad(p(-1, 1, -1), p(-1, 1, 1), p(1, 1, 1), p(1, 1, -1))         // top
        addQuad(p(-1, 0, 1), p(-1, 0, -1), p(1, 0, -1), p(1, 0, 1))         // bottom
        addQuad(p(-1, 0, 1), p(1, 0, 1), p(1, 1, 1), p(-1, 1, 1))           // south
        addQuad(p(1, 0, -1), p(-1, 0, -1), p(-1, 1, -1), p(1, 1, -1))       // north
        addQuad(p(1, 0, 1), p(1, 0, -1), p(1, 1, -1), p(1, 1, 1))           // east
        addQuad(p(-1, 0, -1), p(-1, 0, 1), p(-1, 1, 1), p(-1, 1, -1))       // west
    }

    /// A gabled roof: a triangular prism along the box's x axis.
    mutating func addGable(base: SIMD3<Float>, size: SIMD3<Float>, yaw: Float = 0) {
        let r = simd_quatf(angle: yaw, axis: [0, 1, 0])
        let h = size / 2
        func p(_ x: Float, _ y: Float, _ z: Float) -> SIMD3<Float> { base + r.act([x * h.x, y * size.y, z * h.z]) }
        addQuad(p(-1, 0, 1), p(1, 0, 1), p(1, 1, 0), p(-1, 1, 0))
        addQuad(p(1, 0, -1), p(-1, 0, -1), p(-1, 1, 0), p(1, 1, 0))
        addTriangle(p(1, 0, 1), p(1, 0, -1), p(1, 1, 0))
        addTriangle(p(-1, 0, -1), p(-1, 0, 1), p(-1, 1, 0))
    }

    @MainActor func mesh() throws -> MeshResource {
        var d = MeshDescriptor()
        d.positions = MeshBuffers.Positions(positions)
        d.normals = MeshBuffers.Normals(normals)
        d.primitives = .triangles(indices)
        return try MeshResource.generate(from: [d])
    }

    @MainActor func entity(_ material: any Material) throws -> ModelEntity {
        ModelEntity(mesh: try mesh(), materials: [material])
    }
}
