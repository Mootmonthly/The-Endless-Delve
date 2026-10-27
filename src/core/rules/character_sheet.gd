class_name CharacterSheet
extends RefCounted
## A creature's rules state: abilities, hit points, proficiencies, death saves,
## inventory and equipment, spellcasting and class resources.
## Player characters and (for simplicity) monsters both use this class.
##
## Inventory: `inventory` holds every carried item, equipped ones included,
## as [{"item": id, "qty": int}] (one entry per id). `equipped` maps
## "main_hand" / "off_hand" / "armor" to an item id ("" = empty); an equipped
## id must be carried. Methods that need item / weapon definitions take a
## content dictionary (ContentLoader.cache() shape); {} means the cache.

const SCHEMA_VERSION := 1
const MAX_LEVEL := 20
const DEATH_SAVES_NEEDED := 3
const SLOT_MAIN_HAND := "main_hand"
const SLOT_OFF_HAND := "off_hand"
const SLOT_ARMOR := "armor"
const SLOTS: Array[String] = [SLOT_MAIN_HAND, SLOT_OFF_HAND, SLOT_ARMOR]
const GOLD_ITEM := "gold"
const BUFF_MAGE_ARMOR := "mage_armor"
const MAGE_ARMOR_BASE := 13
## Per-rest resource counters in class_resources: resource id -> the feature
## that grants it.
const RESOURCE_OWNERS: Dictionary[String, String] = {
	"second_wind": "second_wind", "action_surge": "action_surge", "rage": "rage",
	"lay_on_hands": "lay_on_hands", "bardic_inspiration": "bardic_inspiration", "ki": "ki",
	"channel_divinity": "channel_divinity", "sorcery_points": "font_of_magic",
	"arcane_recovery": "arcane_recovery", "natural_recovery": "natural_recovery",
	"indomitable": "indomitable", "wholeness_of_body": "wholeness_of_body",
	"divine_intervention": "divine_intervention", "dark_ones_own_luck": "dark_ones_own_luck",
	"cleansing_touch": "cleansing_touch", "stroke_of_luck": "stroke_of_luck", "wild_shape": "wild_shape",
}
## Resource ids (keys of class_resources).
const RESOURCE_FEATURES: Array[String] = [
	"second_wind", "action_surge", "rage", "lay_on_hands", "bardic_inspiration", "ki",
	"channel_divinity", "sorcery_points", "arcane_recovery", "natural_recovery",
	"indomitable", "wholeness_of_body", "divine_intervention", "dark_ones_own_luck",
	"cleansing_touch", "stroke_of_luck", "wild_shape",
]
## Resources that also come back on a short rest (the rest need a long rest).
## Bardic Inspiration joins them with Font of Inspiration.
const SHORT_REST_RESOURCES: Array[String] = ["second_wind", "action_surge", "ki", "channel_divinity", "dark_ones_own_luck", "stroke_of_luck", "wild_shape"]
## Once-per-long-rest spell uses kept in class_resources under these prefixes:
## "arcanum:<spell>" (Mystic Arcanum) and "invocation:<id>" (invocations that
## cast a spell once with a warlock slot).
const ARCANUM_PREFIX := "arcanum:"
const INVOCATION_PREFIX := "invocation:"
## Invocations that let a warlock cast a spell once per long rest with a slot.
const INVOCATION_SPELLS: Dictionary[String, String] = {
	"bewitching_whispers": "compulsion", "dreadful_word": "confusion", "mire_the_mind": "slow",
	"sign_of_ill_omen": "bestow_curse", "thief_of_five_fates": "bane", "sculptor_of_flesh": "polymorph",
	"minions_of_chaos": "conjure_elemental",
}
## Invocations that cast a spell at will on the warlock itself without a slot.
const AT_WILL_SELF_INVOCATIONS: Dictionary[String, String] = {
	"armor_of_shadows": "mage_armor", "fiendish_vigor": "false_life", "ascendant_step": "levitate",
	"otherworldly_leap": "jump",
}
const FIGHTING_STYLES: Array[String] = ["archery", "defense", "dueling", "great_weapon_fighting", "protection", "two_weapon_fighting"]
## Fighting styles the rules engine models.
const SUPPORTED_FIGHTING_STYLES: Array[String] = ["archery", "defense", "dueling", "great_weapon_fighting", "protection", "two_weapon_fighting"]
const SIZES: Array[String] = ["tiny", "small", "medium", "large", "huge", "gargantuan"]
const MAX_EXHAUSTION := 6
## Damage types (Fiendish Resilience options, Protection from Energy).
const DAMAGE_TYPES: Array[String] = [
	"fire", "cold", "lightning", "poison", "necrotic", "acid", "thunder", "psychic", "radiant", "force",
	"bludgeoning", "piercing", "slashing",
]
const PHYSICAL_TYPES: Array[String] = ["bludgeoning", "piercing", "slashing"]
const DRACONIC_AC_BASE := 13
## SRD rage uses by barbarian level (index = level); 20th level is unlimited (99).
const RAGE_USES: Array[int] = [0, 2, 2, 3, 3, 3, 4, 4, 4, 4, 4, 4, 5, 5, 5, 5, 5, 6, 6, 6, 99]

