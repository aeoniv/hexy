class_name Lattice
extends RefCounted

## Debounce for a sense election. A challenger must lead for HOLD consecutive
## ticks before it is allowed to replace the sitting winner. One instance per
## family (one for the machine, one for the human).

const HOLD: int = 2

var winner: int = 0
var candidate: int = -1
var streak: int = 0
var seen: bool = false


func _init(initial_winner: int = 0) -> void:
	winner = initial_winner


## Feed one tick of scores; returns the current winner index.
func push(scores: Array[float]) -> int:
	if scores.is_empty():
		return winner
	var lead: int = 0
	for i in range(1, scores.size()):
		if scores[i] > scores[lead]:
			lead = i
	if not seen:
		seen = true
		winner = lead
		candidate = -1
		streak = 0
		return winner
	if lead == winner:
		candidate = -1
		streak = 0
		return winner
	if lead == candidate:
		streak += 1
	else:
		candidate = lead
		streak = 1
	if streak >= HOLD:
		winner = candidate
		candidate = -1
		streak = 0
	return winner


func reset(initial_winner: int = 0) -> void:
	winner = initial_winner
	candidate = -1
	streak = 0
	seen = false
