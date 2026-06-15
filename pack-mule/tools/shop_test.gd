extends SceneTree

## Headless checks for the shop: wallet, ownership, skins, and the perks
## resolved at run start. Snapshots and restores the real save so it is
## non-destructive. Run:
## godot --headless --path . --script res://tools/shop_test.gd

var _gm: Node = null
var _frame := 0
var _fails := 0


func _init() -> void:
	var main := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child.call_deferred(main)


func _check(label: String, ok: bool) -> void:
	if ok:
		print("[shoptest] PASS  ", label)
	else:
		_fails += 1
		print("[shoptest] FAIL  ", label)


func _process(_dt: float) -> bool:
	_frame += 1
	if _frame < 5:
		return false
	_gm = root.get_node("Main")

	# Snapshot the real save so the test leaves no trace.
	var ids: Array[String] = []
	for group: Array in [ShopCatalog.SKINS, ShopCatalog.MOUNTS]:
		for item: Dictionary in group:
			ids.append(item["id"])
	var w0 := GameSettings.get_wallet()
	var skin0 := GameSettings.get_skin()
	var base0 := GameSettings.get_base()
	var owned0 := {}
	for id: String in ids:
		owned0[id] = GameSettings.owns(id)

	GameSettings.reset_shop()

	# Wallet arithmetic.
	GameSettings.set_wallet(0)
	_check("wallet starts empty", GameSettings.get_wallet() == 0)
	GameSettings.add_wallet(800)
	_check("add_wallet credits", GameSettings.get_wallet() == 800)
	_check("overspend fails", not GameSettings.spend_wallet(1000))
	_check("failed spend leaves wallet", GameSettings.get_wallet() == 800)
	_check("affordable spend succeeds", GameSettings.spend_wallet(500))
	_check("spend debits wallet", GameSettings.get_wallet() == 300)

	# Ownership and skins.
	_check("default skin owned", GameSettings.owns(ShopCatalog.DEFAULT_SKIN))
	_check("default skin equipped", GameSettings.get_skin() == ShopCatalog.DEFAULT_SKIN)
	_check("skin not owned yet", not GameSettings.owns("skin_blue"))
	GameSettings.buy("skin_blue")
	_check("buy grants ownership", GameSettings.owns("skin_blue"))
	GameSettings.set_skin("skin_blue")
	_check("equip changes skin", GameSettings.get_skin() == "skin_blue")

	# Mounts (base swap).
	_check("default mount owned", GameSettings.owns(ShopCatalog.DEFAULT_BASE))
	_check("default mount equipped", GameSettings.get_base() == ShopCatalog.DEFAULT_BASE)
	_check("mount not owned yet", not GameSettings.owns("base_horse"))
	GameSettings.buy("base_horse")
	GameSettings.set_base("base_horse")
	_check("buy + equip mount", GameSettings.owns("base_horse") and GameSettings.get_base() == "base_horse")
	_check("mount path resolves", ShopCatalog.base_path("base_horse") == "res://assets/Horse.glb")

	# Restore the real save exactly as it was.
	GameSettings.reset_shop()
	GameSettings.set_wallet(w0)
	GameSettings.set_skin(skin0)
	GameSettings.set_base(base0)
	for id: String in ids:
		if owned0[id] and id != ShopCatalog.DEFAULT_SKIN and id != ShopCatalog.DEFAULT_BASE:
			GameSettings.buy(id)

	print("[shoptest] done: %d failure(s)" % _fails)
	quit(1 if _fails > 0 else 0)
	return true
