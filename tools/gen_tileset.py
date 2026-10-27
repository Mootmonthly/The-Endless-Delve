#!/usr/bin/env python3
"""Generate the art atlases.

1. assets/tiles/dungeon_tiles.png (+ .tres, .json, light_soft.png) - the
   dungeon tileset, built by tools/build_tiles.py (Round D art refresh). The
   functions below for columns 5-8 (player, monster, unconscious, selection)
   are still used by it; the old one-row placeholder (columns 0-4) is kept
   only as `generate()` for reference.
2. assets/icons/entity_icons.png (+ entity_icons.json, entity_icons.tres) -
   one row of 32x32 icons for classes, monsters and item kinds; see ICONS.
   The json maps an icon id (class id, monster id, item kind, chest_closed /
   chest_open) to its atlas column (x coordinate in TileSet source 0).

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

Deterministic (fixed seed), so re-running produces identical files.
Requires Pillow. Usage (from the repo root):
    python3 tools/gen_tileset.py              # both atlases (+ icon json/tres)
    python3 tools/gen_tileset.py OUT_DIR      # only the dungeon tileset files, into OUT_DIR
"""

import json
import math
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


# ---------------------------------------------------------------------------
# Entity icons: assets/icons/entity_icons.png (one row of 32x32 icons),
# entity_icons.json (id -> column) and entity_icons.tres (TileSet, source 0).
# Icons are drawn at SCALE x size and downsampled for smooth edges. Classes sit
# on a blue disc, monsters on a dark red disc, items have no background.
# ---------------------------------------------------------------------------

SCALE = 4
CLASS_IDS = ["fighter", "rogue", "cleric", "wizard", "barbarian", "bard", "druid", "monk",
             "paladin", "ranger", "sorcerer", "warlock"]
MONSTER_IDS = ["giant_rat", "goblin", "skeleton", "zombie", "kobold", "giant_centipede",
               "hobgoblin", "bugbear", "ghoul", "giant_spider", "ogre"]
ITEM_IDS = ["potion", "weapon", "armor", "shield", "gold", "misc", "ammo", "chest_closed", "chest_open"]
## Extra keys that share a column with another icon (item kinds -> glyph).
ICON_ALIASES = {"consumable": "potion"}

STEEL = (205, 210, 220, 255)
STEEL_DARK = (120, 126, 140, 255)
GOLD = (236, 196, 72, 255)
GOLD_DARK = (150, 110, 30, 255)
WOOD = (140, 92, 50, 255)
WOOD_DARK = (84, 52, 26, 255)
INK = (24, 20, 28, 255)
WHITE = (240, 240, 236, 255)


class Pen:
    """Draws in 32-unit icon coordinates on a SCALE x canvas."""

    def __init__(self):
        self.img = Image.new("RGBA", (TILE * SCALE, TILE * SCALE), (0, 0, 0, 0))
        self.d = ImageDraw.Draw(self.img)

    @staticmethod
    def _p(points):
        return [(x * SCALE, y * SCALE) for x, y in points]

    def poly(self, points, fill, outline=None, width=1):
        self.d.polygon(self._p(points), fill=fill)
        if outline is not None:
            pts = self._p(points)
            self.d.line(pts + [pts[0]], fill=outline, width=max(1, int(width * SCALE)), joint="curve")

    def line(self, points, fill, width=1):
        self.d.line(self._p(points), fill=fill, width=int(width * SCALE), joint="curve")

    def ellipse(self, box, fill=None, outline=None, width=1):
        x0, y0, x1, y1 = box
        self.d.ellipse([x0 * SCALE, y0 * SCALE, x1 * SCALE, y1 * SCALE], fill=fill, outline=outline,
                       width=int(width * SCALE))

    def circle(self, cx, cy, r, fill=None, outline=None, width=1):
        self.ellipse((cx - r, cy - r, cx + r, cy + r), fill, outline, width)

    def rect(self, box, fill, outline=None, width=1):
        x0, y0, x1, y1 = box
        self.d.rectangle([x0 * SCALE, y0 * SCALE, x1 * SCALE, y1 * SCALE], fill=fill, outline=outline,
                         width=int(width * SCALE))

    def arc(self, box, start, end, fill, width=1):
        x0, y0, x1, y1 = box
        self.d.arc([x0 * SCALE, y0 * SCALE, x1 * SCALE, y1 * SCALE], start, end, fill=fill, width=int(width * SCALE))

    def result(self):
        return self.img.resize((TILE, TILE), Image.LANCZOS)


