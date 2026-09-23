extends SceneTree
## WASTELAND PHASE W-E runtime QA: real physics, real collision, real wire
## range, real (non-practice) death rule (spec section 59) — full Crawler
## Boss encounter end-to-end: Approach -> Underbody -> Upper Body ->
## Overtake -> CLEARED. Same greedy "nearest reachable hookable surface
## ahead" controller as tools/Wasteland-Event-QA.gd, extended to also
## consider the Crawler's own fixed anchors (LOW_ANCHORS/HIGH_ANCHORS +
## the 6 leg hip joints), recomputed fresh every tick since the Crawler
## itself translates in world space.
const Rules = preload("res://scripts/rules.gd")
const Wasteland = preload("res://scripts/wasteland.gd")
const CrawlerBoss = preload("res://scripts/crawler_boss.gd")

var game: Node3D
var best_progress_z: float = INF
var ticks_without_progress: int = 0
var stuck_events: int = 0
var refire_cooldown: int = 0
var leg_hits: int = 0
var upper_hits: int = 0
var armor_consumed: int = 0
var seen_states: Dictionary = {}
## The currently-targeted anchor, tracked explicitly so arrival can be
## judged against ITS OWN current (possibly moving) position — being
## dragged forward while attached to a Crawler anchor constantly decreases
## the rider's Z even after "arriving", so the old z-only progress check
## alone can never detect "time to grab the NEXT anchor in the chain".
var current_target_local: Vector3 = Vector3.ZERO
var current_target_static_pos: Vector3 = Vector3.ZERO
var current_target_is_crawler: bool = false
var has_current_target: bool = false

func _initialize() -> void:
 run.call_deferred()

func run() -> void:
 game = load("res://scenes/main.tscn").instantiate()
 root.add_child(game)
 game.set_physics_process(false)
 game.set_process(false)
 game.start_run(false)
 await physics_frame

 var boss_start: float = Wasteland.wasteland_boss_start_distance()
 var start_distance: float = boss_start - 250.0
 while start_distance - game.city.origin_offset >= 2048.0:
  game.city.rebase(2048.0)
  game.wasteland.rebase(2048.0)
  game.boss.rebase(2048.0)
  game.crawler.rebase(2048.0)
 game.distance = start_distance
 game.city.update_chunks(start_distance)
 game.wasteland.update_chunks(start_distance)
 await physics_frame
 game.rider.position = Vector3(0, 4, -(start_distance - game.city.origin_offset))
 game.rider.velocity = Vector3(0, -1, -8)
 game.rider.mode = "air"
 # A generous, but real, starting armor buffer — the point of this QA is
 # to prove the ENCOUNTER is traversable with base kit, not to prove a
 # bare-handed bot never grazes a single moving leg. Real death rule stays
 # on: armor absorbs, it doesn't grant invincibility.
 game.rider.armor_charges = 3
 game.rider.tiers.armor = 3
 best_progress_z = game.rider.position.z

 var deadline_msec: int = Time.get_ticks_msec() + 240000
 var ticks: int = 0
 var max_ticks: int = 40000
 var outcome: String = "TICK_LIMIT"
 var armor_before: int = game.rider.armor_charges
 while ticks < max_ticks:
  ticks += 1
  step(1.0 / 60.0)
  seen_states[game.crawler.state] = true
  if game.rider.armor_charges < armor_before:
   armor_consumed += armor_before - game.rider.armor_charges
   armor_before = game.rider.armor_charges
  if game.rider.mode == "dead":
   outcome = "DIED: " + game.death_reason
   break
  if game.crawler.state == CrawlerBoss.STATE_CLEARED:
   outcome = "CLEARED"
   break
  if Time.get_ticks_msec() >= deadline_msec:
   outcome = "TIMEOUT"
   break
  if ticks % 6000 == 0:
   print("CRAWLER_BOSS_QA progress tick=%d distance=%.1f state=%s" % [ticks, game.distance, game.crawler.state])
  await physics_frame

 var success: bool = outcome == "CLEARED"
 print("CRAWLER_BOSS_QA result=%s reason=%s distance=%.1f states=%s armor_consumed=%d stuck_events=%d ticks=%d" % [
  "SUCCESS" if success else "FAILURE", outcome, game.distance, str(seen_states.keys()), armor_consumed, stuck_events, ticks,
 ])
 game.free()
 quit(0 if success else 1)

## Crawler's own fixed-relative-to-root candidate points (LOW/HIGH anchors
## + the 6 leg hip joints) — recomputed every call since the root itself
## moves. Feet are deliberately excluded (non-hookable, spec section 39).
## Each candidate carries its own LOCAL offset too, so the caller can track
## "which anchor is this" independent of the Crawler's own motion.
func crawler_candidates_ahead() -> Array:
 var results: Array[Dictionary] = []
 if game.crawler.state != CrawlerBoss.STATE_INTRO and game.crawler.state != CrawlerBoss.STATE_ACTIVE:
  return results
 var root_pos: Vector3 = game.crawler.global_position
 var points: Array[Vector3] = []
 points.append_array(CrawlerBoss.LOW_ANCHORS)
 points.append_array(CrawlerBoss.HIGH_ANCHORS)
 for config in CrawlerBoss.LEG_CONFIG:
  points.append(Vector3(config.side * CrawlerBoss.LEG_HIP_X, CrawlerBoss.LEG_HIP_Y, config.z))
 for local in points:
  var pos: Vector3 = root_pos + local
  if pos.z >= game.rider.position.z - 1.0:
   continue
  results.append({"pos": pos, "local": local, "is_crawler": true, "dist": game.rider.global_position.distance_to(pos)})
 results.sort_custom(func(a, b): return a.dist < b.dist)
 return results

