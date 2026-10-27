#!/usr/bin/env python3
"""Build the dungeon tile atlas: assets/tiles/dungeon_tiles.png (+ .tres, .json)
and the light texture assets/tiles/light_soft.png.

Art is 16 px pixel art scaled x2 (nearest) onto the 32 px grid. Most tiles are
drawn here (deterministic, no randomness beyond fixed patterns); the barrel,
gravestones and the rubble / hole decals come from Kenney's "Tiny Dungeon"
(CC0, see assets/third_party/kenney_tiny_dungeon/PROVENANCE.md), read from
assets/third_party/kenney_tiny_dungeon/tilemap_packed.png.

Atlas (TileSet source 0, 16 columns x 6 rows, coordinates are (column, row)):
  row 0  legacy 0-8 (floor, wall, stairs, arrival rune, zone floor, player,
         monster, unconscious, selection; 5-8 unchanged from gen_tileset.py),
         9 floor cracked, 10 floor mossy, 11 floor rubble, 12 floor puddle,
         13 zone tint (translucent overlay), 14 water, 15 pit
  rows 1-3  the 47 "blob" wall tiles, in BLOB_MASKS order (8-neighbour masks,
         bit 1 N, 2 NE, 4 E, 8 SE, 16 S, 32 SW, 64 W, 128 NW; a diagonal only
         counts when both its sides are walls). They carry terrain set 0
         ("walls", match corners and sides) peering bits.
  row 4  doors (closed, open, locked) for a horizontal wall (h) then a vertical
         wall (v); barrel, barrel damaged; crate, crate damaged; brazier
         (2-frame flicker at 10-11), brazier damaged; bones, bones damaged;
         rubble
  row 5  rubble damaged, landing rune (2-frame glow at 1-2), torch sconce
         (2-frame flicker at 3-4), decals: crack, moss, pebbles, holes, cobweb,
         gravestone a, gravestone b, chest closed, chest open, (14-15 spare)
dungeon_tiles.json maps every name to its [column, row] and lists BLOB_MASKS.

Usage (repo root, Pillow required): python3 tools/build_tiles.py [--out-dir DIR]
"""

import json
import math
import os
import sys

from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
sys.path.insert(0, HERE)
import gen_tileset  # noqa: E402  (legacy figures for columns 5-8)

PX = 16
SCALE = 2
TILE = PX * SCALE
COLS = 16
ROWS = 6
KENNEY = os.path.join(ROOT, "assets", "third_party", "kenney_tiny_dungeon", "tilemap_packed.png")

# Palette (dark barrow stone; wood and metal follow Kenney's Tiny Dungeon palette)
T = (0, 0, 0, 0)
INK = (24, 20, 28, 255)
OUTLINE = (38, 43, 68, 255)
PLUM = (63, 38, 49, 255)
STONE = (74, 68, 76, 255)
STONE_HI = (90, 84, 92, 255)
STONE_LO = (62, 57, 66, 255)
SEAM = (54, 50, 59, 255)
MOSS = (74, 104, 62, 255)
MOSS_HI = (102, 138, 78, 255)
WATER = (46, 66, 98, 255)
WATER_HI = (88, 122, 160, 255)
CAP = (34, 30, 40, 255)
CAP_DOT = (44, 40, 50, 255)
RIM_HI = (156, 148, 160, 255)
RIM_LO = (104, 96, 110, 255)
BRICK = (112, 104, 118, 255)
BRICK_HI = (138, 130, 144, 255)
MORTAR = (62, 56, 68, 255)
FACE_SHADOW = (46, 42, 52, 255)
WOOD = (189, 108, 74, 255)
WOOD_LO = (118, 59, 54, 255)
WOOD_HI = (234, 165, 108, 255)
IRON = (82, 96, 124, 255)
IRON_HI = (139, 155, 180, 255)
IRON_LT = (192, 203, 220, 255)
GOLD = (254, 201, 76, 255)
GOLD_LO = (190, 120, 30, 255)
FIRE_1 = (255, 236, 140, 255)
FIRE_2 = (255, 160, 52, 255)
FIRE_3 = (232, 69, 55, 255)
EMBER = (150, 60, 40, 255)
BONE = (232, 226, 206, 255)
BONE_LO = (170, 162, 140, 255)
RUNE = (120, 210, 255, 255)
RUNE_LO = (60, 120, 190, 255)
WEB = (210, 214, 224, 150)
RED_TINT = (220, 50, 40, 44)
RED_HATCH = (236, 70, 56, 96)

