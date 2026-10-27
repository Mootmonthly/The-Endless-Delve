class_name ClientState
extends RefCounted
## Everything the client knows about the game, derived purely from server
## results (see Messages): FLOOR_LOADED, CHARACTER_STATE, EXPLORE_STATE,
## ENCOUNTER_EVENTS, ERROR, GAME_OVER, FLOOR_CLEARED and SET_CLEARED.
##
## Five-floor sets: FLOOR_LOADED arrives again for every new floor (extras
## set_id / set_name / floor_index / floor_count); each one replaces the floor,
## forgets the old floor's entities and encounter and bumps floor_serial so
## scenes rebuild their views. FLOOR_CLEARED on a floor with a next floor only
## means "descending" (mode LOADING until the next FLOOR_LOADED); on a single
## floor or the set's last floor it is the end (mode FLOOR_CLEARED), and
## SET_CLEARED then ends the run (mode SET_CLEARED).
##
## Pure view-model: no Nodes, no rules resolution, no dice. The client only
## predicts what it needs to drive the UI (movement left this turn, whether
## the action is spent, which tiles look reachable) and the server re-checks
## every intent. Scenes call apply() for each result and then read the state.
##
## Entities are Dictionaries:
##   {"id": String, "kind": "player"|"monster", "name": String,
##    "position": Vector2i, "hp": int (-1 = unknown), "max_hp": int (-1 = unknown),
##    "down": bool, "dead": bool}
## Optional extra fields the server sends are used when present (FLOOR_LOADED /
## CHARACTER_STATE "entity_id", EXPLORE_STATE "name"/"hp"/"max_hp"/"dead",
## ENCOUNTER_EVENTS "encounter_id"/"zone_id", CHARACTER_STATE "healed",
## "xp_gained", "floor_clear_xp", "leveled_to", "levels_pending", "long_rest",
## "item_used", "temp_hp", "equipped" / "unequipped" {item, slot}, "dropped"
## {item, qty}; legacy "levels_gained"; EXPLORE_STATE "monster_id").
## Entities also carry "monster_id" (monsters, from EXPLORE_STATE) and
## "class_id" (this client's character, from its sheet) for the icon atlas.
##
## Items, spells and level-ups (M2):
## - LOOT_GAINED / CHEST_OPENED / CHEST_REVEALED keep `chests` (only chests the
##   server has shown: FLOOR_LOADED "chests", else the floor's non-hidden ones)
##   and log the loot. The inventory itself only changes through CHARACTER_STATE
##   (the server sends one after every loot) or combat events (item_used,
##   attack "consumed", cast "slot_level", feature_used "remaining"), which
##   predict the sheet until the next CHARACTER_STATE.
## - LEVEL_UP_AVAILABLE stores `level_up_offer` (LevelUp.choices) and bumps
##   level_up_serial; a CHARACTER_STATE with "leveled_to" (or no pending
##   level left) clears it. Offers are answered only out of combat.
## - Targeting: begin_cast / begin_feature / begin_attack_targeting put the
##   next map click into `targeting` mode; intent_for_click then picks the
##   target on the clicked tile. Ranged attacks need no mode: clicking a
##   monster uses `selected_attack`.
## - Combat attacks are indexed like the server's Combatant: the sheet's
##   attacks at the start of the encounter plus the unarmed strike (plus the
##   Pact of the Blade weapon once effect_applied "pact_weapon" arrives).
##
## Class progression (round A):
## - `conditions` (id -> [{condition, source, duration, turns_left}]) follow
##   condition_applied / condition_ended; turns_left counts down on turn_ended
##   exactly as the core does, for the "(2 turns)" tags. `concentration`
##   (id -> spell) follows concentration_started / concentration_ended.
## - Extra Attack: the first attack takes the action and leaves
##   attacks_per_action() - 1 `attacks_remaining`; Action Surge gives the
##   action back; Flurry of Blows grants `bonus_attacks_remaining`. Features
##   map to their resource (ki, channel_divinity, sorcery_points, ...) so a
##   feature_used "remaining" updates the right counter.
## - `attack_options` (reckless, smite, stun, technique) are added to attack
##   intents when they apply to that attack; smite and stun are one-shot.
## - Area spells: begin_cast enters targeting with "area": true; a click picks
##   the point; area_preview(tile) gives the footprint and the creatures it
##   would catch (Sculpt Spells allies left out). Metamagic rides on cast
##   intents; Twinned Spell asks for a second target.
## - `reaction_policy` (CHARACTER_STATE "reaction_policy"),
##   reaction_entries() (each trigger with its label and the player's own
##   reactions it governs: opportunity attack, Shield, Uncanny Dodge, ...) and
##   reaction_policy_intent() / reaction_toggle_intent(); usable in and out of
##   combat. reaction_used / damage_reduced mark the player's reaction as spent.
##
## Out of combat (round B UI):
## - spell_entries() carry "casting_time" / "casting_time_text" / "ritual" /
##   "out_of_combat"; while exploring cast_error() follows OutOfCombat.cast
##   (companions, heals, temp HP, restorations, Mage Armor; the player is the
##   only target in M2) and begin_cast() returns the cast intent at once.
## - OUT_OF_COMBAT_EVENTS logs the cast and its outcome (companion summoned,
##   heal, temp HP, revive, restoration, buff); the CHARACTER_STATE after it
##   carries the new sheet (slots, companions, hp).
## - companion_entries() / companions_text() read sheet.companions (server
##   ids "c<n>"); dismiss_companion_intent() removes one (exploring only).
## - Summons and companions in a fight (combatant_joined with "owner") are
##   KIND_ALLY entities: never hostile, never valid ally-spell targets.
##
## Floor objects (Round D):
## - FLOOR_LOADED "doors" / "props" / "landing_id" / "light" fill door_states,
##   destroyed_props, landing_id and floor_light; DOOR_CHANGED,
##   PROP_DESTROYED and ZONE_RESPAWNED update them and log a line (views watch
##   objects_serial). explore_map() is the floor with closed / locked doors
##   as walls (what the server paths on); blocking props are obstacles
##   (prop_blockers); in a fight movement_map() also walls the props and
##   follows terrain_changed walls / floors.
## - intent_for_click while exploring: a door within reach opens / closes (a
##   locked one: thieves' tools, else its key, else Knock), a prop within
##   reach breaks (interact), a chest opens; anything farther walks next to
##   it. A tile behind a closed door walks to the door (and opens it once
##   there: route_intent).
## - Exploration spells (Knock, Mage Hand, Arcane Lock, Clairvoyance...)
##   cast out of combat aim at a door, chest or zone with a click (targeting
##   "object": true) or at a landmark (begin_cast extra "target_kind" /
##   "target_id"); REVEAL results are logged and kept in last_reveal.
##
## Round C in fights: tile_effects (tile_effect_created / moved / ended:
## tiles, terrain, darkness, lit, difficult from the spell's zone data),
## terrain_walls / terrain_floors (terrain_changed), encounter_light
## (encounter_started "light", light_changed), dominated creatures
## (team_changed: `controlled`, controlled_creatures(), control_* intents),
## absent creatures (banished / returned, blink), illusions (combatant_joined
## "illusion"), hidden creatures (hidden / revealed): visibility_of(id) is
## "shown", "ghost" (own side unseen, illusions) or "hidden" (unseen
## hostiles, absent creatures). Spells: ritual casting out of combat (spell
## entries "ritual_castable", cast extra "ritual"), declared no-effect spells
## ("no_effect" reason: castable, free), Overchannel (cast_options), and the
## attack options via_familiar (Pact of the Chain), quivering_palm and
## hurl_through_hell.

enum Mode { LOADING, EXPLORING, COMBAT, GAME_OVER, FLOOR_CLEARED, SET_CLEARED }

const KIND_PLAYER := "player"
const KIND_MONSTER := "monster"
## A summon or companion fighting on the players' side (combatant_joined "owner").
const KIND_ALLY := "ally"
const PLAYER_ID_PREFIX := "p"
const MAX_LOG_LINES := 200
const TEAM_PLAYERS := 0
const TARGET_CAST := "cast"
const TARGET_FEATURE := "feature"
const TARGET_ATTACK := "attack"
## Targeting a dominated creature's order ({"mode", "creature", "order":
## "move" | "attack"}).
const TARGET_CONTROL := "control"
## visibility_of() values.
const VIS_SHOWN := "shown"
const VIS_GHOST := "ghost"
const VIS_HIDDEN := "hidden"
const THIEVES_TOOLS := "thieves_tools"
## Compass landing ids -> how the HUD names them.
const LANDING_NAMES: Dictionary[String, String] = {
	"n": "north", "s": "south", "e": "east", "w": "west", "ne": "north-east", "nw": "north-west",
	"se": "south-east", "sw": "south-west", "north": "north", "south": "south", "east": "east", "west": "west",
}
const FEATURE_MARTIAL_ARTS_STRIKE := "martial_arts"
## Pseudo features of the Features list that are bonus-action attacks.
const FEATURE_OFF_HAND_ATTACK := "off_hand_attack"
const FEATURE_FLURRY_STRIKE := "flurry_strike"
const FEATURE_FRENZY_ATTACK := "frenzy_attack"
## use_feature ids that take the action / cost nothing (the rest are bonus
## actions), as Encounter._feature_cost.
const ACTION_FEATURES: Array[String] = ["lay_on_hands", "turn_undead", "turn_the_unholy", "preserve_life", "sacred_weapon", "pact_weapon"]
const FREE_FEATURES: Array[String] = ["action_surge"]
## use_feature "mode" choices.
const FEATURE_MODES: Dictionary[String, Array] = {
	"step_of_the_wind": ["dash", "disengage"], "cunning_action": ["dash", "disengage"],
	"font_of_magic": ["create_slot", "convert_slot"],
}
## Channel Divinity / Preserve Life reach (Encounter.CHANNEL_DIVINITY_RANGE_TILES).
const CHANNEL_DIVINITY_RANGE := 6
## Conditions that drop speed to 0 (Conditions.IMMOBILIZING).
const IMMOBILIZING: Array[String] = ["stunned", "paralyzed", "restrained", "grappled"]
const CONCENTRATION_REASONS: Dictionary[String, String] = {
	"new_spell": "casting another concentration spell", "damage": "taking damage", "unconscious": "falling unconscious",
	"incapacitated": "being incapacitated", "rage": "raging",
}
## Bardic Inspiration reach (Encounter.BARDIC_INSPIRATION_RANGE_TILES).
const BARDIC_INSPIRATION_RANGE := 12
## Effect id -> the tag shown next to a combatant ("dodge" comes from the dodge event).
const STATUS_TAGS: Dictionary[String, String] = {
	"dodge": "dodging", "rage": "raging", "hex": "hexed", "guiding_bolt_mark": "marked",
	"slow": "slowed", "mockery": "mocked", "bardic_inspiration": "inspired",
	"mage_armor": "mage armor", "no_reactions": "no reactions", "frenzy": "frenzied",
	"reckless_attack": "reckless", "sacred_weapon": "sacred weapon", "pact_weapon": "pact weapon",
}
const FEATURE_NAMES: Dictionary[String, String] = {
	"second_wind": "Second Wind", "rage": "Rage", "lay_on_hands": "Lay on Hands",
	"bardic_inspiration": "Bardic Inspiration", "martial_arts": "Martial Arts strike",
	"action_surge": "Action Surge", "ki": "Ki", "channel_divinity": "Channel Divinity",
	"sorcery_points": "Sorcery points", "arcane_recovery": "Arcane Recovery", "natural_recovery": "Natural Recovery",
	"flurry_of_blows": "Flurry of Blows", "patient_defense": "Patient Defense", "step_of_the_wind": "Step of the Wind",
	"cunning_action": "Cunning Action", "turn_undead": "Turn Undead", "turn_the_unholy": "Turn the Unholy",
	"preserve_life": "Preserve Life", "sacred_weapon": "Sacred Weapon", "font_of_magic": "Font of Magic",
	"pact_weapon": "Pact Weapon", "divine_smite": "Divine Smite", "stunning_strike": "Stunning Strike",
	"open_hand_technique": "Open Hand Technique", "off_hand_attack": "Off-hand attack",
	"flurry_strike": "Flurry of Blows strike", "frenzy_attack": "Frenzy attack",
	"deflect_missiles": "Deflect Missiles", "uncanny_dodge": "Uncanny Dodge", "destroy_undead": "Destroy Undead",
}
const SLOT_NAMES: Dictionary[String, String] = {"main_hand": "Main hand", "off_hand": "Off hand", "armor": "Armor"}
const LOOT_SOURCES: Dictionary[String, String] = {"chest": "from the chest", "monster": "from the fallen", "floor": "found on the floor",
	"prop": "from the wreckage"}
## Reaction policy triggers (Messages.REACTION_TRIGGERS) as the player reads them.
const REACTION_TRIGGER_LABELS: Dictionary[String, String] = {
	"creature_left_reach": "A creature leaves my reach",
	"creature_hit_me": "A creature hits me", "damage_taken": "I take damage", "missed": "An attack misses me",
	"failed_save": "I fail a saving throw", "ally_attacked": "An ally next to me is attacked", "ally_hit": "An ally is hit",
	"spell_cast_in_range": "A hostile casts a spell within range",
}
## The reactions (and save rescues) each trigger governs, as the Encounter checks them.
const REACTIONS_BY_TRIGGER: Dictionary[String, Array] = {
	"creature_left_reach": ["opportunity_attack"],
	"creature_hit_me": ["shield", "deflect_missiles", "uncanny_dodge", "giant_killer"],
	"damage_taken": ["hellish_rebuke", "retaliation"],
	"missed": ["stand_against_the_tide", "giant_killer"],
	"failed_save": ["dark_ones_own_luck", "indomitable", "diamond_soul"],
	"ally_attacked": ["protection"],
	"ally_hit": ["cutting_words"],
	"spell_cast_in_range": ["counterspell"],
}
const REACTION_NAMES: Dictionary[String, String] = {
	"opportunity_attack": "Opportunity attack", "shield": "Shield", "deflect_missiles": "Deflect Missiles",
	"uncanny_dodge": "Uncanny Dodge", "giant_killer": "Giant Killer", "hellish_rebuke": "Hellish Rebuke",
	"retaliation": "Retaliation", "stand_against_the_tide": "Stand Against the Tide",
	"dark_ones_own_luck": "Dark One's Own Luck", "indomitable": "Indomitable", "diamond_soul": "Diamond Soul",
	"protection": "Protection (fighting style)", "cutting_words": "Cutting Words", "counterspell": "Counterspell",
}
## Reactions that are spells (need the spell prepared).
const REACTION_SPELLS: Array[String] = ["shield", "hellish_rebuke", "counterspell"]

var player_id: String = ""
var mode: Mode = Mode.LOADING
var floor_data: FloorData = null
var sheet: CharacterSheet = null
var entities: Dictionary = {}  # id -> entity Dictionary (see above)
var tick: int = 0

# --- the player's encounter (empty / false outside combat) ---
var in_encounter: bool = false
var encounter_id: String = ""  # only known if the server tags results with "encounter_id"
var region: Rect2i = Rect2i()  # the encounter's zone rect, from the floor
var order: Array[String] = []  # initiative order of the player's encounter
var initiatives: Dictionary = {}  # combatant id -> initiative (from combatant_joined)
var round_number: int = 0
var current_actor: String = ""
var movement_remaining: int = 0  # the player's, tracked from events
var action_used: bool = false  # the player's, tracked from events
var last_winning_team: int = -1
var bonus_action_used: bool = false  # the player's, tracked from events
var attack_action_taken: bool = false  # the player took the Attack action this turn (Martial Arts)
## Combat effects per combatant id: Array[String] of effect ids (see STATUS_TAGS).
var statuses: Dictionary = {}
## Conditions per combatant id: Array[Dictionary] {"condition", "source",
## "duration" (Conditions duration dict), "turns_left"}.
var conditions: Dictionary = {}
## Concentration per combatant id: the spell id.
var concentration: Dictionary = {}
## Further attacks of the player's Attack action this turn (Extra Attack).
var attacks_remaining: int = 0
## Bonus-action attacks granted this turn (Flurry of Blows) and their source.
var bonus_attacks_remaining: int = 0
var bonus_attack_source: String = ""
## Action Surge used this turn.
var action_surged: bool = false
## The player started raging this turn (Frenzy attacks start next turn).
var rage_started_this_turn: bool = false
## The player's reaction is spent (Uncanny Dodge / Deflect Missiles).
var reaction_used: bool = false
## Attack options added to the player's next attack intents when they apply:
## "reckless" (bool, first attack of a turn), "smite" (slot level, 0 = none;
## one-shot), "stun" (bool; one-shot), "technique" ("" / prone / push /
## no_reactions, Flurry of Blows strikes).
var attack_options: Dictionary = {"reckless": false, "smite": 0, "stun": false, "technique": "",
	"via_familiar": false, "quivering_palm": false, "hurl_through_hell": false}
## The player's reaction policy as the server last confirmed it (CHARACTER_STATE
## "reaction_policy"): trigger or reaction id -> "auto" | "never".
var reaction_policy: Dictionary = {}
## The latest area_effect of the player's encounter ({} = none): {"caster",
## "spell", "point": Vector2i, "shape", "size_tiles", "affected", "sculpted"}.
var last_area: Dictionary = {}
## Bumped by every area_effect (views may flash the area).
var area_serial: int = 0

# --- items, chests, spells, level-ups ---
## Content definitions ({} = ContentLoader.cache()).
var content: Dictionary = {}
## Chests the client knows about: id -> {"id", "position": Vector2i, "hidden": bool, "opened": bool}.
var chests: Dictionary = {}
## Latest LEVEL_UP_AVAILABLE choices for this character ({} = none pending).
var level_up_offer: Dictionary = {}
## Bumped by every LEVEL_UP_AVAILABLE for this character.
var level_up_serial: int = 0
## Level reached by the latest answered level-up (CHARACTER_STATE "leveled_to").
var last_leveled_to: int = 0
## Items of the latest LOOT_GAINED for this character.
var last_loot: Array[Dictionary] = []
## Index into available_attacks() used by clicks on monsters and the Attack button.
var selected_attack: int = 0
## {} or {"mode": TARGET_CAST, "spell", "slot_level"} / {"mode": TARGET_FEATURE,
## "feature", "amount"} / {"mode": TARGET_ATTACK, "attack_index", "bonus"}.
var targeting: Dictionary = {}
## Why the last begin_* / targeted click did nothing ("" = fine).
var hint: String = ""

var last_error: String = ""
var cleared_floor_id: String = ""

# --- where in the set (FLOOR_LOADED extras; a single floor is a set of one) ---
var set_id: String = ""
var set_name: String = ""
var floor_index: int = 0  # 0-based position of the current floor in the set
var floor_count: int = 1
## Bumped by every FLOOR_LOADED; scenes rebuild the floor view when it changes.
var floor_serial: int = 0
var cleared_set_id: String = ""
## From the latest CHARACTER_STATE that carried them.
var last_xp_gained: int = 0
var last_levels_gained: int = 0
var log_lines: Array[String] = []
## Bumped by every apply(); scenes redraw when it changes.
var revision: int = 0

## Floor objects (Round D): door id -> "open" | "closed" | "locked"; door
## id -> {"dc", "keyed"}; prop id -> true once broken.
var door_states: Dictionary = {}
var door_info: Dictionary = {}
var destroyed_props: Dictionary = {}
## Landing this character arrived at ("" / "arrival" on a v1 floor).
var landing_id: String = ""
## The floor's light level and the player's own (a light spell: bright).
var floor_light: String = "bright"
var light_level: String = "bright"
## Light of the player's fight (encounter_started "light", light_changed).
var encounter_light: String = "bright"
## Bumped by every door / prop change (views resync their tiles).
var objects_serial: int = 0
## Tile effects of the player's fight: id -> {"id", "spell", "tiles":
## Array[Vector2i], "terrain", "darkness", "lit", "opaque", "difficult", "barrier"}.
var tile_effects: Dictionary = {}
## terrain_changed: raised walls and opened floor tiles (Vector2i -> true).
var terrain_walls: Dictionary = {}
var terrain_floors: Dictionary = {}
## Bumped when tile effects or terrain change (the terrain overlay redraws).
var terrain_serial: int = 0
## Creatures the player's side dominates: id -> controller id.
var controlled: Dictionary = {}
## Unseen (hidden events) and absent (banished, blinked away) combatants: id -> true.
var hidden_ids: Dictionary = {}
var absent_ids: Dictionary = {}
## The latest REVEAL for this character ({} = none) and the zones it showed:
## zone id -> [{"id", "monster_id", "position"}].
var last_reveal: Dictionary = {}
var revealed_zones: Dictionary = {}
## Cast options: "overchannel" (bool: added to the next damaging 1st-5th
## level wizard spell while the sheet has Overchannel).
var cast_options: Dictionary = {"overchannel": false}

var _unread_log: Array[String] = []
var _map_cache: WalkMap = null
var _map_cache_key: String = ""
var _last_seen_order: Array[String] = []  # latest encounter_started order (any encounter)
var _event_zone_id: String = ""  # "zone_id" of the ENCOUNTER_EVENTS being applied
var _combat_attacks: Array[Dictionary] = []  # snapshot at the start of the encounter
var _pending_smite: int = 0  # slot level of the last smite intent built (divine_smite events lack it)
var _feature_move: String = ""  # a feature whose dash / dodge / disengage event follows (no action spent)


## player_id is the entity id the server gives this client ("p<peer_id>").
func _init(own_player_id: String = "p1") -> void:
	player_id = own_player_id


## Entity id the server uses for a peer's character.
static func player_id_for_peer(peer_id: int) -> String:
	return "%s%d" % [PLAYER_ID_PREFIX, peer_id]


# --- applying results ------------------------------------------------------

