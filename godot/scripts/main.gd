extends Node3D

const VehicleController = preload("res://scripts/vehicle_controller.gd")
const CameraFollow = preload("res://scripts/camera_follow.gd")
const Dashboard = preload("res://scripts/dashboard.gd")

var cars: Array[VehicleBody3D] = []
var active_car_index := 0
var camera: Camera3D
var dashboard_control: Control

# Starting positions for reset
var _start_positions := []
var _start_rotations := []

func _ready() -> void:
	_create_environment()
	_create_track()
	_create_player_car()
	_create_ai_cars(5)
	_create_camera()
	_create_dashboard()

# ── Environment ──────────────────────────────────────────────

func _create_environment() -> void:
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.3, 0.5, 0.85)
	sky_mat.sky_horizon_color = Color(0.6, 0.72, 0.85)
	sky_mat.ground_bottom_color = Color(0.12, 0.11, 0.08)
	sky_mat.ground_horizon_color = Color(0.55, 0.6, 0.65)

	var sky := Sky.new()
	sky.sky_material = sky_mat

	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.6
	env.tonemap_mode = 2
	env.ssao_enabled = true

	var world_env := WorldEnvironment.new()
	world_env.environment = env
	add_child(world_env)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, 30, 0)
	sun.light_energy = 1.3
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 300.0
	add_child(sun)

# ── Track ────────────────────────────────────────────────────

func _create_track() -> void:
	# Ground
	var ground_body := StaticBody3D.new()
	ground_body.name = "Ground"
	add_child(ground_body)
	var ground_col := CollisionShape3D.new()
	ground_col.shape = WorldBoundaryShape3D.new()
	ground_body.add_child(ground_col)
	var gv := MeshInstance3D.new()
	var gm := PlaneMesh.new()
	gm.size = Vector2(2000, 2000)
	var gmat := StandardMaterial3D.new()
	gmat.albedo_color = Color(0.22, 0.32, 0.15)
	gm.material = gmat
	gv.mesh = gm
	ground_body.add_child(gv)

	# ── Main road (North-South) — 4 lanes, 2km long ──
	_road(Vector3(0, 0.01, 0), Vector3(24, 0.05, 2000))

	# ── Cross road (East-West) — intersection at Z=200 ──
	_road(Vector3(0, 0.01, 200), Vector3(600, 0.05, 16))

	# ── Second cross road at Z=600 ──
	_road(Vector3(0, 0.01, 600), Vector3(400, 0.05, 16))

	# Lane markings — main road dashed
	for i in range(-60, 61):
		if i % 2 == 0:
			_marker(Vector3(0, 0.02, i * 16.0), Vector3(0.15, 0.02, 5.0))
			_marker(Vector3(-6, 0.02, i * 16.0), Vector3(0.15, 0.02, 5.0))
			_marker(Vector3(6, 0.02, i * 16.0), Vector3(0.15, 0.02, 5.0))

	# Lane markings — cross roads
	for i in range(-18, 19):
		if i % 2 == 0:
			_marker(Vector3(i * 16.0, 0.02, 200), Vector3(5.0, 0.02, 0.15))
			_marker(Vector3(i * 16.0, 0.02, 600), Vector3(5.0, 0.02, 0.15))

	# Road edge lines
	_road_edge(Vector3(-11.5, 0.02, 0), Vector3(0.2, 0.02, 2000))
	_road_edge(Vector3(11.5, 0.02, 0), Vector3(0.2, 0.02, 2000))

	# Guardrails (main road only, gaps at intersections)
	_barrier(Vector3(-12.5, 0.4, -400), Vector3(0.2, 0.8, 780))
	_barrier(Vector3(12.5, 0.4, -400), Vector3(0.2, 0.8, 780))
	_barrier(Vector3(-12.5, 0.4, 420), Vector3(0.2, 0.8, 340))
	_barrier(Vector3(12.5, 0.4, 420), Vector3(0.2, 0.8, 340))
	_barrier(Vector3(-12.5, 0.4, 800), Vector3(0.2, 0.8, 380))
	_barrier(Vector3(12.5, 0.4, 800), Vector3(0.2, 0.8, 380))

	# Obstacles
	_obstacle(Vector3(-3, 0.5, 150), Color(1.0, 0.5, 0.0))
	_obstacle(Vector3(4, 0.5, 350), Color(1.0, 0.5, 0.0))
	_obstacle(Vector3(-5, 0.5, 500), Color(0.9, 0.2, 0.1))
	_obstacle(Vector3(2, 0.5, 750), Color(1.0, 0.5, 0.0))

	# Trees along road
	for i in range(-50, 51):
		if absf(i * 20.0 - 200) > 20 and absf(i * 20.0 - 600) > 20:
			_tree(Vector3(-16 + randf() * 3, 0, i * 20.0))
			_tree(Vector3(16 + randf() * 3, 0, i * 20.0))

	# Buildings near intersections
	_building(Vector3(-25, 0, 185), Vector3(12, 8, 14), Color(0.55, 0.5, 0.45))
	_building(Vector3(25, 0, 215), Vector3(10, 6, 12), Color(0.5, 0.45, 0.4))
	_building(Vector3(-30, 0, 590), Vector3(14, 10, 16), Color(0.45, 0.42, 0.4))
	_building(Vector3(28, 0, 610), Vector3(8, 5, 10), Color(0.6, 0.55, 0.5))

