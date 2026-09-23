extends Node3D
## WASTELAND — Phase W-A graybox foundation + Phase W-B LOW/HIGH route
## system + Phase W-C events (Dust Zone / Turbine Field / Crane Yard) +
## Phase W-D environment/art polish + Phase W-E Crawler Boss world-
## generation suppression window for Wire Rush's second chapter. The
## Crawler Boss's own geometry/state machine live in scripts/crawler_boss.gd
## — this file only owns the WASTELAND_BOSS_* window used to keep ordinary
## chunk/event generation out of its way. A separate, independent chunk-
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

## PHASE W-D: reused CityKit textures (spec section 25 — reuse existing
## project assets before ever considering a new external one; none were
## added this phase). T_MetalConcrete already reads as a weathered rusty-
## metal-over-concrete panel straight out of the box, T_Concrete_Asphalt as
## dark worn asphalt, T_Trim as sandy/dusty concrete with a dark band, and
## T_Concrete as plain weathered concrete — verified by eye against the
## actual PNGs before committing to this material plan, not guessed from
## filenames. T_RedBrick/T_MarbleFloor/interior textures are deliberately
## NOT reused here: they read as City building material, and mixing them in
## would blur the City/Wasteland visual distinction spec section 4 asks for.
const T_RUST_METAL_BASE: Texture2D = preload("res://assets/citykit/T_MetalConcrete_BaseColor.png")
const T_RUST_METAL_NORMAL: Texture2D = preload("res://assets/citykit/T_MetalConcrete_Normal.png")
const T_RUST_METAL_ORM: Texture2D = preload("res://assets/citykit/T_MetalConcrete_ORM.png")
const T_ASPHALT_BASE: Texture2D = preload("res://assets/citykit/T_Concrete_Asphalt_BaseColor.png")
const T_SAND_BASE: Texture2D = preload("res://assets/citykit/T_Trim_BaseColor.png")
const T_SAND_NORMAL: Texture2D = preload("res://assets/citykit/T_Trim_Normal.png")
const T_SAND_ORM: Texture2D = preload("res://assets/citykit/T_Trim_ORM.png")
const T_CONCRETE_BASE: Texture2D = preload("res://assets/citykit/T_Concrete_BaseColor.png")
const T_CONCRETE_NORMAL: Texture2D = preload("res://assets/citykit/T_Concrete_Normal.png")
const T_CONCRETE_ORM: Texture2D = preload("res://assets/citykit/T_Concrete_ORM.png")

const LENGTH: float = 64.0
static func first_chunk_index() -> int:
 return ceili(DifficultyDirector.wasteland_start_distance() / LENGTH)

# ---------------------------------------------------------------------
# PHASE W-E: Crawler Boss window — expressed as WASTELAND-LOCAL progress
# (spec section 5), not a second absolute-distance constant duplicated
# from DifficultyDirector, and kept here (not in difficulty_director.gd)
# for the same reason the W-C Event Director lives here: Wasteland owns
# its own directorial state fully independent of City's tier/event system
# (no Player Progression, no City tier read anywhere below). Production
# final Wasteland length is still undecided (spec section 5 explicitly
# forbids guessing it here) — WASTELAND_BOSS_START_DISTANCE is a standalone
# tuning knob, not derived from any "end of Wasteland" constant that
# doesn't exist yet.
# ---------------------------------------------------------------------
const WASTELAND_BOSS_START_DISTANCE: float = 2400.0
## Rough encounter span for world-generation SUPPRESSION purposes only
## (spec section 43/44) — generous enough to cover the real encounter
## (CrawlerBoss.gd's own anchor/escape-marker layout is the actual
## authority on how long the fight plays out; this just has to be at
## least that long so ordinary Wasteland content never spawns inside it).
## Sized from real QA (tools/Crawler-Boss-QA.gd): the Crawler keeps moving
## the whole time it's ACTIVE, so a slow/struggling real attempt can cover
## well more raw distance than the encounter's own ~90m body length before
## catching up — 700m proved too narrow in testing (a real run's own
## `distance` metric can end up past boss_end while still mid-encounter),
## so this is deliberately generous rather than tightly fitted.
const WASTELAND_BOSS_LENGTH: float = 2600.0
## Spec section 45: avoid an event window ending right at the boss's own
## doorstep — widen suppression backward by this much too.
const WASTELAND_BOSS_PRE_BUFFER: float = 150.0

static func wasteland_boss_start_distance() -> float:
 return DifficultyDirector.wasteland_start_distance() + WASTELAND_BOSS_START_DISTANCE

static func wasteland_boss_end_distance() -> float:
 return wasteland_boss_start_distance() + WASTELAND_BOSS_LENGTH

static func is_wasteland_boss_zone(distance: float) -> bool:
 return distance >= wasteland_boss_start_distance() and distance < wasteland_boss_end_distance()

static func is_wasteland_boss_window(distance: float) -> bool:
 return distance >= wasteland_boss_start_distance() - WASTELAND_BOSS_PRE_BUFFER and distance < wasteland_boss_end_distance()

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
## PHASE W-C diagnostics only (spec section 41/55 stress reporting) — which
## event (if any) a chunk actually resolved to. Never read by gameplay code.
var event_used: Dictionary = {}

## PHASE W-C: currently-spinning Turbine Field blade hubs, as
## {"node": AnimatableBody3D, "speed": float} — see update_spinning_hubs().
## Entries for freed chunks are simply skipped (is_instance_valid() check)
## rather than eagerly removed on chunk cleanup; Godot frees a hub's whole
## subtree with its owning chunk, so a stale entry can never leak a node,
## only a tiny dead Dictionary the next update_spinning_hubs() call filters
## out.
var spinning_hubs: Array = []

## PHASE W-C Dust Zone: the single shared WorldEnvironment Main owns (see
## Main.setup_environment()/create_world()), bound once via
## bind_environment() so apply_environment() can blend it toward/away from
## the Dust look. Never created here — Wasteland only ever borrows it.
var environment: Environment
var _base_fog_density: float = 0.0
var _base_fog_light_color: Color = Color.WHITE
var _base_fog_height_density: float = 0.0
var _environment_bound: bool = false

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