## Folds one server result into the state. Malformed results are logged and ignored.
func apply(result: Dictionary) -> void:
	var problem := Messages.validate_result(result)
	if problem != "":
		_log("[bad message] %s" % problem)
		revision += 1
		return
	var kind: String = result["kind"]
	match kind:
		Messages.FLOOR_LOADED:
			_apply_floor_loaded(result)
		Messages.CHARACTER_STATE:
			_apply_character_state(result)
		Messages.EXPLORE_STATE:
			_apply_explore_state(result)
		Messages.ENCOUNTER_EVENTS:
			var enc_id := str(result.get("encounter_id", ""))
			_event_zone_id = str(result.get("zone_id", ""))
			var events: Array = result["events"]
			for ev_v: Variant in events:
				var ev: Dictionary = ev_v
				_apply_event(ev, enc_id)
		Messages.ERROR:
			last_error = str(result["message"])
			_log("[!] %s" % last_error)
		Messages.GAME_OVER:
			mode = Mode.GAME_OVER
			_leave_encounter()
			_log("Your party has fallen. The delve begins anew on floor 1.")
		Messages.FLOOR_CLEARED:
			cleared_floor_id = str(result["floor_id"])
			_leave_encounter()
			if has_next_floor():
				mode = Mode.LOADING
				_log("Floor cleared! You descend the stairs to floor %d." % (floor_number() + 1))
			else:
				mode = Mode.FLOOR_CLEARED
				_log("You descend the stairs. Floor cleared!")
		Messages.SET_CLEARED:
			cleared_set_id = str(result["set_id"])
			mode = Mode.SET_CLEARED
			_leave_encounter()
			_log("%s cleared! You reach the safe zone." % (set_name if not set_name.is_empty() else "The set"))
		Messages.LOOT_GAINED:
			_apply_loot(result)
		Messages.OUT_OF_COMBAT_EVENTS:
			_apply_out_of_combat(result)
		Messages.CHEST_OPENED:
			var chest_id := str(result["chest_id"])
			if chests.has(chest_id):
				var c: Dictionary = chests[chest_id]
				c["opened"] = true
			var opener := str(result.get("entity_id", player_id))
			if opener == player_id:
				_log("You open the chest.")
		Messages.CHEST_REVEALED:
			var raw: Dictionary = result["chest"]
			var known := chests.has(str(raw["id"]))
			var was_locked := known and bool((chests[str(raw["id"])] as Dictionary).get("locked", false))
			_put_chest(raw)
			if not known:
				_log("You discover a hidden chest!")
			elif was_locked and not DictUtil.to_bool(raw.get("locked", false), false):
				_log("The chest's lock clicks open.")
			elif not was_locked and DictUtil.to_bool(raw.get("locked", false), false):
				_log("The chest is sealed shut.")
		Messages.DOOR_CHANGED:
			_apply_door_changed(result)
		Messages.PROP_DESTROYED:
			var prop_id := str(result["prop_id"])
			destroyed_props[prop_id] = true
			objects_serial += 1
			_map_cache = null
			var prop := floor_data.get_prop(prop_id) if floor_data != null else null
			var what := prop.kind if prop != null else str(result.get("kind", "prop"))
			_log("%s %s the %s." % [_who(str(result.get("by", ""))), "smash" if str(result.get("by", "")) == player_id else "smashes", what])
		Messages.ZONE_RESPAWNED:
			var zone_id := str(result["zone_id"])
			var zone := floor_data.get_zone(zone_id) if floor_data != null else null
			var where := zone.name if zone != null and not zone.name.is_empty() else "a cleared room"
			_log("Monsters stir again in %s." % where)
		Messages.REVEAL:
			if str(result["entity_id"]) == player_id:
				_apply_reveal(result)
		Messages.LEVEL_UP_AVAILABLE:
			if str(result["entity_id"]) == player_id:
				var offered: Dictionary = result["choices"]
				level_up_offer = offered.duplicate(true)
				level_up_serial += 1
				var lvl := DictUtil.to_int(level_up_offer.get("new_level", 0), 0)
				_log("Level %d is available! Open the level-up screen to choose." % lvl)
	revision += 1


func _apply_character_state(result: Dictionary) -> void:
	var sheet_dict: Dictionary = result["sheet"]
	sheet = CharacterSheet.from_dict(sheet_dict)
	_adopt_entity_id(result)
	var who := sheet.name if not sheet.name.is_empty() else "You"
	var used := _item_extra(result.get("item_used", null))
	if not used.is_empty():
		_log("%s uses %s." % [who, item_name(used)])
	var healed := DictUtil.to_int(result.get("healed", 0), 0)
	if healed > 0:
		_log("%s regains %d HP." % [sheet.name, healed])
	var temp := DictUtil.to_int(result.get("temp_hp", 0), 0)
	if temp > 0:
		_log("%s gains %d temporary HP." % [who, temp])
	var equipped_id := _item_extra(result.get("equipped", null))
	if not equipped_id.is_empty():
		_log("%s equips %s." % [who, item_name(equipped_id)])
	var unequipped_id := _item_extra(result.get("unequipped", null))
	if not unequipped_id.is_empty():
		_log("%s puts away %s." % [who, item_name(unequipped_id)])
	var dropped_id := _item_extra(result.get("dropped", null))
	if not dropped_id.is_empty():
		var dropped_v: Variant = result["dropped"]
		var dropped_qty := 1
		if typeof(dropped_v) == TYPE_DICTIONARY:
			var dd: Dictionary = dropped_v
			dropped_qty = DictUtil.to_int(dd.get("qty", 1), 1)
		_log("%s drops %s." % [who, ClientState.quantity_text(item_name(dropped_id), dropped_qty, dropped_id == CharacterSheet.GOLD_ITEM)])
	var floor_xp := DictUtil.to_int(result.get("floor_clear_xp", 0), 0)
	if result.has("xp_gained") or result.has("levels_gained") or floor_xp > 0:
		last_xp_gained = DictUtil.to_int(result.get("xp_gained", floor_xp), floor_xp)
		last_levels_gained = DictUtil.to_int(result.get("levels_gained", 0), 0)
		if floor_xp > 0:
			_log("Floor-clear bonus: gained %d XP." % maxi(floor_xp, last_xp_gained))
		elif last_xp_gained > 0:
			_log("Gained %d XP." % last_xp_gained)
		if last_levels_gained > 0:
			_log("Level up! Now level %d." % sheet.level)
	if result.has("leveled_to"):
		last_leveled_to = DictUtil.to_int(result["leveled_to"], sheet.level)
		level_up_offer = {}
		_log("Level up! %s is now level %d." % [who, last_leveled_to])
	if not level_up_offer.is_empty() and sheet.pending_levels() <= 0:
		level_up_offer = {}  # stale: nothing left to choose
	if typeof(result.get("reaction_policy")) == TYPE_DICTIONARY:
		reaction_policy = (result["reaction_policy"] as Dictionary).duplicate()
		_log("Reaction settings saved.")
	if typeof(result.get("companion_dismissed")) == TYPE_DICTIONARY:
		var gone: Dictionary = result["companion_dismissed"]
		_log("%s dismisses the %s." % [who, monster_name(str(gone.get("monster", "")))])
	var recovered := DictUtil.to_string_array(result.get("slots_recovered", []))
	if not recovered.is_empty():
		var levels: PackedStringArray = []
		for lvl in recovered:
			levels.append(ClientState.ordinal(DictUtil.to_int(lvl, 0)))
		_log("%s recovers spell slots: %s." % [who, ", ".join(levels)])
	if typeof(result.get("recovery_error")) == TYPE_STRING:
		_log("No slots recovered: %s." % str(result["recovery_error"]))
	if DictUtil.to_bool(result.get("long_rest", false), false):
		_log("You take a long rest in the safe zone: HP and Hit Dice restored.")
	if typeof(result.get("light_level")) == TYPE_STRING:
		light_level = str(result["light_level"])
		_log("Light surrounds you (%s)." % light_level)
	if typeof(result.get("door_unlocked")) == TYPE_DICTIONARY:
		var du: Dictionary = result["door_unlocked"]
		if str(du.get("method", "")) == Messages.UNLOCK_TOOLS:
			_log("%s picks the lock (%d vs DC %d)." % [who, DictUtil.to_int(du.get("total", 0), 0), DictUtil.to_int(du.get("dc", 0), 0)])
		else:
			_log("%s unlocks the door with the key." % who)
	if typeof(result.get("unlock_failed")) == TYPE_DICTIONARY:
		var uf: Dictionary = result["unlock_failed"]
		_log("%s fails to pick the lock (%d vs DC %d)." % [who, DictUtil.to_int(uf.get("total", 0), 0), DictUtil.to_int(uf.get("dc", 0), 0)])
	if entities.has(player_id):
		var e: Dictionary = entities[player_id]
		e["hp"] = sheet.current_hp
		e["down"] = sheet.is_unconscious()
		e["dead"] = sheet.dead
		e["name"] = sheet.name
		e["max_hp"] = sheet.max_hp
		e["class_id"] = sheet.class_id
	if selected_attack >= available_attacks().size():
		selected_attack = 0


## An item id from a CHARACTER_STATE extra: "id", {"item": id} or true/other ("").
func _item_extra(v: Variant) -> String:
	if typeof(v) == TYPE_STRING:
		return str(v)
	if typeof(v) == TYPE_DICTIONARY:
		var d: Dictionary = v
		return str(d.get("item", ""))
	return ""


func _apply_loot(result: Dictionary) -> void:
	if str(result["entity_id"]) != player_id:
		return
	var items: Array = result["items"]
	last_loot.clear()
	var parts: PackedStringArray = []
	for it_v: Variant in items:
		var it: Dictionary = it_v
		var id := str(it.get("item", ""))
		var qty := DictUtil.to_int(it.get("qty", 1), 1)
		last_loot.append({"item": id, "qty": qty})
		parts.append(ClientState.quantity_text(item_name(id), qty, id == CharacterSheet.GOLD_ITEM))
	var source := str(result.get("source", ""))
	var where: String = LOOT_SOURCES.get(source, "")
	if parts.is_empty():
		_log("Nothing of value %s." % (where if not where.is_empty() else "here"))
	else:
		_log("Loot%s: %s." % [(" " + where) if not where.is_empty() else "", ", ".join(parts)])


## "Potion of Healing x2", "12 gold", "Longsword".
static func quantity_text(item_display: String, qty: int, is_gold: bool = false) -> String:
	if is_gold:
		return "%d gold" % qty
	return item_display if qty == 1 else "%s x%d" % [item_display, qty]


func _put_chest(raw: Dictionary) -> void:
	var id := str(raw.get("id", ""))
	if id.is_empty() or not Messages.is_position(raw.get("position")):
		return
	chests[id] = {
		"id": id,
		"position": Messages.to_position(raw["position"]),
		"hidden": DictUtil.to_bool(raw.get("hidden", false), false),
		"opened": DictUtil.to_bool(raw.get("opened", false), false),
		"locked": DictUtil.to_bool(raw.get("locked", false), false),
	}


## A (new) floor: replaces the old one and everything that lived on it.
func _apply_floor_loaded(result: Dictionary) -> void:
	var floor_dict: Dictionary = result["floor"]
	var first := floor_data == null
	floor_data = FloorData.from_dict(floor_dict)
	floor_serial += 1
	_adopt_entity_id(result)
	set_id = str(result.get("set_id", set_id))
	set_name = str(result.get("set_name", set_name))
	floor_index = maxi(0, DictUtil.to_int(result.get("floor_index", floor_index), floor_index))
	floor_count = maxi(1, DictUtil.to_int(result.get("floor_count", floor_count), floor_count))
	if not first:
		_leave_encounter()
		_last_seen_order.clear()
		initiatives.clear()
		last_winning_team = -1
		entities.clear()
	if mode == Mode.LOADING or mode == Mode.FLOOR_CLEARED or mode == Mode.COMBAT:
		mode = Mode.EXPLORING
	chests.clear()
	targeting = {}
	if typeof(result.get("chests")) == TYPE_ARRAY:
		var listed: Array = result["chests"]
		for c_v: Variant in listed:
			if typeof(c_v) == TYPE_DICTIONARY:
				_put_chest(c_v)
	else:
		for c in floor_data.chests:
			if not c.hidden:
				chests[c.id] = {"id": c.id, "position": c.position, "hidden": false, "opened": false, "locked": c.locked}
	door_states.clear()
	door_info.clear()
	destroyed_props.clear()
	revealed_zones.clear()
	last_reveal = {}
	objects_serial += 1
	_map_cache = null
	for d in floor_data.doors:
		door_states[d.id] = d.state
		door_info[d.id] = {"dc": d.dc, "keyed": not d.key_item.is_empty()}
	if typeof(result.get("doors")) == TYPE_ARRAY:
		for d_v: Variant in (result["doors"] as Array):
			if typeof(d_v) == TYPE_DICTIONARY:
				var dd: Dictionary = d_v
				door_states[str(dd.get("id", ""))] = str(dd.get("state", "closed"))
				door_info[str(dd.get("id", ""))] = {"dc": DictUtil.to_int(dd.get("dc", 0), 0), "keyed": dd.get("keyed", false) == true}
	if typeof(result.get("props")) == TYPE_ARRAY:
		for p_v: Variant in (result["props"] as Array):
			if typeof(p_v) == TYPE_DICTIONARY and (p_v as Dictionary).get("destroyed", false) == true:
				destroyed_props[str((p_v as Dictionary).get("id", ""))] = true
	landing_id = str(result.get("landing_id", ""))
	floor_light = str(result.get("light", "bright"))
	light_level = floor_light
	var where := landing_text()
	_log("You arrive on %s%s." % [floor_label(), (" at " + where) if not where.is_empty() else ""])


## Log lines added since the last call (oldest first).
func drain_log() -> Array[String]:
	var out: Array[String] = _unread_log.duplicate()
	_unread_log.clear()
	return out


func _apply_explore_state(result: Dictionary) -> void:
	tick = DictUtil.to_int(result["tick"], tick)
	var next := {}
	var raw_entities: Array = result["entities"]
	for raw_v: Variant in raw_entities:
		var raw: Dictionary = raw_v
		var id := str(raw["id"])
		var e: Dictionary = entities[id] if entities.has(id) else _new_entity(id, str(raw["kind"]))
		e["kind"] = str(raw["kind"])
		var name_v: Variant = raw.get("name", raw.get("display_name", null))
		if typeof(name_v) == TYPE_STRING and not str(name_v).is_empty():
			e["name"] = str(name_v)
		# During the player's fight, combat events own the combatants' positions.
		if not (in_encounter and order.has(id)):
			e["position"] = Messages.to_position(raw["position"])
		if DictUtil.is_number(raw.get("hp")):
			e["hp"] = DictUtil.to_int(raw["hp"], -1)
			e["down"] = int(e["hp"]) == 0
		if DictUtil.is_number(raw.get("max_hp")):
			e["max_hp"] = DictUtil.to_int(raw["max_hp"], -1)
		if typeof(raw.get("dead")) == TYPE_BOOL:
			e["dead"] = bool(raw["dead"])
		var monster_id := str(raw.get("monster_id", ""))
		if not monster_id.is_empty():
			e["monster_id"] = monster_id
		if typeof(raw.get("class_id")) == TYPE_STRING and not str(raw["class_id"]).is_empty():
			e["class_id"] = str(raw["class_id"])
		if id == player_id and sheet != null:
			e["class_id"] = sheet.class_id
		if id == player_id and sheet != null and not DictUtil.is_number(raw.get("hp")):
			e["hp"] = sheet.current_hp
			e["max_hp"] = sheet.max_hp
			e["down"] = sheet.is_unconscious()
			e["dead"] = sheet.dead
		if bool(e["dead"]):
			e["down"] = false
		next[id] = e
	# Combatants the server leaves out while they fight stay on screen.
	if in_encounter:
		for id: String in order:
			if not next.has(id) and entities.has(id):
				next[id] = entities[id]
	entities = next


func _apply_event(ev: Dictionary, enc_id: String) -> void:
	var kind := str(ev.get("kind", ""))
	if in_encounter and not encounter_id.is_empty() and not enc_id.is_empty() and enc_id != encounter_id:
		# Another encounter's events: keep positions and health current, nothing else.
		if kind in ["moved", "damage", "combatant_joined", "heal", "pushed", "destroyed"]:
			_apply_world_effect(ev)
		return
	match kind:
		"combatant_joined":
			var id := str(ev.get("id", ""))
			_apply_world_effect(ev)
			_mark_ally(ev)
			if DictUtil.to_bool(ev.get("illusion", false), false):
				var ie := _entity_or_new(id)
				ie["illusion"] = true
			initiatives[id] = DictUtil.to_int(ev.get("initiative", 0), 0)
			if in_encounter:
				if not order.has(id):
					_insert_by_initiative(id)
					_log("%s joins the fight." % display_name(id))
			elif id == player_id and not _last_seen_order.is_empty():
				# Walked into a fight that is already running.
				_enter_encounter(_last_seen_order, enc_id)
				_insert_by_initiative(id)
				_log("You join the fight!")
			elif not _last_seen_order.is_empty() and not _last_seen_order.has(id):
				_last_seen_order.append(id)
		"encounter_started":
			var started: Array[String] = []
			var raw_order: Array = ev.get("order", [])
			for id_v: Variant in raw_order:
				started.append(str(id_v))
			_last_seen_order.assign(started)
			if started.has(player_id):
				_enter_encounter(started, enc_id)
				encounter_light = str(ev.get("light", "bright"))
				_log("Combat! Initiative: %s" % ", ".join(_names(order)))
				if encounter_light != "bright":
					_log("The fight begins in %s light." % encounter_light)
		"round_started":
			if in_encounter:
				round_number = DictUtil.to_int(ev.get("round", round_number), round_number)
				_log("-- Round %d --" % round_number)
		"turn_started":
			var actor := str(ev.get("actor", ""))
			_remove_status(actor, "dodge")  # Dodge lasts until the dodger's next turn
			_remove_status(actor, "reckless_attack")  # so does Reckless Attack
			if in_encounter and order.has(actor):
				current_actor = actor
				round_number = DictUtil.to_int(ev.get("round", round_number), round_number)
				if actor == player_id:
					movement_remaining = 0 if is_immobilized(player_id) else speed_tiles()
					action_used = false
					bonus_action_used = false
					attack_action_taken = false
					attacks_remaining = 0
					bonus_attacks_remaining = 0
					bonus_attack_source = ""
					action_surged = false
					rage_started_this_turn = false
					reaction_used = false
					_feature_move = ""
					_log("Your turn.")
		"turn_ended":
			_count_down_conditions(str(ev.get("actor", "")))
			if in_encounter and str(ev.get("actor", "")) == current_actor:
				current_actor = ""
		"moved":
			_apply_world_effect(ev)
			if in_encounter and str(ev.get("actor", "")) == player_id:
				movement_remaining = maxi(0, movement_remaining - 1)
		"dash":
			var actor := str(ev.get("actor", ""))
			if actor == player_id:
				movement_remaining += speed_tiles()
				if not _take_feature_move():
					action_used = true
			_log("%s dashes." % display_name(actor))
		"dodge":
			var actor := str(ev.get("actor", ""))
			if actor == player_id and not _take_feature_move():
				action_used = true
			_add_status(actor, "dodge")
			_log("%s takes the Dodge action." % display_name(actor))
		"disengage":
			var actor := str(ev.get("actor", ""))
			if actor == player_id and not _take_feature_move():
				action_used = true
			_log("%s disengages." % display_name(actor))
		"opportunity_attack":
			_log("%s makes an opportunity attack on %s!" % [display_name(str(ev.get("attacker", ""))), display_name(str(ev.get("target", "")))])
		"attack":
			var attacker := str(ev.get("attacker", ""))
			var attack_kind := str(ev.get("attack_kind", "melee"))
			if attacker == player_id and current_actor == player_id:
				if DictUtil.to_bool(ev.get("bonus", false), false):
					if bonus_attacks_remaining > 0:
						bonus_attacks_remaining -= 1
					else:
						bonus_action_used = true
				elif attack_kind != "spell":
					if action_used and attack_action_taken and attacks_remaining > 0:
						attacks_remaining -= 1
					else:
						action_used = true
						attack_action_taken = true
						attacks_remaining = attacks_per_action() - 1
				if attack_kind != "spell":
					attack_options["smite"] = 0  # one-shot options
					attack_options["stun"] = false
					attack_options["quivering_palm"] = false
					attack_options["hurl_through_hell"] = false
					attack_options["via_familiar"] = false
			var consumed := str(ev.get("consumed", ""))
			if attacker == player_id and sheet != null and not consumed.is_empty():
				sheet.remove_item(consumed, 1, _content())
			# The attack used up the guiding bolt mark on the target and the attacker's mockery.
			_remove_status(str(ev.get("target", "")), "guiding_bolt_mark")
			_remove_status(attacker, "mockery")
			_log(_attack_line(ev))
		"damage":
			_apply_world_effect(ev)
			_log(_damage_line(ev))
		"death_save":
			_apply_death_save(ev)
		"cast":
			_apply_cast(ev)
		"save":
			_log(_save_line(ev))
		"heal":
			_apply_world_effect(ev)
			_log(_heal_line(ev))
		"temp_hp":
			var target := str(ev.get("target", ""))
			var after := DictUtil.to_int(ev.get("temp_hp_after", 0), 0)
			if target == player_id and sheet != null:
				sheet.temp_hp = after
			_log("%s gains %d temporary HP." % [display_name(target), DictUtil.to_int(ev.get("amount", 0), 0)])
		"item_used":
			var actor := str(ev.get("actor", ""))
			var item := str(ev.get("item", ""))
			if actor == player_id:
				var def := item_def(item)
				if current_actor == player_id:
					if def != null and def.use_action == "bonus_action":
						bonus_action_used = true
					else:
						action_used = true
				if sheet != null:
					sheet.remove_item(item, 1, _content())
			_log("%s uses %s." % [display_name(actor), item_name(item)])
		"feature_used":
			_apply_feature_used(ev)
		"inspiration_used":
			var actor := str(ev.get("actor", ""))
			_remove_status(actor, "bardic_inspiration")
			_log("%s adds a Bardic Inspiration die: d%d rolled %d." % [display_name(actor),
				DictUtil.to_int(ev.get("die", 0), 0), DictUtil.to_int(ev.get("roll", 0), 0)])
		"effect_applied":
			var target := str(ev.get("target", ""))
			var effect := str(ev.get("effect", ""))
			_add_status(target, effect)
			if target == player_id:
				if effect == "rage" and current_actor == player_id:
					rage_started_this_turn = true
				elif effect == "pact_weapon" and sheet != null:
					var index := DictUtil.to_int(ev.get("attack_index", _combat_attacks.size()), _combat_attacks.size())
					if index >= _combat_attacks.size():
						_combat_attacks.append(Encounter.pact_weapon_attack(sheet))
			_log(_effect_line(target, effect, true))
		"effect_ended":
			var target := str(ev.get("target", ""))
			var effect := str(ev.get("effect", ""))
			_remove_status(target, effect)
			if effect == "rage":
				_remove_status(target, "frenzy")
			_log(_effect_line(target, effect, false))
		"condition_applied":
			_apply_condition_applied(ev)
		"condition_ended":
			_apply_condition_ended(ev)
		"concentration_started":
			var actor := str(ev.get("actor", ""))
			concentration[actor] = str(ev.get("spell", ""))
			_log("%s is concentrating on %s." % [display_name(actor), spell_name(str(ev.get("spell", "")))])
		"concentration_check":
			var actor := str(ev.get("actor", ""))
			_log("%s makes a concentration check: %d vs DC %d, %s." % [display_name(actor),
				DictUtil.to_int(ev.get("total", 0), 0), DictUtil.to_int(ev.get("dc", 0), 0),
				"holds" if DictUtil.to_bool(ev.get("success", false), false) else "fails"])
		"concentration_ended":
			var actor := str(ev.get("actor", ""))
			concentration.erase(actor)
			var reason := str(ev.get("reason", ""))
			_log("%s loses concentration on %s%s." % [display_name(actor), spell_name(str(ev.get("spell", ""))),
				(" (%s)" % CONCENTRATION_REASONS.get(reason, reason)) if not reason.is_empty() else ""])
		"area_effect":
			_apply_area_effect(ev)
		"damage_reduced":
			var actor := str(ev.get("actor", ""))
			if actor == player_id:
				reaction_used = true
			_log("%s uses %s: %d damage avoided." % [display_name(actor), ClientState.feature_name(str(ev.get("feature", ""))),
				DictUtil.to_int(ev.get("amount", 0), 0)])
		"reaction_used":
			# Forward compatible: round B cores report each reaction they spend.
			var actor := str(ev.get("actor", ""))
			if actor == player_id:
				reaction_used = true
			_log("%s reacts: %s." % [display_name(actor), ClientState.feature_name(str(ev.get("reaction", "reaction")))])
		"pushed":
			_apply_world_effect(ev)
			_log("%s is pushed back." % display_name(str(ev.get("target", ""))))
		"destroyed":
			_apply_world_effect(ev)
			_log("%s is destroyed by %s's %s!" % [display_name(str(ev.get("target", ""))), display_name(str(ev.get("source", ""))),
				ClientState.feature_name(str(ev.get("feature", "destroy_undead")))])
		"summoned":
			var id := str(ev.get("id", ""))
			var monster := str(ev.get("monster", ""))
			if entities.has(id) and not monster.is_empty():
				var e: Dictionary = entities[id]
				e["monster_id"] = monster
			if in_encounter or str(ev.get("caster", "")) == player_id:
				_log("%s's %s appears." % [display_name(str(ev.get("caster", ""))), monster_name(monster) if not monster.is_empty() else display_name(id)])
		"summon_ended":
			var id := str(ev.get("id", ""))
			if in_encounter:
				_log("%s %s." % [display_name(id), "falls" if str(ev.get("reason", "")) == "dropped" else "vanishes"])
		"combatant_removed":
			var id := str(ev.get("id", ""))
			order.erase(id)
			_last_seen_order.erase(id)
			if id == player_id:
				_leave_encounter()
		"encounter_ended":
			var winner := DictUtil.to_int(ev.get("winning_team", -1), -1)
			_last_seen_order.clear()
			if in_encounter:
				last_winning_team = winner
				_leave_encounter()
				if winner == TEAM_PLAYERS:
					_log("Victory! The fight is over.")
				else:
					_log("The fight is over.")
		_:
			_apply_round_c_event(ev)  # round C kinds (others are ignored)


