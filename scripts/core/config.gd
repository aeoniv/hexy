class_name HexyConfig
extends Node

## THE ONE DRAWER EVERY TUNABLE LIVES IN.
##
## Before this file a number that mattered -- how long a breath of stillness
## has to be held, how hard Qwen hears the cube, how often the sixteen senses
## are read -- was a `const` in whichever file happened to need it first, and
## changing it meant an edit, a rebuild and a reinstall. HexyConfig is the
## registry those constants now report to: every one of them keeps its const as
## its DEFAULT, and the live value is read from here.
##
## THE SCHEMA IS THE TRUTH. A key that is not in [method schema] does not
## exist: [method set_value] clamps to the row's min/max or snaps an enum to
## its options, so no caller can put a number into this object that the app
## cannot survive. Every write emits [signal changed] and bumps
## [method revision], and the whole drawer round-trips through JSON so the
## visualiser in tools/ can hand a person the same registry the phone holds.
##
## TWO WAYS TO GET ONE. In the app it is an autoload named "Config" and
## [method instance] hands back that node. In a headless test there is no
## autoload and no tree, so [method instance] LAZILY BUILDS one and remembers
## it in a static. [method peek] is the third way and the careful one: it
## returns the existing instance or null and NEVER builds, which is how Pacing
## and Senses stay exactly at their consts in tests that never ask for a
## config.

## One key just changed. `value` is the CLAMPED value, never the raw one.
signal changed(key: String, value: Variant)

## Where the drawer is written. ConfigFile, so a person may open it in a text
## editor on desktop and read what their own phone decided.
const SAVE_PATH: String = "user://hexy.cfg"

## Milliseconds of quiet after the last write before the drawer is persisted.
## A slider dragged across its range is one save, not two hundred.
const SAVE_DEBOUNCE_MS: int = 400

## The lazily-built or autoload-registered singleton.
static var _instance: HexyConfig = null

## key -> clamped value, holding ONLY keys that differ from their default is
## not the rule: every key is materialised on build, so a reader never has to
## ask the schema what a missing key would have been.
var _values: Dictionary = {}

## Bumped on every accepted write. A reader that cannot afford a signal
## connection -- a RefCounted like Pacing, which a connected signal would keep
## alive forever -- caches this integer and re-pulls only when it moves.
var _revision: int = 0

## Set false by a test that does not want a file written under user://.
var autosave: bool = true

var _save_pending: bool = false
var _rows: Array[Dictionary] = []
var _by_key: Dictionary = {}


# --- the schema --------------------------------------------------------------