func _road(pos: Vector3, sz: Vector3) -> void:
	var body := StaticBody3D.new()
	body.position = pos
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = sz
	col.shape = shape
	body.add_child(col)
	var mesh := BoxMesh.new()
	mesh.size = sz
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.2, 0.2, 0.22)
	mesh.material = mat
	var v := MeshInstance3D.new()
	v.mesh = mesh
	body.add_child(v)
	add_child(body)

func _marker(pos: Vector3, sz: Vector3) -> void:
	var v := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = sz
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1, 1, 1)
	mesh.material = mat
	v.mesh = mesh
	v.position = pos
	add_child(v)

func _road_edge(pos: Vector3, sz: Vector3) -> void:
	var v := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = sz
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.95, 0.95, 0.95)
	mesh.material = mat
	v.mesh = mesh
	v.position = pos
	add_child(v)

func _barrier(pos: Vector3, sz: Vector3) -> void:
	var body := StaticBody3D.new()
	body.position = pos
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = sz
	col.shape = shape
	body.add_child(col)
	var mesh := BoxMesh.new()
	mesh.size = sz
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.6, 0.6, 0.62)
	mat.metallic = 0.5
	mesh.material = mat
	var v := MeshInstance3D.new()
	v.mesh = mesh
	body.add_child(v)
	add_child(body)

func _obstacle(pos: Vector3, color: Color) -> void:
	var body := StaticBody3D.new()
	body.position = pos
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(1.5, 1.0, 1.5)
	col.shape = shape
	body.add_child(col)
	var mesh := BoxMesh.new()
	mesh.size = Vector3(1.5, 1.0, 1.5)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mesh.material = mat
	var v := MeshInstance3D.new()
	v.mesh = mesh
	body.add_child(v)
	add_child(body)

func _tree(pos: Vector3) -> void:
	var trunk := MeshInstance3D.new()
	var tm := CylinderMesh.new()
	tm.top_radius = 0.15
	tm.bottom_radius = 0.2
	tm.height = 3.0
	var tmat := StandardMaterial3D.new()
	tmat.albedo_color = Color(0.35, 0.22, 0.1)
	tm.material = tmat
	trunk.mesh = tm
	trunk.position = pos + Vector3(0, 1.5, 0)
	add_child(trunk)

	var crown := MeshInstance3D.new()
	var cm := SphereMesh.new()
	cm.radius = 1.5
	cm.height = 3.0
	var cmat := StandardMaterial3D.new()
	cmat.albedo_color = Color(0.15, 0.3 + randf() * 0.2, 0.1)
	cm.material = cmat
	crown.mesh = cm
	crown.position = pos + Vector3(0, 4.0, 0)
	add_child(crown)

func _building(pos: Vector3, sz: Vector3, color: Color) -> void:
	var body := StaticBody3D.new()
	body.position = pos + Vector3(0, sz.y / 2, 0)
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = sz
	col.shape = shape
	body.add_child(col)
	var mesh := BoxMesh.new()
	mesh.size = sz
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.8
	mesh.material = mat
	var v := MeshInstance3D.new()
	v.mesh = mesh
	body.add_child(v)
	add_child(body)

# ── Cars ─────────────────────────────────────────────────────

