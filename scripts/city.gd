extends Node3D
const Rules = preload("res://scripts/rules.gd")
const Locale = preload("res://scripts/localization.gd")
const LENGTH: float = 64.0
## Realistic building models: Downtown City MegaKit by Quaternius (CC0) — see THIRD_PARTY_NOTICES.md.
const BUILDING_MODELS: Array[PackedScene] = [
 preload("res://assets/citykit/Building_Small_1.gltf"),
 preload("res://assets/citykit/Building_Medium_2_001.gltf"),
 preload("res://assets/citykit/Building_Large_2.gltf"),
]
## Same Downtown City MegaKit (CC0) asset pack as the buildings above.
const ASPHALT_TEXTURE: Texture2D = preload("res://assets/citykit/T_Concrete_Asphalt_BaseColor.png")
var _asphalt_material: StandardMaterial3D
## Aerial obstacle visual. Measured (not eyeballed) via the model's own full
## transform chain: position is the AABB's min corner, in the model's own
## unscaled local space.
const DRONE_MODEL: PackedScene = preload("res://models/police_drone.glb")
const DRONE_AABB_POSITION := Vector3(-1.122137, -0.454674, -1.430983)
const DRONE_AABB_SIZE := Vector3(2.244274, 4.36355, 3.002841)
var chunks: Dictionary = {}
var pickups: Array[Node3D] = []
var origin_offset: float = 0
var high_level: int = 0
var practice: bool = false
var graphics_style: String = "lowpoly"
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

func asphalt_material() -> StandardMaterial3D:
 if _asphalt_material == null:
  var mat := StandardMaterial3D.new()
  mat.albedo_texture = ASPHALT_TEXTURE
  mat.roughness = 0.95
  mat.metallic_specular = 0.2
  # Tile roughly every 8m so the texture doesn't stretch into a blurry
  # smear across the full 14m-wide, 64m-long road segment.
  mat.uv1_scale = Vector3(14.0 / 8.0, 64.0 / 8.0, 1)
  _asphalt_material = mat
 return _asphalt_material

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

func update_chunks(distance: float, attached: Node3D = null, extra_anchors: Array[Node3D] = []) -> void:
 var current: int = floori(distance / LENGTH)
 for index in range(maxi(0, current - 1), current + 6):
  if not chunks.has(index):
   create_chunk(index)
 for key in chunks.keys():
  if key < current - 2:
   var chunk: Node3D = chunks[key]
   if (is_instance_valid(attached) and chunk.is_ancestor_of(attached)) or extra_anchors.any(func(n: Node3D): return is_instance_valid(n) and chunk.is_ancestor_of(n)):
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
 road.get_child(0).material_override = asphalt_material()
 for side in [-1, 1]:
  box(chunk, Vector3(side * 6.8, 0.035, -32), Vector3(0.1, 0.05, 64), Color("52d8cf"), false, true)
  for b in range(4):
   if not has_building(index, b, side):
    continue
   var z: float = -8 - b * 16
   var base_height: float = 23 + posmod(index * 7 + b * 3 + side, 5) * 3
   var building := box(chunk, Vector3(side * 11.4, 0, z), Vector3(8, base_height, 14), Color("233c56") if (index + b) % 2 == 0 else Color("294860"), true)
   building.set_meta("hookable", true)
   building.set_meta("building", true)
   building.set_meta("base_height", base_height)
   building.set_meta("model_seed", index * 3 + b + side)
   building.set_meta("road_side", side)
   if graphics_style == "realistic":
    attach_realistic_building(building, 8, 14)
   # Windows are local to the grounded building origin, so upgrades never move a hook.
   var windows := Node3D.new()
   windows.name = "Windows"
   building.add_child(windows)
   for floor_index in range(2, 23):
    var window := box(windows, Vector3(-side * 4.06, floor_index * 3, 0), Vector3(0.06, 0.7, 10), Color("39566e"))
    window.set_meta("floor_height", floor_index * 3)
   resize_building(building)
   # A continuous 5m stripe helps judge player height before releasing.
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


func start_height() -> float:
 var roof: float = 100
 for child in chunks[0].get_children():
  if child.get_meta("building", false) and is_equal_approx(child.position.z, -8):
   roof = minf(roof, child.get_meta("height"))
 return roof + 1.0

