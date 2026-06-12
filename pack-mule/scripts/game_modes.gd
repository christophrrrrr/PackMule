class_name GameModes

## The three physics modes, cycled with M. The selection takes effect on
## the next run (scene reload); `selected` is a script static so it
## survives reload_current_scene().
##
## "Realistic" is the original v0.1 physics. "Steady" keeps everything
## dynamic but grippy and damped, so towers wobble far less. "Sticky"
## additionally glues each object in place once it settles — but the glue
## is breakable: an impact with momentum (mass * speed) above
## break_momentum knocks the hit piece loose, everything resting on it
## wakes too, and loose pieces re-glue wherever they come to rest.
## At 250 kg*m/s only the heavy pieces arriving with real speed can crack
## it (piano needs a ~40 cm fall; the rubber duck never can).

const MODES := [
	{
		"name": "Realistic",
		"friction": 0.9,
		"bounce": 0.0,
		"linear_damp": 0.0,
		"angular_damp": 1.0,
		"freeze_settled": false,
		"break_momentum": 0.0,
	},
	{
		"name": "Steady",
		"friction": 1.6,
		"bounce": 0.0,
		"linear_damp": 0.6,
		"angular_damp": 6.0,
		"freeze_settled": false,
		"break_momentum": 0.0,
	},
	{
		"name": "Sticky",
		"friction": 1.6,
		"bounce": 0.0,
		"linear_damp": 0.6,
		"angular_damp": 6.0,
		"freeze_settled": true,
		"break_momentum": 250.0,
	},
]

static var selected := 0
