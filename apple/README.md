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

The rules have their own tests: `cd apple/OdysseyKit && swift test`.

## Playing

| | Mac | iPhone / iPad |
|---|---|---|
| Walk | WASD or arrows | stick |
| Turn / zoom the camera | drag; pinch or ± | drag; pinch |
| Look (names the terrain around) | L | Look button |
| Inventory | I, or click the stats | tap the stats |
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
| `Odyssey/World/` | The 3D island: heightfield terrain and texture, vegetation and site models, the party. |
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

## Changes from the original

- A lowball offer is judged against the list price of the item being sold (the original
  uses the item numbered like the board position).
- The men refuse purchases they cannot carry, instead of buying and then dumping.
- Bargaining with monsters goes by the monster's kind (the original tests a stale variable).
- At a door, Leave closes the panel rather than repeating the entrance text.

## Next

1. Overland events while walking (lines 725–850, 3000–3400): random monsters, merchant
   caravans, wizards, warriors, traps and obstacles cleared with the right item.
2. Monsters, chests and sealed sites shown in 3D.
3. Using magic items (8100+) and the other commands: drop, get, ride (the horse).
4. Saving and resuming a quest.
5. The ship and the sea voyage, the catacombs, and the Caliph's fortress.
