extends Node3D

const VehicleController = preload("res://scripts/vehicle_controller.gd")
const CameraFollow = preload("res://scripts/camera_follow.gd")
const Dashboard = preload("res://scripts/dashboard.gd")

var cars: Array[VehicleBody3D] = []
var active_car_index := 0
var camera: Camera3D
var dashboard_control: Control

func _ready() -> void:
	_create_environment()
	_create_track()
	_create_cars(3)
	_create_camera()
	_create_dashboard()

# ── Environment ──────────────────────────────────────────────

func _create_environment() -> void:
	# Sky
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.35, 0.55, 0.82)
	sky_mat.sky_horizon_color = Color(0.65, 0.75, 0.85)
	sky_mat.ground_bottom_color = Color(0.15, 0.13, 0.1)
	sky_mat.ground_horizon_color = Color(0.65, 0.75, 0.85)

	var sky := Sky.new()
	sky.sky_material = sky_mat

	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.5
	env.tonemap_mode = Environment.TONE_MAP_ACES
	env.ssao_enabled = true
	env.fog_enabled = true
	env.fog_light_color = Color(0.7, 0.75, 0.82)
	env.fog_density = 0.001

	var world_env := WorldEnvironment.new()
	world_env.environment = env
	add_child(world_env)

	# Sun
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-45, 30, 0)
	sun.light_energy = 1.2
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 200.0
	add_child(sun)

# ── Track ────────────────────────────────────────────────────

func _create_track() -> void:
	# Ground plane
	var ground_body := StaticBody3D.new()
	ground_body.name = "Ground"
	add_child(ground_body)

	var ground_shape := WorldBoundaryShape3D.new()
	var ground_col := CollisionShape3D.new()
	ground_col.shape = ground_shape
	ground_body.add_child(ground_col)

	# Visible ground mesh (large flat plane)
	var ground_mesh := PlaneMesh.new()
	ground_mesh.size = Vector2(500, 500)
	var ground_mat := StandardMaterial3D.new()
	ground_mat.albedo_color = Color(0.28, 0.38, 0.2)  # grass green
	ground_mesh.material = ground_mat

	var ground_visual := MeshInstance3D.new()
	ground_visual.mesh = ground_mesh
	ground_body.add_child(ground_visual)

	# Road surface — oval track
	_create_road_segment(Vector3(0, 0.01, 0), Vector3(200, 0.05, 12), 0)       # straight 1
	_create_road_segment(Vector3(0, 0.01, -80), Vector3(200, 0.05, 12), 0)     # straight 2
	_create_road_segment(Vector3(100, 0.01, -40), Vector3(12, 0.05, 92), 0)    # right curve approx
	_create_road_segment(Vector3(-100, 0.01, -40), Vector3(12, 0.05, 92), 0)   # left curve approx

	# Center line markers on straight 1
	for i in range(-10, 11):
		_create_road_marker(Vector3(i * 8.0, 0.02, 0))
	for i in range(-10, 11):
		_create_road_marker(Vector3(i * 8.0, 0.02, -80))

	# Barriers along track edges
	_create_barrier(Vector3(0, 0.5, 7), Vector3(200, 1, 0.3))
	_create_barrier(Vector3(0, 0.5, -7), Vector3(200, 1, 0.3))
	_create_barrier(Vector3(0, 0.5, -73), Vector3(200, 1, 0.3))
	_create_barrier(Vector3(0, 0.5, -87), Vector3(200, 1, 0.3))

	# Obstacle zone (for distance sensor testing)
	_create_obstacle(Vector3(30, 0.5, -40))
	_create_obstacle(Vector3(50, 0.5, -35))

func _create_road_segment(pos: Vector3, size: Vector3, rot_y: float) -> void:
	var mesh := BoxMesh.new()
	mesh.size = size
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.25, 0.25, 0.28)  # asphalt gray
	mesh.material = mat
	var visual := MeshInstance3D.new()
	visual.mesh = mesh
	visual.position = pos
	visual.rotation_degrees.y = rot_y

	var body := StaticBody3D.new()
	body.position = pos
	body.rotation_degrees.y = rot_y
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	col.shape = shape
	body.add_child(col)
	body.add_child(visual)
	visual.position = Vector3.ZERO
	add_child(body)

