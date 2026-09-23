extends Node3D
## WASTELAND PHASE W-E: CRAWLER — the Wasteland chapter boss. Not a combat
## boss: no HP, no damage phase, no weak point, no player attack. The
## Crawler is a giant six-legged walking machine that the player traverses
## — rear -> underbody -> upper body -> front — using only existing
## traversal abilities (Wire, Jump, Double Jump, Skate, Armor). Clear
## condition is relative position (player gets ahead of the Crawler's own
## front), never HP (spec section 3/32/66).
##
## Deliberately its own script/lifecycle rather than an extension of
## city_boss.gd (spec section 6) — City's boss is a stationary-relative-to-
## player flying attacker with telegraphed hazard volumes; the Crawler is a
## large physical structure that moves at its OWN pace and must be
## APPROACHED, so "follow the player" (city_boss.gd's position_near_player())
## would be actively wrong here. What IS reused: the same state-machine
## shape (INACTIVE/INTRO/ACTIVE/ESCAPE/CLEARED), the same
## AnimatableBody3D-for-moving-collision convention City's own vehicles/
## robots/Wasteland's Turbine blades already established, and the same
## Rider.hurt("OBSTACLE COLLISION") reuse for any hazard contact.
##
## No Player Progression is read or written here (same rule W-A through
## W-D already followed for the rest of Wasteland).
const Rules = preload("res://scripts/rules.gd")
const Wasteland = preload("res://scripts/wasteland.gd")

signal cue(kind: String)

const STATE_INACTIVE: String = "INACTIVE"
const STATE_INTRO: String = "INTRO"
const STATE_ACTIVE: String = "ACTIVE"
const STATE_ESCAPE: String = "ESCAPE"
const STATE_CLEARED: String = "CLEARED"

## Slower than typical player travel speed (spec section 15) so a player
## approaching from behind can always close the gap — never an unwinnable
## chase. Empirically tuned via tools/Crawler-Boss-QA.gd (real physics, no
## invincibility, real death rule): 9.0 let the Crawler outrun a real
## traversal attempt entirely (ESCAPE never triggered, no matter how long
## the run went on) — not a graceful "hard boss", just an uncatchable one.
## That in turn surfaced a real QA-controller bug (fixed): judging "arrived
## at this anchor, grab the next one" by raw 3D distance alone falsely
## fired while a fresh hook was still mid-flight toward a nearby target,
## causing fire_manual() to cancel and re-fire every tick and eventually
## strand the rider mid-air with no wire at all. With that fixed, 5.0
## cleared cleanly with zero hits taken and zero navigation stalls in
## repeated real runs; 8.0 reintroduced stalls. 5.0 is the tuned value —
## still real margin below where the bot demonstrably struggles, but a
## human player (who reads anchors visually and chains momentum, unlike
## this bot's simple greedy strategy) should feel a properly brisk chase,
## not a slow crawl. See [HUMAN QA REQUIRED] in the phase completion
## report for why this number still deserves a real playtest.
const CRAWLER_SPEED: float = 5.0
const INTRO_DURATION: float = 1.4
## World-space gap (m) between the player and the Crawler's own rear
## anchor the instant the encounter triggers — spec section 19 requires
## this connection to sit within real base wire range, so it stays
## comfortably under Rules.ROPE_RANGE (30) with the same practical margin
## MAX_BOSS_GAP itself uses elsewhere. Still not a trivial hand's-reach
## grab: INTRO_DURATION plus the player's own forward momentum is what
## turns this into a felt "catching up" beat, not the raw distance alone.
const INTRO_REAR_GAP: float = 22.0
const ESCAPE_DURATION: float = 2.0

