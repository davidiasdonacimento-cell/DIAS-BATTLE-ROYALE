extends Node3D

const ISLAND_SIZE := 240.0
const PLAYER_SPEED := 9.0
const JUMP_VELOCITY := 9.0
const CRYSTAL_GOAL := 5

var player: CharacterBody3D
var camera_pivot: Node3D
var camera: Camera3D
var plane: Node3D
var parachute: MeshInstance3D
var hud: Label
var notice: Label
var crystal_count := 0
var game_state := "plane"
var build_mode := false
var move_vector := Vector2.ZERO
var touch_flags := {"forward": false, "back": false, "left": false, "right": false}
var elapsed := 0.0
var storm_radius := 112.0
var beacon_area: Area3D
var beacon_unlocked := false
var built_count := 0
var bots: Array[Node3D] = []
var bot_targets: Array[Vector3] = []
var rng := RandomNumberGenerator.new()

func _ready() -> void:
	rng.randomize()
	_make_environment()
	_make_island()
	_make_player()
	_make_bots()
	_make_plane()
	_make_collectibles()
	_make_beacon()
	_make_hud()
	_update_hud()
	_show_notice("DIAS ISLAND ROYALE  •  Toque em SALTAR para iniciar!")

func _process(delta: float) -> void:
	for i in range(bots.size()):
		var bot := bots[i]
		if not is_instance_valid(bot):
			continue
		var target: Vector3 = bot_targets[i]
		var flat_target := Vector3(target.x, bot.position.y, target.z)
		if bot.position.distance_to(flat_target) < 2.0:
			var angle := rng.randf_range(0.0, TAU)
			var radius := rng.randf_range(12.0, 70.0)
			bot_targets[i] = Vector3(cos(angle) * radius, 0.0, sin(angle) * radius)
		else:
			bot.position = bot.position.move_toward(flat_target, delta * 2.2)

func _physics_process(delta: float) -> void:
	elapsed += delta
	if game_state == "plane":
		plane.position.x += delta * 13.0
		player.global_position = plane.global_position + Vector3(0, -1.2, 0)
		player.velocity = Vector3.ZERO
		if plane.position.x > 80.0:
			_jump_from_plane()
	elif game_state == "sky":
		player.velocity = Vector3(0, -5.0, 0)
		player.move_and_slide()
		if player.global_position.y <= 2.0:
			player.global_position.y = 2.0
			game_state = "landed"
			_remove_parachute()
			_show_notice("Pouso concluido! Colete cristais e alcance o farol.")
	else:
		_update_player_movement(delta)
	_update_storm(delta)
	_update_hud()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_SPACE:
				if game_state == "plane":
					_jump_from_plane()
				elif game_state == "landed":
					_player_jump()
			KEY_B:
				_toggle_build()
			KEY_1:
				_build_piece("wall")
			KEY_2:
				_build_piece("ramp")
			KEY_3:
				_build_piece("floor")
			KEY_E:
				_try_collect_nearby()

func _make_environment() -> void:
	var world_env := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = Sky.new()
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.65, 0.78, 0.95)
	env.ambient_light_energy = 0.8
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	world_env.environment = env
	add_child(world_env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-48, -32, 0)
	sun.light_energy = 1.25
	sun.shadow_enabled = true
	add_child(sun)