## A combatant_joined with an "owner" (summons, companions) is an ally: it
## keeps its name, owner and hit points and is never a hostile.
func _mark_ally(ev: Dictionary) -> void:
	var owner := str(ev.get("owner", ""))
	if owner.is_empty():
		return
	var e := _entity_or_new(str(ev.get("id", "")))
	e["kind"] = KIND_ALLY
	e["owner"] = owner
	if typeof(ev.get("name")) == TYPE_STRING and not str(ev["name"]).is_empty():
		e["name"] = str(ev["name"])
	if DictUtil.is_number(ev.get("hp")):
		e["hp"] = DictUtil.to_int(ev["hp"], -1)
	if DictUtil.is_number(ev.get("max_hp")):
		e["max_hp"] = DictUtil.to_int(ev["max_hp"], -1)


## OUT_OF_COMBAT_EVENTS for this character: logs the cast and what it did
## (the sheet itself changes with the CHARACTER_STATE that follows).
func _apply_out_of_combat(result: Dictionary) -> void:
	if str(result["entity_id"]) != player_id:
		return
	var events: Array = result["events"]
	for ev_v: Variant in events:
		var ev: Dictionary = ev_v
		match str(ev["kind"]):
			"cast":
				var spell_id := str(ev.get("spell", ""))
				var slot := DictUtil.to_int(ev.get("slot_level", 0), 0)
				var timing := ClientState.casting_time_text(str(ev.get("casting_time", "action")), DictUtil.to_bool(ev.get("ritual", false), false))
				var line := "%s casts %s" % [display_name(str(ev.get("actor", player_id))), spell_name(spell_id)]
				var notes: PackedStringArray = []
				if slot > 0:
					notes.append("level %d slot" % slot)
				if not ClientState.is_quick_casting_time(str(ev.get("casting_time", "action"))):
					notes.append("%s, done at once" % timing)
				if not notes.is_empty():
					line += " (%s)" % ", ".join(notes)
				_log(line + ".")
			"companion_summoned":
				var count := DictUtil.to_int(ev.get("count", 1), 1)
				var what := monster_name(str(ev.get("monster", "")))
				_log("%s %s at your side: it will join your next fight." % [ClientState.quantity_text(what, count),
					"stands" if count == 1 else "stand"])
			"heal":
				_log("%s regains %d HP (%d HP)." % [display_name(str(ev.get("target", ""))), DictUtil.to_int(ev.get("amount", 0), 0),
					DictUtil.to_int(ev.get("hp_after", 0), 0)])
			"temp_hp":
				_log("%s gains %d temporary HP." % [display_name(str(ev.get("target", ""))), DictUtil.to_int(ev.get("amount", 0), 0)])
			"revived":
				_log("%s returns to life with %d HP!" % [display_name(str(ev.get("target", ""))), DictUtil.to_int(ev.get("hp", 1), 1)])
			"restored":
				var removed := DictUtil.to_string_array(ev.get("conditions_removed", []))
				var line := "%s is restored" % display_name(str(ev.get("target", "")))
				if not removed.is_empty():
					line += ": no longer %s" % ", ".join(removed)
				_log(line + " (exhaustion %d)." % DictUtil.to_int(ev.get("exhaustion", 0), 0))
			"buff":
				_log("%s is protected by %s (AC %d)." % [display_name(str(ev.get("target", ""))),
					str(ev.get("buff", "")).replace("_", " ").capitalize(), DictUtil.to_int(ev.get("ac", 0), 0)])
			"no_effect":
				_log("%s has no effect in the delve: %s." % [spell_name(str(ev.get("spell", ""))), str(ev.get("reason", "nothing here answers it"))])
			"lingering_added":
				var n := DictUtil.to_int(ev.get("encounters", 1), 1)
				_log("%s holds on %s for %s." % [spell_name(str(ev.get("spell", ""))), display_name(str(ev.get("target", player_id))),
					"the rest of the delve" if n < 0 else ("the next fight" if n == 1 else "the next %d fights" % n)])


## Position / health changes that hold no matter whose encounter they belong to.
func _apply_world_effect(ev: Dictionary) -> void:
	var kind := str(ev.get("kind", ""))
	match kind:
		"combatant_joined":
			var e := _entity_or_new(str(ev.get("id", "")))
			if Messages.is_position(ev.get("position")):
				e["position"] = Messages.to_position(ev["position"])
		"moved":
			var e := _entity_or_new(str(ev.get("actor", "")))
			if Messages.is_position(ev.get("to")):
				e["position"] = Messages.to_position(ev["to"])
		"pushed":
			var e := _entity_or_new(str(ev.get("target", "")))
			if Messages.is_position(ev.get("to")):
				e["position"] = Messages.to_position(ev["to"])
		"destroyed":
			var e := _entity_or_new(str(ev.get("target", "")))
			e["dead"] = true
			e["down"] = false
			e["hp"] = 0
		"damage":
			var target := str(ev.get("target", ""))
			var e := _entity_or_new(target)
			var hp := DictUtil.to_int(ev.get("hp_after", 0), 0)
			var died := DictUtil.to_bool(ev.get("died", false), false)
			e["hp"] = hp
			e["dead"] = died
			e["down"] = hp == 0 and not died
			if target == player_id and sheet != null:
				sheet.current_hp = hp
				if typeof(ev.get("temp_hp_after")) != TYPE_NIL:
					sheet.temp_hp = DictUtil.to_int(ev["temp_hp_after"], sheet.temp_hp)
				if died:
					sheet.dead = true
				elif hp == 0 and DictUtil.to_bool(ev.get("dropped", false), false):
					sheet.reset_death_saves()
		"heal":
			var target := str(ev.get("target", ""))
			var e := _entity_or_new(target)
			var hp := DictUtil.to_int(ev.get("hp_after", 0), 0)
			e["hp"] = hp
			if hp > 0:
				e["down"] = false
			if target == player_id and sheet != null:
				sheet.current_hp = hp
				if DictUtil.to_bool(ev.get("revived", false), false) or hp > 0:
					sheet.reset_death_saves()


func _apply_death_save(ev: Dictionary) -> void:
	var actor := str(ev.get("actor", ""))
	var e := _entity_or_new(actor)
	var died := DictUtil.to_bool(ev.get("died", false), false)
	var regained := DictUtil.to_bool(ev.get("regained", false), false)
	var stable := DictUtil.to_bool(ev.get("stable", false), false)
	var successes := DictUtil.to_int(ev.get("successes", 0), 0)
	var failures := DictUtil.to_int(ev.get("failures", 0), 0)
	if died:
		e["dead"] = true
		e["down"] = false
		e["hp"] = 0
	elif regained:
		e["down"] = false
		e["hp"] = 1
	if actor == player_id and sheet != null:
		sheet.death_save_successes = successes
		sheet.death_save_failures = failures
		sheet.stable = stable
		if died:
			sheet.dead = true
			sheet.current_hp = 0
		elif regained:
			sheet.current_hp = 1
	var who := display_name(actor)
	var natural := DictUtil.to_int(ev.get("natural", 0), 0)
	if died:
		_log("%s fails a death saving throw (rolled %d) and dies." % [who, natural])
	elif regained:
		_log("%s rolls a natural 20 on a death saving throw and regains 1 HP!" % who)
	elif stable:
		_log("%s is stable (rolled %d)." % [who, natural])
	else:
		_log("%s death saving throw: rolled %d (%d successes, %d failures)." % [who, natural, successes, failures])


func _enter_encounter(new_order: Array[String], enc_id: String) -> void:
	in_encounter = true
	encounter_id = enc_id
	order.assign(new_order)
	mode = Mode.COMBAT if mode == Mode.EXPLORING or mode == Mode.LOADING else mode
	current_actor = ""
	round_number = 0
	movement_remaining = 0
	action_used = false
	bonus_action_used = false
	attack_action_taken = false
	_reset_progression_combat_state()
	_reset_round_c_combat_state()
	statuses.clear()
	targeting = {}
	_combat_attacks = _attacks_from_sheet()
	region = Rect2i()
	if floor_data != null:
		var zone := floor_data.get_zone(_event_zone_id) if not _event_zone_id.is_empty() else null
		if zone == null:
			zone = floor_data.zone_at(player_position())
		if zone != null:
			region = zone.rect


func _leave_encounter() -> void:
	in_encounter = false
	encounter_id = ""
	order.clear()
	current_actor = ""
	round_number = 0
	movement_remaining = 0
	action_used = false
	bonus_action_used = false
	attack_action_taken = false
	_reset_progression_combat_state()
	_reset_round_c_combat_state()
	statuses.clear()
	targeting = {}
	_combat_attacks.clear()
	region = Rect2i()
	if mode == Mode.COMBAT:
		mode = Mode.EXPLORING
	# The server removes the slain; drop them now rather than at the next explore tick.
	for id: String in entities.keys():
		var e: Dictionary = entities[id]
		if bool(e["dead"]) and str(e["kind"]) == KIND_MONSTER:
			entities.erase(id)


## Mid-fight joiners: placed by initiative among the known combatants (the
## server's tracker is authoritative; this only orders the HUD list).
func _insert_by_initiative(id: String) -> void:
	var mine: int = initiatives.get(id, 0)
	for i in range(order.size()):
		var other: int = initiatives.get(order[i], 0)
		if mine > other:
			order.insert(i, id)
			return
	order.append(id)


func _new_entity(id: String, kind: String) -> Dictionary:
	return {"id": id, "kind": kind, "name": "", "position": Vector2i.ZERO, "hp": -1, "max_hp": -1, "down": false, "dead": false}


## The server may name this client's entity explicitly ("entity_id").
func _adopt_entity_id(result: Dictionary) -> void:
	var id_v: Variant = result.get("entity_id", null)
	if typeof(id_v) == TYPE_STRING and not str(id_v).is_empty():
		player_id = str(id_v)


func _entity_or_new(id: String) -> Dictionary:
	if not entities.has(id):
		entities[id] = _new_entity(id, guess_kind(id))
	var e: Dictionary = entities[id]
	return e


## Kind of an id never seen in EXPLORE_STATE: "p<digits>" is a player.
func guess_kind(id: String) -> String:
	if id == player_id:
		return KIND_PLAYER
	if id.begins_with(PLAYER_ID_PREFIX) and id.substr(PLAYER_ID_PREFIX.length()).is_valid_int():
		return KIND_PLAYER
	return KIND_MONSTER


func _log(line: String) -> void:
	log_lines.append(line)
	_unread_log.append(line)
	if log_lines.size() > MAX_LOG_LINES:
		log_lines.remove_at(0)


func _attack_line(ev: Dictionary) -> String:
	var attacker := display_name(str(ev.get("attacker", "")))
	var target := display_name(str(ev.get("target", "")))
	var weapon := str(ev.get("attack_name", "an attack"))
	var total := DictUtil.to_int(ev.get("total", 0), 0)
	var ac := DictUtil.to_int(ev.get("target_ac", 0), 0)
	var mode_name := str(ev.get("advantage", "normal"))
	var rolls := ""
	if typeof(ev.get("d20s")) == TYPE_ARRAY:
		var d20s: Array = ev["d20s"]
		if d20s.size() > 1:
			var parts: PackedStringArray = []
			for r: Variant in d20s:
				parts.append(str(DictUtil.to_int(r, 0)))
			rolls = " [%s, %s]" % ["/".join(parts), mode_name]
	var outcome := "misses"
	if DictUtil.to_bool(ev.get("critical", false), false):
		outcome = "CRITS"
	elif DictUtil.to_bool(ev.get("hit", false), false):
		outcome = "hits"
	return "%s attacks %s with %s: %d vs AC %d%s, %s." % [attacker, target, weapon, total, ac, rolls, outcome]


func _damage_line(ev: Dictionary) -> String:
	var target := display_name(str(ev.get("target", "")))
	var amount := DictUtil.to_int(ev.get("amount", 0), 0)
	var dtype := str(ev.get("type", ""))
	var line := "%s takes %d %s damage (%d HP left)." % [target, amount, dtype, DictUtil.to_int(ev.get("hp_after", 0), 0)]
	if DictUtil.to_bool(ev.get("died", false), false):
		line += " %s dies!" % target
	elif DictUtil.to_bool(ev.get("dropped", false), false):
		line += " %s falls unconscious!" % target
	return line.replace("  ", " ")


func _apply_cast(ev: Dictionary) -> void:
	var actor := str(ev.get("actor", ""))
	var spell_id := str(ev.get("spell", ""))
	var spell := spell_def(spell_id)
	var slot := DictUtil.to_int(ev.get("slot_level", 0), 0)
	var meta := DictUtil.to_string_array(ev.get("metamagic", []))
	if actor == player_id:
		if current_actor == player_id:
			if (spell != null and spell.uses_bonus_action()) or meta.has("quickened_spell"):
				bonus_action_used = true
			else:
				action_used = true
		if sheet != null and slot >= 1 and slot <= sheet.spell_slots.size():
			sheet.spell_slots[slot - 1] = maxi(0, sheet.spell_slots[slot - 1] - 1)
		if sheet != null and not meta.is_empty() and spell != null:
			var cost := 0
			for m in meta:
				cost += ClientState.metamagic_cost(m, spell)
			sheet.class_resources["sorcery_points"] = maxi(0, sheet.class_resource("sorcery_points") - cost)
	var target := str(ev.get("target", actor))
	var line := "%s casts %s" % [display_name(actor), spell.display_name if spell != null else spell_id.capitalize()]
	if not target.is_empty() and target != actor:
		line += " at %s" % display_name(target)
	if slot > 0:
		line += " (level %d slot)" % slot
	if not meta.is_empty():
		var names: PackedStringArray = []
		for m in meta:
			names.append(ClientState.metamagic_name(m))
		line += " [%s]" % ", ".join(names)
	_log(line + ".")


func _save_line(ev: Dictionary) -> String:
	var target := display_name(str(ev.get("target", "")))
	var natural := DictUtil.to_int(ev.get("natural", 0), 0)
	var total := DictUtil.to_int(ev.get("total", 0), 0)
	var dc := DictUtil.to_int(ev.get("dc", 0), 0)
	var ability := str(ev.get("ability", ""))
	var outcome := "succeeds" if DictUtil.to_bool(ev.get("success", false), false) else "fails"
	if natural == 0:
		return "%s automatically fails the %s saving throw (DC %d)." % [target, ability, dc]
	return "%s makes a %s saving throw: %d vs DC %d, %s." % [target, ability, total, dc, outcome]


func _heal_line(ev: Dictionary) -> String:
	var target := display_name(str(ev.get("target", "")))
	var amount := DictUtil.to_int(ev.get("amount", 0), 0)
	var line := "%s regains %d HP (%d HP)." % [target, amount, DictUtil.to_int(ev.get("hp_after", 0), 0)]
	if DictUtil.to_bool(ev.get("revived", false), false):
		line += " %s is back on their feet!" % target
	return line


func _effect_line(target: String, effect: String, applied: bool) -> String:
	var who := display_name(target)
	var tag: String = STATUS_TAGS.get(effect, effect.replace("_", " "))
	if applied:
		return "%s is now %s." % [who, tag]
	return "%s is no longer %s." % [who, tag]


func _add_status(id: String, effect: String) -> void:
	if id.is_empty() or effect.is_empty():
		return
	if not statuses.has(id):
		statuses[id] = [] as Array[String]
	var list: Array[String] = statuses[id]
	if not list.has(effect):
		list.append(effect)


func _remove_status(id: String, effect: String) -> void:
	if statuses.has(id):
		var list: Array[String] = statuses[id]
		list.erase(effect)


func _reset_progression_combat_state() -> void:
	conditions.clear()
	concentration.clear()
	attacks_remaining = 0
	bonus_attacks_remaining = 0
	bonus_attack_source = ""
	action_surged = false
	rage_started_this_turn = false
	reaction_used = false
	last_area = {}
	_pending_smite = 0
	_feature_move = ""
	attack_options["smite"] = 0
	attack_options["stun"] = false


## True (and forgets it) when the dash / dodge / disengage event being applied
## came from the player's feature (Cunning Action, Step of the Wind, Patient
## Defense): no action is spent.
func _take_feature_move() -> bool:
	if _feature_move.is_empty():
		return false
	_feature_move = ""
	return true


## turn_ended of `actor`: its own "rounds" / "until its turn end" conditions
## and the "until the source's next turn" conditions it imposed count down
## (the core then ends those at 0 with condition_ended).
func _count_down_conditions(actor: String) -> void:
	for id: Variant in conditions.keys():
		var list: Array[Dictionary] = conditions[id]
		for entry in list:
			var duration: Dictionary = entry.get("duration", {})
			var kind := str(duration.get("type", ""))
			var own := str(id) == actor and kind in [Conditions.DURATION_TARGET_TURN_END, Conditions.DURATION_ROUNDS]
			var imposed := str(entry.get("source", "")) == actor and kind == Conditions.DURATION_SOURCE_NEXT_TURN
			if own or imposed:
				entry["turns_left"] = maxi(0, DictUtil.to_int(entry.get("turns_left", 1), 1) - 1)


func _apply_condition_applied(ev: Dictionary) -> void:
	var target := str(ev.get("target", ""))
	var condition := str(ev.get("condition", ""))
	var source := str(ev.get("source", ""))
	var duration: Dictionary = ev.get("duration", {}) if typeof(ev.get("duration")) == TYPE_DICTIONARY else {}
	var turns := 0
	match str(duration.get("type", "")):
		Conditions.DURATION_SOURCE_NEXT_TURN:
			turns = 2 if current_actor == source and not source.is_empty() else 1
		Conditions.DURATION_TARGET_TURN_END:
			turns = 1
		Conditions.DURATION_ROUNDS:
			turns = DictUtil.to_int(duration.get("rounds", 1), 1)
	if not conditions.has(target):
		conditions[target] = [] as Array[Dictionary]
	var list: Array[Dictionary] = conditions[target]
	for i in range(list.size() - 1, -1, -1):
		if str(list[i]["condition"]) == condition and str(list[i]["source"]) == source:
			list.remove_at(i)  # the same condition from the same source is replaced
	var entry := {"condition": condition, "source": source, "duration": duration.duplicate(), "turns_left": turns}
	list.append(entry)
	if target == player_id and IMMOBILIZING.has(condition):
		movement_remaining = 0
	var by := (" by %s" % display_name(source)) if not source.is_empty() and source != target else ""
	_log("%s is %s%s." % [display_name(target), condition_text(entry), by])


func _apply_condition_ended(ev: Dictionary) -> void:
	var target := str(ev.get("target", ""))
	var condition := str(ev.get("condition", ""))
	if conditions.has(target):
		var list: Array[Dictionary] = conditions[target]
		for i in range(list.size()):
			if str(list[i]["condition"]) == condition:
				list.remove_at(i)
				break
	if target == player_id and sheet != null:
		sheet.conditions.erase(condition)
	_log("%s is no longer %s." % [display_name(target), condition.replace("_", " ")])


