class_name Debounce
extends RefCounted

## THE DEBOUNCE FOR A SENSE ELECTION, under its own name at last. A challenger
## must lead for HOLD consecutive ticks before it is allowed to replace the
## sitting winner. One instance per family (one for the machine, one for the
## human).
##
## This is scripts/core/iching/lattice.gd's logic verbatim. `Lattice` stays on
## disk under its old class_name so nothing that still says it breaks; the word
## lattice now belongs to Q6Lattice, which is a lattice in the other sense.

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
