extends Node3D
signal cue(kind: String)
## PHASE C — City Boss "Police Interceptor" (Graybox). A *Traversal* Boss,
## not a combat boss: it has no HP, cannot be attacked, and never adds any
## new player ability. The player wins purely by using the existing
## movement toolkit (wire/jump/double jump/skate/armor) to survive
## CITY_BOSS_ESCAPE_DISTANCE of travel — see DifficultyDirector, which owns
## every distance threshold this file reads (kept there since they're World
## Progression constants shared with City.gd's own event suppression).
##
## Player Progression (rules.gd/rider.gd's tiers/upgrades/synergy) is never
## read or written here beyond calling the exact same Rider.hurt() every
## other hazard in this game already uses — armor/collision-grace/etc. all
## keep working unchanged because this is the same code path, not a new one.
const DifficultyDirector = preload("res://scripts/difficulty_director.gd")
const Rules = preload("res://scripts/rules.gd")

const STATE_INACTIVE: String = "INACTIVE"
const STATE_INTRO: String = "INTRO"
const STATE_ACTIVE: String = "ACTIVE"
const STATE_ESCAPE: String = "ESCAPE"
const STATE_CLEARED: String = "CLEARED"

const PATTERN_NONE: String = "NONE"
const PATTERN_COOLDOWN: String = "COOLDOWN"
const PATTERN_PATH_BLOCK: String = "PATH_BLOCK"
const PATTERN_LASER_PLANE: String = "LASER_PLANE"
const PATTERN_ROBOT_BARRAGE: String = "ROBOT_BARRAGE"
## Deterministic, not random — PHASE C spec section 19 explicitly asks for a
## fixed order so the encounter is easy to reason about/test.
const PATTERN_SEQUENCE: Array[String] = [PATTERN_PATH_BLOCK, PATTERN_LASER_PLANE, PATTERN_ROBOT_BARRAGE]

const PHASE_TELEGRAPH: String = "TELEGRAPH"
const PHASE_ACTIVE: String = "ACTIVE"
const PHASE_RECOVERY: String = "RECOVERY"

const INTRO_DURATION: float = 1.5
const ESCAPE_DURATION: float = 2.0
const COOLDOWN_DURATION: float = 2.0

## Boss Pattern Revision V3 (spec sections 13-17): both A (PATH_BLOCK) and
## B (LASER_PLANE) now telegraph with a shared "WARNING" flow — the hazard
## volume appears at its real final position/size immediately, blinking
## on/off WARNING_BLINK_COUNT times (collision OFF throughout), then snaps
## to its bright ACTIVE look with collision on for exactly
## WARNING_ACTIVE_DURATION. Warning and active always share the exact same
## mesh/CollisionShape3D size — there is no separate "grow into place"
## animation anymore (spec section 19: visual and collision must never
## differ in extent).
const WARNING_BLINK_COUNT: int = 3
const WARNING_BLINK_ON_TIME: float = 0.18
const WARNING_BLINK_OFF_TIME: float = 0.18
const WARNING_TOTAL_DURATION: float = WARNING_BLINK_COUNT * (WARNING_BLINK_ON_TIME + WARNING_BLINK_OFF_TIME)
const WARNING_ACTIVE_DURATION: float = 2.0
## PATH_BLOCK and LASER_PLANE both stretch their warning-to-active window to
## the same, slower cadence (three blinks run at two thirds speed) so
## neither pattern gives the player less warning time than the other.
const EXTENDED_WARNING_TIME_SCALE: float = 1.5

## Boss Pattern Revision V3 (spec sections 1-6): PATH_BLOCK is now a true
## vertical space limit — not just the building's own 8m-wide footprint, but
## that building line PLUS roughly the near third of that side's own road
## (the part closest to the sidewalk), so the player can't just hug the
## road's inner edge to dodge it. The other side (building + its own road
## third) is always left completely untouched.
const PATH_BLOCK_TELEGRAPH: float = WARNING_TOTAL_DURATION * EXTENDED_WARNING_TIME_SCALE
const PATH_BLOCK_ACTIVE: float = WARNING_ACTIVE_DURATION
const PATH_BLOCK_RECOVERY: float = 0.4
## Matches City.create_chunk()'s own road (size.x=14, so half-width 7.0 from
## center to edge) and building (center x=+-11.4, half-width 4.0, size.x=8)
## geometry exactly — see path_block_x_bounds().
const PATH_BLOCK_ROAD_HALF_WIDTH: float = 7.0
const PATH_BLOCK_ROAD_FRACTION: float = 1.0 / 3.0
const PATH_BLOCK_BUILDING_CENTER: float = 11.4
const PATH_BLOCK_BUILDING_HALF_WIDTH: float = 4.0
## Long enough to reliably overlap wherever the player actually is for the
## whole WARNING+ACTIVE window regardless of travel speed — shared with
## LASER_PLANE below since both are now "close off this whole zone for a
## couple seconds" hazards rather than a thin slice/beam.
const PATTERN_ZONE_DEPTH: float = 40.0
const PATH_BLOCK_BASE_HEIGHT: float = 35.0
const PATH_BLOCK_HEIGHT_MARGIN: float = 8.0

## Boss Pattern Revision V3 (spec sections 7-12): LASER_PLANE no longer
## threatens a single thin height band — it splits the current Building
## Height tier's usable height exactly in half and blocks one whole half
## (UPPER or LOWER), spanning the full corridor width (both building lines
## and the road between them), forcing a real up/down route choice rather
## than a "duck under one line" dodge.
## Height laser needs more time to change altitude: run its three warning
## blinks at two thirds speed (EXTENDED_WARNING_TIME_SCALE, shared with
## PATH_BLOCK above so both patterns give the same warning-to-active time).
const LASER_TELEGRAPH: float = WARNING_TOTAL_DURATION * EXTENDED_WARNING_TIME_SCALE
const LASER_ACTIVE: float = WARNING_ACTIVE_DURATION
const LASER_RECOVERY: float = 0.4
const LASER_WIDTH: float = 32.0

