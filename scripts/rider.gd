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
var landing_speed: Vector3 = Vector3.ZERO
var slide_left: float = 0.0
var slide_armed: bool = true
var invincible: float = 0.0
var launch_cooldown: float = 0.0
var launch_left: float = 0.0
var launch_velocity := Vector3.ZERO
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
var dual_mode: bool = false
var dual_wires: Dictionary = {}

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
 if mode == "dead" or launch_left > 0:
  return false
 var target: Node3D = city.find_anchor(global_position, side, reach(), get_rid())
 if not dual_mode:
  release_wire(false)
 if target == null:
  notice.emit("NO ANCHOR IN RANGE — jump or try the other side")
  return false
 attach(target, side)
 notice.emit("HOOK FIRED — hold to swing and reel")
 return true

func fire_manual(selection: Dictionary, side: int) -> bool:
 if mode == "dead" or launch_left > 0:
  return false
 if not selection.get("valid", false):
  notice.emit(selection.get("reason", "AIM AT A BUILDING"))
  return false
 var checked: Dictionary = city.validate_manual_point(global_position, selection.surface_point, selection.normal, selection.surface, reach(), get_rid())
 if not checked.valid:
  notice.emit(checked.reason)
  return false
 if not dual_mode:
  release_wire(false)
 var point := Node3D.new()
 checked.surface.add_child(point)
 point.global_position = checked.point
 point.set_meta("manual", true)
 attach(point, side)
 notice.emit("MANUAL HOOK FIRED — position locked until the next shot")
 return true

func attach(target: Node3D, side: int) -> void:
 if dual_mode:
  release_side(side)
  var duration: float = global_position.distance_to(target.global_position) / (Rules.HOOK_SPEED * (1.0 + tiers.hook * 0.2))
  dual_wires[side] = {"anchor": target, "hook_left": duration, "duration": duration, "length": 0.0, "blocked": 0.0, "connected": false}
  return
 anchor = target
 wire_side = side
 hook_duration = global_position.distance_to(anchor.global_position) / (Rules.HOOK_SPEED * (1.0 + tiers.hook * 0.2))
 hook_left = hook_duration

func release_wire(record_input: bool = true) -> void:
 for side in dual_wires.keys():
  release_side(side)
 if record_input and is_instance_valid(anchor):
  released_ago = 0
 if is_instance_valid(anchor) and anchor.get_meta("manual", false):
  anchor.queue_free()
 anchor = null
 wire_side = 0
 hook_left = 0
 blocked_time = 0
 if mode == "swing":
  mode = "air"

func release_side(side: int) -> void:
 if not dual_mode:
  if wire_side == side:
   release_wire()
  return
 if not dual_wires.has(side):
  return
 var target: Node3D = dual_wires[side].anchor
 if is_instance_valid(target) and target.get_meta("manual", false):
  target.queue_free()
 dual_wires.erase(side)
 if mode == "swing" and not dual_wires.values().any(func(w: Dictionary): return w.connected):
  mode = "air"

func attached_anchors() -> Array[Node3D]:
 var result: Array[Node3D] = []
 if is_instance_valid(anchor):
  result.append(anchor)
 for wire in dual_wires.values():
  if is_instance_valid(wire.anchor):
   result.append(wire.anchor)
 for target in [twin_left, twin_right]:
  if is_instance_valid(target):
   result.append(target)
 return result

func integrate_dual(dt: float) -> void:
 var connected: Array[Dictionary] = []
 for side in dual_wires.keys():
  var wire: Dictionary = dual_wires[side]
  if not is_instance_valid(wire.anchor):
   release_side(side)
   continue
  wire.hook_left -= dt
  if wire.hook_left > 0:
   continue
  if not wire.connected:
   wire.length = global_position.distance_to(wire.anchor.global_position)
   wire.connected = true
  var query := PhysicsRayQueryParameters3D.create(global_position, wire.anchor.global_position)
  query.exclude = [get_rid()]
  wire.blocked = 0.0 if get_world_3d().direct_space_state.intersect_ray(query).is_empty() else wire.blocked + dt
  if wire.blocked > 0.12:
   release_side(side)
   notice.emit("WIRE BLOCKED — disconnected")
   continue
  wire.length = maxf(3, wire.length - Rules.REEL_SPEED * (1 + tiers.reel * 0.15) * dt)
  connected.append(wire)
 if connected.is_empty():
  if mode == "swing":
   mode = "air"
  return
 mode = "swing"
 slide_left = 0
 if connected.size() == 2:
  # Two ropes must still span the anchor gap; stop reeling before constraints conflict.
  var gap: float = connected[0].anchor.global_position.distance_to(connected[1].anchor.global_position) + 0.5
  var deficit: float = maxf(0, gap - connected[0].length - connected[1].length)
  connected[0].length += deficit * 0.5
  connected[1].length += deficit * 0.5
 var predicted: Vector3 = global_position + velocity * dt
 var constrained: Vector3 = constrain_dual(predicted, connected)
 velocity = (constrained - global_position) / dt

