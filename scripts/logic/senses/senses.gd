extends RefCounted

## The clock is the only live sense in the skeleton.
func sample(now_ms: int) -> Dictionary:
	return {
		"time_ms": now_ms,
		"clock": {"source": "system_clock", "time_ms": now_ms},
		"signals": [null, null, null, null, null, null],
		"human": null,
	}