## feature_used: the action economy (action / bonus / free), the spent
## resource (feature_resource; "remaining" is what is left of it), and the
## feature's own effect on what the client predicts.
func _apply_feature_used(ev: Dictionary) -> void:
	var actor := str(ev.get("actor", ""))
	var feature := str(ev.get("feature", ""))
	var mode := str(ev.get("mode", ""))
	if actor == player_id:
		if current_actor == player_id and Encounter.USABLE_FEATURES.has(feature):
			match ClientState.feature_cost(feature):
				"action":
					action_used = true
				"bonus":
					bonus_action_used = true
		var res := ClientState.feature_resource(feature)
		if sheet != null and ev.has("remaining") and not res.is_empty():
			sheet.class_resources[res] = DictUtil.to_int(ev["remaining"], 0)
		match feature:
			"action_surge":
				action_used = false
				attacks_remaining = 0
				action_surged = true
			"flurry_of_blows":
				bonus_attacks_remaining = 2
				bonus_attack_source = "flurry_of_blows"
			"patient_defense", "step_of_the_wind", "cunning_action":
				_feature_move = feature  # its dodge / dash / disengage event follows
			"font_of_magic":
				var lvl := DictUtil.to_int(ev.get("slot_level", 0), 0)
				if sheet != null and lvl >= 1:
					while sheet.spell_slots.size() < lvl:
						sheet.spell_slots.append(0)
					if mode == "create_slot":
						sheet.spell_slots[lvl - 1] += 1
					else:
						sheet.spell_slots[lvl - 1] = maxi(0, sheet.spell_slots[lvl - 1] - 1)
			"divine_smite":
				var smite_level := DictUtil.to_int(ev.get("slot_level", _pending_smite), _pending_smite)
				if sheet != null and smite_level >= 1 and smite_level <= sheet.spell_slots.size():
					sheet.spell_slots[smite_level - 1] = DictUtil.to_int(ev.get("remaining", 0), 0)
	var target := str(ev.get("target", actor))
	var line := "%s uses %s" % [display_name(actor), ClientState.feature_name(feature)]
	if not mode.is_empty():
		line += " (%s)" % mode.replace("_", " ")
	if not target.is_empty() and target != actor:
		line += " on %s" % display_name(target)
	_log(line + ".")


func _apply_area_effect(ev: Dictionary) -> void:
	var affected := DictUtil.to_string_array(ev.get("affected", []))
	var sculpted := DictUtil.to_string_array(ev.get("sculpted", []))
	last_area = {
		"caster": str(ev.get("caster", "")), "spell": str(ev.get("spell", "")),
		"point": Messages.to_position(ev["point"]) if Messages.is_position(ev.get("point")) else Vector2i.ZERO,
		"shape": str(ev.get("shape", "")), "size_tiles": DictUtil.to_int(ev.get("size_tiles", 0), 0),
		"affected": affected, "sculpted": sculpted,
	}
	area_serial += 1
	var who := "no one" if affected.is_empty() else ", ".join(_names(affected))
	var line := "%s's %s (%s) catches %s" % [display_name(str(ev.get("caster", ""))), spell_name(str(ev.get("spell", ""))),
		str(ev.get("shape", "area")), who]
	if not sculpted.is_empty():
		line += "; %s spared" % ", ".join(_names(sculpted))
	_log(line + ".")


func _names(ids: Array[String]) -> PackedStringArray:
	var out: PackedStringArray = []
	for id in ids:
		out.append(display_name(id))
	return out


# --- queries for the scenes ---------------------------------------------------

## The character's name for the player, else a server-provided name, else
## the id made readable ("goblin_2" -> "Goblin 2").
func display_name(id: String) -> String:
	if id == player_id and sheet != null and not sheet.name.is_empty():
		return sheet.name
	if entities.has(id):
		var e: Dictionary = entities[id]
		var n := str(e.get("name", ""))
		if not n.is_empty():
			return n
	return id.replace("_", " ").capitalize()


func get_entity(id: String) -> Dictionary:
	if not entities.has(id):
		return {}
	var e: Dictionary = entities[id]
	return e


func has_player_entity() -> bool:
	return entities.has(player_id)


func player_position() -> Vector2i:
	if entities.has(player_id):
		var e: Dictionary = entities[player_id]
		var p: Vector2i = e["position"]
		return p
	return floor_data.arrival if floor_data != null else Vector2i.ZERO


func speed_tiles() -> int:
	return GridMath.feet_to_tiles(sheet.speed) if sheet != null else 0


func is_player_conscious() -> bool:
	return sheet != null and sheet.is_conscious()


func is_my_turn() -> bool:
	return mode == Mode.COMBAT and in_encounter and current_actor == player_id and is_player_conscious()


## Tiles holding a living entity (Vector2i -> id), WalkMap's `occupied` format.
func occupied_cells(except_id: String = "") -> Dictionary:
	var out := {}
	for id: String in entities.keys():
		var e: Dictionary = entities[id]
		if id != except_id and not bool(e["dead"]):
			var p: Vector2i = e["position"]
			out[p] = id
	return out


## The walk map the player moves on right now (cropped to the region in combat).
func movement_map() -> WalkMap:
	if floor_data == null:
		return null
	if in_encounter and region.has_area():
		return fight_map()
	return explore_map()


## Tiles the player can still move to this turn (start excluded): Vector2i -> steps.
## Empty unless it is the player's turn.
func reachable_tiles() -> Dictionary:
	if not is_my_turn() or movement_remaining <= 0:
		return {}
	var wm := movement_map()
	if wm == null:
		return {}
	var start := player_position()
	var out := wm.reachable(start, movement_remaining, occupied_cells(player_id))
	out.erase(start)
	return out


## Combat path from the player to tile within movement_remaining; empty if none.
func move_path_to(tile: Vector2i) -> Array[Vector2i]:
	var empty: Array[Vector2i] = []
	var wm := movement_map()
	if wm == null or not is_my_turn():
		return empty
	var path := wm.path_to(player_position(), tile, occupied_cells(player_id), movement_remaining)
	if path.is_empty() or path[path.size() - 1] != tile or path.size() > movement_remaining:
		return empty
	return path


## Id of a living monster standing on tile, or "".
func hostile_at(tile: Vector2i) -> String:
	for id: String in entities.keys():
		var e: Dictionary = entities[id]
		var p: Vector2i = e["position"]
		if p == tile and str(e["kind"]) == KIND_MONSTER and not bool(e["dead"]):
			return id
	return ""


## Living monsters of the player's encounter within reach, in initiative order.
func adjacent_hostiles() -> Array[String]:
	var out: Array[String] = []
	if not in_encounter:
		return out
	var me := player_position()
	for id in order:
		if not entities.has(id):
			continue
		var e: Dictionary = entities[id]
		var p: Vector2i = e["position"]
		if str(e["kind"]) == KIND_MONSTER and not bool(e["dead"]) and GridMath.is_adjacent(me, p):
			out.append(id)
	return out


func can_take_action() -> bool:
	return is_my_turn() and not action_used


func can_take_bonus_action() -> bool:
	return is_my_turn() and not bonus_action_used


## True when the selected attack can hit some hostile right now (or the
## familiar can, when "via_familiar" is on).
func can_attack() -> bool:
	if bool(attack_options.get("via_familiar", false)) and "via_familiar" in attack_option_kinds():
		return is_my_turn() and can_make_attack() and not familiar_targets().is_empty()
	return is_my_turn() and not attack_targets().is_empty()


## The Attack action is free, or it was taken and Extra Attack rolls remain.
func can_make_attack() -> bool:
	return is_my_turn() and (not action_used or (attack_action_taken and attacks_remaining > 0))


func on_stairs() -> bool:
	return floor_data != null and has_player_entity() and player_position() == floor_data.stairs


## Stairs and resting are only allowed out of combat, on the stairs tile.
func can_use_stairs() -> bool:
	return mode == Mode.EXPLORING and not in_encounter and on_stairs() and is_player_conscious()


## Resting helps: hit dice to heal, short-rest resources or pact slots to
## regain, or slots to recover (Arcane / Natural Recovery).
func can_short_rest() -> bool:
	if not can_use_stairs() or sheet == null:
		return false
	if sheet.hit_dice_remaining > 0 and sheet.current_hp < sheet.max_hp:
		return true
	for r in resource_entries():
		if bool(r["short_rest"]) and int(r["remaining"]) < int(r["max"]):
			return true
	if sheet.slot_recovery == ClassDefinition.SLOT_RECOVERY_SHORT:
		for i in range(sheet.spell_slots_max.size()):
			if sheet.slots_left(i + 1) < sheet.spell_slots_max[i]:
				return true
	return not slot_recovery().is_empty()


## 1-based floor number: the floor's own floor_number, else its place in the set.
func floor_number() -> int:
	if floor_data != null and floor_data.floor_number > 0:
		return floor_data.floor_number
	return floor_index + 1


## "Floor 2 — <display_name>" ("" before the first FLOOR_LOADED).
func floor_label() -> String:
	if floor_data == null:
		return ""
	return "Floor %d — %s" % [floor_number(), floor_data.display_name]


## True while playing a set whose current floor is not its last.
func has_next_floor() -> bool:
	return not set_id.is_empty() and floor_index + 1 < floor_count


func is_last_floor_of_set() -> bool:
	return not set_id.is_empty() and floor_index + 1 >= floor_count


## Text for the stairs button.
func stairs_label() -> String:
	if has_next_floor():
		return "Descend to floor %d" % (floor_number() + 1)
	if is_last_floor_of_set():
		return "Enter the safe zone"
	return "Descend"


## XP needed in total for the next level (the current level's cap at 20).
func xp_for_next_level() -> int:
	if sheet == null:
		return 0
	return Experience.xp_for_level(sheet.level + 1)


## "Lv N  XP x/y" ("" before the first CHARACTER_STATE).
func level_text() -> String:
	if sheet == null:
		return ""
	return "Lv %d  XP %d/%d" % [sheet.level, sheet.xp, xp_for_next_level()]


## Human-readable mode line for the HUD.
func mode_text() -> String:
	match mode:
		Mode.LOADING:
			return "Loading..."
		Mode.EXPLORING:
			return "Exploring"
		Mode.GAME_OVER:
			return "Game over"
		Mode.FLOOR_CLEARED:
			return "Floor cleared"
		Mode.SET_CLEARED:
			return "Set cleared"
	if current_actor.is_empty():
		return "Combat: round %d" % round_number
	if current_actor == player_id:
		return "Combat: your turn (round %d)" % round_number
	return "Combat: %s's turn (round %d)" % [display_name(current_actor), round_number]


# --- intents ------------------------------------------------------------------

## The intent a left click on tile means right now, or {} for none.
## Exploring: open a chest within reach on the tile, else walk there.
## Targeting mode: the cast / feature / attack on the creature on the tile.
## Player's combat turn: attack a hostile on the tile with the selected attack
## (adjacent for melee, in range for ranged / thrown) if the action is free,
## else move there if reachable.
func intent_for_click(tile: Vector2i) -> Dictionary:
	if floor_data == null or not has_player_entity():
		return {}
	if mode == Mode.EXPLORING and not in_encounter:
		if not is_player_conscious():
			return {}
		if is_targeting():
			return _targeted_intent(tile)
		var door := floor_data.door_at(tile)
		if door != null:
			return door_intent(door.id)
		var prop := floor_data.prop_at(tile)
		if prop != null and not destroyed_props.has(prop.id):
			return prop_intent(prop.id)
		var chest_id := chest_at(tile)
		if not chest_id.is_empty() and can_open_chest(chest_id):
			if bool((chests[chest_id] as Dictionary).get("locked", false)):
				hint = "The chest is locked: Knock opens it."
				return {}
			return open_chest_intent(chest_id)
		if not floor_data.walk_map.is_walkable(tile) or tile == player_position():
			return {}
		return route_intent(tile)
	if not is_my_turn():
		return {}
	if is_targeting():
		return _targeted_intent(tile)
	var target := hostile_at(tile)
	if not target.is_empty():
		if order.has(target) and attack_error(target, selected_attack).is_empty():
			return attack_intent(target)
		return {}
	var path := move_path_to(tile)
	if path.is_empty():
		return {}
	return Messages.make_intent(Messages.MOVE, {"actor": player_id, "path": GridMath.vec_list_to_arr(path)})


## One step in a direction (arrow keys / WASD): walk or move, never a target pick.
func step_intent(dir: Vector2i) -> Dictionary:
	if floor_data == null or not has_player_entity() or dir == Vector2i.ZERO:
		return {}
	var tile := player_position() + dir
	if mode == Mode.EXPLORING and not in_encounter:
		if not is_player_conscious() or not explore_map().is_walkable(tile) or prop_blockers().has(tile):
			return {}
		return Messages.make_intent(Messages.EXPLORE_MOVE, {"actor": player_id, "target": GridMath.vec_to_arr(tile)})
	var path := move_path_to(tile)
	if path.is_empty():
		return {}
	return Messages.make_intent(Messages.MOVE, {"actor": player_id, "path": GridMath.vec_list_to_arr(path)})


## Attack with attack_index (-1 = selected_attack). target "" = the first
## hostile the attack can reach (adjacent for melee), in initiative order.
## Off-hand attacks are always bonus attacks. attack_options that apply to
## this attack are added (see attack_option_fields).
func attack_intent(target: String = "", attack_index: int = -1, bonus: bool = false) -> Dictionary:
	if bool(attack_options.get("via_familiar", false)) and not bonus and "via_familiar" in attack_option_kinds():
		return familiar_attack_intent(target)
	var index := selected_attack if attack_index < 0 else attack_index
	var b: bool = bonus or get_attack(index).get("off_hand", false) == true
	var t := target
	if t.is_empty():
		var near := attack_targets(index, b)
		if near.is_empty():
			return {}
		t = near[0]
	var fields := {"actor": player_id, "target": t, "attack_index": index}
	if b:
		fields["bonus"] = true
	fields.merge(attack_option_fields(index, b))
	_pending_smite = DictUtil.to_int(fields.get("smite", 0), 0)
	return Messages.make_intent(Messages.ATTACK, fields)


## dash / dodge / disengage / end_turn / use_stairs: intents with no extra fields.
func simple_intent(type: String) -> Dictionary:
	return Messages.make_intent(type, {"actor": player_id})


## short_rest; recover_slots asks the server for Arcane / Natural Recovery
## (it picks the slots) when slot_recovery() offers it.
func short_rest_intent(hit_dice: int = 1, recover_slots: bool = false) -> Dictionary:
	var fields := {"actor": player_id, "hit_dice": hit_dice}
	if recover_slots:
		fields["recover_slots"] = true
	return Messages.make_intent(Messages.SHORT_REST, fields)


## cast; extra may add "point", "metamagic", "twin_target", "sculpt", "form", "targets".
func cast_intent(spell_id: String, target: String = "", slot_level: int = 0, extra: Dictionary = {}) -> Dictionary:
	var fields := {"actor": player_id, "spell": spell_id,
		"target": target if not target.is_empty() else player_id, "slot_level": slot_level}
	for key: String in ["point", "metamagic", "twin_target", "sculpt", "form", "targets", "mode", "target_kind", "target_id",
			"invocation", "duplicate_mode"]:
		if extra.has(key):
			var v: Variant = extra[key]
			if typeof(v) == TYPE_ARRAY and (v as Array).is_empty():
				continue
			if typeof(v) == TYPE_STRING and str(v).is_empty():
				continue
			fields[key] = v
	for key: String in ["ritual", "spend_slot", "overchannel"]:
		if extra.get(key, false) == true:
			fields[key] = true
	if not fields.has("overchannel") and _overchannel_applies(spell_id):
		fields["overchannel"] = true
	return Messages.make_intent(Messages.CAST, fields)


## A prone player stands up (half the speed).
func stand_intent() -> Dictionary:
	return Messages.make_intent(Messages.STAND, {"actor": player_id})


## The reaction_policy intent with one trigger switched to "auto" (on) or
## "never" (off), the other entries kept. Per-reaction overrides of the
## reactions that trigger governs are dropped, so the trigger decides again.
func reaction_policy_intent(trigger: String, on: bool) -> Dictionary:
	return reaction_toggle_intent(trigger, "", on)


## The reaction_policy intent for one check box: a trigger (reaction "") or
## one reaction under it (a per-reaction key, as Combatant.reaction_allowed reads).
func reaction_toggle_intent(trigger: String, reaction: String, on: bool) -> Dictionary:
	var policy := reaction_policy.duplicate()
	if reaction.is_empty():
		policy[trigger] = "auto" if on else "never"
		for r: Variant in REACTIONS_BY_TRIGGER.get(trigger, []):
			policy.erase(str(r))
	else:
		policy[reaction] = "auto" if on else "never"
	return Messages.make_intent(Messages.REACTION_POLICY, {"actor": player_id, "policy": policy})


## Whether the player reacts automatically to a trigger (missing = "auto").
func reacts_to(trigger: String) -> bool:
	return str(reaction_policy.get(trigger, "auto")) != "never"


## Combatant.reaction_allowed: a reaction's own key wins over its trigger's.
func reacts_with(trigger: String, reaction: String) -> bool:
	if reaction_policy.has(reaction):
		return str(reaction_policy[reaction]) != "never"
	return reacts_to(trigger)


## Whether the character has a reaction (prepared spell, feature, style;
## everyone has the opportunity attack).
func has_reaction(reaction: String) -> bool:
	if sheet == null:
		return false
	if reaction == "opportunity_attack":
		return true
	if REACTION_SPELLS.has(reaction):
		return sheet.is_spell_prepared(reaction)
	if reaction == "protection":
		return sheet.fighting_styles.has("protection")
	if reaction == "uncanny_dodge":
		return sheet.has_feature("uncanny_dodge") or sheet.has_feature("superior_hunters_defense_uncanny_dodge")
	return sheet.has_feature(reaction)


## One entry per reaction trigger for the Reactions panel: {"trigger",
## "label", "on", "reactions": [{"id", "name", "on"}]} with only the
## reactions this character has.
func reaction_entries() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for trigger in Messages.REACTION_TRIGGERS:
		var mine: Array[Dictionary] = []
		for r_v: Variant in REACTIONS_BY_TRIGGER.get(trigger, []):
			var r := str(r_v)
			if has_reaction(r):
				mine.append({"id": r, "name": str(REACTION_NAMES.get(r, r.replace("_", " ").capitalize())), "on": reacts_with(trigger, r)})
		out.append({"trigger": trigger, "label": str(REACTION_TRIGGER_LABELS.get(trigger, trigger.replace("_", " ").capitalize())),
			"on": reacts_to(trigger), "reactions": mine})
	return out


## Always true: the rules engine resolves reactions by policy
## (Encounter.set_reaction_policy, Messages.REACTION_TRIGGERS).
static func reaction_policy_supported() -> bool:
	return not Messages.REACTION_TRIGGERS.is_empty()


# --- companions -----------------------------------------------------------------------

## The sheet's companions: {"id", "monster", "name", "spell", "hp", "max_hp", "dead"}.
func companion_entries() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if sheet == null:
		return out
	var monsters: Dictionary = _content().get("monsters", {})
	for entry in sheet.companions:
		var mid := str(entry.get("monster", ""))
		var def: MonsterDefinition = monsters.get(mid, null)
		var max_hp := def.hit_points_avg if def != null else DictUtil.to_int(entry.get("hp", 0), 0)
		out.append({"id": str(entry.get("id", "")), "monster": mid, "name": monster_name(mid), "spell": str(entry.get("spell", "")),
			"hp": DictUtil.to_int(entry.get("hp", max_hp), max_hp), "max_hp": max_hp, "dead": entry.get("dead", false) == true})
	return out


## "Companions: Cat 2/2 HP, Skeleton 13/13 HP", or "" with none.
func companions_text() -> String:
	var parts: PackedStringArray = []
	for c in companion_entries():
		parts.append("%s %d/%d HP%s" % [str(c["name"]), int(c["hp"]), int(c["max_hp"]), " (dead)" if bool(c["dead"]) else ""])
	return "" if parts.is_empty() else "Companions: %s" % ", ".join(parts)


## Companions may be dismissed while exploring.
func can_dismiss_companion() -> bool:
	return mode == Mode.EXPLORING and not in_encounter and sheet != null and not sheet.companions.is_empty()


func dismiss_companion_intent(companion_id: String) -> Dictionary:
	return Messages.make_intent(Messages.DISMISS_COMPANION, {"actor": player_id, "companion_id": companion_id})


func monster_name(monster_id: String) -> String:
	var monsters: Dictionary = _content().get("monsters", {})
	var def: MonsterDefinition = monsters.get(monster_id, null)
	return def.display_name if def != null else monster_id.replace("_", " ").capitalize()


## use_feature; target "" = self, amount only for lay_on_hands; extra may add
## "mode", "slot_level", "allocations", "frenzy".
func feature_intent(feature: String, target: String = "", amount: int = 0, extra: Dictionary = {}) -> Dictionary:
	var fields := {"actor": player_id, "feature": feature, "target": target if not target.is_empty() else player_id}
	if amount > 0:
		fields["amount"] = amount
	for key: String in ["mode", "slot_level", "allocations", "frenzy"]:
		if extra.has(key):
			fields[key] = extra[key]
	return Messages.make_intent(Messages.USE_FEATURE, fields)


## use_item on yourself: the combat intent on your turn, the exploration one otherwise (same shape).
func use_item_intent(item: String) -> Dictionary:
	return Messages.make_intent(Messages.USE_ITEM, {"actor": player_id, "item": item})


func equip_intent(item: String, slot: String) -> Dictionary:
	return Messages.make_intent(Messages.EQUIP, {"actor": player_id, "item": item, "slot": slot})


func unequip_intent(slot: String) -> Dictionary:
	return Messages.make_intent(Messages.UNEQUIP, {"actor": player_id, "slot": slot})


func drop_item_intent(item: String, qty: int = 1) -> Dictionary:
	return Messages.make_intent(Messages.DROP_ITEM, {"actor": player_id, "item": item, "qty": maxi(1, qty)})


func open_chest_intent(chest_id: String) -> Dictionary:
	return Messages.make_intent(Messages.OPEN_CHEST, {"actor": player_id, "chest_id": chest_id})


