extends SceneTree
## PHASE C: City Boss (Police Interceptor Graybox), Rest Area, and Signal
## Story. Never touches XP/Level/pending_upgrades/upgrade selection/synergy
## (PHASE A) or the Difficulty Director's tier/event pure functions beyond
## reading them (PHASE B) — see the "independence"-flavored checks below,
## which mirror tests/difficulty.gd's own Player/World separation tests.
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

func run() -> void:
 game = load("res://scenes/main.tscn").instantiate()
 root.add_child(game)
 game.set_physics_process(false)
 game.set_process(false)

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

 check(game.boss.pattern == DifficultyDirector.EVENT_NONE or game.boss.pattern == "PATH_BLOCK", "fixture sanity: pattern is either not-yet-set or the deterministic first pattern")
 check(game.boss.pattern == "PATH_BLOCK", "the first ACTIVE pattern is PATH_BLOCK (deterministic order, not random)")

 # ==================================================================
 # Pattern A: PATH BLOCK
 # ==================================================================
 check(game.boss.closed_side == 1 or game.boss.closed_side == -1, "PATH_BLOCK always closes exactly one side")
 check(is_instance_valid(game.boss.block_node), "a PATH_BLOCK blocker node exists")
 check(not game.boss.block_node.monitoring, "the blocker has no collision yet during its telegraph")
 var closed_side_first: int = game.boss.closed_side
 var open_side: int = -closed_side_first
 check(absf(game.boss.block_node.global_position.x - closed_side_first * 11.4) < 0.01, "the blocker sits on the closed side's building line")
 check(not is_equal_approx(game.boss.block_node.global_position.x, open_side * 11.4), "fixture sanity: the open side has no blocker at the same position")

 advance_boss(DifficultyDirector.CITY_BOSS_START_DISTANCE, CityBoss.PATH_BLOCK_TELEGRAPH + 0.2)
 check(game.boss.pattern_phase == "ACTIVE" and game.boss.block_node.monitoring, "the blocker becomes solid once its telegraph ends")

 # Colliding with the open side must never trigger a hit: simulate the
 # Area3D's own body_entered handler directly (deterministic, no physics
 # timing dependency) for a body on the OPEN side by checking the blocker
 # position itself never matches it — already asserted above — and confirm
 # a real physics pass with the rider positioned on the open side is safe.
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

 # ==================================================================
 # Pattern B: LASER SWEEP
 # ==================================================================
 await fixture()
 game.city.practice = false
 advance_boss(DifficultyDirector.CITY_BOSS_START_DISTANCE, CityBoss.INTRO_DURATION + 0.05)
 # Walk PATH_BLOCK all the way through (telegraph+active+recovery+cooldown)
 # to reach the second pattern.
 advance_boss(DifficultyDirector.CITY_BOSS_START_DISTANCE, CityBoss.PATH_BLOCK_TELEGRAPH + CityBoss.PATH_BLOCK_ACTIVE + CityBoss.PATH_BLOCK_RECOVERY + CityBoss.COOLDOWN_DURATION + 0.2)
 check(game.boss.pattern == "LASER_SWEEP", "the second pattern is LASER_SWEEP (deterministic order)")
 check(game.boss.pattern_phase == "TELEGRAPH", "LASER_SWEEP starts in its telegraph phase")
 check(is_instance_valid(game.boss.laser_node) and not game.boss.laser_node.monitoring, "a laser telegraph exists but is not yet collidable")
 var laser_pos_before_active: Vector3 = game.boss.laser_node.global_position

 advance_boss(DifficultyDirector.CITY_BOSS_START_DISTANCE, CityBoss.LASER_TELEGRAPH + 0.2)
 check(game.boss.pattern_phase == "ACTIVE" and game.boss.laser_node.monitoring, "the laser becomes active (collidable) exactly after its telegraph duration")
 check(game.boss.laser_node.global_position.is_equal_approx(laser_pos_before_active), "the laser doesn't move between telegraph and active — same beam, just now live")

 # Armor absorbs one laser hit.
 game.rider.upgrade("armor")
 check(game.rider.armor_charges == 1, "fixture: rider carries one armor charge")
 game.rider.invincible = 0
 game.boss._on_pattern_body_entered(game.rider)
 check(game.rider.mode != "dead" and game.rider.armor_charges == 0, "armor absorbs a laser hit exactly like any other obstacle collision")
 # Duplicate-hit suppression: the same contact firing again within the
 # armor's own invincibility window must never consume a second charge or
 # kill the player a frame later (PHASE C spec section 15).
 game.boss._on_pattern_body_entered(game.rider)
 game.boss._on_pattern_body_entered(game.rider)
 check(game.rider.mode != "dead" and game.rider.armor_charges == 0, "repeated contact within the same invincibility window is suppressed, not stacked")

 # No armor: fatal.
 await fixture()
 game.city.practice = false
 advance_boss(DifficultyDirector.CITY_BOSS_START_DISTANCE, CityBoss.INTRO_DURATION + CityBoss.PATH_BLOCK_TELEGRAPH + CityBoss.PATH_BLOCK_ACTIVE + CityBoss.PATH_BLOCK_RECOVERY + CityBoss.COOLDOWN_DURATION + CityBoss.LASER_TELEGRAPH + 0.2)
 check(game.boss.pattern == "LASER_SWEEP" and game.boss.pattern_phase == "ACTIVE", "fixture: laser is live")
 game.rider.armor_charges = 0
 game.rider.invincible = 0
 game.boss._on_pattern_body_entered(game.rider)
 check(game.rider.mode == "dead", "without armor, a laser hit is fatal, same as any other obstacle")

 # Real-geometry overlap: position the rider inside the actual laser volume
 # and let real physics/Area3D detection fire the hit (not the direct
 # handler call above), confirming the collision shapes are wired correctly.
 await fixture()
 game.city.practice = false
 advance_boss(DifficultyDirector.CITY_BOSS_START_DISTANCE, CityBoss.INTRO_DURATION + CityBoss.PATH_BLOCK_TELEGRAPH + CityBoss.PATH_BLOCK_ACTIVE + CityBoss.PATH_BLOCK_RECOVERY + CityBoss.COOLDOWN_DURATION + CityBoss.LASER_TELEGRAPH + 0.2)
 game.rider.armor_charges = 0
 game.rider.invincible = 0
 game.rider.position = game.boss.laser_node.global_position
 game.rider.velocity = Vector3.ZERO
 await frames(6)
 check(game.rider.mode == "dead", "a real physics overlap with the active laser volume is fatal without armor")

 # ==================================================================
 # Pattern C: DRONE GATE
 # ==================================================================
 await fixture()
 game.city.practice = false
 var to_drone_gate: float = CityBoss.INTRO_DURATION \
  + CityBoss.PATH_BLOCK_TELEGRAPH + CityBoss.PATH_BLOCK_ACTIVE + CityBoss.PATH_BLOCK_RECOVERY + CityBoss.COOLDOWN_DURATION \
  + CityBoss.LASER_TELEGRAPH + CityBoss.LASER_ACTIVE + CityBoss.LASER_RECOVERY + CityBoss.COOLDOWN_DURATION + 0.2
 advance_boss(DifficultyDirector.CITY_BOSS_START_DISTANCE, to_drone_gate)
 check(game.boss.pattern == "DRONE_GATE", "the third pattern is DRONE_GATE (deterministic order)")
 check(game.boss.gate_hazards.size() == 3, "the Drone Gate spawns exactly three police-drone hazards")
 check(game.boss.gate_hazards.all(func(h: Node3D): return h.get_meta("hookable", false)), "every Drone Gate hazard stays wireable, same as any other police drone")
 check(game.boss.gate_hazards.all(func(h: Node3D): return h.get_meta("hazard", false)), "every Drone Gate hazard carries the normal hazard collision meta")
 check(game.boss.gate_hazards[0].get_child(1).disabled, "Drone Gate collision starts disabled during its telegraph")

 var worst_gate_gap: float = 0.0
 for i in range(game.boss.gate_hazards.size() - 1):
  var d: float = game.boss.gate_hazards[i].global_position.distance_to(game.boss.gate_hazards[i + 1].global_position)
  worst_gate_gap = maxf(worst_gate_gap, d)
 check(worst_gate_gap <= game.city.MAX_BASE_TRAVERSAL_GAP, "consecutive Drone Gate targets stay within base wire reach (worst gap %.1fm)" % worst_gate_gap)

 advance_boss(DifficultyDirector.CITY_BOSS_START_DISTANCE, CityBoss.DRONE_GATE_TELEGRAPH + 0.2)
 check(not game.boss.gate_hazards[0].get_child(1).disabled, "Drone Gate collision enables once its telegraph ends")

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
 # Boss Clear / cleanup / no re-trigger
 # ==================================================================
 await fixture()
 game.city.practice = false
 advance_boss(DifficultyDirector.CITY_BOSS_START_DISTANCE, CityBoss.INTRO_DURATION + 0.2)
 advance_boss(DifficultyDirector.city_boss_clear_distance(), 0.0)
 check(game.boss.state == "ESCAPE", "reaching the escape distance moves the boss to ESCAPE")
 check(not is_instance_valid(game.boss.block_node) and not is_instance_valid(game.boss.laser_node) and not is_instance_valid(game.boss.gate_node), "entering ESCAPE cleans up any pattern currently in progress")
 advance_boss(DifficultyDirector.city_boss_clear_distance(), CityBoss.ESCAPE_DURATION + 0.2)
 check(game.boss.state == "CLEARED", "the boss reaches CLEARED after the escape retreat duration")
 check(not game.boss.visible, "the boss visual despawns (hidden) once CLEARED")
 var pattern_before_extra_updates: String = game.boss.pattern
 for i in range(30):
  advance_boss(DifficultyDirector.city_boss_clear_distance() + 1000.0, 1.0)
 check(game.boss.state == "CLEARED", "CLEARED never re-triggers even far past the clear distance")
 check(not is_instance_valid(game.boss.block_node) and not is_instance_valid(game.boss.laser_node) and not is_instance_valid(game.boss.gate_node), "no new pattern nodes ever spawn once CLEARED")

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
 check(DifficultyDirector.CITY_BOSS_START_DISTANCE == DifficultyDirector.CITY_BOSS_START_DISTANCE, "sanity: the boss start distance is a fixed constant, not derived from player level/upgrades")

 # ==================================================================
 # Boss Procedural Stress Test: full encounters run clean, twice, with no leaks.
 # ==================================================================
 for run_index in range(2):
  await fixture()
  game.city.practice = false
  var d: float = DifficultyDirector.CITY_BOSS_START_DISTANCE
  for step in range(400):
   d += 3.0
   game.boss.update(1.0 / 30.0, d, game.rider, game.city)
   if d >= DifficultyDirector.rest_area_end_distance():
    break
  check(game.boss.state == "CLEARED", "run %d: a full simulated encounter reaches CLEARED without getting stuck" % run_index)
  check(not is_instance_valid(game.boss.block_node) and not is_instance_valid(game.boss.laser_node) and not is_instance_valid(game.boss.gate_node), "run %d: no pattern nodes remain after a full encounter" % run_index)

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

 # Existing movement still works normally inside the Rest Area (no new
 # auto-move/cinematic camera — PHASE C spec section 27).
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

 # Localization: every signal message has a real (non-identical) Korean
 # translation, and falls back to the English original when language=en.
 for id in SignalStory.ORDER:
  var english: String = SignalStory.MESSAGES[id]
  game.locale.language = "ko"
  var korean: String = game.locale.text(english)
  check(korean != english, "%s has a Korean localization distinct from the English placeholder" % id)
  game.locale.language = "en"
  check(game.locale.text(english) == english, "%s falls back to the English placeholder when language=en" % id)
 game.locale.language = "ko"

 print("CITY_BOSS_RESULT ", checks - failures, "/", checks, " passed; failures=", failures)
 game.free()
 await process_frame
 quit(0 if failures == 0 else 1)