## EVERY TUNABLE IN THE APP, in the order a person should meet them. `min`,
## `max` and `step` are meaningless for bool and enum rows and are carried as
## zeroes there so every row has the same shape.
static func _schema_rows() -> Array[Dictionary]:
	return [
		# -- pacing: the two fires and the cube they move ---------------------
		{"key": "pacing.civil_fire_s", "group": "pacing", "type": "float",
			"min": 0.1, "max": 30.0, "step": 0.1, "default": 2.5, "options": [],
			"doc": "Seconds of stillness dwell before the civil fire turns a line."},
		{"key": "pacing.rearm_s", "group": "pacing", "type": "float",
			"min": 0.0, "max": 30.0, "step": 0.1, "default": 2.0, "options": [],
			"doc": "Seconds since the last flip before the civil fire may turn another."},
		{"key": "pacing.mutation_cooldown_s", "group": "pacing", "type": "float",
			"min": 0.0, "max": 60.0, "step": 0.1, "default": 3.5, "options": [],
			"doc": "Seconds since the last flip before the martial fire may turn another."},
		{"key": "pacing.martial_threshold", "group": "pacing", "type": "float",
			"min": 0.0, "max": 1.0, "step": 0.01, "default": 0.85, "options": [],
			"doc": "Excitation at which the martial fire takes over from the civil."},
		{"key": "pacing.inject_lockout_s", "group": "pacing", "type": "float",
			"min": 0.0, "max": 30.0, "step": 0.1, "default": 2.5, "options": [],
			"doc": "Seconds both fires are held after a cast lands, so the figure may settle."},
		{"key": "pacing.civil_t", "group": "pacing", "type": "float",
			"min": 0.0, "max": 1.0, "step": 0.01, "default": 0.06, "options": [],
			"doc": "Diffusion time of a civil step: a held breath barely moves the mass."},
		{"key": "pacing.martial_t", "group": "pacing", "type": "float",
			"min": 0.0, "max": 1.0, "step": 0.01, "default": 0.90, "options": [],
			"doc": "Diffusion time of a martial step: a surge throws the mass wide."},
		{"key": "pacing.beta", "group": "pacing", "type": "float",
			"min": 0.0, "max": 64.0, "step": 0.1, "default": 2.5, "options": [],
			"doc": "How hard the Gibbs reweight listens to the six-line bias. Large is the owner's original rule."},
		{"key": "pacing.anchor", "group": "pacing", "type": "float",
			"min": 0.0, "max": 1.0, "step": 0.01, "default": 0.5, "options": [],
			"doc": "How much of the body's own corner is put back each tick, so the walk stays a walk."},
		{"key": "pacing.journal_max", "group": "pacing", "type": "int",
			"min": 16.0, "max": 65536.0, "step": 1.0, "default": 4096, "options": [],
			"doc": "Ring size of the replay journal. Past this many entries the oldest is dropped."},

		# -- prior: how hard the decode loop hears the cube --------------------
		{"key": "prior.follows_stillness", "group": "prior", "type": "bool",
			"min": 0.0, "max": 0.0, "step": 0.0, "default": false, "options": [],
			"doc": "Let Alchemy drive the prior weight from stillness and tension. Off, prior.weight is used as written."},
		{"key": "prior.max", "group": "prior", "type": "float",
			"min": 0.0, "max": 1.0, "step": 0.01, "default": 0.35, "options": [],
			"doc": "Ceiling on the prior weight, however it is driven."},
		{"key": "prior.weight", "group": "prior", "type": "float",
			"min": 0.0, "max": 1.0, "step": 0.01, "default": 0.0, "options": [],
			"doc": "Manual prior weight, used when prior.follows_stillness is off. Clamped to prior.max."},

		# -- alchemy: how many days of pressure a line needs to turn -----------
		{"key": "alchemy.flip_days", "group": "alchemy", "type": "int",
			"min": 0.0, "max": 30.0, "step": 1.0, "default": 3, "options": [],
			"doc": "Distinct days of same-direction evidence before a line turns. 0 turns a line the beat it is asked to."},
		{"key": "alchemy.mark_threshold", "group": "alchemy", "type": "float",
			"min": 0.0, "max": 1.0, "step": 0.01, "default": 0.6, "options": [],
			"doc": "How far a line's signed mark must lean before the days gate is consulted."},
		{"key": "alchemy.mark_decay_days", "group": "alchemy", "type": "float",
			"min": 0.0, "max": 365.0, "step": 0.5, "default": 14.0, "options": [],
			"doc": "Days for an unfed mark to leak away by 1/e. 0 never forgets."},

		# -- entrain: the ring of samples the user's own clock is guessed from -
		{"key": "entrain.days", "group": "entrain", "type": "int",
			"min": 1.0, "max": 30.0, "step": 1.0, "default": 7, "options": [],
			"doc": "Days of zeitgeber samples kept. Older ones are trimmed off the ring before every estimate."},
		{"key": "entrain.min_samples", "group": "entrain", "type": "int",
			"min": 1.0, "max": 2048.0, "step": 1.0, "default": 48, "options": [],
			"doc": "Samples below which the phase estimate is a guess and confidence stays near the floor."},

		# -- qwen: the shape of an answer -------------------------------------
		{"key": "qwen.max_sentences", "group": "qwen", "type": "int",
			"min": 1.0, "max": 6.0, "step": 1.0, "default": 1, "options": [],
			"doc": "How many sentences of the answer survive when qwen.one_line_only is on."},
		{"key": "qwen.max_tokens", "group": "qwen", "type": "int",
			"min": 8.0, "max": 512.0, "step": 1.0, "default": 80, "options": [],
			"doc": "Token budget handed to the decode loop for one answer."},
		{"key": "qwen.one_line_only", "group": "qwen", "type": "bool",
			"min": 0.0, "max": 0.0, "step": 0.0, "default": true, "options": [],
			"doc": "Cut the answer at a sentence boundary so the glass holds one line."},

		# -- senses: the beat the sixteen are read on --------------------------
		{"key": "senses.period_ms", "group": "senses", "type": "int",
			"min": 100.0, "max": 60000.0, "step": 50.0, "default": 3500, "options": [],
			"doc": "Milliseconds between readings of the sixteen senses."},

		# -- hud: what the glass draws ----------------------------------------
		{"key": "hud.dwell_ring", "group": "hud", "type": "bool",
			"min": 0.0, "max": 0.0, "step": 0.0, "default": true, "options": [],
			"doc": "Draw the ring that fills as stillness dwell banks toward the civil fire."},
		{"key": "hud.line_flash", "group": "hud", "type": "bool",
			"min": 0.0, "max": 0.0, "step": 0.0, "default": true, "options": [],
			"doc": "Flash the line that just turned."},
		{"key": "hud.earth_mode", "group": "hud", "type": "enum",
			"min": 0.0, "max": 0.0, "step": 0.0, "default": "lines",
			"options": ["lines", "stations"],
			"doc": "Draw the earth band as six lines or as the stations of the year."},
		{"key": "hud.bubble_ttl_s", "group": "hud", "type": "float",
			"min": 0.5, "max": 60.0, "step": 0.5, "default": 6.0, "options": [],
			"doc": "Seconds a speech bubble stays on the glass."},
		{"key": "hud.status_mode", "group": "hud", "type": "enum",
			"min": 0.0, "max": 0.0, "step": 0.0, "default": "day",
			"options": ["day", "telemetry"],
			"doc": "The status strip reads as the day's shape or as raw telemetry."},
		{"key": "hud.room_highlight", "group": "hud", "type": "bool",
			"min": 0.0, "max": 0.0, "step": 0.0, "default": true, "options": [],
			"doc": "Highlight the room the body is standing in."},

		# -- mesh: what goes out on the wire ----------------------------------
		{"key": "mesh.q6_on_wire", "group": "mesh", "type": "bool",
			"min": 0.0, "max": 0.0, "step": 0.0, "default": true, "options": [],
			"doc": "Carry the Q6 mass in the bio pulse at all."},
		{"key": "mesh.q6_topk", "group": "mesh", "type": "int",
			"min": 0.0, "max": 64.0, "step": 1.0, "default": 8, "options": [],
			"doc": "Send only the k heaviest corners as (index, mass) pairs. 0 sends the full 64."},

		# -- creature ----------------------------------------------------------
		{"key": "creature.breathe_with_dwell", "group": "creature", "type": "bool",
			"min": 0.0, "max": 0.0, "step": 0.0, "default": true, "options": [],
			"doc": "Let the creature's breath follow the stillness dwell instead of a free clock."},
	]


