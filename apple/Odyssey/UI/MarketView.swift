import OdysseyKit
import SwiftUI

/// Text in the original's voice: its capitals set as small caps.
func oldVoice(_ s: String, size: CGFloat = 17) -> Text {
    Text(s.lowercased()).font(.fell(size).smallCaps())
}

/// The city bazaar: the price board, and a merchant to haggle with.
struct MarketView: View {
    let model: GameModel

    private enum Stage: Equatable {
        case choosing
        case offering(words: String)           // waiting for an offer
        case agreed(price: Int)                // how many?
        case said(String)                      // the merchant has the last word
        case sold
    }

    @State private var stage = Stage.choosing
    @State private var haggle: Haggle?
    @State private var amount: Int?
    @State private var counter: Int?           // the merchant's standing counter-offer
    @FocusState private var amountFocused: Bool

    private var market: Market? { model.expedition?.market }
    private var party: Party? { model.expedition?.party }

    var body: some View {
        if let market, let party {
            VStack(spacing: 0) {
                Text(market.isCaravan ? "Caravan Sale Items" : "Bazaar Sale Items").font(.blackletter(34)).padding(.top, 14)
                HStack(alignment: .top, spacing: 20) {
                    board(market)
                        .frame(minWidth: 330, maxWidth: 420)
                    merchant(market)
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                }
                .padding(18)
                Divider().overlay(Color.ink.opacity(0.3))
                HStack {
                    oldVoice("YOU CAN CARRY \(party.capacity - party.load) MORE UNITS. YOU HAVE \(party.gold) QUADROONS TO SPEND.",
                             size: 15)
                    Spacer()
                    Button("Leave") { model.leaveMarket() }
                        .keyboardShortcut(.cancelAction)
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 12)
            }
            .foregroundStyle(Color.ink)
            .background(Color.parchment, in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.ink.opacity(0.4), lineWidth: 1.5))
            .shadow(color: .black.opacity(0.45), radius: 20, y: 8)
            .frame(maxWidth: 860)
            .padding(24)
            .buttonStyle(.bordered)
            .tint(.ink)
            .environment(\.colorScheme, .light)        // parchment is always light
        }
    }

    // MARK: The price board

    private func board(_ market: Market) -> some View {
        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 4) {
            GridRow {
                Text("#").gridColumnAlignment(.trailing)
                Text("Item")
                Text("Price").gridColumnAlignment(.trailing)
                Text("Weight").gridColumnAlignment(.trailing)
                Text("Qty").gridColumnAlignment(.trailing)
            }
            .font(.fell(14, italic: true))
            .opacity(0.7)
            ForEach(market.lots) { lot in
                let chosen = haggle?.lot == lot.id
                GridRow {
                    Text("\(lot.id).")
                    Text(lot.item.name.lowercased()).font(.fell(17).smallCaps())
                    Text("\(lot.price)")
                    Text("\(lot.item.weight)")
                    Text("\(lot.quantity)")
                }
                .font(.fell(17))
                .monospacedDigit()
                .strikethrough(lot.withdrawn)
                .opacity(lot.withdrawn || lot.quantity == 0 ? 0.4 : 1)
                .padding(.vertical, 1)
                .background(chosen ? Color.ink.opacity(0.1) : .clear)
                .contentShape(Rectangle())
                .onTapGesture { choose(lot) }
            }
        }
    }

    // MARK: The merchant

    @ViewBuilder
    private func merchant(_ market: Market) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            switch stage {
            case .choosing:
                oldVoice("WHICH PRODUCT INTERESTS YOU M'LORD?", size: 20)
                Text("Choose from the board.").font(.fell(15, italic: true)).opacity(0.7)
            case let .offering(words):
                oldVoice(words, size: 20)
                HStack {
                    TextField("Your offer", value: $amount, format: .number)
                        .textFieldStyle(.parchment)
                        .frame(width: 120)
                        .focused($amountFocused)
                        #if os(iOS)
                        .keyboardType(.numberPad)
                        #endif
                        .onSubmit(makeOffer)
                    Button("Offer", action: makeOffer)
                    if let counter {
                        Button("Agreed — \(counter)") { stage = .agreed(price: counter); amount = 1 }
                            .keyboardShortcut("y", modifiers: [])
                            .buttonStyle(.borderedProminent)
                    }
                }
                Button("Never mind", action: reset)
            case let .agreed(price):
                if let lot = haggle.map({ market[$0.lot] }) {
                    oldVoice("AT \(price) QUADROONS PER \(lot.item.name), HOW MANY WOULD YOU LIKE?", size: 20)
                    HStack {
                        TextField("How many", value: $amount, format: .number)
                            .textFieldStyle(.parchment)
                            .frame(width: 80)
                            .focused($amountFocused)
                            #if os(iOS)
                            .keyboardType(.numberPad)
                            #endif
                            .onSubmit { purchase(at: price) }
                        Stepper("", value: Binding(get: { amount ?? 1 }, set: { amount = $0 }), in: 1...max(lot.quantity, 1))
                            .labelsHidden()
                        Button("Buy") { purchase(at: price) }
                            .buttonStyle(.borderedProminent)
                    }
                    Button("Never mind", action: reset)
                }
            case let .said(words):
                oldVoice(words, size: 20)
                Button("Very well", action: reset).keyboardShortcut(.defaultAction)
            case .sold:
                Text("SOLD")
                    .font(.blackletter(64))
                    .foregroundStyle(Color(red: 0.6, green: 0.1, blue: 0.1))
                    .rotationEffect(.degrees(-8))
                    .padding(.top, 20)
                    .transition(.scale(scale: 2.5).combined(with: .opacity))
            }
        }
        .animation(.spring(duration: 0.35), value: stage)
        .onChange(of: stage) { amountFocused = true }
    }

    // MARK: Actions

    private func choose(_ lot: Market.Lot) {
        guard !lot.withdrawn, lot.quantity > 0 else { return }
        haggle = Haggle(lot: lot.id)
        counter = nil
        amount = nil
        stage = .offering(words: "WHAT DO YOU OFFER FOR OUR FINE \(lot.item.name(quantity: 2))?")
    }

    private func reset() {
        haggle = nil
        counter = nil
        amount = nil
        stage = .choosing
    }

    private func makeOffer() {
        guard var h = haggle, let offer = amount else { return }
        guard offer >= 1 else { return reset() }
        let reply = model.offer(offer, in: &h)
        haggle = h
        amount = nil
        switch reply {
        case let .accepted(price):
            amount = 1
            stage = .agreed(price: price)
        case let .counter(price, words):
            counter = price
            stage = .offering(words: words)
        case let .broken(words), let .insulted(words):
            counter = nil
            stage = .said(words)
        case nil:
            reset()
        }
    }

    private func purchase(at price: Int) {
        guard let h = haggle, let n = amount, n >= 1, let market else { return }
        let name = market[h.lot].item.name(quantity: 2)
        switch model.buy(lot: h.lot, quantity: n, at: price) {
        case .sold:
            stage = .sold
            Task {
                try? await Task.sleep(for: .seconds(1.3))
                if stage == .sold { reset() }
            }
        case .notEnoughGold: stage = .said("NOT ENOUGH GOLD.")
        case let .onlyHave(q): stage = .said("SORRY, WE ONLY HAVE \(q) \(name).")
        case let .tooHeavy(canCarry): stage = .said("YOUR MEN CAN CARRY ONLY \(max(canCarry, 0)) MORE UNITS, SIRE.")
        case nil: reset()
        }
    }
}

