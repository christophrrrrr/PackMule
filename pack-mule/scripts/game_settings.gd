class_name GameSettings
extends Node

## Persistent settings (audio volumes + key bindings), saved to
## user://settings.cfg. Like Sfx, it's a class_name with static helpers
## backed by a runtime instance the game creates at startup — so it resolves
## in --script tool runs (an autoload would not). It also creates the
## remappable InputMap actions the whole game uses for input.

const PATH := "user://settings.cfg"

## [action, label, default key (or -1), default mouse button (or -1)].
## Order is the order shown in the keybind UI. Esc/Shift stay hard-coded.
const BINDS := [
	["pm_forward", "Fly Forward", KEY_W, -1],
	["pm_back", "Fly Back", KEY_S, -1],
	["pm_left", "Fly Left", KEY_A, -1],
	["pm_right", "Fly Right", KEY_D, -1],
	["pm_up", "Fly Up", KEY_SPACE, -1],
	["pm_down", "Fly Down", KEY_CTRL, -1],
	["pm_rotate_left", "Rotate Left", KEY_Q, -1],
	["pm_rotate_right", "Rotate Right", KEY_E, -1],
	["pm_tip", "Tip Over", KEY_R, -1],
	["pm_spin", "Spin Wheel", KEY_TAB, -1],
	["pm_place", "Place Object", -1, MOUSE_BUTTON_LEFT],
	["pm_photo", "Photo Mode", KEY_C, -1],
	["pm_cashout", "Cash Out", KEY_ENTER, -1],
]

static var _inst: GameSettings

var _cfg := ConfigFile.new()


func _ready() -> void:
	_inst = self
	_cfg.load(PATH)  # missing file is fine — defaults apply
	_ensure_buses()
	_apply_audio()
	_setup_actions()


# --- Audio -------------------------------------------------------------------

func _ensure_buses() -> void:
	for n in ["SFX", "Ambience"]:
		if AudioServer.get_bus_index(n) == -1:
			AudioServer.add_bus()
			var i := AudioServer.bus_count - 1
			AudioServer.set_bus_name(i, n)
			AudioServer.set_bus_send(i, "Master")
			if n == "SFX":
				# Even out the loudness gap between sound files: a compressor
				# pulls the loud ones down toward the quiet ones, and a limiter
				# catches any remaining peaks so nothing clips.
				var comp := AudioEffectCompressor.new()
				comp.threshold = -16.0
				comp.ratio = 4.0
				comp.attack_us = 25.0
				comp.release_ms = 160.0
				comp.gain = 4.0
				AudioServer.add_bus_effect(i, comp)
				var lim := AudioEffectLimiter.new()
				lim.ceiling_db = -1.0
				AudioServer.add_bus_effect(i, lim)


func _apply_audio() -> void:
	_set_bus("Master", _vol("master"))
	_set_bus("SFX", _vol("sfx"))
	_set_bus("Ambience", _vol("ambience"))
	AudioServer.set_bus_mute(0, _cfg.get_value("audio", "muted", false))


func _set_bus(name: String, linear: float) -> void:
	var idx := AudioServer.get_bus_index(name)
	if idx != -1:
		AudioServer.set_bus_volume_db(idx, -80.0 if linear <= 0.001 else linear_to_db(linear))


func _vol(kind: String) -> float:
	return _cfg.get_value("audio", kind, 0.8)


static func get_volume(kind: String) -> float:
	return _inst._vol(kind) if _inst != null else 0.8


static func set_volume(kind: String, value: float) -> void:
	if _inst == null:
		return
	_inst._cfg.set_value("audio", kind, value)
	_inst._apply_audio()
	_inst._save()


static func is_muted() -> bool:
	return _inst != null and _inst._cfg.get_value("audio", "muted", false)


static func set_muted(value: bool) -> void:
	if _inst == null:
		return
	_inst._cfg.set_value("audio", "muted", value)
	_inst._apply_audio()
	_inst._save()


# --- Key bindings ------------------------------------------------------------

func _setup_actions() -> void:
	for b in BINDS:
		var action: String = b[0]
		if not InputMap.has_action(action):
			InputMap.add_action(action)
		InputMap.action_erase_events(action)
		InputMap.action_add_event(action, _load_event(b))


func _load_event(b: Array) -> InputEvent:
	if _cfg.has_section_key("keys", b[0]):
		var parts: PackedStringArray = String(_cfg.get_value("keys", b[0])).split(":")
		if parts.size() == 2:
			return _key(int(parts[1])) if parts[0] == "k" else _mouse(int(parts[1]))
	return _key(b[2]) if b[2] != -1 else _mouse(b[3])


func _key(code: int) -> InputEventKey:
	var e := InputEventKey.new()
	e.keycode = code
	return e


func _mouse(button: int) -> InputEventMouseButton:
	var e := InputEventMouseButton.new()
	e.button_index = button
	return e


func _spec(event: InputEvent) -> String:
	if event is InputEventKey:
		return "k:%d" % (event as InputEventKey).keycode
	if event is InputEventMouseButton:
		return "m:%d" % (event as InputEventMouseButton).button_index
	return ""


static func rebind(action: String, event: InputEvent) -> void:
	if _inst == null:
		return
	InputMap.action_erase_events(action)
	InputMap.action_add_event(action, event)
	_inst._cfg.set_value("keys", action, _inst._spec(event))
	_inst._save()


static func reset_binds() -> void:
	if _inst == null:
		return
	for b in BINDS:
		_inst._cfg.erase_section_key("keys", b[0])
	_inst._setup_actions()
	_inst._save()