N, NE, E, SE, S, SW, W, NW = 1, 2, 4, 8, 16, 32, 64, 128


def canonical(mask):
    """Clears diagonal bits whose two sides are not both walls."""
    m = mask
    if not (m & N and m & E):
        m &= ~NE
    if not (m & S and m & E):
        m &= ~SE
    if not (m & S and m & W):
        m &= ~SW
    if not (m & N and m & W):
        m &= ~NW
    return m


BLOB_MASKS = sorted(set(canonical(m) for m in range(256)))
assert len(BLOB_MASKS) == 47


class Canvas:
    def __init__(self, fill=T):
        self.img = Image.new("RGBA", (PX, PX), fill)
        self.px = self.img.load()

    def set(self, x, y, c):
        if 0 <= x < PX and 0 <= y < PX:
            self.px[x, y] = c

    def get(self, x, y):
        return self.px[x, y]

    def rect(self, x0, y0, x1, y1, c):
        for y in range(y0, y1 + 1):
            for x in range(x0, x1 + 1):
                self.set(x, y, c)

    def hline(self, x0, x1, y, c):
        self.rect(x0, y, x1, y, c)

    def vline(self, x, y0, y1, c):
        self.rect(x, y0, x, y1, c)

    def pixels(self, pts, c):
        for (x, y) in pts:
            self.set(x, y, c)

    def ellipse(self, cx, cy, rx, ry, c, outline=None):
        for y in range(PX):
            for x in range(PX):
                d = ((x + 0.5 - cx) / rx) ** 2 + ((y + 0.5 - cy) / ry) ** 2
                if d <= 1.0:
                    self.set(x, y, c)
                    if outline is not None and d > 0.62:
                        self.set(x, y, outline)

    def paste(self, other):
        self.img.alpha_composite(other.img if isinstance(other, Canvas) else other)
        self.px = self.img.load()

    def scaled(self):
        return self.img.resize((TILE, TILE), Image.NEAREST)


def kenney_tile(index):
    sheet = Image.open(KENNEY).convert("RGBA")
    r, c = divmod(index, 12)
    t = Canvas()
    t.img = sheet.crop((c * PX, r * PX, c * PX + PX, r * PX + PX))
    t.px = t.img.load()
    return t


def kenney_keyed(index, keys):
    """A Kenney tile with its background colours made transparent."""
    t = kenney_tile(index)
    for y in range(PX):
        for x in range(PX):
            if t.get(x, y)[:3] in keys:
                t.set(x, y, T)
    return t


# ---------------------------------------------------------------------------
# Floors
# ---------------------------------------------------------------------------

def stone_floor(variant_seed=0):
    c = Canvas(STONE)
    # two courses of flagstones per tile, offset; seams on the right/bottom edges
    for y in range(PX):
        for x in range(PX):
            n = (x * 7 + y * 13 + (x * y) % 5 + variant_seed * 3) % 17
            if n == 0:
                c.set(x, y, STONE_HI)
            elif n == 5:
                c.set(x, y, STONE_LO)
    c.hline(0, 15, 7, SEAM)
    c.hline(0, 15, 15, SEAM)
    c.vline(9, 0, 6, SEAM)
    c.vline(3, 8, 14, SEAM)
    c.vline(15, 8, 14, SEAM)
    # soft highlight on the top-left edge of each stone
    c.hline(0, 8, 0, STONE_HI)
    c.hline(10, 15, 0, STONE_HI)
    c.hline(4, 14, 8, STONE_HI)
    return c


def floor_plain():
    return stone_floor(0)


def floor_cracked():
    c = stone_floor(1)
    c.pixels([(2, 2), (3, 3), (4, 3), (5, 4), (5, 5), (6, 6), (11, 9), (12, 10), (12, 11), (13, 12), (11, 12)], SEAM)
    c.pixels([(3, 2), (6, 5), (12, 9)], INK)
    return c


