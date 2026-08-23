extends Node3D

const LEADERBOARD_URL := "__LEADERBOARD_URL__"
const SAVE_PATH := "user://deepcore_gold_rush_v1.json"

const GOLD := Color(1.0, 0.72, 0.12)
const GOLD_HI := Color(1.0, 0.94, 0.34)
const CYAN := Color(0.30, 0.91, 1.0)
const ORANGE := Color(1.0, 0.42, 0.12)
const GREEN := Color(0.34, 0.96, 0.56)
const RED := Color(1.0, 0.22, 0.23)
const PURPLE := Color(0.70, 0.40, 1.0)
const TEXT := Color(0.97, 0.98, 1.0)
const MUTED := Color(0.67, 0.70, 0.77)
const PANEL := Color(0.055, 0.043, 0.038, 0.96)
const PANEL_LIGHT := Color(0.11, 0.075, 0.052, 0.97)
const SOIL_1 := Color(0.24, 0.105, 0.045)
const SOIL_2 := Color(0.34, 0.15, 0.064)
const SOIL_3 := Color(0.46, 0.22, 0.095)

var rng := RandomNumberGenerator.new()
var phase := "intro"
var paused_for_panel := false
var level := 1
var best_level := 1
var credits := 250
var lifetime_cash := 0
var level_cash := 0
var goal := 900
var time_left := 65.0
var stars_total := 0
var combo := 0
var best_combo := 0
var fever := 0.0
var fever_time := 0.0
var dynamites := 2
var last_saved := 0
var player_id := ""
var player_name := ""
var winch_level := 1
var strength_level := 1
var luck_level := 0
var magnet_level := 0
var time_level := 0

var hook_state := "swing"
var hook_angle := -0.55
var hook_dir_sign := 1.0
var hook_length := 0.85
var hook_speed := 12.0
var hook_target: Dictionary = {}
var hook_tip := Vector3.ZERO
var pivot := Vector3(0, 6.15, 0.35)
var shot_dir := Vector3.DOWN
var max_hook_length := 15.2
var catch_radius := 0.25
var retract_base := 6.0

var camera: Camera3D
var world_root: Node3D
var object_root: Node3D
var rig_root: Node3D
var arm_root: Node3D
var rope_mesh: MeshInstance3D
var rope_cylinder: CylinderMesh
var hook_root: Node3D
var hook_glow: OmniLight3D
var hook_claw_left: Node3D
var hook_claw_right: Node3D
var dust_particles: GPUParticles3D
var grab_particles: GPUParticles3D
var explosion_particles: GPUParticles3D
var objects: Array = []
var cave_lights: Array = []

var canvas: CanvasLayer
var hud_root: Control
var money_lbl: Label
var goal_lbl: Label
var time_lbl: Label
var level_lbl: Label
var combo_lbl: Label
var fever_bar: ProgressBar
var dynamite_btn: Button
var pause_btn: Button
var status_lbl: Label
var toast: Label
var intro_overlay: Control
var result_panel: PanelContainer
var result_title: Label
var result_details: Label
var result_button: Button
var shop_panel: PanelContainer
var shop_credits_lbl: Label
var leaderboard_panel: PanelContainer
var rank_list: VBoxContainer
var name_edit: LineEdit
var help_panel: PanelContainer

var http: HTTPRequest
var http_busy := false
var http_mode := ""
var pending_board: Dictionary = {}
var audio_players: Dictionary = {}
var haptics_enabled := true
var sound_enabled := true
var elapsed := 0.0
var input_lock := 0.0

func _ready() -> void:
	rng.randomize()
	_load_save()
	_build_environment()
	_build_rig()
	_build_hook()
	_build_particles()
	_build_ui()
	_build_network()
	_build_audio()
	_show_intro()

func _process(delta: float) -> void:
	elapsed += delta
	input_lock = maxf(0.0, input_lock - delta)
	_animate_environment(delta)
	if phase != "playing" or paused_for_panel:
		_update_rope()
		return
	if fever_time > 0.0:
		fever_time -= delta
		if fever_time <= 0.0:
			fever_time = 0.0
			_say("GOLD RUSH cooled down", MUTED)
	time_left -= delta
	if time_left <= 0.0:
		time_left = 0.0
		_finish_level()
		_update_hud()
		return
	_update_hook(delta)
	_update_hud()

func _unhandled_input(event: InputEvent) -> void:
	if phase != "playing" or paused_for_panel or input_lock > 0.0:
		return
	if event is InputEventScreenTouch and event.pressed:
		_launch_hook()
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		_launch_hook()

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_PAUSED or what == NOTIFICATION_WM_CLOSE_REQUEST:
		_save_game()

func _material(color: Color, metallic := 0.0, roughness := 0.75, emission := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.metallic = metallic
	m.roughness = roughness
	if emission > 0.0:
		m.emission_enabled = true
		m.emission = color
		m.emission_energy_multiplier = emission
	return m

func _build_environment() -> void:
	world_root = Node3D.new()
	world_root.name = "MineWorld"
	add_child(world_root)
	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.035, 0.018, 0.012)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.62, 0.38, 0.22)
	env.ambient_light_energy = 0.53
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.fog_enabled = true
	env.fog_light_color = Color(0.20, 0.095, 0.045)
	env.fog_density = 0.012
	we.environment = env
	world_root.add_child(we)
	camera = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 18.2
	camera.position = Vector3(0, -0.2, 21.0)
	camera.current = true
	world_root.add_child(camera)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-18, -25, -8)
	sun.light_color = Color(1.0, 0.72, 0.46)
	sun.light_energy = 1.25
	sun.shadow_enabled = true
	world_root.add_child(sun)
	_add_layer(Vector3(0, 5.95, -2.4), Vector3(11.0, 1.7, 1.0), Color(0.10, 0.045, 0.025), 0.85)
	_add_layer(Vector3(0, 3.55, -2.6), Vector3(11.0, 3.0, 1.0), SOIL_3, 0.96)
	_add_layer(Vector3(0, 0.45, -2.7), Vector3(11.0, 3.4, 1.0), SOIL_2, 0.98)
	_add_layer(Vector3(0, -3.15, -2.8), Vector3(11.0, 3.8, 1.0), SOIL_1, 1.0)
	_add_layer(Vector3(0, -7.1, -2.9), Vector3(11.0, 4.2, 1.0), Color(0.13, 0.055, 0.035), 1.0)
	for side in [-1.0, 1.0]:
		for i in range(9):
			var y := 5.0 - float(i) * 1.7
			var rock := _make_rock(Vector3(1.0, 0.72, 0.65), Color(0.18, 0.13, 0.11))
			rock.position = Vector3(side * rng.randf_range(4.65, 5.25), y, rng.randf_range(-1.3, -0.5))
			rock.rotation = Vector3(rng.randf_range(-0.3, 0.3), rng.randf_range(-0.6, 0.6), rng.randf_range(-0.6, 0.6))
			world_root.add_child(rock)
	for i in range(24):
		var pebble := _make_rock(Vector3(rng.randf_range(0.12, 0.36), rng.randf_range(0.09, 0.24), rng.randf_range(0.10, 0.30)), Color(0.15, 0.105, 0.085))
		pebble.position = Vector3(rng.randf_range(-4.3, 4.3), rng.randf_range(-8.4, 4.5), rng.randf_range(-1.55, -0.65))
		world_root.add_child(pebble)
	for p in [Vector3(-4.3, 4.7, 0.0), Vector3(4.3, 2.2, 0.0), Vector3(-4.3, -1.6, 0.0), Vector3(4.3, -5.2, 0.0)]:
		var lamp := OmniLight3D.new()
		lamp.position = p
		lamp.light_color = Color(1.0, 0.49, 0.16)
		lamp.light_energy = 1.25
		lamp.omni_range = 4.4
		world_root.add_child(lamp)
		cave_lights.append(lamp)
	object_root = Node3D.new()
	object_root.name = "Mineables"
	world_root.add_child(object_root)

