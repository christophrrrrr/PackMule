class_name GameHud
extends CanvasLayer

## In-game HUD plus the game-over "postcard" screen. The game-over screen is
## the real reward — a framed photo of the tower with the run's stats baked
## on, presented like a postcard the player can save and share.

signal restart_requested
signal wheel_landed(modifier: Dictionary)

# Playful cartoon palette.
const CREAM := Color(0.98, 0.96, 0.89)
const INK := Color(0.16, 0.15, 0.22)
const PANEL_BG := Color(0.16, 0.17, 0.30, 0.96)
const SUNNY := Color(1.0, 0.83, 0.22)
const SKY := Color(0.36, 0.74, 1.0)
const LEAF := Color(0.42, 0.80, 0.36)
const TANGERINE := Color(1.0, 0.55, 0.21)

const POSTCARD_SIZE := Vector2i(1024, 680)
const PC_PAD := 22
const PC_CAPTION_H := 150

@onready var _score: Label = $ScoreLabel
@onready var _height: Label = $HeightLabel
@onready var _strikes: Label = $StrikesLabel
@onready var _modifier: Label = $ModifierLabel
@onready var _incoming: Label = $IncomingLabel
@onready var _hint: Label = $HintLabel
@onready var _crosshair: Label = $Crosshair
@onready var _wheel: ModifierWheel = $WheelOverlay
@onready var _game_over: CenterContainer = $GameOverPanel

var _go_built := false
var _go_title: Label
var _go_subtitle: Label
var _pc_display: TextureRect
var _saved_label: Label
var _chip_values := {}

# Postcard SubViewport (the shareable, baked image).
var _pc_vp: SubViewport
var _pc_photo: TextureRect
var _pc_banner: Label
var _pc_big: Label
var _pc_caption: Label


func _ready() -> void:
	_game_over.visible = false
	_wheel.landed.connect(func(modifier: Dictionary) -> void: wheel_landed.emit(modifier))


func spin_wheel() -> void:
	_wheel.spin()


func wheel_busy() -> bool:
	return _wheel.is_busy()


func set_score(total: int) -> void:
	_score.text = "SCORE: %d" % total


func set_height(meters: float) -> void:
	_height.text = "HEIGHT: %.1f m" % meters


func set_strikes(current: int, max_strikes: int) -> void:
	_strikes.text = "FALLEN: %d / %d" % [current, max_strikes]


func set_modifier(text: String) -> void:
	_modifier.text = text


func set_incoming(text: String) -> void:
	_incoming.text = text


func set_crosshair(shown: bool) -> void:
	_crosshair.visible = shown


## Hides every in-game readout so the tower photo is captured clean.
func set_in_game_hud_visible(shown: bool) -> void:
	for node in [_score, _height, _strikes, _modifier, _incoming, _hint, _crosshair]:
		node.visible = shown


func show_game_over(reason: String, stats: Dictionary, photo: Image) -> void:
	if not _go_built:
		_build_game_over_ui()
		_go_built = true
	_build_postcard(photo, stats)
	_go_title.text = reason
	_go_subtitle.text = "FINAL SCORE  %d" % int(stats["score"])
	_chip_values["HEIGHT"].text = "%.1f m" % float(stats["height"])
	_chip_values["OBJECTS"].text = "%d" % int(stats["objects"])
	_chip_values["WEIGHT"].text = "%d kg" % int(round(float(stats["weight"])))
	_pc_display.texture = _pc_vp.get_texture()
	_saved_label.visible = false
	_game_over.visible = true


# --- Game-over panel (the colorful frame around the postcard) ----------------

func _build_game_over_ui() -> void:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _rounded(PANEL_BG, 30, Color(0.0, 0.0, 0.0, 0.0)))

	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 20)
	panel.add_child(margin)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	margin.add_child(box)

	_go_title = _make_label("", 38, SUNNY)
	_go_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_go_title.add_theme_color_override("font_outline_color", INK)
	_go_title.add_theme_constant_override("outline_size", 8)
	box.add_child(_go_title)

	_go_subtitle = _make_label("", 20, Color.WHITE)
	_go_subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_go_subtitle)

	# Postcard preview (the SubViewport texture), kept at the photo's aspect.
	_pc_display = TextureRect.new()
	_pc_display.custom_minimum_size = Vector2(460, 460 * POSTCARD_SIZE.y / POSTCARD_SIZE.x)
	_pc_display.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_pc_display.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	box.add_child(_pc_display)

	# Colorful stat chips.
	var chips := HBoxContainer.new()
	chips.add_theme_constant_override("separation", 14)
	chips.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_child(chips)
	chips.add_child(_make_chip("HEIGHT", SKY))
	chips.add_child(_make_chip("OBJECTS", LEAF))
	chips.add_child(_make_chip("WEIGHT", TANGERINE))

	# Buttons.
	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 16)
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_child(buttons)
	var save_btn := _make_button("SAVE PHOTO", SKY)
	save_btn.pressed.connect(_on_save_pressed)
	buttons.add_child(save_btn)
	var again_btn := _make_button("STACK AGAIN", LEAF)
	again_btn.pressed.connect(func() -> void: restart_requested.emit())
	buttons.add_child(again_btn)

	_saved_label = _make_label("", 16, Color(0.85, 0.9, 1.0))
	_saved_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_saved_label.visible = false
	box.add_child(_saved_label)

	_game_over.add_child(panel)


