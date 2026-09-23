extends Node3D
## WASTELAND — Phase W-A graybox foundation + Phase W-B LOW/HIGH route
## system for Wire Rush's second chapter. A separate, independent chunk-
## generation layer (mirrors City's own chunks/update_chunks()/
## create_chunk()/rebase() shape) rather than a branch bolted onto City.gd
## — see DifficultyDirector.wasteland_start_distance() for the single
## shared boundary both this file and City.gd read.
##
## Chunk-index space is shared with City (same LENGTH, same
## floori(distance/LENGTH) indexing): City.update_chunks() already refuses
## to create any chunk at or past first_chunk_index() (its own existing
## "no gameplay chunks stream beyond City exit" cap, now applied regardless
## of practice mode), and this file only ever creates chunks at or past
## that same index — so the two generators can never collide over the same
## index, and Main simply calls both every tick without either needing to
## know about the other.
##
## No Player Progression is read or written here (spec section 3) — this
## file only ever reads/writes Wasteland-local generation state, and
## Rider/Rules are untouched.
const Rules = preload("res://scripts/rules.gd")
const DifficultyDirector = preload("res://scripts/difficulty_director.gd")

const LENGTH: float = 64.0
static func first_chunk_index() -> int:
 return ceili(DifficultyDirector.wasteland_start_distance() / LENGTH)

const ARCHETYPE_POWERLINE: String = "POWERLINE"
const ARCHETYPE_BROKEN_HIGHWAY: String = "BROKEN_HIGHWAY"
const ARCHETYPE_INDUSTRIAL_RUINS: String = "INDUSTRIAL_RUINS"
const ARCHETYPE_OPEN_WASTELAND: String = "OPEN_WASTELAND"
const ARCHETYPE_CLIFF_FRAME: String = "CLIFF_FRAME"
const ARCHETYPES: Array[String] = [
 ARCHETYPE_POWERLINE, ARCHETYPE_BROKEN_HIGHWAY, ARCHETYPE_INDUSTRIAL_RUINS,
 ARCHETYPE_OPEN_WASTELAND, ARCHETYPE_CLIFF_FRAME,
]

## Graybox palette — deliberately desaturated/dusty (vs. City's cooler
## blue-grey concrete) so the two chapters read as different places even
## before any structure comes into view (spec section 7).
const GROUND_COLOR := Color("6b5c48")
const GROUND_CRACK_COLOR := Color("4a3f30")
const STRUCTURE_COLOR := Color("5a5348")
const STRUCTURE_DARK_COLOR := Color("3d382f")
const RUST_COLOR := Color("7a4630")
const SKY_STRUCTURE_COLOR := Color("342f28")
## LOW/HIGH route anchors get a faint tint on top of each archetype's own
## structure color so the two routes also read apart visually, not just
## mechanically (LOW = closer to the ground palette, HIGH = a cooler,
## higher-visibility accent — graybox-level distinction only).
const LOW_ROUTE_TINT := Color("6b5240")
const HIGH_ROUTE_TINT := Color("7c6a4f")

var chunks: Dictionary = {}
var origin_offset: float = 0.0
var material_cache: Dictionary = {}
## Diagnostics only (spec section 25 stress reporting) — which generation
## variant a chunk actually used, and whether it fell back to the always-
## valid safe template. Never read by gameplay code.
var fallback_used: Dictionary = {}
var variant_used: Dictionary = {}

func _ready() -> void:
 pass

## Same convention as City.update_chunks(): stream a sliding window ahead of
## `distance`, free anything more than 2 chunks behind. Never creates a
## chunk before first_chunk_index() — City.gd's own chunks own everything
## before that, including the existing Wasteland-gate boundary decoration
## at floori(rest_area_end_distance()/LENGTH) (untouched by this file).
func update_chunks(distance: float, attached: Node3D = null) -> void:
 var current: int = floori(distance / LENGTH)
 var first_index: int = first_chunk_index()
 var stream_end: int = current + 6
 for index in range(maxi(first_index, current - 1), stream_end):
  if not chunks.has(index):
   create_chunk(index)
 for key in chunks.keys():
  if key < current - 2:
   var chunk: Node3D = chunks[key]
   if is_instance_valid(attached) and chunk.is_ancestor_of(attached):
    continue
   chunks.erase(key)
   chunk.free()