## Boss Pattern Revision V2 (spec sections 16-28): DRONE_GATE (a set of
## static, wireable police-drone hazards placed like a mini route puzzle)
## is removed entirely as a boss pattern. City's own ordinary
## police-drone hazards (City.obstacle(), spawned by ordinary chunk
## generation) are completely untouched — only the boss's own use of that
## concept goes away. ROBOT_BARRAGE replaces it with a genuinely different
## kind of hazard: 3 moving, straight-line "barrage robots" launched from
## the boss itself, each on its own fixed velocity (no homing — direction
## is locked at launch, with a small predictive lead so it isn't a pure
## sitting duck either). They persist and keep moving independently of the
## pattern's own telegraph/active/recovery/cooldown cycle (see
## update_active_robots()) until their own lifetime or distance-behind-
## player cleanup condition fires, or the boss escapes/resets.
const ROBOT_BARRAGE_TELEGRAPH: float = 0.8
## Long enough to fit all of ROBOT_LAUNCH_TIMES with margin; recovery/
## cooldown then follow while any still-flying robots keep moving on their
## own (see update_active_robots(), called unconditionally during ACTIVE
## regardless of which pattern is currently cycling).
const ROBOT_BARRAGE_ACTIVE: float = 1.4
const ROBOT_BARRAGE_RECOVERY: float = 0.4
## Staggered launch offsets (seconds into ROBOT_BARRAGE's own ACTIVE phase)
## for each of the 3 robots — spec section 23's "0.0 / 0.35-0.6 / 0.7-1.2".
const ROBOT_LAUNCH_TIMES: Array[float] = [0.0, 0.45, 0.9]
## Left / center / right bands, matching this game's existing hazard-x
## convention (see City.create_chunk()'s own [-3.7, 0.0, 3.7] cycling) —
## guarantees the 3 robots never share a spawn X (spec section 24).
const ROBOT_LAUNCH_X: Array[float] = [-3.7, 0.0, 3.7]
## Hull-relative launch ports: keep the source of every projectile visible
## on the interceptor instead of teleporting it to a random city height.
## Value matches the real model's own missile-pod cluster (the midpoint of
## BOSS_LAUNCH_PORT_OFFSET's left/right ports below, scaled) now that the
## graybox boxes are replaced by boss drone.glb — same formula as before
## (spawn_robot() still just adds this to global_position + a per-robot X
## band), only the constant's value changed to match the new visual hull.
## Trajectory (speed/lead/lifetime/non-homing) is untouched.
const ROBOT_LAUNCH_OFFSET := Vector3(0, -2.2, 2.97)
const ROBOT_SIZE := Vector3(2.6, 2.2, 1.4)
## Clearly faster than ambient traffic (City.CAR_SPEED = 4, deliberately
## slow) so it reads as a real threat, while staying well under the
## player's own top speed (Rules.MAX_SPEED = 35) so it's always outrunnable
## or divertable, never an inescapable wall of speed.
const ROBOT_SPEED: float = 16.0
## Small predictive lead on the player's CURRENT velocity at launch only —
## direction is then locked forever (see spawn_robot()). Not homing: the
## robot never re-aims after launch.
const ROBOT_LEAD_TIME: float = 0.4
const ROBOT_LIFETIME: float = 6.0
## A robot this far behind the player's own Z is certain to be irrelevant
## (the player already passed it) — cleaned up early rather than waiting
## out its full lifetime.
const ROBOT_BEHIND_PLAYER_CLEANUP: float = 20.0

# ---------------------------------------------------------------------
# BOSS VISUAL PASS — real "boss drone.glb" model in place of the old
# graybox body/wing boxes, at roughly 2x that graybox's own silhouette,
# plus an eye-laser VFX chain (charge -> flash -> beam -> impact) driven by
# the existing WARNING/ACTIVE timing above. Nothing in this section changes
# any hazard's actual position/size/timing/collision, Robot Barrage's
# trajectory formula, the state machine, or any distance — it only changes
# what the player sees. See docs/PROGRESS_OVERVIEW.md for the calibration
# process (the model was rendered from several angles and a marker sphere
# was matched against its real geometry — these offsets are measured, not
# guessed).
# ---------------------------------------------------------------------
## Source: Sketchfab "Sci-fi Dron-Scorpion-42" (models/boss drone.glb,
## user-supplied). The original file is never edited — only instanced as a
## child, exactly like City.DRONE_MODEL/CAR_MODELS above.
const BOSS_MODEL: PackedScene = preload("res://models/boss drone.glb")
## Measured via the model's own full transform chain, same convention as
## City.DRONE_AABB_POSITION/SIZE.
const BOSS_MODEL_AABB_POSITION := Vector3(-2.955789, -2.158296, -3.459283)
const BOSS_MODEL_AABB_SIZE := Vector3(5.911577, 2.703883, 4.845396)
## The old graybox body+wings read as roughly 6.6m wide (3.4m body + 2x(0.9m
## wing half-width + 2.4m offset)). This model's own combined AABB is
## already ~5.9m wide, so a uniform scale of 2.2 lands the real model at
## ~13m wide — about 2x the graybox's own prior silhouette. Checked against
## building width (8m) and actual boss altitude/distance with a real
## in-game screenshot, not just this arithmetic.
const BOSS_MODEL_SCALE: float = 2.2
## Hull-relative marker offsets below are in the model's own unscaled local
## space — as children of ModelRoot they inherit BOSS_MODEL_SCALE
## automatically. The model has one forward-facing central lens (a
## camera-iris design, concentric rings) at local +Z, which already matches
## this boss's existing "+Z is front" convention (the old beacon sat at -Z,
## i.e. the rear) and the direction the player actually is in (boss.z =
## player.z - 60, so the player is in +Z from the boss) — no extra rotation
## needed.
const BOSS_EYE_LOCAL_OFFSET := Vector3(0.0, -0.55, 1.3)
## The missile-pod cluster directly under the eye — the model's own most
## launcher-like feature. Right port; left is the X-mirror.
const BOSS_LAUNCH_PORT_OFFSET := Vector3(0.35, -1.0, 1.35)
## The two rectangular engine-glow panels on the model's rear (-Z) face.
## Right port; left is the X-mirror.
const BOSS_ENGINE_LOCAL_OFFSET := Vector3(1.25, -0.55, -1.5)

## Eye charge: 3 stages matching the shared WARNING system's own 3 blinks
## (see tick_pattern_visual()'s warning_pulse tracking below) — low glow on
## blink 1, stronger on blink 2, near-white on blink 3, then a bright flash
## right as the beam fires.
const EYE_CHARGE_COLORS: Array[Color] = [Color(0.35, 0.03, 0.03), Color(0.85, 0.1, 0.05), Color(1.0, 0.85, 0.8)]
const EYE_CHARGE_ENERGY: Array[float] = [0.8, 1.8, 3.2]
const EYE_FLASH_COLOR := Color(1.0, 0.95, 0.9)
const EYE_FLASH_ENERGY: float = 5.0
const EYE_IDLE_ENERGY: float = 0.0

## Single RED beam color (spec: "Boss laser는 RED 단일 색상") — a bright
## core inside a softer, wider glow layer.
const BEAM_CORE_COLOR := Color(1.0, 0.55, 0.45, 0.95)
const BEAM_GLOW_COLOR := Color(0.9, 0.05, 0.05, 0.35)
const BEAM_CORE_RADIUS: float = 0.12
const BEAM_GLOW_RADIUS: float = 0.34
const IMPACT_FLASH_DURATION: float = 0.2
const LAUNCH_FLASH_DURATION: float = 0.18

const ENGINE_GLOW_COLOR := Color(0.25, 0.85, 1.0)
const ENGINE_GLOW_OFF_ENERGY: float = 0.0
const ENGINE_GLOW_ACTIVE_ENERGY: float = 1.6
const ENGINE_GLOW_ESCAPE_ENERGY: float = 2.8
## Engine brightness eases toward its target over INTRO_DURATION/1 second
## rather than snapping, per spec sections 24/26 ("fade in").
const ENGINE_GLOW_EASE_SPEED: float = 1.5

const IDLE_BOB_AMPLITUDE: float = 0.18
const IDLE_BOB_PERIOD: float = 2.6
const IDLE_TILT_AMPLITUDE_DEG: float = 1.6

var state: String = STATE_INACTIVE
var pattern: String = PATTERN_NONE
var pattern_phase: String = PATTERN_NONE
var phase_timer: float = 0.0
var pattern_index: int = 0
## Alternates every PATH_BLOCK so the closed side is never the same twice in
## a row and — most importantly — is never "both sides" (see spawn_path_block()).
var closed_side: int = 1
## Alternates every LASER_PLANE the same way closed_side does — never the
## same half twice in a row (see spawn_laser_plane()).
var laser_upper: bool = false
var barrage_launch_index: int = 0
var barrage_active_elapsed: float = 0.0

var rider: CharacterBody3D
var city: Node3D
var block_node: Area3D
var laser_node: Area3D
var barrage_root: Node3D
var barrage_robots: Array[Node3D] = []
var warning_pulse: int = -1
var beacon_normal: StandardMaterial3D
var beacon_launch: StandardMaterial3D
var barrage_tint: StandardMaterial3D

