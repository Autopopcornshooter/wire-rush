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
var last_release_height: float = 0
var fresh_landing_hook: bool = false
var jump_exempt: bool = false
var invincible: float = 0
var launch_left: float = 0
var launch_cooldown: float = 0
var launch_velocity := Vector3.ZERO
var twin_anchors: Array[Node3D] = []
var ignored_obstacles: Array[PhysicsBody3D] = []
var armor_charges: int = 0
var tiers: Dictionary = {"skates": 0, "launcher": 0, "armor": 0, "high": 0, "range": 0, "reel": 0, "hook": 0, "jump": 0}
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
 clear_obstacle_exceptions()
 visuals.visible = true
 practice = training
 mode = "air"
 position = Vector3(0, city.start_height(), 0)
 velocity = Vector3(0, -2, -12)
 tiers = {"skates": 1 if training else 0, "launcher": 0, "armor": 0, "high": 0, "range": 0, "reel": 0, "hook": 0, "jump": 0}
 armor_charges = 0
 launch_cooldown = 0
 invincible = 0
 last_release_height = 0
 fresh_landing_hook = false
 jump_exempt = false
 slides = 0
 high_speed = 0

func reach() -> float:
 return Rules.ROPE_RANGE * (1.0 + tiers.range * 0.1)

func fire_manual(selection: Dictionary, side: int) -> bool:
 if mode == "dead" or launch_left > 0:
  return false
 if not selection.get("valid", false):
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
 anchor = point
 wire_side = side
 hook_duration = global_position.distance_to(point.global_position) / (Rules.HOOK_SPEED * (1.0 + tiers.hook * 0.2))
 hook_left = hook_duration
 hook_connected = false
 notice.emit("MANUAL HOOK FIRED — position locked until the next shot")
 return true

func release_wire() -> void:
 if not twin_anchors.is_empty():
  finish_launch()
 if is_instance_valid(anchor):
  if hook_connected:
   last_release_height = global_position.y
  anchor.queue_free()
 anchor = null
 wire_side = 0
 hook_left = 0
 hook_connected = false
 blocked_time = 0
 if mode == "swing":
  mode = "air"
 # Only detaching a connected wire records player height. Empty/in-flight releases
 # preserve this history, including repeated cleanup and pause/resume calls.

func launch() -> bool:
 if mode == "dead" or launch_left > 0:
  return false
 if launch_cooldown > 0:
  notice.emit("TWIN LAUNCH COOLING DOWN")
  return false
 var targets: Array[Dictionary] = city.launch_targets(global_position, reach(), get_rid())
 if targets.size() != 2:
  notice.emit("TWIN LAUNCH NEEDS TWO FORWARD WALLS")
  return false
 release_wire()
 for target in targets:
  var point := Node3D.new()
  target.surface.add_child(point)
  point.global_position = target.point
  twin_anchors.append(point)
 var displacement: Vector3 = (twin_anchors[0].global_position + twin_anchors[1].global_position) * 0.5 - global_position
 launch_velocity = displacement.normalized() * Rules.LAUNCH_SPEEDS[tiers.launcher]
 launch_left = minf(Rules.LAUNCH_SECONDS, maxf(0.01, displacement.length() - 1.5) / launch_velocity.length())
 launch_cooldown = Rules.LAUNCH_COOLDOWN
 velocity = launch_velocity
 mode = "launch"
 jump_exempt = false
 fresh_landing_hook = true
 notice.emit("TWIN LAUNCH — collisions remain dangerous")
 return true

func finish_launch() -> void:
 last_release_height = global_position.y
 for point in twin_anchors:
  if is_instance_valid(point):
   point.queue_free()
 twin_anchors.clear()
 launch_left = 0
 if mode == "launch":
  mode = "air"

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
  notice.emit("JUMP — safe landing unless you connect a new wire")

func landing_height() -> float:
 # While attached, preview the result of releasing at the current player height.
 return global_position.y if (is_instance_valid(anchor) and hook_connected) or not twin_anchors.is_empty() else last_release_height

func landing_safe() -> bool:
 return jump_exempt or landing_height() <= Rules.SAFE_RELEASE_HEIGHT + 0.00001

