extends SceneTree
const Preferences = preload("res://scripts/preferences.gd")
var game: Node3D
var checks: int = 0
var failures: int = 0

func _initialize() -> void:
 create_timer(25).timeout.connect(func():
  push_error("Dual-wire tests timed out")
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

func fixture(aim: String = "auto") -> void:
 game.set_wire_mode("dual")
 game.set_aim_mode(aim)
 game.start_run(true)
 game.rider.practice = false
 game.set_physics_process(false)
 game.set_process(false)
 await physics_frame

func frames(count: int) -> void:
 for i in range(count):
  await physics_frame
  game.rider.simulate(1.0 / 60.0, 0)

func mouse(button: int, pressed: bool, point: Vector3 = Vector3(0, 10, -10)) -> void:
 var event := InputEventMouseButton.new()
 event.button_index = button
 event.pressed = pressed
 event.position = game.camera.unproject_position(point)
 root.push_input(event, true)
 game.process_mouse_commands()

func run() -> void:
 var path: String = "user://dual-test-%d.cfg" % OS.get_process_id()
 var preferences = Preferences.new()
 preferences.wire_mode = "dual"
 preferences.save_file(path)
 var loaded = Preferences.new()
 loaded.load_file(path)
 check(loaded.wire_mode == "dual", "wire mode survives save and reload")
 var legacy := ConfigFile.new()
 legacy.set_value("controls", "aim_mode", "manual")
 legacy.save(path)
 loaded.load_file(path)
 check(loaded.wire_mode == "single" and loaded.aim_mode == "manual", "old settings default to one wire and preserve aim mode")
 legacy.set_value("controls", "wire_mode", "invalid")
 legacy.save(path)
 loaded.load_file(path)
 check(loaded.wire_mode == "single", "invalid wire mode falls back to one wire")
 DirAccess.remove_absolute(path)

 game = load("res://scenes/main.tscn").instantiate()
 root.add_child(game)
 game.set_physics_process(false)
 game.set_process(false)
 game.open_settings()
 game.hud.buttons[5].pressed.emit()
 check(game.preferences.wire_mode == "dual" and game.rider.dual_mode, "settings button selects two independent wires")
 game.set_wire_mode("invalid")
 check(game.preferences.wire_mode == "dual", "invalid runtime setting is ignored")
 game.close_settings()

 await fixture()
 mouse(MOUSE_BUTTON_LEFT, true)
 var left: Node3D = game.rider.dual_wires[-1].anchor
 mouse(MOUSE_BUTTON_RIGHT, true)
 check(game.rider.dual_wires.size() == 2 and game.rider.dual_wires[-1].anchor == left, "right click keeps the existing left wire")
 check(game.rider.dual_wires[1].anchor != left, "auto aim attaches to distinct left and right anchors")
 check(not game.rider.dual_wires[-1].connected and not game.rider.dual_wires[1].connected, "each hook has its own flight time")
 await frames(25)
 check(game.rider.mode == "swing" and game.rider.dual_wires.values().all(func(w: Dictionary): return w.connected), "both traveling hooks connect through simulation")
 var lengths := Vector2(game.rider.dual_wires[-1].length, game.rider.dual_wires[1].length)
 await frames(10)
 check(game.rider.dual_wires[-1].length < lengths.x and game.rider.dual_wires[1].length < lengths.y, "holding both buttons reels both wires")
 await frames(500)
 check(game.rider.mode == "swing" and game.rider.position.is_finite() and game.rider.velocity.length() <= 35.01, "prolonged dual reeling stays finite and bounded")
 var a: Dictionary = game.rider.dual_wires[-1]
 var b: Dictionary = game.rider.dual_wires[1]
 check(a.length + b.length >= a.anchor.global_position.distance_to(b.anchor.global_position), "reeling never shortens two ropes below their anchor separation")
 check(game.rider.position.distance_to(a.anchor.global_position) <= a.length + 0.1 and game.rider.position.distance_to(b.anchor.global_position) <= b.length + 0.1, "both rope constraints hold together")
 var right: Node3D = b.anchor
 var momentum: Vector3 = game.rider.velocity
 mouse(MOUSE_BUTTON_LEFT, false)
 check(game.rider.dual_wires.size() == 1 and game.rider.dual_wires[1].anchor == right and game.rider.velocity == momentum, "left release preserves the right wire and instantaneous momentum")
 await frames(5)
 check(game.rider.mode == "swing", "remaining right wire continues swinging")
 momentum = game.rider.velocity
 mouse(MOUSE_BUTTON_RIGHT, false)
 check(game.rider.dual_wires.is_empty() and game.rider.mode == "air" and game.rider.velocity == momentum, "last release enters free flight with momentum")

 await fixture()
 mouse(MOUSE_BUTTON_LEFT, true)
 mouse(MOUSE_BUTTON_RIGHT, true)
 await frames(20)
 left = game.rider.dual_wires[-1].anchor
 var blocker: Node3D = game.city.box(game.city, left.global_position.lerp(game.rider.position, 0.15), Vector3(1.6, 2, 2), Color.RED, true)
 await frames(15)
 check(not game.rider.dual_wires.has(-1) and game.rider.dual_wires.has(1), "occlusion drops only the blocked wire")
 blocker.free()

 await fixture()
 mouse(MOUSE_BUTTON_RIGHT, true)
 mouse(MOUSE_BUTTON_LEFT, true)
 mouse(MOUSE_BUTTON_LEFT, false)
 check(game.rider.dual_wires.size() == 1 and game.rider.dual_wires.has(1), "same-frame left press and release cannot drop the right wire")

 await fixture("manual")
 var first := Vector3(-7.4, 11, -12)
 var second := Vector3(7.4, 14, -10)
 mouse(MOUSE_BUTTON_LEFT, true, first)
 left = game.rider.dual_wires[-1].anchor
 mouse(MOUSE_BUTTON_RIGHT, true, second)
 right = game.rider.dual_wires[1].anchor
 check(left.get_meta("manual", false) and right.get_meta("manual", false) and absf(left.global_position.y - right.global_position.y) > 1, "manual mode keeps two independently aimed wall heights")
 var start_left: Vector3 = left.global_position
 game.aim_screen = Vector2(10, 10)
 check(left.global_position == start_left, "cursor movement does not move a held wire")
 await frames(25)
 check(game.rider.mode == "swing" and game.rider.dual_wires.size() == 2, "manual two-wire attachment drives real swinging")
 check(not game.rider.fire_manual({"valid": false}, -1) and game.rider.dual_wires[-1].anchor == left and game.rider.dual_wires[1].anchor == right, "invalid manual shot preserves both wires")
 mouse(MOUSE_BUTTON_LEFT, true, Vector3(-7.4, 16, -10))
 check(game.rider.dual_wires[-1].anchor != left and game.rider.dual_wires[1].anchor == right, "re-firing left replaces only its manual attachment")
 await process_frame
 check(not is_instance_valid(left), "replaced manual point is freed")
 var new_left: Node3D = game.rider.dual_wires[-1].anchor
 mouse(MOUSE_BUTTON_RIGHT, false, second)
 await process_frame
 check(not is_instance_valid(right) and game.rider.dual_wires[-1].anchor == new_left, "right release cleans only the right manual point")
 game.phase = "paused"
 game.resume()
 await process_frame
 check(game.rider.dual_wires.is_empty() and not is_instance_valid(new_left) and game.phase == "countdown", "resume releases both wires and cleans manual points")

 await fixture()
 mouse(MOUSE_BUTTON_LEFT, true)
 mouse(MOUSE_BUTTON_RIGHT, true)
 var anchors_before: Array[Node3D] = game.rider.attached_anchors()
 var relative: Array[Vector3] = []
 for target in anchors_before:
  relative.append(target.global_position - game.rider.position)
 game.city.rebase(2048)
 game.rider.position.z += 2048
 check((anchors_before[0].global_position - game.rider.position).is_equal_approx(relative[0]) and (anchors_before[1].global_position - game.rider.position).is_equal_approx(relative[1]), "floating origin preserves both wire endpoints")

 await fixture()
 left = game.city.anchors.filter(func(n: Node3D): return n.get_parent() == game.city.chunks[0])[0]
 right = game.city.anchors.filter(func(n: Node3D): return n.get_parent() == game.city.chunks[1])[0]
 game.rider.attach(left, -1)
 game.rider.attach(right, 1)
 game.city.update_chunks(640, null, game.rider.attached_anchors())
 check(is_instance_valid(left) and is_instance_valid(right), "streaming protects both attached chunks")
 game.rider.release_side(-1)
 game.city.update_chunks(640, null, game.rider.attached_anchors())
 check(not is_instance_valid(left) and is_instance_valid(right), "streaming reclaims only the released wire's old chunk")
 game.rider.release_wire()
 game.city.update_chunks(640, null, game.rider.attached_anchors())
 check(not is_instance_valid(right) and game.city.chunks.size() <= 8, "last release allows the remaining old chunk to be reclaimed")

 await fixture()
 mouse(MOUSE_BUTTON_LEFT, true)
 mouse(MOUSE_BUTTON_RIGHT, true)
 check(game.rider.launch() and game.rider.dual_wires.is_empty(), "E dash remains separate and releases both swing wires")
 await fixture()
 mouse(MOUSE_BUTTON_LEFT, true)
 mouse(MOUSE_BUTTON_RIGHT, true)
 game.rider.land(Vector3(0, -20, -14))
 check(game.rider.mode == "slide" and game.rider.dual_wires.is_empty(), "safe skating landing releases both wires")
 await fixture()
 mouse(MOUSE_BUTTON_LEFT, true)
 mouse(MOUSE_BUTTON_RIGHT, true)
 game.rider.hurt("test obstacle")
 check(game.rider.mode == "dead" and game.rider.dual_wires.is_empty(), "fatal obstacle collision clears both wires")
 await fixture()
 mouse(MOUSE_BUTTON_LEFT, true)
 mouse(MOUSE_BUTTON_RIGHT, true)
 game.set_wire_mode("single")
 check(not game.rider.dual_mode and game.rider.dual_wires.is_empty(), "switching back to one wire clears two-wire state")
 check(game.rider.fire(-1) and game.rider.fire(1) and game.rider.wire_side == 1, "one-wire mode still replaces the previous side")

 print("DUAL_WIRES_RESULT ", checks - failures, "/", checks, " passed; failures=", failures)
 game.free()
 await process_frame
 quit(0 if failures == 0 else 1)