# ---------------------------------------------------------------------
# PHASE W-C: Wasteland Event Director. Deterministic, stateless, pure
# functions of a chunk index only (spec section 8) — same convention as
# DifficultyDirector.event_for_chunk()'s own window/hash approach, kept
# fully independent of it (no Player Progression, no City tier) so
# Wasteland's own generation stays exactly as order-independent as before.
#
# Events are purely ADDITIVE decoration + hazard layers spawned on top of
# the guaranteed, already-validated LOW/HIGH anchor_chain() (spec section
# 38/61: never redefine or bypass the W-B route/validator) — the same way
# the old static crane/turbine bonus (now replaced by this system) already
# worked. This is what makes "base route always exists regardless of the
# event" (spec section 40) structurally true rather than something each
# event has to separately prove: create_chunk() never skips
# spawn_route_anchors() or the retry/fallback loop for an event chunk.
# ---------------------------------------------------------------------
const EVENT_NONE: String = "NONE"
const EVENT_DUST: String = "DUST"
const EVENT_TURBINE: String = "TURBINE"
const EVENT_CRANE: String = "CRANE"

## No event within the first N chunks of Wasteland (spec section 10) — lets
## the player see a normal Powerline/Highway/Ruins/Cliff chunk and try a
## LOW/HIGH crossing before the first event ever appears.
const EVENT_ENTRY_SAFE_CHUNKS: int = 6
## Each period is EVENT_PERIOD_CHUNKS long; only the first EVENT_LENGTH_CHUNKS
## of a period can ever be an event, so every triggered window is always
## followed by at least (PERIOD - LENGTH) guaranteed-normal chunks before the
## next period is even evaluated — this is the whole cooldown (spec section
## 42: no back-to-back events), exactly like
## DifficultyDirector.is_traffic_surge_chunk()'s own window shape.
const EVENT_PERIOD_CHUNKS: int = 10
const EVENT_LENGTH_CHUNKS: int = 3
## Out of 12 — roughly half of all eligible windows actually trigger, so
## normal Wasteland chunks always outnumber event chunks (spec section 9).
const EVENT_TRIGGER_CHANCE: int = 6

## Which EVENT_PERIOD_CHUNKS-wide window `index` falls into, purely as
## arithmetic on its distance past the entry-safe buffer — valid to call for
## any index (including ones still inside the safe buffer; callers gate that
## separately, see event_for_chunk()).
func event_window_for_index(index: int) -> Dictionary:
 var local_index: int = index - first_chunk_index() - EVENT_ENTRY_SAFE_CHUNKS
 var window_index: int = floori(float(local_index) / float(EVENT_PERIOD_CHUNKS))
 var start_index: int = first_chunk_index() + EVENT_ENTRY_SAFE_CHUNKS + window_index * EVENT_PERIOD_CHUNKS
 return {"window_index": window_index, "start_index": start_index, "end_index": start_index + EVENT_LENGTH_CHUNKS}

## Deterministic per-window roll: whether this window has an event at all,
## and (independently) which of the 3 types — same posmod-hash pseudo-
## randomness this file already uses elsewhere, never a runtime RNG.
func event_type_for_window(window_index: int) -> String:
 var trigger_roll: int = posmod(wasteland_hash(window_index * 977 + 13), 12)
 if trigger_roll >= EVENT_TRIGGER_CHANCE:
  return EVENT_NONE
 var type_roll: int = posmod(wasteland_hash(window_index * 977 + 13 + 500000), 3)
 match type_roll:
  0: return EVENT_DUST
  1: return EVENT_TURBINE
  2: return EVENT_CRANE
 return EVENT_NONE

## The one event (if any) chunk `index` belongs to. City events stay
## completely unaffected (spec section 44) — this never touches
## DifficultyDirector's own City event/tier logic.
func event_for_chunk(index: int) -> String:
 if index < first_chunk_index() + EVENT_ENTRY_SAFE_CHUNKS:
  return EVENT_NONE
 # PHASE W-E spec section 44/45: no Dust/Turbine/Crane inside (or right
 # before) the Crawler Boss window — the boss itself is the challenge.
 if is_wasteland_boss_window(float(index) * LENGTH):
  return EVENT_NONE
 var window: Dictionary = event_window_for_index(index)
 if index >= window.end_index:
  return EVENT_NONE
 return event_type_for_window(window.window_index)

## 0-based position of `index` within its own event window (0 = entrance
## chunk, EVENT_LENGTH_CHUNKS-1 = exit chunk) — lets each event vary its
## layout across the field instead of repeating one chunk 3 times.
func event_slot(index: int) -> int:
 return index - event_window_for_index(index).start_index

## Pure function of `distance` (Main's own origin-shift-independent total
## logical distance — spec section 32/52) -> 0..1 Dust intensity, with a
## linear fade over DUST_FADE_MARGIN world meters on both sides of the
## event window so entry/exit is smooth (spec section 13), never a hard
## cut. Checking the 3 chunks around the player's current one is always
## enough to catch the fade: DUST_FADE_MARGIN is well under one chunk
## LENGTH, and two different DUST windows are always at least
## (EVENT_PERIOD_CHUNKS - EVENT_LENGTH_CHUNKS) chunks apart, so their fade
## margins can never overlap or bleed into an unrelated window.
const DUST_FADE_MARGIN: float = 16.0

func dust_intensity(distance: float) -> float:
 var current_index: int = floori(distance / LENGTH)
 var best: float = 0.0
 for index in [current_index - 1, current_index, current_index + 1]:
  if event_for_chunk(index) != EVENT_DUST:
   continue
  var window: Dictionary = event_window_for_index(index)
  var start_dist: float = float(window.start_index) * LENGTH
  var end_dist: float = float(window.end_index) * LENGTH
  var factor: float = 1.0
  if distance < start_dist:
   factor = clampf(1.0 - (start_dist - distance) / DUST_FADE_MARGIN, 0.0, 1.0)
  elif distance > end_dist:
   factor = clampf(1.0 - (distance - end_dist) / DUST_FADE_MARGIN, 0.0, 1.0)
  best = maxf(best, factor)
 return best

## Dust Zone visual target (spec section 12/14): notably denser than City's
## own base fog (Main.setup_environment()'s 0.003) so mid/far structures
## haze out, but still a plain height/distance fog blend — no volumetric
## feature, since this project's gl_compatibility renderer doesn't support
## FogVolume (see Main.setup_environment()'s own comment on the same
## limitation).
const DUST_FOG_DENSITY: float = 0.024
const DUST_FOG_HEIGHT_DENSITY: float = 0.09
const DUST_FOG_LIGHT_COLOR := Color("8a7355")

## Binds Main's shared WorldEnvironment once (idempotent on the base-value
## snapshot — a later rebind, e.g. after Main.create_world() rebuilds
## Wasteland on a new run, always re-snapshots so a run that ends mid-Dust
## never leaves the NEXT run's baseline polluted).
func bind_environment(env: Environment) -> void:
 environment = env
 if is_instance_valid(env):
  _base_fog_density = env.fog_density
  _base_fog_light_color = env.fog_light_color
  _base_fog_height_density = env.fog_height_density
  _environment_bound = true

