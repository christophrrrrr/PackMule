class_name ShopCatalog

## The between-run shop. Cash banked across runs accumulates in a wallet
## (GameSettings) that is spent here on mounts (the base you stack on) and
## saddle skins. Item ids are stored via GameSettings.owns/buy and read by
## the game manager live (the equipped skin / mount).

const SKINS := [
	{"id": "skin_red", "name": "Classic Red", "price": 0},
	{"id": "skin_blue", "name": "Royal Blue", "price": 1500},
	{"id": "skin_green", "name": "Racing Green", "price": 2500},
	{"id": "skin_pink", "name": "Bubblegum", "price": 2500},
	{"id": "skin_gold", "name": "Gold Rush", "price": 6000},
]

## Mounts replace the donkey as the base you stack on. Each is a model that
## gets normalized and given a saddle platform exactly like the donkey.
const MOUNTS := [
	{"id": "base_donkey", "name": "Donkey", "price": 0,
		"path": "res://assets/Donkey.glb", "desc": "The original pack mule."},
	{"id": "base_goat", "name": "Mountain Goat", "price": 2500,
		"path": "res://assets/Goat.glb", "desc": "Sure-footed and stubborn."},
	{"id": "base_horse", "name": "Horse", "price": 3500,
		"path": "res://assets/Horse.glb", "desc": "A longer, steadier back."},
	{"id": "base_stag", "name": "Stag", "price": 5000,
		"path": "res://assets/Stag.glb", "desc": "Antlers optional, not load-bearing."},
	{"id": "base_bull", "name": "Bull", "price": 6500,
		"path": "res://assets/Bull.glb", "desc": "Broad and unbothered."},
	{"id": "base_moto", "name": "Motorcycle", "price": 8000,
		"path": "res://assets/Motorcycle.glb", "desc": "Who needs an animal?"},
	{"id": "base_elephant", "name": "Elephant", "price": 10000,
		"path": "res://assets/Elephant.glb", "desc": "The widest platform in the shop."},
]

const DEFAULT_BASE := "base_donkey"
const DEFAULT_SKIN := "skin_red"


## The price of any item by id (0 if unknown / free).
static func price(id: String) -> int:
	for group: Array in [SKINS, MOUNTS]:
		for item: Dictionary in group:
			if item["id"] == id:
				return int(item["price"])
	return 0


## The model path for a mount id (the donkey by default).
static func base_path(id: String) -> String:
	for item: Dictionary in MOUNTS:
		if item["id"] == id:
			return str(item["path"])
	return "res://assets/Donkey.glb"


## The saddle-blanket color for a skin id.
static func skin_color(id: String) -> Color:
	match id:
		"skin_blue": return Color(0.16, 0.34, 0.78)
		"skin_green": return Color(0.13, 0.46, 0.22)
		"skin_pink": return Color(0.92, 0.30, 0.62)
		"skin_gold": return Color(0.86, 0.66, 0.16)
		_: return Color(0.55, 0.15, 0.15)  # classic red
