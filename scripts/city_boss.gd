extends Node3D
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

const STATE_INACTIVE: String = "INACTIVE"
const STATE_INTRO: String = "INTRO"
const STATE_ACTIVE: String = "ACTIVE"
const STATE_ESCAPE: String = "ESCAPE"
const STATE_CLEARED: String = "CLEARED"

const PATTERN_NONE: String = "NONE"
const PATTERN_COOLDOWN: String = "COOLDOWN"
const PATTERN_PATH_BLOCK: String = "PATH_BLOCK"
const PATTERN_LASER_SWEEP: String = "LASER_SWEEP"
const PATTERN_DRONE_GATE: String = "DRONE_GATE"
## Deterministic, not random — PHASE C spec section 19 explicitly asks for a
## fixed order so the encounter is easy to reason about/test.
const PATTERN_SEQUENCE: Array[String] = [PATTERN_PATH_BLOCK, PATTERN_LASER_SWEEP, PATTERN_DRONE_GATE]

const PHASE_TELEGRAPH: String = "TELEGRAPH"
const PHASE_ACTIVE: String = "ACTIVE"
const PHASE_RECOVERY: String = "RECOVERY"

const INTRO_DURATION: float = 1.5
const ESCAPE_DURATION: float = 2.0
const COOLDOWN_DURATION: float = 2.0

const PATH_BLOCK_TELEGRAPH: float = 0.6
const PATH_BLOCK_ACTIVE: float = 4.0
const PATH_BLOCK_RECOVERY: float = 0.4

const LASER_TELEGRAPH: float = 0.8
const LASER_ACTIVE: float = 0.5
const LASER_RECOVERY: float = 0.6

const DRONE_GATE_TELEGRAPH: float = 1.0
const DRONE_GATE_ACTIVE: float = 6.0
const DRONE_GATE_RECOVERY: float = 0.4

## Local offsets (X, Y, Z-ahead) for the three Drone Gate hazards, ordered in
## the sequence the player reaches them (more negative Z = further ahead).
## Consecutive spacing here is a fixed, hand-checked ~16.9m (see
## tests/city_boss.gd) — comfortably inside City.MAX_BASE_TRAVERSAL_GAP —
## and always leaves at least one adjacent lane/height clear, matching the
## Traversability Guard PHASE B already established (never require a Wire
## Length upgrade to pass).
const DRONE_GATE_OFFSETS: Array[Vector3] = [
 Vector3(-3.7, 10.0, 0.0),
 Vector3(3.7, 16.0, -14.0),
 Vector3(-3.7, 22.0, -28.0),
]

var state: String = STATE_INACTIVE
var pattern: String = PATTERN_NONE
var pattern_phase: String = PATTERN_NONE
var phase_timer: float = 0.0
var pattern_index: int = 0
## Alternates every PATH_BLOCK so the closed side is never the same twice in
## a row and — most importantly — is never "both sides" (see spawn_path_block()).
var closed_side: int = 1
var laser_low: bool = false

var rider: CharacterBody3D
var city: Node3D
var block_node: Area3D
var laser_node: Area3D
var gate_node: Node3D
var gate_hazards: Array[Node3D] = []

func _ready() -> void:
 build_visual()

func build_visual() -> void:
 var body := MeshInstance3D.new()
 var body_mesh := BoxMesh.new()
 body_mesh.size = Vector3(3.4, 1.1, 5.6)
 body.mesh = body_mesh
 body.material_override = boss_material(Color("2a3f57"))
 body.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
 add_child(body)
 for side in [-1, 1]:
  var wing := MeshInstance3D.new()
  var wing_mesh := BoxMesh.new()
  wing_mesh.size = Vector3(1.8, 0.3, 2.3)
  wing.mesh = wing_mesh
  wing.position = Vector3(side * 2.4, 0, 0.3)
  wing.material_override = boss_material(Color("1c2c3d"))
  wing.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
  add_child(wing)
 var beacon := MeshInstance3D.new()
 var beacon_mesh := SphereMesh.new()
 beacon_mesh.radius = 0.35
 beacon_mesh.height = 0.7
 beacon.mesh = beacon_mesh
 beacon.position = Vector3(0, 0.85, -1.6)
 beacon.material_override = boss_material(Color("ff4a3d"), true)
 beacon.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
 add_child(beacon)
 visible = false

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