# ---------------------------------------------------------------------
# Hand-authored anchor stations, Crawler-ROOT-local space (rear = +Z,
# front = -Z, matching the player's own -Z travel direction). This is a
# single unique encounter, not a repeating procedural chunk, so — unlike
# Wasteland.anchor_chain()'s per-index generator — these are a fixed list,
# validated directly (spec section 38) rather than hashed/retried. Every
# consecutive gap (within a route) is verified in tests/crawler_boss.gd to
# stay under MAX_BOSS_GAP, itself under Rules.ROPE_RANGE with the same
# practical margin Wasteland's own MAX_BASE_TRAVERSAL_GAP uses.
# ---------------------------------------------------------------------
const APPROACH_Z: float = 38.0
const OVERTAKE_HIGH_Z: float = -40.0
const ESCAPE_MARKER_Z: float = -52.0
const MAX_BOSS_GAP: float = 22.0

const LOW_ANCHORS: Array[Vector3] = [
 Vector3(0, 6, 38),     # Phase 1 APPROACH — rear, centered, easy first grab
 Vector3(5, 5, 24),     # Phase 2 UNDERBODY — near back-leg hips
 Vector3(-5, 5, 10),
 Vector3(5, 5, -4),     # near mid-leg hips
 Vector3(-5, 6, -18),
 Vector3(5, 6, -30),    # near front-leg hips
 Vector3(0, 7, -42),    # Phase 4 OVERTAKE — front low frame
]
const HIGH_ANCHORS: Array[Vector3] = [
 Vector3(0, 14, 34),    # Phase 1 APPROACH HIGH — side rail start
 Vector3(-6, 16, 20),   # Phase 2/3 — upper leg joint area (back)
 Vector3(6, 18, 6),     # side rail mid
 Vector3(-6, 20, -8),   # Phase 3 UPPER BODY — near the rotating arm hazard
 Vector3(6, 22, -22),   # top deck, approaching the front mast
 Vector3(0, 20, OVERTAKE_HIGH_Z), # Phase 4 OVERTAKE HIGH — front mast top
]

## Fixed stepping order (spec section 12) — one leg animates at a time,
## never simultaneously, so an early player can read each step in
## isolation. LEG_CONFIG order matches the spec's own example sequence
## (Left Front -> Right Mid -> Left Back -> Right Front -> Left Mid ->
## Right Back).
const LEG_CONFIG: Array[Dictionary] = [
 {"name": "FL", "side": -1, "z": -22.0},
 {"name": "MR", "side": 1, "z": 0.0},
 {"name": "BL", "side": -1, "z": 22.0},
 {"name": "FR", "side": 1, "z": -22.0},
 {"name": "ML", "side": -1, "z": 0.0},
 {"name": "BR", "side": 1, "z": 22.0},
]
const LEG_HIP_X: float = 9.0
const LEG_HIP_Y: float = 12.0
const LEG_FOOT_X: float = 11.0
const LEG_FOOT_Y_REST: float = 0.5
const LEG_FOOT_Y_LIFT: float = 5.0
## Slow, deliberately readable (spec section 14) — a full 6-leg cycle takes
## this long, one leg's own lift/plant taking a 6th of it.
const LEG_CYCLE_DURATION: float = 4.2
const LEG_STEP_DURATION: float = 0.7

const UPPER_HAZARD_SPEED: float = 0.5
const UPPER_HAZARD_LENGTH: float = 12.0
const UPPER_HAZARD_POSITION := Vector3(0, 26.0, -14.0)

const DARK_METAL := Color("2b2b2e")
const UPPER_METAL := Color("3a3934")
const JOINT_COLOR := Color("7a7568")
const RUST_ACCENT := Color("6b4530")
const SENSOR_GLOW := Color("ff5533")

var rider: CharacterBody3D
var wasteland: Node3D
var state: String = STATE_INACTIVE
var phase_timer: float = 0.0
var leg_cycle_time: float = 0.0
var legs: Array = []
var upper_hazard: AnimatableBody3D
var escape_marker: Node3D
var material_cache: Dictionary = {}

func _ready() -> void:
 build_body()
 reset()

