extends Control
## Dashboard HUD — shows vehicle telemetry, ECU status, and safe state.

var _labels := {}
var _ecu_indicators := {}
var _speed_value := 0.0
var _rpm_value := 0.0
var _temp_value := 25.0
var _voltage_value := 12.6
var _vehicle_state := "INIT"
var _mode := "Keyboard"
var _active_car := 1

# Colors
const COLOR_GOOD := Color(0.2, 0.85, 0.3)
const COLOR_WARN := Color(1.0, 0.8, 0.1)
const COLOR_FAULT := Color(1.0, 0.2, 0.1)
const COLOR_BG := Color(0.05, 0.05, 0.1, 0.75)
const COLOR_TEXT := Color(0.9, 0.95, 1.0)

func _ready() -> void:
	_build_hud()

func _process(_delta: float) -> void:
	_read_active_car_data()
	_update_displays()

func _build_hud() -> void:
	# Bottom-left: speed + RPM cluster
	var cluster := _create_panel(Vector2(10, -180), Vector2(220, 170), "BottomLeft")
	cluster.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_labels["speed"] = _add_label(cluster, Vector2(15, 10), 42, "0")
	_labels["speed_unit"] = _add_label(cluster, Vector2(140, 30), 16, "km/h")
	_labels["rpm"] = _add_label(cluster, Vector2(15, 65), 28, "0 RPM")
	_labels["steer"] = _add_label(cluster, Vector2(15, 100), 18, "Steer: 0°")
	_labels["brake"] = _add_label(cluster, Vector2(15, 125), 18, "Brake: OFF")
	add_child(cluster)

	# Bottom-right: motor + battery
	var telemetry := _create_panel(Vector2(-240, -180), Vector2(220, 170), "BottomRight")
	telemetry.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_labels["temp_title"] = _add_label(telemetry, Vector2(15, 10), 14, "MOTOR TEMP")
	_labels["temp"] = _add_label(telemetry, Vector2(15, 28), 32, "25°C")
	_labels["current"] = _add_label(telemetry, Vector2(15, 68), 18, "Current: 0.0 A")
	_labels["voltage"] = _add_label(telemetry, Vector2(15, 93), 18, "Battery: 12.6 V")
	add_child(telemetry)

	# Top-left: vehicle state + mode
	var status := _create_panel(Vector2(10, 10), Vector2(280, 110), "TopLeft")
	_labels["state"] = _add_label(status, Vector2(15, 10), 24, "INIT")
	_labels["mode"] = _add_label(status, Vector2(15, 42), 16, "Mode: Keyboard")
	_labels["car"] = _add_label(status, Vector2(15, 65), 16, "Car 1 (blue)")
	_labels["controls"] = _add_label(status, Vector2(15, 88), 11, "WASD=drive  C=camera  V=vECU  TAB=car  SPACE=e-stop")
	add_child(status)

	# Top-right: ECU status grid
	var ecu_panel := _create_panel(Vector2(-200, 10), Vector2(180, 130), "TopRight")
	ecu_panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_add_label(ecu_panel, Vector2(15, 5), 14, "ECU STATUS")
	var ecu_names := ["CVC", "RZC", "FZC", "SC"]
	for i in range(ecu_names.size()):
		var y_pos := 28 + i * 24
		var indicator := ColorRect.new()
		indicator.size = Vector2(12, 12)
		indicator.position = Vector2(15, y_pos + 3)
		indicator.color = COLOR_GOOD
		ecu_panel.add_child(indicator)
		_ecu_indicators[ecu_names[i]] = indicator
		_add_label(ecu_panel, Vector2(35, y_pos), 16, ecu_names[i])
	add_child(ecu_panel)

func _create_panel(pos: Vector2, size_val: Vector2, panel_name: String) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.name = panel_name
	panel.position = pos
	panel.custom_minimum_size = size_val
	panel.size = size_val

	var style := StyleBoxFlat.new()
	style.bg_color = COLOR_BG
	style.corner_radius_top_left = 8
	style.corner_radius_top_right = 8
	style.corner_radius_bottom_left = 8
	style.corner_radius_bottom_right = 8
	style.border_width_left = 1
	style.border_width_right = 1
	style.border_width_top = 1
	style.border_width_bottom = 1
	style.border_color = Color(0.3, 0.35, 0.5, 0.6)
	panel.add_theme_stylebox_override("panel", style)

	return panel

func _add_label(parent: Control, pos: Vector2, font_size: int, text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.position = pos
	label.add_theme_color_override("font_color", COLOR_TEXT)
	label.add_theme_font_size_override("font_size", font_size)
	parent.add_child(label)
	return label

func _read_active_car_data() -> void:
	var main := get_tree().root.get_node_or_null("Main")
	if not main:
		return

	var cars: Array = main.get("cars")
	var idx: int = main.get("active_car_index")
	if idx < 0 or idx >= cars.size():
		return

	var car: VehicleBody3D = cars[idx]
	var data: Dictionary = car.get("sensor_data")
	if data.is_empty():
		return

	_active_car = idx + 1
	_speed_value = data.get("vehicle_speed_kmh", 0.0)
	_rpm_value = data.get("motor_rpm", 0.0)
	_temp_value = data.get("motor_temp_c", 25.0)
	_voltage_value = data.get("battery_voltage_v", 12.6)
	_vehicle_state = car.get("vecu_vehicle_state") if car.get("vecu_mode") else "KEYBOARD"
	_mode = "vECU" if car.get("vecu_mode") else "Keyboard"

	_labels["speed"].text = "%.0f" % _speed_value
	_labels["rpm"].text = "%.0f RPM" % _rpm_value
	_labels["steer"].text = "Steer: %.1f°" % data.get("steer_angle_deg", 0.0)
	_labels["brake"].text = "Brake: %s" % ("ON" if data.get("brake_active", false) else "OFF")
	_labels["current"].text = "Current: %.1f A" % data.get("motor_current_a", 0.0)

func _update_displays() -> void:
	# Temperature color
	if _temp_value > 90:
		_labels["temp"].add_theme_color_override("font_color", COLOR_FAULT)
	elif _temp_value > 70:
		_labels["temp"].add_theme_color_override("font_color", COLOR_WARN)
	else:
		_labels["temp"].add_theme_color_override("font_color", COLOR_TEXT)
	_labels["temp"].text = "%.0f°C" % _temp_value

	# Voltage
	_labels["voltage"].text = "Battery: %.1f V" % _voltage_value

	# State color
	match _vehicle_state:
		"RUN", "KEYBOARD":
			_labels["state"].add_theme_color_override("font_color", COLOR_GOOD)
		"DEGRADED", "LIMP":
			_labels["state"].add_theme_color_override("font_color", COLOR_WARN)
		"SAFE_STOP", "SHUTDOWN":
			_labels["state"].add_theme_color_override("font_color", COLOR_FAULT)
		_:
			_labels["state"].add_theme_color_override("font_color", COLOR_TEXT)
	_labels["state"].text = _vehicle_state

	_labels["mode"].text = "Mode: %s" % _mode

	var car_colors := ["blue", "red", "green"]
	var c := car_colors[(_active_car - 1) % car_colors.size()]
	_labels["car"].text = "Car %d (%s)" % [_active_car, c]
