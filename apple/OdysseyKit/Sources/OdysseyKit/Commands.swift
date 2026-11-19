/// The island commands besides walking (lines 760-830, 8100-8180): get, drop, ride,
/// halt, and using things, magic above all.

public enum Mount: Sendable, Equatable {
    case horses
    case rug
}

extension Expedition {
    /// Whether the party is free to do as it likes: not in the market, not caught up in
    /// something it must see through.
    public var isFree: Bool { !isLost && market == nil && visit?.holdsParty != true }

    // MARK: Things lying about

    /// Line 320: one step in thirty on bare ground turns up a plank, a monkey, a torch,
    /// a mirror, a crowbar, an old map or a brass key.
    mutating func turnUpSomething() {
        guard island.isBare(cell), rng.rnd(30) == 0 else { return }
        island.lay(Item(31 + rng.rnd(7)), 1, in: cell)
    }

    /// 780-782: pick up what lies here.
    public mutating func get() -> String {
        guard let (item, n) = island.lying(cell) else {
            return "OK, YOU GOT TWO HANDFULS OF MUD. NOW WHAT?"
        }
        // (The original takes it all and makes you drop the excess later.)
        if item != .quadroon && party.load + item.weight * n > party.capacity {
            return "YOUR MEN CAN CARRY ONLY \(max(party.capacity - party.load, 0)) MORE UNITS, SIRE."
        }
        island.clearGround(cell)
        party.inventory[item, default: 0] += n
        if item == .foodPack { hungryRations = 0 }
        return "OK, YOU GOT \(n) \(item.name(quantity: n)). NOW WHAT?"
    }

    /// How many of an item can be dropped here: the ground holds one kind of thing,
    /// up to 99, and nothing at a site. (The original drops anything, and loses it
    /// when the ground is taken.)
    public func room(for item: Item) -> Int {
        guard item != .ship, site == nil else { return 0 }
        if island.isBare(cell) { return 99 }
        if let (there, n) = island.lying(cell), there == item { return 99 - n }
        return 0
    }

    /// 770-777, 430-435: leave some of something here.
    @discardableResult
    public mutating func drop(_ item: Item, quantity: Int) -> Bool {
        let have = party.inventory[item] ?? 0
        guard isFree, quantity >= 1, quantity <= have, quantity <= room(for: item) else { return false }
        let already = island.lying(cell)?.quantity ?? 0
        party.inventory[item] = have - quantity
        island.lay(item, already + quantity, in: cell)
        return true
    }

    // MARK: Riding

    /// 820-825: mount up, a horse for every two men.
    public mutating func ride() -> String? {
        guard isFree else { return nil }
        let horses = party.inventory[Item(20)] ?? 0
        guard horses > 0, horses >= party.men / 2 else { return "NOT ENOUGH HORSES" }
        mount = .horses
        visit = nil
        return nil
    }

    /// H: come down off the horses or the rug. The rug won't land on the water.
    public mutating func halt() -> String? {
        guard mount != nil else { return "YOU ARE HALTED." }
        if mount == .rug && terrain == .ocean {
            return "I AM SORRY, MY LIEGE. YOUR MEN DO NOT APPEAR TO HAVE YOUR ABILITY TO WALK ON WATER."
        }
        mount = nil
        lookAround()
        arrive()
        return nil
    }

    /// 125-130
    mutating func drownHorses() {
        party.inventory[Item(20)] = max((party.inventory[Item(20)] ?? 0) - 2, 0)
        mount = nil
        news.append("NOT ONE OF YOUR BETTER MOVES, SIRE. YOU DROWNED 2 HORSES.")
        arrive()
    }

    // MARK: Using things

    /// Whether an item can be used on the road (the ship waits for the sea).
    public static func isUsable(_ item: Item) -> Bool {
        item != .ship && item != .foodPack && item != .quadroon
    }

    /// 760-765, 8100-8180: use something on the road. Magic does what it does; anything
    /// else does nothing here.
    public mutating func use(_ item: Item) {
        guard isFree, visit == nil, (party.inventory[item] ?? 0) > 0, Expedition.isUsable(item) else { return }
        var v = Visit(cell: cell, stage: .finished)
        switch item.id {
        case 39:
            v.stage = .amulet
        case 40:
            v.said = ["THE SCROLL CONTAINS A SPELL WRITTEN IN ANCIENT HIERGLYPHS."]
            let gold: Int
            if party.wisdom > 8 {
                v.said.append("YOU TRANSLATED MOST OF IT....")
                gold = 2000
            } else if party.wisdom > 4 {
                v.said.append("YOU DECIPHERED SOME OF IT....")
                gold = 1000
            } else {
                v.said.append("YOU CAN'T FIGURE OUT WHAT IT SAYS.")
                visit = v
                return
            }
            v.said += ["SOME ROCKS NEARBY WERE TRANSMUTED INTO GOLD. \(gold) QUADROONS WORTH!",
                       "THE SCROLL DISAPPEARED, THOUGH."]
            party.gold += gold
            useUp(item)
        case 41, 42, 46, 47:
            // The magic lamp, the scepter, the wand and the staff all work one way.
            if party.wisdom + rng.rnd(10) > 8 {
                v.stage = .charm(item)
            } else {
                v.said = ["IT BLEW UP!!! I DON'T THINK YOU KNOW HOW TO USE IT CORRECTLY, SIRE."]
                useUp(item)
            }
        case 43, 44:
            useUp(item)
            if rng.rnd(2) == 0 {
                v.said = ["IT WAS A STRENGTH POTION!"]
                party.strength += 3
            } else {
                v.said = ["WHATEVER THE POTION WAS, IT'S GONE BAD. TWO MEN DIED AND SEVERAL OTHERS ARE SICK. WHAT NOW, SIR?"]
                party.men = max(party.men - 2, 0)
                if isLost { news.append(Expedition.allLost) }
            }
        case 45:
            mount = .rug                   // 8160: the rug isn't used up
            return
        default:
            v.said = ["USING YOUR \(item.name) DIDN'T HAVE ANY USEFUL EFFECT."]
        }
        visit = v
    }

    /// The magic panels' answers.
    mutating func useMagic(_ action: Action, in v: inout Visit) {
        switch (v.stage, action) {
        case (.amulet, .accept):
            party.strength = party.rolledStrength           // 8105
            useUp(Item(39))
            v.stage = .finished
        case (.amulet, .decline), (.charm, .saveIt):
            v.stage = .finished
        case let (.charm(item), .increaseSpeed), let (.charm(item), .increaseCharisma),
             let (.charm(item), .increaseWisdom):
            switch action {
            case .increaseSpeed: party.speed += 3
            case .increaseCharisma: party.charisma += 3
            default: party.wisdom += 3
            }
            useUp(item)
            v.stage = .finished
        default:
            break
        }
    }

    private mutating func useUp(_ item: Item) {
        party.inventory[item] = max((party.inventory[item] ?? 0) - 1, 0)
    }
}