func _make_island() -> void:
	var ground := StaticBody3D.new()
	ground.name = "IslandGround"
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(ISLAND_SIZE, 2.0, ISLAND_SIZE)
	box.material = _material(Color(0.18, 0.48, 0.25))
	mesh.mesh = box
	mesh.position.y = -1.0
	ground.add_child(mesh)
	var shape := CollisionShape3D.new()
	var box_shape := BoxShape3D.new()
	box_shape.size = box.size
	shape.shape = box_shape
	shape.position.y = -1.0
	ground.add_child(shape)
	add_child(ground)

	# Praia clara nas bordas e caminhos de pedra.
	for i in range(36):
		var angle := TAU * float(i) / 36.0
		var rock := _make_box(Vector3(4.0, 1.0, 2.5), Color(0.78, 0.72, 0.55))
		rock.position = Vector3(cos(angle) * 111.0, -0.1, sin(angle) * 111.0)
		rock.rotation.y = -angle
		add_child(rock)

	# Vegetacao distribuida com espacos para explorar e construir.
	for i in range(95):
		var x := rng.randf_range(-100.0, 100.0)
		var z := rng.randf_range(-100.0, 100.0)
		if Vector2(x, z).length() < 15.0:
			continue
		_make_tree(Vector3(x, 0, z))

	# Pequena vila com construcoes simples.
	for i in range(7):
		var x := rng.randf_range(-55.0, 55.0)
		var z := rng.randf_range(-55.0, 55.0)
		if Vector2(x, z).length() < 24.0:
			x += 35.0
		var house := _make_box(Vector3(9, 6, 8), Color(0.68, 0.48, 0.30))
		house.position = Vector3(x, 3.0, z)
		add_child(house)
		var roof := _make_box(Vector3(10, 1.2, 9), Color(0.22, 0.28, 0.38))
		roof.position = Vector3(x, 6.6, z)
		add_child(roof)

func _make_player() -> void:
	player = CharacterBody3D.new()
	player.name = "Player"
	var body_mesh := MeshInstance3D.new()
	var capsule := CapsuleMesh.new()
	capsule.radius = 0.55
	capsule.height = 1.9
	capsule.material = _material(Color(0.12, 0.72, 0.95))
	body_mesh.mesh = capsule
	body_mesh.position.y = 0.95
	player.add_child(body_mesh)
	var collision := CollisionShape3D.new()
	var capsule_shape := CapsuleShape3D.new()
	capsule_shape.radius = 0.55
	capsule_shape.height = 1.9
	collision.shape = capsule_shape
	collision.position.y = 0.95
	player.add_child(collision)
	add_child(player)
	player.global_position = Vector3(0, 52, 0)

	camera_pivot = Node3D.new()
	camera_pivot.position = Vector3(0, 1.2, 0)
	player.add_child(camera_pivot)
	var spring := SpringArm3D.new()
	spring.spring_length = 7.0
	spring.margin = 0.2
	camera_pivot.add_child(spring)
	camera = Camera3D.new()
	camera.position = Vector3(0, 0.4, 0)
	camera.rotation_degrees.x = -12
	spring.add_child(camera)
	camera.current = true

func _make_bots() -> void:
	# Exploradores autonomos que percorrem a ilha; nao atacam o jogador.
	for i in range(6):
		var bot := Node3D.new()
		bot.name = "IslandExplorer_%d" % (i + 1)
		var body := MeshInstance3D.new()
		var capsule := CapsuleMesh.new()
		capsule.radius = 0.48
		capsule.height = 1.8
		capsule.material = _material(Color(0.95, 0.68, 0.18) if i % 2 == 0 else Color(0.72, 0.42, 0.92))
		body.mesh = capsule
		body.position.y = 0.9
		bot.add_child(body)
		var head := MeshInstance3D.new()
		var sphere := SphereMesh.new()
		sphere.radius = 0.32
		sphere.height = 0.64
		sphere.material = _material(Color(0.92, 0.78, 0.62))
		head.mesh = sphere
		head.position.y = 1.85
		bot.add_child(head)
		var angle := TAU * float(i) / 6.0
		bot.position = Vector3(cos(angle) * 28.0, 0.0, sin(angle) * 28.0)
		add_child(bot)
		bots.append(bot)
		var target_angle := angle + 1.4
		bot_targets.append(Vector3(cos(target_angle) * 48.0, 0.0, sin(target_angle) * 48.0))

func _make_plane() -> void:
	plane = Node3D.new()
	plane.name = "DropPlane"
	plane.position = Vector3(-90, 54, 0)
	var fuselage := _make_box(Vector3(13, 1.2, 2.0), Color(0.16, 0.20, 0.28))
	plane.add_child(fuselage)
	var wing := _make_box(Vector3(3.2, 0.25, 15.0), Color(0.12, 0.65, 0.85))
	wing.position.y = 0.2
	plane.add_child(wing)
	var tail := _make_box(Vector3(2.4, 0.25, 5.0), Color(0.12, 0.65, 0.85))
	tail.position = Vector3(-5.0, 1.0, 0)
	plane.add_child(tail)
	add_child(plane)

