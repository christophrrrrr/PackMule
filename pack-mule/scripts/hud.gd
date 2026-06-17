class_name GameHud
extends CanvasLayer

## All UI: the main menu, the in-game readouts, and the game-over "postcard"
## screen — one playful cartoon style (rounded panels, the Luckiest Guy font,
## bright colors) shared across all three.

signal restart_requested
signal start_requested
signal to_main_menu_requested
signal photo_enter_requested
signal photo_to_pause_requested
signal cash_out_requested
signal wheel_landed(modifier: Dictionary)
signal skin_changed              # the equipped saddle skin changed (live recolor)
signal base_changed              # the equipped mount changed (live model swap)
signal place_requested           # mobile PLACE button (mirrors LMB)
signal tip_requested             # mobile TIP button (mirrors R)
signal spin_requested            # mobile SPIN button (mirrors Tab)

# Cartoon palette.
const CREAM := Color(0.98, 0.96, 0.89)
const INK := Color(0.16, 0.15, 0.22)
const PANEL_BG := Color(0.16, 0.17, 0.30, 0.94)
const SUNNY := Color(1.0, 0.83, 0.22)
const SKY := Color(0.36, 0.74, 1.0)
const LEAF := Color(0.42, 0.80, 0.36)
const TANGERINE := Color(1.0, 0.55, 0.21)

const HINT_TEXT := "WASD + MOUSE TO FLY   ·   Q / E ROTATE   ·   R TIP   ·   LMB PLACE   ·   TAB SPIN WHEEL   ·   C PHOTO   ·   ESC PAUSE"
const MOBILE_HINT_TEXT := "LEFT STICK: FLY   ·   DRAG THE SCREEN: LOOK AROUND"
const JOY_SIZE := 220             # virtual joystick base diameter (px)
const JOY_KNOB := 96              # joystick knob diameter (px)
const JOY_RADIUS := 62.0          # how far the knob travels from center: (SIZE-KNOB)/2
const POSTCARD_SIZE := Vector2i(1024, 686)  # photo area below is 16:9
const PC_PAD := 22
const PC_CAPTION_H := 88
const GALLERY_DIR := "user://gallery"
const GALLERY_MAX := 20
const CREDITS_CLIP_H := 456.0

@onready var _crosshair: Label = $Crosshair
@onready var _wheel: ModifierWheel = $WheelOverlay
@onready var _game_over: CenterContainer = $GameOverPanel

# In-game readouts (built in code).
var _money: Label                 # banked, safe money — the big satisfying counter
var _money_shown := 0.0           # value currently displayed (for count-up tween)
var _money_tween: Tween
var _height: Label
var _strikes: Label
var _modifier: Label
var _incoming: Label
var _stats_box: PanelContainer
var _incoming_box: PanelContainer
var _hint_box: PanelContainer
var _cashout: Label
var _cashout_box: PanelContainer

# Main menu, gallery, settings.
var _menu: CenterContainer
var _gallery: CenterContainer
var _gallery_photo: TextureRect
var _gallery_counter: Label
var _gallery_files: PackedStringArray
var _gallery_index := 0
var _settings: CenterContainer
var _settings_return: CenterContainer  # panel to show when leaving settings
var _odds_return: CenterContainer      # panel to show when leaving odds
var _side: VBoxContainer                # corner How-to / Credits buttons
var _howto: CenterContainer
var _credits: CenterContainer
var _credits_scroll: Control           # the moving credits roll
var _credits_y := 0.0
var _menu_best: Label                   # the menu's best-height / wallet line
var _menu_daily: Label                  # the menu's daily-challenge line
var _shop: CenterContainer
var _shop_tabs: HBoxContainer           # category tab buttons
var _shop_body: VBoxContainer           # the rebuilt item rows for the active tab
var _shop_wallet: Label                 # the shop's live wallet readout
var _shop_tab := "mounts"               # active category: mounts / skins
var _listening := ""              # action currently waiting for a new key
var _listening_btn: Button
var _bind_buttons := {}

# Pause.
var _pause: CenterContainer
var _in_run := false              # a run is active (pausable)
var _paused := false

# Mobile on-screen controls (touch build only).
var _is_mobile := false
var _mobile_controls: Control     # holder for the in-run touch buttons
var _mobile_photo: Control        # SNAP / DONE overlay shown in photo mode
var _cash_btn: Button             # cash-out button (enabled when banking is ready)
var _rot_dir := 0.0               # held rotate buttons: +1 left / -1 right / 0
var _vert_dir := 0.0              # held up/down buttons: +1 up / -1 down / 0
var _joy_base: Panel              # fixed move joystick (bottom-left)
var _joy_knob: Panel              # the draggable knob
var _joy_active := -1             # touch index driving the stick (-2 = mouse, desktop test)
var _joy_vec := Vector2.ZERO      # current stick vector, x=right y=up(forward), -1..1

# Odds, overlays, photo mode.
var _odds: CenterContainer
var _odds_pct := {}               # entry name -> percent Label
var _flash: ColorRect
var _fade: ColorRect                    # black curtain for scene transitions
var _record_banner: Label
var _photo := false
var _photo_hint: Label

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
	# The HUD keeps running while the tree is paused so the pause menu works;
	# the wheel still pauses with the game.
	process_mode = Node.PROCESS_MODE_ALWAYS
	_is_mobile = GameSettings.is_mobile()
	_game_over.visible = false
	_wheel.process_mode = Node.PROCESS_MODE_PAUSABLE
	_wheel.landed.connect(func(modifier: Dictionary) -> void: wheel_landed.emit(modifier))
	_build_in_game_hud()
	if _is_mobile:
		_crosshair.add_theme_font_size_override("font_size", 30)  # easier to see on a phone
		# The readouts are non-interactive on mobile; let touches pass through to
		# the orbit camera so a drag started anywhere (even on the crosshair or a
		# readout panel) still rotates the view. Only the buttons capture taps.
		for node in [_stats_box, _incoming_box, _hint_box, _cashout_box, _crosshair]:
			node.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_build_mobile_controls()
	_build_overlays()
	_build_fade()
	fade_in()  # every scene starts black and fades in (hides reload hitches)


# --- Scene transition (fade to/from black) ----------------------------------

## A black curtain on top of everything, used to smooth scene reloads and
## state switches. Starts opaque so the first frame fades in from black.
func _build_fade() -> void:
	_fade = ColorRect.new()
	_fade.color = Color(0, 0, 0, 1)
	_fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fade.z_index = RenderingServer.CANVAS_ITEM_Z_MAX  # above all HUD/menus
	add_child(_fade)


## Reveal the scene (transparent). Non-blocking.
func fade_in() -> void:
	if _fade == null:
		return
	_fade.color.a = 1.0
	var tw := create_tween()  # bound to the HUD (PROCESS_MODE_ALWAYS), so it
	tw.set_ignore_time_scale(true)  # runs even while paused / time-frozen
	tw.tween_property(_fade, "color:a", 0.0, 0.3)


## Cover the screen with black. Await this before reloading/switching.
func fade_out() -> void:
	if _fade == null:
		return
	_fade.color.a = 0.0
	var tw := create_tween()
	tw.set_ignore_time_scale(true)
	tw.tween_property(_fade, "color:a", 1.0, 0.3)
	await tw.finished


## Full-screen lightning flash + the big record banner (both hidden).
func _build_overlays() -> void:
	_flash = ColorRect.new()
	_flash.color = Color(1, 1, 1, 0)
	_flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_flash)

	_record_banner = _make_label("NEW RECORD!", 56, SUNNY)
	_record_banner.set_anchors_preset(Control.PRESET_CENTER)
	_record_banner.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_record_banner.grow_vertical = Control.GROW_DIRECTION_BOTH
	_record_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_record_banner.add_theme_color_override("font_outline_color", INK)
	_record_banner.add_theme_constant_override("outline_size", 12)
	_record_banner.modulate.a = 0.0
	_record_banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_record_banner)


## Lightning: a quick white flash with a flicker.
func flash() -> void:
	var tw := create_tween()
	tw.tween_property(_flash, "color:a", 0.7, 0.04)
	tw.tween_property(_flash, "color:a", 0.0, 0.12)
	tw.tween_property(_flash, "color:a", 0.5, 0.05)
	tw.tween_property(_flash, "color:a", 0.0, 0.3)


## A brief centered banner for one-off messages (e.g. the Safety Rope save).
func toast(text: String, color: Color = SUNNY) -> void:
	_record_banner.text = text
	_record_banner.add_theme_color_override("font_color", color)
	_record_banner.add_theme_font_size_override("font_size", 44)
	_banner_pop()


## Big "NEW RECORD!" celebration when this run beats the all-time best.
func celebrate_record() -> void:
	_record_banner.text = "NEW RECORD!"
	_record_banner.add_theme_color_override("font_color", SUNNY)
	_record_banner.add_theme_font_size_override("font_size", 56)
	_banner_pop()


