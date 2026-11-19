import OdysseyKit
import RealityKit
import SwiftUI

/// The sea in 3D. Arrow keys set the sails; drag turns the camera.
struct SeaView: View {
    let model: GameModel
    @FocusState private var focused: Bool
    @State private var lastDrag: CGSize = .zero
    @State private var lastZoom: CGFloat = 1

    var body: some View {
        RealityView { content in
            content.camera = .virtual
            guard let sea = model.seaWorld else { return }
            content.add(sea.root)
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
        .onKeyPress(phases: .down) { press in
            guard !model.inMarket, model.voyage?.question == nil else { return .ignored }
            switch press.key {
            case .upArrow: model.sail(toward: .forward)
            case .downArrow: model.sail(toward: .back)
            case .leftArrow: model.sail(toward: .left)
            case .rightArrow: model.sail(toward: .right)
            default:
                switch press.characters {
                case "=", "+": model.zoom(by: 1.15)
                case "-": model.zoom(by: 1 / 1.15)
                case "i", "c": model.showingInventory.toggle()
                default: return .ignored
                }
            }
            return .handled
        }
    }
}

/// What the crew says, the questions put, the captain's orders, the bridge report and
/// the chart.
struct SeaHUD: View {
    let model: GameModel
    @State private var choosingSails = false
    @State private var payment: Int?
    @State private var flash = 0.0

    var body: some View {
        ZStack {
            weather
            if model.inMarket {
                MarketView(model: model)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            } else if let v = model.voyage {
                field(v)
            }
        }
        .animation(.easeInOut(duration: 0.4), value: model.inMarket)
    }

    // MARK: Weather

    /// Fog closes in; a storm darkens everything, and lightning lights it up.
    private var weather: some View {
        ZStack {
            if model.voyage?.happening == .fog {
                RadialGradient(colors: [.white.opacity(0.45), .white.opacity(0.92)], center: .center,
                               startRadius: 40, endRadius: 600)
                    .transition(.opacity)
            }
            if model.voyage?.happening == .storm {
                Color(red: 0.04, green: 0.06, blue: 0.12).opacity(0.6).transition(.opacity)
            }
            Color.white.opacity(flash)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .animation(.easeInOut(duration: 1.5), value: model.voyage?.happening)
        .onChange(of: model.voyage?.flashes) {
            flash = 0.85
            withAnimation(.easeOut(duration: 0.5)) { flash = 0 }
        }
    }

    // MARK: The layout

    private func field(_ v: Voyage) -> some View {
        VStack(alignment: .leading) {
            HStack(alignment: .top) {
                if let panel = panel(v) {
                    panel
                        .frame(maxWidth: 480, alignment: .leading)
                        .transition(.move(edge: .leading).combined(with: .opacity))
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 10) {
                    Compass(yaw: model.cameraYaw)
                    SeaMapView(model: model)
                }
            }
            if let toast = model.toast {
                oldVoice(toast, size: 22)
                    .foregroundStyle(Color.parchment)
                    .shadow(color: .black, radius: 4)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 30)
            }
            Spacer()
            HStack(alignment: .bottom) {
                if isCommanding(v) {
                    orders(v)
                }
                Spacer()
                if model.showingInventory {
                    InventoryView(model: model)
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                }
                bridge(v)
            }
            .animation(.easeInOut(duration: 0.25), value: model.showingInventory)
        }
        .padding(20)
        .animation(.easeInOut(duration: 0.3), value: v.said)
    }

    /// Whether the captain's ordinary orders apply (not while a question waits, ashore,
    /// at the temple, or lost).
    private func isCommanding(_ v: Voyage) -> Bool {
        v.question == nil && v.ashore == nil && !v.lost && v.happening != .temple
    }

    // MARK: The panel

    private func panel(_ v: Voyage) -> AnyView? {
        let showing = !v.said.isEmpty || v.question != nil || v.happening != nil || v.lost || v.ashore != nil
        guard showing else { return nil }
        return AnyView(Scroll {
            Text(SeaHUD.title(v)).font(.blackletter(26))
            ForEach(Array(v.said.enumerated()), id: \.offset) { _, line in
                oldVoice(line)
                    .foregroundStyle(line.hasSuffix("!") ? Color(red: 0.55, green: 0.1, blue: 0.08) : Color.ink)
            }
            if v.lost {
                buttons {
                    Button("Recover the ship") { model.recoverShip() }.keyboardShortcut("1", modifiers: [])
                    Button("Begin a new quest") { model.newQuest() }.keyboardShortcut("2", modifiers: [])
                }
            } else if let q = v.question {
                oldVoice(q.words, size: 18).padding(.top, 4)
                if q == .fishermen {
                    payField
                } else {
                    buttons {
                        ForEach(q.answers, id: \.self) { a in
                            let (label, key) = SeaHUD.label(a)
                            Button(label) { model.answer(a) }.keyboardShortcut(key, modifiers: [])
                        }
                    }
                }
            } else if v.happening == .temple {
                buttons {
                    Button("Attack") { model.templeAttack() }.keyboardShortcut("a", modifiers: [])
                    Button("Use or offer…") { model.showingInventory = true }.keyboardShortcut("o", modifiers: [])
                    Button("Leave") { model.templeLeave() }.keyboardShortcut("l", modifiers: [])
                }
            }
        })
    }

