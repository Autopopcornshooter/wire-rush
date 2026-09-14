extends Node3D
const City = preload("res://scripts/city.gd")
const Rider = preload("res://scripts/rider.gd")
const Hud = preload("res://scripts/hud.gd")
const Rules = preload("res://scripts/rules.gd")
const Preferences = preload("res://scripts/preferences.gd")
const Locale = preload("res://scripts/localization.gd")
var preferences = Preferences.new()
var locale = Locale.new()
var settings_return: String = "menu"
var settings_error: bool = false
var aim_screen := Vector2(640, 260)
var aim_preview: Dictionary = {}
var pending_mouse: Array[Dictionary] = []
var city: Node3D
var rider: CharacterBody3D
var camera: Camera3D
var hud: Control
var phase: String = "menu"
var training: bool = false
var distance: float = 0
var best: float = 0
var xp: float = 0
var level: int = 1
var pending_upgrades: int = 0
var upgrades_taken: int = 0
var choices: Array[String] = []
var message: String = ""
var notice_left: float = 0
var death_reason: String = ""
var countdown: float = 0
var countdown_started: bool = false
var pending_jump: bool = false
var camera_pan := Vector2.ZERO
var camera_goal := Vector3.ZERO
var camera_look := Vector3.ZERO
var audio: AudioStreamPlayer
var demo_time: float = 0
var demo_hooks: int = 0
var capture_done: bool = false
var demo: bool = false
var rng := RandomNumberGenerator.new()
var save_enabled: bool = true

func _ready() -> void:
 rng.randomize()
 save_enabled = not "--test" in OS.get_cmdline_user_args()
 if save_enabled:
  preferences.load_file()
  var save := ConfigFile.new()
  if save.load("user://records.cfg") == OK:
   best = float(save.get_value("records", "distance", 0))
 for arg in OS.get_cmdline_user_args():
  if arg == "--english":
   preferences.language = "en"
 locale.language = preferences.language
 setup_environment()
 create_world(false)
 var layer := CanvasLayer.new()
 add_child(layer)
 hud = Hud.new()
 hud.game = self
 layer.add_child(hud)
 audio = AudioStreamPlayer.new()
 audio.volume_db = -18
 add_child(audio)
 hud.rebuild_buttons()
 demo = "--demo" in OS.get_cmdline_user_args()
 if demo:
  start_run(true)
 if "--settings" in OS.get_cmdline_user_args():
  open_settings()

func setup_environment() -> void:
 var world := WorldEnvironment.new()
 var env := Environment.new()
 env.background_mode = Environment.BG_COLOR
 env.background_color = Color("101f35")
 env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
 env.ambient_light_color = Color("b0d0eb")
 env.ambient_light_energy = 0.7
 env.fog_enabled = true
 env.fog_light_color = Color("233d58")
 env.fog_density = 0.003
 env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
 world.environment = env
 add_child(world)
 var sun := DirectionalLight3D.new()
 sun.rotation_degrees = Vector3(-42, -30, 0)
 sun.light_color = Color("ffdab0")
 sun.light_energy = 1.4
 sun.shadow_enabled = true
 add_child(sun)
 camera = Camera3D.new()
 add_child(camera)
 camera.current = true
 camera.fov = 75
 camera.far = 440
 camera.position = Vector3(0, 10, 15)

func create_world(practice: bool) -> void:
 if is_instance_valid(rider):
  rider.free()
 if is_instance_valid(city):
  city.free()
 city = City.new()
 city.locale = locale
 city.practice = practice
 add_child(city)
 city.update_chunks(0)
 rider = Rider.new()
 rider.city = city
 add_child(rider)
 rider.notice.connect(show_notice)
 rider.crashed.connect(end_run)
 rider.slid.connect(func(): tone(740, 0.12))
 rider.reset(practice)