func has_building(index: int, slot: int, side: int) -> bool:
 if practice or index < 2:
  return true
 # 128m alternating sections; the first 16m has both walls as a transition.
 var section: int = floori(float(index - 2) / 2)
 if index % 2 == 0 and slot == 0:
  return true
 return side == (1 if section % 2 == 0 else -1)

func resize_building(building: Node3D) -> void:
 var height: float = float(building.get_meta("base_height")) + Rules.BUILDING_BONUS[high_level]
 var mesh: MeshInstance3D = building.get_child(0)
 var collision: CollisionShape3D = building.get_child(1)
 mesh.mesh.size.y = height
 mesh.position.y = height * 0.5
 collision.shape.size.y = height
 collision.position.y = height * 0.5
 building.set_meta("height", height)
 var windows: Node3D = building.get_node("Windows")
 windows.visible = graphics_style != "realistic"
 for window in windows.get_children():
  window.visible = float(window.get_meta("floor_height")) < height - 1
 update_realistic_scale(building)

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

func model_aabb(node: Node3D) -> AABB:
 # Recursively merges every VisualInstance3D's local AABB into one box in
 # `node`'s own local space, so a multi-mesh imported scene can be measured
 # before it has any scale/position applied.
 var result := AABB()
 var found := false
 for child in node.get_children():
  if child is Node3D:
   var child_box := AABB()
   var has_box := false
   if child is VisualInstance3D:
    child_box = child.get_aabb()
    has_box = true
   var sub: AABB = model_aabb(child)
   if sub.size != Vector3.ZERO or not sub.position.is_equal_approx(Vector3.ZERO):
    child_box = child_box.merge(sub) if has_box else sub
    has_box = true
   if has_box:
    child_box = child.transform * child_box
    result = child_box if not found else result.merge(child_box)
    found = true
 return result

func apply_uv_tiling(node: Node, scale: Vector3) -> void:
 # Non-uniform scaling stretches a mesh's geometry without touching its UVs,
 # which smears whatever texture detail sits along the stretched axis into a
 # long streak (e.g. a small trim/accent color turning into a solid band).
 # Scaling uv1_scale by the same factor makes the texture repeat instead of
 # smear, keeping brick/window texel size roughly constant. Every building
 # of a given model shares the same footprint (so the same horizontal
 # stretch), so this is applied to the model's shared materials directly
 # rather than duplicating a Material per building instance.
 if node is MeshInstance3D and node.mesh != null:
  for i in range(node.mesh.get_surface_count()):
   var mat: Material = node.mesh.surface_get_material(i)
   if mat is StandardMaterial3D:
    # These glTFs carry a baked per-vertex COLOR_0 (probably an authoring
    # leftover, e.g. a masking layer from the original scene) that ranges
    # down to pure red on many meshes including the brick walls. Godot's
    # glTF importer turns on vertex_color_use_as_albedo by default whenever
    # COLOR_0 exists, so that baked red was getting multiplied straight
    # into the albedo — nothing to do with the actual brick texture (which
    # has no red pixels at all) or with UV scale/tiling.
    mat.vertex_color_use_as_albedo = false
    # Only the main wall material is authored to tile seamlessly at any
    # scale; trim/cornice/glass/interior materials are small decorative
    # strips mapped to a specific spot in their texture. Force-tiling those
    # too pushed their UVs past 0..1 into the texture's repeat-wrap, which
    # landed on unrelated atlas pixels and showed up as solid-color bands.
    if mat.resource_name == "MI_RedBrick":
     mat.uv1_scale = scale.abs()
    # The default dielectric Fresnel reflectance (0.5) is tuned for a
    # generic asset, not sun-lit brick/concrete at a low grazing sun angle —
    # it was catching a hot, saturated glare on whichever building facades
    # happened to face the sun most directly, on top of the light energy
    # itself already being tuned down. Cutting it lowers that glare without
    # touching the diffuse albedo (so the material still reads as the same
    # brick/trim color, just less shiny).
    mat.metallic_specular = 0.2
 for child in node.get_children():
  apply_uv_tiling(child, scale)

func attach_realistic_building(building: Node3D, width: float, depth: float) -> void:
 var index: int = posmod(int(building.get_meta("model_seed", 0)), BUILDING_MODELS.size())
 var model: Node3D = BUILDING_MODELS[index].instantiate()
 model.name = "RealisticModel"
 building.add_child(model)
 model.set_meta("base_aabb", model_aabb(model))
 model.set_meta("footprint", Vector2(width, depth))
 update_realistic_scale(building)
 # The flat box mesh must stay hidden here too — this runs both for freshly
 # streamed chunks (create_chunk) and for the live style toggle
 # (refresh_building_style); only the latter used to hide it, so any
 # building created while already in "realistic" mode kept showing its old
 # box drawn right through the new model.
 building.get_child(0).visible = false

