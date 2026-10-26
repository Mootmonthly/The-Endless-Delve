#!/usr/bin/env python3
"""Import SRD 5.1 content from the public 5e SRD API into data/.

Usage (stdlib only; run from anywhere):

    python3 -I tools/import_srd.py              # fetch what is not cached, convert, write data/
    python3 -I tools/import_srd.py --offline    # use tools/srd_cache/ only (no network)
    python3 -I tools/import_srd.py --check      # convert twice into memory, compare with each
                                                # other and with data/ (exit 1 on any difference)
    python3 -I tools/import_srd.py --sync-mechanics   # only refresh "mechanic" in data/features,
                                                      # data/invocations, data/metamagic,
                                                      # data/fighting_styles from features.gd

Source: https://www.dnd5eapi.co/api/2014/ (the SRD 5.1 dataset, CC-BY-4.0; attribution in
docs/licensing.md). Raw API JSON is cached under tools/srd_cache/ (gitignored), so re-runs are
offline and deterministic. HTTPS goes through HTTPS_PROXY when set, verified against the CA
bundle in SSL_CERT_FILE or /root/.ccr/ca-bundle.crt when present.

What it writes (one JSON file per record, tabs, keys in a fixed order):
  data/classes/<id>.json       progression keys (see CLASS_IMPORTED_KEYS) merged into the class
  data/features/<id>.json      every class and subclass feature (+ subfeature options)
  data/invocations/<id>.json   eldritch invocations
  data/metamagic/<id>.json     metamagic options
  data/fighting_styles/<id>.json
  data/spells/<id>.json        every spell on any class list
  data/monsters/<id>.json      every SRD monster that has at least one attack roll
  data/weapons/<id>.json, data/items/<id>.json   SRD equipment and magic items

Hand-written files carry "hand_edited": true. The importer never changes a key that already
exists in such a file; it only adds imported keys the file lacks. Class files are the one
exception: the progression keys in CLASS_IMPORTED_KEYS are always regenerated (they are
importer-owned); everything else in a hand-edited class file (kits, prepared spells, text)
is kept.

"mechanic" is "implemented" only for ids listed in the IMPLEMENTED* constants of
src/core/rules/features.gd (read as text); everything else is "unsupported".
"""

from __future__ import annotations

import argparse
import concurrent.futures
import json
import os
import re
import ssl
import sys
import urllib.request

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DATA = os.path.join(ROOT, "data")
CACHE = os.path.join(ROOT, "tools", "srd_cache")
FEATURES_GD = os.path.join(ROOT, "src", "core", "rules", "features.gd")
API_HOST = "https://www.dnd5eapi.co"
API = "/api/2014/"
SOURCE = "SRD 5.1"
CA_BUNDLES = ["/root/.ccr/ca-bundle.crt"]

CLASS_ORDER = ["barbarian", "bard", "cleric", "druid", "fighter", "monk",
               "paladin", "ranger", "rogue", "sorcerer", "warlock", "wizard"]
KNOWN_CASTERS = ["bard", "ranger", "sorcerer", "warlock"]
PREPARED_CASTERS = ["cleric", "druid", "paladin", "wizard"]

# Progression keys the importer owns in data/classes/*.json (rewritten every run).
CLASS_IMPORTED_KEYS = [
    "features", "features_by_level", "asi_levels", "subclass", "spell_slots", "cantrips_known",
    "spells_known", "prepares", "spell_list", "fighting_styles", "expertise_levels",
    "invocations_known", "metamagic_known", "sorcery_slot_costs", "tables", "srd_source",
]

# API class feature placeholders that only point at the subclass ("Primal Path feature").
SUBCLASS_PLACEHOLDER = re.compile(
    r"^(primal-path|bard-college|divine-domain|druid-circle|martial-archetype|monastic-tradition|"
    r"sacred-oath|ranger-archetype|roguish-archetype|sorcerous-origin|otherworldly-patron|"
    r"arcane-tradition)-improvement-\d+$")
# Features folded into another one (their text is appended to the target's description).
FOLDED_FEATURES = {
    "flexible-casting-creating-spell-slots": "font_of_magic",
    "flexible-casting-converting-spell-slot": "font_of_magic",
}
# Features whose spell list lives in the subclass (moved out of the class progression).
SUBCLASS_SPELL_FEATURES = {"domain_spells": "life", "oath_spells": "devotion"}
SPECIAL_FEATURE_IDS = {
    "barbarian-unarmored-defense": "unarmored_defense_con",
    "monk-unarmored-defense": "unarmored_defense_wis",
    "channel-divinity-turn-undead": "turn_undead",
    "channel-divinity-preserve-life": "preserve_life",
    "channel-divinity-sacred-weapon": "sacred_weapon",
    "channel-divinity-turn-the-unholy": "turn_the_unholy",
    "circle-of-the-land": "circle_spells",
}
# Class-prefixed API indexes that name a feature several classes share
# (barbarian-extra-attack, rogue-evasion, druid-lands-stride): the prefix is dropped.
SHARED_STEMS = ("ability-score-improvement", "extra-attack", "expertise", "fighting-style", "evasion",
                "timeless-body", "lands-stride")
# Hunter options: drop the parent prefix (hunters-prey-colossus-slayer -> colossus_slayer).
OPTION_PREFIX_PARENTS = ["hunters-prey", "defensive-tactics", "multiattack", "superior-hunters-defense"]
# Subfeature-option parents handled as their own content folders.
FIGHTING_STYLE_PARENTS = {"fighter-fighting-style", "paladin-fighting-style", "ranger-fighting-style",
                          "additional-fighting-style"}
METAMAGIC_PARENTS = {"metamagic-1", "metamagic-2", "metamagic-3"}

# Synthetic features the SRD text names but the API does not list as a feature record.
SYNTHETIC_FEATURES = {
    "expanded_spell_list": {
        "display_name": "Expanded Spell List", "class": "warlock", "subclass": "fiend", "level": 1,
        "description": "The Fiend lets you choose from an expanded list of spells when you learn a "
                       "warlock spell. The following spells are added to the warlock spell list for "
                       "you: 1st level burning hands, command; 2nd level blindness/deafness, scorching "
                       "ray; 3rd level fireball, stinking cloud; 4th level fire shield, wall of fire; "
                       "5th level flame strike, hallow.",
    },
}
# SRD 5.1 metamagic missing from the API dataset.
SYNTHETIC_METAMAGIC = {
    "twinned_spell": {
        "display_name": "Twinned Spell",
        "description": "When you cast a spell that targets only one creature and doesn't have a range of "
                       "self, you can spend a number of sorcery points equal to the spell's level to target "
                       "a second creature in range with the same spell (1 sorcery point if the spell is a "
                       "cantrip). To be eligible, a spell must be incapable of targeting more than one "
                       "creature at the spell's current level. For example, magic missile and scorching ray "
                       "aren't eligible, but ray of frost is.",
    },
}
CIRCLE_SPELLS_TEXT = (
    "Your mystical connection to the land infuses you with the ability to cast certain spells. At "
    "3rd, 5th, 7th, and 9th level you gain access to circle spells connected to the land where you "
    "became a druid. Choose that land (arctic, coast, desert, forest, grassland, mountain, or swamp) "
    "and consult the associated list of spells. Once you gain access to a circle spell, you always "
    "have it prepared, and it doesn't count against the number of spells you can prepare each day. "
    "If you gain access to a spell that doesn't appear on the druid spell list, the spell is "
    "nonetheless a druid spell for you.")

# Class table renames: API class_specific key -> our table name.
TABLE_RENAMES = {
    "rage_count": "rage_uses", "rage_damage_bonus": "rage_damage", "sneak_attack": "sneak_attack_dice",
    "martial_arts": "martial_arts_die", "channel_divinity_charges": "channel_divinity_uses",
    "aura_range": "aura_radius", "favored_terrain": "favored_terrains",
}
UNLIMITED = 99  # rage_uses at 20th level ("Unlimited" in the SRD table)
# Where the API's class_specific numbers disagree with the SRD 5.1 class tables, the SRD wins
# (values from the class tables; level -> value, carried forward to 20).
SRD_TABLE_FIXES = {
    ("druid", "wild_shape_max_cr"): {1: 0, 2: 0.25, 4: 0.5, 8: 1},
    ("sorcerer", "metamagic_known"): {1: 0, 3: 2, 10: 3, 17: 4},
    ("warlock", "invocations_known"): {1: 0, 2: 2, 5: 3, 7: 4, 9: 5, 12: 6, 15: 7, 18: 8},
}

SPELL_CASTING_TIMES = {
    "1 action": "action", "1 bonus action": "bonus_action", "1 reaction": "reaction",
    "1 minute": "1_minute", "10 minutes": "10_minutes", "1 hour": "1_hour", "8 hours": "8_hours",
    "12 hours": "12_hours", "24 hours": "24_hours",
}
AREA_SHAPES = ["sphere", "cube", "cone", "line", "cylinder"]
# Spells whose API damage comes from a lingering zone, wall or summoned thing rather than from
# the casting itself: mapping them to a one-shot attack or save would be wrong, so they stay
# "unsupported" (reason "lingering effect") until the engine models persistent effects.
LINGERING_SPELLS = {
    "arcane_sword", "black_tentacles", "blade_barrier", "cloudkill", "control_water", "dream",
    "faithful_hound", "fire_storm", "guardian_of_faith", "mass_heal", "moonbeam", "phantasmal_killer",
    "storm_of_vengeance", "wall_of_fire", "wall_of_ice", "wall_of_thorns", "wind_wall",
}
# Spells whose API "area_of_effect" describes objects or a side effect, not the creatures hit.
AREA_IGNORED_SPELLS = {"disintegrate"}

