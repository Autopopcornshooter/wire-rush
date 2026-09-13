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
 check(Rules.floor_outcome(3, 20, 1, true, true) == "slide", "fast horizontal / soft vertical landing slides")
 check(Rules.floor_outcome(4.1, 20, 1, true, true) == "fatal", "skates do not absorb hard impacts")
 check(Rules.floor_outcome(3, 20, 0, true, true) == "stumble", "without skates soft landing stumbles")
 check(Rules.floor_outcome(3, 20, 1, true, false) == "stumble", "same landing cannot refresh slide")

 await fixture(Vector3(0, 6, 0), Vector3(0, 0, -12))
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
 check(game.rider.mode == "ground", "soft landing recovers to auto-run")
 game.rider.jump()
 await frames(25)
 check(game.rider.position.y > 2.5, "ground jump creates enough room to reconnect")

 await fixture(Vector3(0, 1.0, 0), Vector3(0, -2, -14))
 game.rider.tiers.skates = 1
 game.rider.anchor = game.city.anchors[0]
 game.rider.release_wire()
 await frames(8)
 check(game.rider.mode == "slide", "real low-impact sweep enters slide within early release window")
 check(absf(game.rider.velocity.z + 14) < 0.1, "slide retains horizontal momentum")
 var remaining: float = game.rider.slide_left
 await frames(10)
 check(game.rider.slide_left < remaining and game.rider.slides == 1, "slide consumes traveled distance once")
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
 check(game.rider.mode == "landing", "late-release grace holds landing decision")
 game.rider.release_wire()
 await frames(1)
 check(game.rider.mode == "slide", "release after touchdown still enters slide")

 await fixture(Vector3(0, 1.0, 0), Vector3(0, -9, -14))
 await frames(4)
 check(game.rider.mode == "dead", "hard floor collision ends challenge")
 await fixture(Vector3(0, 1.0, 0), Vector3(0, -9, -14))
 game.rider.upgrade("armor")
 await frames(4)
 check(game.rider.mode == "air" and game.rider.armor_charges == 0, "armor absorbs one hard collision and recovers")
 game.rider.hurt("same collision")
 check(game.rider.mode != "dead", "one collision cluster does not kill during invulnerability")

 await fixture(Vector3(0, 6, 0), Vector3(0, 0, -12), true)
 check(game.rider.launch(), "twin launch succeeds with two visible anchors")
 await frames(12)
 check(game.rider.velocity.z < -18 and game.rider.launch_cooldown > 9, "twin launch adds bounded speed after windup")
 check(not game.rider.launch(), "cooldown prevents twin-launch spam")
 game.rider.launch_cooldown = 0
 game.rider.position = Vector3(0, 80, 0)
 check(not game.rider.launch() and game.rider.launch_cooldown == 0, "invalid twin target spends no cooldown")

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