func _banner_pop() -> void:
	_record_banner.modulate.a = 1.0
	_record_banner.scale = Vector2(0.5, 0.5)
	_record_banner.pivot_offset = _record_banner.size / 2.0
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(_record_banner, "scale", Vector2.ONE, 0.5).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(_record_banner, "modulate:a", 0.0, 2.0).set_delay(1.2)


## A run is active (so Esc should pause). Cleared at game over / main menu.
func set_in_run(value: bool) -> void:
	_in_run = value
	if not value:
		_paused = false


# --- In-game readouts --------------------------------------------------------

func _build_in_game_hud() -> void:
	_stats_box = PanelContainer.new()
	_stats_box.add_theme_stylebox_override("panel", _rounded(PANEL_BG, 16, Color(0, 0, 0, 0), 14, 10))
	_stats_box.position = Vector2(16, 14)
	var sbox := VBoxContainer.new()
	sbox.add_theme_constant_override("separation", 2)
	_stats_box.add_child(sbox)
	_money = _make_label("$0", 40, SUNNY)
	_money.add_theme_color_override("font_outline_color", INK)
	_money.add_theme_constant_override("outline_size", 6)
	_height = _make_label("HEIGHT: 0.0 m", 18, SKY)
	_strikes = _make_label("FALLEN: 0 / 3", 18, TANGERINE)
	_modifier = _make_label("MODIFIER: -   (TAB: SPIN)", 15, CREAM)
	for n in [_money, _height, _strikes, _modifier]:
		sbox.add_child(n)
	add_child(_stats_box)

	# The cash-out gamble: pending pot + live multiplier, always in view.
	_cashout_box = PanelContainer.new()
	_cashout_box.add_theme_stylebox_override("panel", _rounded(LEAF, 18, LEAF.darkened(0.3), 20, 12))
	_cashout_box.anchor_left = 1.0
	_cashout_box.anchor_right = 1.0
	_cashout_box.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_cashout_box.offset_left = -16
	# On mobile the pause button sits in the top-right corner; drop the pot below it.
	_cashout_box.offset_top = 96 if _is_mobile else 14
	_cashout_box.offset_right = -16
	_cashout = _make_label("", 22, INK)
	_cashout.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_cashout_box.add_child(_cashout)
	_cashout_box.modulate = Color(1, 1, 1, 0.4)  # dimmed until banking is allowed
	add_child(_cashout_box)

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
	var hint := _make_label(MOBILE_HINT_TEXT if _is_mobile else HINT_TEXT, 14, CREAM)
	_hint_box.add_child(hint)
	add_child(_hint_box)


func spin_wheel() -> void:
	_wheel.spin()


func wheel_busy() -> bool:
	return _wheel.is_busy()


## The big banked-money counter. Sets it instantly (used on refresh / reset).
func set_money(banked: int) -> void:
	_money_shown = float(banked)
	_money.text = "$%s" % _money_str(banked)


## The cash-out pill: what you'd bank now and the live multiplier. On mobile
## it's a readout (the action lives on the CASH OUT button), so it's labelled
## POT and drops the keyboard hint; on desktop it shows the cash-out key.
func set_pending(pending: int, mult: float) -> void:
	if _is_mobile:
		_cashout.text = "POT  $%s\n×%s" % [_money_str(pending), _mult_str(mult)]
	else:
		_cashout.text = "CASH OUT  $%s\n×%s   [%s]" % [
				_money_str(pending), _mult_str(mult), GameSettings.binding_text("pm_cashout")]
	_punch(_cashout_box, 1.12)


## Dim the cash-out pill when banking isn't allowed (pieces still falling,
## or nothing to bank) so it's clear it's only available between placements.
func set_cashout_ready(ready: bool) -> void:
	_cashout_box.modulate = Color(1, 1, 1, 1.0) if ready else Color(1, 1, 1, 0.4)
	if _cash_btn != null:
		_cash_btn.disabled = not ready


## Cash out! Count the banked money up to its new total and punch it.
func bank_flourish(new_banked: int, _amount: int) -> void:
	if _money_tween != null and _money_tween.is_valid():
		_money_tween.kill()
	_money_tween = create_tween()
	_money_tween.tween_method(_set_money_display, _money_shown, float(new_banked), 0.55) \
			.set_trans(Tween.TRANS_QUAD)
	_punch(_money, 1.4)


func _set_money_display(v: float) -> void:
	_money_shown = v
	_money.text = "$%s" % _money_str(int(v))


## A quick scale-punch for juicy feedback.
func _punch(node: Control, amount := 1.25) -> void:
	node.pivot_offset = node.size / 2.0
	node.scale = Vector2(amount, amount)
	create_tween().tween_property(node, "scale", Vector2.ONE, 0.25) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


## 1240 -> "1,240".
func _money_str(n: int) -> String:
	var s := str(absi(n))
	var out := ""
	var c := 0
	for i in range(s.length() - 1, -1, -1):
		out = s[i] + out
		c += 1
		if c % 3 == 0 and i > 0:
			out = "," + out
	return ("-" if n < 0 else "") + out


func _mult_str(mult: float) -> String:
	return "%d" % int(mult) if mult == floor(mult) else "%.1f" % mult


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
	for node in [_stats_box, _incoming_box, _hint_box, _crosshair, _cashout_box,
			_mobile_controls]:
		if node != null:
			node.visible = shown
	if not shown and _is_mobile:
		_release_joy()  # don't keep flying while the cluster is hidden
		_rot_dir = 0.0
		_vert_dir = 0.0


# --- Mobile on-screen controls ----------------------------------------------

## How far the held rotate buttons are turning the ghost: +1 left, -1 right, 0
## none. Polled each frame by the game manager (mirrors holding Q/E).
func rotate_dir() -> float:
	return _rot_dir


## How the held up/down buttons drive vertical fly: +1 up, -1 down, 0 none.
## Polled by the camera rig each frame.
func vert_dir() -> float:
	return _vert_dir


