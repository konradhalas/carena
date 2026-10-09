extends CanvasLayer
## Player HUD: health, kills and destroyed notice for the tracked car; in a
## match also the clock and leader, a kill feed and the scoreboard (Tab, and
## automatically between matches).

const FEED_SECONDS := 4.0
const FEED_MAX := 5

@export var car: Car:
	set(value):
		if car:
			car.damaged.disconnect(_on_damaged)
		car = value
		if car:
			car.damaged.connect(_on_damaged)

## Set by the game scene in a match; null in the offline sandbox.
var match_state: MatchState:
	set(value):
		match_state = value
		if match_state:
			match_state.kill_announced.connect(_on_kill_announced)

var _flash_tween: Tween
var _clock: Label
var _feed: VBoxContainer
var _board: PanelContainer
var _board_title: Label
var _board_grid: GridContainer

@onready var _health_bar: ProgressBar = %HealthBar
@onready var _kills: Label = %Kills
@onready var _destroyed: Label = %Destroyed
@onready var _damage_flash: ColorRect = %DamageFlash


func _ready() -> void:
	_build_match_ui()


func _process(_delta: float) -> void:
	_update_match_ui()
	var has_car := is_instance_valid(car)
	for node in [%HealthBar, %Kills, %Destroyed]:
		node.visible = has_car and (node != %Destroyed or car.is_destroyed)
	if _board.visible:
		%Destroyed.visible = false  # the scoreboard covers the same spot
	if not has_car:
		return
	_health_bar.max_value = car.max_health
	_health_bar.value = car.health
	_kills.text = "Kills: %d" % car.kills


func _on_damaged(amount: float) -> void:
	if not is_node_ready():
		return
	if _flash_tween:
		_flash_tween.kill()
	_damage_flash.color.a = clampf(0.12 + amount * 0.02, 0.0, 0.45)
	_flash_tween = create_tween()
	_flash_tween.tween_property(_damage_flash, "color:a", 0.0, 0.35)


func _on_kill_announced(killer_name: String, victim_name: String) -> void:
	var line := Label.new()
	line.text = (
		"%s  destroyed  %s" % [killer_name, victim_name]
		if killer_name
		else "%s  was wrecked" % victim_name
	)
	_style(line, 18)
	line.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_feed.add_child(line)
	while _feed.get_child_count() > FEED_MAX:
		_feed.get_child(0).free()
	var tween := line.create_tween()
	tween.tween_interval(FEED_SECONDS)
	tween.tween_property(line, "modulate:a", 0.0, 0.5)
	tween.tween_callback(line.queue_free)


func _update_match_ui() -> void:
	var in_match := match_state != null
	_clock.visible = in_match
	if not in_match:
		_board.visible = false
		return
	var results := match_state.phase == MatchState.Phase.RESULTS
	var seconds := int(ceil(match_state.time_left))
	var rows := match_state.standings()
	if results:
		_clock.text = "Next match in %d" % seconds
	else:
		var leader := ""
		if not rows.is_empty() and rows[0]["kills"] > 0:
			leader = "   ·   leader: %s (%d)" % [rows[0]["name"], rows[0]["kills"]]
		_clock.text = "%d:%02d%s" % [seconds / 60, seconds % 60, leader]

	_board.visible = results or Input.is_action_pressed("scoreboard")
	if not _board.visible:
		return
	_board_title.text = (
		"%s wins!" % match_state.winner_name
		if results and match_state.winner_name
		else "Scoreboard"
	)
	for child in _board_grid.get_children():
		child.free()
	for header in ["", "Player", "Kills", "Deaths"]:
		_add_cell(header, true, false)
	var me := multiplayer.get_unique_id()
	for i in rows.size():
		var row := rows[i]
		var mine: bool = row["peer"] == me
		_add_cell("%d." % (i + 1), false, mine)
		_add_cell(row["name"], false, mine)
		_add_cell(str(row["kills"]), false, mine)
		_add_cell(str(row["deaths"]), false, mine)


func _add_cell(text: String, header: bool, highlight: bool) -> void:
	var cell := Label.new()
	cell.text = text
	_style(cell, 20)
	if header:
		cell.modulate = Color(1, 1, 1, 0.6)
	elif highlight:
		cell.modulate = Color(1.0, 0.85, 0.3)
	_board_grid.add_child(cell)


func _build_match_ui() -> void:
	_clock = Label.new()
	_style(_clock, 26)
	_clock.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_clock.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_clock.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_clock.position.y = 12
	add_child(_clock)

	_feed = VBoxContainer.new()
	_feed.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	_feed.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_feed.position = Vector2(-24, 48)
	add_child(_feed)

	_board = PanelContainer.new()
	_board.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_board.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_board.grow_vertical = Control.GROW_DIRECTION_BOTH
	var background := StyleBoxFlat.new()
	background.bg_color = Color(0, 0, 0, 0.7)
	background.set_corner_radius_all(8)
	background.set_content_margin_all(24)
	_board.add_theme_stylebox_override("panel", background)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 16)
	_board_title = Label.new()
	_style(_board_title, 34)
	_board_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(_board_title)
	_board_grid = GridContainer.new()
	_board_grid.columns = 4
	_board_grid.add_theme_constant_override("h_separation", 32)
	column.add_child(_board_grid)
	_board.add_child(column)
	_board.visible = false
	add_child(_board)


static func _style(label: Label, size: int) -> void:
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", 6)
