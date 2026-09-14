extends SceneTree

## BROKER SMOKE — scripts/core/broker.gd. The one door onto the camera, the
## microphone and the loudspeaker, driven with no camera, no microphone and
## no loudspeaker.
## Prints === ALL PASS === or fails.

var _fails := 0
var _checks := 0
## Every Broker this suite builds. They are Nodes and never enter a tree, so
## the suite frees them itself at the end rather than leaving Godot to report
## a pile of leaked instances over a green run.
var _built: Array[Broker] = []


func _check(cond: bool, what: String) -> void:
	_checks += 1
	if cond:
		print("PASS ", what)
	else:
		printerr("FAIL ", what)
		_fails += 1


func _fresh() -> Broker:
	var b := Broker.new()
	b.autosave = false
	_built.append(b)
	return b


func _initialize() -> void:
	_the_policy()
	_take_and_release()
	_exclusion()
	_the_steal()
	_equals_refuse()
	_written_down()
	_mode_exit()
	_seize()
	_persistence_is_counters_only()

	for b in _built:
		b.free()

	print("checks: ", _checks)
	if _fails == 0:
		print("=== ALL PASS ===")
	quit(0 if _fails == 0 else 1)


func _the_policy() -> void:
	_check(Broker.priority_of(Broker.HOLDER_RIG) > Broker.priority_of(Broker.HOLDER_FIND),
		"rig strictly outranks find")
	_check(Broker.priority_of(Broker.HOLDER_FIND) == Broker.priority_of(Broker.HOLDER_LOOK),
		"find and look are equal")
	_check(Broker.priority_of("nobody_decided_this_name") == -1,
		"an unknown holder is the lowest, never the highest")
	_check(Broker.may_take("", "look") == true, "free is always takeable")
	_check(Broker.may_take("look", "look") == true, "the same holder re-asking is always yes")
	_check(Broker.may_take("face", "find") == true, "find outranks face")
	_check(Broker.may_take("find", "look") == false, "look may not take from an equal, find")


func _take_and_release() -> void:
	var b := _fresh()
	_check(b.can_take(Broker.BACK_LENS, Broker.HOLDER_FIND), "a free lens can be taken")
	_check(b.take(Broker.BACK_LENS, Broker.HOLDER_FIND) == true, "find takes the back lens")
	_check(b.holder_of(Broker.BACK_LENS) == Broker.HOLDER_FIND, "holder_of reports find")
	_check(b.held_now() == 1, "one device held")
	_check(b.takes() == 1 and b.releases() == 0, "one take, zero releases")
	b.release(Broker.BACK_LENS, Broker.HOLDER_FIND)
	_check(b.holder_of(Broker.BACK_LENS) == "", "release frees the device")
	_check(b.releases() == 1, "the release counter moved")
	b.release(Broker.BACK_LENS, Broker.HOLDER_FIND)
	_check(b.releases() == 1, "a release by a non-holder (now free) is a no-op")


func _exclusion() -> void:
	var b := _fresh()
	b.take(Broker.MIC, Broker.HOLDER_EAR)
	_check(b.can_take(Broker.SPEAKER, Broker.HOLDER_MOUTH) == false,
		"the loudspeaker cannot open beside the mic held by an equal-ranked holder")
	_check(b.why_not(Broker.SPEAKER, Broker.HOLDER_MOUTH) != "",
		"why_not() gives a reason for the refusal")
	# The chirp clock outranks ear/mouth and may hold both at once.
	_check(b.take(Broker.MIC, Broker.HOLDER_CHIRP) == true,
		"chirp preempts the ear for the mic")
	_check(b.take(Broker.SPEAKER, Broker.HOLDER_CHIRP) == true,
		"chirp may also take the speaker, its own excluded pair")