# Equipment ids that already exist under another name in data/.
EQUIPMENT_ID_ALIASES = {
    "crossbow-light": "light_crossbow", "crossbow-hand": "hand_crossbow", "crossbow-heavy": "heavy_crossbow",
    "arrow": "arrows", "crossbow-bolt": "bolts", "sling-bullet": "sling_bullets",
    "blowgun-needle": "blowgun_needles", "rations-1-day": "rations",
}
AMMO_FOR_WEAPON = {
    "shortbow": "arrows", "longbow": "arrows", "light_crossbow": "bolts", "hand_crossbow": "bolts",
    "heavy_crossbow": "bolts", "sling": "sling_bullets", "blowgun": "blowgun_needles",
}
COIN_GP = {"cp": 0.01, "sp": 0.1, "ep": 0.5, "gp": 1.0, "pp": 10.0}
# SRD 5.1 "Magic Item Rarity" value table (lower bound of each band, in gp).
RARITY_VALUE_GP = {"common": 50, "uncommon": 101, "rare": 501, "very rare": 5001, "legendary": 50001,
                   "artifact": 0}
HEALING_POTIONS = {
    "potion-of-healing-common": ("potion_of_healing", "2d4+2"),
    "potion-of-healing-greater": ("potion_of_greater_healing", "4d4+4"),
    "potion-of-healing-superior": ("potion_of_superior_healing", "8d4+8"),
    "potion-of-healing-supreme": ("potion_of_supreme_healing", "10d4+20"),
}
PLUS_N = re.compile(r"^(weapon|armor|ammunition)-([123])$")

# Monster helpers.
LOOT_BANDS = [(0.25, "monster_small"), (2.0, "monster_medium"), (1e9, "boss")]
ICON_BY_TYPE = {
    "beast": "giant_rat", "humanoid": "goblin", "undead": "skeleton", "giant": "ogre",
    "monstrosity": "giant_spider", "aberration": "ghoul", "dragon": "kobold", "fiend": "bugbear",
    "celestial": "hobgoblin", "construct": "zombie", "elemental": "ogre", "fey": "goblin",
    "ooze": "zombie", "plant": "giant_centipede",
}
SKILL_KEYS = {
    "acrobatics": "ACROBATICS", "animal-handling": "ANIMAL_HANDLING", "arcana": "ARCANA",
    "athletics": "ATHLETICS", "deception": "DECEPTION", "history": "HISTORY", "insight": "INSIGHT",
    "intimidation": "INTIMIDATION", "investigation": "INVESTIGATION", "medicine": "MEDICINE",
    "nature": "NATURE", "perception": "PERCEPTION", "performance": "PERFORMANCE",
    "persuasion": "PERSUASION", "religion": "RELIGION", "sleight-of-hand": "SLEIGHT_OF_HAND",
    "stealth": "STEALTH", "survival": "SURVIVAL",
}
# SRD "Experience Points by Challenge Rating"; the API's xp disagrees for a few monsters
# (deep gnome, dretch, brass dragon wyrmling, riding horse), so xp is derived from CR.
CR_XP = {0: 10, 0.125: 25, 0.25: 50, 0.5: 100, 1: 200, 2: 450, 3: 700, 4: 1100, 5: 1800, 6: 2300,
         7: 2900, 8: 3900, 9: 5000, 10: 5900, 11: 7200, 12: 8400, 13: 10000, 14: 11500, 15: 13000,
         16: 15000, 17: 18000, 18: 20000, 19: 22000, 20: 25000, 21: 33000, 22: 41000, 23: 50000,
         24: 62000, 25: 75000, 26: 90000, 27: 105000, 28: 120000, 29: 135000, 30: 155000}
ABILITIES = ["STR", "DEX", "CON", "INT", "WIS", "CHA"]
ABILITY_FIELDS = ["strength", "dexterity", "constitution", "intelligence", "wisdom", "charisma"]

# Text the project must not ship outside docs/licensing.md (see that file). Matched with word
# boundaries; a match in imported text is replaced by REDACTIONS or reported by --check.
NON_SRD_TERMS = [
    r"Dungeons\s*(?:&|and)\s*Dragons", r"D&D", r"Wizards of the Coast", r"Player'?s Handbook",
    r"Dungeon Master'?s Guide", r"Monster Manual", r"Forgotten Realms", r"Greyhawk", r"Eberron",
    r"Ravenloft", r"Baldur'?s Gate", r"Waterdeep", r"Faer[uû]n", r"beholders?", r"mind flayers?",
    r"illithids?", r"displacer beasts?", r"umber hulks?", r"yuan-ti", r"githyanki", r"githzerai",
    r"carrion crawlers?", r"slaadi?", r"Totem Warrior", r"Mordenkainen", r"Bigby", r"Otiluke",
    r"Leomund", r"Tenser", r"Tasha", r"Melf", r"Drawmij", r"Nystul", r"Evard", r"Rary",
    r"Tiamat", r"Bahamut", r"Moradin", r"Dispater", r"Asmodeus", r"Orcus", r"Demogorgon", r"Baphomet",
    r"Belial", r"Mephistopheles", r"Fraz'Urb-luu", r"yugoloths?", r"Lolth", r"Vecna", r"Gruumsh",
    r"Tempest domain", r"Trickery domain", r"War domain",
]
REDACTIONS = [
    # The SRD itself only details the Path of the Berserker.
    ("Choose the Path of the Berserker or the Path of the Totem Warrior, both detailed at the end "
     "of the class description.", "Choose the Path of the Berserker, detailed at the end of the "
     "class description."),
    ("Choose one domain related to your deity, such as Knowledge, Life, Light, Nature, Tempest, "
     "Trickery, or War. Only the Life domain is detailed in the Open Game Licensed SRD. Additional "
     "Domains are described in the official rulebooks or products from other publishers.",
     "Choose one domain related to your deity. The SRD details the Life domain."),
    # Named deities and setting characters (see docs/licensing.md) become generic phrases.
    ("Fiends powerful enough to forge a pact include demon lords such as Demogorgon, Orcus, "
     "Fraz'Urb-luu, and Baphomet; archdevils such as Asmodeus, Dispater, Mephistopheles, and Belial; "
     "pit fiends and balors that are especially mighty; and ultroloths and other lords of the yugoloths.",
     "Fiends powerful enough to forge a pact include demon lords, archdevils, pit fiends and balors "
     "that are especially mighty, and other lords of the lower planes."),
    ("lover and beloved of Moradin,", "lover and beloved of the god of the forge,"),
    ("or the palace of Dispater on the second level of the Nine Hells",
     "or an archdevil's palace on the second level of the Nine Hells"),
    ("to advance the worship of Tiamat,", "to advance the worship of a dragon deity,"),
    ("Dragon deities such as Tiamat are unaffected", "Dragon deities are unaffected"),
    # Non-SRD creature names inside SRD text are swapped for SRD ones.
    ("| Ace of diamonds | Beholder |", "| Ace of diamonds | Aboleth |"),
    ("a small amount of umber hulk blood", "a small amount of rare monster blood"),
]

# ---------------------------------------------------------------------------- fetching


class Fetcher:
    def __init__(self, offline: bool) -> None:
        self.offline = offline
        self.fetched = 0
        cafile = os.environ.get("SSL_CERT_FILE") or next((p for p in CA_BUNDLES if os.path.exists(p)), None)
        self.ctx = ssl.create_default_context(cafile=cafile) if cafile else ssl.create_default_context()

    @staticmethod
    def cache_path(url: str) -> str:
        rel = url.replace(API, "").strip("/")
        return os.path.join(CACHE, (rel.replace("/", "__") or "root") + ".json")

    def get(self, url: str):
        if not url.startswith("/"):
            url = API + url
        path = self.cache_path(url)
        if os.path.exists(path):
            with open(path, encoding="utf-8") as f:
                return json.load(f)
        if self.offline:
            raise SystemExit("import_srd: %s is not cached and --offline was given" % url)
        last = None
        for _attempt in range(4):
            try:
                with urllib.request.urlopen(API_HOST + url, context=self.ctx, timeout=60) as resp:
                    data = json.load(resp)
                break
            except Exception as exc:  # noqa: BLE001 - retried, then reported
                last = exc
        else:
            raise SystemExit("import_srd: cannot fetch %s: %s" % (url, last))
        data = strip_volatile(data)
        os.makedirs(CACHE, exist_ok=True)
        tmp = path + ".tmp"
        with open(tmp, "w", encoding="utf-8") as f:
            json.dump(data, f, sort_keys=True, indent=1, ensure_ascii=False)
        os.replace(tmp, path)
        self.fetched += 1
        return data

    def prefetch(self, urls: list[str]) -> None:
        todo = [u for u in urls if not os.path.exists(self.cache_path(u))]
        if not todo:
            return
        with concurrent.futures.ThreadPoolExecutor(8) as pool:
            list(pool.map(self.get, todo))

    def listing(self, resource: str) -> list[dict]:
        return sorted(self.get(API + resource)["results"], key=lambda r: r["index"])


def strip_volatile(v):
    if isinstance(v, dict):
        return {k: strip_volatile(x) for k, x in v.items() if k != "updated_at"}
    if isinstance(v, list):
        return [strip_volatile(x) for x in v]
    return v


# ---------------------------------------------------------------------------- helpers


def snake(index: str) -> str:
    s = re.sub(r"[^a-z0-9]+", "_", index.lower()).strip("_")
    return s


def clean_text(text: str) -> str:
    for old, new in REDACTIONS:
        text = text.replace(old, new)
    return text


def join_desc(parts) -> str:
    if isinstance(parts, str):
        return clean_text(parts.strip())
    return clean_text("\n".join(p.strip() for p in parts if p is not None and p.strip()))


def dice(text: str) -> str:
    return re.sub(r"\s+", "", str(text))


DICE_RE = re.compile(r"^(\d{0,4})d(\d{1,5})([+-]\d{1,6})?$|^[+-]?\d{1,6}$")


