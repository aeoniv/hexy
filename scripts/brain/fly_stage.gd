class_name FlyStage
extends RefCounted

## THE FIRST-PERSON STAGE (N3). The one place the organism says what part of
## its own approach it is standing in, and the only writer of `Body.stage`.
##
## THIS IS NOT THE JOURNEY. Journey/Gauge read the WALK -- the figures the body
## has stood on -- and hand back a chapter index for a reading layer. That rule
## needs the store's path, which the brain does not and must not see. What the
## brain DOES have is its own homeostat: six line fills, the giant fiber's
## startle, and the one attested outside source it has ever had, a conspecific
## pheromone contact. Those three are enough for a first-person stage, so the
## machine lives here, under scripts/brain, preloading nothing but itself.
##
## THE RULE, WHOLE:
##   ""         nothing pulling. The resting stage, and the one it returns to.
##   approach   an attested pheromone contact arrived: something is being
##              reached for. Entered from "" and re-entered on every contact.
##   refusal    the giant fiber fired while approaching: the reach pulled back.
##   reward     the connection line crossed open while approaching, or a
##              positive dopaminergic event landed: the reach landed.
##   -> ""      HOLD_MS with no new contact after refusal or reward, and
##              APPROACH_MS of an approach nothing ever answered.
##
## Deterministic and clockless: every transition is driven by a millisecond
## stamp the caller hands in.

const NONE: String = ""
const APPROACH: String = "approach"
const REFUSAL: String = "refusal"
const REWARD: String = "reward"

## How long refusal and reward stand before the organism is ordinary again.
const HOLD_MS: int = 90 * 1000
## An approach nobody answered gives up after this.
const APPROACH_MS: int = 10 * 60 * 1000
## The connection fill that counts as the reach having landed. The homeostat's
## own OPEN_THRESHOLD; a line that is open is a line that got what it wanted.
const OPEN_THRESHOLD: float = 0.5

var _stage: String = NONE
var _since_ms: int = -1
var _last_contact_ms: int = -1
## Latched by note_startle / note_reward between steps, spent on the next step.
var _startled: bool = false
var _rewarded: bool = false


func stage() -> String:
	return _stage


func since_ms() -> int:
	return _since_ms


## An attested conspecific contact. The only thing that starts an approach.
func note_contact(now_ms: int) -> void:
	_last_contact_ms = now_ms
	if _stage == NONE:
		_enter(APPROACH, now_ms)


## The giant fiber fired.
func note_startle() -> void:
	_startled = true


## A dopaminergic event with positive valence landed.
func note_reward(valence: float) -> void:
	if valence > 0.0:
		_rewarded = true


## ONE BEAT. `connection` is the homeostat's LINE_CONNECTION fill.
func step(now_ms: int, connection: float) -> String:
	if _since_ms < 0:
		_since_ms = now_ms
	var startled: bool = _startled
	var rewarded: bool = _rewarded
	_startled = false
	_rewarded = false
	match _stage:
		APPROACH:
			if startled:
				_enter(REFUSAL, now_ms)
			elif rewarded or connection >= OPEN_THRESHOLD:
				_enter(REWARD, now_ms)
			elif now_ms - _since_ms >= APPROACH_MS:
				_enter(NONE, now_ms)
		REFUSAL, REWARD:
			if now_ms - maxi(_since_ms, _last_contact_ms) >= HOLD_MS:
				_enter(NONE, now_ms)
	return _stage


func _enter(next: String, now_ms: int) -> void:
	if next == _stage:
		_since_ms = now_ms
		return
	_stage = next
	_since_ms = now_ms


## Back to the resting stage, remembering nothing. For a fresh organism.
func reset() -> void:
	_stage = NONE
	_since_ms = -1
	_last_contact_ms = -1
	_startled = false
	_rewarded = false