var name: String = ""
var class_id: String = ""
var ancestry_id: String = ""  # empty for monsters / legacy sheets
var level: int = 1
var xp: int = 0
var abilities: AbilityScores = AbilityScores.new()
var max_hp: int = 1
var current_hp: int = 1
var temp_hp: int = 0
var armor_base: int = 0  # worn armor's base AC; 0 = unarmored (10)
var armor_max_dex: int = -1  # cap on the DEX bonus from armor; -1 = no cap, 0 = heavy (DEX ignored)
var shield_bonus: int = 0  # shield (+2) or any other flat AC bonus
var speed: int = 30
var hit_die: int = 8
var hit_dice_total: int = 1  # equals level for characters
var hit_dice_remaining: int = 1
var proficient_saves: Array[int] = []  # Ability.Type values
var proficient_skills: Array[int] = []  # Skill.Type values
var death_save_successes: int = 0
var death_save_failures: int = 0
var stable: bool = false
var dead: bool = false
var uses_death_saves: bool = true  # false for monsters: they die at 0 hp
var conditions: Array[String] = []  # lasting conditions outside encounters (e.g. "poisoned")
var condition_immunities: Array[String] = []
var damage_resistances: Array[String] = []
var damage_immunities: Array[String] = []
var damage_vulnerabilities: Array[String] = []
var deepest_floor: int = 0
## Weapon attacks, each {"name", "kind": "melee"|"ranged"|"thrown", "to_hit": int,
## "damage": dice expr, "damage_type", "weapon_id", "item": weapon item id,
## "consumes": item id used up per attack ("" = none), "range_tiles": [normal,
## long], "ability": "STR"|"DEX", "properties": [...], "proficient": bool}.
## Built by rebuild_attacks(); empty = unarmed only.
var attacks: Array[Dictionary] = []
## Class feature ids (ClassDefinition.FEATURE_*; others are flavour).
var features: Array[String] = []
var weapon_proficiencies: Array[String] = []  # copied from the class ("simple", "dagger", ...)
var inventory: Array[Dictionary] = []  # [{"item": id, "qty": int}]
var equipped: Dictionary[String, String] = {SLOT_MAIN_HAND: "", SLOT_OFF_HAND: "", SLOT_ARMOR: ""}
## Spellcasting: casting_ability is an Ability.Type or -1. spells_known holds
## cantrips and spells the character knows (spellbook for a wizard);
## spells_prepared are castable (cantrips included). spell_slots[i] is the
## number of remaining slots of level i + 1; spell_slots_max the maximum.
var casting_ability: int = -1
var spells_known: Array[String] = []
var spells_prepared: Array[String] = []
var spell_slots: Array[int] = []
var spell_slots_max: Array[int] = []
var slot_recovery: String = "long_rest"  # "short_rest" for pact magic
## Remaining uses of per-rest class features (see RESOURCE_FEATURES).
var class_resources: Dictionary[String, int] = {}
## Lasting spell effects on this character ("mage_armor"); cleared by a long rest.
var active_buffs: Array[String] = []
## Progression choices: the class's subclass id ("" until chosen), fighting
## styles, skills with expertise (Skill.Type), eldritch invocations, metamagic
## options, and spells that are always prepared and do not count against the
## prepared / known limits (domain, circle, oath spells). Option features (pact
## boon, hunter's prey, land, dragon ancestor) are plain entries of `features`.
var subclass_id: String = ""
var fighting_styles: Array[String] = []
var expertise_skills: Array[int] = []
var invocations: Array[String] = []
var metamagic: Array[String] = []
var always_prepared: Array[String] = []
## Creature size ("tiny" .. "gargantuan"); shove / grapple need the target to
## be at most one size larger.
var size: String = "medium"
## Exhaustion level 0..6 (SRD): 1 disadvantage on ability checks, 2 speed
## halved, 3 disadvantage on attack rolls and saves, 4 hit point maximum
## halved, 5 speed 0, 6 death. A long rest removes one level.
var exhaustion: int = 0
## Monster stat blocks: total skill / save bonuses (Skill.Type / Ability.Type
## -> bonus) used instead of the computed modifier.
var skill_bonuses: Dictionary[int, int] = {}
var save_bonuses: Dictionary[int, int] = {}
var proficiency_override: int = 0  # monsters: the stat block's proficiency bonus (0 = by level)
var fly_speed: int = 0  # feet (monsters with a fly speed)
## Lasting companions that join each encounter at the owner's side (Find
## Familiar, Animate Dead): [{"monster": id, "spell": id, "hp": int}].
var companions: Array[Dictionary] = []
## Mystic Arcanum spells (warlock 11+), one per spell level 6..9.
var mystic_arcanum: Array[String] = []
## Fiendish Resilience: the damage type resisted ("" = none).
var chosen_resistance: String = ""
## Relentless Rage uses since the last rest (DC 10 + 5 per use).
var relentless_rage_uses: int = 0
## Raise Dead: penalty to attack rolls, saves and ability checks (drops by 1 per long rest).
var resurrection_penalty: int = 0
## Last number used for a companion id "c<n>" (core-owned: mint_companion_id).
var companion_serial: int = 0
## Round C: out-of-combat spell effects that last a number of encounters
## (OutOfCombat lingering spells: Foresight, Antipathy/Sympathy, Magic Jar,
## Disguise Self, ...): [{"spell", "slot_level", "kind" ("buff" | "zone" |
## "feature" | "stealth"), "encounters_left" (-1 = until the next long rest),
## "mode"?, "creature_type"?, "effect"?, "modifiers"?, "feature"?}]. The
## Encounter applies them when a fight starts and counts them down when it
## ends; a long rest clears them.
var lingering: Array[Dictionary] = []


func proficiency_bonus() -> int:
	if proficiency_override > 0:
		return proficiency_override
	return Proficiency.bonus_for_level(level)


## (armor_base, or 10 unarmored) + DEX modifier (capped by armor_max_dex) + shield_bonus.
## SRD heavy armor (armor_max_dex 0) ignores DEX entirely, even a penalty.
## Unarmored (armor_base 0) the best of: 10 + DEX, Mage Armor 13 + DEX,
## Unarmored Defense 10 + DEX + CON (shield allowed) or 10 + DEX + WIS (no shield).
func armor_class() -> int:
	var base := armor_base if armor_base > 0 else 10
	var raw_dex := abilities.get_modifier(Ability.Type.DEX)
	var dex := raw_dex
	if armor_max_dex == 0:
		dex = 0
	elif armor_max_dex > 0:
		dex = mini(dex, armor_max_dex)
	var ac := base + dex
	if armor_base <= 0:
		if active_buffs.has(BUFF_MAGE_ARMOR):
			ac = maxi(ac, MAGE_ARMOR_BASE + raw_dex)
		if features.has("draconic_resilience"):
			ac = maxi(ac, DRACONIC_AC_BASE + raw_dex)
		if features.has("unarmored_defense_con"):
			ac = maxi(ac, 10 + raw_dex + abilities.get_modifier(Ability.Type.CON))
		if features.has("unarmored_defense_wis") and shield_bonus == 0:
			ac = maxi(ac, 10 + raw_dex + abilities.get_modifier(Ability.Type.WIS))
	elif fighting_styles.has("defense"):
		ac += 1
	return ac + shield_bonus


## Wearing heavy armor (no DEX bonus at all).
func wears_heavy_armor() -> bool:
	return armor_base > 0 and armor_max_dex == 0


## Speed in feet with Fast Movement (+10 ft without heavy armor) and Unarmored
## Movement (no armor, no shield).
func effective_speed() -> int:
	var feet := speed
	if features.has("fast_movement") and not wears_heavy_armor():
		feet += 10
	if features.has("unarmored_movement") and armor_base <= 0 and shield_bonus == 0:
		feet += table_int("unarmored_movement", Progression.unarmored_movement_ft(level))
	if exhaustion >= 5:
		return 0
	if exhaustion >= 2:
		feet = floori(feet / 2.0)
	return feet


## Hit point maximum after exhaustion (halved from level 4).
func hit_point_maximum() -> int:
	return maxi(1, floori(max_hp / 2.0)) if exhaustion >= 4 else max_hp


## Adds (or removes, n < 0) exhaustion levels, clamped to 0..6. Level 4+ caps
## current hp at the halved maximum; level 6 is death. Returns the new level.
func add_exhaustion(n: int) -> int:
	exhaustion = clampi(exhaustion + n, 0, MAX_EXHAUSTION)
	current_hp = mini(current_hp, hit_point_maximum())
	if exhaustion >= MAX_EXHAUSTION:
		_die()
	return exhaustion


## Size index (0 tiny .. 5 gargantuan; unknown = medium).
func size_index() -> int:
	var i := SIZES.find(size)
	return i if i >= 0 else 2


func has_fighting_style(style: String) -> bool:
	return fighting_styles.has(style)


## Attack rolls per Attack action: 1, plus the class's Extra Attack table
## ("extra_attacks", SRD fighter 1 / 2 at 11 / 3 at 20) with the feature.
func attacks_per_action() -> int:
	if not features.has("extra_attack"):
		return 1
	return 1 + maxi(1, table_int("extra_attacks", 1))