## Answers the pending level-up offer (see LevelUpDraft.to_choices()).
func level_up_intent(choices: Dictionary) -> Dictionary:
	return Messages.make_intent(Messages.LEVEL_UP, {"actor": player_id, "choices": choices.duplicate(true)})


# --- content lookups ------------------------------------------------------------

func _content() -> Dictionary:
	return ContentLoader.resolve(content)


func item_def(item_id: String) -> ItemDefinition:
	return CharacterSheet.item_def(item_id, _content())


func spell_def(spell_id: String) -> SpellDefinition:
	var spells: Dictionary = _content()["spells"]
	if not spells.has(spell_id):
		return null
	var s: SpellDefinition = spells[spell_id]
	return s


func item_name(item_id: String) -> String:
	var def := item_def(item_id)
	return def.display_name if def != null else item_id.replace("_", " ").capitalize()


func spell_name(spell_id: String) -> String:
	var def := spell_def(spell_id)
	return def.display_name if def != null else spell_id.replace("_", " ").capitalize()


static func feature_name(feature: String) -> String:
	return FEATURE_NAMES.get(feature, feature.replace("_", " ").capitalize())


## "1st", "2nd", "3rd", "4th"...
static func ordinal(n: int) -> String:
	match n:
		1:
			return "1st"
		2:
			return "2nd"
		3:
			return "3rd"
	return "%dth" % n


# --- attacks ------------------------------------------------------------------------

func _attacks_from_sheet() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if sheet == null:
		return out
	for a in sheet.attacks:
		out.append(a.duplicate(true))
	out.append(sheet.unarmed_strike())
	return out


## The attacks an attack_index refers to: in combat the server's list (the
## sheet's attacks when the encounter started + the unarmed strike), else the
## sheet's current ones + the unarmed strike.
func available_attacks() -> Array[Dictionary]:
	if in_encounter and not _combat_attacks.is_empty():
		return _combat_attacks
	return _attacks_from_sheet()


func get_attack(index: int) -> Dictionary:
	var list := available_attacks()
	if index < 0 or index >= list.size():
		return {}
	return list[index]


func select_attack(index: int) -> void:
	if index >= 0 and index < available_attacks().size():
		selected_attack = index
		revision += 1


static func is_ranged_attack(attack: Dictionary) -> bool:
	return Encounter.is_ranged_attack(attack)


## "" when the attack's item and ammunition are still carried, else why not.
func attack_supply_error(attack: Dictionary) -> String:
	if sheet == null:
		return "no character"
	var item := str(attack.get("item", ""))
	if not item.is_empty() and not sheet.has_item(item):
		return "no %s left" % item_name(item)
	var consumes := str(attack.get("consumes", ""))
	if not consumes.is_empty() and not sheet.has_item(consumes):
		return "out of %s" % item_name(consumes)
	return ""


## "Longsword (melee) +5, 1d8+3 slashing"; ranged ones add "range 16/64" and the count left.
func attack_label(attack: Dictionary) -> String:
	var kind := str(attack.get("kind", "melee"))
	var text := "%s (%s) %+d, %s %s" % [str(attack.get("name", "?")), kind,
		DictUtil.to_int(attack.get("to_hit", 0), 0), str(attack.get("damage", "")), str(attack.get("damage_type", ""))]
	if ClientState.is_ranged_attack(attack):
		var r := Encounter.attack_range_tiles(attack)
		text += ", range %d/%d" % [r[0], r[1]]
		var consumes := str(attack.get("consumes", ""))
		if not consumes.is_empty() and sheet != null:
			text += ", %d left" % sheet.count_item(consumes)
	return text.strip_edges()


## "" when the player may attack target with attacks[attack_index] now, else why not.
func attack_error(target: String, attack_index: int = -1, bonus: bool = false) -> String:
	if bool(attack_options.get("via_familiar", false)) and not bonus and "via_familiar" in attack_option_kinds():
		return familiar_attack_error(target)
	var index := selected_attack if attack_index < 0 else attack_index
	if not is_my_turn():
		return "not your turn"
	var attack := get_attack(index)
	var b: bool = bonus or attack.get("off_hand", false) == true
	if b:
		var src := bonus_attack_error(attack)
		if not src.is_empty():
			return src
	elif not can_make_attack():
		return "action already used"
	if attack.is_empty():
		return "no such attack"
	var supply := attack_supply_error(attack)
	if not supply.is_empty():
		return supply
	var e := get_entity(target)
	if e.is_empty() or str(e["kind"]) != KIND_MONSTER or bool(e["dead"]) or not order.has(target):
		return "not a hostile in this fight"
	var to: Vector2i = e["position"]
	var dist := GridMath.distance_tiles(player_position(), to)
	var r := Encounter.attack_range_tiles(attack)
	if not ClientState.is_ranged_attack(attack):
		return "" if dist >= 1 and dist <= maxi(1, r[1]) else "out of reach"
	if dist > r[1]:
		return "out of range (%d tiles, long range %d)" % [dist, r[1]]
	if floor_data != null and not sight_map().has_line_of_sight(player_position(), to):
		return "no line of sight"
	return ""


## Hostiles of the player's encounter the attack can hit now, in initiative order.
func attack_targets(attack_index: int = -1, bonus: bool = false) -> Array[String]:
	var out: Array[String] = []
	if not in_encounter:
		return out
	for id in order:
		if attack_error(id, attack_index, bonus).is_empty():
			out.append(id)
	return out


## Tiles to tint for the current choice: Vector2i -> 0 (normal range) or 1
## (long range, disadvantage). A selected ranged attack (action free) or a
## targeting mode, inside the encounter region, with line of sight. {} otherwise.
func range_tiles() -> Dictionary:
	var out := {}
	if not is_my_turn() or floor_data == null:
		return out
	var normal := 0
	var long := 0
	if targeting.get("mode", "") == TARGET_CAST:
		var spell := spell_def(str(targeting["spell"]))
		if spell == null:
			return out
		normal = maxi(1, spell.range_tiles()) if spell.range_ft > 0 else 0
		if spell.is_area() and spell.range_ft == 0:
			normal = spell.area_size_tiles()  # cones / lines reach their size
		long = normal
	elif targeting.get("mode", "") == TARGET_FEATURE:
		normal = BARDIC_INSPIRATION_RANGE if str(targeting["feature"]) == ClassDefinition.FEATURE_BARDIC_INSPIRATION else 1
		long = normal
	else:
		var attack := get_attack(int(targeting.get("attack_index", selected_attack)))
		if attack.is_empty() or (targeting.is_empty() and (not can_make_attack() or not ClientState.is_ranged_attack(attack))):
			return out
		var r := Encounter.attack_range_tiles(attack)
		normal = r[0]
		long = r[1]
	if long <= 0:
		return out
	var me := player_position()
	var area := region if region.has_area() else Rect2i(me - Vector2i(long, long), Vector2i(long * 2 + 1, long * 2 + 1))
	var wm := sight_map()
	for y in range(area.position.y, area.end.y):
		for x in range(area.position.x, area.end.x):
			var t := Vector2i(x, y)
			var dist := GridMath.distance_tiles(me, t)
			if dist == 0 or dist > long or not wm.is_walkable(t):
				continue
			if not wm.has_line_of_sight(me, t):
				continue
			out[t] = 0 if dist <= normal else 1
	return out


# --- spells -------------------------------------------------------------------------

## The prepared spells for the Spells list, cantrips first, each
## {"id", "name", "level", "supported", "bonus", "target", "range_tiles",
##  "slots": Array[int] (slot levels with a slot left, >= the spell's level),
##  "casting_time" (data id), "casting_time_text" ("1 hour (ritual)"),
##  "ritual", "out_of_combat" (OutOfCombat.cast resolves it),
##  "error": "" when castable right now (in or out of combat)}.
##  round C: "prepared" (false for spellbook / Book of Ancient Secrets rituals
##  and at-will invocations listed while exploring), "ritual_castable"
##  (OutOfCombat.can_ritual_cast, exploring), "ritual_error" (cast_error as a
##  ritual), "no_effect" (why it does nothing in the delve, "" otherwise),
##  "target_kinds" (exploration spells: door / chest / zone / landmark),
##  "landmarks", "invocation" (an at-will invocation casting it),
##  "overchannel" (Overchannel would apply).
func spell_entries() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if sheet == null:
		return out
	var ids: Array[String] = []
	ids.assign(sheet.spells_prepared)
	if not in_encounter:
		for id in sheet.spells_known + sheet.ritual_book:
			var d := spell_def(id)
			if d != null and not ids.has(id) and OutOfCombat.can_ritual_cast(sheet, d):
				ids.append(id)
	for inv: String in CharacterSheet.AT_WILL_INVOCATIONS.keys():
		var sid: String = CharacterSheet.AT_WILL_INVOCATIONS[inv]
		if sheet.invocations.has(inv) and not ids.has(sid) and spell_def(sid) != null:
			ids.append(sid)
	for id in ids:
		var def := spell_def(id)
		if def == null:
			continue
		var ritual: bool = def.raw.get("ritual", false) == true
		var ritual_ok := not in_encounter and OutOfCombat.can_ritual_cast(sheet, def)
		out.append({
			"id": id, "name": def.display_name, "level": def.level, "supported": def.is_castable(),
			"bonus": def.uses_bonus_action(), "target": def.target, "range_tiles": def.range_tiles(),
			"slots": cast_slot_options(id), "error": cast_error(id),
			"casting_time": def.casting_time, "ritual": ritual,
			"casting_time_text": ClientState.casting_time_text(def.casting_time, ritual),
			"out_of_combat": ClientState.castable_out_of_combat(def),
			"prepared": sheet.is_spell_prepared(id), "ritual_castable": ritual_ok,
			"ritual_error": cast_error(id, 0, [] as Array[String], true) if ritual_ok else "not a ritual for you",
			"no_effect": no_effect_reason(id), "target_kinds": DictUtil.to_string_array(def.raw_effect.get("target_kinds", [])),
			"landmarks": DictUtil.to_string_array(def.raw_effect.get("landmarks", [])),
			"invocation": sheet.at_will_invocation(id), "overchannel": _overchannel_possible(id),
		})
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if int(a["level"]) != int(b["level"]):
			return int(a["level"]) < int(b["level"])
		return str(a["name"]) < str(b["name"]))
	return out


## Slot levels a leveled spell may use now (lowest first); [] for cantrips.
func cast_slot_options(spell_id: String) -> Array[int]:
	var out: Array[int] = []
	var def := spell_def(spell_id)
	if def == null or def.level == 0 or sheet == null:
		return out
	for lvl in range(def.level, sheet.spell_slots_max.size() + 1):
		if sheet.slots_left(lvl) > 0:
			out.append(lvl)
	return out


## "" when spell_id can be cast now (slot_level 0 = cantrip / lowest free
## slot) with the given metamagic options.
func cast_error(spell_id: String, slot_level: int = 0, metamagic: Array[String] = [], ritual: bool = false) -> String:
	var def := spell_def(spell_id)
	if def == null or sheet == null:
		return "unknown spell"
	if not def.is_castable():
		return "not supported yet"
	if not in_encounter:
		return _out_of_combat_cast_error(def, slot_level, ritual)
	if not def.is_combat_castable():
		return "takes too long to cast in combat"
	var at_will := sheet.at_will_invocation(spell_id)
	if not sheet.is_spell_prepared(spell_id) and at_will.is_empty() and sheet.invocation_spell_use(spell_id).is_empty():
		return "not prepared"
	if not is_my_turn():
		return "only on your turn in combat"
	if status_tags(player_id).has("raging"):
		return "no spells while raging"
	var meta_error := metamagic_error(spell_id, metamagic)
	if not meta_error.is_empty():
		return meta_error
	if def.uses_bonus_action() or metamagic.has("quickened_spell"):
		if bonus_action_used:
			return "bonus action already used"
	elif action_used:
		return "action already used"
	if def.level > 0 and at_will.is_empty() and def.effect_type != SpellDefinition.EFFECT_NO_EFFECT \
			and not _free_cast(spell_id, slot_level):
		var slot := slot_level if slot_level > 0 else sheet.lowest_available_slot(def.level)
		if slot == 0 or slot < def.level or sheet.slots_left(slot) <= 0:
			return "no spell slot left"
	return ""


## Spell Mastery (slot 0 or the spell's level) and Signature Spells (one free
## cast per short rest) cast without a slot.
func _free_cast(spell_id: String, slot_level: int) -> bool:
	var def := spell_def(spell_id)
	if def == null or sheet == null:
		return false
	if sheet.spell_mastery.has(spell_id) and (slot_level == 0 or slot_level == def.level):
		return true
	return sheet.signature_spells.has(spell_id) and sheet.class_resource(CharacterSheet.SIGNATURE_PREFIX + spell_id) > 0 \
		and (slot_level == 0 or slot_level == def.level)


## Why spell_id does nothing in the delve right now ("" when it does
## something): its declared no-effect reason, or (exploring) why a
## fight-only spell with a long casting time has no target here.
func no_effect_reason(spell_id: String) -> String:
	var def := spell_def(spell_id)
	if def == null:
		return ""
	if def.effect_type == SpellDefinition.EFFECT_NO_EFFECT:
		return def.no_effect_reason()
	if not in_encounter:
		return OutOfCombat.fight_only_reason(def)
	return ""


## cast_error while exploring (OutOfCombat.cast's checks, the player as the
## only target; no action economy, no real-time casting wait in M2). A
## ritual cast needs Ritual Casting (or the spellbook / Book of Ancient
## Secrets) and no slot; declared no-effect spells and at-will invocations
## need no slot either.
func _out_of_combat_cast_error(def: SpellDefinition, slot_level: int, ritual: bool = false) -> String:
	var at_will := sheet.at_will_invocation(def.id)
	if ritual:
		if not OutOfCombat.can_ritual_cast(sheet, def):
			return "you cannot cast it as a ritual"
	elif not sheet.is_spell_prepared(def.id) and at_will.is_empty() and sheet.invocation_spell_use(def.id).is_empty():
		return "not prepared"
	if mode != Mode.EXPLORING:
		return "not now"
	if not ClientState.castable_out_of_combat(def):
		return "only in a fight"
	if not sheet.is_conscious():
		return "you cannot cast now"
	if ritual or not at_will.is_empty() or not no_effect_reason(def.id).is_empty() or _free_cast(def.id, slot_level):
		return ""
	match def.effect_type:
		SpellDefinition.EFFECT_REVIVE:
			return "needs a fallen ally (not in this version)"
		SpellDefinition.EFFECT_HEAL, SpellDefinition.EFFECT_AREA_HEAL, SpellDefinition.EFFECT_HEAL_POOL:
			if sheet.current_hp >= sheet.max_hp:
				return "you are at full health"
		SpellDefinition.EFFECT_BUFF:
			if sheet.armor_base > 0:
				return "not while wearing armor"
	if def.level > 0:
		var slot := slot_level if slot_level > 0 else sheet.lowest_available_slot(def.level)
		if slot == 0 or slot < def.level or sheet.slots_left(slot) <= 0:
			return "no spell slot left"
	return ""


## Spells OutOfCombat.cast resolves: lasting companions (Find Familiar,
## Animate Dead, ...), revives other than Spare the Dying, heals, temporary
## hit points, restorations and Mage Armor.
## Round C: also exploration hooks, lingering spells and declared no-effect
## spells (OutOfCombat.castable).
static func castable_out_of_combat(def: SpellDefinition) -> bool:
	if def == null or not def.is_castable():
		return false
	return OutOfCombat.castable(def)


## "1 action", "1 bonus action", "1 reaction", "1 minute", "10 minutes",
## "1 hour"... plus " (ritual)".
static func casting_time_text(casting_time: String, ritual: bool = false) -> String:
	var t := casting_time
	if t in ["action", "bonus_action", "reaction"]:
		t = "1 " + t
	t = t.replace("_", " ")
	return t + (" (ritual)" if ritual else "")


## An action or bonus action (or a reaction): no long casting time.
static func is_quick_casting_time(casting_time: String) -> bool:
	return casting_time in ["action", "bonus_action", "reaction"]


## "" when target is a valid target for spell_id from where the player stands.
func cast_target_error(spell_id: String, target: String) -> String:
	var def := spell_def(spell_id)
	if def == null:
		return "unknown spell"
	var e := get_entity(target)
	if e.is_empty() or bool(e["dead"]):
		return "no creature there"
	if def.target == SpellDefinition.TARGET_SELF and target != player_id:
		return "%s targets only yourself" % def.display_name
	var hostile := str(e["kind"]) == KIND_MONSTER
	if def.is_harmful():
		if not hostile or not order.has(target):
			return "%s needs a hostile target" % def.display_name
	elif hostile:
		return "%s needs an ally" % def.display_name
	if target != player_id:
		var reach := maxi(1, def.range_tiles()) if def.range_ft > 0 else 0
		var to: Vector2i = e["position"]
		if GridMath.distance_tiles(player_position(), to) > reach:
			return "out of range"
		if floor_data != null and not sight_map().has_line_of_sight(player_position(), to):
			return "no line of sight"
	return ""


## Starts casting. Out of combat the cast intent comes back at once (the
## player is the only target; extra_fields may set "form"). In combat a
## self-only spell returns its intent at once; others enter
## targeting mode and return {}. {} with `hint` set when it cannot be cast.
## Area spells centred on the caster cast at once; other area spells enter
## targeting with "area": true (the click picks the point). Twinned Spell
## asks for a second target after the first.
func begin_cast(spell_id: String, slot_level: int = 0, metamagic: Array[String] = [], extra_fields: Dictionary = {}) -> Dictionary:
	hint = cast_error(spell_id, slot_level, metamagic, extra_fields.get("ritual", false) == true)
	if not hint.is_empty():
		return {}
	var def := spell_def(spell_id)
	var slot := 0 if def.level == 0 else (slot_level if slot_level > 0 else sheet.lowest_available_slot(def.level))
	if not sheet.at_will_invocation(spell_id).is_empty() or def.effect_type == SpellDefinition.EFFECT_NO_EFFECT or _free_cast(spell_id, slot_level):
		slot = 0
	if not in_encounter:
		# Out of combat the player is the only creature target (M2): cast at once,
		# unless an exploration spell aims at a door, chest or zone (a click).
		targeting = {}
		var fields := {}
		for key: String in ["form", "mode", "target_kind", "target_id", "invocation", "ritual", "spend_slot"]:
			if extra_fields.has(key):
				fields[key] = extra_fields[key]
		if fields.get("ritual", false) == true or not no_effect_reason(spell_id).is_empty() or not sheet.at_will_invocation(spell_id).is_empty():
			slot = 0
		var kinds := DictUtil.to_string_array(def.raw_effect.get("target_kinds", []))
		var object_kinds: Array[String] = []
		for k in kinds:
			if k != "landmark":
				object_kinds.append(k)
		if not object_kinds.is_empty() and not fields.has("target_kind"):
			targeting = {"mode": TARGET_CAST, "spell": spell_id, "slot_level": slot, "object": true, "kinds": object_kinds, "fields": fields}
			hint = "%s: click a %s." % [def.display_name, " or ".join(object_kinds)]
			revision += 1
			return {}
		if kinds.has("landmark") and not fields.has("target_kind"):
			var marks := DictUtil.to_string_array(def.raw_effect.get("landmarks", ["arrival"]))
			fields["target_kind"] = "landmark"
			fields["target_id"] = marks[0] if not marks.is_empty() else "arrival"
		return cast_intent(spell_id, player_id, slot, fields)
	var extra := {"metamagic": metamagic.duplicate()}
	for key: String in ["mode", "invocation", "overchannel", "target_kind", "target_id"]:
		if extra_fields.has(key):
			extra[key] = extra_fields[key]
	var warning := concentration_warning(spell_id)
	if def.is_area():
		if ClientState.is_self_centred(def):
			targeting = {}
			extra["sculpt"] = sculpt_ids(def, area_preview_tiles(def, player_position()))
			return cast_intent(spell_id, player_id, slot, extra)
		targeting = {"mode": TARGET_CAST, "spell": spell_id, "slot_level": slot, "area": true, "metamagic": metamagic.duplicate(), "fields": extra.duplicate()}
		hint = "%s: click %s." % [def.display_name, "a direction to aim the %s" % def.area_shape if def.range_ft == 0 else "the point at the centre of the %s" % def.area_shape]
	elif def.target == SpellDefinition.TARGET_SELF:
		targeting = {}
		return cast_intent(spell_id, player_id, slot, extra)
	else:
		targeting = {"mode": TARGET_CAST, "spell": spell_id, "slot_level": slot, "metamagic": metamagic.duplicate(), "fields": extra.duplicate()}
		hint = "%s: click a target%s%s." % [def.display_name, "" if def.is_harmful() else " (yourself or an ally)",
			" (Twinned: then a second one)" if metamagic.has("twinned_spell") else ""]
	if not warning.is_empty():
		hint += " " + warning
	revision += 1
	return {}


# --- features -----------------------------------------------------------------------

## Class features usable in combat (Encounter.USABLE_FEATURES the sheet has,
## plus bonus-action attack shortcuts): {"id", "name", "remaining", "max"
## (-1 = no resource), "resource", "cost" ("action"|"bonus"|"free"),
## "modes": Array[String], "error"}.
func feature_entries() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if sheet == null:
		return out
	for f in Encounter.USABLE_FEATURES:
		if not has_usable_feature(f):
			continue
		var res := ClientState.feature_resource(f)
		var modes: Array[String] = []
		modes.assign(FEATURE_MODES.get(f, []))
		if f == ClassDefinition.FEATURE_RAGE and sheet.has_feature("frenzy"):
			modes.assign(["rage", "frenzy"])
		out.append({"id": f, "name": ClientState.feature_name(f),
			"remaining": sheet.class_resource(res) if not res.is_empty() else -1,
			"max": sheet.resource_max(res) if not res.is_empty() else -1, "resource": res,
			"cost": ClientState.feature_cost(f), "modes": modes, "error": feature_error(f)})
	var pseudo: Array[String] = []
	if sheet.has_feature(ClassDefinition.FEATURE_MARTIAL_ARTS):
		pseudo.append(FEATURE_MARTIAL_ARTS_STRIKE)
	if off_hand_attack_index() >= 0:
		pseudo.append(FEATURE_OFF_HAND_ATTACK)
	if has_usable_feature("flurry_of_blows"):
		pseudo.append(FEATURE_FLURRY_STRIKE)
	if sheet.has_feature("frenzy"):
		pseudo.append(FEATURE_FRENZY_ATTACK)
	for f in pseudo:
		out.append({"id": f, "name": ClientState.feature_name(f), "remaining": -1, "max": -1, "resource": "",
			"cost": "bonus", "modes": [] as Array[String], "error": feature_error(f)})
	return out


