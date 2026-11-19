import OdysseyKit
import simd

/// The colours the props are painted in; each becomes one material.
enum Paint: CaseIterable, Sendable {
    case trunk, leaves, leavesDark, palm, reed, rock, stone, paleStone, darkStone, tile, wood, thatch, gold

    var colour: SIMD3<Float> {
        switch self {
        case .trunk: [0.32, 0.22, 0.14]
        case .leaves: [0.16, 0.42, 0.14]
        case .leavesDark: [0.08, 0.28, 0.12]
        case .palm: [0.30, 0.50, 0.16]
        case .reed: [0.40, 0.42, 0.20]
        case .rock: [0.45, 0.43, 0.40]
        case .stone: [0.66, 0.62, 0.55]
        case .paleStone: [0.88, 0.85, 0.78]
        case .darkStone: [0.33, 0.32, 0.31]
        case .tile: [0.66, 0.27, 0.16]
        case .wood: [0.45, 0.31, 0.18]
        case .thatch: [0.72, 0.60, 0.33]
        case .gold: [0.95, 0.75, 0.30]
        }
    }

    var roughness: Float { self == .gold ? 0.3 : 0.9 }
    var metallic: Float { self == .gold ? 1 : 0 }
}

/// Meshes for everything standing on the island, grouped by paint.
struct Props: Sendable {
    var builders: [Paint: MeshBuilder] = [:]

    subscript(_ p: Paint) -> MeshBuilder {
        get { builders[p] ?? MeshBuilder() }
        set { builders[p] = newValue }
    }

    /// Trees, reeds and boulders, kept clear of the sites and the party's start.
    static func vegetation(island: Island, landscape: Landscape, clear: [SIMD2<Float>], seed: UInt64) -> Props {
        var props = Props()
        var rng = SeededRandom(seed: seed ^ 0x7EE5)
        func r(_ lo: Float, _ hi: Float) -> Float { Float.random(in: lo...hi, using: &rng) }

        for cell in island.allCells {
            let terrain = island.terrain(cell)
            let count = switch terrain {
            case .jungle: 9
            case .swamp: 7
            case .mountains: 3
            case .ocean: 0
            }
            for _ in 0..<count {
                let x = (Double(cell.col) + Double(r(0, 1))) * Island.cellWidth
                let y = (Double(cell.row) + Double(r(0, 1))) * Island.cellHeight
                let p = WorldScale.world(x: x, y: y)
                if clear.contains(where: { simd_distance($0, p) < 15 }) { continue }
                let w = landscape.weights(x: x, y: y)
                let h = landscape.height(x: x, y: y)
                if h < 1.0 { continue }
                let base = SIMD3<Float>(p.x, h - 0.2, p.y)
                if w.x > 0.55 {
                    if h < 2.4 && w.w > 0.03 {
                        props.addPalm(base, rng: &rng)
                    } else {
                        props.addBroadleaf(base, rng: &rng)
                    }
                } else if w.y > 0.5 {
                    if r(0, 1) < 0.25 {
                        props.addDeadTree(base, rng: &rng)
                    } else {
                        props.addReeds(base, rng: &rng)
                    }
                } else if w.z > 0.5 {
                    if h < 16 && r(0, 1) < 0.6 {
                        props.addPine(base, rng: &rng)
                    } else {
                        props[.rock].addSpindle(center: base, radius: r(1.2, 3), up: r(1.5, 3.5), down: 1,
                                                sides: 5, yaw: r(0, 6))
                    }
                }
            }
        }
        return props
    }

    private mutating func addBroadleaf(_ base: SIMD3<Float>, rng: inout SeededRandom) {
        let height = Float.random(in: 4...7, using: &rng)
        self[.trunk].addFrustum(base: base, bottomRadius: 0.35, topRadius: 0.22, height: height, sides: 5)
        let paint: Paint = Bool.random(using: &rng) ? .leaves : .leavesDark
        let radius = Float.random(in: 2.2...3.4, using: &rng)
        self[paint].addSpindle(center: base + [0, height, 0], radius: radius, up: radius * 0.9,
                               down: radius * 0.5, sides: 7, yaw: .random(in: 0...6, using: &rng))
    }

