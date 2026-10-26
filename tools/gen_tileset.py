#!/usr/bin/env python3
"""Generate the placeholder dungeon tileset: assets/tiles/dungeon_tiles.png.

One row of 32x32 px tiles (the index is the atlas x coordinate used by
TileSet source 0 in assets/tiles/dungeon_tiles.tres and by FloorView):

  0 floor        dark stone with subtle noise
  1 wall         lighter stone blocks with mortar lines
  2 stairs       floor with a down-arrow motif
  3 arrival      floor with a pale circle
  4 zone floor   floor with a faint red hatch
  5 player       blue figure (transparent background)
  6 monster      red figure (transparent background)
  7 unconscious  grey cross marker (transparent background)
  8 selection    yellow ring (transparent background)

Deterministic (fixed seed), so re-running produces an identical file.
Requires Pillow. Usage (from the repo root):
    python3 tools/gen_tileset.py [output.png]
"""

import os
import random
import sys

from PIL import Image, ImageDraw

TILE = 32
TILE_COUNT = 9
SEED = 1001

FLOOR_BASE = (46, 44, 52)
WALL_BASE = (104, 100, 110)
MORTAR = (62, 58, 66)


def noisy_fill(img, x0, base, amount, rng):
    px = img.load()
    for y in range(TILE):
        for x in range(TILE):
            d = rng.randint(-amount, amount)
            px[x0 + x, y] = (base[0] + d, base[1] + d, base[2] + d, 255)


def floor_tile(img, x0, rng):
    noisy_fill(img, x0, FLOOR_BASE, 4, rng)
    draw = ImageDraw.Draw(img)
    # faint flagstone seams
    draw.line([(x0, TILE - 1), (x0 + TILE - 1, TILE - 1)], fill=(38, 36, 43, 255))
    draw.line([(x0 + TILE - 1, 0), (x0 + TILE - 1, TILE - 1)], fill=(38, 36, 43, 255))


def wall_tile(img, x0, rng):
    noisy_fill(img, x0, WALL_BASE, 6, rng)
    draw = ImageDraw.Draw(img)
    for y in (0, 8, 16, 24):
        draw.line([(x0, y), (x0 + TILE - 1, y)], fill=MORTAR + (255,))
    for row, y in enumerate((0, 8, 16, 24)):
        offset = 0 if row % 2 == 0 else 8
        for x in range(offset, TILE, 16):
            draw.line([(x0 + x, y), (x0 + x, y + 7)], fill=MORTAR + (255,))
    # top highlight / bottom shadow for a little depth
    draw.line([(x0, 1), (x0 + TILE - 1, 1)], fill=(130, 126, 136, 255))
    draw.line([(x0, TILE - 1), (x0 + TILE - 1, TILE - 1)], fill=(50, 47, 55, 255))


def stairs_tile(img, x0, rng):
    floor_tile(img, x0, rng)
    draw = ImageDraw.Draw(img)
    # descending steps getting darker
    for i, shade in enumerate((120, 100, 80, 60)):
        y = 6 + i * 5
        draw.rectangle([x0 + 5 + i * 2, y, x0 + 26 - i * 2, y + 3], fill=(shade, shade - 4, shade + 6, 255))
    # down arrow
    draw.polygon([(x0 + 10, 21), (x0 + 22, 21), (x0 + 16, 29)], fill=(230, 210, 120, 255))
    draw.rectangle([x0 + 14, 15, x0 + 18, 21], fill=(230, 210, 120, 255))


def arrival_tile(img, x0, rng):
    floor_tile(img, x0, rng)
    draw = ImageDraw.Draw(img)
    draw.ellipse([x0 + 4, 4, x0 + 27, 27], outline=(200, 214, 230, 255), width=2)
    draw.ellipse([x0 + 12, 12, x0 + 19, 19], fill=(170, 186, 205, 255))


def zone_tile(img, x0, rng):
    floor_tile(img, x0, rng)
    px = img.load()
    for y in range(TILE):
        for x in range(TILE):
            if (x + y) % 6 == 0:
                r, g, b, a = px[x0 + x, y]
                px[x0 + x, y] = (min(255, r + 40), g, b, a)


def figure(img, x0, body, outline):
    draw = ImageDraw.Draw(img)
    draw.ellipse([x0 + 11, 3, x0 + 20, 12], fill=body, outline=outline)          # head
    draw.polygon([(x0 + 16, 12), (x0 + 7, 28), (x0 + 25, 28)], fill=body, outline=outline)  # body
    draw.line([(x0 + 8, 16), (x0 + 24, 16)], fill=outline, width=2)            # arms


def unconscious_tile(img, x0):
    draw = ImageDraw.Draw(img)
    grey = (190, 190, 196, 230)
    draw.line([(x0 + 6, 6), (x0 + 25, 25)], fill=grey, width=4)
    draw.line([(x0 + 25, 6), (x0 + 6, 25)], fill=grey, width=4)


def selection_tile(img, x0):
    draw = ImageDraw.Draw(img)
    draw.ellipse([x0 + 1, 1, x0 + 30, 30], outline=(250, 220, 60, 255), width=2)


def generate():
    rng = random.Random(SEED)
    img = Image.new("RGBA", (TILE * TILE_COUNT, TILE), (0, 0, 0, 0))
    floor_tile(img, 0 * TILE, rng)
    wall_tile(img, 1 * TILE, rng)
    stairs_tile(img, 2 * TILE, rng)
    arrival_tile(img, 3 * TILE, rng)
    zone_tile(img, 4 * TILE, rng)
    figure(img, 5 * TILE, (60, 110, 220, 255), (20, 40, 100, 255))
    figure(img, 6 * TILE, (200, 50, 50, 255), (90, 15, 15, 255))
    unconscious_tile(img, 7 * TILE)
    selection_tile(img, 8 * TILE)
    return img


def main():
    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    out = sys.argv[1] if len(sys.argv) > 1 else os.path.join(root, "assets", "tiles", "dungeon_tiles.png")
    os.makedirs(os.path.dirname(out), exist_ok=True)
    generate().save(out, optimize=True)
    print("wrote %s (%dx%d)" % (out, TILE * TILE_COUNT, TILE))


if __name__ == "__main__":
    main()
