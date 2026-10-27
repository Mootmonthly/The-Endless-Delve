class_name DiceFormula
extends RefCounted
## A sum of dice terms, constants and "MOD" (a modifier supplied when rolling),
## as found in imported spell tables: "8d6", "1d8 + MOD", "2d6 + 1d8", "3d4+3".
##
## parse() never returns null; check `valid`. roll() supports critical hits
## (dice doubled), Great Weapon Fighting style rerolls (dice showing <= reroll_max
## are rolled again once) and Empowered Spell (up to `empower` of the lowest dice,
## if below the die's average, are rolled again once).

var source: String = ""
var dice: Array[DiceExpr] = []  # dice terms (count/sides, no modifiers)
var constant: int = 0
var mod_count: int = 0  # how many times "MOD" appears (added with its sign)
var valid: bool = false
var error: String = ""


static func parse(text: String) -> DiceFormula:
	var f := DiceFormula.new()
	f.source = text
	var cleaned := text.strip_edges().to_lower().replace(" ", "")
	if cleaned.is_empty():
		f.error = "empty formula"
		return f
	cleaned = cleaned.replace("-", "+-")
	for raw in cleaned.split("+", false):
		var term := raw
		var negative := term.begins_with("-")
		if negative:
			term = term.substr(1)
		if term == "mod":
			f.mod_count += -1 if negative else 1
			continue
		var expr := DiceExpr.parse(term)
		if not expr.valid:
			f.error = "cannot parse '%s' in '%s'" % [raw, text]
			return f
		if expr.is_constant():
			f.constant += -expr.modifier if negative else expr.modifier
		elif negative:
			f.error = "negative dice are not supported in '%s'" % text
			return f
		else:
			f.dice.append(expr)
	f.valid = true
	return f


func is_valid_formula() -> bool:
	return valid


## Total dice count (non-critical).
func dice_count() -> int:
	var n := 0
	for d in dice:
		n += d.count
	return n


## Rolls the formula: dice (doubled on a critical) + constant + mod * mod_count.
## Returns {"total": int, "rolls": Array[int]} (rolls after rerolls).
func roll(rng: Rng, mod: int = 0, critical: bool = false, reroll_max: int = 0, empower: int = 0) -> Dictionary:
	var rolls: Array[int] = []
	var sides: Array[int] = []
	if not valid:
		push_error("DiceFormula.roll on invalid formula: %s" % error)
		return {"total": 0, "rolls": rolls}
	for d in dice:
		var n := d.count * 2 if critical else d.count
		for _i in range(n):
			var v := rng.next_int(1, d.sides)
			if reroll_max > 0 and v <= reroll_max:
				v = rng.next_int(1, d.sides)
			rolls.append(v)
			sides.append(d.sides)
	if empower > 0:
		# Reroll the lowest dice that rolled below their average, lowest first (ties: order).
		var order: Array[int] = []
		for i in range(rolls.size()):
			order.append(i)
		order.sort_custom(func(a: int, b: int) -> bool:
			if rolls[a] != rolls[b]:
				return rolls[a] < rolls[b]
			return a < b)
		var left := empower
		for i in order:
			if left <= 0:
				break
			if float(rolls[i]) < (sides[i] + 1) / 2.0:
				rolls[i] = rng.next_int(1, sides[i])
				left -= 1
	var total := constant + mod * mod_count
	for v in rolls:
		total += v
	return {"total": total, "rolls": rolls}


## Formula text with `extra` copies of per added ("8d6" + "1d6" x 2 -> "8d6+2d6").
static func plus(base: String, per: String, times: int) -> String:
	if per.is_empty() or times <= 0:
		return base
	var out := base
	for _i in range(times):
		out += "+" + per
	return out


## Round C (Overchannel): the formula with every die at its maximum, as text
## ("8d6+3" -> "51", "1d8+MOD" -> "8+MOD"); the text itself when invalid.
static func maximized(text: String) -> String:
	var f := DiceFormula.parse(text)
	if not f.valid:
		return text
	var total := f.constant
	for d in f.dice:
		total += d.count * d.sides
	var out := str(total)
	for _i in range(absi(f.mod_count)):
		out += "+MOD" if f.mod_count > 0 else "-MOD"
	return out
