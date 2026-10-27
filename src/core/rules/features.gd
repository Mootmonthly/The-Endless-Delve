class_name Features
extends RefCounted
## Registry of class / subclass feature ids whose rules the core engine models.
##
## Feature data (data/features/<id>.json) marks `"mechanic": "implemented"` only for ids in
## IMPLEMENTED; everything else is shown as "not yet modelled". Flavour features with no combat
## rules (languages, exploration, ageing) count as implemented. Keep this list exact.

const IMPLEMENTED: Array[String] = [
	# Shared ids (several classes / levels)
	"spellcasting", "extra_attack", "fighting_style", "expertise", "ability_score_improvement",
	"channel_divinity", "evasion", "lands_stride", "timeless_body",
	# Barbarian
	"rage", "unarmored_defense_con", "reckless_attack", "danger_sense", "primal_path", "fast_movement",
	"frenzy", "mindless_rage", "feral_instinct", "brutal_critical", "intimidating_presence",
	"relentless_rage", "retaliation", "persistent_rage", "indomitable_might", "primal_champion",
	# Bard
	"bardic_inspiration", "song_of_rest", "bard_college", "bonus_proficiencies", "font_of_inspiration",
	"jack_of_all_trades", "cutting_words", "countercharm", "additional_magical_secrets", "magical_secrets",
	"superior_inspiration", "peerless_skill",
	# Cleric
	"divine_domain", "turn_undead", "destroy_undead", "domain_spells", "bonus_proficiency",
	"disciple_of_life", "preserve_life", "blessed_healer", "divine_strike", "divine_intervention",
	"supreme_healing",
	# Druid
	"druidic", "druid_circle", "bonus_cantrip", "natural_recovery", "circle_spells",
	"circle_of_the_land_arctic", "circle_of_the_land_coast", "circle_of_the_land_desert",
	"circle_of_the_land_forest", "circle_of_the_land_grassland", "circle_of_the_land_mountain",
	"circle_of_the_land_swamp", "wild_shape", "natures_ward", "natures_sanctuary", "beast_spells",
	"archdruid",
	# Fighter
	"second_wind", "action_surge", "martial_archetype", "improved_critical", "remarkable_athlete",
	"indomitable", "additional_fighting_style", "superior_critical", "survivor",
	# Monk
	"unarmored_defense_wis", "martial_arts", "ki", "flurry_of_blows", "patient_defense",
	"step_of_the_wind", "unarmored_movement", "monastic_tradition", "deflect_missiles",
	"open_hand_technique", "stunning_strike", "ki_empowered_strikes", "wholeness_of_body",
	"stillness_of_mind", "purity_of_body", "tranquility", "tongue_of_the_sun_and_moon", "diamond_soul",
	"empty_body", "perfect_self", "slow_fall", "quivering_palm",
	# Paladin
	"divine_sense", "lay_on_hands", "divine_smite", "divine_health", "sacred_oath", "oath_spells",
	"sacred_weapon", "turn_the_unholy", "aura_of_protection", "aura_of_devotion", "aura_of_courage",
	"improved_divine_smite", "cleansing_touch", "aura_improvements", "purity_of_spirit", "holy_nimbus",
	# Ranger
	"favored_enemy", "natural_explorer", "ranger_archetype", "hunters_prey", "colossus_slayer",
	"giant_killer", "horde_breaker", "primeval_awareness", "defensive_tactics", "escape_the_horde",
	"multiattack_defense", "steel_will", "hide_in_plain_sight", "multiattack", "volley", "whirlwind_attack",
	"vanish", "superior_hunters_defense", "superior_hunters_defense_evasion", "stand_against_the_tide",
	"superior_hunters_defense_uncanny_dodge", "feral_senses", "foe_slayer",
	# Rogue
	"sneak_attack", "thieves_cant", "cunning_action", "roguish_archetype", "fast_hands",
	"second_story_work", "uncanny_dodge", "supreme_sneak", "reliable_talent", "use_magic_device",
	"blindsense", "slippery_mind", "elusive", "thiefs_reflexes", "stroke_of_luck",
	# Sorcerer
	"sorcerous_origin", "dragon_ancestor", "dragon_ancestor_black", "dragon_ancestor_blue",
	"dragon_ancestor_brass", "dragon_ancestor_bronze", "dragon_ancestor_copper", "dragon_ancestor_gold",
	"dragon_ancestor_green", "dragon_ancestor_red", "dragon_ancestor_silver", "dragon_ancestor_white",
	"draconic_resilience", "font_of_magic", "metamagic", "elemental_affinity", "dragon_wings",
	"draconic_presence", "sorcerous_restoration",
	# Warlock
	"otherworldly_patron", "expanded_spell_list", "dark_ones_blessing", "pact_magic",
	"eldritch_invocations", "pact_boon", "pact_of_the_blade", "dark_ones_own_luck", "fiendish_resilience",
	"mystic_arcanum", "pact_of_the_chain", "pact_of_the_tome", "hurl_through_hell", "eldritch_master",
	# Wizard
	"arcane_recovery", "arcane_tradition", "evocation_savant", "sculpt_spells", "potent_cantrip",
	"empowered_evocation", "overchannel", "spell_mastery", "signature_spell",
]
## Invocations, metamagic options and fighting styles the engine models
## (data/invocations, data/metamagic, data/fighting_styles). Eyes of the Rune
## Keeper and Voice of the Chain Master are flavour; invocations that cast a
## declared no_effect spell (Beast Speech, Whispers of the Grave) cast it.
const IMPLEMENTED_INVOCATIONS: Array[String] = [
	"agonizing_blast", "armor_of_shadows", "repelling_blast", "eldritch_spear", "fiendish_vigor",
	"thirsting_blade", "lifedrinker", "ascendant_step", "beguiling_influence", "devils_sight",
	"thief_of_five_fates", "mire_the_mind", "sign_of_ill_omen", "dreadful_word", "sculptor_of_flesh",
	"eyes_of_the_rune_keeper",
	# round C: at will (CharacterSheet.AT_WILL_INVOCATIONS / AT_WILL_SELF_INVOCATIONS), once per long rest
	# (INVOCATION_SPELLS), use_feature (one_with_shadows, gaze_of_two_minds), pacts and senses
	"beast_speech", "eldritch_sight", "mask_of_many_faces", "master_of_myriad_forms", "misty_visions",
	"visions_of_distant_realms", "whispers_of_the_grave", "chains_of_carceri", "otherworldly_leap",
	"bewitching_whispers", "minions_of_chaos", "one_with_shadows", "gaze_of_two_minds", "witch_sight",
	"book_of_ancient_secrets", "voice_of_the_chain_master",
]
const IMPLEMENTED_METAMAGIC: Array[String] = [
	"careful_spell", "distant_spell", "empowered_spell", "extended_spell", "heightened_spell",
	"quickened_spell", "subtle_spell", "twinned_spell",
]
const IMPLEMENTED_FIGHTING_STYLES: Array[String] = ["archery", "defense", "dueling", "great_weapon_fighting", "protection", "two_weapon_fighting"]
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
	"defensive_tactics": ["escape_the_horde", "multiattack_defense", "steel_will"],
	"multiattack": ["volley", "whirlwind_attack"],
	"superior_hunters_defense": ["superior_hunters_defense_evasion", "stand_against_the_tide", "superior_hunters_defense_uncanny_dodge"],
}
const LAND_OPTION_PREFIX := "circle_of_the_land_"


## True when the engine models `feature_id`.
static func is_implemented(feature_id: String) -> bool:
	return IMPLEMENTED.has(feature_id)