    private mutating func addPalm(_ base: SIMD3<Float>, rng: inout SeededRandom) {
        let height = Float.random(in: 5...8, using: &rng)
        let lean = simd_quatf(angle: .random(in: 0.05...0.3, using: &rng),
                              axis: simd_normalize([.random(in: -1...1, using: &rng), 0, .random(in: -1...1, using: &rng)]))
        self[.trunk].addFrustum(base: base, bottomRadius: 0.3, topRadius: 0.18, height: height, sides: 5, rotation: lean)
        let top = base + lean.act([0, height, 0])
        let fronds = 6
        for i in 0..<fronds {
            let a = Float(i) / Float(fronds) * 2 * .pi
            let dir = SIMD3<Float>(cos(a), 0, sin(a))
            let side = SIMD3<Float>(-sin(a), 0, cos(a)) * 0.6
            let tip = top + dir * 3.4 + [0, -1.4, 0]
            let mid = top + dir * 1.7 + [0, 0.4, 0]
            self[.palm].addTriangle(top, mid + side, mid - side)
            self[.palm].addTriangle(mid - side, mid + side, tip)
            self[.palm].addTriangle(top, mid - side, mid + side)        // underside
            self[.palm].addTriangle(mid + side, mid - side, tip)
        }
    }

    private mutating func addPine(_ base: SIMD3<Float>, rng: inout SeededRandom) {
        let height = Float.random(in: 5...9, using: &rng)
        self[.trunk].addFrustum(base: base, bottomRadius: 0.3, topRadius: 0.1, height: height * 0.4, sides: 5)
        for tier in 0..<3 {
            let t = Float(tier)
            self[.leavesDark].addFrustum(base: base + [0, height * (0.25 + 0.22 * t), 0],
                                         bottomRadius: 2.2 - 0.55 * t, topRadius: 0, height: height * 0.4, sides: 7,
                                         yaw: t)
        }
    }

    private mutating func addReeds(_ base: SIMD3<Float>, rng: inout SeededRandom) {
        for _ in 0..<5 {
            let off = SIMD3<Float>(.random(in: -1.5...1.5, using: &rng), 0, .random(in: -1.5...1.5, using: &rng))
            self[.reed].addFrustum(base: base + off, bottomRadius: 0.12, topRadius: 0, height: .random(in: 1.2...2.4, using: &rng),
                                   sides: 3, yaw: .random(in: 0...6, using: &rng),
                                   rotation: simd_quatf(angle: .random(in: -0.2...0.2, using: &rng), axis: [1, 0, 0]))
        }
    }

    private mutating func addDeadTree(_ base: SIMD3<Float>, rng: inout SeededRandom) {
        let height = Float.random(in: 3...5.5, using: &rng)
        self[.trunk].addFrustum(base: base, bottomRadius: 0.3, topRadius: 0.1, height: height, sides: 5)
        for _ in 0..<3 {
            let a = Float.random(in: 0...(2 * .pi), using: &rng)
            let at = base + [0, height * .random(in: 0.5...0.85, using: &rng), 0]
            self[.trunk].addFrustum(base: at, bottomRadius: 0.1, topRadius: 0.02, height: 1.8, sides: 4,
                                    rotation: simd_quatf(angle: 0.9, axis: [sin(a), 0, cos(a)]))
        }
    }
}

// MARK: - Sites