def badge(p, fill, ring):
    p.circle(16, 16, 15, fill=fill, outline=ring, width=1.5)


def class_badge(p):
    badge(p, (30, 46, 92, 255), (120, 160, 235, 255))


def monster_badge(p):
    badge(p, (72, 20, 24, 255), (190, 60, 56, 255))


def star(p, cx, cy, r_out, r_in, n, fill, rot=-math.pi / 2):
    pts = []
    for i in range(n * 2):
        r = r_out if i % 2 == 0 else r_in
        a = rot + i * math.pi / n
        pts.append((cx + r * math.cos(a), cy + r * math.sin(a)))
    p.poly(pts, fill)


def sword(p, x0, y0, x1, y1, blade, guard, width=3.0):
    """A sword from pommel (x0, y0) to tip (x1, y1)."""
    dx, dy = x1 - x0, y1 - y0
    ln = math.hypot(dx, dy)
    ux, uy = dx / ln, dy / ln
    nx, ny = -uy, ux
    gx, gy = x0 + ux * ln * 0.28, y0 + uy * ln * 0.28  # crossguard centre
    hw = width / 2
    p.poly([(gx + nx * hw, gy + ny * hw), (x1 - ux * 2.5 + nx * hw, y1 - uy * 2.5 + ny * hw), (x1, y1),
            (x1 - ux * 2.5 - nx * hw, y1 - uy * 2.5 - ny * hw), (gx - nx * hw, gy - ny * hw)], blade, INK, 0.6)
    p.line([(gx + nx * 5, gy + ny * 5), (gx - nx * 5, gy - ny * 5)], guard, 2.2)
    p.line([(x0 + ux * 1.5, y0 + uy * 1.5), (gx, gy)], WOOD_DARK, 2.2)
    p.circle(x0, y0, 1.8, fill=guard)


# --- classes ---------------------------------------------------------------

def icon_fighter(p):
    class_badge(p)
    sword(p, 16, 27.5, 16, 4.5, STEEL, GOLD, 4.0)


def icon_rogue(p):
    class_badge(p)
    sword(p, 9, 24, 22, 9, (170, 200, 170, 255), (90, 90, 100, 255), 3.0)
    p.ellipse((19, 19, 25, 26), fill=(150, 30, 40, 255))  # blood drop
    p.poly([(22, 15), (19.6, 21), (24.4, 21)], (150, 30, 40, 255))


def icon_cleric(p):
    class_badge(p)
    star(p, 16, 16, 12, 6.5, 8, GOLD)
    p.circle(16, 16, 5.5, fill=(255, 236, 150, 255), outline=GOLD_DARK, width=0.8)


def icon_wizard(p):
    class_badge(p)
    p.line([(9, 27), (20, 11)], WOOD, 2.6)
    star(p, 21.5, 9, 6.5, 2, 4, (170, 220, 255, 255), rot=0)
    p.circle(21.5, 9, 1.8, fill=WHITE)


def icon_barbarian(p):
    class_badge(p)
    p.line([(16, 5), (16, 28)], WOOD, 2.6)
    p.poly([(16, 7), (7, 4), (5, 10), (7, 16), (16, 13)], STEEL, INK, 0.6)
    p.poly([(16, 7), (25, 4), (27, 10), (25, 16), (16, 13)], STEEL, INK, 0.6)


def icon_bard(p):
    class_badge(p)
    c = (250, 214, 120, 255)
    p.ellipse((7, 20, 14, 25.5), fill=c)
    p.ellipse((17, 18, 24, 23.5), fill=c)
    p.line([(13.2, 22.5), (13.2, 8)], c, 1.8)
    p.line([(23.2, 20.5), (23.2, 6)], c, 1.8)
    p.poly([(12.3, 7), (24.1, 5), (24.1, 9), (12.3, 11)], c)


def icon_druid(p):
    class_badge(p)
    leaf = [(16, 4), (22.5, 9), (24, 16), (21, 23), (16, 27), (11, 23), (8, 16), (9.5, 9)]
    p.poly(leaf, (96, 180, 80, 255), (40, 90, 36, 255), 0.8)
    p.line([(16, 6), (16, 28.5)], (40, 90, 36, 255), 1.2)
    for y in (11, 16, 21):
        p.line([(16, y + 2.5), (20.5, y)], (40, 90, 36, 255), 0.9)
        p.line([(16, y + 2.5), (11.5, y)], (40, 90, 36, 255), 0.9)


