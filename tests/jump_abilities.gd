extends SceneTree
const Rules = preload("res://scripts/rules.gd")
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
func fixture(practice: bool = false) -> void:
 game.start_run(practice)
 # Legacy physics fixtures keep their original launch height; rooftop spawn has separate tests.
 game.rider.position = Vector3(0, 6, 0)
 game.rider.velocity = Vector3(0, 0, -12)
 game.camera.position = game.rider.position + game.Rules.CAMERA_OFFSET
 game.camera.look_at(game.rider.position + Vector3(0, 0.8, -9))
 game.rider.practice = practice
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
 var missing: Array = game.city.chunks[3].get_children().filter(func(n: Node): return n.get_meta("building", false) and n.position.x < 0)
 check(missing.is_empty(), "default run keeps the building-spacing layout on one side")
 var opposite: Array = game.city.chunks[3].get_children().filter(func(n: Node): return n.get_meta("building", false) and n.position.x > 0)
 check(opposite.size() == 4, "default run retains the opposite wall")

 await fixture(true)
 var left_practice: Array = game.city.chunks[3].get_children().filter(func(n: Node): return n.get_meta("building", false) and n.position.x < 0)
 var right_practice: Array = game.city.chunks[3].get_children().filter(func(n: Node): return n.get_meta("building", false) and n.position.x > 0)
 check(left_practice.size() == 4 and right_practice.size() == 4, "practice mode always keeps both walls for swing practice")

 # Past 2000m (index 32 = 2048m), a recurring building-free span appears.
 await fixture()
 game.city.practice = false
 check(2048.0 >= game.city.NO_BUILDING_SECTION_START_DISTANCE, "fixture sanity: chunk 32 starts past the no-building threshold")
 game.city.create_chunk(32)
 var no_building_chunk: Array = game.city.chunks[32].get_children().filter(func(n: Node): return n.get_meta("building", false))
 var no_building_hazards: Array = game.city.chunks[32].get_children().filter(func(n: Node): return n.get_meta("hazard", false))
 check(no_building_chunk.is_empty(), "a no-building special section has no playable buildings on either side")
 check(no_building_hazards.size() > 0, "a no-building special section still spawns aerial (police drone) obstacles")
 game.city.create_chunk(35)
 var resumed_chunk: Array = game.city.chunks[35].get_children().filter(func(n: Node): return n.get_meta("building", false))
 check(not resumed_chunk.is_empty(), "the ordinary building-lined layout resumes after the special section ends")
 game.city.create_chunk(40)
 var recurs_chunk: Array = game.city.chunks[40].get_children().filter(func(n: Node): return n.get_meta("building", false))
 check(recurs_chunk.is_empty(), "the special section recurs periodically rather than only appearing once")

 await fixture()
 game.rider.mode = "ground"
 game.rider.jump()
 check(game.rider.mode == "air" and game.rider.velocity.y > 0, "ground jump still works")
 check(game.rider.double_jump_left <= 0, "ground jump does not touch the double jump cooldown")
 game.rider.velocity.y = -5
 game.rider.jump()
 check(game.rider.velocity.y == -5, "double jump does nothing until the special ability has been picked at least once")
 check(game.rider.double_jump_left <= 0, "an unpicked double jump never starts a cooldown")

 await fixture()
 game.rider.upgrade("double_jump")
 game.rider.mode = "ground"
 game.rider.jump()
 var first_jump_speed: float = game.rider.velocity.y
 game.rider.jump()
 check(is_equal_approx(game.rider.velocity.y, first_jump_speed), "once picked, double jump matches jump height")
 check(game.rider.double_jump_left > 0, "double jump starts its cooldown once unlocked")
 game.rider.velocity.y = -5
 game.rider.jump()
 check(game.rider.velocity.y == -5, "a second air jump is blocked while the cooldown is active")
 check(is_equal_approx(game.rider.double_jump_left, Rules.DOUBLE_JUMP_COOLDOWN[0]), "the first pick's cooldown is ten seconds")

 await fixture()
 game.rider.upgrade("double_jump")
 game.rider.upgrade("double_jump")
 game.rider.upgrade("double_jump")
 game.rider.mode = "ground"
 game.rider.jump()
 game.rider.jump()
 check(is_equal_approx(game.rider.double_jump_left, Rules.DOUBLE_JUMP_COOLDOWN[2]), "further double jump picks recharge it faster, independent of jump height")

 await fixture()
 game.rider.mode = "ground"
 game.rider.jump()
 var base_jump_speed: float = game.rider.velocity.y
 await fixture()
 game.rider.upgrade("double_jump")
 game.rider.upgrade("double_jump")
 game.rider.mode = "ground"
 game.rider.jump()
 check(is_equal_approx(game.rider.velocity.y, base_jump_speed), "the double jump upgrade alone does not change jump height")
 await fixture()
 game.rider.upgrade("jump")
 game.rider.mode = "ground"
 game.rider.jump()
 check(game.rider.velocity.y > base_jump_speed, "the jump upgrade alone raises jump height")
 check(game.rider.double_jump_left <= 0, "the jump upgrade alone does not unlock double jump")
 game.rider.velocity.y = -5
 game.rider.jump()
 check(game.rider.velocity.y == -5, "double jump still needs its own pick even after a jump-height upgrade")

 await fixture()
 game.rider.upgrade("double_jump")
 game.rider.mode = "ground"
 game.rider.jump()
 game.rider.jump()
 check(game.rider.double_jump_left > 0, "double jump is consumed before a landing check")
 game.rider.land(Vector3.ZERO)
 check(game.rider.mode == "ground", "landing does not clear an active double jump cooldown")
 game.rider.mode = "air"
 game.rider.velocity.y = -3
 game.rider.jump()
 check(game.rider.velocity.y == -3, "double jump stays blocked by its cooldown even after landing and taking off again")

 # Wall jump is disabled (commented out in rider.gd) pending a working touch-detection pass.
 # Building contact must still be safe and register a touch, even though jump() no longer acts on it.
 await fixture()
 game.rider.position = Vector3(-7.2, 15, -8)
 game.rider.mode = "air"
 game.rider.velocity = Vector3(-12, 0, 0)
 game.rider.simulate(1.0 / 60, 0)
 check(game.rider.mode != "dead", "a real gameplay-speed building collision does not hurt the player")
 check(game.rider.touching_wall_side != 0, "a real gameplay-speed building collision still registers a wall touch")
 game.rider.double_jump_left = 5 # Isolate the wall-touch path from the separate double jump ability.
 var before_velocity: Vector3 = game.rider.velocity
 game.rider.jump()
 check(game.rider.velocity == before_velocity, "wall jump is disabled: touching a wall does not trigger an extra jump")

 print("JUMP_ABILITIES_RESULT ", checks - failures, "/", checks, " passed; failures=", failures)
 game.free()
 await process_frame
 quit(0 if failures == 0 else 1)