# --- Boss visual pass state ---
var visual_pivot: Node3D
var model_root: Node3D
var eye_emitter: Marker3D
var eye_glow: MeshInstance3D
var eye_glow_material: StandardMaterial3D
var launch_port_left: Marker3D
var launch_port_right: Marker3D
var engine_glow_left: MeshInstance3D
var engine_glow_right: MeshInstance3D
var engine_glow_material_left: StandardMaterial3D
var engine_glow_material_right: StandardMaterial3D
var engine_glow_energy: float = 0.0
var beam_node: Node3D
var beam_target_node: Node3D
var idle_time: float = 0.0
var beacon_mesh: MeshInstance3D
var safe_direction: Node3D
var sensor_ring: MeshInstance3D
var temporary_fx: Array[MeshInstance3D] = []
var fx_tweens: Dictionary = {}

func _ready() -> void:
 build_visual()

func build_visual() -> void:
 beacon_normal = boss_material(Color("ff4a3d"), true)
 beacon_launch = boss_material(Color("ffbe55"), true)
 barrage_tint = StandardMaterial3D.new()
 barrage_tint.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
 barrage_tint.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
 barrage_tint.albedo_color = Color(1.0, 0.25, 0.025, 0.8)

 # VisualPivot carries only cosmetic idle bob/tilt (idle_motion()) — the
 # boss's own gameplay transform (global_position, set by
 # position_near_player()/start_escape()) is completely untouched by it.
 visual_pivot = Node3D.new()
 visual_pivot.name = "VisualPivot"
 add_child(visual_pivot)

 # ModelRoot holds the real GLB, scaled up (BOSS_MODEL_SCALE) from its own
 # natural origin — the original resource is only ever instanced, never
 # edited. Every hull-relative marker below is parented under it so it
 # inherits this same scale automatically.
 model_root = Node3D.new()
 model_root.name = "ModelRoot"
 model_root.scale = Vector3.ONE * BOSS_MODEL_SCALE
 visual_pivot.add_child(model_root)
 var model: Node3D = BOSS_MODEL.instantiate()
 model_root.add_child(model)
 var outline := ShaderMaterial.new()
 outline.shader = preload("res://scripts/boss_outline.gdshader")
 for part in model.find_children("*", "MeshInstance3D", true, false):
  part.material_overlay = outline

 eye_emitter = Marker3D.new()
 eye_emitter.name = "EyeLaserEmitter"
 eye_emitter.position = BOSS_EYE_LOCAL_OFFSET
 model_root.add_child(eye_emitter)
 eye_glow = MeshInstance3D.new()
 var eye_glow_mesh := SphereMesh.new()
 eye_glow_mesh.radius = 0.22
 eye_glow_mesh.height = 0.44
 eye_glow.mesh = eye_glow_mesh
 eye_glow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
 eye_glow_material = StandardMaterial3D.new()
 eye_glow_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
 eye_glow_material.no_depth_test = true
 eye_glow_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
 eye_glow_material.albedo_color = Color(1, 1, 1, 0)
 eye_glow_material.emission_enabled = true
 eye_glow_material.emission = EYE_CHARGE_COLORS[0]
 eye_glow_material.emission_energy_multiplier = EYE_IDLE_ENERGY
 eye_glow.material_override = eye_glow_material
 eye_emitter.add_child(eye_glow)
 sensor_ring = MeshInstance3D.new()
 var ring := TorusMesh.new()
 ring.inner_radius = 0.25
 ring.outer_radius = 0.29
 ring.rings = 24
 ring.ring_segments = 8
 sensor_ring.mesh = ring
 sensor_ring.rotation.x = PI * 0.5
 sensor_ring.material_override = guidance_material()
 sensor_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
 eye_emitter.add_child(sensor_ring)
 build_safe_direction()

 launch_port_left = Marker3D.new()
 launch_port_left.name = "RobotLaunchLeft"
 launch_port_left.position = BOSS_LAUNCH_PORT_OFFSET * Vector3(-1, 1, 1)
 model_root.add_child(launch_port_left)
 launch_port_right = Marker3D.new()
 launch_port_right.name = "RobotLaunchRight"
 launch_port_right.position = BOSS_LAUNCH_PORT_OFFSET
 model_root.add_child(launch_port_right)

 engine_glow_material_left = engine_glow_material_template()
 engine_glow_left = engine_glow_mesh_instance(engine_glow_material_left)
 engine_glow_left.position = BOSS_ENGINE_LOCAL_OFFSET * Vector3(-1, 1, 1)
 model_root.add_child(engine_glow_left)
 engine_glow_material_right = engine_glow_material_template()
 engine_glow_right = engine_glow_mesh_instance(engine_glow_material_right)
 engine_glow_right.position = BOSS_ENGINE_LOCAL_OFFSET
 model_root.add_child(engine_glow_right)

 # BeaconVFX — same telegraph role as before (see tick_pattern_visual()'s
 # ROBOT_BARRAGE case / start_pattern()), just remounted on the real hull's
 # topside instead of the old graybox's flat rear deck.
 beacon_mesh = MeshInstance3D.new()
 var beacon_sphere := SphereMesh.new()
 beacon_sphere.radius = 0.65
 beacon_sphere.height = 1.3
 beacon_mesh.name = "Beacon"
 beacon_mesh.mesh = beacon_sphere
 beacon_mesh.position = Vector3(0, 0.35, 0.4)
 # Countering ModelRoot's own BOSS_MODEL_SCALE so the beacon stays a small,
 # compact accent light near the hull's own top ridge instead of scaling
 # into a big floating orb along with the rest of the model.
 beacon_mesh.scale = Vector3.ONE * (0.3 / BOSS_MODEL_SCALE)
 beacon_mesh.material_override = beacon_normal
 beacon_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
 model_root.add_child(beacon_mesh)
 visible = false

func guidance_material() -> StandardMaterial3D:
 var mat := StandardMaterial3D.new()
 mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
 mat.no_depth_test = true
 mat.albedo_color = Color(0.15, 0.95, 0.95)
 return mat

func build_safe_direction() -> void:
 # Two world-space chevrons point toward the safe half even when its
 # boundary is above/below the camera. No new screen-space HUD or collider.
 safe_direction = Node3D.new()
 safe_direction.name = "SafeHeightDirection"
 visual_pivot.add_child(safe_direction)
 safe_direction.position = Vector3(0, 3.8, 3.0)
 var mat := guidance_material()
 for row in [0.0, -1.4]:
  for side in [-1.0, 1.0]:
   var bar := MeshInstance3D.new()
   var mesh := BoxMesh.new()
   mesh.size = Vector3(2.0, 0.35, 0.12)
   bar.mesh = mesh
   bar.position = Vector3(side * 0.65, row, 0)
   bar.rotation.z = -side * PI * 0.25
   bar.material_override = mat
   bar.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
   safe_direction.add_child(bar)
 safe_direction.visible = false

func engine_glow_material_template() -> StandardMaterial3D:
 var mat := StandardMaterial3D.new()
 mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
 mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
 mat.albedo_color = Color(ENGINE_GLOW_COLOR.r, ENGINE_GLOW_COLOR.g, ENGINE_GLOW_COLOR.b, 0.55)
 mat.emission_enabled = true
 mat.emission = ENGINE_GLOW_COLOR
 mat.emission_energy_multiplier = ENGINE_GLOW_OFF_ENERGY
 return mat

func engine_glow_mesh_instance(mat: StandardMaterial3D) -> MeshInstance3D:
 var mesh_instance := MeshInstance3D.new()
 var glow_mesh := QuadMesh.new()
 glow_mesh.size = Vector2(0.55, 0.55)
 mesh_instance.mesh = glow_mesh
 mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
 mesh_instance.material_override = mat
 return mesh_instance

