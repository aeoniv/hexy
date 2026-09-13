class_name SenseAcoustic
extends Sense

## MACHINE 3 -- Lake. The room's own sound, with speech taken out of it. A
## loud room that is loud because someone is talking is not atmosphere, it is
## a conversation, and the human family is the one that should hear it.

const QUIET_DB: float = 30.0
const LOUD_DB: float = 70.0
const SPEECH_DUCK: float = 0.35

var _db: float = 0.0
var _speech: bool = false


func _init() -> void:
	super(Sense.MACHINE, 3, "acoustic")
	_needs_consent = true
	_needs = "ixvoice"


func _has(t: Dictionary) -> bool:
	return t.has("mic_db")


func _read(_now_ms: int, t: Dictionary) -> float:
	_db = Sense.num(t, "mic_db", 0.0)
	_speech = Sense.flag(t, "speech", false)
	var loud: float = Sense.ramp(_db, QUIET_DB, LOUD_DB)
	return loud * (SPEECH_DUCK if _speech else 1.0)


func _high() -> String:
	if _speech:
		return "room at %d db, a voice in it" % int(round(_db))
	return "room at %d db, no voice" % int(round(_db))


func _low() -> String:
	return "room quiet, %d db" % int(round(_db))


func _forget() -> void:
	_db = 0.0
	_speech = false
