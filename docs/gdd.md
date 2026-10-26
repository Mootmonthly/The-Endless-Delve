# The Endless Delve - Game Design Document

Status: living document. Expanded from the owner's original GDD (Session 1, 2026-10-26).
Anything marked **Proposal (needs owner sign-off):** is a design suggestion that fills a gap in the
original GDD and is not yet agreed. Everything else restates or directly follows from the owner's GDD.

Related documents: [Technical design](tdd.md), [Roadmap](roadmap.md), [Licensing](licensing.md).

## 1. Overview

### 1.1 Pitch

The Endless Delve (TED) is a 2D, top-down, massively multiplayer dungeon crawler built on the 5e SRD
rules. Players create a character, enter a single, handcrafted, 100-floor dungeon and try to reach the
bottom. Exploration is real-time; fights are turn-based 5e encounters. Every fifth floor is a safe zone.
If you die, you start again from floor 1.

### 1.2 Pillars

| Pillar | What it means | What it rules out |
|---|---|---|
| The rules are the game | Combat, checks, rests and leveling follow the 5e SRD faithfully. A tabletop player should recognise every number on the screen. | Action-RPG reflex combat, homebrew stat inflation, hidden modifiers. |
| The dungeon is the world | There is no overworld. The 100 floors and the safe zones between them are the whole setting. | Open-world zones, hub cities outside the dungeon, side continents. |
| Death matters | Full death or a party wipe resets the character to floor 1 with no levels or loot. | Corpse runs, death penalties measured in minutes, paid revives. |
| 100 floors, one journey | Every floor is handcrafted and identical for every player, so depth is a shared, comparable achievement. | Procedural floors in the main dungeon, per-player randomised layouts. |

## 2. Target audience and platform

- **Primary audience:** tabletop 5e players who want a persistent, high-stakes version of a dungeon
  crawl they can play without a game master; fans of roguelikes and permadeath.
- **Secondary audience:** MMO players looking for a small-group, tactical, hardcore experience.
- **Platform:** PC via Steam. Windows first, Linux and macOS exported from the same Godot project.
- **Input:** mouse and keyboard first. **Proposal (needs owner sign-off):** controller support is a
  post-Early-Access goal; the turn-based combat UI is designed so it can be driven by a cursor alone.
- **Business model:** box price (owner suggests about USD 20) plus cosmetic-only in-game purchases.
  Nothing purchasable affects rules, stats, loot or progression.
- **Store keywords:** the current GDD keyword list must be revised before any store page goes live.
  See the action item in [licensing.md](licensing.md).

## 3. Core loop

```
 Character creation (class, ancestry, abilities, background, server type)
        |
        v
 +--> Floor N: explore in real time -> monster packs -> secret rooms -> boss(es)
 |      |
 |      v
 |    Stairs down  ==> SHORT REST (spend Hit Dice, recharge short-rest features)
 |      |
 |      +-- N is not a multiple of 5 --> Floor N+1 (same instance) ---+
 |      |                                                               |
 |      +-- N is a multiple of 5 --> SAFE ZONE ==> LONG REST           |
 |                                    trade, chat, regroup, log off      |
 |                                    queue for next instance (N+1..N+5)|
 |                                                                      |
 +----------------------------------------------------------------------+

 At any point: full death or party wipe --> character reset to level 1 on floor 1.
```

Session shape: a single floor is designed to take a full party about 30-60 minutes; an instance
(5 floors) is a 3-5 hour run that can be split across sittings by logging off in a safe zone.
**Proposal (needs owner sign-off):** players can only log off with progress kept inside a safe zone;
disconnecting inside an instance leaves the character in the world for a 3 minute grace period (see
Open question 9).

## 4. Game modes

Server type is chosen at character creation and is permanent for that character.

| Mode | Player combat | Instance population | Notes |
|---|---|---|---|
| PVP server | Yes, anywhere outside safe zones | ~100 players across 5 floors | Other parties are both potential allies and threats. |
| PVE server | No | One party per instance ("the entire instance to themselves") | Same floors, same monsters, same death rules. |
| Offline | No | One local party | Whole game solo. Characters cannot move to online servers. |

**Proposal (needs owner sign-off):** in Offline mode the player may control a party of up to 5
characters (a classic tabletop-style party) rather than a single hero, because the floors are tuned for
parties. A single hero remains possible for challenge runs.

**Proposal (needs owner sign-off):** PVE "instance to themselves" means one party per instance process.
Matchmaking for PVE therefore starts a fresh instance per party; this is cheap because PVE instances
host at most 5 players.

## 5. Dungeon structure

### 5.1 Floors and instances

- 100 floors, grouped into 20 instances of 5 floors (instance 1 = floors 1-5, instance 20 = floors 96-100).
- Each instance holds ~100 players across its 5 floors on PVP servers.
- Players enter an instance by matchmaking, solo or as a party of up to 5.
- **Revolving door:** players always enter on the first floor of the instance. As parties leave via the
  final staircase, new parties are admitted to the first floor, keeping the population near capacity.
- Between instance N and N+1 is safe zone N (after floors 5, 10, ..., 95). Clearing floor 100 leads to the
  postgame (section 13).
- **Owner decision (2026-10-26):** the five floors of an instance form a **set** that shares one theme
  (see 5.4).

### 5.2 Floor anatomy

Each floor is handcrafted and identical for everyone. Every floor contains:

| Element | Description |
|---|---|
| Explorable area | A wide tile map; size and complexity grow with depth. |
| Arrival landing | The tiles where players arrive from the stairs above. |
| Monster packs | Groups of SRD monsters placed in authored encounter zones. |
| Boss(es) | One to three bosses. **Proposal (needs owner sign-off):** at least one boss must be defeated (by anyone in the instance, since the last clear) before the down staircase unlocks; bosses respawn on a timer. |
| Secret loot rooms | Hidden doors and rooms found with Wisdom (Perception) or Intelligence (Investigation) checks, traps guarded by Dexterity saving throws. |
| Staircase | The exit to the next floor. Descending is a short rest. |