## A level table of the class ("tables" in the class JSON) as an int at this
## level (see ClassDefinition.table_int); fallback without a class or table.
func table_int(table_name: String, fallback: int) -> int:
	var cls := class_definition()
	if cls == null or not cls.tables.has(table_name):
		return fallback
	return cls.table_int(table_name, level, fallback)


## As table_int, reading dice values as their die size ("1d6" -> 6).
func table_die(table_name: String, fallback: int) -> int:
	var cls := class_definition()
	if cls == null or not cls.tables.has(table_name):
		return fallback
	return cls.table_die(table_name, level, fallback)


func has_feature(feature: String) -> bool:
	return features.has(feature)


func ability_modifier(ability: int) -> int:
	return abilities.get_modifier(ability)


## Saving throw modifier: a stat block's save bonus, else the ability
## modifier + proficiency when proficient (Diamond Soul: every save).
func save_modifier(ability: int) -> int:
	if save_bonuses.has(ability):
		return save_bonuses[ability]
	var mod := abilities.get_modifier(ability)
	if proficient_saves.has(ability) or features.has("diamond_soul"):
		mod += proficiency_bonus()
	return mod


## Ability modifier + proficiency (doubled with Expertise); see check_modifier.
func skill_modifier(skill: int) -> int:
	return check_modifier(Skill.ability_for(skill), skill)


## Ability check modifier (SRD): the ability modifier, + proficiency for a
## proficient skill (doubled with Expertise); otherwise Jack of All Trades
## (half proficiency, rounded down) or Remarkable Athlete (STR / DEX / CON
## checks: half proficiency, rounded up), whichever is better. A stat block's
## skill bonus replaces the computed value. skill -1 = a plain ability check.
func check_modifier(ability: int, skill: int = -1) -> int:
	if skill >= 0 and skill_bonuses.has(skill):
		return skill_bonuses[skill]
	var mod := abilities.get_modifier(ability)
	if skill >= 0 and proficient_skills.has(skill):
		mod += proficiency_bonus()
		if expertise_skills.has(skill):
			mod += proficiency_bonus()
		return mod
	var half := 0
	if features.has("jack_of_all_trades"):
		half = floori(proficiency_bonus() / 2.0)
	if features.has("remarkable_athlete") and ability in [Ability.Type.STR, Ability.Type.DEX, Ability.Type.CON]:
		half = maxi(half, ceili(proficiency_bonus() / 2.0))
	return mod + half


## Proficient in the skill (Reliable Talent applies; stat-block skills count).
func is_skill_proficient(skill: int) -> bool:
	return skill >= 0 and (proficient_skills.has(skill) or skill_bonuses.has(skill))


## 10 + Wisdom (Perception) modifier.
func passive_perception() -> int:
	return 10 + check_modifier(Ability.Type.WIS, Skill.Type.PERCEPTION)


## Initiative is a Dexterity check (Jack of All Trades / Remarkable Athlete apply).
func initiative_modifier() -> int:
	return check_modifier(Ability.Type.DEX)


func is_alive() -> bool:
	return not dead


func is_dead() -> bool:
	return dead


func is_unconscious() -> bool:
	return not dead and current_hp == 0


func is_conscious() -> bool:
	return not dead and current_hp > 0


## Applies immunity (0), resistance (half, rounded down) and vulnerability
## (double). extra_resistances (e.g. Rage) do not stack with the sheet's own;
## extra_immunities likewise. Stat-block entries such as "bludgeoning,
## piercing, and slashing from nonmagical weapons" apply to those types unless
## the damage is magical (spells, magic weapons, Ki-Empowered Strikes). The
## Fiendish Resilience type (chosen_resistance) is resisted unless it is
## physical damage from a magical source.
func adjust_damage_for_type(amount: int, damage_type: String, extra_resistances: Array[String] = [], magical: bool = false, extra_immunities: Array[String] = []) -> int:
	var t := damage_type.to_lower()
	if t.is_empty():
		return amount
	if damage_immunities.has(t) or extra_immunities.has(t) or (not magical and CharacterSheet._listed_nonmagical(damage_immunities, t)):
		return 0
	var result := amount
	var chosen := not chosen_resistance.is_empty() and chosen_resistance == t and not (magical and PHYSICAL_TYPES.has(t))
	if damage_resistances.has(t) or extra_resistances.has(t) or chosen or (not magical and CharacterSheet._listed_nonmagical(damage_resistances, t)):
		result = floori(result / 2.0)
	if damage_vulnerabilities.has(t):
		result *= 2
	return result


## A stat-block entry like "bludgeoning, piercing, and slashing from
## nonmagical weapons" that names damage_type.
static func _listed_nonmagical(entries: Array[String], damage_type: String) -> bool:
	if not PHYSICAL_TYPES.has(damage_type):
		return false
	for e in entries:
		if e.contains("nonmagical") and e.contains(damage_type):
			return true
	return false


## Temporary hit points don't stack: keep the larger value.
func grant_temp_hp(amount: int) -> void:
	temp_hp = maxi(temp_hp, amount)


## SRD damage rules: temp hp absorbs first; dropping to 0 knocks a character
## unconscious (monsters die); leftover damage >= max hp is instant death;
## damage while at 0 hp is one death-save failure (two on a critical hit).
func take_damage(amount: int, critical: bool = false) -> DamageOutcome:
	var out := DamageOutcome.new()
	out.amount = maxi(amount, 0)
	out.critical = critical
	if dead:
		out.hp_after = current_hp
		return out
	var remaining := out.amount
	var absorbed := mini(temp_hp, remaining)
	temp_hp -= absorbed
	remaining -= absorbed
	out.absorbed_by_temp = absorbed
	if remaining > 0:
		if current_hp > 0:
			if remaining < current_hp:
				current_hp -= remaining
				out.hp_lost = remaining
			else:
				var leftover := remaining - current_hp
				out.hp_lost = current_hp
				current_hp = 0
				out.dropped_to_zero = true
				if leftover >= max_hp:
					out.instant_death = true
					out.died = true
					_die()
				elif not uses_death_saves:
					out.died = true
					_die()
				else:
					reset_death_saves()
		else:
			if remaining >= max_hp:
				out.instant_death = true
				out.died = true
				_die()
			else:
				var added := 2 if critical else 1
				out.death_save_failures_added = added
				stable = false
				death_save_failures = mini(DEATH_SAVES_NEEDED, death_save_failures + added)
				if death_save_failures >= DEATH_SAVES_NEEDED:
					out.died = true
					_die()
	out.hp_after = current_hp
	return out


## Returns hit points actually restored. Healing from 0 hp resets death saves.
## Exhaustion 4+ caps healing at the halved maximum.
func heal(amount: int) -> int:
	if dead or amount <= 0:
		return 0
	var before := current_hp
	current_hp = maxi(before, mini(hit_point_maximum(), current_hp + amount))
	if before == 0 and current_hp > 0:
		reset_death_saves()
	return current_hp - before


func reset_death_saves() -> void:
	death_save_successes = 0
	death_save_failures = 0
	stable = false


