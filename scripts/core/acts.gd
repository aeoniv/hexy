class_name HexyActs
extends Node

## W10a -- THE OUT DOORS, AND THE ONLY THING THAT OPENS THEM.
##
## `HexySenses` is the in half of the bus: a door is read and a Sense goes
## out. This is the mirror image. One subscription to "/act", four doors, and
## nothing else: a message arrives, one door does one thing, and no state is
## kept about it. Nothing here decides WHEN to act -- a producer publishes an
## Act and this file performs it, the same way nothing in HexySenses decides
## what a lux reading means.
##
## THE FOUR DOORS (HexyMsg.ACT_DOORS, and no fifth is representable):
##   speaker -- WING SONG. A short generated tone, played through an
##              AudioStreamGenerator built here. The loudspeaker is a
##              CONTENDED device, so it is acquired from the broker per act
##              and given straight back; an act that cannot get the door is
##              refused, loudly, and nothing is played.
##   haptic  -- `Input.vibrate_handheld`, in milliseconds. Base engine API;
##              silent on a desktop, no door to take.
##   screen  -- NO-OP, on purpose. The creature IS the screen: the glass draws
##              itself off "/body" and "/phase", and a second writer telling
##              it what to show is exactly what the bus removed.
##   radio   -- NO-OP, on purpose. `Wmn` owns the mesh and broadcasts its own
##              body; an Act that wrote the wire would be a second sender.
##
## No timers, no queue, no retry. An act that arrives while the speaker is
## held is dropped, not deferred: a song a second late is a different song.

const ACT_TOPIC := "/act"

## Who this file asks the broker as, and for which door. The speaker is the
## only contended device an act opens today -- `chirp` is the four-law table's
## own name for "a measurement that sharing destroys", which is what a tone
## with a shape is.
const HOLDER_CHIRP := "chirp"
const DOOR_SPEAKER := "speaker"

## THE SONG. Short by contract: a wing song is a greeting, not a ringtone.
const SONG_HZ: float = 620.0
const SONG_SECONDS: float = 0.18
const SONG_GAIN: float = 0.22
const MIX_RATE: float = 22050.0

## The longest buzz a single Act may ask for. A haptic door with no ceiling is
## a door that can be held down.
const HAPTIC_MAX_MS: int = 250

var topic: HexyTopic = null
var broker: Node = null

var _sub: int = -1
var _player: AudioStreamPlayer = null

## What happened, for the panel and for a test. Counters only -- this file
## keeps no opinion about any door's state, only a tally of what it did.
var performed: int = 0
var refused: int = 0
var songs: int = 0
var buzzes: int = 0
var last_door: String = ""
var last_refusal: String = ""


## The bus first, the broker if one is wired. With no broker every door is
## open, which is what a headless test that does not care about contention
## gets.
func bind(p_topic: HexyTopic, p_broker: Node = null) -> void:
	detach()
	topic = p_topic
	broker = p_broker
	if topic != null:
		_sub = int(topic.subscribe(ACT_TOPIC, Callable(self, "_on_act")))


func detach() -> void:
	if topic != null and _sub >= 0:
		topic.unsubscribe(_sub)
	_sub = -1
	topic = null


func _exit_tree() -> void:
	## A hold that outlives the node is Law 3's orphan. Give the door back
	## even if an act somehow left holding it.
	if broker != null:
		broker.call("release_door", DOOR_SPEAKER, HOLDER_CHIRP)
	detach()


## ONE ACT, ONE DOOR. Returns whether the door actually did something; false
## for a refusal (bad door, or a device somebody else has) and for the two
## doors that are no-ops by design.
func perform(msg: Dictionary) -> bool:
	return _on_act(msg)


func _on_act(msg: Dictionary) -> bool:
	if typeof(msg) != TYPE_DICTIONARY or String(msg.get("kind", "")) != HexyMsg.KIND_ACT:
		return _refuse("not an act")
	var door: String = String(msg.get("door", ""))
	if not HexyMsg.ACT_DOORS.has(door):
		return _refuse("no such door '%s'" % door)
	last_door = door
	## ONE LINE PER ACT, for a device pass to grep out of logcat.
	print("hexy.act %s" % door)
	match door:
		"speaker":
			return _wing_song(msg)
		"haptic":
			return _buzz(msg)
		"screen":
			## THE CREATURE IS THE SCREEN. Counted, so a producer can see its
			## act arrived, and deliberately doing nothing.
			performed += 1
			return false
		"radio":
			## WMN OWNS THE WIRE. Same: arrived, deliberately nothing.
			performed += 1
			return false
	return _refuse("unreachable door '%s'" % door)


func _refuse(why: String) -> bool:
	refused += 1
	last_refusal = why
	push_warning("HexyActs: refused -- %s" % why)
	return false


## -- speaker: the wing song --------------------------------------------------

## THE DOOR IS TAKEN PER ACT AND GIVEN BACK IN THE SAME CALL. A song is a
## fifth of a second; holding the loudspeaker between songs would lock out
## every add-on for the sake of silence.
func _wing_song(msg: Dictionary) -> bool:
	if broker != null and not bool(broker.call("acquire", DOOR_SPEAKER, HOLDER_CHIRP)):
		return _refuse("the speaker is held by '%s'" % String(broker.call("holder", DOOR_SPEAKER)))
	var hz: float = SONG_HZ
	var v: Variant = msg.get("value", null)
	if typeof(v) in [TYPE_INT, TYPE_FLOAT] and float(v) > 0.0:
		hz = clampf(float(v), 60.0, 8000.0)
	elif v is Dictionary:
		hz = clampf(float((v as Dictionary).get("hz", SONG_HZ)), 60.0, 8000.0)
	_play_tone(hz)
	songs += 1
	performed += 1
	if broker != null:
		broker.call("release_door", DOOR_SPEAKER, HOLDER_CHIRP)
	return true


## A SINE, PUSHED BY HAND. Headless and on a machine with no audio device the
## playback object never appears; the song is then simply not heard, and that
## is not a failure -- the door was still opened, counted and released.
func _play_tone(hz: float) -> void:
	if _player == null:
		_player = AudioStreamPlayer.new()
		_player.name = "WingSong"
		var gen := AudioStreamGenerator.new()
		gen.mix_rate = MIX_RATE
		gen.buffer_length = SONG_SECONDS + 0.05
		_player.stream = gen
		add_child(_player)
	_player.play()
	var pb: AudioStreamGeneratorPlayback = _player.get_stream_playback() as AudioStreamGeneratorPlayback
	if pb == null:
		return
	var frames: int = mini(int(MIX_RATE * SONG_SECONDS), pb.get_frames_available())
	var step: float = TAU * hz / MIX_RATE
	for i in frames:
		## A short attack/decay envelope, so the tone does not click on or off.
		var t: float = float(i) / maxf(1.0, float(frames))
		var env: float = sin(PI * t)
		var s: float = sin(step * float(i)) * SONG_GAIN * env
		pb.push_frame(Vector2(s, s))


## -- haptic ------------------------------------------------------------------

func _buzz(msg: Dictionary) -> bool:
	var ms: int = 0
	var v: Variant = msg.get("value", null)
	if typeof(v) in [TYPE_INT, TYPE_FLOAT]:
		ms = int(v)
	elif v is Dictionary:
		ms = int((v as Dictionary).get("ms", 0))
	ms = clampi(ms, 0, HAPTIC_MAX_MS)
	if ms <= 0:
		return _refuse("a haptic act with no duration")
	Input.vibrate_handheld(ms)
	buzzes += 1
	performed += 1
	return true