func _the_steal() -> void:
	var b := _fresh()
	b.take(Broker.FRONT_LENS, Broker.HOLDER_FACE)
	# GDScript lambdas capture locals BY VALUE, not by reference, so a box
	# (single-element array) is used to observe the signal from outside it.
	var box := [false, false]
	b.stolen.connect(func(_r: String, _loser: String, _w: String) -> void:
		box[0] = true
		# The hold is erased before 'stolen' fires (see [take]), so at this
		# moment the resource is neither still the loser's nor yet the
		# winner's — the winner is only recorded once this handler returns.
		box[1] = b.holder_of(Broker.FRONT_LENS) != Broker.HOLDER_FIND)
	_check(b.take(Broker.FRONT_LENS, Broker.HOLDER_FIND) == true,
		"a strictly higher priority take succeeds")
	_check(box[0], "the loser is told via 'stolen'")
	_check(box[1],
		"the loser hears 'stolen' before the winner is recorded")
	_check(b.holder_of(Broker.FRONT_LENS) == Broker.HOLDER_FIND,
		"the winner now holds the device")
	_check(b.steals() == 1, "the steal counter moved")


func _equals_refuse() -> void:
	var b := _fresh()
	b.take(Broker.BACK_LENS, Broker.HOLDER_FIND)
	_check(b.take(Broker.BACK_LENS, Broker.HOLDER_LOOK) == false,
		"an equal-priority take is a refusal, not a steal")
	_check(b.holder_of(Broker.BACK_LENS) == Broker.HOLDER_FIND,
		"the original holder keeps the device")
	_check(b.steals() == 0, "no steal was recorded for the refusal")


func _written_down() -> void:
	var b := _fresh()
	var lines: Array = []
	b.noted.connect(func(line: String) -> void: lines.append(line))
	b.take(Broker.MIC, Broker.HOLDER_EAR)
	b.release(Broker.MIC, Broker.HOLDER_EAR)
	_check(lines.size() == 2, "every take and release is written down")
	_check(lines[0] == "mic -> ear", "the take line reads as a person would say it")
	_check(lines[1] == "mic -> free", "the release line reads as a person would say it")


func _mode_exit() -> void:
	var b := _fresh()
	# BACK_LENS is the only mode-tagged hold; SPEAKER is picked as the
	# ambient one deliberately because it pairs with MIC, which nothing here
	# touches — so there is no exclusion conflict to entangle the two checks.
	b.take(Broker.BACK_LENS, Broker.HOLDER_FIND, "HUNT")
	b.take(Broker.SPEAKER, Broker.HOLDER_MOUTH, "")
	var gone := b.release_mode("HUNT")
	_check(gone.size() == 1, "leaving a mode releases everything tagged with it")
	_check(b.holder_of(Broker.BACK_LENS) == "", "the mode's lens hold is gone")
	_check(b.holder_of(Broker.SPEAKER) == Broker.HOLDER_MOUTH,
		"an ambient (no-mode) hold survives a mode exit")
	_check(b.release_mode("") == [], "an empty mode releases nothing")


func _seize() -> void:
	var b := _fresh()
	b.take(Broker.MIC, Broker.HOLDER_EAR)
	_check(b.take(Broker.MIC, Broker.HOLDER_RIG) == true,
		"the rig may take a device held by anything")
	_check(b.can_take(Broker.SPEAKER, Broker.HOLDER_MOUTH) == false,
		"once the rig holds anything, nobody else may take anything")
	_check(b.why_not(Broker.SPEAKER, Broker.HOLDER_MOUTH).find("rig") != -1,
		"why_not() names the rig as the reason")


## The lifetime counters persist across instances; the live hold table does
## not (a fresh boot must never believe yesterday's camera is still open).
func _persistence_is_counters_only() -> void:
	var path := "user://broker_stats.json"
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	var b1 := Broker.new()
	_built.append(b1)
	b1.autosave = true
	b1.take(Broker.MIC, Broker.HOLDER_EAR)
	b1.save_stats()
	_check(FileAccess.file_exists(path), "save_stats() writes to user://")
	var b2 := Broker.new()
	_built.append(b2)
	_check(b2.takes() == b1.takes(), "a fresh Broker loads the persisted take counter")
	_check(b2.held_now() == 0,
		"a fresh Broker never inherits the previous instance's live holds")
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