## Whether the sheet can use a use_feature id (Encounter._has_usable_feature).
func has_usable_feature(feature: String) -> bool:
	if sheet == null:
		return false
	if sheet.has_feature(feature):
		return true
	if Encounter.KI_FEATURES.has(feature):
		return sheet.has_feature("ki")
	if feature == "pact_weapon":
		return sheet.has_feature("pact_of_the_blade")
	return false


## The class resource a feature spends ("" = none), as Encounter._feature_resource;
## Stunning Strike spends ki too.
static func feature_resource(feature: String) -> String:
	if Encounter.KI_FEATURES.has(feature) or feature == "stunning_strike":
		return "ki"
	if Encounter.CHANNEL_DIVINITY_FEATURES.has(feature):
		return "channel_divinity"
	if feature == "font_of_magic":
		return "sorcery_points"
	if CharacterSheet.RESOURCE_FEATURES.has(feature):
		return feature
	return ""


## "action", "bonus" or "free" (Encounter._feature_cost).
static func feature_cost(feature: String) -> String:
	if ACTION_FEATURES.has(feature):
		return "action"
	if FREE_FEATURES.has(feature):
		return "free"
	return "bonus"


func feature_error(feature: String, mode: String = "") -> String:
	if sheet == null:
		return "no character"
	if not is_my_turn():
		return "only on your turn in combat"
	match feature:
		FEATURE_MARTIAL_ARTS_STRIKE:
			return bonus_attack_error(get_attack(available_attacks().size() - 1), true)
		FEATURE_OFF_HAND_ATTACK:
			var index := off_hand_attack_index()
			return "no off-hand weapon" if index < 0 else bonus_attack_error(get_attack(index))
		FEATURE_FLURRY_STRIKE:
			if bonus_attacks_remaining <= 0 or bonus_attack_source != "flurry_of_blows":
				return "use Flurry of Blows first"
			return ""
		FEATURE_FRENZY_ATTACK:
			return bonus_attack_error(get_attack(selected_attack))
	if not has_usable_feature(feature):
		return "you lack %s" % ClientState.feature_name(feature)
	var res := ClientState.feature_resource(feature)
	if not res.is_empty() and feature != "font_of_magic" and sheet.class_resource(res) <= 0:
		return "no %s left" % ("uses" if res == feature else ClientState.feature_name(res).to_lower())
	match ClientState.feature_cost(feature):
		"action":
			if action_used:
				return "action already used"
		"bonus":
			if bonus_action_used:
				return "bonus action already used"
	match feature:
		ClassDefinition.FEATURE_RAGE:
			if status_tags(player_id).has("raging"):
				return "already raging"
		"action_surge":
			if action_surged:
				return "once per turn"
		"flurry_of_blows":
			if not attack_action_taken:
				return "take the Attack action first"
		"step_of_the_wind", "cunning_action":
			if not mode.is_empty() and not mode in ["dash", "disengage"]:
				return "choose dash or disengage"
		"preserve_life":
			if preserve_life_allocations().is_empty():
				return "no ally in range below half hit points"
		"font_of_magic":
			if font_of_magic_options().filter(func(o: Dictionary) -> bool: return str(o["error"]).is_empty()).is_empty():
				return "nothing to convert"
		"pact_weapon":
			if status_tags(player_id).has(STATUS_TAGS["pact_weapon"]):
				return "the pact weapon is already in hand"
	return ""


## Why a bonus-action attack with `attack` is not possible now ("" = it is),
## as Encounter._bonus_attack_source: Flurry of Blows strikes (unarmed), the
## off-hand attack or Martial Arts strike after the Attack action, Frenzy
## (melee, raging and frenzied, from the turn after the rage started).
func bonus_attack_error(attack: Dictionary, martial_arts: bool = false) -> String:
	if not is_my_turn():
		return "not your turn"
	var unarmed: bool = attack.get("unarmed", false) == true
	if bonus_attacks_remaining > 0:
		return "" if unarmed else "Flurry of Blows strikes are unarmed strikes"
	if bonus_action_used:
		return "bonus action already used"
	if attack.get("off_hand", false) == true:
		return "" if attack_action_taken else "take the Attack action first"
	var martial := sheet != null and sheet.has_feature(ClassDefinition.FEATURE_MARTIAL_ARTS)
	if unarmed and martial:
		return "" if attack_action_taken else "take the Attack action first"
	if martial_arts:
		return "you lack Martial Arts"
	var tags := status_tags(player_id)
	if tags.has("frenzied") and tags.has("raging") and not attack.is_empty() and not ClientState.is_ranged_attack(attack):
		return "the Frenzy attack starts on the turn after you rage" if rage_started_this_turn else ""
	return "no bonus-action attack"


## Index of the off-hand attack entry, or -1.
func off_hand_attack_index() -> int:
	var list := available_attacks()
	for i in range(list.size()):
		if list[i].get("off_hand", false) == true:
			return i
	return -1


## Starts a feature. Self features return their intent; lay_on_hands (amount
## from the pool) and bardic_inspiration enter targeting mode; the bonus
## attacks (Martial Arts, off-hand, Flurry strike, Frenzy) target like an
## attack; `mode` picks step_of_the_wind / cunning_action ("dash" /
## "disengage"), font_of_magic ("create_slot" / "convert_slot" with
## slot_level) and rage ("frenzy" = Frenzy); preserve_life spreads its pool
## over the wounded allies in range (preserve_life_allocations).
func begin_feature(feature: String, amount: int = 0, mode: String = "", slot_level: int = 0) -> Dictionary:
	hint = feature_error(feature, mode)
	if not hint.is_empty():
		return {}
	match feature:
		ClassDefinition.FEATURE_LAY_ON_HANDS:
			var pool := sheet.class_resource(feature)
			targeting = {"mode": TARGET_FEATURE, "feature": feature, "amount": clampi(amount if amount > 0 else pool, 1, pool)}
			hint = "Lay on Hands (%d HP): click yourself or an adjacent ally." % int(targeting["amount"])
		ClassDefinition.FEATURE_BARDIC_INSPIRATION:
			targeting = {"mode": TARGET_FEATURE, "feature": feature, "amount": 0}
			hint = "Bardic Inspiration: click an ally within %d tiles." % BARDIC_INSPIRATION_RANGE
		FEATURE_MARTIAL_ARTS_STRIKE, FEATURE_FLURRY_STRIKE:
			targeting = {"mode": TARGET_ATTACK, "attack_index": available_attacks().size() - 1, "bonus": true}
			hint = "%s: click an adjacent hostile." % ClientState.feature_name(feature)
		FEATURE_OFF_HAND_ATTACK:
			targeting = {"mode": TARGET_ATTACK, "attack_index": off_hand_attack_index(), "bonus": true}
			hint = "Off-hand attack: click a hostile."
		FEATURE_FRENZY_ATTACK:
			var melee := selected_attack if not ClientState.is_ranged_attack(get_attack(selected_attack)) else 0
			targeting = {"mode": TARGET_ATTACK, "attack_index": melee, "bonus": true}
			hint = "Frenzy: click an adjacent hostile."
		"step_of_the_wind", "cunning_action":
			targeting = {}
			return feature_intent(feature, "", 0, {"mode": mode if not mode.is_empty() else "dash"})
		"font_of_magic":
			var m := mode if not mode.is_empty() else "create_slot"
			for o in font_of_magic_options():
				if str(o["mode"]) == m and int(o["slot_level"]) == slot_level:
					hint = str(o["error"])
					if not hint.is_empty():
						return {}
					targeting = {}
					return feature_intent(feature, "", 0, {"mode": m, "slot_level": slot_level})
			hint = "choose a slot level"
			return {}
		"preserve_life":
			targeting = {}
			return feature_intent(feature, "", 0, {"allocations": preserve_life_allocations()})
		ClassDefinition.FEATURE_RAGE:
			targeting = {}
			return feature_intent(feature, "", 0, {"frenzy": true} if mode == "frenzy" else {})
		_:
			targeting = {}
			return feature_intent(feature)
	revision += 1
	return {}


## Preserve Life: up to 5 x level hit points over living allies within 6
## tiles below half their maximum (most hurt first), none past half.
## {id: hp}; {} when nobody qualifies.
func preserve_life_allocations() -> Dictionary:
	var out := {}
	if sheet == null:
		return out
	var budget := 5 * sheet.level
	var me := player_position()
	var allies: Array[Dictionary] = []
	var ids: Array[String] = order.duplicate() if in_encounter else [player_id] as Array[String]
	for id in ids:
		var e := get_entity(id)
		if e.is_empty() or str(e["kind"]) != KIND_PLAYER or bool(e["dead"]):
			continue
		var hp := int(e.get("hp", -1))
		var max_hp := int(e.get("max_hp", -1))
		if id == player_id:
			hp = sheet.current_hp
			max_hp = sheet.max_hp
		if hp < 0 or max_hp <= 0:
			continue
		var p: Vector2i = e["position"]
		if GridMath.distance_tiles(me, p) > CHANNEL_DIVINITY_RANGE:
			continue
		var room := floori(max_hp / 2.0) - hp
		if room > 0:
			allies.append({"id": id, "hp": hp, "room": room})
	allies.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a["hp"]) < int(b["hp"]) or (int(a["hp"]) == int(b["hp"]) and str(a["id"]) < str(b["id"])))
	for a in allies:
		if budget <= 0:
			break
		var give := mini(budget, int(a["room"]))
		out[str(a["id"])] = give
		budget -= give
	return out


## Font of Magic choices: {"mode", "slot_level", "cost" (points spent, or
## gained for convert_slot), "label", "error"}: create a slot of level 1..5
## from sorcery points, or convert a slot into points.
func font_of_magic_options() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if sheet == null or not sheet.has_feature("font_of_magic"):
		return out
	var points := sheet.class_resource("sorcery_points")
	var cls := sheet.class_definition(_content())
	for lvl in range(1, Progression.MAX_CREATED_SLOT + 1):
		var cost: int = Progression.SLOT_CREATION_COST.get(lvl, 99)
		if cls != null and cls.sorcery_slot_costs.has(lvl):
			cost = DictUtil.to_int(cls.sorcery_slot_costs[lvl], cost)
		out.append({"mode": "create_slot", "slot_level": lvl, "cost": cost,
			"label": "Create a %s-level slot (%d points)" % [ClientState.ordinal(lvl), cost],
			"error": "" if points >= cost else "needs %d sorcery points" % cost})
	for lvl in range(1, sheet.spell_slots_max.size() + 1):
		if sheet.spell_slots_max[lvl - 1] <= 0:
			continue
		out.append({"mode": "convert_slot", "slot_level": lvl, "cost": lvl,
			"label": "Convert a %s-level slot (+%d points)" % [ClientState.ordinal(lvl), lvl],
			"error": "" if sheet.slots_left(lvl) > 0 else "no %s-level slot left" % ClientState.ordinal(lvl)})
	return out


## Ranged / thrown attack (or any attack) via an explicit target pick.
func begin_attack_targeting(attack_index: int = -1) -> void:
	var index := selected_attack if attack_index < 0 else attack_index
	targeting = {"mode": TARGET_ATTACK, "attack_index": index, "bonus": false}
	hint = "Click a hostile to attack with %s." % str(get_attack(index).get("name", "the attack"))
	revision += 1


func is_targeting() -> bool:
	return not targeting.is_empty()


func cancel_targeting() -> void:
	if not targeting.is_empty():
		targeting = {}
		hint = ""
		revision += 1


## Id of a living creature (any kind) on tile, or "".
func creature_at(tile: Vector2i) -> String:
	if has_player_entity() and player_position() == tile and not bool(get_entity(player_id)["dead"]):
		return player_id
	for id: String in entities.keys():
		var e: Dictionary = entities[id]
		var p: Vector2i = e["position"]
		if p == tile and not bool(e["dead"]):
			return id
	return ""


func _targeted_intent(tile: Vector2i) -> Dictionary:
	if str(targeting.get("mode", "")) == TARGET_CAST and bool(targeting.get("object", false)):
		return _object_cast_intent(tile)
	if str(targeting.get("mode", "")) == TARGET_CONTROL:
		return _control_click_intent(tile)
	if str(targeting.get("mode", "")) == TARGET_CAST and bool(targeting.get("area", false)):
		var area_spell := str(targeting["spell"])
		var def := spell_def(area_spell)
		hint = area_point_error(area_spell, tile)
		if not hint.is_empty() or def == null:
			return {}
		var meta: Array[String] = []
		meta.assign(targeting.get("metamagic", []))
		var area_extra: Dictionary = (targeting.get("fields", {}) as Dictionary).duplicate()
		area_extra.merge({"point": GridMath.vec_to_arr(tile), "metamagic": meta, "sculpt": sculpt_ids(def, area_preview_tiles(def, tile))}, true)
		return cast_intent(area_spell, player_id, int(targeting.get("slot_level", 0)), area_extra)
	var target := creature_at(tile)
	if target.is_empty():
		hint = "No creature there."
		return {}
	match str(targeting.get("mode", "")):
		TARGET_CAST:
			var spell_id := str(targeting["spell"])
			hint = cast_target_error(spell_id, target)
			if not hint.is_empty():
				return {}
			var meta: Array[String] = []
			meta.assign(targeting.get("metamagic", []))
			var extra: Dictionary = (targeting.get("fields", {}) as Dictionary).duplicate()
			extra["metamagic"] = meta
			if meta.has("twinned_spell"):
				var first := str(targeting.get("first_target", ""))
				if first.is_empty():
					targeting["first_target"] = target
					hint = "Twinned Spell: click a second, different target."
					revision += 1
					return {}
				if first == target:
					hint = "Twinned Spell needs a different second target."
					return {}
				extra["twin_target"] = target
				target = first
			return cast_intent(spell_id, target, int(targeting.get("slot_level", 0)), extra)
		TARGET_FEATURE:
			var feature := str(targeting["feature"])
			hint = feature_target_error(feature, target)
			if hint.is_empty():
				return feature_intent(feature, target, int(targeting.get("amount", 0)))
		TARGET_ATTACK:
			var index := int(targeting.get("attack_index", selected_attack))
			var bonus := bool(targeting.get("bonus", false))
			hint = attack_error(target, index, bonus)
			if hint.is_empty():
				return attack_intent(target, index, bonus)
	return {}


func feature_target_error(feature: String, target: String) -> String:
	var e := get_entity(target)
	if e.is_empty() or bool(e["dead"]):
		return "no creature there"
	if str(e["kind"]) == KIND_MONSTER:
		return "%s needs an ally" % ClientState.feature_name(feature)
	var to: Vector2i = e["position"]
	var dist := GridMath.distance_tiles(player_position(), to)
	if feature == ClassDefinition.FEATURE_BARDIC_INSPIRATION:
		if target == player_id:
			return "inspire someone else"
		if dist > BARDIC_INSPIRATION_RANGE:
			return "out of range"
		if bool(e.get("down", false)):
			return "%s cannot hear you" % display_name(target)
	elif feature == ClassDefinition.FEATURE_LAY_ON_HANDS and target != player_id and dist > 1:
		return "touch range: stand next to them"
	return ""


# --- inventory ----------------------------------------------------------------------

## Inventory rows (gold excluded, see gold()): {"item", "name", "kind", "qty",
## "weight" (total), "equipped": Array[String] slots holding it,
## "equip_slots": Array[String] slots it fits, "usable": bool}.
func inventory_rows() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if sheet == null:
		return out
	for entry in sheet.inventory:
		var id := str(entry.get("item", ""))
		if id == CharacterSheet.GOLD_ITEM:
			continue
		var qty := DictUtil.to_int(entry.get("qty", 1), 1)
		var def := item_def(id)
		var slots_held: Array[String] = []
		for slot in CharacterSheet.SLOTS:
			if sheet.equipped_item(slot) == id:
				slots_held.append(slot)
		out.append({
			"item": id, "name": def.display_name if def != null else item_name(id),
			"kind": def.kind if def != null else ItemDefinition.KIND_MISC, "qty": qty,
			"weight": (def.weight * qty) if def != null else 0.0, "equipped": slots_held,
			"equip_slots": equip_slots_for(id), "usable": def != null and def.has_implemented_use(),
			"properties": weapon_properties(id),
		})
	return out


## Weapon properties that matter for fighting styles and two-weapon fighting:
## "two-handed", "heavy", "light", "versatile (1d10)", "finesse", "thrown",
## "ranged" ([] for non-weapons).
func weapon_properties(item_id: String) -> Array[String]:
	var out: Array[String] = []
	var w := CharacterSheet.weapon_for_item(item_id, _content())
	if w == null:
		return out
	if w.is_two_handed():
		out.append("two-handed")
	if w.has_property("heavy"):
		out.append("heavy")
	if w.has_property("light"):
		out.append("light")
	if w.has_property("versatile"):
		out.append("versatile (%s)" % w.versatile_damage if not w.versatile_damage.is_empty() else "versatile")
	if w.is_finesse():
		out.append("finesse")
	if w.is_thrown():
		out.append("thrown")
	if w.ranged:
		out.append("ranged")
	return out


## Equipment slots an item can go into (main hand for weapons, off hand for
## shields and light weapons, armor for armor).
func equip_slots_for(item_id: String) -> Array[String]:
	var out: Array[String] = []
	var def := item_def(item_id)
	if def == null:
		return out
	match def.kind:
		ItemDefinition.KIND_WEAPON:
			out.append(CharacterSheet.SLOT_MAIN_HAND)
			var w := CharacterSheet.weapon_for_item(item_id, _content())
			if w != null and w.has_property("light"):
				out.append(CharacterSheet.SLOT_OFF_HAND)
		ItemDefinition.KIND_SHIELD:
			out.append(CharacterSheet.SLOT_OFF_HAND)
		ItemDefinition.KIND_ARMOR:
			out.append(CharacterSheet.SLOT_ARMOR)
	return out


func gold() -> int:
	return sheet.gold() if sheet != null else 0


func carried_weight() -> float:
	var total := 0.0
	if sheet == null:
		return total
	for entry in sheet.inventory:
		var def := item_def(str(entry.get("item", "")))
		if def != null:
			total += def.weight * DictUtil.to_int(entry.get("qty", 1), 1)
	return total


## Equipment changes (equip / unequip / drop) happen out of combat only.
func can_manage_equipment() -> bool:
	return mode == Mode.EXPLORING and not in_encounter and is_player_conscious()


## "" when the item can be used now (out of combat, or on your combat turn
## with the action / bonus action it needs).
func use_item_error(item_id: String) -> String:
	var def := item_def(item_id)
	if def == null or sheet == null or not sheet.has_item(item_id):
		return "not carried"
	if not def.has_implemented_use():
		return "cannot be used"
	if mode == Mode.EXPLORING and not in_encounter:
		return "" if is_player_conscious() else "you are down"
	if not is_my_turn():
		return "wait for your turn"
	if def.use_action == "bonus_action":
		return "bonus action already used" if bonus_action_used else ""
	return "action already used" if action_used else ""


## "AC 16: chain mail 16, DEX 0, shield +2" (how armor_class() adds up).
func ac_breakdown() -> String:
	if sheet == null:
		return ""
	var ac := sheet.armor_class()
	var raw_dex := sheet.ability_modifier(Ability.Type.DEX)
	var parts: PackedStringArray = []
	var armor_id := sheet.equipped_item(CharacterSheet.SLOT_ARMOR)
	if sheet.armor_base > 0:
		var dex := raw_dex
		if sheet.armor_max_dex == 0:
			dex = 0
		elif sheet.armor_max_dex > 0:
			dex = mini(dex, sheet.armor_max_dex)
		var armor_label := item_name(armor_id).to_lower() if not armor_id.is_empty() else "armor"
		parts.append("%s %d" % [armor_label, sheet.armor_base])
		parts.append("DEX %s" % ClientState._signed_or_zero(dex))
	else:
		var base := 10
		var label := "unarmored"
		var extra := ""
		if sheet.active_buffs.has(CharacterSheet.BUFF_MAGE_ARMOR) and CharacterSheet.MAGE_ARMOR_BASE + raw_dex + sheet.shield_bonus >= ac:
			base = CharacterSheet.MAGE_ARMOR_BASE
			label = "mage armor"
		elif sheet.has_feature("unarmored_defense_con") and 10 + raw_dex + sheet.ability_modifier(Ability.Type.CON) + sheet.shield_bonus == ac:
			label = "unarmored defense"
			extra = "CON %s" % ClientState._signed_or_zero(sheet.ability_modifier(Ability.Type.CON))
		elif sheet.has_feature("unarmored_defense_wis") and sheet.shield_bonus == 0 and 10 + raw_dex + sheet.ability_modifier(Ability.Type.WIS) == ac:
			label = "unarmored defense"
			extra = "WIS %s" % ClientState._signed_or_zero(sheet.ability_modifier(Ability.Type.WIS))
		parts.append("%s %d" % [label, base])
		parts.append("DEX %s" % ClientState._signed_or_zero(raw_dex))
		if not extra.is_empty():
			parts.append(extra)
	parts.append("shield %+d" % sheet.shield_bonus)
	return "AC %d: %s" % [ac, ", ".join(parts)]


static func _signed_or_zero(v: int) -> String:
	return "0" if v == 0 else "%+d" % v


## "Slots: 1st 2/2  2nd 0/1" ("" for non-casters). Pact magic reads
## "Pact slots: 2nd 2/2 (short rest)". Slots created beyond the maximum
## (Font of Magic) show as "3/2".
func slots_text() -> String:
	if sheet == null or sheet.spell_slots_max.is_empty():
		return ""
	var parts: PackedStringArray = []
	for i in range(maxi(sheet.spell_slots_max.size(), sheet.spell_slots.size())):
		var max_n := sheet.spell_slots_max[i] if i < sheet.spell_slots_max.size() else 0
		var left := sheet.spell_slots[i] if i < sheet.spell_slots.size() else 0
		if max_n > 0 or left > 0:
			parts.append("%s %d/%d" % [ClientState.ordinal(i + 1), left, max_n])
	if parts.is_empty():
		return ""
	if sheet.slot_recovery == ClassDefinition.SLOT_RECOVERY_SHORT:
		return "Pact slots: " + "  ".join(parts) + " (short rest)"
	return "Slots: " + "  ".join(parts)


