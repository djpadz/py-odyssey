import RealityKit
import SwiftUI

struct ContentView: View {
    let model: GameModel

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            switch model.phase {
            case .playing:
                IslandView(model: model)
                    .ignoresSafeArea()
                HUD(model: model)
            case let .lost(words):
                LostView(words: words) { model.backToTitle() }
            case .title, .loading:
                TitleView(model: model)
            }
        }
        .animation(.easeInOut(duration: 0.6), value: model.phase)
        .onAppear {
            // `--quest <seed>` skips the title and replays that island.
            let args = ProcessInfo.processInfo.arguments
            if let i = args.firstIndex(of: "--quest"), i + 1 < args.count, let seed = UInt64(args[i + 1]),
               model.phase == .title {
                model.newQuest(seed: seed)
            }
        }
    }
}

/// The 3D island, with keyboard walking and drag-to-orbit.
struct IslandView: View {
    let model: GameModel
    @FocusState private var focused: Bool
    @State private var lastDrag: CGSize = .zero
    @State private var lastZoom: CGFloat = 1

    var body: some View {
        RealityView { content in
            content.camera = .virtual
            guard let world = model.world else { return }
            content.add(world.root)
            let camera = PerspectiveCamera()
            camera.camera.fieldOfViewInDegrees = 55
            camera.camera.far = 5000
            content.add(camera)
            model.camera = camera
            model.updates = content.subscribe(to: SceneEvents.Update.self) { event in
                model.tick(dt: Float(event.deltaTime))
            }
        }
        .gesture(
            DragGesture(minimumDistance: 2)
                .onChanged { g in
                    model.orbit(by: CGSize(width: g.translation.width - lastDrag.width,
                                           height: g.translation.height - lastDrag.height))
                    lastDrag = g.translation
                }
                .onEnded { _ in lastDrag = .zero }
        )
        .simultaneousGesture(
            MagnifyGesture()
                .onChanged { g in
                    model.zoom(by: Float(g.magnification / lastZoom))
                    lastZoom = g.magnification
                }
                .onEnded { _ in lastZoom = 1 }
        )
        .focusable()
        .focusEffectDisabled()
        .focused($focused)
        .onAppear { focused = true }
        .onChange(of: model.inMarket) { focused = !model.inMarket }
        .onKeyPress(phases: [.down, .up]) { press in
            guard !model.inMarket, !(model.visit?.holdsParty ?? false) else { return .ignored }
            let down = press.phase == .down
            if let move = Self.move(for: press) {
                if down { model.held.insert(move) } else { model.held.remove(move) }
                return .handled
            }
            guard down else { return .ignored }
            switch press.characters.lowercased() {
            case "l" where model.visit == nil: model.look()
            case "m": model.enterMarket()
            case "i": model.showingInventory.toggle()
            case "=", "+": model.zoom(by: 1.15)
            case "-": model.zoom(by: 1 / 1.15)
            default: return .ignored
            }
            return .handled
        }
    }

    private static func move(for press: KeyPress) -> GameModel.Move? {
        switch press.key {
        case .upArrow: return .forward
        case .downArrow: return .back
        case .leftArrow: return .left
        case .rightArrow: return .right
        default: break
        }
        switch press.characters.lowercased() {
        case "w": return .forward
        case "s": return .back
        case "a": return .left
        case "d": return .right
        default: return nil
        }
    }
}

/// The party is no more.
struct LostView: View {
    let words: String
    let onDone: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            Text("Alas").font(.blackletter(72)).foregroundStyle(Color.parchment)
            oldVoice(words, size: 22)
                .foregroundStyle(Color.parchment)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 520)
            Button("Back to the Harbour", action: onDone)
                .font(.fell(20))
                .buttonStyle(.borderedProminent)
                .tint(Color(red: 0.55, green: 0.12, blue: 0.10))
                .keyboardShortcut(.defaultAction)
        }
        .padding(30)
    }
}
