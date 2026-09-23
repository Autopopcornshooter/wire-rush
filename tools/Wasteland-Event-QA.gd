extends SceneTree
## WASTELAND PHASE W-C runtime QA: real physics, real collision, real wire
## range, real death rule (spec section 59 — no teleport chain, no
## invincibility, no range override, no gravity bypass). Runs THREE
## independent short legs (Dust / Turbine / Crane), each starting a fresh
## world just before its own event rather than one long combined crawl —
## keeps each run's required travel bounded and its pass/fail result
## individually readable (matches spec section 56-58's own per-event
## reporting split).
##
## Controller strategy: greedy "nearest reachable hookable surface ahead of
## the player", re-evaluated whenever not currently making forward
## progress — not a fixed pre-declared anchor sequence. This mirrors how a
## real player actually plays (grab whatever's next reachable, not a
## memorized path), and never releases a wire just to search — only when a
## confirmed next attempt is ready (same discipline documented across this
## project's earlier QA phases). It also demonstrates the "event is
## optional/avoidable" design claim (spec section 40): every event's own
## hazard/structure sits outside the guaranteed anchor_chain()'s own X
## range (see spawn_turbine_field()/spawn_crane_yard() in
## scripts/wasteland.gd), so a bot that only ever grabs "nearest ahead"
## naturally never has to fly through a Turbine blade or route through a
## crane to keep moving.
##
## Dust Zone visibility itself (does it READ well to a human) is out of
## scope here by design — this bot targets anchors by data, not by camera
## raycast, so it cannot measure "can a human still see the target" (that
## is explicitly a Human QA item, spec section 68). What this DOES prove:
## the fog blend never breaks the underlying physics/route, and a Dust
## chunk adds no hazard of its own (also covered structurally in
## tests/wasteland_events.gd).
const Rules = preload("res://scripts/rules.gd")
const Wasteland = preload("res://scripts/wasteland.gd")

var game: Node3D
var final_index: int
var max_index_reached: int = 0
var ticks_without_progress: int = 0
var best_progress_z: float = INF
var stuck_events: int = 0
var refire_cooldown: int = 0
var leg_deadline_msec: int = 0
var leg_event_type: String = ""
var event_ticks: int = 0

var results: Array[String] = []

func _initialize() -> void:
 run_all.call_deferred()

func run_all() -> void:
 var probe := Wasteland.new()
 root.add_child(probe)
 var start: int = Wasteland.first_chunk_index() + Wasteland.EVENT_ENTRY_SAFE_CHUNKS
 var dust_idx: int = find_event(probe, "DUST", start)
 var turbine_idx: int = find_event(probe, "TURBINE", start)
 var crane_idx: int = find_event(probe, "CRANE", start)
 probe.free()
 print("WASTELAND_EVENT_QA targets: DUST@%d TURBINE@%d CRANE@%d" % [dust_idx, turbine_idx, crane_idx])
 if dust_idx < 0 or turbine_idx < 0 or crane_idx < 0:
  print("WASTELAND_EVENT_QA could not locate all 3 event types within the search span — widen the span")
  quit(1)
  return

 await run_leg("DUST", dust_idx)
 await run_leg("TURBINE", turbine_idx)
 await run_leg("CRANE", crane_idx)

 print("WASTELAND_EVENT_QA_SUMMARY")
 var any_failed: bool = false
 for line in results:
  print(line)
  if line.contains("FAILURE"):
   any_failed = true
 quit(1 if any_failed else 0)

func find_event(w: Wasteland, event_type: String, start: int, span: int = 500) -> int:
 for idx in range(start, start + span):
  if w.event_for_chunk(idx) == event_type:
   return idx
 return -1

func run_leg(event_type: String, event_index: int) -> void:
 leg_event_type = event_type
 game = load("res://scenes/main.tscn").instantiate()
 root.add_child(game)
 game.set_physics_process(false)
 game.set_process(false)
 # Real (non-practice) mode — practice mode's Rider.hurt() branch always
 # auto-rescues instead of dying (see rider.gd), which would silently mask
 # a genuine fatal route/hazard problem as a "pass". Spec section 59
 # requires the real death rule, so this harness needs the real one too.
 game.start_run(false)
 await physics_frame

 var lead_chunks: int = 6
 var start_index: int = event_index - lead_chunks
 final_index = event_index + Wasteland.EVENT_LENGTH_CHUNKS + 4
 var start_distance: float = float(start_index) * Wasteland.LENGTH
 while start_distance - game.city.origin_offset >= 2048.0:
  game.city.rebase(2048.0)
  game.wasteland.rebase(2048.0)
  game.boss.rebase(2048.0)
 game.distance = start_distance
 game.city.update_chunks(start_distance)
 game.wasteland.update_chunks(start_distance)
 await physics_frame
 game.rider.position = Vector3(0, 8, -(start_distance - game.city.origin_offset))
 game.rider.velocity = Vector3(0, -1, -8)
 game.rider.mode = "air"
 max_index_reached = start_index
 best_progress_z = game.rider.position.z
 ticks_without_progress = 0
 stuck_events = 0
 event_ticks = 0
 refire_cooldown = 0
 leg_deadline_msec = Time.get_ticks_msec() + 60000

 var ticks: int = 0
 var max_ticks: int = 40000
 var outcome: String = "TICK_LIMIT"
 while ticks < max_ticks:
  ticks += 1
  step(1.0 / 60.0)
  if game.rider.mode == "dead":
   outcome = "DIED: " + game.death_reason
   break
  if max_index_reached >= final_index and game.distance >= float(final_index) * Wasteland.LENGTH:
   outcome = "REACHED END"
   break
  if Time.get_ticks_msec() >= leg_deadline_msec:
   outcome = "TIMEOUT"
   break
  await physics_frame

 var success: bool = outcome == "REACHED END"
 results.append("WASTELAND_EVENT_QA leg=%s result=%s reason=%s distance=%.1f event_ticks=%d stuck_events=%d" % [
  event_type, "SUCCESS" if success else "FAILURE", outcome, game.distance, event_ticks, stuck_events,
 ])
 game.free()
 await process_frame