func boss_material(color: Color, glow: bool = false) -> StandardMaterial3D:
 var mat := StandardMaterial3D.new()
 mat.albedo_color = color
 mat.roughness = 0.6
 mat.metallic = 0.35
 if glow:
  mat.emission_enabled = true
  mat.emission = color
  mat.emission_energy_multiplier = 2.0
 return mat

# ---------------------------------------------------------------------
# Shared WARNING telegraph (spec sections 13-17): a red, translucent,
# diagonal-hatched volume at the hazard's real final position/size, blinking
# WARNING_BLINK_COUNT times before the hazard goes live. Used by both
# PATH_BLOCK and LASER_PLANE.
# ---------------------------------------------------------------------
var _warning_hatch_texture: ImageTexture

## A small tileable diagonal-stripe pattern generated once and cached —
## Graybox-appropriate (no external texture asset), applied as the warning
## volume's albedo texture so it reads as "hazard tape", not a flat box.
func warning_hatch_texture() -> ImageTexture:
 if _warning_hatch_texture == null:
  var size := 32
  var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
  for y in range(size):
   for x in range(size):
    var on_stripe: bool = posmod(x + y, 8) < 3
    img.set_pixel(x, y, Color(1, 1, 1, 1) if on_stripe else Color(1, 1, 1, 0))
  _warning_hatch_texture = ImageTexture.create_from_image(img)
 return _warning_hatch_texture

func warning_material(size: Vector3) -> StandardMaterial3D:
 var mat := StandardMaterial3D.new()
 mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
 mat.albedo_color = Color(1.0, 0.15, 0.15, 0.4)
 mat.albedo_texture = warning_hatch_texture()
 # Tile roughly every 4m regardless of this particular hazard's own
 # dimensions, so the hatch density reads consistently between the (tall,
 # narrow) PATH_BLOCK volume and the (wide, flat) LASER_PLANE volume.
 mat.uv1_scale = Vector3(maxf(1.0, size.x / 4.0), maxf(1.0, size.y / 4.0), 1.0)
 mat.emission_enabled = true
 mat.emission = Color(1.0, 0.2, 0.2)
 mat.emission_energy_multiplier = 0.6
 return mat

## True during the "on" half of each blink cycle; false during "off". Called
## with elapsed time since the telegraph phase began — see tick_pattern_visual().
func warning_blink_visible(elapsed: float, time_scale: float = 1.0) -> bool:
 var cycle: float = (WARNING_BLINK_ON_TIME + WARNING_BLINK_OFF_TIME) * time_scale
 return fmod(maxf(0.0, elapsed), cycle) < WARNING_BLINK_ON_TIME * time_scale

## Resets to a fresh encounter — called once per Main.create_world() (a new
## Rider/City already gets built fresh there; this mirrors that for the boss).
func reset() -> void:
 state = STATE_INACTIVE
 pattern = PATTERN_NONE
 pattern_phase = PATTERN_NONE
 phase_timer = 0.0
 pattern_index = 0
 closed_side = 1
 laser_upper = false
 barrage_launch_index = 0
 barrage_active_elapsed = 0.0
 cleanup_pattern_nodes()
 cleanup_barrage_robots()
 cleanup_temporary_fx()
 visible = false

## Called every physics frame from Main._physics_process(), same convention
## as City.update_vehicles()/City.update_chunks(). `distance` is the same
## origin-shift-independent total distance the Difficulty Director itself
## reads — never a local/rebased position (see difficulty_director.gd).
func update(delta: float, distance: float, current_rider: CharacterBody3D, current_city: Node3D) -> void:
 rider = current_rider
 city = current_city
 # Resolve the chapter boundary before a telegraph can activate or a robot
 # can launch on this tick. Rest never starts with a fresh attack.
 if distance >= DifficultyDirector.city_boss_clear_distance() and state in [STATE_INACTIVE, STATE_INTRO, STATE_ACTIVE]:
  start_escape()
  return
 if visible:
  idle_motion(delta)
 match state:
  STATE_INACTIVE:
   if distance >= DifficultyDirector.CITY_BOSS_START_DISTANCE:
    start_intro()
  STATE_INTRO:
   visible = true
   position_near_player()
   phase_timer -= delta
   # Fade engine glow in across the intro rather than snapping (spec
   # section 26); ease toward ACTIVE's own steady level from the start.
   update_engine_glow(delta, ENGINE_GLOW_ACTIVE_ENERGY)
   if phase_timer <= 0:
    state = STATE_ACTIVE
    start_pattern(PATTERN_SEQUENCE[0])
  STATE_ACTIVE:
   position_near_player()
   update_current_pattern(delta)
   update_engine_glow(delta, ENGINE_GLOW_ACTIVE_ENERGY)
   # Robots keep flying on their own straight-line paths independently of
   # whichever pattern the boss is currently cycling through — see
   # ROBOT_BARRAGE's own doc comment above.
   update_active_robots(delta)
  STATE_ESCAPE:
   phase_timer -= delta
   update_engine_glow(delta, ENGINE_GLOW_ESCAPE_ENERGY)
   set_eye_charge(-1)
   # Simple, non-cinematic retreat: drift up and away rather than a scripted camera move.
   global_position += Vector3(0, 6.0, -6.0) * delta
   if phase_timer <= 0:
    state = STATE_CLEARED
    cleanup_pattern_nodes()
    visible = false
  STATE_CLEARED:
   pass

func start_intro() -> void:
 cue.emit("intro")
 state = STATE_INTRO
 phase_timer = INTRO_DURATION
 visible = true
 if is_instance_valid(rider):
  global_position = boss_target_position()

func boss_target_position() -> Vector3:
 # Above and well outside every building's footprint (buildings span roughly
 # +-7.4..15.4m either side of the road, up to ~53.5m tall at the highest
 # Building Height tier) so the boss reads as "something large ahead in the
 # sky" without ever clipping city geometry or blocking the camera/aim
 # reticle straight down the road (PHASE C spec sections 8/41).
 # Keep the launch source in the player's neutral view at ground, skate
 # and high-swing heights. The center corridor is free of building walls.
 return Vector3(0, maxf(12.0, rider.position.y + 10.0), rider.position.z - 60.0)

func position_near_player() -> void:
 if not is_instance_valid(rider):
  return
 global_position = global_position.lerp(boss_target_position(), 0.06)

## Main rebases the city and rider together. Pattern volumes and the
## barrage root are top-level world-space nodes, so moving the boss alone
## cannot carry them along. Move each independent root exactly once.
func rebase(amount: float) -> void:
 global_position.z += amount
 for node in [block_node, laser_node, barrage_root, beam_node]:
  if is_instance_valid(node):
   node.global_position.z += amount
 for flash in temporary_fx:
  if is_instance_valid(flash):
   flash.global_position.z += amount
 # GPU trail history is world-space; discard the old-coordinate samples.
 for robot in barrage_robots:
  for child in robot.get_children():
   if child is GPUParticles3D:
    child.restart()

func start_escape() -> void:
 cue.emit("escape")
 state = STATE_ESCAPE
 phase_timer = ESCAPE_DURATION
 cleanup_pattern_nodes()
 cleanup_barrage_robots()
 cleanup_temporary_fx()
 pattern = PATTERN_NONE
 pattern_phase = PATTERN_NONE

# ---------------------------------------------------------------------
# Pattern state machine
# ---------------------------------------------------------------------