**Proposal (needs owner sign-off):** monster packs respawn per party, not globally: once a party kills a
pack it stays dead for that party for the rest of their visit, but other parties still meet it. This keeps
handcrafted floors consistent ("the same journey") with 100 players sharing them. Bosses respawn
globally every 10 minutes after being killed.

### 5.3 Difficulty curve

Deeper floors bring stronger monsters (higher challenge rating), larger and more complex layouts, and on
PVP servers more skilled and better equipped players. **Owner decision (2026-10-26):** within a set the
first floor is relatively easy and the last is very difficult for a solo player fighting head-on, while
players level as they go. Encounter budgets follow the SRD encounter-building guidance, written for one
character of the level a solo is expected to have on that floor; parties face the same zones with more
combined thresholds. The first set's budgets are in 5.4.

### 5.4 The first set (floors 1-5)

**Owner decisions (2026-10-26):** floor 1 is relatively easy and difficulty climbs to floor 5, which is very
difficult for a solo player fighting head-on. Players level as they advance through the set (8.3), so the
curve assumes a rising level. Every five-floor set shares one theme. Solo players get their death saves
before a party wipe is declared (9.3).

#### Theme: The Barrow Warrens

Below the dungeon's first stair lies a buried necropolis whose builders no one remembers. Kobold and goblin
diggers tunnelled in after grave goods and broke the old seals; the dead woke in their niches, rats and
centipedes bred in the spoil heaps, and a hobgoblin war-band moved in to rule the diggings. At the bottom,
in the funeral hall that holds the stair down, squats an ogre the diggers call the Gravebreaker. It takes a
toll in bones from anything that wants to go deeper. Monster families: vermin (giant rat, giant centipede,
giant spider), goblinoids and their kobold labour (kobold, goblin, hobgoblin, bugbear), the restless dead
(skeleton, zombie, ghoul) and the ogre. All are SRD 5.1 stat blocks in `data/monsters/`.

#### Floors

Files: `floors/set_01.json` (the manifest) and `floors/floor_001.json` to `floor_005.json`. Each floor
declares `floor_number`, `theme` and a `budget` (below); zones declare `kind` (`pack`, `ambush`, `boss`),
floor 5's boss zone `"boss": true`, and each floor's side area `"optional": true`. Difficulty is per zone,
for **one** character of the assumed level, using adjusted XP (see the budget rules below); the numbers in
brackets are adjusted XP and side areas are in italics.

| Floor | Name | Size (tiles) | Zones (of which optional) | Assumed solo level | Band (solo) | Roster by zone | Notable feature |
|---|---|---|---|---|---|---|---|
| 1 | The Threshold | 48x32 | 2 (1) | 1 | easy-hard | rat hall: 2 giant rats, hard (75); *crypt*: 2 skeletons + zombie, deadly (300) | One required fight; the crypt is a side room off the rat hall. |
| 2 | The Spoil Tunnels | 56x36 | 3 (1) | 2 | easy-medium | kobold den: 2 kobolds, easy (75); centipede gallery (ambush): giant centipede, easy (50); *goblin cache*: 2 goblins, hard (150) | Two ways off the landing (through the den or down the west tunnel); both meet in the gallery. |
| 3 | The Ossuary | 64x40 | 4 (1) | 2 | medium-hard | bone-pickers' hall: 3 kobolds, hard (150); narrow ossuary (ambush): 2 giant centipedes, hard (150); guard post: hobgoblin + kobold, hard (187.5); *charnel chamber*: ghoul, deadly (200) | After the hall the route forks: low road through the ossuary, or high road through the guard post. |
| 4 | The Webbed Crypts | 72x44 | 4 (1) | 3 | hard | war-band camp: hobgoblin + goblin, hard (225); webbed gallery (ambush): giant spider + giant centipede, hard (375); sealed crypt: ghoul + zombie, hard (375); *chieftain's tomb*: bugbear + hobgoblin, deadly (450) | Landing in the middle of the floor; a north road (camp, then gallery) and a south road (crypt) to the stairs. |
| 5 | The Gravebreaker's Hall | 80x48 | 5 (1) | 3 | hard, boss deadly | muster room: bugbear + goblin, hard (375); sniper gallery (ambush): 3 goblins, hard (300); bone pit: ghoul + skeleton, hard (375); *charnel pit*: 2 ghouls, deadly (600); **boss** great hall: ogre, deadly (450) | The stairs stand inside the great hall: the boss zone is on every route. West road (sniper gallery) or east road (bone pit). |

Layout rules every floor of the set meets (checked by `tests/content/test_set_01.gd`): each floor is wider
and taller than the one before; zone counts never drop; every route from arrival to the stairs crosses at
least one non-optional zone (the shortest route crosses a zone too); the optional zone is a dead end that
never blocks the stairs; and on floor 5 the stairs lie inside the boss zone.

Every floor also has two treasure chests (`"chests"` in the floor file, checked by
`tests/content/test_chests.gd`): a visible `starter_gear` chest within 3 tiles of the stairs and a hidden
`hidden_cache` chest in the optional side area (8.5).

| Floor | Stair chest (`starter_gear`) | Hidden chest (`hidden_cache`, side area) |
|---|---|---|
| 1 | f1_stairs (44, 25), stairs (42, 26) | f1_hidden (28, 29), crypt |
| 2 | f2_stairs (50, 28), stairs (48, 29) | f2_hidden (50, 3), goblin cache |
| 3 | f3_stairs (56, 30), stairs (54, 31) | f3_hidden (37, 14), charnel chamber |
| 4 | f4_stairs (64, 34), stairs (62, 35) | f4_hidden (47, 38), chieftain's tomb |
| 5 | f5_stairs (66, 8), stairs (64, 9), inside the boss hall | f5_hidden (66, 29), charnel pit |

