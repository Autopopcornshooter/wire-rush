extends Node3D
const Rules = preload("res://scripts/rules.gd")
const LENGTH: float = 64.0
const TYPES: Array[String] = ["FREE FLOW", "HURDLES", "LOW CEILING", "LONG REACH", "LOW LINE", "RECONNECT"]
var chunks: Dictionary = {}
var anchors: Array[Node3D] = []
var pickups: Array[Node3D] = []
var origin_offset: float = 0.0
var high_level: int = 0
var practice: bool = false
var material_cache: Dictionary = {}

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
   for i in range(anchors.size() - 1, -1, -1):
    if chunk.is_ancestor_of(anchors[i]):
     anchors.remove_at(i)
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
 var kind: int = 0 if index < 4 or practice else (index - 4) % TYPES.size()
 box(chunk, Vector3(0, -0.5, -32), Vector3(14, 1, 64), Color("192b40"), true)
 for side in [-1, 1]:
  box(chunk, Vector3(side * 6.8, 0.035, -32), Vector3(0.10, 0.05, 64), Color("52d8cf"), false, true)
  for b in range(4):
   var z: float = -8.0 - b * 16.0
   var height: float = 17.0 + float((index * 7 + b * 3 + side) % 5) * 3.0
   var col := Color("233c56") if (index + b) % 2 == 0 else Color("294860")
   box(chunk, Vector3(side * 11.4, height * 0.5, z), Vector3(8, height, 14), col, true)
   box(chunk, Vector3(side * 7.32, 9, z), Vector3(0.08, 0.15, 12), Color("63b2bb"), false, true)
   for floor_index in range(2, int(height / 3)):
    box(chunk, Vector3(side * 7.34, floor_index * 3.0, z), Vector3(0.06, 0.7, 10), Color("39566e"))
   if kind != 3 or b != 2:
    add_anchor(chunk, Vector3(side * 6.1, 10.0 + (b % 2) * 2.0, z), side)
    add_anchor(chunk, Vector3(side * 6.1, 10.0, z - 8.0), side)
    if high_level > 0:
     add_anchor(chunk, Vector3(side * 6.1, 12.0 + Rules.HIGH_ANCHORS[high_level], z), side)
 for stripe in range(8):
  box(chunk, Vector3(0, 0.025, -stripe * 8.0 - 4), Vector3(0.08, 0.035, 3), Color("45627a"))
 if kind == 1 or kind == 5:
  obstacle(chunk, Vector3(0, 0.85, -38), Vector3(14, 1.7, 1.2))
 elif kind == 2:
  obstacle(chunk, Vector3(0, 11, -38), Vector3(14, 7, 1.2))
 elif kind == 4:
  obstacle(chunk, Vector3(-4.5, 2.5, -40), Vector3(5, 5, 1.2))
 # Pickups are deterministic and removed from the active list on collection.
 for i in range(4):
  var orb := MeshInstance3D.new()
  var sphere := SphereMesh.new()
  sphere.radius = 0.24
  sphere.height = 0.48
  orb.mesh = sphere
  orb.material_override = material(Color("ffc876"), true)
  chunk.add_child(orb)
  orb.position = Vector3(2.0 if kind == 4 else 0.0, 1.5 if kind == 4 else 3.5, -12.0 - i * 9.0)
  orb.set_meta("xp", 40 if kind == 4 else 15)
  pickups.append(orb)
 var sign := Label3D.new()
 chunk.add_child(sign)
 sign.position = Vector3(0, 15, -2)
 sign.text = "%02d / %s" % [index + 1, TYPES[kind]]
 sign.font_size = 58
 sign.pixel_size = 0.014
 sign.modulate = Color("a4c9d8")
 sign.no_depth_test = false
 sign.billboard = BaseMaterial3D.BILLBOARD_ENABLED

func obstacle(parent: Node3D, pos: Vector3, size: Vector3) -> void:
 var hazard := box(parent, pos, size, Color("ad5843"), true)
 hazard.set_meta("hazard", true)
 box(parent, pos + Vector3(0, size.y * 0.5, 0.03), Vector3(size.x, 0.12, size.z + 0.05), Color("ffbc78"), false, true)
 # Ground warning starts 60m before impact: >= 1.5s even at 35m/s.
 for i in range(3):
  box(parent, Vector3(0, 0.04, pos.z + 60 - i * 8), Vector3(5 - i, 0.03, 0.35), Color("e8a468"), false, true)

func add_anchor(parent: Node3D, pos: Vector3, side: int) -> void:
 var anchor := Node3D.new()
 parent.add_child(anchor)
 anchor.position = pos
 anchor.set_meta("side", side)
 var mesh := MeshInstance3D.new()
 var sphere := SphereMesh.new()
 sphere.radius = 0.36
 sphere.height = 0.72
 mesh.mesh = sphere
 mesh.material_override = material(Color("61f5df") if side == -1 else Color("ffbc78"), true)
 anchor.add_child(mesh)
 anchors.append(anchor)

func find_anchor(from: Vector3, side: int, reach: float, exclude: RID) -> Node3D:
 var selected: Node3D = null
 var best: float = INF
 for anchor in anchors:
  var delta: Vector3 = anchor.global_position - from
  if anchor.get_meta("side") != side or delta.z > -2.0 or delta.length() > reach:
   continue
  var query := PhysicsRayQueryParameters3D.create(from, anchor.global_position)
  query.exclude = [exclude]
  if not get_world_3d().direct_space_state.intersect_ray(query).is_empty():
   continue
  var score: float = delta.length() + absf(delta.y - 7.0) * 0.25
  if score < best:
   best = score
   selected = anchor
 return selected

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