## The class resources the character has: [{"id", "name", "remaining", "max",
## "short_rest": bool, "die" (Bardic Inspiration, else 0)}].
func resource_entries() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if sheet == null:
		return out
	for r in CharacterSheet.RESOURCE_FEATURES:
		if not sheet.has_feature(str(CharacterSheet.RESOURCE_OWNERS.get(r, r))):
			continue
		out.append({"id": r, "name": ClientState.feature_name(r), "remaining": sheet.class_resource(r),
			"max": sheet.resource_max(r), "short_rest": sheet.resource_short_rest(r),
			"die": sheet.bardic_inspiration_die() if r == "bardic_inspiration" else 0})
	return out


## "Second Wind 1/1  Ki 3/5  Bardic Inspiration 3/3 (d6)" ("" without resources).
func resources_text() -> String:
	var parts: PackedStringArray = []
	for r in resource_entries():
		var text := "%s %d/%d" % [str(r["name"]), int(r["remaining"]), int(r["max"])]
		if int(r["die"]) > 0:
			text += " (d%d)" % int(r["die"])
		parts.append(text)
	return "  ".join(parts)


## Status tags of a combatant: effects ("dodging", "raging", "marked", ...),
## then conditions with their remaining duration ("stunned (1 turn)",
## "restrained (save DC 13 STR)"), lasting sheet conditions of the player, and
## "concentrating: Hex".
func status_tags(id: String) -> PackedStringArray:
	var out: PackedStringArray = []
	if statuses.has(id):
		var list: Array[String] = statuses[id]
		for effect in list:
			out.append(STATUS_TAGS.get(effect, effect.replace("_", " ")))
	for entry in conditions_of(id):
		out.append(condition_text(entry))
	if id == player_id and sheet != null:
		var listed: Array[String] = []
		for entry in conditions_of(id):
			listed.append(str(entry["condition"]))
		for c in sheet.conditions:
			if not listed.has(c):
				out.append(c.replace("_", " "))
	if concentration.has(id):
		out.append("concentrating: %s" % spell_name(str(concentration[id])))
	return out