## Natural 20: regain 1 hp. Natural 1: two failures. 10+: success, else failure.
## Three successes: stable. Three failures: dead.
func roll_death_save(rng: Rng) -> DeathSaveOutcome:
	var out := DeathSaveOutcome.new()
	if dead or current_hp > 0 or stable or not uses_death_saves:
		out.successes = death_save_successes
		out.failures = death_save_failures
		return out
	out.rolled = true
	var d := D20.roll(rng)
	out.natural = d.natural
	if d.natural == 20:
		current_hp = 1
		reset_death_saves()
		out.success = true
		out.regained_consciousness = true
	elif d.natural == 1:
		death_save_failures += 2
	elif d.natural >= 10:
		death_save_successes += 1
		out.success = true
	else:
		death_save_failures += 1
	if death_save_failures >= DEATH_SAVES_NEEDED:
		death_save_failures = DEATH_SAVES_NEEDED
		out.died = true
		_die()
	elif death_save_successes >= DEATH_SAVES_NEEDED:
		death_save_successes = 0
		death_save_failures = 0
		stable = true
		out.became_stable = true
	out.successes = death_save_successes
	out.failures = death_save_failures
	return out


## Adds XP. Levels are NOT applied here: the player chooses them through
## LevelUp.choices() / LevelUp.apply(). Returns pending_levels().
func gain_xp(amount: int) -> int:
	if amount > 0:
		xp += amount
	return pending_levels()


## Levels the current XP allows beyond the current level (0 if none).
func pending_levels() -> int:
	return maxi(0, mini(MAX_LEVEL, Experience.level_for_xp(xp)) - level)


## Raises level by one without choices (tests, monsters; players use LevelUp).
## HP gain is the hit die average (hit_die / 2 + 1), or a roll when `average`
## is false and an rng is given, plus CON modifier, min 1. Also updates spell
## slots and class resources from the class (cls, or the cached class of
## class_id when null) and the to_hit of proficient attacks. Returns the hit
## points gained.
func level_up(rng: Rng = null, average: bool = true, cls: ClassDefinition = null) -> int:
	if level >= MAX_LEVEL:
		return 0
	var base := floori(hit_die / 2.0) + 1
	if not average and rng != null:
		base = rng.next_int(1, hit_die)
	var gain := maxi(1, base + abilities.get_modifier(Ability.Type.CON))
	advance_level(gain, cls)
	return gain + hp_bonus_per_level()


## Extra hit points per level from features (Draconic Resilience: 1).
func hp_bonus_per_level() -> int:
	return 1 if features.has("draconic_resilience") else 0


## The bookkeeping of one level: level + 1, hp + gain (+ hp_bonus_per_level),
## one more hit die, proficient attacks' to_hit follow the proficiency bonus,
## then spell slots and class resources follow the class table (see
## apply_class_level).
func advance_level(hp_gain: int, cls: ClassDefinition = null) -> void:
	var old_prof := proficiency_bonus()
	var resource_before := _resource_maxima()
	level += 1
	hp_gain += hp_bonus_per_level()
	max_hp += hp_gain
	if is_conscious():
		current_hp += hp_gain
	hit_dice_total = level
	hit_dice_remaining = mini(hit_dice_total, hit_dice_remaining + 1)
	var delta := proficiency_bonus() - old_prof
	if delta != 0:
		for attack in attacks:
			if attack.get("proficient", false) == true:
				attack["to_hit"] = DictUtil.to_int(attack["to_hit"]) + delta
	apply_class_level(cls)
	for feature: String in resource_before.keys():
		var gained := resource_max(feature) - DictUtil.to_int(resource_before[feature])
		if gained > 0:
			class_resources[feature] = class_resource(feature) + gained


## Sets spell_slots_max from the class slot table for the current level; new
## slots are available at once (remaining slots grow by the increase). cls null
## = the class of class_id in ContentLoader.cache() (monster sheets: nothing).
func apply_class_level(cls: ClassDefinition = null) -> void:
	var def := cls
	if def == null:
		def = class_definition()
	if def == null or def.spell_slot_table.is_empty():
		return
	if casting_ability < 0 and def.spellcasting_ability >= 0:
		casting_ability = def.spellcasting_ability
	slot_recovery = def.slot_recovery
	var new_max := def.slots_for_level(level)
	var new_slots: Array[int] = []
	for i in range(new_max.size()):
		var old_max := spell_slots_max[i] if i < spell_slots_max.size() else 0
		var old_left := spell_slots[i] if i < spell_slots.size() else 0
		new_slots.append(clampi(old_left + maxi(0, new_max[i] - old_max), 0, new_max[i]))
	spell_slots_max = new_max
	spell_slots = new_slots


## This character's ClassDefinition from ContentLoader.cache() (null for
## monsters and unknown classes).
func class_definition(content: Dictionary = {}) -> ClassDefinition:
	if class_id.is_empty() or class_id.begins_with("monster:"):
		return null
	var classes: Dictionary = ContentLoader.resolve(content)["classes"]
	if not classes.has(class_id):
		return null
	var def: ClassDefinition = classes[class_id]
	return def


# --- companions ----------------------------------------------------------------

## The next companion id "c<n>" (never reused: companion_serial only grows,
## and ids already on the sheet are skipped).
func mint_companion_id() -> String:
	for entry in companions:
		var cid := str(entry.get("id", ""))
		if cid.begins_with("c") and cid.substr(1).is_valid_int():
			companion_serial = maxi(companion_serial, cid.substr(1).to_int())
	companion_serial += 1
	return "c%d" % companion_serial


## Gives every companion without an "id" the next "c<n>" (in list order).
func stamp_companion_ids() -> void:
	for entry in companions:
		if str(entry.get("id", "")).is_empty():
			entry["id"] = mint_companion_id()


## The companion entry with this id ({} when none).
func companion_by_id(companion_id: String) -> Dictionary:
	for entry in companions:
		if str(entry.get("id", "")) == companion_id:
			return entry
	return {}


# --- class resources ---------------------------------------------------------

## Maximum of a resource (RESOURCE_FEATURES) at the current level, or 0 when
## the character lacks the feature that grants it. Sized from the class's
## "tables" when present, else from the SRD formulas.
func resource_max(resource: String) -> int:
	if resource.begins_with(ARCANUM_PREFIX):
		return 1 if mystic_arcanum.has(resource.trim_prefix(ARCANUM_PREFIX)) else 0
	if resource.begins_with(INVOCATION_PREFIX):
		return 1 if invocations.has(resource.trim_prefix(INVOCATION_PREFIX)) else 0
	var owner: String = RESOURCE_OWNERS.get(resource, "")
	if owner.is_empty() or not features.has(owner):
		return 0
	match resource:
		"second_wind", "arcane_recovery", "natural_recovery":
			return 1
		"action_surge":
			return table_int("action_surges", 2 if level >= 17 else 1)
		"rage":
			return table_int("rage_uses", RAGE_USES[clampi(level, 1, MAX_LEVEL)])
		"lay_on_hands":
			return table_int("lay_on_hands_pool", 5 * level)
		"bardic_inspiration":
			return maxi(1, abilities.get_modifier(Ability.Type.CHA))
		"ki":
			return table_int("ki_points", level)
		"channel_divinity":
			return table_int("channel_divinity_uses", Progression.channel_divinity_uses(class_id, level))
		"sorcery_points":
			return table_int("sorcery_points", level)
		"indomitable":
			return table_int("indomitable_uses", 3 if level >= 17 else (2 if level >= 13 else 1))
		"wholeness_of_body", "divine_intervention", "dark_ones_own_luck", "stroke_of_luck":
			return 1
		"cleansing_touch":
			return maxi(1, abilities.get_modifier(Ability.Type.CHA))
		"wild_shape":
			return 99 if level >= 20 else 2
	return 0


