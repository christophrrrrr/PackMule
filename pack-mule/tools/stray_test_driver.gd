extends Node

## Drops a Safe onto the summit dome, off to the side of the donkey (not
## on the tower). It must NOT stick on the rock: within the time limit it
## has to either reach the kill zone (FALLEN) or slide well down the peak.

const TIMEOUT := 20.0

var _t := 0.0
var _placed := false
var _obj: StackableObject
var _fails := 0

@onready var _gm: Node = get_tree().root.get_node("Main")


func _ready() -> void:
	_gm.set_physics_process(true)  # integrity sweep + kill zone run here
	print("[straytest] started")


func _entry(n: String) -> Dictionary:
	for e in ObjectCatalog.ENTRIES:
		if e["name"] == n:
			return e
	return {}


func _process(delta: float) -> void:
	_t += delta
	if not _placed and _gm._ghost != null:
		# Just above the dome, ~2.6 m to the side of the donkey's centre.
		_gm._place_object(_entry("Safe"), Transform3D(Basis.IDENTITY, Vector3(2.6, 2.0, 0.0)))
		_obj = _gm._settling
		_placed = true
		return
	if not _placed:
		return
	var slid_off: bool = _obj.state == StackableObject.State.FALLEN \
			or _obj.global_position.y < -6.0
	if slid_off:
		print("[straytest] PASS  stray object left the summit (state=%d y=%.1f)" % [
				_obj.state, _obj.global_position.y])
		get_tree().quit(0)
		return
	if _t > TIMEOUT:
		print("[straytest] FAIL  stray object stuck at y=%.2f (state=%d, frozen=%s)" % [
				_obj.global_position.y, _obj.state, _obj.freeze])
		get_tree().quit(1)