## PHASE W-D Wasteland ambient atmosphere (spec sections 6/38/39/47) — a
## distinct, warmer/hazier baseline from City's own cooler blue fog
## (Main.setup_environment()'s 0.003/"233d58"), faded in smoothly over
## WASTELAND_AMBIENT_FADE_CHUNKS after the City/Wasteland boundary rather
## than a hard cut, matching the gradual "industrial outskirts -> sparse
## wasteland" read spec section 47 asks for. Dust blends ON TOP of this
## ambient baseline (see apply_environment() below), never City's raw
## baseline — so Dust's own "restore after exit" always means "back to
## Wasteland's own normal", not City's.
const WASTELAND_AMBIENT_FOG_DENSITY: float = 0.0055
const WASTELAND_AMBIENT_FOG_HEIGHT_DENSITY: float = 0.065
const WASTELAND_AMBIENT_FOG_LIGHT_COLOR := Color("a8987a")
const WASTELAND_AMBIENT_FADE_CHUNKS: float = 18.0

func wasteland_ambient_intensity(distance: float) -> float:
 var boundary: float = DifficultyDirector.wasteland_start_distance()
 if distance <= boundary:
  return 0.0
 return clampf((distance - boundary) / (WASTELAND_AMBIENT_FADE_CHUNKS * LENGTH), 0.0, 1.0)

## Blends the bound environment toward/away from the Wasteland ambient look
## (and, on top of that, the Dust look) every frame, purely from `distance`
## — no accumulated/time-based state, so this is automatically correct
## after any number of Main.rebase() calls and instantly correct the first
## frame either effect becomes active (spec section 13: enter/active/exit/
## reset all fall out of these two lerps).
func apply_environment(distance: float) -> void:
 if not is_instance_valid(environment) or not _environment_bound:
  return
 var ambient: float = wasteland_ambient_intensity(distance)
 var ambient_density: float = lerpf(_base_fog_density, WASTELAND_AMBIENT_FOG_DENSITY, ambient)
 var ambient_color: Color = _base_fog_light_color.lerp(WASTELAND_AMBIENT_FOG_LIGHT_COLOR, ambient)
 var ambient_height_density: float = lerpf(_base_fog_height_density, WASTELAND_AMBIENT_FOG_HEIGHT_DENSITY, ambient)
 var dust: float = dust_intensity(distance)
 environment.fog_density = lerpf(ambient_density, DUST_FOG_DENSITY, dust)
 environment.fog_light_color = ambient_color.lerp(DUST_FOG_LIGHT_COLOR, dust)
 environment.fog_height_density = lerpf(ambient_height_density, DUST_FOG_HEIGHT_DENSITY, dust)

## Turbine Field blade rotation (spec section 21): a plain per-frame
## rotation write on a kinematic AnimatableBody3D, exactly the same
## stable-moving-collision convention City.spawn_vehicle()/
## CityBoss.spawn_robot() already use for their own moving hazards (see
## spawn_event_turbine()) — never a StaticBody3D transform hack.
func update_spinning_hubs(delta: float) -> void:
 spinning_hubs = spinning_hubs.filter(func(entry): return is_instance_valid(entry.node))
 for entry in spinning_hubs:
  entry.node.rotate_object_local(Vector3(0, 0, 1), entry.speed * delta)

## Single per-physics-frame entry point for every Wasteland event's runtime
## behavior (Dust fog blend + Turbine blade spin) — Main calls this once,
## right after wasteland.update_chunks(), the same pairing City already has
## with City.update_vehicles().
func update_events(delta: float, distance: float) -> void:
 apply_environment(distance)
 update_spinning_hubs(delta)

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
 spawn_ground(chunk, index)
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
 # PHASE W-E spec section 43: no archetype set-piece clutter inside the
 # Crawler's own encounter zone — the boss is the content there. The
 # guaranteed anchor_chain() above is still placed as normal (a fallback
 # safety net matching every other chunk's own traversability guarantee).
 if not is_wasteland_boss_zone(float(index) * LENGTH):
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
 # PHASE W-C: deterministic Wasteland event (spec sections 1/6/7) — replaces
 # the old W-A/W-B random 1/8 ambient crane/turbine roll entirely, so a
 # crane/turbine sighting now reliably means "this is an event", not
 # ambient decoration (keeps event identity readable, spec section 6/7:
 # never more than one event active on a chunk).
 var event: String = event_for_chunk(index)
 event_used[index] = event
 match event:
  EVENT_DUST:
   spawn_dust_zone(chunk, index)
  EVENT_TURBINE:
   spawn_turbine_field(chunk, index, event_slot(index))
  EVENT_CRANE:
   spawn_crane_yard(chunk, index, event_slot(index))

 # PHASE W-D event entrance telegraph (spec section 36): the chunk right
 # before a Turbine/Crane window gets a small, distant silhouette hint of
 # what's coming — Dust already telegraphs itself via spawn_dust_zone()'s
 # own wall. World-space only, no HUD.
 if event == EVENT_NONE:
  var next_event: String = event_for_chunk(index + 1)
  if next_event == EVENT_TURBINE:
   spawn_turbine_telegraph(chunk)
  elif next_event == EVENT_CRANE:
   spawn_crane_telegraph(chunk)

 # PHASE W-D Wasteland Entry Landmark (spec section 48) — guaranteed, not a
 # random roll, so the very first Wasteland chunk always reads as "a new
 # chapter", UI-free.
 if index == first_chunk_index():
  spawn_entry_landmark(chunk)

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

# ---------------------------------------------------------------------
# PHASE W-D: textured material library (spec sections 4/5/28) — a small,
# reused set (never grows per-call) rather than one material per structure,
# built from CityKit textures already in the project (spec section 25: no
# new external asset this phase). `tint` multiplies the texture's own
# albedo (StandardMaterial3D's normal albedo_color x albedo_texture
# behavior), so the same base texture can serve multiple accent colors
# (rust orange, weathered steel, Crane Yard safety-yellow, ...) without a
# second texture asset. ORM channel packing (R=AO, G=Roughness, B=Metallic)
# matches this pack's own convention.
# ---------------------------------------------------------------------
var _textured_material_cache: Dictionary = {}

