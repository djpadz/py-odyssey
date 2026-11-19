import OdysseyKit
import simd

/// Converts between the original's map pixels and world metres. North is -z.
enum WorldScale {
    static let metresPerPixel: Float = 2
    static let margin = 60.0                    // map pixels of open sea around the island
    static let mapMargin = 10.0                 // ...and how much of it the inset map shows

    static func world(x: Double, y: Double) -> SIMD2<Float> {
        [Float(x - Island.width / 2) * metresPerPixel, Float(y - Island.height / 2) * metresPerPixel]
    }

    static func map(_ p: SIMD2<Float>) -> (x: Double, y: Double) {
        (Double(p.x / metresPerPixel) + Island.width / 2, Double(p.y / metresPerPixel) + Island.height / 2)
    }
}

/// Smooth value noise, so hills and colours don't repeat on the grid.
struct Noise: Sendable {
    let seed: UInt32

    private func hash(_ x: Int32, _ y: Int32) -> Float {
        var h = UInt32(bitPattern: x) &* 374_761_393 &+ UInt32(bitPattern: y) &* 668_265_263 &+ seed &* 2_246_822_519
        h = (h ^ (h >> 13)) &* 1_274_126_177
        return Float(h ^ (h >> 16)) / Float(UInt32.max)
    }

    func value(_ x: Float, _ y: Float) -> Float {
        let xi = Int32(floor(x)), yi = Int32(floor(y))
        let fx = x - floor(x), fy = y - floor(y)
        let u = fx * fx * (3 - 2 * fx), v = fy * fy * (3 - 2 * fy)
        let a = hash(xi, yi), b = hash(xi + 1, yi), c = hash(xi, yi + 1), d = hash(xi + 1, yi + 1)
        return simd_mix(simd_mix(a, b, u), simd_mix(c, d, u), v)
    }

    /// Fractal noise in 0...1.
    func fbm(_ x: Float, _ y: Float, octaves: Int = 4) -> Float {
        var sum: Float = 0, amp: Float = 0.5, f: Float = 1, norm: Float = 0
        for _ in 0..<octaves {
            sum += amp * value(x * f, y * f)
            norm += amp
            amp *= 0.5
            f *= 2.03
        }
        return sum / norm
    }
}

/// The shape and colouring of the island, sampled on a regular grid of map pixels.
struct Landscape: Sendable {
    static let step = 2.0                       // map pixels between height samples
    static let texelsPerPixel = 2

    let originX = -WorldScale.margin, originY = -WorldScale.margin
    let columns: Int, rows: Int
    /// Per sample: weight of each terrain (jungle, swamp, mountains, ocean) and height in metres.
    private(set) var weights: [SIMD4<Float>]
    private(set) var heights: [Float]
    let noise: Noise

    static let terrainHeight: SIMD4<Float> = [2.6, 0.7, 13, -3]

    init(island: Island, seed: UInt64) {
        noise = Noise(seed: UInt32(truncatingIfNeeded: seed))
        columns = Int((Island.width + 2 * WorldScale.margin) / Landscape.step) + 1
        rows = Int((Island.height + 2 * WorldScale.margin) / Landscape.step) + 1
        weights = []
        heights = []
        weights.reserveCapacity(columns * rows)
        heights.reserveCapacity(columns * rows)
        for r in 0..<rows {
            for c in 0..<columns {
                let x = originX + Double(c) * Landscape.step, y = originY + Double(r) * Landscape.step
                let w = Landscape.blend(island: island, x: x, y: y)
                weights.append(w)
                heights.append(height(x: Float(x), y: Float(y), weights: w))
            }
        }
    }

    /// Gaussian-weighted mix of the terrain of the cells around a point; cells are
    /// 14 x 8 pixels so distances are measured in cells.
    private static func blend(island: Island, x: Double, y: Double) -> SIMD4<Float> {
        let fc = x / Island.cellWidth - 0.5, fr = y / Island.cellHeight - 0.5
        var w = SIMD4<Float>(repeating: 0)
        for dc in -2...2 {
            for dr in -2...2 {
                let c = Int(fc.rounded()) + dc, r = Int(fr.rounded()) + dr
                let d2 = Float((Double(c) - fc) * (Double(c) - fc) + (Double(r) - fr) * (Double(r) - fr))
                let k = exp(-d2 / (2 * 0.45 * 0.45))
                w[island.terrain(Cell(col: c, row: r)).rawValue] += k
            }
        }
        return w / (w.x + w.y + w.z + w.w)
    }

    private func height(x: Float, y: Float, weights w: SIMD4<Float>) -> Float {
        var h = simd_dot(w, Landscape.terrainHeight)
        // Mountains get ridges; everything else a gentle roll.
        let ridge = 1 - abs(noise.fbm(x / 22, y / 22) * 2 - 1)
        h += w.z * w.z * (ridge * 26 + noise.fbm(x / 6, y / 6) * 6)
        h += (noise.fbm(x / 10 + 50, y / 10) - 0.5) * 1.6 * (1 - w.w)
        if h < 0 { h *= 4 }
        return h
    }

    // MARK: Sampling

    private func sample<T>(_ grid: [T], x: Double, y: Double, mix: (T, T, Float) -> T) -> T {
        let fx = min(max((x - originX) / Landscape.step, 0), Double(columns - 1) - 0.001)
        let fy = min(max((y - originY) / Landscape.step, 0), Double(rows - 1) - 0.001)
        let c = Int(fx), r = Int(fy)
        let tx = Float(fx - Double(c)), ty = Float(fy - Double(r))
        let i = r * columns + c
        return mix(mix(grid[i], grid[i + 1], tx), mix(grid[i + columns], grid[i + columns + 1], tx), ty)
    }

