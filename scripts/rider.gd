extends CharacterBody3D
const Rules = preload("res://scripts/rules.gd")
signal notice(message: String)
signal crashed(reason: String)
signal slid
var city: Node3D
var mode: String = "air"
var anchor: Node3D = null
var wire_side: int = 0
var rope_length: float = 0
var hook_left: float = 0
var hook_duration: float = 0
var hook_connected: bool = false
var blocked_time: float = 0
var last_anchor_height: float = 0
var fresh_landing_hook: bool = false
var jump_exempt: bool = false
var invincible: float = 0
var armor_charges: int = 0
var tiers: Dictionary = {"skates": 0, "armor": 0, "high": 0, "range": 0, "reel": 0, "hook": 0, "jump": 0}
var practice: bool = false
var visuals: Node3D
var wire_mesh: MeshInstance3D
var wire_surface: ImmediateMesh
var high_speed: float = 0
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
 var wire_material := StandardMaterial3D.new()
 wire_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
 wire_material.vertex_color_use_as_albedo = true
 wire_mesh.material_override = wire_material
 add_child(wire_mesh)
 wire_mesh.top_level = true

func reset(training: bool) -> void:
 release_wire()
 practice = training
 mode = "air"
 position = Vector3(0, 6, 0)
 velocity = Vector3(0, 0, -12)
 tiers = {"skates": 1 if training else 0, "armor": 0, "high": 0, "range": 0, "reel": 0, "hook": 0, "jump": 0}
 armor_charges = 0
 invincible = 0
 last_anchor_height = 0
 fresh_landing_hook = false
 jump_exempt = false
 slides = 0
 high_speed = 0

func reach() -> float:
 return Rules.ROPE_RANGE * (1.0 + tiers.range * 0.1)

func fire_manual(selection: Dictionary, side: int) -> bool:
 if mode == "dead" or not selection.get("valid", false):
  notice.emit(selection.get("reason", "AIM AT A SURFACE"))
  return false
 var checked: Dictionary = city.validate_manual_point(global_position, selection.surface_point, selection.normal, selection.surface, reach(), get_rid())
 if not checked.valid:
  notice.emit(checked.reason)
  return false
 release_wire()
 var point := Node3D.new()
 checked.surface.add_child(point)
 point.global_position = checked.point
 point.set_meta("height_offset", checked.point.y - checked.surface_point.y)
 anchor = point
 wire_side = side
 hook_duration = global_position.distance_to(point.global_position) / (Rules.HOOK_SPEED * (1.0 + tiers.hook * 0.2))
 hook_left = hook_duration
 hook_connected = false
 notice.emit("MANUAL HOOK FIRED — position locked until the next shot")
 return true

func release_wire() -> void:
 if is_instance_valid(anchor):
  if hook_connected:
   last_anchor_height = anchor.global_position.y - float(anchor.get_meta("height_offset"))
  anchor.queue_free()
 anchor = null
 wire_side = 0
 hook_left = 0
 hook_connected = false
 blocked_time = 0
 if mode == "swing":
  mode = "air"
 # Landing history deliberately survives release, pause and unsuccessful shots.

func release_side(side: int) -> void:
 if wire_side == side:
  release_wire()

func jump() -> void:
 if mode in ["ground", "slide"]:
  release_wire()
  velocity.y = Rules.JUMP_SPEED * sqrt(1.0 + tiers.jump * 0.1)
  mode = "air"
  jump_exempt = true
  fresh_landing_hook = false
  notice.emit("JUMP — safe landing unless you connect a new high hook")

func landing_safe() -> bool:
 var height: float = last_anchor_height
 if is_instance_valid(anchor) and hook_connected:
  height = anchor.global_position.y - float(anchor.get_meta("height_offset"))
 return jump_exempt or height <= Rules.SAFE_ANCHOR_HEIGHT + 0.00001

func simulate(delta: float, steer: float) -> void:
 if mode == "dead":
  return
 for step in range(2):
  integrate(delta * 0.5, steer)
 high_speed = maxf(high_speed, velocity.length())
 visuals.rotation.z = lerpf(visuals.rotation.z, clampf(-velocity.x * 0.045, -0.45, 0.45), delta * 8)
 visuals.rotation.x = lerpf(visuals.rotation.x, -0.55 if mode == "slide" else 0.12, delta * 8)

