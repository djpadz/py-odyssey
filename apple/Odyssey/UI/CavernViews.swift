import OdysseyKit
import RealityKit
import SwiftUI

/// A 3D scene with the camera and the frame wired to the model: drag to turn, pinch or
/// ± to zoom, and whatever keys the scene wants.
struct StageView: View {
    let model: GameModel
    let root: Entity?
    let keys: (KeyPress) -> KeyPress.Result
    @FocusState private var focused: Bool
    @State private var lastDrag: CGSize = .zero
    @State private var lastZoom: CGFloat = 1

    var body: some View {
        RealityView { content in
            content.camera = .virtual
            guard let root else { return }
            content.add(root)
            let camera = PerspectiveCamera()
            camera.camera.fieldOfViewInDegrees = 55
            camera.camera.far = 5000
            content.add(camera)
            model.camera = camera
            model.updates = content.subscribe(to: SceneEvents.Update.self) { event in
                model.tick(dt: Float(event.deltaTime))
            }
        }
        // A scene built after the view appeared gets a fresh view.
        .id(root.map(ObjectIdentifier.init))
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
        .onKeyPress(phases: [.down, .up]) { press in
            switch press.characters {
            case "=", "+": if press.phase == .down { model.zoom(by: 1.15) }
            case "-": if press.phase == .down { model.zoom(by: 1 / 1.15) }
            default: return keys(press)
            }
            return .handled
        }
    }
}

// MARK: - The catacombs

struct CatacombsView: View {
    let model: GameModel

    var body: some View {
        StageView(model: model, root: model.catacombWorld?.root) { press in
            guard model.expedition?.catacombs?.question == nil else { return .ignored }
            let down = press.phase == .down
            switch press.key {
            case .upArrow: model.creep(toward: .forward, down: down)
            case .downArrow: model.creep(toward: .back, down: down)
            case .leftArrow: model.creep(toward: .left, down: down)
            case .rightArrow: model.creep(toward: .right, down: down)
            default:
                // The original's N, S, E and W step that way.
                guard down, let d = ["n": 0, "e": 1, "s": 2, "w": 3][press.characters.lowercased()] else { return .ignored }
                model.creep(d)
            }
            return .handled
        }
    }
}

/// What is said below ground, the orders, the maze as far as it is known, and the gas.
struct CatacombsHUD: View {
    let model: GameModel

