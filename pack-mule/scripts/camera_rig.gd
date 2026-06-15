class_name CameraRig
extends Node3D

## Always-on free-fly camera: the mouse looks around (cursor captured),
## WASD flies, Space rises, Ctrl descends, Shift sprints, and the mouse
## wheel adjusts fly speed. (Esc is handled by the HUD: it pauses.)

const LOOK_SENSITIVITY := 0.0035
const DEFAULT_SPEED := 8.0
const MIN_SPEED := 2.0
const MAX_SPEED := 50.0
const SPEED_STEP := 1.25
const SPRINT_MULT := 2.5
const MAX_PITCH := 1.45
const SHAKE_DECAY := 6.0

const START_POSITION := Vector3(8.0, 5.5, 11.0)
const START_LOOK_AT := Vector3(0.0, 1.0, 0.0)

# A "bubble" the camera can roam: a horizontal radius around the peak, from
# just above the clouds up to well above a tall tower. Plus solid avoidance
# so you can't fly into the mountain, donkey, or placed objects.
const BOUND_RADIUS := 35.0
const BOUND_MIN_Y := -6.0
const BOUND_MAX_Y := 55.0
const AVOID_RADIUS := 0.6

var _speed := DEFAULT_SPEED
var _yaw := 0.0
var _pitch := 0.0
var _shake := 0.0
var _avoid := SphereShape3D.new()

@onready var _camera: Camera3D = $Camera3D


func _ready() -> void:
	_camera.position = Vector3.ZERO
	position = START_POSITION
	look_at(START_LOOK_AT)
	_yaw = rotation.y
	_pitch = rotation.x
	_avoid.radius = AVOID_RADIUS
	# The game manager owns the mouse mode (the main menu needs a visible
	# cursor); it captures the mouse when the run starts.


func _unhandled_input(event: InputEvent) -> void:
	# Only act on input while flying (cursor captured). On the menu the cursor
	# is visible, and an unguarded wheel here used to silently change the fly
	# speed before a run even started.
	if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		return
	if event is InputEventMouseMotion:
		_yaw -= event.relative.x * LOOK_SENSITIVITY
		_pitch = clampf(_pitch - event.relative.y * LOOK_SENSITIVITY, -MAX_PITCH, MAX_PITCH)
		rotation = Vector3(_pitch, _yaw, 0.0)
	elif event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_speed = minf(MAX_SPEED, _speed * SPEED_STEP)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_speed = maxf(MIN_SPEED, _speed / SPEED_STEP)


func _process(delta: float) -> void:
	var dir := Vector3.ZERO
	var b := transform.basis
	if Input.is_action_pressed("pm_forward"):
		dir -= b.z
	if Input.is_action_pressed("pm_back"):
		dir += b.z
	if Input.is_action_pressed("pm_left"):
		dir -= b.x
	if Input.is_action_pressed("pm_right"):
		dir += b.x
	if Input.is_action_pressed("pm_up"):
		dir += Vector3.UP
	if Input.is_action_pressed("pm_down"):
		dir -= Vector3.UP
	if dir != Vector3.ZERO:
		var speed := _speed * (SPRINT_MULT if Input.is_key_pressed(KEY_SHIFT) else 1.0)
		var move := dir.normalized() * speed * delta
		# If something (e.g. a freshly placed object) ended up around the
		# camera, let it fly out freely; otherwise slide along walls and stay
		# inside the bubble and out of solid geometry.
		var stuck := _blocked(position)
		_try_move(Vector3(move.x, 0.0, 0.0), stuck)
		_try_move(Vector3(0.0, move.y, 0.0), stuck)
		_try_move(Vector3(0.0, 0.0, move.z), stuck)
	# Screen shake: jitter the camera, decaying back to centered.
	if _shake > 0.001:
		_camera.position = Vector3(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0),
				randf_range(-1.0, 1.0)) * _shake
		_shake = move_toward(_shake, 0.0, SHAKE_DECAY * _shake * delta + delta)
	elif _camera.position != Vector3.ZERO:
		_camera.position = Vector3.ZERO


## Move by one axis if the destination is inside the bubble and not inside
## solid geometry — unless we're already stuck inside something, in which
## case any move is allowed so the player can get out.
func _try_move(step: Vector3, stuck: bool) -> void:
	var cand := _clamp_bounds(position + step)
	if stuck or not _blocked(cand):
		position = cand


func _clamp_bounds(p: Vector3) -> Vector3:
	var flat := Vector2(p.x, p.z)
	if flat.length() > BOUND_RADIUS:
		flat = flat.normalized() * BOUND_RADIUS
	return Vector3(flat.x, clampf(p.y, BOUND_MIN_Y, BOUND_MAX_Y), flat.y)


func _blocked(p: Vector3) -> bool:
	var space := get_world_3d().direct_space_state
	if space == null:
		return false
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = _avoid
	q.transform = Transform3D(Basis.IDENTITY, p)
	q.collision_mask = 1 | 2  # static world (mountain/donkey/ground) + objects
	return not space.intersect_shape(q, 1).is_empty()


## Reset the fly speed to its default at the start of a run, so every run
## begins at the same pace regardless of any earlier wheel scrolling.
func reset_flight() -> void:
	_speed = DEFAULT_SPEED
	_shake = 0.0


## Snap the camera back to its opening pose (used by the in-place restart).
func reset_view() -> void:
	position = START_POSITION
	look_at(START_LOOK_AT)
	_yaw = rotation.y
	_pitch = rotation.x
	_camera.position = Vector3.ZERO
	reset_flight()


## Kick the camera; bigger amount = bigger jolt. Used for impacts/collapses.
func shake(amount: float) -> void:
	_shake = maxf(_shake, amount)
