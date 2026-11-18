# Odyssey: The Compleat Apventure — Python port

A port of Robert Clardy's *Odyssey: The Compleat Apventure* (Synergistic
Software, 1980) for the Apple II, reverse-engineered from the original disk image
(`src_listings/Odyssey_TheCompleatAdv.dsk`).

The game logic is a hand translation of the original Integer BASIC programs
into Python. The parts of the Apple II the game depends on are re-implemented:
- the 40-column text window
- lo-res and hi-res graphics
- the Programmer's Aid shape routines
- the keyboard latch
- the speaker

As a result the game logic, timing, sounds and even the quirks match the
original. The screens do too with `--classic`; by default the pictures are
repainted (see below).

## Playing

```
uv run odyssey     # options: --classic, --scale N, --no-sound, --save FILE, --seed N
```

`uv` creates the environment and installs the one dependency (`pygame-ce`)
on first run. You can also install it as a command with `uv tool install .`.
Without uv: `pip install .` then `odyssey`.

By default the game uses **enhanced graphics**:
- The title screen, the island, the sea chart and the fortress are repainted
  at high resolution.
  - The title is set in blackletter, with a shaded, scaled dragon.
  - The maps get painted seas with shallows and surf, beaches, terrain, snowy
    mountains, a river, a compass rose and a stone castle.
- Everything the game draws on top (the party, ships, monsters, site markers)
  appears over the art.
- The text and the lo-res catacombs keep their original crisp look.

`--classic` shows exactly the Apple II's pixels instead, and **F2** switches
between the two while playing. The window can be resized and draws at the
screen's full (Retina) resolution; **F11** (or Alt/Cmd-Return) toggles full
screen.

Press **N** for a new quest or **P** to continue a saved one. Every command is
a single key, and an unknown key lists the commands available:

| Where | Keys |
|---|---|
| Island | **N S E W** walk (RETURN repeats the step) · **L**ook · **G**et · **D**rop · **U**se · **R**ide · **H**alt · **C**ondition · **I**nventory · **Q**uit · ESC refreshes |
| Sea | **A**nchor (or attack) · **S**et sails (then a direction: E, W, NE, SO...) · **R**eef · **W**atch · **F**ire cannon · **H**ail · **D**ivers · **L**and · **P**ut overboard · **O**ffer · **U**se · **G**et · **C** · **I** · **Q** |
| Catacombs | **N S E W** · **L**ight · **D**own · **O**ut · **T**eleport · **B**urrow · **U**se · **P**ut · **G**et · **C** · **I** · **Q** |
| Fortress | **A**pproach · **R**etreat · **U**se · **C** · **I** · **Q** |

### How a game ends