    var body: some View {
        if let c = model.expedition?.catacombs, let party = model.expedition?.party {
            ZStack {
                if c.gas != nil {
                    // Things look kind of strange.
                    TimelineView(.animation) { t in
                        let hue = t.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 6) / 6
                        Color(hue: hue, saturation: 0.8, brightness: 0.6).opacity(0.28)
                    }
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
                }
                VStack(alignment: .leading) {
                    HStack(alignment: .top) {
                        panel(c).frame(maxWidth: 480, alignment: .leading)
                        Spacer()
                        VStack(alignment: .trailing, spacing: 10) {
                            Compass(yaw: model.cameraYaw)
                            if c.light { MazeMapView(catacombs: c) }
                        }
                    }
                    if let toast = model.toast {
                        oldVoice(toast, size: 22)
                            .foregroundStyle(Color.parchment)
                            .shadow(color: .black, radius: 4)
                            .frame(maxWidth: .infinity)
                    }
                    Spacer()
                    HStack(alignment: .bottom) {
                        if c.question == nil { orders(c) }
                        Spacer()
                        if model.showingInventory {
                            InventoryView(model: model)
                        }
                        Scroll {
                            Grid(alignment: .leading, verticalSpacing: 2) {
                                stat("Men", party.men)
                                stat("Level", c.depth + 1)
                                stat("Gold", party.gold)
                            }
                            .font(.fell(16))
                        }
                        .onTapGesture { model.showingInventory.toggle() }
                    }
                }
                .padding(20)
            }
        }
    }

    private func panel(_ c: Catacombs) -> some View {
        Scroll {
            Text(c.altar != nil ? "The Altar Room" : "The Catacombs").font(.blackletter(26))
            ForEach(Array((c.said.isEmpty ? c.report : c.said).enumerated()), id: \.offset) { _, line in
                oldVoice(line)
                    .foregroundStyle(line.hasSuffix("!") ? Color(red: 0.55, green: 0.1, blue: 0.08) : Color.ink)
            }
            if !c.light {
                Text("It is very dark. Press L for the light, or creep on in the dark.")
                    .font(.fell(15, italic: true)).opacity(0.75)
            }
            if let q = c.question {
                oldVoice(q.words, size: 18).padding(.top, 4)
                FlowRow {
                    if q == .teleport {
                        Button("Yes") { model.answerBelow(true) }.keyboardShortcut("y", modifiers: [])
                        Button("No") { model.answerBelow(false) }.keyboardShortcut("n", modifiers: [])
                    } else {
                        Button("Go down") { model.answerBelow(true) }.keyboardShortcut("d", modifiers: [])
                        Button("Bring them up") { model.answerBelow(false) }.keyboardShortcut("u", modifiers: [])
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(.ink.opacity(0.85))
                .font(.fell(16))
            }
        }
    }

    private func orders(_ c: Catacombs) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            FlowRow {
                Button(c.light ? "Light out" : "Light") { model.orderBelow(.light) }.keyboardShortcut("l", modifiers: [])
                Group {
                    Button("Down") { model.orderBelow(.down) }.keyboardShortcut("d", modifiers: [])
                    Button("Out") { model.orderBelow(.out) }.keyboardShortcut("o", modifiers: [])
                    Button("Get") { model.orderBelow(.get) }.keyboardShortcut("g", modifiers: [])
                    Button("Burrow") { model.orderBelow(.burrow) }.keyboardShortcut("b", modifiers: [])
                    Button("Teleport") { model.orderBelow(.teleport) }.keyboardShortcut("t", modifiers: [])
                    Button("Use or put…") { model.showingInventory = true }.keyboardShortcut("u", modifiers: [])
                }
                .disabled(!c.light)
            }
            .buttonStyle(.borderedProminent)
            .tint(.ink.opacity(0.85))
            .font(.fell(15))
            #if os(iOS)
            Grid(horizontalSpacing: 4, verticalSpacing: 4) {
                GridRow { Color.clear.frame(width: 44, height: 1); pad("N", 0); Color.clear.frame(width: 44, height: 1) }
                GridRow { pad("W", 3); Color.clear.frame(width: 44, height: 1); pad("E", 1) }
                GridRow { Color.clear.frame(width: 44, height: 1); pad("S", 2); Color.clear.frame(width: 44, height: 1) }
            }
            .buttonStyle(.borderedProminent)
            .tint(.ink.opacity(0.85))
            #else
            Text("Arrows, or N S E W, to creep about · drag to turn · ± to zoom")
                .font(.fell(13, italic: true))
                .foregroundStyle(.white.opacity(0.85))
                .shadow(radius: 2)
            #endif
        }
    }

    private func stat(_ label: String, _ value: Int) -> some View {
        GridRow {
            Text(label)
            Text("\(value)").gridColumnAlignment(.trailing).monospacedDigit()
        }
    }

    /// A step that way, on touch screens.
    private func pad(_ label: String, _ direction: Int) -> some View {
        Button(label) { model.creep(direction) }
            .font(.fell(16))
            .frame(width: 44)
    }
}

/// The catacombs as the original showed them: the lo-res screen, a square a block.
struct MazeMapView: View {
    let catacombs: Catacombs

    var body: some View {
        let c = catacombs
        Canvas { ctx, size in
            let s = size.width / 40
            func square(_ x: Int, _ y: Int) -> CGRect { CGRect(x: CGFloat(x) * s, y: CGFloat(y) * s, width: s, height: s) }
            ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(.black))
            for t in 0..<64 where c.laid[t] {
                ctx.fill(Path(CGRect(x: CGFloat(t % 8 * 5) * s, y: CGFloat(t / 8 * 5) * s, width: 5 * s, height: 5 * s)),
                         with: .color(Color(white: 0.16)))
            }
            for y in 0..<40 {
                for x in 0..<40 where c.isWall(x, y) {
                    ctx.fill(Path(square(x, y)), with: .color(Color(red: 0.55, green: 0.5, blue: 0.42)))
                }
            }
            if let a = c.altar { ctx.fill(Path(square(a.x, a.y)), with: .color(Color(red: 0.95, green: 0.75, blue: 0.3))) }
            if let f = c.frenzies { ctx.fill(Path(ellipseIn: square(f.x, f.y)), with: .color(.red)) }
            if let b = c.borer { ctx.fill(Path(ellipseIn: square(b.x, b.y)), with: .color(.orange)) }
            ctx.fill(Path(ellipseIn: square(c.x, c.y).insetBy(dx: -1, dy: -1)), with: .color(Color(red: 0.4, green: 0.7, blue: 1)))
        }
        .frame(width: 200, height: 200)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color.ink.opacity(0.5), lineWidth: 1.5))
        .shadow(color: .black.opacity(0.3), radius: 6, y: 3)
    }
}