func _jump_from_plane() -> void:
	if game_state != "plane":
		return
	game_state = "sky"
	player.global_position = plane.global_position + Vector3(0, -2, 0)
	plane.queue_free()
	parachute = MeshInstance3D.new()
	var canopy := SphereMesh.new()
	canopy.radius = 2.8
	canopy.height = 1.0
	canopy.radial_segments = 20
	canopy.rings = 8
	canopy.material = _material(Color(0.95, 0.38, 0.16))
	parachute.mesh = canopy
	parachute.scale = Vector3(1.0, 0.25, 0.8)
	parachute.position = Vector3(0, 4.0, 0)
	player.add_child(parachute)
	_show_notice("SALTO! Seu paraquedas esta aberto.")

func _remove_parachute() -> void:
	if is_instance_valid(parachute):
		parachute.queue_free()

func _update_player_movement(delta: float) -> void:
	var input_dir := Vector2.ZERO
	input_dir.y -= float(touch_flags.forward)
	input_dir.y += float(touch_flags.back)
	input_dir.x -= float(touch_flags.left)
	input_dir.x += float(touch_flags.right)
	if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):
		input_dir.y -= 1.0
	if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):
		input_dir.y += 1.0
	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
		input_dir.x -= 1.0
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
		input_dir.x += 1.0
	input_dir += move_vector
	input_dir = input_dir.limit_length(1.0)
	var forward := -camera.global_transform.basis.z
	var right := camera.global_transform.basis.x
	var direction := (right * input_dir.x + forward * -input_dir.y)
	direction.y = 0
	direction = direction.normalized()
	player.velocity.x = direction.x * PLAYER_SPEED
	player.velocity.z = direction.z * PLAYER_SPEED
	if not player.is_on_floor():
		player.velocity.y -= 24.0 * delta
	else:
		if player.velocity.y < 0:
			player.velocity.y = 0
	player.move_and_slide()
	if direction.length() > 0.1:
		player.rotation.y = lerp_angle(player.rotation.y, atan2(-direction.x, -direction.z), delta * 10.0)

func _player_jump() -> void:
	if player.is_on_floor():
		player.velocity.y = JUMP_VELOCITY

func _make_collectibles() -> void:
	for i in range(12):
		var angle := rng.randf_range(0.0, TAU)
		var radius := rng.randf_range(18.0, 88.0)
		var p := Vector3(cos(angle) * radius, 1.0, sin(angle) * radius)
		_make_crystal(p)

func _make_crystal(pos: Vector3) -> void:
	var area := Area3D.new()
	area.position = pos
	area.set_meta("crystal", true)
	var crystal := MeshInstance3D.new()
	var mesh := PrismMesh.new()
	mesh.size = Vector3(1.0, 1.7, 1.0)
	mesh.material = _material(Color(0.15, 0.95, 0.9), 0.25)
	crystal.mesh = mesh
	area.add_child(crystal)
	var collision := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = 1.5
	collision.shape = sphere
	area.add_child(collision)
	area.body_entered.connect(_on_crystal_body_entered.bind(area))
	add_child(area)

func _on_crystal_body_entered(body: Node3D, area: Area3D) -> void:
	if body != player or not is_instance_valid(area):
		return
	crystal_count += 1
	area.queue_free()
	_show_notice("Cristal coletado! %d/%d" % [crystal_count, CRYSTAL_GOAL])
	if crystal_count >= CRYSTAL_GOAL:
		beacon_unlocked = true
		_show_notice("Farol ativado! Va ate o centro da ilha.")

func _make_beacon() -> void:
	var pillar := _make_box(Vector3(2.0, 8.0, 2.0), Color(0.2, 0.9, 0.95))
	pillar.position = Vector3(0, 4.0, 0)
	add_child(pillar)
	beacon_area = Area3D.new()
	beacon_area.position = Vector3(0, 1.5, 0)
	var shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = 4.0
	shape.shape = sphere
	beacon_area.add_child(shape)
	beacon_area.body_entered.connect(_on_beacon_entered)
	add_child(beacon_area)

func _on_beacon_entered(body: Node3D) -> void:
	if body == player and beacon_unlocked and game_state != "won":
		game_state = "won"
		_show_notice("VITORIA! Voce encontrou os cristais e ativou o farol!")

