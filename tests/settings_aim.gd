extends SceneTree
const Preferences = preload("res://scripts/preferences.gd")
const Locale = preload("res://scripts/localization.gd")
var game: Node3D
var checks: int = 0
var failures: int = 0

func _initialize() -> void:
 create_timer(20.0).timeout.connect(func():
  push_error("Settings/aim test timed out")
  quit(1)
 )
 run.call_deferred()

func check(condition: bool, description: String) -> void:
 checks += 1
 if condition:
  print("PASS ", description)
 else:
  failures += 1
  push_error("FAIL " + description)

func aim_at(point: Vector3, reach: float = 30) -> Dictionary:
 var pixel: Vector2 = game.camera.unproject_position(point)
 return game.city.manual_target(game.rider.position, game.camera.project_ray_origin(pixel), game.camera.project_ray_normal(pixel), reach, game.rider.get_rid())

func mouse(button: int, pressed: bool, point: Vector3) -> void:
 var event := InputEventMouseButton.new()
 event.button_index = button
 event.pressed = pressed
 event.position = game.camera.unproject_position(point)
 root.push_input(event, true)

func run() -> void:
 var preferences = Preferences.new()
 preferences.language = "en"
 preferences.window_size = Vector2i(1920, 1080)
 preferences.fullscreen = true
 preferences.sfx_volume = 0.4
 preferences.graphics_style = "realistic"

 var temporary: String = "user://settings-test-%d.cfg" % OS.get_process_id()
 check(preferences.save_file(temporary) == OK, "settings save to a separate configuration file")
 var loaded = Preferences.new()
 check(loaded.load_file(temporary) == OK and loaded.language == "en" and loaded.window_size == Vector2i(1920, 1080) and loaded.fullscreen and absf(loaded.sfx_volume - 0.4) < 0.001 and loaded.graphics_style == "realistic", "display and audio preferences survive a fresh settings instance")
 var corrupt := ConfigFile.new()
 corrupt.set_value("interface", "language", "invalid")
 corrupt.set_value("controls", "aim_mode", "invalid")
 corrupt.set_value("display", "window_size", Vector2i(999, 999))
 corrupt.set_value("display", "graphics_style", "invalid")
 corrupt.save(temporary)
 loaded.load_file(temporary)
 check(loaded.language == "ko" and loaded.window_size == Vector2i(1280, 720) and loaded.graphics_style == "lowpoly", "invalid saved options fall back to supported values")
 DirAccess.remove_absolute(temporary)
 var locale = Locale.new()
 check(locale.FONT.has_char("한".unicode_at(0)), "bundled font contains Korean glyphs")
 check(locale.text("SETTINGS") == "설정" and locale.message("PRACTICE RESCUE / OBSTACLE COLLISION").contains("장애물"), "interface and dynamic failure messages translate")
 locale.language = "en"
 check(locale.text("SETTINGS") == "SETTINGS", "English selection restores English text")

 game = load("res://scenes/main.tscn").instantiate()
 root.add_child(game)
 game.set_physics_process(false)
 game.set_process(false)
 await physics_frame
 var settings_button: Button = game.hud.buttons[2]
 settings_button.pressed.emit()
 check(game.phase == "settings", "menu settings button opens settings")
 await process_frame
 game.hud.buttons[1].pressed.emit()
 check(game.preferences.language == "en" and game.hud.buttons[-1].text == "BACK   /   ESC", "language button rebuilds visible controls immediately")
 await process_frame
 game.hud.buttons[0].pressed.emit()
 check(game.hud.buttons[-1].text == "뒤로   /   ESC", "Korean selection updates settings buttons")
 check(game.locale.language == "ko" and game.city.chunks.has(0), "existing city chunks survive a language change without rebuilding physics")

 var preset: Vector2i = Preferences.WINDOW_PRESETS[1]
 game.set_window_size(preset)
 check(game.preferences.window_size == preset and not game.preferences.fullscreen, "a resolution preset updates preferences and clears fullscreen")
 game.set_fullscreen(true)
 check(game.preferences.fullscreen, "fullscreen toggle updates preferences")
 game.set_fullscreen(false)
 check(not game.preferences.fullscreen, "windowed toggle clears fullscreen")
 var sfx_bus: int = AudioServer.get_bus_index("SFX")
 game.set_sfx_volume(0.5)
 check(sfx_bus != -1 and not AudioServer.is_bus_mute(sfx_bus) and absf(AudioServer.get_bus_volume_db(sfx_bus) - linear_to_db(0.5)) < 0.01, "sfx volume slider updates the SFX audio bus")
 game.set_sfx_volume(0.0)
 check(AudioServer.is_bus_mute(sfx_bus), "muting sfx volume mutes the SFX bus")
 game.set_sfx_volume(1.0)

 var escape := InputEventKey.new()
 escape.keycode = KEY_ESCAPE
 escape.pressed = true
 root.push_input(escape, true)
 check(game.phase == "menu", "Escape returns from settings to its parent screen")

 game.start_run(true)
 # Legacy physics fixtures keep their original launch height; rooftop spawn has separate tests.
 game.rider.position = Vector3(0, 6, 0)
 game.rider.velocity = Vector3(0, 0, -12)
 game.camera.position = game.rider.position + game.Rules.CAMERA_OFFSET
 game.camera.look_at(game.rider.position + Vector3(0, 0.8, -9))
 game.phase = "paused"
 game.open_settings()
 game.rider.invincible = 5
 var frozen: Vector3 = game.rider.position
 game.set_physics_process(true)
 for i in range(8):
  await physics_frame
 game.set_physics_process(false)
 check(game.rider.position == frozen and game.rider.invincible == 5, "settings reached from pause freeze movement and cooldown")
 game.close_settings()
 check(game.phase == "paused", "language settings return to the paused run")
 game.resume()
 check(game.phase == "countdown" and game.pending_mouse.is_empty(), "return to play still uses the input-release countdown")
 game.phase = "playing"
 await physics_frame

 var first_point := Vector3(-7.4, 11, -12)
 var second_point := Vector3(7.4, 14, -10)
 var first: Dictionary = aim_at(first_point)
 var second: Dictionary = aim_at(second_point)
 check(first.get("valid", false) and second.get("valid", false), "camera rays resolve two arbitrary building surface points")
 if not first.get("valid", false) or not second.get("valid", false):
  print("Invalid fixture points: ", first, " ", second)
  game.free()
  quit(1)
  return
 mouse(MOUSE_BUTTON_LEFT, true, first_point)
 check(game.rider.anchor == null and game.pending_mouse.size() == 1, "mouse click queues a ray instead of touching physics in input callback")
 game.process_mouse_commands()
 check(is_instance_valid(game.rider.anchor) and game.rider.wire_side == -1, "queued mouse click creates a manual attachment")
 var first_anchor: Node3D = game.rider.anchor
 var fixed_point: Vector3 = first_anchor.global_position
 check(fixed_point.distance_to(first.point) < 0.01, "wire attaches to the clicked wall point rather than a preset anchor")
 var motion := InputEventMouseMotion.new()
 motion.position = game.camera.unproject_position(second_point)
 root.push_input(motion, true)
 game.update_targets()
 check(first_anchor.global_position.is_equal_approx(fixed_point), "moving the cursor while holding does not move the existing attachment")
 var held_length: float = 0
 for i in range(24):
  await physics_frame
  game.rider.simulate(1.0 / 60.0, 0)
  if i == 14:
   held_length = game.rider.rope_length
 check(game.rider.rope_length < held_length and not Input.is_physical_key_pressed(KEY_SHIFT), "manual hook also reels automatically without Shift")
 check(game.rider.mode == "swing" and game.rider.position.z < -3, "manual hook travels and drives actual swinging motion")
 mouse(MOUSE_BUTTON_RIGHT, true, second_point)
 game.process_mouse_commands()
 check(game.rider.wire_side == 1 and game.rider.anchor != first_anchor and game.rider.anchor.global_position.y > 13, "opposite button changes the swing point to a different wall and height")
 mouse(MOUSE_BUTTON_LEFT, false, first_point)
 game.process_mouse_commands()
 check(game.rider.wire_side == 1 and is_instance_valid(game.rider.anchor), "releasing the previous button cannot drop the new wire")
 var second_anchor: Node3D = game.rider.anchor
 var invalid: Dictionary = aim_at(second_point, 2.0)
 check(not invalid.valid and invalid.reason == "NO SURFACE IN RANGE", "range assist cannot invent a surface outside player reach")
 check(not game.rider.fire_manual(invalid, -1) and game.rider.anchor == second_anchor, "an invalid retarget keeps the active wire")
 var ground: Dictionary = aim_at(Vector3(0, 0, -12))
 check(not ground.valid and ground.reason == "AIM AT A SURFACE", "road is not a manual attachment surface")
 var sky: Dictionary = game.city.manual_target(game.rider.position, game.camera.position, Vector3.UP, 30, game.rider.get_rid())
 check(not sky.valid, "empty sky cannot create an anchor")
 var occluder: Node3D = game.city.box(game.city, (game.rider.position + second_anchor.global_position) * 0.5, Vector3(2, 4, 2), Color.RED, true)
 await physics_frame
 var occluded: Dictionary = game.city.validate_manual_point(game.rider.position, second.surface_point, second.normal, second.surface, 30, game.rider.get_rid())
 check(not occluded.valid and occluded.reason == "WIRE PATH BLOCKED", "rider-to-wall occlusion prevents attachment through obstacles")
 occluder.free()
 await physics_frame
 var relative_before: Vector3 = game.rider.anchor.global_position - game.rider.position
 game.city.rebase(2048)
 game.rider.position.z += 2048
 game.camera.position.z += 2048
 check((game.rider.anchor.global_position - game.rider.position).is_equal_approx(relative_before), "manual wall point survives floating-origin shifts")
 game.city.update_chunks(640, game.rider.anchor)
 check(is_instance_valid(second_anchor) and is_instance_valid(second_anchor.get_parent()), "streaming retains a building while its manual point is attached")
 var velocity_before: Vector3 = game.rider.velocity
 game.rider.release_wire()
 check(game.rider.velocity == velocity_before, "manual release preserves momentum")
 await process_frame
 check(not is_instance_valid(first_anchor) and not is_instance_valid(second_anchor), "retarget and release free transient manual anchors")
 game.city.update_chunks(640)
 check(game.city.chunks.size() <= 8, "manual anchors do not leave old chunks permanently resident")

 game.start_run(true)
 # Legacy physics fixtures keep their original launch height; rooftop spawn has separate tests.
 game.rider.position = Vector3(0, 6, 0)
 game.rider.velocity = Vector3(0, 0, -12)
 game.camera.position = game.rider.position + game.Rules.CAMERA_OFFSET
 game.camera.look_at(game.rider.position + Vector3(0, 0.8, -9))
 await physics_frame
 mouse(MOUSE_BUTTON_LEFT, true, first_point)
 mouse(MOUSE_BUTTON_LEFT, false, first_point)
 game.process_mouse_commands()
 check(game.rider.anchor == null, "press and release within one physics frame cannot leave a stuck wire")
 mouse(MOUSE_BUTTON_LEFT, true, first_point)
 game.phase = "paused"
 game.open_settings()
 check(game.pending_mouse.is_empty(), "opening settings clears unconsumed gameplay clicks")
 game.close_settings()
 game.phase = "playing"
 await physics_frame
 check(not game.rider.has_method("fire") and not game.rider.has_method("launch") and not game.city.has_method("find_anchor"), "manual wire stays primary; twin launch and auto anchors remain removed")

 print("SETTINGS_AIM_RESULT ", checks - failures, "/", checks, " passed; failures=", failures)
 game.free()
 await process_frame
 quit(0 if failures == 0 else 1)
