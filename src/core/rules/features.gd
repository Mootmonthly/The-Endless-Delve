class_name Features
extends RefCounted
## Registry of class / subclass feature ids whose rules the core engine models.
##
## Feature data (data/features/<id>.json) marks `"mechanic": "implemented"` only for ids in
## IMPLEMENTED; everything else is shown as "not yet modelled". Flavour features with no combat
## rules (languages, exploration) count as implemented. Keep this list exact.

const IMPLEMENTED: Array[String] = [
	# Shared ids (several classes / levels)
	"spellcasting", "extra_attack", "fighting_style", "expertise", "ability_score_improvement",
	"channel_divinity",
	# Barbarian
	"rage", "unarmored_defense_con", "reckless_attack", "danger_sense", "primal_path", "fast_movement",
	"frenzy",
	# Bard
	"bardic_inspiration", "song_of_rest", "bard_college", "bonus_proficiencies", "font_of_inspiration",
	# Cleric
	"divine_domain", "turn_undead", "destroy_undead", "domain_spells", "bonus_proficiency",
	"disciple_of_life", "preserve_life",
	# Druid
	"druidic", "druid_circle", "bonus_cantrip", "natural_recovery", "circle_spells",
	"circle_of_the_land_arctic", "circle_of_the_land_coast", "circle_of_the_land_desert",
	"circle_of_the_land_forest", "circle_of_the_land_grassland", "circle_of_the_land_mountain",
	"circle_of_the_land_swamp",
	# Fighter
	"second_wind", "action_surge", "martial_archetype", "improved_critical",
	# Monk
	"unarmored_defense_wis", "martial_arts", "ki", "flurry_of_blows", "patient_defense",
	"step_of_the_wind", "unarmored_movement", "monastic_tradition", "deflect_missiles",
	"open_hand_technique", "stunning_strike",
	# Paladin
	"divine_sense", "lay_on_hands", "divine_smite", "divine_health", "sacred_oath", "oath_spells",
	"sacred_weapon", "turn_the_unholy",
	# Ranger
	"favored_enemy", "natural_explorer", "ranger_archetype", "hunters_prey", "colossus_slayer",
	# Rogue
	"sneak_attack", "thieves_cant", "cunning_action", "roguish_archetype", "fast_hands",
	"second_story_work", "uncanny_dodge",
	# Sorcerer
	"sorcerous_origin", "dragon_ancestor", "dragon_ancestor_black", "dragon_ancestor_blue",
	"dragon_ancestor_brass", "dragon_ancestor_bronze", "dragon_ancestor_copper", "dragon_ancestor_gold",
	"dragon_ancestor_green", "dragon_ancestor_red", "dragon_ancestor_silver", "dragon_ancestor_white",
	"draconic_resilience", "font_of_magic", "metamagic",
	# Warlock
	"otherworldly_patron", "expanded_spell_list", "dark_ones_blessing", "pact_magic",
	"eldritch_invocations", "pact_boon", "pact_of_the_blade",
	# Wizard
	"arcane_recovery", "arcane_tradition", "evocation_savant", "sculpt_spells",
]
## Invocations, metamagic options and fighting styles the engine models
## (data/invocations, data/metamagic, data/fighting_styles).
const IMPLEMENTED_INVOCATIONS: Array[String] = ["agonizing_blast", "armor_of_shadows", "repelling_blast"]
const IMPLEMENTED_METAMAGIC: Array[String] = ["empowered_spell", "quickened_spell", "twinned_spell"]
const IMPLEMENTED_FIGHTING_STYLES: Array[String] = ["archery", "defense", "dueling", "great_weapon_fighting", "two_weapon_fighting"]
## Features that are a choice between option features: feature id -> option ids
## (circle_spells options are filled from the class's land terrains).
const FEATURE_OPTIONS: Dictionary[String, Array] = {
	"hunters_prey": ["colossus_slayer", "giant_killer", "horde_breaker"],
	"dragon_ancestor": [
		"dragon_ancestor_black", "dragon_ancestor_blue", "dragon_ancestor_brass", "dragon_ancestor_bronze",
		"dragon_ancestor_copper", "dragon_ancestor_gold", "dragon_ancestor_green", "dragon_ancestor_red",
		"dragon_ancestor_silver", "dragon_ancestor_white",
	],
	"circle_spells": [
		"circle_of_the_land_arctic", "circle_of_the_land_coast", "circle_of_the_land_desert",
		"circle_of_the_land_forest", "circle_of_the_land_grassland", "circle_of_the_land_mountain",
		"circle_of_the_land_swamp",
	],
	"pact_boon": ["pact_of_the_blade", "pact_of_the_chain", "pact_of_the_tome"],
}
const LAND_OPTION_PREFIX := "circle_of_the_land_"


## True when the engine models `feature_id`.
static func is_implemented(feature_id: String) -> bool:
	return IMPLEMENTED.has(feature_id)
