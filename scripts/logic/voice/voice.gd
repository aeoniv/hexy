extends RefCounted

const NO_VOICE: String = "Hexy · no voice yet — download the pack"

func speak(_judgement: Dictionary) -> Dictionary:
	return {"available": false, "card": null, "line": NO_VOICE}