# --- the singleton -----------------------------------------------------------

## The one config. In the app this is the "Config" autoload; in a headless test
## it is built here on first ask and remembered.
static func instance() -> HexyConfig:
	if _instance == null or not is_instance_valid(_instance):
		_instance = HexyConfig.new()
		_instance.name = "Config"
	return _instance


## The existing config, or null. NEVER builds one -- this is what a reader
## calls when "there is no config" must mean "use my own const".
static func peek() -> HexyConfig:
	if _instance != null and is_instance_valid(_instance):
		return _instance
	return null


## Forget the singleton. A test that wants a clean drawer calls this; the app
## never does.
static func forget() -> void:
	_instance = null


func _init() -> void:
	_rows = _schema_rows()
	for row in _rows:
		_by_key[String(row["key"])] = row
		_values[String(row["key"])] = row["default"]
	_instance = self
	_load()
	changed.connect(_on_changed)


func _enter_tree() -> void:
	# The autoload path: whoever the tree registers wins the static.
	_instance = self


## THE DRAWER'S OWN SUBSCRIBER. A handful of tunables are not merely READ by
## somebody later -- they have to be PUSHED the moment they move, because the
## thing that holds them is native and keeps no config of its own. The prior
## weight is the only one today.
func _on_changed(key: String, _value: Variant) -> void:
	if key.begins_with("prior."):
		push_prior()


