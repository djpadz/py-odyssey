# Odyssey — 3D reboot (work in progress)

A reimagining of *Odyssey: The Compleat Apventure* (Synergistic Software, 1980) as a
native macOS and iOS game in SwiftUI and RealityKit. It is built on the Python port
in the rest of this repository: the island map, items, prices, monsters and rules are
taken from the original, and the original's wording is kept for everything the game says.

*Odyssey* remains Synergistic Software's property; this is a personal project.

## Building and running

Requires Xcode 27 and [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`).

```
cd apple
xcodegen generate                       # makes Odyssey.xcodeproj (not committed)
open Odyssey.xcodeproj                  # or build from the command line:
xcodebuild -project Odyssey.xcodeproj -scheme Odyssey -destination 'platform=macOS' \
    -derivedDataPath build CODE_SIGN_IDENTITY=- build
open build/Build/Products/Debug/Odyssey.app --args --quest 1980   # skip the title, fixed island
```

Debug builds also take `--meet <what>` (with `--quest`) to start face to face with something:
a monster by name or number (`dragons`, `13`; add `!` to attack), `caravan`, `wizard`, `warlock`,
`warriors`, `chest`, `horses`, `rug`, `staff`, `torches` (lying here), `inventory`, an obstacle (`thicket`, `ravine`, `bog`, `crevasse`, `cliff`), or `sealed`,
which seals every site (`temple`, `castle`... also stand the party at that site's door).

The rules have their own tests: `cd apple/OdysseyKit && swift test`.

## Playing

| | Mac | iPhone / iPad |
|---|---|---|
| Walk | WASD or arrows | stick |
| Turn / zoom the camera | drag; pinch or ± | drag; pinch |
| Look (names the terrain around) | L | Look button |
| Inventory and status report; use or drop a thing | I or C, or click the stats; click a thing | tap the stats; tap a thing |
| Pick up what lies here | G, or the button | button |
| Ride the horses / come down | R (or H to halt) | Ride / Halt button |
| Map (enlarge it) | click the map | tap the map |
| New quest / continue the saved one (title) | N / P | buttons |
| City market | Return or M at a city | button |
| At a site | the original's keys: U use, S search, G get, O open, A attack, F fight, R run, L leave… | buttons |

## Layout

| Path | What |
|---|---|
| `OdysseyKit/` | The game rules as a pure Swift package (no UI), with tests. |
| `OdysseyKit/.../Island.swift`, `IslandData.swift` | The 20×20 map from the disk, site placement as HAIL does it, the "YOU CAN SEE…" descriptions. |
| `OdysseyKit/.../Expedition.swift` | The party (rolled as in HAIL), walking, turns, rations and starvation. |
| `OdysseyKit/.../Items.swift`, `Market.swift` | The 49 items, and the city bazaar with haggling (lines 1500–1598). |
| `OdysseyKit/.../Visit.swift`, `Combat.swift` | Temples, ruins, castles, tombs and huts (9000–9915), monsters (1200–1370) and battles (6000–6980). |
| `OdysseyKit/.../Commands.swift` | Get, drop, ride and halt, and using things, magic above all (760–830, 8100–8180). |
| `OdysseyKit/.../Road.swift` | What happens between sites (725–3400): encounters, traps and obstacles, played out as visits with no site. |
| `Odyssey/World/` | The 3D island: heightfield terrain and texture, vegetation and site models, the party. |
| `Odyssey/UI/MapView.swift` | The inset map: the island from above, the sites seen, obstacles met, and the party. |
| `Odyssey/World/Cast.swift` | Whoever the party is dealing with, in 3D: the twenty monsters, caravans, wizards, warriors, and chests. |
| `Odyssey/UI/` | Title, HUD, market, inventory and site panels. |
| `Odyssey/GameModel.swift` | Ties the rules, the scene, the camera and input together. |
| `project.yml` | XcodeGen spec for the one multiplatform app target. |

Map pixels (the original's 280×160 island coordinates) are the rules' unit of position;
`WorldScale` converts them to metres (2 m per pixel, north is −z).

## Done

- The island in 3D, with the sites placed per quest from a seed.
- The party walking, blocked by the sea, slowed by swamp and mountains.
- The original's location reports and Look.
- City markets: price board, haggling with counter-offers, insults and broken deals, buying
  (contracts hire men; the ship is sold only at the north-western city).
- Rations every fifth turn (one turn = 3 map pixels walked), starvation, and losing the quest.
- Sites: opening doors with the right tool, six searches, altars, chests, pit traps, monsters,
  combat with the original's tally, spoils, huts selling magic, and sealing on leaving.
- The road: each turn's walk may bring monsters (flying ones too), a merchant caravan to buy
  from or rob, a wizard or warlock, warriors who join as mercenaries or turn out to be bandits,
  a trap that catches men until the right thing frees them, or an obstacle that bars the way
  until the right thing clears it.
- In 3D: monsters and the people of the road stand across the party's path (flyers wheel
  overhead), lunge each round of a battle and fall as they're killed; chests appear to be opened;
  searched sites are sealed (slabbed, boarded up or choked with rubble); obstacles fill their cell.
- Magic: the amulet restores the party's first strength; the scroll turns rocks to gold for a
  wise enough reader; the magic lamp, scepter, wand and staff raise speed, charisma or wisdom
  (or blow up in unwise hands); the potions strengthen or sicken; the flying rug carries the
  party anywhere, sea included.
- Riding (a horse for every two men), as fast as the original's riding loop and as free: no turns
  pass on horseback or the rug, so no rations and no encounters, and sites wait until you halt.
  Riding into the sea drowns two horses.
- Things lying about: one step in thirty on bare ground turns up something, and the party can
  drop things and pick them up again. A sack marks the spot.
- Saving: the quest saves itself whenever the party moves to a new cell or does something, and
  when the app goes to the background or quits; the title offers to continue it. Losing the
  quest deletes the save. Quests started with `--quest` don't save.
- The status report (the original's C) in the inventory panel, and an inset map that marks
  each site once it has come into sight, as the original drew them on its map.

## Changes from the original

- A lowball offer is judged against the list price of the item being sold (the original
  uses the item numbered like the board position).
- The men refuse purchases they cannot carry, instead of buying and then dumping.
- Bargaining with monsters goes by the monster's kind (the original tests a stale variable).
- At a door, Leave closes the panel rather than repeating the entrance text.
- An obstacle bars the cell the party was walking into, and keeps its description. The original
  backs the party off, bars the cell it was standing in, and describes it afresh each time.
- A trap keeps its description while you try things (the original can re-roll the swamp's).
- Men lost to a caravan's guards stay lost. The original skips the count when the caravan falls.
- The ground holds one kind of thing, up to 99, and nothing can be dropped at a site; the original
  drops anything and silently loses it if the ground is taken. The men won't pick up more than
  they can carry.
- Horses are stopped by obstacles (the original rides through them); the rug flies over.
- The rug won't land on the water.
- Magic is used on the road, not at a site's door or in a trap.
- The quest saves itself, rather than when you quit and say so, and only while the party is free:
  continuing after a quit mid-battle or mid-haggle starts from just before it.

## Next

1. The ship and the sea voyage (SEA APVENTURE), then the catacombs, and the Caliph's fortress.