## Once-per-long-rest spell keys this sheet owns ("arcanum:<spell>",
## "invocation:<id>" for INVOCATION_SPELLS).
func once_per_rest_spell_keys() -> Array[String]:
	var out: Array[String] = []
	for s in mystic_arcanum:
		out.append(ARCANUM_PREFIX + s)
	for inv in invocations:
		if INVOCATION_SPELLS.has(inv):
			out.append(INVOCATION_PREFIX + inv)
	return out


func class_resource(feature: String) -> int:
	return DictUtil.to_int(class_resources.get(feature, 0))


## Whether a resource comes back on a short rest (Bardic Inspiration with Font
## of Inspiration).
func resource_short_rest(resource: String) -> bool:
	if resource == "bardic_inspiration":
		return features.has("font_of_inspiration")
	return SHORT_REST_RESOURCES.has(resource)


## Refills every resource feature (long rest), or only the short-rest ones.
## A long rest also restores the once-per-rest spells (Mystic Arcanum,
## invocation spells).
func restore_class_resources(short_rest_only: bool = false) -> void:
	for resource in RESOURCE_FEATURES:
		if not features.has(str(RESOURCE_OWNERS[resource])):
			continue
		if short_rest_only and not resource_short_rest(resource):
			continue
		class_resources[resource] = resource_max(resource)
	if not short_rest_only:
		for key in once_per_rest_spell_keys():
			class_resources[key] = 1


## Adds a feature (if missing); resources it grants start full and Draconic
## Resilience adds its hit points for the levels so far.
func gain_feature(feature: String) -> void:
	if features.has(feature):
		return
	features.append(feature)
	for resource in RESOURCE_FEATURES:
		if str(RESOURCE_OWNERS[resource]) == feature:
			class_resources[resource] = resource_max(resource)
	if feature == "draconic_resilience":
		max_hp += level
		if is_conscious():
			current_hp += level
	if feature == "slippery_mind" and not proficient_saves.has(Ability.Type.WIS):
		proficient_saves.append(Ability.Type.WIS)
	if feature in ["purity_of_body", "natures_ward"]:
		if not damage_immunities.has("poison"):
			damage_immunities.append("poison")
		if not condition_immunities.has(Conditions.POISONED):
			condition_immunities.append(Conditions.POISONED)


## Spends n uses; false (nothing spent) when fewer remain.
func spend_class_resource(feature: String, n: int = 1) -> bool:
	if n <= 0 or class_resource(feature) < n:
		return false
	class_resources[feature] = class_resource(feature) - n
	return true


func _resource_maxima() -> Dictionary:
	var out := {}
	for resource in RESOURCE_FEATURES:
		if features.has(str(RESOURCE_OWNERS[resource])):
			out[resource] = resource_max(resource)
	return out


## Sneak Attack dice at this level: 1d6 per two rogue levels, rounded up.
func sneak_attack_dice() -> String:
	return "%dd6" % table_int("sneak_attack_dice", ceili(level / 2.0))


## Martial Arts die size (4, 6 at 5, 8 at 11, 10 at 17).
func martial_arts_die() -> int:
	return table_die("martial_arts_die", Progression.martial_arts_die(level))


## Bardic Inspiration die size (6, 8 at 5, 10 at 10, 12 at 15).
func bardic_inspiration_die() -> int:
	return table_die("bardic_inspiration_die", Progression.bardic_die(level))


# --- spellcasting ------------------------------------------------------------

func is_spellcaster() -> bool:
	return casting_ability >= 0


func casting_modifier() -> int:
	return abilities.get_modifier(casting_ability) if casting_ability >= 0 else 0


## Proficiency bonus + spellcasting ability modifier.
func spell_attack_bonus() -> int:
	return proficiency_bonus() + casting_modifier()


## 8 + proficiency bonus + spellcasting ability modifier.
func spell_save_dc() -> int:
	return 8 + proficiency_bonus() + casting_modifier()


func is_spell_prepared(spell_id: String) -> bool:
	return spells_prepared.has(spell_id)


## Remaining slots of a spell level (1..9); 0 when none.
func slots_left(slot_level: int) -> int:
	if slot_level < 1 or slot_level > spell_slots.size():
		return 0
	return spell_slots[slot_level - 1]


## Highest spell level with a maximum slot count above 0 (0 = none).
func highest_slot_level() -> int:
	for i in range(spell_slots_max.size() - 1, -1, -1):
		if spell_slots_max[i] > 0:
			return i + 1
	return 0


## Lowest slot level >= min_level with a slot left, or 0.
func lowest_available_slot(min_level: int) -> int:
	for lvl in range(maxi(1, min_level), spell_slots.size() + 1):
		if spell_slots[lvl - 1] > 0:
			return lvl
	return 0


## Spends one slot of slot_level; false (nothing spent) when none is left.
func use_spell_slot(slot_level: int) -> bool:
	if slots_left(slot_level) <= 0:
		return false
	spell_slots[slot_level - 1] -= 1
	return true


func restore_spell_slots() -> void:
	spell_slots = spell_slots_max.duplicate()


# --- inventory and equipment -------------------------------------------------

func count_item(item_id: String) -> int:
	for entry in inventory:
		if str(entry["item"]) == item_id:
			return DictUtil.to_int(entry["qty"])
	return 0


func has_item(item_id: String, qty: int = 1) -> bool:
	return count_item(item_id) >= qty


func gold() -> int:
	return count_item(GOLD_ITEM)


## Adds qty (>= 1) of an item, stacking onto its existing entry.
func add_item(item_id: String, qty: int = 1) -> void:
	if item_id.is_empty() or qty <= 0:
		return
	for entry in inventory:
		if str(entry["item"]) == item_id:
			entry["qty"] = DictUtil.to_int(entry["qty"]) + qty
			return
	inventory.append({"item": item_id, "qty": qty})


## Removes qty of an item; false (and no change) when fewer are carried. If
## fewer copies remain than slots holding the item, those slots are emptied
## (off hand first) and armor / attacks are updated with `content`.
func remove_item(item_id: String, qty: int = 1, content: Dictionary = {}) -> bool:
	if qty <= 0 or count_item(item_id) < qty:
		return false
	for i in range(inventory.size()):
		if str(inventory[i]["item"]) == item_id:
			var left := DictUtil.to_int(inventory[i]["qty"]) - qty
			if left <= 0:
				inventory.remove_at(i)
			else:
				inventory[i]["qty"] = left
			break
	var changed := false
	for slot: String in [SLOT_OFF_HAND, SLOT_MAIN_HAND, SLOT_ARMOR]:
		if equipped_count(item_id) > count_item(item_id) and equipped_item(slot) == item_id:
			_clear_slot(slot)
			changed = true
	if changed or _has_attack_using(item_id):
		rebuild_attacks(content)
	return true