**Proposal (needs owner sign-off):** in this set only floor 5 has a boss. Floors 1-4 gate their stairs with
required pack zones instead of the one-to-three bosses of 5.2, so the set's single boss is a clear finale;
later sets may add mid-set bosses once boss mechanics (lair behaviour, respawn, shared fights) exist.

#### Encounter budgets

- **Method (SRD encounter building):** adjusted XP = the sum of the monsters' XP x a multiplier for their
  number (1: x1, 2: x1.5, 3-6: x2, 7-10: x2.5, 11-14: x3, 15+: x4). Compare it with one character's
  thresholds (easy / medium / hard / deadly): level 1 25/50/75/100, level 2 50/100/150/200, level 3
  75/150/225/400, level 4 125/250/375/500. A zone's band is the highest threshold it reaches.
- **Solo basis:** the set is tuned for a solo at the floor's assumed level, so a party (whose thresholds
  add up across members) always finds the same zone easier, even though it levels more slowly (below).
- **The `budget` field:** each floor stores `{"level": L, "min": band, "max": band}`. Every required zone
  must fall inside the band for level L.
- **Proposal (needs owner sign-off):** optional side areas may exceed `max` (they are opt-in risk for extra
  XP and, later, loot) but must reach `min`; the boss zone must be at least deadly.

#### The boss: the Gravebreaker (floor 5)

An ogre (SRD 5.1, CR 2, 450 XP: AC 11, 59 hit points, greatclub +6 for 2d8+4) alone in a 32x13 hall with
pillars, standing by the stairs. Adjusted XP 450: **deadly** for one level-3 character, **hard** for three
level-2 characters, medium for three level-3 characters (a full-clear party of three now arrives at level 3
thanks to the floor-clear bonus) and for four level-2 characters.

- **Why a solo loses head-on.** A level-3 solo has about 28 hit points (a Fighter with Constitution 14).
  The ogre hits AC 16-18 about half the time for 13 on average (20 at most, 22 on average with a
  critical), so two or three hits drop the solo in about five rounds even after Second Wind. The solo needs
  about seven or eight rounds of hits (with Action Surge) to chew through 59 hit points, so it loses most
  head-on fights. Retreating does not help: monsters are leashed to their zone and an encounter
  with no players left resets them to full (7.5). Once the solo is down, the ogre keeps attacking the dying
  character (9.3), each hit within 5 feet a critical worth two failed death saves.
- **Why a party wins.** Three level-2 characters bring 55-60 hit points and three attacks a round: they
  drop the ogre in three or four rounds while it can only hit one of them per turn. A downed member can be
  stabilised or healed while the others keep swinging. The action economy, not the numbers on the sheet,
  is the gate.

#### Leveling within the set

- **XP from kills:** when players win an encounter, the XP of every monster that died in it is split evenly
  (integer division) among the players who were in that encounter and are alive at its end. Levels apply
  at once (average hit points). Taking the stairs on floors 1-4 is a short rest (5.2); floor 5's stairs
  lead to the safe zone (for now: a long rest and the end of the set).
- **Floor-clear bonus (owner decision, playtest round 1):** every living player who takes the stairs of a
  floor, any floor, earns `FLOOR_CLEAR_XP = 100` XP, not split. It answers "still level 1 entering
  floor 2": a solo who clears floor 1 (200 XP) arrives on floor 2 with 300 XP, which is level 2.
- **XP per floor (sum of monster XP):**

| Floor | Required zones (both roads) | Optional zone | Full clear | Solo total after full clears | Solo total, side rooms skipped |
|---|---|---|---|---|---|
| 1 | 50 | 150 | 200 | 200 | 50 |
| 2 | 100 | 100 | 200 | 400 | 150 |
| 3 | 300 | 200 | 500 | 900 | 450 |
| 4 | 650 | 300 | 950 | 1,850 | 1,100 |
| 5 | 1,100 | 400 | 1,500 | 3,350 | 2,200 |

- **Expected level on arrival**, monster XP plus 100 per floor already left by the stairs (SRD
  thresholds: level 2 at 300 XP, 3 at 900, 4 at 2,700). Each floor's `budget.level` is the full-clear solo
  column: 1, 2, 2, 3, 3.

| Arriving on | Solo, full clears (XP) | Solo, side rooms skipped (XP) | Party of 3, full clears (XP each) | Party of 5, full clears (XP each) |
|---|---|---|---|---|
| Floor 1 | 1 (0) | 1 (0) | 1 (0) | 1 (0) |
| Floor 2 | 2 (300) | 1 (150) | 1 (166) | 1 (140) |
| Floor 3 | 2 (600) | 2 (350) | 2 (333) | 1 (280) |
| Floor 4 | 3 (1,200) | 2 (750) | 2 (600) | 2 (480) |
| Floor 5 | 3 (2,250) | 3 (1,500) | 3 (1,016) | 2 (770) |
| Safe zone 1 | 4 (3,850) | 4 (2,700) | 3 (1,616) | 3 (1,170) |

  With the bonus, floor 2 drops to easy-medium for its full-clear level-2 solo (its required zones are
  easy at level 2; the goblin cache is hard). A solo who skips side rooms runs a level behind the budget
  on floors 2 and 4 and catches up on floor 5. Side rooms (now with a hidden chest each) remain the solo's
  way to stay on the curve, at a risk. `test_full_clear_level_matches_each_floor_budget` pins the
  full-clear column to each floor's budget level.

#### Measurement (moved from Open question 19)

