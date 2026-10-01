extends RefCounted

## No need is inferred from a clock reading.
func step(sample: Dictionary, _dt: float = 1.0) -> Dictionary:
	var needs: Array = [null, null, null, null, null, null]
	return {"time_ms": sample.get("time_ms"), "needs": needs, "moving": [], "heading": null, "X": null}
