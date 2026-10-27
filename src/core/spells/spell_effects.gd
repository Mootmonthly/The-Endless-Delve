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
	"dominate_beast": {"type": "save", "save": "WIS", "apply_condition": {"condition": "dominated", "duration": {"type": "rounds", "rounds": 10}}, "condition_save_on_damage": true, "creature_types": ["beast"]},
	"dominate_person": {"type": "save", "save": "WIS", "apply_condition": {"condition": "dominated", "duration": {"type": "rounds", "rounds": 10}}, "condition_save_on_damage": true, "creature_types": ["humanoid"]},
	"dominate_monster": {"type": "save", "save": "WIS", "apply_condition": {"condition": "dominated", "duration": "encounter"}, "condition_save_on_damage": true},
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
	"darkness": {"type": "zone", "zone": {"obscured": true, "darkness": true}},  # magical darkness: only Devil's Sight, blindsight and truesight see through
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
	# --- round C: walls, terrain and wards (the encounter owns its map copy) ----------------------
	"wall_of_force": {"type": "zone", "zone": {"wall": true, "terrain": "solid"}, "_area": {"shape": "line", "size_ft": 100}},  # lite: a straight wall of ten panels
	"wall_of_ice": {"type": "zone", "zone": {"wall": true, "terrain": "solid", "save": "DEX", "damage": "10d6", "damage_type": "cold", "on_save": "half", "per_slot_level_above": "2d6", "triggers": ["create"]},
		"_area": {"shape": "line", "size_ft": 100}},  # lite: no breakable panels
	"wall_of_stone": {"type": "zone", "zone": {"wall": true, "terrain": "solid"}, "_area": {"shape": "line", "size_ft": 100}},
	"forcecage": {"type": "zone", "zone": {"cells": "ring", "terrain": "solid"}},  # the cage's bars: the ring of tiles 10 ft from the point
	"resilient_sphere": {"type": "buff", "save": "DEX", "modifiers": {"sealed": true, "speed_zero": true}, "_target": "any"},  # a single-tile cage
	"prismatic_wall": {"type": "zone", "zone": {"wall": true, "opaque": true, "triggers": ["enter"], "layers": ["red", "orange", "yellow", "green", "blue", "indigo", "violet"]}},
	"wind_wall": {"type": "zone", "zone": {"wall": true, "wind": true, "save": "STR", "damage": "3d8", "damage_type": "bludgeoning", "on_save": "half", "triggers": ["create"]}},
	"antilife_shell": {"type": "zone", "zone": {"anchor": "caster", "barrier": "living"}},  # lite: hostiles inside are pushed out
	"globe_of_invulnerability": {"type": "zone", "zone": {"anchor": "caster", "globe": 5}},
	"antimagic_field": {"type": "zone", "zone": {"anchor": "caster", "antimagic": true}},
	"reverse_gravity": {"type": "zone", "zone": {"save": "DEX", "fall": "4d6", "condition": "prone", "condition_duration": "encounter", "triggers": ["create", "enter"]}},  # lite: one fall to a 40-ft ceiling
	"earthquake": {"type": "zone", "zone": {"difficult": true, "ground": true, "phases": [{"save": "DEX", "condition": "prone", "condition_duration": "encounter", "breaks_concentration": true}]}},  # lite: no fissures
	"fire_storm": {"type": "area_save", "save": "DEX", "damage": "7d10", "damage_type": "fire", "on_save": "half", "_area": {"shape": "cube", "size_ft": 30}},  # lite: one block instead of ten cubes
	"storm_of_vengeance": {"type": "zone", "zone": {"phases": [
		{"save": "CON", "damage": "2d6", "damage_type": "thunder", "on_save": "none", "condition": "deafened", "condition_duration": {"type": "rounds", "rounds": 50}},
		{"damage": "1d6", "damage_type": "acid"},
		{"save": "DEX", "damage": "10d6", "damage_type": "lightning", "on_save": "half", "max_targets": 6},
		{"damage": "2d6", "damage_type": "bludgeoning"},
		{"damage": "1d6", "damage_type": "cold", "set": {"difficult": true, "wind": true, "obscured": true}}]}},
	"control_water": {"type": "zone", "zone": {"difficult": true, "ground": true}},  # lite: Flood: the water is difficult terrain
	"telekinesis": {"type": "forced_move", "move_ft": 30, "condition": "restrained", "sustain": "action", "_target": "any"},
	"arcane_hand": {"type": "summon", "custom": "arcane_hand", "targetable": true, "rounds": 0},  # lite: Clenched Fist every turn
	"move_earth": {"type": "zone", "zone": {"cells": "raw", "terrain": "open", "terrain_modes": {"lower": "open", "raise": "solid"}}, "_area": {"shape": "cube", "size_ft": 20}},  # lite: one 20-ft section, reshaped at once
	"stone_shape": {"type": "zone", "zone": {"cells": "raw", "terrain": "open", "terrain_modes": {"open": "open", "wall": "solid"}, "point_on": "wall", "point_on_modes": {"open": "wall", "wall": "floor"}},
		"_area": {"shape": "cube", "size_ft": 5}},
	"passwall": {"type": "zone", "zone": {"cells": "raw", "terrain": "open", "point_on": "wall"}, "_area": {"shape": "line", "size_ft": 20}},
	"plant_growth": {"type": "zone", "zone": {"difficult": true, "difficult_cost": 4, "ground": true, "plant": true, "affects": "hostiles"}, "_area": {"shape": "sphere", "size_ft": 100}},  # lite: the caster's allies are spared
	"spider_climb": {"type": "buff", "modifiers": {"climbing": true, "ignore_difficult": true}, "rounds": 0, "_target": "ally"},
	"jump": {"type": "buff", "modifiers": {"ignores_ground": true, "ignore_difficult": true}, "_target": "ally"},  # lite: leaps clear ground effects and rough terrain
	"feather_fall": {"type": "reaction", "trigger": "falling", "_target": "ally"},
	# --- round C: compulsion, charm and planar effects -------------------------------------------
	"suggestion": {"type": "save", "save": "WIS", "apply_condition": {"condition": "suggested", "duration": "encounter"}, "condition_ends_on_damage": true},  # lite: "leave us be"
	"mass_suggestion": {"type": "save", "save": "WIS", "apply_condition": {"condition": "suggested", "duration": "encounter"}, "condition_ends_on_damage": true, "max_targets": 12},
	"compulsion": {"type": "area_save", "save": "WIS", "affects": "hostiles", "apply_condition": {"condition": "compelled", "duration": "save_ends"}, "sustain": "bonus_action", "sustain_mode": "redirect",
		"_area": {"shape": "sphere", "size_ft": 30}, "_range_ft": 0},
	"enthrall": {"type": "save", "save": "WIS", "apply_effect": {"disadv_checks": ["WIS"]}, "max_targets": 6},  # disadvantage on Perception: WIS checks
	"calm_emotions": {"type": "area_save", "save": "CHA", "affects": "hostiles", "allies_cure": ["charmed", "frightened"], "apply_condition": {"condition": "suggested", "duration": {"type": "rounds", "rounds": 10}}, "condition_ends_on_damage": true},
	"geas": {"type": "no_effect", "reason": "commands a creature for 30 days; outside a fight there is no creature to command in the delve yet"},
	"modify_memory": {"type": "save", "save": "WIS", "apply_condition": {"condition": "charmed", "duration": {"type": "rounds", "rounds": 10}}, "creature_types": ["humanoid"]},  # lite: the charm, no memories rewritten
	"animal_friendship": {"type": "save", "save": "WIS", "apply_condition": {"condition": "charmed", "duration": "encounter"}, "creature_types": ["beast"], "targets_per_slot": 1},
	"antipathy_sympathy": {"type": "zone", "zone": {"affects": "hostiles", "save": "WIS", "triggers": ["enter", "start_turn"], "condition": "frightened", "condition_duration": "until_target_turn_end",
		"modes": {"antipathy": {"condition": "frightened"}, "sympathy": {"condition": "charmed"}}}, "lingering": {"kind": "zone"}, "_area": {"shape": "sphere", "size_ft": 30}},  # the warded spot is where you stand when the next fight starts
	"banishment": {"type": "banish", "save": "CHA", "rounds": 10, "native_permanent": true},
	"maze": {"type": "banish", "rounds": 10, "escape": {"ability": "INT", "dc": 20}},
	"imprisonment": {"type": "banish", "save": "WIS", "permanent": true},
	"plane_shift": {"type": "banish", "attack": "melee", "save": "CHA", "permanent": true, "self_rounds": 10, "_target": "any"},  # lite: travellers come back after 10 rounds
	"magic_jar": {"type": "lingering", "lingering": {"kind": "feature", "feature": "magic_jar"}},  # use_feature magic_jar in a fight: possess a humanoid
	"true_polymorph": {"type": "transform", "save": "WIS", "any_type": true, "kind": "true_polymorph", "form": "rat", "ally_form": "brown_bear", "_target": "any"},
	"shapechange": {"type": "transform", "any_type": true, "excluded_form_types": ["construct", "undead"], "cr_limit": "caster", "kind": "shapechange", "form": "brown_bear", "_target": "self"},
	"animal_shapes": {"type": "transform", "kind": "animal_shapes", "max_cr": 4, "cr_limit": "none", "form": "brown_bear", "ally_form": "brown_bear", "max_targets": 10, "_target": "ally"},
	"gaseous_form": {"type": "buff", "modifiers": {"fly_ft": 10, "speed_cap_ft": 10, "resist_nonmagical": true, "adv_saves": ["STR", "DEX", "CON"], "no_attacks": true, "no_spellcasting": true}, "rounds": 0, "_target": "ally"},
	"blink": {"type": "buff", "modifiers": {"blink": true}, "rounds": 10},
	"etherealness": {"type": "buff", "apply_condition": {"condition": "ethereal", "duration": "encounter"}, "modifiers": {"fly_ft": -1}, "rounds": 0},  # use_feature end_spell returns
	# --- round C: summons and companions (1-minute+ conjurations are out-of-combat companions lasting encounters) ---
	"conjure_celestial": {"type": "summon", "monster": "couatl", "forms": "celestial", "max_cr": 4.0, "cr_by_slot": {"9": 5.0}, "count_base": 1, "companion": true, "encounters": 0},
	"conjure_elemental": {"type": "summon", "monster": "air_elemental", "forms": "elemental", "max_cr": 5.0, "cr_per_slot": 1.0, "count_base": 1, "companion": true, "encounters": 0},  # lite: it vanishes when concentration ends
	"conjure_fey": {"type": "summon", "monster": "dryad", "forms": "fey", "max_cr": 6.0, "cr_per_slot": 1.0, "count_base": 1, "companion": true, "encounters": 0},
	"conjure_minor_elementals": {"type": "summon", "monster": "magma_mephit", "forms": "elemental", "max_cr": 2.0, "count": {"2": 1, "1": 2, "0.5": 4, "0.25": 8}, "slot_multiplier": {"6": 2, "8": 3},
		"companion": true, "encounters": 0},
	"animate_objects": {"type": "summon", "custom": "animated_object", "targetable": true, "count_base": 10, "count_per_slot": 2, "rounds": 0},  # lite: ten Tiny objects
	"giant_insect": {"type": "summon", "monster": "giant_spider", "forms": ["giant_centipede", "giant_spider", "giant_wasp", "giant_scorpion"],
		"count_by_form": {"giant_centipede": 10, "giant_spider": 3, "giant_wasp": 5, "giant_scorpion": 1}, "rounds": 0},  # lite: the insects appear rather than grow
	"faithful_hound": {"type": "summon", "custom": "faithful_hound", "rounds": 0},
	"planar_ally": {"type": "summon", "monster": "couatl", "form_types": ["celestial", "elemental", "fiend"], "max_cr": 6.0, "count_base": 1, "companion": true, "until_long_rest": true},  # lite: no payment
	"planar_binding": {"type": "summon", "monster": "couatl", "form_types": ["celestial", "elemental", "fey", "fiend"], "max_cr": 5.0, "cr_per_slot": 1.0, "count_base": 1, "companion": true, "until_long_rest": true},  # lite: the bound creature is called with the spell
	"unseen_servant": {"type": "summon", "custom": "unseen_servant", "targetable": true, "familiar": true, "companion": true, "count_base": 1, "encounters": 0, "rounds": 0},  # it helps
	"phantom_steed": {"type": "lingering", "lingering": {"kind": "buff", "effect": "phantom_steed", "modifiers": {"speed_bonus_ft": 30}}},  # lite: a mount as +30 ft of speed
	"simulacrum": {"type": "summon", "custom": "simulacrum", "targetable": true, "single": true, "companion": true, "count_base": 1},
	"awaken": {"type": "summon", "monster": "awakened_tree", "forms": "beast", "also_forms": ["awakened_shrub", "awakened_tree"], "max_cr": 2.0, "count_base": 1, "companion": true},  # lite: the awakened creature joins you
	"reincarnate": {"type": "revive", "max_rounds": -1, "hp": -1, "reincarnate": true, "_target": "ally"},
	# --- round C: illusions (images fool hostiles until an Investigation check succeeds) ---------------
	"silent_image": {"type": "summon", "custom": "illusion", "targetable": true, "rounds": 0, "_range_ft": 60},
	"major_image": {"type": "summon", "custom": "illusion", "targetable": true, "rounds": 0},
	"programmed_illusion": {"type": "summon", "custom": "illusion", "targetable": true, "rounds": 0},  # lite: it plays at once
	"project_image": {"type": "summon", "custom": "illusion", "targetable": true, "copy_caster": true, "rounds": 0, "_range_ft": 120},  # lite: a decoy of you
	"mislead": {"type": "summon", "custom": "illusion", "targetable": true, "copy_caster": true, "self_invisible": true, "rounds": 0},
	"phantasmal_force": {"type": "save", "save": "INT", "dot": {"dice": "1d6", "type": "psychic", "trigger": "end_turn", "save": "INT"}},  # lite: an end-of-turn INT save ends it
	"weird": {"type": "area_save", "save": "WIS", "affects": "hostiles", "apply_condition": {"condition": "frightened", "duration": "encounter"},
		"dot": {"dice": "4d10", "type": "psychic", "trigger": "end_turn", "save": "WIS"}},
	"disguise_self": {"type": "buff", "modifiers": {"stealth_advantage": true, "label": "advantage on your first Stealth check this fight"}, "rounds": 0,
		"lingering": {"kind": "stealth", "effect": "disguise_self", "modifiers": {"stealth_advantage": true, "label": "advantage on your first Stealth check this fight"}, "encounters": 1}},
	"alter_self": {"type": "buff", "modifiers": {"unarmed_die": 6, "stealth_advantage": true, "label": "natural weapons (1d6, magical); advantage on your first Stealth check"}, "rounds": 0,
		"lingering": {"kind": "stealth", "effect": "alter_self", "modifiers": {"stealth_advantage": true, "label": "advantage on your first Stealth check this fight"}, "encounters": 1}},
	"seeming": {"type": "buff", "modifiers": {"stealth_advantage": true, "label": "advantage on your first Stealth check this fight"}, "rounds": 0, "max_targets": 8, "_target": "ally",
		"lingering": {"kind": "stealth", "effect": "seeming", "modifiers": {"stealth_advantage": true, "label": "advantage on your first Stealth check this fight"}, "encounters": 1}},
	"minor_illusion": {"type": "zone", "zone": {"obscured": true, "rounds": 10}, "_area": {"shape": "cube", "size_ft": 5},
		"lingering": {"kind": "stealth", "effect": "minor_illusion", "modifiers": {"stealth_advantage": true, "label": "advantage on your first Stealth check this fight"}, "encounters": 1}},  # in a fight: a 5-ft image to hide behind
	"hallucinatory_terrain": {"type": "lingering", "lingering": {"kind": "stealth", "effect": "hallucinatory_terrain", "modifiers": {"stealth_advantage": true, "label": "advantage on your first Stealth check this fight"}, "encounters": 1}},
	"mirage_arcane": {"type": "lingering", "lingering": {"kind": "stealth", "effect": "mirage_arcane", "modifiers": {"stealth_advantage": true, "label": "advantage on your first Stealth check this fight"}, "encounters": 1}},
	"gate": {"type": "summon", "monster": "couatl", "form_types": ["celestial", "elemental", "fiend"], "max_cr": 12.0, "count_base": 1, "companion": true, "encounters": 1, "rounds": 0},  # lite: the portal brings a planar ally
	# --- round C: special outcomes ------------------------------------------------------------------------
	"contagion": {"type": "spell_attack", "attack": "melee", "damage": "", "apply_condition": {"condition": "poisoned", "duration": {"type": "save_track", "ability": "CON"}},
		"track_effect": {"effect": "contagion", "ends_condition": true, "modifiers": {"disadv_saves": ["WIS"], "disadv_checks": ["WIS"]}, "conditions": ["blinded"], "label": "Blinding Sickness"},
		"modes": {
			"blinding_sickness": {"track_effect": {"effect": "contagion", "ends_condition": true, "modifiers": {"disadv_saves": ["WIS"], "disadv_checks": ["WIS"]}, "conditions": ["blinded"], "label": "Blinding Sickness"}},
			"filth_fever": {"track_effect": {"effect": "contagion", "ends_condition": true, "modifiers": {"disadv_saves": ["STR"], "disadv_checks": ["STR"], "attack_disadvantage_abilities": ["STR"]}, "label": "Filth Fever"}},
			"flesh_rot": {"track_effect": {"effect": "contagion", "ends_condition": true, "modifiers": {"disadv_checks": ["CHA"], "vulnerable_all": true}, "label": "Flesh Rot"}},
			"mindfire": {"track_effect": {"effect": "contagion", "ends_condition": true, "modifiers": {"disadv_saves": ["INT"], "disadv_checks": ["INT"], "confused": true}, "label": "Mindfire"}},
			"seizure": {"track_effect": {"effect": "contagion", "ends_condition": true, "modifiers": {"disadv_saves": ["DEX"], "disadv_checks": ["DEX"], "attack_disadvantage_abilities": ["DEX"]}, "label": "Seizure"}},
			"slimy_doom": {"track_effect": {"effect": "contagion", "ends_condition": true, "modifiers": {"disadv_saves": ["CON"], "disadv_checks": ["CON"], "stunned_on_damage": true}, "label": "Slimy Doom"}}}},
	"prismatic_spray": {"type": "area_save", "save": "DEX", "prismatic": true, "on_save": "half"},  # one d8 ray per creature (8: two rays)
	"flame_blade": {"type": "weapon_attack", "rounds": 0, "attack": {"name": "Flame Blade", "kind": "melee", "damage": "3d6", "damage_type": "fire", "spell_attack": true, "per_two_slots": "1d6"}},
	"shillelagh": {"type": "weapon_attack", "rounds": 10, "requires_items": ["club", "quarterstaff"], "attack": {"ability": "CASTING", "damage_die": 8}, "_target": "self", "_range_ft": 0},
	"wish": {"type": "wish", "max_duplicate_level": 8, "instant_health_targets": 10},  # mode: a spell id, "restore_slots" or "instant_health"
	"time_stop": {"type": "time_stop", "dice": "1d4+1"},
	"foresight": {"type": "lingering", "lingering": {"kind": "buff", "effect": "foresight", "modifiers": {"attack_advantage": true, "attackers_disadvantage": true,
		"adv_saves": ["STR", "DEX", "CON", "INT", "WIS", "CHA"], "adv_checks": ["STR", "DEX", "CON", "INT", "WIS", "CHA"], "no_surprise": true,
		"label": "advantage on attacks, checks and saves; attacks against you have disadvantage; you cannot be surprised"}}, "_target": "ally"},
	# --- round C: exploration utilities (exploration_effect for the server; fight hooks where they exist) ---
	"knock": {"type": "exploration", "exploration": "unlock", "target_kinds": ["chest", "door"], "range_ft": 60},
	"arcane_lock": {"type": "exploration", "exploration": "lock", "target_kinds": ["chest", "door"], "range_ft": 5},
	"mage_hand": {"type": "exploration", "exploration": "open", "target_kinds": ["chest", "door"], "range_ft": 30},
	"find_traps": {"type": "exploration", "exploration": "reveal", "reveal": "traps", "range_ft": 120},
	"detect_magic": {"type": "exploration", "exploration": "reveal", "reveal": "magic_items", "radius_ft": 30},
	"locate_object": {"type": "exploration", "exploration": "reveal", "reveal": "hidden_chests", "radius_ft": 1000},
	"arcane_eye": {"type": "exploration", "exploration": "reveal", "reveal": "monsters", "radius_ft": 300},  # lite: the eye scouts nearby zones
	"clairvoyance": {"type": "exploration", "exploration": "reveal", "reveal": "monsters", "target_kinds": ["zone"]},
	"scrying": {"type": "exploration", "exploration": "reveal", "reveal": "monsters", "target_kinds": ["zone"]},
	"locate_creature": {"type": "exploration", "exploration": "reveal", "reveal": "monsters", "radius_ft": 1000},
	"detect_thoughts": {"type": "exploration", "exploration": "reveal", "reveal": "monsters", "radius_ft": 30, "fight_reveal": {"radius_ft": 30, "min_int": 4}},
	"detect_evil_and_good": {"type": "exploration", "exploration": "reveal", "reveal": "creatures", "radius_ft": 30,
		"creature_types": ["aberration", "celestial", "elemental", "fey", "fiend", "undead"],
		"fight_reveal": {"radius_ft": 30, "creature_types": ["aberration", "celestial", "elemental", "fey", "fiend", "undead"]}},
	"locate_animals_or_plants": {"type": "exploration", "exploration": "reveal", "reveal": "creatures", "creature_types": ["beast", "plant"], "radius_ft": 26400},
	"find_the_path": {"type": "exploration", "exploration": "reveal", "reveal": "stairs"},
	"commune_with_nature": {"type": "exploration", "exploration": "reveal", "reveal": "map"},
	"augury": {"type": "exploration", "exploration": "reveal", "reveal": "threat", "target_kinds": ["zone"]},  # lite: weal or woe = the next zone's danger
	"divination": {"type": "exploration", "exploration": "reveal", "reveal": "threat", "target_kinds": ["zone"]},
	"commune": {"type": "exploration", "exploration": "reveal", "reveal": "threat", "target_kinds": ["zone"]},
	"contact_other_plane": {"type": "exploration", "exploration": "reveal", "reveal": "threat", "target_kinds": ["zone"]},  # lite: no madness save
	"legend_lore": {"type": "exploration", "exploration": "reveal", "reveal": "threat", "target_kinds": ["zone"]},
	"light": {"type": "exploration", "exploration": "light", "radius_ft": 20, "encounters": 2, "save": "DEX", "_target": "any"},
	"daylight": {"type": "exploration", "exploration": "light", "radius_ft": 60, "encounters": 2, "dispel_darkness": 3, "_target": "any"},
	"continual_flame": {"type": "exploration", "exploration": "light", "radius_ft": 20, "encounters": -1, "_target": "ally"},
	"dancing_lights": {"type": "exploration", "exploration": "light", "radius_ft": 10, "encounters": 1, "_target": "any"},  # lite: the lights hover over a creature
	"teleport": {"type": "exploration", "exploration": "teleport", "target_kinds": ["landmark"], "landmarks": ["arrival", "stairs"]},
	"teleportation_circle": {"type": "exploration", "exploration": "teleport", "target_kinds": ["landmark"], "landmarks": ["arrival"]},
	"word_of_recall": {"type": "exploration", "exploration": "recall", "max_targets": 6, "_target": "ally"},
	# --- round C: exploration spells with a fight hook of their own --------------------------------------
	"darkvision": {"type": "buff", "modifiers": {"darkvision_ft": 60}, "rounds": 0, "_target": "ally",
		"lingering": {"kind": "buff", "effect": "darkvision", "modifiers": {"darkvision_ft": 60, "label": "darkvision 60 ft"}}},
	"pass_without_trace": {"type": "buff", "modifiers": {"stealth_bonus": 10}, "rounds": 0, "max_targets": 10, "_target": "ally", "_range_ft": 30,
		"lingering": {"kind": "stealth", "effect": "pass_without_trace", "modifiers": {"stealth_bonus": 10, "label": "+10 to Stealth checks"}}},
	"heroes_feast": {"type": "lingering", "max_targets": 12, "_target": "ally", "lingering": {"kind": "buff", "effect": "heroes_feast", "encounters": -1,
		"modifiers": {"immune_conditions": ["poisoned", "frightened"], "immune_damage": ["poison"], "adv_saves": ["WIS"], "max_hp_bonus": 11,
		"label": "immune to poison and fear, advantage on WIS saves, +11 hit point maximum"}}},  # lite: the 2d10 hit point bonus is its average
	"magic_circle": {"type": "lingering", "lingering": {"kind": "buff", "effect": "magic_circle", "modifiers": {"attackers_disadvantage_types": ["celestial", "elemental", "fey", "fiend", "undead"],
		"label": "celestials, elementals, fey, fiends and undead have disadvantage attacking you"}}},  # lite: the circle travels with its caster
	"gentle_repose": {"type": "lingering", "_target": "any", "dead_ok": true, "lingering": {"kind": "feature", "feature": "gentle_repose", "encounters": -1}},  # the dead stay revivable (Revivify's minute does not run)
	"goodberry": {"type": "heal_pool", "pool": 10, "_target": "ally"},  # lite: the ten berries are eaten at once
	"meld_into_stone": {"type": "banish", "self_rounds": 10, "requires_wall": true, "_target": "self"},  # lite: steps back out after 10 rounds
	# --- round C: declared no effect in the delve (castable, free unless the caster spends the slot) -------
	"animal_messenger": {"type": "no_effect", "reason": "no one in the delve to talk to yet"},
	"comprehend_languages": {"type": "no_effect", "reason": "no one in the delve to talk to yet"},
	"message": {"type": "no_effect", "reason": "no one in the delve to talk to yet"},
	"sending": {"type": "no_effect", "reason": "no one in the delve to talk to yet"},
	"speak_with_animals": {"type": "no_effect", "reason": "no one in the delve to talk to yet"},
	"speak_with_dead": {"type": "no_effect", "reason": "no one in the delve to talk to yet"},
	"speak_with_plants": {"type": "no_effect", "reason": "no one in the delve to talk to yet"},
	"telepathic_bond": {"type": "no_effect", "reason": "no one in the delve to talk to yet"},
	"tongues": {"type": "no_effect", "reason": "no one in the delve to talk to yet"},
	"zone_of_truth": {"type": "no_effect", "reason": "no one in the delve to talk to yet"},
	"dream": {"type": "no_effect", "reason": "no one in the delve to talk to yet"},
	"glibness": {"type": "no_effect", "reason": "no one in the delve to talk to yet"},
	"druidcraft": {"type": "no_effect", "reason": "cosmetic: no rules effect in the delve"},
	"prestidigitation": {"type": "no_effect", "reason": "cosmetic: no rules effect in the delve"},
	"thaumaturgy": {"type": "no_effect", "reason": "cosmetic: no rules effect in the delve"},
	"arcanists_magic_aura": {"type": "no_effect", "reason": "cosmetic: no rules effect in the delve"},
	"illusory_script": {"type": "no_effect", "reason": "cosmetic: no rules effect in the delve"},
	"magic_mouth": {"type": "no_effect", "reason": "cosmetic: no rules effect in the delve"},
	"mending": {"type": "no_effect", "reason": "items in the delve do not break yet"},
	"identify": {"type": "no_effect", "reason": "items in the delve are always identified"},
	"detect_poison_and_disease": {"type": "no_effect", "reason": "the delve hides no poisons to find yet"},
	"create_food_and_water": {"type": "no_effect", "reason": "the delve does not track food, water, crafting or carrying yet"},
	"create_or_destroy_water": {"type": "no_effect", "reason": "the delve does not track food, water, crafting or carrying yet"},
	"purify_food_and_drink": {"type": "no_effect", "reason": "the delve does not track food, water, crafting or carrying yet"},
	"creation": {"type": "no_effect", "reason": "the delve does not track food, water, crafting or carrying yet"},
	"fabricate": {"type": "no_effect", "reason": "the delve does not track food, water, crafting or carrying yet"},
	"floating_disk": {"type": "no_effect", "reason": "the delve does not track food, water, crafting or carrying yet"},
	"secret_chest": {"type": "no_effect", "reason": "the delve does not track food, water, crafting or carrying yet"},
	"instant_summons": {"type": "no_effect", "reason": "the delve does not track food, water, crafting or carrying yet"},
	"tiny_hut": {"type": "no_effect", "reason": "the delve has no resting hook for shelters yet"},
	"rope_trick": {"type": "no_effect", "reason": "the delve has no resting hook for shelters yet"},
	"magnificent_mansion": {"type": "no_effect", "reason": "the delve has no resting hook for shelters yet"},
	"demiplane": {"type": "no_effect", "reason": "the delve has no resting hook for shelters yet"},
	"private_sanctum": {"type": "no_effect", "reason": "the delve has no resting hook for shelters yet"},
	"alarm": {"type": "no_effect", "reason": "it wards a place, and the delve keeps no warded places yet"},
	"glyph_of_warding": {"type": "no_effect", "reason": "it wards a place, and the delve keeps no warded places yet"},
	"symbol": {"type": "no_effect", "reason": "it wards a place, and the delve keeps no warded places yet"},
	"forbiddance": {"type": "no_effect", "reason": "it wards a place, and the delve keeps no warded places yet"},
	"guards_and_wards": {"type": "no_effect", "reason": "it wards a place, and the delve keeps no warded places yet"},
	"hallow": {"type": "no_effect", "reason": "it wards a place, and the delve keeps no warded places yet"},
	"sequester": {"type": "no_effect", "reason": "nothing in the delve searches for you yet"},
	"nondetection": {"type": "no_effect", "reason": "nothing in the delve searches for you yet"},
	"water_breathing": {"type": "no_effect", "reason": "the delve has no water, plants, sky or other planes to use it with"},
	"water_walk": {"type": "no_effect", "reason": "the delve has no water, plants, sky or other planes to use it with"},
	"transport_via_plants": {"type": "no_effect", "reason": "the delve has no water, plants, sky or other planes to use it with"},
	"tree_stride": {"type": "no_effect", "reason": "the delve has no water, plants, sky or other planes to use it with"},
	"wind_walk": {"type": "no_effect", "reason": "the delve has no water, plants, sky or other planes to use it with"},
	"control_weather": {"type": "no_effect", "reason": "the delve has no water, plants, sky or other planes to use it with"},
	"astral_projection": {"type": "no_effect", "reason": "the delve has no water, plants, sky or other planes to use it with"},
	"clone": {"type": "no_effect", "reason": "a clone takes 120 days to grow, longer than any delve"},
	"contingency": {"type": "no_effect", "reason": "the delve cannot hold a spell for a later trigger yet"},
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
