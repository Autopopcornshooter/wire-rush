extends Node3D
const Rules = preload("res://scripts/rules.gd")
const Locale = preload("res://scripts/localization.gd")
const LENGTH: float = 64.0
const TYPES: Array[String] = ["FREE FLOW", "SKY POSTS", "HIGH CROSSING", "ZIGZAG", "LOW APPROACH", "AERIAL STEPS"]
var chunks: Dictionary = {}
var pickups: Array[Node3D] = []
var origin_offset: float = 0
var high_level: int = 0
var practice: bool = false
var material_cache: Dictionary = {}
var locale = Locale.new()

func material(color: Color, glow: bool = false) -> StandardMaterial3D:
 var key: String = color.to_html() + str(glow)
 if material_cache.has(key):
  return material_cache[key]
 var mat := StandardMaterial3D.new()
 mat.albedo_color = color
 mat.roughness = 0.85
 if glow:
  mat.emission_enabled = true
  mat.emission = color
  mat.emission_energy_multiplier = 1.6
 material_cache[key] = mat
 return mat

func box(parent: Node3D, pos: Vector3, size: Vector3, color: Color, solid: bool = false, glow: bool = false) -> Node3D:
 var root: Node3D = StaticBody3D.new() if solid else Node3D.new()
 parent.add_child(root)
 root.position = pos
 var mesh := MeshInstance3D.new()
 var shape := BoxMesh.new()
 shape.size = size
 mesh.mesh = shape
 mesh.material_override = material(color, glow)
 root.add_child(mesh)
 if solid:
  var collision := CollisionShape3D.new()
  var cuboid := BoxShape3D.new()
  cuboid.size = size
  collision.shape = cuboid
  root.add_child(collision)
 return root

func update_chunks(distance: float, attached: Node3D = null) -> void:
 var current: int = floori(distance / LENGTH)
 for index in range(maxi(0, current - 1), current + 6):
  if not chunks.has(index):
   create_chunk(index)
 for key in chunks.keys():
  if key < current - 2:
   var chunk: Node3D = chunks[key]
   if is_instance_valid(attached) and chunk.is_ancestor_of(attached):
    continue
   for i in range(pickups.size() - 1, -1, -1):
    if chunk.is_ancestor_of(pickups[i]):
     pickups.remove_at(i)
   chunks.erase(key)
   chunk.free()

func create_chunk(index: int) -> void:
 var chunk := Node3D.new()
 chunk.name = "Block_%d" % index
 add_child(chunk)
 chunk.position.z = -index * LENGTH + origin_offset
 chunks[index] = chunk
 var kind: int = 0 if index < 2 or practice else (index - 2) % 5 + 1
 var road := box(chunk, Vector3(0, -0.5, -32), Vector3(14, 1, 64), Color("192b40"), true)
 road.set_meta("road", true)
 for side in [-1, 1]:
  box(chunk, Vector3(side * 6.8, 0.035, -32), Vector3(0.1, 0.05, 64), Color("52d8cf"), false, true)
  for b in range(4):
   var z: float = -8 - b * 16
   var base_height: float = 23 + posmod(index * 7 + b * 3 + side, 5) * 3
   var building := box(chunk, Vector3(side * 11.4, 0, z), Vector3(8, base_height, 14), Color("233c56") if (index + b) % 2 == 0 else Color("294860"), true)
   building.set_meta("hookable", true)
   building.set_meta("building", true)
   building.set_meta("base_height", base_height)
   # Windows are local to the grounded building origin, so upgrades never move a hook.
   var windows := Node3D.new()
   windows.name = "Windows"
   building.add_child(windows)
   for floor_index in range(2, 23):
    var window := box(windows, Vector3(-side * 4.06, floor_index * 3, 0), Vector3(0.06, 0.7, 10), Color("39566e"))
    window.set_meta("floor_height", floor_index * 3)
   resize_building(building)
   # A continuous 5m reference stripe helps deliberate low-hook approaches.
   box(chunk, Vector3(side * 7.32, 5, z), Vector3(0.08, 0.1, 12), Color("63b2bb"), false, true)
 for stripe in range(8):
  box(chunk, Vector3(0, 0.025, -stripe * 8 - 4), Vector3(0.08, 0.035, 3), Color("45627a"))
 if kind > 0:
  # Four compact hazards per 64m, spread sideways and vertically instead of a full-width wall.
  for i in range(4):
   var x: float = [-3.7, 0.0, 3.7][posmod(index + i, 3)]
   var y: float = [6.0, 12.0, 18.0, 24.0][posmod(i + kind, 4)]
   obstacle(chunk, Vector3(x, y, -10 - i * 14), Vector3(2.6, 2.2, 1.4))
 for i in range(4):
  var orb := MeshInstance3D.new()
  var sphere := SphereMesh.new()
  sphere.radius = 0.24
  sphere.height = 0.48
  orb.mesh = sphere
  orb.material_override = material(Color("ffc876"), true)
  chunk.add_child(orb)
  orb.position = Vector3(0, 3.5, -12 - i * 9)
  orb.set_meta("xp", 15)
  pickups.append(orb)
 var sign := Label3D.new()
 sign.name = "RouteSign"
 chunk.add_child(sign)
 sign.position = Vector3(0, 15 + Rules.BUILDING_BONUS[high_level] * 0.8, -2)
 sign.set_meta("route", TYPES[kind])
 sign.set_meta("index", index + 1)
 sign.font = Locale.FONT
 sign.text = "%02d / %s" % [index + 1, locale.text(TYPES[kind])]
 sign.font_size = 58
 sign.pixel_size = 0.014
 sign.modulate = Color("a4c9d8")
 sign.billboard = BaseMaterial3D.BILLBOARD_ENABLED

