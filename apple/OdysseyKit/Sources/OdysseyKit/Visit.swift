/// What the player can do at a site or on the road. Each matches one of the original's keys.
public enum Action: Hashable, Sendable {
    case use(Item)              // U: the right key or tool opens the way, or saves trapped men
    case enter                  // E: into a hut
    case leave                  // L
    case search                 // search further
    case take                   // G: take what is on the altar
    case leaveIt                // ...or leave it
    case open                   // O: open a chest
    case goOn                   // ...or go on
    case attack                 // A
    case slipAway               // leave the monsters be
    case offerGold, offerFood   // O, then G or F
    case fight, run             // F or R, each round
    case accept, decline        // Y/N to the hut's offer
    case carryOn                // abandon the men in the pit
    case ignore                 // I: pass the caravan or the warriors by
    case buy                    // B: from the caravan
    case requestAid             // R: of the wizard
    case beFriendly             // to the warriors
    case wait                   // W: ...or wait cautiously
    case increaseSpeed          // 1-3: what magic may do
    case increaseCharisma
    case increaseWisdom
    case saveIt                 // 4
}

/// A visit to a temple, ruin, castle, tomb or hut (lines 9000-9915), with the
/// monsters, chests and pits found inside; or something met on the road between
/// them (725-3400), when `site` is nil.
public struct Visit: Sendable {
    public enum Stage: Sendable, Equatable {
        case door                           // locked; find the right thing to use
        case hutDoor                        // enter or leave?
        case hutOffer(Item, price: Int)
        case searching                      // search further or leave?
        case altar(Item)
        case chest
        case pit(trapped: Int)
        case monstersAhead(Monster)
        case offering(Monster)
        case battle(Battle)
        case spoils(Foe)                    // the beaten monsters' chest
        case finished                       // nothing more here: leave
        // On the road (Road.swift).
        case caravan
        case wizard(good: Bool)             // a wizard, or a warlock
        case warriors
        case trapped(Trap, men: Int)
        case obstacle(Obstacle)
        // Magic (Commands.swift).
        case amulet
        case charm(Item)                    // the lamp, scepter, wand or staff
    }

    /// Where this happens: a site, or nil on the road.
    public let site: Site?
    /// The site's cell, the party's cell on the road, or the cell an obstacle bars.
    public let cell: Cell
    public internal(set) var stage: Stage
    /// What has just happened, oldest first.
    public internal(set) var said: [String]
    /// Searches left once inside (Z1); nil until the party gets in.
    var searchesLeft: Int?
    /// The items that open this site's door (U1-U3).
    let opens: Set<Item>

    public var isInside: Bool { searchesLeft != nil }

    /// Whether the party must see this through before walking on. At a door it may
    /// walk away, and likewise from an obstacle.
    public var holdsParty: Bool {
        if site != nil { return isInside }
        if case .obstacle = stage { return false }
        return true
    }

    /// Whether the player may use something they carry here.
    public var canUseItems: Bool {
        switch stage {
        case .door, .pit, .trapped, .obstacle: true
        default: false
        }
    }