func _add_layer(pos: Vector3, size: Vector3, color: Color, rough: float) -> void:
	var mesh := BoxMesh.new()
	mesh.size = size
	var n := MeshInstance3D.new()
	n.mesh = mesh
	n.material_override = _material(color, 0.0, rough)
	n.position = pos
	world_root.add_child(n)

func _make_rock(scale_v: Vector3, color: Color) -> MeshInstance3D:
	var mesh := SphereMesh.new()
	mesh.radial_segments = 8
	mesh.rings = 5
	var n := MeshInstance3D.new()
	n.mesh = mesh
	n.scale = scale_v
	n.material_override = _material(color, 0.03, 0.98)
	return n

func _build_rig() -> void:
	rig_root = Node3D.new()
	rig_root.position = Vector3(0, 7.15, 0.25)
	world_root.add_child(rig_root)
	var platform_mesh := BoxMesh.new()
	platform_mesh.size = Vector3(4.9, 0.28, 1.6)
	var platform := MeshInstance3D.new()
	platform.mesh = platform_mesh
	platform.material_override = _material(Color(0.11, 0.12, 0.13), 0.65, 0.32)
	platform.position = Vector3(0, -0.55, -0.05)
	rig_root.add_child(platform)
	for x in [-2.15, 2.15]:
		var leg_mesh := BoxMesh.new()
		leg_mesh.size = Vector3(0.20, 1.35, 0.22)
		var leg := MeshInstance3D.new()
		leg.mesh = leg_mesh
		leg.material_override = _material(GOLD, 0.65, 0.25)
		leg.position = Vector3(x, -1.05, 0.0)
		rig_root.add_child(leg)
	var drum_mesh := CylinderMesh.new()
	drum_mesh.top_radius = 0.52
	drum_mesh.bottom_radius = 0.52
	drum_mesh.height = 1.2
	drum_mesh.radial_segments = 16
	var drum := MeshInstance3D.new()
	drum.mesh = drum_mesh
	drum.rotation_degrees.z = 90
	drum.position = Vector3(-0.55, -0.15, 0.35)
	drum.material_override = _material(Color(0.25, 0.28, 0.31), 0.82, 0.20)
	rig_root.add_child(drum)
	var miner := Node3D.new()
	miner.position = Vector3(0.85, 0.05, 0.0)
	rig_root.add_child(miner)
	var torso_mesh := CapsuleMesh.new()
	torso_mesh.radius = 0.42
	torso_mesh.height = 1.25
	var torso := MeshInstance3D.new()
	torso.mesh = torso_mesh
	torso.material_override = _material(Color(0.14, 0.32, 0.52), 0.0, 0.72)
	miner.add_child(torso)
	var head_mesh := SphereMesh.new()
	head_mesh.radius = 0.36
	head_mesh.height = 0.72
	var head := MeshInstance3D.new()
	head.mesh = head_mesh
	head.position = Vector3(0, 0.84, 0)
	head.material_override = _material(Color(0.78, 0.49, 0.31), 0.0, 0.92)
	miner.add_child(head)
	var helmet_mesh := SphereMesh.new()
	helmet_mesh.radius = 0.39
	helmet_mesh.height = 0.42
	var helmet := MeshInstance3D.new()
	helmet.mesh = helmet_mesh
	helmet.position = Vector3(0, 1.04, 0)
	helmet.scale = Vector3(1.08, 0.55, 1.08)
	helmet.material_override = _material(GOLD, 0.25, 0.35)
	miner.add_child(helmet)
	var helmet_light := OmniLight3D.new()
	helmet_light.position = Vector3(0, 1.02, 0.45)
	helmet_light.light_color = Color(1.0, 0.91, 0.62)
	helmet_light.light_energy = 1.6
	helmet_light.omni_range = 3.5
	miner.add_child(helmet_light)
	arm_root = Node3D.new()
	arm_root.position = Vector3(0, -0.92, 0.28)
	rig_root.add_child(arm_root)
	pivot = rig_root.position + arm_root.position

func _build_hook() -> void:
	rope_cylinder = CylinderMesh.new()
	rope_cylinder.top_radius = 0.035
	rope_cylinder.bottom_radius = 0.035
	rope_cylinder.height = 1.0
	rope_cylinder.radial_segments = 7
	rope_mesh = MeshInstance3D.new()
	rope_mesh.mesh = rope_cylinder
	rope_mesh.material_override = _material(Color(0.12, 0.13, 0.14), 0.78, 0.27)
	world_root.add_child(rope_mesh)
	hook_root = Node3D.new()
	world_root.add_child(hook_root)
	var hub_mesh := SphereMesh.new()
	hub_mesh.radius = 0.19
	hub_mesh.height = 0.38
	var hub := MeshInstance3D.new()
	hub.mesh = hub_mesh
	hub.material_override = _material(GOLD, 0.8, 0.18)
	hook_root.add_child(hub)
	hook_claw_left = _claw(-1.0)
	hook_claw_right = _claw(1.0)
	hook_root.add_child(hook_claw_left)
	hook_root.add_child(hook_claw_right)
	hook_glow = OmniLight3D.new()
	hook_glow.light_color = GOLD_HI
	hook_glow.light_energy = 0.8
	hook_glow.omni_range = 1.7
	hook_root.add_child(hook_glow)
	_reset_hook()

func _claw(side: float) -> Node3D:
	var root := Node3D.new()
	root.position = Vector3(side * 0.18, -0.04, 0.0)
	root.rotation_degrees.z = side * 22.0
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.07
	mesh.bottom_radius = 0.11
	mesh.height = 0.55
	mesh.radial_segments = 7
	var claw := MeshInstance3D.new()
	claw.mesh = mesh
	claw.position = Vector3(side * 0.10, -0.20, 0)
	claw.rotation_degrees.z = side * -31.0
	claw.material_override = _material(Color(0.44, 0.47, 0.50), 0.9, 0.16)
	root.add_child(claw)
	return root

func _build_particles() -> void:
	dust_particles = _particle_system(Color(0.58, 0.31, 0.13), 30, 0.75, 2.0, 4.0, Vector3(0, -4.0, 0))
	world_root.add_child(dust_particles)
	grab_particles = _particle_system(GOLD_HI, 36, 0.55, 2.2, 5.2, Vector3(0, -2.0, 0))
	world_root.add_child(grab_particles)
	explosion_particles = _particle_system(ORANGE, 80, 0.8, 4.0, 8.0, Vector3(0, -2.5, 0))
	world_root.add_child(explosion_particles)

func _particle_system(color: Color, amount: int, lifetime: float, vel_min: float, vel_max: float, gravity: Vector3) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = amount
	p.lifetime = lifetime
	p.one_shot = true
	p.emitting = false
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3(0, 1, 0)
	pm.spread = 180.0
	pm.initial_velocity_min = vel_min
	pm.initial_velocity_max = vel_max
	pm.gravity = gravity
	pm.scale_min = 0.035
	pm.scale_max = 0.12
	pm.color = color
	p.process_material = pm
	var sm := SphereMesh.new()
	sm.radius = 0.055
	sm.height = 0.11
	sm.radial_segments = 5
	sm.rings = 3
	sm.material = _material(color, 0.0, 0.28, 2.5)
	p.draw_pass_1 = sm
	return p

func _animate_environment(_delta: float) -> void:
	for i in range(cave_lights.size()):
		var light := cave_lights[i] as OmniLight3D
		light.light_energy = 1.1 + sin(elapsed * 2.2 + float(i)) * 0.18
	if rig_root:
		rig_root.position.y = 7.15 + sin(elapsed * 1.1) * 0.025

func _reset_hook() -> void:
	hook_state = "swing"
	hook_length = 0.85
	hook_target = {}
	_set_claw(false)
	_update_hook_tip()
	_update_rope()

