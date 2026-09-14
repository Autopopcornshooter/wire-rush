extends SceneTree
const Rules = preload("res://scripts/rules.gd")
var game: Node3D
var checks: int = 0
var failures: int = 0
func _initialize() -> void:
 create_timer(40).timeout.connect(func():
  push_error("Behavior tests timed out")
  quit(1)
 )
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
 # Legacy physics fixtures keep their original launch height; rooftop spawn has separate tests.
 game.rider.position = Vector3(0, 6, 0)
 game.rider.velocity = Vector3(0, 0, -12)
 game.camera.position = game.rider.position + game.Rules.CAMERA_OFFSET
 game.camera.look_at(game.rider.position + Vector3(0, 0.8, -9))
 game.rider.practice = false
 game.set_physics_process(false)
 game.set_process(false)
 await physics_frame
func frames(count: int) -> void:
 for i in range(count):
  await physics_frame
  game.rider.simulate(1.0 / 60, 0)
func shoot(height: float, side: int = -1) -> bool:
 var point := Vector3(side * 7.4, height, game.rider.position.z - 8)
 var target: Dictionary = game.city.manual_target(game.rider.position, game.rider.position, (point - game.rider.position).normalized(), game.rider.reach(), game.rider.get_rid())
 return game.rider.fire_manual(target, side)
func hook(height: float) -> void:
 if not shoot(height):
  push_error("fixture hook not valid")
 await frames(20)
func touchdown(release_height: float = 4.0) -> void:
 game.rider.position.y = release_height
 game.rider.release_wire()
 game.rider.position = Vector3(0, 0.9, game.rider.position.z)
 game.rider.velocity = Vector3(0, -20, -14)
 await frames(3)
func hazards(chunk: Node3D) -> Array:
 return chunk.get_children().filter(func(n: Node): return n.get_meta("hazard", false))
func buildings(chunk: Node3D) -> Array:
 return chunk.get_children().filter(func(n: Node): return n.get_meta("building", false))