    /// The question put to the player now.
    public var question: String {
        switch stage {
        case .door: "WHAT WILL YOU DO?"
        case .hutDoor: "DO YOU WISH TO ENTER OR LEAVE?"
        case let .hutOffer(_, price): "FOR \(price) GOLD PIECES. INTERESTED?"
        case .searching: "YOU HAVEN'T FOUND ANYTHING. DO YOU WANT TO SEARCH FURTHER OR LEAVE NOW?"
        case let .altar(item): "YOU'VE COME INTO A ROOM WITH AN ALTAR IN IT. ON THE ALTAR IS A \(item.name). DO YOU WANT TO GET IT OR LEAVE IT?"
        case .chest: "YOU'VE FOUND A LARGE WOODEN CHEST. DO YOU WANT TO OPEN IT OR GO ON?"
        case let .pit(n): "\(n) OF YOUR MEN FELL INTO THE PIT. WHAT DO YOU WANT TO DO?"
        case let .monstersAhead(m): "YOU CAN SEE SOME \(m.name) AHEAD. THEY HAVEN'T SEEN YOU YET. DO YOU WANT TO ATTACK, LEAVE, OR OFFER SOMETHING?"
        case .offering: "DO YOU WANT TO OFFER GOLD OR FOOD?"
        case .battle: "WILL YOU RUN OR FIGHT?"
        case .spoils: "IT LOOKS LIKE THEY HAVE A CHEST OF SOME SORT. WILL YOU OPEN IT OR LEAVE?"
        case .finished: site == nil ? "" : "IT LOOKS LIKE THERE IS NOTHING ELSE IN HERE. YOU'D BETTER LEAVE NOW."
        case .caravan: "YOU HAVE ENCOUNTERED A SMALL CARAVAN OF MERCHANTS. WILL YOU IGNORE THEM, ATTACK THEM, OR BUY SOMETHING FROM THEM?"
        case let .wizard(good): "YOU'VE COME UPON A WANDERING \(good ? "WIZARD" : "WARLOCK"). HE IS ACCOMPANIED BY SEVERAL APPRENTICES. WILL YOU ATTACK, REQUEST AID, OR LEAVE."
        case .warriors: "DO YOU WANT TO ATTACK, BE FRIENDLY, IGNORE THEM, OR WAIT CAUTIOUSLY?"
        case let .trapped(trap, n): "\(n) \(trap.words). WHAT DO YOU WANT TO DO?"
        case let .obstacle(obstacle): "\(obstacle.words) WHAT DO YOU WANT TO DO?"
        case .amulet: "THE AMULET HAS THE POWER TO HEAL WOUNDS AND RESTORE STRENGTH. IT CAN BE USED ONLY ONCE. SHALL WE USE IT NOW (Y/N)?"
        case .charm: "YOU MAY: 1) INCREASE SPEED 2) INCREASE CHARISMA 3) INCREASE WISDOM 4) SAVE IT. WHICH?"
        }
    }

    /// The choices on offer, besides using something (see `canUseItems`).
    public var actions: [Action] {
        switch stage {
        case .door: [.leave]
        case .hutDoor: [.enter, .leave]
        case .hutOffer: [.accept, .decline]
        case .searching: [.search, .leave]
        case .altar: [.take, .leaveIt]
        case .chest, .spoils: [.open, .goOn]
        case .pit: [.carryOn]
        case .monstersAhead: [.attack, .slipAway, .offerGold, .offerFood]
        case .offering: [.offerGold, .offerFood]
        case .battle: [.fight, .run]
        case .finished: [.leave]
        case .caravan: [.ignore, .attack, .buy]
        case .wizard: [.attack, .requestAid, .leave]
        case .warriors: [.attack, .beFriendly, .ignore, .wait]
        case .trapped: [.carryOn]
        case .obstacle: [.leave]
        case .amulet: [.accept, .decline]
        case .charm: [.increaseSpeed, .increaseCharisma, .increaseWisdom, .saveIt]
        }
    }

    init(site: Site, cell: Cell) {
        self.site = site
        self.cell = cell
        said = [site.entrance]
        stage = site == .hut ? .hutDoor : .door
        opens = switch site {
        case .temple: [Item(2)]                     // lock pick
        case .ruin: [Item(11), Item(33)]            // oil lamp, torch
        case .castle: [Item(37), Item(2)]           // brass key, lock pick
        case .tomb: [Item(35), Item(8)]             // crowbar, shovel
        case .hut, .city: []
        }
    }

    /// Something met on the road.
    init(cell: Cell, stage: Stage, said: [String] = []) {
        site = nil
        self.cell = cell
        self.stage = stage
        self.said = said
        opens = []
    }
}

extension Expedition {
    /// Step up to the site in this cell, if there is one still open.
    mutating func arrive() {
        guard visit == nil, let site, site != .city, !island.isSealed(cell) else { return }
        visit = Visit(site: site, cell: cell)
    }