func reset() -> void:
 state = STATE_INACTIVE
 phase_timer = 0.0
 leg_cycle_time = 0.0
 visible = false
 # Parked far outside any reachable play space — collision shapes are
 # real StaticBody3D/AnimatableBody3D nodes that always exist (built once
 # in _ready(), never recreated per-encounter), so "inactive" has to mean
 # "physically nowhere near the track", not just "invisible" (spec section
 # 52).
 global_position = Vector3(0, 0, 200000.0)

## Called every physics frame from Main._physics_process(), the same
## convention as Wasteland.update_events()/City.update_vehicles() —
## unconditional, not gated on `not training`. Unlike CityBoss (gated on
## `not training`), Wasteland itself is currently only ever reached via
## practice mode (Main.complete_city() halts _physics_process() at the
## City/Wasteland boundary in a real run — a pre-existing, documented W-A
## architecture choice this phase does not touch), so gating the Crawler
## on `not training` would make it unreachable in EVERY mode that can
## currently reach it. `distance` is Main's own origin-shift-independent
## total logical distance, matching every other Wasteland-facing system.
func update(delta: float, distance: float, current_rider: CharacterBody3D, current_wasteland: Node3D) -> void:
 rider = current_rider
 wasteland = current_wasteland
 match state:
  STATE_INACTIVE:
   if distance >= Wasteland.wasteland_boss_start_distance():
    start_intro()
  STATE_INTRO:
   phase_timer -= delta
   if phase_timer <= 0:
    start_active()
  STATE_ACTIVE:
   position.z -= CRAWLER_SPEED * delta
   update_legs(delta)
   update_upper_hazard(delta)
   if is_instance_valid(rider) and rider.global_position.z < escape_marker.global_position.z:
    start_escape()
  STATE_ESCAPE:
   # Keeps moving at its own pace — the player, already ahead and free to
   # move at full speed, naturally pulls away. No destroy/explode (spec
   # section 33): the Crawler just falls behind.
   position.z -= CRAWLER_SPEED * delta
   phase_timer -= delta
   if phase_timer <= 0:
    state = STATE_CLEARED
    visible = false
    global_position.z -= 1000.0

func start_intro() -> void:
 if not is_instance_valid(rider):
  return
 cue.emit("intro")
 state = STATE_INTRO
 phase_timer = INTRO_DURATION
 visible = true
 global_position = Vector3(0, 0, rider.global_position.z - INTRO_REAR_GAP - APPROACH_Z)

func start_active() -> void:
 cue.emit("active")
 state = STATE_ACTIVE

func start_escape() -> void:
 cue.emit("escape")
 state = STATE_ESCAPE
 phase_timer = ESCAPE_DURATION

## Main rebases the whole world together; the Crawler is a single node
## tree (no separate top-level VFX roots like CityBoss needs for its own
## pattern volumes), so one offset covers everything under it.
func rebase(amount: float) -> void:
 global_position.z += amount

func material(color: Color) -> StandardMaterial3D:
 var key: String = color.to_html()
 if material_cache.has(key):
  return material_cache[key]
 var mat := StandardMaterial3D.new()
 mat.albedo_color = color
 mat.roughness = 0.8
 mat.metallic = 0.3
 material_cache[key] = mat
 return mat

func box(parent: Node3D, pos: Vector3, size: Vector3, color: Color, solid: bool = false) -> Node3D:
 var root: Node3D = StaticBody3D.new() if solid else Node3D.new()
 parent.add_child(root)
 root.position = pos
 var mesh := MeshInstance3D.new()
 var box_mesh := BoxMesh.new()
 box_mesh.size = size
 mesh.mesh = box_mesh
 mesh.material_override = material(color)
 mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
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

