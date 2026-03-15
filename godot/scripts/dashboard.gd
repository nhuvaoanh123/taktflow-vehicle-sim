extends Control
## Telemetry-style dashboard HUD with fixed pixel layout.

var _labels := {}
var _ecu_dots := {}
var _temp_bar: ColorRect
var _reset_btn: Button

const C_GOOD := Color(0.2, 0.9, 0.35)
const C_WARN := Color(1.0, 0.8, 0.1)
const C_FAULT := Color(1.0, 0.15, 0.1)
const C_TEXT := Color(0.9, 0.93, 1.0)
const C_DIM := Color(0.45, 0.5, 0.6)
const C_BG := Color(0.03, 0.03, 0.08, 0.85)

func _ready() -> void:
	_build()

func _process(_delta: float) -> void:
	_update()

func _build() -> void:
	# All UI uses absolute positions from screen edges

	# ── BOTTOM LEFT: RPM / Steer / Lidar ──
	var bl := _panel(8, -88, 200, 80, "bottom_left")
	_dim_label(bl, 8, 4, 10, "RPM")
	_labels["rpm"] = _val_label(bl, 8, 16, 26, "0")
	_dim_label(bl, 8, 46, 10, "STEER")
	_labels["steer"] = _val_label(bl, 8, 58, 16, "0.0°")
	_dim_label(bl, 110, 4, 10, "LIDAR")
	_labels["lidar"] = _val_label(bl, 110, 16, 26, "12.0")
	_dim_label(bl, 110, 46, 10, "m")

	# ── BOTTOM CENTER: Speed + Gear ──
	var bc := _panel(-80, -88, 160, 80, "bottom_center")
	_labels["gear"] = _val_label(bc, 8, 8, 32, "N")
	_labels["speed"] = _val_label(bc, 45, 2, 54, "0")
	_labels["speed_unit"] = _dim_label(bc, 120, 35, 14, "km/h")

	# ── BOTTOM RIGHT: Temp / Battery / Current ──
	var br := _panel(-208, -88, 200, 80, "bottom_right")
	_dim_label(br, 8, 4, 10, "MOTOR °C")
	_labels["temp"] = _val_label(br, 8, 16, 26, "25")
	# Temp bar background
	var bar_bg := ColorRect.new()
	bar_bg.position = Vector2(8, 48)
	bar_bg.size = Vector2(80, 5)
	bar_bg.color = Color(0.15, 0.15, 0.2)
	br.add_child(bar_bg)
	_temp_bar = ColorRect.new()
	_temp_bar.position = Vector2(8, 48)
	_temp_bar.size = Vector2(0, 5)
	_temp_bar.color = C_GOOD
	br.add_child(_temp_bar)

	_dim_label(br, 110, 4, 10, "BATTERY")
	_labels["voltage"] = _val_label(br, 110, 16, 26, "12.6")
	_dim_label(br, 110, 46, 10, "CURRENT")
	_labels["current"] = _val_label(br, 110, 58, 16, "0.0 A")

	# ── TOP LEFT: State + Car ──
	var tl := _panel(8, 8, 180, 50, "top_left")
	_labels["state"] = _val_label(tl, 8, 2, 22, "KEYBOARD")
	_labels["car"] = _val_label(tl, 8, 28, 12, "Car 1 — Blue")
	_labels["car"].add_theme_color_override("font_color", C_DIM)

	# Root cause panel (only visible during SAFE_STOP)
	var rc := _panel(8, 65, 300, 40, "top_left")
	_labels["root_cause"] = _val_label(rc, 8, 4, 11, "")
	_labels["root_cause"].add_theme_color_override("font_color", C_FAULT)
	_labels["root_cause_title"] = _dim_label(rc, 8, 22, 9, "")
	rc.name = "RootCausePanel"

	# ── TOP RIGHT: ECU + Reset Button ──
	var tr := _panel(-150, 8, 142, 140, "top_right")
	_dim_label(tr, 8, 4, 10, "ECU STATUS")
	var ecu_names := ["CVC", "RZC", "FZC", "SC"]
	for i in range(4):
		var y := 22 + i * 18
		var dot := ColorRect.new()
		dot.position = Vector2(8, y + 2)
		dot.size = Vector2(8, 8)
		dot.color = C_DIM
		tr.add_child(dot)
		_ecu_dots[ecu_names[i]] = dot
		_val_label(tr, 24, y, 12, ecu_names[i])

	# Reset button
	_reset_btn = Button.new()
	_reset_btn.text = "RESET ECU"
	_reset_btn.position = Vector2(8, 100)
	_reset_btn.custom_minimum_size = Vector2(126, 30)
	_reset_btn.add_theme_font_size_override("font_size", 11)
	_reset_btn.pressed.connect(_on_reset_pressed)
	tr.add_child(_reset_btn)

	# ── Controls hint ──
	var hint_label := Label.new()
	hint_label.text = "WASD=drive  C=cam  Tab=car  V=vECU  Space=stop  R=reset  F=faults"
	hint_label.add_theme_font_size_override("font_size", 10)
	hint_label.add_theme_color_override("font_color", Color(0.35, 0.38, 0.45, 0.5))
	hint_label.position = Vector2(200, 8)
	add_child(hint_label)

