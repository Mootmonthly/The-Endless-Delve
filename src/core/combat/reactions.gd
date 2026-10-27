class_name Reactions
extends RefCounted
## Which reactions (and reaction-like features) each trigger governs, for
## Combatant.reaction_policy ({trigger or reaction id: "auto" | "never"}) and
## the client's Reactions popup. The Encounter resolves them automatically.
##
## Triggers:
##   creature_left_reach   a hostile leaves the creature's reach
##   creature_hit_me       an attack hits the creature
##   ally_attacked         an ally next to the creature is attacked
##   ally_hit              an ally within range is hit
##   missed                a melee attack against the creature missed
##   spell_cast_in_range   a hostile casts a spell within 60 ft
##   damage_taken          the creature took damage from a hostile it sees
##   failed_save           the creature failed a saving throw (not reactions)
##   falling               the creature takes falling damage (Reverse Gravity)
##   own_attack_missed     the creature's own attack missed (Stroke of Luck)
##   failed_check          the creature failed an ability check (Stroke of Luck,
##                         Peerless Skill)
##   own_attack            once-per-turn riders on the creature's own attacks
##                         (Horde Breaker, Foe Slayer)

const BY_TRIGGER: Dictionary[String, Array] = {
	"creature_left_reach": ["opportunity_attack"],
	"creature_hit_me": ["shield", "deflect_missiles", "uncanny_dodge", "giant_killer"],
	"ally_attacked": ["protection"],
	"ally_hit": ["cutting_words"],
	"missed": ["stand_against_the_tide", "giant_killer"],
	"spell_cast_in_range": ["counterspell"],
	"damage_taken": ["hellish_rebuke", "retaliation"],
	"failed_save": ["dark_ones_own_luck", "indomitable", "diamond_soul"],
	"falling": ["feather_fall", "slow_fall"],
	"own_attack_missed": ["stroke_of_luck"],
	"failed_check": ["stroke_of_luck", "peerless_skill"],
	"own_attack": ["horde_breaker", "foe_slayer"],
}
## Reaction id -> what grants it: {"feature": id} (any of "features" for
## several), {"spell": id} (prepared), {"style": id} (fighting style), or
## {"any": true} (every creature).
const SOURCES: Dictionary[String, Dictionary] = {
	"opportunity_attack": {"any": true},
	"shield": {"spell": "shield"},
	"counterspell": {"spell": "counterspell"},
	"hellish_rebuke": {"spell": "hellish_rebuke"},
	"feather_fall": {"spell": "feather_fall"},
	"deflect_missiles": {"feature": "deflect_missiles"},
	"uncanny_dodge": {"features": ["uncanny_dodge", "superior_hunters_defense_uncanny_dodge"]},
	"giant_killer": {"feature": "giant_killer"},
	"protection": {"style": "protection"},
	"cutting_words": {"feature": "cutting_words"},
	"stand_against_the_tide": {"feature": "stand_against_the_tide"},
	"retaliation": {"feature": "retaliation"},
	"dark_ones_own_luck": {"feature": "dark_ones_own_luck"},
	"indomitable": {"feature": "indomitable"},
	"diamond_soul": {"feature": "diamond_soul"},
	"slow_fall": {"feature": "slow_fall"},
	"stroke_of_luck": {"feature": "stroke_of_luck"},
	"peerless_skill": {"feature": "peerless_skill"},
	"horde_breaker": {"feature": "horde_breaker"},
	"foe_slayer": {"feature": "foe_slayer"},
}


## Triggers that govern `reaction` (several for Giant Killer, Stroke of Luck).
static func triggers_of(reaction: String) -> Array[String]:
	var out: Array[String] = []
	for trigger: String in BY_TRIGGER.keys():
		if BY_TRIGGER[trigger].has(reaction):
			out.append(trigger)
	return out


## Whether `sheet` has what grants `reaction`.
static func has_reaction(sheet: CharacterSheet, reaction: String) -> bool:
	if sheet == null or not SOURCES.has(reaction):
		return false
	var src: Dictionary = SOURCES[reaction]
	if src.get("any", false) == true:
		return true
	if src.has("spell"):
		return sheet.is_spell_prepared(str(src["spell"]))
	if src.has("style"):
		return sheet.fighting_styles.has(str(src["style"]))
	for f in DictUtil.to_string_array(src.get("features", [src.get("feature", "")])):
		if sheet.has_feature(f):
			return true
	return false


## trigger -> the reaction ids `sheet` has for it (triggers without one left out).
static func for_sheet(sheet: CharacterSheet) -> Dictionary:
	var out := {}
	for trigger: String in BY_TRIGGER.keys():
		var ids: Array[String] = []
		for r: Variant in BY_TRIGGER[trigger]:
			if Reactions.has_reaction(sheet, str(r)):
				ids.append(str(r))
		if not ids.is_empty():
			out[trigger] = ids
	return out