def icon_monk(p):
    class_badge(p)
    skin = (232, 186, 140, 255)
    edge = (120, 80, 50, 255)
    p.rect((8.5, 12, 23.5, 25), skin, edge, 0.8)
    for x in (8.5, 12.25, 16, 19.75):
        p.ellipse((x, 8.5, x + 3.75, 14), fill=skin, outline=edge, width=0.8)
    p.poly([(8.5, 17), (15, 17), (15, 20), (8.5, 21)], (214, 160, 116, 255), edge, 0.8)  # thumb
    p.rect((10, 25, 22, 28), (230, 120, 40, 255))  # sleeve


def icon_paladin(p):
    class_badge(p)
    shape = [(7, 6), (25, 6), (25, 15), (16, 27), (7, 15)]
    p.poly(shape, WHITE, STEEL_DARK, 1.0)
    p.rect((14.5, 8.5, 17.5, 22), GOLD)
    p.rect((10, 11.5, 22, 14.5), GOLD)


def icon_ranger(p):
    class_badge(p)
    green = (110, 190, 110, 255)
    p.arc((4, 5, 20, 27), 270, 90, WOOD, 2.2)
    p.line([(12, 5.5), (12, 26.5)], (220, 220, 210, 255), 0.7)  # bowstring
    p.line([(6, 16), (27, 16)], (220, 220, 210, 255), 1.2)  # arrow shaft
    p.poly([(27, 16), (23, 13.5), (23, 18.5)], STEEL)
    p.poly([(6, 16), (9, 13), (10, 13), (8, 16), (10, 19), (9, 19)], green)


def icon_sorcerer(p):
    class_badge(p)
    outer = [(16, 3.5), (21, 11), (24, 17), (22.5, 24), (16, 28), (9.5, 24), (8, 17), (11, 12), (13, 15), (14, 9)]
    p.poly(outer, (236, 90, 40, 255))
    inner = [(16, 13), (19.5, 19), (18.5, 24), (16, 26), (13.5, 24), (12.5, 19)]
    p.poly(inner, (255, 214, 90, 255))


def icon_warlock(p):
    class_badge(p)
    eye = [(4, 16), (9, 10.5), (16, 8.5), (23, 10.5), (28, 16), (23, 21.5), (16, 23.5), (9, 21.5)]
    p.poly(eye, (230, 220, 240, 255), (120, 60, 160, 255), 1.0)
    p.circle(16, 16, 5.5, fill=(150, 70, 200, 255))
    p.ellipse((14.8, 11.5, 17.2, 20.5), fill=INK)


# --- monsters --------------------------------------------------------------

def icon_giant_rat(p):
    monster_badge(p)
    fur = (150, 130, 118, 255)
    p.line([(8, 21), (4, 18), (4.5, 12)], (230, 160, 170, 255), 1.4)  # tail
    p.ellipse((7, 14, 21, 24), fill=fur)
    p.poly([(19, 15), (27.5, 20), (19, 23)], fur)
    p.circle(18.5, 14.5, 3, fill=(230, 160, 170, 255), outline=fur, width=1)  # ear
    p.circle(23, 18.5, 1, fill=(250, 40, 40, 255))
    p.line([(10, 24), (10, 26)], fur, 1.4)
    p.line([(17, 24), (17, 26)], fur, 1.4)


def icon_goblin(p):
    monster_badge(p)
    g = (110, 170, 70, 255)
    p.poly([(9, 13), (2.5, 8), (10, 19)], g)
    p.poly([(23, 13), (29.5, 8), (22, 19)], g)
    p.ellipse((9, 8, 23, 26), fill=g)
    p.ellipse((11.5, 13.5, 15, 16.5), fill=(255, 220, 60, 255))
    p.ellipse((17, 13.5, 20.5, 16.5), fill=(255, 220, 60, 255))
    p.line([(12.5, 21.5), (19.5, 21.5)], INK, 1)
    p.poly([(14, 21.5), (15, 23.5), (16, 21.5)], WHITE)


def icon_skeleton(p):
    monster_badge(p)
    bone = (236, 232, 214, 255)
    p.ellipse((8, 5, 24, 21), fill=bone)
    p.rect((11, 18, 21, 25), bone)
    p.ellipse((10.5, 11, 15, 16), fill=INK)
    p.ellipse((17, 11, 21.5, 16), fill=INK)
    p.poly([(16, 16.5), (14.8, 19), (17.2, 19)], INK)
    for x in (13, 15, 17, 19):
        p.line([(x, 21.5), (x, 25)], INK, 0.7)