def alt(text: str, pick: int) -> str:
    """'4d6 OR 5d6' (flame strike upcasting: one of the two damage types grows) -> one option:
    the first damage entry takes the larger (last) option, the others the base (first) one."""
    options = [dice(o) for o in re.split(r"\s+OR\s+", str(text))]
    return options[pick]


def valid_dice(text: str) -> bool:
    return bool(DICE_RE.match(dice(text)))


def parse_dice(text: str):
    m = re.match(r"^(\d{0,4})d(\d{1,5})([+-]\d{1,6})?$", dice(text))
    if not m:
        return None
    return (int(m.group(1) or 1), int(m.group(2)), int(m.group(3) or 0))


def per_level_increment(table: dict[str, str]):
    """'1d6' when consecutive table entries grow by the same dice, else None."""
    keys = sorted(table, key=int)
    if len(keys) < 2:
        return None
    steps = set()
    for a, b in zip(keys, keys[1:]):
        da, db = parse_dice(table[a]), parse_dice(table[b])
        if da is None or db is None or da[1] != db[1] or int(b) - int(a) != 1:
            return None
        if db[2] != da[2]:
            return None  # the modifier grows too (magic missile "3d4+3"): not a plain dice step
        steps.add(db[0] - da[0])
    if len(steps) != 1:
        return None
    step = steps.pop()
    if step <= 0:
        return None
    return "%dd%d" % (step, parse_dice(table[keys[0]])[1])


def feet(text) -> int:
    m = re.search(r"(\d+)\s*(?:ft|feet|foot)", str(text))
    return int(m.group(1)) if m else 0


def by_level(values: dict[int, object]) -> dict[str, object]:
    return {str(k): values[k] for k in sorted(values)}


def load_json(path: str):
    with open(path, encoding="utf-8") as f:
        return json.load(f)


# ---------------------------------------------------------------------------- JSON output

INLINE_WIDTH = 100


def _scalar(v) -> str:
    return json.dumps(v, ensure_ascii=False)


def _inline(v) -> str:
    if isinstance(v, dict):
        if not v:
            return "{}"
        return "{ " + ", ".join("%s: %s" % (_scalar(k), _inline(x)) for k, x in v.items()) + " }"
    if isinstance(v, list):
        return "[" + ", ".join(_inline(x) for x in v) + "]"
    return _scalar(v)


def _format(v, indent: int, key_len: int) -> str:
    one = _inline(v)
    if not isinstance(v, (dict, list)) or len(one) + indent * 4 + key_len <= INLINE_WIDTH or not v:
        return one
    pad = "\t" * (indent + 1)
    if isinstance(v, dict):
        items = ["%s%s: %s" % (pad, _scalar(k), _format(x, indent + 1, len(_scalar(k)) + 2)) for k, x in v.items()]
        return "{\n" + ",\n".join(items) + "\n" + "\t" * indent + "}"
    if all(not isinstance(x, (dict, list)) for x in v):
        # long scalar arrays: one entry per line
        return "[\n" + ",\n".join(pad + _scalar(x) for x in v) + "\n" + "\t" * indent + "]"
    return "[\n" + ",\n".join(pad + _format(x, indent + 1, 0) for x in v) + "\n" + "\t" * indent + "]"


def dumps(record: dict) -> str:
    pad = "\t"
    lines = ["%s%s: %s" % (pad, _scalar(k), _format(v, 1, len(_scalar(k)) + 2)) for k, v in record.items()]
    return "{\n" + ",\n".join(lines) + "\n}\n"


# ---------------------------------------------------------------------------- output set


class Output:
    """Collects files to write: relative path -> text."""

    def __init__(self) -> None:
        self.files: dict[str, str] = {}
        self.notes: list[str] = []

    def put(self, rel: str, record: dict) -> None:
        if rel in self.files:
            raise SystemExit("import_srd: %s produced twice" % rel)
        self.files[rel] = dumps(record)

    def put_merged(self, rel: str, imported: dict, owned: list[str] | None = None) -> None:
        """Writes `imported`, or merges it into an existing hand_edited file: keys the file has
        are kept (except `owned` ones), missing imported keys are appended."""
        path = os.path.join(DATA, rel)
        existing = load_json(path) if os.path.exists(path) else None
        if existing is None or not existing.get("hand_edited", False):
            self.put(rel, imported)
            return
        merged = dict(existing)
        for k, v in imported.items():
            if k in ("hand_edited",):
                continue
            if owned and k in owned:
                merged[k] = v
            elif k not in merged:
                merged[k] = v
        if merged == existing:
            with open(path, encoding="utf-8") as f:
                self.files[rel] = f.read()
        else:
            self.put(rel, merged)


# ---------------------------------------------------------------------------- mechanics


def implemented_ids() -> set[str]:
    """String literals inside every `const IMPLEMENTED...` array of features.gd."""
    if not os.path.exists(FEATURES_GD):
        return set()
    with open(FEATURES_GD, encoding="utf-8") as f:
        text = f.read()
    out: set[str] = set()
    for m in re.finditer(r"const\s+IMPLEMENTED\w*\s*(?::[^=]*)?=\s*\[(.*?)\]", text, re.S):
        body = re.sub(r"#[^\n]*", "", m.group(1))
        out.update(re.findall(r'"([^"]+)"', body))
    return out


def mechanic_for(fid: str, implemented: set[str], aliases: list[str] | None = None) -> str:
    names = [fid] + (aliases or [])
    return "implemented" if any(n in implemented for n in names) else "unsupported"


# ---------------------------------------------------------------------------- features


def feature_id(index: str, cls: str) -> str | None:
    """Our feature id for an API feature index; None for subclass placeholders."""
    if SUBCLASS_PLACEHOLDER.match(index):
        return None
    if index in FOLDED_FEATURES:
        return FOLDED_FEATURES[index]
    if index in SPECIAL_FEATURE_IDS:
        return SPECIAL_FEATURE_IDS[index]
    i = index
    if i.startswith(cls + "-") and i[len(cls) + 1:].startswith(SHARED_STEMS):
        i = i[len(cls) + 1:]
    if i.startswith("spellcasting-"):
        return "spellcasting"
    for pattern, repl in [
        (r"^(destroy-undead|wild-shape|mystic-arcanum)-.*$", r"\1"),
        (r"^(bardic-inspiration|song-of-rest)-d\d+$", r"\1"),
        (r"^divine-intervention-improvement$", "divine-intervention"),
        (r"^(.*?)-\d+-[a-z-]+$", r"\1"),
        (r"^(.*?)-\d+$", r"\1"),
    ]:
        if re.match(pattern, i):
            i = re.sub(pattern, repl, i)
            break
    return snake(i)


def clean_feature_name(name: str) -> str:
    if name.startswith("Spellcasting:"):
        return "Spellcasting"
    name = re.sub(r"\s*\([^)]*\)$", "", name)
    name = re.sub(r"\s+\d+$", "", name)
    return name.strip()


def option_id(index: str, parent: str, taken: set[str]) -> str:
    for p in OPTION_PREFIX_PARENTS:
        if parent == p and index.startswith(p + "-"):
            short = snake(index[len(p) + 1:])
            if short not in taken:
                return short
    m = re.match(r"^dragon-ancestor-([a-z]+)---", index)
    if m:
        return "dragon_ancestor_" + m.group(1)
    return snake(index)


class FeatureSet:
    def __init__(self) -> None:
        self.records: dict[str, dict] = {}

    def add(self, fid: str, api: dict, cls: str, level: int, subclass: str | None) -> None:
        name = clean_feature_name(api["name"])
        desc = join_desc(api.get("desc", []))
        rec = self.records.get(fid)
        if rec is None:
            rec = {"id": fid, "display_name": name, "classes": [], "subclass_of": {}, "levels": {},
                   "descriptions": {}, "variants": {}, "prerequisites": api.get("prerequisites") or []}
            self.records[fid] = rec
        if cls not in rec["classes"]:
            rec["classes"].append(cls)
        rec["levels"].setdefault(cls, [])
        if level not in rec["levels"][cls]:
            rec["levels"][cls].append(level)
        if cls not in rec["descriptions"]:
            rec["descriptions"][cls] = desc
        elif desc and desc != rec["descriptions"][cls] and api["name"] != rec["display_name"]:
            rec["variants"].setdefault(str(level), {"name": api["name"], "description": desc})
        if subclass:
            rec["subclass_of"][cls] = subclass