func _update_storm(delta: float) -> void:
	storm_radius = maxf(28.0, 112.0 - elapsed * 0.18)
	if game_state == "landed":
		var distance := Vector2(player.global_position.x, player.global_position.z).length()
		if distance > storm_radius:
			_show_notice("ATENCAO: a tempestade esta se aproximando do centro!")

func _make_hud() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var panel := ColorRect.new()
	panel.color = Color(0.02, 0.05, 0.10, 0.78)
	panel.position = Vector2(18, 16)
	panel.size = Vector2(430, 78)
	layer.add_child(panel)
	hud = Label.new()
	hud.position = Vector2(32, 25)
	hud.size = Vector2(400, 60)
	hud.add_theme_font_size_override("font_size", 20)
	hud.add_theme_color_override("font_color", Color(0.82, 0.96, 1.0))
	panel.add_child(hud)

	notice = Label.new()
	notice.anchor_left = 0.5
	notice.anchor_right = 0.5
	notice.offset_left = -300
	notice.offset_right = 300
	notice.offset_top = 105
	notice.offset_bottom = 150
	notice.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	notice.add_theme_font_size_override("font_size", 22)
	notice.add_theme_color_override("font_color", Color(1.0, 0.9, 0.55))
	layer.add_child(notice)

	_add_action_button(layer, "SALTAR", Vector2(-190, -175), Vector2(160, 68), _jump_from_plane, true)
	_add_action_button(layer, "PULAR", Vector2(-190, -95), Vector2(125, 58), _player_jump, true)
	_add_action_button(layer, "CONSTRUIR", Vector2(-360, -175), Vector2(155, 64), _toggle_build, true)
	_add_action_button(layer, "PAREDE", Vector2(-360, -100), Vector2(105, 54), _build_wall, true)
	_add_action_button(layer, "RAMPA", Vector2(-245, -100), Vector2(105, 54), _build_ramp, true)
	_add_action_button(layer, "PISO", Vector2(-130, -100), Vector2(95, 54), _build_floor, true)
	_add_action_button(layer, "COLETAR", Vector2(-190, -250), Vector2(140, 58), _try_collect_nearby, true)

	# Direcional touch no canto inferior esquerdo.
	_add_direction_button(layer, "↑", Vector2(35, -205), "forward")
	_add_direction_button(layer, "↓", Vector2(35, -85), "back")
	_add_direction_button(layer, "←", Vector2(-25, -145), "left")
	_add_direction_button(layer, "→", Vector2(95, -145), "right")

func _add_action_button(layer: CanvasLayer, text_value: String, bottom_right_offset: Vector2, button_size: Vector2, action: Callable, right_side: bool) -> void:
	var button := Button.new()
	button.text = text_value
	button.size = button_size
	button.anchor_left = 1.0
	button.anchor_right = 1.0
	button.anchor_top = 1.0
	button.anchor_bottom = 1.0
	button.offset_left = bottom_right_offset.x
	button.offset_right = bottom_right_offset.x + button_size.x
	button.offset_top = bottom_right_offset.y
	button.offset_bottom = bottom_right_offset.y + button_size.y
	button.add_theme_font_size_override("font_size", 18)
	button.add_theme_color_override("font_color", Color.WHITE)
	button.add_theme_stylebox_override("normal", _button_style(Color(0.04, 0.36, 0.56, 0.92)))
	button.add_theme_stylebox_override("pressed", _button_style(Color(0.08, 0.62, 0.72, 1.0)))
	button.pressed.connect(action)
	layer.add_child(button)

func _add_direction_button(layer: CanvasLayer, label_text: String, offset: Vector2, direction: String) -> void:
	var button := Button.new()
	button.text = label_text
	button.size = Vector2(58, 58)
	button.anchor_top = 1.0
	button.anchor_bottom = 1.0
	button.offset_left = offset.x
	button.offset_right = offset.x + 58
	button.offset_top = offset.y
	button.offset_bottom = offset.y + 58
	button.add_theme_font_size_override("font_size", 24)
	button.add_theme_stylebox_override("normal", _button_style(Color(0.08, 0.12, 0.2, 0.82)))
	button.button_down.connect(func(): touch_flags[direction] = true)
	button.button_up.connect(func(): touch_flags[direction] = false)
	layer.add_child(button)