## Resets to a fresh encounter — called once per Main.create_world() (a new
## Rider/City already gets built fresh there; this mirrors that for the boss).
func reset() -> void:
 state = STATE_INACTIVE
 pattern = PATTERN_NONE
 pattern_phase = PATTERN_NONE
 phase_timer = 0.0
 pattern_index = 0
 closed_side = 1
 laser_low = false
 cleanup_pattern_nodes()
 visible = false

## Called every physics frame from Main._physics_process(), same convention
## as City.update_vehicles()/City.update_chunks(). `distance` is the same
## origin-shift-independent total distance the Difficulty Director itself
## reads — never a local/rebased position (see difficulty_director.gd).
func update(delta: float, distance: float, current_rider: CharacterBody3D, current_city: Node3D) -> void:
 rider = current_rider
 city = current_city
 match state:
  STATE_INACTIVE:
   if distance >= DifficultyDirector.CITY_BOSS_START_DISTANCE:
    start_intro()
  STATE_INTRO:
   visible = true
   position_near_player()
   phase_timer -= delta
   if phase_timer <= 0:
    state = STATE_ACTIVE
    start_pattern(PATTERN_SEQUENCE[0])
  STATE_ACTIVE:
   position_near_player()
   update_current_pattern(delta)
   if distance >= DifficultyDirector.city_boss_clear_distance():
    start_escape()
  STATE_ESCAPE:
   phase_timer -= delta
   # Simple, non-cinematic retreat: drift up and away rather than a scripted camera move.
   global_position += Vector3(0, 6.0, -6.0) * delta
   if phase_timer <= 0:
    state = STATE_CLEARED
    cleanup_pattern_nodes()
    visible = false
  STATE_CLEARED:
   pass

func start_intro() -> void:
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
 return Vector3(0, 55.0, rider.position.z - 60.0)

func position_near_player() -> void:
 if not is_instance_valid(rider):
  return
 global_position = global_position.lerp(boss_target_position(), 0.06)

func start_escape() -> void:
 state = STATE_ESCAPE
 phase_timer = ESCAPE_DURATION
 cleanup_pattern_nodes()
 pattern = PATTERN_NONE
 pattern_phase = PATTERN_NONE

# ---------------------------------------------------------------------
# Pattern state machine
# ---------------------------------------------------------------------

func start_pattern(name: String) -> void:
 pattern = name
 pattern_phase = PHASE_TELEGRAPH
 phase_timer = telegraph_duration(name)
 match name:
  PATTERN_PATH_BLOCK:
   spawn_path_block()
  PATTERN_LASER_SWEEP:
   spawn_laser()
  PATTERN_DRONE_GATE:
   spawn_drone_gate()

func enter_cooldown() -> void:
 cleanup_pattern_nodes()
 pattern = PATTERN_COOLDOWN
 pattern_phase = PATTERN_NONE
 phase_timer = COOLDOWN_DURATION

func update_current_pattern(delta: float) -> void:
 phase_timer -= delta
 tick_pattern_visual()
 if phase_timer > 0:
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
  PATTERN_LASER_SWEEP: return LASER_TELEGRAPH
  PATTERN_DRONE_GATE: return DRONE_GATE_TELEGRAPH
 return 0.5

func active_duration(name: String) -> float:
 match name:
  PATTERN_PATH_BLOCK: return PATH_BLOCK_ACTIVE
  PATTERN_LASER_SWEEP: return LASER_ACTIVE
  PATTERN_DRONE_GATE: return DRONE_GATE_ACTIVE
 return 1.0

func recovery_duration(name: String) -> float:
 match name:
  PATTERN_PATH_BLOCK: return PATH_BLOCK_RECOVERY
  PATTERN_LASER_SWEEP: return LASER_RECOVERY
  PATTERN_DRONE_GATE: return DRONE_GATE_RECOVERY
 return 0.4

func set_pattern_collision(enabled: bool) -> void:
 match pattern:
  PATTERN_PATH_BLOCK:
   if is_instance_valid(block_node):
    block_node.monitoring = enabled
  PATTERN_LASER_SWEEP:
   if is_instance_valid(laser_node):
    laser_node.monitoring = enabled
    laser_node.visible = enabled
  PATTERN_DRONE_GATE:
   for hazard in gate_hazards:
    if is_instance_valid(hazard):
     hazard.get_child(1).disabled = not enabled