func rebase(amount: float) -> void:
 origin_offset += amount
 for chunk in chunks.values():
  chunk.position.z += amount

static func wasteland_hash(value: int) -> int:
 var mixed: int = (value ^ (value >> 16)) * 2246822519
 return posmod(mixed ^ (mixed >> 13), 2147483647)

func archetype_for(index: int) -> String:
 return ARCHETYPES[wasteland_hash(index) % ARCHETYPES.size()]

# ---------------------------------------------------------------------
# PHASE W-B: LOW/HIGH route anchor chain — a small, pure "route graph"
# (spec section 10): each chunk contributes ANCHOR_Z.size() LOW anchors and
# the same number of HIGH anchors, all in the chunk's own LOCAL space (never
# world/origin-shifted coordinates — spec section 32), so this stays valid
# forever regardless of how many times Main.rebase()s. One slot
# (TRANSITION_SLOT) deliberately narrows the LOW/HIGH vertical+lateral gap
# so a LOW<->HIGH crossing exists without ever being trivially free at every
# slot (spec section 11).
# ---------------------------------------------------------------------
const ROUTE_LOW: String = "LOW"
const ROUTE_HIGH: String = "HIGH"
const ANCHOR_Z: Array[float] = [-4.0, -21.0, -38.0, -55.0]
const TRANSITION_SLOT: int = 1
const LOW_Y: float = 6.0
const HIGH_Y: float = 30.0
const TRANSITION_LOW_Y: float = 13.0
const TRANSITION_HIGH_Y: float = 20.0
## Side alternates every chunk (see anchor_chain()'s own `side`), so a
## chunk-boundary hop's worst case pays for the FULL side flip (2x this
## offset) on top of the Z step — sized so that full flip still clears
## MAX_BASE_TRAVERSAL_GAP (verified directly in tests/wasteland_routes.gd,
## not just by this comment).
const LOW_X_OFFSET: float = 6.0
const HIGH_X_OFFSET: float = 8.0
const TRANSITION_LOW_X_OFFSET: float = 8.0
const TRANSITION_HIGH_X_OFFSET: float = 9.0
## Base wire reach (Rules.ROPE_RANGE = 30) minus a real-swing safety margin.
## Mirrors City.MAX_BASE_TRAVERSAL_GAP's own role/naming for the same
## reason: real swings never fly a mathematically-exact straight line at
## the aim point (player offset/velocity/release timing all eat into raw
## range) — verified empirically here via a real-physics QA harness (see
## the completion report), not an arbitrary guess.
const MAX_BASE_TRAVERSAL_GAP: float = 22.0
## Bounded retry (spec section 17): each retry shrinks anchor spacing
## instead of regenerating blindly, so a retry is a strictly SAFER variant
## of the same layout, not a fresh random roll that could fail again for a
## different reason. Never loops unbounded — index MAX_LAYOUT_RETRIES-1
## always falls back to safe_template_chain() below, which is fixed/always
## valid by construction.
const MAX_LAYOUT_RETRIES: int = 3