## Builds the in-run touch controls: a big PLACE plus rotate/tip on the right
## (right thumb), spin/cash-out on the left (left thumb), and a pause button in
## the top-right corner. The holder ignores the mouse so drags on empty space
## still reach the orbit camera; only the buttons themselves capture taps.
func _build_mobile_controls() -> void:
	_mobile_controls = Control.new()
	_mobile_controls.set_anchors_preset(Control.PRESET_FULL_RECT)
	_mobile_controls.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_mobile_controls.visible = false
	add_child(_mobile_controls)

	# Right thumb: big PLACE in the corner, rotate/tip in a row just above it.
	var place := _make_button("PLACE", LEAF)
	place.custom_minimum_size = Vector2(240, 150)
	place.add_theme_font_size_override("font_size", 44)
	place.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	place.offset_left = -264
	place.offset_top = -174
	place.offset_right = -24
	place.offset_bottom = -24
	place.pressed.connect(func() -> void: place_requested.emit())
	_mobile_controls.add_child(place)

	var right_row := HBoxContainer.new()
	right_row.add_theme_constant_override("separation", 14)
	right_row.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	right_row.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	right_row.grow_vertical = Control.GROW_DIRECTION_BEGIN
	right_row.offset_left = -264
	right_row.offset_top = -320
	right_row.offset_right = -24
	right_row.offset_bottom = -186
	_mobile_controls.add_child(right_row)
	# Curved (rotation) arrows so it's clear these spin the OBJECT, not move you.
	var rot_l := _icon_button(SKY, "spin_ccw")
	rot_l.button_down.connect(func() -> void: _rot_dir = 1.0)
	rot_l.button_up.connect(func() -> void: _rot_dir = 0.0)
	right_row.add_child(rot_l)
	var rot_r := _icon_button(SKY, "spin_cw")
	rot_r.button_down.connect(func() -> void: _rot_dir = -1.0)
	rot_r.button_up.connect(func() -> void: _rot_dir = 0.0)
	right_row.add_child(rot_r)
	var tip := _round_touch_button("TIP", TANGERINE)
	tip.pressed.connect(func() -> void: tip_requested.emit())
	right_row.add_child(tip)

	# Top center (under the INCOMING banner): cash out + spin. Keeping them off
	# the bottom-left leaves that whole side free for the left-hand move drag.
	var top_row := HBoxContainer.new()
	top_row.add_theme_constant_override("separation", 16)
	top_row.set_anchors_preset(Control.PRESET_CENTER_TOP)
	top_row.grow_horizontal = Control.GROW_DIRECTION_BOTH
	top_row.offset_top = 78
	_mobile_controls.add_child(top_row)
	_cash_btn = _make_button("CASH OUT", SUNNY)
	_cash_btn.custom_minimum_size = Vector2(200, 78)
	_cash_btn.disabled = true
	_cash_btn.pressed.connect(func() -> void: cash_out_requested.emit())
	top_row.add_child(_cash_btn)
	var spin := _make_button("SPIN", Color(0.78, 0.5, 1.0))
	spin.custom_minimum_size = Vector2(160, 78)
	spin.pressed.connect(func() -> void: spin_requested.emit())
	top_row.add_child(spin)

	# Top-right corner: pause.
	var pause := _make_button("PAUSE", Color(0.5, 0.5, 0.58))
	pause.custom_minimum_size = Vector2(150, 72)
	pause.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	pause.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	pause.offset_left = -166
	pause.offset_top = 14
	pause.offset_right = -16
	pause.pressed.connect(_toggle_pause)
	_mobile_controls.add_child(pause)

	# Bottom-left: a fixed virtual joystick to fly around. It captures its own
	# touch (the rest of the screen is the look drag, handled by the camera rig).
	_joy_base = Panel.new()
	_joy_base.add_theme_stylebox_override("panel",
			_rounded(Color(0.1, 0.12, 0.2, 0.4), JOY_SIZE / 2, Color(1, 1, 1, 0.45)))
	_joy_base.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_joy_base.grow_horizontal = Control.GROW_DIRECTION_END
	_joy_base.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_joy_base.offset_left = 40
	_joy_base.offset_top = -(JOY_SIZE + 40)
	_joy_base.offset_right = JOY_SIZE + 40
	_joy_base.offset_bottom = -40
	_joy_base.gui_input.connect(_on_joystick_input)
	_mobile_controls.add_child(_joy_base)
	_joy_knob = Panel.new()
	_joy_knob.add_theme_stylebox_override("panel",
			_rounded(Color(0.95, 0.97, 1.0, 0.8), JOY_KNOB / 2, Color(0, 0, 0, 0.3)))
	_joy_knob.mouse_filter = Control.MOUSE_FILTER_IGNORE  # visual only
	_joy_knob.size = Vector2(JOY_KNOB, JOY_KNOB)
	_joy_base.add_child(_joy_knob)
	_release_joy()  # center the knob

	# Just right of the joystick: straight up / down fly buttons (held).
	var vert_col := VBoxContainer.new()
	vert_col.add_theme_constant_override("separation", 12)
	vert_col.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	vert_col.grow_vertical = Control.GROW_DIRECTION_BEGIN
	vert_col.offset_left = JOY_SIZE + 60
	vert_col.offset_bottom = -78
	_mobile_controls.add_child(vert_col)
	var up_btn := _icon_button(Color(0.5, 0.6, 0.78), "up")
	up_btn.button_down.connect(func() -> void: _vert_dir = 1.0)
	up_btn.button_up.connect(func() -> void: _vert_dir = 0.0)
	vert_col.add_child(up_btn)
	var down_btn := _icon_button(Color(0.5, 0.6, 0.78), "down")
	down_btn.button_down.connect(func() -> void: _vert_dir = -1.0)
	down_btn.button_up.connect(func() -> void: _vert_dir = 0.0)
	vert_col.add_child(down_btn)

	# Photo-mode overlay (separate, since the cluster above is hidden in photo
	# mode): SNAP on the right, DONE on the left. Without these a touch player
	# would be stuck — there is no [P]/[Esc] to snap or leave.
	_mobile_photo = Control.new()
	_mobile_photo.set_anchors_preset(Control.PRESET_FULL_RECT)
	_mobile_photo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_mobile_photo.visible = false
	add_child(_mobile_photo)
	var snap := _make_button("SNAP", LEAF)
	snap.custom_minimum_size = Vector2(220, 110)
	snap.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	snap.offset_left = -244
	snap.offset_top = -134
	snap.offset_right = -24
	snap.offset_bottom = -24
	snap.pressed.connect(_snap_photo)
	_mobile_photo.add_child(snap)
	var done := _make_button("DONE", Color(0.5, 0.5, 0.58))
	done.custom_minimum_size = Vector2(220, 110)
	done.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	done.offset_left = 24
	done.offset_top = -134
	done.offset_right = 244
	done.offset_bottom = -24
	done.pressed.connect(_photo_to_pause)
	_mobile_photo.add_child(done)


## A chunky square touch button for the rotate/tip/pause cluster.
func _round_touch_button(text: String, color: Color) -> Button:
	var btn := _make_button(text, color)
	btn.custom_minimum_size = Vector2(96, 96)
	return btn


## A chunky square button whose face is a vector icon (no font glyphs, so it
## renders identically everywhere). `kind`: spin_ccw / spin_cw (curved rotation
## arrows) or up / down (movement triangles).
func _icon_button(color: Color, kind: String) -> Button:
	var btn := _make_button("", color)
	btn.custom_minimum_size = Vector2(96, 96)
	var icon := Control.new()
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE  # the button under it takes the press
	icon.set_anchors_preset(Control.PRESET_FULL_RECT)
	icon.draw.connect(_draw_icon.bind(icon, kind))
	btn.add_child(icon)
	return btn


func _draw_icon(icon: Control, kind: String) -> void:
	var sz := icon.size
	if sz.x < 1.0:
		return
	var c := sz * 0.5
	if kind == "up" or kind == "down":
		var s := minf(sz.x, sz.y) * 0.24
		var up := kind == "up"
		var tip_y := -s if up else s    # screen y is down: up = tip above center
		var base_y := s if up else -s
		icon.draw_colored_polygon(PackedVector2Array([
				c + Vector2(0.0, tip_y),
				c + Vector2(-s, base_y),
				c + Vector2(s, base_y)]), INK)
		return
	# Curved rotation arrow: a ~250° arc with an arrowhead at the leading tip.
	var cw := kind == "spin_cw"
	var r := minf(sz.x, sz.y) * 0.26
	var w := maxf(4.0, r * 0.32)
	var a0 := deg_to_rad(140.0)
	var a1 := deg_to_rad(140.0 + 250.0)
	icon.draw_arc(c, r, a0, a1, 48, INK, w, true)
	var ang := a1 if cw else a0
	var dirsign := 1.0 if cw else -1.0
	var on := c + Vector2(cos(ang), sin(ang)) * r
	var tang := Vector2(-sin(ang), cos(ang)) * dirsign
	var perp := Vector2(-tang.y, tang.x)
	var hs := r * 0.85
	icon.draw_colored_polygon(PackedVector2Array([
			on + tang * hs,
			on + perp * hs * 0.55,
			on - perp * hs * 0.55]), INK)


## Let touch drags fall through a subtree (labels, panels) to an ancestor
## ScrollContainer, so a list scrolls even when the finger starts on a row —
## buttons keep MOUSE_FILTER_STOP so taps still register. Mobile scroll fix.
func _pass_touches(node: Node) -> void:
	if node is Control and not (node is BaseButton):
		(node as Control).mouse_filter = Control.MOUSE_FILTER_PASS
	for c in node.get_children():
		_pass_touches(c)


# --- Move joystick (mobile) --------------------------------------------------

## The current stick vector, polled by the camera rig each frame: x = right,
## y = up/forward, each in -1..1. Zero when the stick isn't being touched.
func move_vector() -> Vector2:
	return _joy_vec


## Drives the joystick from its own touches (real multitouch, so the look drag
## on the rest of the screen runs at the same time). Falls back to the mouse
## only on a non-touch device, for testing the touch build on desktop.
func _on_joystick_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		var t := event as InputEventScreenTouch
		if t.pressed and _joy_active == -1:
			_joy_active = t.index
			_set_joy_knob(t.position)
		elif not t.pressed and t.index == _joy_active:
			_release_joy()
	elif event is InputEventScreenDrag and (event as InputEventScreenDrag).index == _joy_active:
		_set_joy_knob((event as InputEventScreenDrag).position)
	elif not DisplayServer.is_touchscreen_available():
		if event is InputEventMouseButton and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
			if (event as InputEventMouseButton).pressed and _joy_active == -1:
				_joy_active = -2
				_set_joy_knob((event as InputEventMouseButton).position)
			elif not (event as InputEventMouseButton).pressed and _joy_active == -2:
				_release_joy()
		elif event is InputEventMouseMotion and _joy_active == -2:
			_set_joy_knob((event as InputEventMouseMotion).position)


## Moves the knob to a base-local point (clamped to the ring) and updates the
## stick vector. Screen Y is down, so it's flipped: dragging up = forward (+y).
func _set_joy_knob(local_pos: Vector2) -> void:
	var center := Vector2(JOY_SIZE, JOY_SIZE) * 0.5
	var off := (local_pos - center).limit_length(JOY_RADIUS)
	_joy_knob.position = center + off - Vector2(JOY_KNOB, JOY_KNOB) * 0.5
	_joy_vec = Vector2(off.x, -off.y) / JOY_RADIUS


## Recenter the knob and stop movement (finger up, or the HUD was hidden).
func _release_joy() -> void:
	_joy_active = -1
	_joy_vec = Vector2.ZERO
	if _joy_knob != null:
		_joy_knob.position = (Vector2(JOY_SIZE, JOY_SIZE) - Vector2(JOY_KNOB, JOY_KNOB)) * 0.5


# --- Main menu ---------------------------------------------------------------

func show_main_menu() -> void:
	if _menu == null:
		_build_main_menu()
	if _side == null:
		_build_side_buttons()
	# Make sure nothing lingers on top of the menu — e.g. the pause panel when
	# you choose Main Menu from a paused run, or the game-over panel.
	_paused = false
	_wheel.visible = false  # in case a spin was on screen when leaving a run
	for panel in [_pause, _settings, _gallery, _shop, _howto, _credits, _odds, _game_over]:
		if panel != null:
			panel.visible = false
	set_in_game_hud_visible(false)
	_menu_best.text = _menu_best_text()  # wallet may have grown since last shown
	refresh_daily()
	_menu.visible = true
	_side.visible = true
	Sfx.start_music()