func start_pattern(name: String) -> void:
 warning_pulse = -1
 if is_instance_valid(beacon_mesh):
  beacon_mesh.material_override = beacon_normal
 set_eye_charge(-1)
 pattern = name
 pattern_phase = PHASE_TELEGRAPH
 phase_timer = telegraph_duration(name)
 match name:
  PATTERN_PATH_BLOCK:
   spawn_path_block()
  PATTERN_LASER_PLANE:
   spawn_laser_plane()
  PATTERN_ROBOT_BARRAGE:
   barrage_launch_index = 0
   barrage_active_elapsed = 0.0
 safe_direction.visible = name == PATTERN_LASER_PLANE
 safe_direction.rotation.z = PI if laser_upper else 0.0

func enter_cooldown() -> void:
 cleanup_pattern_nodes()
 pattern = PATTERN_COOLDOWN
 pattern_phase = PATTERN_NONE
 phase_timer = COOLDOWN_DURATION

func update_current_pattern(delta: float) -> void:
 phase_timer -= delta
 tick_pattern_visual()
 if pattern == PATTERN_ROBOT_BARRAGE and pattern_phase == PHASE_ACTIVE:
  barrage_active_elapsed += delta
  try_launch_robots()
 # 120 subtractions of 1/60 can leave a tiny positive residue at 2s.
 # Treat that as the boundary rather than keeping collision on another tick.
 if phase_timer > 0.000001:
  return
 if pattern == PATTERN_COOLDOWN:
  pattern_index = (pattern_index + 1) % PATTERN_SEQUENCE.size()
  start_pattern(PATTERN_SEQUENCE[pattern_index])
  return
 match pattern_phase:
  PHASE_TELEGRAPH:
   pattern_phase = PHASE_ACTIVE
   phase_timer = active_duration(pattern)
   set_pattern_collision(true)
  PHASE_ACTIVE:
   pattern_phase = PHASE_RECOVERY
   phase_timer = recovery_duration(pattern)
   set_pattern_collision(false)
  PHASE_RECOVERY:
   enter_cooldown()

func telegraph_duration(name: String) -> float:
 match name:
  PATTERN_PATH_BLOCK: return PATH_BLOCK_TELEGRAPH
  PATTERN_LASER_PLANE: return LASER_TELEGRAPH
  PATTERN_ROBOT_BARRAGE: return ROBOT_BARRAGE_TELEGRAPH
 return 0.5

func active_duration(name: String) -> float:
 match name:
  PATTERN_PATH_BLOCK: return PATH_BLOCK_ACTIVE
  PATTERN_LASER_PLANE: return LASER_ACTIVE
  PATTERN_ROBOT_BARRAGE: return ROBOT_BARRAGE_ACTIVE
 return 1.0

func recovery_duration(name: String) -> float:
 match name:
  PATTERN_PATH_BLOCK: return PATH_BLOCK_RECOVERY
  PATTERN_LASER_PLANE: return LASER_RECOVERY
  PATTERN_ROBOT_BARRAGE: return ROBOT_BARRAGE_RECOVERY
 return 0.4

## enabled=true is the TELEGRAPH->ACTIVE transition (warning blinking ends,
## hazard goes live: bright material, collision on, mesh continuously
## visible). enabled=false is ACTIVE->RECOVERY (collision off, hazard hidden
## — spec section 17: "Recovery: fade/remove").
func set_pattern_collision(enabled: bool) -> void:
 if enabled and pattern in [PATTERN_PATH_BLOCK, PATTERN_LASER_PLANE]:
  cue.emit("laser")
 match pattern:
  PATTERN_PATH_BLOCK:
   if is_instance_valid(block_node):
    block_node.monitoring = enabled
    var mesh: MeshInstance3D = block_node.get_child(0)
    mesh.visible = enabled
    if enabled:
     mesh.material_override = laser_material()
     fire_eye_beam(block_node.global_position)
  PATTERN_LASER_PLANE:
   if is_instance_valid(laser_node):
    laser_node.monitoring = enabled
    var mesh: MeshInstance3D = laser_node.get_child(0)
    mesh.visible = enabled
    if enabled:
     mesh.material_override = laser_material()
     fire_eye_beam(laser_node.global_position)
  PATTERN_ROBOT_BARRAGE:
   pass # each robot is collidable (a real PhysicsBody3D) from the instant it's launched; nothing to toggle here.
 if not enabled and pattern in [PATTERN_PATH_BLOCK, PATTERN_LASER_PLANE]:
  remove_beam()
  set_eye_charge(-1)
  safe_direction.visible = false

func tick_pattern_visual() -> void:
 if pattern_phase == PHASE_TELEGRAPH and pattern in [PATTERN_PATH_BLOCK, PATTERN_LASER_PLANE]:
  var time_scale: float = EXTENDED_WARNING_TIME_SCALE
  var warning_elapsed: float = telegraph_duration(pattern) - phase_timer
  var pulse: int = mini(WARNING_BLINK_COUNT - 1, floori(warning_elapsed / ((WARNING_BLINK_ON_TIME + WARNING_BLINK_OFF_TIME) * time_scale)))
  if pulse > warning_pulse:
   warning_pulse = pulse
   cue.emit("warning")
   # Eye charge (spec section 10): stage up with each of the 3 warning
   # blinks — same pulses the hazard volume itself blinks on.
   set_eye_charge(pulse)
 match pattern:
  PATTERN_PATH_BLOCK:
   if is_instance_valid(block_node):
    var mesh: MeshInstance3D = block_node.get_child(0)
    if pattern_phase == PHASE_TELEGRAPH:
     mesh.visible = warning_blink_visible(PATH_BLOCK_TELEGRAPH - phase_timer, EXTENDED_WARNING_TIME_SCALE)
    elif pattern_phase == PHASE_ACTIVE:
     pulse_hazard_material(mesh)
  PATTERN_LASER_PLANE:
   if is_instance_valid(laser_node):
    var mesh: MeshInstance3D = laser_node.get_child(0)
    if pattern_phase == PHASE_TELEGRAPH:
     mesh.visible = warning_blink_visible(LASER_TELEGRAPH - phase_timer, EXTENDED_WARNING_TIME_SCALE)
    elif pattern_phase == PHASE_ACTIVE:
     pulse_hazard_material(mesh)
  PATTERN_ROBOT_BARRAGE:
   # Boss beacon flash (spec section 27) as the pre-launch telegraph — no
   # new node, just brightening the existing beacon mesh built in
   # build_visual() while robots are about to/currently launching.
   if is_instance_valid(beacon_mesh):
    var flashing: bool = pattern_phase == PHASE_TELEGRAPH or (pattern_phase == PHASE_ACTIVE and barrage_launch_index < ROBOT_LAUNCH_TIMES.size())
    beacon_mesh.material_override = beacon_launch if flashing else beacon_normal
  _:
   pass
 # The beam must keep tracking the eye's real (moving/hovering) position and
 # the hazard's own fixed world center every frame it exists — see
 # spawn_beam()/update_beam().
 if is_instance_valid(beam_node):
  update_beam()

func cleanup_pattern_nodes() -> void:
 if is_instance_valid(safe_direction):
  safe_direction.visible = false
 if is_instance_valid(block_node):
  block_node.queue_free()
 block_node = null
 if is_instance_valid(laser_node):
  laser_node.queue_free()
 laser_node = null
 remove_beam()
 set_eye_charge(-1)
 # Robots are NOT freed here on purpose: they persist across pattern/
 # cooldown transitions with their own independent lifetime — see
 # update_active_robots()/cleanup_barrage_robots().

func cleanup_barrage_robots() -> void:
 if is_instance_valid(barrage_root):
  barrage_root.queue_free()
 barrage_root = null
 barrage_robots.clear()