func _update_hook(delta: float) -> void:
	if hook_state == "swing":
		var swing_speed := 1.38 + float(winch_level - 1) * 0.035
		hook_angle += hook_dir_sign * swing_speed * delta
		if hook_angle > 1.18:
			hook_angle = 1.18
			hook_dir_sign = -1.0
		elif hook_angle < -1.18:
			hook_angle = -1.18
			hook_dir_sign = 1.0
		_update_hook_tip()
	elif hook_state == "extend":
		hook_length += hook_speed * delta
		_update_hook_tip()
		var hit := _find_hit()
		if not hit.is_empty():
			_grab(hit)
		elif hook_length >= max_hook_length or absf(hook_tip.x) > 5.0 or hook_tip.y < -9.0:
			hook_state = "retract"
			_play_sfx("empty")
	elif hook_state == "retract":
		var weight := 0.0
		if not hook_target.is_empty():
			weight = float(hook_target.get("weight", 1.0))
		var strength := 1.0 + float(strength_level - 1) * 0.17
		var weight_drag := 1.0 + maxf(0.0, weight - strength) * 0.40
		var speed := retract_base * (1.0 + float(winch_level - 1) * 0.16) / weight_drag
		if fever_time > 0.0:
			speed *= 1.25
		hook_length -= speed * delta
		hook_length = maxf(0.78, hook_length)
		_update_hook_tip()
		if not hook_target.is_empty() and is_instance_valid(hook_target.get("node")):
			var target_node := hook_target.get("node") as Node3D
			target_node.position = hook_tip + Vector3(0, -0.20, 0)
			target_node.rotation.z += delta * 1.9
		if hook_length <= 0.80:
			_complete_retract()
	_update_rope()

func _update_hook_tip() -> void:
	var dir := Vector3(sin(hook_angle), -cos(hook_angle), 0.0)
	if hook_state != "swing":
		dir = shot_dir
	hook_tip = pivot + dir * hook_length
	hook_root.position = hook_tip
	hook_root.rotation.z = -hook_angle

func _update_rope() -> void:
	if not rope_mesh:
		return
	var a := pivot
	var b := hook_tip
	var delta := b - a
	var length := maxf(0.01, delta.length())
	rope_cylinder.height = length
	rope_mesh.position = (a + b) * 0.5
	rope_mesh.quaternion = Quaternion(Vector3.UP, delta.normalized())

func _launch_hook() -> void:
	if hook_state != "swing":
		return
	shot_dir = Vector3(sin(hook_angle), -cos(hook_angle), 0.0).normalized()
	hook_state = "extend"
	_play_sfx("launch")
	_vibrate(18)
	input_lock = 0.08

func _find_hit() -> Dictionary:
	var best: Dictionary = {}
	var best_dist := 999.0
	var radius_bonus := 0.06 * float(magnet_level)
	for obj in objects:
		if obj.get("removed", false):
			continue
		var node := obj.get("node") as Node3D
		if not is_instance_valid(node):
			continue
		var pos: Vector3 = node.position
		var d := Vector2(pos.x - hook_tip.x, pos.y - hook_tip.y).length()
		if d < float(obj.get("radius", 0.45)) + catch_radius + radius_bonus and d < best_dist:
			best = obj
			best_dist = d
	return best

func _grab(obj: Dictionary) -> void:
	hook_target = obj
	hook_state = "retract"
	_set_claw(true)
	grab_particles.position = hook_tip
	grab_particles.restart()
	grab_particles.emitting = true
	_play_sfx("grab")
	_vibrate(28)
	var node := obj.get("node") as Node3D
	if is_instance_valid(node):
		node.position.z = 0.25

func _set_claw(closed: bool) -> void:
	if not hook_claw_left:
		return
	var left_target := -11.0 if closed else -22.0
	var right_target := 11.0 if closed else 22.0
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(hook_claw_left, "rotation_degrees:z", left_target, 0.10)
	tw.tween_property(hook_claw_right, "rotation_degrees:z", right_target, 0.10)

func _complete_retract() -> void:
	if hook_target.is_empty():
		_reset_hook()
		return
	var obj := hook_target
	var kind := String(obj.get("kind", "rock"))
	_remove_object(obj)
	if kind == "mystery":
		_resolve_mystery()
	elif kind == "tnt":
		_resolve_tnt()
	else:
		var base_value := int(obj.get("value", 0))
		var multiplier := 1.0 + minf(0.75, float(combo) * 0.05)
		if fever_time > 0.0:
			multiplier *= 1.35
		var reward := int(round(float(base_value) * multiplier))
		level_cash += reward
		credits += reward
		lifetime_cash += reward
		if kind.begins_with("gold") or kind == "diamond" or kind == "fossil":
			combo += 1
			best_combo = maxi(best_combo, combo)
			fever = minf(100.0, fever + (22.0 if kind == "diamond" else 13.0))
			if fever >= 100.0 and fever_time <= 0.0:
				fever = 0.0
				fever_time = 8.0
				_say("GOLD RUSH!  +35% value / faster winch", GOLD_HI)
				_play_sfx("fever")
		else:
			combo = 0
		_say("%s  +$%d" % [String(obj.get("name", "Find")), reward], obj.get("color", GOLD))
		_play_sfx("coin" if reward >= 100 else "rock")
		_vibrate(45 if reward >= 100 else 20)
	_save_game()
	_reset_hook()

func _remove_object(obj: Dictionary) -> void:
	obj["removed"] = true
	var node := obj.get("node") as Node3D
	if is_instance_valid(node):
		node.queue_free()

func _resolve_mystery() -> void:
	combo += 1
	var roll := rng.randi_range(0, 4)
	if roll == 0:
		var bonus := 250 + level * 35
		credits += bonus
		level_cash += bonus
		lifetime_cash += bonus
		_say("Mystery cache: +$%d" % bonus, PURPLE)
	elif roll == 1:
		time_left += 10.0
		_say("Mystery cache: +10 seconds", CYAN)
	elif roll == 2:
		dynamites += 1
		_say("Mystery cache: +1 dynamite", ORANGE)
	elif roll == 3:
		fever = minf(100.0, fever + 50.0)
		_say("Mystery cache: Gold Rush charge", GOLD)
	else:
		var bonus2 := 100 + level * 15
		credits += bonus2
		level_cash += bonus2
		lifetime_cash += bonus2
		time_left += 5.0
		_say("Mystery jackpot: cash + time", GREEN)
	_play_sfx("mystery")
	_vibrate(60)

func _resolve_tnt() -> void:
	combo = 0
	time_left = maxf(0.0, time_left - 5.0)
	explosion_particles.position = hook_tip
	explosion_particles.restart()
	explosion_particles.emitting = true
	_play_sfx("boom")
	_vibrate(110)
	_say("Unstable TNT!  -5 seconds", RED)
	var cleared := 0
	for obj in objects:
		if obj.get("removed", false) or String(obj.get("kind", "")) != "rock":
			continue
		var n := obj.get("node") as Node3D
		if is_instance_valid(n) and n.position.distance_to(hook_tip) < 2.7:
			_remove_object(obj)
			cleared += 1
	if cleared >= 2 and rng.randf() < 0.70:
		_spawn_specific("gold_m", Vector3(clampf(hook_tip.x, -4.0, 4.0), clampf(hook_tip.y - 1.4, -7.8, 4.2), 0.0))

func _use_dynamite() -> void:
	if phase != "playing" or dynamites <= 0 or hook_state != "retract" or hook_target.is_empty():
		_say("Dynamite works while hauling an unwanted object", MUTED)
		return
	dynamites -= 1
	var obj := hook_target
	var target_node := obj.get("node") as Node3D
	if is_instance_valid(target_node):
		explosion_particles.position = target_node.position
		explosion_particles.restart()
		explosion_particles.emitting = true
	_remove_object(obj)
	hook_target = {}
	hook_length = minf(hook_length, 3.2)
	_play_sfx("boom")
	_vibrate(100)
	_say("Dynamite deployed — load destroyed", ORANGE)
	_update_hud()