## The condition entries the client knows for a combatant (encounter only).
func conditions_of(id: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if conditions.has(id):
		out.assign(conditions[id])
	return out


## Whether a combatant has a condition (encounter entries; the player's
## lasting sheet conditions too). Stunned / paralyzed count as incapacitated.
func has_condition(id: String, condition: String) -> bool:
	for entry in conditions_of(id):
		var c := str(entry["condition"])
		if c == condition or (condition == "incapacitated" and c in ["stunned", "paralyzed"]):
			return true
	return id == player_id and sheet != null and sheet.conditions.has(condition)


## Speed 0 (stunned, paralyzed, restrained, grappled).
func is_immobilized(id: String) -> bool:
	for c in IMMOBILIZING:
		if has_condition(id, c):
			return true
	return false


## "stunned (1 turn)", "frightened (9 rounds)", "prone", "poisoned (ends this
## turn)", "restrained (save DC 13 STR)".
func condition_text(entry: Dictionary) -> String:
	var name := str(entry.get("condition", "")).replace("_", " ")
	var duration: Dictionary = entry.get("duration", {}) if typeof(entry.get("duration")) == TYPE_DICTIONARY else {}
	var left := DictUtil.to_int(entry.get("turns_left", 0), 0)
	match str(duration.get("type", "")):
		Conditions.DURATION_SOURCE_NEXT_TURN:
			return "%s (%d turn%s)" % [name, maxi(1, left), "" if maxi(1, left) == 1 else "s"]
		Conditions.DURATION_TARGET_TURN_END:
			return "%s (ends this turn)" % name
		Conditions.DURATION_ROUNDS:
			return "%s (%d round%s)" % [name, maxi(1, left), "" if maxi(1, left) == 1 else "s"]
		Conditions.DURATION_SAVE_ENDS:
			return "%s (save DC %d %s)" % [name, DictUtil.to_int(duration.get("dc", 10), 10), str(duration.get("ability", "WIS"))]
	return name


## "" or a warning that casting spell_id ends the player's concentration.
func concentration_warning(spell_id: String) -> String:
	var def := spell_def(spell_id)
	if def == null or not def.concentration or not concentration.has(player_id):
		return ""
	return "Casting %s ends your concentration on %s." % [def.display_name, spell_name(str(concentration[player_id]))]


# --- attack flow (Extra Attack, options) ----------------------------------------------

## Attack rolls per Attack action (Extra Attack).
func attacks_per_action() -> int:
	return sheet.attacks_per_action() if sheet != null else 1


## "Attack 1/2" before the first of several attacks, "Attack 2/2" while the
## Attack action has rolls left; "" with a single attack or none left.
func attack_counter_text() -> String:
	var n := attacks_per_action()
	if n <= 1 or not is_my_turn():
		return ""
	if not action_used:
		return "Attack 1/%d" % n
	if attack_action_taken and attacks_remaining > 0:
		return "Attack %d/%d" % [n - attacks_remaining + 1, n]
	return ""


## Which attack options the character has: subset of reckless, smite, stun, technique.
func attack_option_kinds() -> Array[String]:
	var out: Array[String] = []
	if sheet == null:
		return out
	if sheet.has_feature("reckless_attack"):
		out.append("reckless")
	if sheet.has_feature("divine_smite"):
		out.append("smite")
	if sheet.has_feature("stunning_strike"):
		out.append("stun")
	if sheet.has_feature("open_hand_technique"):
		out.append("technique")
	if sheet.has_feature("pact_of_the_chain") and not familiar_id().is_empty():
		out.append("via_familiar")
	if sheet.has_feature("quivering_palm"):
		out.append("quivering_palm")
	if sheet.has_feature("hurl_through_hell"):
		out.append("hurl_through_hell")
	return out


func set_attack_option(key: String, value: Variant) -> void:
	if not attack_options.has(key):
		return
	match key:
		"reckless", "stun", "via_familiar", "quivering_palm", "hurl_through_hell":
			attack_options[key] = value == true
		"smite":
			attack_options[key] = clampi(DictUtil.to_int(value, 0), 0, Messages.MAX_SLOT_LEVEL)
		"technique":
			attack_options[key] = str(value) if Messages.TECHNIQUES.has(str(value)) else ""
	revision += 1


## Slot levels Divine Smite could use now (slots left).
func smite_levels() -> Array[int]:
	var out: Array[int] = []
	if sheet == null:
		return out
	for lvl in range(1, sheet.spell_slots.size() + 1):
		if sheet.slots_left(lvl) > 0:
			out.append(lvl)
	return out


## The attack_options that apply to attacks[index] now, as intent fields:
## reckless (first attack of the turn, melee STR, not a bonus attack), smite
## (melee, a slot of that level left), stun (melee, 1 ki), technique (a
## Flurry of Blows strike).
func attack_option_fields(index: int, bonus: bool) -> Dictionary:
	var out := {}
	var attack := get_attack(index)
	if sheet == null or attack.is_empty():
		return out
	var melee := not ClientState.is_ranged_attack(attack)
	if bool(attack_options.get("reckless", false)) and sheet.has_feature("reckless_attack") and not bonus \
			and not attack_action_taken and melee and str(attack.get("ability", "STR")) == "STR":
		out["reckless"] = true
	var smite := DictUtil.to_int(attack_options.get("smite", 0), 0)
	if smite > 0 and sheet.has_feature("divine_smite") and melee and sheet.slots_left(smite) > 0:
		out["smite"] = smite
	if bool(attack_options.get("stun", false)) and sheet.has_feature("stunning_strike") and melee and sheet.class_resource("ki") >= 1:
		out["stun"] = true
	var technique := str(attack_options.get("technique", ""))
	if not technique.is_empty() and sheet.has_feature("open_hand_technique") and bonus \
			and bonus_attacks_remaining > 0 and bonus_attack_source == "flurry_of_blows":
		out["technique"] = technique
	if bool(attack_options.get("quivering_palm", false)) and sheet.has_feature("quivering_palm") and not bonus \
			and str(attack.get("name", "")).to_lower().contains("unarmed") and sheet.class_resource("ki") >= 3:
		out["quivering_palm"] = true
	if bool(attack_options.get("hurl_through_hell", false)) and sheet.has_feature("hurl_through_hell") \
			and sheet.class_resource("hurl_through_hell") > 0:
		out["hurl_through_hell"] = true
	return out


# --- metamagic ------------------------------------------------------------------------

## Sorcery points a metamagic option costs for spell (Encounter._metamagic_cost).
static func metamagic_cost(id: String, spell: SpellDefinition) -> int:
	match id:
		"quickened_spell":
			return 2
		"empowered_spell":
			return 1
		"twinned_spell":
			return maxi(1, spell.level if spell != null else 1)
	return 0


static func metamagic_name(id: String) -> String:
	return id.replace("_spell", "").capitalize()


## The modelled metamagic options the character knows, for spell_id:
## [{"id", "name", "cost", "error"}].
func metamagic_options(spell_id: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if sheet == null:
		return out
	var def := spell_def(spell_id)
	for m in sheet.metamagic:
		if not Features.IMPLEMENTED_METAMAGIC.has(m):
			continue
		var one: Array[String] = [m]
		out.append({"id": m, "name": ClientState.metamagic_name(m), "cost": ClientState.metamagic_cost(m, def),
			"error": metamagic_error(spell_id, one)})
	return out


## "" when the metamagic options can apply to spell_id (Encounter._check_cast rules).
func metamagic_error(spell_id: String, metamagic: Array[String]) -> String:
	if metamagic.is_empty():
		return ""
	var def := spell_def(spell_id)
	if def == null or sheet == null:
		return "unknown spell"
	var cost := 0
	for m in metamagic:
		if not sheet.metamagic.has(m):
			return "you do not know %s" % ClientState.metamagic_name(m)
		if not Features.IMPLEMENTED_METAMAGIC.has(m):
			return "%s is not modelled yet" % ClientState.metamagic_name(m)
		cost += ClientState.metamagic_cost(m, def)
	if metamagic.has("quickened_spell") and metamagic.has("twinned_spell"):
		return "only one of Quickened and Twinned per casting"
	if metamagic.has("quickened_spell") and def.uses_bonus_action():
		return "Quickened needs a spell cast with an action"
	if metamagic.has("twinned_spell") and (def.is_area() or def.range_ft == 0 or def.target == SpellDefinition.TARGET_SELF):
		return "Twinned needs a single-target spell"
	if sheet.class_resource("sorcery_points") < cost:
		return "needs %d sorcery points" % cost
	return ""


# --- area spells ------------------------------------------------------------------------

## Range-self spheres / cubes / cylinders are centred on the caster (no point).
static func is_self_centred(spell: SpellDefinition) -> bool:
	return spell != null and spell.range_ft == 0 and spell.area_shape in ["sphere", "cube", "cylinder"]


## "" when tile is a valid point for area spell_id (Encounter._check_area).
func area_point_error(spell_id: String, tile: Vector2i) -> String:
	var def := spell_def(spell_id)
	if def == null or not def.is_area():
		return "not an area spell"
	if ClientState.is_self_centred(def):
		return ""
	if region.has_area() and not region.has_point(tile):
		return "outside the battle area"
	var me := player_position()
	if def.range_ft == 0:
		return "aim away from yourself" if tile == me else ""
	if GridMath.distance_tiles(me, tile) > def.range_tiles():
		return "out of range"
	if floor_data != null and not sight_map().has_line_of_sight(me, tile):
		return "no line of sight"
	return ""


## Tiles an area spell covers when aimed / centred at tile (cones and lines
## from the player toward tile; self-centred areas around the player).
func area_preview_tiles(def: SpellDefinition, tile: Vector2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var wm := movement_map()
	if def == null or not def.is_area() or wm == null:
		return out
	var me := player_position()
	var point := me if ClientState.is_self_centred(def) else tile
	return AreaOfEffect.tiles(def.area_shape, def.area_size_tiles(), me, point, wm)


## Allies Sculpt Spells keeps out of an evocation area (at most 1 + level):
## the other player characters of the encounter on the covered tiles (SRD:
## creatures other than the caster).
func sculpt_ids(def: SpellDefinition, tiles: Array[Vector2i]) -> Array[String]:
	var out: Array[String] = []
	if def == null or sheet == null or not sheet.has_feature("sculpt_spells") or def.school.to_lower() != "evocation":
		return out
	var ids: Array[String] = order.duplicate() if in_encounter else [player_id] as Array[String]
	for id in ids:
		if out.size() >= 1 + def.level:
			break
		var e := get_entity(id)
		if e.is_empty() or str(e["kind"]) != KIND_PLAYER or bool(e["dead"]):
			continue
		if id == player_id:
			continue
		var p: Vector2i = e["position"]
		if tiles.has(p):
			out.append(id)
	return out


## What an area spell in targeting mode would do at tile: {"tiles":
## Array[Vector2i], "affected": Array[String] (creatures caught, initiative
## order), "sculpted": Array[String], "error": String}. {} outside area targeting.
func area_preview(tile: Vector2i) -> Dictionary:
	if str(targeting.get("mode", "")) != TARGET_CAST or not bool(targeting.get("area", false)):
		return {}
	var def := spell_def(str(targeting["spell"]))
	var error := area_point_error(str(targeting["spell"]), tile)
	var tiles: Array[Vector2i] = []
	if error.is_empty():
		tiles = area_preview_tiles(def, tile)
	var sculpted := sculpt_ids(def, tiles)
	var affected: Array[String] = []
	var ids: Array[String] = order.duplicate()
	if not in_encounter:
		for key: Variant in entities.keys():
			ids.append(str(key))
	for id in ids:
		var e := get_entity(id)
		if e.is_empty() or bool(e["dead"]) or sculpted.has(id):
			continue
		if id == player_id and ClientState.is_self_centred(def):
			continue
		var p: Vector2i = e["position"]
		if tiles.has(p):
			affected.append(id)
	return {"tiles": tiles, "affected": affected, "sculpted": sculpted, "error": error}


# --- rests ----------------------------------------------------------------------------

## Arcane / Natural Recovery the character could use after a short rest:
## {"feature", "budget", "max_slot_level", "levels": Array[int] (what the
## server picks for recover_slots: true)}; {} when none applies.
func slot_recovery() -> Dictionary:
	if sheet == null:
		return {}
	var opts := Rest.slot_recovery_options(sheet)
	if opts.is_empty():
		return {}
	var levels := ClientState.recovery_picks(sheet)
	if levels.is_empty():
		return {}
	var out := opts.duplicate()
	out["levels"] = levels
	return out


## Expended slots, highest level first, within the recovery budget (the same
## picks as InstanceServer.recovery_picks).
static func recovery_picks(s: CharacterSheet) -> Array[int]:
	var out: Array[int] = []
	var opts := Rest.slot_recovery_options(s)
	if opts.is_empty():
		return out
	var budget := DictUtil.to_int(opts.get("budget", 0), 0)
	var top := mini(DictUtil.to_int(opts.get("max_slot_level", 5), 5), s.spell_slots_max.size())
	for lvl in range(top, 0, -1):
		var missing := s.spell_slots_max[lvl - 1] - s.slots_left(lvl)
		while missing > 0 and budget >= lvl:
			out.append(lvl)
			budget -= lvl
			missing -= 1
	return out


# --- chests -------------------------------------------------------------------------

## Chests to draw: every known chest (hidden ones only once revealed).
func visible_chests() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for id: String in chests.keys():
		var c: Dictionary = chests[id]
		out.append(c)
	return out


## Id of a known chest on tile, or "".
func chest_at(tile: Vector2i) -> String:
	for id: String in chests.keys():
		var c: Dictionary = chests[id]
		var p: Vector2i = c["position"]
		if p == tile:
			return id
	return ""


## Unopened, known, and the player stands on it or next to it, out of combat.
func can_open_chest(chest_id: String) -> bool:
	if not chests.has(chest_id) or not has_player_entity() or in_encounter or mode != Mode.EXPLORING:
		return false
	var c: Dictionary = chests[chest_id]
	var p: Vector2i = c["position"]
	return not bool(c["opened"]) and GridMath.distance_tiles(player_position(), p) <= 1


## The nearest known unopened chest ("" if none).
func nearest_closed_chest() -> String:
	var best := ""
	var best_d := 1 << 30
	for id: String in chests.keys():
		var c: Dictionary = chests[id]
		if bool(c["opened"]):
			continue
		var p: Vector2i = c["position"]
		var d := GridMath.distance_tiles(player_position(), p)
		if d < best_d:
			best_d = d
			best = id
	return best


# --- level-ups ----------------------------------------------------------------------

func has_level_up_offer() -> bool:
	return not level_up_offer.is_empty()


## A pending offer can be answered now: out of combat and alive (the server
## also accepts it after the floor / set is cleared).
func can_level_up() -> bool:
	return has_level_up_offer() and not in_encounter and sheet != null and not sheet.dead \
		and mode in [Mode.EXPLORING, Mode.FLOOR_CLEARED, Mode.SET_CLEARED]


# --- floor objects (Round D) -----------------------------------------------------------

var _explore_cache: WalkMap = null
var _explore_cache_key: String = ""


## "You" for this character, else its display name.
func _who(id: String) -> String:
	return "You" if id == player_id else display_name(id)


func _apply_door_changed(result: Dictionary) -> void:
	var door_id := str(result["door_id"])
	var state := str(result["state"])
	var before := str(door_states.get(door_id, ""))
	door_states[door_id] = state
	objects_serial += 1
	var by := str(result.get("by", ""))
	var who := _who(by)
	var you := by == player_id
	var method := str(result.get("method", "hand"))
	var verb := ""
	match state:
		DoorData.STATE_OPEN:
			verb = "open" if you else "opens"
		DoorData.STATE_CLOSED:
			if before == DoorData.STATE_LOCKED:
				verb = "unlock" if you else "unlocks"
			else:
				verb = "close" if you else "closes"
		DoorData.STATE_LOCKED:
			verb = "lock" if you else "locks"
	var how := ""
	if method == Messages.UNLOCK_SPELL and result.has("spell"):
		how = " with %s" % spell_name(str(result["spell"]))
	_log("%s %s the door%s." % [who, verb, how])


## The door's current state ("" for an unknown id).
func door_state(door_id: String) -> String:
	return str(door_states.get(door_id, ""))


## The floor's walk map with closed and locked doors as walls (what the
## server paths on while exploring). Cached per floor and door change.
func explore_map() -> WalkMap:
	if floor_data == null:
		return null
	var key := "%d|%d" % [floor_serial, objects_serial]
	if _explore_cache != null and _explore_cache_key == key:
		return _explore_cache
	var m := floor_data.walk_map.copy()
	for d in floor_data.doors:
		if door_state(d.id) != DoorData.STATE_OPEN and m.in_bounds(d.position):
			m.set_walkable(d.position, false)
	_explore_cache = m
	_explore_cache_key = key
	return m


## The map line of sight is judged on: the fight's map (doors, props and
## raised walls, as the server's encounter copy) or, exploring, explore_map.
func sight_map() -> WalkMap:
	if in_encounter and region.has_area():
		return fight_map()
	return explore_map()


## Intact blocking props: Vector2i -> prop id.
func prop_blockers() -> Dictionary:
	var out := {}
	if floor_data == null:
		return out
	for p in floor_data.props:
		if p.blocks and not destroyed_props.has(p.id):
			out[p.position] = p.id
	return out


## occupied_cells(except_id) plus the blocking props (exploration paths).
func explore_blocked(except_id: String = "") -> Dictionary:
	var out := occupied_cells(except_id)
	out.merge(prop_blockers())
	return out


## The fight's map as the server built it: explore_map with blocking props
## as walls, terrain_changed walls / floors applied, cropped to the region.
func fight_map() -> WalkMap:
	var key := "%d|%d|%s|%d" % [floor_serial, objects_serial, str(region), terrain_serial]
	if _map_cache != null and _map_cache_key == key:
		return _map_cache
	var m := explore_map().copy()
	for p: Vector2i in prop_blockers().keys():
		m.set_walkable(p, false)
	for p: Vector2i in terrain_walls.keys():
		if m.in_bounds(p):
			m.set_walkable(p, false)
	for p: Vector2i in terrain_floors.keys():
		if m.in_bounds(p):
			m.set_walkable(p, true)
	_map_cache = m.cropped_to(region) if region.has_area() else m
	_map_cache_key = key
	return _map_cache


## "the north-west landing" ("" on a v1 floor's single arrival).
func landing_text() -> String:
	if landing_id.is_empty() or landing_id == LandingData.ARRIVAL_ID:
		return ""
	if LANDING_NAMES.has(landing_id):
		return "the %s landing" % LANDING_NAMES[landing_id]
	return "landing %s" % landing_id


## The HUD's floor line: "Floor 1 — The Barrow Warrens, arrived at the north landing".
func floor_hud_text() -> String:
	var where := landing_text()
	return floor_label() + (", arrived at %s" % where if not where.is_empty() else "")


## What a click on a door within reach does now: open / close it, or try
## thieves' tools, then its key, then Knock on a locked one (hint says why
## not). Farther away: walk next to it.
func door_intent(door_id: String) -> Dictionary:
	var d := floor_data.get_door(door_id) if floor_data != null else null
	if d == null or not has_player_entity():
		return {}
	var me := player_position()
	if GridMath.distance_tiles(me, d.position) > 1:
		return _walk_next_to(d.position, "the door")
	match door_state(door_id):
		DoorData.STATE_OPEN:
			if not creature_at(d.position).is_empty():
				hint = "Step out of the doorway to close the door."
				return {}
			return Messages.make_intent(Messages.CLOSE_DOOR, {"actor": player_id, "door_id": door_id})
		DoorData.STATE_LOCKED:
			var method := unlock_method(door_id)
			if method.is_empty():
				var info: Dictionary = door_info.get(door_id, {})
				var dc := DictUtil.to_int(info.get("dc", 0), 0)
				hint = "The door is locked%s: thieves' tools, its key or Knock open it." % (" (DC %d)" % dc if dc > 0 else "")
				return {}
			return Messages.make_intent(Messages.UNLOCK_DOOR, {"actor": player_id, "door_id": door_id, "method": method})
	return Messages.make_intent(Messages.OPEN_DOOR, {"actor": player_id, "door_id": door_id})


## How the player would try a locked door: "tools" (thieves' tools, the lock
## has a DC), "key" (a keyed door), "spell" (Knock castable), or "".
func unlock_method(door_id: String) -> String:
	if sheet == null:
		return ""
	var info: Dictionary = door_info.get(door_id, {})
	if sheet.has_item(THIEVES_TOOLS) and DictUtil.to_int(info.get("dc", 0), 0) > 0:
		return Messages.UNLOCK_TOOLS
	if info.get("keyed", false) == true:
		return Messages.UNLOCK_KEY
	if sheet.is_spell_prepared("knock") and cast_error("knock").is_empty():
		return Messages.UNLOCK_SPELL
	return ""


## A click on a prop: break it when within reach, else walk next to it.
func prop_intent(prop_id: String) -> Dictionary:
	var p := floor_data.get_prop(prop_id) if floor_data != null else null
	if p == null or destroyed_props.has(prop_id) or not has_player_entity():
		return {}
	if GridMath.distance_tiles(player_position(), p.position) > 1:
		return _walk_next_to(p.position, "the %s" % p.kind)
	return Messages.make_intent(Messages.INTERACT, {"actor": player_id, "prop_id": prop_id})


## explore_move to the nearest reachable tile next to `tile` ({} with a hint
## when there is none).
func _walk_next_to(tile: Vector2i, what: String) -> Dictionary:
	var blocked := explore_blocked(player_id)
	blocked[tile] = true
	var path := explore_map().path_to(player_position(), tile, blocked)
	if path.is_empty():
		hint = "No way to reach %s." % what
		return {}
	return Messages.make_intent(Messages.EXPLORE_MOVE, {"actor": player_id, "target": GridMath.vec_to_arr(path[path.size() - 1])})


## Exploring toward tile: walk there when a path exists; when only closed
## doors are in the way, walk up to the first one, and open it once there.
## {} (hint set) when nothing leads there.
func route_intent(tile: Vector2i) -> Dictionary:
	var me := player_position()
	var blocked := explore_blocked(player_id)
	var walk := Messages.make_intent(Messages.EXPLORE_MOVE, {"actor": player_id, "target": GridMath.vec_to_arr(tile)})
	if blocked.has(tile) or not explore_map().path_to(me, tile, blocked).is_empty():
		return walk
	var through := floor_data.walk_map.copy()
	for d in floor_data.doors:
		if door_state(d.id) == DoorData.STATE_LOCKED:
			through.set_walkable(d.position, false)
	var path := through.path_to(me, tile, blocked)
	if path.is_empty():
		hint = "No way there."
		return {}
	var before := me
	for step in path:
		var d := floor_data.door_at(step)
		if d != null and door_state(d.id) != DoorData.STATE_OPEN:
			if before == me:
				return Messages.make_intent(Messages.OPEN_DOOR, {"actor": player_id, "door_id": d.id})
			hint = "A closed door is in the way."
			return Messages.make_intent(Messages.EXPLORE_MOVE, {"actor": player_id, "target": GridMath.vec_to_arr(before)})
		before = step
	return walk


## The door / prop within reach and what a click does ("" when none).
func nearby_object_hint() -> String:
	if floor_data == null or not has_player_entity() or in_encounter:
		return ""
	var me := player_position()
	for d in floor_data.doors:
		if GridMath.distance_tiles(me, d.position) <= 1:
			match door_state(d.id):
				DoorData.STATE_OPEN:
					return "An open door: click it to close it."
				DoorData.STATE_LOCKED:
					var how := unlock_method(d.id)
					return "A locked door: click it to %s." % ("pick the lock" if how == Messages.UNLOCK_TOOLS else
						("use the key" if how == Messages.UNLOCK_KEY else ("cast Knock" if how == Messages.UNLOCK_SPELL else "try it")))
				_:
					return "A closed door: click it to open it."
	for p in floor_data.props:
		if not destroyed_props.has(p.id) and GridMath.distance_tiles(me, p.position) <= 1:
			return "A %s: click it to break it open." % p.kind
	return ""


## An exploration cast aimed by a click: the door, chest or zone on the tile.
func _object_cast_intent(tile: Vector2i) -> Dictionary:
	var spell_id := str(targeting.get("spell", ""))
	var kinds := DictUtil.to_string_array(targeting.get("kinds", []))
	var fields: Dictionary = (targeting.get("fields", {}) as Dictionary).duplicate()
	var door := floor_data.door_at(tile)
	var chest := chest_at(tile)
	var zone := floor_data.zone_at(tile)
	if door != null and kinds.has("door"):
		fields["target_kind"] = "door"
		fields["target_id"] = door.id
	elif not chest.is_empty() and kinds.has("chest"):
		fields["target_kind"] = "chest"
		fields["target_id"] = chest
	elif zone != null and kinds.has("zone"):
		fields["target_kind"] = "zone"
		fields["target_id"] = zone.id
	else:
		hint = "%s: click a %s." % [spell_name(spell_id), " or ".join(kinds)]
		return {}
	return cast_intent(spell_id, player_id, int(targeting.get("slot_level", 0)), fields)


func _apply_reveal(r: Dictionary) -> void:
	last_reveal = r.duplicate(true)
	var spell := spell_name(str(r.get("spell", "")))
	match str(r["reveal"]):
		"monsters", "creatures":
			var parts: PackedStringArray = []
			for z_v: Variant in (r.get("zones", []) as Array):
				var z: Dictionary = z_v
				var zid := str(z.get("zone_id", ""))
				var ms: Array = z.get("monsters", [])
				revealed_zones[zid] = ms.duplicate(true)
				var counts := {}
				for m_v: Variant in ms:
					var mid := str((m_v as Dictionary).get("monster_id", ""))
					counts[mid] = DictUtil.to_int(counts.get(mid, 0), 0) + 1
				var names: PackedStringArray = []
				for mid: String in counts.keys():
					names.append(ClientState.quantity_text(monster_name(mid), int(counts[mid])))
				var zn := str(z.get("name", ""))
				parts.append("%s: %s" % [zn if not zn.is_empty() else zid, ", ".join(names)])
			_log("%s reveals %s." % [spell, "; ".join(parts) if not parts.is_empty() else "no creatures nearby"])
		"hidden_chests":
			var n := (r.get("chests", []) as Array).size()
			_log("%s: %s." % [spell, "%d hidden chest%s found" % [n, "" if n == 1 else "s"] if n > 0 else "nothing hidden nearby"])
		"stairs":
			_log("%s: the stairs lie %d steps away." % [spell, DictUtil.to_int(r.get("distance", 0), 0)])
		"map":
			var zones: Array = r.get("zones", [])
			var cleared := 0
			for z_v: Variant in zones:
				if (z_v as Dictionary).get("cleared", false) == true:
					cleared += 1
			_log("%s: the floor unfolds before you: %d guarded rooms, %d cleared." % [spell, zones.size(), cleared])
		"threat":
			match str(r.get("threat", "")):
				"weal":
					_log("%s: weal. The way ahead looks manageable." % spell)
				"woe":
					_log("%s: woe. Danger waits ahead." % spell)
				_:
					_log("%s: nothing threatens you here." % spell)
		"teleport", "recall":
			_log("You vanish and reappear at %s." % ("the stairs" if str(r.get("landmark", "")) == "stairs" else (landing_text() if not landing_text().is_empty() else "your arrival")))
		"light":
			pass  # the CHARACTER_STATE light_level line says it
		"nothing":
			_log("%s: %s." % [spell, str(r.get("reason", "nothing happens"))])
		_:
			_log("%s: nothing of note here." % spell)


# --- round C in fights ---------------------------------------------------------------

func _reset_round_c_combat_state() -> void:
	tile_effects.clear()
	terrain_walls.clear()
	terrain_floors.clear()
	controlled.clear()
	hidden_ids.clear()
	absent_ids.clear()
	encounter_light = "bright"
	terrain_serial += 1
	for k: String in ["via_familiar", "quivering_palm", "hurl_through_hell"]:
		attack_options[k] = false


func _apply_round_c_event(ev: Dictionary) -> void:
	var kind := str(ev.get("kind", ""))
	match kind:
		"exploration_effect":
			pass  # the server's door / chest / reveal results describe the outcome
		"no_effect":
			_log("%s has no effect in the delve: %s." % [spell_name(str(ev.get("spell", ""))), str(ev.get("reason", "nothing here answers it"))])
		"light_changed":
			encounter_light = str(ev.get("light", "bright"))
			_log("The light turns %s." % encounter_light)
		"terrain_changed":
			for p_v: Variant in (ev.get("walls", []) as Array):
				if Messages.is_position(p_v):
					var p := Messages.to_position(p_v)
					terrain_walls[p] = true
					terrain_floors.erase(p)
			for p_v: Variant in (ev.get("floors", []) as Array):
				if Messages.is_position(p_v):
					var p := Messages.to_position(p_v)
					terrain_floors[p] = true
					terrain_walls.erase(p)
			terrain_serial += 1
		"tile_effect_created":
			var id := str(ev.get("id", ""))
			var spell := spell_def(str(ev.get("spell", "")))
			var fx := {"id": id, "spell": str(ev.get("spell", "")), "tiles": GridMath.arr_to_vec_list(ev.get("tiles", [])),
				"terrain": str(ev.get("terrain", "")), "darkness": ev.get("darkness", false) == true, "lit": ev.get("lit", false) == true,
				"opaque": ev.get("opaque", false) == true, "barrier": str(ev.get("barrier", "")),
				"difficult": spell != null and spell.zone.get("difficult", false) == true}
			tile_effects[id] = fx
			terrain_serial += 1
		"tile_effect_moved":
			var id := str(ev.get("id", ""))
			if tile_effects.has(id):
				(tile_effects[id] as Dictionary)["tiles"] = GridMath.arr_to_vec_list(ev.get("tiles", []))
				terrain_serial += 1
		"tile_effect_ended":
			tile_effects.erase(str(ev.get("id", "")))
			terrain_serial += 1
		"team_changed":
			var target := str(ev.get("target", ""))
			var by := str(ev.get("controlled_by", ""))
			var e := _entity_or_new(target)
			if not by.is_empty():
				controlled[target] = by
				if not e.has("orig_kind"):
					e["orig_kind"] = str(e["kind"])
				if DictUtil.to_int(ev.get("team", -1), -1) == TEAM_PLAYERS:
					e["kind"] = KIND_ALLY
					e["owner"] = by
				_log("%s is now under %s's control." % [display_name(target), display_name(by)])
			else:
				controlled.erase(target)
				if e.has("orig_kind"):
					e["kind"] = str(e["orig_kind"])
					e.erase("orig_kind")
					e.erase("owner")
				_log("%s breaks free of control." % display_name(target))
		"control":
			_log("%s commands %s." % [display_name(str(ev.get("actor", ""))), display_name(str(ev.get("target", "")))])
		"compelled":
			_log("%s is compelled to move." % display_name(str(ev.get("actor", ""))))
		"redirected":
			_log("%s redirects %s." % [display_name(str(ev.get("actor", ""))), spell_name(str(ev.get("spell", "")))])
		"banished":
			var target := str(ev.get("target", ""))
			absent_ids[target] = true
			var rounds := DictUtil.to_int(ev.get("rounds", 0), 0)
			_log("%s is banished%s." % [display_name(target), " for good" if ev.get("permanent", false) == true else (" (%d rounds)" % rounds if rounds > 0 else "")])
		"returned":
			var target := str(ev.get("target", ""))
			absent_ids.erase(target)
			if Messages.is_position(ev.get("position")):
				_entity_or_new(target)["position"] = Messages.to_position(ev["position"])
			_log("%s returns." % display_name(target))
		"possessed":
			_log("%s possesses %s." % [display_name(str(ev.get("actor", ""))), display_name(str(ev.get("target", "")))])
		"blink":
			var actor := str(ev.get("actor", ""))
			if ev.get("vanished", false) == true:
				absent_ids[actor] = true
				_log("%s blinks out of sight." % display_name(actor))
			else:
				absent_ids.erase(actor)
		"disbelieved":
			_log("%s sees through the illusion." % display_name(str(ev.get("actor", ""))))
		"hidden":
			hidden_ids[str(ev.get("actor", ""))] = true
			_log("%s hides." % display_name(str(ev.get("actor", ""))))
		"revealed":
			var actor := str(ev.get("actor", ""))
			if hidden_ids.has(actor):
				hidden_ids.erase(actor)
				_log("%s is revealed." % display_name(actor))
		"time_stop":
			_log("%s stops time (%d turns)." % [display_name(str(ev.get("actor", ""))), DictUtil.to_int(ev.get("turns", 0), 0)])
		"extra_turn":
			var actor := str(ev.get("actor", ""))
			if actor == player_id and current_actor == player_id:
				movement_remaining = 0 if is_immobilized(player_id) else speed_tiles()
				action_used = false
				bonus_action_used = false
				attack_action_taken = false
				attacks_remaining = 0
			_log("%s takes another turn." % display_name(actor))
		"time_stop_ended":
			_log("Time flows again.")
		"lingering_added":
			_log("%s lingers on %s." % [spell_name(str(ev.get("spell", ""))), display_name(str(ev.get("target", "")))])
		"lingering_ended":
			_log("%s fades from %s." % [spell_name(str(ev.get("spell", ""))), display_name(str(ev.get("target", "")))])
		"teleported":
			var actor := str(ev.get("actor", ""))
			if Messages.is_position(ev.get("to")):
				_entity_or_new(actor)["position"] = Messages.to_position(ev["to"])
			_log("%s teleports." % display_name(actor))
		"slots_restored":
			_log("%s regains spell slots." % display_name(str(ev.get("actor", ""))))
		"prismatic_ray":
			_log("A prismatic ray (%s) strikes %s." % [str(ev.get("layer", "")), display_name(str(ev.get("target", "")))])
		"save_track_ended":
			_log("%s: %s %s." % [display_name(str(ev.get("target", ""))), str(ev.get("condition", "")).replace("_", " "),
				"passes" if str(ev.get("outcome", "")) == "recovered" else "takes hold"])
		"check_modified":
			_log("%s turns a failed check with %s." % [display_name(str(ev.get("actor", ""))), ClientState.feature_name(str(ev.get("feature", "")))])


## How the player sees a creature now: VIS_SHOWN, VIS_GHOST (its own side
## while hidden or invisible, and illusions) or VIS_HIDDEN (unseen hostiles:
## hidden or invisible; banished / blinked away creatures).
func visibility_of(id: String) -> String:
	var e := get_entity(id)
	if e.is_empty() or absent_ids.has(id):
		return VIS_HIDDEN
	if bool(e.get("illusion", false)):
		return VIS_GHOST
	var unseen := hidden_ids.has(id) or has_condition(id, "invisible")
	if not unseen:
		return VIS_SHOWN
	var own := id == player_id or str(e.get("kind", "")) in [KIND_PLAYER, KIND_ALLY]
	return VIS_GHOST if own else VIS_HIDDEN


## Tiles the terrain overlay paints: Vector2i -> "wall" | "darkness" | "fog"
## | "difficult" | "zone" | "lit" | "opened" (strongest first).
func terrain_cells() -> Dictionary:
	var rank := {"wall": 6, "darkness": 5, "fog": 4, "difficult": 3, "zone": 2, "lit": 1, "opened": 0}
	var out := {}
	var put := func(p: Vector2i, k: String) -> void:
		if not out.has(p) or int(rank[k]) > int(rank[out[p]]):
			out[p] = k
	for p: Vector2i in terrain_floors.keys():
		put.call(p, "opened")
	for p: Vector2i in terrain_walls.keys():
		put.call(p, "wall")
	for fx_v: Variant in tile_effects.values():
		var fx: Dictionary = fx_v
		var k := "zone"
		if str(fx.get("terrain", "")) == "solid":
			k = "wall"
		elif fx.get("darkness", false) == true:
			k = "darkness"
		elif fx.get("opaque", false) == true:
			k = "fog"
		elif fx.get("difficult", false) == true:
			k = "difficult"
		elif fx.get("lit", false) == true:
			k = "lit"
		for p: Vector2i in (fx.get("tiles", []) as Array):
			put.call(p, k)
	return out


# --- Pact of the Chain, Overchannel ----------------------------------------------------

## The player's familiar fighting in this encounter ("" if none).
func familiar_id() -> String:
	if not in_encounter or sheet == null:
		return ""
	var familiar_monsters: Array[String] = []
	familiar_monsters.assign(CharacterSheet.CHAIN_FAMILIARS)
	for c in sheet.companions:
		if str(c.get("spell", "")) == "find_familiar":
			familiar_monsters.append(str(c.get("monster", "")))
	for id in order:
		var e := get_entity(id)
		if not e.is_empty() and str(e.get("owner", "")) == player_id and not bool(e["dead"]) \
				and familiar_monsters.has(str(e.get("monster_id", ""))):
			return id
	return ""


## Hostiles in the familiar's reach, in initiative order.
func familiar_targets() -> Array[String]:
	var out: Array[String] = []
	var fam := familiar_id()
	if fam.is_empty():
		return out
	var fp: Vector2i = get_entity(fam)["position"]
	for id in order:
		var e := get_entity(id)
		if not e.is_empty() and str(e["kind"]) == KIND_MONSTER and not bool(e["dead"]) and GridMath.is_adjacent(fp, e["position"]) \
				and visibility_of(id) != VIS_HIDDEN:
			out.append(id)
	return out


func familiar_attack_error(target: String) -> String:
	if not is_my_turn():
		return "not your turn"
	if not can_make_attack():
		return "action already used"
	if familiar_id().is_empty():
		return "no familiar in this fight"
	if not familiar_targets().has(target):
		return "not in your familiar's reach"
	return ""


## Pact of the Chain: one attack of the Attack action made by the familiar
## (its first attack) against a hostile in its reach.
func familiar_attack_intent(target: String = "") -> Dictionary:
	var t := target
	if t.is_empty():
		var near := familiar_targets()
		if near.is_empty():
			return {}
		t = near[0]
	if not familiar_attack_error(t).is_empty():
		return {}
	return Messages.make_intent(Messages.ATTACK, {"actor": player_id, "target": t, "attack_index": 0, "via_familiar": true})


## Overchannel can apply: a wizard with the feature and a damaging spell of
## 1st-5th level.
func _overchannel_possible(spell_id: String) -> bool:
	var def := spell_def(spell_id)
	return sheet != null and def != null and sheet.has_feature("overchannel") and def.level >= 1 and def.level <= 5 \
		and not def.damage.is_empty()


func _overchannel_applies(spell_id: String) -> bool:
	return bool(cast_options.get("overchannel", false)) and in_encounter and _overchannel_possible(spell_id)


func set_cast_option(key: String, value: Variant) -> void:
	if cast_options.has(key):
		cast_options[key] = value == true
		revision += 1


# --- dominated creatures (control intent) ------------------------------------------------

## Creatures the player dominates in this fight (alive, present).
func controlled_creatures() -> Array[String]:
	var out: Array[String] = []
	for id: String in controlled.keys():
		var e := get_entity(id)
		if str(controlled[id]) == player_id and not e.is_empty() and not bool(e["dead"]) and order.has(id):
			out.append(id)
	return out


## "" when orders can be given to creature now (on the player's turn).
func control_error(creature: String) -> String:
	if not is_my_turn():
		return "only on your turn"
	if not controlled_creatures().has(creature):
		return "%s is not under your control" % display_name(creature)
	return ""


func control_intent(creature: String, orders: Array) -> Dictionary:
	return Messages.make_intent(Messages.CONTROL, {"actor": player_id, "target": creature, "orders": orders})


## Orders to hold still: its next turn ends at once.
func control_hold_intent(creature: String) -> Dictionary:
	if not control_error(creature).is_empty():
		return {}
	return control_intent(creature, [{"type": Messages.END_TURN}])


## Starts picking a tile ("move") or a hostile ("attack") for a dominated creature.
func begin_control(creature: String, order_kind: String) -> void:
	hint = control_error(creature)
	if not hint.is_empty():
		return
	targeting = {"mode": TARGET_CONTROL, "creature": creature, "order": order_kind}
	hint = "%s: click %s." % [display_name(creature), "where it should go" if order_kind == "move" else "the hostile it should attack"]
	revision += 1


## Speed of a creature in tiles (stat block; 6 when unknown).
func creature_speed_tiles(id: String) -> int:
	var e := get_entity(id)
	var monsters: Dictionary = _content().get("monsters", {})
	var def: MonsterDefinition = monsters.get(str(e.get("monster_id", "")), null)
	return GridMath.feet_to_tiles(def.speed) if def != null else 6


## A move order (path within its speed) then end_turn; [] when unreachable.
func control_move_orders(creature: String, tile: Vector2i) -> Array:
	var e := get_entity(creature)
	if e.is_empty():
		return []
	var path := fight_map().path_to(e["position"], tile, occupied_cells(creature))
	if path.is_empty():
		return []
	path.resize(mini(path.size(), creature_speed_tiles(creature)))
	return [{"type": Messages.MOVE, "path": GridMath.vec_list_to_arr(path)}, {"type": Messages.END_TURN}]


## Walk next to target (within its speed) and attack it with its first attack.
func control_attack_orders(creature: String, target: String) -> Array:
	var e := get_entity(creature)
	var t := get_entity(target)
	if e.is_empty() or t.is_empty():
		return []
	var orders: Array = []
	var from: Vector2i = e["position"]
	if not GridMath.is_adjacent(from, t["position"]):
		var path := fight_map().path_to(from, t["position"], occupied_cells(creature))
		if path.is_empty():
			return []
		path.resize(mini(path.size(), creature_speed_tiles(creature)))
		orders.append({"type": Messages.MOVE, "path": GridMath.vec_list_to_arr(path)})
	orders.append({"type": Messages.ATTACK, "target": target, "attack_index": 0})
	orders.append({"type": Messages.END_TURN})
	return orders


func _control_click_intent(tile: Vector2i) -> Dictionary:
	var creature := str(targeting.get("creature", ""))
	hint = control_error(creature)
	if not hint.is_empty():
		return {}
	var orders: Array = []
	if str(targeting.get("order", "")) == "attack":
		var target := hostile_at(tile)
		if target.is_empty() or controlled.has(target):
			hint = "Click a hostile."
			return {}
		orders = control_attack_orders(creature, target)
	else:
		orders = control_move_orders(creature, tile)
	if orders.is_empty():
		hint = "%s cannot get there." % display_name(creature)
		return {}
	return control_intent(creature, orders)
