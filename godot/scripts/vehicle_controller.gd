extends VehicleBody3D
## Vehicle controller — keyboard, vECU, or AI driven.

# Physics tuning
var max_engine_force := 2500.0
var max_brake_force := 120.0
var max_steer_angle := 0.4
var max_reverse_force := 800.0

# Control mode
var vecu_mode := false
var ai_mode := false

# vECU state
var vecu_torque_pct := 0.0
var vecu_brake_pct := 0.0
var vecu_steer_deg := 0.0
var vecu_kill_relay := false
var vecu_vehicle_state := "INIT"
var vecu_root_cause := ""
var vecu_active_dtcs: Array = []

# AI state
var ai_speed_target := 60.0  # km/h
var ai_wander_timer := 0.0
var ai_steer_target := 0.0
var ai_lane_offset := 0.0

# User input (captured even in vECU mode for forwarding to bridge)
var user_pedal_pct := 0.0
var user_steer_deg := 0.0
var user_brake_pct := 0.0
var user_estop := false

# Sensor data
var sensor_data := {}
var _braking := false
var motor_temp_c := 25.0
var motor_current_a := 0.0
var lidar_distance_m := 12.0

func _ready() -> void:
	if UdpClient:
		UdpClient.actuator_data_received.connect(_on_actuator_data)
	# Exclude own body from lidar raycast
	call_deferred("_setup_lidar")

func _physics_process(delta: float) -> void:
	# Always capture user input (for forwarding to bridge in vECU mode)
	_capture_user_input()

	if vecu_mode:
		# In vECU mode, disable all input until state is RUN
		if vecu_vehicle_state == "INIT" or vecu_vehicle_state == "SAFE_STOP" or vecu_vehicle_state == "SHUTDOWN":
			engine_force = 0.0
			brake = max_brake_force * 0.5
			_braking = true
		else:
			_apply_vecu_commands(delta)
	elif ai_mode:
		_apply_ai(delta)
	else:
		_apply_keyboard_input()

	_update_lidar()
	_update_sensor_data()
	_update_thermal_model(delta)
	_update_brake_lights()

	if vecu_mode and UdpClient:
		UdpClient.send_sensor_data(sensor_data, get_meta("car_index", 0))

# ── User Input Capture (always runs, even in vECU mode) ──────

func _capture_user_input() -> void:
	user_pedal_pct = Input.get_action_strength("accelerate") * 100.0
	user_brake_pct = Input.get_action_strength("brake") * 100.0
	user_steer_deg = Input.get_axis("steer_right", "steer_left") * 23.0
	user_estop = Input.is_action_pressed("estop")

# ── Keyboard ─────────────────────────────────────────────────

func _apply_keyboard_input() -> void:
	var throttle := Input.get_action_strength("accelerate")
	var brake_input := Input.get_action_strength("brake")
	var steer_input := Input.get_axis("steer_right", "steer_left")

	if Input.is_action_pressed("estop"):
		engine_force = 0.0
		brake = max_brake_force
		_braking = true
		return

	var speed_forward := linear_velocity.dot(global_transform.basis.z)

	if brake_input > 0.1 and speed_forward > -1.0:
		engine_force = -brake_input * max_reverse_force
		brake = 0.0
		_braking = false
	elif brake_input > 0.1:
		engine_force = 0.0
		brake = brake_input * max_brake_force
		_braking = true
	elif throttle > 0.1:
		engine_force = throttle * max_engine_force
		brake = 0.0
		_braking = false
	else:
		engine_force = 0.0
		brake = 0.0
		_braking = false

	steering = steer_input * max_steer_angle

# ── AI ───────────────────────────────────────────────────────