func _start_level(target_level: int) -> void:
	_close_all_panels()
	level = maxi(1, target_level)
	best_level = maxi(best_level, level)
	level_cash = 0
	combo = 0
	fever = 0.0
	fever_time = 0.0
	goal = int(900.0 * pow(1.18, float(level - 1)))
	time_left = maxf(46.0, 68.0 - float(level - 1) * 0.7) + float(time_level) * 2.5
	phase = "playing"
	paused_for_panel = false
	_clear_objects()
	_generate_level()
	_reset_hook()
	_update_hud()
	_say("LEVEL %d — target $%d" % [level, goal], GOLD)
	_play_sfx("start")
	_save_game()

func _generate_level() -> void:
	var count := mini(27, 15 + int(level / 2))
	var planned: Array[String] = []
	planned.append_array(["gold_s", "gold_s", "gold_m", "rock", "rock", "gold_l", "mystery"])
	if level >= 2:
		planned.append("diamond")
	if level >= 3:
		planned.append("fossil")
	if level >= 4:
		planned.append("tnt")
	while planned.size() < count:
		planned.append(_random_kind())
	planned.shuffle()
	for kind in planned:
		var pos := _find_spawn_position(kind)
		_spawn_specific(kind, pos)

func _random_kind() -> String:
	var luck := float(luck_level) * 0.018
	var r := rng.randf()
	if r < 0.025 + luck:
		return "diamond"
	if r < 0.075 + luck * 1.5:
		return "mystery"
	if level >= 3 and r < 0.13 + luck:
		return "fossil"
	if level >= 4 and r > 0.955:
		return "tnt"
	if r < 0.27 + luck:
		return "gold_l"
	if r < 0.54 + luck:
		return "gold_m"
	if r < 0.77:
		return "gold_s"
	return "rock"

func _find_spawn_position(kind: String) -> Vector3:
	var radius := _kind_radius(kind)
	for _attempt in range(90):
		var pos := Vector3(rng.randf_range(-4.2, 4.2), rng.randf_range(-7.8, 4.35), rng.randf_range(-0.18, 0.22))
		if pos.y > 3.4 and absf(pos.x) < 1.1:
			continue
		var clear := true
		for obj in objects:
			if obj.get("removed", false):
				continue
			var n := obj.get("node") as Node3D
			if is_instance_valid(n):
				var min_dist := radius + float(obj.get("radius", 0.5)) + 0.26
				if Vector2(pos.x - n.position.x, pos.y - n.position.y).length() < min_dist:
					clear = false
					break
		if clear:
			return pos
	return Vector3(rng.randf_range(-4.0, 4.0), rng.randf_range(-7.5, 3.8), 0)

func _kind_radius(kind: String) -> float:
	match kind:
		"gold_s": return 0.38
		"gold_m": return 0.58
		"gold_l": return 0.82
		"diamond": return 0.42
		"mystery": return 0.48
		"fossil": return 0.64
		"tnt": return 0.52
		_: return 0.68

func _spawn_specific(kind: String, pos: Vector3) -> void:
	var data := _object_data(kind)
	var node := Node3D.new()
	node.name = String(data["name"]).replace(" ", "")
	node.position = pos
	node.rotation.z = rng.randf_range(-0.32, 0.32)
	object_root.add_child(node)
	_build_object_model(node, kind, data)
	var obj := {"kind": kind, "name": data["name"], "value": data["value"], "weight": data["weight"], "radius": data["radius"], "color": data["color"], "node": node, "removed": false}
	objects.append(obj)

func _object_data(kind: String) -> Dictionary:
	match kind:
		"gold_s": return {"name":"Small Gold", "value":90 + level * 5, "weight":0.8, "radius":0.38, "color":GOLD}
		"gold_m": return {"name":"Gold Cluster", "value":220 + level * 10, "weight":2.0, "radius":0.58, "color":GOLD_HI}
		"gold_l": return {"name":"Motherlode", "value":560 + level * 22, "weight":4.6, "radius":0.82, "color":GOLD_HI}
		"diamond": return {"name":"Deep Diamond", "value":900 + level * 34, "weight":0.65, "radius":0.42, "color":CYAN}
		"mystery": return {"name":"Mystery Cache", "value":0, "weight":1.35, "radius":0.48, "color":PURPLE}
		"fossil": return {"name":"Ancient Fossil", "value":390 + level * 18, "weight":3.1, "radius":0.64, "color":Color(0.85,0.77,0.58)}
		"tnt": return {"name":"Unstable TNT", "value":0, "weight":1.0, "radius":0.52, "color":RED}
		_: return {"name":"Heavy Rock", "value":24 + level * 2, "weight":5.8, "radius":0.68, "color":Color(0.37,0.38,0.40)}

func _build_object_model(root: Node3D, kind: String, data: Dictionary) -> void:
	if kind.begins_with("gold"):
		var scale_factor := 0.43 if kind == "gold_s" else 0.64 if kind == "gold_m" else 0.90
		for i in range(4 if kind != "gold_l" else 6):
			var mesh := SphereMesh.new()
			mesh.radial_segments = 9
			mesh.rings = 6
			var n := MeshInstance3D.new()
			n.mesh = mesh
			n.scale = Vector3(scale_factor * rng.randf_range(0.55, 0.9), scale_factor * rng.randf_range(0.48, 0.82), scale_factor * rng.randf_range(0.55, 0.85))
			n.position = Vector3(rng.randf_range(-scale_factor * 0.42, scale_factor * 0.42), rng.randf_range(-scale_factor * 0.34, scale_factor * 0.34), rng.randf_range(-0.12, 0.12))
			n.material_override = _material(GOLD, 0.86, 0.18, 0.25)
			root.add_child(n)
		_add_glow(root, GOLD_HI, 0.65 if kind == "gold_s" else 1.2)
	elif kind == "rock":
		var r := _make_rock(Vector3(0.70, 0.58, 0.52), Color(0.34, 0.35, 0.37))
		root.add_child(r)
		for i in range(3):
			var chip := _make_rock(Vector3(0.15,0.10,0.12), Color(0.23,0.24,0.26))
			chip.position = Vector3(rng.randf_range(-0.45,0.45),rng.randf_range(-0.30,0.30),0.30)
			root.add_child(chip)
	elif kind == "diamond":
		var top_mesh := CylinderMesh.new()
		top_mesh.top_radius = 0.0
		top_mesh.bottom_radius = 0.46
		top_mesh.height = 0.78
		top_mesh.radial_segments = 6
		var top := MeshInstance3D.new()
		top.mesh = top_mesh
		top.position.y = 0.20
		top.material_override = _material(CYAN, 0.22, 0.12, 2.7)
		root.add_child(top)
		var bot_mesh := CylinderMesh.new()
		bot_mesh.top_radius = 0.46
		bot_mesh.bottom_radius = 0.0
		bot_mesh.height = 0.54
		bot_mesh.radial_segments = 6
		var bot := MeshInstance3D.new()
		bot.mesh = bot_mesh
		bot.position.y = -0.42
		bot.material_override = _material(Color(0.18,0.66,1.0), 0.24, 0.10, 2.4)
		root.add_child(bot)
		_add_glow(root, CYAN, 2.0)
	elif kind == "mystery":
		var bag_mesh := SphereMesh.new()
		bag_mesh.radial_segments = 10
		bag_mesh.rings = 7
		var bag := MeshInstance3D.new()
		bag.mesh = bag_mesh
		bag.scale = Vector3(0.50,0.58,0.34)
		bag.material_override = _material(Color(0.39,0.19,0.50),0.08,0.65,0.55)
		root.add_child(bag)
		var ring_mesh := TorusMesh.new()
		ring_mesh.inner_radius = 0.11
		ring_mesh.outer_radius = 0.18
		ring_mesh.rings = 10
		ring_mesh.ring_segments = 6
		var ring := MeshInstance3D.new()
		ring.mesh = ring_mesh
		ring.position.y = 0.55
		ring.material_override = _material(GOLD,0.8,0.20)
		root.add_child(ring)
		_add_glow(root, PURPLE, 1.1)
	elif kind == "fossil":
		var rock := _make_rock(Vector3(0.68,0.55,0.42), Color(0.47,0.31,0.21))
		root.add_child(rock)
		var bone_mesh := TorusMesh.new()
		bone_mesh.inner_radius = 0.24
		bone_mesh.outer_radius = 0.31
		bone_mesh.rings = 16
		bone_mesh.ring_segments = 8
		var bone := MeshInstance3D.new()
		bone.mesh = bone_mesh
		bone.position.z = 0.40
		bone.scale = Vector3(1.0,0.72,1.0)
		bone.material_override = _material(Color(0.84,0.78,0.61),0,0.92)
		root.add_child(bone)
	elif kind == "tnt":
		var crate_mesh := BoxMesh.new()
		crate_mesh.size = Vector3(0.92,0.72,0.62)
		var crate := MeshInstance3D.new()
		crate.mesh = crate_mesh
		crate.material_override = _material(Color(0.34,0.12,0.08),0.1,0.78)
		root.add_child(crate)
		for x in [-0.22, 0.0, 0.22]:
			var stick_mesh := CylinderMesh.new()
			stick_mesh.top_radius = 0.11
			stick_mesh.bottom_radius = 0.11
			stick_mesh.height = 0.72
			stick_mesh.radial_segments = 8
			var stick := MeshInstance3D.new()
			stick.mesh = stick_mesh
			stick.position = Vector3(x,0,0.36)
			stick.material_override = _material(RED,0,0.55,0.45)
			root.add_child(stick)
		_add_glow(root, RED, 1.0)