# ---------------------------------------------------------------------
# A. PATH BLOCK — makes the closed apartment side's whole contact surface
# briefly lethal (spec sections 1-7). The other side is always left
# completely untouched. Wire aim/attach is never modified — the building
# itself stays exactly as hookable as always; only touching it while this
# hazard is active hurts the player.
# ---------------------------------------------------------------------
func path_block_wall_height() -> float:
 return PATH_BLOCK_BASE_HEIGHT + Rules.BUILDING_BONUS[city.high_level] + PATH_BLOCK_HEIGHT_MARGIN

## The closed side's X span: that building line's own footprint PLUS the
## near third of that side's road (the part closest to the sidewalk) — spec
## sections 2/5. Returns (min_x, max_x), always correctly ordered regardless
## of `side`'s sign, and never crosses the road's center line since even the
## innermost edge (the road-third boundary) stays a full
## PATH_BLOCK_ROAD_HALF_WIDTH*(1-1/3) = ~4.67m from center.
func path_block_x_bounds(side: int) -> Vector2:
 var building_outer: float = side * (PATH_BLOCK_BUILDING_CENTER + PATH_BLOCK_BUILDING_HALF_WIDTH)
 var road_inner: float = side * (PATH_BLOCK_ROAD_HALF_WIDTH * (1.0 - PATH_BLOCK_ROAD_FRACTION))
 return Vector2(minf(building_outer, road_inner), maxf(building_outer, road_inner))

func spawn_path_block() -> void:
 closed_side = -closed_side
 var wall_height: float = path_block_wall_height()
 var bounds: Vector2 = path_block_x_bounds(closed_side)
 var region_width: float = bounds.y - bounds.x
 var region_center_x: float = (bounds.x + bounds.y) * 0.5
 var mesh_box := BoxMesh.new()
 mesh_box.size = Vector3(region_width, wall_height, PATTERN_ZONE_DEPTH)
 var mesh := MeshInstance3D.new()
 mesh.mesh = mesh_box
 mesh.material_override = warning_material(mesh_box.size)
 var collision := CollisionShape3D.new()
 var shape := BoxShape3D.new()
 shape.size = mesh_box.size
 collision.shape = shape
 block_node = Area3D.new()
 block_node.top_level = true
 block_node.collision_layer = 0
 block_node.collision_mask = 2 # Rider.collision_layer == 2 (see rider.gd _ready())
 block_node.monitoring = false
 add_child(block_node)
 block_node.add_child(mesh)
 block_node.add_child(collision)
 # Ground (y=0) up to wall_height, same convention as City's own buildings
 # (see City.resize_building(): mesh.position.y = height * 0.5, spanning
 # 0..height) — so the hazard reaches all the way down, not just the upper
 # building band. A long Z span (PATTERN_ZONE_DEPTH) centered a little ahead
 # of the player means it reliably overlaps wherever they actually are
 # during the WARNING+ACTIVE window, rather than a thin slice they could
 # easily have already passed.
 block_node.global_position = Vector3(region_center_x, wall_height * 0.5, rider.position.z - 40.0)
 block_node.body_entered.connect(_on_pattern_body_entered)

# ---------------------------------------------------------------------
# B. LASER PLANE — splits the current Building Height tier's usable height
# exactly in half and makes one whole half (UPPER or LOWER) a hazard volume
# spanning the full corridor width (spec sections 7-12). Always leaves the
# other half as a real, traversable route.
# ---------------------------------------------------------------------
func laser_building_top() -> float:
 return PATH_BLOCK_BASE_HEIGHT + Rules.BUILDING_BONUS[city.high_level]

## (bottom, top) of whichever half is selected — UPPER is the top half of
## the current usable building height, LOWER is the bottom half. Splitting
## exactly at building-top/2 means both halves scale together with
## high_level (0-3), and the split point is always well-defined since
## laser_building_top() > 0 always.
func laser_half_bounds(upper: bool) -> Vector2:
 var top: float = laser_building_top()
 var mid: float = top * 0.5
 return Vector2(mid, top) if upper else Vector2(0.0, mid)

func spawn_laser_plane() -> void:
 laser_upper = not laser_upper
 var bounds: Vector2 = laser_half_bounds(laser_upper)
 var half_height: float = bounds.y - bounds.x
 var center_y: float = (bounds.x + bounds.y) * 0.5
 var mesh_box := BoxMesh.new()
 mesh_box.size = Vector3(LASER_WIDTH, half_height, PATTERN_ZONE_DEPTH)
 var mesh := MeshInstance3D.new()
 mesh.mesh = mesh_box
 mesh.material_override = warning_material(mesh_box.size)
 var collision := CollisionShape3D.new()
 var shape := BoxShape3D.new()
 shape.size = mesh_box.size
 collision.shape = shape
 laser_node = Area3D.new()
 laser_node.top_level = true
 laser_node.collision_layer = 0
 laser_node.collision_mask = 2
 laser_node.monitoring = false
 add_child(laser_node)
 laser_node.add_child(mesh)
 laser_node.add_child(collision)
 laser_node.global_position = Vector3(0, center_y, rider.position.z - 40.0)
 laser_node.body_entered.connect(_on_pattern_body_entered)

## The bright, collidable-and-live look (the WARNING phase uses
## warning_material() instead — see set_pattern_collision()).
const LASER_MATERIAL_BASE_ENERGY: float = 0.9
func laser_material() -> StandardMaterial3D:
 var mat := StandardMaterial3D.new()
 mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
 mat.albedo_color = Color(1.0, 0.12, 0.08, 0.38)
 mat.emission_enabled = true
 mat.emission = Color(1.0, 0.25, 0.2)
 mat.emission_energy_multiplier = LASER_MATERIAL_BASE_ENERGY
 return mat

## Subtle "bright edge" breathing on the active hazard field (spec section
## 17) — a small emission oscillation around the base ACTIVE look set by
## laser_material() above. Never touches alpha/collision/position/size.
const HAZARD_PULSE_PERIOD: float = 0.5
const HAZARD_PULSE_AMPLITUDE: float = 0.35
func pulse_hazard_material(mesh: MeshInstance3D) -> void:
 var mat: StandardMaterial3D = mesh.material_override
 if mat == null:
  return
 var t: float = idle_time # reuses the same running clock idle_motion() already accumulates
 mat.emission_energy_multiplier = LASER_MATERIAL_BASE_ENERGY + sin(t * TAU / HAZARD_PULSE_PERIOD) * HAZARD_PULSE_AMPLITUDE

func _on_pattern_body_entered(body: Node3D) -> void:
 if body == rider and is_instance_valid(rider):
  # Same obstacle-damage path every other hazard in this game already uses
  # (see Rider.hurt()): armor absorbs one hit and grants its own invincible
  # window, during which Rider.hurt() itself no-ops on repeat contact — so a
  # laser/blocker overlap spanning several physics frames can never consume
  # more than one charge or land a delayed kill the frame after (PHASE C
  # spec section 15).
  rider.hurt("OBSTACLE COLLISION")

# ---------------------------------------------------------------------
# Eye charge / beam / impact — purely cosmetic layer on top of A/B's
# existing WARNING (blink) -> ACTIVE (collision) timing. None of this reads
# or writes hazard position/size/collision/timing; it only decorates the
# same transitions those systems already drive (see tick_pattern_visual()'s
# warning_pulse tracking and set_pattern_collision() above).
# ---------------------------------------------------------------------

