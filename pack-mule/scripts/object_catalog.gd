class_name ObjectCatalog

## The v0.1 object pool. Sizes are the target longest dimension in meters
## after normalization; masses encode the tradeoff design (Vision pillar 4):
## small+light is safe but slow, small+heavy stabilizes or crushes,
## big+light is a wobbly platform, big+heavy is a wrecking ball.

const ENTRIES := [
	{"name": "Chair", "path": "res://assets/Chair.glb", "size": 1.0, "mass": 8.0},
	{"name": "Rubber Duck", "path": "res://assets/Rubber Duck.glb", "size": 1.5, "mass": 4.0},
	{"name": "Tub", "path": "res://assets/Tub.glb", "size": 1.7, "mass": 35.0},
	{"name": "Washer", "path": "res://assets/Washer.glb", "size": 0.9, "mass": 50.0},
	{"name": "Refrigerator", "path": "res://assets/Refrigerator.glb", "size": 1.9, "mass": 70.0},
	{"name": "Safe", "path": "res://assets/Safe.glb", "size": 0.8, "mass": 100.0},
	{"name": "Couch", "path": "res://assets/Couch.glb", "size": 2.2, "mass": 40.0},
	{"name": "Piano", "path": "res://assets/Piano.glb", "size": 1.8, "mass": 90.0},
	{"name": "Lady Liberty", "path": "res://assets/Lady Liberty.glb", "size": 2.0, "mass": 60.0},
]
