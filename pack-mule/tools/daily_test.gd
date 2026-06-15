extends SceneTree

## Checks the daily challenge: a deterministic daily pick, the is_met rule,
## done-state persistence, and live completion through the game manager.
## Non-destructive (restores the daily record). Run:
## godot --headless --path . --script res://tools/daily_test.gd

var _gm: Node = null
var _f := 0
var _fails := 0


func _init() -> void:
	var main := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child.call_deferred(main)


func _check(label: String, ok: bool) -> void:
	if ok:
		print("[dailytest] PASS  ", label)
	else:
		_fails += 1
		print("[dailytest] FAIL  ", label)


func _process(_dt: float) -> bool:
	_f += 1
	if _f < 5:
		return false
	_gm = root.get_node("Main")
	var was_done := GameSettings.daily_done()
	GameSettings.reset_daily()

	# 20 challenges, deterministic pick within range.
	_check("twenty challenges", DailyChallenge.CHALLENGES.size() == 20)
	var idx := DailyChallenge.today_index()
	_check("today index in range", idx >= 0 and idx < 20)
	_check("today is stable", DailyChallenge.today() == DailyChallenge.today())
	_check("today has fields", DailyChallenge.today().has("metric") and DailyChallenge.today().has("target"))

	# is_met compares the run stat against the target.
	_check("is_met true at target",
			DailyChallenge.is_met({"metric": "height", "target": 10.0}, {"height": 10.0}))
	_check("is_met false below target",
			not DailyChallenge.is_met({"metric": "height", "target": 10.0}, {"height": 9.0}))

	# Persistence.
	_check("not done after reset", not GameSettings.daily_done())
	GameSettings.set_daily_done()
	_check("done after marking", GameSettings.daily_done())

	# Live completion: a run that smashes every metric finishes today's pick.
	GameSettings.reset_daily()
	_gm._start_game()
	_gm._max_height = 999.0
	_gm._placed_count = 999
	_gm._banked = 999999
	_gm._total_weight = 999999.0
	_gm._max_mult = 999.0
	_gm._cashout_count = 999
	_gm._check_daily()
	_check("run completes the daily", GameSettings.daily_done())

	# Restore the player's real daily state.
	GameSettings.reset_daily()
	if was_done:
		GameSettings.set_daily_done()

	print("[dailytest] done: %d failure(s)" % _fails)
	quit(1 if _fails > 0 else 0)
	return true