## Hand the manual prior weight to the decode loop. Does nothing at all while
## `prior.follows_stillness` is on -- that path is Alchemy's, and two writers
## on one number is how a body ends up listening to neither.
func push_prior() -> bool:
	return Q6Core.apply_manual_prior(
		float(get_value("prior.weight")),
		float(get_value("prior.max")),
		bool(get_value("prior.follows_stillness")))


# --- reading and writing -----------------------------------------------------

## The live value, or the schema default when the key was never written. An
## unknown key answers null, loudly and without inventing a number.
func get_value(key: String) -> Variant:
	if not _by_key.has(key):
		push_warning("HexyConfig: unknown key %s" % key)
		return null
	return _values.get(key, _by_key[key]["default"])


## Write one key. The value is CLAMPED to its row first, so what comes back out
## of [method get_value] is always something the app can survive. A write that
## changes nothing is silent: no signal, no revision, no save.
func set_value(key: String, value: Variant) -> void:
	if not _by_key.has(key):
		push_warning("HexyConfig: unknown key %s" % key)
		return
	var clamped: Variant = _coerce(_by_key[key], value)
	if _values.has(key) and _same(_values[key], clamped):
		return
	_values[key] = clamped
	_revision += 1
	changed.emit(key, clamped)
	_queue_save()


## One key back to its default, or -- with no key -- the whole drawer. Every
## key that actually moves emits its own [signal changed].
func reset(key: String = "") -> void:
	if key != "":
		if _by_key.has(key):
			set_value(key, _by_key[key]["default"])
		return
	for row in _rows:
		set_value(String(row["key"]), row["default"])


## Every row, copied, so a caller building a panel cannot edit the schema by
## accident.
func schema() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for row in _rows:
		out.append(row.duplicate(true))
	return out


## AN ADD-ON'S TUNABLES, JOINED TO THE ONE DRAWER.
##
## `rows` is keyed by NAMESPACED key ("body.min_confidence") and valued by a
## row in the same shape [method schema] uses. A row may leave out anything but
## `default`: the group falls back to the key's own prefix, the type to what
## the default is, and the bounds to zeroes. Once registered a key is
## indistinguishable from a built-in -- it clamps, it persists, it appears on
## the dashboard, and it bumps [method revision].
##
## A key that is already in the drawer is left exactly as it stands: an add-on
## may not move a built-in's bounds, and a re-attach may not undo a person's
## setting. Returns how many keys were actually added.
func register(rows: Dictionary) -> int:
	var added: int = 0
	for k in rows:
		var key: String = String(k)
		if key == "" or _by_key.has(key):
			continue
		if not (rows[k] is Dictionary):
			push_warning("HexyConfig: %s is not a row" % key)
			continue
		var row: Dictionary = _normalise_row(key, rows[k] as Dictionary)
		_rows.append(row)
		_by_key[key] = row
		_values[key] = row["default"]
		added += 1
	if added > 0:
		_revision += 1
		_queue_save()
	return added


## One loose row filled out to the shape every reader expects.
static func _normalise_row(key: String, given: Dictionary) -> Dictionary:
	var row: Dictionary = given.duplicate(true)
	row["key"] = key
	var dotted: PackedStringArray = key.split(".")
	if String(row.get("group", "")) == "":
		row["group"] = dotted[0] if dotted.size() > 1 else key
	var dflt: Variant = row.get("default", 0.0)
	if String(row.get("type", "")) == "":
		if dflt is bool:
			row["type"] = "bool"
		elif dflt is int:
			row["type"] = "int"
		elif dflt is String:
			row["type"] = "enum" if (row.get("options", []) as Array).size() > 0 else "string"
		else:
			row["type"] = "float"
	for field in ["min", "max", "step"]:
		row[field] = float(row.get(field, 0.0))
	if not (row.get("options", null) is Array):
		row["options"] = []
	row["doc"] = String(row.get("doc", ""))
	row["default"] = _coerce(row, dflt)
	return row