func textured_material(base: Texture2D, normal_tex: Texture2D, orm_tex: Texture2D, tint: Color, uv_scale: Vector2) -> StandardMaterial3D:
 var key: String = "%s|%s|%s" % [base.resource_path, tint.to_html(), uv_scale]
 if _textured_material_cache.has(key):
  return _textured_material_cache[key]
 var mat := StandardMaterial3D.new()
 mat.albedo_texture = base
 mat.albedo_color = tint
 mat.uv1_scale = Vector3(uv_scale.x, uv_scale.y, 1)
 if is_instance_valid(normal_tex):
  mat.normal_enabled = true
  mat.normal_texture = normal_tex
 if is_instance_valid(orm_tex):
  mat.ao_enabled = true
  mat.ao_texture = orm_tex
  mat.ao_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_RED
  mat.roughness_texture = orm_tex
  mat.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_GREEN
  mat.metallic_texture = orm_tex
  mat.metallic_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_BLUE
 else:
  mat.roughness = 0.85
 mat.metallic_specular = 0.2
 _textured_material_cache[key] = mat
 return mat

## Weathered rust-metal-over-concrete — the workhorse material for towers,
## cranes, turbines, industrial frames. `tint` lets the same texture read as
## dark steel, warm rust, or (Crane Yard) safety-accented, purely via color
## multiply — no extra texture needed (spec section 28: don't multiply
## material count unboundedly).
func rust_metal_material(tint: Color = Color(1, 1, 1), uv_scale: Vector2 = Vector2(1, 1)) -> StandardMaterial3D:
 return textured_material(T_RUST_METAL_BASE, T_RUST_METAL_NORMAL, T_RUST_METAL_ORM, tint, uv_scale)

## Dark worn asphalt — broken road remnants (spec section 10).
func broken_asphalt_material(tint: Color = Color(0.85, 0.78, 0.68), uv_scale: Vector2 = Vector2(1, 1)) -> StandardMaterial3D:
 return textured_material(T_ASPHALT_BASE, null, null, tint, uv_scale)

## Sandy/dusty ground cover (spec sections 8-9).
func sand_material(tint: Color = Color(1, 1, 1), uv_scale: Vector2 = Vector2(1, 1)) -> StandardMaterial3D:
 return textured_material(T_SAND_BASE, T_SAND_NORMAL, T_SAND_ORM, tint, uv_scale)

## Plain weathered concrete — Broken Highway deck/pillars, Industrial Ruins
## slabs.
func concrete_material(tint: Color = Color(1, 1, 1), uv_scale: Vector2 = Vector2(1, 1)) -> StandardMaterial3D:
 return textured_material(T_CONCRETE_BASE, T_CONCRETE_NORMAL, T_CONCRETE_ORM, tint, uv_scale)

## Same shape as City.box(): a StaticBody3D with one BoxMesh + matching
## BoxShape3D child, on the default physics layer/mask City's own hookable
## surfaces already use (so City.manual_target()'s raycast picks these up
## with zero extra wiring). `hookable`/`building` metas mirror City's own
## convention exactly, so an ordinary structure reads as a normal safe-to-
## touch wall (Rider.integrate()'s obstacle-damage branch only triggers for
## colliders that are neither "road" nor "building").
##
## `visual_mat`, if given, replaces the flat `color` material on the MESH
## only — the StaticBody3D + CollisionShape3D (the actual wire-target/
## gameplay geometry, spec section 3/43) are built from `size`/`pos` exactly
## as before, completely unaffected by which material the mesh uses. This
## is this file's whole "GameplayRoot/CollisionRoot vs VisualRoot"
## separation in practice: one shared collision box, a swappable visual
## layer on top of it.
func box(parent: Node3D, pos: Vector3, size: Vector3, color: Color, solid: bool = false, visual_mat: StandardMaterial3D = null) -> Node3D:
 var root: Node3D = StaticBody3D.new() if solid else Node3D.new()
 parent.add_child(root)
 root.position = pos
 var mesh := MeshInstance3D.new()
 var box_mesh := BoxMesh.new()
 box_mesh.size = size
 mesh.mesh = box_mesh
 mesh.material_override = visual_mat if is_instance_valid(visual_mat) else material(color)
 mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF if not solid else GeometryInstance3D.SHADOW_CASTING_SETTING_ON
 root.add_child(mesh)
 if solid:
  var collision := CollisionShape3D.new()
  var shape := BoxShape3D.new()
  shape.size = size
  collision.shape = shape
  root.add_child(collision)
 return root

func decoration(parent: Node3D, pos: Vector3, size: Vector3, color: Color, visual_mat: StandardMaterial3D = null) -> MeshInstance3D:
 var mesh := MeshInstance3D.new()
 var box_mesh := BoxMesh.new()
 box_mesh.size = size
 mesh.mesh = box_mesh
 mesh.position = pos
 mesh.material_override = visual_mat if is_instance_valid(visual_mat) else material(color)
 mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
 parent.add_child(mesh)
 return mesh

## A translucent, unshaded decoration with its own fresh (never cached/
## shared) material — used for hazy distant silhouettes (Dust telegraph
## wall, City-fade skyline). Deliberately NOT built through decoration()'s
## shared material() cache: mutating a cached material's transparency after
## the fact would silently change every other decoration sharing that same
## color/cache key.
func transparent_decoration(parent: Node3D, pos: Vector3, size: Vector3, color: Color) -> MeshInstance3D:
 var mesh := MeshInstance3D.new()
 var box_mesh := BoxMesh.new()
 box_mesh.size = size
 mesh.mesh = box_mesh
 mesh.position = pos
 var mat := StandardMaterial3D.new()
 mat.albedo_color = color
 mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
 mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
 mesh.material_override = mat
 mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
 parent.add_child(mesh)
 return mesh

func hookable_structure(parent: Node3D, pos: Vector3, size: Vector3, color: Color, visual_mat: StandardMaterial3D = null) -> Node3D:
 var body: Node3D = box(parent, pos, size, color, true, visual_mat)
 body.set_meta("hookable", true)
 body.set_meta("building", true)
 return body