func start_run(practice: bool) -> void:
 pending_mouse.clear()
 pending_jump = false
 aim_preview.clear()
 training = practice
 create_world(practice)
 distance = 0
 xp = 0
 level = 1
 pending_upgrades = 0
 upgrades_taken = 0
 death_reason = ""
 phase = "playing"
 camera_pan = Vector2.ZERO
 aim_screen = Vector2(640, 360)
 camera_goal = rider.position + Rules.CAMERA_OFFSET
 camera_look = rider.position + Vector3(0, 0.8, -9)
 camera.position = camera_goal
 camera.look_at(camera_look)
 hud.rebuild_buttons()
 show_notice("HOOK WALLS OR AERIAL OBSTACLES — release at player height 5m or below")

func _input(event: InputEvent) -> void:
 if event is InputEventKey and event.pressed and not event.echo:
  if event.keycode == KEY_ESCAPE:
   if phase in ["playing", "countdown"]:
    phase = "paused"
    pending_mouse.clear()
    pending_jump = false
    hud.rebuild_buttons()
   elif phase == "paused":
    resume()
   elif phase == "settings":
    close_settings()
   return
  if phase == "menu":
   if event.keycode == KEY_ENTER:
    start_run(false)
   elif event.keycode == KEY_P:
    start_run(true)
   return
  if phase == "upgrade" and event.keycode in [KEY_1, KEY_2, KEY_3]:
   choose(event.keycode - KEY_1)
   return
  if event.keycode == KEY_R and phase in ["playing", "dead", "paused"]:
   start_run(training)
   return
  if phase == "playing" and event.keycode == KEY_G and pending_upgrades > 0:
   open_upgrades()
   return
  if phase == "playing" or (phase == "countdown" and countdown_started):
   if event.keycode == KEY_SPACE:
    if phase == "playing":
     rider.jump()
    else:
     pending_jump = true
 if event is InputEventMouseMotion:
  aim_screen = event.position
 if event is InputEventMouseButton and (phase == "playing" or (phase == "countdown" and countdown_started)):
  var side: int = -1 if event.button_index == MOUSE_BUTTON_LEFT else (1 if event.button_index == MOUSE_BUTTON_RIGHT else 0)
  if side != 0:
   aim_screen = event.position
   pending_mouse.append({"side": side, "pressed": event.pressed, "origin": camera.project_ray_origin(event.position), "direction": camera.project_ray_normal(event.position)})

func _notification(what: int) -> void:
 if what == NOTIFICATION_APPLICATION_FOCUS_OUT and phase in ["playing", "countdown"] and not demo:
  phase = "paused"
  pending_mouse.clear()
  pending_jump = false
  if is_instance_valid(hud):
   hud.rebuild_buttons()

func _physics_process(delta: float) -> void:
 if phase == "countdown":
  if not countdown_started:
   if gameplay_released():
    countdown_started = true
    countdown = 3 * Rules.COUNTDOWN_BEAT
    tone(440, 0.08)
  else:
   var previous_number: int = countdown_number()
   countdown = maxf(0, countdown - delta)
   if countdown <= 0:
    phase = "playing"
    tone(880, 0.12)
   elif countdown_number() != previous_number:
    tone(440, 0.08)
 if phase != "playing":
  update_camera_goal(delta)
  return
 process_mouse_commands()
 var steer: float = float(Input.is_physical_key_pressed(KEY_D)) - float(Input.is_physical_key_pressed(KEY_A))
 if demo:
  demo_time += delta
  demo_manual()
 rider.simulate(delta, steer)
 var previous: float = distance
 distance = Rules.progress(distance, rider.position.z, city.origin_offset)
 xp += distance - previous
 var collected: int = city.collect(rider.position)
 xp += collected
 if collected > 0:
  tone(960, 0.055)
 city.update_chunks(distance, rider.anchor)
 if rider.position.z < -2048:
  city.rebase(2048)
  rider.position.z += 2048
  camera.position.z += 2048
 update_camera_goal(delta)
 update_targets()
 if not training:
  while xp >= Rules.xp_required(level):
   xp -= Rules.xp_required(level)
   level += 1
   pending_upgrades += 1
 notice_left = maxf(0, notice_left - delta)