def icon_zombie(p):
    monster_badge(p)
    skin = (126, 156, 110, 255)
    p.rect((8.5, 6, 23.5, 25), skin, (60, 80, 50, 255), 0.8)
    p.rect((8.5, 6, 23.5, 9), (70, 60, 50, 255))  # hair
    p.circle(12.5, 14, 2.4, fill=(230, 230, 180, 255))
    p.circle(12.5, 14, 0.9, fill=INK)
    p.line([(17.5, 14.5), (21.5, 13.5)], INK, 1.2)  # closed eye
    p.line([(11, 21), (14, 19.5), (17, 21), (20.5, 19.5)], INK, 1.2)
    p.line([(19, 7), (22, 11)], (180, 60, 60, 255), 0.8)  # stitches
    for t in (0.3, 0.6):
        x, y = 19 + 3 * t, 7 + 4 * t
        p.line([(x - 1, y + 0.7), (x + 1, y - 0.7)], (180, 60, 60, 255), 0.6)


def icon_kobold(p):
    monster_badge(p)
    s = (210, 110, 50, 255)
    p.ellipse((6, 8, 18, 22), fill=s)
    p.poly([(14, 11), (28, 15.5), (27, 19), (14, 21)], s)  # snout
    p.poly([(9, 10), (5, 4), (12, 8.5)], (240, 220, 190, 255))  # horn
    p.circle(13.5, 13.5, 1.6, fill=(255, 230, 60, 255))
    p.line([(18, 18.5), (26.5, 18)], INK, 0.8)
    p.poly([(9, 22), (16, 21), (14, 27), (9, 27)], s)  # neck


def icon_giant_centipede(p):
    monster_badge(p)
    body = (176, 100, 50, 255)
    pts = [(6 + i * 2.6, 16 + 6 * math.sin(i * 0.8)) for i in range(8)]
    for i, (x, y) in enumerate(pts):
        p.line([(x, y - 4), (x - 1, y - 6.5)], (90, 50, 20, 255), 0.8)
        p.line([(x, y + 4), (x - 1, y + 6.5)], (90, 50, 20, 255), 0.8)
    for x, y in pts:
        p.circle(x, y, 2.9, fill=body, outline=(90, 50, 20, 255), width=0.6)
    hx, hy = pts[-1]
    p.circle(hx + 1, hy, 3.4, fill=(120, 60, 30, 255))
    p.line([(hx + 3, hy - 2), (hx + 6, hy - 5)], (90, 50, 20, 255), 0.8)
    p.line([(hx + 3, hy + 2), (hx + 6, hy + 5)], (90, 50, 20, 255), 0.8)


def icon_hobgoblin(p):
    monster_badge(p)
    s = (214, 96, 60, 255)
    p.ellipse((9, 9, 23, 27), fill=s)
    p.ellipse((8, 4, 24, 16), fill=STEEL_DARK)  # helmet dome
    p.rect((8, 11.5, 24, 13.5), STEEL)
    p.rect((15, 11.5, 17, 20), STEEL)  # nose guard
    p.ellipse((11, 15, 14.5, 17.5), fill=(255, 220, 60, 255))
    p.ellipse((17.5, 15, 21, 17.5), fill=(255, 220, 60, 255))
    p.line([(12.5, 23), (19.5, 23)], INK, 1)


def icon_bugbear(p):
    monster_badge(p)
    fur = (128, 84, 46, 255)
    p.circle(8.5, 8.5, 3.5, fill=fur)
    p.circle(23.5, 8.5, 3.5, fill=fur)
    p.ellipse((5, 6, 27, 28), fill=fur)
    p.ellipse((10, 16, 22, 26), fill=(206, 166, 110, 255))  # muzzle
    p.circle(12, 13, 1.6, fill=(255, 230, 60, 255))
    p.circle(20, 13, 1.6, fill=(255, 230, 60, 255))
    p.ellipse((14, 17, 18, 19.5), fill=INK)
    p.line([(13, 22.5), (19, 22.5)], INK, 1)


