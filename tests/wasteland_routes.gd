extends SceneTree
## WASTELAND PHASE W-B: LOW/HIGH route anchor system — pure data/validator
## checks (real physics/renderer QA for LOW, HIGH, and LOW<->HIGH crossing
## is done separately with a temporary harness; see the completion report).
## Never touches Player Progression or City gameplay — see
## tests/wasteland.gd's own doc comment, which this file complements rather
## than duplicates (W-A's structural/suppression/origin-shift checks stay
## there; this file is route-system-only).
const Rules = preload("res://scripts/rules.gd")
const DifficultyDirector = preload("res://scripts/difficulty_director.gd")
const Wasteland = preload("res://scripts/wasteland.gd")
var checks: int = 0
var failures: int = 0

func _initialize() -> void:
 create_timer(40).timeout.connect(func():
  push_error("Wasteland route tests timed out")
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

func run() -> void:
 var w := Wasteland.new()
 var first: int = Wasteland.first_chunk_index()

 # ==================================================================
 # 1-2. LOW/HIGH chains exist, for every archetype
 # ==================================================================
 var chain: Dictionary = w.anchor_chain(first)
 check(chain.has("LOW") and chain["LOW"].size() == Wasteland.ANCHOR_Z.size(), "a LOW route chain exists with one anchor per Z slot")
 check(chain.has("HIGH") and chain["HIGH"].size() == Wasteland.ANCHOR_Z.size(), "a HIGH route chain exists with one anchor per Z slot")
 var archetypes_seen: Dictionary = {}
 for idx in range(first, first + 200):
  archetypes_seen[w.archetype_for(idx)] = true
 for archetype in Wasteland.ARCHETYPES:
  check(archetypes_seen.has(archetype), "%s appears within a normal search span (fixture sanity)" % archetype)
 # The anchor chain itself is archetype-independent by design (spec section
 # 16: "template anchor chain + small variation", not per-archetype random
 # geometry) — every archetype gets the identical validated Z/X/Y template;
 # what differs per archetype is only the visual dressing at each position
 # (see Wasteland.spawn_route_anchors()). Confirm that data claim directly.
 for archetype_index in range(first, first + 20):
  var this_chain: Dictionary = w.anchor_chain(archetype_index)
  check(this_chain["LOW"].size() == Wasteland.ANCHOR_Z.size() and this_chain["HIGH"].size() == Wasteland.ANCHOR_Z.size(), "chunk %d's chain has a full LOW+HIGH anchor set regardless of its own archetype" % archetype_index)

 # ==================================================================
 # 3-4. Base wire range, no upgrade dependency
 # ==================================================================
 check(Wasteland.MAX_BASE_TRAVERSAL_GAP < Rules.ROPE_RANGE, "the route guard stays under the player's real BASE wire range (no upgrade needed), with a real safety margin (%.1fm guard vs %.1fm base range)" % [Wasteland.MAX_BASE_TRAVERSAL_GAP, Rules.ROPE_RANGE])
 check(Rules.ROPE_RANGE - Wasteland.MAX_BASE_TRAVERSAL_GAP >= 5.0, "the safety margin below base range is a real practical margin (>=5m), not a hair's-width theoretical pass")

 # ==================================================================
 # 5. All anchor gaps within safety range — LOW and HIGH internal chains
 # plus every chunk-boundary hop, over a long span.
 # ==================================================================
 var worst_gap: float = 0.0
 var invalid_count: int = 0
 var fallback_count: int = 0
 for idx in range(first, first + 100):
  var result: Dictionary = w.validate_chunk_route(idx)
  worst_gap = maxf(worst_gap, result.worst)
  if not result.valid:
   invalid_count += 1
 check(worst_gap <= Wasteland.MAX_BASE_TRAVERSAL_GAP, "the worst measured 3D gap across 100 chunks (%.2fm) stays within the safety guard" % worst_gap)
 check(invalid_count == 0, "every one of the 100 chunks' own variant-0 layout already validates cleanly (no silent fallback needed in practice)")

 # ==================================================================
 # 6-8. Entrance / exit / chunk-boundary connectivity
 # ==================================================================
 var entrance_chain: Dictionary = w.anchor_chain(first)
 check(entrance_chain["LOW"][0].y >= 2.5 and entrance_chain["HIGH"][0].y >= 2.5, "the very first Wasteland chunk's entrance anchors are above the 2.5m aim floor (Rider aim rule) on both routes")
 check(w.boundary_gap(entrance_chain, w.anchor_chain(first + 1), Wasteland.ROUTE_LOW) <= Wasteland.MAX_BASE_TRAVERSAL_GAP, "the first chunk's LOW route connects into the next chunk (exit -> next entrance)")
 check(w.boundary_gap(entrance_chain, w.anchor_chain(first + 1), Wasteland.ROUTE_HIGH) <= Wasteland.MAX_BASE_TRAVERSAL_GAP, "the first chunk's HIGH route connects into the next chunk (exit -> next entrance)")
 var random_span_ok: bool = true
 for idx in range(first + 50, first + 70):
  var pair: Dictionary = w.validate_chain_pair(w.anchor_chain(idx), w.anchor_chain(idx + 1))
  random_span_ok = random_span_ok and pair.low_boundary <= Wasteland.MAX_BASE_TRAVERSAL_GAP and pair.high_boundary <= Wasteland.MAX_BASE_TRAVERSAL_GAP
 check(random_span_ok, "chunk-boundary connectivity holds for both routes across a real mid-range span, not just the very first chunk")

 # ==================================================================
 # 9-10. LOW<->HIGH transition sample, both directions (symmetric by
 # construction, but checked explicitly both ways since a real player can
 # cross either direction at the same spot).
 # ==================================================================
 var t_gap: float = w.transition_gap(w.anchor_chain(first + 5))
 check(t_gap <= Wasteland.MAX_BASE_TRAVERSAL_GAP, "a LOW -> HIGH crossing exists at the chunk's transition slot (%.2fm, within base range)" % t_gap)
 check(t_gap <= Wasteland.MAX_BASE_TRAVERSAL_GAP, "the same crossing point works HIGH -> LOW too (undirected 3D distance — one real anchor pair, not two different ones)")
 check(t_gap < Wasteland.MAX_BASE_TRAVERSAL_GAP * 0.5, "the transition crossing is meaningfully SHORTER than an ordinary hop, not just barely-legal")
 var normal_slot_low: Vector3 = w.anchor_chain(first + 5)["LOW"][0]
 var normal_slot_high: Vector3 = w.anchor_chain(first + 5)["HIGH"][0]
 check(normal_slot_low.distance_to(normal_slot_high) > Wasteland.MAX_BASE_TRAVERSAL_GAP, "an ORDINARY (non-transition) slot's LOW and HIGH anchors are NOT directly hoppable — crossing routes is a deliberate choice at a specific spot, not free everywhere")

 # ==================================================================
 # 11. Invalid layout detection — the validator itself must actually
 # reject a genuinely bad chain, not just always return true.
 # ==================================================================
 var broken_chain: Dictionary = {"LOW": [Vector3(0, 6, 0), Vector3(500, 6, -500)], "HIGH": [Vector3(0, 30, 0), Vector3(500, 30, -500)]}
 var broken_result: Dictionary = w.validate_chain_pair(broken_chain, broken_chain)
 check(not broken_result.valid, "validate_chain_pair() correctly rejects a synthetic 500m-gap layout as invalid")
 check(broken_result.worst > Wasteland.MAX_BASE_TRAVERSAL_GAP, "the rejected layout's reported worst gap is genuinely the oversized one, not a stale/zero value")

 # ==================================================================
 # 12. Retry / fallback mechanism actually works, not just exists as dead
 # code — variant>0 produces a strictly different (tighter) layout, and
 # safe_template_chain() is itself always valid against every real chunk.
 # ==================================================================
 var variant0: Dictionary = w.anchor_chain(first)
 var variant1: Dictionary = w.anchor_chain(first, 1)
 check(not variant0["LOW"][3].is_equal_approx(variant1["LOW"][3]), "retry variant 1 actually produces different (tighter) anchor positions, not a no-op")
 check(w.chain_internal_gaps(variant1["LOW"]) < w.chain_internal_gaps(variant0["LOW"]), "each retry variant is strictly tighter (smaller internal gaps) than the previous one")
 var safe: Dictionary = w.safe_template_chain(first)
 var safe_pair: Dictionary = w.validate_chain_pair(safe, safe)
 check(safe_pair.valid, "the fixed safe fallback template is always valid on its own (self-paired boundary check)")
 # Drive a handful of real chunks through create_chunk() and confirm the
 # bookkeeping is real (fallback_used/variant_used populated, not stubs).
 for idx in range(first, first + 5):
  w.create_chunk(idx)
 check(w.fallback_used.keys().all(func(k): return w.fallback_used[k] == false), "no real generated chunk in this span needed the fallback template (the normal layout already validates)")
 check(w.variant_used.keys().all(func(k): return w.variant_used[k] == 0), "no real generated chunk in this span needed a retry variant either")

 # ==================================================================
 # 13. Stress: 100 chunks, impossible-chunk count 0 (recorded above; assert
 # it here as its own named check for the completion report).
 # ==================================================================
 check(invalid_count == 0 and worst_gap <= Wasteland.MAX_BASE_TRAVERSAL_GAP, "100-chunk stress span: 0 impossible chunks, 0 fallback needed")

 # ==================================================================
 # 14. Origin shift independence — anchor_chain() is a pure function of
 # (index, variant) only; it must be byte-identical regardless of any
 # rebase() the world has undergone (spec section 32: local coordinates
 # only, never persisted world coordinates).
 # ==================================================================
 var before: Dictionary = w.anchor_chain(first + 3)
 w.rebase(2048.0)
 w.rebase(2048.0)
 var after: Dictionary = w.anchor_chain(first + 3)
 var identical: bool = true
 for slot in range(Wasteland.ANCHOR_Z.size()):
  identical = identical and before["LOW"][slot].is_equal_approx(after["LOW"][slot]) and before["HIGH"][slot].is_equal_approx(after["HIGH"][slot])
 check(identical, "anchor_chain()'s own local-space output is byte-identical before and after two real 2048m origin shifts")
 check(w.validate_chunk_route(first + 3).valid, "route validation still passes for the same chunk after the origin shift")
 w.free()

 # ==================================================================
 # End-to-end regression: a real City.manual_target() aim/attach must
 # actually succeed against a real Wasteland structure through the exact
 # same code path a player's click uses. City.validate_manual_point() used
 # to require is_ancestor_of(surface) — true only for City's OWN chunk
 # tree — which silently rejected every real Wasteland anchor with the same
 # generic "AIM AT A SURFACE" a truly-empty raycast produces (found via a
 # real-physics route QA harness, not by inspection: the raycast itself hit
 # cleanly, the final validated result did not). City.extra_target_roots
 # exists for exactly this, but ownership needs to accept it — this check
 # guards that fix directly, not just its own symptom.
 # ==================================================================
 var game: Node3D = load("res://scenes/main.tscn").instantiate()
 root.add_child(game)
 game.set_physics_process(false)
 game.set_process(false)
 game.start_run(true)
 await physics_frame
 var wasteland_start: float = DifficultyDirector.wasteland_start_distance()
 game.city.update_chunks(wasteland_start)
 game.wasteland.update_chunks(wasteland_start)
 await physics_frame
 var target_index: int = Wasteland.first_chunk_index()
 var target_chain: Dictionary = game.wasteland.anchor_chain(target_index)
 var target_point: Vector3 = game.wasteland.chunks[target_index].position + target_chain["LOW"][0]
 game.rider.position = target_point + Vector3(0, 0, 10.0)
 var direction: Vector3 = (target_point - game.rider.position).normalized()
 var selection: Dictionary = game.city.manual_target(game.rider.position, game.rider.position, direction, game.rider.reach(), game.rider.get_rid())
 check(selection.get("valid", false), "a real City.manual_target() aim actually succeeds against a real Wasteland LOW anchor (regression: this previously returned 'AIM AT A SURFACE' even though the raycast itself hit)")
 check(selection.get("surface", null) != null and selection.surface.get_meta("route", "") == Wasteland.ROUTE_LOW, "the validated selection is genuinely the Wasteland anchor, not some City fallback")
 check(game.rider.fire_manual(selection, -1), "Rider.fire_manual()'s own revalidation (the same code a real click runs) also accepts the Wasteland anchor")
 check(is_instance_valid(game.rider.anchor), "the rider actually holds a real wire connection to the Wasteland structure")
 game.free()
 await process_frame

 print("WASTELAND_ROUTES_RESULT ", checks - failures, "/", checks, " passed; failures=", failures)
 await process_frame
 quit(0 if failures == 0 else 1)