## Number of equipment slots holding item_id.
func equipped_count(item_id: String) -> int:
	var n := 0
	for slot in SLOTS:
		if equipped_item(slot) == item_id:
			n += 1
	return n


func equipped_item(slot: String) -> String:
	var held: String = equipped.get(slot, "")
	return held


## Equips a carried item. main_hand: a weapon; off_hand: a shield or a light
## weapon; armor: armor. An occupied slot is swapped (the old item stays in
## the inventory). A shield or off-hand weapon needs a free hand (no
## two-handed main-hand weapon) and vice versa. Updates armor_base /
## armor_max_dex / shield_bonus and rebuilds attacks. Returns "" or an error.
## Armor proficiency is not enforced (M2).
func equip(item_id: String, slot: String, content: Dictionary = {}) -> String:
	var c := ContentLoader.resolve(content)
	if not SLOTS.has(slot):
		return "unknown slot '%s'" % slot
	if not has_item(item_id):
		return "%s is not carried" % item_id
	if equipped_item(slot) == item_id:
		return ""
	var copies_needed := equipped_count(item_id) + 1
	if count_item(item_id) < copies_needed:
		return "only %d %s carried" % [count_item(item_id), item_id]
	var item := CharacterSheet.item_def(item_id, c)
	var weapon := CharacterSheet.weapon_for_item(item_id, c)
	var kind := item.kind if item != null else (ItemDefinition.KIND_WEAPON if weapon != null else "")
	match slot:
		SLOT_MAIN_HAND:
			if kind != ItemDefinition.KIND_WEAPON or weapon == null:
				return "%s is not a weapon" % item_id
			if weapon.is_two_handed() and not equipped_item(SLOT_OFF_HAND).is_empty():
				return "%s needs both hands: empty the off hand first" % item_id
		SLOT_OFF_HAND:
			if kind == ItemDefinition.KIND_SHIELD:
				pass
			elif kind == ItemDefinition.KIND_WEAPON and weapon != null and weapon.has_property("light"):
				pass
			else:
				return "%s cannot be held in the off hand" % item_id
			var main := CharacterSheet.weapon_for_item(equipped_item(SLOT_MAIN_HAND), c)
			if main != null and main.is_two_handed():
				return "the main-hand weapon needs both hands"
		SLOT_ARMOR:
			if kind != ItemDefinition.KIND_ARMOR or item == null:
				return "%s is not armor" % item_id
	_clear_slot(slot)
	equipped[slot] = item_id
	if slot == SLOT_ARMOR:
		armor_base = item.armor_base
		armor_max_dex = item.armor_max_dex
	elif slot == SLOT_OFF_HAND and kind == ItemDefinition.KIND_SHIELD:
		shield_bonus = item.shield_bonus
	rebuild_attacks(c)
	return ""


## Empties a slot (the item stays in the inventory). Returns "" or an error.
func unequip(slot: String, content: Dictionary = {}) -> String:
	if not SLOTS.has(slot):
		return "unknown slot '%s'" % slot
	if equipped_item(slot).is_empty():
		return ""
	_clear_slot(slot)
	rebuild_attacks(content)
	return ""


func _clear_slot(slot: String) -> void:
	var held := equipped_item(slot)
	equipped[slot] = ""
	if held.is_empty():
		return
	if slot == SLOT_ARMOR:
		armor_base = 0
		armor_max_dex = -1
	elif slot == SLOT_OFF_HAND:
		shield_bonus = 0


func _has_attack_using(item_id: String) -> bool:
	for attack in attacks:
		if attack.get("item", "") == item_id or attack.get("consumes", "") == item_id:
			return true
	return false


## Rebuilds `attacks` from the equipment and inventory, in this order:
## the main-hand weapon (melee, or ranged with its ammunition), its thrown
## attack if it has the thrown property, then each other carried weapon that
## can be thrown or shot (drawing a weapon is the free object interaction),
## in inventory order. Thrown attacks use up the weapon item; ranged attacks
## use up the ammunition item (item or weapon "ammo_id"). Items whose weapon
## is unknown are skipped. Last, with light melee weapons in both hands, the
## off-hand attack ("off_hand": true, a bonus action; no positive ability
## modifier to damage without the Two-Weapon Fighting style).
## Fighting styles: Dueling (+2 damage, main-hand melee weapon not two-handed,
## no off-hand weapon), Great Weapon Fighting ("reroll_max": 2 on a two-handed
## melee weapon), Archery (see CharacterBuilder.weapon_attack).
func rebuild_attacks(content: Dictionary = {}) -> void:
	var c := ContentLoader.resolve(content)
	attacks.clear()
	var main := equipped_item(SLOT_MAIN_HAND)
	var off := equipped_item(SLOT_OFF_HAND)
	var off_weapon := CharacterSheet.weapon_for_item(off, c)
	var main_weapon: WeaponDefinition = null
	if not main.is_empty():
		var w := CharacterSheet.weapon_for_item(main, c)
		main_weapon = w
		if w != null:
			if w.ranged and not w.is_thrown():
				attacks.append(CharacterBuilder.weapon_attack(self, w, _proficient(w, c), "ranged", main, CharacterSheet.ammo_for_item(main, c)))
			elif w.ranged:
				attacks.append(CharacterBuilder.weapon_attack(self, w, _proficient(w, c), "thrown", main, main))
			else:
				var dueling := 2 if has_fighting_style("dueling") and not w.is_two_handed() and off_weapon == null else 0
				var melee := CharacterBuilder.weapon_attack(self, w, _proficient(w, c), "melee", main, "", dueling)
				if has_fighting_style("great_weapon_fighting") and w.is_two_handed():
					melee["reroll_max"] = 2
				attacks.append(melee)
				if w.is_thrown():
					attacks.append(CharacterBuilder.weapon_attack(self, w, _proficient(w, c), "thrown", main, main))
	for entry in inventory:
		var item_id := str(entry["item"])
		if item_id == main or DictUtil.to_int(entry["qty"]) <= 0:
			continue
		var w := CharacterSheet.weapon_for_item(item_id, c)
		if w == null:
			continue
		if w.is_thrown():
			attacks.append(CharacterBuilder.weapon_attack(self, w, _proficient(w, c), "thrown", item_id, item_id))
		elif w.ranged:
			attacks.append(CharacterBuilder.weapon_attack(self, w, _proficient(w, c), "ranged", item_id, CharacterSheet.ammo_for_item(item_id, c)))
	if off_weapon != null and main_weapon != null and not off_weapon.ranged and not main_weapon.ranged \
			and off_weapon.has_property("light") and main_weapon.has_property("light"):
		var off_attack := CharacterBuilder.weapon_attack(self, off_weapon, _proficient(off_weapon, c), "melee", off, "", 0, has_fighting_style("two_weapon_fighting"))
		off_attack["name"] = "%s (off hand)" % off_weapon.display_name
		off_attack["off_hand"] = true
		attacks.append(off_attack)


func _proficient(weapon: WeaponDefinition, content: Dictionary) -> bool:
	var profs := weapon_proficiencies
	if profs.is_empty():
		var cls := class_definition(content)
		if cls != null:
			profs = cls.weapon_proficiencies
	return profs.has(weapon.category) or profs.has(weapon.id)


