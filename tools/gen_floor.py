#!/usr/bin/env python3
"""Generate concentric floor files (floor file format v2, docs/gdd.md 5.2.2).

The generator makes the first pass of a floor; hand edits follow (mark a hand
edited file with "hand_edited": true so tests stop comparing it with the
generator output). Standard library only, deterministic for a given preset,
parameters and seed.

Layout (docs/gdd.md 5.2.1): a square-ish map of concentric corridor loops.
  * Band 0 (between the map edge and loop 0) holds the arrival landings, each
    in its own landing room that opens only into its landing pack's room; the
    pack room opens onto loop 0. Other band-0 rooms hang off loop 0 by doors.
  * Band k (between loop k-1 and loop k) holds gate rooms: 2-wide spokes run
    from loop k-1 through a gate room (a pack zone) to loop k, so every route
    inward crosses one gate pack per band. Other rooms open onto one loop only
    (closed, open or locked doors; locked rooms are vaults with a chest).
  * Inside the innermost loop: the stairs hall in the centre (the stairs-guard
    zone, a chest by the stairs), an optional deadly side area (dead end with a
    hidden cache) to the west, a vault and a shrine to the east.
  * Keys: a share of the locked doors (--key-doors, default half, at most one
    per key colour) also take a key; a barrel or crate on the landings' side
    drops it ("drops"): 6-14 tiles' walk from the door when one fits, else up
    to 20 tiles, outside the encounter zones when possible. The DC stays, so
    thieves' tools still work. Chosen with a separate random stream, so the rest of the
    floor does not move when the share changes.
  * Chests: the stairs chest rolls chest_stairs_t1 (floors 1-2) or
    chest_stairs_t2 (floors 3-5); the hidden cache cache_t1 / cache_t2.
Spoke and landing placements are chosen from a few templates by search so the
route from every landing to the stairs has (nearly) the same length.

Usage (from the repo root):
  python3 tools/gen_floor.py --list                          # presets
  python3 tools/gen_floor.py --preset floor_001              # write floors/floor_001.json
  python3 tools/gen_floor.py --preset floor_001 --stdout     # print instead of writing
  python3 tools/gen_floor.py --preset floor_001 --stats      # also print statistics
  python3 tools/gen_floor.py --all                           # every preset
  python3 tools/gen_floor.py --check floors/floor_00*.json   # validate files (exit 1 on problems)
Overrides (any preset): --seed N --width W --height H --landings N --rings R
  --room-len N --props F --doors F --locked F --key-doors F --out PATH.
"""

import argparse
import glob
import json
import os
import random
import sys
from collections import deque

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
WALL = "#"
FLOOR = "."
LEGEND_V2 = set("#.ASLD")
PROP_KINDS = ["barrel", "crate", "brazier", "bones", "rubble"]
DOOR_STATES = ["open", "closed", "locked"]
FACINGS = ["north", "east", "south", "west"]
ZONE_KINDS = ["pack", "boss", "ambush"]
PROP_HP = {"barrel": 4, "crate": 5, "brazier": 10, "bones": 2, "rubble": 6}
PROP_BLOCKS = {"barrel": True, "crate": True, "brazier": True, "bones": False, "rubble": False}
LANDING_MIN_EDGE_RATIO = 2.0 / 3.0
KEY_COLOURS = ["bronze", "iron", "silver", "brass", "copper", "bone"]
KEY_ITEMS = ["key_%s" % c for c in KEY_COLOURS]
KEY_DOORS_DEFAULT = 0.5  # share of locked doors that take a key
KEY_RANGE = (6, 14)  # preferred walk distance from the door to its key prop
KEY_MAX_WALK = 20  # a crate or barrel outside the zones may stretch to this
KEY_PROP_KINDS = ["crate", "barrel"]  # preferred key holders
ROUTE_SPREAD_MAX = 1.2  # longest landing route <= 1.2 x the shortest

BARROW_STYLE = {
    "darkness": "#3b342e",
    "torch_color": "#ffb45e",
    "torch_density": 0.06,
    "decor_density": 0.06,
    "floor_variant_weights": {"plain": 12, "cracked": 3, "mossy": 1.5, "rubble": 1, "puddle": 0.3},
}

PRESETS = {
    "floor_001": {
        "id": "floor_001", "display_name": "The Threshold", "floor_number": 1,
        "theme": "The Barrow Warrens", "seed": 101,
        "width": 112, "height": 80, "landings": 4, "rings": 2, "outer": 14, "band": 11,
        "room_len": 12, "hall_half": 9, "props": 0.8, "doors": 0.7, "locked": 0.15, "open": 0.25,
        "vaults": 1, "room_chests": 2, "lock_dc": 12,
        "budget": {"level": 1, "min": "easy", "max": "hard"},
        "roster": {
            "landing_pack": [{"monsters": ["giant_rat"], "name": "rat run"}],
            "ring_pack": [[{"monsters": ["giant_rat", "giant_rat"], "name": "gnawed gate"},
                           {"monsters": ["kobold", "kobold"], "name": "diggers' gate"}]],
            "stairs_guard": {"monsters": ["kobold", "kobold"], "name": "threshold stair"},
            "optional": {"monsters": ["skeleton", "skeleton", "zombie"], "name": "the crypt"},
        },
        "style": dict(BARROW_STYLE, darkness="#4a4038"),
    },
    "floor_002": {
        "id": "floor_002", "display_name": "The Spoil Tunnels", "floor_number": 2,
        "theme": "The Barrow Warrens", "seed": 202,
        "width": 112, "height": 80, "landings": 4, "rings": 2, "outer": 14, "band": 11,
        "room_len": 11, "hall_half": 9, "props": 1.0, "doors": 0.75, "locked": 0.2, "open": 0.2,
        "vaults": 1, "room_chests": 2, "lock_dc": 12,
        "budget": {"level": 2, "min": "easy", "max": "medium"},
        "roster": {
            "landing_pack": [{"monsters": ["kobold", "kobold"], "name": "kobold den"}],
            "ring_pack": [[{"monsters": ["giant_centipede"], "name": "centipede gallery", "kind": "ambush"},
                           {"monsters": ["goblin"], "name": "spoil heap"}]],
            "stairs_guard": {"monsters": ["goblin", "kobold"], "name": "tunnel stair"},
            "optional": {"monsters": ["goblin", "goblin"], "name": "goblin cache"},
        },
        "style": dict(BARROW_STYLE, darkness="#40382f"),
    },
    "floor_003": {
        "id": "floor_003", "display_name": "The Ossuary", "floor_number": 3,
        "theme": "The Barrow Warrens", "seed": 303,
        "width": 128, "height": 96, "landings": 6, "rings": 3, "outer": 14, "band": 10,
        "room_len": 11, "hall_half": 9, "props": 1.0, "doors": 0.75, "locked": 0.2, "open": 0.2,
        "vaults": 2, "room_chests": 3, "lock_dc": 13,
        "budget": {"level": 2, "min": "medium", "max": "hard"},
        "roster": {
            "landing_pack": [{"monsters": ["kobold", "kobold", "kobold"], "name": "bone-pickers' hall"}],
            "ring_pack": [[{"monsters": ["giant_centipede", "giant_centipede"], "name": "narrow ossuary", "kind": "ambush"}],
                          [{"monsters": ["hobgoblin", "kobold"], "name": "guard post"}]],
            "stairs_guard": {"monsters": ["hobgoblin", "kobold"], "name": "ossuary stair"},
            "optional": {"monsters": ["ghoul"], "name": "charnel chamber"},
        },
        "style": dict(BARROW_STYLE, darkness="#37302b", floor_variant_weights={"plain": 10, "cracked": 4, "mossy": 1, "rubble": 2, "puddle": 0.3}),
    },
    "floor_004": {
        "id": "floor_004", "display_name": "The Webbed Crypts", "floor_number": 4,
        "theme": "The Barrow Warrens", "seed": 404,
        "width": 128, "height": 96, "landings": 6, "rings": 3, "outer": 14, "band": 10,
        "room_len": 10, "hall_half": 9, "props": 1.1, "doors": 0.8, "locked": 0.25, "open": 0.15,
        "vaults": 2, "room_chests": 3, "lock_dc": 14,
        "budget": {"level": 3, "min": "hard", "max": "hard"},
        "roster": {
            "landing_pack": [{"monsters": ["hobgoblin", "goblin"], "name": "war-band camp"}],
            "ring_pack": [[{"monsters": ["hobgoblin", "goblin"], "name": "picket"},
                           {"monsters": ["goblin", "goblin", "goblin"], "name": "goblin warren"}],
                          [{"monsters": ["giant_spider", "giant_centipede"], "name": "webbed gallery", "kind": "ambush"},
                           {"monsters": ["ghoul", "zombie"], "name": "sealed crypt"}]],
            "stairs_guard": {"monsters": ["hobgoblin", "goblin"], "name": "crypt stair"},
            "optional": {"monsters": ["bugbear", "hobgoblin"], "name": "chieftain's tomb"},
        },
        "style": dict(BARROW_STYLE, darkness="#2f2a28", floor_variant_weights={"plain": 10, "cracked": 3, "mossy": 2.5, "rubble": 2, "puddle": 0.5}),
    },
    "floor_005": {
        "id": "floor_005", "display_name": "The Gravebreaker's Hall", "floor_number": 5,
        "theme": "The Barrow Warrens", "seed": 505,
        "width": 128, "height": 96, "landings": 6, "rings": 3, "outer": 14, "band": 10,
        "room_len": 10, "hall_half": 10, "props": 1.2, "doors": 0.8, "locked": 0.25, "open": 0.15,
        "vaults": 3, "room_chests": 3, "lock_dc": 15,
        "budget": {"level": 3, "min": "hard", "max": "hard"},
        "roster": {
            "landing_pack": [{"monsters": ["bugbear", "goblin"], "name": "muster room"}],
            "ring_pack": [[{"monsters": ["goblin", "goblin", "goblin"], "name": "sniper gallery", "kind": "ambush"}],
                          [{"monsters": ["ghoul", "skeleton"], "name": "bone pit"}]],
            "stairs_guard": {"monsters": ["ogre"], "name": "great hall", "boss": True, "kind": "boss"},
            "optional": {"monsters": ["ghoul", "ghoul"], "name": "charnel pit"},
        },
        "style": dict(BARROW_STYLE, darkness="#2a2422", torch_color="#ff9a48", floor_variant_weights={"plain": 9, "cracked": 4, "mossy": 1.5, "rubble": 3, "puddle": 0.3}),
    },
}