func update_realistic_scale(building: Node3D) -> void:
 var model: Node3D = building.get_node_or_null("RealisticModel")
 if model == null:
  return
 var box: AABB = model.get_meta("base_aabb")
 var footprint: Vector2 = model.get_meta("footprint")
 var height: float = float(building.get_meta("height", building.get_meta("base_height")))
 if box.size.x <= 0 or box.size.y <= 0 or box.size.z <= 0:
  return
 # These Quaternius models are authored with their detailed, window-heavy
 # facade facing their own local Z axis rather than X, so rotate to bring
 # that facade to face the road. Which way to rotate depends on which side
 # of the road the building sits on — a fixed rotation would make one
 # side's buildings face away from the road instead of toward it.
 var road_side: int = int(building.get_meta("road_side", -1))
 var angle: float = -road_side * PI * 0.5
 # Stretch width and depth independently so the model matches the lowpoly
 # hitbox's size and position exactly (distortion of angled details is
 # accepted as the trade-off).
 var scale := Vector3(footprint.y / box.size.x, height / box.size.y, footprint.x / box.size.z)
 var basis := Basis(Vector3.UP, angle) * Basis.from_scale(scale)
 model.transform.basis = basis
 var target_min := Vector3(-footprint.x * 0.5, 0, -footprint.y * 0.5)
 # Transform the whole AABB, not just its raw min corner: a 90-degree
 # rotation can turn that corner into the transformed box's max corner on
 # some axes, which silently shifted one road side's buildings relative to
 # their hitbox while the other side happened to line up by coincidence.
 var world_box: AABB = Transform3D(basis, Vector3.ZERO) * box
 model.position = target_min - world_box.position
 apply_uv_tiling(model, scale)

func set_graphics_style(style: String) -> void:
 if style == graphics_style:
  return
 graphics_style = style
 for chunk in chunks.values():
  for child in chunk.get_children():
   if child.get_meta("building", false):
    refresh_building_style(child)

func refresh_building_style(building: Node3D) -> void:
 var model: Node3D = building.get_node_or_null("RealisticModel")
 if graphics_style == "realistic":
  if model == null:
   var size: Vector3 = building.get_child(1).shape.size
   attach_realistic_building(building, size.x, size.z)
 else:
  building.get_child(0).visible = true
  if model != null:
   model.free()
 # Recomputes the flat-box windows' visibility (and rescales any realistic
 # model) for the style that's now active — keeps this one function as the
 # single source of truth instead of duplicating that logic here too.
 resize_building(building)

func obstacle(parent: Node3D, pos: Vector3, size: Vector3) -> Node3D:
 var hazard := box(parent, pos + Vector3(0, Rules.BUILDING_BONUS[high_level] * 0.8, 0), size, Color("ad5843"), true)
 hazard.set_meta("hazard", true)
 hazard.set_meta("hookable", true)
 hazard.set_meta("base_y", pos.y)
 attach_drone_visual(hazard, size)
 box(hazard, Vector3(0, size.y * 0.5 + 0.02, 0), Vector3(size.x, 0.12, size.z + 0.05), Color("ffbc78"), false, true)
 for i in range(3):
  box(parent, Vector3(pos.x, 0.04, pos.z + 40 - i * 8), Vector3(2.4 - i * 0.3, 0.03, 0.35), Color("e8a468"), false, true)
 return hazard

func attach_drone_visual(hazard: StaticBody3D, size: Vector3) -> void:
 # child(0) is the pink box mesh from box(), child(1) is its CollisionShape3D
 # — code elsewhere (city.gd's own range_limited_target) reads that
 # CollisionShape3D via get_child(1), so the box mesh is only hidden, never
 # freed/reordered, and the drone is appended after both instead of
 # replacing anything in place.
 hazard.get_child(0).visible = false
 var drone: Node3D = DRONE_MODEL.instantiate()
 hazard.add_child(drone)
 # Uniform scale fit to the smallest ratio on any axis, so the model never
 # pokes out past the obstacle's own collision box on any side.
 var fit_scale: float = minf(minf(size.x / DRONE_AABB_SIZE.x, size.y / DRONE_AABB_SIZE.y), size.z / DRONE_AABB_SIZE.z)
 drone.scale = Vector3.ONE * fit_scale
 var center: Vector3 = DRONE_AABB_POSITION + DRONE_AABB_SIZE * 0.5
 drone.position = -center * fit_scale
 # No rotation applied, and none varies per spawn: measured through the
 # model's own full correction-node chain, its face/eye/gun cluster already
 # sits on the +Z side at identity rotation, and this game's travel
 # direction is -Z — so "6 o'clock" (the direction opposite of travel) is
 # already +Z with zero extra rotation needed.