## A readable label for an action's current binding (e.g. "W", "MOUSE LEFT").
static func binding_text(action: String) -> String:
	var events := InputMap.action_get_events(action)
	if events.is_empty():
		return "-"
	var e := events[0]
	if e is InputEventKey:
		return OS.get_keycode_string((e as InputEventKey).keycode).to_upper()
	if e is InputEventMouseButton:
		match (e as InputEventMouseButton).button_index:
			MOUSE_BUTTON_LEFT: return "MOUSE LEFT"
			MOUSE_BUTTON_RIGHT: return "MOUSE RIGHT"
			MOUSE_BUTTON_MIDDLE: return "MOUSE MIDDLE"
			_: return "MOUSE %d" % (e as InputEventMouseButton).button_index
	return "?"


func _save() -> void:
	_cfg.save(PATH)


# --- Spawn weights (rarity) --------------------------------------------------

static func get_weight(entry_name: String) -> float:
	if _inst == null:
		return ObjectCatalog.default_weight(entry_name)
	return _inst._cfg.get_value("rarity", entry_name, ObjectCatalog.default_weight(entry_name))


static func set_weight(entry_name: String, value: float) -> void:
	if _inst == null:
		return
	_inst._cfg.set_value("rarity", entry_name, value)
	_inst._save()


static func reset_weights() -> void:
	if _inst == null:
		return
	for e in ObjectCatalog.ENTRIES:
		_inst._cfg.erase_section_key("rarity", e["name"])
	_inst._save()


# --- Best-height record ------------------------------------------------------

static func get_record() -> float:
	return _inst._cfg.get_value("stats", "best_height", 0.0) if _inst != null else 0.0


static func set_record(meters: float) -> void:
	if _inst == null:
		return
	_inst._cfg.set_value("stats", "best_height", meters)
	_inst._save()


static func get_score_record() -> int:
	return _inst._cfg.get_value("stats", "best_score", 0) if _inst != null else 0


static func set_score_record(value: int) -> void:
	if _inst == null:
		return
	_inst._cfg.set_value("stats", "best_score", value)
	_inst._save()


# --- Shop: wallet, unlocks, equipped skin ------------------------------------

static func get_wallet() -> int:
	return int(_inst._cfg.get_value("shop", "wallet", 0)) if _inst != null else 0


static func set_wallet(value: int) -> void:
	if _inst == null:
		return
	_inst._cfg.set_value("shop", "wallet", maxi(0, value))
	_inst._save()


static func add_wallet(amount: int) -> void:
	if amount > 0:
		set_wallet(get_wallet() + amount)


## Spends from the wallet if it can be afforded; true on success.
static func spend_wallet(amount: int) -> bool:
	if _inst == null or amount > get_wallet():
		return false
	set_wallet(get_wallet() - amount)
	return true


## Owns a perk/boost/skin/mount. The default red saddle and donkey are free.
static func owns(id: String) -> bool:
	if id == ShopCatalog.DEFAULT_SKIN or id == ShopCatalog.DEFAULT_BASE:
		return true
	return bool(_inst._cfg.get_value("shop_items", id, false)) if _inst != null else false


static func buy(id: String) -> void:
	if _inst == null:
		return
	_inst._cfg.set_value("shop_items", id, true)
	_inst._save()


static func get_skin() -> String:
	if _inst == null:
		return ShopCatalog.DEFAULT_SKIN
	return str(_inst._cfg.get_value("shop", "skin", ShopCatalog.DEFAULT_SKIN))


static func set_skin(id: String) -> void:
	if _inst == null:
		return
	_inst._cfg.set_value("shop", "skin", id)
	_inst._save()


static func get_base() -> String:
	if _inst == null:
		return ShopCatalog.DEFAULT_BASE
	return str(_inst._cfg.get_value("shop", "base", ShopCatalog.DEFAULT_BASE))


static func set_base(id: String) -> void:
	if _inst == null:
		return
	_inst._cfg.set_value("shop", "base", id)
	_inst._save()


# --- Daily challenge ---------------------------------------------------------

## True if today's challenge has already been completed.
static func daily_done() -> bool:
	if _inst == null:
		return false
	return int(_inst._cfg.get_value("daily", "done_day", -1)) == DailyChallenge.absolute_day()


static func set_daily_done() -> void:
	if _inst == null:
		return
	_inst._cfg.set_value("daily", "done_day", DailyChallenge.absolute_day())
	_inst._save()


## Clears the daily-challenge record (used by tests to restore a clean slate).
static func reset_daily() -> void:
	if _inst != null and _inst._cfg.has_section("daily"):
		_inst._cfg.erase_section("daily")
		_inst._save()


## Wipes all shop progress (wallet, unlocks, equipped skin). Used by tests
## to restore a clean slate; also a hook for a future "reset progress".
static func reset_shop() -> void:
	if _inst == null:
		return
	for section: String in ["shop", "shop_items"]:
		if _inst._cfg.has_section(section):
			_inst._cfg.erase_section(section)
	_inst._save()


# --- Platform ----------------------------------------------------------------

## True on a touchscreen build (Android/iOS), which swaps the free-fly camera
## and click-to-place for an orbit camera and on-screen buttons. Reads only
## OS feature tags, so it works before the GameSettings instance exists and in
## --script tool runs. Passing `mobile` as a user cmdline arg forces it on for
## testing the touch path on desktop (e.g. `godot ... -- mobile`).
static func is_mobile() -> bool:
	return OS.has_feature("mobile") or "mobile" in OS.get_cmdline_user_args()