func _menu_best_text() -> String:
	return "BEST  %.1f M   ·   WALLET  $%s" % [
			GameSettings.get_record(), _money_str(GameSettings.get_wallet())]


## Updates the menu's daily-challenge line (text + done/not-done color).
func refresh_daily() -> void:
	if _menu_daily == null:
		return
	var c := DailyChallenge.today()
	if GameSettings.daily_done():
		_menu_daily.text = "DAILY DONE!   %s" % c["text"]
		_menu_daily.add_theme_color_override("font_color", LEAF)
	else:
		_menu_daily.text = "TODAY'S CHALLENGE:   %s" % c["text"]
		_menu_daily.add_theme_color_override("font_color", SKY)


## Hide the game-over panel (used by the in-place restart).
func hide_game_over() -> void:
	_game_over.visible = false


func hide_main_menu() -> void:
	Sfx.stop_music()
	for panel in [_menu, _gallery, _settings, _pause, _side, _howto, _credits, _shop]:
		if panel != null:
			panel.visible = false


func _build_main_menu() -> void:
	_menu = CenterContainer.new()
	_menu.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_menu)

	# Tighten the menu on a phone so the whole panel (down to QUIT) fits the
	# shorter landscape screen — smaller title, padding, and row spacing.
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _rounded(PANEL_BG, 36, SUNNY,
			56 if _is_mobile else 80, 28 if _is_mobile else 64, 18))
	_menu.add_child(panel)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12 if _is_mobile else 20)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	panel.add_child(box)

	var title := _make_label("PACK MULE", 64 if _is_mobile else 104, SUNNY)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_color_override("font_outline_color", INK)
	title.add_theme_constant_override("outline_size", 18)
	box.add_child(title)

	var tagline := _make_label("STACK RIDICULOUS THINGS. DON'T LOOK DOWN.", 24, CREAM)
	tagline.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(tagline)

	_menu_best = _make_label(_menu_best_text(), 26, SUNNY)
	_menu_best.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_menu_best)

	_menu_daily = _make_label("", 20, SKY)
	_menu_daily.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_menu_daily)
	refresh_daily()

	box.add_child(_divider())

	var play := _make_button("PLAY", LEAF)
	play.add_theme_font_size_override("font_size", 48)
	play.custom_minimum_size = Vector2(440, 0)
	play.pressed.connect(func() -> void: start_requested.emit())
	box.add_child(play)

	var shop := _make_button("SHOP", SUNNY)
	shop.add_theme_font_size_override("font_size", 34)
	shop.custom_minimum_size = Vector2(440, 0)
	shop.pressed.connect(_open_shop)
	box.add_child(shop)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 20)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_child(row)
	var gallery_btn := _make_button("GALLERY", SKY)
	gallery_btn.custom_minimum_size = Vector2(210, 0)
	gallery_btn.pressed.connect(_open_gallery)
	row.add_child(gallery_btn)
	var settings_btn := _make_button("SETTINGS", TANGERINE)
	settings_btn.custom_minimum_size = Vector2(210, 0)
	settings_btn.pressed.connect(_open_settings.bind(null))
	row.add_child(settings_btn)

	var quit := _make_button("QUIT", Color(0.5, 0.5, 0.58))
	quit.pressed.connect(func() -> void: get_tree().quit())
	box.add_child(quit)

	# Desktop shows the keyboard cheat-sheet here; on mobile it's irrelevant
	# (and the controls are on-screen), so it's dropped to save vertical space.
	if not _is_mobile:
		var controls := _make_label(HINT_TEXT, 15, Color(0.8, 0.83, 0.92))
		controls.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		box.add_child(controls)


## A thin accent divider line for menu panels.
func _divider() -> Control:
	var line := ColorRect.new()
	line.color = Color(1, 1, 1, 0.12)
	line.custom_minimum_size = Vector2(0, 3)
	return line


# --- Side buttons (How to Play / Credits) ------------------------------------

func _build_side_buttons() -> void:
	_side = VBoxContainer.new()
	_side.add_theme_constant_override("separation", 10)
	_side.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_side.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_side.position = Vector2(24, -24)
	var howto_btn := _make_button("HOW TO PLAY", SKY)
	howto_btn.add_theme_font_size_override("font_size", 20)
	howto_btn.pressed.connect(_open_howto)
	_side.add_child(howto_btn)
	var credits_btn := _make_button("CREDITS", TANGERINE)
	credits_btn.add_theme_font_size_override("font_size", 20)
	credits_btn.pressed.connect(_open_credits)
	_side.add_child(credits_btn)
	add_child(_side)


# --- How to play -------------------------------------------------------------

func _open_howto() -> void:
	if _howto == null:
		_build_howto()
	_menu.visible = false
	_side.visible = false
	_howto.visible = true


func _build_howto() -> void:
	_howto = CenterContainer.new()
	_howto.set_anchors_preset(Control.PRESET_FULL_RECT)
	_howto.visible = false
	add_child(_howto)

	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _rounded(PANEL_BG, 36, SKY, 64, 48, 18))
	_howto.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 14)
	panel.add_child(box)

	var title := _make_label("HOW TO PLAY", 44 if _is_mobile else 60, SKY)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_color_override("font_outline_color", INK)
	title.add_theme_constant_override("outline_size", 10)
	box.add_child(title)
	box.add_child(_divider())

	var move_line := "RIGHT side: drag to aim (swing & tilt).  LEFT side: drag to move around and raise/lower.  Pinch to zoom.  < / > spin it, TIP tips it, PLACE drops it. Objects glue where they land." \
			if _is_mobile \
			else "WASD + mouse to fly. Aim with the crosshair, Q/E to spin, R to tip, Left-Click to place. Objects glue where they land."
	var wheel_line := "Tap SPIN for a modifier (Tiny, Massive, Heavy, Slippery, Super Glue...). It applies to the next object." \
			if _is_mobile \
			else "Press Tab to spin for a modifier (Tiny, Massive, Heavy, Slippery, Super Glue...). It applies to the next object."
	var cash_verb := "Tap CASH OUT" if _is_mobile else "Press Enter"
	var extras_line := "A golden item is a rare treat, and the tower's a record to beat." \
			if _is_mobile \
			else "C: photo mode  ·  Esc: pause. A golden item is a rare treat, and the tower's a record to beat."
	var lines := VBoxContainer.new()
	lines.add_theme_constant_override("separation", 14)
	lines.add_child(_howto_line("GOAL", "Stack the most ridiculous tower you can on the mule's red saddle. The higher you go, the more it's worth.", SUNNY))
	lines.add_child(_howto_line("MOVE & PLACE", move_line, LEAF))
	lines.add_child(_howto_line("THE WHEEL", wheel_line, TANGERINE))
	lines.add_child(_howto_line("CASH & MULTIPLIER", "Every piece you place pays out at a multiplier that climbs the longer you go (×1, ×1.5, ×2, ×3...). %s to bank the money and reset the multiplier to ×1." % cash_verb, SUNNY))
	lines.add_child(_howto_line("DON'T COLLAPSE", "If 3 objects fall, the run ends and you lose any money you hadn't cashed out. Bank often, or push your luck!", Color(1.0, 0.5, 0.45)))
	lines.add_child(_howto_line("SPEND IT", "Banked cash carries over into your WALLET. Spend it in the SHOP on new mounts and saddle skins for your mule.", LEAF))
	lines.add_child(_howto_line("EXTRAS", extras_line, SKY))
	if _is_mobile:
		# Bounded, scrollable body so the title and BACK button stay on-screen.
		var scroll := ScrollContainer.new()
		scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		scroll.custom_minimum_size = Vector2(760, 360)
		scroll.add_child(lines)
		_pass_touches(lines)  # drags scroll even when they start on the text
		box.add_child(scroll)
	else:
		box.add_child(lines)

	box.add_child(_divider())
	var back := _make_button("BACK", LEAF)
	back.pressed.connect(func() -> void: _back_to_side(_howto))
	box.add_child(back)


func _howto_line(heading: String, body: String, color: Color) -> VBoxContainer:
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 0)
	vb.custom_minimum_size = Vector2(760, 0)
	var h := _make_label(heading, 22, color)
	vb.add_child(h)
	var b := _make_label(body, 17, CREAM)
	b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	b.custom_minimum_size = Vector2(760, 0)
	vb.add_child(b)
	return vb


# --- Credits (scrolling) -----------------------------------------------------

func _open_credits() -> void:
	if _credits == null:
		_build_credits()
	_menu.visible = false
	_side.visible = false
	_credits.visible = true
	_credits_y = CREDITS_CLIP_H  # start just below the clip window, then roll up


