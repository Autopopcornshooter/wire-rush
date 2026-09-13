extends CharacterBody3D
const Rules = preload("res://scripts/rules.gd")
signal notice(message: String)
signal crashed(reason: String)
signal slid
var city: Node3D
var mode: String = "air"
var anchor: Node3D = null
var wire_side: int = 0
var rope_length: float = 0.0
var hook_left: float = 0.0
var hook_duration: float = 0.0
var blocked_time: float = 0.0
var released_ago: float = 99.0
var landing_left: float = 0.0
var landing_speed: Vector3 = Vector3.ZERO
var slide_left: float = 0.0
var slide_armed: bool = true
var stumble_left: float = 0.0
var invincible: float = 0.0
var launch_cooldown: float = 0.0
var launch_left: float = 0.0
var twin_left: Node3D = null
var twin_right: Node3D = null
var armor_charges: int = 0
var tiers: Dictionary = {"skates": 0, "launcher": 0, "armor": 0, "high": 0, "range": 0, "reel": 0, "hook": 0, "jump": 0}
var practice: bool = false
var safe_z: float = 0.0
var visuals: Node3D
var wire_mesh: MeshInstance3D
var wire_surface: ImmediateMesh
var high_speed: float = 0.0
var slides: int = 0

func _ready() -> void:
 collision_layer = 2
 collision_mask = 1
 var collider := CollisionShape3D.new()
 var capsule := CapsuleShape3D.new()
 capsule.radius = 0.35
 capsule.height = 1.6
 collider.shape = capsule
 add_child(collider)
 visuals = Node3D.new()
 add_child(visuals)
 city.box(visuals, Vector3(0, 0.05, 0), Vector3(0.65, 0.75, 0.38), Color("e2e9e4"))
 city.box(visuals, Vector3(0, 0.65, -0.01), Vector3(0.48, 0.43, 0.46), Color("ffc876"))
 city.box(visuals, Vector3(0, 0.68, -0.26), Vector3(0.43, 0.13, 0.035), Color("162f42"))
 city.box(visuals, Vector3(0, 0.15, 0.25), Vector3(0.45, 0.5, 0.2), Color("42c4b5"), false, true)
 for side in [-1, 1]:
  city.box(visuals, Vector3(side * 0.2, -0.5, 0), Vector3(0.22, 0.55, 0.23), Color("314659"))
  city.box(visuals, Vector3(side * 0.2, -0.76, -0.07), Vector3(0.25, 0.14, 0.48), Color("67f1dc"), false, true)
  city.box(visuals, Vector3(side * 0.45, 0.0, 0), Vector3(0.20, 0.6, 0.2), Color("b2c8c8"))
 wire_mesh = MeshInstance3D.new()
 wire_surface = ImmediateMesh.new()
 wire_mesh.mesh = wire_surface
 wire_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
 wire_mesh.material_override = city.material(Color("78f9e5"), true)
 add_child(wire_mesh)
 wire_mesh.top_level = true

func reset(training: bool) -> void:
 practice = training
 mode = "air"
 position = Vector3(0, 6, 0)
 velocity = Vector3(0, 0, -12)
 tiers = {"skates": 1 if training else 0, "launcher": 1 if training else 0, "armor": 0, "high": 0, "range": 0, "reel": 0, "hook": 0, "jump": 0}
 armor_charges = 0
 release_wire(false)
 released_ago = 99
 invincible = 0
 launch_cooldown = 0
 launch_left = 0
 twin_left = null
 twin_right = null
 slide_left = 0
 slide_armed = true
 slides = 0
 high_speed = 0
 safe_z = 0

func reach() -> float:
 return Rules.ROPE_RANGE * (1.0 + tiers.range * 0.1)

func fire(side: int) -> bool:
 if mode in ["dead", "stumble", "landing"] or launch_left > 0:
  return false
 var target: Node3D = city.find_anchor(global_position, side, reach(), get_rid())
 release_wire(false)
 if target == null:
  notice.emit("NO ANCHOR IN RANGE — jump or try the other side")
  return false
 anchor = target
 wire_side = side
 hook_duration = global_position.distance_to(anchor.global_position) / (Rules.HOOK_SPEED * (1.0 + tiers.hook * 0.2))
 hook_left = hook_duration
 notice.emit("HOOK FIRED — hold to swing; Shift to reel")
 return true