## One row by key, copied, or {} when there is no such key.
func row(key: String) -> Dictionary:
	if not _by_key.has(key):
		return {}
	return (_by_key[key] as Dictionary).duplicate(true)


## The groups, in schema order and without repeats.
func groups() -> Array[String]:
	var out: Array[String] = []
	for r in _rows:
		var g: String = String(r["group"])
		if not out.has(g):
			out.append(g)
	return out


## Every key, in schema order.
func keys() -> Array[String]:
	var out: Array[String] = []
	for r in _rows:
		out.append(String(r["key"]))
	return out


## Bumped on every accepted write. A RefCounted reader caches this and re-pulls
## its fields only when it moves, which costs one integer compare a tick and
## keeps no signal connection alive.
func revision() -> int:
	return _revision


# --- export and import -------------------------------------------------------

## The whole drawer as JSON, for the visualiser in tools/ and for a person who
## would rather configure a phone from a text editor.
func to_json() -> String:
	return JSON.stringify(_values, "\t", true)


## Read a drawer back. Unknown keys are ignored rather than fatal -- a file
## written by an older build must still load -- and every known key goes
## through [method set_value], so an import cannot smuggle past the clamps.
## Returns false only when the text is not a JSON object at all.
func from_json(text: String) -> bool:
	var parsed: Variant = JSON.parse_string(text)
	if not (parsed is Dictionary):
		return false
	for k in (parsed as Dictionary):
		var key: String = String(k)
		if _by_key.has(key):
			set_value(key, (parsed as Dictionary)[k])
	return true


# --- persistence -------------------------------------------------------------

func _queue_save() -> void:
	if not autosave or _save_pending:
		return
	_save_pending = true
	var loop: MainLoop = Engine.get_main_loop()
	if loop is SceneTree and (loop as SceneTree).root != null:
		var t: SceneTreeTimer = (loop as SceneTree).create_timer(
			float(SAVE_DEBOUNCE_MS) / 1000.0)
		t.timeout.connect(_flush_save)
	else:
		_flush_save.call_deferred()


func _flush_save() -> void:
	if not _save_pending:
		return
	_save_pending = false
	save()


## Write the drawer now, debounce or no debounce.
func save() -> void:
	var cf := ConfigFile.new()
	for row in _rows:
		var key: String = String(row["key"])
		cf.set_value(String(row["group"]), key, _values[key])
	cf.save(SAVE_PATH)


func _load() -> void:
	var cf := ConfigFile.new()
	if cf.load(SAVE_PATH) != OK:
		return
	for row in _rows:
		var key: String = String(row["key"])
		var g: String = String(row["group"])
		if cf.has_section_key(g, key):
			_values[key] = _coerce(row, cf.get_value(g, key))


# --- clamping ----------------------------------------------------------------

## The one place a raw value becomes a legal one.
static func _coerce(row: Dictionary, value: Variant) -> Variant:
	match String(row["type"]):
		"bool":
			if value is String:
				return String(value).to_lower() in ["1", "true", "yes", "on"]
			return bool(value)
		"int":
			var iv: int = int(round(float(value)))
			## A REGISTERED ROW MAY BE UNBOUNDED: max <= min means "no bound",
			## not "pin everything to zero". No built-in row is shaped that way,
			## so this branch belongs to the add-ons alone.
			if float(row["max"]) <= float(row["min"]):
				return iv
			return clampi(iv, int(row["min"]), int(row["max"]))
		"float":
			if float(row["max"]) <= float(row["min"]):
				return float(value)
			return clampf(float(value), float(row["min"]), float(row["max"]))
		"enum":
			var s: String = String(value)
			var opts: Array = row["options"]
			if opts.has(s):
				return s
			return String(row["default"])
	return value


static func _same(a: Variant, b: Variant) -> bool:
	if a is float and b is float:
		return is_equal_approx(float(a), float(b))
	return a == b
