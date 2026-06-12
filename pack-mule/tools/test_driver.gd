extends Node

## Drives the game loop headless for auto_test.gd: disables ghost aiming
## (there is no mouse) and places every object dead-center above the tower,
## then reports the result after MAX_DROPS placements or game over.

const MAX_DROPS := 6
const TIMEOUT := 60.0

var _since_action := 0.0
var _total := 0.0
var _drops := 0
var _seen_settled := 0

@onready var _gm: Node = get_tree().root.get_node("Main")


func _ready() -> void:
	# Without a player the mouse sits at (0,0); freeze ghost aiming and place
	# objects programmatically instead.
	_gm.set_physics_process(false)
	print("[autotest] started, saddle top=%.2f" % _gm._base_top)


func _process(delta: float) -> void:
	_since_action += delta
	_total += delta
	while _seen_settled < _gm._settled.size():
		var obj: Node3D = _gm._settled[_seen_settled]
		_seen_settled += 1
		print("[autotest]   settled %s at y=%.2f (top_y=%.2f, tower_top=%.2f)" % [
			obj.display_name, obj.global_position.y, obj.top_y(), _gm._tower_top])
	if _total > TIMEOUT:
		print("[autotest] TIMEOUT in phase ", _gm._phase)
		get_tree().quit(1)
		return
	if _gm._phase == 2:  # GAME_OVER
		print("[autotest] game over reached after %d drops: score=%d strikes=%d" % [
			_drops, _gm._total_score(), _gm._strikes])
		get_tree().quit(0)
		return
	if _drops >= MAX_DROPS:
		if _gm._phase == 0:  # AIMING again => last drop fully resolved
			print("[autotest] PASS: drops=%d settled=%d score=%d strikes=%d height=%.2f" % [
				_drops, _gm._settled.size(), _gm._total_score(), _gm._strikes,
				_gm._tower_top - _gm._base_top])
			get_tree().quit(0)
		return
	if _gm._phase == 0 and _gm._ghost != null and _since_action > 0.3:
		_since_action = 0.0
		_drops += 1
		var ghost: Node3D = _gm._ghost
		var pos := Vector3(0, _gm._tower_top + ghost.half_extents.y + 0.05, 0)
		print("[autotest] place #%d: %s" % [_drops, ghost.entry["name"]])
		_gm._place_object(ghost.entry, Transform3D(Basis.IDENTITY, pos))