func _build_credits() -> void:
	_credits = CenterContainer.new()
	_credits.set_anchors_preset(Control.PRESET_FULL_RECT)
	_credits.visible = false
	add_child(_credits)

	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _rounded(PANEL_BG, 36, TANGERINE, 40, 32, 18))
	_credits.add_child(panel)

	# Holder so the panel has a single child; it carries the clipped roll
	# window and the Back button.
	var holder := Control.new()
	holder.custom_minimum_size = Vector2(660, 540)
	panel.add_child(holder)

	var clip := Control.new()
	clip.clip_contents = true
	clip.position = Vector2(10, 6)
	clip.size = Vector2(640, CREDITS_CLIP_H)
	holder.add_child(clip)

	_credits_scroll = VBoxContainer.new()
	(_credits_scroll as VBoxContainer).add_theme_constant_override("separation", 10)
	_credits_scroll.size = Vector2(640, 0)
	clip.add_child(_credits_scroll)
	for entry in _credits_lines():
		var lbl := _make_label(entry[1], entry[0], entry[2] as Color)
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lbl.custom_minimum_size = Vector2(640, 0)
		_credits_scroll.add_child(lbl)

	var back := _make_button("BACK", LEAF)
	back.pressed.connect(func() -> void: _back_to_side(_credits))
	holder.add_child(back)
	back.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT, Control.PRESET_MODE_MINSIZE, 16)


## [font_size, text, color] rows for the credit roll. Model attributions
## come from Poly Pizza (CC-BY / CC0); the full text + links live in
## ATTRIBUTION.txt at the project root.
func _credits_lines() -> Array:
	var faint := Color(0.8, 0.83, 0.92)
	var rows := [
		[64, "PACK MULE", SUNNY],
		[22, "Stack ridiculous things. Don't look down.", CREAM],
		[34, "", CREAM],
		[26, "DESIGN & CODE", SKY],
		[24, "Christoph", CREAM],
		[34, "", CREAM],
		[26, "BUILT WITH", SKY],
		[20, "Godot Engine 4.5", CREAM],
		[20, "Font: Luckiest Guy by Astigmatic", CREAM],
		[34, "", CREAM],
		[26, "3D MODELS", SKY],
		[16, "via Poly Pizza  ·  CC-BY / CC0", faint],
		[16, "", CREAM],
	]
	# name, creator — grouped loosely by what they are.
	var models := [
		["Donkey", "Poly by Google"], ["Horse", "Poly by Google"],
		["Goat", "Poly by Google"], ["Stag", "Quaternius"],
		["Bull", "Quaternius"], ["Elephant", "Poly by Google"],
		["Cow", "Quaternius"], ["Bear", "jiang liu"],
		["Alien", "Quaternius"], ["T-Rex", "Poly by Google"],
		["Eagle", "Robert Mirabelle"], ["Bird", "Poly by Google"],
		["Car", "Poly by Google"], ["Motorcycle", "Poly by Google"],
		["Helicopter", "Poly by Google"], ["Flying Saucer", "Poly by Google"],
		["Airship", "Poly by Google"], ["Hot Air Balloon", "Poly by Google"],
		["Refrigerator", "sirkitree"], ["Kitchen Oven", "Bouggles"],
		["Washer", "Kenney"], ["Couch", "CMHT Oculus"],
		["Chair", "Quaternius"], ["Table", "Hunter Paramore"],
		["Rug", "Akimkhan"], ["Toilet", "jeremy"],
		["Tub", "sirkitree"], ["Trashcan", "Poly by Google"],
		["Safe", "CreativeTrio"], ["Piano", "jeremy"],
		["Grill", "S. Paul Michael"], ["Anvil", "shantoan"],
		["Rubber Duck", "Poly by Google"], ["Fold Out Ladder", "Jarlan Perez"],
		["Traffic Cone", "Adam Marc Williams"], ["Lady Liberty", "Anna M"],
		["Windmill", "Poly by Google"], ["Mountain", "Quaternius"],
		["Cloud", "Poly by Google"],
	]
	for m: Array in models:
		rows.append([18, "%s — %s" % [m[0], m[1]], CREAM])
	rows.append([40, "", CREAM])
	rows.append([28, "Thanks for playing!", SUNNY])
	return rows


func _back_to_side(panel: CenterContainer) -> void:
	panel.visible = false
	_menu.visible = true
	_set_side(true)


## Show/hide the corner How-to/Credits buttons (only on the main menu).
func _set_side(visible: bool) -> void:
	if _side != null:
		_side.visible = visible


# --- Shop --------------------------------------------------------------------

func _open_shop() -> void:
	if _shop == null:
		_build_shop()
	_menu.visible = false
	_set_side(false)
	_populate_shop()
	_shop.visible = true


func _build_shop() -> void:
	_shop = CenterContainer.new()
	_shop.set_anchors_preset(Control.PRESET_FULL_RECT)
	_shop.visible = false
	add_child(_shop)

	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _rounded(PANEL_BG, 36, SUNNY,
			32 if _is_mobile else 40, 18 if _is_mobile else 28, 18))
	_shop.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	panel.add_child(box)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 24)
	header.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_child(header)
	var title := _make_label("SHOP", 40 if _is_mobile else 56, SUNNY)
	title.add_theme_color_override("font_outline_color", INK)
	title.add_theme_constant_override("outline_size", 10)
	header.add_child(title)
	_shop_wallet = _make_label("", 28, LEAF)
	_shop_wallet.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	header.add_child(_shop_wallet)

	_shop_tabs = HBoxContainer.new()
	_shop_tabs.add_theme_constant_override("separation", 12)
	_shop_tabs.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_child(_shop_tabs)

	box.add_child(_divider())

	var scroll := ScrollContainer.new()
	# Shorter on mobile so the title, tabs, and BACK all fit the landscape screen.
	scroll.custom_minimum_size = Vector2(720, 300 if _is_mobile else 420)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	box.add_child(scroll)
	_shop_body = VBoxContainer.new()
	_shop_body.add_theme_constant_override("separation", 8)
	_shop_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_shop_body)

	box.add_child(_divider())
	var back := _make_button("BACK", LEAF)
	back.pressed.connect(func() -> void: _back_to_menu(_shop))
	box.add_child(back)


## Fills (or refills) the tab bar, the active category's rows, and the wallet
## readout — called on open and after every purchase / equip / tab switch.
func _populate_shop() -> void:
	_shop_wallet.text = "WALLET  $%s" % _money_str(GameSettings.get_wallet())

	for c in _shop_tabs.get_children():
		_shop_tabs.remove_child(c)
		c.queue_free()
	for tab: Array in [["mounts", "MOUNTS"], ["skins", "SKINS"]]:
		var t := _make_button(tab[1], LEAF if _shop_tab == tab[0] else Color(0.42, 0.45, 0.55))
		t.add_theme_font_size_override("font_size", 22)
		t.pressed.connect(func() -> void: _shop_switch_tab(tab[0]))
		_shop_tabs.add_child(t)

	for c in _shop_body.get_children():
		_shop_body.remove_child(c)
		c.queue_free()
	if _shop_tab == "skins":
		for item: Dictionary in ShopCatalog.SKINS:
			_shop_body.add_child(_shop_row(item, "skin"))
	else:
		for item: Dictionary in ShopCatalog.MOUNTS:
			_shop_body.add_child(_shop_row(item, "mount"))


func _shop_switch_tab(tab: String) -> void:
	if tab == _shop_tab:
		return
	_shop_tab = tab
	Sfx.play("ding")
	_populate_shop()


## One item card: a picture on the left, name + description in the middle, and
## an action button (price / OWNED / EQUIP / EQUIPPED) on the right.
## `kind` is "skin" or "mount".
func _shop_row(item: Dictionary, kind: String) -> PanelContainer:
	var id: String = item["id"]
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel",
			_rounded(Color(1, 1, 1, 0.06), 14, Color(0, 0, 0, 0), 14, 8))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	card.add_child(row)

	if kind == "mount":
		row.add_child(_model_thumb(item["path"]))
	else:
		row.add_child(_skin_swatch(ShopCatalog.skin_color(id)))

	var info := VBoxContainer.new()
	info.add_theme_constant_override("separation", 2)
	info.custom_minimum_size = Vector2(330, 0)
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	info.add_child(_make_label(item["name"], 22, CREAM))
	if item.has("desc"):
		var desc := _make_label(item["desc"], 15, Color(0.82, 0.85, 0.95))
		desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		desc.custom_minimum_size = Vector2(330, 0)
		info.add_child(desc)
	row.add_child(info)

	var btn := _shop_action_button(item, kind)
	btn.custom_minimum_size = Vector2(150, 0)
	btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(btn)
	if _is_mobile:
		_pass_touches(card)  # let a drag on the card scroll the list (button still taps)
	return card


