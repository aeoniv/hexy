class_name FlyRecall
extends RefCounted

## ASSOCIATIVE RECALL over FlyHash codes.
##
## Remembers a line of text under the sparse code of whatever vector the caller
## says means it, and gives back the nearest few by Hamming distance. It never
## calls the model itself: whoever has the embedder hands the vector in, which
## is what lets the tests run on synthetic clusters with no model on disk.

const FlyHashScript := preload("res://scripts/brain/fly_hash.gd")

const SCHEMA := 1

var hasher: RefCounted = null
var entries: Array[Dictionary] = []


func _init(p_hasher: RefCounted = null) -> void:
	hasher = p_hasher if p_hasher != null else FlyHashScript.new()


func size() -> int:
	return entries.size()


func clear() -> void:
	entries.clear()


## Stores one memory. `vec` is whatever embedding the caller trusts.
func remember(text: String, vec: PackedFloat32Array, meta: Dictionary = {}) -> Dictionary:
	var e: Dictionary = {
		"text": text,
		"hash": hasher.hash(vec),
		"meta": meta.duplicate(true),
		"t": int(Time.get_unix_time_from_system()),
	}
	entries.append(e)
	return e


## The k nearest memories, nearest first. Each row carries text, meta, t,
## "dist" (Hamming bits) and "similarity" (1.0 = same cells).
func recall(vec: PackedFloat32Array, k: int = 5) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if entries.is_empty() or k <= 0:
		return out
	var probe: PackedInt32Array = hasher.hash(vec)
	var scored: Array[Dictionary] = []
	for i in range(entries.size()):
		var e: Dictionary = entries[i]
		var d: int = FlyHashScript.hamming(probe, e["hash"])
		scored.append({
			"index": i,
			"text": String(e.get("text", "")),
			"meta": e.get("meta", {}),
			"t": int(e.get("t", 0)),
			"dist": d,
			"similarity": hasher.similarity(probe, e["hash"]),
		})
	scored.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if int(a["dist"]) == int(b["dist"]):
			return int(a["index"]) < int(b["index"])
		return int(a["dist"]) < int(b["dist"])
	)
	for i in range(mini(k, scored.size())):
		out.append(scored[i])
	return out


func to_dict() -> Dictionary:
	var rows: Array = []
	for e in entries:
		var words: Array = []
		for w in (e["hash"] as PackedInt32Array):
			words.append(int(w))
		rows.append({
			"text": String(e.get("text", "")),
			"hash": words,
			"meta": e.get("meta", {}),
			"t": int(e.get("t", 0)),
		})
	return {"schema": SCHEMA, "entries": rows}


func from_dict(d: Dictionary) -> void:
	entries.clear()
	for row in (d.get("entries", []) as Array):
		var r: Dictionary = row
		var words := PackedInt32Array()
		for w in (r.get("hash", []) as Array):
			words.append(int(w))
		entries.append({
			"text": String(r.get("text", "")),
			"hash": words,
			"meta": r.get("meta", {}),
			"t": int(r.get("t", 0)),
		})


## JSON under user://. Returns true on success.
func save(path: String) -> bool:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(JSON.stringify(to_dict()))
	f.close()
	return true


func load(path: String) -> bool:
	if not FileAccess.file_exists(path):
		return false
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return false
	var text: String = f.get_as_text()
	f.close()
	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		return false
	from_dict(parsed)
	return true