func resize_building(building: Node3D) -> void:
 var height: float = float(building.get_meta("base_height")) + Rules.BUILDING_BONUS[high_level]
 var mesh: MeshInstance3D = building.get_child(0)
 var collision: CollisionShape3D = building.get_child(1)
 mesh.mesh.size.y = height
 mesh.position.y = height * 0.5
 collision.shape.size.y = height
 collision.position.y = height * 0.5
 building.set_meta("height", height)
 for window in building.get_node("Windows").get_children():
  window.visible = float(window.get_meta("floor_height")) < height - 1

func apply_height_level(level: int) -> void:
 if level == high_level:
  return
 high_level = clampi(level, 0, 3)
 for chunk in chunks.values():
  for child in chunk.get_children():
   if child.get_meta("building", false):
    resize_building(child)
   elif child.get_meta("hazard", false):
    child.position.y = float(child.get_meta("base_y")) + Rules.BUILDING_BONUS[high_level] * 0.8
  chunk.get_node("RouteSign").position.y = 15 + Rules.BUILDING_BONUS[high_level] * 0.8

func obstacle(parent: Node3D, pos: Vector3, size: Vector3) -> Node3D:
 var hazard := box(parent, pos + Vector3(0, Rules.BUILDING_BONUS[high_level] * 0.8, 0), size, Color("ad5843"), true)
 hazard.set_meta("hazard", true)
 hazard.set_meta("hookable", true)
 hazard.set_meta("base_y", pos.y)
 box(hazard, Vector3(0, size.y * 0.5 + 0.02, 0), Vector3(size.x, 0.12, size.z + 0.05), Color("ffbc78"), false, true)
 for i in range(3):
  box(parent, Vector3(pos.x, 0.04, pos.z + 40 - i * 8), Vector3(2.4 - i * 0.3, 0.03, 0.35), Color("e8a468"), false, true)
 return hazard

func refresh_language() -> void:
 for chunk in chunks.values():
  var sign: Label3D = chunk.get_node("RouteSign")
  sign.text = "%02d / %s" % [sign.get_meta("index"), locale.text(sign.get_meta("route"))]

func manual_target(from: Vector3, ray_origin: Vector3, direction: Vector3, reach: float, exclude: RID) -> Dictionary:
 var query := PhysicsRayQueryParameters3D.create(ray_origin, ray_origin + direction.normalized() * 500.0, 1)
 query.exclude = [exclude]
 var hit: Dictionary = get_world_3d().direct_space_state.intersect_ray(query)
 if hit.is_empty():
  return {"valid": false, "reason": "AIM AT A SURFACE"}
 return validate_manual_point(from, hit.position, hit.normal, hit.collider, reach, exclude)

func validate_manual_point(from: Vector3, surface_point: Vector3, normal: Vector3, surface: Node3D, reach: float, exclude: RID) -> Dictionary:
 if not is_instance_valid(surface) or not is_ancestor_of(surface) or not surface.get_meta("hookable", false):
  return {"valid": false, "reason": "AIM AT A SURFACE"}
 # Keep the endpoint just outside the wall so its own surface cannot occlude the rope.
 var point: Vector3 = surface_point + normal * 0.08
 var result: Dictionary = {"valid": false, "point": point, "surface_point": surface_point, "normal": normal, "surface": surface, "distance": from.distance_to(point)}
 if point.y < 2.5:
  result.reason = "AIM ABOVE 2.5m"
 elif from.distance_to(point) > reach:
  result.reason = "OUT OF RANGE"
 else:
  var line := PhysicsRayQueryParameters3D.create(from, point, 1)
  line.exclude = [exclude]
  if not get_world_3d().direct_space_state.intersect_ray(line).is_empty():
   result.reason = "WIRE PATH BLOCKED"
  else:
   result.valid = true
   result.reason = "POINT READY"
 return result

func collect(pos: Vector3) -> int:
 var gained: int = 0
 for i in range(pickups.size() - 1, -1, -1):
  var pickup: Node3D = pickups[i]
  if pickup.global_position.distance_squared_to(pos) < 5.0:
   gained += int(pickup.get_meta("xp"))
   pickups.remove_at(i)
   pickup.queue_free()
 return gained

func rebase(amount: float) -> void:
 origin_offset += amount
 for chunk in chunks.values():
  chunk.position.z += amount