## Pure function of (index, variant) — no node creation, no randomness
## beyond the deterministic wasteland_hash already used elsewhere. variant
## 0 is every real chunk's normal layout; variant>0 only ever gets reached
## by create_chunk()'s own retry loop if variant 0 somehow failed
## validate_chunk_route() (see that function's own doc comment on why this
## essentially never fires with the current constants, and
## tests/wasteland_routes.gd's synthetic-failure check for why the
## mechanism itself still has to exist and actually work).
func anchor_chain(index: int, variant: int = 0) -> Dictionary:
 var side: int = 1 if posmod(index, 2) == 0 else -1
 var shrink: float = 1.0 - float(variant) * 0.2
 var low: Array[Vector3] = []
 var high: Array[Vector3] = []
 for slot in range(ANCHOR_Z.size()):
  var is_transition: bool = slot == TRANSITION_SLOT
  var z: float = ANCHOR_Z[slot] * shrink
  var low_y: float = TRANSITION_LOW_Y if is_transition else LOW_Y
  var high_y: float = TRANSITION_HIGH_Y if is_transition else HIGH_Y
  var low_x_off: float = (TRANSITION_LOW_X_OFFSET if is_transition else LOW_X_OFFSET) * shrink
  var high_x_off: float = (TRANSITION_HIGH_X_OFFSET if is_transition else HIGH_X_OFFSET) * shrink
  low.append(Vector3(side * low_x_off, low_y, z))
  high.append(Vector3(side * high_x_off, high_y, z))
 return {"LOW": low, "HIGH": high, "side": side}

## A fixed, hand-verified-safe chain used only if every retry variant
## somehow still fails — see create_chunk(). Keeps ANCHOR_Z's own full
## entrance-to-exit span (compressing Z here would leave nothing near the
## chunk exit to hand off to the next chunk's entrance — a real bug this
## template previously had, caught by tests/wasteland_routes.gd's own
## self-paired boundary check) but centers X and keeps LOW/HIGH close in Y
## to make every gap trivially small.
func safe_template_chain(index: int) -> Dictionary:
 var low: Array[Vector3] = []
 var high: Array[Vector3] = []
 for slot in range(ANCHOR_Z.size()):
  var z: float = ANCHOR_Z[slot]
  low.append(Vector3(4.0, 6.0, z))
  high.append(Vector3(4.0, 13.0, z))
 return {"LOW": low, "HIGH": high, "side": 1}

func chain_internal_gaps(chain: Array) -> float:
 var worst: float = 0.0
 for i in range(chain.size() - 1):
  worst = maxf(worst, chain[i].distance_to(chain[i + 1]))
 return worst

## The gap between this chunk's LAST anchor of `route` and the NEXT chunk's
## FIRST anchor of the same route, expressed entirely in THIS chunk's own
## local frame (the next chunk's own local point shifted by -LENGTH) — so
## this is correct regardless of either chunk's real world position/
## rebase history (spec section 19/32).
func boundary_gap(chain: Dictionary, next_chain: Dictionary, route: String) -> float:
 var this_route: Array = chain[route]
 var next_route: Array = next_chain[route]
 var last_point: Vector3 = this_route[this_route.size() - 1]
 var first_point: Vector3 = next_route[0] + Vector3(0, 0, -LENGTH)
 return last_point.distance_to(first_point)

## The one designated LOW<->HIGH crossing point this chunk offers (spec
## section 11) — deliberately much shorter than a normal same-slot LOW/HIGH
## gap (see the constants above: ~7m here vs. ~25m everywhere else), so
## crossing routes is a real, deliberate choice at a specific spot, not
## something that's trivially always available.
func transition_gap(chain: Dictionary) -> float:
 var low: Vector3 = chain["LOW"][TRANSITION_SLOT]
 var high: Vector3 = chain["HIGH"][TRANSITION_SLOT]
 return low.distance_to(high)

## Pure validator (spec section 18): true only if BOTH routes' own internal
## chain and BOTH routes' boundary hop into the next chunk stay within
## MAX_BASE_TRAVERSAL_GAP. Never touches a node/scene — takes/returns plain
## data so tests can call it directly with synthetic chains too.
func validate_chain_pair(chain: Dictionary, next_chain: Dictionary) -> Dictionary:
 var low_gap: float = chain_internal_gaps(chain["LOW"])
 var high_gap: float = chain_internal_gaps(chain["HIGH"])
 var low_boundary: float = boundary_gap(chain, next_chain, ROUTE_LOW)
 var high_boundary: float = boundary_gap(chain, next_chain, ROUTE_HIGH)
 var worst: float = maxf(maxf(low_gap, high_gap), maxf(low_boundary, high_boundary))
 return {
  "valid": worst <= MAX_BASE_TRAVERSAL_GAP,
  "low_gap": low_gap, "high_gap": high_gap,
  "low_boundary": low_boundary, "high_boundary": high_boundary,
  "worst": worst,
 }

