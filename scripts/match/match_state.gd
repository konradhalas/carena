class_name MatchState
extends Node
## Server-authoritative match: players and names, kills/deaths, the clock and
## the match cycle (play until the time or kill limit, show results, restart).
## State replicates to clients through the "Sync" child; kill announcements go
## out as an RPC. Clients only read.

signal kill_announced(killer_name: String, victim_name: String)
## Server only: a match ended and the results pause is over; restart now.
signal restart_requested

enum Phase { PLAYING, RESULTS }

@export var time_limit := 300.0  ## seconds
@export var kill_limit := 10
@export var results_duration := 8.0

# Replicated state.
var phase := Phase.PLAYING
var time_left := 0.0
## peer id -> {"name": String, "kills": int, "deaths": int}
var scores := {}
var winner_name := ""


func _ready() -> void:
	time_left = time_limit


func _process(delta: float) -> void:
	if not multiplayer.is_server():
		return
	time_left = maxf(time_left - delta, 0.0)
	if time_left > 0.0:
		return
	match phase:
		Phase.PLAYING:
			_end_match()
		Phase.RESULTS:
			_start_match()
			restart_requested.emit()


func is_playing() -> bool:
	return phase == Phase.PLAYING


func add_player(peer_id: int, player_name := "") -> void:
	var entry: Dictionary = scores.get(peer_id, {"kills": 0, "deaths": 0})
	entry["name"] = _unique_name(peer_id, player_name)
	scores[peer_id] = entry
	_touch()


func remove_player(peer_id: int) -> void:
	scores.erase(peer_id)
	_touch()


func player_name(peer_id: int) -> String:
	return scores.get(peer_id, {}).get("name", "Player %d" % (peer_id % 1000))


## Server only. killer_peer_id 0 or == victim means no credit (crash, self).
func record_kill(killer_peer_id: int, victim_peer_id: int) -> void:
	if not is_playing():
		return
	if scores.has(victim_peer_id):
		scores[victim_peer_id]["deaths"] += 1
	var credited := killer_peer_id != 0 and killer_peer_id != victim_peer_id
	if credited and scores.has(killer_peer_id):
		scores[killer_peer_id]["kills"] += 1
	_touch()
	var killer := player_name(killer_peer_id) if credited else ""
	_announce_kill.rpc(killer, player_name(victim_peer_id))
	if credited and scores.get(killer_peer_id, {}).get("kills", 0) >= kill_limit:
		_end_match()


## Rows sorted best first: [{"peer": id, "name", "kills", "deaths"}].
func standings() -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	for peer_id: int in scores:
		var row: Dictionary = scores[peer_id].duplicate()
		row["peer"] = peer_id
		rows.append(row)
	rows.sort_custom(
		func(a, b): return a.kills > b.kills or (a.kills == b.kills and a.deaths < b.deaths)
	)
	return rows


func _end_match() -> void:
	var rows := standings()
	winner_name = rows[0]["name"] if not rows.is_empty() else ""
	phase = Phase.RESULTS
	time_left = results_duration


func _start_match() -> void:
	for peer_id: int in scores:
		scores[peer_id]["kills"] = 0
		scores[peer_id]["deaths"] = 0
	_touch()
	winner_name = ""
	phase = Phase.PLAYING
	time_left = time_limit


@rpc("authority", "call_local", "reliable")
func _announce_kill(killer_name: String, victim_name: String) -> void:
	kill_announced.emit(killer_name, victim_name)


## Names are trimmed, limited and made unique ("Ann", "Ann 2").
func _unique_name(peer_id: int, wanted: String) -> String:
	var base := wanted.strip_edges().left(16)
	if base.is_empty():
		base = "Player %d" % (peer_id % 1000)
	var taken := {}
	for other: int in scores:
		if other != peer_id:
			taken[scores[other]["name"]] = true
	var candidate := base
	var n := 2
	while taken.has(candidate):
		candidate = "%s %d" % [base, n]
		n += 1
	return candidate


## Dictionaries replicate when the property is reassigned, not when nested
## values change in place.
func _touch() -> void:
	scores = scores.duplicate(true)