def floor_mossy():
    c = stone_floor(2)
    for (x, y) in [(1, 9), (2, 9), (1, 10), (2, 10), (3, 10), (2, 11), (10, 2), (11, 2), (11, 3), (12, 3),
                   (12, 4), (6, 12), (7, 12), (7, 13)]:
        c.set(x, y, MOSS)
    c.pixels([(2, 9), (11, 2), (7, 12)], MOSS_HI)
    return c


def floor_rubble():
    c = stone_floor(3)
    for (x, y, big) in [(3, 4, True), (10, 11, True), (12, 3, False), (5, 12, False), (8, 7, False)]:
        c.set(x, y, RIM_LO)
        c.set(x + 1, y + 1, SEAM)
        if big:
            c.set(x + 1, y, RIM_LO)
            c.set(x, y - 1, RIM_HI)
            c.set(x + 2, y + 1, SEAM)
    return c


def floor_puddle():
    c = stone_floor(4)
    c.ellipse(8, 9, 5.5, 3.2, WATER)
    c.pixels([(5, 8), (6, 8), (9, 10)], WATER_HI)
    return c


def zone_floor():
    c = stone_floor(0)
    for y in range(PX):
        for x in range(PX):
            if (x + y) % 4 == 0:
                r, g, b, a = c.get(x, y)
                c.set(x, y, (min(255, r + 70), g, b, a))
    return c


def zone_tint():
    c = Canvas(RED_TINT)
    for y in range(PX):
        for x in range(PX):
            if (x + y) % 4 == 0:
                c.set(x, y, RED_HATCH)
    return c


def water():
    c = Canvas(WATER)
    for (x, y) in [(2, 3), (3, 3), (9, 6), (10, 6), (11, 6), (4, 11), (5, 11), (12, 13)]:
        c.set(x, y, WATER_HI)
    return c


def pit():
    c = Canvas(INK)
    c.hline(0, 15, 0, RIM_LO)
    c.hline(0, 15, 1, FACE_SHADOW)
    c.rect(0, 2, 15, 4, (30, 26, 34, 255))
    return c


def stairs_down():
    c = Canvas(STONE)
    c.rect(1, 1, 14, 14, OUTLINE)
    shades = [(150, 142, 154), (122, 114, 128), (96, 90, 104), (72, 66, 80), (52, 48, 60)]
    for i, sh in enumerate(shades):
        y0 = 2 + i * 2
        c.rect(2 + i, y0, 13 - i, y0 + 1, sh + (255,))
        c.hline(2 + i, 13 - i, y0, tuple(min(255, v + 18) for v in sh) + (255,))
    c.rect(7, 12, 8, 13, INK)
    # frame studs
    for (x, y) in [(1, 1), (14, 1), (1, 14), (14, 14)]:
        c.set(x, y, IRON_HI)
    return c


def landing_rune(frame=0):
    c = Canvas()
    hi = RUNE if frame == 0 else (170, 236, 255, 255)
    lo = RUNE_LO if frame == 0 else RUNE
    for y in range(PX):
        for x in range(PX):
            d = math.hypot(x + 0.5 - 8, y + 0.5 - 8)
            if 6.2 <= d <= 7.4:
                c.set(x, y, lo)
            elif 3.6 <= d <= 4.4:
                c.set(x, y, lo)
    # rune marks on the ring
    for (x, y) in [(8, 1), (14, 8), (8, 14), (1, 8), (3, 3), (12, 3), (12, 12), (3, 12)]:
        c.set(x, y, hi)
    c.rect(7, 7, 8, 8, hi)
    return c


# ---------------------------------------------------------------------------
# Walls (47-tile blob, 3/4 view: dark cap, light rim, brick face on open south)
# ---------------------------------------------------------------------------

FACE_TOP = 7  # rows FACE_TOP..15 show the brick face when the south is open