## Same shape as Wasteland.hookable_structure(): a StaticBody3D on the
## default physics layer City.manual_target()'s raycast already queries,
## tagged the same "hookable"/"building" convention every other safe-to-
## touch surface in this game uses.
func hookable_structure(parent: Node3D, pos: Vector3, size: Vector3, color: Color) -> Node3D:
 var body: Node3D = box(parent, pos, size, color, true)
 body.set_meta("hookable", true)
 body.set_meta("building", true)
 var sensor := decoration(body, Vector3(0, size.y * 0.5 + 0.15, 0), Vector3(0.3, 0.3, 0.3), SENSOR_GLOW)
 sensor.material_override = sensor.material_override.duplicate()
 sensor.material_override.emission_enabled = true
 sensor.material_override.emission = SENSOR_GLOW
 sensor.material_override.emission_energy_multiplier = 1.2
 return body

func build_body() -> void:
 var core_frame := Node3D.new()
 core_frame.name = "CoreFrame"
 add_child(core_frame)
 decoration(core_frame, Vector3(0, 6.0, -2.0), Vector3(14.0, 6.0, 96.0), DARK_METAL)
 decoration(core_frame, Vector3(0, 20.0, -12.0), Vector3(9.0, 2.0, 40.0), UPPER_METAL)
 decoration(core_frame, Vector3(0, 24.0, -40.0), Vector3(3.0, 8.0, 3.0), UPPER_METAL) # front mast stub

 var attachment_points := Node3D.new()
 attachment_points.name = "AttachmentPoints"
 add_child(attachment_points)
 for pos in LOW_ANCHORS:
  hookable_structure(attachment_points, pos, Vector3(2.2, 2.2, 2.2), JOINT_COLOR).set_meta("route", "LOW")
 for pos in HIGH_ANCHORS:
  hookable_structure(attachment_points, pos, Vector3(2.2, 2.2, 2.2), JOINT_COLOR).set_meta("route", "HIGH")

 legs.clear()
 for index in range(LEG_CONFIG.size()):
  spawn_leg(LEG_CONFIG[index], index)

 build_upper_hazard()

 escape_marker = Node3D.new()
 escape_marker.name = "EscapeMarker"
 escape_marker.position = Vector3(0, 10.0, ESCAPE_MARKER_Z)
 add_child(escape_marker)

## Each leg is a SEPARATE container so range_limited_target()'s own
## `for root in extra_target_roots: root.get_children()` two-level search
## (root -> container -> hookable surface) finds the hip joint correctly —
## same reasoning as AttachmentPoints above.
func spawn_leg(config: Dictionary, order: int) -> void:
 var container := Node3D.new()
 container.name = "Leg" + config.name
 add_child(container)
 var side: int = config.side
 var z: float = config.z
 # The hip joint is FIXED to the body — never animated — deliberately the
 # only hookable part of the leg (spec section 39): a moving wire target
 # would risk sudden target teleport/invalid mid-swing state, which this
 # design sidesteps entirely rather than trying to solve.
 hookable_structure(container, Vector3(side * LEG_HIP_X, LEG_HIP_Y, z), Vector3(2.4, 2.4, 2.4), JOINT_COLOR).set_meta("route", "LOW")
 decoration(container, Vector3(side * (LEG_HIP_X - 2.5) * 0.5, LEG_HIP_Y * 0.6, z), Vector3(1.2, LEG_HIP_Y * 0.9, 1.2), DARK_METAL)

 # The FOOT is the real moving hazard — a kinematic AnimatableBody3D, same
 # stable-moving-collision convention as City.spawn_vehicle()/
 # CityBoss.spawn_robot()/Wasteland's own Turbine blade hub. Deliberately
 # non-hookable (spec section 10/39).
 var foot := AnimatableBody3D.new()
 foot.sync_to_physics = false
 container.add_child(foot)
 foot.position = Vector3(side * LEG_FOOT_X, LEG_FOOT_Y_REST, z)
 foot.set_meta("hazard", true)
 foot.set_meta("hookable", false)
 var foot_mesh := MeshInstance3D.new()
 var foot_box := BoxMesh.new()
 foot_box.size = Vector3(2.6, 3.0, 2.6)
 foot_mesh.mesh = foot_box
 foot_mesh.material_override = material(RUST_ACCENT)
 foot_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
 foot.add_child(foot_mesh)
 var foot_collision := CollisionShape3D.new()
 var foot_shape := BoxShape3D.new()
 foot_shape.size = Vector3(2.6, 3.0, 2.6)
 foot_collision.shape = foot_shape
 foot.add_child(foot_collision)

 # World-space plant telegraph (spec section 24) — a flat ground marker
 # whose own (never shared/cached) material brightens right before the
 # foot plants. No HUD.
 var telegraph_mat := StandardMaterial3D.new()
 telegraph_mat.albedo_color = Color(0, 0, 0, 0.15)
 telegraph_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
 telegraph_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
 var telegraph := MeshInstance3D.new()
 var telegraph_mesh := BoxMesh.new()
 telegraph_mesh.size = Vector3(3.6, 0.05, 3.6)
 telegraph.mesh = telegraph_mesh
 telegraph.material_override = telegraph_mat
 telegraph.position = Vector3(side * LEG_FOOT_X, 0.03, z)
 container.add_child(telegraph)

 legs.append({
  "foot": foot, "telegraph_mat": telegraph_mat, "rest_z": z, "order": order,
 })