func run() -> void:
 game = load("res://scenes/main.tscn").instantiate()
 root.add_child(game)
 game.set_physics_process(false)
 game.set_process(false)
 await fixture()
 check(Rules.progress(80, -40, 0) == 80 and Rules.progress(80, -90, 0) == 90, "distance rewards only new forward travel")
 check(Rules.UPGRADES.has("launcher") and game.rider.has_method("launch"), "two-wire launch and its speed upgrade are restored")
 check(not game.city.has_method("find_anchor") and not game.city.has_method("add_anchor"), "automatic anchor network is removed")
 check((game.camera.position - game.rider.position).is_equal_approx(Vector3(0, 4.5, 12)), "distant camera stays restored")
 check(shoot(18), "manual wall shot succeeds")
 check(not game.rider.hook_connected and game.rider.last_release_height == 0, "flying hook does not change landing history early")
 await frames(25)
 check(game.rider.hook_connected and game.rider.mode == "swing" and game.rider.last_release_height == 0, "connection alone does not record release height")
 var length: float = game.rider.rope_length
 await frames(8)
 check(game.rider.rope_length < length, "holding the wire reels automatically")
 check(game.rider.position.distance_to(game.rider.anchor.global_position) <= game.rider.rope_length + 0.1, "swing movement respects rope constraint")
 var velocity_before: Vector3 = game.rider.velocity
 var release_y: float = game.rider.global_position.y
 game.rider.release_wire()
 check(game.rider.velocity == velocity_before and game.rider.last_release_height == release_y, "release records player height and preserves momentum")

 for height in [4.99, 5.0, 5.01, 18.0]:
  await fixture()
  await hook(18)
  game.rider.invincible = 2
  game.rider.upgrade("armor")
  await touchdown(height)
  if height <= 5:
   check(game.rider.mode == "slide" and game.rider.armor_charges == 1, "player release %.2fm from high anchor permits skating without consuming armor" % height)
  else:
   check(game.rider.mode == "dead" and game.phase == "dead" and game.rider.armor_charges == 1, "player release %.2fm is fatal despite shield and armor" % height)
 await fixture()
 game.rider.practice = true
 await hook(4)
 await touchdown(8)
 check(game.rider.mode == "dead", "low anchor released high is fatal even in practice")
 await fixture()
 await hook(4)
 game.rider.tiers.skates = 0
 await touchdown()
 check(game.rider.mode == "ground" and game.rider.velocity.length() < 0.1, "safe low release without skates stops")
 await fixture()
 await touchdown()
 check(game.rider.mode == "ground", "initial no-hook drop can land")
 await fixture()
 await hook(18)
 game.rider.position.y = 8
 game.rider.release_wire()
 game.rider.position.y = 3
 game.phase = "paused"
 game.resume()
 check(game.rider.last_release_height > 5 and not game.rider.landing_safe(), "pausing cannot erase fatal landing history")
 await fixture()
 await hook(18)
 game.rider.position.y = 8
 game.rider.release_wire()
 game.rider.position = Vector3(0, 4, -1)
 game.rider.velocity = Vector3.ZERO
 await physics_frame
 check(shoot(18), "new high anchor can be chosen after a high release")
 await frames(20)
 await touchdown()
 check(game.rider.mode == "slide", "new wire released low replaces previous high-release danger")
 await fixture()
 await hook(4)
 check(not game.rider.fire_manual({"valid": false}, 1) and game.rider.last_release_height < 5, "invalid retarget does not alter release history")


 await fixture()
 await hook(18)
 game.rider.position.y = 8
 check(not game.rider.landing_safe(), "held wire previews current high player release as fatal")
 game.rider.position.y = 4
 check(game.rider.landing_safe(), "held wire previews current low player release as safe")
 game.rider.release_wire()
 game.rider.position.y = 12
 check(game.rider.last_release_height == 4 and game.rider.landing_safe(), "rising after release does not change recorded height")
 await touchdown()
 check(game.rider.mode == "slide", "high free-flight peak after low release remains safe")
 await fixture()
 await hook(4)
 game.rider.position.y = 8
 game.rider.release_wire()
 game.rider.position.y = 4
 check(shoot(18), "replacement shot can fly after a high release")
 game.rider.release_wire()
 check(game.rider.last_release_height == 8 and not game.rider.landing_safe(), "canceling an in-flight hook cannot clear fatal release history")
 await touchdown()
 check(game.rider.mode == "dead", "descending below 5m without a new connected release remains fatal")
 await fixture()
 await hook(18)
 game.rider.position.y = 8
 game.phase = "paused"
 game.resume()
 check(game.rider.last_release_height == 8, "resume detach records player height while wire is held")
 await fixture()
 await hook(18)
 game.rider.position = Vector3(0, 0.9, game.rider.position.z)
 game.rider.velocity = Vector3(0, -20, -14)
 game.rider.rope_length = 30
 await frames(3)
 check(game.rider.mode == "slide" and game.rider.last_release_height < 1, "road contact detaches a held wire at the low player contact height")

 var speeds: Array[float] = []
 for tier in range(1, 4):
  await fixture()
  await hook(4)
  game.rider.tiers.skates = tier
  await touchdown()
  var before: float = Vector2(game.rider.velocity.x, game.rider.velocity.z).length()
  await frames(60)
  var after: float = Vector2(game.rider.velocity.x, game.rider.velocity.z).length()
  speeds.append(after)
  check(absf(before - after - Rules.SKATE_FRICTION[tier] * Rules.GRAVITY) < 0.1, "tier %d loses speed from friction over one second" % tier)
  check(after > 0 and after < before, "tier %d decelerates naturally" % tier)
  await frames(400)
  check(game.rider.mode == "ground" and game.rider.velocity.length() < 0.1, "tier %d eventually stops without a duration timer" % tier)
 check(speeds[0] < speeds[1] and speeds[1] < speeds[2], "higher skates tiers retain more speed through lower friction")

 await fixture()
 await hook(4)
 await touchdown()
 var slides_before: int = game.rider.slides
 game.rider.jump()
 game.rider.velocity.y = 16 # Fixture: an ordinary jump higher than 5m.
 var max_y: float = 0
 for i in range(110):
  await frames(1)
  max_y = maxf(max_y, game.rider.position.y)
 check(max_y > 5 and game.rider.mode == "ground", "unhooked jump above 5m is safe")
 check(game.rider.slides == slides_before and game.rider.velocity.length() < 0.1, "jump and landing alone do not restart skating")
 await fixture()
 game.rider.stop_on_ground()
 game.rider.jump()
 await hook(18)
 await touchdown(8)
 check(game.rider.mode == "dead", "new connection cancels jump exemption and high release is fatal")
 await fixture()
 await hook(4)
 await touchdown()
 game.rider.jump()
 await hook(4)
 await touchdown()
 check(game.rider.mode == "slide" and game.rider.slides == 2, "a fresh wire released low after jumping permits a new slide")

 await fixture()
 game.rider.upgrade("armor")
 game.rider.hurt("OBSTACLE COLLISION")
 check(game.rider.mode == "air" and game.rider.armor_charges == 0 and game.rider.invincible > 0, "armor still absorbs an obstacle collision")
 game.rider.hurt("OBSTACLE COLLISION")
 check(game.rider.mode != "dead", "obstacle protection still covers a collision cluster")
 game.phase = "paused"
 game.resume()
 game.countdown = 0
 game.countdown_started = true
 game._physics_process(1.0 / 60)
 check(game.phase == "playing" and game.rider.invincible > 1.9, "resume protection starts when simulation resumes")

 await fixture()
 game.city.practice = false
 game.city.create_chunk(8)
 var chunk: Node3D = game.city.chunks[8]
 var blocks: Array = hazards(chunk)
 check(blocks.size() == 4, "challenge chunk contains four aerial obstacles")
 check(blocks.all(func(n: Node3D): return n.position.y > 4 and n.get_meta("hookable", false)), "all aerial obstacles can accept hooks")
 check(blocks.all(func(n: Node3D): return n.get_child(0).mesh.size.x < 3 and n.get_child(0).mesh.size.y < 3), "obstacles have compact footprints rather than full-road walls")
 var building: Node3D = buildings(chunk)[0]
 var original_height: float = building.get_meta("height")
 var original_hazard_y: float = blocks[0].position.y
 game.rider.upgrade("high")
 check(is_equal_approx(building.get_meta("height"), original_height + 10), "height perk raises existing building geometry")
 check(is_equal_approx(blocks[0].position.y, original_hazard_y + 8), "height perk raises existing aerial hazards")
 check(is_equal_approx(building.get_child(1).shape.size.y, original_height + 10), "building collision height grows with the mesh")
 game.city.create_chunk(9)
 var future: Node3D = buildings(game.city.chunks[9])[0]
 check(is_equal_approx(future.get_meta("height"), float(future.get_meta("base_height")) + 10), "new chunks inherit the same height perk")
 game.rider.upgrade("high")
 game.rider.upgrade("high")
 check(is_equal_approx(building.get_meta("height"), original_height + 30) and is_equal_approx(blocks[0].position.y, original_hazard_y + 24), "highest tier scales buildings and hazards together")

 await fixture()
 await hook(4)
 var fixed: Vector3 = game.rider.anchor.global_position
 game.rider.upgrade("high")
 check(game.rider.anchor.global_position == fixed, "growing a building does not displace its fixed wall hook")
 var roof_target := Vector3(-7.4, 32, -8)
 game.rider.position = Vector3(0, 23, 0)
 await physics_frame
 var tall: Dictionary = game.city.manual_target(game.rider.position, game.rider.position, (roof_target - game.rider.position).normalized(), 30, game.rider.get_rid())
 check(tall.valid, "newly raised wall area is hookable through actual collision geometry")

 await fixture()
 var hazard: Node3D = game.city.obstacle(game.city.chunks[0], Vector3(0, 4.9, -10), Vector3(2.6, 2.2, 1.4))
 game.rider.position = Vector3(0, 4.9, 0)
 game.rider.velocity = Vector3.ZERO
 await physics_frame
 var selection: Dictionary = game.city.manual_target(game.rider.position, game.rider.position, Vector3.FORWARD, 30, game.rider.get_rid())
 check(selection.valid and selection.surface == hazard, "camera-style ray can target an airborne obstacle")
 check(game.rider.fire_manual(selection, -1), "wire can fire into the aerial obstacle")
 await frames(20)
 check(game.rider.hook_connected and game.rider.anchor.get_parent() == hazard, "aerial hook connects through normal hook flight")
 game.rider.position.y = 4
 game.rider.upgrade("high")
 game.rider.release_wire()
 check(game.rider.last_release_height == 4 and game.rider.landing_safe(), "raising a held aerial anchor does not change player release height")
 game.rider.invincible = 0
 game.rider.position = hazard.global_position + Vector3(0, 0, 3)
 game.rider.velocity = Vector3(0, 0, -35)
 await frames(8)
 check(game.rider.mode == "dead", "hookable aerial obstacles remain physically dangerous")

 await fixture()
 await hook(4)
 var attached: Node3D = game.rider.anchor
 var relative: Vector3 = attached.global_position - game.rider.position
 game.city.rebase(2048)
 game.rider.position.z += 2048
 check((attached.global_position - game.rider.position).is_equal_approx(relative) and game.rider.last_release_height <= 5, "floating origin preserves attachment and landing height")
 game.city.update_chunks(640, attached)
 check(is_instance_valid(attached), "streaming protects the attached surface chunk")
 game.rider.release_wire()
 await process_frame
 game.city.update_chunks(640)
 check(not is_instance_valid(attached) and game.city.chunks.size() <= 8, "release frees manual points and old chunks")

 await fixture()
 game.xp = 250
 game.open_upgrades()
 check(game.phase == "upgrade" and game.choices.all(func(key: String): return Rules.UPGRADES.has(key)), "upgrade cards contain supported abilities")
 var frozen: Vector3 = game.rider.position
 game._physics_process(0.5)
 check(game.rider.position == frozen, "upgrade selection freezes simulation")
 game.choose(0)
 check(game.level == 2 and game.xp == 70 and game.phase == "countdown", "upgrade selection carries XP and gates resume")
 print("RESULT ", checks - failures, "/", checks, " passed; failures=", failures)
 game.free()
 await process_frame
 quit(0 if failures == 0 else 1)