## A real, wireable LOW or HIGH route anchor at the given chunk-local
## position (from anchor_chain()) — every route anchor in the game is
## created through this one function, so "is this node part of the route
## system" is always exactly `n.get_meta("route", "") in ["LOW","HIGH"]`.
func spawn_route_anchor(chunk: Node3D, pos: Vector3, route: String, color: Color, size: Vector3 = Vector3(1.4, 1.4, 1.4), visual_mat: StandardMaterial3D = null) -> Node3D:
 var tint: Color = LOW_ROUTE_TINT if route == ROUTE_LOW else HIGH_ROUTE_TINT
 var blended: Color = color.lerp(tint, 0.4)
 var anchor: Node3D = hookable_structure(chunk, pos, size, blended, visual_mat)
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
    # PHASE W-D: rust-metal material (dark-steel tint for the lower pole,
    # a warmer weathered tint for the taller high pole, spec section 34's
    # "LOW = grounded, HIGH = skyline exposed" distinction).
    spawn_route_anchor(chunk, low_pos, ROUTE_LOW, STRUCTURE_DARK_COLOR, Vector3(0.9, 9.0, 0.9), rust_metal_material(Color(0.55, 0.55, 0.58), Vector2(0.9, 9.0) / 4.0))
    var high_pole: Node3D = spawn_route_anchor(chunk, high_pos, ROUTE_HIGH, STRUCTURE_COLOR, Vector3(0.9, 20.0, 0.9), rust_metal_material(Color(0.72, 0.62, 0.5), Vector2(0.9, 20.0) / 4.0))
    decoration(high_pole, Vector3(0, 9.0, 0), Vector3(4.0, 0.4, 0.4), STRUCTURE_DARK_COLOR, rust_metal_material(Color(0.55, 0.55, 0.58), Vector2(4.0, 0.4) / 2.0))
   ARCHETYPE_BROKEN_HIGHWAY:
    # Low = support column stub (matches the deck's own columns); high =
    # a short deck fragment at anchor height, so the HIGH route reads as
    # "walking the remaining road" one piece at a time.
    # PHASE W-D: weathered concrete column, cracked-asphalt deck top.
    spawn_route_anchor(chunk, low_pos, ROUTE_LOW, STRUCTURE_DARK_COLOR, Vector3(1.2, 10.0, 1.2), concrete_material(Color(0.8, 0.76, 0.7), Vector2(1.2, 10.0) / 3.0))
    var deck_piece: Node3D = spawn_route_anchor(chunk, high_pos, ROUTE_HIGH, STRUCTURE_COLOR, Vector3(6.0, 1.0, 4.0), concrete_material(Color(0.78, 0.73, 0.66), Vector2(6.0, 4.0) / 3.0))
    decoration(deck_piece, Vector3(0, 0.7, 0), Vector3(6.0, 0.35, 4.0), RUST_COLOR, broken_asphalt_material(Color(0.7, 0.58, 0.46), Vector2(6.0, 4.0) / 3.0))
   ARCHETYPE_INDUSTRIAL_RUINS:
    # PHASE W-D: open rust-metal frame (spec section 15 — never a solid
    # City-style wall).
    spawn_route_anchor(chunk, low_pos, ROUTE_LOW, STRUCTURE_DARK_COLOR, Vector3(2.4, 4.0, 2.4), rust_metal_material(Color(0.6, 0.5, 0.42), Vector2(2.4, 4.0) / 3.0))
    spawn_route_anchor(chunk, high_pos, ROUTE_HIGH, STRUCTURE_COLOR, Vector3(2.4, 4.0, 2.4), rust_metal_material(Color(0.62, 0.55, 0.46), Vector2(2.4, 4.0) / 3.0))
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
## PHASE W-D (spec sections 8-10): textured, varied ground instead of one
## flat color plane — `decay` fades from "still reads as broken road" right
## at the City/Wasteland boundary to "fully sand/dirt" further in (the
## City-road -> cracks -> sand -> broken-remnants transition spec section
## 10 asks for), using distance from first_chunk_index() as the only input
## (deterministic, no new state).
func spawn_ground(chunk: Node3D, index: int) -> void:
 var local_index: int = index - first_chunk_index()
 var decay: float = clampf(1.0 - float(local_index) / 24.0, 0.0, 1.0)
 var ground_tint: Color = Color(0.62, 0.55, 0.44).lerp(Color(0.74, 0.65, 0.5), 1.0 - decay)
 var ground_mat: StandardMaterial3D = broken_asphalt_material(ground_tint, Vector2(20.0, LENGTH) / 6.0) if decay > 0.15 else sand_material(ground_tint, Vector2(20.0, LENGTH) / 6.0)
 var ground := box(chunk, Vector3(0, -0.5, -32), Vector3(20, 1, LENGTH), GROUND_COLOR, true, ground_mat)
 ground.set_meta("road", true)
 for i in range(3):
  var crack := decoration(chunk, Vector3((i - 1) * 5.5, 0.03, -8 - i * 20), Vector3(0.15, 0.04, 10 + i * 3), GROUND_CRACK_COLOR)
  crack.rotation.y = (float(i) - 1.0) * 0.15
 # Sand drift patches — per-chunk hash-placed/sized (spec section 9: subtle
 # per-chunk variation without touching gameplay height), more coverage the
 # further from the City boundary (spec section 10's transition).
 var sand_count: int = 1 + int(round((1.0 - decay) * 2.0))
 var loose_sand: StandardMaterial3D = sand_material(Color(0.86, 0.78, 0.62), Vector2(1, 1))
 for i in range(sand_count):
  var seed: int = wasteland_hash(index * 19 + i * 31)
  var sx: float = float(posmod(seed, 14)) - 7.0
  var sz: float = -4.0 - float(posmod(seed / 14, 14)) * 4.0
  var patch := decoration(chunk, Vector3(sx, 0.02, sz), Vector3(4.0 + float(posmod(seed, 4)), 0.03, 5.0 + float(posmod(seed / 4, 4))), Color.WHITE, loose_sand)
  patch.rotation.y = float(posmod(seed, 30)) * 0.05
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
 # PHASE W-D City -> Wasteland transition (spec section 47): a fading
 # chance of a hazy, distant City-skyline silhouette for the first ~20
 # chunks after entry, tapering to 0 — City's own real chunks are already
 # freed behind the player well before this range (City.update_chunks()'s
 # normal cleanup), so this decorative silhouette is what actually gives
 # the "the city recedes behind you" read, not lingering real geometry.
 var local_index: int = index - first_chunk_index()
 if local_index >= 0 and local_index < 20:
  var chance: int = wasteland_hash(index * 41 + 7) % 20
  if chance < 20 - local_index:
   var side: int = 1 if posmod(index, 2) == 0 else -1
   var cx: float = side * (70.0 + float(wasteland_hash(index * 3) % 20))
   var cz: float = -30.0
   var fade: float = 0.55 * clampf(1.0 - float(local_index) / 20.0, 0.15, 1.0)
   transparent_decoration(chunk, Vector3(cx, 18.0, cz), Vector3(3.0, 36.0, 3.0), Color(0.55, 0.58, 0.62, fade))
   transparent_decoration(chunk, Vector3(cx + side * 4.0, 12.0, cz - 5.0), Vector3(2.2, 24.0, 2.2), Color(0.55, 0.58, 0.62, fade * 0.8))

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
 var steel: StandardMaterial3D = rust_metal_material(Color(0.5, 0.5, 0.54), Vector2(1.6, tower_height) / 4.0)
 # Split the mast into a LOW lower half and a HIGH upper half (each its own
 # collision) instead of one tall box, so the tower itself is both a LOW
 # and a HIGH anchor exactly like the spec's "tower middle / cross arm"
 # split, not just decoration around the generic chain.
 spawn_route_anchor(chunk, Vector3(x, tower_height * 0.28, z), ROUTE_LOW, STRUCTURE_COLOR, Vector3(1.6, tower_height * 0.56, 1.6), steel)
 var upper: Node3D = spawn_route_anchor(chunk, Vector3(x, tower_height * 0.78, z), ROUTE_HIGH, STRUCTURE_COLOR, Vector3(1.6, tower_height * 0.44, 1.6), steel)
 decoration(upper, Vector3(0, tower_height * 0.15, 0), Vector3(9.0, 0.6, 0.6), STRUCTURE_DARK_COLOR, steel)
 decoration(upper, Vector3(0, tower_height * 0.44, 0), Vector3(0.9, 2.2, 0.9), STRUCTURE_DARK_COLOR, steel)
 # PHASE W-D lattice cross-bracing (spec section 11-12): thin diagonal
 # struts down the mast's visible faces so the silhouette reads as a real
 # lattice tower from a distance, not a plain pole — purely decorative,
 # never touches the mast's own collision (the two spawn_route_anchor()
 # calls above own that, unchanged).
 var brace_color := Color(0.42, 0.4, 0.42)
 for i in range(4):
  var brace_y: float = 3.0 + float(i) * 6.5
  for sign in [-1.0, 1.0]:
   var brace := decoration(chunk, Vector3(x, brace_y, z + sign * 0.75), Vector3(1.7, 0.18, 0.18), brace_color, steel)
   brace.rotation.x = sign * 0.5