func validate_chunk_route(index: int, variant: int = 0) -> Dictionary:
 return validate_chain_pair(anchor_chain(index, variant), anchor_chain(index + 1, variant))

func create_chunk(index: int) -> void:
 var chunk := Node3D.new()
 chunk.name = "Wasteland_%d" % index
 add_child(chunk)
 chunk.position.z = -index * LENGTH + origin_offset
 chunks[index] = chunk
 spawn_ground(chunk)
 spawn_background(chunk, index)

 # Bounded retry, then a fixed safe fallback (spec section 17) — see
 # anchor_chain()/safe_template_chain()'s own doc comments.
 var chain: Dictionary = {}
 var used_variant: int = 0
 var used_fallback: bool = false
 for variant in range(MAX_LAYOUT_RETRIES):
  var candidate: Dictionary = anchor_chain(index, variant)
  var next_candidate: Dictionary = anchor_chain(index + 1, variant)
  if validate_chain_pair(candidate, next_candidate).valid:
   chain = candidate
   used_variant = variant
   break
  if variant == MAX_LAYOUT_RETRIES - 1:
   chain = safe_template_chain(index)
   used_fallback = true
 fallback_used[index] = used_fallback
 variant_used[index] = used_variant

 var archetype: String = archetype_for(index)
 spawn_route_anchors(chunk, index, archetype, chain)
 match archetype:
  ARCHETYPE_POWERLINE:
   spawn_powerline_landmark(chunk, chain)
  ARCHETYPE_BROKEN_HIGHWAY:
   spawn_broken_highway_landmark(chunk, chain)
  ARCHETYPE_INDUSTRIAL_RUINS:
   spawn_industrial_ruins_landmark(chunk, chain)
  ARCHETYPE_OPEN_WASTELAND:
   spawn_open_wasteland_landmark(chunk, index, chain)
  ARCHETYPE_CLIFF_FRAME:
   spawn_cliff_frame_landmark(chunk, chain)
 # Static event-name placeholders (spec sections 15-16): a small, purely
 # decorative/wireable chance of a crane or turbine appearing on TOP of
 # whichever archetype was already placed. Tagged with route metas too
 # (spec sections 14-15: crane tower/turbine tower-lower = LOW, crane
 # boom/turbine nacelle = HIGH) so they can genuinely serve as bonus
 # route anchors when present, without ever being load-bearing for base
 # traversability (the real guaranteed chain above already covers that).
 var extra_roll: int = wasteland_hash(index * 7 + 3) % 8
 if extra_roll == 0:
  spawn_static_crane(chunk, Vector3(-9.5, 0, -32))
 elif extra_roll == 1:
  spawn_static_turbine(chunk, Vector3(9.5, 0, -32))

func material(color: Color, glow: bool = false) -> StandardMaterial3D:
 var key: String = color.to_html() + str(glow)
 if material_cache.has(key):
  return material_cache[key]
 var mat := StandardMaterial3D.new()
 mat.albedo_color = color
 mat.roughness = 0.9
 if glow:
  mat.emission_enabled = true
  mat.emission = color
  mat.emission_energy_multiplier = 1.4
 material_cache[key] = mat
 return mat

## Same shape as City.box(): a StaticBody3D with one BoxMesh + matching
## BoxShape3D child, on the default physics layer/mask City's own hookable
## surfaces already use (so City.manual_target()'s raycast picks these up
## with zero extra wiring). `hookable`/`building` metas mirror City's own
## convention exactly, so an ordinary structure reads as a normal safe-to-
## touch wall (Rider.integrate()'s obstacle-damage branch only triggers for
## colliders that are neither "road" nor "building").
func box(parent: Node3D, pos: Vector3, size: Vector3, color: Color, solid: bool = false) -> Node3D:
 var root: Node3D = StaticBody3D.new() if solid else Node3D.new()
 parent.add_child(root)
 root.position = pos
 var mesh := MeshInstance3D.new()
 var box_mesh := BoxMesh.new()
 box_mesh.size = size
 mesh.mesh = box_mesh
 mesh.material_override = material(color)
 mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF if not solid else GeometryInstance3D.SHADOW_CASTING_SETTING_ON
 root.add_child(mesh)
 if solid:
  var collision := CollisionShape3D.new()
  var shape := BoxShape3D.new()
  shape.size = size
  collision.shape = shape
  root.add_child(collision)
 return root