func _button_style(color_value: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color_value
	style.corner_radius_top_left = 14
	style.corner_radius_top_right = 14
	style.corner_radius_bottom_left = 14
	style.corner_radius_bottom_right = 14
	style.border_width_left = 2
	style.border_width_right = 2
	style.border_width_top = 2
	style.border_width_bottom = 2
	style.border_color = Color(0.3, 0.85, 1.0, 0.9)
	return style

func _toggle_build() -> void:
	build_mode = not build_mode
	_show_notice("Modo construcao: %s" % ("ATIVADO" if build_mode else "DESATIVADO"))

func _build_wall() -> void:
	_build_piece("wall")

func _build_ramp() -> void:
	_build_piece("ramp")

func _build_floor() -> void:
	_build_piece("floor")

func _build_piece(kind: String) -> void:
	if game_state != "landed":
		_show_notice("A construcao fica disponivel depois do pouso.")
		return
	if not build_mode:
		_show_notice("Toque em CONSTRUIR primeiro.")
		return
	if built_count >= 35:
		_show_notice("Limite de construcoes atingido nesta partida.")
		return
	var forward := -player.global_transform.basis.z
	var pos := player.global_position + forward * 4.0
	pos.y = 1.0
	var size := Vector3(5.0, 0.35, 5.0)
	var color_value := Color(0.66, 0.42, 0.22)
	if kind == "wall":
		size = Vector3(5.0, 4.0, 0.35)
		pos.y = 2.0
		color_value = Color(0.55, 0.32, 0.18)
	elif kind == "ramp":
		size = Vector3(5.0, 0.4, 6.0)
		pos.y = 1.2
		color_value = Color(0.72, 0.52, 0.28)
	var piece := StaticBody3D.new()
	piece.position = pos
	piece.rotation.y = player.rotation.y
	if kind == "ramp":
		piece.rotation.x = -0.28
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	box.material = _material(color_value)
	mesh.mesh = box
	piece.add_child(mesh)
	var collision := CollisionShape3D.new()
	var box_shape := BoxShape3D.new()
	box_shape.size = size
	collision.shape = box_shape
	piece.add_child(collision)
	add_child(piece)
	built_count += 1
	_show_notice("%s construida! (%d/35)" % [kind.to_upper(), built_count])

func _try_collect_nearby() -> void:
	for node in get_children():
		if node is Area3D and node.has_meta("crystal") and node.global_position.distance_to(player.global_position) < 4.0:
			_on_crystal_body_entered(player, node)
			return
	_show_notice("Aproxime-se de um cristal brilhante para coletar.")

func _make_tree(pos: Vector3) -> void:
	var trunk := _make_box(Vector3(0.8, 4.0, 0.8), Color(0.34, 0.20, 0.10))
	trunk.position = pos + Vector3(0, 2.0, 0)
	add_child(trunk)
	var crown := MeshInstance3D.new()
	var cone := ConeMesh.new()
	cone.radius = 2.7
	cone.height = 6.0
	cone.material = _material(Color(0.08, rng.randf_range(0.32, 0.48), 0.18))
	crown.mesh = cone
	crown.position = pos + Vector3(0, 6.0, 0)
	add_child(crown)

func _make_box(size_value: Vector3, color_value: Color) -> MeshInstance3D:
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size_value
	box.material = _material(color_value)
	mesh.mesh = box
	return mesh

func _material(color_value: Color, metallic_value: float = 0.0) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color_value
	mat.metallic = metallic_value
	mat.roughness = 0.72
	return mat

func _show_notice(message: String) -> void:
	if is_instance_valid(notice):
		notice.text = message

func _update_hud() -> void:
	if not is_instance_valid(hud):
		return
	var state_text := "NO AVIAO"
	if game_state == "sky":
		state_text = "SALTO / PARAQUEDAS"
	elif game_state == "landed":
		state_text = "EXPLORACAO"
	elif game_state == "won":
		state_text = "VITORIA"
	hud.text = "DIAS ISLAND ROYALE\n%s  |  Cristais: %d/%d  |  Construcoes: %d" % [state_text, crystal_count, CRYSTAL_GOAL, built_count]
