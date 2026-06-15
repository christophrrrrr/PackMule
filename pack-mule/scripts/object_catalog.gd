class_name ObjectCatalog

## The stackable object pool. Sizes are the target longest dimension in
## meters after normalization; masses encode the tradeoff design (Vision
## pillar 4). "weight" is the spawn weight (rarity) — higher = more common.
## "sound" selects the impact sound material (wood / metal / soft / glass /
## piano / critter).

const ENTRIES := [
	{"name": "Chair", "path": "res://assets/Chair.glb", "size": 1.0, "mass": 8.0, "weight": 10.0, "sound": "wood"},
	{"name": "Rubber Duck", "path": "res://assets/Rubber Duck.glb", "size": 1.5, "mass": 4.0, "weight": 6.0, "sound": "soft"},
	{"name": "Tub", "path": "res://assets/Tub.glb", "size": 1.7, "mass": 35.0, "weight": 8.0, "sound": "metal"},
	{"name": "Washer", "path": "res://assets/Washer.glb", "size": 0.9, "mass": 50.0, "weight": 8.0, "sound": "metal"},
	{"name": "Refrigerator", "path": "res://assets/Refrigerator.glb", "size": 1.9, "mass": 70.0, "weight": 6.0, "sound": "metal"},
	{"name": "Safe", "path": "res://assets/Safe.glb", "size": 0.8, "mass": 100.0, "weight": 8.0, "sound": "metal"},
	{"name": "Couch", "path": "res://assets/Couch.glb", "size": 2.2, "mass": 40.0, "weight": 6.0, "sound": "soft"},
	{"name": "Piano", "path": "res://assets/Piano.glb", "size": 1.8, "mass": 90.0, "weight": 5.0, "sound": "piano"},
	{"name": "Lady Liberty", "path": "res://assets/Lady Liberty.glb", "size": 2.0, "mass": 60.0, "weight": 3.0, "sound": "metal"},
	{"name": "Car", "path": "res://assets/Car.glb", "size": 2.4, "mass": 120.0, "weight": 5.0, "sound": "metal"},
	{"name": "Cow", "path": "res://assets/Cow.glb", "size": 2.0, "mass": 75.0, "weight": 3.0, "sound": "cow"},
	{"name": "Rug", "path": "res://assets/Rug.glb", "size": 2.0, "mass": 6.0, "weight": 8.0, "sound": "soft"},
	{"name": "Table", "path": "res://assets/Table.glb", "size": 1.6, "mass": 15.0, "weight": 10.0, "sound": "wood"},
	{"name": "Toilet", "path": "res://assets/Toilet.glb", "size": 0.9, "mass": 25.0, "weight": 9.0, "sound": "glass"},
	{"name": "Trashcan", "path": "res://assets/Trashcan.glb", "size": 1.0, "mass": 12.0, "weight": 9.0, "sound": "metal"},
	{"name": "Bear", "path": "res://assets/Bear.glb", "size": 2.0, "mass": 140.0, "weight": 2.5, "sound": "bear"},
	{"name": "Grill", "path": "res://assets/Grill.glb", "size": 1.2, "mass": 30.0, "weight": 6.0, "sound": "metal"},
	{"name": "Helicopter", "path": "res://assets/Helicopter.glb", "size": 3.0, "mass": 200.0, "weight": 1.5, "sound": "metal"},
	{"name": "T-Rex", "path": "res://assets/T-Rex.glb", "size": 2.6, "mass": 170.0, "weight": 1.5, "sound": "trex"},
	{"name": "Windmill", "path": "res://assets/Windmill.glb", "size": 2.8, "mass": 55.0, "weight": 3.0, "sound": "wood"},
	{"name": "Alien", "path": "res://assets/Alien.glb", "size": 1.6, "mass": 45.0, "weight": 3.0, "sound": "alien"},
	{"name": "Flying Saucer", "path": "res://assets/Flying saucer.glb", "size": 2.6, "mass": 100.0, "weight": 2.0, "sound": "metal"},
	{"name": "Anvil", "path": "res://assets/Anvil.glb", "size": 0.8, "mass": 130.0, "weight": 6.0, "sound": "metal"},
	{"name": "Kitchen Oven", "path": "res://assets/Kitchen Oven.glb", "size": 1.2, "mass": 70.0, "weight": 7.0, "sound": "metal"},
]


## The default spawn weight for an object (before any player override).
static func default_weight(entry_name: String) -> float:
	for e in ENTRIES:
		if e["name"] == entry_name:
			return e["weight"]
	return 1.0