func decoration(parent: Node3D, pos: Vector3, size: Vector3, color: Color) -> MeshInstance3D:
 var mesh := MeshInstance3D.new()
 var box_mesh := BoxMesh.new()
 box_mesh.size = size
 mesh.mesh = box_mesh
 mesh.position = pos
 mesh.material_override = material(color)
 mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
 parent.add_child(mesh)
 return mesh

func hookable_structure(parent: Node3D, pos: Vector3, size: Vector3, color: Color) -> Node3D:
 var body: Node3D = box(parent, pos, size, color, true)
 body.set_meta("hookable", true)
 body.set_meta("building", true)
 return body

## A real, wireable LOW or HIGH route anchor at the given chunk-local
## position (from anchor_chain()) — every route anchor in the game is
## created through this one function, so "is this node part of the route
## system" is always exactly `n.get_meta("route", "") in ["LOW","HIGH"]`.
func spawn_route_anchor(chunk: Node3D, pos: Vector3, route: String, color: Color, size: Vector3 = Vector3(1.4, 1.4, 1.4)) -> Node3D:
 var tint: Color = LOW_ROUTE_TINT if route == ROUTE_LOW else HIGH_ROUTE_TINT
 var blended: Color = color.lerp(tint, 0.4)
 var anchor: Node3D = hookable_structure(chunk, pos, size, blended)
 anchor.set_meta("route", route)
 return anchor

## Places the guaranteed LOW/HIGH anchor chain itself — archetype-flavored
## geometry (spec section 13's per-archetype notes) sitting AT each of the
## already-validated anchor_chain() positions, so the visual and the actual
## wireable point are always the same place. The landmark spawn_* functions
## below add each archetype's signature structure around/behind this chain
## for flavor; they never move or duplicate an anchor position.
func spawn_route_anchors(chunk: Node3D, index: int, archetype: String, chain: Dictionary) -> void:
 for slot in range(ANCHOR_Z.size()):
  var is_transition: bool = slot == TRANSITION_SLOT
  var low_pos: Vector3 = chain["LOW"][slot]
  var high_pos: Vector3 = chain["HIGH"][slot]
  match archetype:
   ARCHETYPE_POWERLINE:
    # A row of support poles leading up to the transition slot's real
    # tower (spawned separately) — low pole = short stub, high pole =
    # tall pole with a small cross-tip, matching a real power line row.
    spawn_route_anchor(chunk, low_pos, ROUTE_LOW, STRUCTURE_DARK_COLOR, Vector3(0.9, 9.0, 0.9))
    var high_pole: Node3D = spawn_route_anchor(chunk, high_pos, ROUTE_HIGH, STRUCTURE_COLOR, Vector3(0.9, 20.0, 0.9))
    decoration(high_pole, Vector3(0, 9.0, 0), Vector3(4.0, 0.4, 0.4), STRUCTURE_DARK_COLOR)
   ARCHETYPE_BROKEN_HIGHWAY:
    # Low = support column stub (matches the deck's own columns); high =
    # a short deck fragment at anchor height, so the HIGH route reads as
    # "walking the remaining road" one piece at a time.
    spawn_route_anchor(chunk, low_pos, ROUTE_LOW, STRUCTURE_DARK_COLOR, Vector3(1.2, 10.0, 1.2))
    var deck_piece: Node3D = spawn_route_anchor(chunk, high_pos, ROUTE_HIGH, STRUCTURE_COLOR, Vector3(6.0, 1.0, 4.0))
    decoration(deck_piece, Vector3(0, 0.7, 0), Vector3(6.0, 0.35, 4.0), RUST_COLOR)
   ARCHETYPE_INDUSTRIAL_RUINS:
    spawn_route_anchor(chunk, low_pos, ROUTE_LOW, STRUCTURE_DARK_COLOR, Vector3(2.4, 4.0, 2.4))
    spawn_route_anchor(chunk, high_pos, ROUTE_HIGH, STRUCTURE_COLOR, Vector3(2.4, 4.0, 2.4))
   ARCHETYPE_OPEN_WASTELAND:
    # Sparser (spec section 13: low density) — thin single posts only.
    spawn_route_anchor(chunk, low_pos, ROUTE_LOW, RUST_COLOR, Vector3(1.0, 5.0, 1.0))
    spawn_route_anchor(chunk, high_pos, ROUTE_HIGH, STRUCTURE_DARK_COLOR, Vector3(1.0, 5.0, 1.0))
   ARCHETYPE_CLIFF_FRAME:
    # Low = rock outcrop stub; high = scaffold rung (the wire target stays
    # on the artificial structure, per spec section 14).
    spawn_route_anchor(chunk, low_pos, ROUTE_LOW, Color("564d3f"), Vector3(2.6, 5.0, 2.6))
    spawn_route_anchor(chunk, high_pos, ROUTE_HIGH, STRUCTURE_COLOR, Vector3(1.3, 3.0, 1.3))
  if is_transition:
   # A faint connecting strut so the crossing point also reads visually,
   # not just mechanically.
   var mid: Vector3 = (low_pos + high_pos) * 0.5
   var diff: Vector3 = high_pos - low_pos
   var strut := decoration(chunk, mid, Vector3(0.25, diff.length(), 0.25), Color("8a7355"))
   strut.rotation.x = atan2(diff.y, diff.z) - PI * 0.5 if absf(diff.z) > 0.001 else 0.0

