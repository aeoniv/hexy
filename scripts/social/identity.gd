extends RefCounted
## Who this install is, to everyone else on the mesh: a display name and a hue.
##
## Stable per install, because a visitor that changes colour every launch is a
## stranger every launch. The defaults are derived from the fabric id, so two
## installs differ without anyone naming themselves; the config file exists so
## a person can overrule that later, and HEXY_NAME still wins for the
## two-instances-on-one-desktop proof.

const CONFIG_PATH := "user://identity.cfg"
const SECTION := "identity"

var display_name := "hexy"
## 0..1 around the colour wheel.
var hue := 0.45


## Colour a Hexy body is drawn in for a given hue. One function so the local
## Hexy and a remote visitor agree on what "hue 0.7" looks like.
static func body_color(h: float) -> Color:
	return Color.from_hsv(fposmod(h, 1.0), 0.52, 0.82)


static func edge_color(h: float) -> Color:
	return Color.from_hsv(fposmod(h, 1.0), 0.62, 0.55)


## How many hues the wheel is cut into. Quantized on purpose: a raw hash gives
## two peers 0.345 and 0.376 and they are both "green" to a person across the
## room. Twelve buckets are 30 degrees apart — always tellable, and a repeat
## after twelve neighbours is a fair price.
const HUE_STEPS := 12

## Deterministic hue from an id string: same install, same colour, forever.
static func hue_from_id(id: String) -> float:
	return float(absi(id.hash()) % HUE_STEPS) / float(HUE_STEPS)


## ── ONE PEER, ONE NAME (field, m9) ──────────────────────────────────────────
##
## The same phone appeared under three names on one screen: `hexy-8aad` on the
## door and on the radar, `dc631d7c` in the workshop's PEERS section, and `9OT0`
## in its RADIO section. Three id SPACES, all of them real — the minted display
## name, the fabric id, and the transport's own peer handle — and nothing on the
## glass said they were one person. A panel that lists a peer twice under two
## strings is a panel that cannot be used to answer "is my friend connected".
##
## So there is one name a person reads, it is the `hexy-xxxx` one, and this is
## where it is minted. It was already the first line of [load_or_mint]; it is a
## function now because four places need to say it and only one of them can own
## the spelling. The raw id is not deleted — it is what a log and a bug report
## are written in — it is put in parentheses in the ONE row that is an
## instrument reading (workshop PEERS) and nowhere else.
const NAME_PREFIX := "hexy-"
const NAME_CHARS := 4


## The name a stranger's id earns before they have told us one. Deterministic,
## like [hue_from_id]: the same install is the same name on every phone that
## sees it, with no beacon needed and nothing invented.
static func short_name(fabric_id: String) -> String:
	if fabric_id == "":
		return NAME_PREFIX + "?"
	return NAME_PREFIX + fabric_id.substr(0, NAME_CHARS)


## ── THE ID THAT OUTLIVES THE LAUNCH (field, m11) ────────────────────────────
##
## `MeshFabric.fabric_id` was minted from `randi()` at every start, while this
## file remembered the name minted from the FIRST launch's id forever. So a
## phone said `hexy-205c` in presence and `hexy-36a2` on the link, both minted
## by `short_name`, both correct, off two different ids — the m11 fault, one
## layer under the transport beacon that first showed it.
##
## The identity file is where an install's identity lives, so the fabric id
## lives here too: minted once, kept, and handed to the fabric before it starts.
## One id, therefore one name, on every surface and across every launch.
const FABRIC_KEY := "fabric"


static func stable_fabric_id() -> String:
	var cfg := ConfigFile.new()
	var loaded := cfg.load(CONFIG_PATH) == OK
	var stored := String(cfg.get_value(SECTION, FABRIC_KEY, "")) if loaded else ""
	if stored != "":
		return stored
	var minted := "%08x%08x" % [randi(), randi()]
	cfg.set_value(SECTION, FABRIC_KEY, minted)
	cfg.save(CONFIG_PATH)
	return minted


## Whether a stored name is one this code minted rather than one a person chose.
## A minted name is only ever as good as the id it came from, and an id that has
## been replaced makes it a stale word that reads exactly like a chosen one —
## so it is re-minted rather than obeyed. A name a person typed never matches
## this shape and is never touched.
static func is_minted_name(n: String) -> bool:
	if not n.begins_with(NAME_PREFIX):
		return false
	var tail := n.substr(NAME_PREFIX.length())
	if tail == "?":
		return true
	if tail.length() != NAME_CHARS:
		return false
	for c in tail:
		if not ("0123456789abcdefABCDEF".contains(c)):
			return false
	return true


## Loads the stored identity, minting one from `fabric_id` on first run.
## `name_override` (HEXY_NAME) wins over the file without rewriting it, so one
## checkout can host alpha and beta at once.
static func load_or_mint(fabric_id: String, name_override: String = "") -> Object:
	var me = new()
	me.display_name = short_name(fabric_id)
	me.hue = hue_from_id(fabric_id)
	var cfg := ConfigFile.new()
	if cfg.load(CONFIG_PATH) == OK:
		# A CHOSEN NAME WINS; A MINTED ONE DOES NOT. The file used to hand back
		# whatever was written on first run, which after the fabric id moved was
		# a word for a phone that no longer exists. Only a name a person typed
		# survives a re-mint — see `is_minted_name`.
		var stored := String(cfg.get_value(SECTION, "name", ""))
		if stored != "" and not is_minted_name(stored):
			me.display_name = stored
		me.hue = float(cfg.get_value(SECTION, "hue", me.hue))
	else:
		cfg.set_value(SECTION, "hue", me.hue)
		cfg.save(CONFIG_PATH)
	if name_override != "":
		me.display_name = name_override
		# A named instance gets a hue from its name, not from the shared file:
		# alpha and beta run off one user:// dir and must not share a colour.
		me.hue = hue_from_id(name_override)
	return me
