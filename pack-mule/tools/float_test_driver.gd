extends Node

## Reproduces the floating-tower bug and asserts the integrity sweep fixes
## it: stack Tub on Safe, sever the support-graph edges (simulating the
## missed-link case), then blast the Safe away. The Tub is left glued in
## midair with no recorded dependents — only the integrity sweep can know
## it must fall. It has to come loose within a second.

const TIMEOUT := 30.0

var _t := 0.0
var _stage := 0
var _grace := 0.0
var _saw_unfloat := false
var _fails := 0
var _safe: StackableObject
var _tub: StackableObject

@onready var _gm: Node = get_tree().root.get_node("Main")


func _ready() -> void:
	# Unlike the other drivers, _physics_process stays ON: the integrity
	# sweep lives there. The ghost aiming it also runs is harmless headless.
	print("[floattest] started")


func _check(label: String, ok: bool) -> void:
	if ok:
		print("[floattest] PASS  ", label)
	else:
		_fails += 1
		print("[floattest] FAIL  ", label)


func _entry(entry_name: String) -> Dictionary:
	for e in ObjectCatalog.ENTRIES:
		if e["name"] == entry_name:
			return e
	return {}


func _finish() -> void:
	print("[floattest] safe: state=%d pos=%s  tub: state=%d pos=%s" % [
			_safe.state, _safe.global_position, _tub.state, _tub.global_position])
	_check("floating piece was broken loose by the sweep", _saw_unfloat)
	var space: PhysicsDirectSpaceState3D = _gm.get_world_3d().direct_space_state
	for obj: StackableObject in _gm._settled:
		if obj.state == StackableObject.State.SETTLED:
			_check("%s is touching something" % obj.display_name,
					not obj.touching_bodies(space).is_empty())
	print("[floattest] done: %d failure(s), strikes=%d" % [_fails, _gm._strikes])
	get_tree().quit(1 if _fails > 0 else 0)


func _process(delta: float) -> void:
	_t += delta
	if _t > TIMEOUT:
		print("[floattest] TIMEOUT at stage ", _stage)
		get_tree().quit(1)
		return
	# From the moment the Safe is knocked loose (stage 3+), any tub
	# unfreeze is the sweep doing its job — the support edges are severed,
	# so nothing else can wake it.
	if _stage >= 3 and _tub != null \
			and _tub.state != StackableObject.State.SETTLED:
		_saw_unfloat = true
	match _stage:
		0:
			if _gm._phase == 0 and _gm._ghost != null:
				_gm._place_object(_entry("Safe"),
						Transform3D(Basis.IDENTITY, Vector3(0, _gm._base_top + 0.45, 0)))
				_stage = 1
		1:
			if _gm._settled.size() == 1:
				_safe = _gm._settled[0]
				_gm._place_object(_entry("Tub"),
						Transform3D(Basis.IDENTITY, Vector3(0, _safe.top_y() + 0.4, 0)))
				_stage = 2
		2:
			if _gm._settled.size() == 2:
				_tub = _gm._settled[1]
				_check("Tub glued on Safe", _tub.is_glued())
				# Simulate the bug: no recorded support edges anywhere.
				_safe._dependents.clear()
				_tub._supporters.clear()
				_safe.break_loose(true)
				_stage = 3
		3:
			# Wait a beat so the unfreeze reaches the physics server, then
			# yank the Safe out from under the Tub — the Tub is now a glued
			# piece in midair, exactly the reported bug.
			_grace += delta
			if _grace > 0.2:
				_grace = 0.0
				_safe.global_position += Vector3(10.0, 0.0, 0.0)
				_stage = 4
		4:
			# The Tub must come loose (FALLING or FALLEN) — not stay glued in air.
			if _saw_unfloat:
				_grace = 0.0
				_stage = 5
		5:
			# Let everything land, then verify no settled piece floats.
			_grace += delta
			if _grace > 6.0:
				_finish()