# ---------------------------------------------------------------------
# Ground / background — Wasteland's own identity (spec sections 21-22):
# a dusty, cracked, wide-open surface instead of City's asphalt road, with
# a thinner, sparser skyline of the chapter's own silhouettes.
# ---------------------------------------------------------------------
func spawn_ground(chunk: Node3D) -> void:
 var ground := box(chunk, Vector3(0, -0.5, -32), Vector3(20, 1, LENGTH), GROUND_COLOR, true)
 ground.set_meta("road", true)
 for i in range(3):
  var crack := decoration(chunk, Vector3((i - 1) * 5.5, 0.03, -8 - i * 20), Vector3(0.15, 0.04, 10 + i * 3), GROUND_CRACK_COLOR)
  crack.rotation.y = (float(i) - 1.0) * 0.15
 # Visual-only foundation skirt so a high/steep view over the ground edge
 # never finds an empty drop (same convention as City.create_chunk()'s own
 # road_support decoration).
 var skirt := decoration(chunk, Vector3(0, -1 - 3.0, -32), Vector3(20, 6.0, LENGTH), Color("241f18"))
 skirt.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

func spawn_background(chunk: Node3D, index: int) -> void:
 # A sparse, thinning silhouette band on both sides — power towers, a
 # turbine outline, a distant ruin — well outside the ~10m collision
 # footprint of the chunk's own real structures, purely decorative.
 for side in [-1, 1]:
  var block: int = wasteland_hash(index * 11 + side * 5)
  if block % 3 == 0:
   continue
  var distance_x: float = 45.0 + float(block % 4) * 12.0
  var z: float = -6.0 - float(block % 5) * 11.0
  var shape: int = (block / 5) % 3
  match shape:
   0:
    decoration(chunk, Vector3(side * distance_x, 14.0, z), Vector3(1.0, 28.0, 1.0), SKY_STRUCTURE_COLOR)
    decoration(chunk, Vector3(side * distance_x, 26.0, z), Vector3(6.0, 0.5, 0.5), SKY_STRUCTURE_COLOR)
   1:
    decoration(chunk, Vector3(side * distance_x, 10.0, z), Vector3(2.2, 20.0, 2.2), SKY_STRUCTURE_COLOR)
   2:
    decoration(chunk, Vector3(side * distance_x, 6.0, z), Vector3(9.0, 12.0, 7.0), SKY_STRUCTURE_COLOR)

