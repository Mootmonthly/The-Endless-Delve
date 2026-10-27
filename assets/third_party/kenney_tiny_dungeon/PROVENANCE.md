# Kenney "Tiny Dungeon" (1.0)

| Field | Value |
|---|---|
| Pack | Tiny Dungeon 1.0 (132 tiles, 16 x 16 px) |
| Author | Kenney (www.kenney.nl) |
| Source page | https://kenney.nl/assets/tiny-dungeon |
| Download | https://kenney.nl/media/pages/assets/tiny-dungeon/f8422efb44-1674742415/kenney_tiny-dungeon.zip (SHA-256 `c109438ab06f65fd80f9b2686a4cf9c7c11dc64444b47333ec71d602f8bb5fc7`) |
| Licence | Creative Commons Zero (CC0 1.0), http://creativecommons.org/publicdomain/zero/1.0/ — stated on the pack's page and in its `License.txt` ("This content is free to use in personal, educational and commercial projects. Support us by crediting Kenney or www.kenney.nl (this is not mandatory)") |
| Retrieved | 2026-10-27 |
| File kept here | `tilemap_packed.png` (the pack's `Tilemap/tilemap_packed.png`, unmodified; SHA-256 `d24e60a41e4ac7a745c0304dfde121143688557f40215f23221c29cfe683825f`) |

CC0 needs no attribution; we credit Kenney anyway (README / docs/licensing.md).

Used by `tools/build_tiles.py` (scaled x2, nearest filtering) for these atlas tiles in
`assets/tiles/dungeon_tiles.png`: barrel and barrel_damaged (tile 82), rubble and rubble_damaged
(tile 24, background keyed out), decal_holes (tile 12, keyed), gravestone_a / gravestone_b (64, 65),
chest_closed / chest_open (89, 91). Every other tile in the atlas is drawn by the tool itself.