    func height(x: Double, y: Double) -> Float {
        sample(heights, x: x, y: y) { simd_mix($0, $1, $2) }
    }

    func weights(x: Double, y: Double) -> SIMD4<Float> {
        sample(weights, x: x, y: y) { simd_mix($0, $1, SIMD4(repeating: $2)) }
    }

    /// Height at a world position (metres).
    func height(world p: SIMD2<Float>) -> Float {
        let m = WorldScale.map(p)
        return height(x: m.x, y: m.y)
    }

    // MARK: Mesh

    struct MeshData: Sendable {
        var positions: [SIMD3<Float>] = []
        var normals: [SIMD3<Float>] = []
        var uvs: [SIMD2<Float>] = []
        var indices: [UInt32] = []
    }

    func meshData() -> MeshData {
        Landscape.mesh(heights, columns: columns, rows: rows, originX: originX, originY: originY, step: Landscape.step)
    }

    /// A grid of heights (rows from the north, `step` map pixels apart from the origin) as a mesh.
    static func mesh(_ heights: [Float], columns: Int, rows: Int, originX: Double, originY: Double,
                     step: Double) -> MeshData {
        var m = MeshData()
        let s = Float(step) * WorldScale.metresPerPixel
        for r in 0..<rows {
            for c in 0..<columns {
                let x = originX + Double(c) * step, y = originY + Double(r) * step
                let p = WorldScale.world(x: x, y: y)
                m.positions.append([p.x, heights[r * columns + c], p.y])
                let hl = heights[r * columns + max(c - 1, 0)], hr = heights[r * columns + min(c + 1, columns - 1)]
                let hu = heights[max(r - 1, 0) * columns + c], hd = heights[min(r + 1, rows - 1) * columns + c]
                m.normals.append(simd_normalize([hl - hr, 2 * s, hu - hd]))
                m.uvs.append([Float(c) / Float(columns - 1), 1 - Float(r) / Float(rows - 1)])
            }
        }
        for r in 0..<(rows - 1) {
            for c in 0..<(columns - 1) {
                let i = UInt32(r * columns + c), below = i + UInt32(columns)
                m.indices += [i, below, i + 1, i + 1, below, below + 1]
            }
        }
        return m
    }

    // MARK: Texture

    /// RGBA8 pixels of the ground colour, one row per texel row from the north.
    func texture() -> (width: Int, height: Int, pixels: [UInt8]) {
        let w = (columns - 1) * Int(Landscape.step) * Landscape.texelsPerPixel
        let h = (rows - 1) * Int(Landscape.step) * Landscape.texelsPerPixel
        var px = [UInt8](repeating: 255, count: w * h * 4)
        let scale = 1 / Double(Landscape.texelsPerPixel)
        for ty in 0..<h {
            for tx in 0..<w {
                let x = originX + Double(tx) * scale, y = originY + Double(ty) * scale
                let colour = groundColour(x: x, y: y)
                let o = (ty * w + tx) * 4
                px[o] = UInt8(min(max(colour.x, 0), 1) * 255)
                px[o + 1] = UInt8(min(max(colour.y, 0), 1) * 255)
                px[o + 2] = UInt8(min(max(colour.z, 0), 1) * 255)
            }
        }
        return (w, h, px)
    }

    private func groundColour(x: Double, y: Double) -> SIMD3<Float> {
        let w = weights(x: x, y: y)
        let h = height(x: x, y: y)
        let fx = Float(x), fy = Float(y)
        let grain = noise.fbm(fx / 1.3, fy / 1.3, octaves: 2)
        let patch = noise.fbm(fx / 9 + 17, fy / 9)

        let jungle = simd_mix(SIMD3<Float>(0.13, 0.33, 0.12), [0.25, 0.45, 0.16], SIMD3(repeating: patch)) * (0.85 + 0.3 * grain)
        let pools = smoothstep(0.55, 0.62, noise.fbm(fx / 4, fy / 4 + 30))
        let swamp = simd_mix(SIMD3<Float>(0.30, 0.33, 0.17), [0.14, 0.22, 0.20], SIMD3(repeating: pools)) * (0.85 + 0.3 * grain)
        let rock = simd_mix(SIMD3<Float>(0.42, 0.39, 0.35), [0.55, 0.52, 0.47], SIMD3(repeating: patch)) * (0.8 + 0.4 * grain)
        let snow = SIMD3<Float>(0.93, 0.94, 0.97) * (0.95 + 0.05 * grain)
        let sand = SIMD3<Float>(0.84, 0.76, 0.55) * (0.92 + 0.16 * grain)
        let seabed = SIMD3<Float>(0.55, 0.52, 0.38)

        let mountain = simd_mix(rock, snow, SIMD3(repeating: smoothstep(21, 25, h + grain * 3)))
        let land = w.x * jungle + w.y * swamp + w.z * mountain
        var c = land / max(w.x + w.y + w.z, 0.001)
        // Beaches where the land meets the sea, and the seabed below.
        let beach = smoothstep(1.6, 0.6, h) * smoothstep(0.0, 0.08, w.w)
        c = simd_mix(c, sand, SIMD3(repeating: beach))
        c = simd_mix(c, seabed, SIMD3(repeating: smoothstep(-0.2, -2.5, h)))
        return c
    }
}

func smoothstep(_ e0: Float, _ e1: Float, _ x: Float) -> Float {
    let t = min(max((x - e0) / (e1 - e0), 0), 1)
    return t * t * (3 - 2 * t)
}
