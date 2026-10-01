extends RefCounted

## A clock observation is recorded, but cannot mint an act receipt.
func remember(sample: Dictionary, judgement: Dictionary, voice: Dictionary, mesh: Dictionary) -> Dictionary:
	return {
		"kind": "tick",
		"source": sample.get("clock", {}).get("source"),
		"time_ms": sample.get("time_ms"),
		"H": judgement.get("H"),
		"X": judgement.get("X"),
		"d": judgement.get("d"),
		"line": voice.get("line"),
		"voice_available": voice.get("available"),
		"mesh_available": mesh.get("available"),
		"minted": false,
	}