func _create_player_car() -> void:
	var car := _build_vehicle(Color(0.1, 0.3, 0.8), 0)
	car.position = Vector3(3.0, 0.5, -20.0)
	car.name = "Car1_Player"
	add_child(car)
	cars.append(car)
	_start_positions.append(car.position)
	_start_rotations.append(car.rotation)

func _create_ai_cars(count: int) -> void:
	var ai_colors := [
		Color(0.8, 0.1, 0.1),
		Color(0.1, 0.6, 0.2),
		Color(0.7, 0.5, 0.1),
		Color(0.5, 0.1, 0.6),
		Color(0.1, 0.5, 0.6),
	]
	var ai_positions := [
		Vector3(-3.0, 0.5, 30.0),
		Vector3(3.0, 0.5, 80.0),
		Vector3(-3.0, 0.5, 160.0),
		Vector3(3.0, 0.5, 280.0),
		Vector3(-3.0, 0.5, 450.0),
	]
	for i in range(mini(count, ai_positions.size())):
		var car := _build_vehicle(ai_colors[i], i + 1)
		car.position = ai_positions[i]
		car.name = "Car%d_AI" % (i + 2)
		car.ai_mode = true
		car.ai_speed_target = randf_range(40.0, 80.0)
		add_child(car)
		cars.append(car)
		_start_positions.append(car.position)
		_start_rotations.append(car.rotation)

func _build_vehicle(color: Color, car_index: int) -> VehicleBody3D:
	var vehicle := VehicleBody3D.new()
	vehicle.mass = 1500.0
	vehicle.set_script(VehicleController)
	vehicle.set_meta("car_index", car_index)

	var body_col := CollisionShape3D.new()
	var body_shape := BoxShape3D.new()
	body_shape.size = Vector3(1.9, 0.7, 4.4)
	body_col.shape = body_shape
	body_col.position = Vector3(0, 0.55, 0)
	vehicle.add_child(body_col)

	# Lower body
	vehicle.add_child(_box(Vector3(1.9, 0.35, 4.4), Vector3(0, 0.35, 0), color, 0.4, 0.5))
	# Cabin
	vehicle.add_child(_box(Vector3(1.7, 0.45, 2.2), Vector3(0, 0.8, -0.4), color.darkened(0.15), 0.3, 0.35))
	# Hood
	vehicle.add_child(_box(Vector3(1.8, 0.08, 1.4), Vector3(0, 0.55, 1.3), color.lightened(0.05), 0.5, 0.4))
	# Windshield
	var ws := _box(Vector3(1.5, 0.02, 0.8), Vector3(0, 0.95, 0.45), Color(0.3, 0.35, 0.45, 0.7), 0.1, 0.1)
	ws.rotation_degrees.x = -25
	vehicle.add_child(ws)
	# Rear window
	var rw := _box(Vector3(1.5, 0.02, 0.6), Vector3(0, 0.9, -1.2), Color(0.3, 0.35, 0.45, 0.7), 0.1, 0.1)
	rw.rotation_degrees.x = 20
	vehicle.add_child(rw)

	# Headlights
	for side in [-1, 1]:
		var hl := _box(Vector3(0.35, 0.12, 0.06), Vector3(side * 0.65, 0.4, 2.2), Color(1, 1, 0.85), 0.0, 0.0)
		var hm: StandardMaterial3D = hl.mesh.material
		hm.emission_enabled = true
		hm.emission = Color(1, 1, 0.85)
		hm.emission_energy_multiplier = 3.0
		vehicle.add_child(hl)

	# Brake lights
	for side in [-1, 1]:
		var bl := _box(Vector3(0.35, 0.1, 0.06), Vector3(side * 0.65, 0.4, -2.2), Color(0.4, 0, 0), 0.0, 0.0)
		bl.name = "BrakeLight%s" % ("L" if side == -1 else "R")
		vehicle.add_child(bl)

	# Bumpers
	vehicle.add_child(_box(Vector3(1.9, 0.15, 0.1), Vector3(0, 0.2, 2.2), color.darkened(0.3), 0.2, 0.7))
	vehicle.add_child(_box(Vector3(1.9, 0.15, 0.1), Vector3(0, 0.2, -2.2), color.darkened(0.3), 0.2, 0.7))

	# Lidar raycast
	var ray := RayCast3D.new()
	ray.name = "LidarRay"
	ray.position = Vector3(0, 0.5, 2.2)
	ray.target_position = Vector3(0, 0, 12.0)
	ray.enabled = true
	vehicle.add_child(ray)

	# Wheels
	for wp in [
		{"n": "WheelFL", "p": Vector3(-0.85, 0, 1.4), "s": true, "d": false},
		{"n": "WheelFR", "p": Vector3(0.85, 0, 1.4), "s": true, "d": false},
		{"n": "WheelRL", "p": Vector3(-0.85, 0, -1.4), "s": false, "d": true},
		{"n": "WheelRR", "p": Vector3(0.85, 0, -1.4), "s": false, "d": true},
	]:
		var w := VehicleWheel3D.new()
		w.name = wp["n"]
		w.position = wp["p"]
		w.use_as_steering = wp["s"]
		w.use_as_traction = wp["d"]
		w.wheel_radius = 0.35
		w.wheel_rest_length = 0.2
		w.suspension_stiffness = 40.0
		w.damping_compression = 2.0
		w.damping_relaxation = 3.0
		w.wheel_friction_slip = 4.0
		w.wheel_roll_influence = 0.2

		var tire := CylinderMesh.new()
		tire.top_radius = 0.35
		tire.bottom_radius = 0.35
		tire.height = 0.22
		var tmat := StandardMaterial3D.new()
		tmat.albedo_color = Color(0.12, 0.12, 0.12)
		tmat.roughness = 0.95
		tire.material = tmat
		var tv := MeshInstance3D.new()
		tv.mesh = tire
		tv.rotation_degrees.z = 90.0
		w.add_child(tv)

		var rim := CylinderMesh.new()
		rim.top_radius = 0.18
		rim.bottom_radius = 0.18
		rim.height = 0.23
		var rmat := StandardMaterial3D.new()
		rmat.albedo_color = Color(0.75, 0.75, 0.78)
		rmat.metallic = 0.85
		rim.material = rmat
		var rv := MeshInstance3D.new()
		rv.mesh = rim
		rv.rotation_degrees.z = 90.0
		w.add_child(rv)

		vehicle.add_child(w)

	return vehicle