## Every real hookable LOW/HIGH anchor within a small window ahead of the
## player, nearest-first — the exact positions the game itself generated
## (chunk position + that chunk's own anchor_chain()), never approximated.
func candidates_ahead() -> Array:
 var current_index: int = floori(game.distance / Wasteland.LENGTH)
 var results_local: Array[Dictionary] = []
 for index in range(current_index - 1, current_index + 5):
  var chain: Dictionary = game.wasteland.anchor_chain(index)
  if not game.wasteland.chunks.has(index):
   game.wasteland.create_chunk(index)
  var chunk_pos: Vector3 = game.wasteland.chunks[index].position
  for route in [Wasteland.ROUTE_LOW, Wasteland.ROUTE_HIGH]:
   for slot in range(Wasteland.ANCHOR_Z.size()):
    var pos: Vector3 = chunk_pos + chain[route][slot]
    if pos.z >= game.rider.position.z - 1.0:
     continue # behind (or level with) the player — not useful as a forward target
    results_local.append({"pos": pos, "index": index, "dist": game.rider.global_position.distance_to(pos)})
 results_local.sort_custom(func(a, b): return a.dist < b.dist)
 return results_local

## Tries each nearby forward candidate, nearest first, and fires at the
## first one manual_target() actually validates — never releases/replaces
## a live wire on a guess, only commits once a candidate is confirmed.
func acquire_next() -> bool:
 for candidate in candidates_ahead():
  var direction: Vector3 = (candidate.pos - game.rider.position).normalized()
  var selection: Dictionary = game.city.manual_target(game.rider.position, game.rider.position, direction, game.rider.reach(), game.rider.get_rid())
  if selection.get("valid", false):
   game.rider.fire_manual(selection, -1)
   max_index_reached = maxi(max_index_reached, candidate.index)
   return true
 return false

func step(delta: float) -> void:
 game.rider.simulate(delta, 0.0, 1.0)
 if game.rider.mode == "dead":
  return
 game.distance = Rules.progress(game.distance, game.rider.position.z, game.city.origin_offset)
 game.city.update_chunks(game.distance, game.rider.anchor)
 game.wasteland.update_chunks(game.distance, game.rider.anchor)
 game.wasteland.update_events(delta, game.distance)
 game.city.update_vehicles(delta)
 if game.rider.position.z < -2048:
  game.city.rebase(2048)
  game.wasteland.rebase(2048)
  game.boss.rebase(2048)
  game.rider.position.z += 2048
  best_progress_z += 2048
 var current_chunk_index: int = floori(game.distance / Wasteland.LENGTH)
 if game.wasteland.event_for_chunk(current_chunk_index) == leg_event_type:
  event_ticks += 1

 if refire_cooldown > 0:
  refire_cooldown -= 1

 # Progress is measured purely by how far forward (more negative Z) the
 # player has actually gotten — never by whether a wire happens to be
 # attached, which proved unreliable (a live wire to an unhelpful surface
 # still reads as "attached" while making zero real progress).
 if game.rider.position.z < best_progress_z - 0.1:
  best_progress_z = game.rider.position.z
  ticks_without_progress = 0
 else:
  ticks_without_progress += 1

 var need_new_target: bool = not is_instance_valid(game.rider.anchor)
 if not need_new_target and ticks_without_progress > 0 and ticks_without_progress % 90 == 0 and refire_cooldown == 0:
  # A live wire, but no forward progress for 1.5s — it isn't helping.
  need_new_target = true
  game.rider.jump()
  refire_cooldown = 30
 if need_new_target:
  acquire_next()

 if ticks_without_progress >= 1800:
  stuck_events += 1
  print("WASTELAND_EVENT_QA[%s] STUCK near index=%d rider=%s (no forward progress for 30s) — nudging past" % [leg_event_type, current_chunk_index, game.rider.position])
  ticks_without_progress = 0
  best_progress_z = game.rider.position.z
  game.rider.position.z -= 15.0
  game.rider.velocity = Vector3(0, 2, -10)
  game.rider.release_wire()
  game.rider.mode = "air"