// MARK: - Lapour

struct FortressView: View {
    let model: GameModel

    var body: some View {
        StageView(model: model, root: model.fortressWorld?.root) { _ in .ignored }
    }
}

/// The way up to the fortress: what bars it, and the orders (20012).
struct FortressHUD: View {
    let model: GameModel

    var body: some View {
        if let f = model.expedition?.fortress, let party = model.expedition?.party {
            VStack(alignment: .leading) {
                HStack(alignment: .top) {
                    Scroll {
                        Text("The Isle of Lapour").font(.blackletter(26))
                        ForEach(Array(f.said.enumerated()), id: \.offset) { _, line in oldVoice(line) }
                        if f.askingRetreat {
                            oldVoice("YOU WISH TO RETREAT?", size: 18)
                            FlowRow {
                                Button("Yes") { model.confirmRetreat(true) }.keyboardShortcut("y", modifiers: [])
                                Button("No") { model.confirmRetreat(false) }.keyboardShortcut("n", modifiers: [])
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(.ink.opacity(0.85))
                            .font(.fell(16))
                        } else {
                            oldVoice("WHAT DO YOU WANT TO DO NOW?", size: 18)
                        }
                    }
                    .frame(maxWidth: 480, alignment: .leading)
                    Spacer()
                    Compass(yaw: model.cameraYaw)
                }
                if let toast = model.toast {
                    oldVoice(toast, size: 22)
                        .foregroundStyle(Color.parchment)
                        .shadow(color: .black, radius: 4)
                        .frame(maxWidth: .infinity)
                }
                Spacer()
                HStack(alignment: .bottom) {
                    if !f.askingRetreat {
                        FlowRow {
                            Button("Approach the fortress") { model.approach() }.keyboardShortcut("a", modifiers: [])
                            Button("Use something…") { model.showingInventory = true }.keyboardShortcut("u", modifiers: [])
                            Button("Return to the ship") { model.retreat() }.keyboardShortcut("r", modifiers: [])
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.ink.opacity(0.85))
                        .font(.fell(15))
                        .frame(maxWidth: 520, alignment: .leading)
                    }
                    Spacer()
                    if model.showingInventory {
                        InventoryView(model: model)
                    }
                    Scroll {
                        Grid(alignment: .leading, verticalSpacing: 2) {
                            GridRow { Text("Men"); Text("\(party.men)").monospacedDigit() }
                            GridRow { Text("The orb"); Text(model.expedition?.hasOrb == true ? "yes" : "no") }
                        }
                        .font(.fell(16))
                    }
                    .onTapGesture { model.showingInventory.toggle() }
                }
            }
            .padding(20)
        }
    }
}

// MARK: - The end

/// 22000-23010: the reckoning.
struct EndingView: View {
    let model: GameModel

    var body: some View {
        if let end = model.expedition?.ending {
            ZStack {
                LinearGradient(colors: [Color(red: 0.05, green: 0.10, blue: 0.20), Color(red: 0.10, green: 0.25, blue: 0.35)],
                               startPoint: .top, endPoint: .bottom)
                    .ignoresSafeArea()
                VStack(spacing: 18) {
                    Text(end.won ? "Victory" : "Alas").font(.blackletter(72)).foregroundStyle(Color.parchment)
                    Scroll {
                        ForEach(Array(end.words.enumerated()), id: \.offset) { i, line in
                            oldVoice(line, size: i < 2 ? 19 : 17)
                                .fontWeight(line.hasPrefix("YOUR COMPOSITE SCORE") ? .bold : .regular)
                        }
                    }
                    .frame(maxWidth: 560)
                    HStack(spacing: 16) {
                        Button("Begin a New Quest") { model.newQuest() }.keyboardShortcut("1", modifiers: [])
                        Button("Back to the Title") { model.backToTitle() }.keyboardShortcut("2", modifiers: [])
                    }
                    .font(.fell(20))
                    .buttonStyle(.borderedProminent)
                    .tint(Color(red: 0.55, green: 0.12, blue: 0.10))
                }
                .padding(30)
            }
        }
    }
}
