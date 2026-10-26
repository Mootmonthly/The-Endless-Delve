class_name Rng
extends RefCounted
## Seeded, deterministic random source. This is the ONLY source of randomness
## allowed in src/core: every function that needs dice takes an Rng argument.
## The same seed always produces the same sequence (on the same Godot version).
##
## Ranges must fit in 32 bits (Godot's RandomNumberGenerator limitation).

const _FLOAT_BITS := 0x3FFFFFFF  # 2^30 - 1
const _FLOAT_SCALE := 1073741824.0  # 2^30

var seed_value: int = 0
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()


func _init(initial_seed: int) -> void:
	seed_value = initial_seed
	_rng.seed = initial_seed


## Uniform integer in [lo, hi], both inclusive.
func next_int(lo: int, hi: int) -> int:
	if hi < lo:
		push_error("Rng.next_int: hi (%d) < lo (%d)" % [hi, lo])
		return lo
	return _rng.randi_range(lo, hi)


## Uniform float in [0.0, 1.0).
func next_float() -> float:
	return float(_rng.randi_range(0, _FLOAT_BITS)) / _FLOAT_SCALE


## Derives an independent child stream. The child seed depends only on this
## Rng's seed_value and stream_id (not on how many numbers were drawn), so
## e.g. fork(floor_number) is stable no matter what happened before.
func fork(stream_id: int) -> Rng:
	var mixer := RandomNumberGenerator.new()
	mixer.seed = seed_value
	var a: int = mixer.randi_range(0, _FLOAT_BITS)
	var b: int = mixer.randi_range(0, _FLOAT_BITS)
	mixer.seed = ((a << 30) | b) ^ stream_id
	var c: int = mixer.randi_range(0, _FLOAT_BITS)
	var d: int = mixer.randi_range(0, _FLOAT_BITS)
	return Rng.new((c << 30) | d)


## Opaque generator state; pass to set_state() to replay from this point.
func state() -> int:
	return _rng.state


func set_state(s: int) -> void:
	_rng.state = s