func _create_road_marker(pos: Vector3) -> void:
	var mesh := BoxMesh.new()
	mesh.size = Vector3(2.0, 0.02, 0.15)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1, 1, 1)
	mesh.material = mat
	var visual := MeshInstance3D.new()
	visual.mesh = mesh
	visual.position = pos
	add_child(visual)

func _create_barrier(pos: Vector3, size: Vector3) -> void:
	var body := StaticBody3D.new()
	body.position = pos
	add_child(body)

	var shape := BoxShape3D.new()
	shape.size = size
	var col := CollisionShape3D.new()
	col.shape = shape
	body.add_child(col)

	var mesh := BoxMesh.new()
	mesh.size = size
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.85, 0.15, 0.1)  # red barriers
	mesh.material = mat
	var visual := MeshInstance3D.new()
	visual.mesh = mesh
	body.add_child(visual)

func _create_obstacle(pos: Vector3) -> void:
	var body := StaticBody3D.new()
	body.position = pos
	add_child(body)

	var shape := BoxShape3D.new()
	shape.size = Vector3(1.5, 1.0, 1.5)
	var col := CollisionShape3D.new()
	col.shape = shape
	body.add_child(col)

	var mesh := BoxMesh.new()
	mesh.size = Vector3(1.5, 1.0, 1.5)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.6, 0.0)  # orange obstacle
	mesh.material = mat
	var visual := MeshInstance3D.new()
	visual.mesh = mesh
	body.add_child(visual)

# ── Cars ─────────────────────────────────────────────────────

func _create_cars(count: int) -> void:
	var colors := [
		Color(0.15, 0.35, 0.75),  # blue
		Color(0.75, 0.15, 0.15),  # red
		Color(0.15, 0.65, 0.25),  # green
	]
	for i in range(count):
		var car := _build_vehicle(colors[i % colors.size()], i)
		car.position = Vector3(i * 5.0 - 5.0, 1.0, 0)
		car.name = "Car%d" % (i + 1)
		add_child(car)
		cars.append(car)