func release_wire(record_input: bool = true) -> void:
 if record_input and is_instance_valid(anchor):
  released_ago = 0
 anchor = null
 wire_side = 0
 hook_left = 0
 blocked_time = 0
 if mode == "swing":
  mode = "air"

func jump() -> void:
 if mode in ["ground", "slide"]:
  release_wire(false)
  velocity.y = Rules.JUMP_SPEED * sqrt(1.0 + tiers.jump * 0.1)
  mode = "air"
  slide_left = 0
  notice.emit("RECONNECT — hold a mouse button in the air")

func launch() -> bool:
 if tiers.launcher == 0 or launch_cooldown > 0 or mode in ["dead", "stumble", "landing"]:
  return false
 var left: Node3D = city.find_anchor(global_position, -1, 40, get_rid())
 var right: Node3D = city.find_anchor(global_position, 1, 40, get_rid())
 if left == null or right == null:
  notice.emit("TWIN LAUNCH NEEDS TWO FORWARD ANCHORS")
  return false
 release_wire(false)
 twin_left = left
 twin_right = right
 launch_left = 0.18
 launch_cooldown = 10.0
 notice.emit("TWIN LAUNCH")
 return true

func simulate(delta: float, steer: float, reel: bool) -> void:
 if mode == "dead":
  return
 # Two fixed substeps; collision sweeps also cover full displacement at max speed.
 for step in range(2):
  integrate(delta * 0.5, steer, reel)
 high_speed = maxf(high_speed, velocity.length())
 var tilt: float = clampf(-velocity.x * 0.045, -0.45, 0.45)
 visuals.rotation.z = lerpf(visuals.rotation.z, tilt, delta * 8.0)
 visuals.rotation.x = lerpf(visuals.rotation.x, -0.55 if mode == "slide" else 0.12, delta * 8.0)

func integrate(dt: float, steer: float, reel: bool) -> void:
 if mode == "dead":
  return
 released_ago += dt
 invincible = maxf(0.0, invincible - dt)
 launch_cooldown = maxf(0.0, launch_cooldown - dt)
 if launch_left > 0:
  launch_left -= dt
  if launch_left <= 0:
   velocity.z -= Rules.LAUNCH_BOOSTS[tiers.launcher]
   velocity.y = maxf(velocity.y, 3.0)
   mode = "air"
   twin_left = null
   twin_right = null
 if mode == "landing":
  landing_left -= dt
  if released_ago <= Rules.RELEASE_WINDOW and tiers.skates > 0 and slide_armed:
   begin_slide()
  elif landing_left <= 0:
   stumble()
  else:
   return
 if mode == "stumble":
  stumble_left -= dt
  if stumble_left <= 0:
   mode = "ground"
  return
 if global_position.y >= 2.3:
  slide_armed = true
 if mode == "ground":
  velocity.z = move_toward(velocity.z, -Rules.RUN_SPEED, 55.0 * dt)
  safe_z = position.z
 if mode in ["ground", "slide"]:
  velocity.x = move_toward(velocity.x, steer * 4.5, 18.0 * dt)
 else:
  velocity.x = move_toward(velocity.x, steer * 5.0, 3.5 * dt)
 velocity.y -= Rules.GRAVITY * dt
 if is_instance_valid(anchor):
  hook_left -= dt
  if hook_left <= 0 and mode != "swing":
   rope_length = minf(reach(), global_position.distance_to(anchor.global_position))
   mode = "swing"
   slide_left = 0
  if mode == "swing":
   var query := PhysicsRayQueryParameters3D.create(global_position, anchor.global_position)
   query.exclude = [get_rid()]
   if not get_world_3d().direct_space_state.intersect_ray(query).is_empty():
    blocked_time += dt
    if blocked_time > 0.12:
     notice.emit("WIRE BLOCKED — disconnected")
     release_wire(false)
   else:
    blocked_time = 0
  if mode == "swing" and is_instance_valid(anchor):
   if reel:
    rope_length = maxf(3.0, rope_length - Rules.REEL_SPEED * (1.0 + tiers.reel * 0.15) * dt)
   var radial: Vector3 = global_position + velocity * dt - anchor.global_position
   if radial.length() > rope_length:
    var constrained: Vector3 = anchor.global_position + radial.normalized() * rope_length
    velocity = (constrained - global_position) / dt
 velocity = velocity.limit_length(Rules.MAX_SPEED)
 var before: Vector3 = position
 var motion: Vector3 = velocity * dt
 var touched_floor: bool = false
 for collision_index in range(3):
  var incoming: Vector3 = velocity
  var hit := move_and_collide(motion)
  if hit == null:
   break
  var normal: Vector3 = hit.get_normal()
  var impact: float = maxf(0, -incoming.dot(normal))
  if normal.y > 0.7:
   touched_floor = true
   if mode in ["air", "swing"]:
    land(impact, incoming)
    if mode in ["dead", "stumble", "landing"]:
     return
   velocity = velocity.slide(normal)
  elif impact > 3.0:
   hurt("HEAD-ON COLLISION")
   return
  else:
   velocity = velocity.slide(normal) * 0.85
  motion = hit.get_remainder().slide(normal)
 if mode == "slide":
  slide_left = maxf(0.0, slide_left - Vector2(position.x - before.x, position.z - before.z).length())
  if slide_left <= 0:
   mode = "ground"
   notice.emit("SLIDE FINISHED — jump to swing again")
 if mode == "ground" and not touched_floor and velocity.y < -0.5:
  mode = "air"
 if position.y < -8.0:
  hurt("MISSED THE ROAD")
 if absf(position.x) > 6.6:
  position.x = clampf(position.x, -6.6, 6.6)
  velocity.x = 0

