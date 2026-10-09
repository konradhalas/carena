extends GdUnitTestSuite
## MatchState rules, run offline (this peer is the server).

var _match: MatchState


func before_test() -> void:
	_match = auto_free(MatchState.new())
	_match.kill_limit = 3
	add_child(_match)
	_match.add_player(1, "Ann")
	_match.add_player(2, "Bob")


func test_kills_and_deaths_are_counted_and_ranked() -> void:
	_match.record_kill(2, 1)
	_match.record_kill(2, 1)
	_match.record_kill(1, 2)

	var rows := _match.standings()
	assert_str(rows[0]["name"]).is_equal("Bob")
	assert_int(rows[0]["kills"]).is_equal(2)
	assert_int(rows[0]["deaths"]).is_equal(1)
	assert_int(rows[1]["kills"]).is_equal(1)
	assert_int(rows[1]["deaths"]).is_equal(2)


func test_no_credit_for_wrecking_yourself_but_it_counts_as_a_death() -> void:
	_match.record_kill(1, 1)
	_match.record_kill(0, 1)

	assert_int(_match.scores[1]["kills"]).is_equal(0)
	assert_int(_match.scores[1]["deaths"]).is_equal(2)


func test_reaching_the_kill_limit_ends_the_match() -> void:
	for i in 3:
		_match.record_kill(1, 2)

	assert_int(_match.phase).is_equal(MatchState.Phase.RESULTS)
	assert_str(_match.winner_name).is_equal("Ann")


func test_kills_during_results_are_ignored() -> void:
	for i in 3:
		_match.record_kill(1, 2)
	_match.record_kill(2, 1)

	assert_int(_match.scores[2]["kills"]).is_equal(0)


func test_running_out_of_time_ends_and_then_restarts_the_match() -> void:
	var restarts := [0]
	_match.restart_requested.connect(func(): restarts[0] += 1)
	_match.record_kill(1, 2)
	_match.time_left = 0.01
	_match._process(0.1)
	assert_int(_match.phase).is_equal(MatchState.Phase.RESULTS)

	_match.time_left = 0.01
	_match._process(0.1)

	assert_int(_match.phase).is_equal(MatchState.Phase.PLAYING)
	assert_int(restarts[0]).is_equal(1)
	assert_float(_match.time_left).is_equal(_match.time_limit)
	assert_int(_match.scores[1]["kills"]).is_equal(0)
	assert_str(_match.player_name(1)).is_equal("Ann")


func test_names_are_unique_and_never_empty() -> void:
	_match.add_player(3, "Ann")
	_match.add_player(4, "   ")

	assert_str(_match.player_name(3)).is_equal("Ann 2")
	assert_str(_match.player_name(4)).starts_with("Player")


func test_kills_are_announced() -> void:
	var announced := []
	_match.kill_announced.connect(func(killer, victim): announced.append([killer, victim]))
	_match.record_kill(1, 2)

	assert_array(announced).is_equal([["Ann", "Bob"]])
