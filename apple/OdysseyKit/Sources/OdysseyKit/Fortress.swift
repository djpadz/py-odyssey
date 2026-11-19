/// CAVERN APVENTURE, on the Isle of Lapour (lines 20000-23010): the way up to the
/// Caliph's fortress, barred three times over, and the end of the quest.

/// What bars the way (21000-21800), what gets past it cleanly (U1, U2), and what gets
/// past it at a cost in men (U3, U4).
public enum Hazard: Int, Sendable, Codable, CaseIterable {
    case lava, slime, thorns, gate, medusa, fire, portal, labyrinth, spiders

    public var words: String {
        switch self {
        case .lava: "A STREAM OF LAVA IN A NARROW FISSURE. FLAMES AND FUMES ARE RISING FROM IT."
        case .slime: "A RIVER OF CORROSIVE GREEN SLIME."
        case .thorns: "A DENSE FOREST OF POISONOUS THORNS."
        case .gate: "AN ENORMOUS STONE GATE WITH A SMALL WINDOW IN IT."
        case .medusa: "A MEDUSAE UP AHEAD. TO LOOK UPON ONE UP CLOSE IS DEATH."
        case .fire: "A SHIMMERING CURTAIN OF FIRE."
        case .portal: "A SPIKE STUDDED, IRON SHEATHED PORTAL WITH SEVERAL LARGE LOCKS."
        case .labyrinth: "A LABYRINTH WITH NUMEROUS TRAPS."
        case .spiders: "SEVERAL GIGANTIC SPIDERS AHEAD IN A NARROW PASSAGE, TOO CONFINED TO FIGHT."
        }
    }

    var clean: [Int] {
        switch self {
        case .lava, .slime: [45]                 // the flying rug
        case .thorns: [33, 11]                   // a torch, an oil lamp
        case .gate: [32]                         // the monkey
        case .medusa: [34]                       // mirrors
        case .fire: [46, 47]                     // the wand, the staff
        case .portal: [38]                       // the golden key
        case .labyrinth: [36, 40]                // the old map, the scroll
        case .spiders: [43, 44]                  // a potion
        }
    }

    var costly: [Int] {
        switch self {
        case .lava: [31]                         // a plank
        case .slime: [3]                         // the small boat
        case .thorns: [4]                        // a machete
        case .gate: [35]                         // a crowbar
        case .medusa: [25, 26]                   // crossbows, long bows
        case .fire: [13]                         // water jugs
        case .portal: [2]                        // a lock pick
        case .labyrinth: []
        case .spiders: [18]                      // a net
        }
    }

    var passed: String {
        switch self {
        case .lava: "WE MADE IT ACROSS, SIRE, BUT THE CARPET CAUGHT FIRE AND BURNED."
        case .slime: "WE MADE IT ACROSS, SIR, BUT THE CARPET DISSOLVED AS WE LANDED."
        case .thorns: "THE THORN FOREST BURNED NICELY."
        case .gate: "THE MONKEY GOT THE DOOR OPEN."
        case .medusa: "WITH THE MIRRORS, WE GOT CLOSE ENOUGH TO KILL IT."
        case .fire: "THE FIRE WAS BLOWN AWAY."
        case .portal: "THE PORTAL SILENTLY OPENED."
        case .labyrinth: "WE MADE IT THROUGH SAFELY."
        case .spiders: "THE POTION TEMPORARILY TURNED EVERYONE INVISIBLE AND WE GOT BY."
        }
    }

    var cost: String {
        switch self {
        case .lava: "SUCCUMBED TO THE FUMES AND FELL IN."
        case .slime: "FELL IN AS THE BOAT DISSOLVED."
        case .thorns: "WERE STABBED AND DIED IN AGONY."
        case .gate: "WERE CRUSHED WHEN THE DOOR FELL."
        case .medusa: "WERE TURNED TO STONE AS HER GAZE CAUGHT THEM WHILE THEY FIRED."
        case .fire: "WERE BURNED."
        case .portal: "WERE IMPALED WHEN THE PORTAL FELL OPEN."
        case .labyrinth: "WERE KILLED BY THE TRAPS."
        case .spiders: "WERE STUNG AND DIED HORRIBLY."
        }
    }
}

public struct Fortress: Sendable, Codable {
    /// The three things in the way (Z6, Z7, Z9).
    public let hazards: [Hazard]
    /// How far up: 0 at the landing, 1-3 at each hazard in turn.
    public internal(set) var stage = 0
    /// Whether the hazard at this stage still bars the way (U1).
    public internal(set) var blocked = false
    public internal(set) var said: [String] = []
    /// Asked whether to retreat (20050).
    public internal(set) var askingRetreat = false

    public var hazard: Hazard? { blocked && stage > 0 ? hazards[stage - 1] : nil }
}

/// How the quest ended (22000-23010).
public struct Ending: Sendable, Codable, Equatable {
    public let won: Bool
    public let words: [String]
    public let men: Int, recruited: Int, gold: Int, goods: Int, killed: Int, ships: Int, score: Int
    public let alignment: String
}

extension Expedition {
    /// 20000: ashore on Lapour, three hazards between the party and the fortress.
    /// (The original can choose the third the same as one of the others.)
    mutating func landOnLapour() {
        var hazards: [Hazard] = []
        while hazards.count < 3 {
            let h = Hazard(rawValue: rng.rnd(9))!
            if !hazards.contains(h) { hazards.append(h) }
        }
        fortress = Fortress(hazards: hazards)
    }