static func item_def(item_id: String, content: Dictionary) -> ItemDefinition:
	var items: Dictionary = content.get("items", {})
	if items.has(item_id):
		var it: ItemDefinition = items[item_id]
		return it
	return null


## The weapon an item wields: its weapon_id, or a weapon with the item's own id.
static func weapon_for_item(item_id: String, content: Dictionary) -> WeaponDefinition:
	if item_id.is_empty():
		return null
	var weapons: Dictionary = content.get("weapons", {})
	var item := CharacterSheet.item_def(item_id, content)
	var weapon_id := item_id
	if item != null:
		if item.kind != ItemDefinition.KIND_WEAPON:
			return null
		weapon_id = item.weapon_id
	if weapons.has(weapon_id):
		var w: WeaponDefinition = weapons[weapon_id]
		return w
	return null


## Ammunition item id for a weapon item: the item's ammo_id, else the weapon's ("" = none).
static func ammo_for_item(item_id: String, content: Dictionary) -> String:
	var item := CharacterSheet.item_def(item_id, content)
	if item != null and not item.ammo_id.is_empty():
		return item.ammo_id
	var w := CharacterSheet.weapon_for_item(item_id, content)
	return w.ammo_id if w != null else ""


## SRD unarmed strike: proficiency + STR to hit, 1 + STR bludgeoning damage.
## Martial Arts (monk): 1d4 + the better of STR and DEX.
func unarmed_strike() -> Dictionary:
	var str_mod := abilities.get_modifier(Ability.Type.STR)
	var attack := {
		"name": "Unarmed Strike",
		"kind": "melee",
		"to_hit": proficiency_bonus() + str_mod,
		"damage": str(maxi(0, 1 + str_mod)),
		"damage_type": "bludgeoning",
		"unarmed": true,
		"ability": "STR",
		"range_tiles": [1, 1],
		"proficient": true,
	}
	if features.has("martial_arts"):
		var dex_mod := abilities.get_modifier(Ability.Type.DEX)
		var mod := maxi(str_mod, dex_mod)
		attack["to_hit"] = proficiency_bonus() + mod
		attack["damage"] = "1d%d" % martial_arts_die() + CharacterBuilder.signed(mod)
		attack["ability"] = "DEX" if dex_mod > str_mod else "STR"
	return attack


## Kills the character outright (e.g. the server finishing off a downed
## player after a party wipe). Clears stability and sets hit points to 0.
func kill() -> void:
	_die()


func _die() -> void:
	dead = true
	current_hp = 0
	stable = false


func to_dict() -> Dictionary:
	return {
		"schema_version": SCHEMA_VERSION,
		"name": name,
		"class_id": class_id,
		"ancestry_id": ancestry_id,
		"level": level,
		"xp": xp,
		"abilities": abilities.to_dict(),
		"max_hp": max_hp,
		"current_hp": current_hp,
		"temp_hp": temp_hp,
		"armor_base": armor_base,
		"armor_max_dex": armor_max_dex,
		"shield_bonus": shield_bonus,
		"speed": speed,
		"hit_die": hit_die,
		"hit_dice_total": hit_dice_total,
		"hit_dice_remaining": hit_dice_remaining,
		"proficient_saves": DictUtil.ability_keys(proficient_saves),
		"proficient_skills": DictUtil.skill_keys(proficient_skills),
		"death_save_successes": death_save_successes,
		"death_save_failures": death_save_failures,
		"stable": stable,
		"dead": dead,
		"uses_death_saves": uses_death_saves,
		"conditions": conditions.duplicate(),
		"condition_immunities": condition_immunities.duplicate(),
		"subclass_id": subclass_id,
		"fighting_styles": fighting_styles.duplicate(),
		"expertise_skills": DictUtil.skill_keys(expertise_skills),
		"invocations": invocations.duplicate(),
		"metamagic": metamagic.duplicate(),
		"always_prepared": always_prepared.duplicate(),
		"damage_resistances": damage_resistances.duplicate(),
		"damage_immunities": damage_immunities.duplicate(),
		"damage_vulnerabilities": damage_vulnerabilities.duplicate(),
		"deepest_floor": deepest_floor,
		"attacks": attacks.duplicate(true),
		"features": features.duplicate(),
		"weapon_proficiencies": weapon_proficiencies.duplicate(),
		"inventory": inventory.duplicate(true),
		"equipped": {SLOT_MAIN_HAND: equipped_item(SLOT_MAIN_HAND), SLOT_OFF_HAND: equipped_item(SLOT_OFF_HAND), SLOT_ARMOR: equipped_item(SLOT_ARMOR)},
		"casting_ability": Ability.abbreviation(casting_ability) if casting_ability >= 0 else "",
		"spells_known": spells_known.duplicate(),
		"spells_prepared": spells_prepared.duplicate(),
		"spell_slots": spell_slots.duplicate(),
		"spell_slots_max": spell_slots_max.duplicate(),
		"slot_recovery": slot_recovery,
		"class_resources": _resources_dict(),
		"active_buffs": active_buffs.duplicate(),
		"size": size,
		"exhaustion": exhaustion,
		"skill_bonuses": CharacterSheet._keyed(skill_bonuses, true),
		"save_bonuses": CharacterSheet._keyed(save_bonuses, false),
		"proficiency_override": proficiency_override,
		"fly_speed": fly_speed,
		"companions": companions.duplicate(true),
		"mystic_arcanum": mystic_arcanum.duplicate(),
		"chosen_resistance": chosen_resistance,
		"relentless_rage_uses": relentless_rage_uses,
		"resurrection_penalty": resurrection_penalty,
		"companion_serial": companion_serial,
		"lingering": lingering.duplicate(true),
	}


## {Skill / Ability key: bonus} for JSON.
static func _keyed(values: Dictionary[int, int], skills: bool) -> Dictionary:
	var out := {}
	for k: int in values.keys():
		out[Skill.key_of(k) if skills else Ability.abbreviation(k)] = values[k]
	return out


func _resources_dict() -> Dictionary:
	var out := {}
	for key: String in class_resources.keys():
		out[key] = class_resources[key]
	return out


