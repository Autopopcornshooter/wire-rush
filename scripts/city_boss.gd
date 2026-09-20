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

## Boss Pattern Revision V2 (spec sections 1-7): PATH_BLOCK is reframed from
## "a wall you route around" into "this whole apartment side is briefly
## lethal to touch" — a short, sharp punish rather than a long-standing
## obstacle. Width still matches City.gd's own building footprint exactly
## (see City.create_chunk()'s `box(..., Vector3(8, base_height, 14) ...)`),
## height is still computed dynamically per the current Building Height
## tier (see path_block_wall_height()), but the Z span is now much longer
## (covers a real stretch of travel, not a single 4m slice) so the danger
## reliably overlaps wherever the player actually is during the now much
## shorter ACTIVE window, and ACTIVE itself is far shorter (a brief flash of
## danger, not a multi-second wall).
const PATH_BLOCK_TELEGRAPH: float = 0.8
const PATH_BLOCK_ACTIVE: float = 1.5
const PATH_BLOCK_RECOVERY: float = 0.4
const PATH_BLOCK_WIDTH: float = 8.0
const PATH_BLOCK_DEPTH: float = 30.0
const PATH_BLOCK_BASE_HEIGHT: float = 35.0
const PATH_BLOCK_HEIGHT_MARGIN: float = 8.0

## Boss Pattern Revision V2 (spec sections 8-15): LASER_PLANE drops the old
## fixed y=8/y=30 alternation for a random height re-picked every spawn,
## bounded so it always sits meaningfully between the road and the current
## Building Height tier's usable ceiling (never right at the floor, never
## above the buildings). It stays a wide horizontal slab spanning both
## building lines (unchanged width), thin in Y (one height tier only).
const LASER_TELEGRAPH: float = 0.8
const LASER_ACTIVE: float = 1.5
const LASER_RECOVERY: float = 0.5
const LASER_WIDTH: float = 32.0
const LASER_THICKNESS: float = 0.6
const LASER_DEPTH: float = 6.0
## Shared height bounds for both the laser plane's random height and each
## Robot Barrage robot's random spawn height — "0..apartment height" per
## spec, with a floor above ground clutter and a ceiling margin below the
## rooftops so neither pattern ever reads as "at the floor" or "above the
## buildings" (see random_safe_height()/laser_building_top()).
const LASER_MIN_HEIGHT: float = 3.0
const LASER_TOP_MARGIN: float = 3.0

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

var state: String = STATE_INACTIVE
var pattern: String = PATTERN_NONE
var pattern_phase: String = PATTERN_NONE
var phase_timer: float = 0.0
var pattern_index: int = 0
## Alternates every PATH_BLOCK so the closed side is never the same twice in
## a row and — most importantly — is never "both sides" (see spawn_path_block()).
var closed_side: int = 1
var barrage_launch_index: int = 0
var barrage_active_elapsed: float = 0.0

var rider: CharacterBody3D
var city: Node3D
var block_node: Area3D
var laser_node: Area3D
var barrage_root: Node3D
var barrage_robots: Array[Node3D] = []
var rng := RandomNumberGenerator.new()

func _ready() -> void:
 rng.randomize()
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
 beacon.name = "Beacon"
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
 barrage_launch_index = 0
 barrage_active_elapsed = 0.0
 cleanup_pattern_nodes()
 cleanup_barrage_robots()
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
   # Robots keep flying on their own straight-line paths independently of
   # whichever pattern the boss is currently cycling through — see
   # ROBOT_BARRAGE's own doc comment above.
   update_active_robots(delta)
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
 cleanup_barrage_robots()
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
  PATTERN_LASER_PLANE:
   spawn_laser_plane()
  PATTERN_ROBOT_BARRAGE:
   barrage_launch_index = 0
   barrage_active_elapsed = 0.0

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

func set_pattern_collision(enabled: bool) -> void:
 match pattern:
  PATTERN_PATH_BLOCK:
   if is_instance_valid(block_node):
    block_node.monitoring = enabled
  PATTERN_LASER_PLANE:
   if is_instance_valid(laser_node):
    laser_node.monitoring = enabled
    laser_node.visible = enabled
  PATTERN_ROBOT_BARRAGE:
   pass # each robot is collidable (a real PhysicsBody3D) from the instant it's launched; nothing to toggle here.

