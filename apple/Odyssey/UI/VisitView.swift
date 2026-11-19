import OdysseyKit
import SwiftUI

/// A visit to a temple, ruin, castle, tomb or hut, or something met on the road:
/// what happened, what now.
struct VisitView: View {
    let model: GameModel
    let visit: Visit
    @State private var choosingItem = false
    /// Whether the original's keys work yet. As in the original, a panel ignores keys
    /// pressed before it appeared: with A held to walk west, a caravan's Attack mustn't
    /// fire. They arm once every walking key is up, and a moment has passed.
    @State private var armed = false

    var body: some View {
        Scroll {
            Text(title).font(.blackletter(26))
            ForEach(Array(visit.said.enumerated()), id: \.offset) { _, line in
                oldVoice(line)
                    .foregroundStyle(line.hasSuffix("!") ? Color(red: 0.55, green: 0.1, blue: 0.08) : Color.ink)
            }
            if case let .battle(b) = visit.stage {
                Tally(battle: b)
            }
            if !visit.question.isEmpty {
                oldVoice(visit.question, size: 18)
                    .padding(.top, 4)
            }
            if choosingItem {
                itemPicker
            } else {
                buttons
            }
        }
        .frame(maxWidth: 480, alignment: .leading)
        .animation(.easeInOut(duration: 0.2), value: visit.stage)
        .onChange(of: visit.stage) { choosingItem = false }
        .task(id: "\(visit.stage)\(visit.said)") {
            armed = false
            while !model.held.isEmpty {
                try? await Task.sleep(for: .milliseconds(50))
            }
            try? await Task.sleep(for: .milliseconds(300))
            if !Task.isCancelled { armed = true }
        }
    }

    private var title: String {
        switch visit.stage {
        case let .battle(b):
            if case .monsters = b.foe { "Monsters!" } else { "To Arms!" }
        case .monstersAhead, .offering: "Monsters!"
        case .pit: "A Pit Trap"
        case .caravan: "A Caravan"
        case let .wizard(good): good ? "A Wizard" : "A Warlock"
        case .warriors: "Warriors"
        case .trapped: "Misfortune"
        case .obstacle: "The Way Is Barred"
        case .amulet: "The Amulet"
        case let .charm(item): "The \(item.name.capitalized)"
        default: visit.site.map { "The \($0.distantName.capitalized)" } ?? "On the Road"
        }
    }

    private var buttons: some View {
        FlowRow {
            if visit.canUseItems {
                Button("Use…") { choosingItem = true }
                    .keyboardShortcut(armed ? KeyboardShortcut("u", modifiers: []) : nil)
            }
            ForEach(visit.actions, id: \.self) { action in
                // On the road, leaving at the end is just walking on.
                let (label, key) = visit.site == nil && visit.stage == .finished ? ("Go on", "g") : Self.label(action)
                Button(label) { model.act(action) }
                    .keyboardShortcut(armed ? KeyboardShortcut(key, modifiers: []) : nil)
            }
        }
        .buttonStyle(.borderedProminent)
        .tint(.ink.opacity(0.85))
        .font(.fell(16))
    }

    private var itemPicker: some View {
        VStack(alignment: .leading, spacing: 6) {
            let things = model.expedition?.party.belongings ?? []
            if things.isEmpty {
                Text("You carry nothing that might help.").font(.fell(15, italic: true))
            }
            FlowRow {
                ForEach(things, id: \.item) { thing in
                    Button(thing.item.name.lowercased()) { model.act(.use(thing.item)) }
                        .font(.fell(16).smallCaps())
                }
                Button("Never mind") { choosingItem = false }
                    .keyboardShortcut(.cancelAction)
                    .font(.fell(15, italic: true))
            }
            .buttonStyle(.bordered)
        }
    }

    /// Button labels, keyed as in the original where it had a key.
    static func label(_ a: Action) -> (String, KeyEquivalent) {
        switch a {
        case .use: ("Use…", "u")
        case .enter: ("Enter", "e")
        case .leave: ("Leave", "l")
        case .search: ("Search further", "s")
        case .take: ("Get it", "g")
        case .leaveIt: ("Leave it", "l")
        case .open: ("Open it", "o")
        case .goOn: ("Go on", "g")
        case .attack: ("Attack", "a")
        case .slipAway: ("Leave them be", "l")
        case .offerGold: ("Offer gold", "g")
        case .offerFood: ("Offer food", "f")
        case .fight: ("Fight", "f")
        case .run: ("Run", "r")
        case .accept: ("Yes", "y")
        case .decline: ("No", "n")
        case .carryOn: ("Leave them", "c")
        case .ignore: ("Ignore them", "i")
        case .buy: ("Buy something", "b")
        case .requestAid: ("Request aid", "r")
        case .beFriendly: ("Be friendly", "f")
        case .wait: ("Wait cautiously", "w")
        case .increaseSpeed: ("Increase speed", "1")
        case .increaseCharisma: ("Increase charisma", "2")
        case .increaseWisdom: ("Increase wisdom", "3")
        case .saveIt: ("Save it", "4")
        }
    }
}

/// The battle board: both sides' numbers and the last round's reckoning.
struct Tally: View {
    let battle: Battle

    var body: some View {
        Grid(horizontalSpacing: 16, verticalSpacing: 2) {
            GridRow {
                Text("You").font(.blackletter(18))
                Text("")
                Text(battle.foe.name.capitalized).font(.blackletter(18))
            }
            row(battle.ourNumber, "original number", battle.theirNumber)
            row(battle.ourLosses, "casualties", battle.theirLosses)
            row(battle.ourStanding, "current number", battle.theirStanding)
            if let r = battle.lastRound {
                Divider().gridCellUnsizedAxes(.horizontal)
                row(battle.ourArms * battle.ourStanding, "weapons & armour", battle.theirArms * battle.theirStanding)
                row(battle.ourStrength * battle.ourStanding, "experience & strength", battle.theirStrength * battle.theirStanding)
                row(r.ourLuck, "luck", r.theirLuck)
                row(r.ourTotal, "totals", r.theirTotal).bold()
            }
        }
        .font(.fell(16))
        .monospacedDigit()
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity)
    }

    private func row(_ ours: Int, _ label: String, _ theirs: Int) -> some View {
        GridRow {
            Text("\(ours)")
            Text(label).font(.fell(14, italic: true)).opacity(0.7)
            Text("\(theirs)")
        }
    }
}

/// Lays its children out in rows, wrapping as needed.
struct FlowRow: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(width: proposal.width ?? .infinity, subviews: subviews)
        let width = rows.map { $0.last.map { $0.x + $0.size.width } ?? 0 }.max() ?? 0
        let height = rows.last.flatMap { $0.map { $0.y + $0.size.height }.max() } ?? 0
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for (i, place) in arrange(width: bounds.width, subviews: subviews).joined().enumerated() {
            subviews[i].place(at: CGPoint(x: bounds.minX + place.x, y: bounds.minY + place.y), proposal: .unspecified)
        }
    }

    private func arrange(width: CGFloat, subviews: Subviews) -> [[(x: CGFloat, y: CGFloat, size: CGSize)]] {
        var rows: [[(x: CGFloat, y: CGFloat, size: CGSize)]] = [[]]
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > 0 && x + size.width > width {
                rows.append([])
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            rows[rows.count - 1].append((x, y, size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return rows
    }
}