func land(impact: float, incoming: Vector3) -> void:
 var horizontal := Vector3(incoming.x, 0, incoming.z)
 var outcome: String = Rules.floor_outcome(impact, horizontal.length(), tiers.skates, released_ago <= Rules.RELEASE_WINDOW, slide_armed)
 if outcome == "fatal":
  hurt("HARD LANDING  /  %.1f m/s impact" % impact)
 elif outcome == "slide":
  landing_speed = horizontal
  begin_slide()
 elif tiers.skates > 0 and horizontal.length() >= Rules.SLIDE_MIN_SPEED and slide_armed and is_instance_valid(anchor):
  landing_speed = horizontal
  landing_left = Rules.RELEASE_WINDOW
  mode = "landing"
  velocity = Vector3.ZERO
  notice.emit("RELEASE NOW — slide window")
 else:
  stumble()

func begin_slide() -> void:
 release_wire(false)
 velocity = landing_speed
 mode = "slide"
 slide_left = Rules.SLIDE_DISTANCES[tiers.skates]
 slide_armed = false
 slides += 1
 notice.emit("PERFECT SLIDE — Space to jump / mouse to reconnect")
 slid.emit()

func stumble() -> void:
 release_wire(false)
 mode = "stumble"
 stumble_left = 0.6
 velocity = Vector3.ZERO
 notice.emit("STUMBLED — jump before hooking; release near the ground")

func hurt(reason: String) -> void:
 if invincible > 0:
  velocity = Vector3(0, 2, -Rules.RUN_SPEED)
  return
 release_wire(false)
 launch_left = 0
 twin_left = null
 twin_right = null
 if armor_charges > 0 or practice:
  if not practice:
   armor_charges -= 1
  position = Vector3(0, 6, position.z + 5.0)
  velocity = Vector3(0, 0, -12)
  mode = "air"
  invincible = 1.0
  notice.emit("PRACTICE RESCUE / " + reason if practice else "ARMOR SAVED YOU")
 else:
  mode = "dead"
  velocity = Vector3.ZERO
  crashed.emit(reason)

func upgrade(key: String) -> void:
 tiers[key] = mini(3, tiers[key] + 1)
 if key == "armor":
  armor_charges = mini(tiers.armor, armor_charges + 1)

func draw_wire() -> void:
 wire_surface.clear_surfaces()
 if not is_instance_valid(anchor) and launch_left <= 0:
  return
 wire_surface.surface_begin(Mesh.PRIMITIVE_LINES)
 if is_instance_valid(anchor):
  var target: Vector3 = anchor.global_position
  if hook_left > 0:
   target = global_position.lerp(target, 1.0 - hook_left / hook_duration)
  wire_surface.surface_add_vertex(global_position + Vector3(0, 0.3, 0))
  wire_surface.surface_add_vertex(target)
 if launch_left > 0:
  for target in [twin_left, twin_right]:
   if is_instance_valid(target):
    wire_surface.surface_add_vertex(global_position)
    wire_surface.surface_add_vertex(target.global_position)
 wire_surface.surface_end()
