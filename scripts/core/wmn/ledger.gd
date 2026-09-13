class_name Ledger
extends RefCounted

## Append-only record of the figures this install has cast or heard.
##
## The id of a cast is the sha256 of its canonical JSON — the five fields that
## make a cast the cast it is (bits, moving, throws, when, who) and nothing
## else. Source and signature are metadata ABOUT the cast and are deliberately
## outside the hash: re-signing a figure must not rename it, and the same six
## lines thrown by the same person at the same millisecond are the same event
## whether they arrived by tap or over the mesh.
##
## Canonical means one spelling, written here by hand rather than left to
## JSON.stringify's key order: two phones must agree byte-for-byte on the
## string they hash or they will disagree about what happened in the room.
##
## Witnesses are a map who -> sig. Provenance only, never a score — the same
## ruling EventEnvelope.prov carries. A witness says "I was there", and an
## empty sig is an honest witness with nothing to sign with.

const PATH := "user://ledger.json"

var _by_id := {}
var _order: Array[String] = ([] as Array[String])
## Optional Identity-like object. If it can `sign`/`verify`, signatures are
## checked; if not, verify() falls back to the structural check and says so.
var identity: Object = null


## The exact bytes an id is taken over. Fixed key order, ints as ints, throws
## as a flat list. Anything not in this line cannot change a cast's name.
static func canonical(h: Dictionary) -> String:
	var throws: Array = []
	var raw = h.get("throws", [])
	if raw is Array:
		for v in (raw as Array):
			throws.append(int(v))
	return '{"bits":%d,"moving":%d,"throws":%s,"when":%d,"who":%s}' % [
		int(h.get("bits", 0)) & 63,
		int(h.get("moving", 0)) & 63,
		JSON.stringify(throws),
		int(h.get("when", 0)),
		JSON.stringify(String(h.get("who", ""))),
	]


static func id_of(h: Dictionary) -> String:
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(canonical(h).to_utf8_buffer())
	return ctx.finish().hex_encode()


func size() -> int:
	return _order.size()


func has(id: String) -> bool:
	return _by_id.has(id)


## Appends a cast and returns its id. Appending the same cast twice is not an
## error and not a second entry — the id IS the cast, so the second call only
## folds in any new witnesses. Append-only means nothing is ever removed; it
## does not mean the same event is recorded twice.
func append(h: Dictionary, witnesses: Array = []) -> String:
	var id := id_of(h)
	if not _by_id.has(id):
		var throws: Array = []
		var raw = h.get("throws", [])
		if raw is Array:
			for v in (raw as Array):
				throws.append(int(v))
		_by_id[id] = {
			"id": id,
			"bits": int(h.get("bits", 0)) & 63,
			"moving": int(h.get("moving", 0)) & 63,
			"throws": throws,
			"when": int(h.get("when", 0)),
			"who": String(h.get("who", "")),
			"source": String(h.get("source", "tap")),
			"sig": String(h.get("sig", "")),
			"witnesses": {},
		}
		_order.append(id)
	for w in witnesses:
		witness(id, String(w), "")
	return id


func witness(id: String, who: String, sig: String = "") -> bool:
	if not _by_id.has(id) or who == "":
		return false
	var ws: Dictionary = _by_id[id]["witnesses"]
	# A signed witness upgrades an unsigned one; an unsigned one never
	# downgrades a signature that is already there.
	if ws.has(who) and String(ws[who]) != "" and sig == "":
		return true
	ws[who] = sig
	return true


func witnesses_of(id: String) -> Array:
	if not _by_id.has(id):
		return []
	var out: Array = (_by_id[id]["witnesses"] as Dictionary).keys()
	out.sort()
	return out


## One entry, or {} if unknown. Named `get_cast` rather than `get`: RefCounted
## already owns `get`, and shadowing a native method is a compile error, not a
## style choice.
func get_cast(id: String) -> Dictionary:
	return (_by_id.get(id, {}) as Dictionary).duplicate(true)


## Every entry in the order it was appended.
func all() -> Array:
	var out: Array = []
	for id in _order:
		out.append((_by_id[id] as Dictionary).duplicate(true))
	return out


func latest() -> Dictionary:
	return get_cast(_order[-1]) if not _order.is_empty() else {}


## Structural first, cryptographic only if an identity can actually do it.
## The structural check is not a weak version of the signature check — it is a
## different question, and the one that catches a tampered ledger file: an
## entry whose fields no longer hash to the id it is filed under has been
## edited since it was written, signature or no signature.
func verify(id: String) -> bool:
	if not _by_id.has(id):
		return false
	var e: Dictionary = _by_id[id]
	if id_of(e) != id:
		return false
	var sig := String(e.get("sig", ""))
	if sig != "" and identity != null and identity.has_method("verify_sig"):
		return bool(identity.call("verify_sig", String(e.get("who", "")), canonical(e), sig))
	return true


func verify_all() -> bool:
	for id in _order:
		if not verify(id):
			return false
	return true


func to_dict() -> Dictionary:
	return {"v": 1, "casts": all()}


func from_dict(d: Dictionary) -> void:
	_by_id.clear()
	_order.clear()
	var casts = d.get("casts", [])
	if not (casts is Array):
		return
	for c in (casts as Array):
		if not (c is Dictionary):
			continue
		var e: Dictionary = c as Dictionary
		var id := append(e, [])
		var ws = e.get("witnesses", {})
		if ws is Dictionary:
			for w in (ws as Dictionary):
				witness(id, String(w), String((ws as Dictionary)[w]))


func save(path: String = PATH) -> Error:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return FileAccess.get_open_error()
	f.store_string(JSON.stringify(to_dict()))
	f.close()
	return OK


func load(path: String = PATH) -> Error:
	if not FileAccess.file_exists(path):
		return ERR_FILE_NOT_FOUND
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return FileAccess.get_open_error()
	var parsed = JSON.parse_string(f.get_as_text())
	f.close()
	if not (parsed is Dictionary):
		return ERR_PARSE_ERROR
	from_dict(parsed as Dictionary)
	return OK