func _add_glow(root: Node3D, color: Color, energy: float) -> void:
	var light := OmniLight3D.new()
	light.light_color = color
	light.light_energy = energy
	light.omni_range = 2.5
	root.add_child(light)

func _clear_objects() -> void:
	objects.clear()
	for child in object_root.get_children():
		child.queue_free()

func _finish_level() -> void:
	if phase != "playing":
		return
	phase = "result"
	if hook_target.size() > 0:
		if not hook_target.get("removed", false):
			_remove_object(hook_target)
		hook_target = {}
	_reset_hook()
	var won := level_cash >= goal
	var ratio := float(level_cash) / maxf(1.0, float(goal))
	var stars := 0
	if won:
		stars = 1
		if ratio >= 1.25:
			stars = 2
		if ratio >= 1.60:
			stars = 3
		stars_total += stars
		best_level = maxi(best_level, level + 1)
		var bonus := level * 75 * stars
		credits += bonus
		lifetime_cash += bonus
		result_title.text = "LEVEL CLEAR"
		result_title.add_theme_color_override("font_color", GOLD_HI)
		result_details.text = "Target $%d\nMined $%d\n%s\nBonus +$%d\nBest combo x%d" % [goal, level_cash, "★".repeat(stars) + "☆".repeat(3-stars), bonus, best_combo]
		result_button.text = "UPGRADE RIG"
		_play_sfx("win")
		_vibrate(120)
	else:
		result_title.text = "SHIFT FAILED"
		result_title.add_theme_color_override("font_color", RED)
		result_details.text = "Target $%d\nMined $%d\nShort by $%d\nUpgrade or retry the level." % [goal, level_cash, maxi(0, goal-level_cash)]
		result_button.text = "RETRY LEVEL"
		_play_sfx("fail")
	result_panel.visible = true
	_save_game()
	_submit_score(true)

func _result_action() -> void:
	if level_cash >= goal:
		result_panel.visible = false
		_open_shop(true)
	else:
		_start_level(level)

func _continue_from_shop() -> void:
	_start_level(level + 1)

func _style(bg: Color, accent := Color.TRANSPARENT, radius := 18, border := 2) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.corner_radius_top_left = radius
	s.corner_radius_top_right = radius
	s.corner_radius_bottom_left = radius
	s.corner_radius_bottom_right = radius
	s.border_width_left = border
	s.border_width_right = border
	s.border_width_top = border
	s.border_width_bottom = border
	s.border_color = accent
	s.content_margin_left = 18
	s.content_margin_right = 18
	s.content_margin_top = 12
	s.content_margin_bottom = 12
	return s

func _label(text: String, size: int, color := TEXT) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l

func _button(text: String, accent: Color, size := 22) -> Button:
	var b := Button.new()
	b.text = text
	b.add_theme_font_size_override("font_size", size)
	b.add_theme_color_override("font_color", TEXT)
	b.add_theme_stylebox_override("normal", _style(accent.darkened(0.68), accent.darkened(0.12), 18, 2))
	b.add_theme_stylebox_override("hover", _style(accent.darkened(0.58), accent, 18, 2))
	b.add_theme_stylebox_override("pressed", _style(accent.darkened(0.78), accent.lightened(0.15), 18, 2))
	b.add_theme_stylebox_override("disabled", _style(Color(0.08,0.07,0.065), Color(0.18,0.17,0.16), 18, 1))
	return b

func _build_ui() -> void:
	canvas = CanvasLayer.new()
	canvas.name = "CanvasLayer"
	add_child(canvas)
	hud_root = Control.new()
	hud_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	canvas.add_child(hud_root)
	var top := PanelContainer.new()
	top.position = Vector2(26, 26)
	top.size = Vector2(1028, 210)
	top.add_theme_stylebox_override("panel", _style(Color(0.075,0.048,0.030,0.95), Color(0.55,0.31,0.10,0.72), 24, 2))
	hud_root.add_child(top)
	var top_v := VBoxContainer.new()
	top_v.add_theme_constant_override("separation", 7)
	top.add_child(top_v)
	var line1 := HBoxContainer.new()
	top_v.add_child(line1)
	money_lbl = _label("MONEY  $0", 31, GREEN)
	money_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	line1.add_child(money_lbl)
	status_lbl = _label("ONLINE", 18, GREEN)
	line1.add_child(status_lbl)
	pause_btn = _button("Ⅱ", Color(0.45,0.36,0.29), 24)
	pause_btn.custom_minimum_size = Vector2(70, 52)
	pause_btn.pressed.connect(_toggle_pause)
	line1.add_child(pause_btn)
	var line2 := HBoxContainer.new()
	top_v.add_child(line2)
	goal_lbl = _label("GOAL  $0", 26, GOLD_HI)
	goal_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	line2.add_child(goal_lbl)
	level_lbl = _label("LEVEL 1", 24, CYAN)
	level_lbl.custom_minimum_size.x = 190
	line2.add_child(level_lbl)
	time_lbl = _label("TIME  65", 26, ORANGE)
	time_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	time_lbl.custom_minimum_size.x = 220
	line2.add_child(time_lbl)
	var line3 := HBoxContainer.new()
	top_v.add_child(line3)
	combo_lbl = _label("COMBO x0", 18, MUTED)
	combo_lbl.custom_minimum_size.x = 180
	line3.add_child(combo_lbl)
	fever_bar = ProgressBar.new()
	fever_bar.min_value = 0
	fever_bar.max_value = 100
	fever_bar.show_percentage = false
	fever_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	fever_bar.custom_minimum_size.y = 22
	fever_bar.add_theme_stylebox_override("background", _style(Color(0.06,0.04,0.025), Color.TRANSPARENT, 10, 0))
	fever_bar.add_theme_stylebox_override("fill", _style(GOLD.darkened(0.12), Color.TRANSPARENT, 10, 0))
	line3.add_child(fever_bar)
	line3.add_child(_label(" GOLD RUSH", 16, GOLD))
	var hint := _label("TAP ANYWHERE IN THE MINE TO FIRE THE CLAW", 19, Color(0.90,0.82,0.69))
	hint.position = Vector2(100, 1555)
	hint.size = Vector2(880, 54)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud_root.add_child(hint)
	dynamite_btn = _button("DYNAMITE  ×2", ORANGE, 23)
	dynamite_btn.position = Vector2(48, 1640)
	dynamite_btn.size = Vector2(360, 110)
	dynamite_btn.pressed.connect(_use_dynamite)
	hud_root.add_child(dynamite_btn)
	var rank_btn := _button("GLOBAL RANKING", PURPLE, 21)
	rank_btn.position = Vector2(672, 1640)
	rank_btn.size = Vector2(360, 110)
	rank_btn.pressed.connect(_open_leaderboard)
	hud_root.add_child(rank_btn)
	var help_btn := _button("?", CYAN, 27)
	help_btn.position = Vector2(455, 1640)
	help_btn.size = Vector2(170, 110)
	help_btn.pressed.connect(_open_help)
	hud_root.add_child(help_btn)
	toast = _label("", 27, TEXT)
	toast.position = Vector2(80, 1465)
	toast.size = Vector2(920, 70)
	toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	toast.modulate.a = 0.0
	toast.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud_root.add_child(toast)
	_build_result_panel()
	_build_shop_panel()
	_build_leaderboard_panel()
	_build_help_panel()
	_update_hud()