## stage -1 resets to idle (no glow, matches the model's own baked cyan
## lens look with nothing added). stage 0/1/2 step through EYE_CHARGE_COLORS
## as the 3 warning blinks land.
func set_eye_charge(stage: int) -> void:
 if not is_instance_valid(eye_glow_material):
  return
 if stage < 0:
  eye_glow_material.albedo_color.a = 0.0
  eye_glow_material.emission_energy_multiplier = EYE_IDLE_ENERGY
  return
 var index: int = clampi(stage, 0, EYE_CHARGE_COLORS.size() - 1)
 eye_glow_material.albedo_color = EYE_CHARGE_COLORS[index]
 eye_glow_material.emission = EYE_CHARGE_COLORS[index]
 eye_glow_material.emission_energy_multiplier = EYE_CHARGE_ENERGY[index]

## Called right as a hazard goes ACTIVE (set_pattern_collision(true)): a
## bright flash at the eye, then the beam itself fires from the eye to the
## hazard's own center, plus a brief impact flash there. `target` is
## world-space — always block_node/laser_node's own global_position, i.e.
## the exact point that hazard's collision is centered on.
func fire_eye_beam(target: Vector3) -> void:
 if is_instance_valid(eye_glow_material):
  eye_glow_material.albedo_color = EYE_FLASH_COLOR
  eye_glow_material.emission = EYE_FLASH_COLOR
  eye_glow_material.emission_energy_multiplier = EYE_FLASH_ENERGY
 spawn_beam(target)
 spawn_impact_flash(target)

func spawn_beam(target: Vector3) -> void:
 remove_beam()
 if not is_instance_valid(eye_emitter):
  return
 beam_node = Node3D.new()
 beam_node.top_level = true
 add_child(beam_node)
 var core := MeshInstance3D.new()
 var core_mesh := CylinderMesh.new()
 core_mesh.top_radius = BEAM_CORE_RADIUS
 core_mesh.bottom_radius = BEAM_CORE_RADIUS
 core_mesh.height = 1.0 # kept fixed; update_beam() stretches via node.scale.y, not mesh regeneration
 core.mesh = core_mesh
 core.name = "Core"
 core.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
 var core_mat := StandardMaterial3D.new()
 core_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
 core_mat.no_depth_test = true
 core_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
 core_mat.albedo_color = BEAM_CORE_COLOR
 core_mat.emission_enabled = true
 core_mat.emission = BEAM_CORE_COLOR
 core_mat.emission_energy_multiplier = 2.5
 core.material_override = core_mat
 beam_node.add_child(core)
 var glow := MeshInstance3D.new()
 var glow_mesh := CylinderMesh.new()
 glow_mesh.top_radius = BEAM_GLOW_RADIUS
 glow_mesh.bottom_radius = BEAM_GLOW_RADIUS
 glow_mesh.height = 1.0 # kept fixed; update_beam() stretches via node.scale.y, not mesh regeneration
 glow.mesh = glow_mesh
 glow.name = "Glow"
 glow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
 var glow_mat := StandardMaterial3D.new()
 glow_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
 glow_mat.no_depth_test = true
 glow_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
 glow_mat.albedo_color = BEAM_GLOW_COLOR
 glow_mat.emission_enabled = true
 glow_mat.emission = BEAM_GLOW_COLOR
 glow_mat.emission_energy_multiplier = 1.2
 glow.material_override = glow_mat
 beam_node.add_child(glow)
 beam_target_node = block_node if pattern == PATTERN_PATH_BLOCK else laser_node
 update_beam()

## Re-orients/re-scales the beam every frame it exists so it keeps
## connecting the eye's real (hovering/lerping) position to the hazard's own
## fixed world center — see tick_pattern_visual()'s unconditional call.
func update_beam() -> void:
 if not is_instance_valid(beam_node) or not is_instance_valid(eye_emitter):
  remove_beam()
  return
 var target: Vector3 = beam_target_node.global_position if is_instance_valid(beam_target_node) else beam_node.global_position
 var origin: Vector3 = eye_emitter.global_position
 var offset: Vector3 = target - origin
 var length: float = maxf(0.05, offset.length())
 beam_node.global_position = origin + offset * 0.5
 if offset.length() > 0.001:
  beam_node.look_at(target, Vector3.UP if absf(offset.normalized().dot(Vector3.UP)) < 0.99 else Vector3.FORWARD)
  beam_node.rotate_object_local(Vector3.RIGHT, PI * 0.5)
 for child in beam_node.get_children():
  var mesh_instance: MeshInstance3D = child
  mesh_instance.position = Vector3.ZERO
  mesh_instance.scale = Vector3(1, length, 1)

func remove_beam() -> void:
 if is_instance_valid(beam_node):
  beam_node.queue_free()
 beam_node = null
 beam_target_node = null

func spawn_impact_flash(target: Vector3) -> void:
 var flash := MeshInstance3D.new()
 flash.top_level = true
 var flash_mesh := SphereMesh.new()
 flash_mesh.radius = 0.4
 flash_mesh.height = 0.8
 flash.mesh = flash_mesh
 var mat := StandardMaterial3D.new()
 mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
 mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
 mat.albedo_color = EYE_FLASH_COLOR
 mat.emission_enabled = true
 mat.emission = EYE_FLASH_COLOR
 mat.emission_energy_multiplier = 4.0
 flash.material_override = mat
 add_child(flash)
 flash.global_position = target
 var tween: Tween = create_tween()
 temporary_fx.append(flash)
 fx_tweens[flash] = tween
 tween.tween_property(flash, "scale", Vector3.ONE * 3.0, IMPACT_FLASH_DURATION)
 tween.parallel().tween_property(mat, "albedo_color:a", 0.0, IMPACT_FLASH_DURATION)
 tween.tween_callback(finish_temporary_fx.bind(flash))

## Snapshot the same world-space exit point as the actual robot. Cosmetic
## hull bob/tilt must not detach this flash from the projectile's origin.
func launch_port_flash(spawn_position: Vector3) -> void:
 var flash := MeshInstance3D.new()
 flash.top_level = true
 var flash_mesh := SphereMesh.new()
 flash_mesh.radius = 0.3
 flash_mesh.height = 0.6
 flash.mesh = flash_mesh
 var mat := StandardMaterial3D.new()
 mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
 mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
 mat.albedo_color = Color(1.0, 0.6, 0.15, 1.0)
 mat.emission_enabled = true
 mat.emission = Color(1.0, 0.6, 0.15)
 mat.emission_energy_multiplier = 3.5
 flash.material_override = mat
 add_child(flash)
 flash.global_position = spawn_position
 var tween: Tween = create_tween()
 temporary_fx.append(flash)
 fx_tweens[flash] = tween
 tween.tween_property(flash, "scale", Vector3.ONE * 2.2, LAUNCH_FLASH_DURATION)
 tween.parallel().tween_property(mat, "albedo_color:a", 0.0, LAUNCH_FLASH_DURATION)
 tween.tween_callback(finish_temporary_fx.bind(flash))

func finish_temporary_fx(flash: MeshInstance3D) -> void:
 temporary_fx.erase(flash)
 fx_tweens.erase(flash)
 if is_instance_valid(flash):
  flash.queue_free()

func cleanup_temporary_fx() -> void:
 for flash in temporary_fx.duplicate():
  var tween: Tween = fx_tweens.get(flash)
  if tween != null and tween.is_valid():
   tween.kill()
  finish_temporary_fx(flash)

## Subtle cosmetic bob/tilt on VisualPivot only (spec section 25) — never
## touches the boss's own gameplay transform (global_position), which
## position_near_player()/start_escape() alone continue to own.
func idle_motion(delta: float) -> void:
 idle_time += delta
 if not is_instance_valid(visual_pivot):
  return
 var bob: float = sin(idle_time * TAU / IDLE_BOB_PERIOD) * IDLE_BOB_AMPLITUDE
 var tilt: float = sin(idle_time * TAU / (IDLE_BOB_PERIOD * 1.3)) * deg_to_rad(IDLE_TILT_AMPLITUDE_DEG)
 visual_pivot.position = Vector3(0, bob, 0)
 visual_pivot.rotation = Vector3(tilt, 0, tilt * 0.6)

