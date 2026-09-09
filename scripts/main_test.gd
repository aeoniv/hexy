extends Node2D

const MnnRuntime = preload("res://scripts/brain/mnn_runtime.gd")

var label: Label

func _ready() -> void:
	label = Label.new()
	label.position = Vector2(40, 80)
	label.size = Vector2(640, 1000)
	label.text = "Hexy Android MNN Engine Test\n----------------------------\n"
	add_child(label)
	
	_log("Starting MnnRuntime checks...")
	var m := MnnRuntime.new()
	_log("Backend: %s" % m.backend_name())
	_log("Available (plugin attached): %s" % str(m.available()))
	
	var dim := m.embed_start()
	_log("Embed dimension: %d" % dim)
	var v1 := m.embed("squat form complete")
	var v2 := m.embed("squat form complete")
	var cos := MnnRuntime.cosine(v1, v2)
	_log("Cosine similarity (same prompt): %.4f" % cos)
	
	var chat_ok := m.chat_start()
	_log("Chat ready: %s (model: %s)" % [str(chat_ok), m.chat_model()])
	
	var reply := m.chat("Hello Hexy")
	_log("Chat reply: %s" % reply)
	
	_log("\n=== ALL CHECKS FINISHED ===")

func _log(msg: String) -> void:
	print("HEXY_A22_TEST: ", msg)
	if label:
		label.text += msg + "\n"
