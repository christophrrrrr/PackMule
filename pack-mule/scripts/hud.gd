class_name GameHud
extends CanvasLayer

signal restart_requested
signal wheel_landed(modifier: Dictionary)

@onready var _score: Label = $ScoreLabel
@onready var _height: Label = $HeightLabel
@onready var _strikes: Label = $StrikesLabel
@onready var _modifier: Label = $ModifierLabel
@onready var _incoming: Label = $IncomingLabel
@onready var _crosshair: Label = $Crosshair
@onready var _wheel: ModifierWheel = $WheelOverlay
@onready var _game_over: CenterContainer = $GameOverPanel
@onready var _go_title: Label = $GameOverPanel/Panel/Margin/Box/TitleLabel
@onready var _go_stats: Label = $GameOverPanel/Panel/Margin/Box/StatsLabel
@onready var _restart: Button = $GameOverPanel/Panel/Margin/Box/RestartButton


func _ready() -> void:
	_game_over.visible = false
	_restart.pressed.connect(func() -> void: restart_requested.emit())
	_wheel.landed.connect(func(modifier: Dictionary) -> void: wheel_landed.emit(modifier))


func spin_wheel() -> void:
	_wheel.spin()


func wheel_busy() -> bool:
	return _wheel.is_busy()


func set_score(total: int) -> void:
	_score.text = "Score: %d" % total


func set_height(meters: float) -> void:
	_height.text = "Height: %.1f m" % meters


func set_strikes(current: int, max_strikes: int) -> void:
	_strikes.text = "Fallen: %d / %d" % [current, max_strikes]


func set_modifier(text: String) -> void:
	_modifier.text = text


func set_incoming(text: String) -> void:
	_incoming.text = text


func set_crosshair(shown: bool) -> void:
	_crosshair.visible = shown


func show_game_over(reason: String, final_score: int, best_height: float) -> void:
	_go_title.text = reason
	_go_stats.text = "Final score: %d\nMax height: %.1f m" % [final_score, best_height]
	_game_over.visible = true