Measured on 2026-10-26 with a naive bot (attacks when adjacent, otherwise closes distance, never Dodges)
playing a level 1 human Fighter on floor_001: one giant rat 19/20 wins, two giant rats 11/20, goblin + giant
rat 9/20, two goblins + giant rat 2/20. Floor 1 ships its rat hall as a two-rat pack (the owner's call: players are smarter than the bot) and the crypt (two
skeletons + zombie) as a side room off the main route. Two giant rats sit exactly on the level-1 hard
threshold (75 adjusted XP), so floor 1 is "relatively easy" only next to the rest of the set. The
measurement predates death saves before the wipe and XP awards: re-run the bot on all five floors (solo
at the assumed level, and a party of three) before tuning further. Death saves give a downed solo a chance
at a natural 20, but monsters attack the dying when nobody else is standing, so most downed solos still die.

#### Later sets share a theme

Every five-floor set (instance) has exactly one theme: one name, one fiction, and a monster roster drawn
from a few related SRD families. The set manifest `floors/set_NN.json` names the theme and lists its five
floors in descent order, and every floor in it carries the same `theme`. **Proposal (needs owner
sign-off):** each later set follows the same template: floor numbers continue (set N holds floors
5N-4 to 5N); floors grow in size and never lose zones within a set; each floor has one optional side area;
the set's last floor has a boss zone that contains or encloses the stairs; budgets are written for a solo
at the level a full-clear solo reaches, with the last floor's ordinary zones hard and its boss deadly, and
the boss at most hard for a party of three at the party's (lower) expected level; and each set ships with a
content test like `tests/content/test_set_01.gd`. Themes never repeat between consecutive sets.

## 6. Exploration

- The world is a square tile grid. **1 tile = 5 feet**, matching SRD distances.
- Out of combat, movement is real-time and free: no turns, no action economy.
- A party of up to 5 explores together. Party members can be anywhere on the floor; there is no leash.
- **Proposal (needs owner sign-off):** real-time movement speed is derived from the SRD walking speed:
  30 ft speed = 4 tiles per second. Difficult terrain halves speed. Stealth uses passive and active
  checks resolved by the server.
- Interactions (doors, levers, chests, searching) use SRD ability checks rolled by the server.
- Light and vision use SRD rules (bright light, dim light, darkness, darkvision).

## 7. Combat

### 7.1 Encounter zones

Combat happens inside an **encounter**: a bounded rectangular region of tiles with its own initiative
order. Inside the region time is turn-based; outside it the floor keeps running in real time.

- Authored encounter zones are placed by level designers around monster packs and boss rooms.
- An encounter starts when a hostile pair becomes aware of each other inside or at the edge of a zone
  (line of sight and perception checks), or when a player attacks.
- **Proposal (needs owner sign-off):** the region boundary is drawn on screen. No action may cross the
  boundary: you cannot shoot into, cast into, or reach into an encounter from outside. Area effects are
  clipped to the boundary.

### 7.2 Initiative and turn structure

When an encounter forms, every creature inside the region rolls initiative (d20 + Dexterity modifier);
ties are broken by higher Dexterity score, then by a server-side roll. Rounds then proceed in order. On
its turn a creature has, per the SRD:

| Resource | Per turn | Examples |
|---|---|---|
| Movement | Up to its speed, split before and after actions | Walk, Dash adds speed |
| Action | 1 | Attack, Cast a Spell, Dash, Disengage, Dodge, Help, Hide, Ready, Search, Use an Object |
| Bonus action | 0 or 1, only if a feature grants one | Off-hand attack, Cunning Action, some spells |
| Reaction | 1 per round, can be used off-turn | Opportunity attack, readied action, some spells |
| Free object interaction | 1 | Draw a weapon, open a door |

**Proposal (needs owner sign-off):** online turn timer of 30 seconds per turn (bosses' turns are
resolved instantly by the server). On timeout the character takes the Dodge action and ends its turn.
Offline mode has no timer. Reactions are set per character to Auto, Ask (4 second prompt) or Never.

### 7.3 Joining an encounter in progress

Additional players or monsters that enter the region are added to the combat table, as in the GDD.

**Proposal (needs owner sign-off):** a creature that steps into the region immediately stops its
real-time movement, rolls initiative and is inserted into the order. If its slot comes later in the
current round it acts this round; otherwise it acts next round. Joining creatures are not surprised.

### 7.4 How PVP engagement starts

On PVP servers any player may target any other player outside a safe zone.

**Proposal (needs owner sign-off):**
- A player declares a hostile action (attack or hostile spell) against a player in range during real-time
  exploration. The server freezes both, creates an encounter region of at least 12x12 tiles centred on the
  two, clamped to walls, and everyone inside joins.
- The aggressor's party does not get surprise unless they were hidden (SRD Stealth vs passive Perception).
- **Arrival protection:** a player who arrives on a floor cannot be attacked, and cannot attack, while
  standing on the arrival landing, for up to 60 seconds. Attacking ends protection early.
- No PVP on staircase tiles and in the 3-tile ring around them (see Open question 2).

### 7.5 Ending an encounter and fleeing

An encounter ends when at most one side is still in the fight; a side is in the fight while a member is
conscious or (players only) dying, so downed players keep rolling death saves (owner decision, see 9.3).
Then all survivors return to real-time.

- **Fleeing:** a creature that moves out of the region on its turn (provoking opportunity attacks as
  normal) leaves the initiative order and returns to real time. It may re-enter later and will roll
  initiative again.
- Monsters are leashed to their encounter zone and never flee across its boundary.
- If every member of one side has fled, the encounter ends for the remaining side.
- An encounter with no player characters left inside resets: monsters heal to full and return to place.

### 7.6 Ranged, thrown and spell attacks (M2)

Replaces M1's "ranged attacks always have disadvantage" stand-in with the SRD rules:

- **Range:** distance is Chebyshev tiles (1 tile = 5 ft). A ranged or thrown attack, or a spell, needs the
  target within its long range (`range_ft[1]` for weapons, `range_ft` for spells); beyond the normal range
  the attack roll has disadvantage. Melee attacks still need an adjacent target.
- **Hostile adjacent:** a ranged attack roll (weapon or spell) has disadvantage while any conscious hostile
  is adjacent to the attacker. Melee spell attacks (Shocking Grasp, Inflict Wounds) are exempt.