func _process(delta: float) -> void:
 if not is_instance_valid(rider):
  return
 camera.position = camera.position.lerp(camera_goal, 1.0 - exp(-7.0 * delta))
 var desired_basis: Basis = Transform3D.IDENTITY.looking_at(camera_look - camera.position, Vector3.UP).basis
 camera.basis = camera.basis.slerp(desired_basis, 1.0 - exp(-8.0 * delta))
 camera.fov = lerpf(camera.fov, 75.0 + clampf(rider.velocity.length() - 12, 0, 18) * 0.35, minf(1, delta * 2))
 rider.draw_wire()
 hud.queue_redraw()
 if "--capture" in OS.get_cmdline_user_args() and not capture_done:
  if (demo and demo_time >= 1.8) or (not demo and Time.get_ticks_msec() > 2200):
   capture_done = true
   capture.call_deferred()

func countdown_number() -> int:
 return clampi(ceili(countdown / Rules.COUNTDOWN_BEAT - 0.00001), 1, 3)

func update_camera_goal(delta: float) -> void:
 var cursor: Vector2 = (aim_screen - Vector2(640, 360)) / Vector2(640, 360)
 cursor = cursor.clamp(Vector2(-1, -1), Vector2(1, 1))
 for axis in range(2):
  cursor[axis] = signf(cursor[axis]) * maxf(0, (absf(cursor[axis]) - 0.12) / 0.88)
 var target_pan := Vector2(-cursor.x * deg_to_rad(30), -cursor.y * deg_to_rad(50 if cursor.y < 0 else 18))
 if phase not in ["playing", "countdown"]:
  target_pan = Vector2.ZERO
 camera_pan = camera_pan.lerp(target_pan, 1.0 - exp(-Rules.CAMERA_DAMPING * delta))
 var orbit := Basis.from_euler(Vector3(camera_pan.y, camera_pan.x, 0))
 var desired: Vector3 = rider.position + orbit * Rules.CAMERA_OFFSET + Vector3(-rider.position.x * 0.65, 0, 0)
 if phase == "menu" or (phase == "settings" and settings_return == "menu"):
  desired = rider.position + Vector3(3, 9, 15)
 desired.y = maxf(1.2, desired.y)
 var pivot: Vector3 = rider.position + Vector3(0, 0.8, 0)
 var query := PhysicsRayQueryParameters3D.create(pivot, desired, 1)
 query.exclude = [rider.get_rid()]
 var hit: Dictionary = get_world_3d().direct_space_state.intersect_ray(query)
 camera_goal = hit.position + hit.normal * 0.4 if not hit.is_empty() else desired
 camera_look = rider.position + orbit * Vector3(0, 0.8, -9)

func process_mouse_commands() -> void:
 if pending_jump:
  rider.jump()
 for command in pending_mouse:
  if command.pressed:
   var selection: Dictionary = city.manual_target(rider.position, command.origin, command.direction, rider.reach(), rider.get_rid())
   rider.fire_manual(selection, command.side)
  else:
   rider.release_side(command.side)
 pending_mouse.clear()
 pending_jump = false

func update_targets() -> void:
 aim_preview = city.manual_target(rider.position, camera.project_ray_origin(aim_screen), camera.project_ray_normal(aim_screen), rider.reach(), rider.get_rid())

func open_settings() -> void:
 if phase not in ["menu", "paused"]:
  return
 settings_return = phase
 pending_mouse.clear()
 pending_jump = false
 phase = "settings"
 hud.rebuild_buttons()

func close_settings() -> void:
 if phase != "settings":
  return
 phase = settings_return
 pending_mouse.clear()
 pending_jump = false
 hud.rebuild_buttons()

func set_language(language: String) -> void:
 if language not in ["ko", "en"]:
  return
 preferences.language = language
 locale.language = language
 save_preferences()
 hud.rebuild_buttons()





