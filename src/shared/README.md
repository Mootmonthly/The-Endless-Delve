# src/shared — network message definitions (stub)

Typed definitions of the messages exchanged between client and server:
client intents (move, attack, cast, end turn, chat, trade) and server events
(state snapshots, roll results, initiative changes, encounter start/end).
Both `src/server/` and `src/client/` depend on this folder; it depends on
nothing but `src/core/` value types.
Keep messages small, versionable and serialisable to plain Dictionaries.