def icon_ghoul(p):
    monster_badge(p)
    s = (176, 164, 196, 255)
    p.poly([(9, 8), (23, 8), (24.5, 15), (20, 27), (12, 27), (7.5, 15)], s)
    p.ellipse((10.5, 12, 15, 17), fill=INK)
    p.ellipse((17, 12, 21.5, 17), fill=INK)
    p.circle(12.8, 14.5, 1, fill=(140, 255, 140, 255))
    p.circle(19.2, 14.5, 1, fill=(140, 255, 140, 255))
    p.rect((12.5, 20.5, 19.5, 23.5), INK)
    for x in (13.2, 15.4, 17.6):
        p.poly([(x, 20.5), (x + 1.8, 20.5), (x + 0.9, 23)], WHITE)


def icon_giant_spider(p):
    monster_badge(p)
    leg = (176, 166, 186, 255)
    for side in (-1, 1):
        for i, (ky, fy) in enumerate([(9, 5), (13, 11), (18, 20), (21, 27)]):
            kx = 16 + side * (8 + (i % 2))
            fx = 16 + side * 13
            p.line([(16, 15 + i), (kx, ky), (fx, fy)], leg, 1.3)
    p.ellipse((10, 14, 22, 27), fill=(52, 46, 60, 255), outline=leg, width=0.8)
    p.circle(16, 12, 4.5, fill=(52, 46, 60, 255), outline=leg, width=0.8)
    for x in (14, 16, 18):
        p.circle(x, 11, 0.9, fill=(255, 50, 50, 255))
    p.poly([(16, 17), (14, 20), (16, 23), (18, 20)], (200, 40, 40, 255))


def icon_ogre(p):
    monster_badge(p)
    s = (196, 170, 112, 255)
    p.ellipse((4.5, 6, 27.5, 29), fill=s)
    p.line([(9, 12), (23, 12)], (90, 70, 40, 255), 2.2)  # unibrow
    p.circle(11.5, 15, 1.5, fill=INK)
    p.circle(20.5, 15, 1.5, fill=INK)
    p.ellipse((13.5, 15.5, 18.5, 20), fill=(170, 140, 90, 255))
    p.rect((9, 22, 23, 25.5), (90, 50, 40, 255))
    p.poly([(10, 25.5), (11.5, 19.5), (13, 25.5)], WHITE)  # tusks
    p.poly([(19, 25.5), (20.5, 19.5), (22, 25.5)], WHITE)


# --- items -----------------------------------------------------------------

def icon_potion(p):
    p.rect((13, 4, 19, 7.5), WOOD)  # cork
    p.rect((13.5, 7, 18.5, 13), (200, 220, 230, 200), (90, 110, 120, 255), 0.8)
    p.circle(16, 20, 8.5, fill=(200, 30, 50, 255), outline=(90, 110, 120, 255), width=1)
    p.ellipse((11, 15, 14.5, 19), fill=(255, 150, 160, 255))


def icon_weapon(p):
    sword(p, 6, 26, 26, 6, STEEL, GOLD, 3.6)


def icon_armor(p):
    shape = [(8, 5), (12.5, 7), (19.5, 7), (24, 5), (27, 11), (23, 13), (23, 27), (9, 27), (9, 13), (5, 11)]
    p.poly(shape, STEEL, STEEL_DARK, 1.0)
    p.line([(16, 9), (16, 26)], STEEL_DARK, 0.8)
    p.line([(10, 19), (22, 19)], STEEL_DARK, 0.8)


def icon_shield(p):
    p.circle(16, 16, 12, fill=WOOD, outline=STEEL_DARK, width=2)
    p.line([(6, 16), (26, 16)], WOOD_DARK, 0.8)
    p.line([(16, 6), (16, 26)], WOOD_DARK, 0.8)
    p.circle(16, 16, 3.5, fill=STEEL, outline=STEEL_DARK, width=0.6)


def icon_gold(p):
    for cx, cy in [(10, 22), (22, 22), (16, 18), (16, 12.5), (11, 15)]:
        p.ellipse((cx - 6, cy - 3.5, cx + 6, cy + 3.5), fill=GOLD, outline=GOLD_DARK, width=0.8)
        p.ellipse((cx - 3, cy - 1.6, cx + 3, cy + 1.6), outline=GOLD_DARK, width=0.5)


def icon_misc(p):
    bag = (190, 150, 100, 255)
    p.poly([(12, 9), (20, 9), (25, 17), (25, 25), (21, 28), (11, 28), (7, 25), (7, 17)], bag, WOOD_DARK, 1.0)
    p.poly([(11, 4.5), (21, 4.5), (19, 9), (13, 9)], bag, WOOD_DARK, 1.0)
    p.line([(11.5, 9.5), (20.5, 9.5)], (200, 50, 50, 255), 1.6)


