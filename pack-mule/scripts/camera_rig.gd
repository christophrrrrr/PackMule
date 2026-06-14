class_name CameraRig
extends Node3D

## Always-on free-fly camera: the mouse looks around (cursor captured),
## WASD flies, Space rises, Ctrl descends, Shift sprints, and the mouse
## wheel adjusts fly speed. (Esc is handled by the HUD: it pauses.)

const LOOK_SENSITIVITY := 0.0035
const MIN_SPEED := 2.0
const MAX_SPEED := 50.0
const SPEED_STEP := 1.25
const SPRINT_MULT := 2.5
const MAX_PITCH := 1.45
const SHAKE_DECAY := 6.0

const START_POSITION := Vector3(8.0, 5.5, 11.0)
const START_LOOK_AT := Vector3(0.0, 1.0, 0.0)

var _speed := 8.0
var _yaw := 0.0
var _pitch := 0.0
var _shake := 0.0

@onready var _camera: Camera3D = $Camera3D


func _ready() -> void:
	_camera.position = Vector3.ZERO
	position = START_POSITION
	look_at(START_LOOK_AT)
	_yaw = rotation.y
	_pitch = rotation.x
	# The game manager owns the mouse mode (the main menu needs a visible
	# cursor); it captures the mouse when the run starts.


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
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
		position += dir.normalized() * speed * delta
	# Screen shake: jitter the camera, decaying back to centered.
	if _shake > 0.001:
		_camera.position = Vector3(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0),
				randf_range(-1.0, 1.0)) * _shake
		_shake = move_toward(_shake, 0.0, SHAKE_DECAY * _shake * delta + delta)
	elif _camera.position != Vector3.ZERO:
		_camera.position = Vector3.ZERO


## Kick the camera; bigger amount = bigger jolt. Used for impacts/collapses.
func shake(amount: float) -> void:
	_shake = maxf(_shake, amount)
