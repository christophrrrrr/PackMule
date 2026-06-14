extends SceneTree

## Reports whether each sound resolves to a real file in assets/ or falls
## back to the synthesized version. Run:
## godot --headless --path . --script res://tools/check_sfx.gd

func _init() -> void:
	var names := ["wood", "metal", "soft", "glass", "piano", "critter",
			"cow", "bear", "trex", "alien", "rock", "crash", "thunder",
			"tick", "ding", "sting", "wind", "coin", "register"]
	for n in names:
		var found := ""
		for dir in ["res://assets/", "res://assets/sfx/"]:
			for ext in [".ogg", ".wav"]:
				if ResourceLoader.exists(dir + n + ext):
					found = dir + n + ext
		print("%-8s -> %s" % [n, found if found != "" else "(synth fallback)"])
	quit(0)