def wall_tile(mask):
    c = Canvas(CAP)
    for y in range(PX):
        for x in range(PX):
            if (x * 5 + y * 3) % 13 == 0:
                c.set(x, y, CAP_DOT)
    open_n = not mask & N
    open_e = not mask & E
    open_s = not mask & S
    open_w = not mask & W
    cap_bottom = FACE_TOP - 1 if open_s else 15
    # rims on open sides of the cap
    if open_n:
        c.hline(0, 15, 0, RIM_HI)
        c.hline(0, 15, 1, RIM_LO)
    if open_w:
        c.vline(0, 0, cap_bottom, RIM_HI)
        c.vline(1, 1 if open_n else 0, cap_bottom, RIM_LO)
    if open_e:
        c.vline(15, 0, cap_bottom, RIM_LO)
        c.vline(14, 1 if open_n else 0, cap_bottom, RIM_HI if not open_n else RIM_LO)
    # inner corners (both sides wall, the diagonal open)
    if mask & N and mask & W and not mask & NW:
        c.rect(0, 0, 1, 1, RIM_LO)
        c.set(0, 0, RIM_HI)
    if mask & N and mask & E and not mask & NE:
        c.rect(14, 0, 15, 1, RIM_LO)
        c.set(15, 0, RIM_HI)
    if mask & S and mask & W and not mask & SW:
        c.rect(0, 14, 1, 15, RIM_LO)
    if mask & S and mask & E and not mask & SE:
        c.rect(14, 14, 15, 15, RIM_LO)
    # outer corner pixels darkened for a rounded look
    if open_n and open_w:
        c.set(0, 0, CAP)
    if open_n and open_e:
        c.set(15, 0, CAP)
    if open_s:
        c.hline(0, 15, FACE_TOP - 1, RIM_HI)
        # brick courses
        for y in range(FACE_TOP, PX):
            for x in range(PX):
                c.set(x, y, BRICK)
        for row, y in enumerate(range(FACE_TOP, PX, 3)):
            c.hline(0, 15, y, MORTAR)
            off = 0 if row % 2 == 0 else 3
            for x in range(off, PX, 6):
                c.vline(x, y, min(15, y + 2), MORTAR)
            for x in range(off + 1, PX, 6):
                if y + 1 < PX:
                    c.set(x, y + 1, BRICK_HI)
        c.hline(0, 15, 15, FACE_SHADOW)
        if open_w:
            c.vline(0, FACE_TOP - 1, 15, FACE_SHADOW)
        if open_e:
            c.vline(15, FACE_TOP - 1, 15, FACE_SHADOW)
    return c


def wall_solid():
    return wall_tile(255)


# ---------------------------------------------------------------------------
# Doors
# ---------------------------------------------------------------------------

def door_h(state):
    """Door in a horizontal wall (walls west and east; passage north-south)."""
    c = stone_floor(5)
    # stone posts (look like the wall face)
    for x0 in (0, 13):
        c.rect(x0, 0, x0 + 2, 15, BRICK)
        c.hline(x0, x0 + 2, 0, RIM_HI)
        for y in (4, 8, 12):
            c.hline(x0, x0 + 2, y, MORTAR)
        c.vline(x0 + 2 if x0 == 0 else x0, 0, 15, FACE_SHADOW)
    c.hline(3, 12, 0, OUTLINE)
    c.hline(3, 12, 1, IRON)
    if state == "open":
        c.rect(3, 2, 12, 15, (40, 36, 46, 255))
        c.rect(3, 2, 4, 15, WOOD_LO)  # leaf swung against the post
        c.vline(4, 2, 15, WOOD)
        return c
    c.rect(3, 2, 12, 15, WOOD)
    for x in (5, 8, 11):
        c.vline(x, 2, 15, WOOD_LO)
    c.hline(3, 12, 5, IRON)
    c.hline(3, 12, 12, IRON)
    c.pixels([(4, 5), (11, 5), (4, 12), (11, 12)], IRON_LT)
    c.set(10, 9, IRON_LT)
    c.set(10, 8, IRON_HI)
    if state == "locked":
        c.rect(6, 7, 9, 10, GOLD)
        c.rect(6, 10, 9, 10, GOLD_LO)
        c.pixels([(6, 6), (9, 6), (7, 5), (8, 5)], IRON_LT)
        c.set(7, 8, INK)
        c.set(7, 9, INK)
        c.set(8, 8, INK)
    return c


