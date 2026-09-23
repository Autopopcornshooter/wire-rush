extends SceneTree
## WASTELAND PHASE W-C: Dust Zone / Turbine Field / Crane Yard event tests.
## Complements tests/wasteland.gd (W-A structure/suppression) and
## tests/wasteland_routes.gd (W-B route system) rather than duplicating
## them — this file is event-system-only. Events are purely additive on
## top of the already-validated LOW/HIGH anchor_chain() (see
## scripts/wasteland.gd's own doc comment on the Event Director), so most
## "is the base route still safe" checks here just re-run
## validate_chunk_route() on an event chunk and expect it unchanged.
const Rules = preload("res://scripts/rules.gd")
const DifficultyDirector = preload("res://scripts/difficulty_director.gd")
const Wasteland = preload("res://scripts/wasteland.gd")
var checks: int = 0
var failures: int = 0

func _initialize() -> void:
 create_timer(60).timeout.connect(func():
  push_error("Wasteland event tests timed out")
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

## First chunk index at/after which an event can ever occur.
func first_event_index(w: Wasteland) -> int:
 return Wasteland.first_chunk_index() + Wasteland.EVENT_ENTRY_SAFE_CHUNKS

## Scans forward from `start` and returns the first chunk index whose event
## is exactly `event_type`, or -1 if none found within `span`.
func find_event_index(w: Wasteland, event_type: String, start: int, span: int = 400) -> int:
 for idx in range(start, start + span):
  if w.event_for_chunk(idx) == event_type:
   return idx
 return -1

func run() -> void:
 var w := Wasteland.new()
 root.add_child(w)
 var first: int = first_event_index(w)

 # ==================================================================
 # 23-25. Event system shape (checked first — everything else below
 # depends on actually finding real DUST/TURBINE/CRANE chunks to test).
 # ==================================================================
 var normal_count: int = 0
 var dust_count: int = 0
 var turbine_count: int = 0
 var crane_count: int = 0
 var consecutive_event_chunks: int = 0
 var worst_consecutive: int = 0
 var stress_span: int = 400
 var event_bounds: Array = [] # [{"start":int,"end":int,"type":String}]
 var idx: int = first
 while idx < first + stress_span:
  var event: String = w.event_for_chunk(idx)
  if event == Wasteland.EVENT_NONE:
   normal_count += 1
   consecutive_event_chunks = 0
  else:
   consecutive_event_chunks += 1
   if event == Wasteland.EVENT_DUST:
    dust_count += 1
   elif event == Wasteland.EVENT_TURBINE:
    turbine_count += 1
   elif event == Wasteland.EVENT_CRANE:
    crane_count += 1
  worst_consecutive = maxi(worst_consecutive, consecutive_event_chunks)
  if event != Wasteland.EVENT_NONE:
   var window: Dictionary = w.event_window_for_index(idx)
   if event_bounds.is_empty() or event_bounds[-1].start != window.start_index:
    event_bounds.append({"start": window.start_index, "end": window.end_index, "type": event})
  idx += 1
 var event_total: int = dust_count + turbine_count + crane_count
 print("WASTELAND_EVENT_DISTRIBUTION span=%d normal=%d dust=%d turbine=%d crane=%d" % [stress_span, normal_count, dust_count, turbine_count, crane_count])

 # 25. deterministic distribution: normal chunks outnumber event chunks,
 # and calling event_for_chunk() twice for the same index is stable.
 check(normal_count > event_total, "normal Wasteland chunks outnumber event chunks over a %d-chunk span (%d normal vs %d event)" % [stress_span, normal_count, event_total])
 check(w.event_for_chunk(first) == w.event_for_chunk(first), "event_for_chunk() is deterministic — same index, same result")
 var repeat_w := Wasteland.new()
 var mismatch: bool = false
 for check_idx in range(first, first + 60):
  if repeat_w.event_for_chunk(check_idx) != w.event_for_chunk(check_idx):
   mismatch = true
 check(not mismatch, "a brand-new Wasteland instance resolves the exact same event schedule (pure function of index, no hidden state)")
 repeat_w.free()

 # 23. no overlap: no two triggered windows ever share a chunk index.
 var overlap_found: bool = false
 for i in range(event_bounds.size() - 1):
  if event_bounds[i].end > event_bounds[i + 1].start:
   overlap_found = true
 check(not overlap_found, "no two Wasteland event windows ever overlap")

 # 24. cooldown: every event window is followed by real normal chunks
 # before the next one (>= EVENT_PERIOD_CHUNKS - EVENT_LENGTH_CHUNKS).
 var min_gap: int = 999999
 for i in range(event_bounds.size() - 1):
  min_gap = mini(min_gap, event_bounds[i + 1].start - event_bounds[i].end)
 check(event_bounds.size() < 2 or min_gap >= 2, "consecutive Wasteland events are always separated by at least a couple of normal chunks (worst gap found: %d)" % min_gap)
 check(worst_consecutive <= Wasteland.EVENT_LENGTH_CHUNKS, "no run of consecutive event chunks ever exceeds one event window's own length (no back-to-back different events)")

 var dust_idx: int = find_event_index(w, Wasteland.EVENT_DUST, first)
 var turbine_idx: int = find_event_index(w, Wasteland.EVENT_TURBINE, first)
 var crane_idx: int = find_event_index(w, Wasteland.EVENT_CRANE, first)
 check(dust_idx >= 0, "fixture: a DUST event window exists within the search span")
 check(turbine_idx >= 0, "fixture: a TURBINE event window exists within the search span")
 check(crane_idx >= 0, "fixture: a CRANE event window exists within the search span")

 # ==================================================================
 # 1. Dust event deterministic selection (index-only, no chunk needed)
 # ==================================================================
 check(w.event_for_chunk(dust_idx) == Wasteland.EVENT_DUST, "the located DUST index really resolves to EVENT_DUST")
 check(w.event_for_chunk(dust_idx - 1 - Wasteland.EVENT_PERIOD_CHUNKS) != Wasteland.EVENT_DUST or w.event_window_for_index(dust_idx - 1 - Wasteland.EVENT_PERIOD_CHUNKS).start_index != w.event_window_for_index(dust_idx).start_index, "a different window index resolves independently, not by coincidence")

 # ==================================================================
 # 2-4. Dust enter/exit/reset — pure dust_intensity()/apply_environment()
 # ==================================================================
 var dust_window: Dictionary = w.event_window_for_index(dust_idx)
 var dust_start_dist: float = float(dust_window.start_index) * Wasteland.LENGTH
 var dust_end_dist: float = float(dust_window.end_index) * Wasteland.LENGTH
 var dust_mid_dist: float = (dust_start_dist + dust_end_dist) * 0.5
 check(w.dust_intensity(dust_start_dist - Wasteland.DUST_FADE_MARGIN * 4.0) == 0.0, "well before a Dust Zone, intensity is exactly 0 (event scope stays local)")
 check(w.dust_intensity(dust_mid_dist) == 1.0, "deep inside a Dust Zone, intensity is fully active")
 check(w.dust_intensity(dust_end_dist + Wasteland.DUST_FADE_MARGIN * 4.0) == 0.0, "well after a Dust Zone, intensity is back to exactly 0 (reset)")
 var entering: float = w.dust_intensity(dust_start_dist - Wasteland.DUST_FADE_MARGIN * 0.5)
 check(entering > 0.0 and entering < 1.0, "entering a Dust Zone is a smooth fade, not a hard cut (%.2f mid-fade)" % entering)
 var exiting: float = w.dust_intensity(dust_end_dist + Wasteland.DUST_FADE_MARGIN * 0.5)
 check(exiting > 0.0 and exiting < 1.0, "exiting a Dust Zone is a smooth fade, not a hard cut (%.2f mid-fade)" % exiting)

 # PHASE W-D: outside a Dust Zone, apply_environment() settles on
 # Wasteland's OWN ambient baseline (a deliberate warmer/hazier blend from
 # City's raw fog — see wasteland_ambient_intensity()), not City's literal
 # 0.003. The ambient blend is itself still ramping in over its own
 # WASTELAND_AMBIENT_FADE_CHUNKS window (spec section 47), so the "before"
 # and "after" checkpoints (192m apart) can legitimately expect slightly
 # different ambient baselines — each expected value is computed at its
 # OWN checkpoint's distance, the same way apply_environment() itself does,
 # rather than assuming a single shared baseline.
 var env := Environment.new()
 env.fog_density = 0.003
 env.fog_light_color = Color("233d58")
 env.fog_height_density = 0.05
 w.bind_environment(env)
 var before_dist: float = dust_start_dist - Wasteland.DUST_FADE_MARGIN * 4.0
 var after_dist: float = dust_end_dist + Wasteland.DUST_FADE_MARGIN * 4.0
 var expected_before: float = lerpf(0.003, Wasteland.WASTELAND_AMBIENT_FOG_DENSITY, w.wasteland_ambient_intensity(before_dist))
 var expected_after: float = lerpf(0.003, Wasteland.WASTELAND_AMBIENT_FOG_DENSITY, w.wasteland_ambient_intensity(after_dist))
 w.apply_environment(before_dist)
 check(is_equal_approx(env.fog_density, expected_before), "apply_environment() leaves fog at Wasteland's own ambient baseline outside any Dust Zone")
 w.apply_environment(dust_mid_dist)
 check(env.fog_density > expected_before, "apply_environment() raises fog density inside a Dust Zone, above Wasteland's own ambient baseline")
 var dust_peak_density: float = env.fog_density
 w.apply_environment(after_dist)
 check(is_equal_approx(env.fog_density, expected_after), "apply_environment() restores exactly Wasteland's own ambient baseline after the Dust Zone ends (spec section 18/53: no leftover state)")

 # ==================================================================
 # 5-6. Dust route/physics safety
 # ==================================================================
 var dust_route: Dictionary = w.validate_chunk_route(dust_idx)
 check(dust_route.valid, "the guaranteed base route through a DUST event chunk is still valid (events never touch anchor_chain())")
 w.create_chunk(dust_idx)
 var dust_chunk: Node3D = w.chunks[dust_idx]
 var dust_hazards: Array = dust_chunk.get_children().filter(func(n: Node): return n.get_meta("hazard", false))
 check(dust_hazards.is_empty(), "a Dust Zone introduces zero physics hazards of its own — visibility pressure only, no wind/gravity/wire modifier")

 # ==================================================================
 # 7-14. Turbine Field
 # ==================================================================
 w.create_chunk(turbine_idx)
 var turbine_chunk: Node3D = w.chunks[turbine_idx]
 var turbine_hookable: Array = turbine_chunk.get_children().filter(func(n: Node): return n.get_meta("hookable", false))
 check(turbine_hookable.size() >= 2, "a Turbine Field chunk generates at least one tower + nacelle pair")
 var low_towers: Array = turbine_hookable.filter(func(n: Node): return n.get_meta("route", "") == Wasteland.ROUTE_LOW)
 var high_nacelles: Array = turbine_hookable.filter(func(n: Node): return n.get_meta("route", "") == Wasteland.ROUTE_HIGH)
 check(not low_towers.is_empty(), "Turbine tower(s) are hookable LOW route anchors")
 check(not high_nacelles.is_empty(), "Turbine nacelle(s) are hookable HIGH route anchors")
 var turbine_hubs: Array = turbine_chunk.get_children().filter(func(n: Node): return n is AnimatableBody3D and n.get_meta("hazard", false))
 check(not turbine_hubs.is_empty(), "a Turbine Field chunk generates at least one spinning blade hub")
 var all_hubs_non_hookable: bool = true
 for hub in turbine_hubs:
  if hub.get_meta("hookable", true):
   all_hubs_non_hookable = false
 check(all_hubs_non_hookable, "every blade hub is explicitly non-hookable (spec section 23)")
 var hub: Node3D = turbine_hubs[0]
 var blade_collisions: Array = hub.get_children().filter(func(n: Node): return n is CollisionShape3D and n.shape is BoxShape3D)
 check(blade_collisions.size() == 3, "each blade hub carries 3 real (simple box) collision shapes, one per blade")
 var before_basis: Basis = hub.basis
 w.spinning_hubs = [{"node": hub, "speed": 1.0}]
 w.update_spinning_hubs(1.0)
 check(not hub.basis.is_equal_approx(before_basis), "update_spinning_hubs() actually rotates a registered hub over time")

 var turbine_route: Dictionary = w.validate_chunk_route(turbine_idx)
 check(turbine_route.valid, "the guaranteed base route through a TURBINE event chunk is still valid")
 var turbine_window: Dictionary = w.event_window_for_index(turbine_idx)
 var entrance_route: Dictionary = w.validate_chunk_route(turbine_window.start_index)
 var exit_route: Dictionary = w.validate_chunk_route(turbine_window.end_index - 1)
 check(entrance_route.valid and exit_route.valid, "both the entrance and exit chunks of the Turbine Field window keep a valid base route")

 # ==================================================================
 # 15-22. Crane Yard
 # ==================================================================
 w.create_chunk(crane_idx)
 var crane_chunk: Node3D = w.chunks[crane_idx]
 var crane_hookable: Array = crane_chunk.get_children().filter(func(n: Node): return n.get_meta("hookable", false))
 check(crane_hookable.size() >= 2, "a Crane Yard chunk generates at least one tower + boom pair")
 var crane_low: Array = crane_hookable.filter(func(n: Node): return n.get_meta("route", "") == Wasteland.ROUTE_LOW)
 var crane_high: Array = crane_hookable.filter(func(n: Node): return n.get_meta("route", "") == Wasteland.ROUTE_HIGH)
 check(not crane_low.is_empty(), "Crane tower(s) are hookable LOW route anchors")
 check(not crane_high.is_empty(), "Crane boom(s) are hookable HIGH route anchors")
 var closest_pair: float = INF
 for low_node in crane_low:
  for high_node in crane_high:
   closest_pair = minf(closest_pair, low_node.position.distance_to(high_node.position))
 check(closest_pair <= Wasteland.MAX_BASE_TRAVERSAL_GAP, "at least one Crane Yard tower/boom pair offers a LOW<->HIGH hop within the same practical base-range guard (%.1fm)" % closest_pair)
 var crane_route: Dictionary = w.validate_chunk_route(crane_idx)
 check(crane_route.valid, "the guaranteed base route through a CRANE event chunk is still valid")
 var crane_window: Dictionary = w.event_window_for_index(crane_idx)
 var crane_entrance: Dictionary = w.validate_chunk_route(crane_window.start_index)
 var crane_exit: Dictionary = w.validate_chunk_route(crane_window.end_index - 1)
 check(crane_entrance.valid and crane_exit.valid, "both the entrance and exit chunks of the Crane Yard window keep a valid base route")
 var crane_moving_parts: Array = crane_chunk.get_children().filter(func(n: Node): return n is AnimatableBody3D)
 check(crane_moving_parts.is_empty(), "Crane Yard is intentionally static-only in this pass (spec section 32/33: movement is optional, deliberately skipped) — confirms that decision is actually true in the generated content, not just in a comment")

 # ==================================================================
 # 26. No event chunk ever forces a retry/fallback across a long span
 # ==================================================================
 var probe := Wasteland.new()
 root.add_child(probe)
 var fallback_seen: bool = false
 var retry_seen: bool = false
 for probe_idx in range(first, first + 300):
  probe.create_chunk(probe_idx)
  if probe.fallback_used.get(probe_idx, false):
   fallback_seen = true
  if probe.variant_used.get(probe_idx, 0) > 0:
   retry_seen = true
 check(not fallback_seen, "no chunk across a 300-chunk span (event or not) ever needed the safe fallback template")
 check(not retry_seen, "no chunk across a 300-chunk span (event or not) ever needed a retry variant")
 probe.free()
 await process_frame

 # ==================================================================
 # 27. Origin shift — event schedule + dust intensity are pure functions
 # of `distance`/index, so they must be byte-identical before and after a
 # real rebase.
 # ==================================================================
 var game: Node3D = load("res://scenes/main.tscn").instantiate()
 root.add_child(game)
 game.set_physics_process(false)
 game.set_process(false)
 game.start_run(true)
 await process_frame
 var pre_event: String = game.wasteland.event_for_chunk(turbine_idx)
 var pre_dust: float = game.wasteland.dust_intensity(dust_mid_dist)
 var pre_distance: float = float(turbine_idx) * Wasteland.LENGTH
 while pre_distance - game.wasteland.origin_offset >= 2048.0:
  game.city.rebase(2048.0)
  game.wasteland.rebase(2048.0)
  game.boss.rebase(2048.0)
 var post_event: String = game.wasteland.event_for_chunk(turbine_idx)
 var post_dust: float = game.wasteland.dust_intensity(dust_mid_dist)
 check(pre_event == post_event, "event_for_chunk() is identical before/after a real origin shift")
 check(is_equal_approx(pre_dust, post_dust), "dust_intensity() is identical before/after a real origin shift")

 # ==================================================================
 # 28. Cleanup — a freed chunk's spinning hub is no longer touched
 # ==================================================================
 game.wasteland.chunks.clear()
 for c in game.wasteland.get_children():
  c.free()
 await process_frame
 game.wasteland.spinning_hubs.clear()
 # Stream a window that ends well BEFORE the Turbine Field (window is
 # current-1..current+6, so current = turbine_idx-20 never reaches it).
 game.wasteland.update_chunks(float(turbine_idx - 20) * Wasteland.LENGTH)
 await physics_frame
 var pre_cleanup_hub_count: int = game.wasteland.spinning_hubs.size()
 check(pre_cleanup_hub_count == 0, "a fresh Wasteland streaming window starts with no tracked spinning hubs until a Turbine Field chunk actually streams in")
 # Now stream forward until the window actually includes turbine_idx.
 game.wasteland.update_chunks(float(turbine_idx) * Wasteland.LENGTH)
 await physics_frame
 check(not game.wasteland.spinning_hubs.is_empty(), "spinning hubs appear once the Turbine Field chunk actually streams in")
 for hub_entry in game.wasteland.spinning_hubs:
  check(is_instance_valid(hub_entry.node), "every currently-tracked spinning hub is a real, valid node")
 # Stream far past it — old chunks (including the Turbine Field) get freed.
 var far_index: int = turbine_idx + 500
 game.wasteland.update_chunks(float(far_index) * Wasteland.LENGTH)
 await physics_frame
 game.wasteland.update_spinning_hubs(0.016)
 var stale_found: bool = false
 for hub_entry in game.wasteland.spinning_hubs:
  if not is_instance_valid(hub_entry.node):
   stale_found = true
 check(not stale_found, "after streaming far past a Turbine Field, update_spinning_hubs() never holds a stale/freed node reference")

 # ==================================================================
 # 12. Hit dedupe — reuses Rider.hurt()'s own existing invincibility
 # no-op, the same path CityBoss's hazards already rely on.
 # ==================================================================
 game.rider.invincible = 1.0
 game.rider.position.y = 0.0
 game.rider.armor_charges = 0
 var first_hurt: bool = game.rider.hurt("OBSTACLE COLLISION")
 var second_hurt: bool = game.rider.hurt("OBSTACLE COLLISION")
 check(first_hurt and second_hurt, "Rider.hurt()'s existing invincibility window no-ops a repeat hit — the exact dedupe a Turbine blade spanning several physics frames relies on")

 # ==================================================================
 # 29. City events completely unaffected by the Wasteland Event Director
 # ==================================================================
 check(DifficultyDirector.event_for_chunk(32) == DifficultyDirector.EVENT_SKY_GAP, "City's own Sky Gap event selection is unchanged by adding Wasteland's Event Director")
 check(DifficultyDirector.is_wasteland(float(32) * DifficultyDirector.LENGTH) == false, "the City chunk used for the Sky Gap regression check is genuinely still City, not Wasteland")

 game.free()
 w.free()
 await process_frame

 print("WASTELAND_EVENTS_RESULT %d/%d passed; failures=%d" % [checks - failures, checks, failures])
 quit(1 if failures > 0 else 0)
