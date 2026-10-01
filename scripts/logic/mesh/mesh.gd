extends RefCounted

func share(_event: Dictionary) -> Dictionary:
	return {"available": false, "sent": false, "peers": null, "reason": "mesh unavailable"}