| What happens | What you see | Then |
|---|---|---|
| You press **Q** | "QUIT GAME?" then "SAVE GAME?" (saving writes `odyssey-old-game.json`) | The window closes. Press **P** at the title next time to continue. |
| Your party is lost, anywhere | The death message | Press any key and the window closes. |
| You storm the fortress without the High One's Orb | Your force is destroyed, then your final score | Press any key and the window closes. |
| You take the fortress with the orb | Your final score and alignment | A menu: **1** start a new quest, **2** leave. |
| Your ship sails off the edge of the world | "Your ship was lost..." | A menu: **1** recover your ship and sail on, **2** start a new quest, **3** leave. |
| A run-time error (see [Faithfulness](#faithfulness)) | `*** RANGE ERR` or similar | A menu: **1** continue the quest, **2** start a new quest, **3** leave. |

The menus ignore keys pressed before they appear, so you can't skip one by
accident.

The quest: on the island, buy a ship at the city in the north and sail
away with at least 15 men. At sea, find the High One's Orb. It lies in the
catacombs under a wizard's temple on one of the islands, or Argorion may tell you
where to dive for it. Then storm the Caliph's fortress on the Isle of Lapour (the
north-west island).

*Photosensitivity note:* the poison gas in the catacombs makes the screen
flash quickly through random colours, exactly as the original did.

## Layout

| Path | What |
|---|---|
| `odyssey/apple.py` | The Apple II model: 64K memory with text/lo-res pages, text window and cursor, display switches, keyboard latch, speaker routine, timing, Integer BASIC arithmetic. |
| `odyssey/hires.py` | The hi-res page and an exact port of the Programmer's Aid `DRAW`/`DRAW1` routines (rotation, scale, colour and the collision counter). |
| `odyssey/screen.py` | pygame-ce window: renders the screen memory (NTSC-style colour) in the enhanced or classic look, keyboard, speaker. |
| `odyssey/part.py` | Shared machinery: the variable `State`, item names, inventory, menus, quitting. |
| `odyssey/island.py`, `sea.py`, `cavern.py` | The three programs: ISLAND, SEA and CAVERN APVENTURE. |
| `odyssey/game.py` | HAIL (title, character rolls, island setup), CHAIN between parts, save/restore, the end-of-game menu. |
| `odyssey/data.py`, `odyssey/assets/` | Tables, maps, pictures and shapes extracted from the disk. |
| `odyssey/assets/art/` | The repainted pictures for the enhanced graphics. |
| `tools/` | The reverse-engineering tools: DOS 3.3 reader, Integer BASIC detokenizer, variable-table parser, asset extractor, string checker. |
| `src_listings/` | The original disk images, and the detokenized programs from them (control characters shown as `{^M}`, `{^G}`). |
| `tests/` | Scenario tests (`uv run python -m unittest discover tests`). |

`odyssey/data.py` and `odyssey/assets/` are generated with
`python3 tools/extract_assets.py src_listings/Odyssey_TheCompleatAdv.dsk`. The repainted pictures in
`odyssey/assets/art/` are made by
`uv run --with pillow --with numpy --with scipy python tools/render_art.py`, using the
OFL-licensed fonts in `tools/fonts/` (UnifrakturCook and IM Fell English). For the listings,
first unpack the disk with `python3 tools/dos33.py src_listings/Odyssey_TheCompleatAdv.dsk extracted/game`,
then run `python3 tools/intbasic.py extracted/game/<FILE>.I`.

## What is on the disk

| File | Type | Contents |
|---|---|---|
| HELLO | Applesoft | Loads Integer BASIC into a language card, runs HAIL |
| HAIL | Integer BASIC | Title screen, rolls the party, lays out the island |
| ISLAND / SEA / CAVERN APVENTURE | Integer BASIC | The three parts of the game, which CHAIN to each other |
| APVENTURE SETUP | binary, $0800-$1FFF | Programmer's Aid hi-res routines at $0800, the initial **variable table** at $0C00, the shape table at $1AA4 |
| ISLAND 1, ISLAND 2, SEA MAP, LOGO | hi-res pictures | The island, the fortress approach, the sea chart, the title |
| LC2 | binary, $0C61 | The sea chart's currents and depths, loaded over the island map array |
| SOUND | binary, $0342 | Speaker tone routine (pitch $340, length $341, repeats $35C) |
| COL | binary, $2400 | Lo-res colour-swap routine used for the poison-gas hallucinations |
| INTBASIC | binary | Integer BASIC for the language card |

## Reverse-engineering notes

- **Data lives in the variable table.** The programs contain no DATA for the
  item names, prices, weights, monster names or the island map. HAIL BLOADs
  APVENTURE SETUP, which contains a ready-made Integer BASIC variable table at
  $0C00. It then POKEs the end-of-variables pointer ($CC/$CD) to $185F. Because
  CHAIN keeps variables, every part sees that data. A saved game is simply
  `BSAVE OLD GAME,A3070,L13314`: the variable table plus the hi-res page.
- **Variables X0, Y0, COLR, SHAPE, ROT, SCALE come first** because Programmer's
  Aid reads them at fixed offsets from LOMEM. `CALL 2871` is DRAW, `CALL 2884` is DRAW1
  (XOR), and `CALL 2865` fills the screen.
- **Running aground** at sea is detected with the DRAW collision counter
  (`PEEK(810)`). The ship shape overlaps itself exactly 33 times, so any other
  count means it touched land. `hires.py` reproduces the routine bit for bit so
  this works unchanged.
- **The island map** is 20×20 cells of 14×8 pixels, column major. A cell's value
  `TTQQII` holds the terrain, the quantity and the item or site code.
- **The sea chart** cells hold depth×1000 + current direction×100 + current
  speed, and 0 is land.
- **The catacombs have no map in memory.** The lo-res screen is the map: 5×5 tiles
  appear as you walk off the known area, and a tile counts as explored once its
  bottom-left pixel is set. With the light off the display flips to text page 2,
  which holds a frozen copy of the screen.
- Integer BASIC semantics the port follows:
  - `IF … THEN stmt : more` runs `more` unconditionally.
  - `TAB` sets the column directly and can move left.
  - Division truncates, and `MOD` takes the dividend's sign.
  - FOR loops run at least once.
  - Strings keep their CTRL-A padding, which prints as nothing but counts in `LEN`.

## Faithfulness

All game text was checked mechanically against the original string literals
(`tools/check_strings.py`). Quirks of the original are kept. Some examples:
- dropping all of something can leave a different item on the ground;
- buying at a caravan subtracts the gold's weight;
- the borer "kills" men from a misspelt variable, so nobody dies;
- the fortress can set the same hazard twice;
- the score charges for every man lost.

A few places where the original program would stop with an Integer BASIC
error or hang have been given the obvious fix:

| Line | Original | Port |
|---|---|---|
| SEA 952 | `GOSUB 140`, a line that does not exist | pause and retry |
| CAVERN 3225 | looks the magic item up with the wrong index, then `RETURN` without `GOSUB` | uses up the item that was used |
| CAVERN 3350 | `GOTO 3325`, which does not exist | continues as 3320 does |
| CAVERN 21030 | `GOTO 20025`, which does not exist | `21025` |
| ISLAND 2010 | a trap just after trying to walk on water does `GOTO 2400`, which does not exist | no trap |
| CAVERN 5000 | loops forever if no item can be lost | gives up |
| SEA 1820 | an endless `FOR … STEP 0` | runs once |
| item menus | choosing an empty slot stops with a RANGE ERR | treated as cancelling |
| island edges | map look-ups past the edge stop with a RANGE ERR | read as open sea |

Any other run-time error is reported the way Integer BASIC did
(`*** RANGE ERR`), followed by a menu where you can continue the quest.

### Deliberate changes from the original

These are conveniences, not fixes. The game logic underneath is unchanged.

| Original | Port |
|---|---|
| Quitting ended at the Integer BASIC `>` prompt with "TYPE 'GOTO 32000' TO REENTER GAME." | Quitting closes the window. A saved game is continued with **P** at the title. |
| Losing the party ended at the `>` prompt. In the catacombs the message didn't wait for a key. | Every death message waits for a key, then the window closes. |
| A ship lost off the edge of the world said "TO RECOVER YOUR SHIP, TYPE 'GOTO 31000'". Winning, and run-time errors, also ended at the `>` prompt. | A menu offers to recover the ship (or continue after an error), start a new quest, or leave. |
| Saving asked you to swap disks, and in the catacombs to type a file name. | Saving writes `odyssey-old-game.json` after a key press. |
| The hi-res pictures were 280×192 pixels. | Repainted pictures by default; `--classic` or **F2** shows the original. |
