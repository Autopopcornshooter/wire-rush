extends SceneTree
## PHASE C: City Boss (Police Interceptor Graybox), Rest Area, and Signal
## Story. Never touches XP/Level/pending_upgrades/upgrade selection/synergy
## (PHASE A) or the Difficulty Director's tier/event pure functions beyond
## reading them (PHASE B) — see the "independence"-flavored checks below,
## which mirror tests/difficulty.gd's own Player/World separation tests.
##
## Boss Pattern Revision V2: PATH_BLOCK/LASER_PLANE keep their Area3D-based
## mechanism (resized/retimed only); DRONE_GATE is gone entirely, replaced
## by ROBOT_BARRAGE (moving AnimatableBody3D projectiles) — see
## scripts/city_boss.gd's own doc comments for the full reasoning.
const Rules = preload("res://scripts/rules.gd")
const DifficultyDirector = preload("res://scripts/difficulty_director.gd")
const CityBoss = preload("res://scripts/city_boss.gd")
const SignalStory = preload("res://scripts/signal_story.gd")
var game: Node3D
var checks: int = 0
var failures: int = 0

func _initialize() -> void:
 create_timer(40).timeout.connect(func():
  push_error("City Boss tests timed out")
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
 game.start_run(false)
 game.set_physics_process(false)
 game.set_process(false)
 await physics_frame

func frames(count: int) -> void:
 for i in range(count):
  await physics_frame
  game.rider.simulate(1.0 / 60, 0)

## Drives the boss directly (bypassing Main._physics_process's own
## distance-tracking loop) so tests can pin an exact distance/delta without
## real physics interference — the same "call the pure/isolated piece
## directly" style tests/difficulty.gd already uses for the Director.
func advance_boss(distance: float, seconds: float) -> void:
 var step: float = 1.0 / 60.0
 var elapsed: float = 0.0
 while true:
  game.boss.update(step, distance, game.rider, game.city)
  elapsed += step
  if elapsed >= seconds:
   break

## Cumulative time (from ACTIVE start) needed to reach the start of each
## pattern in the fixed sequence, derived from the pattern durations
## themselves rather than hardcoded, so a future duration tweak doesn't
## silently desync these tests.
func time_to_pattern_start(index: int) -> float:
 var t: float = 0.0
 for i in range(index):
  var name: String = CityBoss.PATTERN_SEQUENCE[i]
  t += game.boss.telegraph_duration(name) + game.boss.active_duration(name) + game.boss.recovery_duration(name) + CityBoss.COOLDOWN_DURATION
 return t

func run() -> void:
 game = load("res://scenes/main.tscn").instantiate()
 root.add_child(game)
 game.set_physics_process(false)
 game.set_process(false)

 check(CityBoss.PATTERN_SEQUENCE == ["PATH_BLOCK", "LASER_PLANE", "ROBOT_BARRAGE"], "the boss pattern sequence is PATH_BLOCK -> LASER_PLANE -> ROBOT_BARRAGE (DRONE_GATE is gone)")

 # ==================================================================
 # Boss: trigger / no-duplicate-start / state machine
 # ==================================================================
 await fixture()
 game.city.practice = false
 check(game.boss.state == "INACTIVE", "boss starts INACTIVE")
 advance_boss(0.0, 0.5)
 check(game.boss.state == "INACTIVE", "boss stays inactive at distance 0")
 advance_boss(DifficultyDirector.CITY_BOSS_START_DISTANCE - 1.0, 0.5)
 check(game.boss.state == "INACTIVE", "boss stays inactive 1m before the start distance")
 advance_boss(DifficultyDirector.CITY_BOSS_START_DISTANCE, 0.0)
 check(game.boss.state == "INTRO", "crossing the start distance begins the boss intro")
 check(game.boss.visible, "the boss becomes visible on intro")

 # No duplicate start: repeated updates at/after the threshold never restart the intro.
 advance_boss(DifficultyDirector.CITY_BOSS_START_DISTANCE, CityBoss.INTRO_DURATION + 0.1)
 check(game.boss.state == "ACTIVE", "the boss becomes ACTIVE once the intro duration elapses")
 var state_after_active: String = game.boss.state
 advance_boss(DifficultyDirector.CITY_BOSS_START_DISTANCE, 0.1)
 check(game.boss.state == state_after_active and game.boss.state != "INTRO", "further updates at the same distance never re-trigger INTRO")
 check(game.boss.pattern == "PATH_BLOCK", "the first ACTIVE pattern is PATH_BLOCK (deterministic order, not random)")

 # ==================================================================
 # Pattern A: PATH BLOCK (V3: whole-side vertical space limit — building
 # line + ~1/3 of that side's road, warning-blink telegraph, 2.0s active)
 # ==================================================================
 check(game.boss.closed_side == 1 or game.boss.closed_side == -1, "PATH_BLOCK always closes exactly one side")
 check(is_instance_valid(game.boss.block_node), "a PATH_BLOCK hazard volume exists")
 check(not game.boss.block_node.monitoring, "the hazard has no collision yet during its telegraph")
 var closed_side_first: int = game.boss.closed_side
 var open_side: int = -closed_side_first

 var bounds: Vector2 = game.boss.path_block_x_bounds(closed_side_first)
 check(signi(bounds.x) == closed_side_first and signi(bounds.y) == closed_side_first, "the hazard region stays entirely on the closed side (never crosses the road's center line into the open side)")
 var building_far_edge: float = closed_side_first * (CityBoss.PATH_BLOCK_BUILDING_CENTER + CityBoss.PATH_BLOCK_BUILDING_HALF_WIDTH)
 check(is_equal_approx(bounds.x, building_far_edge) or is_equal_approx(bounds.y, building_far_edge), "the hazard region reaches all the way to the closed building line's own far edge")
 var road_third_edge: float = closed_side_first * (CityBoss.PATH_BLOCK_ROAD_HALF_WIDTH * (1.0 - CityBoss.PATH_BLOCK_ROAD_FRACTION))
 check(is_equal_approx(bounds.x, road_third_edge) or is_equal_approx(bounds.y, road_third_edge), "the hazard region's inner edge stops at roughly a third of that side's road, matching the spec exactly")

 var block_shape: BoxShape3D = game.boss.block_node.get_child(1).shape
 var block_mesh: MeshInstance3D = game.boss.block_node.get_child(0)
 check(is_equal_approx(block_shape.size.x, bounds.y - bounds.x), "the hazard's collision width matches the computed building+road-third region exactly")
 check(is_equal_approx(block_mesh.mesh.size.x, block_shape.size.x) and is_equal_approx(block_mesh.mesh.size.y, block_shape.size.y) and is_equal_approx(block_mesh.mesh.size.z, block_shape.size.z), "the hazard's visible mesh and its collision volume are exactly the same size")
 check(is_equal_approx(block_shape.size.z, CityBoss.PATTERN_ZONE_DEPTH), "the hazard's Z depth covers the full pattern zone, not a thin slice")
 var current_max_building_height: float = 35.0 + Rules.BUILDING_BONUS[game.city.high_level]
 check(block_shape.size.y >= current_max_building_height, "the hazard's height covers every building variant at the current Building Height tier, not a fixed value")
 check(is_equal_approx(game.boss.block_node.global_position.y, block_shape.size.y * 0.5), "the hazard spans from ground level up (no gap to duck under, and no gap to fly over)")

 # The height formula must scale with EVERY Building Height tier (0-3).
 for high_level in range(4):
  game.city.apply_height_level(high_level)
  var expected: float = CityBoss.PATH_BLOCK_BASE_HEIGHT + Rules.BUILDING_BONUS[high_level] + CityBoss.PATH_BLOCK_HEIGHT_MARGIN
  check(is_equal_approx(game.boss.path_block_wall_height(), expected), "the hazard height formula covers Building Height tier %d with its own margin" % high_level)
 game.city.apply_height_level(3)

 check(is_equal_approx(game.boss.active_duration("PATH_BLOCK"), 2.0), "PATH_BLOCK's active duration is exactly 2.0 seconds")

 # Warning: exactly WARNING_BLINK_COUNT on/off blinks, collision OFF
 # throughout, ending exactly at the telegraph->active boundary.
 var sample_dt: float = 0.01
 var t: float = 0.0
 var prev_blink: bool = game.boss.warning_blink_visible(0.0)
 var blink_transitions: int = 0
 while t < CityBoss.WARNING_TOTAL_DURATION:
  var cur_blink: bool = game.boss.warning_blink_visible(t)
  if cur_blink != prev_blink:
   blink_transitions += 1
  prev_blink = cur_blink
  t += sample_dt
 check(blink_transitions == CityBoss.WARNING_BLINK_COUNT * 2 - 1, "the warning blinks ON/OFF/ON/OFF/ON/OFF exactly %d times before going active" % CityBoss.WARNING_BLINK_COUNT)
 check(is_equal_approx(CityBoss.PATH_BLOCK_TELEGRAPH, CityBoss.WARNING_TOTAL_DURATION), "PATH_BLOCK's telegraph is exactly the shared 3-blink warning duration")

 advance_boss(DifficultyDirector.CITY_BOSS_START_DISTANCE, CityBoss.PATH_BLOCK_TELEGRAPH * 0.5)
 check(not game.boss.block_node.monitoring, "collision stays OFF partway through the warning blink, regardless of blink phase")
 advance_boss(DifficultyDirector.CITY_BOSS_START_DISTANCE, CityBoss.PATH_BLOCK_TELEGRAPH * 0.5 + 0.05)
 check(game.boss.pattern_phase == "ACTIVE" and game.boss.block_node.monitoring, "the hazard becomes lethal exactly once the warning blinking ends")
 check(game.boss.block_node.get_child(0).visible, "the hazard is continuously visible (no more blinking) once active")

 # Wire aim/attach itself is completely unaffected: a real building on the
 # OPEN side must still be a valid, connectable wire target while PATH_BLOCK
 # is fully active on the other side.
 var open_target := Vector3(open_side * 7.4, 26.0, game.rider.position.z - 8.0)
 var open_selection: Dictionary = game.city.manual_target(game.rider.position, game.rider.position, (open_target - game.rider.position).normalized(), game.rider.reach(), game.rider.get_rid())
 check(open_selection.get("valid", false), "a building on the open side is still a normal, connectable wire target while PATH_BLOCK is active")

 await fixture()
 game.city.practice = false
 advance_boss(DifficultyDirector.CITY_BOSS_START_DISTANCE, CityBoss.INTRO_DURATION + CityBoss.PATH_BLOCK_TELEGRAPH + 0.2)
 var open_side2: int = -game.boss.closed_side
 game.rider.position = Vector3(open_side2 * 11.4, 15.0, game.boss.block_node.global_position.z)
 game.rider.velocity = Vector3.ZERO
 game.rider.invincible = 0
 game.rider.armor_charges = 0
 await frames(4)
 check(game.rider.mode != "dead", "standing on the PATH_BLOCK's open side is safe (at least one route always exists)")

 # Armor absorbs a PATH_BLOCK hit exactly like any other obstacle collision.
 # Rules.ARMOR_PROTECTION (2.0s) exactly covers the whole 2.0s active
 # window, so a player pinned in the hazard for its entire duration still
 # only ever loses one charge (spec section 18).
 await fixture()
 game.city.practice = false
 advance_boss(DifficultyDirector.CITY_BOSS_START_DISTANCE, CityBoss.INTRO_DURATION + CityBoss.PATH_BLOCK_TELEGRAPH + 0.2)
 game.rider.upgrade("armor")
 game.rider.invincible = 0
 game.boss._on_pattern_body_entered(game.rider)
 check(game.rider.mode != "dead" and game.rider.armor_charges == 0, "armor absorbs a PATH_BLOCK hit exactly like any other obstacle collision")
 game.boss._on_pattern_body_entered(game.rider)
 check(game.rider.mode != "dead", "repeated PATH_BLOCK contact within the same invincibility window is suppressed, not stacked")
 advance_boss(DifficultyDirector.CITY_BOSS_START_DISTANCE, CityBoss.PATH_BLOCK_ACTIVE - 0.05)
 game.boss._on_pattern_body_entered(game.rider)
 check(game.rider.mode != "dead", "armor's protection window covers the entire 2.0s active duration, not just the first hit")

 await fixture()
 game.city.practice = false
 advance_boss(DifficultyDirector.CITY_BOSS_START_DISTANCE, CityBoss.INTRO_DURATION + CityBoss.PATH_BLOCK_TELEGRAPH + 0.2)
 game.rider.armor_charges = 0
 game.rider.invincible = 0
 game.boss._on_pattern_body_entered(game.rider)
 check(game.rider.mode == "dead", "without armor, touching the closed side during PATH_BLOCK is Game Over, same as any obstacle")

 # ==================================================================
 # Pattern B: LASER PLANE (V3: splits usable building height exactly in
 # half; UPPER/LOWER alternates, full corridor width, warning blink,
 # 2.0s active)
 # ==================================================================
 await fixture()
 game.city.practice = false
 game.city.apply_height_level(3)
 game.rider.position = Vector3(0, 20, -100)
 game.boss.rider = game.rider
 game.boss.city = game.city
 var top_now: float = game.boss.laser_building_top()
 var mid_now: float = top_now * 0.5

 game.boss.spawn_laser_plane()
 var first_upper: bool = game.boss.laser_upper
 var first_bounds: Vector2 = game.boss.laser_half_bounds(first_upper)
 check(is_equal_approx(first_bounds.x, mid_now if first_upper else 0.0) and is_equal_approx(first_bounds.y, top_now if first_upper else mid_now), "the selected half's bounds are exactly [mid,top] for UPPER or [0,mid] for LOWER")
 game.boss.laser_node.queue_free()

 game.boss.spawn_laser_plane()
 check(game.boss.laser_upper != first_upper, "LASER_PLANE alternates between UPPER and LOWER every spawn, never repeating the same half twice in a row")
 game.boss.laser_node.queue_free()

 await fixture()
 game.city.practice = false
 advance_boss(DifficultyDirector.CITY_BOSS_START_DISTANCE, CityBoss.INTRO_DURATION + time_to_pattern_start(1) + 0.2)
 check(game.boss.pattern == "LASER_PLANE", "the second pattern is LASER_PLANE (deterministic order)")
 check(game.boss.pattern_phase == "TELEGRAPH", "LASER_PLANE starts in its telegraph phase")
 check(is_instance_valid(game.boss.laser_node) and not game.boss.laser_node.monitoring, "a laser telegraph exists but is not yet collidable")
 var laser_pos_before_active: Vector3 = game.boss.laser_node.global_position

 var laser_mesh: MeshInstance3D = game.boss.laser_node.get_child(0)
 var laser_shape: BoxShape3D = game.boss.laser_node.get_child(1).shape
 check(is_equal_approx(laser_mesh.mesh.size.x, laser_shape.size.x) and is_equal_approx(laser_mesh.mesh.size.y, laser_shape.size.y) and is_equal_approx(laser_mesh.mesh.size.z, laser_shape.size.z), "the laser's visible mesh and its collision volume are exactly the same size")
 check(laser_shape.size.x >= 30.0, "the laser spans the full corridor width, both building lines and the road between them")
 var current_top: float = game.boss.laser_building_top()
 check(is_equal_approx(laser_shape.size.y, current_top * 0.5), "the laser volume is a full half of the current usable building height, not a thin slab")
 check(is_equal_approx(laser_shape.size.z, CityBoss.PATTERN_ZONE_DEPTH), "the laser's Z depth covers the full pattern zone, not a thin slice")
 check(is_equal_approx(game.boss.active_duration("LASER_PLANE"), 2.0), "LASER_PLANE's active duration is exactly 2.0 seconds")
 check(is_equal_approx(CityBoss.LASER_TELEGRAPH, CityBoss.WARNING_TOTAL_DURATION), "LASER_PLANE's telegraph is exactly the shared 3-blink warning duration")

 advance_boss(DifficultyDirector.CITY_BOSS_START_DISTANCE, CityBoss.LASER_TELEGRAPH * 0.5)
 check(not game.boss.laser_node.monitoring, "collision stays OFF partway through the warning blink")
 advance_boss(DifficultyDirector.CITY_BOSS_START_DISTANCE, CityBoss.LASER_TELEGRAPH * 0.5 + 0.05)
 check(game.boss.pattern_phase == "ACTIVE" and game.boss.laser_node.monitoring, "the laser becomes active (collidable) exactly once the warning blinking ends")
 check(game.boss.laser_node.global_position.is_equal_approx(laser_pos_before_active), "the laser doesn't move between telegraph and active — same volume, just now live")
 check(game.boss.laser_node.get_child(0).visible, "the laser is continuously visible (no more blinking) once active")

 # The OTHER half must remain a real, hazard-free route: UPPER and LOWER
 # bounds partition [0, top] exactly, with no gap and no overlap, so
 # whichever half ISN'T currently selected is guaranteed completely free of
 # this hazard (spec section 12 — never both halves at once).
 var active_upper: bool = game.boss.laser_upper
 var active_bounds: Vector2 = game.boss.laser_half_bounds(active_upper)
 var safe_bounds: Vector2 = game.boss.laser_half_bounds(not active_upper)
 check(is_equal_approx(active_bounds.x, safe_bounds.y) or is_equal_approx(active_bounds.y, safe_bounds.x), "the active half and the safe half share a boundary with no gap and no overlap between them")
 check(is_equal_approx(minf(active_bounds.x, safe_bounds.x), 0.0) and is_equal_approx(maxf(active_bounds.y, safe_bounds.y), current_top), "the two halves together span the entire usable height, from the road up to the current tier's ceiling")

 # A real physics check: standing in the SAFE half is fine even while the
 # laser is fully active in the other half.
 game.rider.position = Vector3(0, (safe_bounds.x + safe_bounds.y) * 0.5, game.boss.laser_node.global_position.z)
 game.rider.velocity = Vector3.ZERO
 game.rider.invincible = 0
 game.rider.armor_charges = 0
 await frames(4)
 check(game.rider.mode != "dead", "standing in the safe half is fine while LASER_PLANE is fully active in the other half")

 # Armor absorbs one laser hit; the same protection window covers the
 # entire 2.0s active duration.
 game.rider.upgrade("armor")
 check(game.rider.armor_charges == 1, "fixture: rider carries one armor charge")
 game.rider.invincible = 0
 game.boss._on_pattern_body_entered(game.rider)
 check(game.rider.mode != "dead" and game.rider.armor_charges == 0, "armor absorbs a laser hit exactly like any other obstacle collision")
 game.boss._on_pattern_body_entered(game.rider)
 game.boss._on_pattern_body_entered(game.rider)
 check(game.rider.mode != "dead" and game.rider.armor_charges == 0, "repeated contact within the same invincibility window is suppressed, not stacked")

 await fixture()
 game.city.practice = false
 advance_boss(DifficultyDirector.CITY_BOSS_START_DISTANCE, CityBoss.INTRO_DURATION + time_to_pattern_start(1) + CityBoss.LASER_TELEGRAPH + 0.2)
 check(game.boss.pattern == "LASER_PLANE" and game.boss.pattern_phase == "ACTIVE", "fixture: laser is live")
 game.rider.armor_charges = 0
 game.rider.invincible = 0
 game.boss._on_pattern_body_entered(game.rider)
 check(game.rider.mode == "dead", "without armor, a laser hit is fatal, same as any other obstacle")

 await fixture()
 game.city.practice = false
 advance_boss(DifficultyDirector.CITY_BOSS_START_DISTANCE, CityBoss.INTRO_DURATION + time_to_pattern_start(1) + CityBoss.LASER_TELEGRAPH + 0.2)
 game.rider.armor_charges = 0
 game.rider.invincible = 0
 game.rider.position = game.boss.laser_node.global_position
 game.rider.velocity = Vector3.ZERO
 await frames(6)
 check(game.rider.mode == "dead", "a real physics overlap with the active laser volume is fatal without armor")

 # ==================================================================
 # Pattern C: ROBOT BARRAGE (replaces DRONE_GATE entirely)
 # ==================================================================
 await fixture()
 game.city.practice = false
 advance_boss(DifficultyDirector.CITY_BOSS_START_DISTANCE, CityBoss.INTRO_DURATION + time_to_pattern_start(2) + 0.2)
 check(game.boss.pattern == "ROBOT_BARRAGE", "the third pattern is ROBOT_BARRAGE (deterministic order; DRONE_GATE is removed)")
 check(game.boss.pattern_phase == "TELEGRAPH", "ROBOT_BARRAGE starts with a telegraph (boss beacon flash) before anything launches")
 check(game.boss.barrage_robots.is_empty(), "no robots exist yet during the telegraph")

 advance_boss(DifficultyDirector.CITY_BOSS_START_DISTANCE, CityBoss.ROBOT_BARRAGE_TELEGRAPH + CityBoss.ROBOT_LAUNCH_TIMES[-1] + 0.2)
 check(game.boss.barrage_robots.size() == 3, "exactly three robots have launched by the end of the scheduled window")
 check(game.boss.barrage_robots.all(func(r: Node3D): return not r.get_meta("hookable", true)), "barrage robots are non-hookable")
 check(game.boss.barrage_robots.all(func(r: Node3D): return r.get_meta("hazard", false)), "barrage robots carry the normal hazard collision meta")
 var xs: Array = game.boss.barrage_robots.map(func(r: Node3D): return r.position.x)
 check(xs[0] != xs[1] and xs[1] != xs[2] and xs[0] != xs[2], "the three robots launch from three distinct X positions (left/center/right)")

 # Straight-line, non-homing: velocity is fixed at launch and never re-aimed.
 var robot: Node3D = game.boss.barrage_robots[0]
 var v: Vector3 = robot.get_meta("velocity")
 check(v.length() > 0.0 and is_equal_approx(v.length(), CityBoss.ROBOT_SPEED), "each robot launches at the configured speed")
 var pos_before: Vector3 = robot.position
 game.rider.position = robot.position + Vector3(80, 80, 80)
 game.boss.update_active_robots(1.0 / 60.0)
 var v_after: Vector3 = robot.get_meta("velocity")
 check(v_after.is_equal_approx(v), "a robot's velocity never changes after launch even if the player moves elsewhere — it does not home")
 check(robot.position.is_equal_approx(pos_before + v * (1.0 / 60.0)), "a robot moves in a straight line at its launch velocity")

 # Direction leads the player's position at launch time, but is not a pure
 # homing re-aim (computed once, from position, not tracked continuously).
 await fixture()
 game.city.practice = false
 game.rider.position = Vector3(0, 20, -100)
 game.rider.velocity = Vector3(5, 0, -10)
 game.boss.rider = game.rider
 game.boss.city = game.city
 game.boss.global_position = Vector3(0, 20, -50)
 game.boss.spawn_robot(0.0)
 check(game.boss.barrage_robots.size() == 1, "fixture: one robot spawned directly")
 var spawned: Node3D = game.boss.barrage_robots[0]
 var expected_target: Vector3 = game.rider.position + game.rider.velocity * CityBoss.ROBOT_LEAD_TIME
 var expected_dir: Vector3 = (expected_target - spawned.position).normalized()
 var actual_velocity: Vector3 = spawned.get_meta("velocity")
 check(actual_velocity.normalized().is_equal_approx(expected_dir), "a robot's initial direction leads the player's position/velocity at launch, then locks")

 # Lifetime cleanup.
 await fixture()
 game.city.practice = false
 game.rider.position = Vector3(0, 20, -100)
 game.boss.rider = game.rider
 game.boss.city = game.city
 game.boss.spawn_robot(0.0)
 var expiring: Node3D = game.boss.barrage_robots[0]
 expiring.set_meta("age", CityBoss.ROBOT_LIFETIME + 1.0)
 game.boss.update_active_robots(1.0 / 60.0)
 check(game.boss.barrage_robots.is_empty(), "a robot past its lifetime is removed from tracking")
 await process_frame # queue_free() only actually frees the node at the next idle/frame boundary
 check(not is_instance_valid(expiring), "the expired robot node itself is freed, not just untracked")

 # Falling far behind the player also triggers early cleanup.
 await fixture()
 game.city.practice = false
 game.rider.position = Vector3(0, 20, -100)
 game.boss.rider = game.rider
 game.boss.city = game.city
 game.boss.spawn_robot(0.0)
 var behind: Node3D = game.boss.barrage_robots[0]
 game.rider.position = behind.global_position + Vector3(0, 0, -100)
 game.boss.update_active_robots(1.0 / 60.0)
 check(game.boss.barrage_robots.is_empty(), "a robot that falls far enough behind the player is cleaned up early, before its full lifetime")
 await process_frame
 check(not is_instance_valid(behind), "the cleaned-up robot node is actually freed")

 # Collision/armor parity, same as every other hazard — approach with real
 # relative motion (mirrors the existing vehicle-collision test convention
 # in tests/run.gd), since a zero-velocity body already exactly overlapping
 # a target at frame 1 doesn't reliably produce a move_and_collide() hit.
 await fixture()
 game.city.practice = false
 game.rider.position = Vector3(0, 20, -100)
 game.boss.rider = game.rider
 game.boss.city = game.city
 game.boss.spawn_robot(0.0)
 var target_robot: Node3D = game.boss.barrage_robots[0]
 game.rider.position = target_robot.global_position + Vector3(0, 0, 3.0)
 game.rider.velocity = Vector3(0, 0, -25)
 game.rider.armor_charges = 0
 game.rider.invincible = 0
 await frames(6)
 check(game.rider.mode == "dead", "colliding with a barrage robot without armor is fatal, same as any obstacle")

 await fixture()
 game.city.practice = false
 game.rider.position = Vector3(0, 20, -100)
 game.boss.rider = game.rider
 game.boss.city = game.city
 game.boss.spawn_robot(0.0)
 var target_robot2: Node3D = game.boss.barrage_robots[0]
 game.rider.upgrade("armor")
 game.rider.position = target_robot2.global_position + Vector3(0, 0, 3.0)
 game.rider.velocity = Vector3(0, 0, -25)
 game.rider.invincible = 0
 await frames(6)
 check(game.rider.mode != "dead" and game.rider.armor_charges == 0, "armor absorbs a barrage robot collision, consuming one charge")

 # ==================================================================
 # Sky Gap / Traffic Surge never overlap the boss encounter or rest area
 # ==================================================================
 var boss_start_index: int = floori(DifficultyDirector.CITY_BOSS_START_DISTANCE / 64.0)
 var rest_end_index: int = floori(DifficultyDirector.rest_area_end_distance() / 64.0)
 var any_event_in_zone: bool = false
 for idx in range(boss_start_index, rest_end_index + 1):
  if DifficultyDirector.event_for_chunk(idx) != DifficultyDirector.EVENT_NONE:
   any_event_in_zone = true
 check(not any_event_in_zone, "no Sky Gap or Traffic Surge chunk ever falls inside the boss encounter or rest area")

 # ==================================================================
 # Boss Clear / cleanup (including any still-flying robots) / no re-trigger
 # ==================================================================
 await fixture()
 game.city.practice = false
 advance_boss(DifficultyDirector.CITY_BOSS_START_DISTANCE, CityBoss.INTRO_DURATION + 0.2)
 advance_boss(DifficultyDirector.city_boss_clear_distance(), 0.0)
 check(game.boss.state == "ESCAPE", "reaching the escape distance moves the boss to ESCAPE")
 check(not is_instance_valid(game.boss.block_node) and not is_instance_valid(game.boss.laser_node) and not is_instance_valid(game.boss.barrage_root), "entering ESCAPE cleans up any pattern in progress, including any still-flying robots")
 advance_boss(DifficultyDirector.city_boss_clear_distance(), CityBoss.ESCAPE_DURATION + 0.2)
 check(game.boss.state == "CLEARED", "the boss reaches CLEARED after the escape retreat duration")
 check(not game.boss.visible, "the boss visual despawns (hidden) once CLEARED")
 for i in range(30):
  advance_boss(DifficultyDirector.city_boss_clear_distance() + 1000.0, 1.0)
 check(game.boss.state == "CLEARED", "CLEARED never re-triggers even far past the clear distance")
 check(not is_instance_valid(game.boss.block_node) and not is_instance_valid(game.boss.laser_node) and not is_instance_valid(game.boss.barrage_root), "no new pattern nodes or robots ever spawn once CLEARED")

 # ==================================================================
 # Independence from Player Progression (mirrors tests/difficulty.gd)
 # ==================================================================
 await fixture()
 game.city.practice = false
 game.rider.upgrade("range")
 game.rider.upgrade("jump")
 game.rider.upgrade("double_jump")
 var tiers_before: Dictionary = game.rider.tiers.duplicate()
 advance_boss(DifficultyDirector.CITY_BOSS_START_DISTANCE + 50.0, 0.5)
 check(game.rider.tiers == tiers_before, "advancing the boss encounter never changes player upgrade tiers")

 # ==================================================================
 # Boss Procedural Stress Test: full encounters run clean, twice, with no leaks.
 # ==================================================================
 for run_index in range(2):
  await fixture()
  game.city.practice = false
  var d: float = DifficultyDirector.CITY_BOSS_START_DISTANCE
  var end_d: float = DifficultyDirector.rest_area_end_distance() + 10.0
  while d < end_d:
   d += 5.0
   game.boss.update(1.0 / 30.0, d, game.rider, game.city)
  for i in range(int(CityBoss.ESCAPE_DURATION * 30.0) + 10):
   game.boss.update(1.0 / 30.0, end_d, game.rider, game.city)
  check(game.boss.state == "CLEARED", "run %d: a full simulated encounter reaches CLEARED without getting stuck" % run_index)
  check(not is_instance_valid(game.boss.block_node) and not is_instance_valid(game.boss.laser_node) and not is_instance_valid(game.boss.barrage_root), "run %d: no pattern nodes or robots remain after a full encounter" % run_index)

 # ==================================================================
 # Real end-to-end integration: Main._physics_process() itself drives the boss.
 # ==================================================================
 await fixture()
 game.city.practice = false
 game.phase = "playing"
 game.distance = DifficultyDirector.CITY_BOSS_START_DISTANCE
 for i in range(5):
  game._physics_process(1.0 / 60.0)
 check(game.boss.state in ["INTRO", "ACTIVE"], "Main._physics_process() itself drives the boss into the encounter once game.distance crosses the threshold")

 # ==================================================================
 # Rest Area
 # ==================================================================
 check(DifficultyDirector.chapter_for_distance(DifficultyDirector.city_boss_clear_distance() + 1.0) == "CITY_REST", "the chapter becomes CITY_REST immediately after the boss clears")
 var rest_index: int = floori((DifficultyDirector.city_boss_clear_distance() + 50.0) / 64.0)
 check(DifficultyDirector.event_for_chunk(rest_index) == DifficultyDirector.EVENT_NONE, "no random City event ever occurs inside the Rest Area")

 await fixture()
 game.city.practice = false
 game.city.apply_height_level(DifficultyDirector.get_city_difficulty(rest_index * 64.0).building_height_level)
 game.city.create_chunk(rest_index)
 var rest_chunk: Node3D = game.city.chunks[rest_index]
 var rest_hazards: Array = rest_chunk.get_children().filter(func(n: Node): return n.get_meta("hazard", false))
 var rest_vehicles: Array = rest_chunk.get_children().filter(func(n: Node): return n.get_meta("vehicle", false))
 check(rest_hazards.is_empty(), "the Rest Area spawns no aerial hazards/police drones")
 check(rest_vehicles.is_empty(), "the Rest Area spawns no vehicles")
 var rest_buildings: Array = rest_chunk.get_children().filter(func(n: Node): return n.get_meta("building", false))
 check(not rest_buildings.is_empty(), "the Rest Area keeps its normal, safe building/road structure")

 check(DifficultyDirector.chapter_for_distance(DifficultyDirector.rest_area_end_distance() + 1.0) == "CITY_COMPLETE", "the chapter becomes CITY_COMPLETE once the Rest Area ends")

 game.rider.position = Vector3(0, 20, rest_chunk.position.z - 8)
 game.rider.velocity = Vector3(0, 0, -10)
 game.rider.mode = "air"
 var start_y: float = game.rider.position.y
 await frames(20)
 check(game.rider.position.y < start_y, "gravity/movement behave normally inside the Rest Area")
 check(game.rider.mode != "dead", "falling through the open Rest Area sky is not itself fatal")

 # ==================================================================
 # Signal Story
 # ==================================================================
 await fixture()
 game.city.practice = false
 check(game.played_signals.is_empty(), "fixture: no signal has played yet")
 game.check_signals()
 check(game.played_signals == [SignalStory.SIGNAL_CITY_START], "the City Start signal plays exactly once, first")
 check(game.signal_text == SignalStory.MESSAGES[SignalStory.SIGNAL_CITY_START], "the displayed subtitle matches the City Start message")

 for i in range(10):
  game.check_signals()
 check(game.played_signals == [SignalStory.SIGNAL_CITY_START], "repeated checks at the same distance never replay or duplicate a signal")
 check(game.phase == "playing", "checking signals never changes/pauses the game phase")

 game.distance = SignalStory.MID_DISTANCE
 game.check_signals()
 check(game.played_signals == [SignalStory.SIGNAL_CITY_START, SignalStory.SIGNAL_CITY_MID], "the Mid signal plays once, in order, once its distance is reached")
 for i in range(10):
  game.check_signals()
 check(game.played_signals.count(SignalStory.SIGNAL_CITY_MID) == 1, "the Mid signal never plays more than once in the same run")

 game.distance = DifficultyDirector.city_boss_clear_distance() + 1.0
 game.check_signals()
 check(game.played_signals.has(SignalStory.SIGNAL_CITY_BOSS_CLEAR), "the Boss Clear / Rest Area signal plays once the chapter reaches CITY_REST")
 for i in range(10):
  game.check_signals()
 check(game.played_signals.count(SignalStory.SIGNAL_CITY_BOSS_CLEAR) == 1, "the Boss Clear signal never plays more than once")
 check(game.played_signals.size() == 3, "all three signals have played, and none more than once, by the end of a run")

 for id in SignalStory.ORDER:
  var english: String = SignalStory.MESSAGES[id]
  game.locale.language = "ko"
  var korean: String = game.locale.text(english)
  check(korean != english, "%s has a Korean localization distinct from the English placeholder" % id)
  game.locale.language = "en"
  check(game.locale.text(english) == english, "%s falls back to the English placeholder when language=en" % id)
 game.locale.language = "ko"

 await runtime_regressions()
 print("CITY_BOSS_RESULT ", checks - failures, "/", checks, " passed; failures=", failures)
 game.free()
 await process_frame
 quit(0 if failures == 0 else 1)

func runtime_regressions() -> void:
 # Exercise Main's real floating-origin branch while each laser and an
 # independently moving robot exist. Isolated boss.update() tests miss it.
 for name in [CityBoss.PATTERN_PATH_BLOCK, CityBoss.PATTERN_LASER_PLANE]:
  await fixture()
  game.city.rebase(2048)
  game.distance = 4095
  game.city.update_chunks(game.distance)
  game.rider.position = Vector3(0, 20, -2048.01)
  game.rider.velocity = Vector3(0, 0, -20)
  game.rider.invincible = 10
  game.boss.rider = game.rider
  game.boss.city = game.city
  game.boss.global_position = game.boss.boss_target_position()
  game.boss.state = CityBoss.STATE_ACTIVE
  game.boss.start_pattern(name)
  game.boss.pattern_phase = CityBoss.PHASE_ACTIVE
  game.boss.phase_timer = 1.0
  game.boss.set_pattern_collision(true)
  game.boss.spawn_robot(0)
  var hazard: Area3D = game.boss.block_node if name == CityBoss.PATTERN_PATH_BLOCK else game.boss.laser_node
  var relative_hazard: Vector3 = hazard.global_position - game.rider.position
  var relative_boss: Vector3 = game.boss.global_position - game.rider.position
  var robot: Node3D = game.boss.barrage_robots[0]
  var relative_robot: Vector3 = robot.global_position - game.rider.position
  game._physics_process(1.0 / 60.0)
  check(is_equal_approx(game.city.origin_offset, 4096), "%s fixture crosses the real 4096m origin boundary" % name)
  check(absf(hazard.global_position.z - game.rider.position.z - relative_hazard.z) < 1.0, "%s keeps its relative Z after Main rebases the world" % name)
  check(absf(game.boss.global_position.z - game.rider.position.z - relative_boss.z) < 1.0, "the visible boss keeps its relative Z after rebasing")
  check(absf(robot.global_position.z - game.rider.position.z - relative_robot.z) < 1.0, "a live barrage robot keeps its relative Z trajectory across rebasing")
  check(hazard.monitoring, "rebasing preserves an active laser's collision state")

 await fixture()
 game.boss.rider = game.rider
 game.boss.city = game.city
 game.boss.global_position = game.boss.boss_target_position()
 for x in CityBoss.ROBOT_LAUNCH_X:
  game.boss.spawn_robot(x)
  var robot: Node3D = game.boss.barrage_robots.back()
  check(robot.global_position.distance_to(game.boss.global_position) < 5.0, "robot %.1f launches from the boss hull, not a random detached height" % x)

 for name in [CityBoss.PATTERN_PATH_BLOCK, CityBoss.PATTERN_LASER_PLANE]:
  game.boss.cleanup_pattern_nodes()
  game.boss.start_pattern(name)
  while game.boss.pattern_phase == CityBoss.PHASE_TELEGRAPH:
   game.boss.update_current_pattern(1.0 / 60.0)
  var active_frames: int = 0
  while game.boss.pattern_phase == CityBoss.PHASE_ACTIVE:
   active_frames += 1
   game.boss.update_current_pattern(1.0 / 60.0)
  check(active_frames == 120, "%s is active for exactly 120 physics ticks at 60Hz (got %d)" % [name, active_frames])

 await fixture()
 game.city.rebase(4096)
 game.city.update_chunks(4700)
 var unsafe_drones: int = 0
 for chunk in game.city.chunks.values():
  for n in chunk.get_children():
   if n.get_meta("hazard", false):
    var distance: float = -n.global_position.z + game.city.origin_offset
    var half_depth: float = n.get_child(1).shape.size.z * 0.5
    if distance + half_depth >= 4700 and distance - half_depth < 5100:
     unsafe_drones += 1
 check(unsafe_drones == 0, "the partial first Rest Area chunk has no overlapping drone hazards")
 check(rest_vehicle_count() == 0, "no vehicle spawns across the exact 4700m Rest Area boundary")
 game.city.update_vehicles(30.0)
 check(rest_vehicle_count() == 0, "traffic from before the Rest Area cannot drive into it")
 game.city.update_chunks(5050)
 var oncoming: Node3D = game.city.spawn_vehicle(game.city.chunks[80], 0, Vector3(-3.4, 0, -20), 1.0)
 check(is_instance_valid(oncoming), "fixture: an oncoming car exists beyond the Rest Area exit")
 game.city.update_vehicles(40.0)
 check(rest_vehicle_count() == 0, "oncoming traffic beyond the Rest Area cannot drive back into it")
 check(game.city.vehicles.all(func(v: Node3D): return is_instance_valid(v) and not v.is_queued_for_deletion()), "retired Rest Area traffic leaves no stale tracking entries")

func rest_vehicle_count() -> int:
 var count: int = 0
 for v in game.city.vehicles:
  var distance: float = -v.global_position.z + game.city.origin_offset
  var half_depth: float = v.get_child(1).shape.size.z * 0.5
  if distance + half_depth >= 4700 and distance - half_depth < 5100:
   count += 1
 return count