# ---------------------------------------------------------------------
# Archetype landmarks (spec section 13): each archetype's own signature
# structure, placed around the transition slot of the already-validated
# route-anchor chain (spawn_route_anchors() above) — decorative/thematic
# on top of a chain that is traversable on its own regardless of these.
# ---------------------------------------------------------------------
func spawn_powerline_landmark(chunk: Node3D, chain: Dictionary) -> void:
 var side: int = chain["side"]
 var x: float = side * 9.5
 var z: float = ANCHOR_Z[TRANSITION_SLOT]
 var tower_height: float = 32.0
 # Split the mast into a LOW lower half and a HIGH upper half (each its own
 # collision) instead of one tall box, so the tower itself is both a LOW
 # and a HIGH anchor exactly like the spec's "tower middle / cross arm"
 # split, not just decoration around the generic chain.
 spawn_route_anchor(chunk, Vector3(x, tower_height * 0.28, z), ROUTE_LOW, STRUCTURE_COLOR, Vector3(1.6, tower_height * 0.56, 1.6))
 var upper: Node3D = spawn_route_anchor(chunk, Vector3(x, tower_height * 0.78, z), ROUTE_HIGH, STRUCTURE_COLOR, Vector3(1.6, tower_height * 0.44, 1.6))
 decoration(upper, Vector3(0, tower_height * 0.15, 0), Vector3(9.0, 0.6, 0.6), STRUCTURE_DARK_COLOR)
 decoration(upper, Vector3(0, tower_height * 0.44, 0), Vector3(0.9, 2.2, 0.9), STRUCTURE_DARK_COLOR)

func spawn_broken_highway_landmark(chunk: Node3D, chain: Dictionary) -> void:
 var z: float = ANCHOR_Z[TRANSITION_SLOT]
 var deck_height: float = 20.0
 var deck: Node3D = decoration(chunk, Vector3(2.0, deck_height, z), Vector3(14.0, 1.2, 20.0), STRUCTURE_COLOR)
 decoration(deck, Vector3(0, 0.9, 0), Vector3(14.0, 0.4, 20.0), RUST_COLOR)
 # The broken edge: a jagged, exposed end with rebar-like fins instead of a
 # clean cut, plus rubble on the ground below it — purely decorative,
 # reading as where the road used to continue.
 var broken_x: float = 2.0
 var broken_z: float = z - 10.0
 decoration(chunk, Vector3(broken_x - 5.0, deck_height - 0.9, broken_z), Vector3(2.0, 1.0, 1.6), RUST_COLOR)
 for i in range(3):
  var fin := decoration(chunk, Vector3(broken_x - 5.0 + float(i) * 2.6, deck_height - 1.6, broken_z), Vector3(0.15, 1.6, 0.15), STRUCTURE_DARK_COLOR)
  fin.rotation.x = 0.35
 decoration(chunk, Vector3(broken_x - 1.0, 1.0, broken_z), Vector3(6.0, 1.6, 5.0), STRUCTURE_DARK_COLOR)

func spawn_industrial_ruins_landmark(chunk: Node3D, chain: Dictionary) -> void:
 var side: int = chain["side"]
 var x: float = side * 9.5
 var z: float = ANCHOR_Z[TRANSITION_SLOT]
 var height: float = 22.0
 for level in range(3):
  var y: float = 5.0 + float(level) * 6.0
  decoration(chunk, Vector3(x, y, z), Vector3(7.5, 0.4, 7.5), STRUCTURE_DARK_COLOR)
 for corner_x in [-1, 1]:
  for corner_z in [-1, 1]:
   decoration(chunk, Vector3(x + corner_x * 3.0, height * 0.5, z + corner_z * 3.0), Vector3(0.5, height, 0.5), STRUCTURE_DARK_COLOR)