def door_v(state):
    """Door in a vertical wall (walls north and south; passage west-east)."""
    c = stone_floor(6)
    c.rect(0, 0, 15, 2, CAP)
    c.hline(0, 15, 2, RIM_HI)
    c.rect(0, 13, 15, 15, BRICK)
    c.hline(0, 15, 13, RIM_HI)
    c.hline(0, 15, 15, FACE_SHADOW)
    if state == "open":
        c.rect(9, 3, 15, 4, WOOD)  # leaf swung along the north wall
        c.hline(9, 15, 4, WOOD_LO)
        c.set(9, 3, IRON_HI)
        return c
    c.rect(6, 3, 9, 12, WOOD)
    c.vline(6, 3, 12, WOOD_LO)
    c.vline(9, 3, 12, WOOD_HI)
    c.hline(6, 9, 5, IRON)
    c.hline(6, 9, 10, IRON)
    if state == "locked":
        c.rect(10, 6, 12, 9, GOLD)
        c.hline(10, 12, 9, GOLD_LO)
        c.set(11, 7, INK)
        c.pixels([(10, 5), (12, 5)], IRON_LT)
    return c


# ---------------------------------------------------------------------------
# Props and decals
# ---------------------------------------------------------------------------

def barrel():
    return kenney_tile(82)


def barrel_damaged():
    c = kenney_tile(82)
    for y in range(0, 6):
        for x in range(PX):
            c.set(x, y, T)
    jag = [7, 6, 6, 7, 8, 6, 7, 9, 7, 6, 7, 8, 6, 7, 6, 7]
    for x in range(PX):
        for y in range(6, jag[x]):
            c.set(x, y, T)
    c.pixels([(2, 13), (3, 14), (13, 12), (12, 14), (1, 11)], WOOD)
    c.pixels([(3, 13), (13, 13)], WOOD_LO)
    return c


def crate(damaged=False):
    c = Canvas()
    c.rect(2, 3, 13, 14, WOOD)
    c.rect(2, 3, 13, 3, WOOD_HI)
    for (x, y) in [(2, 3), (13, 3), (2, 14), (13, 14)]:
        c.set(x, y, WOOD_LO)
    c.rect(1, 2, 14, 2, PLUM)
    c.rect(1, 15, 14, 15, PLUM)
    c.vline(1, 2, 15, PLUM)
    c.vline(14, 2, 15, PLUM)
    for i in range(10):  # diagonal brace
        c.set(3 + i, 4 + i, WOOD_LO)
        c.set(4 + i, 4 + i, WOOD_LO)
    c.vline(2, 3, 14, WOOD_LO)
    c.vline(13, 3, 14, WOOD_LO)
    if damaged:
        for (x, y) in [(6, 2), (7, 2), (7, 3), (8, 3), (8, 4), (9, 4), (6, 3), (9, 5), (10, 5)]:
            c.set(x, y, T)
        c.rect(5, 6, 9, 9, INK)
        c.pixels([(0, 12), (15, 10), (0, 9)], WOOD)
    return c


def brazier(frame=0, damaged=False):
    c = Canvas()
    # tripod legs
    c.pixels([(4, 14), (5, 13), (5, 12), (11, 14), (10, 13), (10, 12), (8, 13), (8, 14), (7, 12)], IRON)
    if damaged:
        c.ellipse(8, 11, 5, 2.2, IRON, OUTLINE)
        c.pixels([(4, 13), (6, 14), (10, 14), (12, 13)], EMBER)
        c.pixels([(5, 14), (11, 13)], FIRE_3)
        return c
    c.ellipse(8, 9.5, 6, 2.6, IRON, OUTLINE)
    c.hline(3, 12, 8, IRON_HI)
    c.rect(6, 11, 9, 11, IRON)
    if frame == 0:
        flame = [(5, 7), (6, 7), (7, 7), (8, 7), (9, 7), (10, 7), (6, 6), (7, 6), (8, 6), (9, 6), (6, 5), (7, 5),
                 (8, 5), (7, 4), (8, 3), (7, 2)]
        core = [(7, 6), (8, 6), (7, 5), (8, 5), (8, 4)]
        tips = [(7, 2), (8, 3), (10, 5)]
    else:
        flame = [(5, 7), (6, 7), (7, 7), (8, 7), (9, 7), (10, 7), (6, 6), (7, 6), (8, 6), (9, 6), (7, 5), (8, 5),
                 (9, 5), (8, 4), (8, 3), (9, 2), (5, 5)]
        core = [(7, 6), (8, 6), (8, 5), (8, 4)]
        tips = [(9, 2), (5, 5), (6, 4)]
    c.pixels(flame, FIRE_2)
    c.pixels(core, FIRE_1)
    c.pixels(tips, FIRE_3)
    return c