func spawn_broken_highway_landmark(chunk: Node3D, chain: Dictionary) -> void:
 var z: float = ANCHOR_Z[TRANSITION_SLOT]
 var deck_height: float = 20.0
 var deck_concrete: StandardMaterial3D = concrete_material(Color(0.75, 0.71, 0.65), Vector2(14.0, 20.0) / 4.0)
 var deck: Node3D = decoration(chunk, Vector3(2.0, deck_height, z), Vector3(14.0, 1.2, 20.0), STRUCTURE_COLOR, deck_concrete)
 decoration(deck, Vector3(0, 0.9, 0), Vector3(14.0, 0.4, 20.0), RUST_COLOR, broken_asphalt_material(Color(0.65, 0.55, 0.44), Vector2(14.0, 20.0) / 4.0))
 # The broken edge: a jagged, exposed end with rebar-like fins instead of a
 # clean cut, plus rubble on the ground below it — purely decorative,
 # reading as where the road used to continue.
 var broken_x: float = 2.0
 var broken_z: float = z - 10.0
 decoration(chunk, Vector3(broken_x - 5.0, deck_height - 0.9, broken_z), Vector3(2.0, 1.0, 1.6), RUST_COLOR, deck_concrete)
 var rebar: StandardMaterial3D = rust_metal_material(Color(0.62, 0.42, 0.3), Vector2(1, 1))
 for i in range(3):
  var fin := decoration(chunk, Vector3(broken_x - 5.0 + float(i) * 2.6, deck_height - 1.6, broken_z), Vector3(0.15, 1.6, 0.15), STRUCTURE_DARK_COLOR, rebar)
  fin.rotation.x = 0.35
 decoration(chunk, Vector3(broken_x - 1.0, 1.0, broken_z), Vector3(6.0, 1.6, 5.0), STRUCTURE_DARK_COLOR, deck_concrete)

func spawn_industrial_ruins_landmark(chunk: Node3D, chain: Dictionary) -> void:
 var side: int = chain["side"]
 var x: float = side * 9.5
 var z: float = ANCHOR_Z[TRANSITION_SLOT]
 var height: float = 22.0
 var frame: StandardMaterial3D = rust_metal_material(Color(0.58, 0.48, 0.4), Vector2(7.5, 7.5) / 3.0)
 var frame_tall: StandardMaterial3D = rust_metal_material(Color(0.58, 0.48, 0.4), Vector2(0.5, height) / 3.0)
 for level in range(3):
  var y: float = 5.0 + float(level) * 6.0
  decoration(chunk, Vector3(x, y, z), Vector3(7.5, 0.4, 7.5), STRUCTURE_DARK_COLOR, frame)
 for corner_x in [-1, 1]:
  for corner_z in [-1, 1]:
   decoration(chunk, Vector3(x + corner_x * 3.0, height * 0.5, z + corner_z * 3.0), Vector3(0.5, height, 0.5), STRUCTURE_DARK_COLOR, frame_tall)

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

func spawn_machine_wreck(chunk: Node3D, base: Vector3) -> void:
 var wreck_metal: StandardMaterial3D = rust_metal_material(Color(0.68, 0.42, 0.28), Vector2(7.0, 6.0) / 3.0)
 var main_body: Node3D = hookable_structure(chunk, base + Vector3(0, 2.5, 0), Vector3(7.0, 5.0, 6.0), RUST_COLOR, wreck_metal)
 main_body.set_meta("route", ROUTE_LOW)
 var tilted := decoration(main_body, Vector3(3.0, 3.0, 1.0), Vector3(4.0, 3.0, 4.0), STRUCTURE_DARK_COLOR, wreck_metal)
 tilted.rotation.z = 0.25
 decoration(main_body, Vector3(-2.0, 4.5, -1.0), Vector3(1.0, 4.0, 1.0), STRUCTURE_DARK_COLOR, wreck_metal)
 # PHASE W-D: a bent boom/arm and scattered debris (spec section 23 —
 # "excavator-like wreck") so the silhouette reads as fallen machinery, not
 # a plain crate.
 var arm := decoration(main_body, Vector3(1.5, 5.5, 2.0), Vector3(6.0, 0.9, 0.9), STRUCTURE_DARK_COLOR, wreck_metal)
 arm.rotation.z = -0.4
 arm.rotation.y = 0.3
 decoration(main_body, Vector3(-3.2, 0.5, 2.6), Vector3(1.4, 0.8, 1.4), STRUCTURE_DARK_COLOR, wreck_metal)

