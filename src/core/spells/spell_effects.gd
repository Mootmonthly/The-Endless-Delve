class_name SpellEffects
extends RefCounted
## Rules-engine effects for SRD spells whose data effect is still
## "unsupported" (data/spells is importer-owned): SpellDefinition.from_dict
## swaps in OVERRIDES[id] when the data says "unsupported", so data that
## later carries a real effect wins. Keys starting with "_" replace top-level
## spell fields ("_area", "_target", "_range_ft"). Values may use the
## placeholders "MOD" (caster's casting modifier), "DC" (spell save DC) and
## "CASTER" (caster id), resolved when the spell is cast.
## Simplifications ("lite") are noted per entry; see src/core/README.md.

const OVERRIDES: Dictionary = {
	# --- buffs on allies / self -------------------------------------------------------
	"bless": {"type": "buff", "modifiers": {"attack_dice": "1d4", "save_dice": "1d4"}, "max_targets": 3, "targets_per_slot": 1, "_target": "ally"},
	"shield_of_faith": {"type": "buff", "modifiers": {"ac": 2}, "_target": "ally"},
	"haste": {"type": "buff", "modifiers": {"ac": 2, "speed_double": true, "adv_saves": ["DEX"], "haste_action": true, "lethargy": true}, "_target": "ally"},
	"heroism": {"type": "buff", "modifiers": {"immune_conditions": ["frightened"], "temp_hp_each_turn": "MOD"}, "targets_per_slot": 1, "_target": "ally"},
	"longstrider": {"type": "buff", "modifiers": {"speed_bonus_ft": 10}, "rounds": 0, "targets_per_slot": 1, "_target": "ally"},
	"expeditious_retreat": {"type": "buff", "modifiers": {"speed_double": true}, "rounds": 0},  # lite: a Dash every turn = double speed
	"enhance_ability": {"type": "buff", "modifiers": {"adv_checks": ["CON"], "temp_hp_dice": "2d6"}, "targets_per_slot": 1, "rounds": 0, "_target": "ally",
		"modes": {"bear": {"adv_checks": ["CON"], "temp_hp_dice": "2d6"}, "bull": {"adv_checks": ["STR"], "temp_hp_dice": ""}, "cat": {"adv_checks": ["DEX"], "temp_hp_dice": ""},
			"eagle": {"adv_checks": ["CHA"], "temp_hp_dice": ""}, "fox": {"adv_checks": ["INT"], "temp_hp_dice": ""}, "owl": {"adv_checks": ["WIS"], "temp_hp_dice": ""}}},
	"protection_from_energy": {"type": "buff", "modifiers": {"resist": ["fire"]}, "rounds": 0, "_target": "ally",
		"modes": {"acid": {"resist": ["acid"]}, "cold": {"resist": ["cold"]}, "fire": {"resist": ["fire"]}, "lightning": {"resist": ["lightning"]}, "thunder": {"resist": ["thunder"]}}},
	"protection_from_poison": {"type": "buff", "modifiers": {"resist": ["poison"], "cure_conditions": ["poisoned"]}, "rounds": 0, "_target": "ally"},
	"protection_from_evil_and_good": {"type": "buff", "modifiers": {"attackers_disadvantage_types": ["aberration", "celestial", "elemental", "fey", "fiend", "undead"]}, "_target": "ally"},
	"stoneskin": {"type": "buff", "modifiers": {"resist_nonmagical": true}, "rounds": 0, "_target": "ally"},
	"barkskin": {"type": "buff", "modifiers": {"ac_min": 16}, "rounds": 0, "_target": "ally"},
	"blur": {"type": "buff", "modifiers": {"attackers_disadvantage": true}},
	"mirror_image": {"type": "buff", "modifiers": {"images": 3}},
	"fire_shield": {"type": "buff", "modifiers": {"resist": ["cold"], "retaliate_dice": "2d8", "retaliate_type": "fire"}, "rounds": 0,
		"modes": {"warm": {"resist": ["cold"], "retaliate_type": "fire"}, "chill": {"resist": ["fire"], "retaliate_type": "cold"}}},
	"freedom_of_movement": {"type": "buff", "modifiers": {"immune_conditions": ["paralyzed", "restrained"], "ignore_difficult": true}, "rounds": 0, "_target": "ally"},
	"death_ward": {"type": "buff", "modifiers": {"death_ward": true}, "rounds": 0, "_target": "ally"},
	"beacon_of_hope": {"type": "buff", "modifiers": {"adv_saves": ["WIS"], "max_healing": true}, "max_targets": 6, "_target": "ally"},
	"warding_bond": {"type": "buff", "modifiers": {"ac": 1, "save_bonus": 1, "resist_all": true, "share_damage_with": "CASTER"}, "rounds": 0, "_target": "ally"},
	"invisibility": {"type": "buff", "apply_condition": {"condition": "invisible", "duration": "encounter"}, "condition_ends_on_attack": true, "targets_per_slot": 1, "_target": "ally"},
	"greater_invisibility": {"type": "buff", "apply_condition": {"condition": "invisible", "duration": {"type": "rounds", "rounds": 10}}, "_target": "ally"},
	"sanctuary": {"type": "buff", "modifiers": {"sanctuary_dc": "DC", "ends_on_attack": true}, "_target": "ally"},
	"divine_favor": {"type": "buff", "modifiers": {"weapon_damage_dice": "1d4", "weapon_damage_type": "radiant"}},
	"magic_weapon": {"type": "buff", "modifiers": {"weapon_bonus": 1, "weapon_magical": true}, "rounds": 0, "_target": "ally"},
	"branding_smite": {"type": "buff", "modifiers": {"next_hit_dice": "2d6", "next_hit_type": "radiant"}},
	"true_strike": {"type": "buff", "buff_on_caster": true, "modifiers": {"advantage_vs": "TARGET"}, "duration": "until_source_next_turn", "_target": "any"},
	"guidance": {"type": "buff", "modifiers": {"check_dice": "1d4", "once": true}, "_target": "ally"},
	"resistance": {"type": "buff", "modifiers": {"save_dice": "1d4", "once": true}, "_target": "ally"},
	"see_invisibility": {"type": "buff", "modifiers": {"see_invisible": true}, "rounds": 0},
	"true_seeing": {"type": "buff", "modifiers": {"see_invisible": true}, "rounds": 0, "_target": "ally"},
	"fly": {"type": "buff", "modifiers": {"fly_ft": 60}, "rounds": 0, "targets_per_slot": 1, "_target": "ally"},
	"aid": {"type": "buff", "modifiers": {"max_hp_bonus": 5, "max_hp_bonus_per_slot": 5}, "rounds": 0, "max_targets": 3, "_target": "ally"},
	"holy_aura": {"type": "buff", "modifiers": {"adv_saves": ["ALL"], "attackers_disadvantage": true}, "max_targets": 8, "_target": "ally", "_range_ft": 30},  # lite: chosen allies in range
	"mind_blank": {"type": "buff", "modifiers": {"immune_damage": ["psychic"], "immune_conditions": ["charmed"]}, "rounds": 0, "_target": "ally"},
	"levitate": {"type": "buff", "modifiers": {"speed_zero": true, "levitating": true}, "save": "CON", "_target": "any"},  # lite: no vertical movement on the grid
	"enlarge_reduce": {"type": "buff", "modifiers": {"weapon_damage_dice": "1d4", "adv_checks": ["STR"], "adv_saves": ["STR"]}, "save": "CON", "_target": "any",
		"modes": {"enlarge": {"weapon_damage_dice": "1d4", "adv_checks": ["STR"], "adv_saves": ["STR"]}, "reduce": {"weapon_damage_dice": "", "adv_checks": [], "adv_saves": [], "weapon_damage_penalty_dice": "1d4", "disadv_saves": ["STR"]}}},
	"false_life": {"type": "temp_hp", "dice": "1d4+4", "per_slot_level_above": "5"},
	"hunters_mark": {"type": "mark", "mark": "hunters_mark", "bonus_damage": "1d6", "damage_type": "", "weapon_only": true},
	"spare_the_dying": {"type": "revive", "stabilize": true, "_target": "ally"},
	"revivify": {"type": "revive", "max_rounds": 10, "hp": 1, "_target": "ally"},
	# --- conditions and debuffs on hostiles -------------------------------------------------
	"bane": {"type": "save", "save": "CHA", "apply_effect": {"attack_dice": "-1d4", "save_dice": "-1d4"}, "max_targets": 3, "targets_per_slot": 1},
	"charm_person": {"type": "save", "save": "WIS", "apply_condition": {"condition": "charmed", "duration": "encounter"}, "condition_ends_on_damage": true, "creature_types": ["humanoid"], "targets_per_slot": 1},
	"hold_person": {"type": "save", "save": "WIS", "apply_condition": {"condition": "paralyzed", "duration": "save_ends"}, "creature_types": ["humanoid"], "targets_per_slot": 1},
	"hold_monster": {"type": "save", "save": "WIS", "apply_condition": {"condition": "paralyzed", "duration": "save_ends"}, "excluded_types": ["undead"], "targets_per_slot": 1},
	"blindness_deafness": {"type": "save", "save": "CON", "apply_condition": {"condition": "blinded", "duration": "save_ends"}, "targets_per_slot": 1,
		"modes": {"blinded": {"condition": "blinded"}, "deafened": {"condition": "deafened"}}},
	"command": {"type": "save", "save": "WIS", "apply_condition": {"condition": "turn_lost", "duration": "until_target_turn_end"}, "extra_conditions": ["prone"], "targets_per_slot": 1,
		"modes": {"grovel": {"extra_conditions": ["prone"]}, "halt": {"extra_conditions": []}}},  # lite: grovel (prone, turn lost) or halt (turn lost)
	"hideous_laughter": {"type": "save", "save": "WIS", "apply_condition": {"condition": "incapacitated", "duration": "save_ends"}, "extra_conditions": ["prone"]},
	"irresistible_dance": {"type": "save", "auto_fail": true, "save": "WIS", "apply_effect": {"speed_zero": true, "attack_disadvantage": true, "attackers_advantage": true, "disadv_saves": ["DEX"]}, "duration": "save_ends"},
	"ray_of_enfeeblement": {"type": "spell_attack", "damage": "0", "damage_type": "necrotic", "apply_effect": {"half_str_damage": true}, "duration": "save_ends", "save": "CON"},
	"bestow_curse": {"type": "save", "save": "WIS", "curse_mark": {"dice": "1d8", "type": "necrotic"}},  # lite: the SRD "extra 1d8 necrotic from you" option
	"phantasmal_killer": {"type": "save", "save": "WIS", "apply_condition": {"condition": "frightened", "duration": "encounter"}, "dot": {"dice": "4d10", "type": "psychic", "trigger": "end_turn", "save": "WIS", "per_slot_level_above": "1d10"}},
	"eyebite": {"type": "save", "save": "WIS", "apply_condition": {"condition": "unconscious", "duration": "encounter"}, "condition_ends_on_damage": true, "sustain": "action",
		"modes": {"asleep": {"condition": "unconscious"}, "panicked": {"condition": "frightened"}, "sickened": {"condition": "poisoned"}}},
	"feeblemind": {"type": "save", "save": "INT", "damage": "4d6", "damage_type": "psychic", "on_save": "none", "apply_effect": {"no_spellcasting": true}, "rounds": 0, "damage_on_save": true},
	"flesh_to_stone": {"type": "save", "save": "CON", "apply_condition": {"condition": "restrained", "duration": "save_ends"}},  # lite: no petrification after three failures
	"dominate_beast": {"type": "save", "save": "WIS", "apply_condition": {"condition": "charmed", "duration": "save_ends"}, "extra_conditions": ["incapacitated"], "creature_types": ["beast"]},  # lite: charmed and held, not controlled
	"dominate_person": {"type": "save", "save": "WIS", "apply_condition": {"condition": "charmed", "duration": "save_ends"}, "extra_conditions": ["incapacitated"], "creature_types": ["humanoid"]},
	"dominate_monster": {"type": "save", "save": "WIS", "apply_condition": {"condition": "charmed", "duration": "save_ends"}, "extra_conditions": ["incapacitated"]},
	"heat_metal": {"type": "save", "auto_fail": true, "save": "CON", "damage": "2d8", "damage_type": "fire", "per_slot_level_above": "1d8", "sustain": "bonus_action"},  # lite: no dropped objects
	"vampiric_touch": {"type": "spell_attack", "attack": "melee", "damage": "3d6", "damage_type": "necrotic", "per_slot_level_above": "1d6", "heal_caster": "half", "sustain": "action", "_range_ft": 5},
	"power_word_kill": {"type": "threshold", "levels": [[100, "kill"]]},
	"power_word_stun": {"type": "threshold", "levels": [[150, "stunned"]], "save": "CON"},
	"divine_word": {"type": "threshold", "save": "CHA", "save_first": true, "levels": [[20, "kill"], [30, ["blinded", "deafened", "stunned"]], [40, ["blinded", "deafened"]], [50, ["deafened"]]], "_range_ft": 30},
	"polymorph": {"type": "transform", "save": "WIS", "form": "rat", "ally_form": "brown_bear", "_target": "any"},
	"dispel_magic": {"type": "dispel", "spells": true, "_target": "any"},
	"lesser_restoration": {"type": "dispel", "conditions": ["blinded", "deafened", "paralyzed", "poisoned"], "_target": "ally"},
	"greater_restoration": {"type": "dispel", "conditions": ["charmed", "petrified"], "exhaustion": 1, "_target": "ally"},
	"remove_curse": {"type": "dispel", "spell_ids": ["bestow_curse", "hex"], "_target": "ally"},
	"dispel_evil_and_good": {"type": "dispel", "conditions": ["charmed", "frightened"], "_target": "ally"},  # lite: the "break enchantment" use
	# --- areas -----------------------------------------------------------------------------
	"hypnotic_pattern": {"type": "area_save", "save": "WIS", "apply_condition": {"condition": "charmed", "duration": {"type": "rounds", "rounds": 10}}, "extra_conditions": ["incapacitated"], "condition_ends_on_damage": true,
		"_area": {"shape": "cube", "size_ft": 30}},
	"fear": {"type": "area_save", "save": "WIS", "apply_condition": {"condition": "frightened", "duration": "save_ends"}, "condition_flee": true},
	"slow": {"type": "area_save", "save": "WIS", "apply_effect": {"ac": -2, "save_bonus_DEX": -2, "speed_half": true, "no_reactions": true, "single_action": true}, "duration": "save_ends"},
	"faerie_fire": {"type": "area_save", "save": "DEX", "apply_effect": {"attackers_advantage": true, "outlined": true}},
	"confusion": {"type": "area_save", "save": "WIS", "effect_id": "confused", "apply_effect": {"confused": true}, "duration": "save_ends", "radius_per_slot_ft": 5},
	"sleep": {"type": "sleep", "pool": "5d8", "per_slot_level_above": "2d8"},
	"color_spray": {"type": "sleep", "pool": "6d10", "per_slot_level_above": "2d10", "condition": "blinded"},
	"gust_of_wind": {"type": "area_save", "save": "STR", "push_ft": 15},  # lite: one push when cast
	"call_lightning": {"type": "area_save", "save": "DEX", "damage": "3d10", "damage_type": "lightning", "on_save": "half", "per_slot_level_above": "1d10", "sustain": "action"},
	"flame_strike": {"type": "area_save", "save": "DEX", "damage": "4d6", "damage_type": "fire", "on_save": "half", "per_slot_level_above": "1d6", "_area": {"shape": "cylinder", "size_ft": 10}},
	"ice_storm": {"type": "area_save", "save": "DEX", "damage": "2d8", "damage_type": "bludgeoning", "on_save": "half", "per_slot_level_above": "1d8"},
	"meteor_swarm": {"type": "area_save", "save": "DEX", "damage": "20d6", "damage_type": "fire", "on_save": "half", "extra_damage": [{"damage": "20d6", "damage_type": "bludgeoning"}]},  # lite: one sphere
	"mass_cure_wounds": {"type": "area_heal", "max_targets": 6},
	"mass_healing_word": {"type": "heal", "max_targets": 6, "_target": "ally"},
	"mass_heal": {"type": "heal_pool", "pool": 700, "_target": "ally"},
	# --- lingering zones -------------------------------------------------------------------------
	"grease": {"type": "zone", "zone": {"save": "DEX", "condition": "prone", "condition_duration": "encounter", "triggers": ["create", "enter", "end_turn"], "difficult": true, "ground": true, "rounds": 10}},
	"web": {"type": "zone", "zone": {"save": "DEX", "condition": "restrained", "condition_duration": {"type": "save_ends", "ability": "STR", "dc": 12}, "triggers": ["create", "enter", "start_turn"], "difficult": true}},
	"entangle": {"type": "zone", "zone": {"save": "STR", "condition": "restrained", "condition_duration": {"type": "save_ends", "ability": "STR", "dc": 12}, "triggers": ["create"], "difficult": true, "ground": true, "plant": true}},
	"spike_growth": {"type": "zone", "zone": {"per_tile_damage": "2d4", "damage_type": "piercing", "difficult": true, "ground": true, "plant": true}},
	"moonbeam": {"type": "zone", "zone": {"save": "CON", "damage": "2d10", "damage_type": "radiant", "on_save": "half", "per_slot_level_above": "1d10", "triggers": ["enter", "start_turn"], "move": "action", "move_ft": 60}},
	"cloudkill": {"type": "zone", "zone": {"save": "CON", "damage": "5d8", "damage_type": "poison", "on_save": "half", "per_slot_level_above": "1d8", "triggers": ["enter", "start_turn"], "drift_ft": 10, "obscured": true}},
	"stinking_cloud": {"type": "zone", "zone": {"save": "CON", "condition": "incapacitated", "condition_duration": "until_target_turn_end", "triggers": ["enter", "start_turn"], "obscured": true}},
	"sleet_storm": {"type": "zone", "zone": {"save": "DEX", "condition": "prone", "condition_duration": "encounter", "triggers": ["enter", "start_turn"], "difficult": true, "ground": true, "obscured": true}},
	"fog_cloud": {"type": "zone", "zone": {"obscured": true}},
	"darkness": {"type": "zone", "zone": {"obscured": true}},
	"silence": {"type": "zone", "zone": {"silence": true}},
	"wall_of_fire": {"type": "zone", "zone": {"wall": true, "save": "DEX", "damage": "5d8", "damage_type": "fire", "on_save": "half", "per_slot_level_above": "1d8", "triggers": ["create", "enter", "end_turn"]}},  # lite: the wall's own tiles burn
	"blade_barrier": {"type": "zone", "zone": {"wall": true, "save": "DEX", "damage": "6d10", "damage_type": "slashing", "on_save": "half", "triggers": ["enter", "start_turn"], "difficult": true}},
	"wall_of_thorns": {"type": "zone", "zone": {"wall": true, "save": "DEX", "damage": "7d8", "damage_type": "piercing", "on_save": "half", "per_slot_level_above": "1d8", "triggers": ["create", "enter"], "difficult": true, "plant": true}},
	"spirit_guardians": {"type": "zone", "zone": {"anchor": "caster", "affects": "hostiles", "save": "WIS", "damage": "3d8", "damage_type": "radiant", "on_save": "half", "per_slot_level_above": "1d8", "triggers": ["enter", "start_turn"], "difficult": true},
		"_area": {"shape": "sphere", "size_ft": 15}},
	"flaming_sphere": {"type": "zone", "zone": {"save": "DEX", "damage": "2d6", "damage_type": "fire", "on_save": "half", "per_slot_level_above": "1d6", "triggers": ["end_turn"], "move": "bonus_action", "move_ft": 30},
		"_area": {"shape": "sphere", "size_ft": 5}},
	"black_tentacles": {"type": "zone", "zone": {"save": "DEX", "damage": "3d6", "damage_type": "bludgeoning", "on_save": "none", "condition": "restrained", "condition_duration": {"type": "save_ends", "ability": "STR", "dc": 15}, "triggers": ["create", "enter", "start_turn"], "difficult": true}},
	"guardian_of_faith": {"type": "zone", "zone": {"affects": "hostiles", "save": "DEX", "damage": "20", "damage_type": "radiant", "on_save": "half", "triggers": ["enter", "start_turn"], "pool": 60}},
	# --- movement --------------------------------------------------------------------------------
	"misty_step": {"type": "teleport", "range_ft": 30, "need_sight": true},
	"dimension_door": {"type": "teleport", "range_ft": 500, "need_sight": false},
	# --- summons ----------------------------------------------------------------------------------
	"spiritual_weapon": {"type": "summon", "custom": "spiritual_weapon", "rounds": 10, "concentration": false},
	"arcane_sword": {"type": "summon", "custom": "arcane_sword", "rounds": 10},
	"conjure_animals": {"type": "summon", "monster": "wolf", "forms": "beast", "max_cr": 2.0, "count": {"2": 1, "1": 2, "0.5": 4, "0.25": 8}, "slot_multiplier": {"5": 2, "7": 3, "9": 4}, "rounds": 0},
	"conjure_woodland_beings": {"type": "summon", "monster": "satyr", "forms": "fey", "max_cr": 2.0, "count": {"2": 1, "1": 2, "0.5": 4, "0.25": 8}, "slot_multiplier": {"6": 2, "8": 3}, "rounds": 0},
	"find_familiar": {"type": "summon", "monster": "owl", "forms": ["bat", "cat", "crab", "hawk", "lizard", "octopus", "owl", "poisonous_snake", "quipper", "rat", "raven", "spider", "weasel"], "familiar": true, "companion": true},
	"animate_dead": {"type": "summon", "monster": "skeleton", "forms": ["skeleton", "zombie"], "count_base": 1, "count_per_slot": 2, "companion": true, "until_long_rest": true},  # lite: no corpse needed
	"find_steed": {"type": "summon", "monster": "warhorse", "forms": ["warhorse", "pony", "camel", "elk", "mastiff"], "companion": true},
	"create_undead": {"type": "summon", "monster": "ghoul", "forms": ["ghoul"], "count_base": 3, "count_per_slot": 1, "companion": true, "until_long_rest": true},
	# --- reactions (resolved by the reaction system) -----------------------------------------------
	"shield": {"type": "reaction", "trigger": "creature_hit_me"},
	"counterspell": {"type": "reaction", "trigger": "spell_cast_in_range"},
	# --- out of combat (OutOfCombat.cast) ---------------------------------------------------------------
	"raise_dead": {"type": "revive", "max_rounds": -1, "hp": 1, "penalty": 4, "_target": "ally"},
	"resurrection": {"type": "revive", "max_rounds": -1, "hp": -1, "penalty": 4, "_target": "ally"},
	"true_resurrection": {"type": "revive", "max_rounds": -1, "hp": -1, "_target": "ally"},
	"prayer_of_healing": {"type": "heal", "dice": "2d8", "add_casting_mod": true, "per_slot_level_above": "1d8", "max_targets": 6, "_target": "ally"},
}


## The spell dictionary with the override's effect (and "_" top-level keys) applied.
static func apply_override(d: Dictionary) -> Dictionary:
	var out := d.duplicate(true)
	var override_v: Variant = OVERRIDES.get(str(d.get("id", "")), {})
	if typeof(override_v) != TYPE_DICTIONARY:
		return out
	var e: Dictionary = (override_v as Dictionary).duplicate(true)
	for key: Variant in e.keys():
		var k := str(key)
		if k.begins_with("_"):
			out[k.substr(1)] = e[key]
			e.erase(key)
	out["effect"] = e
	return out