func _apply_ai(delta: float) -> void:
	var speed_kmh := linear_velocity.length() * 3.6

	# Wander: gently change lane / steer
	ai_wander_timer -= delta
	if ai_wander_timer <= 0:
		ai_wander_timer = randf_range(2.0, 6.0)
		ai_lane_offset = randf_range(-4.0, 4.0)
		ai_speed_target = randf_range(40.0, 90.0)

	# Steer toward lane offset
	var pos_x := global_position.x
	var steer_error := (ai_lane_offset - pos_x) * 0.05
	ai_steer_target = clampf(steer_error, -0.3, 0.3)
	steering = lerpf(steering, ai_steer_target, 3.0 * delta)

	# Lidar braking
	if lidar_distance_m < 4.0:
		engine_force = 0.0
		brake = max_brake_force * 0.8
		_braking = true
		return
	elif lidar_distance_m < 8.0:
		ai_speed_target = minf(ai_speed_target, 30.0)

	# Speed control
	if speed_kmh < ai_speed_target - 5:
		engine_force = max_engine_force * 0.6
		brake = 0.0
		_braking = false
	elif speed_kmh > ai_speed_target + 5:
		engine_force = 0.0
		brake = max_brake_force * 0.3
		_braking = true
	else:
		engine_force = max_engine_force * 0.2
		brake = 0.0
		_braking = false

	# Keep on road — steer back if too far
	if absf(pos_x) > 10.0:
		var correction: float = -sign(pos_x) * 0.3
		steering = lerpf(steering, correction, 5.0 * delta)

# ── vECU ─────────────────────────────────────────────────────

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
		_braking = true
		return

	engine_force = vecu_torque_pct * max_engine_force
	brake = vecu_brake_pct * max_brake_force
	steering = deg_to_rad(clampf(vecu_steer_deg, -23.0, 23.0))
	_braking = vecu_brake_pct > 0.1

func _on_actuator_data(data: Dictionary) -> void:
	if data.get("car_index", 0) != get_meta("car_index", 0):
		return
	vecu_torque_pct = data.get("motor_torque_pct", 0.0)
	vecu_brake_pct = data.get("brake_force_pct", 0.0)
	vecu_steer_deg = data.get("steer_cmd_deg", 0.0)
	vecu_kill_relay = data.get("kill_relay", false)
	vecu_vehicle_state = data.get("vehicle_state", "RUN")
	var causes: Array = data.get("root_cause", [])
	vecu_root_cause = ", ".join(PackedStringArray(causes)) if causes.size() > 0 else ""
	vecu_active_dtcs = data.get("active_dtcs", [])

# ── Lidar ────────────────────────────────────────────────────

func _setup_lidar() -> void:
	var ray := get_node_or_null("LidarRay") as RayCast3D
	if ray:
		ray.add_exception(self)

func _update_lidar() -> void:
	var ray := get_node_or_null("LidarRay") as RayCast3D
	if not ray:
		return
	ray.force_raycast_update()
	if ray.is_colliding():
		lidar_distance_m = ray.global_position.distance_to(ray.get_collision_point())
	else:
		lidar_distance_m = 12.0

# ── Sensors ──────────────────────────────────────────────────

func _update_sensor_data() -> void:
	var speed_kmh := linear_velocity.length() * 3.6
	motor_current_a = absf(engine_force) / max_engine_force * 25.0

	var wheel_rpms := []
	var motor_rpm := 0.0
	for child in get_children():
		if child is VehicleWheel3D:
			wheel_rpms.append(child.get_rpm())
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
		"battery_voltage_v": 12.6 - motor_current_a * 0.02,
		"steer_angle_deg": rad_to_deg(steering),
		"brake_active": _braking,
		"lidar_distance_m": lidar_distance_m,
		"position": {"x": global_position.x, "y": global_position.y, "z": global_position.z},
		"rotation_y": global_rotation_degrees.y,
		# User input — forwarded by bridge to CVC SPI
		"pedal_pct": user_pedal_pct,
		"steer_input_deg": user_steer_deg,
		"brake_input_pct": user_brake_pct,
		"estop_input": user_estop,
	}

# ── Thermal (fixed: proper cooling when idle) ────────────────

func _update_thermal_model(delta: float) -> void:
	var ambient := 25.0
	var heat := motor_current_a * motor_current_a * 0.005
	var cool := (motor_temp_c - ambient) * 0.15
	motor_temp_c += (heat - cool) * delta
	motor_temp_c = clampf(motor_temp_c, ambient, 150.0)

# ── Brake Lights ─────────────────────────────────────────────

func _update_brake_lights() -> void:
	for child in get_children():
		if child is MeshInstance3D and child.name.begins_with("BrakeLight"):
			var mat: StandardMaterial3D = child.mesh.material
			if mat:
				if _braking:
					mat.albedo_color = Color(1, 0, 0)
					mat.emission_enabled = true
					mat.emission = Color(1, 0, 0)
					mat.emission_energy_multiplier = 3.0
				else:
					mat.albedo_color = Color(0.4, 0, 0)
					mat.emission_enabled = false