func _build_result_panel() -> void:
	result_panel = PanelContainer.new()
	result_panel.position = Vector2(115, 520)
	result_panel.size = Vector2(850, 670)
	result_panel.add_theme_stylebox_override("panel", _style(Color(0.055,0.032,0.022,0.995), GOLD.darkened(0.25), 30, 3))
	result_panel.visible = false
	hud_root.add_child(result_panel)
	var v := VBoxContainer.new()
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_theme_constant_override("separation", 24)
	result_panel.add_child(v)
	result_title = _label("LEVEL CLEAR", 48, GOLD_HI)
	result_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(result_title)
	result_details = _label("", 27, TEXT)
	result_details.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(result_details)
	result_button = _button("CONTINUE", GOLD, 28)
	result_button.custom_minimum_size.y = 100
	result_button.pressed.connect(_result_action)
	v.add_child(result_button)

func _build_shop_panel() -> void:
	shop_panel = PanelContainer.new()
	shop_panel.position = Vector2(55, 300)
	shop_panel.size = Vector2(970, 1370)
	shop_panel.add_theme_stylebox_override("panel", _style(Color(0.045,0.031,0.024,0.997), Color(0.58,0.33,0.12), 28, 3))
	shop_panel.visible = false
	hud_root.add_child(shop_panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 13)
	shop_panel.add_child(v)
	var title := _label("RIG WORKSHOP", 39, GOLD_HI)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(title)
	shop_credits_lbl = _label("CREDITS $0", 25, GREEN)
	shop_credits_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(shop_credits_lbl)
	var sub := _label("Permanent upgrades carry through every level.", 19, MUTED)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(sub)
	_add_upgrade_row(v, "WINCH SPEED", "Haul heavy objects faster", "winch", CYAN)
	_add_upgrade_row(v, "CLAW STRENGTH", "Reduces weight slowdown", "strength", GOLD)
	_add_upgrade_row(v, "LUCK SCANNER", "More diamonds and rare caches", "luck", PURPLE)
	_add_upgrade_row(v, "MAGNET COIL", "Larger grab radius", "magnet", GREEN)
	_add_upgrade_row(v, "SHIFT CLOCK", "+2.5 seconds each level", "time", ORANGE)
	var dyn_row := HBoxContainer.new()
	v.add_child(dyn_row)
	var dyn_text := _label("DYNAMITE PACK\nDestroy a bad haul instantly", 21, TEXT)
	dyn_text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	dyn_row.add_child(dyn_text)
	var dyn_buy := _button("BUY ×2\n$180", ORANGE, 20)
	dyn_buy.custom_minimum_size = Vector2(280, 92)
	dyn_buy.pressed.connect(_buy_dynamite)
	dyn_buy.set_meta("shop_kind", "dynamite")
	dyn_row.add_child(dyn_buy)
	var start := _button("START NEXT LEVEL", GOLD, 27)
	start.custom_minimum_size.y = 105
	start.set_meta("continue_button", true)
	start.pressed.connect(_continue_from_shop)
	v.add_child(start)
	var close := _button("BACK", Color(0.38,0.30,0.25), 21)
	close.custom_minimum_size.y = 75
	close.pressed.connect(_close_all_panels)
	v.add_child(close)

func _add_upgrade_row(parent: VBoxContainer, title: String, desc: String, kind: String, color: Color) -> void:
	var p := PanelContainer.new()
	p.custom_minimum_size.y = 145
	p.add_theme_stylebox_override("panel", _style(PANEL_LIGHT, Color(0.28,0.18,0.11), 18, 1))
	parent.add_child(p)
	var h := HBoxContainer.new()
	p.add_child(h)
	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(left)
	left.add_child(_label(title, 24, color))
	left.add_child(_label(desc, 18, MUTED))
	var lvl := _label("LEVEL 0", 18, TEXT)
	lvl.set_meta("upgrade_level", kind)
	left.add_child(lvl)
	var buy := _button("BUY", color, 20)
	buy.custom_minimum_size = Vector2(270, 92)
	buy.set_meta("upgrade_buy", kind)
	buy.pressed.connect(_buy_upgrade.bind(kind))
	h.add_child(buy)

func _build_leaderboard_panel() -> void:
	leaderboard_panel = PanelContainer.new()
	leaderboard_panel.position = Vector2(55, 300)
	leaderboard_panel.size = Vector2(970, 1370)
	leaderboard_panel.add_theme_stylebox_override("panel", _style(Color(0.038,0.029,0.046,0.997), PURPLE.darkened(0.20), 28, 3))
	leaderboard_panel.visible = false
	hud_root.add_child(leaderboard_panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 15)
	leaderboard_panel.add_child(v)
	var title := _label("GLOBAL MINING LEAGUE", 37, PURPLE.lightened(0.20))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(title)
	var name_row := HBoxContainer.new()
	v.add_child(name_row)
	name_edit = LineEdit.new()
	name_edit.text = player_name
	name_edit.max_length = 18
	name_edit.custom_minimum_size = Vector2(570, 72)
	name_edit.add_theme_font_size_override("font_size", 22)
	name_row.add_child(name_edit)
	var save_name := _button("SAVE NAME", CYAN, 19)
	save_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	save_name.pressed.connect(_save_name)
	name_row.add_child(save_name)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size.y = 930
	v.add_child(scroll)
	rank_list = VBoxContainer.new()
	rank_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rank_list.add_theme_constant_override("separation", 5)
	scroll.add_child(rank_list)
	var buttons := HBoxContainer.new()
	v.add_child(buttons)
	var refresh := _button("REFRESH", PURPLE, 20)
	refresh.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	refresh.pressed.connect(_get_board)
	buttons.add_child(refresh)
	var submit := _button("SUBMIT", GOLD, 20)
	submit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	submit.pressed.connect(_submit_score.bind(false))
	buttons.add_child(submit)
	var close := _button("BACK TO MINE", CYAN, 21)
	close.custom_minimum_size.y = 78
	close.pressed.connect(_close_all_panels)
	v.add_child(close)