LANDING_TEMPLATES = {
    2: ["lr", "tb"],
    4: ["corners", "quarters"],
    6: ["corners+lr", "corners+tb", "quarters+lr"],
}
SPOKE_TEMPLATES = ["tb_quarter", "tb_mid", "lr_mid", "tb_quarter+lr_mid", "tb_mid+lr_mid"]
HALL_TEMPLATES = ["ns", "ns_wide"]


# ---------------------------------------------------------------------------
# Geometry
# ---------------------------------------------------------------------------

class Room:
    def __init__(self, rid, x0, y0, x1, y1, band, side, index):
        self.id = rid
        self.x0, self.y0, self.x1, self.y1 = x0, y0, x1, y1
        self.band = band
        self.side = side  # top bottom left right corner_tl corner_tr corner_bl corner_br hall inner_w inner_ne inner_se
        self.index = index
        self.role = "filler"
        self.openings = []  # cells carved through this room's walls
        self.connect = None  # ("loop", k, wall_side) or ("room", other) chosen for fillers
        self.pillars = []

    @property
    def w(self):
        return self.x1 - self.x0 + 1

    @property
    def h(self):
        return self.y1 - self.y0 + 1

    def rect(self):
        return [self.x0, self.y0, self.w, self.h]

    def contains(self, p):
        return self.x0 <= p[0] <= self.x1 and self.y0 <= p[1] <= self.y1

    def cells(self):
        return [(x, y) for y in range(self.y0, self.y1 + 1) for x in range(self.x0, self.x1 + 1)]

    def centre(self):
        return ((self.x0 + self.x1 + 1) // 2, (self.y0 + self.y1 + 1) // 2)


def segments(s, e, target, need_odd=False):
    """Splits [s, e] into rooms separated by 1-wide walls, mirror symmetric.
    Returns a list of (start, end) interior spans."""
    length = e - s + 1
    n = max(1, int(round((length + 1) / float(target + 1))))
    if need_odd and n % 2 == 0:
        n = n + 1 if (length + 1) / float(target + 1) > n else max(1, n - 1)
    seps = [1] * (n - 1)
    total = length - (n - 1)
    base, rem = divmod(total, n)
    if rem % 2 == 1 and n % 2 == 0:
        seps[(n - 1) // 2] += 1
        total -= 1
        base, rem = divmod(total, n)
    widths = [base] * n
    if rem % 2 == 1:
        widths[n // 2] += 1
        rem -= 1
    i = 0
    while rem > 0:
        widths[i] += 1
        widths[n - 1 - i] += 1
        rem -= 2
        i += 1
    out = []
    x = s
    for k in range(n):
        out.append((x, x + widths[k] - 1))
        x += widths[k]
        if k < n - 1:
            x += seps[k]
    return out


class Layout:
    def __init__(self, p, landing_tpl, spoke_tpls, hall_tpl):
        self.p = p
        self.W, self.H = p["width"], p["height"]
        self.R = p["rings"]
        self.cw = 2
        self.landing_tpl = landing_tpl
        self.spoke_tpls = spoke_tpls
        self.hall_tpl = hall_tpl
        self.grid = [[WALL] * self.W for _ in range(self.H)]
        self.rooms = []
        self.insets = [p["outer"] + k * (self.cw + p["band"]) for k in range(self.R)]
        self.landing_rooms = []  # (room, pack_room, compass id)
        self.gates = []  # per band k>=1: list of rooms
        self.hall = None
        self.optional_room = None
        self.inner_vault = None
        self.shrine = None
        self.ok = True
        self.problems = []
        self.build()

    # -- grid helpers --
    def carve(self, x, y):
        if 0 < x < self.W - 1 and 0 < y < self.H - 1:
            self.grid[y][x] = FLOOR

    def wall(self, x, y):
        self.grid[y][x] = WALL

    def walkable(self, x, y):
        return 0 <= x < self.W and 0 <= y < self.H and self.grid[y][x] != WALL

    def carve_room(self, r):
        for (x, y) in r.cells():
            self.carve(x, y)

    def fill_room(self, r):
        for (x, y) in r.cells():
            self.wall(x, y)

    def add_room(self, x0, y0, x1, y1, band, side, index):
        r = Room("r%d" % (len(self.rooms) + 1), x0, y0, x1, y1, band, side, index)
        self.rooms.append(r)
        return r

    # -- construction --
    def build(self):
        W, H, cw = self.W, self.H, self.cw
        for k, I in enumerate(self.insets):
            for y in range(I, H - I):
                for x in range(I, W - I):
                    if x < I + cw or x > W - 1 - I - cw or y < I + cw or y > H - 1 - I - cw:
                        self.carve(x, y)
        self.band_rooms = []
        for k in range(self.R):
            a = 1 if k == 0 else self.insets[k - 1] + cw
            c = self.insets[k] - 1
            rooms = {"corners": {}, "top": [], "bottom": [], "left": [], "right": []}
            for name, (x0, y0) in {"corner_tl": (a + 1, a + 1), "corner_tr": (W - c, a + 1),
                                   "corner_bl": (a + 1, H - c), "corner_br": (W - c, H - c)}.items():
                rooms["corners"][name] = self.add_room(x0, y0, x0 + (c - a - 2), y0 + (c - a - 2), k, name, 0)
            need_odd_tb = (k == 0 and ("tb" in self.landing_tpl.split("+"))) or (k > 0 and "tb_mid" in self.spoke_tpls[k - 1])
            need_odd_lr = (k == 0 and ("lr" in self.landing_tpl.split("+"))) or (k > 0 and "lr_mid" in self.spoke_tpls[k - 1])
            for i, (s, e) in enumerate(segments(c + 1, W - 2 - c, self.p["room_len"], need_odd_tb)):
                rooms["top"].append(self.add_room(s, a + 1, e, c - 1, k, "top", i))
                rooms["bottom"].append(self.add_room(s, H - c, e, H - 2 - a, k, "bottom", i))
            for i, (s, e) in enumerate(segments(c + 1, H - 2 - c, self.p["room_len"], need_odd_lr)):
                rooms["left"].append(self.add_room(a + 1, s, c - 1, e, k, "left", i))
                rooms["right"].append(self.add_room(W - c, s, W - 2 - a, e, k, "right", i))
            self.band_rooms.append(rooms)
        for r in self.rooms:
            self.carve_room(r)
        self.build_inner()
        self.place_landings()
        for k in range(1, self.R):
            self.place_gates(k)
        self.connect_fillers()
        self.place_pillars()

    def wall_cells_toward(self, r, side, at, width):
        """Cells of r's wall on `side` (outside r) centred on `at` (x for
        top/bottom, y for left/right), `width` cells wide, plus the cell beyond."""
        out = []
        offs = [at - width // 2 + i for i in range(width)] if width > 1 else [at]
        for o in offs:
            if side == "top":
                out.append((o, r.y0 - 1))
            elif side == "bottom":
                out.append((o, r.y1 + 1))
            elif side == "left":
                out.append((r.x0 - 1, o))
            else:
                out.append((r.x1 + 1, o))
        return out

    def open_wall(self, r, side, width=2, at=None):
        cx, cy = r.centre()
        if at is None:
            at = cx if side in ("top", "bottom") else cy
        cells = self.wall_cells_toward(r, side, at, width)
        for (x, y) in cells:
            self.carve(x, y)
            r.openings.append((x, y))
        return cells

    def inward_side(self, r):
        """The wall of a band side room that faces the centre."""
        return {"top": "bottom", "bottom": "top", "left": "right", "right": "left"}[r.side]

    def outward_side(self, r):
        return {"top": "top", "bottom": "bottom", "left": "left", "right": "right"}[r.side]

    def build_inner(self):
        W, H = self.W, self.H
        J = self.insets[-1] + self.cw
        x0, x1, y0, y1 = J + 1, W - 2 - J, J + 1, H - 2 - J
        cx = W // 2
        cy = H // 2
        hw = self.p["hall_half"]
        self.hall = Room("hall", cx - hw, y0, cx + hw - 1, y1, self.R, "hall", 0)
        self.hall.role = "hall"
        self.rooms.append(self.hall)
        self.carve_room(self.hall)
        west = Room("inner_w", x0, y0, cx - hw - 2, y1, self.R, "inner_w", 0)
        ne = Room("inner_ne", cx + hw + 1, y0, x1, cy - 1, self.R, "inner_ne", 0)
        se = Room("inner_se", cx + hw + 1, cy + 1, x1, y1, self.R, "inner_se", 0)
        for r in (west, ne, se):
            self.rooms.append(r)
            self.carve_room(r)
        self.optional_room, self.inner_vault, self.shrine = west, ne, se
        west.role = "optional"
        ne.role = "vault_inner"
        se.role = "shrine"
        if self.hall_tpl == "ns":
            for side in ("top", "bottom"):
                self.open_wall(self.hall, side, 2, cx)
        else:
            for side in ("top", "bottom"):
                for at in (cx - hw // 2, cx + hw // 2):
                    self.open_wall(self.hall, side, 2, at)
        self.open_wall(west, "top", 1)
        west.door_cells = list(west.openings)
        self.open_wall(ne, "top", 1)
        ne.door_cells = list(ne.openings)
        self.open_wall(se, "bottom", 1)
        se.door_cells = list(se.openings)
        self.stairs = (cx, cy)

    def place_landings(self):
        rooms = self.band_rooms[0]
        tb, lr = rooms["top"], rooms["left"]
        picks = []  # (landing room, pack room, compass)
        parts = self.landing_tpl.split("+")
        corner_pack = {"corner_tl": rooms["top"][0], "corner_tr": rooms["top"][-1],
                       "corner_bl": rooms["bottom"][0], "corner_br": rooms["bottom"][-1]}
        compass = {"corner_tl": "nw", "corner_tr": "ne", "corner_bl": "sw", "corner_br": "se"}
        if "corners" in parts:
            for name in ("corner_tl", "corner_tr", "corner_bl", "corner_br"):
                picks.append((rooms["corners"][name], corner_pack[name], compass[name]))
        if "quarters" in parts:
            n = len(tb)
            q = max(1, n // 4)
            for side, cmp in (("top", "n"), ("bottom", "s")):
                lst = rooms[side]
                picks.append((lst[q], lst[q + 1], cmp + "w"))
                picks.append((lst[n - 1 - q], lst[n - 2 - q], cmp + "e"))
        if "tb" in parts:
            for side, cmp in (("top", "n"), ("bottom", "s")):
                lst = rooms[side]
                m = len(lst) // 2
                picks.append((lst[m], lst[m + 1], cmp))
        if "lr" in parts:
            for side, cmp in (("left", "w"), ("right", "e")):
                lst = rooms[side]
                m = len(lst) // 2
                picks.append((lst[m], lst[m + 1], cmp))
        used = set()
        for (lr_room, pack, cmp) in picks:
            if lr_room.id in used or pack.id in used:
                self.ok = False
                self.problems.append("landing template %s overlaps" % self.landing_tpl)
                return
            used.add(lr_room.id)
            used.add(pack.id)
            lr_room.role = "landing"
            pack.role = "pack"
            # opening between landing room and pack room (they share a separator)
            self.open_between(lr_room, pack, 2)
            self.open_wall(pack, self.inward_side(pack), 2)
            self.landing_rooms.append((lr_room, pack, cmp))
        order = {"nw": 0, "n": 1, "ne": 2, "e": 3, "se": 4, "s": 5, "sw": 6, "w": 7,
                 "nnw": 0, "nne": 2, "sse": 4, "ssw": 6}
        self.landing_rooms.sort(key=lambda t: (order.get(t[2], 9), t[2]))

    def open_between(self, a, b, width):
        """Carves a gap through the wall separating two adjacent rooms."""
        if a.x1 < b.x0 or b.x1 < a.x0:  # side by side horizontally
            left, right = (a, b) if a.x1 < b.x0 else (b, a)
            lo, hi = max(left.y0, right.y0), min(left.y1, right.y1)
            mid = (lo + hi + 1) // 2
            cells = [(x, mid - width // 2 + i) for x in range(left.x1 + 1, right.x0) for i in range(width)]
        else:
            top, bot = (a, b) if a.y1 < b.y0 else (b, a)
            lo, hi = max(top.x0, bot.x0), min(top.x1, bot.x1)
            mid = (lo + hi + 1) // 2
            cells = [(mid - width // 2 + i, y) for y in range(top.y1 + 1, bot.y0) for i in range(width)]
        for (x, y) in cells:
            self.carve(x, y)
            a.openings.append((x, y))
            b.openings.append((x, y))
        return cells

    def place_gates(self, k):
        rooms = self.band_rooms[k]
        tpl = self.spoke_tpls[k - 1]
        chosen = []
        parts = tpl.split("+")
        if "tb_quarter" in parts:
            n = len(rooms["top"])
            q = max(0, min(n - 1, (n - 1) // 4)) if n >= 4 else 0
            for side in ("top", "bottom"):
                lst = rooms[side]
                chosen += [lst[q], lst[len(lst) - 1 - q]]
        if "tb_mid" in parts:
            for side in ("top", "bottom"):
                lst = rooms[side]
                chosen.append(lst[len(lst) // 2])
        if "lr_mid" in parts:
            for side in ("left", "right"):
                lst = rooms[side]
                chosen.append(lst[len(lst) // 2])
        gates = []
        for r in chosen:
            if r.role == "gate":
                continue
            r.role = "gate"
            self.open_wall(r, self.outward_side(r), 2)
            self.open_wall(r, self.inward_side(r), 2)
            gates.append(r)
        self.gates.append(gates)

    def connect_fillers(self):
        """Band 0 fillers open onto loop 0; band k fillers onto one loop.
        Band-0 corner fillers open into a neighbouring filler side room."""
        for k in range(self.R):
            rooms = self.band_rooms[k]
            for name, r in rooms["corners"].items():
                if r.role != "filler":
                    continue
                if k > 0:
                    side = "top" if name in ("corner_tl", "corner_tr") else "bottom"
                    r.connect = ("loop", k - 1, side)
                else:
                    ncands = [rooms["top"][0] if name == "corner_tl" else None,
                              rooms["top"][-1] if name == "corner_tr" else None,
                              rooms["bottom"][0] if name == "corner_bl" else None,
                              rooms["bottom"][-1] if name == "corner_br" else None,
                              rooms["left"][0] if name == "corner_tl" else None,
                              rooms["right"][0] if name == "corner_tr" else None,
                              rooms["left"][-1] if name == "corner_bl" else None,
                              rooms["right"][-1] if name == "corner_br" else None]
                    target = next((n for n in ncands if n is not None and n.role == "filler"), None)
                    if target is None:
                        r.role = "sealed"
                        self.fill_room(r)
                    else:
                        r.connect = ("room", target)
            for side in ("top", "bottom", "left", "right"):
                for r in rooms[side]:
                    if r.role != "filler":
                        continue
                    if k == 0:
                        r.connect = ("loop", 0, self.inward_side(r))
                    else:
                        r.connect = ("loop", k, self.inward_side(r)) if r.index % 2 == 0 else ("loop", k - 1, self.outward_side(r))

    def place_pillars(self):
        """Symmetric pillars in large rooms (never in front of an opening)."""
        for r in self.rooms:
            if r.role in ("sealed",) or r.w < 8 or r.h < 8:
                continue
            cands = [(r.x0 + 2, r.y0 + 2), (r.x1 - 2, r.y0 + 2), (r.x0 + 2, r.y1 - 2), (r.x1 - 2, r.y1 - 2)]
            if r.role == "hall":
                cands = [(r.x0 + 2, r.y0 + 2), (r.x1 - 2, r.y0 + 2), (r.x0 + 2, r.y1 - 2), (r.x1 - 2, r.y1 - 2)]
                if r.w >= 16:
                    cands += [(r.x0 + 2, (r.y0 + r.y1) // 2), (r.x1 - 2, (r.y0 + r.y1) // 2)]
            for (x, y) in cands:
                if any(abs(x - ox) <= 2 and abs(y - oy) <= 2 for (ox, oy) in r.openings):
                    continue
                if abs(x - self.stairs[0]) <= 3 and abs(y - self.stairs[1]) <= 3:
                    continue
                self.wall(x, y)
                r.pillars.append((x, y))


# ---------------------------------------------------------------------------
# Path finding (same rules as WalkMap: 8 directions, no corner cutting)
# ---------------------------------------------------------------------------

DIRS8 = [(-1, -1), (0, -1), (1, -1), (-1, 0), (1, 0), (-1, 1), (0, 1), (1, 1)]


def bfs(rows_walk, w, h, start, blocked=frozenset()):
    dist = {start: 0}
    q = deque([start])
    while q:
        cx, cy = q.popleft()
        d = dist[(cx, cy)]
        for dx, dy in DIRS8:
            nx, ny = cx + dx, cy + dy
            if not (0 <= nx < w and 0 <= ny < h) or not rows_walk[ny][nx] or (nx, ny) in blocked or (nx, ny) in dist:
                continue
            if dx != 0 and dy != 0 and (not rows_walk[cy][nx] or not rows_walk[ny][cx]):
                continue
            dist[(nx, ny)] = d + 1
            q.append((nx, ny))
    return dist


def walk_grid(rows):
    return [[c != WALL for c in row] for row in rows]


def chest_tier(floor_number):
    """Loot tier of a floor's stairs chest and hidden cache: 1 on floors 1-2, else 2."""
    return 1 if floor_number <= 2 else 2


# ---------------------------------------------------------------------------
# Content
# ---------------------------------------------------------------------------

class Builder:
    def __init__(self, p, seed):
        self.p = p
        self.seed = seed
        self.rng = random.Random(seed)
        self.layout = self.choose_layout()
        L = self.layout
        self.W, self.H = L.W, L.H
        self.occupied = {}  # cell -> label (stairs, landings, chests, doors, props)
        self.spawn = set()
        self.zones = []
        self.chests = []
        self.doors = []
        self.props = []
        self.landings = []
        self.build_content()

    # -- layout search --
    def choose_layout(self):
        n = self.p["landings"]
        if n not in LANDING_TEMPLATES:
            raise SystemExit("landings must be one of %s" % sorted(LANDING_TEMPLATES))
        best = None
        combos = [[]]
        for _ in range(self.p["rings"] - 1):
            combos = [c + [t] for c in combos for t in SPOKE_TEMPLATES]
        for ltpl in LANDING_TEMPLATES[n]:
            for spokes in combos:
                for htpl in HALL_TEMPLATES:
                    lay = Layout(self.p, ltpl, spokes, htpl)
                    if not lay.ok or len(lay.landing_rooms) != n:
                        continue
                    rows = ["".join(r) for r in lay.grid]
                    dist = bfs(walk_grid(rows), lay.W, lay.H, lay.stairs)
                    lens = []
                    for (room, _pack, _c) in lay.landing_rooms:
                        lens.append(dist.get(room.centre(), 10 ** 6))
                    spread = max(lens) / float(max(1, min(lens)))
                    # balanced routes first, then the most gates (room for many
                    # parties), then the closest balance
                    bucket = 0 if spread <= 1.08 else 1 if spread <= 1.15 else 2
                    key = (bucket, -sum(len(g) for g in lay.gates), round(spread, 3), ltpl, tuple(spokes), htpl)
                    if best is None or key < best[0]:
                        best = (key, lay)
        if best is None:
            raise SystemExit("no landing / spoke template fits these parameters")
        return best[1]

    # -- helpers --
    def free(self, cell, room=None, margin_openings=1):
        x, y = cell
        if not self.layout.walkable(x, y) or cell in self.occupied or cell in self.spawn:
            return False
        if room is not None:
            for (ox, oy) in room.openings:
                if abs(ox - x) <= margin_openings and abs(oy - y) <= margin_openings:
                    return False
        return True

    def take(self, cell, label):
        self.occupied[cell] = label

    def wall_adjacent(self, cell):
        x, y = cell
        return any(not self.layout.walkable(x + dx, y + dy) for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)))

    def on_spoke_line(self, room, cell):
        """Cells on the straight line between a room's openings (keep routes clear)."""
        x, y = cell
        for (ox, oy) in room.openings:
            if room.side in ("top", "bottom") and abs(x - ox) <= 0 and room.role == "gate":
                return True
            if room.side in ("left", "right") and abs(y - oy) <= 0 and room.role == "gate":
                return True
        return False

    # -- content --
    def build_content(self):
        L = self.layout
        p = self.p
        rng = self.rng
        self.take(L.stairs, "stairs")
        roster = p["roster"]
        zone_n = [0]

        def new_zone(room, spec, extra):
            zone_n[0] += 1
            zid = "z%d" % zone_n[0]
            monsters = list(spec["monsters"])
            spawns = self.pick_spawns(room, len(monsters), extra.get("near"))
            z = {"id": zid, "name": spec.get("name", ""), "kind": spec.get("kind", "pack"),
                 "rect": room.rect(), "monster_ids": monsters,
                 "spawn_points": [list(s) for s in spawns]}
            if spec.get("boss"):
                z["boss"] = True
            if extra.get("guards_stairs"):
                z["guards_stairs"] = True
            if extra.get("optional"):
                z["optional"] = True
            z["respawns"] = True
            z["_role"] = extra["role"]
            room.zone = z
            self.zones.append(z)
            return z

        # landings
        for i, (room, pack, cmp) in enumerate(L.landing_rooms):
            pos = self.landing_cell(room, pack)
            facing = self.facing_towards(pos, pack.centre())
            self.landings.append({"id": cmp, "position": list(pos), "facing": facing})
            self.take(pos, "landing")
            room.landing = pos
        # stairs-hall chest first (so spawns avoid it), then zones
        sx, sy = L.stairs
        chest_cell = (sx + 2, sy)
        self.take(chest_cell, "chest")
        fn = p["floor_number"]
        tier = chest_tier(fn)
        self.chests.append({"id": "f%d_stairs" % fn, "position": list(chest_cell), "table": "chest_stairs_t%d" % tier, "hidden": False})
        # optional room: hidden cache in the far corner from its door
        opt = L.optional_room
        hid = self.far_cell(opt, opt.door_cells[0])
        self.take(hid, "chest")
        self.chests.append({"id": "f%d_hidden" % fn, "position": list(hid), "table": "cache_t%d" % tier, "hidden": True})
        # zones: landing packs, gates per band, stairs guard, optional
        lp = roster["landing_pack"]
        for i, (_room, pack, _c) in enumerate(L.landing_rooms):
            new_zone(pack, lp[i % len(lp)], {"role": "landing_pack"})
        for k, gates in enumerate(L.gates):
            band_roster = roster["ring_pack"][min(k, len(roster["ring_pack"]) - 1)]
            for i, g in enumerate(gates):
                new_zone(g, band_roster[i % len(band_roster)], {"role": "ring_pack"})
        new_zone(L.hall, roster["stairs_guard"], {"role": "stairs_guard", "guards_stairs": True, "near": L.stairs})
        new_zone(opt, roster["optional"], {"role": "optional", "optional": True})
        # doors: optional room, inner vault, shrine
        self.add_door(opt.door_cells[0], "closed")
        self.add_door(L.inner_vault.door_cells[0], "locked", p["lock_dc"])
        self.add_door(L.shrine.door_cells[0], "closed")
        vc = self.far_cell(L.inner_vault, L.inner_vault.door_cells[0])
        self.take(vc, "chest")
        self.chests.append({"id": "f%d_vault_1" % fn, "position": list(vc), "table": "monster_medium", "hidden": False})
        # fillers
        fillers = [r for r in L.rooms if r.role == "filler" and r.connect is not None]
        order = list(fillers)
        rng.shuffle(order)
        extra_vaults = [r for r in order if r.connect[0] == "loop" and r.band > 0][: max(0, p["vaults"] - 1)]
        vault_ids = set(r.id for r in extra_vaults)
        for r in fillers:
            kind, *rest = r.connect
            if kind == "loop":
                cells = L.open_wall(r, rest[1], 1)
            else:
                cells = L.open_between(r, rest[0], 1)
                cells = cells[len(cells) // 2: len(cells) // 2 + 1] if len(cells) > 1 else cells
            cell = cells[0]
            if r.id in vault_ids:
                r.role = "vault"
                self.add_door(cell, "locked", p["lock_dc"])
                vc = self.far_cell(r, cell)
                self.take(vc, "chest")
                self.chests.append({"id": "f%d_vault_%d" % (fn, len([c for c in self.chests if "_vault_" in c["id"]]) + 1),
                                    "position": list(vc), "table": "monster_medium", "hidden": False})
                continue
            roll = rng.random()
            if roll < p["doors"]:
                state = "open" if rng.random() < p["open"] else "closed"
                if rng.random() < p["locked"] * 0.5:
                    state = "locked"
                self.add_door(cell, state, p["lock_dc"] if state == "locked" else 0)
        # room chests in a few filler rooms
        plain = [r for r in fillers if r.role == "filler"]
        rng.shuffle(plain)
        for i, r in enumerate(plain[: p["room_chests"]]):
            cell = self.far_cell(r, r.openings[0] if r.openings else r.centre())
            self.take(cell, "chest")
            self.chests.append({"id": "f%d_cache_%d" % (fn, i + 1), "position": list(cell), "table": "monster_small", "hidden": False})
        self.place_props()
        self.place_keys()

    def landing_cell(self, room, pack):
        cx, cy = room.centre()
        return (cx, cy)

    @staticmethod
    def facing_towards(a, b):
        dx, dy = b[0] - a[0], b[1] - a[1]
        if abs(dx) >= abs(dy):
            return "east" if dx > 0 else "west"
        return "south" if dy > 0 else "north"

    def far_cell(self, room, ref):
        cells = [c for c in room.cells() if self.free(c, room, 1)]
        cells.sort(key=lambda c: (-(abs(c[0] - ref[0]) + abs(c[1] - ref[1])), c[1], c[0]))
        return cells[0]

    def pick_spawns(self, room, n, near=None):
        cells = [c for c in room.cells() if self.free(c, room, 2) and not self.on_spoke_line(room, c)]
        if near is not None:
            ring = [c for c in cells if 2 <= max(abs(c[0] - near[0]), abs(c[1] - near[1])) <= 4]
            if len(ring) >= n:
                cells = ring
        cells.sort(key=lambda c: (c[1], c[0]))
        self.rng.shuffle(cells)
        out = []
        for c in cells:
            if all(max(abs(c[0] - o[0]), abs(c[1] - o[1])) >= 2 for o in out):
                out.append(c)
            if len(out) == n:
                break
        if len(out) < n:
            for c in cells:
                if c not in out:
                    out.append(c)
                if len(out) == n:
                    break
        for c in out:
            self.spawn.add(c)
        return sorted(out, key=lambda c: (c[1], c[0]))

    def add_door(self, cell, state, dc=0):
        d = {"id": "d%d" % (len(self.doors) + 1), "position": list(cell), "state": state}
        if state == "locked":
            d["dc"] = dc
        self.doors.append(d)
        self.take(tuple(cell), "door")

    def add_prop(self, cell, kind, loot=None):
        pr = {"id": "p%d" % (len(self.props) + 1), "kind": kind, "position": list(cell),
              "hp": PROP_HP[kind], "blocks": PROP_BLOCKS[kind]}
        if loot:
            pr["loot_table"] = loot
        self.props.append(pr)
        self.take(cell, "prop")

    def place_props(self):
        L, rng, p = self.layout, self.rng, self.p
        # braziers: by every landing, flanking the stairs, in the optional crypt
        for (room, _pack, _c) in L.landing_rooms:
            lx, ly = room.landing
            for c in ((room.x0, room.y0), (room.x1, room.y1)):
                if self.free(c, room, 1):
                    self.add_prop(c, "brazier")
        sx, sy = L.stairs
        for c in ((sx - 2, sy - 2), (sx + 2, sy - 2), (sx - 2, sy + 2), (sx + 2, sy + 2)):
            if self.free(c, L.hall, 1):
                self.add_prop(c, "brazier")
        for r in (L.optional_room, L.shrine):
            c = r.centre()
            if self.free(c, r, 1):
                self.add_prop(c, "brazier")
        # barrels / crates along walls, bones and rubble scattered
        for r in L.rooms:
            if r.role in ("sealed", "landing"):
                continue
            n = int(p["props"] * 2 + rng.random() * p["props"] * 2)
            if r.role in ("hall",):
                n = 2
            wall_cells = [c for c in r.cells() if self.free(c, r, 1) and self.wall_adjacent(c) and not self.on_spoke_line(r, c)]
            wall_cells.sort(key=lambda c: (c[1], c[0]))
            rng.shuffle(wall_cells)
            for c in wall_cells[:n]:
                if not self.free(c, r, 1):
                    continue
                kind = "barrel" if rng.random() < 0.5 else "crate"
                loot = "monster_small" if rng.random() < 0.5 else None
                self.add_prop(c, kind, loot)
            scatter = [c for c in r.cells() if self.free(c, r, 1)]
            scatter.sort(key=lambda c: (c[1], c[0]))
            rng.shuffle(scatter)
            nd = 1 + int(rng.random() * 2 * p["props"]) if r.role in ("optional", "gate", "pack", "hall") else int(rng.random() * 2 * p["props"])
            for c in scatter[:nd]:
                kind = "bones" if r.role in ("optional", "hall", "gate") or rng.random() < 0.5 else "rubble"
                self.add_prop(c, kind, "monster_small" if kind == "bones" and rng.random() < 0.2 else None)
        # debris in the loop corridors
        loops = []
        for y in range(self.H):
            for x in range(self.W):
                if L.walkable(x, y) and not any(r.contains((x, y)) for r in L.rooms) and (x, y) not in self.occupied:
                    loops.append((x, y))
        rng.shuffle(loops)
        count = int(len(loops) * 0.01 * p["props"])
        for c in loops[:count]:
            if self.free(c, None) and not self.next_to_door(c):
                self.add_prop(c, "rubble" if rng.random() < 0.6 else "bones")

    def place_keys(self):
        """Turns a share of the locked doors into key doors, each with a key
        prop on the landings' side (own random stream: nothing else moves)."""
        share = float(self.p.get("key_doors", KEY_DOORS_DEFAULT))
        krng = random.Random(self.seed * 7919 + 17)
        locked = [d for d in self.doors if d["state"] == "locked"]
        n = min(len(KEY_ITEMS), int(len(locked) * share + 0.5))
        if n <= 0:
            return
        chosen = sorted(krng.sample(locked, n), key=lambda d: int(d["id"][1:]))
        rows = self.rows()
        walk = walk_grid(rows)
        w, h = self.W, self.H
        prop_block = set(tuple(pr["position"]) for pr in self.props if pr["blocks"])
        locked_cells = set(tuple(d["position"]) for d in locked)
        stairs = tuple(self.layout.stairs)
        # tiles every landing reaches without passing a locked door or a blocking prop
        safe = bfs(walk, w, h, stairs, frozenset((locked_cells | prop_block) - {stairs}))
        used = set()
        for i, door in enumerate(chosen):
            key = KEY_ITEMS[i]
            dpos = tuple(door["position"])
            dist = bfs(walk, w, h, dpos, frozenset((locked_cells - {dpos}) | prop_block))
            best = None
            for pr in self.props:
                if pr["id"] in used or pr.get("drops"):
                    continue
                pp = tuple(pr["position"])
                if pr["blocks"]:
                    near = [dist[(pp[0] + dx, pp[1] + dy)] + 1 for dx, dy in DIRS8
                            if (pp[0] + dx, pp[1] + dy) in dist and (pp[0] + dx, pp[1] + dy) in safe]
                    if not near:
                        continue
                    dd = min(near)
                else:
                    if pp not in dist or pp not in safe:
                        continue
                    dd = dist[pp]
                lo, hi = KEY_RANGE
                out_of_range = 0 if lo <= dd <= hi else 1 + min(abs(dd - lo), abs(dd - hi))
                in_zone = any(z["rect"][0] <= pp[0] < z["rect"][0] + z["rect"][2] and
                              z["rect"][1] <= pp[1] < z["rect"][1] + z["rect"][3] for z in self.zones)
                # a crate or barrel, then no farther than KEY_MAX_WALK, outside
                # every zone, then as close to KEY_RANGE as possible
                key_tuple = (0 if pr["kind"] in KEY_PROP_KINDS else 1, 1 if dd > KEY_MAX_WALK else 0,
                             1 if in_zone else 0, out_of_range,
                             krng.random(), int(pr["id"][1:]))
                if best is None or key_tuple < best[0]:
                    best = (key_tuple, pr)
            if best is None:
                continue  # no reachable prop: the door stays DC-only
            pr = best[1]
            used.add(pr["id"])
            door["key_item"] = key
            pr["drops"] = [{"item": key, "qty": 1}]

    def next_to_door(self, c):
        return any((c[0] + dx, c[1] + dy) in self.occupied and self.occupied[(c[0] + dx, c[1] + dy)] == "door"
                   for dx, dy in DIRS8)

    # -- output --
    def rows(self):
        L = self.layout
        g = [list(r) for r in L.grid]
        sx, sy = L.stairs
        g[sy][sx] = "S"
        for i, l in enumerate(self.landings):
            x, y = l["position"]
            g[y][x] = "A" if i == 0 else "L"
        for d in self.doors:
            x, y = d["position"]
            g[y][x] = "D"
        return ["".join(r) for r in g]

    def floor_dict(self, generated_by):
        p = self.p
        zones = []
        for z in self.zones:
            zz = {k: v for k, v in z.items() if not k.startswith("_")}
            zones.append(zz)
        d = {
            "schema_version": 2,
            "id": p["id"],
            "display_name": p["display_name"],
            "floor_number": p["floor_number"],
            "theme": p["theme"],
            "generated_by": generated_by,
            "budget": p["budget"],
            "respawn": {"pack_seconds": 600, "boss_seconds": 1800},
            "theme_style": p.get("style", {}),
            "rows": self.rows(),
            "arrival": self.landings[0]["position"],
            "stairs": list(self.layout.stairs),
            "landings": self.landings,
            "encounter_zones": zones,
            "chests": self.chests,
            "doors": self.doors,
            "props": self.props,
        }
        return d


# ---------------------------------------------------------------------------
# JSON output (one object per line in lists, one row per line)
# ---------------------------------------------------------------------------

def compact(v):
    return json.dumps(v, ensure_ascii=False, separators=(", ", ": "))


def dump_floor(d):
    out = ["{"]
    keys = list(d.keys())
    for i, k in enumerate(keys):
        v = d[k]
        comma = "," if i < len(keys) - 1 else ""
        if isinstance(v, list) and v and (isinstance(v[0], (dict, str))) and k != "arrival":
            out.append("\t%s: [" % json.dumps(k))
            for j, item in enumerate(v):
                out.append("\t\t%s%s" % (compact(item), "," if j < len(v) - 1 else ""))
            out.append("\t]%s" % comma)
        else:
            out.append("\t%s: %s%s" % (json.dumps(k), compact(v), comma))
    out.append("}")
    return "\n".join(out) + "\n"


# ---------------------------------------------------------------------------
# Checks (the rules of FloorFile.structural_problems + FloorData.validate)
# ---------------------------------------------------------------------------

def load_ids(sub):
    out = {}
    for path in glob.glob(os.path.join(ROOT, "data", sub, "*.json")):
        try:
            with open(path, encoding="utf-8") as f:
                rec = json.load(f)
            out[str(rec.get("id", os.path.basename(path)[:-5]))] = rec
        except (OSError, ValueError):
            pass
    return out


def is_pair(v):
    return isinstance(v, list) and len(v) == 2 and all(isinstance(n, (int, float)) and not isinstance(n, bool) for n in v)


def check_floor(d, loot=None, monsters=None, items=None):
    """Problems with a floor dictionary (schema 2 rules); [] when valid."""
    probs = []
    if d.get("schema_version") != 2:
        probs.append("schema_version must be 2")
    rows = d.get("rows")
    if not isinstance(rows, list) or not rows or not all(isinstance(r, str) for r in rows):
        return probs + ["'rows' must be a non-empty array of strings"]
    w, h = len(rows[0]), len(rows)
    markers = {"A": [], "S": [], "L": [], "D": []}
    for y, row in enumerate(rows):
        if len(row) != w:
            probs.append("row %d has width %d, expected %d" % (y, len(row), w))
        for x, c in enumerate(row):
            if c not in LEGEND_V2:
                probs.append("unknown tile '%s' at (%d, %d)" % (c, x, y))
            elif c in markers:
                markers[c].append((x, y))
    if probs:
        return probs
    walk = walk_grid(rows)

    def walkable(p):
        return 0 <= p[0] < w and 0 <= p[1] < h and walk[p[1]][p[0]]

    landings = d.get("landings")
    if not isinstance(landings, list) or not landings:
        return probs + ["'landings' must be a non-empty array"]
    for l in landings:
        if not isinstance(l, dict) or not is_pair(l.get("position")) or not isinstance(l.get("id"), str) or not l["id"]:
            return probs + ["malformed landing %r" % (l,)]
        if "facing" in l and l["facing"] not in FACINGS:
            probs.append("landing '%s' facing '%s'" % (l["id"], l["facing"]))
    arrival = tuple(d.get("arrival", landings[0]["position"]))
    if arrival != tuple(landings[0]["position"]):
        probs.append("arrival %s is not landings[0]" % (arrival,))
    if not is_pair(d.get("stairs")):
        return probs + ["'stairs' must be [x, y]"]
    stairs = tuple(d["stairs"])
    if markers["A"] and markers["A"] != [arrival]:
        probs.append("'A' marker does not match arrival")
    if markers["S"] and markers["S"] != [stairs]:
        probs.append("'S' marker does not match stairs")
    lpos = [tuple(l["position"]) for l in landings]
    for m in markers["L"]:
        if m not in lpos[1:]:
            probs.append("'L' marker %s is not a landing" % (m,))
    doors = d.get("doors", [])
    props = d.get("props", [])
    chests = d.get("chests", [])
    zones = d.get("encounter_zones", [])
    dpos = [tuple(x["position"]) for x in doors]
    for m in markers["D"]:
        if m not in dpos:
            probs.append("'D' marker %s is not a door" % (m,))
    for label, p in (("arrival", arrival), ("stairs", stairs)):
        if not walkable(p):
            probs.append("%s %s is not walkable" % (label, p))
    if arrival == stairs:
        probs.append("arrival and stairs are the same tile")

    def zone_at(p):
        for z in zones:
            x, y, zw, zh = z["rect"]
            if x <= p[0] < x + zw and y <= p[1] < y + zh:
                return z
        return None

    door_at = {tuple(x["position"]): x for x in doors}
    prop_at = {tuple(x["position"]): x for x in props}
    ids = set()
    for z in zones:
        ctx = "zone '%s'" % z.get("id")
        if not z.get("id") or z["id"] in ids:
            probs.append("%s: empty or duplicate id" % ctx)
        ids.add(z.get("id"))
        x, y, zw, zh = z["rect"]
        if zw <= 0 or zh <= 0 or x < 0 or y < 0 or x + zw > w or y + zh > h:
            probs.append("%s rect out of bounds or empty" % ctx)
        if z.get("kind", "pack") not in ZONE_KINDS:
            probs.append("%s kind" % ctx)
        mons = z.get("monster_ids", [])
        if not mons:
            probs.append("%s has no monsters" % ctx)
        if monsters is not None:
            for m in mons:
                if m not in monsters:
                    probs.append("%s unknown monster '%s'" % (ctx, m))
        sp = [tuple(s) for s in z.get("spawn_points", [])]
        if len(sp) < len(mons):
            probs.append("%s has %d monsters but %d spawn points" % (ctx, len(mons), len(sp)))
        if len(set(sp)) != len(sp):
            probs.append("%s repeats a spawn point" % ctx)
        for s in sp:
            if not (x <= s[0] < x + zw and y <= s[1] < y + zh):
                probs.append("%s spawn %s outside rect" % (ctx, s))
            if not walkable(s):
                probs.append("%s spawn %s not walkable" % (ctx, s))
            if s in door_at or (s in prop_at and prop_at[s].get("blocks", True)):
                probs.append("%s spawn %s on a door or blocking prop" % (ctx, s))
        if z.get("guards_stairs") and zone_at(stairs) is not z:
            probs.append("%s guards the stairs but does not hold them" % ctx)
    owners = {stairs: "stairs"}
    for label, lst in (("landing", landings), ("chest", chests), ("door", doors), ("prop", props)):
        seen = set()
        for o in lst:
            oid = o.get("id")
            if not oid or oid in seen:
                probs.append("%s: empty or duplicate id '%s'" % (label, oid))
            seen.add(oid)
            p = tuple(o["position"])
            if not walkable(p):
                probs.append("%s '%s' %s is not walkable" % (label, oid, p))
            if p in owners:
                probs.append("%s and %s '%s' share tile %s" % (owners[p], label, oid, p))
            owners[p] = "%s '%s'" % (label, oid)
    for l in landings:
        p = tuple(l["position"])
        if zone_at(p) is not None:
            probs.append("landing '%s' is inside zone '%s'" % (l["id"], zone_at(p)["id"]))
        nx = abs(p[0] + 0.5 - w / 2.0) / (w / 2.0)
        ny = abs(p[1] + 0.5 - h / 2.0) / (h / 2.0)
        if max(nx, ny) < LANDING_MIN_EDGE_RATIO - 0.0001:
            probs.append("landing '%s' %s is not on the outer third" % (l["id"], p))
    for c in chests:
        if not c.get("table"):
            probs.append("chest '%s' has no table" % c.get("id"))
        elif loot is not None and c["table"] not in loot:
            probs.append("chest '%s' unknown table '%s'" % (c.get("id"), c["table"]))
    for door in doors:
        ctx = "door '%s'" % door.get("id")
        st = door.get("state", "closed")
        if st not in DOOR_STATES:
            probs.append("%s state '%s'" % (ctx, st))
        if st == "locked" and int(door.get("dc", 0)) <= 0 and not door.get("key_item"):
            probs.append("%s is locked with neither dc nor key_item" % ctx)
        x, y = door["position"]
        n, s, wv, e = walkable((x, y - 1)), walkable((x, y + 1)), walkable((x - 1, y)), walkable((x + 1, y))
        if not ((not n and not s and wv and e) or (not wv and not e and n and s)):
            probs.append("%s %s is not a 1-wide corridor cell" % (ctx, (x, y)))
    for pr in props:
        ctx = "prop '%s'" % pr.get("id")
        if pr.get("kind") not in PROP_KINDS:
            probs.append("%s kind '%s'" % (ctx, pr.get("kind")))
        if int(pr.get("hp", 1)) < 1:
            probs.append("%s hp" % ctx)
        lt = pr.get("loot_table")
        if lt and loot is not None and lt not in loot:
            probs.append("%s unknown table '%s'" % (ctx, lt))
        drops = pr.get("drops", [])
        if not isinstance(drops, list):
            probs.append("%s drops must be an array" % ctx)
            continue
        for dr in drops:
            if not isinstance(dr, dict) or not isinstance(dr.get("item"), str) or not dr["item"]:
                probs.append("%s has a malformed drop %r" % (ctx, dr))
            elif not isinstance(dr.get("qty", 1), int) or dr.get("qty", 1) < 1:
                probs.append("%s drop '%s' qty must be at least 1" % (ctx, dr["item"]))
            elif items is not None and dr["item"] not in items:
                probs.append("%s drops unknown item '%s'" % (ctx, dr["item"]))
    sz = zone_at(stairs)
    if sz is None:
        probs.append("the stairs are not inside a zone")
    else:
        if not sz.get("guards_stairs"):
            probs.append("zone '%s' holds the stairs but is not guards_stairs" % sz["id"])
        x, y, zw, zh = sz["rect"]
        if not any(x <= c["position"][0] < x + zw and y <= c["position"][1] < y + zh for c in chests):
            probs.append("stairs zone '%s' has no chest" % sz["id"])
    blocked = set(p for p, pr in prop_at.items() if pr.get("blocks", True))
    blocked |= set(p for p, dr in door_at.items() if dr.get("state") == "locked")
    blocked.discard(stairs)
    blocked = frozenset(blocked)
    dist = bfs(walk, w, h, stairs, frozenset(blocked))
    lens = []
    for l in landings:
        p = tuple(l["position"])
        if p not in dist:
            probs.append("stairs are not reachable from landing '%s' %s" % (l["id"], p))
        else:
            lens.append(dist[p])
    if lens and max(lens) > ROUTE_SPREAD_MAX * min(lens):
        probs.append("landing routes %s differ by more than %d%%" % (lens, round((ROUTE_SPREAD_MAX - 1) * 100)))
    # every walkable tile is reachable once locked doors are opened (no sealed pockets)
    open_dist = bfs(walk, w, h, stairs, frozenset(p for p in blocked if p not in door_at))
    pockets = sum(1 for y in range(h) for x in range(w) if walk[y][x] and (x, y) not in open_dist and (x, y) not in blocked)
    if pockets:
        probs.append("%d walkable tiles cannot be reached from the stairs" % pockets)
    probs += check_keys(d, walk, w, h, blocked)
    return probs


def key_doors(d):
    """[(door, key prop or None)] for every door with a key_item."""
    out = []
    for door in d.get("doors", []):
        key = door.get("key_item")
        if key:
            holders = [pr for pr in d.get("props", []) if any(isinstance(x, dict) and x.get("item") == key
                                                                for x in pr.get("drops", []))]
            out.append((door, holders))
    return out


def check_keys(d, walk, w, h, blocked):
    """Key doors: unique key per floor, exactly one prop drops it, and every
    landing reaches that prop (its tile or a neighbour) past no locked door or
    blocking prop."""
    probs = []
    seen = {}
    floods = {}
    for door, holders in key_doors(d):
        key = door["key_item"]
        ctx = "door '%s' key_item '%s'" % (door.get("id"), key)
        if key in seen:
            probs.append("doors '%s' and '%s' share key_item '%s'" % (seen[key], door.get("id"), key))
            continue
        seen[key] = door.get("id")
        if len(holders) != 1:
            probs.append("%s is dropped by %d props (needs exactly 1)" % (ctx, len(holders)))
            continue
        pr = holders[0]
        pp = tuple(pr["position"])
        targets = [(pp[0] + dx, pp[1] + dy) for dx, dy in DIRS8]
        if not pr.get("blocks", True):
            targets.append(pp)
        for l in d["landings"]:
            lp = tuple(l["position"])
            if lp not in floods:
                floods[lp] = bfs(walk, w, h, lp, frozenset(blocked - {lp}))
            if not any(t in floods[lp] for t in targets):
                probs.append("key prop '%s' (%s for door '%s') is not reachable from landing '%s'" % (
                    pr.get("id"), key, door.get("id"), l["id"]))
    return probs


def stats(d, monsters=None):
    rows = d["rows"]
    w, h = len(rows[0]), len(rows)
    walk = walk_grid(rows)
    n_walk = sum(1 for r in walk for c in r if c)
    stairs = tuple(d["stairs"])
    props = d.get("props", [])
    doors = d.get("doors", [])
    blocked = set(tuple(p["position"]) for p in props if p.get("blocks", True))
    blocked |= set(tuple(x["position"]) for x in doors if x.get("state") == "locked")
    dist = bfs(walk, w, h, stairs, frozenset(blocked))
    lines = ["%s %s: %dx%d, walkable %.1f%%" % (d["id"], d.get("display_name", ""), w, h, 100.0 * n_walk / (w * h))]
    lens = [dist.get(tuple(l["position"]), -1) for l in d["landings"]]
    lines.append("  landings %d, route lengths to the stairs %s (spread %.2f)" % (
        len(lens), lens, max(lens) / float(max(1, min(lens)))))
    zones = d.get("encounter_zones", [])
    lines.append("  zones %d (optional %d, stairs guard %s), monsters %d" % (
        len(zones), sum(1 for z in zones if z.get("optional")),
        next((z["id"] for z in zones if z.get("guards_stairs")), "-"),
        sum(len(z["monster_ids"]) for z in zones)))
    lines.append("  doors %d (open %d, closed %d, locked %d), props %d (%s), chests %d" % (
        len(doors), sum(1 for x in doors if x["state"] == "open"), sum(1 for x in doors if x["state"] == "closed"),
        sum(1 for x in doors if x["state"] == "locked"), len(props),
        ", ".join("%s %d" % (k, sum(1 for p in props if p["kind"] == k)) for k in PROP_KINDS), len(d.get("chests", []))))
    kd = key_doors(d)
    if kd:
        dist_parts = []
        for door, holders in kd:
            where = "-"
            if len(holders) == 1:
                pr = holders[0]
                where = "%s %s" % (pr["kind"], pr["id"])
            dist_parts.append("%s->%s (%s)" % (door["id"], door["key_item"], where))
        lines.append("  key doors %d: %s" % (len(kd), ", ".join(dist_parts)))
    if monsters:
        for z in zones:
            xp = sum(int(monsters.get(m, {}).get("xp", 0)) for m in z["monster_ids"])
            lines.append("  %-4s %-20s %-6s xp %4d  %s" % (z["id"], z.get("name", ""), z.get("kind", "pack"), xp,
                                                        "+".join(z["monster_ids"])))
    return "\n".join(lines)


# ---------------------------------------------------------------------------

def params_for(args):
    if args.preset not in PRESETS:
        raise SystemExit("unknown preset %r (see --list)" % args.preset)
    p = json.loads(json.dumps(PRESETS[args.preset]))
    p.setdefault("key_doors", KEY_DOORS_DEFAULT)
    for key, attr in (("seed", "seed"), ("width", "width"), ("height", "height"), ("landings", "landings"),
                      ("rings", "rings"), ("room_len", "room_len"), ("props", "props"), ("doors", "doors"),
                      ("locked", "locked"), ("key_doors", "key_doors")):
        v = getattr(args, attr)
        if v is not None:
            p[key] = v
    return p


def generated_by(args, p):
    parts = ["tools/gen_floor.py", "--preset", args.preset]
    for key, attr in (("width", "width"), ("height", "height"), ("landings", "landings"), ("rings", "rings"),
                      ("room_len", "room_len"), ("props", "props"), ("doors", "doors"), ("locked", "locked")):
        v = getattr(args, attr)
        if v is not None:
            parts += ["--" + attr.replace("_", "-"), str(v)]
    parts += ["--key-doors", str(p["key_doors"])]
    parts += ["--seed", str(p["seed"])]
    return " ".join(parts)


def generate(args):
    p = params_for(args)
    b = Builder(p, p["seed"])
    d = b.floor_dict(generated_by(args, p))
    return d


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--preset")
    ap.add_argument("--all", action="store_true")
    ap.add_argument("--list", action="store_true")
    ap.add_argument("--check", nargs="*")
    ap.add_argument("--stats", action="store_true")
    ap.add_argument("--stdout", action="store_true")
    ap.add_argument("--out")
    ap.add_argument("--seed", type=int)
    ap.add_argument("--width", type=int)
    ap.add_argument("--height", type=int)
    ap.add_argument("--landings", type=int)
    ap.add_argument("--rings", type=int)
    ap.add_argument("--room-len", dest="room_len", type=int)
    ap.add_argument("--props", type=float)
    ap.add_argument("--doors", type=float)
    ap.add_argument("--locked", type=float)
    ap.add_argument("--key-doors", dest="key_doors", type=float)
    args = ap.parse_args(argv)
    monsters = load_ids("monsters")
    loot = load_ids("loot")
    items = load_ids("items")
    if args.list:
        for name, p in sorted(PRESETS.items()):
            print("%s  %dx%d  landings %d  rings %d  seed %d  %s" % (name, p["width"], p["height"], p["landings"],
                                                                    p["rings"], p["seed"], p["display_name"]))
        return 0
    if args.check is not None:
        bad = 0
        for path in args.check:
            with open(path, encoding="utf-8") as f:
                d = json.load(f)
            probs = check_floor(d, loot or None, monsters or None, items or None)
            if probs:
                bad += 1
                print("%s: %d problem(s)" % (path, len(probs)))
                for pr in probs:
                    print("  - " + pr)
            else:
                print("%s: ok" % path)
            if args.stats:
                print(stats(d, monsters))
        return 1 if bad else 0
    presets = sorted(PRESETS) if args.all else [args.preset] if args.preset else []
    if not presets:
        ap.print_help()
        return 2
    status = 0
    for name in presets:
        args.preset = name
        d = generate(args)
        probs = check_floor(d, loot or None, monsters or None, items or None)
        text = dump_floor(d)
        if args.stdout:
            sys.stdout.write(text)
        else:
            out = args.out if (args.out and not args.all) else os.path.join(ROOT, "floors", "%s.json" % d["id"])
            with open(out, "w", encoding="utf-8") as f:
                f.write(text)
            print("wrote %s" % os.path.relpath(out, ROOT))
        if args.stats:
            print(stats(d, monsters), file=sys.stderr if args.stdout else sys.stdout)
        if probs:
            status = 1
            for pr in probs:
                print("  problem: " + pr, file=sys.stderr)
    return status


if __name__ == "__main__":
    sys.exit(main())
