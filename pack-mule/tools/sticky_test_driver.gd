extends Node

## Scenario test for Sticky mode's breakable glue:
## 1. Place a Safe gently on the saddle -> it settles and glues.
## 2. Drop a Piano from 2.5 m dead-center -> momentum (~560 kg*m/s) far
##    exceeds break_momentum (250), so the Safe must break loose.
## 3. Wait for the dust to settle -> every surviving tower piece must be
##    glued (frozen) again.

const TIMEOUT := 30.0

var _t := 0.0
var _stage := 0
var _grace := 0.0
var _saw_break := false
var _fails := 0
var _base: StackableObject

@onready var _gm: Node = get_tree().root.get_node("Main")


func _ready() -> void:
	_gm._start_game()  # skip the main menu
	_gm.set_physics_process(false)  # no mouse: keep the ghost aiming frozen
	print("[stickytest] started")


func _check(label: String, ok: bool) -> void:
	if ok:
		print("[stickytest] PASS  ", label)
	else:
		_fails += 1
		print("[stickytest] FAIL  ", label)


func _entry(entry_name: String) -> Dictionary:
	for e in ObjectCatalog.ENTRIES:
		if e["name"] == entry_name:
			return e
	push_error("no catalog entry named %s" % entry_name)
	return {}


func _finish() -> void:
	_check("glue broke on hard impact", _saw_break)
	for obj: StackableObject in _gm._settled:
		if obj.state == StackableObject.State.SETTLED:
			_check("%s re-glued (frozen)" % obj.display_name, obj.freeze)
	print("[stickytest] done: %d failure(s), %d on tower, strikes=%d" % [
			_fails, _gm._settled.size(), _gm._strikes])
	get_tree().quit(1 if _fails > 0 else 0)


func _process(delta: float) -> void:
	_t += delta
	if _t > TIMEOUT:
		print("[stickytest] TIMEOUT at stage ", _stage)
		get_tree().quit(1)
		return
	if _base != null and _base.state == StackableObject.State.FALLING:
		_saw_break = true  # the glued base piece is loose again
	match _stage:
		0:
			if _gm._phase == GameManager.Phase.AIMING and _gm._ghost != null:
				_gm._place_object(_entry("Safe"),
						Transform3D(Basis.IDENTITY, Vector3(0, _gm._base_top + 0.45, 0)))
				_stage = 1
		1:
			if _gm._settled.size() == 1:
				_base = _gm._settled[0]
				_check("Safe settled and glued", _base.is_glued())
				_gm._place_object(_entry("Piano"),
						Transform3D(Basis.IDENTITY, Vector3(0, _gm._base_top + 2.5, 0)))
				_stage = 2
		2:
			# Done once the game is out of SETTLING and nothing moves anymore.
			if _gm._phase == GameManager.Phase.SETTLING:
				_grace = 0.0
				return
			var all_resting := true
			for obj: StackableObject in _gm._settled:
				if obj.state == StackableObject.State.FALLING:
					all_resting = false
			_grace += delta if all_resting else -_grace
			if _grace > 3.0:
				_finish()