extension Props {
    /// A model of a site, centred on the origin at ground level, about one cell (28 x 16 m) across.
    static func model(of site: Site, seed: Int) -> Props {
        var p = Props()
        var rng = SeededRandom(seed: UInt64(seed))
        // Every site stands on a plinth that reaches down into sloping ground.
        switch site {
        case .temple:
            p[.paleStone].addBox(base: [0, -3, 0], size: [17, 3.4, 12])
            p[.paleStone].addBox(base: [0, 0.4, 0], size: [15, 0.6, 10])
            p[.paleStone].addBox(base: [0, 1.0, 0], size: [13, 0.6, 8.5])
            for i in 0..<6 {
                for z: Float in [-3.4, 3.4] {
                    p[.paleStone].addFrustum(base: [-5.5 + Float(i) * 2.2, 1.6, z], bottomRadius: 0.5, topRadius: 0.42,
                                             height: 5.5, sides: 8)
                }
            }
            p[.paleStone].addBox(base: [0, 7.1, 0], size: [13.4, 0.9, 8.6])
            p[.tile].addGable(base: [0, 8, 0], size: [13.4, 2.4, 8.6])
            p[.darkStone].addBox(base: [0, 1.6, 0], size: [8, 5.5, 5])
            p[.gold].addBox(base: [0, 1.6, 2.52], size: [2.4, 3.8, 0.1])     // the bronze doors
        case .ruin:
            p[.stone].addBox(base: [0, -3, 0], size: [16, 3.4, 11])
            for i in 0..<5 {
                for z: Float in [-3.5, 3.5] {
                    let h = Float.random(in: 0.6...4.5, using: &rng)
                    p[.stone].addFrustum(base: [-5.6 + Float(i) * 2.8, 0.4, z], bottomRadius: 0.5, topRadius: 0.45,
                                         height: h, sides: 7, yaw: .random(in: 0...1, using: &rng))
                }
            }
            p[.stone].addFrustum(base: [2, 0.9, 0], bottomRadius: 0.5, topRadius: 0.45, height: 6, sides: 7,
                                 rotation: simd_quatf(angle: .pi / 2, axis: [0.3, 0, 1]))
            for _ in 0..<7 {
                p[.darkStone].addBox(base: [.random(in: -7...7, using: &rng), 0.3, .random(in: -5...5, using: &rng)],
                                     size: [.random(in: 0.8...1.6, using: &rng), 0.8, .random(in: 0.8...1.6, using: &rng)],
                                     yaw: .random(in: 0...3, using: &rng))
            }
            p[.leaves].addSpindle(center: [-4, 0.4, 1], radius: 1.4, up: 1.3, down: 0.3, sides: 6)
        case .castle:
            p[.stone].addBox(base: [0, -3, 0], size: [20, 3.4, 15])
            for (x, z, w, d) in [(0, -6.5, 16, 1.2), (0, 6.5, 16, 1.2), (-8, 0, 1.2, 13), (8, 0, 1.2, 13)] as [(Float, Float, Float, Float)] {
                p[.stone].addBox(base: [x, 0.4, z], size: [w, 5, d])
                // Crenellations.
                let n = Int(max(w, d) / 1.6)
                for i in 0..<n {
                    let t = (Float(i) + 0.5) / Float(n) - 0.5
                    p[.stone].addBox(base: [x + (w > d ? t * w : 0), 5.4, z + (w > d ? 0 : t * d)],
                                     size: [w > d ? 0.8 : w, 0.8, w > d ? d : 0.8])
                }
            }
            for x: Float in [-8, 8] {
                for z: Float in [-6.5, 6.5] {
                    p[.stone].addFrustum(base: [x, 0.4, z], bottomRadius: 1.9, topRadius: 1.7, height: 7.5, sides: 10)
                    p[.tile].addFrustum(base: [x, 7.9, z], bottomRadius: 2.2, topRadius: 0, height: 3.4, sides: 10)
                }
            }
            p[.darkStone].addBox(base: [0, 0.4, 0], size: [6, 10, 5])
            p[.tile].addFrustum(base: [0, 10.4, 0], bottomRadius: 4.2, topRadius: 0, height: 3, sides: 4, yaw: .pi / 4)
            p[.wood].addBox(base: [0, 0.4, 7.15], size: [2.4, 3.2, 0.2])
        case .tomb:
            p[.stone].addBox(base: [0, -3, 0], size: [15, 3.4, 13])
            p[.stone].addFrustum(base: [0, 0.4, 0], bottomRadius: 8.5, topRadius: 1.2, height: 9, sides: 4, yaw: .pi / 4)
            p[.darkStone].addBox(base: [0, 0.4, 5.2], size: [3, 3.6, 1.6])
            for x: Float in [-3, 3] {
                p[.paleStone].addBox(base: [x, 0.4, 7.2], size: [1, 2.6, 1])
            }
        case .hut:
            p[.wood].addFrustum(base: [0, -1.5, 0], bottomRadius: 3.2, topRadius: 3.2, height: 4.3, sides: 9)
            p[.thatch].addFrustum(base: [0, 2.6, 0], bottomRadius: 4.2, topRadius: 0, height: 3.6, sides: 9,
                                  rotation: simd_quatf(angle: 0.08, axis: [1, 0, 0.4]))
            p[.darkStone].addBox(base: [0, 0, 3.15], size: [1.3, 2.1, 0.2])
            p[.wood].addFrustum(base: [3.8, 0, 2], bottomRadius: 0.15, topRadius: 0.15, height: 3.2, sides: 4,
                                rotation: simd_quatf(angle: 0.2, axis: [0, 0, 1]))
        case .city:
            p[.stone].addBox(base: [0, -3, 0], size: [27, 3.4, 18])
            // Walls.
            for (x, z, w, d) in [(0, -8.5, 26, 1), (-12.5, 0, 1, 17), (12.5, 0, 1, 17),
                                 (-7.5, 8.5, 11, 1), (7.5, 8.5, 11, 1)] as [(Float, Float, Float, Float)] {
                p[.stone].addBox(base: [x, 0.4, z], size: [w, 3.6, d])
            }
            for x: Float in [-2.6, 2.6] {
                p[.stone].addFrustum(base: [x, 0.4, 8.5], bottomRadius: 1.3, topRadius: 1.2, height: 5.5, sides: 8)
                p[.tile].addFrustum(base: [x, 5.9, 8.5], bottomRadius: 1.6, topRadius: 0, height: 2.2, sides: 8)
            }
            // Houses on a loose grid, and the market square in the middle.
            for gx in -3...3 {
                for gz in -2...2 where !(abs(gx) <= 1 && abs(gz) <= 1) && !(gx == 0 && gz == 2) {
                    let size = SIMD3<Float>(.random(in: 2.4...3.2, using: &rng), .random(in: 2.2...4.2, using: &rng),
                                            .random(in: 2.2...2.8, using: &rng))
                    let base = SIMD3<Float>(Float(gx) * 3.3, 0.4, Float(gz) * 3.2) + [.random(in: -0.3...0.3, using: &rng), 0, 0]
                    p[.paleStone].addBox(base: base, size: size)
                    p[.tile].addGable(base: base + [0, size.y, 0], size: [size.x + 0.3, 1.3, size.z + 0.3])
                }
            }
            p[.darkStone].addBox(base: [0, 0.4, 0], size: [5, 0.15, 5])
            p[.wood].addBox(base: [-1, 0.5, -1], size: [1.6, 1.0, 1.0])
            p[.thatch].addGable(base: [-1, 1.5, -1], size: [2, 0.6, 1.4])
            p[.stone].addFrustum(base: [5, 0.4, -5], bottomRadius: 1.4, topRadius: 1.1, height: 9, sides: 8)
            p[.gold].addFrustum(base: [5, 9.4, -5], bottomRadius: 1.4, topRadius: 0, height: 2.5, sides: 8)
        }
        return p
    }
}
