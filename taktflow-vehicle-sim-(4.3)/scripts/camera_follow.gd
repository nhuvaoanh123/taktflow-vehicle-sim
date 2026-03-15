extends Camera3D
## Third-person follow camera with multiple view modes.
## Press C to cycle: chase → top-down → cockpit.

enum CameraMode { CHASE, TOP_DOWN, COCKPIT }

var target: Node3D = null
var mode := CameraMode.CHASE
var smooth_speed := 5.0

# Chase cam offset (behind and above)
var chase_offset := Vector3(0, 4.0, -10.0)
# Top-down offset
var top_offset := Vector3(0, 25.0, -5.0)
# Cockpit offset (inside car)
var cockpit_offset := Vector3(0, 1.2, 0.8)

func _process(delta: float) -> void:
	if not target:
		return

	var target_pos := target.global_position
	var target_basis := target.global_transform.basis
	var desired_pos: Vector3

	match mode:
		CameraMode.CHASE:
			desired_pos = target_pos + target_basis * chase_offset
			global_position = global_position.lerp(desired_pos, smooth_speed * delta)
			look_at(target_pos + Vector3.UP * 1.0)

		CameraMode.TOP_DOWN:
			desired_pos = target_pos + top_offset
			global_position = global_position.lerp(desired_pos, smooth_speed * delta)
			look_at(target_pos)

		CameraMode.COCKPIT:
			desired_pos = target_pos + target_basis * cockpit_offset
			global_position = desired_pos
			# Look forward from car
			var look_target = target_pos + target_basis * Vector3(0, 1.0, 10.0)
			look_at(look_target)

func _input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_camera"):
		mode = ((mode + 1) % 3) as CameraMode
		print("Camera: %s" % CameraMode.keys()[mode])