- **Line of sight:** every ranged attack and spell needs a clear line (Bresenham over walkable tiles)
  from attacker to target.
- **Thrown weapons** (dagger, handaxe, javelin, spear, dart) use the weapon's `thrown` property and range.
  A thrown weapon is used up from the inventory and is lost for M2 (proposal for later: it lands on the
  target's tile and can be picked up).
- **Ammunition weapons** (shortbow, longbow, light crossbow, sling) consume one `arrows`, `bolts` or
  `sling_bullets` per shot and cannot attack without ammunition. Ammunition is not recovered in M2.
- **Spells:** `cast` intents name the spell, target and slot level. Spell attacks roll d20 + proficiency +
  casting modifier against AC; saving-throw spells use DC 8 + proficiency + casting modifier. Cantrip
  damage grows at character levels 5, 11 and 17; levelled spells add dice (or darts and rays) per slot
  level above their own. Healing spells can target a dying ally and bring them back up (Cure Wounds is
  the main revive path; Healing Word does it at 60 ft as a bonus action). Area spells (Burning Hands,
  Thunderwave, Shatter, Sleep) and condition spells (Hold Person, Charm Person, Bless) are data only in
  M2: they appear in spell lists but cannot be cast yet.

## 8. Characters and progression

### 8.1 Character sheet

A character is a standard 5e SRD character sheet: six ability scores, ancestry (SRD race/species),
class and level, background, proficiency bonus, skills, saving throws, hit points and Hit Dice, armor
class, speed, features, spell slots, equipment and attunement.

**Proposal (needs owner sign-off):** ability scores use the SRD standard array or point buy only; no
rolled stats online (avoids rerolling abuse and keeps PVP fair). Offline mode may allow rolled stats.

### 8.2 Classes at launch

**Owner request (playtest round 1):** all twelve SRD classes are playable from M2 at level-1 depth. The
original plan shipped Fighter, Rogue, Cleric and Wizard first (M1-M3) and the other eight in M4; wave 2
landed early, with each class's level-1 features that matter in a fight implemented and the rest listed
as flavour until later milestones. Class data lives in `data/classes/<id>.json` (SRD 5.1 hit dice, saves,
proficiencies and skill lists); every class also starts with 2 potions of healing, 5 rations and 10 gp.

| Class | Hit die | Saves | Starting gear (equipped; carried) | M2 level-1 mechanics | Deferred |
|---|---|---|---|---|---|
| Barbarian | d12 | STR, CON | greataxe, no armor; 2 handaxes | Rage (bonus action, 2 per long rest, until the encounter ends: +2 damage on Strength melee attacks, resistance to bludgeoning, piercing and slashing); Unarmored Defense (AC 10 + DEX + CON, shield allowed) | Reckless Attack, Danger Sense (2), Primal Path (3) |
| Bard | d8 | DEX, CHA | rapier, leather armor; dagger | Spellcasting (CHA, known caster): Vicious Mockery, Healing Word, Cure Wounds; Bardic Inspiration (bonus action, CHA-modifier uses per long rest, a d6 added to an ally's next attack roll within 60 ft) | Inspiration on checks and saves, Jack of All Trades, Song of Rest (2), College, Expertise (3) |
| Cleric | d8 | WIS, CHA | mace, scale mail, shield; light crossbow, 20 bolts, holy symbol | Spellcasting (WIS, prepared): Sacred Flame, Cure Wounds, Healing Word, Guiding Bolt | Divine Domain features, Channel Divinity (2) |
| Druid | d8 | INT, WIS | scimitar, leather armor, shield | Spellcasting (WIS, prepared): Produce Flame, Cure Wounds, Healing Word | Druidic, Wild Shape and Druid Circle (2) |
| Fighter | d10 | STR, CON | longsword, chain mail; 2 handaxes | Second Wind (bonus action, 1d10 + level hit points, once per short or long rest) | Fighting Style, Action Surge (2), Martial Archetype (3) |
| Monk | d8 | STR, DEX | shortsword, no armor; 10 darts | Unarmored Defense (AC 10 + DEX + WIS, no shield); Martial Arts (unarmed strike 1d4, DEX for unarmed and monk weapons, a bonus-action unarmed strike after the Attack action) | Ki, Unarmored Movement (2), Monastic Tradition, Deflect Missiles (3) |
| Paladin | d10 | WIS, CHA | longsword, chain mail, shield; holy symbol | Lay on Hands (action, pool of 5 x level hit points per long rest, touch, can bring a dying ally up); Divine Sense (flavour) | Spellcasting (CHA, prepared, from level 2), Fighting Style, Divine Smite (2), Sacred Oath (3) |
| Ranger | d10 | STR, DEX | shortsword, leather armor; second shortsword, longbow, 20 arrows | Favored Enemy and Natural Explorer (flavour) | Spellcasting (WIS, known, from level 2), Fighting Style (2), Archetype (3) |
| Rogue | d8 | DEX, INT | shortsword, leather armor; 4 daggers, thieves' tools | Sneak Attack (once per turn, +1d6 per two levels rounded up, finesse or ranged weapon, with advantage or an ally adjacent to the target and no disadvantage) | Expertise, Thieves' Cant, Cunning Action (2), Archetype (3) |
| Sorcerer | d6 | CON, CHA | dagger; second dagger, light crossbow, 20 bolts, component pouch | Spellcasting (CHA, known caster): Fire Bolt, Ray of Frost, Magic Missile, Mage Armor | Sorcerous Origin, Font of Magic (2), Metamagic (3) |
| Warlock | d8 | WIS, CHA | dagger, leather armor; light crossbow, 20 bolts, component pouch | Pact Magic (CHA, known caster, slots recover on a short rest): Eldritch Blast (one beam at level 1), Chill Touch, Hex (bonus action: +1d6 necrotic on the caster's hits against the target until the encounter ends) | Otherworldly Patron, Eldritch Invocations (2), Pact Boon (3) |
| Wizard | d6 | INT, WIS | quarterstaff; 2 daggers, spellbook, component pouch | Spellcasting (INT, prepared from a spellbook of six): Fire Bolt, Ray of Frost, Magic Missile, Mage Armor | Arcane Recovery, Arcane Tradition (2), ritual casting |

Notes:

- Spell slots per level follow the SRD tables (full casters 2, 3, 4+2, 4+3, 4+3+2 for levels 1-5; the
  warlock's pact slots 1, 2, then 2 of 2nd level, then 2 of 3rd level at 5). Paladin and Ranger have no
  spells at level 1 in the SRD; their level-2 spellcasting is a later task (their spell lists are already
  in the data for the level-up screen, 8.6).
- Hex is the only SRD 5.2 spell in the data (`"source": "SRD 5.2"`); everything else is SRD 5.1. See
  `docs/licensing.md` for the two attribution statements.
- Armor proficiency is not enforced in M2; shields need an empty off hand.
- Subclasses: each class gets its SRD subclass when its subclass level is implemented.

Multiclassing: **Proposal (needs owner sign-off):** not at launch; reconsider after Early Access.

### 8.3 Leveling pace

**Owner decision (2026-10-26):** characters level as they advance through a set, by SRD experience points
from kills. When players win an encounter, the XP of every monster that died in it is split evenly (integer
division, remainder to nobody) among the players who were in that encounter and are alive at its end. A
level gained applies at once, with average hit points. The level cap is 20. The earlier proposal of
milestone leveling (one level per instance, applied in the safe zone) is withdrawn.

Because XP is split, a solo levels faster than a party, and a player who clears side areas levels faster
than one who does not. Encounter budgets are therefore written per floor for a solo at the level a
full-clear solo reaches there; see 5.4 for the first set's expected levels for solos and parties.

**Owner decision (playtest round 1):** every living player who takes the stairs of a floor earns a
floor-clear bonus of 100 XP (not split), so progress through the dungeon itself is rewarded and a solo who
clears floor 1 reaches level 2 on the way down (5.4).

### 8.4 Deepest-floor badge

The deepest floor a player has ever reached with a given class is shown next to their name and level,
for example `Mira  Lv 7  Rogue  [Deepest 38]`. **Proposal (needs owner sign-off):** the record is per
account and per class, is never lost on death, and counts a floor as "reached" when the player arrives on
it. Separate records for PVP, PVE and Offline, displayed only on the matching server type.

### 8.5 Items and inventory

**Owner request (playtest round 1):** characters carry items: potions, throwing weapons, ammunition and
gear found in chests and on monsters. Item data lives in `data/items/` (one SRD item per file; weapons
point at `data/weapons/`), loot tables in `data/loot/`.

- **Inventory screen (Tab):** lists everything the character carries with quantities (potions, ammunition,
  thrown weapons and gold stack), the total weight and the gold count. From it a player equips, unequips
  and uses items. Out of combat this is free; in combat equipping a weapon is the free object interaction,
  donning or doffing armor is not allowed, and drinking a potion takes the item's action.
- **Slots:** `main_hand` (a weapon), `off_hand` (a shield, or a light weapon later), `armor` (one suit).
  Equipping armor or a shield updates AC at once; equipping a weapon rebuilds the attack list. A shield
  needs the off hand free; a two-handed weapon needs both hands.
- **Starter kits:** every class starts with its SRD-flavoured kit (8.2): the equipped weapon and armor plus
  carried extras, always 2 potions of healing, 5 rations and 10 gp.
- **Consumables:** Potion of Healing (2d4 + 2) and Potion of Greater Healing (4d4 + 4) take an action and
  target the drinker in M2 (feeding a potion to a dying ally is a later "touch" target). Rations, torches
  and tools are carried flavour for now.
- **Thrown and ranged weapons:** thrown weapons are used up when thrown and ammunition is used up per shot
  (7.6); keep a stack. Each attack in the HUD shows its kind (melee, ranged, thrown) and range.
- **Chests by the stairs:** every floor has a visible treasure chest within 3 tiles of its staircase,
  rolling the `starter_gear` table twice: low-level weapons, light and medium armor, a shield,
  ammunition, potions, gold, or nothing. It is the safety net for a character who arrives under-equipped.
- **Hidden chests:** every floor's optional side area hides a chest (`"hidden": true`) rolling the
  better `hidden_cache` table (two rolls: healing, medium armor, martial weapons, more gold). A hidden
  chest is drawn only once a player is adjacent to it. **Proposal (needs owner sign-off):** later a
  passive Wisdom (Perception) or an active Intelligence (Investigation) check reveals it from further away.
- **Monster drops:** every monster names a loot table. Vermin and weak foes (giant rats, centipedes,
  kobolds, goblins, skeletons, zombies) roll `monster_small`, which drops nothing more than half the time;
  hobgoblins, bugbears, ghouls and giant spiders roll `monster_medium`; the set boss rolls `boss` three
  times and never comes up empty. **Proposal (needs owner sign-off):** drops are rolled per monster when
  the encounter is won and go to the winning side (personal loot for bosses, 11).
- **More secrets as floors deepen:** **Proposal (needs owner sign-off):** the first set has one hidden
  chest per floor; later sets add more per floor (two from floor 6, three from floor 11, and so on) along
  with hidden doors and trapped chests (5.2), and the hidden tables improve set by set (SRD magic items
  by rarity).
- **Death:** items carried by a fully dead character are destroyed (9.4).

### 8.6 Levelling up

**Owner request:** levelling is an interactive screen, opened from the HUD when a character has enough XP
(8.3). XP still applies at once in combat (hit points and proficiency go up immediately, so a fight is
never paused); the choices below are made on the screen, out of combat, and the character keeps playing
with defaults until they are confirmed.

- **Hit points:** take the class average (hit die / 2 + 1) or roll the hit die (minimum 1), plus the
  Constitution modifier. **Proposal (needs owner sign-off):** online servers allow only the average.
- **Spell slots:** the new slot row from the class table, shown as "+1 1st-level slot" and so on.
- **Spells:** known casters (Bard, Sorcerer, Warlock, Ranger) learn up to `spells_known[level]` spells
  from their `spell_list` and may swap one known spell per level; cantrips grow at levels 4 and 10
  (`cantrips_known`). Prepared casters (Cleric, Druid, Paladin, Wizard) re-pick their prepared list
  (casting modifier + level, or + half level for the Paladin) after every long rest, not only on level up.
  The Wizard adds `spellbook_learn_per_level` (2) spells of a level it can cast to its spellbook each level
  and prepares from the book (it starts with six level-1 spells). Spells marked unsupported (area and
  condition spells) are shown greyed out with "coming later".
- **Ability Score Improvement** at levels 4, 8, 12, 16 and 19 (Fighter also 6 and 14, Rogue also 10):
  +2 to one ability or +1 to two, maximum 20. The SRD 5.1 has one feat (Grappler), so feats are deferred.
- **Features:** the list from `features_by_level` for the new level with a one-line summary; features
  without M2 mechanics say so.
- The screen confirms everything at once; the server validates the choices against the class data.

## 9. Death and reset

### 9.1 Dying under SRD rules

- At 0 hit points a character falls unconscious and makes death saving throws at the start of each of its
  turns (DC 10; three successes: stable; three failures: dead; natural 20: regain 1 hit point; natural 1:
  two failures). Damage while at 0 HP counts as a failure (a critical hit counts as two).
- Massive damage (remaining damage equal to or greater than the hit point maximum) kills outright.
- Allies can stabilise a dying character with a DC 10 Wisdom (Medicine) check or any healing.

### 9.2 What "fully dies" means

**Proposal (needs owner sign-off):** a character fully dies when it is dead under SRD rules and has not
been returned to life within 10 rounds (1 minute, the Revivify window) if in an encounter, or 60 seconds
of real time if outside one. During that window the body stays on the map and allies may use SRD
revival magic. After the window, the death is final and the character is reset.

### 9.3 Party wipe

**Owner decision (2026-10-26):** solo players get their death saves before a party wipe is declared ("only
fair"), and the same rule applies to parties.

- A side is still **in the fight** while at least one member is conscious or dying (at 0 hit points, not
  dead, not stable, still rolling death saves). An encounter ends when at most one side is still in the
  fight; that side wins.
- While every player is down but someone is still dying, the fight continues: downed players roll their
  death saves at the start of their turns and the monsters keep acting. Monsters prefer conscious enemies;
  when none are left they attack the dying (with advantage, and hits within 5 feet are critical hits, each
  worth two failed death saves). They never attack stable or dead characters.
- When no player is conscious or dying (all stable or dead) while hostiles remain, it is a **party wipe**:
  the monsters win and every member of the party, including those unconscious but stable, is reset.
- Monsters never make death saves: at 0 hit points they die.

### 9.4 What reset means

A reset character returns to floor 1 at level 1 with no equipment beyond class starting equipment and
no gold. **Proposal (needs owner sign-off):** what persists across a reset:

| Persists | Wiped |
|---|---|
| Account, cosmetics (purchased and earned) | Levels and XP |
| Deepest-floor records per class | All items, gold, attunements |
| Character name and appearance (player may change them) | Learned spells, chosen feats and subclass |
| Friends list, chat history | Position in the dungeon |

Items carried by a fully dead character are destroyed, not dropped (no loot pinata for gankers; strong
economy sink). See Open question 3.

## 10. Safe zones

A safe zone sits between every pair of instances (after floors 5, 10, ..., 95). It is a shared social space
with no combat of any kind.

- Entering counts as a long rest (full hit points, spent Hit Dice regained up to half the total, all spell slots and
  long-rest features restored). Levels are earned from XP during the instance (8.3), not on entry.
- Trade between players, an SRD-priced merchant for basic gear, chat, and logging off with progress kept.
- **Global text chat:** every safe zone carries a global text channel shared across all safe zones of that
  server type (PVP or PVE), so the whole population can talk, recruit and trade-talk regardless of depth.
  It is text only; voice does not exist in safe zones.
- Disband and regroup: players may leave their party, form a new one and queue for the next instance
  solo or with up to 4 others.
- **Proposal (needs owner sign-off):** each safe zone is a separate lightweight "hub" server per server
  type (PVP hubs and PVE hubs are separate) and only characters at that depth can enter it, so safe zone
  10 is populated by people about to enter floors 51-55.

## 11. Loot and economy

Sketch only; tuned in M4.

- Loot comes from monster packs, bosses and secret loot rooms; items are SRD equipment and SRD magic
  items, using SRD rarities.
- M2 implements the first slice: items, inventory, starter kits, chests by the stairs, hidden chests and
  monster drops (8.5).
- Gold uses SRD coinage (cp, sp, ep, gp, pp) and SRD prices for mundane gear.
- **Proposal (needs owner sign-off):** boss loot is rolled per player (personal loot) so 100-player
  instances do not fight over drops; secret loot rooms are one chest per player per visit.
- Trading only happens in safe zones, through a two-sided confirmation window logged by the server.
- Sinks: permadeath destroys items; consumables; spell components with gold cost (for example the
  diamonds for revival magic); merchant purchases.
- Real money buys cosmetics only: character skins, portrait frames, nameplate styles, emotes, safe zone
  decorations. Never stats, items, revives, XP or convenience that affects survival.

## 12. Social

- **Party:** up to 5 players; shared party chat; party members see each other on the floor map.
- **Matchmaking:** queue solo or as a party for the instance matching your depth; solo players can opt
  in to be grouped with other solo players. **Proposal (needs owner sign-off):** a looking-for-group board
  in each safe zone shows class, level and deepest-floor badge.
- **Proximity voice chat:** inside an instance, players hear each other by voice when they are within
  earshot on the same floor. Volume falls off with tile distance and is cut by walls, so a party coordinates
  freely while rivals must get close to overhear. Push-to-talk by default with an open-mic option; per-player
  mute; voice is off entirely in safe zones. On PVE servers this is party-plus-nearby-strangers; on PVP
  servers it is also a tactical signal (talking can give you away). **Proposal (needs owner sign-off):**
  hearing radius of 12 tiles (60 ft), with full volume inside 4 tiles; combat does not change the radius.
- **Chat:** party, floor-local (proximity) and the safe zone global text channel; whispers between friends.
  Profanity filter on by default. Report and block tools from M5 cover voice (mute, report with a short
  server-side voice buffer for review) as well as text.

## 13. Postgame

Clearing floor 100 ends the main journey "for now". The player may then:

- make another character (deepest-floor records are kept per class, so a new class is a new goal), or
- take part in postgame activities. **Proposal (needs owner sign-off):** "Floor 101" is a single, very
  large, replayable floor for level-20 characters with weekly rotating modifiers and a leaderboard. It is
  the only place in the game where content may be procedurally varied. Death on floor 101 is still
  permanent.

## 14. Open questions

1. **PVP scaling between levels.** With XP leveling, players on a floor can differ by a level or two
   (solo or party, side areas cleared or not), and instance 1 mixes fresh characters with returning
   veterans' new characters. Do we scale, protect low
   levels, or accept it?
2. **Griefing at stairs and arrival points.** Is arrival protection plus a no-PVP ring around stairs
   enough, or do we need more (for example, staggered arrival positions)?
3. **What persists across death?** The table in 9.4 is a proposal; is destroying items right, or should
   PVP kills drop loot for the killer?
4. **Offline save protection.** How strongly do we protect offline saves from tampering, given offline
   characters never go online? Is HMAC signing (TDD) enough, or should we not care?
5. **Latency and turn timers.** Is 30 seconds right? How do reaction prompts work at 150 ms or more
   latency without stalling 20 creatures?
6. **Producing 100 handcrafted floors.** What is the realistic production rate for a small team, and do
   we use a kit of reusable rooms to reach 100?
7. **Population and the revolving door.** What happens when an instance is full but a party in the
   safe zone is waiting: queue time limit, or spin up a new instance?
8. **Combat time bubbles.** Inside an encounter time is turn-based; outside it real time continues. Is it
   acceptable that a long fight lets other parties overtake you?
9. **Disconnects.** What happens to a character whose connection drops mid-encounter? Proposal so far: the
   character takes the Dodge action each turn for up to 3 minutes, then is removed safely or dies?
10. **Spell selection.** Which SRD spells ship at launch, and how do we handle spells that break a
    shared, persistent dungeon (teleportation, scrying, plane shift)?
11. **Long-duration effects.** How do 8-hour or 24-hour SRD spell durations map onto a game that has no
    real clock between rests?
12. **Bosses in a shared instance.** If two parties fight the same boss, do they share one encounter?
    How is credit and loot assigned?
13. **SRD version.** Do we build on SRD 5.1 or SRD 5.2 rules? (Licensing allows both; mixing them per
    mechanic is confusing.)
14. **Character slots.** How many characters can an account have per server type?
15. **Region and server count.** How many PVP and PVE servers per region at launch?
16. **Floor 100 completion.** What happens to the character after clearing floor 100: retired to a hall
    of fame, kept for floor 101, or both?
17. **Voice transport and cost:** which voice stack (Steam Voice via a Steamworks wrapper, or a WebRTC/Opus
    mesh) do we use, is audio relayed through the instance server or peer-to-peer, and what does it cost at
    100 players per instance?
18. **Voice moderation:** how long is the server-side voice buffer kept for reports, who reviews it, and what
    are the privacy and regional-law implications of recording player voice at all?
19. **Solo difficulty and the party-wipe rule: resolved (owner, 2026-10-26).** Floor 1 of a set is
    relatively easy and difficulty climbs to floor 5, which is very difficult for a solo fighting head-on;
    players level through the set as they go (8.3). Solo players get their death saves before a party wipe
    is declared (9.3). Every five-floor set shares one theme. The first set's design and the floor-1
    measurement that raised the question are in 5.4.

## 15. Glossary

| Term | Meaning |
|---|---|
| 5e SRD | The System Reference Document for the fifth edition rules, used under CC-BY-4.0. See [licensing.md](licensing.md). |
| Floor | One handcrafted dungeon level. There are 100. |
| Instance | A group of 5 consecutive floors hosted by one server process for ~100 players. |
| Set | The five floors of an instance, sharing one theme and listed in a set manifest (`floors/set_NN.json`). |
| Revolving door | Admitting new parties to an instance's first floor as others leave its last floor. |
| Safe zone | Combat-free social space between instances; entering is a long rest. |
| Encounter | A bounded tile region with its own initiative order where combat is turn-based. |
| Encounter zone | An authored region on a floor where encounters with placed monsters form. |
| Intent | A request from a client ("attack goblin 3 with longsword"); the server decides the outcome. |
| Short rest | SRD short rest; granted on taking the stairs down. |
| Long rest | SRD long rest; granted on entering a safe zone. |
| Full death | Dead under SRD rules and not revived in time; triggers reset. |
| Party wipe | No party member conscious or still dying (all stable or dead) while hostiles remain; resets the whole party. |
| Reset | Return to floor 1 at level 1 with levels and loot wiped. |
| Deepest-floor badge | Deepest floor reached per class, shown beside name and level. |
| PVP / PVE server | Server types with and without player-versus-player combat. |
| Offline mode | Single-player mode that runs the same server code locally. |