func _build_help_panel() -> void:
	help_panel = PanelContainer.new()
	help_panel.position = Vector2(85, 430)
	help_panel.size = Vector2(910, 930)
	help_panel.add_theme_stylebox_override("panel", _style(Color(0.038,0.035,0.031,0.997), CYAN.darkened(0.35), 28, 2))
	help_panel.visible = false
	hud_root.add_child(help_panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 18)
	help_panel.add_child(v)
	var title := _label("HOW TO MINE", 38, CYAN)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(title)
	v.add_child(_label("• The claw swings automatically. Tap the mine at the right angle.\n\n• Gold and diamonds pay well. Large finds are heavier and return slowly.\n\n• Rocks are cheap and heavy — use dynamite while hauling one.\n\n• Consecutive valuable finds build COMBO and charge GOLD RUSH.\n\n• Reach the money goal before the shift timer expires.\n\n• Upgrade the rig between successful levels.\n\n• Your best level and lifetime haul are saved and can be submitted online.", 23, TEXT))
	var close := _button("GOT IT", CYAN, 24)
	close.custom_minimum_size.y = 90
	close.pressed.connect(_close_all_panels)
	v.add_child(close)

func _show_intro() -> void:
	intro_overlay = ColorRect.new()
	intro_overlay.color = Color(0.025,0.014,0.010,1.0)
	intro_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	intro_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	hud_root.add_child(intro_overlay)
	var v := VBoxContainer.new()
	v.position = Vector2(90, 620)
	v.size = Vector2(900, 600)
	v.add_theme_constant_override("separation", 8)
	intro_overlay.add_child(v)
	var pre := _label("SKYLOST LABS", 21, MUTED)
	pre.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(pre)
	var title := _label("DEEPCORE", 76, GOLD_HI)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(title)
	var sub := _label("G O L D   R U S H", 34, CYAN)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(sub)
	var strap := _label("A modern claw-mining challenge", 22, Color(0.86,0.76,0.62))
	strap.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(strap)
	var play := _button("START MINING", GOLD, 29)
	play.custom_minimum_size.y = 110
	play.pressed.connect(_dismiss_intro)
	v.add_child(play)
	var resume := _button("CONTINUE LEVEL %d" % best_level, CYAN, 22)
	resume.custom_minimum_size.y = 82
	resume.visible = best_level > 1
	resume.pressed.connect(func(): _dismiss_intro(best_level))
	v.add_child(resume)

func _dismiss_intro(start_at := 1) -> void:
	if intro_overlay:
		intro_overlay.queue_free()
		intro_overlay = null
	_play_sfx("start")
	_start_level(start_at)

func _update_hud() -> void:
	if not money_lbl:
		return
	money_lbl.text = "MONEY  $%d" % level_cash
	goal_lbl.text = "GOAL  $%d" % goal
	level_lbl.text = "LEVEL %d" % level
	time_lbl.text = "TIME  %02d" % int(ceil(time_left))
	time_lbl.add_theme_color_override("font_color", RED if time_left <= 10.0 else ORANGE)
	combo_lbl.text = "COMBO  x%d" % combo
	combo_lbl.add_theme_color_override("font_color", GOLD_HI if combo >= 3 else MUTED)
	fever_bar.value = 100.0 if fever_time > 0.0 else fever
	dynamite_btn.text = "DYNAMITE  ×%d" % dynamites
	dynamite_btn.disabled = dynamites <= 0
	if fever_time > 0.0:
		goal_lbl.text = "GOLD RUSH  %.1fs" % fever_time
	_refresh_shop()

func _say(text: String, color: Color) -> void:
	if not toast:
		return
	toast.text = text
	toast.add_theme_color_override("font_color", color)
	toast.modulate.a = 0.0
	var tw := create_tween()
	tw.tween_property(toast, "modulate:a", 1.0, 0.12)
	tw.tween_interval(1.25)
	tw.tween_property(toast, "modulate:a", 0.0, 0.32)

func _toggle_pause() -> void:
	if phase != "playing":
		return
	paused_for_panel = not paused_for_panel
	pause_btn.text = "▶" if paused_for_panel else "Ⅱ"
	_say("SHIFT PAUSED" if paused_for_panel else "SHIFT RESUMED", MUTED)

func _open_help() -> void:
	paused_for_panel = true
	leaderboard_panel.visible = false
	shop_panel.visible = false
	help_panel.visible = true

func _open_shop(after_win := false) -> void:
	paused_for_panel = true
	leaderboard_panel.visible = false
	help_panel.visible = false
	shop_panel.visible = true
	var continue_button := _find_meta_node(shop_panel, "continue_button") as Button
	if continue_button:
		continue_button.visible = after_win
	_refresh_shop()

func _open_leaderboard() -> void:
	paused_for_panel = true
	shop_panel.visible = false
	help_panel.visible = false
	leaderboard_panel.visible = true
	name_edit.text = player_name
	_get_board()

func _close_all_panels() -> void:
	result_panel.visible = false
	shop_panel.visible = false
	leaderboard_panel.visible = false
	help_panel.visible = false
	paused_for_panel = false
	if pause_btn:
		pause_btn.text = "Ⅱ"

func _upgrade_level(kind: String) -> int:
	match kind:
		"winch": return winch_level
		"strength": return strength_level
		"luck": return luck_level
		"magnet": return magnet_level
		"time": return time_level
		_: return 0

func _upgrade_cost(kind: String) -> int:
	var lvl := _upgrade_level(kind)
	var base := 180
	match kind:
		"winch": base = 190
		"strength": base = 220
		"luck": base = 310
		"magnet": base = 275
		"time": base = 340
	return int(float(base) * pow(1.62, float(maxi(0, lvl - (1 if kind in ["winch","strength"] else 0)))))

func _max_upgrade(kind: String) -> int:
	return 10 if kind in ["winch", "strength"] else 8 if kind in ["luck", "magnet"] else 6

func _buy_upgrade(kind: String) -> void:
	var lvl := _upgrade_level(kind)
	if lvl >= _max_upgrade(kind):
		_say("Upgrade already maxed", MUTED)
		return
	var price := _upgrade_cost(kind)
	if credits < price:
		_say("Need $%d credits" % price, RED)
		return
	credits -= price
	match kind:
		"winch": winch_level += 1
		"strength": strength_level += 1
		"luck": luck_level += 1
		"magnet": magnet_level += 1
		"time": time_level += 1
	_play_sfx("upgrade")
	_vibrate(35)
	_say("Rig upgraded", GREEN)
	_save_game()
	_refresh_shop()

func _buy_dynamite() -> void:
	if credits < 180:
		_say("Need $180 credits", RED)
		return
	credits -= 180
	dynamites += 2
	_play_sfx("upgrade")
	_say("+2 dynamite loaded", ORANGE)
	_save_game()
	_refresh_shop()

func _refresh_shop() -> void:
	if not shop_panel:
		return
	shop_credits_lbl.text = "CREDITS  $%d   •   DYNAMITE ×%d" % [credits, dynamites]
	for n in _all_nodes(shop_panel):
		if n.has_meta("upgrade_level") and n is Label:
			var kind := String(n.get_meta("upgrade_level"))
			var lvl := _upgrade_level(kind)
			(n as Label).text = "LEVEL %d / %d" % [lvl, _max_upgrade(kind)]
		elif n.has_meta("upgrade_buy") and n is Button:
			var kind2 := String(n.get_meta("upgrade_buy"))
			var lvl2 := _upgrade_level(kind2)
			var b := n as Button
			if lvl2 >= _max_upgrade(kind2):
				b.text = "MAXED"
				b.disabled = true
			else:
				var price := _upgrade_cost(kind2)
				b.text = "UPGRADE\n$%d" % price
				b.disabled = credits < price
		elif n.has_meta("shop_kind") and n is Button:
			(n as Button).disabled = credits < 180

func _all_nodes(root: Node) -> Array:
	var arr: Array = []
	for n in root.get_children():
		arr.append(n)
		arr.append_array(_all_nodes(n))
	return arr