func tick_pattern_visual() -> void:
 match pattern:
  PATTERN_PATH_BLOCK:
   if is_instance_valid(block_node) and pattern_phase == PHASE_TELEGRAPH:
    var mesh: MeshInstance3D = block_node.get_child(0)
    var t: float = 1.0 - clampf(phase_timer / PATH_BLOCK_TELEGRAPH, 0.0, 1.0)
    mesh.scale.x = lerpf(0.05, 1.0, t)
  PATTERN_ROBOT_BARRAGE:
   # Boss beacon flash (spec section 27) as the pre-launch telegraph — no
   # new node, just brightening the existing beacon mesh built in
   # build_visual() while robots are about to/currently launching.
   var beacon: MeshInstance3D = get_node_or_null("Beacon")
   if beacon != null:
    var flashing: bool = pattern_phase == PHASE_TELEGRAPH or (pattern_phase == PHASE_ACTIVE and barrage_launch_index < ROBOT_LAUNCH_TIMES.size())
    beacon.material_override = boss_material(Color("fff2a0") if flashing else Color("ff4a3d"), true)
  _:
   pass

func cleanup_pattern_nodes() -> void:
 if is_instance_valid(block_node):
  block_node.queue_free()
 block_node = null
 if is_instance_valid(laser_node):
  laser_node.queue_free()
 laser_node = null
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

func spawn_path_block() -> void:
 closed_side = -closed_side
 var wall_height: float = path_block_wall_height()
 var mesh_box := BoxMesh.new()
 mesh_box.size = Vector3(PATH_BLOCK_WIDTH, wall_height, PATH_BLOCK_DEPTH)
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
 # Ground (y=0) up to wall_height, same convention as City's own buildings
 # (see City.resize_building(): mesh.position.y = height * 0.5, spanning
 # 0..height) — so the hazard reaches all the way down, not just the upper
 # building band. A long Z span (PATH_BLOCK_DEPTH) centered a little ahead
 # of the player means it reliably overlaps wherever they actually are
 # during the short telegraph+active window, rather than a thin slice they
 # could easily have already passed.
 block_node.global_position = Vector3(closed_side * 11.4, wall_height * 0.5, rider.position.z - 40.0)
 block_node.body_entered.connect(_on_pattern_body_entered)

# ---------------------------------------------------------------------
# B. LASER PLANE — a wide horizontal barrier slab at a random height,
# re-picked every spawn, spanning both building lines (spec sections 8-15).
# Always leaves both "above the plane" and "below the plane" as real,
# traversable routes — it only ever threatens one height band.
# ---------------------------------------------------------------------
func laser_building_top() -> float:
 return PATH_BLOCK_BASE_HEIGHT + Rules.BUILDING_BONUS[city.high_level]

## Shared by the laser plane and Robot Barrage spawn heights: a safe,
## meaningful band between the road (LASER_MIN_HEIGHT above it) and the
## current Building Height tier's usable ceiling (LASER_TOP_MARGIN below
## the rooftops) — never degenerates to "basically the floor" or "basically
## the roof" regardless of high_level (0-3).
func random_safe_height() -> float:
 var top: float = laser_building_top() - LASER_TOP_MARGIN
 var bottom: float = LASER_MIN_HEIGHT
 if top <= bottom:
  return bottom
 return rng.randf_range(bottom, top)

func spawn_laser_plane() -> void:
 var band_y: float = random_safe_height()
 var mesh_box := BoxMesh.new()
 mesh_box.size = Vector3(LASER_WIDTH, LASER_THICKNESS, LASER_DEPTH)
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
 var spawn_pos := Vector3(global_position.x + x_offset, random_safe_height(), global_position.z - 6.0)
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
 robot.position = spawn_pos
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
 robot.set_meta("velocity", direction * ROBOT_SPEED)
 robot.set_meta("age", 0.0)
 barrage_robots.append(robot)

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