# ---------------------------------------------------------------------
# PHASE W-C EVENT: DUST ZONE (spec sections 11-18). Visibility-pressure
# only — no wind/gravity/wire modifier (spec section 16) — see
# dust_intensity()/apply_environment() above for the actual fog blend this
# pairs with. This function only adds the local, purely decorative particle
# haze; it never touches Environment itself (avoids per-chunk Environment
# churn — one shared blend already handles the whole zone smoothly).
# ---------------------------------------------------------------------
func spawn_dust_zone(chunk: Node3D, index: int) -> void:
 var particles := GPUParticles3D.new()
 # Modest count (spec section 49: gl_compatibility performance) — this is a
 # soft haze layer, not a dense sandstorm.
 particles.amount = 22
 particles.lifetime = 5.0
 particles.local_coords = false
 particles.position = Vector3(0, 9.0, -32)
 var quad := QuadMesh.new()
 quad.size = Vector2(4.0, 4.0)
 var dust_material := StandardMaterial3D.new()
 dust_material.albedo_color = Color(0.62, 0.52, 0.4, 0.16)
 dust_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
 dust_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
 dust_material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
 quad.material = dust_material
 particles.draw_pass_1 = quad
 var mat := ParticleProcessMaterial.new()
 mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
 mat.emission_box_extents = Vector3(20.0, 16.0, LENGTH * 0.5)
 mat.direction = Vector3(0, 0, 1)
 mat.spread = 25.0
 mat.initial_velocity_min = 0.3
 mat.initial_velocity_max = 1.0
 mat.gravity = Vector3.ZERO
 mat.scale_min = 0.8
 mat.scale_max = 1.6
 particles.process_material = mat
 chunk.add_child(particles)
 # A faint silhouette wall well before the zone's own entrance (spec
 # section 17: world-space telegraph, no HUD popup) — cheap, decorative,
 # visible from the previous normal chunk.
 transparent_decoration(chunk, Vector3(0, 10.0, 4.0), Vector3(26.0, 20.0, 2.0), Color(0.55, 0.47, 0.38, 0.12))

# ---------------------------------------------------------------------
# PHASE W-C EVENT: TURBINE FIELD (spec sections 19-29). Tower/nacelle stay
# hookable route anchors exactly like the old static turbine; only the
# blades are new — a real moving hazard via a rotating AnimatableBody3D hub
# (registered in spinning_hubs, spun by update_spinning_hubs() every
# physics frame). Placed well outside the guaranteed anchor_chain()'s own
# X range (+-6..9m) so the always-valid base route never has to pass
# through a blade sweep — the event is an optional, avoidable risk/reward
# detour, never a mandatory hazard (spec section 40).
# ---------------------------------------------------------------------
const TURBINE_BLADE_SIZE := Vector3(0.35, 8.0, 0.35)
const TURBINE_BASE_ANGULAR_SPEED: float = 0.4

func spawn_turbine_field(chunk: Node3D, index: int, slot: int) -> void:
 # Entrance/exit chunk: 1 turbine. Middle chunk: 2 turbines, offset to
 # opposite sides — 2 to 4 across the whole field (spec section 27), never
 # more than 2 in view on one chunk (spec section 27: no visual clutter).
 var turbine_count: int = 2 if slot == 1 else 1
 for n in range(turbine_count):
  var side: int = 1 if posmod(index * 3 + n, 2) == 0 else -1
  var x: float = side * (17.0 + float(n) * 6.0)
  var z: float = -10.0 - float(n) * 24.0
  spawn_event_turbine(chunk, index, n, Vector3(x, 0, z))

func spawn_event_turbine(chunk: Node3D, index: int, seed_n: int, base: Vector3) -> void:
 var tower_height: float = 22.0
 var tower_mat: StandardMaterial3D = rust_metal_material(Color(0.82, 0.8, 0.76), Vector2(1.2, tower_height) / 4.0)
 var tower: Node3D = hookable_structure(chunk, base + Vector3(0, tower_height * 0.5, 0), Vector3(1.2, tower_height, 1.2), Color("cfcabf"), tower_mat)
 tower.set_meta("route", ROUTE_LOW)
 var nacelle_pos: Vector3 = base + Vector3(0, tower_height + 1.0, 0)
 var nacelle: Node3D = hookable_structure(chunk, nacelle_pos, Vector3(3.4, 1.6, 1.6), Color("b7b1a3"), rust_metal_material(Color(0.72, 0.7, 0.66), Vector2(3.4, 1.6) / 2.0))
 nacelle.set_meta("route", ROUTE_HIGH)
 # The spinning hub is a SEPARATE body from the (stationary, hookable)
 # nacelle — real moving collision needs a kinematic AnimatableBody3D (spec
 # section 21), and deliberately non-hookable (spec section 23): wire-
 # attaching to a rotating body has no established behavior in this
 # codebase's wire physics (every existing anchor is stationary, same
 # reasoning CityBoss.spawn_robot() already documents for its own hazards).
 var hub := AnimatableBody3D.new()
 hub.sync_to_physics = false
 chunk.add_child(hub)
 hub.position = nacelle_pos + Vector3(0, 0, 0.9)
 hub.set_meta("hazard", true)
 hub.set_meta("hookable", false)
 # PHASE W-D readability (spec section 19): each blade is visually two-tone
 # — a light body + a darker tip band, like a real turbine's tip paint —
 # purely a second MeshInstance3D layered on top; the COLLISION shape below
 # still spans the blade's full length unchanged, so this never touches
 # gameplay hit-detection (spec section 43).
 var blade_body_mat: StandardMaterial3D = material(Color("d8d3c6"))
 var blade_tip_mat: StandardMaterial3D = material(Color("3d2f28"))
 for angle_deg in [0.0, 120.0, 240.0]:
  var blade := Node3D.new()
  blade.position = Vector3(0, TURBINE_BLADE_SIZE.y * 0.5, 0)
  blade.rotation.z = deg_to_rad(angle_deg)
  hub.add_child(blade)
  var body_mesh := MeshInstance3D.new()
  var body_box := BoxMesh.new()
  body_box.size = Vector3(TURBINE_BLADE_SIZE.x, TURBINE_BLADE_SIZE.y * 0.8, TURBINE_BLADE_SIZE.z)
  body_mesh.mesh = body_box
  body_mesh.position = Vector3(0, -TURBINE_BLADE_SIZE.y * 0.1, 0)
  body_mesh.material_override = blade_body_mat
  body_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
  blade.add_child(body_mesh)
  var tip_mesh := MeshInstance3D.new()
  var tip_box := BoxMesh.new()
  tip_box.size = Vector3(TURBINE_BLADE_SIZE.x, TURBINE_BLADE_SIZE.y * 0.2, TURBINE_BLADE_SIZE.z)
  tip_mesh.mesh = tip_box
  tip_mesh.position = Vector3(0, TURBINE_BLADE_SIZE.y * 0.4, 0)
  tip_mesh.material_override = blade_tip_mat
  tip_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
  blade.add_child(tip_mesh)
  var collision := CollisionShape3D.new()
  var shape := BoxShape3D.new()
  shape.size = TURBINE_BLADE_SIZE
  collision.shape = shape
  collision.position = blade.position
  collision.rotation.z = blade.rotation.z
  hub.add_child(collision)
 # Direction/speed variation per turbine (spec section 26) — deterministic,
 # kept gentle (spec section 25: readable timing, no upgrade required).
 var direction: int = 1 if posmod(index * 17 + seed_n * 5, 2) == 0 else -1
 var speed: float = TURBINE_BASE_ANGULAR_SPEED + float(posmod(index * 23 + seed_n * 7, 5)) * 0.05
 spinning_hubs.append({"node": hub, "speed": direction * speed})

