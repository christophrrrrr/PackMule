class_name ShopCatalog

## The between-run shop. Cash banked across runs accumulates in a wallet
## (GameSettings) that is spent here on permanent perks, a spawn booster, and
## saddle skins. Item ids are stored via GameSettings.owns/buy and read by the
## game manager at the start of each run (perks) or live (the equipped skin).

const PERKS := [
	{"id": "head_start", "name": "Head Start", "price": 500,
		"desc": "Start each climb at a x1.5 multiplier - even right after cashing out."},
	{"id": "reinforced", "name": "Reinforced Nerves", "price": 900,
		"desc": "Shrug off one extra fallen object before the run ends."},
	{"id": "wide_saddle", "name": "Wide Saddle", "price": 700,
		"desc": "A roomier platform on the mule's back - an easier base to build on."},
	{"id": "safety_rope", "name": "Safety Rope", "price": 1500,
		"desc": "Survive your first collapse each run: the pending pot is lost, but you keep climbing."},
]

const BOOSTS := [
	{"id": "exotic", "name": "Exotic Crate", "price": 1000,
		"desc": "The wildest cargo (T-Rex, UFO, chopper, bear...) turns up far more often."},
]

const SKINS := [
	{"id": "skin_red", "name": "Classic Red", "price": 0},
	{"id": "skin_blue", "name": "Royal Blue", "price": 300},
	{"id": "skin_green", "name": "Racing Green", "price": 400},
	{"id": "skin_pink", "name": "Bubblegum", "price": 400},
	{"id": "skin_gold", "name": "Gold Rush", "price": 1200},
]

## Objects the Exotic Crate makes more common, and the weight multiplier.
const EXOTIC_NAMES := ["T-Rex", "Helicopter", "Flying Saucer", "Alien", "Bear", "Cow"]
const EXOTIC_MULT := 4.0

const DEFAULT_SKIN := "skin_red"


## The price of any item by id (0 if unknown / free).
static func price(id: String) -> int:
	for group: Array in [PERKS, BOOSTS, SKINS]:
		for item: Dictionary in group:
			if item["id"] == id:
				return int(item["price"])
	return 0


## The saddle-blanket color for a skin id.
static func skin_color(id: String) -> Color:
	match id:
		"skin_blue": return Color(0.16, 0.34, 0.78)
		"skin_green": return Color(0.13, 0.46, 0.22)
		"skin_pink": return Color(0.92, 0.30, 0.62)
		"skin_gold": return Color(0.86, 0.66, 0.16)
		_: return Color(0.55, 0.15, 0.15)  # classic red
