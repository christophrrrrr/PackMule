class_name DailyChallenge

## The daily challenge. 20 challenges cycle by calendar day (the same one for
## everyone on a given UTC day), so a player gets a fresh goal each day and the
## set repeats every 20 days. Each challenge is met when a single run's stat
## (see GameManager._run_stats: height / objects / banked / weight / multiplier
## / cashouts) reaches the target.

const CHALLENGES := [
	{"metric": "height", "target": 8.0, "text": "Reach 8 m tall"},
	{"metric": "objects", "target": 8.0, "text": "Stack 8 objects"},
	{"metric": "banked", "target": 500.0, "text": "Bank $500 in one run"},
	{"metric": "multiplier", "target": 3.0, "text": "Reach a x3 multiplier"},
	{"metric": "weight", "target": 800.0, "text": "Carry 800 kg of cargo"},
	{"metric": "height", "target": 12.0, "text": "Reach 12 m tall"},
	{"metric": "cashouts", "target": 2.0, "text": "Cash out twice in a run"},
	{"metric": "objects", "target": 12.0, "text": "Stack 12 objects"},
	{"metric": "banked", "target": 1500.0, "text": "Bank $1,500 in one run"},
	{"metric": "multiplier", "target": 6.0, "text": "Reach a x6 multiplier"},
	{"metric": "height", "target": 16.0, "text": "Reach 16 m tall"},
	{"metric": "weight", "target": 1500.0, "text": "Haul 1,500 kg in one run"},
	{"metric": "objects", "target": 18.0, "text": "Stack 18 objects"},
	{"metric": "banked", "target": 4000.0, "text": "Bank $4,000 in one run"},
	{"metric": "cashouts", "target": 4.0, "text": "Cash out 4 times in a run"},
	{"metric": "multiplier", "target": 8.0, "text": "Reach a x8 multiplier"},
	{"metric": "height", "target": 20.0, "text": "Reach a dizzying 20 m"},
	{"metric": "objects", "target": 25.0, "text": "Stack 25 objects"},
	{"metric": "banked", "target": 8000.0, "text": "Bank $8,000 in one run"},
	{"metric": "multiplier", "target": 11.0, "text": "Reach a x11 multiplier"},
]


## Whole days since the Unix epoch (UTC) — the cycle key.
static func absolute_day() -> int:
	return int(floor(Time.get_unix_time_from_system() / 86400.0))


static func today_index() -> int:
	return absolute_day() % CHALLENGES.size()


static func today() -> Dictionary:
	return CHALLENGES[today_index()]


## True once a run's stats reach the challenge's target.
static func is_met(challenge: Dictionary, stats: Dictionary) -> bool:
	return float(stats.get(challenge["metric"], 0.0)) >= float(challenge["target"])
