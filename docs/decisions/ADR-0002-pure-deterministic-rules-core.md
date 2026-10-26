# ADR-0002: A pure, deterministic rules core

## Status

Accepted 2026-10-26

## Context

The game is defined by 5e SRD rules: dice, ability checks, initiative, attacks, damage, death saving
throws, rests and leveling. The same rules must run in three places:

1. the authoritative instance server (online play),
2. the offline client (single-player runs the server logic in-process),
3. headless automated tests in CI.

If rules code depends on nodes, scenes, autoloads, frame time or the global random number generator,
it cannot be shared cleanly between these hosts, and bugs cannot be reproduced. Online disputes ("that
roll was wrong") and balance analysis also need outcomes that can be replayed exactly.

## Decision

- All rules code lives in `src/core/` (`rng`, `dice`, `rules`, `combat`, `content`).
- Every class there extends **`RefCounted`** and declares a **`class_name`**. Never `Node`, never scenes,
  never autoload singletons, never engine services such as `Time` or `OS`.
- **All randomness flows through an injected, seeded RNG object** from `src/core/rng`. `randi()`,
  `randf()`, `randomize()` and any global RNG are forbidden in `src/core`.
- Rules math uses integers. Time is passed in explicitly (rounds, turns), never read from a clock.
- Core functions return result objects that record every roll and modifier, so hosts can display,
  broadcast and log them.
- Inside `src/core`, refer to other classes by `class_name` rather than `preload` paths.
- `src/core` depends on nothing in the repository; everything else may depend on it.

## Consequences

### Positive

- Identical behaviour on server, offline client and tests: one implementation of the rules.
- Determinism: same seed + same content + same intents = same transcript. Bugs reproduce from a log;
  replay tests are possible; the server can audit outcomes.
- Fast, simple unit tests with no scene tree setup.
- Clear boundary for contributors: if it is a rule, it goes in `src/core` and has a test.

### Negative

- Hosts must translate between nodes and core data (positions, markers, entities), which is extra glue
  code in `src/server` and `src/client`.
- Developers cannot use convenient engine features (signals on nodes, timers, `randi()`) in rules code.
- Determinism is fragile: a single extra RNG call changes every later roll. Tests that pin roll
  sequences will break on legitimate changes and must be updated deliberately.
- Seeds must be protected on the server; leaking one would let clients predict rolls.
