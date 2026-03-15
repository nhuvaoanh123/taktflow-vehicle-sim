extends Control
## Fault injection panel — triggers faults via REST API to fault-inject service.
## Random mode: 10% chance every 5 seconds. Shows state transitions + DTCs.

const FAULT_API := "http://192.168.0.195:8092"

# All faults from safety analysis, mapped to REST API scenarios
const FAULTS := {
	# Sensor faults
	"F-PED-01: Pedal stuck high": "runaway_accel",
	"F-PED-02: Pedal stuck low": "torque_loss",
	"F-STR-01: Steering oscillation": "steer_fault",
	"F-MOT-04: Motor overcurrent": "overcurrent",
	"F-MOT-05: Motor overtemp": "motor_overtemp",
	"F-MOT-03: Motor reversal": "motor_reversal",
	# Actuator faults
	"F-BRK-02: Unintended braking": "unintended_braking",
	"F-MOT-02: Motor unresponsive": "torque_loss",
	"F-MOT-01: Creep from stop": "creep_from_stop",
	# Network faults
	"F-CAN-03: Babbling node": "babbling_node",
	"F-SYS-01: Heartbeat loss (FZC)": "heartbeat_loss",
	# System faults
	"F-SYS-02: Battery undervoltage": "battery_low",
	"F-SYS-03: E-Stop": "estop",
	"F-BRK-01: Brake fault": "brake_fault",
}

var _http: HTTPRequest
var _fault_list: ItemList
var _random_check: CheckBox
var _random_timer: Timer
var _ftti_timer_label: Label
var _ftti_start_ms := 0
var _ftti_active := false
var _last_state := ""
var _state_log: RichTextLabel
var _visible_panel := false

func _ready() -> void:
	_build_ui()
	_http = HTTPRequest.new()
	_http.request_completed.connect(_on_response)
	add_child(_http)

	_random_timer = Timer.new()
	_random_timer.wait_time = 5.0
	_random_timer.timeout.connect(_on_random_tick)
	add_child(_random_timer)

func _process(_delta: float) -> void:
	_update_ftti()
	_update_state_monitor()

func _input(event: InputEvent) -> void:
	# F key toggles fault panel
	if event is InputEventKey and event.pressed and event.keycode == KEY_F:
		_visible_panel = !_visible_panel
		visible = _visible_panel

func _build_ui() -> void:
	visible = false

	# Background
	var bg := ColorRect.new()
	bg.color = Color(0.02, 0.02, 0.06, 0.92)
	bg.set_anchors_preset(Control.PRESET_CENTER_RIGHT)
	bg.anchor_left = 1.0
	bg.anchor_right = 1.0
	bg.anchor_top = 0.0
	bg.anchor_bottom = 1.0
	bg.offset_left = -320
	bg.offset_right = 0
	bg.offset_top = 0
	bg.offset_bottom = 0
	add_child(bg)

	# Title
	var title := Label.new()
	title.text = "FAULT INJECTION"
	title.add_theme_font_size_override("font_size", 14)
	title.add_theme_color_override("font_color", Color(0.9, 0.3, 0.2))
	title.position = Vector2(-310, 8)
	title.anchor_left = 1.0
	bg.add_child(title)

	# Fault list
	_fault_list = ItemList.new()
	_fault_list.position = Vector2(8, 30)
	_fault_list.size = Vector2(304, 280)
	_fault_list.add_theme_font_size_override("font_size", 11)
	for fault_name in FAULTS.keys():
		_fault_list.add_item(fault_name)
	_fault_list.item_activated.connect(_on_fault_selected)
	bg.add_child(_fault_list)

	# Inject button
	var inject_btn := Button.new()
	inject_btn.text = "INJECT SELECTED"
	inject_btn.position = Vector2(8, 318)
	inject_btn.custom_minimum_size = Vector2(150, 28)
	inject_btn.add_theme_font_size_override("font_size", 11)
	inject_btn.pressed.connect(_on_inject_pressed)
	bg.add_child(inject_btn)

	# Reset button
	var reset_btn := Button.new()
	reset_btn.text = "RESET ALL"
	reset_btn.position = Vector2(165, 318)
	reset_btn.custom_minimum_size = Vector2(147, 28)
	reset_btn.add_theme_font_size_override("font_size", 11)
	reset_btn.pressed.connect(_on_reset_pressed)
	bg.add_child(reset_btn)

	# Random mode
	_random_check = CheckBox.new()
	_random_check.text = "Random (10% every 5s)"
	_random_check.add_theme_font_size_override("font_size", 11)
	_random_check.add_theme_color_override("font_color", Color(0.8, 0.8, 0.85))
	_random_check.position = Vector2(8, 354)
	_random_check.toggled.connect(_on_random_toggled)
	bg.add_child(_random_check)

	# FTTI timer
	var ftti_title := Label.new()
	ftti_title.text = "FTTI TIMER"
	ftti_title.add_theme_font_size_override("font_size", 10)
	ftti_title.add_theme_color_override("font_color", Color(0.5, 0.5, 0.6))
	ftti_title.position = Vector2(8, 382)
	bg.add_child(ftti_title)

	_ftti_timer_label = Label.new()
	_ftti_timer_label.text = "-- ms"
	_ftti_timer_label.add_theme_font_size_override("font_size", 24)
	_ftti_timer_label.add_theme_color_override("font_color", Color(0.5, 0.5, 0.6))
	_ftti_timer_label.position = Vector2(8, 396)
	bg.add_child(_ftti_timer_label)

	# State transition log
	var log_title := Label.new()
	log_title.text = "STATE LOG"
	log_title.add_theme_font_size_override("font_size", 10)
	log_title.add_theme_color_override("font_color", Color(0.5, 0.5, 0.6))
	log_title.position = Vector2(8, 432)
	bg.add_child(log_title)

	_state_log = RichTextLabel.new()
	_state_log.position = Vector2(8, 448)
	_state_log.size = Vector2(304, 260)
	_state_log.add_theme_font_size_override("normal_font_size", 10)
	_state_log.bbcode_enabled = true
	_state_log.scroll_following = true
	bg.add_child(_state_log)