def bones(damaged=False):
    c = Canvas()
    if not damaged:
        # skull
        c.ellipse(6, 7, 3.4, 3.0, BONE, BONE_LO)
        c.rect(4, 9, 7, 10, BONE)
        c.pixels([(5, 7), (7, 7)], INK)
        c.set(6, 9, BONE_LO)
        # crossed long bones
        for i in range(9):
            c.set(4 + i, 13 - i // 2, BONE)
            c.set(12 - i, 14 - i // 3, BONE_LO if i % 3 == 0 else BONE)
        c.pixels([(3, 13), (13, 9), (12, 14), (3, 11)], BONE)
    else:
        for (x, y) in [(3, 4), (4, 4), (10, 6), (11, 7), (12, 7), (5, 11), (6, 11), (7, 12), (12, 12), (2, 9)]:
            c.set(x, y, BONE)
        c.pixels([(4, 5), (11, 6), (6, 12)], BONE_LO)
    return c


RUBBLE_KEYS = {(118, 59, 54)}


def rubble(damaged=False):
    c = kenney_keyed(24, RUBBLE_KEYS)
    if damaged:
        for y in range(PX):
            for x in range(PX):
                if (x + y) % 2 == 0 and y < 9:
                    c.set(x, y, T)
    return c


def torch(frame=0):
    """A wall sconce, drawn on the wall face (lower half of a wall tile)."""
    c = Canvas()
    c.rect(7, 10, 8, 13, WOOD_LO)
    c.rect(6, 12, 9, 12, IRON)
    c.set(6, 13, IRON)
    c.set(9, 13, IRON)
    if frame == 0:
        c.pixels([(7, 9), (8, 9), (7, 8), (8, 8), (7, 7), (8, 6)], FIRE_2)
        c.pixels([(7, 9), (8, 8)], FIRE_1)
        c.set(8, 5, FIRE_3)
    else:
        c.pixels([(7, 9), (8, 9), (7, 8), (8, 8), (7, 7), (7, 6), (6, 8)], FIRE_2)
        c.pixels([(8, 9), (7, 8)], FIRE_1)
        c.set(7, 5, FIRE_3)
    return c


def decal_crack():
    c = Canvas()
    c.pixels([(3, 2), (4, 3), (4, 4), (5, 5), (6, 5), (7, 6), (7, 7), (8, 8), (9, 8), (10, 9), (6, 6), (11, 10),
              (11, 11)], SEAM)
    c.pixels([(4, 3), (7, 7), (10, 9)], INK)
    return c


def decal_moss():
    c = Canvas()
    for (x, y) in [(3, 11), (4, 11), (5, 11), (3, 12), (4, 12), (5, 12), (6, 12), (4, 13), (5, 13), (9, 3), (10, 3),
                   (10, 4), (11, 4), (12, 5), (11, 5)]:
        c.set(x, y, MOSS)
    c.pixels([(4, 11), (10, 3), (5, 12)], MOSS_HI)
    return c


def decal_pebbles():
    c = Canvas()
    for (x, y) in [(3, 5), (9, 3), (12, 10), (5, 12), (8, 9)]:
        c.set(x, y, RIM_LO)
        c.set(x + 1, y, STONE_HI)
        c.set(x, y + 1, SEAM)
    return c


def decal_holes():
    return kenney_keyed(12, RUBBLE_KEYS)


def decal_cobweb():
    c = Canvas()
    for i in range(10):
        c.set(i, 0, WEB)
        c.set(0, i, WEB)
        c.set(i // 2 + 0, i // 2 + 0, WEB)
    for (x, y) in [(5, 1), (4, 2), (3, 3), (2, 4), (1, 5), (8, 1), (7, 3), (6, 4), (4, 6), (3, 7), (1, 8)]:
        c.set(x, y, WEB)
    return c


def gravestone(which):
    return kenney_tile(64 if which == 0 else 65)


def chest(opened):
    return kenney_tile(91 if opened else 89)


# ---------------------------------------------------------------------------
# Atlas
# ---------------------------------------------------------------------------

def legacy_figures():
    """Columns 5-8 of the old atlas, drawn by gen_tileset.py at 32 px."""
    img = Image.new("RGBA", (TILE * 4, TILE), (0, 0, 0, 0))
    gen_tileset.figure(img, 0 * TILE, (60, 110, 220, 255), (20, 40, 100, 255))
    gen_tileset.figure(img, 1 * TILE, (200, 50, 50, 255), (90, 15, 15, 255))
    gen_tileset.unconscious_tile(img, 2 * TILE)
    gen_tileset.selection_tile(img, 3 * TILE)
    return img


def layout():
    """name -> (column, row, Canvas or None for the legacy figures)."""
    tiles = {
        "floor": (0, 0, floor_plain()),
        "wall": (1, 0, wall_solid()),
        "stairs": (2, 0, stairs_down()),
        "arrival": (3, 0, landing_rune(0)),
        "zone_floor": (4, 0, zone_floor()),
        "player": (5, 0, None),
        "monster": (6, 0, None),
        "unconscious": (7, 0, None),
        "selection": (8, 0, None),
        "floor_cracked": (9, 0, floor_cracked()),
        "floor_mossy": (10, 0, floor_mossy()),
        "floor_rubble": (11, 0, floor_rubble()),
        "floor_puddle": (12, 0, floor_puddle()),
        "zone_tint": (13, 0, zone_tint()),
        "water": (14, 0, water()),
        "pit": (15, 0, pit()),
        "door_closed_h": (0, 4, door_h("closed")),
        "door_open_h": (1, 4, door_h("open")),
        "door_locked_h": (2, 4, door_h("locked")),
        "door_closed_v": (3, 4, door_v("closed")),
        "door_open_v": (4, 4, door_v("open")),
        "door_locked_v": (5, 4, door_v("locked")),
        "barrel": (6, 4, barrel()),
        "barrel_damaged": (7, 4, barrel_damaged()),
        "crate": (8, 4, crate()),
        "crate_damaged": (9, 4, crate(True)),
        "brazier": (10, 4, brazier(0)),
        "brazier_frame_1": (11, 4, brazier(1)),
        "brazier_damaged": (12, 4, brazier(0, True)),
        "bones": (13, 4, bones()),
        "bones_damaged": (14, 4, bones(True)),
        "rubble": (15, 4, rubble()),
        "rubble_damaged": (0, 5, rubble(True)),
        "landing": (1, 5, landing_rune(0)),
        "landing_frame_1": (2, 5, landing_rune(1)),
        "torch": (3, 5, torch(0)),
        "torch_frame_1": (4, 5, torch(1)),
        "decal_crack": (5, 5, decal_crack()),
        "decal_moss": (6, 5, decal_moss()),
        "decal_pebbles": (7, 5, decal_pebbles()),
        "decal_holes": (8, 5, decal_holes()),
        "decal_cobweb": (9, 5, decal_cobweb()),
        "gravestone_a": (10, 5, gravestone(0)),
        "gravestone_b": (11, 5, gravestone(1)),
        "chest_closed": (12, 5, chest(False)),
        "chest_open": (13, 5, chest(True)),
    }
    for i, m in enumerate(BLOB_MASKS):
        tiles["wall_%d" % m] = (i % COLS, 1 + i // COLS, wall_tile(m))
    return tiles


## Tiles shown as 2-frame animations (frame 1 sits in the next column and is
## not a tile of its own).
ANIMATED = {"brazier": 2, "landing": 2, "torch": 2}
ANIMATION_SPEED = 3.0


def build_atlas():
    img = Image.new("RGBA", (TILE * COLS, TILE * ROWS), (0, 0, 0, 0))
    figures = legacy_figures()
    tiles = layout()
    for name, (col, row, canvas) in tiles.items():
        if canvas is None:
            continue
        img.paste(canvas.scaled(), (col * TILE, row * TILE))
    img.paste(figures, (5 * TILE, 0))
    return img, tiles


def light_texture(size=128):
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    px = img.load()
    c = (size - 1) / 2.0
    for y in range(size):
        for x in range(size):
            d = math.hypot(x - c, y - c) / c
            a = max(0.0, 1.0 - d)
            a = a * a * (3 - 2 * a)  # smoothstep falloff
            px[x, y] = (255, 255, 255, int(round(a * 255)))
    return img


PEERING = [(N, "top_side"), (NE, "top_right_corner"), (E, "right_side"), (SE, "bottom_right_corner"),
           (S, "bottom_side"), (SW, "bottom_left_corner"), (W, "left_side"), (NW, "top_left_corner")]


def tileset_tres(tiles):
    skip = set()
    for name in ANIMATED:
        col, row, _ = tiles[name]
        for k in range(1, ANIMATED[name]):
            skip.add((col + k, row))
    lines = [
        '[gd_resource type="TileSet" load_steps=3 format=3]',
        "",
        '[ext_resource type="Texture2D" path="res://assets/tiles/dungeon_tiles.png" id="1"]',
        "",
        '[sub_resource type="TileSetAtlasSource" id="TileSetAtlasSource_1"]',
        'texture = ExtResource("1")',
        "texture_region_size = Vector2i(32, 32)",
    ]
    by_pos = {}
    for name, (col, row, _) in tiles.items():
        by_pos[(col, row)] = name
    for (col, row) in sorted(by_pos, key=lambda p: (p[1], p[0])):
        if (col, row) in skip:
            continue
        name = by_pos[(col, row)]
        key = "%d:%d" % (col, row)
        if name in ANIMATED:
            lines.append("%s/animation_speed = %.1f" % (key, ANIMATION_SPEED))
            lines.append("%s/animation_frames_count = %d" % (key, ANIMATED[name]))
            for k in range(ANIMATED[name]):
                lines.append("%s/animation_frame_%d/duration = 1.0" % (key, k))
        lines.append("%s/0 = 0" % key)
        if name.startswith("wall_"):
            mask = int(name[5:])
            lines.append("%s/0/terrain_set = 0" % key)
            lines.append("%s/0/terrain = 0" % key)
            for bit, label in PEERING:
                if mask & bit:
                    lines.append("%s/0/terrains_peering_bit/%s = 0" % (key, label))
    lines += [
        "",
        "[resource]",
        "tile_size = Vector2i(32, 32)",
        "terrain_set_0/mode = 0",
        'terrain_set_0/terrain_0/name = "walls"',
        "terrain_set_0/terrain_0/color = Color(0.4, 0.38, 0.45, 1)",
        'sources/0 = SubResource("TileSetAtlasSource_1")',
    ]
    return "\n".join(lines) + "\n"


def atlas_json(tiles):
    return {
        "schema_version": 1,
        "texture": "res://assets/tiles/dungeon_tiles.png",
        "tileset": "res://assets/tiles/dungeon_tiles.tres",
        "atlas_source_id": 0,
        "tile_size": TILE,
        "columns": COLS,
        "rows": ROWS,
        "tiles": {name: [col, row] for name, (col, row, _) in sorted(tiles.items(), key=lambda t: (t[1][1], t[1][0]))},
        "animated": ANIMATED,
        "blob_masks": BLOB_MASKS,
        "blob_bits": {"N": N, "NE": NE, "E": E, "SE": SE, "S": S, "SW": SW, "W": W, "NW": NW},
        "terrain_set": 0,
        "terrain": 0,
        "sources": {
            "procedural": "tools/build_tiles.py",
            "kenney_tiny_dungeon": ["barrel", "barrel_damaged", "rubble", "rubble_damaged", "decal_holes",
                                    "gravestone_a", "gravestone_b", "chest_closed", "chest_open"],
        },
    }


def write_all(out_dir=None):
    out_dir = out_dir or os.path.join(ROOT, "assets", "tiles")
    os.makedirs(out_dir, exist_ok=True)
    img, tiles = build_atlas()
    png = os.path.join(out_dir, "dungeon_tiles.png")
    img.save(png, optimize=True)
    with open(os.path.join(out_dir, "dungeon_tiles.tres"), "w", encoding="utf-8") as f:
        f.write(tileset_tres(tiles))
    with open(os.path.join(out_dir, "dungeon_tiles.json"), "w", encoding="utf-8") as f:
        json.dump(atlas_json(tiles), f, indent="\t")
        f.write("\n")
    light_texture().save(os.path.join(out_dir, "light_soft.png"), optimize=True)
    print("wrote %s (%dx%d, %d named tiles) + dungeon_tiles.tres + dungeon_tiles.json + light_soft.png"
          % (png, img.width, img.height, len(tiles)))


def main(argv):
    out_dir = None
    if len(argv) >= 2 and argv[0] == "--out-dir":
        out_dir = argv[1]
    write_all(out_dir)


if __name__ == "__main__":
    main(sys.argv[1:])
