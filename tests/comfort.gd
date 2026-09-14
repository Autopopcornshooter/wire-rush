extends SceneTree
var game: Node3D
var checks: int = 0
var failures: int = 0
func _initialize() -> void:
 create_timer(40).timeout.connect(func(): quit(1))
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
 await physics_frame
func frames(count: int) -> void:
 for i in range(count):
  await physics_frame
  game.rider.simulate(1.0 / 60, 0)
func camera_frames(cursor: Vector2, count: int, delta: float = 1.0 / 60) -> void:
 game.aim_screen = cursor
 for i in range(count):
  await physics_frame
  game.update_camera_goal(delta)
  game._process(delta)
func key(pressed: bool) -> void:
 var event := InputEventKey.new()
 event.keycode = KEY_A
 event.physical_keycode = KEY_A
 event.pressed = pressed
 Input.parse_input_event(event)
 Input.flush_buffered_events()
func mouse(pressed: bool, at: Vector2) -> void:
 var event := InputEventMouseButton.new()
 event.button_index = MOUSE_BUTTON_LEFT
 event.pressed = pressed
 event.position = at
 root.push_input(event, true)
func run() -> void:
 game = load("res://scenes/main.tscn").instantiate()
 root.add_child(game)
 game.set_process(false)
 game.set_physics_process(false)
 await fixture()
 check(game.rider.position.y == 27 and game.rider.position.y == game.city.start_height(), "run starts at the opening rooftop height plus clearance")
 check(game.rider.velocity.y < 0 and game.rider.mode == "air", "rooftop start is already falling forward")
 var start_y: float = game.rider.position.y
 await frames(30)
 check(game.rider.position.y < start_y and game.rider.position.y > 20, "first half-second leaves room for an initial hook")
 var wall := Vector3(-7.4, 26, game.rider.position.z - 8)
 var shot: Dictionary = game.city.manual_target(game.rider.position, game.rider.position, (wall - game.rider.position).normalized(), game.rider.reach(), game.rider.get_rid())
 check(shot.valid and game.rider.fire_manual(shot, -1), "rooftop drop can acquire an opening wall")
 await frames(20)
 check(game.rider.hook_connected, "first rooftop hook completes into a swing")
 game.rider.upgrade("armor")
 var position_before: Vector3 = game.rider.position
 var velocity_before: Vector3 = game.rider.velocity
 var attached: Node3D = game.rider.anchor
 game.rider.hurt("OBSTACLE COLLISION")
 check(game.rider.position == position_before and game.rider.velocity == velocity_before, "armor absorbs a hit without changing position or velocity")
 check(game.rider.anchor == attached and game.rider.hook_connected, "armor keeps the active wire connected")
 check(game.rider.armor_charges == 0 and game.rider.invincible == 2, "one armor charge grants exactly two seconds of protection")
 game.rider.hurt("OBSTACLE COLLISION")
 check(game.rider.armor_charges == 0 and game.rider.invincible == 2, "protected repeat contact does not consume another charge")
 await fixture()
 game.rider.position = Vector3(0, 12, 0)
 game.rider.velocity = Vector3(0, 0, -28)
 game.rider.upgrade("armor")
 var block: Node3D = game.city.obstacle(game.city.chunks[0], Vector3(0, 12, -4), Vector3(4, 8, 0.5))
 game.city.obstacle(game.city.chunks[0], Vector3(0, 12, -7), Vector3(4, 8, 0.5))
 await physics_frame
 var blink_states: Dictionary = {}
 for i in range(40):
  await frames(1)
  if game.rider.invincible > 0:
   blink_states[game.rider.visuals.visible] = true
 check(game.rider.position.z < -18 and is_equal_approx(game.rider.velocity.z, -28), "armor preserves forward progress through two obstacle collision sweeps")
 check(game.rider.armor_charges == 0 and game.rider.invincible > 1.3, "collision cluster consumes only one armor charge")
 check(blink_states.has(true) and blink_states.has(false), "character visibly blinks during protection")
 await frames(100)
 check(game.rider.invincible == 0 and game.rider.visuals.visible and game.rider.ignored_obstacles.is_empty(), "protection ends and restores visibility and obstacle collisions")
 game.rider.position = Vector3(0, 12, 0)
 game.rider.velocity = Vector3(0, 0, -28)
 game.rider.mode = "air"
 await frames(12)
 check(game.rider.mode == "dead", "same obstacle is lethal again after armor protection expires")
 check(is_instance_valid(block), "armor does not delete obstacle geometry")
 await fixture()
 game.rider.upgrade("armor")
 var armor_offered: bool = false
 game.pending_upgrades = 1
 for seed_value in range(40):
  game.phase = "playing"
  game.rng.seed = seed_value
  game.open_upgrades()
  armor_offered = armor_offered or game.choices.has("armor")
 check(not armor_offered, "held armor never appears across upgrade offers")
 for perk in game.rider.tiers:
  game.rider.tiers[perk] = 3
 game.phase = "playing"
 game.pending_upgrades = 1
 game.open_upgrades()
 check(game.choices.is_empty() and game.phase == "playing" and game.pending_upgrades == 0, "fully upgraded held armor does not force an empty choice screen")
 game.rider.armor_charges = 0
 game.pending_upgrades = 1
 game.open_upgrades()
 check(game.choices == ["armor"], "empty armor can be replenished even at its maximum tier")
 game.choose(0)
 check(game.rider.armor_charges == 1, "armor refill provides a replacement charge")
 await fixture()
 key(true)
 game.resume()
 var frozen: Vector3 = game.rider.position
 game._physics_process(0.5)
 check(not game.countdown_started and game.rider.position == frozen, "countdown waits for steering keys as well as mouse and action keys")
 key(false)
 game._physics_process(0.016)
 check(game.countdown_started and game.countdown_number() == 3, "releasing controls starts at three")
 game._physics_process(0.7)
 check(game.countdown_number() == 2 and game.rider.position == frozen, "second countdown beat displays two with physics frozen")
 game._physics_process(0.7)
 check(game.countdown_number() == 1 and game.rider.position == frozen, "third countdown beat displays one with physics frozen")
 var pixel: Vector2 = game.camera.unproject_position(Vector3(-7.4, 26, -8))
 mouse(true, pixel)
 check(game.pending_mouse.size() == 1 and game.rider.anchor == null, "wire input can be buffered during the countdown")
 for i in range(43):
  await physics_frame
  game._physics_process(1.0 / 60)
 check(game.phase == "playing" and is_instance_valid(game.rider.anchor), "countdown finishes on schedule and fires the buffered wire")
 check(game.rider.invincible == 0, "resuming from pause grants no invincibility")
 mouse(false, pixel)
 game.process_mouse_commands()
 await fixture()
 game.resume()
 game._physics_process(0.016)
 mouse(true, game.camera.unproject_position(Vector3(-7.4, 26, -8)))
 mouse(false, game.camera.unproject_position(Vector3(-7.4, 26, -8)))
 game.countdown = 0.001
 game._physics_process(1.0 / 60)
 check(game.rider.anchor == null, "press and release within countdown does not leave a stuck wire")
 await fixture()
 await camera_frames(Vector2(640, 0), 1)
 check(game.camera_pan.y > 0 and game.camera_pan.y < deg_to_rad(10), "mouse camera begins moving with damping rather than snapping")
 await camera_frames(Vector2(640, 0), 90)
 check((-game.camera.basis.z).y > 0.4, "top-edge mouse aim raises the view toward high buildings")
 await camera_frames(Vector2(1280, 360), 90)
 check((-game.camera.basis.z).x > 0.3, "right-edge mouse aim turns the view right")
 await camera_frames(Vector2(0, 360), 90)
 check((-game.camera.basis.z).x < -0.3, "left-edge mouse aim turns the view left")
 await camera_frames(Vector2(640, 360), 90)
 check(game.camera_pan.length() < 0.005, "centered cursor returns to the neutral view")
 await camera_frames(Vector2(660, 355), 30)
 check(game.camera_pan.length() < 0.001, "small central mouse movements stay inside the camera dead zone")
 await fixture()
 game.rider.position = Vector3(0, 24, -8)
 for i in range(3):
  game.rider.upgrade("high")
 await camera_frames(Vector2(640, 0), 90)
 var upper := Vector3(-7.4, 44, -12)
 var upper_pixel: Vector2 = game.camera.unproject_position(upper)
 check(Rect2(0, 0, 1280, 720).has_point(upper_pixel), "upper building target becomes visible with upward mouse view")
 var target: Dictionary = game.city.manual_target(game.rider.position, game.camera.project_ray_origin(upper_pixel), game.camera.project_ray_normal(upper_pixel), game.rider.reach(), game.rider.get_rid())
 check(target.valid and target.surface_point.y > 40 and game.rider.fire_manual(target, -1), "camera ray can fire a real wire into the raised building wall")
 game.rider.position = Vector3(6, 12, -8)
 await camera_frames(Vector2(0, 360), 90)
 check(not game.city.wire_path_blocked(game.rider.position + Vector3(0, 0.8, 0), game.camera_goal, game.rider.get_rid()), "camera collision probe keeps the orbit outside the wall")
 game.rider.position = Vector3(0, 0.8, 0)
 await camera_frames(Vector2(640, 0), 90)
 check(game.camera_goal.y >= 1.19, "upward orbit stays above the road at ground height")
 print("COMFORT_RESULT ", checks - failures, "/", checks, " passed; failures=", failures)
 game.free()
 await process_frame
 quit(0 if failures == 0 else 1)