func _make_chip(name_text: String, color: Color) -> PanelContainer:
	var chip := PanelContainer.new()
	chip.add_theme_stylebox_override("panel", _rounded(color, 18, color.darkened(0.25)))
	chip.custom_minimum_size = Vector2(170, 0)
	var m := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		m.add_theme_constant_override("margin_" + side, 12)
	chip.add_child(m)
	var vb := VBoxContainer.new()
	vb.alignment = BoxContainer.ALIGNMENT_CENTER
	m.add_child(vb)
	var value := _make_label("-", 30, INK)
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(value)
	var caption := _make_label(name_text, 15, INK.lerp(color.darkened(0.5), 0.5))
	caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(caption)
	_chip_values[name_text] = value
	return chip


func _make_button(text: String, color: Color) -> Button:
	var btn := Button.new()
	btn.text = text
	btn.add_theme_font_size_override("font_size", 24)
	btn.add_theme_color_override("font_color", INK)
	btn.add_theme_color_override("font_hover_color", INK)
	btn.add_theme_color_override("font_pressed_color", INK)
	btn.add_theme_stylebox_override("normal", _rounded(color, 16, color.darkened(0.3), 16, 10))
	btn.add_theme_stylebox_override("hover", _rounded(color.lightened(0.12), 16, color.darkened(0.3), 16, 10))
	btn.add_theme_stylebox_override("pressed", _rounded(color.darkened(0.12), 16, color.darkened(0.3), 16, 10))
	return btn


# --- Postcard (the baked, shareable image) -----------------------------------

func _build_postcard(image: Image, stats: Dictionary) -> void:
	if _pc_vp == null:
		_pc_vp = SubViewport.new()
		_pc_vp.size = POSTCARD_SIZE
		_pc_vp.transparent_bg = false
		_pc_vp.disable_3d = true
		_pc_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		add_child(_pc_vp)

		var root := Control.new()
		root.size = POSTCARD_SIZE
		_pc_vp.add_child(root)

		var paper := ColorRect.new()
		paper.color = CREAM
		paper.size = POSTCARD_SIZE
		root.add_child(paper)

		_pc_photo = TextureRect.new()
		_pc_photo.position = Vector2(PC_PAD, PC_PAD)
		_pc_photo.size = Vector2(POSTCARD_SIZE.x - 2 * PC_PAD, POSTCARD_SIZE.y - PC_PAD - PC_CAPTION_H)
		_pc_photo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		_pc_photo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		_pc_photo.clip_contents = true
		root.add_child(_pc_photo)

		# Title banner across the top of the photo.
		var banner_bg := ColorRect.new()
		banner_bg.color = Color(0.16, 0.15, 0.22, 0.55)
		banner_bg.position = Vector2(PC_PAD, PC_PAD)
		banner_bg.size = Vector2(POSTCARD_SIZE.x - 2 * PC_PAD, 66)
		root.add_child(banner_bg)
		_pc_banner = _make_label("GREETINGS FROM MT. MULE", 34, CREAM)
		_pc_banner.position = banner_bg.position
		_pc_banner.size = banner_bg.size
		_pc_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_pc_banner.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		root.add_child(_pc_banner)

		# A little postage stamp in the corner, for charm.
		var stamp := ColorRect.new()
		stamp.color = TANGERINE
		stamp.position = Vector2(POSTCARD_SIZE.x - PC_PAD - 86, PC_PAD + 14)
		stamp.size = Vector2(72, 86)
		root.add_child(stamp)
		var stamp_label := _make_label("MULE\nMAIL", 18, INK)
		stamp_label.position = stamp.position
		stamp_label.size = stamp.size
		stamp_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		stamp_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		root.add_child(stamp_label)

		# Caption strip (the cream band below the photo).
		var cap_y := POSTCARD_SIZE.y - PC_CAPTION_H
		_pc_big = _make_label("MT. MULE", 44, INK)
		_pc_big.position = Vector2(PC_PAD + 8, cap_y + 6)
		root.add_child(_pc_big)
		_pc_caption = _make_label("", 26, TANGERINE.darkened(0.25))
		_pc_caption.position = Vector2(PC_PAD + 10, cap_y + 76)
		root.add_child(_pc_caption)

	if image != null:
		_pc_photo.texture = ImageTexture.create_from_image(image)
	_pc_caption.text = "%.1f M HIGH   ·   %d THINGS STACKED   ·   %d KG HAULED" % [
			float(stats["height"]), int(stats["objects"]), int(round(float(stats["weight"])))]


func _on_save_pressed() -> void:
	# Make sure the postcard has rendered, then grab and write it.
	await RenderingServer.frame_post_draw
	var img := _pc_vp.get_texture().get_image()
	var dir := OS.get_system_dir(OS.SYSTEM_DIR_PICTURES)
	if dir.is_empty():
		dir = OS.get_user_data_dir()
	var path := dir.path_join("PackMule_%d.png" % int(Time.get_unix_time_from_system()))
	var err := img.save_png(path)
	if err == OK:
		_saved_label.text = "SAVED TO  %s" % path
	else:
		_saved_label.text = "COULD NOT SAVE (error %d)" % err
	_saved_label.visible = true


# --- Small style helpers -----------------------------------------------------

func _make_label(text: String, size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	return label


func _rounded(bg: Color, radius: int, border: Color, pad_x := 0, pad_y := 0) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.set_corner_radius_all(radius)
	if border.a > 0.0:
		sb.set_border_width_all(3)
		sb.border_color = border
	if pad_x > 0:
		sb.content_margin_left = pad_x
		sb.content_margin_right = pad_x
	if pad_y > 0:
		sb.content_margin_top = pad_y
		sb.content_margin_bottom = pad_y
	return sb