func constrain_dual(point: Vector3, wires: Array[Dictionary]) -> Vector3:
 var first: Dictionary = wires[0]
 var a: Vector3 = first.anchor.global_position
 var ra: float = first.length
 var on_a: Vector3 = a + (point - a).limit_length(ra)
 if wires.size() == 1:
  return on_a
 var second: Dictionary = wires[1]
 var b: Vector3 = second.anchor.global_position
 var rb: float = second.length
 if on_a.distance_to(b) <= rb:
  return on_a
 var on_b: Vector3 = b + (point - b).limit_length(rb)
 if on_b.distance_to(a) <= ra:
  return on_b
 # Closest point on the circle where the two rope spheres intersect.
 var gap: float = a.distance_to(b)
 if gap < 0.001:
  return a + (point - a).limit_length(minf(ra, rb))
 var axis: Vector3 = (b - a) / gap
 var offset: float = (ra * ra - rb * rb + gap * gap) / (2 * gap)
 var center: Vector3 = a + axis * offset
 var radius: float = sqrt(maxf(0, ra * ra - offset * offset))
 var radial: Vector3 = (point - center).slide(axis)
 if radial.length_squared() < 0.000001:
  radial = Vector3.DOWN.slide(axis)
  if radial.length_squared() < 0.000001:
   radial = Vector3.FORWARD.slide(axis)
 return center + radial.normalized() * radius

func jump() -> void:
 if mode in ["ground", "slide"]:
  release_wire(false)
  velocity.y = Rules.JUMP_SPEED * sqrt(1.0 + tiers.jump * 0.1)
  mode = "air"
  slide_left = 0
  notice.emit("RECONNECT — hold a mouse button in the air")

func launch() -> bool:
 if tiers.launcher == 0 or launch_cooldown > 0 or mode == "dead" or launch_left > 0:
  return false
 var left: Node3D = city.find_anchor(global_position, -1, 40, get_rid())
 var right: Node3D = city.find_anchor(global_position, 1, 40, get_rid())
 if left == null or right == null:
  notice.emit("TWIN LAUNCH NEEDS TWO FORWARD ANCHORS")
  return false
 release_wire(false)
 twin_left = left
 twin_right = right
 var displacement: Vector3 = (left.global_position + right.global_position) * 0.5 - global_position
 launch_velocity = displacement.normalized() * Rules.LAUNCH_SPEEDS[tiers.launcher]
 launch_left = minf(Rules.LAUNCH_SECONDS, maxf(0.01, displacement.length() - 1.5) / launch_velocity.length())
 velocity = launch_velocity
 mode = "launch"
 slide_left = 0
 invincible = maxf(invincible, launch_left + 0.3)
 launch_cooldown = 10.0
 notice.emit("TWIN DASH — protected flight toward both anchors")
 return true

func simulate(delta: float, steer: float) -> void:
 if mode == "dead":
  return
 # Two fixed substeps; collision sweeps also cover full displacement at max speed.
 for step in range(2):
  integrate(delta * 0.5, steer)
 high_speed = maxf(high_speed, velocity.length())
 var tilt: float = clampf(-velocity.x * 0.045, -0.45, 0.45)
 visuals.rotation.z = lerpf(visuals.rotation.z, tilt, delta * 8.0)
 visuals.rotation.x = lerpf(visuals.rotation.x, -0.55 if mode == "slide" else 0.12, delta * 8.0)

