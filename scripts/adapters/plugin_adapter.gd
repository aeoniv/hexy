class_name PluginAdapter
extends RefCounted

## ONE DOOR PER PLUGIN, AND THE DOOR IS THE ONLY THING THAT KNOWS THE NAME.
## Refactor R5.
##
## THE DEFECT THIS CLOSES. Twelve seams each grew their own three lines:
## `Engine.has_singleton`, `Engine.get_singleton`, `Seam.check`. They agreed by
## habit rather than by contract — the same `available()`, the same
## `backend_name()`, the same degrade-to-mock, all written out longhand twelve
## times. A new plugin copied forty lines; a fix to the handshake reached one
## seam and left eleven. Nothing anywhere could stub every sensor at once,
## because there was no one place a sensor came from.
##
## THE ARRANGEMENT. One subclass per Android plugin — seven, exactly the seven
## under `android_plugin/`. Each subclass owns the singleton's NAME and the two
## engine calls that use it, and nothing else. Everything that is the same for
## every plugin — the absent line, the version handshake, the degrade, the two
## honest questions — lives here, once.
##
## WHAT DOES NOT MOVE. The seams keep their own `_android`, their own signal
## connections, their own `available()` and `backend_name()` and every log line
## they ever printed. This is a door, not a facade: it hands back the singleton
## and gets out of the way. Behaviour is byte-identical on both sides of it.
##
## THE RESERVED SEAM. Adapters emit nothing themselves; the seams above them
## still emit the signals they always did. That signal surface is what a future
## 64-state oracle would subscribe to instead of the creature. This milestone
## owes it a uniform door and nothing more — no oracle, no stub, no `oracle/`.
##
## NOT MEMOIZED, ON PURPOSE. Every seam above already guards with
## `if _android != null: return`. A second cache here would answer "attached"
## for a seam that bailed after the handshake for its own reasons (a missing
## signal, say) — `world_sense.gd` does exactly that — and the next `attach()`
## would skip the log line the first one earned. So [attach] asks the engine
## every time it is called, and the seam stays the one that remembers.

const Seam = preload("res://scripts/seam.gd")

## The version string this seam was written against, as `<plugin>/<n>`. Empty
## means "do not handshake" — the one honest case is a plain fact read
## (`DeviceFacts.plugin_ram`) that connects no signal and calls no new method.
var needs := ""
## The word `seam.gd` prints in front of a stale-plugin line: `body`, `pose`,
## `lens`, `geo`, `voice`, `chirp`, `pulse`, `cam`, `mesh`, `vision`, `mnn`.
var tag := ""
## What [backend_name] says when a plugin answered, and when none did. Both are
## given by the seam, because one plugin wears different names in different
## lanes: `IxBody` is `mediapipe` to the face and `efficientdet-lite0` to the
## finder, and a name that lied about which would be worse than no name.
var real := ""
var mock := ""

var _node: Object = null


func _init(p_needs: String = "", p_tag: String = "", p_real: String = "",
		p_mock: String = "") -> void:
	needs = p_needs
	tag = p_tag
	real = p_real
	mock = p_mock


# ── the three a subclass answers ─────────────────────────────────────────────


## The JNI singleton's name. The ONLY place in the app that spells it.
func singleton_name() -> String:
	return ""


## Whether the engine has it at all. False on every desktop.
func present() -> bool:
	return false


## The singleton itself, unchecked. Never called except through [attach].
func fetch() -> Object:
	return null


# ── the four every adapter shares ────────────────────────────────────────────


## THE WHOLE OF THE OLD THREE LINES. Returns the singleton, or null and the
## reason it is null. `absent_line` is printed only when there is no plugin at
## all — a stale one is `seam.gd`'s to shout about, in its own words.
func attach(absent_line: String = "") -> Object:
	_node = null
	if not present():
		if absent_line != "":
			print(absent_line)
		return null
	var got: Object = fetch()
	# THE VERSION HANDSHAKE, before a single signal is connected. A stale aar
	# under a fresh script is the silent failure `scripts/seam.gd` exists for;
	# on a mismatch the seam above runs its mock and says so once, loudly.
	if needs != "" and not Seam.check(got, needs, tag):
		return null
	_node = got
	return _node


## The singleton this adapter last handed out, or null.
func node() -> Object:
	return _node


## Whether a plugin is present at all. Not the same as a working one.
func available() -> bool:
	return _node != null


## The real name when a plugin answered, the mock name otherwise. A mocked
## reading is never dressed as a measured one.
func backend_name() -> String:
	return real if available() else mock


## Forget the singleton. For a seam that took the plugin and then declined it
## for its own reasons, so the next `attach()` starts from the engine again.
func detach() -> void:
	_node = null