func integrate(dt: float, steer: float) -> void:
 if mode == "dead":
  return
 invincible = maxf(0, invincible - dt)
 if mode == "ground":
  velocity.z = 0
  velocity.x = move_toward(velocity.x, steer * 4.5, 18 * dt)
 elif mode == "slide":
  var horizontal := Vector3(velocity.x, 0, velocity.z)
  var speed: float = maxf(0, horizontal.length() - Rules.SKATE_FRICTION[tiers.skates] * Rules.GRAVITY * dt)
  # Steering rotates the decelerating velocity; it cannot create new speed.
  var direction: Vector3 = horizontal.normalized().rotated(Vector3.UP, -steer * 0.6 * dt)
  velocity.x = direction.x * speed
  velocity.z = direction.z * speed
  if speed <= Rules.STOP_SPEED:
   stop_on_ground()
 else:
  velocity.x = move_toward(velocity.x, steer * 5, 3.5 * dt)
 velocity.y -= Rules.GRAVITY * dt
 if is_instance_valid(anchor):
  hook_left -= dt
  var query := PhysicsRayQueryParameters3D.create(global_position, anchor.global_position)
  query.exclude = [get_rid()]
  var blocked: bool = not get_world_3d().direct_space_state.intersect_ray(query).is_empty()
  if blocked:
   blocked_time += dt
   if blocked_time > 0.12:
    notice.emit("WIRE BLOCKED — disconnected")
    release_wire()
  else:
   blocked_time = 0
  if is_instance_valid(anchor) and hook_left <= 0 and not blocked:
   if not hook_connected:
    hook_connected = true
    rope_length = global_position.distance_to(anchor.global_position)
    fresh_landing_hook = true
    jump_exempt = false
   last_anchor_height = anchor.global_position.y - float(anchor.get_meta("height_offset"))
   mode = "swing"
   rope_length = maxf(3, rope_length - Rules.REEL_SPEED * (1 + tiers.reel * 0.15) * dt)
   var radial: Vector3 = global_position + velocity * dt - anchor.global_position
   if radial.length() > rope_length:
    velocity = (anchor.global_position + radial.normalized() * rope_length - global_position) / dt
 velocity = velocity.limit_length(Rules.MAX_SPEED)
 var motion: Vector3 = velocity * dt
 var touched_floor: bool = false
 for collision_index in range(3):
  var incoming: Vector3 = velocity
  var hit := move_and_collide(motion)
  if hit == null:
   break
  var normal: Vector3 = hit.get_normal()
  var impact: float = maxf(0, -incoming.dot(normal))
  var collider: Object = hit.get_collider()
  if normal.y > 0.7 and collider.get_meta("road", false):
   touched_floor = true
   if mode in ["air", "swing"]:
    land(incoming)
    if mode in ["dead", "ground"]:
     return
   velocity = velocity.slide(normal)
  elif impact > 3 and invincible <= 0:
   hurt("OBSTACLE COLLISION")
   return
  else:
   velocity = velocity.slide(normal) * 0.85
  motion = hit.get_remainder().slide(normal)
 if mode in ["ground", "slide"] and not touched_floor and velocity.y < -0.5:
  mode = "air"
 if position.y < -8:
  hurt("MISSED THE ROAD")
 if absf(position.x) > 6.6:
  position.x = clampf(position.x, -6.6, 6.6)
  velocity.x = 0

func land(incoming: Vector3) -> void:
 if not landing_safe():
  die("HIGH ANCHOR LANDING — last hook above 5m")
  return
 var can_slide: bool = fresh_landing_hook and not jump_exempt and tiers.skates > 0
 release_wire()
 fresh_landing_hook = false
 jump_exempt = false
 if can_slide and Vector2(incoming.x, incoming.z).length() > Rules.STOP_SPEED:
  velocity = Vector3(incoming.x, 0, incoming.z)
  mode = "slide"
  slides += 1
  notice.emit("SKATING — friction slows you down; reconnect before landing again")
  slid.emit()
 else:
  stop_on_ground()

func stop_on_ground() -> void:
 release_wire()
 mode = "ground"
 velocity = Vector3.ZERO
 notice.emit("LANDED — stopped; Space to jump or mouse to hook")

func die(reason: String) -> void:
 release_wire()
 mode = "dead"
 velocity = Vector3.ZERO
 crashed.emit(reason)

func hurt(reason: String) -> void:
 if invincible > 0 and position.y >= -8:
  return
 release_wire()
 if armor_charges > 0 or practice or invincible > 0:
  if not practice and invincible <= 0:
   armor_charges -= 1
  position = Vector3(0, 6, position.z + 5)
  velocity = Vector3(0, 0, -12)
  mode = "air"
  last_anchor_height = 0
  fresh_landing_hook = false
  jump_exempt = false
  invincible = 1
  notice.emit("PRACTICE RESCUE / " + reason if practice else "ARMOR SAVED YOU")
 else:
  die(reason)

func upgrade(key: String) -> void:
 if not tiers.has(key):
  return
 tiers[key] = mini(3, tiers[key] + 1)
 if key == "armor":
  armor_charges = mini(tiers.armor, armor_charges + 1)
 elif key == "high":
  city.apply_height_level(tiers.high)

func draw_wire() -> void:
 wire_surface.clear_surfaces()
 if not is_instance_valid(anchor):
  return
 wire_surface.surface_begin(Mesh.PRIMITIVE_LINES)
 wire_surface.surface_set_color(Color("78f9e5"))
 var target: Vector3 = anchor.global_position
 if hook_left > 0:
  target = global_position.lerp(target, 1 - hook_left / hook_duration)
 wire_surface.surface_add_vertex(global_position + Vector3(0, 0.3, 0))
 wire_surface.surface_add_vertex(target)
 wire_surface.surface_end()
