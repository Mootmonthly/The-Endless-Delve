class_name Progression
extends RefCounted
## SRD class progression numbers used when a class JSON has no "tables" entry
## (tests, legacy data). Class data tables take precedence (CharacterSheet.table_int).

## Sorcery points needed to create a spell slot of level 1..5 (Flexible Casting).
const SLOT_CREATION_COST: Dictionary[int, int] = {1: 2, 2: 3, 3: 5, 4: 6, 5: 7}
const MAX_CREATED_SLOT := 5
## Arcane Recovery / Natural Recovery: no recovered slot above this level.
const MAX_RECOVERED_SLOT := 5


## Unarmored Movement bonus in feet (monk 2+: 10, 6: 15, 10: 20, 14: 25, 18: 30).
static func unarmored_movement_ft(level: int) -> int:
	if level < 2:
		return 0
	if level >= 18:
		return 30
	if level >= 14:
		return 25
	if level >= 10:
		return 20
	if level >= 6:
		return 15
	return 10


## Channel Divinity uses: cleric 1 (2 at 6, 3 at 18); paladin 1.
static func channel_divinity_uses(class_id: String, level: int) -> int:
	if class_id == "paladin":
		return 1
	if level >= 18:
		return 3
	if level >= 6:
		return 2
	return 1


## Martial Arts die size by monk level.
static func martial_arts_die(level: int) -> int:
	if level >= 17:
		return 10
	if level >= 11:
		return 8
	if level >= 5:
		return 6
	return 4


## Bardic Inspiration die size by bard level.
static func bardic_die(level: int) -> int:
	if level >= 15:
		return 12
	if level >= 10:
		return 10
	if level >= 5:
		return 8
	return 6


## Song of Rest die size by bard level (0 below 2).
static func song_of_rest_die(level: int) -> int:
	if level < 2:
		return 0
	if level >= 17:
		return 12
	if level >= 13:
		return 10
	if level >= 9:
		return 8
	return 6


## Destroy Undead: the highest challenge rating destroyed (-1 below cleric 5).
static func destroy_undead_cr(level: int) -> float:
	if level >= 17:
		return 4.0
	if level >= 14:
		return 3.0
	if level >= 11:
		return 2.0
	if level >= 8:
		return 1.0
	if level >= 5:
		return 0.5
	return -1.0


## Arcane Recovery / Natural Recovery budget: combined slot levels (half the
## level, rounded up).
static func recovery_budget(level: int) -> int:
	return ceili(level / 2.0)