# ---------------------------------------------------------------------
# PHASE W-C EVENT: CRANE YARD (spec sections 30-37). Static-only in this
# pass (spec section 32: fully optional to add movement — intentionally
# skipped here to keep the first pass shippable and low-risk; see
# completion report). Tower/boom stay hookable bonus LOW/HIGH anchors, the
# same shape as the old static crane, just placed across the field's slots
# with varying height to read as a LOW->HIGH->LOW vertical rhythm (spec
# section 35) rather than one repeated silhouette.
# ---------------------------------------------------------------------
const CRANE_YARD_HEIGHTS: Array[float] = [16.0, 26.0, 16.0]

func spawn_crane_yard(chunk: Node3D, index: int, slot: int) -> void:
 var side: int = 1 if posmod(index, 2) == 0 else -1
 var tower_height: float = CRANE_YARD_HEIGHTS[clampi(slot, 0, CRANE_YARD_HEIGHTS.size() - 1)]
 spawn_event_crane(chunk, Vector3(side * 13.0, 0, -30.0), tower_height)
 # A second, opposite-side crane only at the field's tallest/middle slot
 # (spec section 27-style restraint applied here too: readable, not
 # cluttered) — this is what actually offers a LOW<->HIGH cross choice
 # between two cranes, not just height variation on one.
 if slot == 1:
  spawn_event_crane(chunk, Vector3(-side * 16.0, 0, -14.0), 20.0)

## Crane Yard's own accent (spec section 17: "industrial yellow/rust/gray
## accents" is this event's visual-identity marker — cranes only ever
## appear inside a Crane Yard event now that W-C removed the old ambient
## random crane, so this is always a genuine Crane Yard signal, never
## background noise).
const CRANE_YARD_ACCENT := Color("d9a02a")

func spawn_event_crane(chunk: Node3D, base: Vector3, tower_height: float) -> void:
 var steel: StandardMaterial3D = rust_metal_material(Color(0.6, 0.44, 0.3), Vector2(1.3, tower_height) / 4.0)
 var tower: Node3D = hookable_structure(chunk, base + Vector3(0, tower_height * 0.5, 0), Vector3(1.3, tower_height, 1.3), RUST_COLOR, steel)
 tower.set_meta("route", ROUTE_LOW)
 var boom: Node3D = hookable_structure(chunk, base + Vector3(5.0, tower_height, 0), Vector3(10.0, 0.8, 0.8), RUST_COLOR, rust_metal_material(CRANE_YARD_ACCENT, Vector2(10.0, 0.8) / 2.0))
 boom.set_meta("route", ROUTE_HIGH)
 decoration(boom, Vector3(-6.4, 0.6, 0), Vector3(1.6, 2.0, 1.6), STRUCTURE_DARK_COLOR, steel)
 # A hanging cable/hook (spec section 16/36) — landmark/visual only, never
 # a wire target (spec section 36: a small moving target would hurt
 # readability, so it's deliberately not hookable and not part of the
 # route system).
 var cable := decoration(boom, Vector3(3.0, -2.2, 0), Vector3(0.12, 4.4, 0.12), Color(0.2, 0.2, 0.2))
 decoration(cable, Vector3(0, -2.2, 0), Vector3(0.8, 0.6, 0.8), Color(0.3, 0.28, 0.26))

# ---------------------------------------------------------------------
# PHASE W-D: event entrance telegraphs (spec section 36) — a small, distant
# silhouette hint placed on the NORMAL chunk immediately before a Turbine
# Field or Crane Yard window, purely decorative (never hookable, never a
# hazard), so the player can read "something's coming" one chunk early
# without any HUD.
# ---------------------------------------------------------------------
func spawn_turbine_telegraph(chunk: Node3D) -> void:
 var mat: StandardMaterial3D = rust_metal_material(Color(0.75, 0.73, 0.68), Vector2(1, 1))
 decoration(chunk, Vector3(20.0, 12.0, -50.0), Vector3(0.8, 24.0, 0.8), Color("cfcabf"), mat)
 decoration(chunk, Vector3(20.0, 24.4, -50.0), Vector3(2.6, 1.2, 2.6), Color("b7b1a3"), mat)

func spawn_crane_telegraph(chunk: Node3D) -> void:
 var mat: StandardMaterial3D = rust_metal_material(Color(0.6, 0.46, 0.32), Vector2(1, 1))
 decoration(chunk, Vector3(-18.0, 10.0, -50.0), Vector3(1.0, 20.0, 1.0), RUST_COLOR, mat)
 decoration(chunk, Vector3(-14.0, 19.0, -50.0), Vector3(8.0, 0.6, 0.6), RUST_COLOR, rust_metal_material(CRANE_YARD_ACCENT, Vector2(1, 1)))

# ---------------------------------------------------------------------
# PHASE W-D: Wasteland Entry Landmark (spec section 48) — one deliberate,
# guaranteed large structure at the very first Wasteland chunk (never a
# random roll), on top of whatever that chunk's own archetype already
# placed. Purely decorative/optional-hookable — never load-bearing for the
# guaranteed base route (same rule every other landmark in this file
# already follows).
# ---------------------------------------------------------------------
func spawn_entry_landmark(chunk: Node3D) -> void:
 var steel: StandardMaterial3D = rust_metal_material(Color(0.62, 0.46, 0.34), Vector2(1, 1))
 var z: float = -46.0
 for i in range(3):
  var x: float = -18.0 + float(i) * 18.0
  var tower: Node3D = hookable_structure(chunk, Vector3(x, 14.0, z), Vector3(1.6, 28.0, 1.6), STRUCTURE_COLOR, steel)
  tower.set_meta("route", ROUTE_LOW)
  decoration(tower, Vector3(0, 12.0, 0), Vector3(9.0, 0.6, 0.6), STRUCTURE_DARK_COLOR, steel)
  if i < 2:
   var span := decoration(chunk, Vector3(x + 9.0, 24.0, z), Vector3(0.15, 0.15, 2.0), Color(0.25, 0.24, 0.22))
   span.rotation.x = 0.05