func _box(sz: Vector3, pos: Vector3, color: Color, metal: float, rough: float) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = sz
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.metallic = metal
	mat.roughness = rough
	mesh.material = mat
	var v := MeshInstance3D.new()
	v.mesh = mesh
	v.position = pos
	return v

# ── Camera ───────────────────────────────────────────────────

func _create_camera() -> void:
	camera = Camera3D.new()
	camera.name = "FollowCamera"
	camera.set_script(CameraFollow)
	camera.fov = 65.0
	camera.far = 500.0
	add_child(camera)
	camera.set("target", cars[0])

# ── Dashboard ────────────────────────────────────────────────

func _create_dashboard() -> void:
	var canvas := CanvasLayer.new()
	canvas.name = "HUD"
	add_child(canvas)
	dashboard_control = Control.new()
	dashboard_control.name = "Dashboard"
	dashboard_control.set_script(Dashboard)
	dashboard_control.set_anchors_preset(Control.PRESET_FULL_RECT)
	canvas.add_child(dashboard_control)

# ── Input ────────────────────────────────────────────────────

func _input(event: InputEvent) -> void:
	if event.is_action_pressed("switch_car"):
		active_car_index = (active_car_index + 1) % cars.size()
		camera.set("target", cars[active_car_index])

	if event.is_action_pressed("toggle_vecu"):
		# Only toggle vECU on player car (index 0)
		cars[0].vecu_mode = !cars[0].vecu_mode
		if cars[0].vecu_mode:
			# Reset vECU state so it doesn't start in SAFE_STOP
			cars[0].vecu_vehicle_state = "INIT"
			cars[0].vecu_kill_relay = false
			cars[0].vecu_torque_pct = 0.0
			cars[0].vecu_brake_pct = 0.0

	# R = reset all cars to starting positions
	if event is InputEventKey and event.pressed and event.keycode == KEY_R:
		_reset_all()

func _reset_all() -> void:
	for i in range(cars.size()):
		var car := cars[i]
		car.linear_velocity = Vector3.ZERO
		car.angular_velocity = Vector3.ZERO
		car.global_position = _start_positions[i]
		car.global_rotation = _start_rotations[i]
		car.engine_force = 0.0
		car.brake = 0.0
		car.steering = 0.0
		car.motor_temp_c = 25.0
		car.vecu_vehicle_state = "INIT"
		car.vecu_kill_relay = false
	print("Track reset — all cars repositioned")