## A small live 3D preview of a model (its own world + light + framed camera),
## used as the picture for a mount.
func _model_thumb(path: String) -> Control:
	var holder := TextureRect.new()
	holder.custom_minimum_size = Vector2(92, 92)
	holder.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED

	var vp := SubViewport.new()
	vp.size = Vector2i(128, 128)
	vp.transparent_bg = true
	vp.own_world_3d = true
	vp.render_target_update_mode = SubViewport.UPDATE_ONCE  # static preview
	holder.add_child(vp)

	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(deg_to_rad(-50.0), deg_to_rad(35.0), 0.0)
	sun.light_energy = 1.3
	vp.add_child(sun)

	var stage := Node3D.new()
	var model: Node3D = (load(path) as PackedScene).instantiate()
	stage.add_child(model)
	var pts := PackedVector3Array()
	StackableObject.collect_hull_points(model, Transform3D.IDENTITY, pts)
	if not pts.is_empty():
		var aabb := StackableObject.points_aabb(pts)
		var longest := maxf(aabb.size.x, maxf(aabb.size.y, aabb.size.z))
		model.scale = Vector3.ONE * (1.7 / maxf(longest, 0.001))
		model.position = -aabb.get_center() * model.scale
	stage.rotation.y = deg_to_rad(35.0)  # three-quarter view
	vp.add_child(stage)

	var cam := Camera3D.new()
	# look_at needs the node in-tree; set the transform directly instead.
	cam.look_at_from_position(Vector3(0.0, 0.7, 2.4), Vector3.ZERO, Vector3.UP)
	vp.add_child(cam)

	holder.texture = vp.get_texture()
	return holder


## A rounded color blanket used as the picture for a saddle skin.
func _skin_swatch(color: Color) -> Control:
	var holder := CenterContainer.new()
	holder.custom_minimum_size = Vector2(92, 92)
	var blanket := PanelContainer.new()
	blanket.custom_minimum_size = Vector2(80, 56)
	blanket.add_theme_stylebox_override("panel", _rounded(color, 12, color.darkened(0.35)))
	holder.add_child(blanket)
	return holder


func _shop_action_button(item: Dictionary, kind: String) -> Button:
	var id: String = item["id"]
	var price: int = int(item["price"])
	var equipped := (kind == "skin" and GameSettings.get_skin() == id) \
			or (kind == "mount" and GameSettings.get_base() == id)
	var equippable := kind == "skin" or kind == "mount"
	var btn: Button
	if equippable and equipped:
		btn = _make_button("EQUIPPED", LEAF)
		btn.disabled = true
	elif GameSettings.owns(id):
		if equippable:
			btn = _make_button("EQUIP", SKY)
			btn.pressed.connect(func() -> void: _shop_equip(item, kind))
		else:
			btn = _make_button("OWNED", LEAF)
			btn.disabled = true
	else:
		btn = _make_button("$%s" % _money_str(price), SUNNY)
		btn.pressed.connect(func() -> void: _shop_buy(item, kind))
	btn.add_theme_font_size_override("font_size", 20)
	return btn


func _shop_buy(item: Dictionary, kind: String) -> void:
	var id: String = item["id"]
	if GameSettings.owns(id):
		return
	if GameSettings.spend_wallet(int(item["price"])):
		GameSettings.buy(id)
		Sfx.play("register")
		Sfx.play("coin")
		if kind == "skin" or kind == "mount":
			_equip(item, kind)
		_punch(_shop_wallet, 1.2)
		_populate_shop()
	else:
		Sfx.play("sting")  # can't afford
		_punch(_shop_wallet, 1.25)


func _shop_equip(item: Dictionary, kind: String) -> void:
	_equip(item, kind)
	Sfx.play("ding")
	_populate_shop()


## Equips a skin or a mount and signals the game manager to update the mule.
func _equip(item: Dictionary, kind: String) -> void:
	if kind == "skin":
		GameSettings.set_skin(item["id"])
		skin_changed.emit()
	elif kind == "mount":
		GameSettings.set_base(item["id"])
		base_changed.emit()


func _process(delta: float) -> void:
	# Movie-style credit roll while the credits screen is open.
	if _credits == null or not _credits.visible:
		return
	_credits_y -= delta * 45.0
	var content_h := _credits_scroll.get_combined_minimum_size().y
	if _credits_y < -content_h:
		_credits_y = CREDITS_CLIP_H  # loop back to the bottom of the window
	_credits_scroll.position.y = _credits_y


# --- Tower gallery -----------------------------------------------------------

func _open_gallery() -> void:
	if _gallery == null:
		_build_gallery()
	_menu.visible = false
	_set_side(false)
	_gallery.visible = true
	_load_gallery_files()
	_gallery_index = _gallery_files.size() - 1  # newest first
	_show_gallery_photo()


func _build_gallery() -> void:
	_gallery = CenterContainer.new()
	_gallery.set_anchors_preset(Control.PRESET_FULL_RECT)
	_gallery.visible = false
	add_child(_gallery)

	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _rounded(PANEL_BG, 30, SKY,
			24 if _is_mobile else 28, 14 if _is_mobile else 24))
	_gallery.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	panel.add_child(box)

	var title := _make_label("TOWER GALLERY", 32 if _is_mobile else 40, SKY)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)

	# Smaller photo on mobile so the nav + BACK row stays on the short screen.
	var photo_w := 460.0 if _is_mobile else 620.0
	_gallery_photo = TextureRect.new()
	_gallery_photo.custom_minimum_size = Vector2(photo_w, photo_w * POSTCARD_SIZE.y / POSTCARD_SIZE.x)
	_gallery_photo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_gallery_photo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	box.add_child(_gallery_photo)

	var nav := HBoxContainer.new()
	nav.add_theme_constant_override("separation", 16)
	nav.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_child(nav)
	var prev := _make_button("< PREV", SKY)
	prev.pressed.connect(func() -> void: _step_gallery(-1))
	nav.add_child(prev)
	_gallery_counter = _make_label("0 / 0", 22, CREAM)
	_gallery_counter.custom_minimum_size = Vector2(140, 0)
	_gallery_counter.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_gallery_counter.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	nav.add_child(_gallery_counter)
	var next := _make_button("NEXT >", SKY)
	next.pressed.connect(func() -> void: _step_gallery(1))
	nav.add_child(next)

	var back := _make_button("BACK", Color(0.55, 0.55, 0.62))
	back.pressed.connect(_back_to_menu.bind(_gallery))
	box.add_child(back)


func _load_gallery_files() -> void:
	_gallery_files = PackedStringArray()
	var dir := DirAccess.open(GALLERY_DIR)
	if dir == null:
		return
	for f in dir.get_files():
		if f.ends_with(".png"):
			_gallery_files.append(GALLERY_DIR.path_join(f))
	_gallery_files.sort()  # filenames are timestamped → chronological


func _step_gallery(delta: int) -> void:
	if _gallery_files.is_empty():
		return
	_gallery_index = wrapi(_gallery_index + delta, 0, _gallery_files.size())
	_show_gallery_photo()


func _show_gallery_photo() -> void:
	if _gallery_files.is_empty():
		_gallery_photo.texture = null
		_gallery_counter.text = "EMPTY"
		return
	var img := Image.load_from_file(_gallery_files[_gallery_index])
	_gallery_photo.texture = ImageTexture.create_from_image(img) if img != null else null
	_gallery_counter.text = "%d / %d" % [_gallery_index + 1, _gallery_files.size()]


## Saves the just-built postcard into the rolling in-game gallery.
func _autosave_gallery() -> void:
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute(GALLERY_DIR)
	var img := _pc_vp.get_texture().get_image()
	img.save_png(GALLERY_DIR.path_join("tower_%d.png" % int(Time.get_unix_time_from_system())))
	# Prune to the most recent GALLERY_MAX.
	var dir := DirAccess.open(GALLERY_DIR)
	if dir == null:
		return
	var files := []
	for f in dir.get_files():
		if f.ends_with(".png"):
			files.append(f)
	files.sort()
	while files.size() > GALLERY_MAX:
		dir.remove(files.pop_front())


# --- Odds (item rarity) ------------------------------------------------------

func _open_odds(return_to: CenterContainer = null) -> void:
	if _odds == null:
		_build_odds()
	_odds_return = return_to if return_to != null else _menu
	_odds_return.visible = false
	if _odds_return == _menu:
		_set_side(false)
	_odds.visible = true
	_refresh_odds_pcts()


func _back_from_odds() -> void:
	_odds.visible = false
	if _odds_return != null:
		_odds_return.visible = true
		if _odds_return == _menu:
			_set_side(true)