def build_features(f: Fetcher, out: Output, implemented: set[str]) -> dict:
    """Returns {"class_fbl": {cls: {lvl: [ids]}}, "subclasses": {...}, "options": {...}}."""
    features = FeatureSet()
    api_feature = {r["index"]: f.get(r["url"]) for r in f.listing("features")}
    class_fbl: dict[str, dict[int, list[str]]] = {}
    folded: dict[str, list[str]] = {}
    subclass_spell_feature_levels: dict[str, tuple[str, list[int], dict]] = {}

    for cls in CLASS_ORDER:
        levels = f.get(API + "classes/%s/levels" % cls)
        fbl: dict[int, list[str]] = {n: [] for n in range(1, 21)}
        for lv in levels:
            if "subclass" in lv:
                continue
            for ref in lv["features"]:
                idx = ref["index"]
                fid = feature_id(idx, cls)
                if fid is None:
                    continue
                if idx in FOLDED_FEATURES:
                    folded.setdefault(fid, []).append(join_desc(api_feature[idx]["desc"]))
                    continue
                if fid in SUBCLASS_SPELL_FEATURES:
                    sub = SUBCLASS_SPELL_FEATURES[fid]
                    entry = subclass_spell_feature_levels.setdefault(fid, (sub, [], api_feature[idx]))
                    entry[1].append(lv["level"])
                    features.add(fid, api_feature[idx], cls, lv["level"], sub)
                    continue
                features.add(fid, api_feature[idx], cls, lv["level"], None)
                if fid not in fbl[lv["level"]]:
                    fbl[lv["level"]].append(fid)
        class_fbl[cls] = fbl

    # Subclasses.
    subclasses: dict[str, dict] = {}
    option_parents: dict[str, list[str]] = {}
    for ref in f.listing("subclasses"):
        sub = f.get(ref["url"])
        cls = sub["class"]["index"]
        sid = snake(sub["index"])
        sfbl: dict[int, list[str]] = {}
        for lv in sorted(f.get(ref["url"] + "/levels"), key=lambda x: x["level"]):
            for fref in lv["features"]:
                fid = feature_id(fref["index"], cls)
                features.add(fid, api_feature[fref["index"]], cls, lv["level"], sid)
                sfbl.setdefault(lv["level"], []).append(fid)
        # Spell features that the API files under the class progression.
        for fid, (owner, lvls, api) in subclass_spell_feature_levels.items():
            if owner == sid:
                sfbl.setdefault(min(lvls), []).insert(0, fid)
        if sid == "land":
            api = api_feature["circle-of-the-land"]
            for lvl in (3, 5, 7, 9):
                features.add("circle_spells", dict(api, name="Circle Spells", desc=[CIRCLE_SPELLS_TEXT]), cls, lvl, sid)
            sfbl.setdefault(3, []).append("circle_spells")
        if sid == "fiend":
            sfbl.setdefault(1, []).insert(0, "expanded_spell_list")
        first = min(sfbl) if sfbl else 1
        spells_by_level: dict[str, list[str]] = {}
        spells_by_terrain: dict[str, dict[str, list[str]]] = {}
        for entry in sub.get("spells", []):
            lvl = None
            terrain = None
            for pre in entry["prerequisites"]:
                if pre["type"] == "level":
                    lvl = int(pre["index"].rsplit("-", 1)[1])
                elif pre["type"] == "feature":
                    terrain = pre["index"].replace("circle-of-the-land-", "")
            sp = snake(entry["spell"]["index"])
            if terrain:
                bucket = spells_by_terrain.setdefault(terrain, {}).setdefault(str(lvl), [])
            else:
                bucket = spells_by_level.setdefault(str(lvl), [])
            if sp not in bucket:
                bucket.append(sp)
        record = {
            "id": sid,
            "display_name": sub["name"],
            "flavor": sub["subclass_flavor"],
            "level": first,
            "description": join_desc(sub.get("desc", [])),
            "features_by_level": by_level({k: v for k, v in sfbl.items()}),
        }
        if spells_by_level:
            record["spells_by_level"] = {k: spells_by_level[k] for k in sorted(spells_by_level, key=int)}
            record["spells_mode"] = "expanded_list" if sid == "fiend" else "always_prepared"
        if spells_by_terrain:
            record["spells_by_terrain"] = {
                t: {k: v[k] for k in sorted(v, key=int)} for t, v in sorted(spells_by_terrain.items())}
            record["spells_mode"] = "always_prepared"
        specific = {}
        for lv in f.get(ref["url"] + "/levels"):
            for k, v in (lv.get("subclass_specific") or {}).items():
                specific.setdefault(k, {})[lv["level"]] = v
        if specific:
            record["tables"] = {k: fill_levels(v, first) for k, v in sorted(specific.items())}
        subclasses[cls] = record

    # Subfeature options (hunter choices, pact boons, dragon ancestors, land terrains).
    taken = set(features.records)
    for idx, api in sorted(api_feature.items()):
        parent = (api.get("parent") or {}).get("index")
        if not parent or idx.startswith("eldritch-invocation-") or parent in FIGHTING_STYLE_PARENTS \
                or parent in METAMAGIC_PARENTS:
            continue
        cls = api["class"]["index"]
        parent_id = feature_id(parent, cls)
        oid = option_id(idx, parent, taken)
        taken.add(oid)
        sub = snake(api["subclass"]["index"]) if api.get("subclass") else None
        features.add(oid, api, cls, api["level"], sub)
        features.records[oid]["option_of"] = parent_id
        option_parents.setdefault(parent_id, []).append(oid)
        if oid.startswith("dragon_ancestor_"):
            m = re.search(r"-\s*(\w+) Damage", api["name"])
            if m:
                features.records[oid]["damage_type"] = m.group(1).lower()
            features.records[oid]["display_name"] = api["name"].split(" - ")[0]

    # Write feature files.
    for fid, extra in SYNTHETIC_FEATURES.items():
        features.records[fid] = {
            "id": fid, "display_name": extra["display_name"], "classes": [extra["class"]],
            "subclass_of": {extra["class"]: extra["subclass"]}, "levels": {extra["class"]: [extra["level"]]},
            "descriptions": {extra["class"]: extra["description"]}, "variants": {}, "prerequisites": [],
            "synthetic": True,
        }
    for fid in sorted(features.records):
        rec = features.records[fid]
        classes = rec["classes"]
        primary = classes[0]
        all_levels = sorted({lv for lvls in rec["levels"].values() for lv in lvls})
        descs = rec["descriptions"]
        description = descs[primary]
        if fid in folded:
            description = "\n".join([description] + folded[fid])
        out_rec = {
            "schema_version": 1,
            "id": fid,
            "display_name": rec["display_name"],
            "class": primary,
        }
        if len(classes) > 1:
            out_rec["classes"] = sorted(classes, key=CLASS_ORDER.index)
        subs = rec["subclass_of"]
        if subs and len(classes) == 1:
            out_rec["subclass"] = subs[primary]
        elif subs:
            out_rec["subclass_by_class"] = {c: subs[c] for c in sorted(subs, key=CLASS_ORDER.index)}
        out_rec["level"] = all_levels[0]
        if len(all_levels) > 1:
            out_rec["levels"] = all_levels
        if len(classes) > 1 and len({tuple(sorted(v)) for v in rec["levels"].values()}) > 1:
            out_rec["levels_by_class"] = {c: sorted(rec["levels"][c]) for c in out_rec["classes"]}
        out_rec["description"] = description
        if len(classes) > 1 and len(set(descs.values())) > 1:
            out_rec["description_by_class"] = {c: descs[c] for c in out_rec["classes"]}
        if rec["variants"]:
            out_rec["improvements"] = {k: rec["variants"][k] for k in sorted(rec["variants"], key=int)}
        if rec.get("option_of"):
            out_rec["option_of"] = rec["option_of"]
        if fid in option_parents:
            out_rec["options"] = option_parents[fid]
        if rec.get("damage_type"):
            out_rec["damage_type"] = rec["damage_type"]
        if rec.get("synthetic"):
            out_rec["synthetic"] = True
        out_rec["mechanic"] = mechanic_for(fid, implemented)
        out_rec["source"] = SOURCE
        out.put("features/%s.json" % fid, out_rec)

    # Fighting styles, metamagic, invocations.
    styles: dict[str, dict] = {}
    style_classes: dict[str, list[str]] = {}
    metamagic: dict[str, dict] = {}
    invocations: dict[str, dict] = {}
    for idx, api in sorted(api_feature.items()):
        parent = (api.get("parent") or {}).get("index")
        if parent in FIGHTING_STYLE_PARENTS:
            sid = snake(re.sub(r"^(fighter-|ranger-|paladin-)?fighting-style-", "", idx))
            cls = api["class"]["index"]
            style_classes.setdefault(sid, [])
            if cls not in style_classes[sid]:
                style_classes[sid].append(cls)
            if sid not in styles or cls == "fighter":
                styles[sid] = {"display_name": api["name"].split(": ")[-1].replace("Fighting Style ", ""),
                               "description": join_desc(api["desc"])}
        elif parent in METAMAGIC_PARENTS:
            mid = snake(idx.replace("metamagic-", ""))
            metamagic[mid] = {"display_name": api["name"].split(": ")[-1], "description": join_desc(api["desc"])}
        elif idx.startswith("eldritch-invocation-"):
            iid = snake(idx.replace("eldritch-invocation-", ""))
            pre: dict = {}
            for p in api.get("prerequisites") or []:
                if p["type"] == "level":
                    pre["level"] = p["level"]
                elif p["type"] == "spell":
                    pre["spell"] = snake(p["spell"].rsplit("/", 1)[1])
                elif p["type"] == "feature":
                    pre["pact"] = snake(p["feature"].rsplit("/", 1)[1])
            invocations[iid] = {"display_name": api["name"].split(": ", 1)[-1],
                                "description": join_desc(api["desc"]), "prerequisites": pre}
    for sid in sorted(styles):
        out.put("fighting_styles/%s.json" % sid, {
            "schema_version": 1, "id": sid, "display_name": clean_style_name(styles[sid]["display_name"]),
            "description": styles[sid]["description"],
            "classes": sorted(style_classes[sid], key=CLASS_ORDER.index),
            "mechanic": mechanic_for(sid, implemented, ["fighting_style_" + sid]),
            "source": SOURCE,
        })
    for mid, extra in SYNTHETIC_METAMAGIC.items():
        metamagic.setdefault(mid, extra)
    for mid in sorted(metamagic):
        out.put("metamagic/%s.json" % mid, {
            "schema_version": 1, "id": mid, "display_name": metamagic[mid]["display_name"],
            "description": metamagic[mid]["description"], "cost": metamagic_cost(mid),
            "mechanic": mechanic_for(mid, implemented, [mid.replace("_spell", "")]),
            "source": SOURCE,
        })
    for iid in sorted(invocations):
        rec = {"schema_version": 1, "id": iid, "display_name": invocations[iid]["display_name"],
               "description": invocations[iid]["description"]}
        if invocations[iid]["prerequisites"]:
            rec["prerequisites"] = invocations[iid]["prerequisites"]
        rec["mechanic"] = mechanic_for(iid, implemented)
        rec["source"] = SOURCE
        out.put("invocations/%s.json" % iid, rec)

    styles_by_class: dict[str, list[str]] = {}
    for sid in sorted(styles):
        for cls in style_classes[sid]:
            styles_by_class.setdefault(cls, []).append(sid)
    return {"class_fbl": class_fbl, "subclasses": subclasses, "styles_by_class": styles_by_class,
            "feature_ids": set(features.records)}


