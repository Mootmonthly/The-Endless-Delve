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
PVP servers more skilled and better equipped players. **Proposal (needs owner sign-off):** encounter
budgets follow the SRD encounter-building guidance, targeting "Medium" difficulty packs and "Hard" to
"Deadly" bosses for a 5-character party of the expected level for that floor (see 8.3).

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

**Proposal (needs owner sign-off):** an encounter ends when, at the end of any turn, no two conscious
creatures inside the region are hostile to each other. Then all survivors return to real-time.

- **Fleeing:** a creature that moves out of the region on its turn (provoking opportunity attacks as
  normal) leaves the initiative order and returns to real time. It may re-enter later and will roll
  initiative again.
- Monsters are leashed to their encounter zone and never flee across its boundary.
- If every member of one side has fled, the encounter ends for the remaining side.
- An encounter with no player characters left inside resets: monsters heal to full and return to place.

## 8. Characters and progression

### 8.1 Character sheet

A character is a standard 5e SRD character sheet: six ability scores, ancestry (SRD race/species),
class and level, background, proficiency bonus, skills, saving throws, hit points and Hit Dice, armor
class, speed, features, spell slots, equipment and attunement.

**Proposal (needs owner sign-off):** ability scores use the SRD standard array or point buy only; no
rolled stats online (avoids rerolling abuse and keeps PVP fair). Offline mode may allow rolled stats.

### 8.2 Classes at launch

**Proposal (needs owner sign-off):** classes ship in two waves, each class with its SRD subclass.

| Wave | Classes | Rationale |
|---|---|---|
| Wave 1 (M1-M3) | Fighter, Rogue, Cleric, Wizard | Covers the four classic roles; martial classes first because they need no spell system. |
| Wave 2 (M4) | Barbarian, Bard, Druid, Monk, Paladin, Ranger, Sorcerer, Warlock | The remaining SRD classes once spells, conditions and concentration are solid. |

Multiclassing: **Proposal (needs owner sign-off):** not at launch; reconsider after Early Access.

### 8.3 Leveling pace

**Proposal (needs owner sign-off):** milestone leveling, one level per instance:

| Milestone | Character level |
|---|---|
| Enter floor 1 | 1 |
| Reach safe zone N (after floor 5N) | N + 1 |
| Reach safe zone 19 (after floor 95) | 20 (cap) |
| Floors 96-100 | 20 |

Level-ups are applied during the long rest on safe zone entry. This keeps every character on a given
floor at a predictable level, which makes encounter tuning and PVP balance tractable. Gear, spells
learned and player skill provide differentiation within a floor.

### 8.4 Deepest-floor badge

The deepest floor a player has ever reached with a given class is shown next to their name and level,
for example `Mira  Lv 7  Rogue  [Deepest 38]`. **Proposal (needs owner sign-off):** the record is per
account and per class, is never lost on death, and counts a floor as "reached" when the player arrives on
it. Separate records for PVP, PVE and Offline, displayed only on the matching server type.

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

**Proposal (needs owner sign-off):** a party wipe occurs when, at the end of any turn, no member of the
party is conscious and at least one hostile creature remains conscious in the encounter. Every member
of the party, including those unconscious but stable, is reset. A party whose last enemy dies while all
members are down but stable survives; the members wake with 1 hit point when the encounter ends.

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
  long-rest features restored), and applies the milestone level-up.
- Trade between players, an SRD-priced merchant for basic gear, chat, and logging off with progress kept.
- Disband and regroup: players may leave their party, form a new one and queue for the next instance
  solo or with up to 4 others.
- **Proposal (needs owner sign-off):** each safe zone is a separate lightweight "hub" server per server
  type (PVP hubs and PVE hubs are separate) and only characters at that depth can enter it, so safe zone
  10 is populated by people about to enter floors 51-55.

## 11. Loot and economy

Sketch only; tuned in M4.

- Loot comes from monster packs, bosses and secret loot rooms; items are SRD equipment and SRD magic
  items, using SRD rarities.
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
- **Chat:** party, floor-local (proximity) and safe zone channels; whispers between friends. Profanity
  filter on by default. Report and block tools from M5.

## 13. Postgame

Clearing floor 100 ends the main journey "for now". The player may then:

- make another character (deepest-floor records are kept per class, so a new class is a new goal), or
- take part in postgame activities. **Proposal (needs owner sign-off):** "Floor 101" is a single, very
  large, replayable floor for level-20 characters with weekly rotating modifiers and a leaderboard. It is
  the only place in the game where content may be procedurally varied. Death on floor 101 is still
  permanent.

## 14. Open questions

1. **PVP scaling between levels.** With milestone leveling most players on a floor share a level, but
   instance 1 mixes fresh characters with returning veterans' new characters. Do we scale, protect low
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

## 15. Glossary

| Term | Meaning |
|---|---|
| 5e SRD | The System Reference Document for the fifth edition rules, used under CC-BY-4.0. See [licensing.md](licensing.md). |
| Floor | One handcrafted dungeon level. There are 100. |
| Instance | A group of 5 consecutive floors hosted by one server process for ~100 players. |
| Revolving door | Admitting new parties to an instance's first floor as others leave its last floor. |
| Safe zone | Combat-free social space between instances; entering is a long rest. |
| Encounter | A bounded tile region with its own initiative order where combat is turn-based. |
| Encounter zone | An authored region on a floor where encounters with placed monsters form. |
| Intent | A request from a client ("attack goblin 3 with longsword"); the server decides the outcome. |
| Short rest | SRD short rest; granted on taking the stairs down. |
| Long rest | SRD long rest; granted on entering a safe zone. |
| Full death | Dead under SRD rules and not revived in time; triggers reset. |
| Party wipe | No conscious party member while hostiles remain; resets the whole party. |
| Reset | Return to floor 1 at level 1 with levels and loot wiped. |
| Deepest-floor badge | Deepest floor reached per class, shown beside name and level. |
| PVP / PVE server | Server types with and without player-versus-player combat. |
| Offline mode | Single-player mode that runs the same server code locally. |
