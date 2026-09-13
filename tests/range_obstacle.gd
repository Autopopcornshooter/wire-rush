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

func fixture() -> void:
 game.start_run(true)
 game.rider.practice = false
 game.set_process(false)
 game.set_physics_process(false)
 await physics_frame

func aim(point: Vector3, reach: float = 30) -> Dictionary:
 var pixel: Vector2 = game.camera.unproject_position(point)
 return game.city.manual_target(game.rider.position, game.camera.project_ray_origin(pixel), game.camera.project_ray_normal(pixel), reach, game.rider.get_rid())

func frames(count: int) -> void:
 for i in range(count):
  await physics_frame
  game.rider.simulate(1.0 / 60, 0)

func attach_obstacle() -> Node3D:
 var hazard: Node3D = game.city.obstacle(game.city.chunks[0], Vector3(0, 12, -10), Vector3(2.6, 2.2, 1.4))
 game.rider.position = Vector3(0, 12, 0)
 game.rider.velocity = Vector3.ZERO
 await physics_frame
 var selection: Dictionary = game.city.manual_target(game.rider.position, game.rider.position, Vector3.FORWARD, 30, game.rider.get_rid())
 check(selection.valid and game.rider.fire_manual(selection, -1), "aerial hook fires at a visible face")
 await frames(20)
 check(game.rider.hook_connected, "aerial hook completes flight before orbit")
 return hazard

func run() -> void:
 game = load("res://scenes/main.tscn").instantiate()
 root.add_child(game)
 await fixture()
 var target: Dictionary = aim(Vector3(-7.4, 12, -110))
 check(target.valid and target.get("adjusted", false), "distant camera wall aim resolves a reachable surface")
 if target.valid:
  check(target.distance <= 30 and target.distance > 29.98, "wall aim clamps to actual maximum wire reach")
  check(target.surface.get_meta("building", false) and absf(target.surface_point.x + 7.4) < 0.01, "range assist remains on a real wall on the aimed side")
  check(game.rider.fire_manual(target, -1), "assisted preview passes firing revalidation")
  check(game.rider.anchor.global_position.distance_to(target.point) < 0.01, "fired anchor matches assisted preview")
  await frames(30)
  check(game.rider.hook_connected, "maximum-range shot actually connects")
 await fixture()
 target = aim(Vector3(-7.4, 12, -110), 39)
 check(target.valid and target.distance <= 39 and target.distance > 38.98, "range upgrade expands assisted attachment distance")
 target = aim(Vector3(-7.4, 12, -110), 2)
 check(not target.valid, "no reachable surface produces no floating anchor")
 var sky: Dictionary = game.city.manual_target(game.rider.position, game.camera.position, Vector3.UP, 30, game.rider.get_rid())
 check(not sky.valid, "empty sky still requires a real aimed surface")
 await fixture()
 var near_block: Node3D = game.city.obstacle(game.city.chunks[0], Vector3(1.8, 10, -29), Vector3(2.6, 2.2, 1.4))
 game.city.obstacle(game.city.chunks[1], Vector3(0, 12, -16), Vector3(2.6, 2.2, 1.4))
 await physics_frame
 target = aim(Vector3(0, 12, -79.3))
 check(target.valid and target.get("adjusted", false), "distant airborne obstacle aim also enables range assist")
 if target.valid:
  check(target.surface == near_block and target.distance <= 30, "assist can select a reachable aerial obstacle near the range limit")
  check(game.rider.fire_manual(target, -1), "assisted obstacle target can be fired")
  await frames(30)
  check(game.rider.hook_connected, "assisted obstacle shot completes connection")
 await fixture()
 # Put a solid barrier across the full route. Assistance must not bypass it.
 game.city.box(game.city.chunks[0], Vector3(0, 15, -5), Vector3(14.7, 30, 1), Color.RED, true)
 await physics_frame
 target = game.city.range_limited_target(game.rider.position, Vector3(-7.4, 12, -110), 30, game.rider.get_rid())
 check(not target.valid or target.point.z > -4.5, "range assistance only uses visible surfaces before a blocking barrier")
 await fixture()
 var hazard: Node3D = await attach_obstacle()
 var attached: Node3D = game.rider.anchor
 game.rider.position = Vector3(0, 12, -16)
 game.rider.velocity = Vector3(0, 0, -6)
 game.rider.rope_length = 12
 await physics_frame
 check(game.city.wire_path_blocked(game.rider.position, attached.global_position, game.rider.get_rid()), "regression fixture crosses the attached obstacle body")
 await frames(15)
 check(game.rider.anchor == attached and game.rider.hook_connected and game.rider.blocked_time == 0, "swinging behind the attached obstacle no longer disconnects")
 await frames(45)
 check(game.rider.anchor == attached and game.rider.hook_connected, "aerial swing continues beyond the old disconnect timeout")
 game.rider.upgrade("high")
 await frames(10)
 check(game.rider.anchor == attached and game.rider.hook_connected, "raised attached obstacle stays connected")
 game.rider.position = hazard.global_position + Vector3(0, 0, -6)
 game.rider.velocity = Vector3.ZERO
 game.rider.rope_length = 20
 var blocker: Node3D = game.city.box(game.city.chunks[0], (game.rider.position + attached.global_position) * 0.5, Vector3(4, 5, 0.4), Color.RED, true)
 await physics_frame
 await frames(15)
 check(not is_instance_valid(game.rider.anchor) and game.message.contains("WIRE BLOCKED"), "a different obstacle still disconnects a blocked wire")
 blocker.free()
 await fixture()
 hazard = await attach_obstacle()
 game.rider.position = hazard.global_position + Vector3(0, 0, 3)
 game.rider.velocity = Vector3(0, 0, -35)
 game.rider.rope_length = 20
 game.rider.invincible = 0
 await frames(8)
 check(game.rider.mode == "dead", "attached obstacle still causes dangerous character collisions")
 print("RANGE_OBSTACLE_RESULT ", checks - failures, "/", checks, " passed; failures=", failures)
 game.free()
 await process_frame
 quit(0 if failures == 0 else 1)