def clean_style_name(name: str) -> str:
    return name.replace("Fighting Style: ", "").strip()


def metamagic_cost(mid: str):
    return {"careful_spell": 1, "distant_spell": 1, "empowered_spell": 1, "extended_spell": 1,
            "heightened_spell": 3, "quickened_spell": 2, "subtle_spell": 1,
            "twinned_spell": "spell_level_min_1"}.get(mid, 1)


def fill_levels(values: dict[int, object], start: int = 1, default=0) -> dict[str, object]:
    """Every level 1..20: the value of the highest given level <= it, else default."""
    out: dict[str, object] = {}
    current = default
    for n in range(1, 21):
        if n in values and n >= start:
            current = values[n]
        out[str(n)] = current
    return out


# ---------------------------------------------------------------------------- classes


def slot_row(sc: dict | None) -> list[int]:
    if not sc:
        return []
    row = [int(sc.get("spell_slots_level_%d" % n, 0) or 0) for n in range(1, 10)]
    while row and row[-1] == 0:
        row.pop()
    return row


def build_classes(f: Fetcher, out: Output, feat: dict, spell_ids: set[str], extra_lists: dict[str, list[str]]) -> None:
    for cls in CLASS_ORDER:
        api = f.get(API + "classes/" + cls)
        levels = sorted(f.get(API + "classes/%s/levels" % cls), key=lambda x: x["level"])
        levels = [lv for lv in levels if "subclass" not in lv]
        fbl = feat["class_fbl"][cls]
        imported: dict = {}
        imported["features"] = list(fbl[1])
        imported["features_by_level"] = {str(n): fbl[n] for n in range(1, 21)}
        imported["asi_levels"] = [n for n in range(1, 21) if "ability_score_improvement" in fbl[n]]
        sub = feat["subclasses"][cls]
        imported["subclass"] = sub
        # Spellcasting tables.
        has_slots = any(slot_row(lv.get("spellcasting")) for lv in levels)
        if has_slots:
            imported["spell_slots"] = {str(lv["level"]): slot_row(lv.get("spellcasting")) for lv in levels}
            cantrips = {lv["level"]: lv["spellcasting"]["cantrips_known"] for lv in levels
                        if lv.get("spellcasting") and "cantrips_known" in lv["spellcasting"]}
            if cantrips:
                imported["cantrips_known"] = fill_levels(cantrips)
            known = {lv["level"]: lv["spellcasting"]["spells_known"] for lv in levels
                     if lv.get("spellcasting") and "spells_known" in lv["spellcasting"]}
            if cls in KNOWN_CASTERS and known:
                imported["spells_known"] = fill_levels(known)
            imported["prepares"] = cls in PREPARED_CASTERS
            spells = [snake(r["index"]) for r in f.get(API + "classes/%s/spells" % cls)["results"]]
            spells = sorted(set(s for s in spells if s in spell_ids) | set(extra_lists.get(cls, [])))
            imported["spell_list"] = spells
        styles = feat["styles_by_class"].get(cls)
        if styles and cls in ("fighter", "paladin", "ranger"):
            imported["fighting_styles"] = styles
        expertise = {n: 2 for n in range(1, 21) if "expertise" in fbl[n]}
        if expertise:
            imported["expertise_levels"] = by_level(expertise)
        # Class-specific tables.
        tables: dict[str, dict] = {}
        raw: dict[str, dict[int, object]] = {}
        for lv in levels:
            for k, v in (lv.get("class_specific") or {}).items():
                raw.setdefault(k, {})[lv["level"]] = v
        for k, vals in sorted(raw.items()):
            name = TABLE_RENAMES.get(k, k)
            conv: dict[int, object] = {}
            for lvl, v in vals.items():
                if isinstance(v, dict) and "dice_value" in v:
                    v = v["dice_value"] if name == "martial_arts_die" else v["dice_count"]
                if isinstance(v, bool):
                    v = 1 if v else 0
                if name == "rage_uses" and v == 9999:
                    v = UNLIMITED
                conv[lvl] = v
            if name == "creating_spell_slots":
                last = vals[max(vals)]
                imported["sorcery_slot_costs"] = {str(e["spell_slot_level"]): e["sorcery_point_cost"] for e in last}
                continue
            if (cls, name) in SRD_TABLE_FIXES:
                conv = dict(SRD_TABLE_FIXES[(cls, name)])
            tables[name] = fill_levels(conv)
        if cls in ("barbarian", "monk", "paladin", "ranger"):
            tables["extra_attacks"] = fill_levels({5: 1})
        if cls == "paladin":
            tables["lay_on_hands_pool"] = {str(n): 5 * n for n in range(1, 21)}
            tables["channel_divinity_uses"] = fill_levels({3: 1})
            tables["aura_radius"] = fill_levels({6: 10, 18: 30})
        imported["tables"] = {k: tables[k] for k in sorted(tables)}
        if cls == "warlock" and "invocations_known" in tables:
            imported["invocations_known"] = tables["invocations_known"]
        if cls == "sorcerer" and "metamagic_known" in tables:
            imported["metamagic_known"] = tables["metamagic_known"]
        imported["srd_source"] = SOURCE
        rel = "classes/%s.json" % cls
        path = os.path.join(DATA, rel)
        existing = load_json(path) if os.path.exists(path) else {}
        merged = dict(existing)
        for k in CLASS_IMPORTED_KEYS:
            if k in imported:
                merged[k] = imported[k]
            elif k in merged and k not in ("prepares",):
                del merged[k]
        # Extend the level-1 casters' existing slot table to 20 levels.
        sc = merged.get("spellcasting")
        if isinstance(sc, dict) and "spell_slots" in imported:
            sc = dict(sc)
            sc["slots"] = imported["spell_slots"]
            merged["spellcasting"] = sc
        if not existing:
            raise SystemExit("import_srd: data/%s is missing (class files are hand-seeded)" % rel)
        if merged == existing:
            with open(path, encoding="utf-8") as fh:
                out.files[rel] = fh.read()
        else:
            out.put(rel, merged)


# ---------------------------------------------------------------------------- spells


def range_fields(text: str) -> tuple[object, str | None]:
    t = text.strip()
    low = t.lower()
    if low.startswith("self"):
        return 0, (t if t != "Self" else None)
    if low == "touch":
        return 5, None
    m = re.match(r"^(\d+)\s*feet$", low)
    if m:
        return int(m.group(1)), None
    m = re.match(r"^(\d+)\s*miles?$", low)
    if m:
        return int(m.group(1)) * 5280, t
    return 0, t


def convert_spell(api: dict) -> dict:
    sid = snake(api["index"])
    rng, range_text = range_fields(api["range"])
    damage = api.get("damage") or []
    if isinstance(damage, dict):
        damage = [damage]
    damage = [d for d in damage if isinstance(d, dict)]
    first = damage[0] if damage else {}
    dtype = (first.get("damage_type") or {}).get("index", "")
    by_slot = {k: alt(v, -1) for k, v in sorted((first.get("damage_at_slot_level") or {}).items(), key=lambda x: int(x[0]))}
    by_char = {k: dice(v) for k, v in sorted((first.get("damage_at_character_level") or {}).items(), key=lambda x: int(x[0]))}
    heal = {k: dice(v) for k, v in sorted((api.get("heal_at_slot_level") or {}).items(), key=lambda x: int(x[0]))}
    area = None
    if api.get("area_of_effect"):
        area = {"shape": api["area_of_effect"]["type"], "size_ft": int(api["area_of_effect"]["size"])}
    save = None
    if api.get("dc"):
        success = api["dc"].get("dc_success", "none")
        save = {"ability": api["dc"]["dc_type"]["index"].upper(),
                "on_success": success if success in ("half", "none") else "none"}
        if success not in ("half", "none"):
            save["on_success_text"] = success
    level = int(api["level"])
    casting_time = SPELL_CASTING_TIMES.get(api["casting_time"], snake(api["casting_time"]))
    effect, target = spell_effect(api, sid, level, rng, range_text, dtype, by_slot, by_char, heal, area, save)
    rec: dict = {
        "schema_version": 1,
        "id": sid,
        "display_name": api["name"],
        "level": level,
        "school": api["school"]["index"],
        "casting_time": casting_time,
        "range_ft": rng,
        "target": target,
        "effect": effect,
        "duration": api["duration"].lower(),
        "concentration": bool(api["concentration"]),
        "ritual": bool(api["ritual"]),
        "components": list(api["components"]),
        "classes": sorted(snake(c["index"]) for c in api["classes"]),
        "source": SOURCE,
        "description": join_desc(api["desc"]),
    }
    if casting_time not in ("action", "bonus_action") or api["casting_time"] not in SPELL_CASTING_TIMES:
        rec["casting_time_text"] = api["casting_time"]
    if range_text:
        rec["range_text"] = range_text
    if api.get("material"):
        rec["material"] = clean_text(api["material"])
    if api.get("higher_level"):
        rec["higher_level"] = join_desc(api["higher_level"])
    if api.get("subclasses"):
        rec["subclasses"] = sorted(snake(s["index"]) for s in api["subclasses"])
    if area and sid in AREA_IGNORED_SPELLS:
        rec["object_area"] = area
    elif area:
        rec["area"] = area
    if save:
        rec["saving_throw"] = save
    if by_slot:
        rec["damage_by_slot"] = by_slot
    if by_char:
        rec["damage_by_character_level"] = by_char
    if dtype:
        rec["damage_type"] = dtype
    extra = []
    for d in damage[1:]:
        e = {"damage_type": (d.get("damage_type") or {}).get("index", "")}
        if d.get("damage_at_slot_level"):
            e["damage_by_slot"] = {k: alt(v, 0) for k, v in sorted(d["damage_at_slot_level"].items(), key=lambda x: int(x[0]))}
        if d.get("damage_at_character_level"):
            e["damage_by_character_level"] = {k: dice(v) for k, v in sorted(d["damage_at_character_level"].items(), key=lambda x: int(x[0]))}
        extra.append(e)
    if extra:
        rec["extra_damage"] = extra
    if heal:
        rec["heal_by_slot"] = heal
    return rec


