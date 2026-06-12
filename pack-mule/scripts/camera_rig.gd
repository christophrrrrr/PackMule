class_name CameraRig
extends Node3D

## Always-on free-fly camera: the mouse looks around (cursor captured),
## WASD flies, Space rises, Ctrl descends, Shift sprints, and the mouse
## wheel adjusts fly speed. Esc frees the cursor (aim with the cursor
## instead); Esc again returns to mouse-look.

const LOOK_SENSITIVITY := 0.0035
const MIN_SPEED := 2.0
const MAX_SPEED := 50.0
const SPEED_STEP := 1.25
const SPRINT_MULT := 2.5
const MAX_PITCH := 1.45

const START_POSITION := Vector3(5.0, 3.5, 7.0)
const START_LOOK_AT := Vector3(0.0, 1.5, 0.0)

var _speed := 8.0
var _yaw := 0.0
var _pitch := 0.0

@onready var _camera: Camera3D = $Camera3D


func _ready() -> void:
	_camera.position = Vector3.ZERO
	position = START_POSITION
	look_at(START_LOOK_AT)
	_yaw = rotation.y
	_pitch = rotation.x
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo \
			and event.keycode == KEY_ESCAPE:
		var captured := Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if captured else Input.MOUSE_MODE_CAPTURED
	elif event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
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
	if Input.is_key_pressed(KEY_W):
		dir -= b.z
	if Input.is_key_pressed(KEY_S):
		dir += b.z
	if Input.is_key_pressed(KEY_A):
		dir -= b.x
	if Input.is_key_pressed(KEY_D):
		dir += b.x
	if Input.is_key_pressed(KEY_SPACE):
		dir += Vector3.UP
	if Input.is_key_pressed(KEY_CTRL):
		dir -= Vector3.UP
	if dir == Vector3.ZERO:
		return
	var speed := _speed * (SPRINT_MULT if Input.is_key_pressed(KEY_SHIFT) else 1.0)
	position += dir.normalized() * speed * delta
