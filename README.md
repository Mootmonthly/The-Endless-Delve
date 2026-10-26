# The Endless Delve

A hundred floors down, and every one of them wants you dead.

The Endless Delve is a 2D, top-down multiplayer dungeon crawl built on the
5e SRD rules. You roll a character, fill in your sheet and step onto floor 1
of a single, handcrafted dungeon that is the same for everyone. Explore in
real time; the moment steel is drawn, the area locks into a turn-based
encounter where everyone nearby rolls initiative, and anyone who wanders in
joins the fight. Floors are grouped into five-floor instances shared by around
a hundred players, so the people on the stairs beside you may be allies,
rivals or (on PvP servers) a threat. Every descent is a short rest, every
fifth floor is a safe zone for trading, chatting and a long rest, and death
is final: fall, and you start again from floor 1 with nothing. Your deepest
floor reached is shown beside your name. Solo offline play is supported too.

**Status:** pre-alpha, M0 bootstrap.

## Requirements

- [Godot 4.5 stable](https://godotengine.org/download) (standard build; no C#)

## Open, run, test

- **Open:** launch Godot, *Import*, and select this folder's `project.godot`.
- **Run:** press F5 in the editor, or `godot --path .`
- **Test (headless):**

  ```
  godot --headless --path . --import
  godot --headless --path . -s res://tests/run_tests.gd
  ```

  The runner exits non-zero on any failure; CI runs the same commands.

## Repository map

| Path | Contents |
| --- | --- |
| `src/core/` | Pure, deterministic rules engine (dice, rules, combat, content loading) |
| `src/server/` | Authoritative instance server (stub) |
| `src/client/` | Presentation layer (stub) |
| `src/shared/` | Client/server message definitions (stub) |
| `data/` | JSON content from the SRD (classes, monsters, ...) |
| `scenes/` | Godot scenes (currently a minimal boot scene) |
| `tests/` | In-house headless test runner and tests |
| `docs/` | Design and technical documents |

## Documentation

- [Game design document](docs/gdd.md)
- [Technical design document](docs/tdd.md)
- [Roadmap](docs/roadmap.md)
- [Licensing notes](docs/licensing.md)
- Contributor / AI-session guide: [CLAUDE.md](CLAUDE.md)

## Licensing

The game's own code and assets: license to be decided by the owner (all
rights reserved until then). Rules content derived from the SRD is used under
CC-BY-4.0, with the following attribution:

This work includes material from the System Reference Document 5.1 (“SRD 5.1”) by Wizards of the Coast LLC, available at https://dnd.wizards.com/resources/systems-reference-document. The SRD 5.1 is licensed under the Creative Commons Attribution 4.0 International License, available at https://creativecommons.org/licenses/by/4.0/legalcode.

This work includes material from the System Reference Document 5.2.1 (“SRD 5.2.1”) by Wizards of the Coast LLC, available at https://www.dndbeyond.com/srd. The SRD 5.2.1 is licensed under the Creative Commons Attribution 4.0 International License, available at https://creativecommons.org/licenses/by/4.0/legalcode.
