extends SceneTree
## WASTELAND PHASE W-A: chunk-generation foundation for Wire Rush's second
## chapter. Never touches Player Progression (XP/Level/Upgrade/Synergy —
## see tests/upgrades.gd) or City's own gameplay (Boss/Sky Gap/Traffic
## Surge/Signal Story — see tests/city_boss.gd/city_completion.gd, both
## re-verified unchanged by this phase's own full validation run).
const Rules = preload("res://scripts/rules.gd")
const DifficultyDirector = preload("res://scripts/difficulty_director.gd")
const Wasteland = preload("res://scripts/wasteland.gd")
var game: Node3D
var checks: int = 0
var failures: int = 0

func _initialize() -> void:
 create_timer(40).timeout.connect(func():
  push_error("Wasteland tests timed out")
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

func structures(chunk: Node3D) -> Array:
 return chunk.get_children().filter(func(n: Node): return n.get_meta("hookable", false))

func hazards(chunk: Node3D) -> Array:
 return chunk.get_children().filter(func(n: Node): return n.get_meta("hazard", false))

func find_archetype_index(archetype: String, min_index: int, search_span: int = 60) -> int:
 for idx in range(min_index, min_index + search_span):
  if game.wasteland.archetype_for(idx) == archetype:
   return idx
 return -1

func run() -> void:
 game = load("res://scenes/main.tscn").instantiate()
 root.add_child(game)
 game.set_physics_process(false)
 game.set_process(false)

 # ==================================================================
 # Chapter boundary (spec section 5) — reuses City's own existing
 # rest_area_end_distance() as the single source of truth, no new literal.
 # ==================================================================
 check(DifficultyDirector.wasteland_start_distance() == DifficultyDirector.rest_area_end_distance(), "Wasteland begins exactly where City's own Rest Area ends (single shared constant, no duplicated literal)")
 check(not DifficultyDirector.is_wasteland(DifficultyDirector.wasteland_start_distance() - 1.0), "one meter before the boundary is still City")
 check(DifficultyDirector.is_wasteland(DifficultyDirector.wasteland_start_distance()), "the boundary distance itself is already Wasteland")
 check(DifficultyDirector.chapter_for_distance(DifficultyDirector.wasteland_start_distance() + 1.0) == "CITY_COMPLETE", "City's own chapter_for_distance() contract is untouched by adding Wasteland (still CITY_COMPLETE, not a new enum value)")

 # ==================================================================
 # 1. CITY COMPLETE 후 WASTELAND 진입 — a real practice run (the only mode
 # that doesn't hard-stop at City's own completion screen) naturally
 # streams Wasteland chunks once distance crosses the boundary, through
 # the exact same per-tick Main._physics_process() path every other chunk
 # already streams through.
 # ==================================================================
 await fixture()
 game.city.practice = true
 var pre_distance: float = DifficultyDirector.wasteland_start_distance() - 100.0
 # Real gameplay would already have rebased twice by 5000m of travel — apply
 # the same rebases here so the fixture's raw Z matches what a real run
 # would actually have at this distance (see Main._physics_process()'s own
 # `if rider.position.z < -2048` trigger). Skipping this made the very
 # first tick(s) below trigger two rebases back to back instead of zero,
 # which is a fixture bug, not a real gameplay issue.
 while pre_distance - game.city.origin_offset >= 2048.0:
  game.city.rebase(2048.0)
  game.wasteland.rebase(2048.0)
  game.boss.rebase(2048.0)
 # Stream real chunk/road collision in before placing the rider on it (a
 # freshly-created CollisionShape3D isn't queryable/solid until the physics
 # server flushes at least one frame — same as any other direct-position
 # fixture elsewhere in this suite).
 game.city.update_chunks(pre_distance)
 game.wasteland.update_chunks(pre_distance)
 await physics_frame
 # Airborne with real forward+down velocity (same fixture convention used
 # elsewhere in this codebase's own wire-segment QA): momentum alone carries
 # it across the boundary without needing synthesized key input.
 game.rider.position = Vector3(0, 20.0, -(pre_distance - game.city.origin_offset))
 game.rider.velocity = Vector3(0, -1.0, -14.0)
 game.rider.mode = "air"
 game.distance = pre_distance
 for i in range(400):
  game._physics_process(1.0 / 60.0)
  if game.phase != "playing":
   break
 check(game.phase == "playing", "practice keeps playing straight through the City/Wasteland boundary (ended at phase=%s, reason=%s, distance=%.1f)" % [game.phase, game.death_reason, game.distance])
 check(not game.wasteland.chunks.is_empty(), "Wasteland chunks have started streaming once distance is near/through the boundary")
 check(game.wasteland.chunks.keys().all(func(idx: int): return idx >= Wasteland.first_chunk_index()), "every Wasteland chunk index is at/after Wasteland's own first_chunk_index()")

 # ==================================================================
 # 2. Wasteland chunk 생성
 # ==================================================================
 await fixture()
 var first: int = Wasteland.first_chunk_index()
 game.wasteland.create_chunk(first)
 check(game.wasteland.chunks.has(first), "a Wasteland chunk can be created directly at its own first index")
 check(game.wasteland.chunks[first].get_child_count() > 0, "a fresh Wasteland chunk actually contains generated content, not an empty node")
 check(game.wasteland.chunks[first].position.z == -first * Wasteland.LENGTH, "a freshly-created chunk (no rebase yet) sits at the expected raw world Z")

 # ==================================================================
 # 3-7. Archetypes
 # ==================================================================
 await fixture()
 var powerline_idx: int = find_archetype_index(Wasteland.ARCHETYPE_POWERLINE, first)
 check(powerline_idx >= 0, "fixture: a POWERLINE chunk exists within the search span")
 game.wasteland.create_chunk(powerline_idx)
 var powerline_structs: Array = structures(game.wasteland.chunks[powerline_idx])
 check(powerline_structs.size() >= 1, "POWERLINE generates at least one hookable structure (the tower)")
 check(powerline_structs.any(func(n: Node3D): return n.get_meta("building", false)), "the power tower is safe to touch (tagged building, like City's own walls)")

 var highway_idx: int = find_archetype_index(Wasteland.ARCHETYPE_BROKEN_HIGHWAY, first)
 check(highway_idx >= 0, "fixture: a BROKEN_HIGHWAY chunk exists within the search span")
 game.wasteland.create_chunk(highway_idx)
 var highway_structs: Array = structures(game.wasteland.chunks[highway_idx])
 check(highway_structs.size() >= 2, "BROKEN_HIGHWAY generates the elevated deck plus at least one support column, all wireable")

 var ruins_idx: int = find_archetype_index(Wasteland.ARCHETYPE_INDUSTRIAL_RUINS, first)
 check(ruins_idx >= 0, "fixture: an INDUSTRIAL_RUINS chunk exists within the search span")
 game.wasteland.create_chunk(ruins_idx)
 check(not structures(game.wasteland.chunks[ruins_idx]).is_empty(), "INDUSTRIAL_RUINS generates a real wireable frame")

 var open_idx: int = find_archetype_index(Wasteland.ARCHETYPE_OPEN_WASTELAND, first)
 check(open_idx >= 0, "fixture: an OPEN_WASTELAND chunk exists within the search span")
 game.wasteland.create_chunk(open_idx)
 check(structures(game.wasteland.chunks[open_idx]).size() >= 1, "OPEN_WASTELAND is never a truly empty chunk — at least one structure always exists")

 var cliff_idx: int = find_archetype_index(Wasteland.ARCHETYPE_CLIFF_FRAME, first)
 check(cliff_idx >= 0, "fixture: a CLIFF_FRAME chunk exists within the search span")
 game.wasteland.create_chunk(cliff_idx)
 var cliff_structs: Array = structures(game.wasteland.chunks[cliff_idx])
 check(cliff_structs.size() >= 2, "CLIFF_FRAME generates both the cliff mass and its mounted artificial scaffold")

 # ==================================================================
 # 8-10. City-only suppression: police drones, traffic, Sky Gap
 # ==================================================================
 await fixture()
 for idx in range(first, first + 40):
  game.wasteland.create_chunk(idx)
 var any_hazard: bool = false
 for idx in game.wasteland.chunks.keys():
  if not hazards(game.wasteland.chunks[idx]).is_empty():
   any_hazard = true
 check(not any_hazard, "no police drone / robot hazard ever spawns in ordinary Wasteland chunks")

 await fixture()
 game.city.practice = true
 game.rider.position = Vector3(0, 5, -(DifficultyDirector.wasteland_start_distance() + 200.0))
 game.rider.velocity = Vector3.ZERO
 game.rider.mode = "ground"
 game.distance = DifficultyDirector.wasteland_start_distance() + 200.0
 game.city.update_chunks(game.distance)
 game.wasteland.update_chunks(game.distance)
 var wasteland_vehicles: int = 0
 for v in game.city.vehicles:
  if is_instance_valid(v) and -v.global_position.z + game.city.origin_offset >= DifficultyDirector.wasteland_start_distance():
   wasteland_vehicles += 1
 check(wasteland_vehicles == 0, "no City traffic vehicle exists anywhere inside Wasteland's own distance range")

 var any_sky_route_sign: bool = false
 for idx in game.wasteland.chunks.keys():
  for label in game.wasteland.chunks[idx].find_children("*", "Label3D", true, false):
   if label.get_meta("route_text", "") == "SKY ROUTE":
    any_sky_route_sign = true
 check(not any_sky_route_sign, "Wasteland never generates a City Sky Gap route sign — the event itself is City.event_for_chunk()-only and Wasteland never calls it")

 # ==================================================================
 # 11. Chunk cleanup
 # ==================================================================
 await fixture()
 game.city.practice = true
 var far: float = DifficultyDirector.wasteland_start_distance() + 800.0
 game.wasteland.update_chunks(far)
 var stale_index: int = Wasteland.first_chunk_index()
 game.wasteland.create_chunk(stale_index)
 var stale_chunk: Node3D = game.wasteland.chunks[stale_index]
 game.wasteland.update_chunks(far)
 check(not game.wasteland.chunks.has(stale_index), "a Wasteland chunk far behind the player is dropped from tracking")
 await process_frame
 check(not is_instance_valid(stale_chunk), "the dropped Wasteland chunk node is actually freed, not just untracked")

 # ==================================================================
 # 12. Origin shift compatibility
 # ==================================================================
 await fixture()
 var idx_for_rebase: int = Wasteland.first_chunk_index() + 2
 game.wasteland.create_chunk(idx_for_rebase)
 var pos_before: float = game.wasteland.chunks[idx_for_rebase].position.z
 game.wasteland.rebase(2048.0)
 check(is_equal_approx(game.wasteland.chunks[idx_for_rebase].position.z, pos_before + 2048.0), "rebase() shifts an existing Wasteland chunk's world position by the exact rebase amount")
 check(is_equal_approx(game.wasteland.origin_offset, 2048.0), "rebase() updates Wasteland's own origin_offset")
 var idx_after_rebase: int = idx_for_rebase + 3
 game.wasteland.update_chunks((idx_after_rebase) * Wasteland.LENGTH)
 check(game.wasteland.chunks.has(idx_after_rebase), "new Wasteland chunks still stream in correctly after an origin shift")
 check(is_equal_approx(game.wasteland.chunks[idx_after_rebase].position.z, -idx_after_rebase * Wasteland.LENGTH + 2048.0), "a chunk created AFTER rebase() already accounts for the shifted origin_offset")

 # ==================================================================
 # 13-14. City regression: City's own generation is untouched by Wasteland
 # existing (a direct check here, in addition to the full unmodified
 # tests/city_boss.gd + tests/city_completion.gd + tests/difficulty.gd
 # suites already re-run clean against these changes).
 # ==================================================================
 await fixture()
 game.city.practice = false
 game.city.apply_height_level(0)
 game.city.create_chunk(10)
 var city_hazards: Array = hazards(game.city.chunks[10])
 check(not city_hazards.is_empty(), "City still generates its own ordinary aerial hazards (police drones) at a normal City distance")
 check(city_hazards.all(func(n: Node3D): return n.get_meta("hookable", false)), "City's own drones are still hookable, unaffected by Wasteland's addition")
 game.city.update_chunks(5000.0)
 check(game.city.chunks.keys().all(func(idx: int): return idx < Wasteland.first_chunk_index()), "City's own non-practice stream still never reaches into Wasteland's chunk index range")

 print("WASTELAND_RESULT ", checks - failures, "/", checks, " passed; failures=", failures)
 game.free()
 await process_frame
 quit(0 if failures == 0 else 1)