func update_legs(delta: float) -> void:
 leg_cycle_time = fmod(leg_cycle_time + delta, LEG_CYCLE_DURATION)
 var step_slot: float = LEG_CYCLE_DURATION / float(LEG_CONFIG.size())
 for leg in legs:
  var offset: float = float(leg.order) * step_slot
  var t: float = fmod(leg_cycle_time - offset + LEG_CYCLE_DURATION, LEG_CYCLE_DURATION)
  var foot: AnimatableBody3D = leg.foot
  var telegraph_mat: StandardMaterial3D = leg.telegraph_mat
  if t < LEG_STEP_DURATION:
   var p: float = t / LEG_STEP_DURATION
   var lift: float = sin(p * PI)
   foot.position.y = lerpf(LEG_FOOT_Y_REST, LEG_FOOT_Y_LIFT, lift)
   foot.position.z = leg.rest_z + sin(p * PI) * 3.0
   var warn: float = clampf((p - 0.55) / 0.45, 0.0, 1.0)
   telegraph_mat.albedo_color = Color(1.0, 0.35, 0.2, 0.1 + warn * 0.45)
  else:
   foot.position.y = LEG_FOOT_Y_REST
   foot.position.z = leg.rest_z
   telegraph_mat.albedo_color = Color(0, 0, 0, 0.15)

## A single slow rotating arm (spec section 29 — at most one moving upper
## hazard in this first pass), positioned well above every HIGH anchor's
## own Y (max 22) so its swept radius can never overlap a real anchor's
## collision regardless of rotation angle — same "hazard offset from
## anchor" principle Wasteland's own Turbine Field already established.
func build_upper_hazard() -> void:
 upper_hazard = AnimatableBody3D.new()
 upper_hazard.sync_to_physics = false
 add_child(upper_hazard)
 upper_hazard.position = UPPER_HAZARD_POSITION
 upper_hazard.set_meta("hazard", true)
 upper_hazard.set_meta("hookable", false)
 var mesh := MeshInstance3D.new()
 var box_mesh := BoxMesh.new()
 box_mesh.size = Vector3(1.2, 1.2, UPPER_HAZARD_LENGTH)
 mesh.mesh = box_mesh
 mesh.position = Vector3(0, 0, -UPPER_HAZARD_LENGTH * 0.5)
 mesh.material_override = material(RUST_ACCENT)
 mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
 upper_hazard.add_child(mesh)
 var collision := CollisionShape3D.new()
 var shape := BoxShape3D.new()
 shape.size = Vector3(1.2, 1.2, UPPER_HAZARD_LENGTH)
 collision.shape = shape
 collision.position = mesh.position
 upper_hazard.add_child(collision)

func update_upper_hazard(delta: float) -> void:
 upper_hazard.rotate_object_local(Vector3(0, 1, 0), UPPER_HAZARD_SPEED * delta)