    /// Do something at the site.
    public mutating func act(_ action: Action) {
        guard var v = visit else { return }
        v.said = []
        perform(action, in: &v)
        if party.men <= 0 && v.stage != .finished { lose(&v) }
        visit = v
        // On the road, an ending with nothing to say needs no leave-taking.
        if v.stage == .finished && (action == .leave || (v.site == nil && v.said.isEmpty)) {
            visit = nil
            if v.site == nil {
                arrive()                    // a site may wait behind the encounter
            } else if v.isInside {
                island.seal(v.cell)
                news.append("THE ENTRANCE SEALED BEHIND YOU AS YOU LEFT.")
            }
        }
    }

    private mutating func perform(_ action: Action, in v: inout Visit) {
        switch (v.stage, action) {

        // The door (9010-9020, 760, 8000, 9700).
        case let (.door, .use(item)):
            if v.opens.contains(item) {
                v.said = ["YOU GOT IN. IT LOOKS DESERTED."]
                v.searchesLeft = 6
                searchOn(&v)
            } else {
                v.said = ["USING YOUR \(item.name) DIDN'T HAVE ANY USEFUL EFFECT."]
            }
        case (.door, .leave), (.hutDoor, .leave):
            v.stage = .finished

        // Huts (9500-9570): a witch, a hermit or a monk with something to sell.
        case (.hutDoor, .enter):
            v.searchesLeft = 0
            let price = 300 + rng.rnd(300)
            let item: Item
            switch rng.rnd(3) {
            case 0:
                v.said = ["THE HUT IS INHABITED BY AN OLD CRONE WHO CLAIMS TO BE A POWERFUL WITCH. SHE HAS OFFERED TO SELL YOU A MAGIC LAMP"]
                item = rng.rnd(2) == 1 ? Item(41) : Item(11)
            case 1:
                v.said = ["A FILTHY HERMIT LIVES IN THE HUT. HE CLAIMS TO BE AN ORACLE. HE OFFERS TO SELL YOU A POWERFUL MAGIC POTION"]
                let j = rng.rnd(4)
                item = j > 1 ? Item(41 + j) : Item(13)
            default:
                v.said = ["A MONK LIVES IN THE HUT. HE CLAIMS TO HAVE A BOOK OR SCROLL CONTAINING ANCIENT AND MIGHTY SPELLS THAT HE WILL SELL YOU"]
                item = rng.rnd(2) == 1 ? Item(40) : Item(12)
            }
            v.stage = .hutOffer(item, price: price)
        case let (.hutOffer(item, price), .accept):
            let gold = party.gold
            if gold >= price {
                party.gold -= price
                gain(item)
                v.said = ["YOU NOW HAVE THE \(item.name)."]
            } else if gold < price / 2 {
                v.said = ["YOU ONLY HAVE \(gold) GOLD PIECES! I THINK YOU HAD BETTER LEAVE."]
            } else {
                v.said = ["YOU ONLY HAVE \(gold) GOLD PIECES.", "I GUESS THAT WILL DO."]
                party.gold = 0
                gain(item)
            }
            v.stage = .finished
        case (.hutOffer, .decline):
            v.stage = .finished

        // Searching (9710-9762).
        case (.searching, .search):
            if rng.rnd(2) == 1 {
                searchOn(&v)
                return
            }
            switch rng.rnd(4) {
            case 0: v.stage = .altar(Item(39 + rng.rnd(9)))
            case 1: meetMonsters(&v)
            case 2: v.stage = .chest
            default: pitTrap(&v)
            }
        case (.searching, .leave):
            if rng.rnd(3) != 0 {
                v.stage = .finished
            } else {
                pitTrap(&v)
            }
        case let (.altar(item), .take):
            gain(item)
            v.said = ["OK, YOU GOT THE \(item.name)."]
            v.stage = .finished
        case (.altar, .leaveIt), (.chest, .goOn):
            searchOn(&v)
        case (.chest, .open):
            if rng.rnd(4) == 0 {
                if rng.rnd(2) == 1 {
                    v.said = ["A POISONED NEEDLE WAS EJECTED FROM THE LOCK. THE MAN OPENING IT WAS KILLED."]
                    party.men -= 1
                } else {
                    v.said = ["WHEN IT WAS OPENED, THE CHEST RELEASED A CLOUD OF POISONOUS VAPOR. NO ONE WAS KILLED, BUT YOU WERE ALL WEAKENED."]
                    searchOn(&v)
                    return
                }
            }
            let gold = 500 + rng.rnd(500)
            v.said.append("CONGRATULATIONS! THE CHEST CONTAINED \(gold) GOLD QUADROONS.")
            party.gold += gold
            v.stage = .finished

        // The pit (9760-9762, 8000-8017): a rope, a net or a spare sail pulls men out.
        case let (.pit(trapped), .use(item)):
            if [7, 19, 18].contains(item.id) {
                rescue(trapped, with: item, in: &v)
                searchOn(&v)
            } else {
                v.said = ["USING YOUR \(item.name) DIDN'T HAVE ANY USEFUL EFFECT."]
            }
        case (.pit, .carryOn):
            searchOn(&v)

        // Monsters (1200-1370).
        case let (.monstersAhead(m), .attack):
            startBattle(.monsters(m), theyWereSurprised: true, surprise: rng.rnd(3), in: &v)
        case let (.monstersAhead(m), .slipAway):
            if rng.rnd(4) != 0 {
                searchOn(&v)
            } else {
                v.said = ["YOU MADE SOME NOISE. THEY'RE ATTACKING!"]
                startBattle(.monsters(m), theyWereSurprised: false, surprise: 0, in: &v)
            }
        case let (.monstersAhead(m), .offerGold), let (.offering(m), .offerGold):
            if !m.reasons {
                v.said = ["THEY ARE TOO STUPID TO BE INTERESTED IN TREASURE. THEY ARE ATTACKING."]
                startBattle(.monsters(m), theyWereSurprised: false, surprise: 1, in: &v)
            } else if party.alignment < 0 {
                let joined = party.charisma / 2 + rng.rnd(3)
                party.men += joined
                party.gold = max(party.gold - 50, 0)
                v.said = ["\(joined) OF THEM ACCEPTED YOUR OFFER. FINDING YOUR GROUP TO BE KINDRED SOULS, THEY WILL JOIN IN YOUR QUEST."]
                searchOn(&v)
            } else {
                party.gold = max(party.gold - 50, 0)
                v.said = ["THEY TOOK THE GOLD AND ARE ATTACKING ANYWAY!"]
                startBattle(.monsters(m), theyWereSurprised: false, surprise: 1, in: &v)
            }
        case let (.monstersAhead(m), .offerFood), let (.offering(m), .offerFood):
            if m.reasons {
                v.said = ["THEY WERE ENRAGED BY YOUR INSULTING OFFER AND ARE ATTACKING!"]
                startBattle(.monsters(m), theyWereSurprised: false, surprise: 1, in: &v)
            } else {
                party.foodPacks = max(party.foodPacks - 5, 0)
                v.said = ["THEY ATE THE FOOD AND WANDERED OFF."]
                searchOn(&v)
            }

        // Battle (6200-6980).
        case (.battle(var b), .fight):
            b.round(rng: &rng)
            settle(b, in: &v)
        case (.battle(var b), .run):
            let (words, away) = b.run(rng: &rng)
            v.said = words
            if away {
                party.men -= b.ourLosses
                v.stage = .finished          // the original leaves the ruin after a getaway
            } else {
                b.round(rng: &rng)
                settle(b, in: &v)
                v.said.insert(contentsOf: words, at: 0)
            }
        case let (.spoils(foe), .open):
            openSpoils(of: foe, in: &v)
        case (.spoils, .goOn):
            searchOn(&v)

        case (.finished, .leave):
            break
        default:
            onTheRoad(action, in: &v)
        }
    }