# ── Panel helper (anchored to screen edges) ──

func _panel(x: int, y: int, w: int, h: int, anchor_mode: String) -> Control:
	var container := Control.new()

	# Background
	var bg := ColorRect.new()
	bg.color = C_BG
	bg.size = Vector2(w, h)
	bg.position = Vector2.ZERO
	container.add_child(bg)

	container.size = Vector2(w, h)

	match anchor_mode:
		"bottom_left":
			container.anchor_left = 0.0
			container.anchor_top = 1.0
			container.offset_left = x
			container.offset_top = y
		"bottom_center":
			container.anchor_left = 0.5
			container.anchor_top = 1.0
			container.offset_left = x
			container.offset_top = y
		"bottom_right":
			container.anchor_left = 1.0
			container.anchor_top = 1.0
			container.offset_left = x
			container.offset_top = y
		"top_left":
			container.anchor_left = 0.0
			container.anchor_top = 0.0
			container.offset_left = x
			container.offset_top = y
		"top_right":
			container.anchor_left = 1.0
			container.anchor_top = 0.0
			container.offset_left = x
			container.offset_top = y

	add_child(container)
	return container

func _val_label(parent: Control, x: int, y: int, sz: int, txt: String) -> Label:
	var l := Label.new()
	l.text = txt
	l.position = Vector2(x, y)
	l.add_theme_color_override("font_color", C_TEXT)
	l.add_theme_font_size_override("font_size", sz)
	parent.add_child(l)
	return l

func _dim_label(parent: Control, x: int, y: int, sz: int, txt: String) -> Label:
	var l := _val_label(parent, x, y, sz, txt)
	l.add_theme_color_override("font_color", C_DIM)
	return l

# ── Reset ECU ──

func _on_reset_pressed() -> void:
	print("[HUD] ECU Reset — sending to bridge")
	_reset_btn.text = "RESETTING..."
	_reset_btn.disabled = true

	# Send reset command to bridge on Pi via UDP port 5099
	var sock := PacketPeerUDP.new()
	sock.set_dest_address("192.168.0.195", 5099)
	var cmd := JSON.stringify({"cmd": "reset_ecu"})
	sock.put_packet(cmd.to_utf8_buffer())
	sock.close()

	# Reset local state
	var main := get_tree().root.get_node_or_null("Main")
	if main:
		for car in main.get("cars"):
			car.set("vecu_vehicle_state", "INIT")
			car.set("vecu_kill_relay", false)
			car.set("vecu_torque_pct", 0.0)
			car.set("vecu_brake_pct", 0.0)

	# Re-enable button after delay
	get_tree().create_timer(5.0).timeout.connect(_on_reset_done)

