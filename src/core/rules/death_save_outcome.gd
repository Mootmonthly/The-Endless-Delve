class_name DeathSaveOutcome
extends RefCounted
## Result of one death saving throw.

var rolled: bool = false  # false when no save was needed (conscious, stable or dead)
var natural: int = 0
var success: bool = false
var successes: int = 0  # counters after this save
var failures: int = 0
var became_stable: bool = false
var regained_consciousness: bool = false  # natural 20: back up with 1 hp
var died: bool = false