func demo_manual() -> void:
 if not is_instance_valid(rider.anchor) and rider.position.y > 2:
  var side: int = -1 if demo_hooks % 2 == 0 else 1
  var point := Vector3(side * 7.4, 18 + Rules.BUILDING_BONUS[rider.tiers.high] * 0.5, rider.position.z - 10)
  aim_screen = camera.unproject_position(point)
  var selection: Dictionary = city.manual_target(rider.position, camera.position, (point - camera.position).normalized(), rider.reach(), rider.get_rid())
  if rider.fire_manual(selection, side):
   demo_hooks += 1
 if rider.mode == "ground":
  rider.jump()
 if rider.mode == "swing" and is_instance_valid(rider.anchor) and rider.position.z < rider.anchor.global_position.z - 1:
  rider.release_wire()

func save_preferences() -> void:
 settings_error = save_enabled and preferences.save_file() != OK

func capture() -> void:
 await RenderingServer.frame_post_draw
 var target: String = "user://preview.png"
 for arg in OS.get_cmdline_user_args():
  if arg.begins_with("--capture-path="):
   target = arg.trim_prefix("--capture-path=")
 var result: Error = get_viewport().get_texture().get_image().save_png(target)
 print("CAPTURE_RESULT ", result, " ", target)
 get_tree().quit()

func gameplay_released() -> bool:
 return not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) and not Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT) and not Input.is_physical_key_pressed(KEY_SPACE) and not Input.is_physical_key_pressed(KEY_A) and not Input.is_physical_key_pressed(KEY_D)

func resume() -> void:
 pending_mouse.clear()
 pending_jump = false
 rider.release_wire()
 phase = "countdown"
 countdown = 3 * Rules.COUNTDOWN_BEAT
 countdown_started = false
 hud.rebuild_buttons()

func return_menu() -> void:
 pending_mouse.clear()
 pending_jump = false
 phase = "menu"
 create_world(false)
 hud.rebuild_buttons()

func open_upgrades() -> void:
 if pending_upgrades <= 0:
  return
 choices.clear()
 var pool: Array[String] = []
 for key in Rules.UPGRADES:
  if key == "armor":
   if rider.armor_charges == 0:
    pool.append(key)
   continue
  if rider.tiers[key] < 3:
   pool.append(key)
 if upgrades_taken == 0 and "skates" in pool:
  choices.append("skates")
  pool.erase("skates")
 while choices.size() < 3 and not pool.is_empty():
  var i: int = rng.randi_range(0, pool.size() - 1)
  choices.append(pool[i])
  pool.remove_at(i)
 if choices.is_empty():
  # All abilities maxed: consume the pending upgrade without an empty modal.
  pending_upgrades -= 1
  upgrades_taken += 1
  open_upgrades()
  return
 phase = "upgrade"
 pending_mouse.clear()
 pending_jump = false
 hud.rebuild_buttons()
 tone(620, 0.13)

func choose(index: int) -> void:
 if phase != "upgrade" or index < 0 or index >= choices.size():
  return
 rider.upgrade(choices[index])
 pending_upgrades = maxi(0, pending_upgrades - 1)
 upgrades_taken += 1
 if pending_upgrades > 0:
  open_upgrades()
 else:
  resume()

func end_run(reason: String) -> void:
 phase = "dead"
 pending_mouse.clear()
 pending_jump = false
 death_reason = reason
 if not training and distance > best:
  best = distance
  if save_enabled:
   var save := ConfigFile.new()
   save.set_value("records", "distance", best)
   save.save("user://records.cfg")
 hud.rebuild_buttons()
 tone(130, 0.2)

func show_notice(text: String) -> void:
 message = text
 notice_left = 3.0

func tone(frequency: float, duration: float) -> void:
 if not is_instance_valid(audio) or DisplayServer.get_name() == "headless":
  return
 var stream := AudioStreamWAV.new()
 stream.format = AudioStreamWAV.FORMAT_16_BITS
 stream.mix_rate = 22050
 var count: int = int(22050 * duration)
 var data := PackedByteArray()
 data.resize(count * 2)
 for i in range(count):
  var envelope: float = sin(PI * float(i) / count)
  var value: int = int(sin(TAU * frequency * float(i) / 22050) * 13000 * envelope)
  data.encode_s16(i * 2, value)
 stream.data = data
 audio.stream = stream
 audio.play()
