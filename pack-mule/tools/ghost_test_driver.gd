extends Node

## Assertions for GhostPreview.align_up / place_on / spin / tip.
## Waits a few physics frames so the world geometry is registered with the
## physics server before querying it.

var _frames := 0
var _fails := 0
var _phase := 0
var _base0 := ""

@onready var _gm: Node = get_tree().root.get_node("Main")


func _physics_process(_delta: float) -> void:
	_frames += 1
	# Phase 0: force the donkey base so the saddle geometry is deterministic
	# (the assertions assume the donkey; the player may have equipped a mount).
	if _phase == 0 and _frames >= 10:
		_base0 = GameSettings.get_base()
		if _base0 != ShopCatalog.DEFAULT_BASE:
			GameSettings.set_base(ShopCatalog.DEFAULT_BASE)
			_gm._rebuild_base()
		_phase = 1
		_frames = 0
		return
	# Phase 1: let the rebuilt base register with the physics server.
	if _phase == 1 and _frames >= 10:
		set_physics_process(false)
		_run()


func _check(label: String, ok: bool) -> void:
	if ok:
		print("[ghosttest] PASS  ", label)
	else:
		_fails += 1
		print("[ghosttest] FAIL  ", label)


func _run() -> void:
	_gm.set_physics_process(false)  # stop the aiming loop from moving our ghost
	var space: PhysicsDirectSpaceState3D = _gm.get_world_3d().direct_space_state

	# 1. align_up maps world-up onto the normal for representative normals.
	for n: Vector3 in [Vector3.UP, Vector3(1, 1, 0).normalized(),
			Vector3.RIGHT, Vector3(0.2, -0.9, 0.3).normalized(), Vector3.DOWN]:
		var up: Vector3 = GhostPreview.align_up(n) * Vector3.UP
		_check("align_up %s" % n, up.is_equal_approx(n))

	# 2. Flat placement on the saddle: fits, flush, no overlap.
	var ghost: GhostPreview = GhostPreview.create(ObjectCatalog.ENTRIES[6])  # Safe
	_gm.add_child(ghost)
	var saddle_top: float = _gm._base_top
	var hit := Vector3(0, saddle_top, 0)
	var fits: bool = ghost.place_on(space, hit, Vector3.UP)
	_check("flat place_on fits", fits)
	_check("flat place_on clear", not ghost.overlaps(space))
	var bottom_y: float = ghost.global_position.y - ghost.bottom_offset(Vector3.UP)
	_check("flat place_on flush (bottom=%.3f saddle=%.3f)" % [bottom_y, saddle_top],
			absf(bottom_y - saddle_top) < 0.05)

	# 3. Tilted surface: ghost's up-axis follows the normal.
	var slope := Vector3(0.4, 1, 0).normalized()
	ghost.place_on(space, Vector3(8, 4, 0), slope)  # mid-air: no overlap possible
	_check("tilted basis follows normal",
			(ghost.global_basis * Vector3.UP).is_equal_approx(slope))

	# 4. Auto-adjust: hit point buried inside the donkey torso must still
	# resolve to a clear pose nearby.
	var buried := Vector3(0, saddle_top - 0.4, 0)
	fits = ghost.place_on(space, buried, Vector3.UP)
	_check("buried place_on resolves", fits)
	_check("buried place_on clear", not ghost.overlaps(space))

	# 5. spin keeps the up-axis on the normal (pure spin around the surface).
	ghost.spin(1.0)
	ghost.place_on(space, Vector3(8, 4, 0), slope)
	_check("spin preserves alignment",
			(ghost.global_basis * Vector3.UP).is_equal_approx(slope))

	# 6. tip changes the up-axis (object lies on its side) but placement on
	# the saddle still resolves clear.
	ghost.tip(Vector3.RIGHT, PI / 2.0)
	fits = ghost.place_on(space, hit, Vector3.UP)
	_check("tipped place_on fits", fits)
	_check("tipped place_on clear", not ghost.overlaps(space))

	GameSettings.set_base(_base0)  # restore the player's equipped mount
	print("[ghosttest] done: %d failure(s)" % _fails)
	get_tree().quit(1 if _fails > 0 else 0)
