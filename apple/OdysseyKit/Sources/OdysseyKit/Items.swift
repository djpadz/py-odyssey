/// The original's 49 items (G1$, G2$, G3$), with their weights (GW) and list prices (AP).
public struct Item: Hashable, Sendable, Comparable, CustomStringConvertible {
    public let id: Int

    public init(_ id: Int) {
        precondition((1...49).contains(id), "no item \(id)")
        self.id = id
    }

    public static let foodPack = Item(1)
    public static let contract = Item(5)
    public static let quadroon = Item(48)
    public static let ship = Item(49)

    private static let names = [
        "FOOD PACK", "LOCK PICK", "SMALL BOAT", "MACHETE", "CONTRACT", "IRON HOOK", "ROPE", "SHOVEL",
        "BACKPACK", "HELMET", "OIL LAMP", "OLD BOOK", "WATER JUG", "FRUIT", "COMPASS", "SEXTANT", "DAGGER",
        "NET", "SPARE SAIL", "HORSE", "BATTLE AXE", "BROADSWORD", "SPEAR", "HAND LANCE", "CROSSBOW",
        "LONG BOW", "LEATHER", "SHIELD", "CHAIN MAIL", "PLATE MAIL", "10' PLANK", "MONKEY", "TORCH", "MIRROR",
        "CROWBAR", "OLD MAP", "BRASS KEY", "GOLDEN KEY", "AMULET", "SCROLL", "MAGIC LAMP", "SCEPTER",
        "POTION #1", "POTION #2", "FLYING RUG", "MAGIC WAND", "STAFF", "QUADROON", "SHIP",
    ]
    private static let weights = [
        5, 2, 200, 5, 0, 5, 5, 5, 5, 5, 5, 2, 5, 2, 5, 2, 2, 10, 25, 0, 50, 10, 10, 10, 15, 15,
        10, 30, 75, 150, 15, 1, 1, 1, 2, 1, 1, 5, 1, 1, 5, 5, 2, 2, 5, 3, 5, 1, 0,
    ]
    private static let prices = [
        5, 5, 100, 10, 50, 15, 10, 10, 10, 10, 20, 50, 30, 10, 50, 50, 50, 40, 100, 150, 35, 40,
        45, 40, 35, 30, 50, 40, 80, 120, 10, 40, 2, 5, 2, 1, 5, 10, 10, 10, 20, 90, 90, 90, 0, 0, 0, 1, 2500,
    ]

    public var name: String { Item.names[id - 1] }
    public var weight: Int { Item.weights[id - 1] }
    public var listPrice: Int { Item.prices[id - 1] }
    public var description: String { name }

    /// The name for `quantity` of them (GOSUB 542): TORCHES, COMPASSES, otherwise an S.
    public func name(quantity: Int) -> String {
        quantity < 2 ? name : name + (id == 33 || id == 15 ? "ES" : "S")
    }

    public static func < (a: Item, b: Item) -> Bool { a.id < b.id }
}
