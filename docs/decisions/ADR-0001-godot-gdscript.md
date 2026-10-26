# ADR-0001: Godot 4.5 with statically typed GDScript

## Status

Accepted 2026-10-26

## Context

The Endless Delve is a 2D, top-down, tile-based MMO with turn-based combat, built by a solo or small
indie team. It needs a desktop client for Steam, a headless dedicated server that hosts one five-floor
instance per process, and an offline mode that runs the same server logic locally. The owner's GDD
already names Godot as the engine.

Forces:

- One codebase should cover client, server and tests so a small team is not maintaining two stacks.
- The server must run headless on Linux without a GPU.
- 2D rendering needs are modest; broad hardware support matters more than visual features.
- Contributors (including AI agents working without a running editor) need code that is easy to read and
  where mistakes surface early.
- The engine licence must allow commercial release with no royalties.

## Decision

- Use **Godot 4.5 stable** for client, server and tooling. `project.godot` lists `"4.5"` in
  `config/features`.
- Use **GDScript only**. No C#, no GDExtension in M0-M3. A GDExtension may be introduced later only for
  a profiled hot path or for Steamworks, and only through a new ADR.
- **Static typing everywhere:** typed variables, parameters, return types and typed arrays
  (`Array[int]`, `Array[Creature]`). Use `:=` only where the inferred type is obvious.
- Use the **`gl_compatibility`** renderer.
- The dedicated server is the same project exported with Godot's dedicated server mode and run with
  `--headless`.

## Consequences

### Positive

- One language and one project for client, server, offline mode and tests.
- Godot's MIT licence: no royalties, no revenue thresholds, full source access.
- Headless mode and the high-level multiplayer API (ENet) cover the server and networking needs with no
  extra frameworks.
- Static typing gives parse-time errors, editor completion and measurably faster GDScript.
- `gl_compatibility` runs on older and integrated GPUs, widening the Steam audience.

### Negative

- GDScript is slower than C# or C++ for heavy server simulation; the 100-player instance budget must be
  proven by benchmark (M3), with a GDExtension as the fallback.
- No third-party ecosystem comparable to larger engines for MMO back ends; matchmaking and persistence
  services will be built by us.
- The `gl_compatibility` renderer lacks some 2D effects available in Forward+; art direction must work
  within it.
- Pinning to 4.5 means engine upgrades are deliberate, tested steps.