func _build_odds() -> void:
	_odds = CenterContainer.new()
	_odds.set_anchors_preset(Control.PRESET_FULL_RECT)
	_odds.visible = false
	add_child(_odds)

	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _rounded(PANEL_BG, 30, LEAF, 28, 20))
	_odds.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	panel.add_child(box)

	var title := _make_label("ITEM ODDS", 40, LEAF)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)
	box.add_child(_make_label("HIGHER = MORE COMMON", 14, Color(0.8, 0.83, 0.92)))

	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size = Vector2(560, 360)
	box.add_child(scroll)
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 14)
	grid.add_theme_constant_override("v_separation", 6)
	scroll.add_child(grid)
	for e in ObjectCatalog.ENTRIES:
		var entry_name: String = e["name"]
		var name_label := _make_label(entry_name, 15, CREAM)
		name_label.custom_minimum_size = Vector2(150, 0)
		grid.add_child(name_label)
		var slider := HSlider.new()
		slider.min_value = 0.0
		slider.max_value = 20.0
		slider.step = 0.5
		slider.value = GameSettings.get_weight(entry_name)
		slider.custom_minimum_size = Vector2(280, 0)
		slider.value_changed.connect(_on_odds_changed.bind(entry_name))
		grid.add_child(slider)
		var pct := _make_label("", 15, SUNNY)
		pct.custom_minimum_size = Vector2(60, 0)
		_odds_pct[entry_name] = pct
		grid.add_child(pct)

	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 16)
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_child(buttons)
	var reset := _make_button("DEFAULT", Color(0.55, 0.55, 0.62))
	reset.pressed.connect(_reset_odds)
	buttons.add_child(reset)
	var back := _make_button("BACK", LEAF)
	back.pressed.connect(_back_from_odds)
	buttons.add_child(back)


func _on_odds_changed(value: float, entry_name: String) -> void:
	GameSettings.set_weight(entry_name, value)
	_refresh_odds_pcts()


func _reset_odds() -> void:
	GameSettings.reset_weights()
	# Rebuild the screen so sliders snap back to defaults.
	var ret := _odds_return
	_odds.queue_free()
	_odds = null
	_odds_pct.clear()
	_open_odds(ret)


func _refresh_odds_pcts() -> void:
	var total := 0.0
	for e in ObjectCatalog.ENTRIES:
		total += GameSettings.get_weight(e["name"])
	for e in ObjectCatalog.ENTRIES:
		var n: String = e["name"]
		var w := GameSettings.get_weight(n)
		(_odds_pct[n] as Label).text = "0%" if total <= 0.0 else "%.1f%%" % (w / total * 100.0)


# --- Settings ----------------------------------------------------------------

func _open_settings(return_to: CenterContainer = null) -> void:
	if _settings == null:
		_build_settings()
	_settings_return = return_to if return_to != null else _menu
	_settings_return.visible = false
	if _settings_return == _menu:
		_set_side(false)
	_settings.visible = true


func _build_settings() -> void:
	_settings = CenterContainer.new()
	_settings.set_anchors_preset(Control.PRESET_FULL_RECT)
	_settings.visible = false
	add_child(_settings)

	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _rounded(PANEL_BG, 30, TANGERINE, 30, 24))
	_settings.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	panel.add_child(box)

	var title := _make_label("SETTINGS", 40, TANGERINE)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)

	box.add_child(_make_label("SOUND", 22, SUNNY))
	box.add_child(_make_volume_row("MASTER", "master"))
	box.add_child(_make_volume_row("SFX", "sfx"))
	box.add_child(_make_volume_row("AMBIENCE", "ambience"))
	var mute := CheckButton.new()
	mute.text = "MUTE"
	mute.button_pressed = GameSettings.is_muted()
	mute.add_theme_color_override("font_color", CREAM)
	mute.add_theme_color_override("font_pressed_color", CREAM)
	mute.toggled.connect(func(on: bool) -> void: GameSettings.set_muted(on))
	box.add_child(mute)

	# Key rebinding is desktop-only — a touch build has no keyboard, and tapping a
	# rebind row would just wait for a key that never comes (or capture an
	# emulated mouse button). Hide the whole CONTROLS block on mobile.
	if not _is_mobile:
		var gap := Control.new()
		gap.custom_minimum_size = Vector2(0, 8)
		box.add_child(gap)
		box.add_child(_make_label("CONTROLS", 22, SUNNY))
		box.add_child(_make_label("CLICK A KEY, THEN PRESS THE NEW ONE  ·  ESC CANCELS", 13, Color(0.8, 0.83, 0.92)))

		var scroll := ScrollContainer.new()
		scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		scroll.custom_minimum_size = Vector2(430, 200)
		box.add_child(scroll)
		var grid := GridContainer.new()
		grid.columns = 2
		grid.add_theme_constant_override("h_separation", 16)
		grid.add_theme_constant_override("v_separation", 6)
		scroll.add_child(grid)
		for b in GameSettings.BINDS:
			var action: String = b[0]
			grid.add_child(_make_label(String(b[1]), 16, CREAM))
			var btn := _make_button(GameSettings.binding_text(action), Color(0.32, 0.34, 0.5))
			btn.add_theme_font_size_override("font_size", 16)
			btn.add_theme_color_override("font_color", CREAM)
			btn.pressed.connect(_begin_listen.bind(action, btn))
			_bind_buttons[action] = btn
			grid.add_child(btn)

	var gap2 := Control.new()
	gap2.custom_minimum_size = Vector2(0, 8)
	box.add_child(gap2)
	var odds_btn := _make_button("ITEM ODDS", SKY)
	odds_btn.pressed.connect(func() -> void: _open_odds(_settings))
	box.add_child(odds_btn)

	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 16)
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_child(buttons)
	if not _is_mobile:
		var reset := _make_button("RESET KEYS", Color(0.55, 0.55, 0.62))
		reset.pressed.connect(_reset_binds)
		buttons.add_child(reset)
	var back := _make_button("BACK", LEAF)
	back.pressed.connect(_back_from_settings)
	buttons.add_child(back)


func _make_volume_row(label: String, kind: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	var name := _make_label(label, 16, CREAM)
	name.custom_minimum_size = Vector2(150, 0)
	row.add_child(name)
	var slider := HSlider.new()
	slider.min_value = 0.0
	slider.max_value = 1.0
	slider.step = 0.05
	slider.value = GameSettings.get_volume(kind)
	slider.custom_minimum_size = Vector2(280, 0)
	slider.value_changed.connect(func(v: float) -> void: GameSettings.set_volume(kind, v))
	row.add_child(slider)
	return row


func _begin_listen(action: String, btn: Button) -> void:
	_listening = action
	_listening_btn = btn
	btn.text = "PRESS A KEY..."
	btn.release_focus()  # so Space/Enter don't re-press this button


func _reset_binds() -> void:
	GameSettings.reset_binds()
	for action in _bind_buttons:
		(_bind_buttons[action] as Button).text = GameSettings.binding_text(action)


func _back_to_menu(panel: CenterContainer) -> void:
	panel.visible = false
	_menu.visible = true
	_set_side(true)


func _back_from_settings() -> void:
	_settings.visible = false
	if _settings_return != null:
		_settings_return.visible = true
		if _settings_return == _menu:
			_set_side(true)


# --- Pause -------------------------------------------------------------------

func _toggle_pause() -> void:
	if not _in_run:
		return
	_paused = not _paused
	get_tree().paused = _paused
	if not _is_mobile:  # no cursor to capture/free on a touchscreen
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if _paused else Input.MOUSE_MODE_CAPTURED
	if _pause == null:
		_build_pause()
	_pause.visible = _paused
	# Hide the readouts behind the pause panel; restore them on resume
	# (also covers returning from photo mode, which hid them).
	set_in_game_hud_visible(not _paused)


func _resume() -> void:
	if _paused:
		_toggle_pause()


func _build_pause() -> void:
	_pause = CenterContainer.new()
	_pause.set_anchors_preset(Control.PRESET_FULL_RECT)
	_pause.visible = false
	add_child(_pause)

	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _rounded(PANEL_BG, 36, SUNNY, 72, 56, 18))
	_pause.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 20)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	panel.add_child(box)

	var title := _make_label("PAUSED", 72, SUNNY)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_color_override("font_outline_color", INK)
	title.add_theme_constant_override("outline_size", 14)
	box.add_child(title)

	box.add_child(_divider())

	var resume := _make_button("RESUME", LEAF)
	resume.add_theme_font_size_override("font_size", 34)
	resume.custom_minimum_size = Vector2(360, 0)
	resume.pressed.connect(_resume)
	box.add_child(resume)
	var restart := _make_button("RESTART", Color(0.95, 0.45, 0.4))
	restart.custom_minimum_size = Vector2(360, 0)
	restart.pressed.connect(func() -> void:
		_paused = false
		_pause.visible = false
		restart_requested.emit())
	box.add_child(restart)
	var photo := _make_button("PHOTO MODE", SKY)
	photo.custom_minimum_size = Vector2(360, 0)
	photo.pressed.connect(start_photo_mode)
	box.add_child(photo)
	var settings := _make_button("SETTINGS", TANGERINE)
	settings.custom_minimum_size = Vector2(360, 0)
	settings.pressed.connect(func() -> void: _open_settings(_pause))
	box.add_child(settings)
	var menu := _make_button("MAIN MENU", Color(0.5, 0.5, 0.58))
	menu.custom_minimum_size = Vector2(360, 0)
	menu.pressed.connect(func() -> void: to_main_menu_requested.emit())
	box.add_child(menu)


