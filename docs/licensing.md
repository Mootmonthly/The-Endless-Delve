# Licensing

> This is not legal advice. It is the project's working understanding, written so contributors make
> consistent choices. The owner should have a lawyer review it before any public release.

This is the only file in the repository allowed to name the trademarks and non-SRD terms listed
below, and only to explain that we must avoid them. Everywhere else, say "5e SRD" or "SRD rules".

## What the SRD licences permit

| Document | Licence | Rules edition | Notes |
|---|---|---|---|
| SRD 5.1 | Creative Commons Attribution 4.0 International (CC-BY-4.0) | Fifth edition, 2014 rules | Released under CC-BY-4.0 in 2023. Baseline for this project. |
| SRD 5.2 | CC-BY-4.0 | Fifth edition, 2024 revision | Released 2025. Usable, but do not mix 5.1 and 5.2 versions of the same mechanic. |

CC-BY-4.0 lets us copy, adapt and sell material from the SRD, including in a commercial game, provided
we give attribution, indicate that we changed it, and do not suggest the licensor endorses us. It grants
no trademark rights.

Game mechanics themselves (for example "roll a d20, add a modifier, compare to a target number") are
generally not protected by copyright; the specific expression of them (text, names of unique creatures
and places, artwork, layout) is. Using the SRD under CC-BY gives us a clear, licensed basis for both the
mechanics and the SRD wording, so we do not need to rely on that distinction.

## Required attribution

The following text must appear in the game's credits, on the Steam store page's legal section, and in
the repository (this file and the Licensing section of the top-level README). Copy it exactly:

> This work includes material from the System Reference Document 5.1 (“SRD 5.1”) by Wizards of the
> Coast LLC, available at https://dnd.wizards.com/resources/systems-reference-document. The SRD 5.1 is
> licensed under the Creative Commons Attribution 4.0 International License, available at
> https://creativecommons.org/licenses/by/4.0/legalcode.

The game also uses SRD 5.2.1 material (currently one spell, Hex, in `data/spells/hex.json` with
`"source": "SRD 5.2"`; no mechanic exists in both a 5.1 and a 5.2 version). Its attribution, copied from
the SRD 5.2.1 document itself, must appear alongside the one above:

> This work includes material from the System Reference Document 5.2.1 (“SRD 5.2.1”) by Wizards of the
> Coast LLC, available at https://www.dndbeyond.com/srd. The SRD 5.2.1 is licensed under the Creative
> Commons Attribution 4.0 International License, available at https://creativecommons.org/licenses/by/4.0/legalcode.

**Action item:** add this second statement to the Licensing section of the top-level README and to the
credits.

Every record in `data/spells/` carries a `source` field ("SRD 5.1" or "SRD 5.2"); a spell found in
neither SRD does not go in, even when a design brief asks for it.

We should also state in the credits that the material has been adapted for a video game.

## Never use

The following are not in the SRD (or are trademarks) and must never appear in code, data, assets,
UI text, docs (outside this file), store pages or marketing:

| Category | Examples |
|---|---|
| Trademarks | "Dungeons & Dragons", "Dungeons and Dragons", "D&D", the ampersand-dragon logo, "Wizards of the Coast" (except inside the attribution text above) |
| Book titles | "Player's Handbook", "Dungeon Master's Guide", "Monster Manual" |
| Product identity monsters | beholder, mind flayer, illithid, displacer beast, umber hulk, yuan-ti, githyanki (and githzerai), carrion crawler, slaad |
| Named settings and places | Forgotten Realms, Greyhawk, Eberron, Ravenloft, Baldur's Gate, Waterdeep, Faerun |
| Named characters | Any named setting character or deity, including wizard names attached to spells outside the SRD (the SRD uses generic names such as "Arcane Hand") |
| Non-SRD rules text | Subclasses, feats, spells, backgrounds and monsters from other books |

When in doubt, check that the item appears in the SRD and record the SRD version in the content
record's `source` field. If it is not in the SRD, it does not go in.

**Proposal (needs owner sign-off):** add a CI step that greps code, data and docs (excluding this file)
for the terms above and fails the build on a match.

## Store page and marketing

The Steam store page, trailers, social posts and press kit must not use the trademarks above,
including in tags, keywords or comparisons ("like D&D"). Acceptable phrasing: "built on the 5e SRD
rules", "fifth edition compatible tabletop rules", "classic tabletop RPG rules".

**Action item for the owner:** the original GDD keyword list includes "Dungeons and Dragons". Replace
that keyword before creating the store page (suggested: "Tabletop RPG", "Turn-Based Tactics",
"Dungeon Crawler").

## The game's own code and assets

**Proposal (needs owner sign-off):** the project's own code, data files (beyond SRD-derived text) and
assets are proprietary, all rights reserved, for now. Decide before any public release whether to
keep it proprietary or open some of it (for example the rules core) under a permissive licence. Until
then, do not add a LICENSE file that grants rights. Third-party assets and plugins may only be added if
their licence allows commercial use and is recorded in a `THIRD_PARTY.md` (to be created when the first
one is added).
