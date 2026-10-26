class_name DamageOutcome
extends RefCounted
## What happened when a CharacterSheet took damage.

var amount: int = 0  # damage applied (after resistances, before temp hp)
var critical: bool = false
var absorbed_by_temp: int = 0
var hp_lost: int = 0
var hp_after: int = 0
var dropped_to_zero: bool = false  # hit points went from above 0 to 0
var instant_death: bool = false  # massive-damage rule
var death_save_failures_added: int = 0  # damage taken while already at 0 hp
var died: bool = false  # the creature died as a result of this damage
