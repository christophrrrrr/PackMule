class_name GameHud
extends CanvasLayer

## All UI: the main menu, the in-game readouts, and the game-over "postcard"
## screen — one playful cartoon style (rounded panels, the Luckiest Guy font,
## bright colors) shared across all three.

signal restart_requested
signal start_requested
signal wheel_landed(modifier: Dictionary)

# Cartoon palette.
const CREAM := Color(0.98, 0.96, 0.89)
const INK := Color(0.16, 0.15, 0.22)
const PANEL_BG := Color(0.16, 0.17, 0.30, 0.94)
const SUNNY := Color(1.0, 0.83, 0.22)
const SKY := Color(0.36, 0.74, 1.0)
const LEAF := Color(0.42, 0.80, 0.36)
const TANGERINE := Color(1.0, 0.55, 0.21)

const HINT_TEXT := "WASD + MOUSE TO FLY   ·   Q / E ROTATE   ·   R TIP   ·   LMB PLACE   ·   TAB SPIN WHEEL   ·   ESC FREE CURSOR"
const POSTCARD_SIZE := Vector2i(1024, 686)  # photo area below is 16:9
const PC_PAD := 22
const PC_CAPTION_H := 88

@onready var _crosshair: Label = $Crosshair
@onready var _wheel: ModifierWheel = $WheelOverlay
@onready var _game_over: CenterContainer = $GameOverPanel

# In-game readouts (built in code).
var _score: Label
var _height: Label
var _strikes: Label
var _modifier: Label
var _incoming: Label
var _stats_box: PanelContainer
var _incoming_box: PanelContainer
var _hint_box: PanelContainer

# Main menu.
var _menu: CenterContainer

# Game-over panel.
var _go_built := false
var _go_panel: PanelContainer
var _go_title: Label
var _go_subtitle: Label
var _pc_display: TextureRect
var _saved_label: Label
var _chip_values := {}

# Postcard SubViewport (the shareable, baked image).
var _pc_vp: SubViewport
var _pc_photo: TextureRect
var _pc_caption: Label


func _ready() -> void:
	_game_over.visible = false
	_wheel.landed.connect(func(modifier: Dictionary) -> void: wheel_landed.emit(modifier))
	_build_in_game_hud()


# --- In-game readouts --------------------------------------------------------

func _build_in_game_hud() -> void:
	_stats_box = PanelContainer.new()
	_stats_box.add_theme_stylebox_override("panel", _rounded(PANEL_BG, 16, Color(0, 0, 0, 0), 14, 10))
	_stats_box.position = Vector2(16, 14)
	var sbox := VBoxContainer.new()
	sbox.add_theme_constant_override("separation", 2)
	_stats_box.add_child(sbox)
	_score = _make_label("SCORE: 0", 28, SUNNY)
	_height = _make_label("HEIGHT: 0.0 m", 18, SKY)
	_strikes = _make_label("FALLEN: 0 / 3", 18, TANGERINE)
	_modifier = _make_label("MODIFIER: -   (TAB: SPIN)", 15, CREAM)
	for n in [_score, _height, _strikes, _modifier]:
		sbox.add_child(n)
	add_child(_stats_box)

	_incoming_box = PanelContainer.new()
	_incoming_box.add_theme_stylebox_override("panel", _rounded(SUNNY, 16, SUNNY.darkened(0.3), 18, 6))
	_incoming_box.anchor_left = 0.5
	_incoming_box.anchor_right = 0.5
	_incoming_box.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_incoming_box.offset_top = 14
	_incoming = _make_label("", 24, INK)
	_incoming_box.add_child(_incoming)
	add_child(_incoming_box)

	_hint_box = PanelContainer.new()
	_hint_box.add_theme_stylebox_override("panel", _rounded(Color(0, 0, 0, 0.38), 12, Color(0, 0, 0, 0), 16, 6))
	_hint_box.anchor_left = 0.5
	_hint_box.anchor_right = 0.5
	_hint_box.anchor_top = 1.0
	_hint_box.anchor_bottom = 1.0
	_hint_box.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_hint_box.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_hint_box.offset_top = -38
	_hint_box.offset_bottom = -8
	var hint := _make_label(HINT_TEXT, 14, CREAM)
	_hint_box.add_child(hint)
	add_child(_hint_box)


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
	_incoming_box.visible = not text.is_empty()


func set_crosshair(shown: bool) -> void:
	_crosshair.visible = shown


## Hides every in-game readout so the tower photo is captured clean.
func set_in_game_hud_visible(shown: bool) -> void:
	for node in [_stats_box, _incoming_box, _hint_box, _crosshair]:
		node.visible = shown