## Photo mode: frozen scene, free camera, hidden UI, snap a shot.
## `from_pause` true = opened via the pause menu (return to it on exit);
## false = opened with the hotkey mid-run (return to play on exit).
## Free-look photo mode: cursor captured, fly with WASD + mouse, [P] snaps,
## [Esc] opens the pause menu (which has a button back to builder mode).
func start_photo_mode() -> void:
	if _photo:
		return
	if _pause != null:
		_pause.visible = false
	set_in_game_hud_visible(false)
	_photo = true
	if _photo_hint == null:
		var hint := "PHOTO MODE   ·   DRAG TO ORBIT   ·   PINCH TO ZOOM   ·   SNAP / DONE BELOW" \
				if _is_mobile \
				else "PHOTO MODE   ·   WASD + MOUSE TO FLY   ·   [P] SNAP   ·   [ESC] MENU"
		_photo_hint = _make_label(hint, 16, CREAM)
		_photo_hint.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
		_photo_hint.grow_horizontal = Control.GROW_DIRECTION_BOTH
		_photo_hint.grow_vertical = Control.GROW_DIRECTION_BEGIN
		_photo_hint.offset_top = -40
		add_child(_photo_hint)
	_photo_hint.visible = true
	if _mobile_photo != null:
		_mobile_photo.visible = true  # SNAP / DONE buttons (no keys on touch)
	photo_enter_requested.emit()


## Esc in photo mode -> the pause menu (cursor freed, camera frozen).
func _photo_to_pause() -> void:
	_photo = false
	if _photo_hint != null:
		_photo_hint.visible = false
	if _mobile_photo != null:
		_mobile_photo.visible = false
	_paused = true
	get_tree().paused = true
	if not _is_mobile:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if _pause == null:
		_build_pause()
	_pause.visible = true
	photo_to_pause_requested.emit()


func _snap_photo() -> void:
	if _photo_hint != null:
		_photo_hint.visible = false
	if _mobile_photo != null:
		_mobile_photo.visible = false  # keep SNAP/DONE out of the captured frame
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	Sfx.play("tick", 1.3)
	# Into the in-game gallery (works everywhere, incl. Android app storage)...
	DirAccess.make_dir_recursive_absolute(GALLERY_DIR)
	img.save_png(GALLERY_DIR.path_join("photo_%d.png" % int(Time.get_unix_time_from_system())))
	# ...and, on desktop, also to the system Pictures folder for sharing. Android
	# scoped storage blocks arbitrary Pictures writes, so there the in-game
	# Gallery is the share point (no error spam from a forbidden path).
	if not _is_mobile:
		var pics := OS.get_system_dir(OS.SYSTEM_DIR_PICTURES)
		if pics.is_empty():
			pics = OS.get_user_data_dir()
		img.save_png(pics.path_join("PackMule_%d.png" % int(Time.get_unix_time_from_system())))
	if _photo:
		if _photo_hint != null:
			_photo_hint.visible = true
		if _mobile_photo != null:
			_mobile_photo.visible = true


## Rebind capture runs in _input (before the GUI), so keys like Space and
## Enter — which would otherwise activate the focused button — are caught
## and assigned instead.
func _input(event: InputEvent) -> void:
	if _listening.is_empty():
		return
	if event is InputEventKey and event.pressed and not event.echo:
		get_viewport().set_input_as_handled()
		if (event as InputEventKey).keycode != KEY_ESCAPE:
			GameSettings.rebind(_listening, event)
		_listening_btn.text = GameSettings.binding_text(_listening)
		_listening = ""
	elif event is InputEventMouseButton and event.pressed:
		get_viewport().set_input_as_handled()
		GameSettings.rebind(_listening, event)
		_listening_btn.text = GameSettings.binding_text(_listening)
		_listening = ""


func _unhandled_input(event: InputEvent) -> void:
	# Photo mode: P snaps, Esc opens the pause menu.
	if _photo and event is InputEventKey and event.pressed and not event.echo:
		var code := (event as InputEventKey).keycode
		if code == KEY_P:
			get_viewport().set_input_as_handled()
			_snap_photo()
			return
		if code == KEY_ESCAPE:
			get_viewport().set_input_as_handled()
			_photo_to_pause()
			return
	if not _listening.is_empty():
		return  # handled in _input
	# Esc is the universal "back / pause".
	if event is InputEventKey and event.pressed and not event.echo \
			and (event as InputEventKey).keycode == KEY_ESCAPE:
		if _odds != null and _odds.visible:
			_back_from_odds()
		elif _settings != null and _settings.visible:
			_back_from_settings()
		elif _gallery != null and _gallery.visible:
			_back_to_menu(_gallery)
		elif _howto != null and _howto.visible:
			_back_to_side(_howto)
		elif _credits != null and _credits.visible:
			_back_to_side(_credits)
		elif _shop != null and _shop.visible:
			_back_to_menu(_shop)
		elif _in_run:
			_toggle_pause()
		else:
			return
		get_viewport().set_input_as_handled()


# --- Game-over panel ---------------------------------------------------------

func show_game_over(reason: String, stats: Dictionary, photo: Image) -> void:
	if not _go_built:
		_build_game_over_ui()
		_go_built = true
	_build_postcard(photo, stats)
	if stats.get("new_record", false):
		_go_title.text = "NEW RECORD!"
	else:
		_go_title.text = reason
	var banked := int(stats["score"])
	var lost := int(stats.get("lost", 0))
	var wallet := int(stats.get("wallet", 0))
	if lost > 0:
		_go_subtitle.text = "BANKED  $%s   ·   LOST $%s UNCASHED   ·   WALLET  $%s" % [
				_money_str(banked), _money_str(lost), _money_str(wallet)]
	else:
		_go_subtitle.text = "BANKED  $%s      WALLET  $%s" % [_money_str(banked), _money_str(wallet)]
	_chip_values["HEIGHT"].text = "%.1f m" % float(stats["height"])
	_chip_values["OBJECTS"].text = "%d" % int(stats["objects"])
	_chip_values["WEIGHT"].text = "%d kg" % int(round(float(stats["weight"])))
	_pc_display.texture = _pc_vp.get_texture()
	_saved_label.visible = false
	_game_over.visible = true
	_pop_in_panel()
	_autosave_gallery()


## A quick scale-in so the game-over panel lands with some bounce. Runs on
## unscaled time because the scene is frozen (Engine.time_scale = 0).
func _pop_in_panel() -> void:
	await get_tree().process_frame  # let the panel get its size
	_go_panel.pivot_offset = _go_panel.size / 2.0
	_go_panel.scale = Vector2(0.9, 0.9)
	_go_panel.modulate.a = 0.0
	var tw := create_tween().set_parallel(true)
	tw.set_ignore_time_scale(true)
	tw.tween_property(_go_panel, "scale", Vector2.ONE, 0.35) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(_go_panel, "modulate:a", 1.0, 0.28)


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
	var menu_btn := _make_button("MAIN MENU", TANGERINE)
	menu_btn.pressed.connect(func() -> void: to_main_menu_requested.emit())
	buttons.add_child(menu_btn)

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
	_pc_caption.text = "$%s  ·  %.1f M  ·  %d OBJECTS  ·  %d KG" % [
			_money_str(int(stats.get("score", 0))), float(stats["height"]),
			int(stats["objects"]), int(round(float(stats["weight"])))]


func _on_save_pressed() -> void:
	await RenderingServer.frame_post_draw
	var img := _pc_vp.get_texture().get_image()
	# On mobile the system Pictures folder is off-limits (Android scoped
	# storage), so save into the in-game Gallery (browsable from the menu).
	if _is_mobile:
		DirAccess.make_dir_recursive_absolute(GALLERY_DIR)
		var gpath := GALLERY_DIR.path_join("PackMule_%d.png" % int(Time.get_unix_time_from_system()))
		var gerr := img.save_png(gpath)
		_saved_label.text = "SAVED TO YOUR GALLERY!" if gerr == OK \
				else "COULD NOT SAVE (error %d)" % gerr
		_saved_label.visible = true
		return
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
	# Bigger text and padding on a touchscreen so every button is an easy target.
	var fsize := 34 if _is_mobile else 28
	var px := 32 if _is_mobile else 26
	var py := 20 if _is_mobile else 14
	btn.add_theme_font_size_override("font_size", fsize)
	for c in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_disabled_color"]:
		btn.add_theme_color_override(c, INK)
	btn.add_theme_stylebox_override("normal", _rounded(color, 18, color.darkened(0.3), px, py, 5))
	btn.add_theme_stylebox_override("hover", _rounded(color.lightened(0.12), 18, color.darkened(0.3), px, py, 6))
	btn.add_theme_stylebox_override("pressed", _rounded(color.darkened(0.12), 18, color.darkened(0.3), px, py, 2))
	btn.add_theme_stylebox_override("disabled", _rounded(color.darkened(0.08), 18, color.darkened(0.3), px, py, 3))
	btn.add_theme_stylebox_override("focus", _rounded(Color(0, 0, 0, 0), 18, CREAM, px, py))
	return btn


func _rounded(bg: Color, radius: int, border: Color, pad_x := 0, pad_y := 0, shadow := 0) -> StyleBoxFlat:
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
	if shadow > 0:
		sb.shadow_size = shadow
		sb.shadow_color = Color(0.0, 0.0, 0.0, 0.35)
		sb.shadow_offset = Vector2(0, shadow * 0.5)
	return sb
