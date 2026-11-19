import OdysseyKit
import SwiftUI

/// The report, the party's state, a compass and (on touch screens) a stick.
struct HUD: View {
    let model: GameModel

    var body: some View {
        VStack(alignment: .leading) {
            HStack(alignment: .top) {
                Scroll {
                    if let site = model.siteHere {
                        Text(site.distantName == "VILLAGE" ? "The City" : "The \(site.distantName.capitalized)")
                            .font(.blackletter(24))
                        Text(site.entrance.lowercased()).font(.fell(17).smallCaps())
                        Text("Its secrets await a later chapter.").font(.fell(14, italic: true)).opacity(0.7)
                    } else {
                        Text(model.report.lowercased()).font(.fell(17).smallCaps())
                    }
                }
                .frame(maxWidth: 440, alignment: .leading)
                .animation(.easeInOut(duration: 0.25), value: model.report)
                Spacer()
                Compass(yaw: model.cameraYaw)
            }
            Spacer()
            HStack(alignment: .bottom) {
                #if os(iOS)
                Joystick { model.stick = $0 }
                #else
                Text("WASD or arrows to walk · L to look · drag to turn · pinch or ± to zoom")
                    .font(.fell(13, italic: true))
                    .foregroundStyle(.white.opacity(0.85))
                    .shadow(radius: 2)
                #endif
                Spacer()
                VStack(alignment: .trailing, spacing: 10) {
                    #if os(iOS)
                    Button("Look") { model.look() }
                        .font(.fell(18))
                        .buttonStyle(.borderedProminent)
                        .tint(.ink.opacity(0.8))
                    #endif
                    if let party = model.expedition?.party {
                        Scroll {
                            Grid(alignment: .leading, verticalSpacing: 2) {
                                stat("Men", party.men)
                                stat("Food packs", party.foodPacks)
                                stat("Gold", party.gold)
                            }
                            .font(.fell(16))
                        }
                    }
                }
            }
        }
        .padding(20)
    }

    private func stat(_ label: String, _ value: Int) -> some View {
        GridRow {
            Text(label)
            Text("\(value)").gridColumnAlignment(.trailing).monospacedDigit()
        }
    }
}

/// A parchment panel.
struct Scroll<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 6) { content }
            .foregroundStyle(Color.ink)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color.parchment.opacity(0.92), in: RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color.ink.opacity(0.35), lineWidth: 1))
            .shadow(color: .black.opacity(0.3), radius: 6, y: 3)
    }
}

struct Compass: View {
    let yaw: Float

    var body: some View {
        ZStack {
            Circle().fill(Color.parchment.opacity(0.9))
            Circle().strokeBorder(Color.ink.opacity(0.5), lineWidth: 1.5)
            ForEach(Array(["N", "E", "S", "W"].enumerated()), id: \.offset) { i, letter in
                Text(letter)
                    .font(letter == "N" ? .blackletter(18) : .fell(13))
                    .foregroundStyle(letter == "N" ? Color(red: 0.6, green: 0.1, blue: 0.1) : .ink)
                    .rotationEffect(.degrees(-Double(i) * 90))
                    .offset(y: -24)
                    .rotationEffect(.degrees(Double(i) * 90))
            }
            Image(systemName: "location.north.fill")
                .foregroundStyle(Color.ink.opacity(0.6))
                .font(.system(size: 14))
        }
        .frame(width: 70, height: 70)
        // The world turns under the camera, so north swings the other way.
        .rotationEffect(.radians(Double(yaw)))
        .shadow(color: .black.opacity(0.3), radius: 6, y: 3)
    }
}

/// A thumb stick for touch screens: reports x right, y forward, length <= 1.
struct Joystick: View {
    let onChange: (SIMD2<Float>) -> Void
    @State private var knob: CGSize = .zero
    private let radius: CGFloat = 55

    var body: some View {
        ZStack {
            Circle().fill(.black.opacity(0.25))
            Circle().strokeBorder(.white.opacity(0.5), lineWidth: 2)
            Circle().fill(Color.parchment.opacity(0.9))
                .frame(width: 50, height: 50)
                .offset(knob)
        }
        .frame(width: radius * 2, height: radius * 2)
        .contentShape(Circle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { g in
                    var v = g.translation
                    let len = hypot(v.width, v.height)
                    if len > radius { v = CGSize(width: v.width / len * radius, height: v.height / len * radius) }
                    knob = v
                    onChange([Float(v.width / radius), Float(-v.height / radius)])
                }
                .onEnded { _ in
                    withAnimation(.spring(duration: 0.2)) { knob = .zero }
                    onChange(.zero)
                }
        )
    }
}