func tick_pattern_visual() -> void:
 match pattern:
  PATTERN_PATH_BLOCK:
   if is_instance_valid(block_node) and pattern_phase == PHASE_TELEGRAPH:
    var mesh: MeshInstance3D = block_node.get_child(0)
    var t: float = 1.0 - clampf(phase_timer / PATH_BLOCK_TELEGRAPH, 0.0, 1.0)
    mesh.scale.x = lerpf(0.05, 1.0, t)
  PATTERN_DRONE_GATE:
   if pattern_phase == PHASE_TELEGRAPH:
    var t: float = 1.0 - clampf(phase_timer / DRONE_GATE_TELEGRAPH, 0.0, 1.0)
    for hazard in gate_hazards:
     if is_instance_valid(hazard):
      hazard.scale = Vector3.ONE * lerpf(0.15, 1.0, t)
  _:
   pass

func cleanup_pattern_nodes() -> void:
 if is_instance_valid(block_node):
  block_node.queue_free()
 block_node = null
 if is_instance_valid(laser_node):
  laser_node.queue_free()
 laser_node = null
 if is_instance_valid(gate_node):
  gate_node.queue_free()
 gate_node = null
 gate_hazards.clear()

# ---------------------------------------------------------------------
# A. PATH BLOCK — closes exactly one side of the road ahead; the other side
# is always left completely open (spec section 11: "양쪽 모두 동시에 막으면
# 안 된다"). Non-wireable by design (spec section 12).
# ---------------------------------------------------------------------
func spawn_path_block() -> void:
 closed_side = -closed_side
 var mesh_box := BoxMesh.new()
 mesh_box.size = Vector3(6.0, 9.0, 3.0)
 var mesh := MeshInstance3D.new()
 mesh.mesh = mesh_box
 mesh.material_override = boss_material(Color("c94b3d"), true)
 mesh.scale = Vector3(0.05, 1.0, 1.0)
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
 block_node.global_position = Vector3(closed_side * 11.4, 15.0, rider.position.z - 40.0)
 block_node.body_entered.connect(_on_pattern_body_entered)

# ---------------------------------------------------------------------
# B. LASER SWEEP — a horizontal beam across one height band only, never the
# whole vertical play space, alternating band so the "safe" route alternates
# too (spec section 16: route pressure, not a random kill zone).
# ---------------------------------------------------------------------
func spawn_laser() -> void:
 laser_low = not laser_low
 var band_y: float = 8.0 if laser_low else 30.0
 var mesh_box := BoxMesh.new()
 mesh_box.size = Vector3(14.0, 0.6, 3.0)
 var mesh := MeshInstance3D.new()
 mesh.mesh = mesh_box
 mesh.material_override = laser_material(false)
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
 laser_node.global_position = Vector3(0, band_y, rider.position.z - 35.0)
 laser_node.body_entered.connect(_on_pattern_body_entered)

## `active`=false is the dim world-space telegraph (PHASE C spec section 14:
## "0.5~1.0초 약한 붉은 line"); `active`=true is the bright, collidable beam.
func laser_material(active: bool) -> StandardMaterial3D:
 var mat := StandardMaterial3D.new()
 mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
 mat.albedo_color = Color(1.0, 0.25, 0.2, 0.9 if active else 0.25)
 mat.emission_enabled = true
 mat.emission = Color(1.0, 0.25, 0.2)
 mat.emission_energy_multiplier = 2.0 if active else 0.4
 return mat

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
# C. DRONE GATE — reuses City.obstacle() verbatim (same police_drone.glb
# visual, same hookable/hazard collision), just placed by the boss instead
# of by ordinary chunk generation. Collision starts disabled (telegraph) and
# is enabled without ever removing/re-adding the node, so there's no window
# where a hazard could vanish and reappear.
# ---------------------------------------------------------------------
func spawn_drone_gate() -> void:
 gate_node = Node3D.new()
 gate_node.top_level = true
 add_child(gate_node)
 var base_z: float = rider.position.z - 40.0
 gate_hazards.clear()
 for offset in DRONE_GATE_OFFSETS:
  var pos := Vector3(offset.x, offset.y, base_z + offset.z)
  var hazard: Node3D = city.obstacle(gate_node, pos, Vector3(2.6, 2.2, 1.4))
  hazard.get_child(1).disabled = true
  hazard.scale = Vector3.ONE * 0.15
  gate_hazards.append(hazard)

## City Chapter state (PHASE C spec section 35), for anything (tests, a
## future HUD-less debug hook) that wants it without duplicating the
## distance math — just forwards to the Difficulty Director's own pure
## function using whatever distance the caller has on hand.
static func chapter_for_distance(distance: float) -> String:
 return DifficultyDirector.chapter_for_distance(distance)