func _on_reset_done() -> void:
	_reset_btn.text = "RESET ECU"
	_reset_btn.disabled = false

# ── Update ──

func _update() -> void:
	var main := get_tree().root.get_node_or_null("Main")
	if not main:
		return
	var cars: Array = main.get("cars")
	var idx: int = main.get("active_car_index")
	if idx < 0 or idx >= cars.size():
		return

	var car: VehicleBody3D = cars[idx]
	var sd: Dictionary = car.get("sensor_data")
	if sd.is_empty():
		return

	var vecu: bool = car.get("vecu_mode")

	_labels["speed"].text = "%.0f" % sd.get("vehicle_speed_kmh", 0.0)
	_labels["rpm"].text = "%.0f" % sd.get("motor_rpm", 0.0)
	_labels["steer"].text = "%.1f°" % sd.get("steer_angle_deg", 0.0)

	# Gear
	var ef: float = car.get("engine_force")
	if ef < -5.0:
		_labels["gear"].text = "R"
		_labels["gear"].add_theme_color_override("font_color", C_WARN)
	elif ef > 5.0:
		_labels["gear"].text = "D"
		_labels["gear"].add_theme_color_override("font_color", C_GOOD)
	else:
		_labels["gear"].text = "N"
		_labels["gear"].add_theme_color_override("font_color", C_DIM)

	# Temp
	var temp: float = sd.get("motor_temp_c", 25.0)
	_labels["temp"].text = "%.0f" % temp
	var temp_color := C_TEXT
	if temp > 90:
		temp_color = C_FAULT
	elif temp > 70:
		temp_color = C_WARN
	_labels["temp"].add_theme_color_override("font_color", temp_color)

	var temp_pct := clampf((temp - 25.0) / 125.0, 0.0, 1.0)
	_temp_bar.size.x = temp_pct * 80
	_temp_bar.color = temp_color if temp > 70 else C_GOOD

	_labels["voltage"].text = "%.1f" % sd.get("battery_voltage_v", 12.6)
	_labels["current"].text = "%.1f A" % sd.get("motor_current_a", 0.0)

	# Lidar
	var lidar: float = sd.get("lidar_distance_m", 12.0)
	_labels["lidar"].text = "%.1f" % lidar
	if lidar < 2.0:
		_labels["lidar"].add_theme_color_override("font_color", C_FAULT)
	elif lidar < 5.0:
		_labels["lidar"].add_theme_color_override("font_color", C_WARN)
	else:
		_labels["lidar"].add_theme_color_override("font_color", C_TEXT)

	# State
	var state_str: String = car.get("vecu_vehicle_state") if vecu else "KEYBOARD"
	_labels["state"].text = state_str
	match state_str:
		"RUN", "KEYBOARD":
			_labels["state"].add_theme_color_override("font_color", C_GOOD)
		"DEGRADED", "LIMP":
			_labels["state"].add_theme_color_override("font_color", C_WARN)
		"SAFE_STOP", "SHUTDOWN":
			_labels["state"].add_theme_color_override("font_color", C_FAULT)
		_:
			_labels["state"].add_theme_color_override("font_color", C_TEXT)

	var names := ["Blue", "Red", "Green"]
	_labels["car"].text = "Car %d — %s" % [idx + 1, names[idx % names.size()]]

	# Root cause (visible only when not in RUN/KEYBOARD)
	var rc_panel := get_node_or_null("RootCausePanel")
	if state_str == "SAFE_STOP" or state_str == "SHUTDOWN":
		var cause: String = car.get("vecu_root_cause")
		if cause.length() > 0:
			_labels["root_cause"].text = cause
			_labels["root_cause_title"].text = "ROOT CAUSE:"
		else:
			_labels["root_cause"].text = "Unknown — check ECU logs"
			_labels["root_cause_title"].text = "ROOT CAUSE:"
		if rc_panel:
			rc_panel.visible = true
	else:
		_labels["root_cause"].text = ""
		_labels["root_cause_title"].text = ""
		if rc_panel:
			rc_panel.visible = false