    /// 9710: another search, unless the searches are used up. (On the road there are
    /// none, so this ends the encounter.)
    mutating func searchOn(_ v: inout Visit) {
        let left = (v.searchesLeft ?? 0) - 1
        v.searchesLeft = left
        v.stage = left < 0 ? .finished : .searching
    }

    /// 8000-8017: some of the trapped men are saved with the right thing.
    mutating func rescue(_ trapped: Int, with item: Item, in v: inout Visit) {
        let saved = min(rng.rnd(trapped) + 2, trapped)
        party.men += saved
        v.said = ["CONGRATULATIONS! YOU SAVED \(saved) MEN WITH YOUR \(item.name)."]
        if trapped > saved { v.said.append("THE OTHER \(trapped - saved) DIED, HOWEVER.") }
    }

    private mutating func pitTrap(_ v: inout Visit) {
        let n = min(1 + rng.rnd(3), party.men)
        party.men -= n
        v.said.append("PIT TRAP!")
        v.stage = .pit(trapped: n)
        if isLost { lose(&v) }
    }

    /// 1200-1210. Only on the road (Z3=0) do the four flying kinds come.
    mutating func meetMonsters(_ v: inout Visit) {
        let m = Monster(kind: 1 + rng.rnd(v.site == nil ? 20 : 16))
        if m.flies {
            v.said.append("TAKE COVER! A BUNCH OF \(m.name) ARE FLYING THIS WAY!")
        }
        if rng.rnd(2) == 0 {
            v.said.append("YOU'VE BEEN ATTACKED BY \(m.name)!")
            startBattle(.monsters(m), theyWereSurprised: false, surprise: rng.rnd(3), in: &v)
        } else {
            v.stage = .monstersAhead(m)
        }
    }

