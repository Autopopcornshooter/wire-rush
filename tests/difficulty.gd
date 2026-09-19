extends SceneTree
## PHASE B: World Progression (Difficulty Director + City Events). Tests here
## never touch XP/Level/pending_upgrades/upgrade selection/synergy — those
## are PHASE A's Player Progression, covered by tests/upgrades.gd. This file
## verifies the two systems stay independent (see the "independence" block
## below) as much as it verifies the world-side behavior itself.
const Rules = preload("res://scripts/rules.gd")
const DifficultyDirector = preload("res://scripts/difficulty_director.gd")
var game: Node3D
var checks: int = 0
var failures: int = 0

func _initialize() -> void:
 create_timer(40).timeout.connect(func():
  push_error("Difficulty tests timed out")
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

func buildings(chunk: Node3D) -> Array:
 return chunk.get_children().filter(func(n: Node): return n.get_meta("building", false))

func hazards(chunk: Node3D) -> Array:
 return chunk.get_children().filter(func(n: Node): return n.get_meta("hazard", false))

func vehicles_in(chunk: Node3D) -> Array:
 return chunk.get_children().filter(func(n: Node): return n.get_meta("vehicle", false))

## Mirrors what City.update_chunks() does for a single chunk, but scoped to
## exactly one index so tests can pin down a precise chunk's own distance
## tier instead of relying on update_chunks()'s multi-chunk lookahead batch.
func build_chunk_at_own_tier(index: int) -> void:
 game.city.apply_height_level(DifficultyDirector.get_city_difficulty(index * 64.0).building_height_level)
 game.city.create_chunk(index)

func find_event_index(event: String, min_index: int, search_span: int = 600) -> int:
 for idx in range(min_index, min_index + search_span):
  if DifficultyDirector.event_for_chunk(idx) == event:
   return idx
 return -1

func run() -> void:
 game = load("res://scenes/main.tscn").instantiate()
 root.add_child(game)
 game.set_physics_process(false)
 game.set_process(false)

 # ==================================================================
 # Difficulty Director: pure functions
 # ==================================================================
 check(DifficultyDirector.tier_for_distance(0) == 0, "0m is TIER 0")
 check(DifficultyDirector.tier_for_distance(499) == 0, "499m is still TIER 0")
 check(DifficultyDirector.tier_for_distance(500) == 1, "500m enters TIER 1")
 check(DifficultyDirector.tier_for_distance(999) == 1, "999m is still TIER 1")
 check(DifficultyDirector.tier_for_distance(1000) == 2, "1000m enters TIER 2")
 check(DifficultyDirector.tier_for_distance(1999) == 2, "1999m is still TIER 2")
 check(DifficultyDirector.tier_for_distance(2000) == 3, "2000m enters TIER 3 (late City)")
 check(DifficultyDirector.tier_for_distance(50000) == 3, "TIER 3 is the final tier; distance keeps increasing tier no further")

 var p0: Dictionary = DifficultyDirector.get_city_difficulty(0)
 var p1: Dictionary = DifficultyDirector.get_city_difficulty(600)
 var p2: Dictionary = DifficultyDirector.get_city_difficulty(1500)
 var p3: Dictionary = DifficultyDirector.get_city_difficulty(2500)
 check(p0.building_height_level == 0 and p1.building_height_level == 1 and p2.building_height_level == 2 and p3.building_height_level == 3, "building_height_level rises 0 -> 1 -> 2 -> 3 across the four tiers")
 check(p0.aerial_obstacle_count_bonus <= p1.aerial_obstacle_count_bonus and p1.aerial_obstacle_count_bonus <= p2.aerial_obstacle_count_bonus and p2.aerial_obstacle_count_bonus <= p3.aerial_obstacle_count_bonus, "aerial obstacle density never decreases as distance increases")
 check(p0.vehicle_gap_scale > p1.vehicle_gap_scale and p1.vehicle_gap_scale >= p2.vehicle_gap_scale and p2.vehicle_gap_scale >= p3.vehicle_gap_scale, "vehicle gap scale shrinks (traffic gets denser) as distance increases")
 check(DifficultyDirector.get_city_difficulty(600) == DifficultyDirector.get_city_difficulty(600), "the profile is a pure function: the same distance always yields the same profile")
 check(DifficultyDirector.get_city_difficulty(1999).sky_gap_eligible == false and DifficultyDirector.get_city_difficulty(2000).sky_gap_eligible == true, "Sky Gap eligibility begins exactly at 2000m")

 # ==================================================================
 # Independence: Player Progression vs World Progression
 # ==================================================================
 await fixture()
 game.city.practice = false
 var tier_before_upgrades: int = DifficultyDirector.tier_for_distance(2500)
 game.rider.upgrade("range")
 game.rider.upgrade("reel")
 game.rider.upgrade("jump")
 game.rider.upgrade("double_jump")
 game.rider.upgrade("skates")
 game.rider.upgrade("armor")
 check(DifficultyDirector.tier_for_distance(2500) == tier_before_upgrades, "picking every kind of player upgrade never changes the distance-based City tier")
 check(game.city.high_level == 0, "picking player upgrades never touches City.high_level (Building Height is world-only now)")
 var tiers_before_world_progress: Dictionary = game.rider.tiers.duplicate()
 var synergies_before: Dictionary = game.rider.active_synergies.duplicate()
 game.city.update_chunks(2500)
 check(game.rider.tiers == tiers_before_world_progress, "advancing world difficulty (update_chunks at 2500m) never changes player upgrade tiers")
 check(game.rider.active_synergies == synergies_before, "advancing world difficulty never changes active synergies")

 # ==================================================================
 # City Progression: Building Height / obstacle density, new-chunk-only
 # ==================================================================
 await fixture()
 game.city.practice = false
 build_chunk_at_own_tier(2) # 128m -> TIER 0
 var tier0_building: Node3D = buildings(game.city.chunks[2])[0]
 check(is_equal_approx(tier0_building.get_meta("height"), float(tier0_building.get_meta("base_height")) + Rules.BUILDING_BONUS[0]), "a TIER 0 chunk's building uses building_height_level 0")
 var tier0_hazards: Array = hazards(game.city.chunks[2])
 check(tier0_hazards.size() == 4, "a TIER 0 chunk's aerial obstacle count matches the historical baseline (4)")

 build_chunk_at_own_tier(8) # 512m -> TIER 1
 var tier1_building: Node3D = buildings(game.city.chunks[8])[0]
 check(is_equal_approx(tier1_building.get_meta("height"), float(tier1_building.get_meta("base_height")) + Rules.BUILDING_BONUS[1]), "a TIER 1 chunk's building uses building_height_level 1")
 check(is_equal_approx(tier0_building.get_meta("height"), float(tier0_building.get_meta("base_height")) + Rules.BUILDING_BONUS[0]), "an already-existing TIER 0 chunk is unaffected by a later TIER 1 chunk being created")

 build_chunk_at_own_tier(20) # 1280m -> TIER 2
 var tier2_building: Node3D = buildings(game.city.chunks[20])[0]
 check(is_equal_approx(tier2_building.get_meta("height"), float(tier2_building.get_meta("base_height")) + Rules.BUILDING_BONUS[2]), "a TIER 2 chunk's building uses building_height_level 2")
 var tier2_hazards: Array = hazards(game.city.chunks[20])
 check(tier2_hazards.size() > 5, "a TIER 2 chunk spawns more aerial obstacles than the TIER 0/1 baseline (4/5)")
 var tier2_ys: Array = tier2_hazards.map(func(n: Node3D): return n.position.y)
 check(tier2_ys.min() < 10.0, "TIER 2 still keeps a low route (obstacles present near the historical low band)")
 check(tier2_ys.max() > 30.0, "TIER 2 also reaches into a higher band than TIER 0/1 (vertical space genuinely expands)")

 build_chunk_at_own_tier(40) # inside a Sky Gap window but TIER 3 either way -> 2560m
 var tier3_hazards: Array = hazards(game.city.chunks[40])
 var tier3_ys: Array = tier3_hazards.map(func(n: Node3D): return n.position.y)
 check(tier3_ys.min() < 10.0, "TIER 3 still keeps a low route even at the highest Building Height tier")

 # Real update_chunks() (the gameplay entry point) also drives this correctly.
 await fixture()
 game.city.practice = false
 game.city.update_chunks(0)
 var early_created_building: Node3D = buildings(game.city.chunks[2])[0] if not buildings(game.city.chunks[2]).is_empty() else null
 check(early_created_building != null and is_equal_approx(early_created_building.get_meta("height"), float(early_created_building.get_meta("base_height"))), "update_chunks(0) streams in TIER 0 chunks")
 game.city.update_chunks(2500)
 var found_tier3_building: bool = false
 for idx in game.city.chunks.keys():
  if idx * 64.0 >= 2000.0:
   var found: Array = buildings(game.city.chunks[idx])
   if not found.is_empty() and is_equal_approx(found[0].get_meta("height"), float(found[0].get_meta("base_height")) + Rules.BUILDING_BONUS[3]):
    found_tier3_building = true
 check(found_tier3_building, "update_chunks(2500) streams in newly-created chunks at building_height_level 3")

 # ==================================================================
 # Sky Gap
 # ==================================================================
 for idx in range(0, 32):
  check(DifficultyDirector.event_for_chunk(idx) != DifficultyDirector.EVENT_SKY_GAP, "chunk %d (before 2000m) is never Sky Gap" % idx)
 check(DifficultyDirector.event_for_chunk(32) == DifficultyDirector.EVENT_SKY_GAP, "chunk 32 (>=2000m, same period pattern PHASE A already shipped) is Sky Gap eligible")

 await fixture()
 game.city.practice = false
 build_chunk_at_own_tier(32)
 check(buildings(game.city.chunks[32]).is_empty(), "a Sky Gap chunk has no playable buildings")
 var sky_gap_hazards: Array = hazards(game.city.chunks[32])
 check(sky_gap_hazards.size() > 0, "a Sky Gap chunk still has wireable aerial targets")
 check(sky_gap_hazards.all(func(n: Node3D): return n.get_meta("hookable", false)), "every Sky Gap target is hookable")
 check(vehicles_in(game.city.chunks[32]).is_empty(), "a Sky Gap chunk never spawns vehicles")

 # A full 3-chunk span (40-42, all fully past 2000m) plus one normal chunk
 # on each side, for entrance/exit + full traversability.
 await fixture()
 game.city.practice = false
 for idx in range(38, 44):
  build_chunk_at_own_tier(idx)
 check(DifficultyDirector.event_for_chunk(39) == DifficultyDirector.EVENT_NONE, "chunk 39 (entrance) is a normal chunk")
 check(DifficultyDirector.event_for_chunk(40) == DifficultyDirector.EVENT_SKY_GAP and DifficultyDirector.event_for_chunk(41) == DifficultyDirector.EVENT_SKY_GAP and DifficultyDirector.event_for_chunk(42) == DifficultyDirector.EVENT_SKY_GAP, "chunks 40-42 form one full 3-chunk Sky Gap span")
 check(DifficultyDirector.event_for_chunk(43) == DifficultyDirector.EVENT_NONE, "chunk 43 (exit) is a normal chunk")
 check(not buildings(game.city.chunks[39]).is_empty(), "entrance chunk keeps its normal buildings")
 check(not buildings(game.city.chunks[43]).is_empty(), "the ordinary building-lined layout returns immediately after the span (exit)")

 var span_points: Array[Vector3] = []
 for idx in range(38, 44):
  for haz in hazards(game.city.chunks[idx]):
   span_points.append(haz.global_position)
 span_points.sort_custom(func(a: Vector3, b: Vector3): return a.z > b.z)
 check(span_points.size() > 10, "fixture sanity: plenty of aerial targets exist across the whole span")
 var worst_gap: float = 0.0
 for i in range(span_points.size() - 1):
  worst_gap = maxf(worst_gap, span_points[i].distance_to(span_points[i + 1]))
 check(worst_gap <= game.city.MAX_BASE_TRAVERSAL_GAP, "every consecutive aerial target across the entrance/Sky-Gap/exit span (including the boundary hops) stays within base wire reach (worst gap %.1fm)" % worst_gap)
 var entrance_gap: float = hazards(game.city.chunks[39])[-1].global_position.distance_to(hazards(game.city.chunks[40])[0].global_position)
 check(entrance_gap <= game.city.MAX_BASE_TRAVERSAL_GAP, "the Sky Gap entrance hop (last normal-chunk target to first Sky-Gap target) is reachable (%.1fm)" % entrance_gap)
 var exit_gap: float = hazards(game.city.chunks[42])[-1].global_position.distance_to(hazards(game.city.chunks[43])[0].global_position)
 check(exit_gap <= game.city.MAX_BASE_TRAVERSAL_GAP, "the Sky Gap exit hop (last Sky-Gap target to first normal-chunk target) is reachable (%.1fm)" % exit_gap)

 # Cooldown: scan a wide range and verify every Sky Gap run is <=3 chunks and
 # every gap between runs is >=7 chunks (the built-in 10-chunk period minus
 # the 3-chunk length) — a general property, not just one hand-picked example.
 var runs: Array = []
 var run_start: int = -1
 for idx in range(0, 150):
  var is_gap: bool = DifficultyDirector.event_for_chunk(idx) == DifficultyDirector.EVENT_SKY_GAP
  if is_gap and run_start == -1:
   run_start = idx
  elif not is_gap and run_start != -1:
   runs.append([run_start, idx - 1])
   run_start = -1
 if run_start != -1:
  runs.append([run_start, 149])
 check(runs.size() >= 2, "fixture sanity: at least two Sky Gap runs occur within the first 150 chunks")
 for r in runs:
  check(r[1] - r[0] + 1 <= DifficultyDirector.SKY_GAP_LENGTH_CHUNKS, "a Sky Gap run never exceeds its configured length")
 for i in range(runs.size() - 1):
  var cooldown_chunks: int = runs[i + 1][0] - runs[i][1] - 1
  check(cooldown_chunks >= DifficultyDirector.SKY_GAP_PERIOD_CHUNKS - DifficultyDirector.SKY_GAP_LENGTH_CHUNKS, "consecutive Sky Gap events never repeat back-to-back — a cooldown of normal chunks always separates them")

 # Chunk cleanup around a Sky Gap span works the same as anywhere else.
 await fixture()
 game.city.practice = false
 game.city.update_chunks(2500)
 check(game.city.chunks.has(40), "fixture sanity: the Sky Gap span is actually streamed in at distance 2500m")
 game.city.update_chunks(2500 + 2048)
 check(not game.city.chunks.has(40), "streaming far past a Sky Gap span eventually frees it like any other chunk")
 check(game.city.chunks.size() <= 8, "chunk cleanup keeps the resident chunk count bounded after passing a Sky Gap span")

 # ==================================================================
 # Traffic Surge
 # ==================================================================
 var surge_index: int = find_event_index(DifficultyDirector.EVENT_TRAFFIC_SURGE, 8)
 check(surge_index != -1, "a Traffic Surge window exists somewhere past TIER 1's start")
 var normal_index: int = -1
 for idx in range(8, 8 + 600):
  if DifficultyDirector.event_for_chunk(idx) == DifficultyDirector.EVENT_NONE and DifficultyDirector.tier_for_distance(idx * 64.0) == DifficultyDirector.tier_for_distance(surge_index * 64.0):
   normal_index = idx
   break
 check(normal_index != -1, "fixture sanity: a same-tier normal (non-event) chunk exists for density comparison")

 await fixture()
 game.city.practice = false
 build_chunk_at_own_tier(surge_index)
 build_chunk_at_own_tier(normal_index)
 var surge_vehicles: Array = vehicles_in(game.city.chunks[surge_index])
 var normal_vehicles: Array = vehicles_in(game.city.chunks[normal_index])
 check(surge_vehicles.size() > normal_vehicles.size(), "a Traffic Surge chunk spawns more vehicles than a normal chunk at the same tier")
 check(game.city.CAR_MODELS.size() == 5, "Traffic Surge reuses the existing five car models — no new vehicle assets")
 check(surge_vehicles.all(func(v: Node3D): return not v.get_meta("hookable", false)), "Traffic Surge vehicles remain non-wireable")
 check(surge_vehicles.all(func(v: Node3D): return (v.position.x > 0) == (float(v.get_meta("dir")) < 0)), "right-hand traffic lane/direction pairing holds during a Traffic Surge")

 # No initial overlap: for every same-lane pair, their Z-extents (from each
 # vehicle's own BoxShape3D) must not intersect.
 var overlap_found: bool = false
 for i in range(surge_vehicles.size()):
  for j in range(i + 1, surge_vehicles.size()):
   var a: Node3D = surge_vehicles[i]
   var b: Node3D = surge_vehicles[j]
   var shape_a: BoxShape3D = a.get_child(1).shape
   var shape_b: BoxShape3D = b.get_child(1).shape
   var x_overlap: bool = absf(a.global_position.x - b.global_position.x) < (shape_a.size.x + shape_b.size.x) * 0.5
   var z_overlap: bool = absf(a.global_position.z - b.global_position.z) < (shape_a.size.z + shape_b.size.z) * 0.5
   if x_overlap and z_overlap:
    overlap_found = true
 check(not overlap_found, "no two Traffic-Surge-spawned vehicles overlap at spawn time")

 # Vehicle collision rule is unchanged: same armor-consumes-one-charge /
 # no-armor-is-fatal behavior as any other vehicle (PHASE A's own vehicle
 # collision test, replayed against a Traffic-Surge-spawned car specifically).
 check(surge_vehicles.size() > 0, "fixture sanity: a surge vehicle exists to collide with")
 var target_car: Node3D = surge_vehicles[0]
 game.rider.position = target_car.global_position + Vector3(0, 0.9, 2.6)
 game.rider.velocity = Vector3(0, 0, -25)
 game.rider.armor_charges = 0
 game.rider.invincible = 0
 await frames(6)
 check(game.rider.mode == "dead", "colliding with a Traffic-Surge-spawned vehicle without armor is still fatal")

 await fixture()
 game.city.practice = false
 build_chunk_at_own_tier(surge_index)
 var target_car2: Node3D = vehicles_in(game.city.chunks[surge_index])[0]
 game.rider.upgrade("armor")
 game.rider.position = target_car2.global_position + Vector3(0, 0.9, 2.6)
 game.rider.velocity = Vector3(0, 0, -25)
 game.rider.invincible = 0
 await frames(6)
 check(game.rider.mode != "dead" and game.rider.armor_charges == 0, "armor still absorbs a collision with a Traffic-Surge-spawned vehicle, consuming one charge")

 # Ends and returns to normal: a chunk right after a surge window uses the
 # tier's ordinary gap scale again, not the surge's.
 var after_surge_index: int = -1
 for idx in range(surge_index + 1, surge_index + DifficultyDirector.TRAFFIC_SURGE_PERIOD_CHUNKS + 1):
  if DifficultyDirector.event_for_chunk(idx) == DifficultyDirector.EVENT_NONE:
   after_surge_index = idx
   break
 check(after_surge_index != -1, "fixture sanity: a normal chunk follows the surge window")
 await fixture()
 game.city.practice = false
 build_chunk_at_own_tier(after_surge_index)
 check(true, "a chunk after a Traffic Surge window generates normally without error") # generation itself not throwing is the real assertion here

 # ==================================================================
 # Procedural stress test: 0m -> 3000m+, sequential streaming
 # ==================================================================
 await fixture()
 game.city.practice = false
 var reached: float = 0.0
 for step in range(52):
  reached = step * 64.0
  game.city.update_chunks(reached, game.rider.anchor)
  check(game.city.chunks.size() <= 10, "chunk count stays bounded while streaming (distance %.0fm)" % reached)
  check(game.city.vehicles.size() < 400, "vehicle count does not run away while streaming (distance %.0fm)" % reached)
  check(game.city.vehicles.all(func(v: Node3D): return is_instance_valid(v)), "no stale/invalid vehicle references while streaming (distance %.0fm)" % reached)
 check(reached >= 3000.0, "the stress test actually reached past 3000m")
 var late_buildings_found: bool = false
 var late_hazards: Array[Vector3] = []
 for idx in game.city.chunks.keys():
  if idx * 64.0 >= 2000.0:
   if not buildings(game.city.chunks[idx]).is_empty():
    late_buildings_found = true
   for haz in hazards(game.city.chunks[idx]):
    late_hazards.append(haz.global_position)
 check(late_buildings_found, "ordinary buildings still generate somewhere past 2000m during long-distance streaming (Sky Gap never gets permanently stuck on)")
 late_hazards.sort_custom(func(a: Vector3, b: Vector3): return a.z > b.z)
 var stress_worst_gap: float = 0.0
 for i in range(late_hazards.size() - 1):
  stress_worst_gap = maxf(stress_worst_gap, late_hazards[i].distance_to(late_hazards[i + 1]))
 check(stress_worst_gap <= game.city.MAX_BASE_TRAVERSAL_GAP, "no impossible target spacing appears anywhere in the currently-loaded late-City chunks (worst gap %.1fm)" % stress_worst_gap)

 print("DIFFICULTY_RESULT ", checks - failures, "/", checks, " passed; failures=", failures)
 game.free()
 await process_frame
 quit(0 if failures == 0 else 1)