    private var payField: some View {
        HStack {
            TextField("Quadroons", value: $payment, format: .number)
                .textFieldStyle(.parchment)
                .frame(width: 120)
                .onSubmit(pay)
            Button("Pay") { pay() }.keyboardShortcut(.defaultAction)
        }
        .buttonStyle(.borderedProminent)
        .tint(.ink.opacity(0.85))
        .font(.fell(16))
    }

    private func pay() {
        model.pay(payment ?? 0)
        payment = nil
    }

    private func buttons<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        FlowRow { content() }
            .buttonStyle(.borderedProminent)
            .tint(.ink.opacity(0.85))
            .font(.fell(16))
            .padding(.top, 4)
    }

    static func title(_ v: Voyage) -> String {
        if v.lost { return "Lost" }
        if let shore = v.ashore { return shore == .catacombs ? "The Catacombs" : "The Isle of Lapour" }
        switch v.question {
        case .merchants?: return "Merchantmen"
        case .raft?: return "A Raft"
        case .raftChest?: return "The Raft's Chest"
        case .hail?: return "Hailing Them"
        case .fishermen?: return "The Fishermen"
        case .lapour?: return "The Isle of Lapour"
        case nil: break
        }
        switch v.happening {
        case .ships?: return "Ships!"
        case .pirates?: return "Pirates!"
        case .fog?: return "Fog"
        case .storm?: return "A Storm"
        case .aground?: return "Aground"
        case .whirlpool?: return "A Whirlpool!"
        case .flyers?: return "Monsters!"
        case let .seaMonster(m)?: return m == .octopus ? "A Giant Octopus" : "A Sea Serpent"
        case .argorion?: return "Argorion"
        case .temple?: return "The Temple"
        case .rottenSails?: return "Rotten Sails"
        case .nearEdge?: return "The Edge of the World"
        case nil: return "The Sargalo Sea"
        }
    }

    static func label(_ a: SeaAnswer) -> (String, KeyEquivalent) {
        switch a {
        case .buy: ("Buy something", "b")
        case .ignore: ("Ignore them", "i")
        case .attack: ("Attack", "a")
        case .takeAboard: ("Take them aboard", "t")
        case .kill: ("Kill them", "k")
        case .open: ("Open it", "o")
        case .dump: ("Dump it over the side", "d")
        case .friendly: ("Friendly", "f")
        case .challenge: ("Challenge", "c")
        case .yes: ("Yes", "y")
        case .no: ("No", "n")
        }
    }

    // MARK: Orders