## Ordinary Wasteland anchors ahead (same logic as Wasteland-Event-QA.gd) —
## still useful for the Approach phase before the Crawler itself is close.
func wasteland_candidates_ahead() -> Array:
 var current_index: int = floori(game.distance / Wasteland.LENGTH)
 var results: Array[Dictionary] = []
 for index in range(current_index - 1, current_index + 5):
  var chain: Dictionary = game.wasteland.anchor_chain(index)
  if not game.wasteland.chunks.has(index):
   game.wasteland.create_chunk(index)
  var chunk_pos: Vector3 = game.wasteland.chunks[index].position
  for route in [Wasteland.ROUTE_LOW, Wasteland.ROUTE_HIGH]:
   for slot in range(Wasteland.ANCHOR_Z.size()):
    var pos: Vector3 = chunk_pos + chain[route][slot]
    if pos.z >= game.rider.position.z - 1.0:
     continue
    results.append({"pos": pos, "local": Vector3.ZERO, "is_crawler": false, "dist": game.rider.global_position.distance_to(pos)})
 results.sort_custom(func(a, b): return a.dist < b.dist)
 return results

func acquire_next() -> bool:
 var candidates: Array = crawler_candidates_ahead()
 candidates.append_array(wasteland_candidates_ahead())
 candidates.sort_custom(func(a, b): return a.dist < b.dist)
 for candidate in candidates:
  var direction: Vector3 = (candidate.pos - game.rider.position).normalized()
  var selection: Dictionary = game.city.manual_target(game.rider.position, game.rider.position, direction, game.rider.reach(), game.rider.get_rid())
  if selection.get("valid", false):
   game.rider.fire_manual(selection, -1)
   current_target_is_crawler = candidate.is_crawler
   if candidate.is_crawler:
    current_target_local = candidate.local
   else:
    current_target_static_pos = candidate.pos
   has_current_target = true
   return true
 print("DEBUG acquire_next FAILED — no valid candidate among %d, rider=%s y=%.1f" % [candidates.size(), game.rider.global_position, game.rider.position.y])
 return false

## Where the currently-targeted anchor actually is RIGHT NOW — for a
## Crawler anchor this moves every tick with the Crawler itself; an
## ordinary Wasteland anchor is static, so its stored position is exact.
func current_target_world() -> Vector3:
 if current_target_is_crawler:
  return game.crawler.global_position + current_target_local
 return current_target_static_pos

func step(delta: float) -> void:
 game.rider.simulate(delta, 0.0, 1.0)
 if game.rider.mode == "dead":
  return
 game.distance = Rules.progress(game.distance, game.rider.position.z, game.city.origin_offset)
 game.city.update_chunks(game.distance, game.rider.anchor)
 game.wasteland.update_chunks(game.distance, game.rider.anchor)
 game.wasteland.update_events(delta, game.distance)
 game.crawler.update(delta, game.distance, game.rider, game.wasteland)
 game.city.update_vehicles(delta)
 if game.rider.position.z < -2048:
  game.city.rebase(2048)
  game.wasteland.rebase(2048)
  game.boss.rebase(2048)
  game.crawler.rebase(2048)
  game.rider.position.z += 2048
  best_progress_z += 2048

 if refire_cooldown > 0:
  refire_cooldown -= 1
 if game.rider.position.z < best_progress_z - 0.1:
  best_progress_z = game.rider.position.z
  ticks_without_progress = 0
 else:
  ticks_without_progress += 1

 var need_new_target: bool = not is_instance_valid(game.rider.anchor)
 # "Arrived" is judged against the CURRENT target's own live position, not
 # by z-progress alone — a Crawler anchor keeps dragging the rider forward
 # at the Crawler's own speed for as long as it's attached, which would
 # otherwise look like permanent "progress" and mask that this specific
 # anchor has already been fully closed out and it's time for the next one
 # in the chain.
 # "Arrived" only counts once the CURRENT wire has actually locked on and
 # reeled in close (hook_connected + a short rope) — checking raw 3D
 # distance alone fired true for most of a still-IN-FLIGHT hook's own
 # short flight toward a nearby target, causing fire_manual() to cancel
 # and re-fire every single tick (release_wire() runs before a replacement
 # is even confirmed reachable) and eventually strand the rider mid-air
 # with no wire at all — a real bug this harness had, not a Crawler issue.
 if not need_new_target and has_current_target and game.rider.hook_connected and game.rider.rope_length <= 5.0:
  if game.rider.global_position.distance_to(current_target_world()) < 9.0:
   need_new_target = true
 if not need_new_target and ticks_without_progress > 0 and ticks_without_progress % 90 == 0 and refire_cooldown == 0:
  need_new_target = true
  game.rider.jump()
  refire_cooldown = 30
 if need_new_target:
  acquire_next()

 if ticks_without_progress >= 900:
  stuck_events += 1
  print("CRAWLER_BOSS_QA STUCK rider=%s crawler_state=%s (no forward progress for 30s) — nudging past" % [game.rider.position, game.crawler.state])
  ticks_without_progress = 0
  best_progress_z = game.rider.position.z
  game.rider.position.z -= 15.0
  game.rider.velocity = Vector3(0, 2, -10)
  game.rider.release_wire()
  game.rider.mode = "air"