    mutating func startBattle(_ foe: Foe, theyWereSurprised: Bool, surprise: Int, in v: inout Visit) {
        let b = Battle(foe: foe, party: party, theyWereSurprised: theyWereSurprised, surprise: surprise, rng: &rng)
        v.said.append(b.sizeUp)
        settle(b, in: &v)
    }

    /// After a round: fight on, or count the dead.
    private mutating func settle(_ b: Battle, in v: inout Visit) {
        if b.isLost {
            party.men = 0
            lose(&v)
        } else if b.isWon {
            party.experience += 5
            party.men -= b.ourLosses
            if b.foe == .merchants {
                caravanSpoils(&v)
                return
            }
            v.said.append("CONGRATULATIONS! YOU KILLED ALL OF THE \(b.foe.name).")
            if v.site == nil && rng.rnd(2) == 0 {
                v.said.append("IT LOOKS LIKE THEY HAD NO TREASURE.")
                v.stage = .finished
            } else {
                v.stage = .spoils(b.foe)
            }
        } else {
            v.stage = .battle(b)
        }
    }

    /// 4000-4065: the monsters' chest. A wizard's holds magic more often.
    private mutating func openSpoils(of foe: Foe, in v: inout Visit) {
        if rng.rnd(5) == 0 {
            v.said.append("SOME POISONOUS SPORES WERE RELEASED FROM THE CHEST. YOUR PARTY WAS WEAKENED, BUT NO ONE WAS KILLED.")
            party.strength = max(party.strength - 1, 1)
            if rng.rnd(4) == 0 {
                v.said.append("THERE IS NOTHING ELSE IN THE CHEST.")
                searchOn(&v)
                return
            }
        }
        let wizards = foe == .wizards || foe == .warlocks
        if (rng.rnd(5) != 0 && !wizards) || rng.rnd(2) == 1 || rng.rnd(4) != 0 {
            let gold = 500 + rng.rnd(500)
            v.said.append("THERE ARE \(gold) QUADROONS OF GOLD IN THE CHEST!")
            party.gold += gold
        } else {
            let item = Item(39 + rng.rnd(9))
            gain(item)
            v.said.append("THE CHEST CONTAINED A \(item.name).")
            if rng.rnd(3) != 0 {
                let gold = 700 + rng.rnd(1000)
                v.said.append("THERE IS ALSO \(gold) QUADROONS OF GOLD!")
                party.gold += gold
            } else {
                v.said.append("THERE IS NOTHING ELSE IN THE CHEST.")
            }
        }
        searchOn(&v)
    }

    mutating func lose(_ v: inout Visit) {
        party.men = 0
        v.stage = .finished
        news.append(Expedition.allLost)
    }

    mutating func gain(_ item: Item, _ quantity: Int = 1) {
        party.inventory[item, default: 0] += quantity
    }
}
