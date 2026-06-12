class_name GameModes

## The three physics modes, cycled with M. The selection takes effect on
## the next run (scene reload); `selected` is a script static so it
## survives reload_current_scene().
##
## "Realistic" is the original v0.1 physics. "Steady" keeps everything
## dynamic but grippy and damped, so towers wobble far less. "Sticky"
## additionally locks each object in place once it settles — only the
## object just placed can still fall.

const MODES := [
	{
		"name": "Realistic",
		"friction": 0.9,
		"bounce": 0.0,
		"linear_damp": 0.0,
		"angular_damp": 1.0,
		"freeze_settled": false,
	},
	{
		"name": "Steady",
		"friction": 1.6,
		"bounce": 0.0,
		"linear_damp": 0.6,
		"angular_damp": 6.0,
		"freeze_settled": false,
	},
	{
		"name": "Sticky",
		"friction": 1.6,
		"bounce": 0.0,
		"linear_damp": 0.6,
		"angular_damp": 6.0,
		"freeze_settled": true,
	},
]

static var selected := 0
