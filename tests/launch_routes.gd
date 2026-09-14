extends SceneTree
var game: Node3D
var checks: int = 0
var failures: int = 0
func _initialize() -> void:
 create_timer(30).timeout.connect(func(): quit(1))
 run.call_deferred()
func check(ok: bool, description: String) -> void:
 checks += 1
 if ok:
  print("PASS ", description)
 else:
  failures += 1
  push_error("FAIL " + description)
func fixture(route: String = "standard") -> void:
 game.preferences.route = route
 game.start_run(true)
 game.rider.practice = false
 await physics_frame
func frames(count: int) -> void:
 for i in range(count):
  await physics_frame
  game.rider.simulate(1.0 / 60, 0)
func run() -> void:
 game = load("res://scenes/main.tscn").instantiate()
 root.add_child(game)
 game.set_process(false)
 game.set_physics_process(false)
 await fixture()
 game.update_targets()
 check(game.launch_available, "HUD marks E ready when both walls are available")
 check(game.rider.launch(), "E launch is available at run start when both walls are visible")
 var twins: Array = game.rider.twin_anchors.duplicate()
 var midpoint: Vector3 = (twins[0].global_position + twins[1].global_position) * 0.5
 check(game.rider.velocity.normalized().is_equal_approx((midpoint - game.rider.position).normalized()), "launch follows player-to-pair midpoint vector")
 check(game.rider.invincible == 0, "launch grants no invulnerability")
 check(not game.rider.launch(), "E cannot restart an active dash")
 await frames(45)
 check(game.rider.mode == "air" and game.rider.twin_anchors.is_empty(), "dash ends in ordinary momentum flight")
 check(game.rider.last_release_height > 5 and not game.rider.landing_safe(), "dash ending records player release height")
 check(game.rider.launch_cooldown > 9 and not game.rider.launch(), "ten-second cooldown is enforced")
 await process_frame
 check(not is_instance_valid(twins[0]) and not is_instance_valid(twins[1]), "both temporary dash anchors are freed")
 await fixture()
 game.rider.upgrade("launcher")
 game.rider.launch()
 check(is_equal_approx(game.rider.velocity.length(), 30), "launch perk increases speed without protection")
 game.resume()
 check(game.rider.launch_left == 0 and game.rider.twin_anchors.is_empty(), "pause resume detaches both launch anchors")
 await fixture()
 game.rider.launch()
 # Add an obstacle after acquisition so the launch must collide during its sweep.
 game.city.box(game.city.chunks[0], Vector3(0, 8, -5), Vector3(5, 8, 0.3), Color.RED, true)
 await physics_frame
 await frames(20)
 check(game.rider.mode == "dead" and game.death_reason == "OBSTACLE COLLISION", "unprotected dash dies on a thin obstacle instead of tunneling")
 await fixture()
 game.rider.upgrade("armor")
 game.rider.launch()
 game.city.box(game.city.chunks[0], Vector3(0, 8, -5), Vector3(5, 8, 0.3), Color.RED, true)
 await physics_frame
 await frames(20)
 check(game.rider.armor_charges == 0 and game.rider.launch_left == 0 and game.rider.mode != "dead", "existing armor absorbs dash collision and cancels the dash")
 await fixture()
 var event := InputEventKey.new()
 event.keycode = KEY_E
 event.pressed = true
 root.push_input(event, true)
 check(game.pending_launch and game.rider.launch_left == 0, "E queues physics work through real input")
 game.process_mouse_commands()
 check(game.rider.launch_left > 0 and not game.pending_launch, "queued E activates once in physics")
 game.resume()
 game.phase = "playing"
 root.push_input(event, true)
 game.phase = "paused"
 game.open_settings()
 check(not game.pending_launch, "settings clear a pending E press")
 await fixture("sparse")
 var missing: Array = game.city.chunks[3].get_children().filter(func(n: Node): return n.get_meta("building", false) and n.position.x < 0)
 check(missing.is_empty(), "sparse section removes buildings on the intended side")
 var opposite: Array = game.city.chunks[3].get_children().filter(func(n: Node): return n.get_meta("building", false) and n.position.x > 0)
 check(opposite.size() == 4, "sparse section retains the opposite wall")
 game.rider.position = Vector3(0, 12, -205)
 await physics_frame
 game.update_targets()
 check(not game.launch_available, "HUD distinguishes missing wall pair from cooldown readiness")
 check(not game.rider.launch() and game.rider.launch_cooldown == 0, "one-sided section cannot trigger E or consume cooldown")
 game.rider.position = Vector3(0, 12, -260)
 await physics_frame
 check(game.rider.launch(), "transition overlap permits two-wall E launch")
 game.city.update_chunks(700, game.rider.anchor, game.rider.twin_anchors)
 check(game.rider.twin_anchors.all(func(n: Node3D): return is_instance_valid(n) and is_instance_valid(n.get_parent())), "streaming retains both launch surfaces")
 var relative: Vector3 = game.rider.twin_anchors[0].global_position - game.rider.position
 game.city.rebase(2048)
 game.rider.position.z += 2048
 check((game.rider.twin_anchors[0].global_position - game.rider.position).is_equal_approx(relative), "launch anchors follow floating-origin shifts")
 await fixture("barriers")
 var gates: Array = game.city.chunks[2].get_children().filter(func(n: Node): return n.get_meta("side_barrier", false))
 check(gates.size() == 1 and not gates[0].get_meta("hookable", false), "vertical gate is a non-hookable physical barrier")
 var gate: Node3D = gates[0]
 game.rider.upgrade("high")
 check(gate.get_meta("height") == 50 and gate.get_child(1).shape.size.y == 50, "vertical gate height and collision follow building upgrade")
 game.city.create_chunk(8)
 var future: Array = game.city.chunks[8].get_children().filter(func(n: Node): return n.get_meta("side_barrier", false))
 check(future[0].get_meta("height") == 50, "future vertical gates inherit building height")
 game.phase = "paused"
 game.open_settings()
 game.hud.buttons[3].pressed.emit()
 check(game.city.route == "barriers" and game.preferences.route == "sparse", "route selection applies next run without replacing the paused city")
 game.start_run(true)
 check(game.city.route == "sparse", "next run uses selected route")
 var path: String = "user://route-test-%d.cfg" % OS.get_process_id()
 game.preferences.save_file(path)
 var restored = game.Preferences.new()
 restored.load_file(path)
 check(restored.route == "sparse", "route selection survives settings reload")
 var bad := ConfigFile.new()
 bad.set_value("experiment", "route", "unknown")
 bad.save(path)
 restored.load_file(path)
 check(restored.route == "standard", "invalid saved route falls back to standard")
 DirAccess.remove_absolute(path)
 print("LAUNCH_ROUTES_RESULT ", checks - failures, "/", checks, " passed; failures=", failures)
 game.free()
 await process_frame
 quit(0 if failures == 0 else 1)