def spell_effect(api, sid, level, rng, range_text, dtype, by_slot, by_char, heal, area, save):
    self_range = api["range"].lower().startswith("self")
    unsupported_target = "self" if self_range else "creature"
    reason = None
    attack = api.get("attack_type")
    if sid in LINGERING_SPELLS:
        return {"type": "unsupported", "reason": "lingering effect"}, unsupported_target
    if sid in AREA_IGNORED_SPELLS:
        area = None
    if sid == "magic_missile":
        return ({"type": "auto_hit", "darts": 3, "damage": "1d4+1", "damage_type": "force",
                 "per_slot_level_above": 1}, "creature")
    base_damage = None
    scaling = None
    per_slot = None
    if by_char:
        base_damage = by_char.get("1")
        scaling = {k: v for k, v in by_char.items() if k != "1"}
    elif by_slot:
        base_damage = by_slot.get(str(level)) or by_slot[sorted(by_slot, key=int)[0]]
        per_slot = per_level_increment(by_slot)
    damage_ok = bool(base_damage) and valid_dice(base_damage) and bool(dtype)
    if damage_ok and scaling:
        damage_ok = all(valid_dice(v) for v in scaling.values())
    if len(api.get("damage") or []) > 1:
        damage_ok = False
        reason = "more than one damage type"
    if api.get("dc") and api["dc"].get("dc_success") not in ("half", "none"):
        damage_ok = False
        reason = "special saving throw outcome"
    if area and area["shape"] not in AREA_SHAPES:
        damage_ok = False
    if attack and damage_ok and not (self_range and not area):
        eff = {"type": "area_attack" if area else "spell_attack", "attack": attack,
               "damage": base_damage, "damage_type": dtype}
        if scaling:
            eff["scaling"] = scaling
        if per_slot:
            eff["per_slot_level_above"] = per_slot
        return eff, "self" if (area and self_range) else "creature"
    if save and damage_ok and not attack and (area or not self_range):
        eff = {"type": "area_save" if area else "save", "save": save["ability"], "damage": base_damage,
               "damage_type": dtype, "on_save": save["on_success"]}
        if scaling:
            eff["scaling"] = scaling
        if per_slot:
            eff["per_slot_level_above"] = per_slot
        return eff, "self" if (area and self_range) else "creature"
    if heal and not area:
        base = heal.get(str(level)) or heal[sorted(heal, key=int)[0]]
        mod = "+MOD" in base
        dice_part = base.replace("+MOD", "")
        heal_step = per_level_increment({k: v.replace("+MOD", "") for k, v in heal.items()})
        multi = re.search(r"up to (six|five|\w+) creatures|each creature|choice within range", join_desc(api["desc"]).lower())
        if valid_dice(dice_part) and not multi and not self_range:
            eff = {"type": "heal", "dice": dice_part, "add_casting_mod": mod}
            if heal_step:
                eff["per_slot_level_above"] = heal_step
            return eff, "creature_or_self"
        reason = reason or "multi-target healing"
    if reason is None:
        if attack or save:
            reason = "no direct damage roll" if not damage_ok else "self-range effect"
        elif heal:
            reason = "area healing"
        else:
            reason = "utility or condition effect"
    return {"type": "unsupported", "reason": reason}, unsupported_target


def build_spells(f: Fetcher, out: Output) -> tuple[set[str], dict[str, list[str]]]:
    ids: set[str] = set()
    for ref in f.listing("spells"):
        api = f.get(ref["url"])
        if not api.get("classes"):
            continue
        rec = convert_spell(api)
        ids.add(rec["id"])
        imported = dict(rec)
        path = os.path.join(DATA, "spells", rec["id"] + ".json")
        if os.path.exists(path) and load_json(path).get("hand_edited"):
            # Keep hand text; offer the SRD text under its own key.
            imported["srd_description"] = imported.pop("description")
        out.put_merged("spells/%s.json" % rec["id"], imported)
    # Hand-written spells the API does not carry (e.g. SRD 5.2 hex) extend the class lists.
    extra: dict[str, list[str]] = {}
    spell_dir = os.path.join(DATA, "spells")
    for name in sorted(os.listdir(spell_dir)):
        sid = name[:-5]
        if not name.endswith(".json") or sid in ids:
            continue
        rec = load_json(os.path.join(spell_dir, name))
        if rec.get("hand_edited"):
            with open(os.path.join(spell_dir, name), encoding="utf-8") as fh:
                out.files["spells/" + name] = fh.read()
            ids.add(sid)
            for cls in rec.get("classes", []):
                extra.setdefault(cls, []).append(sid)
    return ids, extra


# ---------------------------------------------------------------------------- monsters


def monster_cr_band(cr: float) -> str:
    for limit, table in LOOT_BANDS:
        if cr <= limit:
            return table
    return "boss"


def parse_speed(speed: dict) -> tuple[int, dict]:
    speeds: dict = {}
    for k in sorted(speed):
        v = speed[k]
        if isinstance(v, bool):
            speeds[k] = v
        else:
            speeds[k] = feet(v)
    return speeds.get("walk", 0) if isinstance(speeds.get("walk", 0), int) else 0, speeds


def senses_text(senses: dict) -> str:
    parts = []
    for k in sorted(senses):
        if k == "passive_perception":
            continue
        parts.append("%s %s" % (k.replace("_", " "), senses[k]))
    if "passive_perception" in senses:
        parts.append("passive Perception %d" % senses["passive_perception"])
    return ", ".join(parts)


def first_damage(entries: list) -> tuple[list[dict], str | None]:
    """[{damage, damage_type}] from an API damage list (first option of a choice)."""
    out = []
    versatile = None
    for d in entries or []:
        if "from" in d:
            opts = d["from"].get("options", [])
            if not opts:
                continue
            o = opts[0]
            if len(opts) > 1 and opts[1].get("damage_dice"):
                versatile = dice(opts[1]["damage_dice"])
            if o.get("damage_dice") and o.get("damage_type"):
                out.append({"damage": dice(o["damage_dice"]), "damage_type": o["damage_type"]["index"]})
            continue
        if d.get("damage_dice") and d.get("damage_type"):
            out.append({"damage": dice(d["damage_dice"]), "damage_type": d["damage_type"]["index"]})
    return out, versatile


def convert_attack(action: dict) -> dict | None:
    if action.get("attack_bonus") is None:
        return None
    dmg, versatile = first_damage(action.get("damage", []))
    if not dmg or not valid_dice(dmg[0]["damage"]):
        return None
    desc = action.get("desc", "")
    m = re.match(r"^(Melee|Ranged)( or Ranged)? (Weapon|Spell) Attack", desc)
    kind = "ranged" if m and m.group(1) == "Ranged" else "melee"
    attack: dict = {"name": action["name"], "kind": kind}
    reach = re.search(r"reach (\d+) ft", desc)
    rng = re.search(r"range (\d+)(?:/(\d+))? ft", desc)
    if kind == "melee":
        r = int(reach.group(1)) if reach else 5
        attack["reach_ft"] = r
        if r > 5:
            attack["range_ft"] = [r, r]
        if m and m.group(2) and rng:
            attack["thrown_range_ft"] = [int(rng.group(1)), int(rng.group(2) or rng.group(1))]
    elif rng:
        attack["range_ft"] = [int(rng.group(1)), int(rng.group(2) or rng.group(1))]
    if m and m.group(3) == "Spell":
        attack["spell_attack"] = True
    attack["to_hit"] = int(action["attack_bonus"])
    attack["damage"] = dmg[0]["damage"]
    attack["damage_type"] = dmg[0]["damage_type"]
    if versatile:
        attack["versatile_damage"] = versatile
    extra = [d for d in dmg[1:] if valid_dice(d["damage"])]
    if extra:
        attack["extra_damage"] = extra
    attack["description"] = desc
    return attack


def multiattack_names(action: dict, attack_names: list[str]) -> list[str]:
    def expand(entries) -> list[str]:
        names = []
        for e in entries:
            n = e.get("action_name")
            if n in attack_names:
                count = str(e.get("count", 1))
                names += [n] * (int(count) if count.isdigit() else 1)  # hydra: "Number of Heads"
        return names

    if action.get("multiattack_type") == "action_options":
        for opt in action.get("action_options", {}).get("from", {}).get("options", []):
            names = expand(opt.get("items", [opt]))
            if names:
                return names
        return []
    return expand(action.get("actions", []))