static func from_dict(d: Dictionary) -> CharacterSheet:
	var s := CharacterSheet.new()
	s.name = str(d.get("name", ""))
	s.class_id = str(d.get("class_id", ""))
	s.ancestry_id = str(d.get("ancestry_id", ""))
	s.level = clampi(DictUtil.to_int(d.get("level", 1), 1), 1, MAX_LEVEL)
	s.xp = DictUtil.to_int(d.get("xp", 0), 0)
	var ab: Variant = d.get("abilities", {})
	if typeof(ab) == TYPE_DICTIONARY:
		var ab_dict: Dictionary = ab
		s.abilities = AbilityScores.from_dict(ab_dict)
	s.max_hp = maxi(1, DictUtil.to_int(d.get("max_hp", 1), 1))
	s.current_hp = clampi(DictUtil.to_int(d.get("current_hp", s.max_hp), s.max_hp), 0, s.max_hp)
	s.temp_hp = maxi(0, DictUtil.to_int(d.get("temp_hp", 0), 0))
	if d.has("armor_base") or not d.has("armor_bonus"):
		s.armor_base = maxi(0, DictUtil.to_int(d.get("armor_base", 0), 0))
		s.armor_max_dex = DictUtil.to_int(d.get("armor_max_dex", -1), -1)
		s.shield_bonus = DictUtil.to_int(d.get("shield_bonus", 0), 0)
	else:
		# Legacy (M0) sheets: AC = 10 + DEX + armor_bonus.
		s.shield_bonus = DictUtil.to_int(d.get("armor_bonus", 0), 0)
	s.speed = DictUtil.to_int(d.get("speed", 30), 30)
	s.hit_die = DictUtil.to_int(d.get("hit_die", 8), 8)
	s.hit_dice_total = DictUtil.to_int(d.get("hit_dice_total", s.level), s.level)
	s.hit_dice_remaining = DictUtil.to_int(d.get("hit_dice_remaining", s.hit_dice_total), s.hit_dice_total)
	for save in DictUtil.to_ability_array(d.get("proficient_saves", [])):
		if save >= 0 and not s.proficient_saves.has(save):
			s.proficient_saves.append(save)
	for skill in DictUtil.to_skill_array(d.get("proficient_skills", [])):
		if skill >= 0 and not s.proficient_skills.has(skill):
			s.proficient_skills.append(skill)
	s.death_save_successes = DictUtil.to_int(d.get("death_save_successes", 0), 0)
	s.death_save_failures = DictUtil.to_int(d.get("death_save_failures", 0), 0)
	s.stable = DictUtil.to_bool(d.get("stable", false), false)
	s.dead = DictUtil.to_bool(d.get("dead", false), false)
	s.uses_death_saves = DictUtil.to_bool(d.get("uses_death_saves", true), true)
	s.conditions = DictUtil.to_string_array(d.get("conditions", []))
	s.condition_immunities = DictUtil.to_string_array(d.get("condition_immunities", []))
	s.subclass_id = str(d.get("subclass_id", ""))
	s.fighting_styles = DictUtil.to_string_array(d.get("fighting_styles", []))
	for skill in DictUtil.to_skill_array(d.get("expertise_skills", [])):
		if skill >= 0 and not s.expertise_skills.has(skill):
			s.expertise_skills.append(skill)
	s.invocations = DictUtil.to_string_array(d.get("invocations", []))
	s.metamagic = DictUtil.to_string_array(d.get("metamagic", []))
	s.always_prepared = DictUtil.to_string_array(d.get("always_prepared", []))
	s.damage_resistances = DictUtil.to_string_array(d.get("damage_resistances", []))
	s.damage_immunities = DictUtil.to_string_array(d.get("damage_immunities", []))
	s.damage_vulnerabilities = DictUtil.to_string_array(d.get("damage_vulnerabilities", []))
	s.deepest_floor = DictUtil.to_int(d.get("deepest_floor", 0), 0)
	for raw in DictUtil.to_dict_array(d.get("attacks", [])):
		s.attacks.append(CharacterSheet.normalize_attack(raw))
	s.features = DictUtil.to_string_array(d.get("features", []))
	s.weapon_proficiencies = DictUtil.to_string_array(d.get("weapon_proficiencies", []))
	for raw in DictUtil.to_dict_array(d.get("inventory", [])):
		s.add_item(str(raw.get("item", "")), DictUtil.to_int(raw.get("qty", 1), 0))
	var eq: Variant = d.get("equipped", {})
	if typeof(eq) == TYPE_DICTIONARY:
		var eq_d: Dictionary = eq
		for slot in SLOTS:
			var held := "" if eq_d.get(slot) == null else str(eq_d.get(slot, ""))
			s.equipped[slot] = held if s.has_item(held) else ""
	var ability_v: Variant = d.get("casting_ability", "")
	s.casting_ability = -1 if ability_v == null or str(ability_v).is_empty() else Ability.from_string(str(ability_v))
	s.spells_known = DictUtil.to_string_array(d.get("spells_known", []))
	s.spells_prepared = DictUtil.to_string_array(d.get("spells_prepared", []))
	s.spell_slots_max = DictUtil.to_int_array(d.get("spell_slots_max", []))
	s.spell_slots = DictUtil.to_int_array(d.get("spell_slots", s.spell_slots_max))
	s.spell_slots.resize(s.spell_slots_max.size())
	s.slot_recovery = str(d.get("slot_recovery", "long_rest"))
	var res: Variant = d.get("class_resources", {})
	if typeof(res) == TYPE_DICTIONARY:
		var res_d: Dictionary = res
		for key: Variant in res_d.keys():
			s.class_resources[str(key)] = DictUtil.to_int(res_d[key], 0)
	s.active_buffs = DictUtil.to_string_array(d.get("active_buffs", []))
	s.size = str(d.get("size", "medium")).to_lower()
	s.exhaustion = clampi(DictUtil.to_int(d.get("exhaustion", 0), 0), 0, MAX_EXHAUSTION)
	var sk: Variant = d.get("skill_bonuses", {})
	if typeof(sk) == TYPE_DICTIONARY:
		var sk_d: Dictionary = sk
		for key: Variant in sk_d.keys():
			var skill := Skill.from_string(str(key))
			if skill >= 0:
				s.skill_bonuses[skill] = DictUtil.to_int(sk_d[key], 0)
	var sv: Variant = d.get("save_bonuses", {})
	if typeof(sv) == TYPE_DICTIONARY:
		var sv_d: Dictionary = sv
		for key: Variant in sv_d.keys():
			var ability := Ability.from_string(str(key))
			if ability >= 0:
				s.save_bonuses[ability] = DictUtil.to_int(sv_d[key], 0)
	s.proficiency_override = DictUtil.to_int(d.get("proficiency_override", 0), 0)
	s.fly_speed = DictUtil.to_int(d.get("fly_speed", 0), 0)
	s.companions = DictUtil.to_dict_array(d.get("companions", []))
	s.mystic_arcanum = DictUtil.to_string_array(d.get("mystic_arcanum", []))
	s.chosen_resistance = str(d.get("chosen_resistance", ""))
	s.relentless_rage_uses = DictUtil.to_int(d.get("relentless_rage_uses", 0), 0)
	s.resurrection_penalty = DictUtil.to_int(d.get("resurrection_penalty", 0), 0)
	s.companion_serial = DictUtil.to_int(d.get("companion_serial", 0), 0)
	s.lingering = DictUtil.to_dict_array(d.get("lingering", []))
	return s


## Copies an attack dictionary with JSON-safe, typed values (to_hit as int).
static func normalize_attack(raw: Dictionary) -> Dictionary:
	var attack: Dictionary = raw.duplicate(true)
	attack["name"] = str(raw.get("name", "Attack"))
	attack["kind"] = str(raw.get("kind", "melee"))
	attack["to_hit"] = DictUtil.to_int(raw.get("to_hit", 0), 0)
	attack["damage"] = str(raw.get("damage", "0"))
	attack["damage_type"] = str(raw.get("damage_type", "")).to_lower()
	if raw.has("range_tiles"):
		var tiles := DictUtil.to_int_array(raw["range_tiles"])
		if tiles.size() == 2:
			attack["range_tiles"] = [tiles[0], tiles[1]]
	return attack