func _build_vehicle(color: Color, car_index: int) -> VehicleBody3D:
	var vehicle := VehicleBody3D.new()
	vehicle.mass = 1200.0
	vehicle.set_script(VehicleController)
	vehicle.set_meta("car_index", car_index)

	# Body collision
	var body_shape := BoxShape3D.new()
	body_shape.size = Vector3(1.8, 0.6, 4.0)
	var body_col := CollisionShape3D.new()
	body_col.shape = body_shape
	body_col.position = Vector3(0, 0.5, 0)
	vehicle.add_child(body_col)

	# Body mesh — lower chassis
	var chassis_mesh := BoxMesh.new()
	chassis_mesh.size = Vector3(1.8, 0.4, 4.0)
	var chassis_mat := StandardMaterial3D.new()
	chassis_mat.albedo_color = color
	chassis_mat.metallic = 0.3
	chassis_mat.roughness = 0.6
	chassis_mesh.material = chassis_mat
	var chassis_visual := MeshInstance3D.new()
	chassis_visual.mesh = chassis_mesh
	chassis_visual.position = Vector3(0, 0.35, 0)
	vehicle.add_child(chassis_visual)

	# Cabin mesh — upper part
	var cabin_mesh := BoxMesh.new()
	cabin_mesh.size = Vector3(1.6, 0.5, 2.0)
	var cabin_mat := StandardMaterial3D.new()
	cabin_mat.albedo_color = color.darkened(0.2)
	cabin_mat.metallic = 0.3
	cabin_mat.roughness = 0.4
	cabin_mesh.material = cabin_mat
	var cabin_visual := MeshInstance3D.new()
	cabin_visual.mesh = cabin_mesh
	cabin_visual.position = Vector3(0, 0.8, -0.3)
	vehicle.add_child(cabin_visual)

	# Headlights
	for side in [-1, 1]:
		var light_mesh := BoxMesh.new()
		light_mesh.size = Vector3(0.3, 0.15, 0.05)
		var light_mat := StandardMaterial3D.new()
		light_mat.albedo_color = Color(1, 1, 0.8)
		light_mat.emission_enabled = true
		light_mat.emission = Color(1, 1, 0.8)
		light_mat.emission_energy_multiplier = 2.0
		light_mesh.material = light_mat
		var light_visual := MeshInstance3D.new()
		light_visual.mesh = light_mesh
		light_visual.position = Vector3(side * 0.6, 0.35, 2.0)
		vehicle.add_child(light_visual)

	# Brake lights
	for side in [-1, 1]:
		var brake_mesh := BoxMesh.new()
		brake_mesh.size = Vector3(0.3, 0.15, 0.05)
		var brake_mat := StandardMaterial3D.new()
		brake_mat.albedo_color = Color(0.5, 0, 0)
		brake_mesh.material = brake_mat
		var brake_visual := MeshInstance3D.new()
		brake_visual.name = "BrakeLight%s" % ("L" if side == -1 else "R")
		brake_visual.mesh = brake_mesh
		brake_visual.position = Vector3(side * 0.6, 0.35, -2.0)
		vehicle.add_child(brake_visual)

	# Wheels
	var wheel_positions := [
		{"name": "WheelFL", "pos": Vector3(-0.85, 0.0, 1.25), "steer": true, "traction": false},
		{"name": "WheelFR", "pos": Vector3(0.85, 0.0, 1.25), "steer": true, "traction": false},
		{"name": "WheelRL", "pos": Vector3(-0.85, 0.0, -1.25), "steer": false, "traction": true},
		{"name": "WheelRR", "pos": Vector3(0.85, 0.0, -1.25), "steer": false, "traction": true},
	]

	for wp in wheel_positions:
		var wheel := VehicleWheel3D.new()
		wheel.name = wp["name"]
		wheel.position = wp["pos"]
		wheel.use_as_steering = wp["steer"]
		wheel.use_as_traction = wp["traction"]
		wheel.wheel_radius = 0.3
		wheel.wheel_rest_length = 0.15
		wheel.suspension_stiffness = 50.0
		wheel.damping_compression = 2.3
		wheel.damping_relaxation = 3.5
		wheel.wheel_friction_slip = 3.5
		wheel.wheel_roll_influence = 0.3

		# Wheel mesh (cylinder rotated sideways)
		var wheel_mesh := CylinderMesh.new()
		wheel_mesh.top_radius = 0.3
		wheel_mesh.bottom_radius = 0.3
		wheel_mesh.height = 0.2
		var wheel_mat := StandardMaterial3D.new()
		wheel_mat.albedo_color = Color(0.15, 0.15, 0.15)
		wheel_mat.metallic = 0.1
		wheel_mat.roughness = 0.9
		wheel_mesh.material = wheel_mat
		var wheel_visual := MeshInstance3D.new()
		wheel_visual.mesh = wheel_mesh
		wheel_visual.rotation_degrees.z = 90.0
		wheel.add_child(wheel_visual)

		# Tire rim accent
		var rim_mesh := CylinderMesh.new()
		rim_mesh.top_radius = 0.15
		rim_mesh.bottom_radius = 0.15
		rim_mesh.height = 0.21
		var rim_mat := StandardMaterial3D.new()
		rim_mat.albedo_color = Color(0.7, 0.7, 0.72)
		rim_mat.metallic = 0.8
		rim_mesh.material = rim_mat
		var rim_visual := MeshInstance3D.new()
		rim_visual.mesh = rim_mesh
		rim_visual.rotation_degrees.z = 90.0
		wheel.add_child(rim_visual)

		vehicle.add_child(wheel)

	return vehicle

# ── Camera ───────────────────────────────────────────────────

func _create_camera() -> void:
	camera = Camera3D.new()
	camera.name = "FollowCamera"
	camera.set_script(CameraFollow)
	camera.fov = 65.0
	camera.far = 500.0
	add_child(camera)
	camera.set("target", cars[0])

# ── Dashboard HUD ────────────────────────────────────────────

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
		print("Switched to Car %d" % (active_car_index + 1))

	if event.is_action_pressed("toggle_vecu"):
		for car in cars:
			car.vecu_mode = !car.vecu_mode
		var mode_str = "vECU" if cars[0].vecu_mode else "Keyboard"
		print("Control mode: %s" % mode_str)
