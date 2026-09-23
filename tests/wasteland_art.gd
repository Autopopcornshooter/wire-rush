extends SceneTree
## WASTELAND PHASE W-D: environment/art polish technical checks (spec
## section 53) — never re-checks W-A/W-B/W-C's own gameplay coverage
## (tests/wasteland.gd, tests/wasteland_routes.gd, tests/wasteland_events.gd
## already own that and are re-run unchanged by this phase). This file only
## verifies the ART PASS'S OWN promise: visual materials actually load,
## collision/wire-target geometry is byte-identical to what W-A/W-B/W-C
## already validated, and the new Wasteland ambient atmosphere behaves.
const Rules = preload("res://scripts/rules.gd")
const DifficultyDirector = preload("res://scripts/difficulty_director.gd")
const Wasteland = preload("res://scripts/wasteland.gd")
var checks: int = 0
var failures: int = 0

func _initialize() -> void:
 create_timer(40).timeout.connect(func():
  push_error("Wasteland art tests timed out")
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
 var first: int = Wasteland.first_chunk_index()

 # ==================================================================
 # Material library: textured materials actually carry a texture, and
 # equal calls are cached (spec section 28 — bounded material count).
 # ==================================================================
 var w := Wasteland.new()
 root.add_child(w)
 var rust: StandardMaterial3D = w.rust_metal_material(Color(0.7, 0.5, 0.4))
 check(is_instance_valid(rust.albedo_texture), "rust_metal_material() actually assigns a real albedo texture, not a flat color fallback")
 check(is_instance_valid(rust.normal_texture), "rust_metal_material() assigns a normal map")
 var sand: StandardMaterial3D = w.sand_material()
 check(is_instance_valid(sand.albedo_texture), "sand_material() actually assigns a real albedo texture")
 var asphalt: StandardMaterial3D = w.broken_asphalt_material()
 check(is_instance_valid(asphalt.albedo_texture), "broken_asphalt_material() actually assigns a real albedo texture")
 var concrete: StandardMaterial3D = w.concrete_material()
 check(is_instance_valid(concrete.albedo_texture), "concrete_material() actually assigns a real albedo texture")
 var rust_again: StandardMaterial3D = w.rust_metal_material(Color(0.7, 0.5, 0.4))
 check(rust == rust_again, "an identical rust_metal_material() call reuses the cached material instead of creating a new one")
 var rust_different_tint: StandardMaterial3D = w.rust_metal_material(Color(0.2, 0.2, 0.2))
 check(rust != rust_different_tint, "a different tint produces a distinct cached material (materials aren't silently shared across colors)")

 # ==================================================================
 # Collision/wire-target alignment preserved (spec section 3/43) — the
 # POWERLINE archetype's route-anchor tower, built through the same
 # spawn_route_anchor() -> hookable_structure() -> box() path every visual
 # material change in this phase went through, must still carry EXACTLY
 # the collision size/position the gameplay geometry always had.
 # ==================================================================
 var powerline_idx: int = find_archetype(w, Wasteland.ARCHETYPE_POWERLINE, first)
 check(powerline_idx >= 0, "fixture: a POWERLINE chunk exists within the search span")
 w.create_chunk(powerline_idx)
 var powerline_chunk: Node3D = w.chunks[powerline_idx]
 var low_anchor: Node3D = find_first_with_meta(powerline_chunk, "route", Wasteland.ROUTE_LOW)
 check(is_instance_valid(low_anchor), "a POWERLINE LOW route anchor exists after the art pass")
 if is_instance_valid(low_anchor):
  var collision: CollisionShape3D = low_anchor.get_child(1)
  check(collision.shape.size == Vector3(0.9, 9.0, 0.9), "the LOW route anchor's collision shape is exactly the gameplay size W-B always used — untouched by the visual material swap")
  var mesh: MeshInstance3D = low_anchor.get_child(0)
  check(is_instance_valid(mesh.material_override) and mesh.material_override is StandardMaterial3D, "the LOW route anchor's visual mesh actually has a real material (the visual wrapper loaded)")
  check(is_instance_valid(mesh.material_override.albedo_texture), "the LOW route anchor's visual material is the new textured rust-metal material, not the old flat color")

 # `w` is fully freed before the real-game fixture below creates its OWN
 # Wasteland chunks at the same indices/world positions — two live
 # instances with overlapping geometry at the same coordinates would make
 # a raycast non-deterministically able to hit either one's collider.
 w.free()
 await process_frame

 # ==================================================================
 # Real end-to-end wire-target regression (same discipline as W-B's own
 # regression test): a real aim/fire against the POWERLINE LOW anchor must
 # still succeed after the art pass — proves mesh/collision/wire-target are
 # still all the same point, not just that the CollisionShape3D size
 # matches on paper.
 # ==================================================================
 var game: Node3D = load("res://scenes/main.tscn").instantiate()
 root.add_child(game)
 game.set_physics_process(false)
 game.set_process(false)
 game.start_run(true)
 await physics_frame
 var low_pos: Vector3 = game.wasteland.anchor_chain(powerline_idx)["LOW"][0]
 game.wasteland.update_chunks(float(powerline_idx) * Wasteland.LENGTH)
 await physics_frame
 var anchor_world: Vector3 = game.wasteland.chunks[powerline_idx].position + low_pos
 game.rider.position = anchor_world + Vector3(0, 0, 10.0)
 var direction: Vector3 = (anchor_world - game.rider.position).normalized()
 var selection: Dictionary = game.city.manual_target(game.rider.position, game.rider.position, direction, game.rider.reach(), game.rider.get_rid())
 check(selection.get("valid", false), "a real aim against the art-updated POWERLINE LOW anchor still succeeds (wire target/collision/visual all still aligned)")
 check(game.rider.fire_manual(selection, -1), "Rider.fire_manual()'s own revalidation also still accepts the art-updated anchor")
 game.free()
 await process_frame

 # ==================================================================
 # Wasteland ambient atmosphere (spec sections 6/38/39/47) — a fresh
 # instance (no chunks needed; these are pure functions of distance).
 # ==================================================================
 var ambient_probe := Wasteland.new()
 var boundary: float = DifficultyDirector.wasteland_start_distance()
 check(ambient_probe.wasteland_ambient_intensity(boundary) == 0.0, "at the exact City/Wasteland boundary, ambient intensity is still 0 (no hard cut)")
 check(ambient_probe.wasteland_ambient_intensity(boundary - 500.0) == 0.0, "still in City, ambient intensity is 0")
 var mid_fade: float = ambient_probe.wasteland_ambient_intensity(boundary + Wasteland.WASTELAND_AMBIENT_FADE_CHUNKS * Wasteland.LENGTH * 0.5)
 check(mid_fade > 0.0 and mid_fade < 1.0, "partway through the entry fade, ambient intensity is a smooth partial blend (%.2f)" % mid_fade)
 check(ambient_probe.wasteland_ambient_intensity(boundary + Wasteland.WASTELAND_AMBIENT_FADE_CHUNKS * Wasteland.LENGTH * 2.0) == 1.0, "well past the entry fade, ambient intensity is fully saturated at 1.0")

 var env := Environment.new()
 env.fog_density = 0.003
 env.fog_light_color = Color("233d58")
 env.fog_height_density = 0.05
 ambient_probe.bind_environment(env)
 ambient_probe.apply_environment(boundary - 500.0)
 check(is_equal_approx(env.fog_density, 0.003), "still in City, apply_environment() leaves the fog completely at City's own baseline")
 ambient_probe.free()

 # ==================================================================
 # Origin shift visual cleanup (spec section 45-46) — Dust particles,
 # telegraph decorations, and entry-landmark nodes are all ordinary
 # children of their owning chunk, so freeing the chunk must free them too;
 # confirmed directly rather than assumed.
 # ==================================================================
 var w2 := Wasteland.new()
 root.add_child(w2)
 var dust_idx: int = -1
 for idx in range(first, first + 500):
  if w2.event_for_chunk(idx) == Wasteland.EVENT_DUST:
   dust_idx = idx
   break
 check(dust_idx >= 0, "fixture: a DUST event window exists for the cleanup check")
 w2.create_chunk(dust_idx)
 var dust_chunk: Node3D = w2.chunks[dust_idx]
 var particle_nodes: Array = dust_chunk.get_children().filter(func(n): return n is GPUParticles3D)
 check(not particle_nodes.is_empty(), "fixture: the Dust chunk actually has particle nodes to clean up")
 w2.update_chunks(float(dust_idx + 500) * Wasteland.LENGTH)
 check(not w2.chunks.has(dust_idx), "the Dust chunk is dropped from tracking once far behind the streaming window")
 check(not is_instance_valid(dust_chunk), "the freed Dust chunk (and everything under it — particles, telegraph, landmark decorations) is actually gone, not just untracked")

 w2.free()
 await process_frame

 print("WASTELAND_ART_RESULT %d/%d passed; failures=%d" % [checks - failures, checks, failures])
 quit(1 if failures > 0 else 0)

func find_archetype(w: Wasteland, archetype: String, min_index: int, span: int = 60) -> int:
 for idx in range(min_index, min_index + span):
  if w.archetype_for(idx) == archetype:
   return idx
 return -1

func find_first_with_meta(node: Node, key: String, value) -> Node:
 for child in node.get_children():
  if child.has_meta(key) and child.get_meta(key) == value:
   return child
  var nested: Node = find_first_with_meta(child, key, value)
  if is_instance_valid(nested):
   return nested
 return null