## Engine glow eases toward a target brightness per boss state (spec section
## 24: fade in on INTRO, normal on ACTIVE, stronger on ESCAPE, off on
## CLEARED — visible=false on the whole root already covers CLEARED/off).
func update_engine_glow(delta: float, target_energy: float) -> void:
 engine_glow_energy = move_toward(engine_glow_energy, target_energy, ENGINE_GLOW_EASE_SPEED * delta)
 if is_instance_valid(engine_glow_material_left):
  engine_glow_material_left.emission_energy_multiplier = engine_glow_energy
 if is_instance_valid(engine_glow_material_right):
  engine_glow_material_right.emission_energy_multiplier = engine_glow_energy

# ---------------------------------------------------------------------
# C. ROBOT BARRAGE — 3 moving, straight-line hazards launched from the
# boss (spec sections 17-28), replacing DRONE_GATE entirely as a boss
# pattern. Built as an AnimatableBody3D with sync_to_physics=false, exactly
# like City.spawn_vehicle()'s own moving obstacles — NOT City.obstacle()'s
# StaticBody3D, which is meant to stay put; moving a true StaticBody3D
# produces unreliable collision, which is the same reason City's vehicles
# already avoid it. Rider.integrate()'s existing generic collision branch
# (obstacle collision for any non-road/non-building body) picks these up
# automatically — no bespoke signal/handler needed here, unlike the Area3D
# patterns above.
# ---------------------------------------------------------------------
func ensure_barrage_root() -> void:
 if not is_instance_valid(barrage_root):
  barrage_root = Node3D.new()
  barrage_root.top_level = true
  add_child(barrage_root)

func try_launch_robots() -> void:
 while barrage_launch_index < ROBOT_LAUNCH_TIMES.size() and barrage_active_elapsed >= ROBOT_LAUNCH_TIMES[barrage_launch_index]:
  spawn_robot(ROBOT_LAUNCH_X[barrage_launch_index])
  barrage_launch_index += 1

func spawn_robot(x_offset: float) -> void:
 if not is_instance_valid(rider):
  return
 ensure_barrage_root()
 cue.emit("launch")
 var spawn_pos: Vector3 = global_position + ROBOT_LAUNCH_OFFSET + Vector3(x_offset, 0, 0)
 launch_port_flash(spawn_pos)
 # Direction is computed ONCE, here, from the player's position and current
 # velocity with a small predictive lead — then locked for the robot's
 # entire lifetime (see update_active_robots()). This is deliberately not
 # homing (spec sections 20-21): re-aiming every frame would make it
 # unavoidable and unfair; a fixed straight line can always be read and
 # dodged.
 var target_point: Vector3 = rider.position + rider.velocity * ROBOT_LEAD_TIME
 var direction: Vector3 = target_point - spawn_pos
 if direction.length() < 0.001:
  direction = Vector3(0, 0, -1)
 direction = direction.normalized()
 var robot := AnimatableBody3D.new()
 robot.sync_to_physics = false
 barrage_root.add_child(robot)
 robot.global_position = spawn_pos
 var mesh := MeshInstance3D.new()
 var box_mesh := BoxMesh.new()
 box_mesh.size = ROBOT_SIZE
 mesh.mesh = box_mesh
 robot.add_child(mesh)
 var collision := CollisionShape3D.new()
 var shape := BoxShape3D.new()
 shape.size = ROBOT_SIZE
 collision.shape = shape
 robot.add_child(collision)
 robot.set_meta("hazard", true)
 # Deliberately non-hookable (spec section 18/28): this is a moving
 # projectile, not a route element, and wire-attaching to something on a
 # fixed straight-line velocity has no established behavior in this
 # codebase's wire physics (every existing anchor is stationary).
 robot.set_meta("hookable", false)
 city.attach_drone_visual(robot, ROBOT_SIZE)
 for part in robot.get_child(2).find_children("*", "MeshInstance3D", true, false):
  part.material_overlay = barrage_tint
 # Amber fins distinguish launched threats from white, hookable route
 # drones. The existing drone remains the visual; fins have no collision.
 for side in [-1, 1]:
  var fin := MeshInstance3D.new()
  var fin_mesh := BoxMesh.new()
  fin_mesh.size = Vector3(0.35, 1.7, 0.65)
  fin.mesh = fin_mesh
  fin.position = Vector3(side * 1.15, 0, 0)
  fin.material_override = barrage_tint
  fin.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
  robot.add_child(fin)
 robot.set_meta("velocity", direction * ROBOT_SPEED)
 robot.set_meta("age", 0.0)
 barrage_robots.append(robot)
 attach_robot_trail(robot)

## A short, cheap trail (spec section 22 — "과도한 trail 금지") so a launched
## robot reads as "a moving attack object", not just a static box that
## teleports frame to frame. Parented to the robot itself so it moves and is
## freed with it automatically; no per-frame bookkeeping needed elsewhere.
func attach_robot_trail(robot: Node3D) -> void:
 var trail := GPUParticles3D.new()
 trail.amount = 10
 trail.lifetime = 0.35
 trail.local_coords = false # particles stay behind in world space as the robot moves on
 trail.position = Vector3(0, 0, ROBOT_SIZE.z * 0.5)
 # Omnidirectional, near-zero drift: the robot can launch toward any lead
 # angle (not just -Z), so this just leaves a soft glow hanging where the
 # robot passed rather than trying to compute a travel-aligned cone.
 var mat := ParticleProcessMaterial.new()
 mat.spread = 180.0
 mat.initial_velocity_min = 0.1
 mat.initial_velocity_max = 0.4
 mat.gravity = Vector3.ZERO
 mat.scale_min = 0.15
 mat.scale_max = 0.3
 mat.color = Color(1.0, 0.35, 0.05, 0.8)
 trail.process_material = mat
 var trail_mesh := SphereMesh.new()
 trail_mesh.radius = 0.12
 trail_mesh.height = 0.24
 var trail_mat := StandardMaterial3D.new()
 trail_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
 trail_mat.vertex_color_use_as_albedo = true
 trail_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
 trail_mat.emission_enabled = true
 trail_mat.emission = Color(1.0, 0.35, 0.05)
 trail_mat.emission_energy_multiplier = 2.0
 trail_mesh.material = trail_mat
 trail.draw_pass_1 = trail_mesh
 robot.add_child(trail)

func update_active_robots(delta: float) -> void:
 for i in range(barrage_robots.size() - 1, -1, -1):
  var robot: Node3D = barrage_robots[i]
  if not is_instance_valid(robot):
   barrage_robots.remove_at(i)
   continue
  var velocity: Vector3 = robot.get_meta("velocity")
  robot.position += velocity * delta
  var age: float = float(robot.get_meta("age")) + delta
  robot.set_meta("age", age)
  var behind_player: bool = is_instance_valid(rider) and robot.global_position.z > rider.position.z + ROBOT_BEHIND_PLAYER_CLEANUP
  if age >= ROBOT_LIFETIME or behind_player:
   robot.queue_free()
   barrage_robots.remove_at(i)

## City Chapter state (PHASE C spec section 35), for anything (tests, a
## future HUD-less debug hook) that wants it without duplicating the
## distance math — just forwards to the Difficulty Director's own pure
## function using whatever distance the caller has on hand.
static func chapter_for_distance(distance: float) -> String:
 return DifficultyDirector.chapter_for_distance(distance)
