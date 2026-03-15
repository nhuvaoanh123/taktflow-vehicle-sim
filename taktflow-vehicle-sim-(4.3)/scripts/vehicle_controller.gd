extends VehicleBody3D
## Vehicle controller — keyboard or vECU driven.
## In keyboard mode: WASD / arrows to drive.
## In vECU mode: receives actuator commands from bridge via UDP.

# Physics tuning
var max_engine_force := 600.0
var max_brake_force := 80.0
var max_steer_angle := 0.45  # radians (~26 degrees)

# vECU bridge state
var vecu_mode := false
var vecu_torque_pct := 0.0       # -1.0 to 1.0
var vecu_brake_pct := 0.0        # 0.0 to 1.0
var vecu_steer_deg := 0.0        # degrees
var vecu_kill_relay := false
var vecu_vehicle_state := "INIT"  # INIT, RUN, DEGRADED, SAFE_STOP, SHUTDOWN

# Sensor data (computed from physics each frame)
var sensor_data := {}

# Brake light state
var _braking := false

# Thermal model (simple)
var motor_temp_c := 25.0
var motor_current_a := 0.0

func _ready() -> void:
	# Connect to UDP bridge if autoloaded
	if UdpClient:
		UdpClient.actuator_data_received.connect(_on_actuator_data)

func _physics_process(delta: float) -> void:
	if vecu_mode:
		_apply_vecu_commands(delta)
	else:
		_apply_keyboard_input()

	_update_sensor_data()
	_update_thermal_model(delta)
	_update_brake_lights()

	# Send sensor data to bridge at physics rate
	if vecu_mode and UdpClient:
		var car_idx: int = get_meta("car_index", 0)
		UdpClient.send_sensor_data(sensor_data, car_idx)

# ── Keyboard Control ─────────────────────────────────────────

func _apply_keyboard_input() -> void:
	var throttle := Input.get_action_strength("accelerate")
	var brake_input := Input.get_action_strength("brake")
	var steer_input := Input.get_axis("steer_right", "steer_left")
	var estop := Input.is_action_pressed("estop")

	if estop:
		engine_force = 0.0
		brake = max_brake_force
		_braking = true
		return

	engine_force = throttle * max_engine_force
	brake = brake_input * max_brake_force
	steering = steer_input * max_steer_angle
	_braking = brake_input > 0.1

# ── vECU Control ─────────────────────────────────────────────

func _apply_vecu_commands(_delta: float) -> void:
	if vecu_kill_relay or vecu_vehicle_state == "SHUTDOWN":
		engine_force = 0.0
		brake = max_brake_force
		steering = 0.0
		_braking = true
		return

	if vecu_vehicle_state == "SAFE_STOP":
		engine_force = 0.0
		brake = max_brake_force * 0.7
		# Keep current steering
		_braking = true
		return

	engine_force = vecu_torque_pct * max_engine_force
	brake = vecu_brake_pct * max_brake_force
	steering = deg_to_rad(clampf(vecu_steer_deg, -26.0, 26.0))
	_braking = vecu_brake_pct > 0.1

func _on_actuator_data(data: Dictionary) -> void:
	var car_idx: int = get_meta("car_index", 0)
	var target_idx: int = data.get("car_index", 0)
	if target_idx != car_idx:
		return

	vecu_torque_pct = data.get("motor_torque_pct", 0.0)
	vecu_brake_pct = data.get("brake_force_pct", 0.0)
	vecu_steer_deg = data.get("steer_cmd_deg", 0.0)
	vecu_kill_relay = data.get("kill_relay", false)
	vecu_vehicle_state = data.get("vehicle_state", "RUN")

# ── Sensor Data ──────────────────────────────────────────────

func _update_sensor_data() -> void:
	var speed_ms := linear_velocity.length()
	var speed_kmh := speed_ms * 3.6

	# Wheel RPMs
	var wheel_rpms := []
	for child in get_children():
		if child is VehicleWheel3D:
			wheel_rpms.append(child.get_rpm())

	# Motor current proportional to applied force
	motor_current_a = absf(engine_force) / max_engine_force * 25.0

	# Motor RPM from rear wheel average
	var motor_rpm := 0.0
	if wheel_rpms.size() >= 4:
		motor_rpm = absf(wheel_rpms[2] + wheel_rpms[3]) / 2.0

	sensor_data = {
		"car_index": get_meta("car_index", 0),
		"timestamp_ms": Time.get_ticks_msec(),
		"vehicle_speed_kmh": speed_kmh,
		"wheel_rpm": wheel_rpms,
		"motor_rpm": motor_rpm,
		"motor_current_a": motor_current_a,
		"motor_temp_c": motor_temp_c,
		"battery_voltage_v": 12.6,
		"steer_angle_deg": rad_to_deg(steering),
		"brake_active": _braking,
		"position": {"x": global_position.x, "y": global_position.y, "z": global_position.z},
		"rotation_y": global_rotation_degrees.y,
	}

# ── Thermal Model ────────────────────────────────────────────

func _update_thermal_model(delta: float) -> void:
	var ambient := 25.0
	var heat_input := motor_current_a * motor_current_a * 0.01  # I²R heating
	var cooling := (motor_temp_c - ambient) * 0.05  # passive cooling
	motor_temp_c += (heat_input - cooling) * delta
	motor_temp_c = clampf(motor_temp_c, ambient, 150.0)

# ── Brake Lights ─────────────────────────────────────────────

func _update_brake_lights() -> void:
	for child in get_children():
		if child is MeshInstance3D and child.name.begins_with("BrakeLight"):
			var mat := child.mesh.material as StandardMaterial3D
			if mat:
				if _braking:
					mat.albedo_color = Color(1, 0, 0)
					mat.emission_enabled = true
					mat.emission = Color(1, 0, 0)
					mat.emission_energy_multiplier = 3.0
				else:
					mat.albedo_color = Color(0.5, 0, 0)
					mat.emission_enabled = false
