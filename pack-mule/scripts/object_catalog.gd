class_name ObjectCatalog

## The stackable object pool. Sizes are the target longest dimension in
## meters after normalization; masses encode the tradeoff design (Vision
## pillar 4). "weight" is the spawn weight (rarity) — higher = more common;
## the player can override these in the Odds screen.

const ENTRIES := [
	{"name": "Chair", "path": "res://assets/Chair.glb", "size": 1.0, "mass": 8.0, "weight": 10.0},
	{"name": "Rubber Duck", "path": "res://assets/Rubber Duck.glb", "size": 1.5, "mass": 4.0, "weight": 6.0},
	{"name": "Tub", "path": "res://assets/Tub.glb", "size": 1.7, "mass": 35.0, "weight": 8.0},
	{"name": "Washer", "path": "res://assets/Washer.glb", "size": 0.9, "mass": 50.0, "weight": 8.0},
	{"name": "Refrigerator", "path": "res://assets/Refrigerator.glb", "size": 1.9, "mass": 70.0, "weight": 6.0},
	{"name": "Safe", "path": "res://assets/Safe.glb", "size": 0.8, "mass": 100.0, "weight": 8.0},
	{"name": "Couch", "path": "res://assets/Couch.glb", "size": 2.2, "mass": 40.0, "weight": 6.0},
	{"name": "Piano", "path": "res://assets/Piano.glb", "size": 1.8, "mass": 90.0, "weight": 5.0},
	{"name": "Lady Liberty", "path": "res://assets/Lady Liberty.glb", "size": 2.0, "mass": 60.0, "weight": 3.0},
	{"name": "Car", "path": "res://assets/Car.glb", "size": 2.4, "mass": 120.0, "weight": 5.0},
	{"name": "Cow", "path": "res://assets/Cow.glb", "size": 2.0, "mass": 75.0, "weight": 3.0},
	{"name": "Rug", "path": "res://assets/Rug.glb", "size": 2.0, "mass": 6.0, "weight": 8.0},
	{"name": "Table", "path": "res://assets/Table.glb", "size": 1.6, "mass": 15.0, "weight": 10.0},
	{"name": "Toilet", "path": "res://assets/Toilet.glb", "size": 0.9, "mass": 25.0, "weight": 9.0},
	{"name": "Trashcan", "path": "res://assets/Trashcan.glb", "size": 1.0, "mass": 12.0, "weight": 9.0},
	{"name": "Bear", "path": "res://assets/Bear.glb", "size": 2.0, "mass": 140.0, "weight": 2.5},
	{"name": "Grill", "path": "res://assets/Grill.glb", "size": 1.2, "mass": 30.0, "weight": 6.0},
	{"name": "Helicopter", "path": "res://assets/Helicopter.glb", "size": 3.0, "mass": 200.0, "weight": 1.5},
	{"name": "T-Rex", "path": "res://assets/T-Rex.glb", "size": 2.6, "mass": 170.0, "weight": 1.5},
	{"name": "Windmill", "path": "res://assets/Windmill.glb", "size": 2.8, "mass": 55.0, "weight": 3.0},
]


## The default spawn weight for an object (before any player override).
static func default_weight(entry_name: String) -> float:
	for e in ENTRIES:
		if e["name"] == entry_name:
			return e["weight"]
	return 1.0