def icon_ammo(p):
    for dy in (-5, 0, 5):
        y0, y1 = 25 + dy, 7 + dy
        p.line([(6, y0), (24, y1)], WOOD, 1.3)
        p.poly([(26.5, y1 - 2.5), (21.5, y1 - 1), (24.5, y1 + 2.5)], STEEL)
        p.poly([(6, y0), (4, y0 - 3), (8, y0 - 3)], (230, 230, 230, 255))


def chest_base(p):
    p.rect((4, 15, 28, 27), WOOD, WOOD_DARK, 1.0)
    p.rect((4, 20, 28, 22), STEEL_DARK)
    p.rect((7, 15, 9, 27), STEEL_DARK)
    p.rect((23, 15, 25, 27), STEEL_DARK)


def icon_chest_closed(p):
    chest_base(p)
    p.poly([(4, 15), (4, 10), (8, 6), (24, 6), (28, 10), (28, 15)], (160, 108, 60, 255), WOOD_DARK, 1.0)
    p.rect((14, 12, 18, 18), GOLD, GOLD_DARK, 0.6)


def icon_chest_open(p):
    p.poly([(5, 15), (8, 3), (24, 3), (27, 15)], (110, 72, 38, 255), WOOD_DARK, 1.0)  # lid raised
    p.rect((5, 13, 27, 16), (40, 26, 16, 255))
    chest_base(p)
    for cx in (11, 16, 21):
        p.ellipse((cx - 3, 12.5, cx + 3, 16.5), fill=GOLD, outline=GOLD_DARK, width=0.5)
    star(p, 23.5, 9.5, 3, 1, 4, (255, 250, 200, 255), rot=0)


ICONS = CLASS_IDS + MONSTER_IDS + ITEM_IDS


def generate_icons():
    img = Image.new("RGBA", (TILE * len(ICONS), TILE), (0, 0, 0, 0))
    for col, icon_id in enumerate(ICONS):
        pen = Pen()
        globals()["icon_" + icon_id](pen)
        img.paste(pen.result(), (col * TILE, 0))
    return img


def icon_map():
    icons = {icon_id: col for col, icon_id in enumerate(ICONS)}
    for alias, target in ICON_ALIASES.items():
        icons[alias] = icons[target]
    return {
        "schema_version": 1,
        "texture": "res://assets/icons/entity_icons.png",
        "tileset": "res://assets/icons/entity_icons.tres",
        "atlas_source_id": 0,
        "tile_size": TILE,
        "columns": len(ICONS),
        "icons": icons,
        "groups": {"classes": CLASS_IDS, "monsters": MONSTER_IDS, "items": ITEM_IDS},
        "aliases": ICON_ALIASES,
    }


def tileset_tres(texture_path, count):
    lines = [
        '[gd_resource type="TileSet" load_steps=3 format=3]',
        "",
        '[ext_resource type="Texture2D" path="%s" id="1"]' % texture_path,
        "",
        '[sub_resource type="TileSetAtlasSource" id="TileSetAtlasSource_1"]',
        'texture = ExtResource("1")',
        "texture_region_size = Vector2i(32, 32)",
    ]
    lines += ["%d:0/0 = 0" % i for i in range(count)]
    lines += [
        "",
        "[resource]",
        "tile_size = Vector2i(32, 32)",
        'sources/0 = SubResource("TileSetAtlasSource_1")',
    ]
    return "\n".join(lines) + "\n"


def write_icons(root):
    out_dir = os.path.join(root, "assets", "icons")
    os.makedirs(out_dir, exist_ok=True)
    png = os.path.join(out_dir, "entity_icons.png")
    generate_icons().save(png, optimize=True)
    with open(os.path.join(out_dir, "entity_icons.json"), "w", encoding="utf-8") as f:
        json.dump(icon_map(), f, indent="\t")
        f.write("\n")
    with open(os.path.join(out_dir, "entity_icons.tres"), "w", encoding="utf-8") as f:
        f.write(tileset_tres("res://assets/icons/entity_icons.png", len(ICONS)))
    print("wrote %s (%dx%d, %d icons) + entity_icons.json + entity_icons.tres" % (png, TILE * len(ICONS), TILE, len(ICONS)))


def main():
    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
    import build_tiles  # the dungeon atlas (needs this module's figures)
    if len(sys.argv) > 1:
        build_tiles.write_all(sys.argv[1])
        return
    build_tiles.write_all(os.path.join(root, "assets", "tiles"))
    write_icons(root)


if __name__ == "__main__":
    main()