    /// 20020-20024, 20900: A approaches. A hazard in the way is forced at the cost of
    /// half the men (at least five).
    public mutating func approach() {
        guard var f = fortress, !isLost, ending == nil else { return }
        f.said = []
        f.askingRetreat = false
        defer { if fortress != nil { fortress = f } }
        if f.blocked {
            let n = max(party.men / 2, 5)
            party.men = max(party.men - n, 0)
            if isLost {
                news.append("I AM SORRY TO REPORT, MY LEIGE, THAT ALL THE MEMBERS OF YOUR PARTY WERE KILLED. BETTER LUCK NEXT TIME, SIRE.")
                return
            }
            f.said = ["WE MADE IT PAST THE HAZARD, SIR, BUT \(n) MEN WERE KILLED."]
            f.blocked = false
            return
        }
        if f.stage == 3 {
            theEnd()
            return
        }
        f.stage += 1
        f.blocked = true
        f.said = ["WE MADE IT THIS FAR, BUT WE'RE BLOCKED BY \(f.hazards[f.stage - 1].words)"]
    }

    /// 20070-20090, 21025: use something on what bars the way.
    public mutating func useAtFortress(_ item: Item) {
        guard var f = fortress, ending == nil, (party.inventory[item] ?? 0) > 0 else { return }
        f.said = []
        f.askingRetreat = false
        defer { fortress = f }
        guard let h = f.hazard, h.clean.contains(item.id) || h.costly.contains(item.id) else {
            f.said = ["USING YOUR \(item.name) SERVED NO USEFUL PURPOSE. NOW WHAT?"]
            return
        }
        party.inventory[item] = (party.inventory[item] ?? 0) - 1
        f.blocked = false
        if h.clean.contains(item.id) {
            f.said = [h.passed]
        } else {
            let n = 2 + rng.rnd(3)
            party.men = max(party.men - n, 0)
            f.said = ["MOST OF THE TROOP MADE IT, SIRE. \(n) MEN \(h.cost)"]
            if isLost {
                news.append("I AM SORRY TO REPORT, MY LEIGE, THAT ALL THE MEMBERS OF YOUR PARTY WERE KILLED. BETTER LUCK NEXT TIME, SIRE.")
            }
        }
    }

    /// R: "YOU WISH TO RETREAT?" (20050)
    public mutating func retreat() {
        guard ending == nil else { return }
        fortress?.askingRetreat = true
        fortress?.said = []
    }

    /// 20055: back to the ship, if so.
    public mutating func confirmRetreat(_ yes: Bool) {
        guard fortress?.askingRetreat == true else { return }
        fortress?.askingRetreat = false
        guard yes else { return }
        returnToShip()
        voyage?.said = ["BACK TO THE SHIP!"]
    }

    /// 22000-23010: into the fortress, and the reckoning.
    private mutating func theEnd() {
        let won = hasOrb
        var words: [String]
        if won {
            words = ["YOU MADE IT!!!!!",
                     "SINCE YOU HAVE THE HIGH ONE'S ORB, THE CALIPH'S MEN HAVE DESERTED TO YOUR SIDE. THE CALIPH HAS FLED. YOU ARE THE NEW HIGH ONE OF THE REALM."]
        } else {
            words = ["YOU MADE IT INTO THE CASTLE. WITHOUT THE HIGH ONE'S ORB, HOWEVER, THE CALIPH'S MEN FOUGHT AND DESTROYED YOUR FORCE."]
            party.men = 0
        }
        // 22005: a tenth of what everything carried is worth (gold and food included),
        // then a tenth of the gold again, ten for every inhabitant killed, five for
        // every ship sunk, less twenty for every man lost.
        let goods = party.inventory.reduce(0) { $0 + $1.value * $1.key.listPrice / 10 }
        let score = party.gold / 10 + goods + killed * 10 - (recruited - party.men) * 20 + shipsSunk * 5
        let a = party.alignment
        let alignment = a <= -30 ? "A BLACKHEARTED FIEND." : a <= -20 ? "QUITE EVIL MINDED."
            : a <= 20 ? "BALANCED BETWEEN GOOD AND EVIL." : a <= 40 ? "A KIND AND GENEROUS LEADER." : "A VIRTUAL SAINT AMONG MEN."
        words += ["YOU ENDED THE QUEST WITH:",
                  "- \(party.men) MEN OUT OF \(recruited) RECRUITED.",
                  "- \(party.gold) GOLD QUADROONS.",
                  "- \(goods)0 QUADROONS WORTH OF GOODS.",
                  "- YOU ALSO KILLED \(killed) OF THE REALM'S INHABITANTS.",
                  "- AND SANK \(shipsSunk) SHIPS.",
                  "YOUR COMPOSITE SCORE IS \(score)0",
                  "(INCIDENTALLY, YOUR ALIGNMENT FACTOR INDICATES YOU'RE \(alignment))"]
        ending = Ending(won: won, words: words, men: party.men, recruited: recruited, gold: party.gold, goods: goods,
                        killed: killed, ships: shipsSunk, score: score, alignment: alignment)
    }
}
