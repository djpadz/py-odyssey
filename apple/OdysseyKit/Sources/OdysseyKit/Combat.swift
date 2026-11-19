/// The original's twenty monsters (MN$). The first ten can be bargained with.
public struct Monster: Hashable, Sendable {
    public let kind: Int                     // 1...20, the original's MT

    private static let names = [
        "GHOULS", "LYCANTHROPES", "GIANT OGRES", "GORGONS", "VAMPIRES", "WEREWOLVES", "MUMMIES", "ORCS",
        "CYCLOPS", "GOBLINS", "GIANT SNAKES", "SANDSERPENTS", "DRAGONS", "MINOTAURS", "FIRE DEMONS",
        "ALLOSAURS", "ROCS", "PTERIDACTYLS", "HARPIES", "GARGOYLES",
    ]

    public init(kind: Int) {
        precondition((1...20).contains(kind))
        self.kind = kind
    }

    public var name: String { Monster.names[kind - 1] }
    /// Kinds 1-10 understand gold (the original tests I<11, which looks meant for MT).
    var reasons: Bool { kind < 11 }
    /// The rocs, pterodactyls, harpies and gargoyles fly in.
    public var flies: Bool { kind > 16 }
}

/// A fight (lines 6000-6980). "We" are the party, "they" the monsters.
public struct Battle: Sendable, Equatable {
    public let monster: Monster
    public let ourNumber: Int                // FM at the start
    public let theirNumber: Int              // MN
    public internal(set) var ourLosses = 0   // CK
    public internal(set) var theirLosses = 0 // MK
    /// Arms and armour (CW, MW), strength and experience (ST, MST), speed (SP, MSP).
    public let ourArms: Int, theirArms: Int
    public let ourStrength: Int, theirStrength: Int
    let ourSpeed: Int, theirSpeed: Int
    /// Surprise rounds left (SR) and who was surprised: `theyWereSurprised` is UT.
    var surprise: Int
    let theyWereSurprised: Bool
    /// The last round's luck and totals, for the tally.
    public internal(set) var lastRound: (ourLuck: Int, theirLuck: Int, ourTotal: Int, theirTotal: Int)?

    public static func == (a: Battle, b: Battle) -> Bool {
        a.monster == b.monster && a.ourLosses == b.ourLosses && a.theirLosses == b.theirLosses
            && a.theirNumber == b.theirNumber && a.surprise == b.surprise
    }

    public var ourStanding: Int { ourNumber - ourLosses }
    public var theirStanding: Int { theirNumber - theirLosses }

    init(monster: Monster, party: Party, theyWereSurprised: Bool, surprise: Int, rng: inout SeededRandom) {
        self.monster = monster
        ourNumber = party.men
        theirNumber = party.men + rng.rnd(10) - 5
        theirArms = 2 + rng.rnd(4)
        theirSpeed = 2 + rng.rnd(6)
        ourStrength = party.strength + party.experience / max(party.men, 1)
        theirStrength = 3 + rng.rnd(max(ourStrength - 1, 1))
        ourSpeed = party.speed
        // Weapons count 1-6 (battle axe to long bow), armour 1-4 (leather to plate);
        // the party fights with the average of what it carries.
        var arms = 0, pieces = 0
        for (item, n) in party.inventory {
            switch item.id {
            case 21...26: arms += n * (item.id - 20); pieces += n
            case 27...30: arms += n * (item.id - 26); pieces += n
            default: break
            }
        }
        ourArms = arms / max(pieces, 1)
        self.theyWereSurprised = theyWereSurprised
        self.surprise = surprise
    }

    /// Lines 6100-6160.
    public var sizeUp: String {
        var text = "THERE ARE \(theirNumber) OF THEM. THEY HAVE "
        let s = theirStrength
        if s == 3 && monster.kind <= 9 { text += "NO ARMOR OR WEAPONS TO SPEAK OF." }
        if monster.kind > 9 {
            if s == 3 { text += "LIGHT ARMOR AND WEAPONS." }
            if s == 4 { text += "MODERATE ARMOR AND WEAPONS." }
            if s == 5 { text += "HEAVY SCALE ARMOR AND WEAPONS." }
            if s > 5 { text += "MASSIVE ARMOR AND POWERFUL WEAPONS!" }
        } else {
            if s == 4 { text += "LEATHER ARMOR AND SHORT SWORDS." }
            if s == 5 { text += "LIGHT ARMOR AND BROAD SWORDS." }
            if s == 6 { text += "CHAIN MAIL, SPEARS, AND AXES." }
            if s > 6 { text += "PLATE ARMOR, BROAD SWORDS, AND SPEARS." }
        }
        text += theyWereSurprised ? " THEY" : " YOU"
        text += [" WERE READY FOR THE ATTACK.", " WERE SURPRISED BY THE ATTACK.", " WERE COMPLETELY UNPREPARED."][surprise]
        return text
    }

    public var isWon: Bool { theirStanding < 1 }
    public var isLost: Bool { ourStanding < 1 }

    /// Lines 6240-6280: one round. Luck is a d20 each, unless surprise fixes it at 5.
    mutating func round(rng: inout SeededRandom) {
        var i = rng.rnd(20), j = rng.rnd(20)
        if surprise > 0 && theyWereSurprised { j = 5 }
        if surprise > 0 && !theyWereSurprised { i = 5 }
        let ourLuck = i, theirLuck = j
        if surprise > 0 { surprise -= 1 }
        i += ourStanding * (ourArms + ourStrength)
        j += theirStanding * (theirArms + theirStrength)
        lastRound = (ourLuck, theirLuck, i, j)
        var k = (i - j) / 3
        if k > 3 && k > theirStanding / 2 && theirStanding > 2 { k = theirStanding / 2 }
        if i > j && k == 0 { k = 1 }
        if k > 0 {
            theirLosses += k
            if rng.rnd(3) == 0 { ourLosses += 1 }
        }
        if k < 0 && k > -4 { k = -1 }
        if k < -3 { k = -2 }
        if k < 0 {
            ourLosses -= k
            if rng.rnd(2) == 1 { theirLosses += 2 }
        }
        theirLosses = min(theirLosses, theirNumber)
        ourLosses = min(ourLosses, ourNumber)
    }

    /// Lines 6800-6830: try to run. Returns what was said and whether we got away.
    func run(rng: inout SeededRandom) -> (words: [String], away: Bool) {
        var words = ["YOUR SPEED IS \(ourSpeed) WHILE THEIRS IS \(theirSpeed)."]
        if ourSpeed > theirSpeed || (ourSpeed == theirSpeed && rng.rnd(2) == 1) {
            return (words + ["YOU GOT AWAY!"], true)
        }
        if rng.rnd(4) == 0 {
            return (words + ["THEY DIDN'T CHASE YOU FOR SOME REASON.", "YOU GOT AWAY!"], true)
        }
        words.append("YOU DIDN'T GET AWAY.")
        return (words, false)
    }
}