    private func orders(_ v: Voyage) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if choosingSails {
                sailsRose(v)
            }
            FlowRow {
                Button(anchorLabel(v)) { model.order(.anchor) }.keyboardShortcut("a", modifiers: [])
                Button("Set sails…") { choosingSails.toggle() }.keyboardShortcut("s", modifiers: [])
                Button("Reef") { model.order(.reef) }.keyboardShortcut("r", modifiers: [])
                Button("Fire cannon") { model.order(.fire) }.keyboardShortcut("f", modifiers: [])
                Button("Land") { model.order(.land) }.keyboardShortcut("l", modifiers: [])
                Button("Divers") { model.order(.divers) }.keyboardShortcut("d", modifiers: [])
                Button("Hail") { model.order(.hail) }.keyboardShortcut("h", modifiers: [])
                Button("Get") { model.order(.get) }.keyboardShortcut("g", modifiers: [])
                Button("Watch") { model.order(.watch) }.keyboardShortcut("w", modifiers: [])
            }
            .buttonStyle(.borderedProminent)
            .tint(.ink.opacity(0.85))
            .font(.fell(15))
            #if os(macOS)
            Text("Arrows set the sails · the original's keys give the orders · I for inventory · drag to turn · ± to zoom")
                .font(.fell(13, italic: true))
                .foregroundStyle(.white.opacity(0.85))
                .shadow(radius: 2)
            #endif
        }
        .frame(maxWidth: 560, alignment: .leading)
    }

    /// A raises or drops the anchor, unless something alongside wants attacking.
    private func anchorLabel(_ v: Voyage) -> String {
        switch v.happening {
        case .seaMonster?, .flyers?: "Attack"
        case .ships?: "Sail away"
        case .pirates?: "Defy them"
        case .argorion?: "Weigh anchor"
        default: v.anchored ? "Weigh anchor" : "Drop anchor"
        }
    }

    /// The eight points, those into the wind greyed.
    private func sailsRose(_ v: Voyage) -> some View {
        let grid = [[7, 0, 1], [6, -1, 2], [5, 4, 3]]
        return Scroll {
            Text("Set the sails").font(.blackletter(18))
            Grid(horizontalSpacing: 6, verticalSpacing: 6) {
                ForEach(grid, id: \.self) { row in
                    GridRow {
                        ForEach(row, id: \.self) { d in
                            if d < 0 {
                                Button("Cancel") { choosingSails = false }.font(.fell(13, italic: true))
                            } else {
                                Button(CompassPoint.names[d]) {
                                    model.order(.setSails(d))
                                    choosingSails = false
                                }
                                .disabled(v.wind.map { $0 == d || ($0 + 1) % 8 == d || ($0 + 7) % 8 == d } ?? true)
                                .frame(minWidth: 44)
                            }
                        }
                    }
                }
            }
            .buttonStyle(.bordered)
            .tint(.ink)
            .font(.fell(15))
            oldVoice(v.wind.map { "THE WIND IS OUT OF THE \(CompassPoint.names[$0])." } ?? "THERE IS NO WIND AT ALL.", size: 14)
        }
        .fixedSize()
    }

    // MARK: The bridge

    private func bridge(_ v: Voyage) -> some View {
        Scroll {
            ForEach(v.report(sextant: model.expedition?.hasSextant ?? false), id: \.self) { line in
                oldVoice(line, size: 14)
            }
            if let party = model.expedition?.party {
                Divider().overlay(Color.ink.opacity(0.3))
                Grid(alignment: .leading, verticalSpacing: 2) {
                    stat("Men", party.men)
                    stat("Food packs", party.foodPacks)
                    stat("Gold", party.gold)
                }
                .font(.fell(16))
            }
        }
        .frame(maxWidth: 300)
        .onTapGesture { model.showingInventory.toggle() }
    }

    private func stat(_ label: String, _ value: Int) -> some View {
        GridRow {
            Text(label)
            Text("\(value)").gridColumnAlignment(.trailing).monospacedDigit()
        }
    }
}

/// The painted chart, the ship on it, and where Argorion said the orb lies. In fog
/// there is nothing to see.
struct SeaMapView: View {
    let model: GameModel
    @State private var large = false

    var body: some View {
        if let image = model.chartImage, let v = model.voyage {
            let width: CGFloat = large ? 480 : 230
            let span = CGSize(width: SeaChart.width, height: SeaChart.height)
            let ship = CGPoint(x: v.x, y: v.y)
            let orb = v.orbAt.map { CGPoint(x: $0.x, y: $0.y) }
            let heading = Double(model.partyHeading)
            let scale: CGFloat = large ? 1.4 : 1
            Image(decorative: image, scale: 1)
                .resizable()
                .frame(width: width, height: width * span.height / span.width)
                .overlay {
                    Canvas { ctx, size in
                        func place(_ p: CGPoint) -> CGPoint {
                            CGPoint(x: p.x / span.width * size.width, y: p.y / span.height * size.height)
                        }
                        if let orb {
                            let p = place(orb)
                            let r = 5 * scale
                            var x = Path()
                            x.move(to: CGPoint(x: p.x - r, y: p.y - r))
                            x.addLine(to: CGPoint(x: p.x + r, y: p.y + r))
                            x.move(to: CGPoint(x: p.x + r, y: p.y - r))
                            x.addLine(to: CGPoint(x: p.x - r, y: p.y + r))
                            ctx.stroke(x, with: .color(Color(red: 0.95, green: 0.75, blue: 0.3)), lineWidth: 2.5)
                        }
                        let p = place(ship)
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
                .overlay {
                    if v.happening == .fog {
                        Color.white.opacity(0.9)
                        Text("Fog").font(.fell(18, italic: true)).foregroundStyle(Color.ink.opacity(0.6))
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color.ink.opacity(0.5), lineWidth: 1.5))
                .shadow(color: .black.opacity(0.3), radius: 6, y: 3)
                .onTapGesture { large.toggle() }
                .animation(.easeInOut(duration: 0.25), value: large)
                .accessibilityLabel("Chart of the Sargalo Sea")
        }
    }
}
