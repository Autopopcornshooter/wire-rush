extends SceneTree
const Rules = preload("res://scripts/rules.gd")
var game: Node3D
var failures: int = 0
var checks: int = 0

func _initialize() -> void:
 run.call_deferred()

func check(condition: bool, description: String) -> void:
 checks += 1
 if condition:
  print("PASS ", description)
 else:
  failures += 1
  push_error("FAIL " + description)

func frames(count: int, steer: float = 0.0) -> void:
 for i in range(count):
  await physics_frame
  game.rider.simulate(1.0 / 60.0, steer)

func fixture(pos: Vector3, speed: Vector3, training: bool = false) -> void:
 game.start_run(training)
 game.set_physics_process(false)
 game.set_process(false)
 game.rider.position = pos
 game.rider.velocity = speed
 await physics_frame

func run() -> void:
 game = load("res://scenes/main.tscn").instantiate()
 root.add_child(game)
 game.set_physics_process(false)
 game.set_process(false)
 await physics_frame
 check(Rules.progress(80, -40, 0) == 80, "backtracking awards no distance")
 check(Rules.progress(80, -90, 0) == 90, "new forward distance advances record")
 check(Rules.floor_outcome(20, 1, true) == "slide", "skates preserve landing speed without release timing")
 check(Rules.floor_outcome(20, 0, true) == "ground", "without skates landing stops")
 check(Rules.floor_outcome(20, 1, false) == "ground", "same landing cannot refresh skating")

 await fixture(Vector3(0, 6, 0), Vector3(0, 0, -12))
 check((game.camera.position - game.rider.position).is_equal_approx(Vector3(0, 4.5, 12)), "camera restores the original distant offset")
 check(game.city.anchors.all(func(a: Node3D): return a.global_position.y >= 16.0), "base anchors are at least 16m high")
 check(game.rider.fire(-1), "left input acquires visible forward anchor")
 await frames(15)
 var held_length: float = game.rider.rope_length
 await frames(10)
 check(game.rider.rope_length < held_length and not Input.is_physical_key_pressed(KEY_SHIFT), "holding an automatic hook reels without Shift")
 check(game.rider.mode == "swing", "hook travels then becomes a swing")
 check(game.rider.position.z < -3, "swing physically moves forward")
 check(game.rider.position.distance_to(game.rider.anchor.global_position) <= game.rider.rope_length + 0.08, "taut rope constrains actual body displacement")
 var retained: Vector3 = game.rider.velocity
 game.rider.release_wire()
 var released_length: float = game.rider.rope_length
 check(game.rider.velocity.is_equal_approx(retained), "release preserves full velocity immediately")
 var old_y: float = game.rider.position.y
 await frames(10)
 check(game.rider.rope_length == released_length, "release stops automatic reeling")
 check(game.rider.position.y != old_y and game.rider.mode == "air", "released rider follows free flight")
 check(game.rider.fire(1), "opposite side can be acquired")
 check(game.rider.wire_side == 1, "single-wire ownership moves to latest side")
 game.rider.release_wire()

 await fixture(Vector3(0, 0.82, 0), Vector3(0, -1, -6))
 await frames(60)
 check(game.rider.mode == "ground" and game.rider.velocity.length() < 0.1, "soft landing stops without automatic running")
 game.rider.jump()
 await frames(25)
 check(game.rider.position.y > 2.5, "ground jump creates enough room to reconnect")

 await fixture(Vector3(0, 1.0, 0), Vector3(0, -2, -14))
 game.rider.tiers.skates = 1
 game.rider.anchor = game.city.anchors[0]
 game.rider.release_wire()
 await frames(8)
 check(game.rider.mode == "slide", "real floor sweep enters skating")
 check(absf(game.rider.velocity.z + 14) < 0.1, "slide retains horizontal momentum")
 var remaining: float = game.rider.slide_left
 await frames(10)
 check(absf(remaining - game.rider.slide_left - 10.0 / 60.0) < 0.01 and game.rider.slides == 1, "skating consumes elapsed seconds once")
 game.rider.jump()
 await frames(20)
 check(game.rider.mode == "air" and game.rider.slide_armed, "slide jump re-arms after actual air height")
 check(game.rider.fire(-1), "slide jump can reconnect")
 await frames(20)
 check(game.rider.mode == "swing", "slide > jump > hook reaches swing through physics")

 await fixture(Vector3(0, 1.0, 0), Vector3(0, -2, -14))
 game.rider.tiers.skates = 1
 game.rider.anchor = game.city.anchors[0]
 game.rider.hook_left = 100 # Fixture: connected-input state pending release; no rope constraint.
 await frames(5)
 check(game.rider.mode == "slide" and game.rider.anchor == null, "holding a wire at touchdown still skates and detaches safely")
 await frames(130)
 check(game.rider.mode == "ground" and game.rider.velocity.length() < 0.1, "skating expiry stops without auto-run")

 await fixture(Vector3(0, 1.0, 0), Vector3(0, -9, -14))
 await frames(4)
 check(game.rider.mode == "ground" and game.phase == "playing", "hard floor collision stops safely in challenge")
 await fixture(Vector3(0, 1.0, 0), Vector3(0, -9, -14))
 game.rider.upgrade("armor")
 await frames(4)
 check(game.rider.mode == "ground" and game.rider.armor_charges == 1, "hard landing does not consume armor")
 game.rider.hurt("obstacle collision")
 check(game.rider.mode == "air" and game.rider.armor_charges == 0, "armor still absorbs an obstacle collision")
 game.rider.hurt("same collision")
 check(game.rider.mode != "dead", "one collision cluster does not kill during invulnerability")

 await fixture(Vector3(0, 6, 0), Vector3(0, 0, -12), true)
 check(game.rider.launch(), "twin launch succeeds with two visible anchors")
 var direction: Vector3 = ((game.rider.twin_left.global_position + game.rider.twin_right.global_position) * 0.5 - game.rider.position).normalized()
 check(game.rider.velocity.normalized().dot(direction) > 0.999, "launch immediately replaces momentum with player-to-anchor-midpoint vector")
 var launch_start: Vector3 = game.rider.position
 await frames(12)
 check((game.rider.position - launch_start).normalized().dot(direction) > 0.999 and game.rider.invincible > 0, "dash moves along locked vector with protection")
 var dash_velocity: Vector3 = game.rider.velocity
 game.rider.hurt("dash collision")
 check(game.rider.velocity == dash_velocity and game.rider.mode == "launch", "dash invulnerability preserves direction and speed")
 check(not game.rider.launch(), "cooldown prevents twin-launch spam")
 game.rider.launch_cooldown = 0
 await frames(45)
 game.rider.position = Vector3(0, 80, 0)
 check(not game.rider.launch() and game.rider.launch_cooldown == 0, "invalid twin target spends no cooldown")

 await fixture(Vector3(0, 6, 0), Vector3.ZERO, true)
 for target in game.city.anchors:
  target.set_meta("side", -1)
 check(not game.rider.launch() and game.rider.launch_cooldown == 0, "one-sided anchors cannot trigger or spend a twin launch")

 for tier in range(1, 4):
  await fixture(Vector3(0, 1, 0), Vector3(0, -25, -10), true)
  game.rider.practice = false
  game.rider.tiers.skates = tier
  await frames(2)
  check(game.rider.mode == "slide" and absf(game.rider.velocity.z + 10) < 0.1, "tier %d hard landing preserves speed without dying" % tier)
  await frames(100)
  check(game.rider.mode == "slide" and absf(game.rider.velocity.z + 10) < 0.1, "tier %d skating holds speed while time remains" % tier)
  await frames(ceili(Rules.SLIDE_SECONDS[tier] * 60) - 100)
  check(game.rider.mode == "ground" and absf(game.rider.velocity.z) < 0.1, "tier %d stops when its duration expires" % tier)

 await fixture(Vector3(2, 6, 0), Vector3(9, -20, 10), true)
 game.rider.practice = false
 check(game.rider.launch(), "off-center falling rider can launch")
 var dash_start: Vector3 = game.rider.position
 var dash_direction: Vector3 = game.rider.velocity.normalized()
 # Put a collider across the already selected dash route to exercise passage.
 var barrier: Node3D = game.city.box(game.city, dash_start + dash_direction * 3, Vector3(8, 2, 1), Color.WHITE, true)
 await frames(12, 1)
 check(game.rider.mode == "launch" and (game.rider.position - dash_start).length() > 5 and game.rider.velocity.normalized().dot(dash_direction) > 0.999, "protected dash passes an obstacle without steering or gravity changing its vector")
 barrier.free()
 await frames(50)
 check(game.rider.launch_left == 0 and game.rider.mode == "air" and game.rider.invincible == 0, "dash and its brief exit protection expire normally")

 await fixture(Vector3(0, 1, -354), Vector3(0, 0, -35))
 game.rider.invincible = Rules.RESUME_PROTECTION
 game.rider.mode = "slide"
 game.rider.slide_left = 5
 await frames(12)
 check(game.rider.mode != "dead" and game.rider.armor_charges == 0, "resume shield survives a real swept hurdle collision without armor")
 await frames(125)
 game.rider.hurt("after shield")
 check(game.rider.mode == "dead", "normal danger returns after resume protection expires")

 await fixture(Vector3(0, 6, 0), Vector3(0, 0, -12))
 game.xp = 250
 game.open_upgrades()
 check(game.phase == "upgrade" and "skates" in game.choices and "launcher" in game.choices, "first upgrade offers core abilities")
 var frozen_pos: Vector3 = game.rider.position
 var frozen_cooldown: float = game.rider.launch_cooldown
 game.set_physics_process(true)
 for i in range(12):
  await physics_frame
 game.set_physics_process(false)
 check(game.rider.position == frozen_pos and game.rider.launch_cooldown == frozen_cooldown, "upgrade UI freezes physics and cooldown")
 game.choose(0)
 check(game.level == 2 and game.xp == 70 and game.phase == "countdown", "choice carries XP and gates resume")
 game.choose(0)
 check(game.level == 2, "duplicate selection is ignored")
 game._physics_process(1.01)
 check(game.phase == "playing" and game.rider.invincible > 0.9, "upgrade countdown grants protection only as play resumes")
 game.phase = "paused"
 game.rider.invincible = 0
 game.resume()
 check(game.rider.invincible == 0, "pause countdown does not consume protection early")
 game._physics_process(1.01)
 check(game.phase == "playing" and game.rider.invincible > 0.9, "ordinary pause resume also grants protection")

 await fixture(Vector3(0, 6, 0), Vector3(0, 0, -12))
 game.rider.fire(-1)
 var attached: Node3D = game.rider.anchor
 game.city.update_chunks(640, attached)
 check(is_instance_valid(attached), "streaming retains attached anchor chunk")
 game.rider.release_wire()
 game.city.update_chunks(640)
 check(not is_instance_valid(attached), "unattached old chunk is reclaimed")
 check(game.city.chunks.size() <= 8, "streaming active chunk count is bounded")
 var old_progress: float = Rules.progress(0, game.rider.position.z, game.city.origin_offset)
 game.city.rebase(2048)
 game.rider.position.z += 2048
 check(Rules.progress(0, game.rider.position.z, game.city.origin_offset) == old_progress, "floating origin preserves logical distance")

 await fixture(Vector3(0, 2.0, -291), Vector3(0, 0, -35))
 # Block 4 is FREE FLOW, block 5 HURDLES at z=-358.
 game.rider.position = Vector3(0, 1.0, -354)
 game.rider.velocity = Vector3(0, 0, -35)
 await frames(12)
 check(game.rider.mode == "dead", "35m/s swept collision cannot tunnel through hurdle")

 print("RESULT ", checks - failures, "/", checks, " passed; failures=", failures)
 game.free()
 await process_frame
 quit(0 if failures == 0 else 1)