func simulate(delta: float, steer: float) -> void:
 if mode == "dead":
  return
 for step in range(2):
  integrate(delta * 0.5, steer)
 high_speed = maxf(high_speed, velocity.length())
 visuals.visible = invincible <= 0 or fmod(invincible, 0.4) > 0.16
 visuals.rotation.z = lerpf(visuals.rotation.z, clampf(-velocity.x * 0.045, -0.45, 0.45), delta * 8)
 visuals.rotation.x = lerpf(visuals.rotation.x, -0.55 if mode == "slide" else 0.12, delta * 8)

func integrate(dt: float, steer: float) -> void:
 if mode == "dead":
  return
 invincible = maxf(0, invincible - dt)
 if invincible <= 0:
  clear_obstacle_exceptions()
 launch_cooldown = maxf(0, launch_cooldown - dt)
 var launching: bool = launch_left > 0
 if launching:
  velocity = launch_velocity
  launch_left = maxf(0, launch_left - dt)
 elif mode == "ground":
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
 if not launching:
  velocity.y -= Rules.GRAVITY * dt
 if is_instance_valid(anchor):
  hook_left -= dt
  var surface: Node3D = anchor.get_parent() if hook_connected else null
  var blocked: bool = invincible <= 0 and city.wire_path_blocked(global_position, anchor.global_position, get_rid(), surface)
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
   if mode in ["air", "swing", "launch"]:
    land(incoming)
    if mode in ["dead", "ground"]:
     return
   velocity = velocity.slide(normal)
  elif not collider.get_meta("road", false) and (invincible > 0 or impact > 3):
   if not hurt("OBSTACLE COLLISION"):
    return
   # Preserve incoming velocity and use the untraveled sweep after the hit.
   # Only obstacle bodies are ignored. Road landing rules remain active.
   if collider is PhysicsBody3D:
    add_collision_exception_with(collider)
    if not ignored_obstacles.has(collider):
     ignored_obstacles.append(collider)
   motion = hit.get_remainder()
   continue
  else:
   velocity = velocity.slide(normal) * 0.85
  motion = hit.get_remainder().slide(normal)
 if launching and launch_left <= 0 and not twin_anchors.is_empty():
  finish_launch()
 if mode in ["ground", "slide"] and not touched_floor and velocity.y < -0.5:
  mode = "air"
 if position.y < -8:
  hurt("MISSED THE ROAD")
 if absf(position.x) > 6.6:
  position.x = clampf(position.x, -6.6, 6.6)
  velocity.x = 0

func land(incoming: Vector3) -> void:
 # Road contact also detaches a held wire at the player contact height.
 release_wire()
 if not landing_safe():
  die("HIGH RELEASE LANDING — player released above 5m")
  return
 var can_slide: bool = fresh_landing_hook and not jump_exempt and tiers.skates > 0
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
 visuals.visible = true
 clear_obstacle_exceptions()
 velocity = Vector3.ZERO
 crashed.emit(reason)

func clear_obstacle_exceptions() -> void:
 for body in ignored_obstacles:
  if is_instance_valid(body):
   remove_collision_exception_with(body)
 ignored_obstacles.clear()

func hurt(reason: String) -> bool:
 if invincible > 0 and position.y >= -8:
  return true
 if reason == "OBSTACLE COLLISION" and armor_charges > 0:
  armor_charges -= 1
  invincible = Rules.ARMOR_PROTECTION
  notice.emit("ARMOR HIT — keep moving / protected for 2 seconds")
  return true
 release_wire()
 clear_obstacle_exceptions()
 if armor_charges > 0 or practice or invincible > 0:
  if not practice and invincible <= 0:
   armor_charges -= 1
  position = Vector3(0, 6, position.z + 5)
  velocity = Vector3(0, 0, -12)
  mode = "air"
  last_release_height = 0
  fresh_landing_hook = false
  jump_exempt = false
  invincible = 1
  notice.emit("PRACTICE RESCUE / " + reason if practice else "ARMOR SAVED YOU")
 else:
  die(reason)
 return false

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
 if not is_instance_valid(anchor) and twin_anchors.is_empty():
  return
 wire_surface.surface_begin(Mesh.PRIMITIVE_LINES)
 wire_surface.surface_set_color(Color("78f9e5"))
 for target_node in ([anchor] if is_instance_valid(anchor) else twin_anchors):
  var target: Vector3 = target_node.global_position
  if hook_left > 0:
   target = global_position.lerp(target, 1 - hook_left / hook_duration)
  wire_surface.surface_add_vertex(global_position + Vector3(0, 0.3, 0))
  wire_surface.surface_add_vertex(target)
 wire_surface.surface_end()