func _find_meta_node(root: Node, key: String) -> Node:
	for n in _all_nodes(root):
		if n.has_meta(key):
			return n
	return null

func _build_audio() -> void:
	for key in ["launch","grab","coin","rock","boom","mystery","fever","win","fail","upgrade","start","empty"]:
		var p := AudioStreamPlayer.new()
		p.volume_db = -5.0
		var path := "res://assets/sfx/%s.wav" % key
		if ResourceLoader.exists(path):
			p.stream = load(path)
		add_child(p)
		audio_players[key] = p

func _play_sfx(key: String) -> void:
	if not sound_enabled:
		return
	if audio_players.has(key):
		var p := audio_players[key] as AudioStreamPlayer
		if p.stream:
			p.stop()
			p.play()

func _vibrate(ms: int) -> void:
	if haptics_enabled:
		Input.vibrate_handheld(ms)

func _build_network() -> void:
	http = HTTPRequest.new()
	http.timeout = 7.0
	http.request_completed.connect(_http_done)
	add_child(http)

func _get_board() -> void:
	if http_busy or LEADERBOARD_URL.begins_with("__"):
		return
	http_busy = true
	http_mode = "get"
	status_lbl.text = "SYNCING"
	var err := http.request(LEADERBOARD_URL, PackedStringArray(["Accept: application/json"]))
	if err != OK:
		http_busy = false
		_network_fail()

func _submit_score(silent := false) -> void:
	if http_busy or LEADERBOARD_URL.begins_with("__"):
		return
	http_busy = true
	http_mode = "submit_get"
	if not silent:
		status_lbl.text = "SYNCING"
	var err := http.request(LEADERBOARD_URL, PackedStringArray(["Accept: application/json"]))
	if err != OK:
		http_busy = false
		_network_fail()

func _http_done(_result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	http_busy = false
	if code < 200 or code >= 300:
		_network_fail()
		return
	var parsed = JSON.parse_string(body.get_string_from_utf8())
	var data: Dictionary = parsed if parsed is Dictionary else {"entries": []}
	if not data.has("entries") or not data["entries"] is Array:
		data["entries"] = []
	if http_mode == "get":
		_draw_board(data)
		_set_online(true)
	elif http_mode == "submit_get":
		var entries: Array = data["entries"]
		var found := false
		for i in range(entries.size()):
			if String(entries[i].get("id", "")) == player_id:
				entries[i] = _leader_entry()
				found = true
				break
		if not found:
			entries.append(_leader_entry())
		entries.sort_custom(func(a, b):
			if int(a.get("level", 1)) == int(b.get("level", 1)):
				return int(a.get("score", 0)) > int(b.get("score", 0))
			return int(a.get("level", 1)) > int(b.get("level", 1))
		)
		if entries.size() > 60:
			entries.resize(60)
		data["entries"] = entries
		pending_board = data
		call_deferred("_put_board")
	elif http_mode == "put":
		_draw_board(pending_board)
		_set_online(true)

func _put_board() -> void:
	http_busy = true
	http_mode = "put"
	var err := http.request(LEADERBOARD_URL, PackedStringArray(["Content-Type: application/json", "Accept: application/json"]), HTTPClient.METHOD_PUT, JSON.stringify(pending_board))
	if err != OK:
		http_busy = false
		_network_fail()

func _leader_entry() -> Dictionary:
	return {"id": player_id, "name": player_name, "level": best_level, "score": lifetime_cash, "stars": stars_total, "combo": best_combo, "updated": int(Time.get_unix_time_from_system())}

func _draw_board(data: Dictionary) -> void:
	if not rank_list:
		return
	for n in rank_list.get_children():
		n.queue_free()
	var entries: Array = data.get("entries", [])
	entries.sort_custom(func(a, b):
		if int(a.get("level", 1)) == int(b.get("level", 1)):
			return int(a.get("score", 0)) > int(b.get("score", 0))
		return int(a.get("level", 1)) > int(b.get("level", 1))
	)
	for i in range(mini(entries.size(), 25)):
		var e: Dictionary = entries[i]
		var row := PanelContainer.new()
		row.custom_minimum_size.y = 72
		row.add_theme_stylebox_override("panel", _style(Color(0.070,0.052,0.081,0.82), Color(0.20,0.14,0.25), 12, 1))
		rank_list.add_child(row)
		var h := HBoxContainer.new()
		row.add_child(h)
		var rank := _label("#%d" % (i+1), 20, GOLD_HI if i < 3 else MUTED)
		rank.custom_minimum_size.x = 65
		h.add_child(rank)
		var nm := _label(String(e.get("name", "Miner")), 20, TEXT)
		nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		h.add_child(nm)
		var lv := _label("LV %d" % int(e.get("level", 1)), 18, CYAN)
		lv.custom_minimum_size.x = 110
		h.add_child(lv)
		var sc := _label("$%d" % int(e.get("score", 0)), 19, GOLD)
		sc.custom_minimum_size.x = 190
		sc.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		h.add_child(sc)
	if entries.is_empty():
		var empty := _label("No miners on the board yet. Be the first.", 22, MUTED)
		empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		rank_list.add_child(empty)

func _save_name() -> void:
	var clean := name_edit.text.strip_edges()
	if clean.length() < 2:
		_say("Name needs at least 2 characters", RED)
		return
	player_name = clean.substr(0, 18)
	_save_game()
	_submit_score(false)
	_say("Miner name saved", GREEN)

func _network_fail() -> void:
	_set_online(false)
	if leaderboard_panel.visible and rank_list:
		for n in rank_list.get_children():
			n.queue_free()
		var l := _label("Leaderboard temporarily unavailable.\nYour progress is saved locally.", 21, RED)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		rank_list.add_child(l)

func _set_online(ok: bool) -> void:
	status_lbl.text = "ONLINE" if ok else "OFFLINE"
	status_lbl.add_theme_color_override("font_color", GREEN if ok else RED)

func _save_game() -> void:
	last_saved = int(Time.get_unix_time_from_system())
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if not f:
		return
	f.store_string(JSON.stringify({"credits": credits, "lifetime": lifetime_cash, "best_level": best_level, "stars": stars_total, "best_combo": best_combo, "dynamites": dynamites, "winch": winch_level, "strength": strength_level, "luck": luck_level, "magnet": magnet_level, "time_upgrade": time_level, "id": player_id, "name": player_name, "sound": sound_enabled, "haptics": haptics_enabled, "last": last_saved}))

func _load_save() -> void:
	player_id = "%08x%08x" % [rng.randi(), rng.randi()]
	player_name = "Miner-%04d" % rng.randi_range(1000, 9999)
	if not FileAccess.file_exists(SAVE_PATH):
		return
	var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if not f:
		return
	var parsed = JSON.parse_string(f.get_as_text())
	if not parsed is Dictionary:
		return
	var d: Dictionary = parsed
	credits = maxi(0, int(d.get("credits", 250)))
	lifetime_cash = maxi(0, int(d.get("lifetime", 0)))
	best_level = maxi(1, int(d.get("best_level", 1)))
	stars_total = maxi(0, int(d.get("stars", 0)))
	best_combo = maxi(0, int(d.get("best_combo", 0)))
	dynamites = maxi(0, int(d.get("dynamites", 2)))
	winch_level = clampi(int(d.get("winch", 1)), 1, 10)
	strength_level = clampi(int(d.get("strength", 1)), 1, 10)
	luck_level = clampi(int(d.get("luck", 0)), 0, 8)
	magnet_level = clampi(int(d.get("magnet", 0)), 0, 8)
	time_level = clampi(int(d.get("time_upgrade", 0)), 0, 6)
	player_id = String(d.get("id", player_id))
	player_name = String(d.get("name", player_name))
	sound_enabled = bool(d.get("sound", true))
	haptics_enabled = bool(d.get("haptics", true))
	last_saved = int(d.get("last", 0))