# --- Main menu ---------------------------------------------------------------

func show_main_menu() -> void:
	if _menu == null:
		_build_main_menu()
	set_in_game_hud_visible(false)
	_menu.visible = true


func hide_main_menu() -> void:
	if _menu != null:
		_menu.visible = false


func _build_main_menu() -> void:
	_menu = CenterContainer.new()
	_menu.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_menu)

	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _rounded(PANEL_BG, 30, SUNNY, 48, 40))
	_menu.add_child(panel)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 16)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	panel.add_child(box)

	var title := _make_label("PACK MULE", 80, SUNNY)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_color_override("font_outline_color", INK)
	title.add_theme_constant_override("outline_size", 14)
	box.add_child(title)

	var tagline := _make_label("STACK RIDICULOUS THINGS. DON'T LOOK DOWN.", 20, CREAM)
	tagline.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(tagline)

	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 10)
	box.add_child(spacer)

	var play := _make_button("PLAY", LEAF)
	play.add_theme_font_size_override("font_size", 34)
	play.pressed.connect(func() -> void: start_requested.emit())
	box.add_child(play)

	var quit := _make_button("QUIT", Color(0.55, 0.55, 0.62))
	quit.pressed.connect(func() -> void: get_tree().quit())
	box.add_child(quit)

	var controls := _make_label(HINT_TEXT, 14, Color(0.8, 0.83, 0.92))
	controls.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(controls)


# --- Game-over panel ---------------------------------------------------------

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
	_pop_in_panel()


## A quick scale-in so the game-over panel lands with some bounce. Runs on
## unscaled time because the scene is frozen (Engine.time_scale = 0).
func _pop_in_panel() -> void:
	await get_tree().process_frame  # let the panel get its size
	_go_panel.pivot_offset = _go_panel.size / 2.0
	_go_panel.scale = Vector2(0.85, 0.85)
	var tw := create_tween().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.set_ignore_time_scale(true)
	tw.tween_property(_go_panel, "scale", Vector2.ONE, 0.35)


func _build_game_over_ui() -> void:
	var panel := PanelContainer.new()
	_go_panel = panel
	panel.add_theme_stylebox_override("panel", _rounded(PANEL_BG, 30, SUNNY))

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

	_pc_display = TextureRect.new()
	_pc_display.custom_minimum_size = Vector2(460, 460 * POSTCARD_SIZE.y / POSTCARD_SIZE.x)
	_pc_display.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_pc_display.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	box.add_child(_pc_display)

	var chips := HBoxContainer.new()
	chips.add_theme_constant_override("separation", 14)
	chips.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_child(chips)
	chips.add_child(_make_chip("HEIGHT", SKY))
	chips.add_child(_make_chip("OBJECTS", LEAF))
	chips.add_child(_make_chip("WEIGHT", TANGERINE))

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
		# FIT (not cover) so the whole framed shot shows — never crop a piece.
		_pc_photo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		_pc_photo.clip_contents = true
		root.add_child(_pc_photo)

		# Caption band: just the run's stats, centered.
		_pc_caption = _make_label("", 32, INK)
		_pc_caption.position = Vector2(PC_PAD, POSTCARD_SIZE.y - PC_CAPTION_H)
		_pc_caption.size = Vector2(POSTCARD_SIZE.x - 2 * PC_PAD, PC_CAPTION_H)
		_pc_caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_pc_caption.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		root.add_child(_pc_caption)

	if image != null:
		_pc_photo.texture = ImageTexture.create_from_image(image)
	_pc_caption.text = "%.1f M  ·  %d OBJECTS  ·  %d KG" % [
			float(stats["height"]), int(stats["objects"]), int(round(float(stats["weight"])))]


func _on_save_pressed() -> void:
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


func _make_button(text: String, color: Color) -> Button:
	var btn := Button.new()
	btn.text = text
	btn.add_theme_font_size_override("font_size", 24)
	for c in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		btn.add_theme_color_override(c, INK)
	btn.add_theme_stylebox_override("normal", _rounded(color, 16, color.darkened(0.3), 18, 10))
	btn.add_theme_stylebox_override("hover", _rounded(color.lightened(0.12), 16, color.darkened(0.3), 18, 10))
	btn.add_theme_stylebox_override("pressed", _rounded(color.darkened(0.12), 16, color.darkened(0.3), 18, 10))
	btn.add_theme_stylebox_override("focus", _rounded(Color(0, 0, 0, 0), 16, CREAM, 18, 10))
	return btn


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