/// What the party carries, and its condition (the original's C, lines 800-812).
/// Choosing a thing offers to use it or drop some here.
struct InventoryView: View {
    let model: GameModel
    @State private var chosen: Item?
    @State private var count = 1

    var body: some View {
        if let e = model.expedition {
            let party = e.party
            Scroll {
                HStack {
                    Text("Inventory").font(.blackletter(26))
                    Spacer()
                    Button { model.showingInventory = false } label: { Image(systemName: "xmark") }
                        .buttonStyle(.plain)
                        .keyboardShortcut(.cancelAction)
                }
                Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 3) {
                    row(.foodPack, party.foodPacks)
                    row(.quadroon, party.gold)
                    ForEach(party.belongings, id: \.item) { row($0.item, $0.quantity) }
                }
                if let item = chosen, let have = party.inventory[item], have > 0 {
                    actions(item, have: have, e)
                }
                oldVoice("YOUR \(party.men) MEN CAN CARRY \(party.capacity). YOU HAVE \(party.load).", size: 15)
                    .padding(.top, 6)
                Divider().overlay(Color.ink.opacity(0.3))
                Text("Status Report").font(.blackletter(20))
                Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 2) {
                    GridRow { stat("# IN PARTY", party.men); stat("STRENGTH", party.strength) }
                    GridRow { stat("CHARISMA", party.charisma); stat("EXPER.", party.experience) }
                    GridRow { stat("WISDOM", party.wisdom); stat("SPEED", party.speed) }
                    GridRow { stat("DEXTERITY", party.dexterity); stat("ALIGN.", party.alignment) }
                }
            }
            .frame(maxWidth: 380)
            .onChange(of: chosen) { count = 1 }
        }
    }

    private func row(_ item: Item, _ quantity: Int) -> some View {
        GridRow {
            Text("\(quantity)").gridColumnAlignment(.trailing).monospacedDigit()
            Button { chosen = chosen == item ? nil : item } label: {
                Text(item.name(quantity: quantity).lowercased()).font(.fell(17).smallCaps())
                    .underline(chosen == item)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(item.name.capitalized)
            Text("\(item.weight * quantity)").gridColumnAlignment(.trailing).monospacedDigit().opacity(0.6)
        }
        .font(.fell(17))
    }

    @ViewBuilder
    private func actions(_ item: Item, have: Int, _ e: Expedition) -> some View {
        if e.catacombs != nil {
            HStack(spacing: 10) {
                Button("Use") { model.useBelow(item) }
                Stepper("\(count)", value: $count, in: 1...have).font(.fell(16)).fixedSize()
                Button("Put down") {
                    model.putDown(item, quantity: count)
                    chosen = nil
                }
            }
            .buttonStyle(.bordered)
            .tint(.ink)
            .font(.fell(16))
        } else if e.fortress != nil {
            Button("Use") { model.useAtFortress(item) }
                .buttonStyle(.bordered)
                .tint(.ink)
                .font(.fell(16))
        } else if e.voyage != nil {
            seaActions(item, have: have)
        } else {
            islandActions(item, have: have, e)
        }
    }

    /// At sea: use it, offer it, or put some over the side.
    private func seaActions(_ item: Item, have: Int) -> some View {
        HStack(spacing: 10) {
            Button("Use") { model.useAtSea(item) }
            Button("Offer") { model.useAtSea(item, offering: true) }
            Stepper("\(count)", value: $count, in: 1...have)
                .font(.fell(16))
                .fixedSize()
            Button("Put over") {
                model.putOver(item, quantity: count)
                chosen = nil
            }
        }
        .buttonStyle(.bordered)
        .tint(.ink)
        .font(.fell(16))
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private func islandActions(_ item: Item, have: Int, _ e: Expedition) -> some View {
        let free = e.isFree && e.visit == nil && e.mount == nil
        let room = min(e.room(for: item), have)
        HStack(spacing: 10) {
            if Expedition.isUsable(item) {
                Button("Use") { model.use(item) }
                    .disabled(!e.isFree || e.visit != nil)
            }
            if room > 0 && free {
                Stepper("\(count)", value: $count, in: 1...room)
                    .font(.fell(16))
                    .fixedSize()
                Button("Drop") {
                    model.drop(item, quantity: count)
                    chosen = nil
                }
            } else if free {
                Text(e.site == nil ? "Something else lies here." : "Not here.").font(.fell(14, italic: true)).opacity(0.7)
            }
        }
        .buttonStyle(.bordered)
        .tint(.ink)
        .font(.fell(16))
        .padding(.vertical, 2)
    }

    private func stat(_ label: String, _ value: Int) -> some View {
        HStack(spacing: 4) {
            oldVoice(label + "=", size: 14)
            Text("\(value)").font(.fell(15)).monospacedDigit()
        }
    }
}

/// A number field inked on paler parchment, legible whatever the system appearance.
struct ParchmentFieldStyle: TextFieldStyle {
    func _body(configuration: TextField<Self._Label>) -> some View {
        configuration
            .textFieldStyle(.plain)
            .font(.fell(18))
            .foregroundStyle(Color.ink)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(Color.white.opacity(0.75), in: RoundedRectangle(cornerRadius: 5))
            .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(Color.ink.opacity(0.45), lineWidth: 1))
    }
}

extension TextFieldStyle where Self == ParchmentFieldStyle {
    static var parchment: ParchmentFieldStyle { ParchmentFieldStyle() }
}
