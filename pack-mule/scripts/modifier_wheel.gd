class_name ModifierWheel
extends Control

## Full-screen overlay with a custom-drawn prize wheel of the six
## modifiers. spin() picks the result up front, then animates the wheel
## decelerating onto it; `landed` fires with the winning modifier and the
## overlay hides itself shortly after.

signal landed(modifier: Dictionary)

const RADIUS := 170.0
const SPIN_TIME := 3.2
const SPIN_TURNS := 5
const SHOW_RESULT_TIME := 1.4

var _rot := 0.0
var _busy := false
var _result_text := ""
var _tick_seg := -1


func _ready() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func is_busy() -> bool:
	return _busy


func spin() -> void:
	if _busy:
		return
	_busy = true
	_result_text = ""
	visible = true
	var count := ModifierCatalog.ENTRIES.size()
	var seg := TAU / count
	var idx := randi() % count
	# Wheel rotation that puts the winning segment (with some in-segment
	# jitter) under the pointer at the top (-PI/2).
	var jitter := randf_range(-0.33, 0.33) * seg
	var target := -PI / 2.0 - (idx + 0.5) * seg + jitter
	var final := _rot + TAU * SPIN_TURNS + wrapf(target - _rot, 0.0, TAU)
	var tween := create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUART)
	tween.tween_method(_set_rot, _rot, final, SPIN_TIME)
	tween.tween_callback(_finish.bind(idx))


func _set_rot(value: float) -> void:
	_rot = value
	# Click once per segment that passes under the pointer.
	var seg := int(value / (TAU / ModifierCatalog.ENTRIES.size()))
	if seg != _tick_seg:
		_tick_seg = seg
		Sfx.play("tick", randf_range(0.95, 1.08))
	queue_redraw()


func _finish(idx: int) -> void:
	var modifier: Dictionary = ModifierCatalog.ENTRIES[idx]
	_result_text = "%s!" % modifier["name"]
	Sfx.play("ding")
	queue_redraw()
	landed.emit(modifier)
	get_tree().create_timer(SHOW_RESULT_TIME).timeout.connect(func() -> void:
		visible = false
		_busy = false)


func _draw() -> void:
	var center := size / 2.0
	var count := ModifierCatalog.ENTRIES.size()
	var seg := TAU / count
	var font := get_theme_default_font()
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.0, 0.0, 0.0, 0.55))
	for i in count:
		var modifier: Dictionary = ModifierCatalog.ENTRIES[i]
		var a0: float = _rot + i * seg
		var pts := PackedVector2Array([center])
		for s in 17:
			var a := a0 + seg * s / 16.0
			pts.append(center + Vector2(cos(a), sin(a)) * RADIUS)
		draw_colored_polygon(pts, modifier["color"])
		# Special slices get a thick rim: gold = always good, red = risky.
		if modifier.has("border"):
			var border: Color = modifier["border"]
			var arc := PackedVector2Array()
			for s in 17:
				var a := a0 + seg * s / 16.0
				arc.append(center + Vector2(cos(a), sin(a)) * RADIUS)
			draw_polyline(arc, border, 5.0, true)
			draw_line(center, arc[0], border, 5.0)
			draw_line(center, arc[16], border, 5.0)
		var mid := a0 + seg / 2.0
		var label: String = modifier["name"]
		var width := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x
		var pos := center + Vector2(cos(mid), sin(mid)) * RADIUS * 0.62
		draw_string(font, pos + Vector2(-width / 2.0, 6.0), label,
				HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(0.05, 0.05, 0.08))
	draw_circle(center, 26.0, Color(0.12, 0.12, 0.16))
	draw_arc(center, RADIUS, 0.0, TAU, 64, Color(0.1, 0.1, 0.12), 4.0)
	# Fixed pointer at the top, pointing down at the wheel.
	var tip := center + Vector2(0.0, -RADIUS + 12.0)
	draw_colored_polygon(PackedVector2Array([
			tip, tip + Vector2(-14.0, -30.0), tip + Vector2(14.0, -30.0)]),
			Color(0.95, 0.95, 0.98))
	if not _result_text.is_empty():
		var width := font.get_string_size(_result_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 30).x
		draw_string(font, center + Vector2(-width / 2.0, RADIUS + 56.0), _result_text,
				HORIZONTAL_ALIGNMENT_LEFT, -1, 30, Color.WHITE)