func integrate(dt: float, steer: float) -> void:
 if mode == "dead":
  return
 released_ago += dt
 invincible = maxf(0.0, invincible - dt)
 launch_cooldown = maxf(0.0, launch_cooldown - dt)
 if launch_left > 0:
  # Fixed player-to-anchor-midpoint vector; steering and gravity cannot bend the dash.
  var step_time: float = minf(dt, launch_left)
  position += launch_velocity * step_time
  velocity = launch_velocity
  launch_left = maxf(0, launch_left - dt)
  if launch_left <= 0:
   mode = "air"
   twin_left = null
   twin_right = null
  return
 if global_position.y >= 2.3:
  slide_armed = true
 if mode == "ground":
  velocity.z = 0
  safe_z = position.z
 if mode == "ground":
  velocity.x = move_toward(velocity.x, steer * 4.5, 18.0 * dt)
 elif mode == "slide":
  # Steering rotates horizontal momentum without reducing its magnitude.
  var speed: float = Vector2(velocity.x, velocity.z).length()
  var lateral: float = move_toward(velocity.x, steer * minf(4.5, speed), 18.0 * dt)
  velocity = Vector3(lateral, velocity.y, (-1.0 if velocity.z <= 0 else 1.0) * sqrt(maxf(0, speed * speed - lateral * lateral)))
 else:
  velocity.x = move_toward(velocity.x, steer * 5.0, 3.5 * dt)
 velocity.y -= Rules.GRAVITY * dt
 if dual_mode:
  integrate_dual(dt)
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
   # An active wire belongs to its held mouse button; release input detaches it.
   if wire_side != 0:
    rope_length = maxf(3.0, rope_length - Rules.REEL_SPEED * (1.0 + tiers.reel * 0.15) * dt)
   var radial: Vector3 = global_position + velocity * dt - anchor.global_position
   if radial.length() > rope_length:
    var constrained: Vector3 = anchor.global_position + radial.normalized() * rope_length
    velocity = (constrained - global_position) / dt
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
  if normal.y > 0.7:
   touched_floor = true
   if mode in ["air", "swing"]:
    land(incoming)
    if mode == "ground":
     return
   velocity = velocity.slide(normal)
  elif impact > 3.0 and invincible <= 0:
   hurt("HEAD-ON COLLISION")
   return
  else:
   velocity = velocity.slide(normal) * 0.85
  motion = hit.get_remainder().slide(normal)
 if mode == "slide":
  slide_left = maxf(0.0, slide_left - dt)
  if slide_left <= 0:
   stop_on_ground()
   notice.emit("SLIDE FINISHED — jump to swing again")
 if mode == "ground" and not touched_floor and velocity.y < -0.5:
  mode = "air"
 if position.y < -8.0:
  hurt("MISSED THE ROAD")
 if absf(position.x) > 6.6:
  position.x = clampf(position.x, -6.6, 6.6)
  velocity.x = 0

func land(incoming: Vector3) -> void:
 var horizontal := Vector3(incoming.x, 0, incoming.z)
 var outcome: String = Rules.floor_outcome(horizontal.length(), tiers.skates, slide_armed)
 if outcome == "slide":
  landing_speed = horizontal
  begin_slide()
 else:
  stop_on_ground()

func begin_slide() -> void:
 release_wire(false)
 velocity = landing_speed
 mode = "slide"
 slide_left = Rules.SLIDE_SECONDS[tiers.skates]
 slide_armed = false
 slides += 1
 notice.emit("SKATING — speed held; Space to jump / mouse to reconnect")
 slid.emit()

func stop_on_ground() -> void:
 release_wire(false)
 mode = "ground"
 slide_left = 0
 velocity = Vector3.ZERO
 notice.emit("LANDED — stopped safely; Space to jump or mouse to hook")

func hurt(reason: String) -> void:
 if invincible > 0:
  if position.y < -8:
   release_wire(false)
   position = Vector3(0, 6, position.z + 5)
   velocity = Vector3(0, 0, -12)
   mode = "air"
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
 if not is_instance_valid(anchor) and dual_wires.is_empty() and launch_left <= 0:
  return
 wire_surface.surface_begin(Mesh.PRIMITIVE_LINES)
 for side in dual_wires:
  wire_surface.surface_set_color(Color("78f9e5") if side == -1 else Color("ffca8d"))
  var wire: Dictionary = dual_wires[side]
  if is_instance_valid(wire.anchor):
   var target: Vector3 = wire.anchor.global_position
   if wire.hook_left > 0:
    target = global_position.lerp(target, 1 - wire.hook_left / wire.duration)
   wire_surface.surface_add_vertex(global_position + Vector3(side * 0.4, 0.3, 0))
   wire_surface.surface_add_vertex(target)
 if is_instance_valid(anchor):
  wire_surface.surface_set_color(Color("78f9e5"))
  var target: Vector3 = anchor.global_position
  if hook_left > 0:
   target = global_position.lerp(target, 1.0 - hook_left / hook_duration)
  wire_surface.surface_add_vertex(global_position + Vector3(0, 0.3, 0))
  wire_surface.surface_add_vertex(target)
 if launch_left > 0:
  wire_surface.surface_set_color(Color("78f9e5"))
  for target in [twin_left, twin_right]:
   if is_instance_valid(target):
    wire_surface.surface_add_vertex(global_position)
    wire_surface.surface_add_vertex(target.global_position)
 wire_surface.surface_end()