def convert_monster(api: dict) -> dict | None:
    mid = snake(api["index"])
    attacks = []
    traits = []
    multi = None
    for action in api.get("actions", []):
        if action["name"] == "Multiattack" or action.get("multiattack_type"):
            multi = action
            continue
        att = convert_attack(action)
        if att is not None:
            attacks.append(att)
        else:
            traits.append(trait("action", action))
    if not attacks:
        return None
    hit_dice = dice(api.get("hit_points_roll") or api["hit_dice"])
    if not valid_dice(hit_dice):
        hit_dice = dice(api["hit_dice"])
    speed, speeds = parse_speed(api.get("speed", {}))
    ac = api["armor_class"][0]
    ctype = api["type"].lower()
    swarm = False
    sm = re.match(r"swarm of \w+ (\w+?)s?$", ctype)
    if sm:
        swarm = True
        ctype = sm.group(1)
    rec: dict = {
        "schema_version": 1,
        "id": mid,
        "display_name": api["name"],
        "size": api["size"].lower(),
        "creature_type": ctype,
    }
    if api.get("subtype"):
        rec["subtype"] = api["subtype"].lower()
    if swarm:
        rec["swarm"] = True
    rec["alignment"] = api.get("alignment", "")
    rec["armor_class"] = int(ac["value"])
    note = ", ".join(a["name"].lower() for a in ac.get("armor", [])) or ac.get("type", "")
    if note and note != "dex":
        rec["armor_note"] = note
    rec["hit_points"] = int(api["hit_points"])
    rec["hit_dice"] = hit_dice
    rec["speed"] = speed
    rec["speeds"] = speeds
    rec["abilities"] = {ab: int(api[field]) for ab, field in zip(ABILITIES, ABILITY_FIELDS)}
    saves = {}
    skills = {}
    for p in api.get("proficiencies", []):
        idx = p["proficiency"]["index"]
        if idx.startswith("saving-throw-"):
            saves[idx.replace("saving-throw-", "").upper()] = int(p["value"])
        elif idx.startswith("skill-"):
            key = SKILL_KEYS.get(idx.replace("skill-", ""))
            if key:
                skills[key] = int(p["value"])
    if saves:
        rec["saving_throws"] = saves
    if skills:
        rec["skills"] = skills
    rec["damage_resistances"] = list(api.get("damage_resistances", []))
    rec["damage_immunities"] = list(api.get("damage_immunities", []))
    rec["damage_vulnerabilities"] = list(api.get("damage_vulnerabilities", []))
    conds = []
    for c in api.get("condition_immunities", []):
        if c["index"] not in conds:
            conds.append(c["index"])
    rec["condition_immunities"] = conds
    rec["senses"] = senses_text(api.get("senses", {}))
    rec["languages"] = api.get("languages", "")
    rec["challenge_rating"] = api["challenge_rating"]
    rec["proficiency_bonus"] = api.get("proficiency_bonus", 2)
    cr = api["challenge_rating"]
    rec["xp"] = int(api["xp"]) if cr == 0 else CR_XP.get(cr, int(api["xp"]))
    rec["loot_table"] = monster_cr_band(float(api["challenge_rating"]))
    rec["icon"] = ICON_BY_TYPE.get(ctype, "ogre")
    for sa in api.get("special_abilities", []):
        traits.insert(len([t for t in traits if t["kind"] == "trait"]), trait("trait", sa))
    for r in api.get("reactions", []):
        traits.append(trait("reaction", r))
    for la in api.get("legendary_actions", []):
        traits.append(trait("legendary_action", la))
    # Order: traits, then actions, reactions, legendary actions.
    order = {"trait": 0, "action": 1, "reaction": 2, "legendary_action": 3}
    rec["traits"] = sorted(traits, key=lambda t: order[t["kind"]])
    if multi is not None:
        rec["multiattack"] = multiattack_names(multi, [a["name"] for a in attacks])
        rec["multiattack_text"] = multi.get("desc", "")
    rec["attacks"] = attacks
    rec["source"] = SOURCE
    return rec


def trait(kind: str, api: dict) -> dict:
    t = {"name": api["name"], "kind": kind, "description": join_desc(api.get("desc", ""))}
    if api.get("usage"):
        u = api["usage"]
        t["usage"] = {k: u[k] for k in sorted(u) if k in ("type", "times", "dice", "min_value", "rest_types")}
    if api.get("dc"):
        t["dc"] = {"ability": api["dc"]["dc_type"]["index"].upper(), "value": api["dc"].get("dc_value"),
                   "on_success": api["dc"].get("success_type")}
    if api.get("spellcasting"):
        sc = api["spellcasting"]
        t["spellcasting"] = {
            "ability": sc.get("ability", {}).get("index", "").upper(),
            "dc": sc.get("dc"), "modifier": sc.get("modifier"),
            "spells": sorted({snake(s["url"].rsplit("/", 1)[1]) for s in sc.get("spells", []) if s.get("url")}),
        }
    t["mechanic"] = "unsupported"
    return t


def build_monsters(f: Fetcher, out: Output) -> list[str]:
    skipped = []
    for ref in f.listing("monsters"):
        api = f.get(ref["url"])
        rec = convert_monster(api)
        if rec is None:
            skipped.append(snake(api["index"]))
            continue
        out.put_merged("monsters/%s.json" % rec["id"], rec)
    return skipped


# ---------------------------------------------------------------------------- equipment


def cost_gp(cost: dict | None) -> float:
    if not cost:
        return 0.0
    v = float(cost.get("quantity", 0)) * COIN_GP.get(cost.get("unit", "gp"), 1.0)
    return round(v, 2)


def equipment_id(index: str) -> str:
    return EQUIPMENT_ID_ALIASES.get(index, snake(index))


def convert_weapon(api: dict) -> tuple[dict | None, dict]:
    wid = equipment_id(api["index"])
    cat = api["weapon_category"].lower()
    ranged = api.get("weapon_range") == "Ranged"
    props = [p["index"].replace("two-handed", "two_handed") for p in api.get("properties", [])]
    dmg = (api.get("damage") or {}).get("damage_dice")
    dtype = ((api.get("damage") or {}).get("damage_type") or {}).get("index", "")
    desc_bits = ["%s %s weapon" % (cat.capitalize(), "ranged" if ranged else "melee")]
    item = {"schema_version": 1, "id": wid, "display_name": api["name"], "kind": "weapon"}
    if dmg is None:
        # The net deals no damage: kept as a misc item.
        item["kind"] = "misc"
        item["description"] = "Martial ranged weapon (thrown, 5/15 ft) that deals no damage. " + join_desc(api.get("special", []))
        item["weight"] = api.get("weight", 0)
        item["value_gp"] = cost_gp(api.get("cost"))
        item["stackable"] = False
        item["mechanic"] = "unsupported"
        item["source"] = SOURCE
        return None, item
    weapon = {"schema_version": 1, "id": wid, "display_name": api["name"], "category": cat}
    if re.fullmatch(r"\d+", dmg):
        weapon["damage"] = "1d%s" % dmg  # flat damage (blowgun: 1) as a one-sided die
        weapon["damage_note"] = "%s %s damage (flat)" % (dmg, dtype)
    else:
        weapon["damage"] = dice(dmg)
    weapon["damage_type"] = dtype
    weapon["properties"] = props
    if api.get("two_handed_damage"):
        weapon["versatile_damage"] = dice(api["two_handed_damage"]["damage_dice"])
    rng = api.get("range") or {}
    if ranged and rng.get("long"):
        weapon["range_ft"] = [rng["normal"], rng["long"]]
        weapon["ranged"] = True
    elif "thrown" in props and api.get("throw_range"):
        weapon["range_ft"] = [api["throw_range"]["normal"], api["throw_range"]["long"]]
    if "ammunition" in props:
        weapon["ammo_id"] = AMMO_FOR_WEAPON.get(wid, "")
    if api.get("special"):
        weapon["special"] = join_desc(api["special"])
    weapon["source"] = SOURCE
    desc = "%s: %s %s" % (desc_bits[0], weapon["damage_note"] if "damage_note" in weapon else weapon["damage"], dtype)
    if props:
        desc += " (%s)" % ", ".join(p.replace("_", "-") for p in props)
    if "range_ft" in weapon:
        desc += ", range %d/%d ft" % tuple(weapon["range_ft"])
    item.update({
        "description": desc + ".",
        "weight": api.get("weight", 0),
        "value_gp": cost_gp(api.get("cost")),
        "stackable": True,
        "weapon_id": wid,
    })
    if weapon.get("ammo_id"):
        item["ammo_id"] = weapon["ammo_id"]
    item["source"] = SOURCE
    return weapon, item


def convert_armor(api: dict) -> dict:
    aid = equipment_id(api["index"])
    item = {"schema_version": 1, "id": aid, "display_name": api["name"]}
    ac = api["armor_class"]
    if api["armor_category"] == "Shield":
        item.update({"kind": "shield", "description": "A shield carried in one hand: +%d AC." % ac["base"],
                     "weight": api.get("weight", 0), "value_gp": cost_gp(api.get("cost")), "stackable": False,
                     "shield": {"bonus": ac["base"]}})
    else:
        cat = api["armor_category"].lower()
        max_dex = -1 if ac.get("dex_bonus") and ac.get("max_bonus") is None else (ac.get("max_bonus") or 0)
        desc = "%s armor: AC %d" % (cat.capitalize(), ac["base"])
        if cat != "heavy":
            desc += " + DEX modifier" + (" (max %d)" % max_dex if max_dex > 0 else "")
        if api.get("str_minimum"):
            desc += ". Needs Strength %d" % api["str_minimum"]
        if api.get("stealth_disadvantage"):
            desc += ". Disadvantage on Stealth checks"
        armor = {"base": ac["base"], "max_dex": max_dex, "category": cat,
                 "stealth_disadvantage": bool(api.get("stealth_disadvantage"))}
        if api.get("str_minimum"):
            armor["strength"] = api["str_minimum"]
        item.update({"kind": "armor", "description": desc + ".", "weight": api.get("weight", 0),
                     "value_gp": cost_gp(api.get("cost")), "stackable": False, "armor": armor})
    item["source"] = SOURCE
    return item


def convert_gear(api: dict) -> dict:
    gid = equipment_id(api["index"])
    cat = api["equipment_category"]["index"]
    gear_cat = (api.get("gear_category") or {}).get("index", "")
    kind = "ammo" if gear_cat == "ammunition" else "misc"
    desc = join_desc(api.get("desc", []))
    if not desc:
        label = (api.get("gear_category") or {}).get("name") or api.get("tool_category") or "Adventuring gear"
        desc = "%s: %s." % (label, api["name"])
    item = {"schema_version": 1, "id": gid, "display_name": api["name"], "kind": kind, "description": desc,
            "weight": api.get("weight", 0), "value_gp": cost_gp(api.get("cost")),
            "stackable": kind == "ammo"}
    if api.get("quantity", 1) and api.get("quantity", 1) > 1:
        item["bundle_quantity"] = api["quantity"]
    if cat == "tools":
        item["tool_category"] = api.get("tool_category", "")
    elif gear_cat:
        item["gear_category"] = gear_cat
    if api.get("contents"):
        item["contents"] = [{"item": equipment_id(c["item"]["index"]), "qty": c["quantity"]} for c in api["contents"]]
    item["source"] = SOURCE
    return item


