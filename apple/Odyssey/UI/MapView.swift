import OdysseyKit
import SwiftUI

/// The island from above, north up: the sites the party has seen (as the original
/// drew them on its map once they came in sight), obstacles met, and the party
/// itself. Click or tap to enlarge.
struct MapView: View {
    let model: GameModel
    @State private var large = false

    private struct Marker {
        let at: CGPoint                  // map pixels
        let symbol: String
        let colour: Color
        let faded: Bool
    }

    var body: some View {
        if let image = model.mapImage, let e = model.expedition {
            let m = WorldScale.mapMargin
            let span = CGSize(width: Island.width + 2 * m, height: Island.height + 2 * m)
            let width: CGFloat = large ? 480 : 230
            let markers = Self.markers(e)
            let party = CGPoint(x: e.x, y: e.y)
            let heading = Double(model.partyHeading)
            let scale: CGFloat = large ? 1.4 : 1

            Image(decorative: image, scale: 1)
                .resizable()
                .interpolation(.medium)
                .frame(width: width, height: width * span.height / span.width)
                .overlay {
                    Canvas { ctx, size in
                        func place(_ p: CGPoint) -> CGPoint {
                            CGPoint(x: (p.x + m) / span.width * size.width, y: (p.y + m) / span.height * size.height)
                        }
                        for marker in markers {
                            let p = place(marker.at)
                            let r = 7 * scale
                            ctx.opacity = marker.faded ? 0.5 : 1
                            ctx.fill(Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: 2 * r, height: 2 * r)),
                                     with: .color(Color.parchment.opacity(0.9)))
                            var symbol = ctx.resolve(Image(systemName: marker.symbol))
                            symbol.shading = .color(marker.colour)
                            ctx.draw(symbol, in: CGRect(x: p.x - r * 0.65, y: p.y - r * 0.65, width: r * 1.3, height: r * 1.3))
                        }
                        ctx.opacity = 1
                        // The party: an arrowhead pointing the way it faces.
                        let p = place(party)
                        let s = 7 * scale
                        var arrow = Path()
                        arrow.move(to: CGPoint(x: 0, y: -s))
                        arrow.addLine(to: CGPoint(x: s * 0.7, y: s * 0.8))
                        arrow.addLine(to: CGPoint(x: 0, y: s * 0.35))
                        arrow.addLine(to: CGPoint(x: -s * 0.7, y: s * 0.8))
                        arrow.closeSubpath()
                        let turned = arrow.applying(CGAffineTransform(rotationAngle: heading))
                            .applying(CGAffineTransform(translationX: p.x, y: p.y))
                        ctx.fill(turned, with: .color(Color(red: 0.75, green: 0.1, blue: 0.08)))
                        ctx.stroke(turned, with: .color(.white), lineWidth: 1.2)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color.ink.opacity(0.5), lineWidth: 1.5))
                .shadow(color: .black.opacity(0.3), radius: 6, y: 3)
                .onTapGesture { large.toggle() }
                .animation(.easeInOut(duration: 0.25), value: large)
                .accessibilityLabel("Map of the island")
        }
    }

    private static func markers(_ e: Expedition) -> [Marker] {
        var markers: [Marker] = []
        for cell in e.seen {
            let c = cell.center
            if let site = e.island.site(cell) {
                markers.append(Marker(at: CGPoint(x: c.x, y: c.y), symbol: symbol(site), colour: .ink,
                                      faded: e.island.isSealed(cell)))
            } else if e.island.obstacles[cell] != nil {
                markers.append(Marker(at: CGPoint(x: c.x, y: c.y), symbol: "xmark",
                                      colour: Color(red: 0.6, green: 0.1, blue: 0.08), faded: false))
            }
        }
        return markers
    }

    private static func symbol(_ site: Site) -> String {
        switch site {
        case .temple: "building.columns.fill"
        case .ruin: "square.dashed"
        case .castle: "flag.fill"
        case .tomb: "triangle.fill"
        case .hut: "house.fill"
        case .city: "building.2.fill"
        }
    }
}
