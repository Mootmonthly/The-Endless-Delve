# ADR-0003: Server-authoritative multiplayer, one instance per process

## Status

Accepted 2026-10-26

## Context

The dungeon is split into 20 instances of 5 floors, each holding about 100 players on PVP servers (one
party on PVE servers). Combat is 5e with dice, and permadeath makes every roll high-stakes, so cheating
must be prevented. Players also need an offline mode that plays the whole game solo. The team is small,
so the networking model must be simple enough to build and debug in GDScript.

Options considered briefly: peer-to-peer or client-authoritative (cheap, but cheatable and unfair under
permadeath); one big server process for the whole dungeon (hard to scale and a single point of
failure); one process per instance (natural boundary matching the design).

## Decision

- **Server authority.** The server owns all game state. Clients send **intents** (what they want to do);
  the server validates them, resolves outcomes with the rules core, rolls all dice, and broadcasts
  **results**. Clients never roll dice.
- **One headless Godot process = one dungeon instance** (5 floors, ~100 players). Instances are started
  with an instance id, floor range and server mode, and shut down when empty.
- **Godot high-level multiplayer over ENet.** Intents use `@rpc("any_peer", "call_remote", "reliable")`;
  results use `@rpc("authority", ...)` with the transfer mode written explicitly (`reliable` for
  outcomes, `unreliable_ordered` for position snapshots).
- Exploration is real-time on a fixed server tick; combat is turn-based inside an encounter region owned
  by a server-side state machine. No client-side prediction in M1; clients interpolate.
- **Offline mode runs the same server code in-process**, connected to the client through a local
  transport instead of ENet.
- Matchmaking, lobby and persistence services are separate, later components (M5).

## Consequences

### Positive

- Cheating on rolls, damage, loot or movement is not possible from the client.
- Instance processes scale horizontally and fail independently; a crash affects one instance only.
- Turn-based combat tolerates latency well; only exploration needs smoothing.
- One server implementation serves PVP, PVE and offline play.

### Negative

- Every action has at least one round trip of latency; without prediction, movement will feel slightly
  delayed on poor connections.
- Server hosting costs scale with player count; offline mode cannot be the only test of server load.
- Instances need orchestration (start, monitor, restart, route players), which is extra operations work.
- Moving between instances and safe zones requires a hand-off protocol and persistence that do not
  exist yet.
