class_name ModifierCatalog

## The six wheel modifiers (Vision.md: size / weight / surface, all with
## tradeoffs). Size modifiers scale mass with volume, so a Massive piano
## is a huge platform AND a guaranteed glue-breaker if it ever falls,
## while a Tiny safe is a harmless pebble. "friction" of -1 keeps the
## object's default. Slippery objects never glue — a permanent live
## wobble in the tower. Super Glue bonds instantly on first contact and
## its glue can never be broken.

const ENTRIES := [
	{
		"name": "Tiny",
		"color": Color(0.45, 0.75, 1.0),
		"size_mul": 0.35, "mass_mul": 0.043,
		"friction": -1.0, "no_glue": false, "super_glue": false,
	},
	{
		"name": "Massive",
		"color": Color(1.0, 0.55, 0.2),
		"size_mul": 1.6, "mass_mul": 4.1,
		"friction": -1.0, "no_glue": false, "super_glue": false,
	},
	{
		"name": "Feather",
		"color": Color(0.95, 0.92, 0.7),
		"size_mul": 1.0, "mass_mul": 0.25,
		"friction": -1.0, "no_glue": false, "super_glue": false,
	},
	{
		"name": "Heavy",
		"color": Color(0.45, 0.45, 0.55),
		"size_mul": 1.0, "mass_mul": 3.0,
		"friction": -1.0, "no_glue": false, "super_glue": false,
	},
	{
		"name": "Slippery",
		"color": Color(0.4, 0.9, 0.9),
		"size_mul": 1.0, "mass_mul": 1.0,
		"friction": 0.1, "no_glue": true, "super_glue": false,
	},
	{
		"name": "Super Glue",
		"color": Color(0.45, 0.85, 0.4),
		"size_mul": 1.0, "mass_mul": 1.0,
		"friction": -1.0, "no_glue": false, "super_glue": true,
	},
]
