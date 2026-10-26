# src/server — authoritative instance server (stub)

One headless Godot process = one dungeon instance (5 floors, ~100 players).
Code here will own the authoritative world state: player sessions, real-time
exploration, encounter regions and their initiative order.
It calls into `src/core/` (the pure rules engine) for every roll and resolution,
using a seeded RNG it owns. Clients never roll dice; they send intents, the
server resolves them and broadcasts results over ENet.
Offline mode runs this same code in-process with an offline `MultiplayerPeer`.
Matchmaking, lobby and persistence services are later milestones.