def convert_magic_item(api: dict, taken: set[str]) -> dict | None:
    idx = api["index"]
    if api.get("variants"):
        return None  # a "varies" parent: its variants are separate records
    rarity = api["rarity"]["name"].lower()
    desc_lines = api.get("desc", [])
    header = desc_lines[0] if desc_lines else ""
    attune = "requires attunement" in header.lower()
    m = re.search(r"\(requires attunement([^)]*)\)", header)
    plus = PLUS_N.match(idx)
    if idx in HEALING_POTIONS:
        mid, heal = HEALING_POTIONS[idx]
    else:
        mid = snake(re.sub(r"-([123])$", r"-plus-\1", idx) if re.search(r"\+\d", api["name"]) else idx)
        if mid in taken:
            mid = "magic_" + mid
    item: dict = {"schema_version": 1, "id": mid, "display_name": api["name"], "kind": "misc",
                  "description": join_desc(desc_lines[1:] if len(desc_lines) > 1 else desc_lines),
                  "weight": 0, "value_gp": RARITY_VALUE_GP.get(rarity, 0), "stackable": False}
    if idx in HEALING_POTIONS:
        item["kind"] = "consumable"
        item["weight"] = 0.5
        item["stackable"] = True
        item["use"] = {"action": "action", "effect": "heal", "dice": HEALING_POTIONS[idx][1], "target": "self"}
    elif plus and plus.group(1) == "ammunition":
        item["kind"] = "ammo"
        item["stackable"] = True
    item["magic"] = True
    item["magic_category"] = api["equipment_category"]["index"]
    item["item_line"] = header
    item["rarity"] = rarity
    item["requires_attunement"] = attune
    if m and m.group(1).strip():
        item["attunement_note"] = m.group(1).strip()
    if plus:
        item["bonus"] = int(plus.group(2))
        item["bonus_applies_to"] = plus.group(1)
        item["mechanic"] = "bonus"
    elif idx in HEALING_POTIONS:
        item["mechanic"] = "implemented"
    else:
        item["mechanic"] = "unsupported"
    item["value_basis"] = "rarity"
    item["source"] = SOURCE
    return item


def build_equipment(f: Fetcher, out: Output) -> dict:
    counts = {"weapons": 0, "items": 0, "magic_items": 0, "skipped_vehicles": 0, "skipped_variant_parents": 0}
    taken: set[str] = set()
    for ref in f.listing("equipment"):
        api = f.get(ref["url"])
        cat = api["equipment_category"]["index"]
        if cat == "mounts-and-vehicles":
            counts["skipped_vehicles"] += 1
            continue
        if cat == "weapon":
            weapon, item = convert_weapon(api)
            if weapon:
                out.put_merged("weapons/%s.json" % weapon["id"], weapon)
                counts["weapons"] += 1
        elif cat == "armor":
            item = convert_armor(api)
        else:
            item = convert_gear(api)
        out.put_merged("items/%s.json" % item["id"], item)
        taken.add(item["id"])
        counts["items"] += 1
    for ref in f.listing("magic-items"):
        api = f.get(ref["url"])
        item = convert_magic_item(api, taken)
        if item is None:
            counts["skipped_variant_parents"] += 1
            continue
        taken.add(item["id"])
        out.put_merged("items/%s.json" % item["id"], item)
        counts["magic_items"] += 1
    # Hand-written items/weapons with no API record stay as they are.
    for sub in ("items", "weapons"):
        d = os.path.join(DATA, sub)
        for name in sorted(os.listdir(d)):
            rel = "%s/%s" % (sub, name)
            if name.endswith(".json") and rel not in out.files:
                with open(os.path.join(d, name), encoding="utf-8") as fh:
                    out.files[rel] = fh.read()
    return counts


# ---------------------------------------------------------------------------- driver

MANAGED_DIRS = ["classes", "features", "invocations", "metamagic", "fighting_styles", "spells",
                "monsters", "weapons", "items"]


def prefetch_all(f: Fetcher) -> None:
    urls = []
    for res in ["classes", "subclasses", "features", "spells", "monsters", "equipment", "magic-items"]:
        urls += [r["url"] for r in f.listing(res)]
    for c in CLASS_ORDER:
        urls += [API + "classes/%s/levels" % c, API + "classes/%s/spells" % c]
    for s in f.listing("subclasses"):
        urls.append(s["url"] + "/levels")
    f.prefetch(urls)


def convert(f: Fetcher) -> Output:
    out = Output()
    implemented = implemented_ids()
    spell_ids, extra_lists = build_spells(f, out)
    feat = build_features(f, out, implemented)
    build_classes(f, out, feat, spell_ids, extra_lists)
    skipped = build_monsters(f, out)
    counts = build_equipment(f, out)
    # Hand-written monsters with no API record are kept.
    d = os.path.join(DATA, "monsters")
    for name in sorted(os.listdir(d)):
        rel = "monsters/" + name
        if name.endswith(".json") and rel not in out.files:
            with open(os.path.join(d, name), encoding="utf-8") as fh:
                out.files[rel] = fh.read()
    out.notes.append("monsters skipped (no attack roll): %s" % ", ".join(skipped))
    out.notes.append("equipment: %s" % json.dumps(counts, sort_keys=True))
    out.notes.append("implemented ids read from features.gd: %d" % len(implemented))
    return out


def scan_terms(out: Output) -> list[str]:
    hits = []
    pattern = re.compile(r"\b(?:%s)\b" % "|".join(NON_SRD_TERMS), re.I)
    for rel, text in sorted(out.files.items()):
        for m in pattern.finditer(text):
            hits.append("%s: %s" % (rel, m.group(0)))
    return hits


def write(out: Output) -> int:
    changed = 0
    for rel, text in sorted(out.files.items()):
        path = os.path.join(DATA, rel)
        os.makedirs(os.path.dirname(path), exist_ok=True)
        old = None
        if os.path.exists(path):
            with open(path, encoding="utf-8") as fh:
                old = fh.read()
        if old != text:
            with open(path, "w", encoding="utf-8") as fh:
                fh.write(text)
            changed += 1
    # Remove generated files the import no longer produces (never hand-edited ones).
    for sub in MANAGED_DIRS:
        d = os.path.join(DATA, sub)
        if not os.path.isdir(d):
            continue
        for name in sorted(os.listdir(d)):
            rel = "%s/%s" % (sub, name)
            if name.endswith(".json") and rel not in out.files:
                if not load_json(os.path.join(d, name)).get("hand_edited"):
                    os.remove(os.path.join(d, name))
                    changed += 1
    return changed


def diff_against_disk(out: Output) -> list[str]:
    problems = []
    for rel, text in sorted(out.files.items()):
        path = os.path.join(DATA, rel)
        if not os.path.exists(path):
            problems.append("missing: data/" + rel)
            continue
        with open(path, encoding="utf-8") as fh:
            if fh.read() != text:
                problems.append("differs: data/" + rel)
    for sub in MANAGED_DIRS:
        d = os.path.join(DATA, sub)
        for name in sorted(os.listdir(d)) if os.path.isdir(d) else []:
            if name.endswith(".json") and "%s/%s" % (sub, name) not in out.files:
                problems.append("not produced: data/%s/%s" % (sub, name))
    return problems


def sync_mechanics() -> int:
    implemented = implemented_ids()
    changed = 0
    for sub in ("features", "invocations", "metamagic", "fighting_styles"):
        d = os.path.join(DATA, sub)
        for name in sorted(os.listdir(d)) if os.path.isdir(d) else []:
            path = os.path.join(d, name)
            rec = load_json(path)
            fid = rec["id"]
            aliases = [fid.replace("_spell", "")] if sub == "metamagic" else (
                ["fighting_style_" + fid] if sub == "fighting_styles" else [])
            want = mechanic_for(fid, implemented, aliases)
            if rec.get("mechanic") != want:
                rec["mechanic"] = want
                with open(path, "w", encoding="utf-8") as fh:
                    fh.write(dumps(rec))
                changed += 1
    return changed


def main(argv: list[str]) -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("--offline", action="store_true", help="use tools/srd_cache only")
    ap.add_argument("--check", action="store_true", help="convert twice, compare with data/ (no writes)")
    ap.add_argument("--sync-mechanics", action="store_true", help="only refresh mechanic fields")
    args = ap.parse_args(argv)
    if args.sync_mechanics:
        print("import_srd: %d mechanic field(s) updated" % sync_mechanics())
        return 0
    f = Fetcher(offline=args.offline or args.check)
    if not args.check:
        prefetch_all(f)
    out = convert(f)
    hits = scan_terms(out)
    if args.check:
        again = convert(f)
        problems = []
        if again.files != out.files:
            problems.append("two conversions differ: %s" % sorted(
                k for k in set(out.files) | set(again.files) if out.files.get(k) != again.files.get(k))[:10])
        problems += diff_against_disk(out)
        problems += ["non-SRD term: " + h for h in hits]
        for p in problems[:50]:
            print(p)
        print("import_srd --check: %s (%d files)" % ("OK" if not problems else "%d problem(s)" % len(problems), len(out.files)))
        return 1 if problems else 0
    changed = write(out)
    for note in out.notes:
        print("import_srd: " + note)
    for h in hits:
        print("import_srd: WARNING non-SRD term in " + h)
    print("import_srd: %d file(s) produced, %d changed, %d fetched" % (len(out.files), changed, f.fetched))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