func manual_target(from: Vector3, ray_origin: Vector3, direction: Vector3, reach: float, exclude: RID) -> Dictionary:
 var query := PhysicsRayQueryParameters3D.create(ray_origin, ray_origin + direction.normalized() * 500.0, 1)
 query.exclude = [exclude]
 var hit: Dictionary = get_world_3d().direct_space_state.intersect_ray(query)
 if hit.is_empty():
  return {"valid": false, "reason": "AIM AT A SURFACE"}
 var target: Dictionary = validate_manual_point(from, hit.position, hit.normal, hit.collider, reach, exclude)
 if target.get("reason", "") == "OUT OF RANGE":
  return range_limited_target(from, hit.position, reach, exclude)
 return target

func range_limited_target(from: Vector3, desired: Vector3, reach: float, exclude: RID) -> Dictionary:
 # Project the cursor's distant surface onto reachable box faces. Keep real surfaces,
 # including building gaps and small aerial blocks, rather than making floating hooks.
 var aim: Vector3 = (desired - from).normalized()
 var limit_point: Vector3 = from + aim * reach
 var candidates: Array[Dictionary] = []
 for chunk in chunks.values():
  for surface in chunk.get_children():
   if not surface.get_meta("hookable", false):
    continue
   var collision: CollisionShape3D = surface.get_child(1)
   var half_size: Vector3 = collision.shape.size * 0.5
   var center: Vector3 = collision.global_position
   var bounds := AABB(center - half_size, half_size * 2)
   var nearest: Vector3 = from.clamp(bounds.position, bounds.end)
   if from.distance_to(nearest) > reach + 0.08:
    continue
   for axis in range(3):
    for side in [-1.0, 1.0]:
     var normal := Vector3.ZERO
     normal[axis] = side
     var low: Vector3 = bounds.position + normal * 0.08
     var high: Vector3 = bounds.end + normal * 0.08
     var face: float = center[axis] + side * (half_size[axis] + 0.08)
     low[axis] = face
     high[axis] = face
     low.y = maxf(low.y, 2.5)
     if low.y > high.y:
      continue
     var start: Vector3 = from.clamp(low, high)
     if from.distance_to(start) > reach:
      continue
     var end: Vector3 = desired.clamp(low, high)
     if from.distance_to(end) > reach:
      # The face rectangle is convex: bisection stays on this real surface.
      var inside: Vector3 = start
      var outside: Vector3 = end
      for i in range(24):
       var midpoint: Vector3 = (inside + outside) * 0.5
       if from.distance_to(midpoint) <= reach - 0.001:
        inside = midpoint
       else:
        outside = midpoint
      end = inside
     if (end - from).dot(aim) <= 0:
      continue
     candidates.append({"point": end, "normal": normal, "surface": surface, "score": end.distance_squared_to(limit_point)})
 candidates.sort_custom(func(a: Dictionary, b: Dictionary): return a.score < b.score)
 for candidate in candidates:
  var result: Dictionary = validate_manual_point(from, candidate.point - candidate.normal * 0.08, candidate.normal, candidate.surface, reach, exclude)
  if result.valid:
   result.adjusted = true
   result.reason = "RANGE ASSIST"
   return result
 return {"valid": false, "reason": "NO SURFACE IN RANGE"}

func wire_path_blocked(from: Vector3, to: Vector3, exclude: RID, attached_surface: Node3D = null) -> bool:
 var query := PhysicsRayQueryParameters3D.create(from, to, 1)
 var exclusions: Array[RID] = [exclude]
 # A hook on an aerial block may swing around that block. Only this attached
 # body is ignored for rope occlusion; character collisions and other blockers stay.
 if is_instance_valid(attached_surface) and attached_surface.get_meta("hazard", false):
  exclusions.append(attached_surface.get_rid())
 query.exclude = exclusions
 return not get_world_3d().direct_space_state.intersect_ray(query).is_empty()

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