func spawn_open_wasteland_landmark(chunk: Node3D, index: int, chain: Dictionary) -> void:
 var choice: int = wasteland_hash(index * 13 + 9) % 2
 var z: float = ANCHOR_Z[TRANSITION_SLOT]
 if choice == 0:
  spawn_machine_wreck(chunk, Vector3(-8.0, 0, z))
 else:
  decoration(chunk, Vector3(9.0, 13.0, z), Vector3(7.0, 0.5, 0.5), STRUCTURE_DARK_COLOR)

func spawn_cliff_frame_landmark(chunk: Node3D, chain: Dictionary) -> void:
 var side: int = chain["side"]
 var x: float = side * 15.0
 var z: float = ANCHOR_Z[TRANSITION_SLOT]
 decoration(chunk, Vector3(x, 14.0, z), Vector3(8.0, 28.0, 40.0), Color("564d3f"))
 decoration(chunk, Vector3(x - side * 6.0, 22.0, z - 2.0), Vector3(7.0, 12.0, 20.0), Color("463f34"))

# ---------------------------------------------------------------------
# Static placeholders (spec sections 15-17): visual/wireable only, no
# movement, no rotation, no hazard behavior — reserved for later Phase
# gameplay (Crane Yard / Turbine Field events, not implemented here). Route
# metas mirror the spec's own guidance (crane tower / turbine tower-lower =
# LOW, crane boom / turbine nacelle = HIGH) — bonus anchors on top of the
# guaranteed chain, never load-bearing for base traversability on their own.
# ---------------------------------------------------------------------
func spawn_static_crane(chunk: Node3D, base: Vector3) -> void:
 var tower_height: float = 18.0
 var tower: Node3D = hookable_structure(chunk, base + Vector3(0, tower_height * 0.5, 0), Vector3(1.3, tower_height, 1.3), RUST_COLOR)
 tower.set_meta("route", ROUTE_LOW)
 var boom: Node3D = hookable_structure(chunk, base + Vector3(5.0, tower_height, 0), Vector3(10.0, 0.8, 0.8), RUST_COLOR)
 boom.set_meta("route", ROUTE_HIGH)
 decoration(boom, Vector3(-6.4, 0.6, 0), Vector3(1.6, 2.0, 1.6), STRUCTURE_DARK_COLOR)

func spawn_static_turbine(chunk: Node3D, base: Vector3) -> void:
 var tower_height: float = 24.0
 var tower: Node3D = hookable_structure(chunk, base + Vector3(0, tower_height * 0.5, 0), Vector3(1.1, tower_height, 1.1), Color("cfcabf"))
 tower.set_meta("route", ROUTE_LOW)
 var nacelle: Node3D = hookable_structure(chunk, base + Vector3(0, tower_height + 1.0, 0), Vector3(3.4, 1.6, 1.6), Color("b7b1a3"))
 nacelle.set_meta("route", ROUTE_HIGH)
 for angle_deg in [0.0, 120.0, 240.0]:
  var blade := decoration(nacelle, Vector3(0, 0, 0), Vector3(0.35, 8.0, 0.35), Color("dcd7cb"))
  blade.position = Vector3(0, 4.2, 0.9)
  blade.rotation.z = deg_to_rad(angle_deg)

func spawn_machine_wreck(chunk: Node3D, base: Vector3) -> void:
 var main_body: Node3D = hookable_structure(chunk, base + Vector3(0, 2.5, 0), Vector3(7.0, 5.0, 6.0), RUST_COLOR)
 main_body.set_meta("route", ROUTE_LOW)
 var tilted := decoration(main_body, Vector3(3.0, 3.0, 1.0), Vector3(4.0, 3.0, 4.0), STRUCTURE_DARK_COLOR)
 tilted.rotation.z = 0.25
 decoration(main_body, Vector3(-2.0, 4.5, -1.0), Vector3(1.0, 4.0, 1.0), STRUCTURE_DARK_COLOR)
