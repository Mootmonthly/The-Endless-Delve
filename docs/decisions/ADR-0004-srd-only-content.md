# ADR-0004: SRD-only rules and content, stored as data

## Status

Accepted 2026-10-26

## Context

The game implements fifth edition tabletop rules. The System Reference Documents (SRD 5.1 and SRD 5.2)
are published under Creative Commons Attribution 4.0, which permits commercial use with attribution.
Material outside the SRD (other books, product identity monsters, settings, named characters) and the
publisher's trademarks are not licensed and would create legal risk for a commercial Steam release.

The game also needs a large amount of content (classes, monsters, items, spells) that designers must be
able to edit without changing code, and that both server and client load identically.

## Decision

- Implement only rules and content found in the SRD (5.1 as the baseline; 5.2 only per mechanic and
  never mixed with 5.1 for the same mechanic).
- In code, data and docs, refer to the rules as **"5e SRD"** or **"SRD rules"**. Trademarks and non-SRD
  names appear only in [licensing.md](../licensing.md), which lists what to avoid.
- Include the CC-BY-4.0 attribution text from licensing.md in the game credits and store page.
- **Content is data:** classes, monsters, items and spells live as JSON under `data/`, one record per
  file, with `id`, `schema_version`, `name` and `source` (for example `"SRD 5.1"`).
- Loaders in `src/core/content` turn JSON into typed definition objects and validate it at boot; any
  error stops the server or offline client from starting.
- Floors are handcrafted Godot scenes using `TileMapLayer`, referencing content by id.

## Consequences

### Positive

- A clear, licensed legal basis for the game's rules.
- Designers add or tune content without touching GDScript; changes are reviewable diffs.
- The `source` field makes audits simple: every record states where it came from.
- Server and client share one content set, verified by a content hash at connect time.

### Negative

- Some well-known monsters, subclasses, spells and feats are unavailable; the game must create its own
  original content to fill gaps, with its own design cost.
- Marketing cannot use the most recognisable brand terms; the store page must explain the game in
  generic language.
- JSON has no compile-time checking; the loader's validation must be thorough and tested.
- Attribution must be maintained across every distribution channel.