# ── Fault Injection ──────────────────────────────────────────

func _on_fault_selected(idx: int) -> void:
	_trigger_fault_by_index(idx)

func _on_inject_pressed() -> void:
	var selected := _fault_list.get_selected_items()
	if selected.size() > 0:
		_trigger_fault_by_index(selected[0])

func _trigger_fault_by_index(idx: int) -> void:
	var fault_name: String = FAULTS.keys()[idx]
	var scenario: String = FAULTS[fault_name]
	_trigger_fault(fault_name, scenario)

func _trigger_fault(fault_name: String, scenario: String) -> void:
	var url := FAULT_API + "/api/fault/scenario/" + scenario
	_http.request(url, [], HTTPClient.METHOD_POST)

	# Start FTTI timer
	_ftti_start_ms = Time.get_ticks_msec()
	_ftti_active = true
	_ftti_timer_label.add_theme_color_override("font_color", Color(1, 0.8, 0.1))

	_log("[color=yellow]INJECT:[/color] " + fault_name)

func _on_reset_pressed() -> void:
	var url := FAULT_API + "/api/fault/reset"
	_http.request(url, [], HTTPClient.METHOD_POST)
	_ftti_active = false
	_ftti_timer_label.text = "-- ms"
	_ftti_timer_label.add_theme_color_override("font_color", Color(0.5, 0.5, 0.6))
	_log("[color=cyan]RESET:[/color] All faults cleared")

func _on_response(_result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	if code == 200:
		var json = JSON.parse_string(body.get_string_from_utf8())
		if json and json.has("result"):
			_log("[color=gray]API:[/color] " + str(json["result"]))
	elif code != 0:
		_log("[color=red]API ERROR:[/color] HTTP " + str(code))

# ── Random Fault Mode ────────────────────────────────────────

func _on_random_toggled(enabled: bool) -> void:
	if enabled:
		_random_timer.start()
		_log("[color=magenta]RANDOM:[/color] Enabled (10% every 5s)")
	else:
		_random_timer.stop()
		_log("[color=magenta]RANDOM:[/color] Disabled")

func _on_random_tick() -> void:
	if randf() < 0.1:
		var idx := randi() % FAULTS.size()
		var fault_name: String = FAULTS.keys()[idx]
		var scenario: String = FAULTS[fault_name]
		_trigger_fault(fault_name, scenario)
		_log("[color=magenta]RANDOM:[/color] " + fault_name)

# ── FTTI Timer ───────────────────────────────────────────────

func _update_ftti() -> void:
	if not _ftti_active:
		return
	var elapsed := Time.get_ticks_msec() - _ftti_start_ms
	_ftti_timer_label.text = "%d ms" % elapsed

	if elapsed > 500:
		_ftti_timer_label.add_theme_color_override("font_color", Color(1, 0.15, 0.1))
	elif elapsed > 200:
		_ftti_timer_label.add_theme_color_override("font_color", Color(1, 0.6, 0.1))

# ── State Monitoring ─────────────────────────────────────────

func _update_state_monitor() -> void:
	var main := get_tree().root.get_node_or_null("Main")
	if not main:
		return
	var cars: Array = main.get("cars")
	if cars.is_empty():
		return

	var car: VehicleBody3D = cars[0]
	var new_state: String = car.get("vecu_vehicle_state")

	if new_state != _last_state and _last_state != "":
		var color := "green"
		match new_state:
			"SAFE_STOP", "SHUTDOWN":
				color = "red"
				# Stop FTTI timer — safe state reached
				if _ftti_active:
					var elapsed := Time.get_ticks_msec() - _ftti_start_ms
					_ftti_active = false
					var pass_fail := "[color=green]PASS[/color]" if elapsed <= 500 else "[color=red]FAIL[/color]"
					_log("[color=white]FTTI:[/color] %d ms %s" % [elapsed, pass_fail])
			"DEGRADED", "LIMP":
				color = "yellow"
			"RUN":
				color = "green"
			"INIT":
				color = "gray"

		_log("[color=%s]STATE:[/color] %s → %s" % [color, _last_state, new_state])

	_last_state = new_state

	# Check for DTCs
	var dtcs: Array = car.get("vecu_active_dtcs")
	if dtcs.size() > 0:
		for dtc in dtcs:
			_log("[color=red]DTC:[/color] " + str(dtc))

func _log(msg: String) -> void:
	var ts := "%.1f" % (Time.get_ticks_msec() / 1000.0)
	_state_log.append_text("[%s] %s\n" % [ts, msg])
