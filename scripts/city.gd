extends Node3D
const Rules = preload("res://scripts/rules.gd")
const Locale = preload("res://scripts/localization.gd")
const DifficultyDirector = preload("res://scripts/difficulty_director.gd")
const LENGTH: float = 64.0
## Traversability Guard (PHASE B): the largest 3D distance any two
## consecutive wire-attachable points this generator places are allowed to
## end up, measured against the *base* (no Wire Length upgrade) wire reach
## (Rules.ROPE_RANGE = 30) with a safety margin — a route must never require
## an upgrade to be physically possible. Not a runtime rejection/backtrack
## system (this generator is simple enough that its placement formulas are
## themselves designed to respect this bound — see create_chunk()'s hazard
## vertical placement); tests/difficulty.gd verifies real generated geometry
## against it directly.
const MAX_BASE_TRAVERSAL_GAP: float = 26.0
## World-only marking for the early "can't die from a missed wire" stretch
## (see Rider.landing_safe()/SAFE_RELEASE_HEIGHT — the actual survival rule
## itself is untouched here; this is purely a visual cue). Evaluated once
## per chunk at creation time using that chunk's own starting distance, so
## it naturally stops appearing on chunks created once the run has already
## passed this distance — no separate "remove the marking" step needed.
const SAFE_ZONE_DISTANCE: float = 500.0
## Muted teal-cyan, dim enough to read as a subtle band rather than a bright
## beacon — matches the game's existing cyan accent (e.g. the lane-edge
## strips) rather than introducing a new color.
const SAFE_ZONE_COLOR := Color("3fa89c")
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
## Road traffic. Five different models purely for visual variety — none are
## wire targets (no "hookable"/"building" meta, and no code path ever adds
## them as a manual_target() candidate), and none carry gameplay damage
## differences by model or speed (see spawn_vehicle()/update_vehicles()).
const CAR_MODELS: Array[PackedScene] = [
 preload("res://models/car1.glb"),
 preload("res://models/car2.glb"),
 preload("res://models/car3.glb"),
 preload("res://models/car4.glb"),
 preload("res://models/car5.glb"),
]
## Per-model target overall length (meters), measured against each raw
## model's own AABB (see spawn_vehicle()) to derive a uniform scale — every
## model's raw proportions differ a lot (car4's raw AABB is ~20x smaller
## than car1's), so a single shared scale would leave some comically large
## and others tiny. Deliberately varied a little rather than identical, per
## "모든 차를 같은 크기로 만들 필요는 없다". Base targets were 4.6/4.2/5.0/
## 3.9/4.0; bumped 20% across the board (both the model and the
## BoxShape3D collision derived from it scale with this, since both come
## from the same uniform `scale` in spawn_vehicle()).
const CAR_TARGET_LENGTH: Array[float] = [5.52, 5.04, 6.0, 4.68, 4.8]
## Center of each lane, either side of the road's own center dashed line
## (x=0) — comfortably inside the road's real half-width (edge lines sit at
## x=±6.8) and clear of it so a car never visually crosses into the other
## lane.
const CAR_LANE_OFFSET: float = 3.4
## Deliberately slow — "차가 고속 장애물처럼 느껴지면 안 된다" — city-street
## crawl, not traffic the player needs to dodge like the aerial obstacles.
const CAR_SPEED: float = 4.0
## Background-only skyline (same Downtown City MegaKit models as the
## playable buildings, reused at a distance). Purely decorative: no
## collision, no wire targets, no gameplay metadata. Its ground sits below
## the road so it never visually touches the playable lane, but shallow
## enough that its taller buildings' rooftops climb back up into roughly
## the same height band as the playable buildings (up to ~65 with every
## height upgrade) — the two are meant to read as one continuous city seen
## at different distances, not two disconnected tiers. Horizontal distance
## alone (BACKGROUND_NEAR/MID/FAR_X below, well outside the playable
## buildings' ~7.4-15.4m band) is what actually keeps them from ever
## touching, not height.
const BACKGROUND_Y: float = -18.0
const BACKGROUND_TINT := Color(0.62, 0.68, 0.76)
## Buildings spread along each chunk's own depth per (side, distance-band) —
## was implicitly 1 (a single fixed spot per band); this many roughly
## multiplies total background building count by the same factor.
const BACKGROUND_SUBSLOTS: int = 4
## How far down the road/building/sidewalk visuals extend a plain dark
## "foundation" skirt so nothing appears to float over the empty gap above
## the background city. Deep enough that fog and distance hide the bottom
## edge rather than needing it to visually reach BACKGROUND_Y (-55) itself.
const FOUNDATION_DEPTH: float = 40.0
var bg_material_cache: Dictionary = {}
var _bg_ground_material: StandardMaterial3D
var chunks: Dictionary = {}
var pickups: Array[Node3D] = []
var vehicles: Array[Node3D] = []
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

## Real gameplay's only entry point into the Difficulty Director: `distance`
## here is Main.distance (origin-shift-independent total distance — see
## Rules.progress()), so tiers/events never reset after City.rebase(). This
## sets `high_level` for whichever chunks get created *by this same call*,
## exactly like a player picking the old Building Height upgrade used to —
## already-existing chunks read `high_level` once, at their own creation
## time, and are never touched again (see apply_height_level()).
## Deliberately NOT called from create_chunk() itself: tests construct
## specific world states by calling create_chunk() directly after manually
## setting high_level/practice/etc, and must keep doing exactly that without
## this automatic distance-driven overwrite getting in the way.
func update_chunks(distance: float, attached: Node3D = null, extra_anchors: Array[Node3D] = []) -> void:
 apply_height_level(DifficultyDirector.get_city_difficulty(distance).building_height_level)
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
   for i in range(vehicles.size() - 1, -1, -1):
    if chunk.is_ancestor_of(vehicles[i]):
     vehicles.remove_at(i)
   chunks.erase(key)
   chunk.free()

## Advances every live vehicle along its own lane; called from main.gd's
## _physics_process, gated the same way rider.simulate() already is (only
## while phase == "playing"), so traffic pauses exactly when the player
## does. Vehicles are plain children of their chunk, so origin-shift
## rebasing (city.rebase()) already carries them along for free, same as
## every other chunk-local decoration.
func update_vehicles(delta: float) -> void:
 for i in range(vehicles.size() - 1, -1, -1):
  var v: Node3D = vehicles[i]
  if not is_instance_valid(v):
   vehicles.remove_at(i)
   continue
  var travel: float = float(v.get_meta("dir")) * float(v.get_meta("speed")) * delta
  var distance: float = -v.global_position.z + origin_offset
  var next_distance: float = distance - travel
  var half_depth: float = v.get_child(1).shape.size.z * 0.5
  if DifficultyDirector.overlaps_rest_zone(minf(distance, next_distance) - half_depth, maxf(distance, next_distance) + half_depth):
   vehicles.remove_at(i)
   v.queue_free()
   continue
  v.position.z += travel

func create_chunk(index: int) -> void:
 var chunk := Node3D.new()
 chunk.name = "Block_%d" % index
 add_child(chunk)
 chunk.position.z = -index * LENGTH + origin_offset
 chunks[index] = chunk
 spawn_background_city(chunk, index)
 var kind: int = 0 if index < 2 or practice else (index - 2) % 5 + 1
 var road := box(chunk, Vector3(0, -0.5, -32), Vector3(14, 1, 64), Color("192b40"), true)
 road.set_meta("road", true)
 road.get_child(0).material_override = asphalt_material()
 # Visual-only support slab flush with the road's own collision underside
 # (y=-1), so a high or steep view over the road edge finds solid ground
 # fading into fog instead of the empty drop straight to the background
 # city. Road collision itself (on `road`, above) is untouched.
 var road_support := MeshInstance3D.new()
 var road_support_mesh := BoxMesh.new()
 road_support_mesh.size = Vector3(14, FOUNDATION_DEPTH, LENGTH)
 road_support.mesh = road_support_mesh
 road_support.material_override = material(Color("16222f"))
 road_support.position = Vector3(0, -1 - FOUNDATION_DEPTH * 0.5, -32)
 road_support.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
 chunk.add_child(road_support)
 for side in [-1, 1]:
  box(chunk, Vector3(side * 6.8, 0.035, -32), Vector3(0.1, 0.05, 64), Color("52d8cf"), false, true)
  # Sidewalk strip filling the real gap between the road's collision edge
  # (x=7) and the nearest building's collision edge (x=side*11.4-4=7.4), so
  # building and road read as connected ground rather than two separate
  # slabs with a sliver of empty space between them. It shares the same
  # downward foundation skirt as the road/building so its own underside
  # isn't a visible thin floating plate either.
  var sidewalk := MeshInstance3D.new()
  var sidewalk_mesh := BoxMesh.new()
  sidewalk_mesh.size = Vector3(0.4, FOUNDATION_DEPTH + 0.06, LENGTH)
  sidewalk.mesh = sidewalk_mesh
  sidewalk.material_override = material(Color("2c3a44"))
  sidewalk.position = Vector3(side * 7.2, 0.06 - (FOUNDATION_DEPTH + 0.06) * 0.5, -32)
  sidewalk.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
  chunk.add_child(sidewalk)
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
   attach_realistic_building(building, 8, 14)
   # Windows are local to the grounded building origin, so upgrades never move a hook.
   var windows := Node3D.new()
   windows.name = "Windows"
   building.add_child(windows)
   for floor_index in range(2, 23):
    var window := box(windows, Vector3(-side * 4.06, floor_index * 3, 0), Vector3(0.06, 0.7, 10), Color("39566e"))
    window.set_meta("floor_height", floor_index * 3)
   resize_building(building)
   if index * LENGTH < SAFE_ZONE_DISTANCE:
    add_safe_zone_marking(building, side)
   # Plain dark skirt extending down from the building's own base (y=0,
   # unaffected by height upgrades since those only grow the building
   # upward) so the building doesn't visually end in midair when seen from
   # above or from far down the road. Purely decorative: no collision, not
   # part of the hookable StaticBody3D's shape, and not touched by
   # resize_building/apply_height_level.
   var foundation := MeshInstance3D.new()
   var foundation_mesh := BoxMesh.new()
   foundation_mesh.size = Vector3(8, FOUNDATION_DEPTH, 14)
   foundation.mesh = foundation_mesh
   foundation.material_override = material(Color("1c2f45"))
   foundation.position = Vector3(0, -FOUNDATION_DEPTH * 0.5, 0)
   foundation.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
   building.add_child(foundation)
 for stripe in range(8):
  box(chunk, Vector3(0, 0.025, -stripe * 8 - 4), Vector3(0.08, 0.035, 3), Color("45627a"))
 var event: String = event_for_chunk(index)
 var rest_zone: bool = DifficultyDirector.is_rest_zone(index * LENGTH)
 # SKY GAP is a "no vehicles" event by definition (PHASE B spec section 13);
 # the Rest Area (PHASE C section 26: "차량 없음 또는 극소수") gets the same
 # treatment; TRAFFIC SURGE instead raises density on an otherwise-normal chunk.
 if not practice and not rest_zone and event != DifficultyDirector.EVENT_SKY_GAP:
  var gap_scale: float = DifficultyDirector.TRAFFIC_SURGE_VEHICLE_GAP_SCALE if event == DifficultyDirector.EVENT_TRAFFIC_SURGE else DifficultyDirector.get_city_difficulty(index * LENGTH).vehicle_gap_scale
  spawn_vehicles(chunk, index, gap_scale)
 if rest_zone:
  spawn_wasteland_gate_if_boundary(chunk, index)
 # The Rest Area also drops the ordinary aerial-hazard/police-drone spawn
 # entirely (PHASE C section 26: "일반 hazard 거의 없음... police drone 없음
 # 또는 극소수") — buildings/road stay exactly as normal City generation
 # would make them ("건물/도로 구조는 안전"), only the hazard loop below is skipped.
 if kind > 0 and not rest_zone:
  # Compact hazards spread sideways and vertically instead of a full-width
  # wall. Count and vertical spread both scale with the CURRENT high_level
  # (read once, here, at chunk-creation time — never touched again after
  # the chunk exists, which is what makes a later Building Height upgrade
  # next-chunk-only instead of retroactive): a taller high_level means more
  # usable vertical space, so more obstacles are spread across the *entire*
  # low-to-high range rather than the same fixed 4 positions just sliding
  # upward as one block (that used to leave the lower band empty).
  var hazard_count: int = 4 + high_level + DifficultyDirector.get_city_difficulty(index * LENGTH).aerial_obstacle_count_bonus
  var min_hazard_y: float = 6.0
  var max_hazard_y: float = 24.0 + Rules.BUILDING_BONUS[high_level] * 0.85
  # Same 3-obstacle Z span (42m) regardless of count, so more obstacles
  # just pack the existing depth tighter instead of spilling past this
  # chunk's own 64m into the next one's hazard band.
  var z_step: float = 42.0 / maxf(1.0, float(hazard_count - 1))
  # Traversability Guard (PHASE B): a symmetric triangle wave (rise from min
  # up to max at the middle hazard, then back down to min at the last one)
  # instead of a wrapping ramp. Two properties matter here:
  #  1. It never wraps, so the largest possible step between two
  #     CONSECUTIVE hazards *within* one chunk is bounded
  #     ((max_hazard_y - min_hazard_y) / half_span) — the pre-PHASE-B
  #     wrapping fposmod ramp instead inevitably completed a full cycle
  #     somewhere across i=0..hazard_count-1, landing two consecutive
  #     hazards at opposite ends of the full min/max range right where it
  #     wrapped (up to ~44m at the highest Building Height tier).
  #  2. It always starts AND ends at min_hazard_y (t=0 at i=0 and at
  #     i=hazard_count-1), so the hazard-to-hazard gap *across* a chunk
  #     boundary is also bounded regardless of what the next chunk's own
  #     hazard_count/high_level happen to be — both boundary hazards sit at
  #     the same low band instead of two independently-phased chunks
  #     potentially landing at opposite height extremes right at the seam.
  # Combined with the fixed 42m z-span (so the gap between a chunk's last
  # hazard and the next chunk's first is always LENGTH-42=22m in Z) and the
  # +-3.7/0 lateral spread, every consecutive pair — inside a chunk or across
  # one — stays comfortably inside MAX_BASE_TRAVERSAL_GAP (see
  # tests/difficulty.gd for the real-geometry check across a full Sky Gap
  # span). `kind` no longer shifts the peak position (that would let the
  # peak land close to an edge, steepening the slope right where two chunks
  # meet) — chunks still read as varied via the independent X cycling below.
  var half_span: float = maxf(1.0, float(hazard_count - 1) * 0.5)
  for i in range(hazard_count):
   var hazard_distance: float = index * LENGTH + 10 + i * z_step
   if DifficultyDirector.overlaps_rest_zone(hazard_distance - 0.7, hazard_distance + 0.7):
    continue
   var x: float = [-3.7, 0.0, 3.7][posmod(index + i, 3)]
   var t: float = 1.0 - absf(float(i) - half_span) / half_span
   var y: float = lerpf(min_hazard_y, max_hazard_y, t)
   obstacle(chunk, Vector3(x, y, -10 - i * z_step), Vector3(2.6, 2.2, 1.4))

func background_ground_material() -> StandardMaterial3D:
 if _bg_ground_material == null:
  var mat := StandardMaterial3D.new()
  mat.albedo_texture = ASPHALT_TEXTURE
  mat.albedo_color = Color(0.5, 0.53, 0.58)
  mat.roughness = 1.0
  mat.metallic_specular = 0.1
  mat.uv1_scale = Vector3(260.0 / 8.0, LENGTH / 8.0, 1)
  _bg_ground_material = mat
 return _bg_ground_material

func background_material_for(source: StandardMaterial3D) -> StandardMaterial3D:
 if bg_material_cache.has(source):
  return bg_material_cache[source]
 var tinted: StandardMaterial3D = source.duplicate()
 tinted.vertex_color_use_as_albedo = false
 tinted.metallic_specular = 0.1
 tinted.albedo_color = tinted.albedo_color * BACKGROUND_TINT
 bg_material_cache[source] = tinted
 return tinted

func style_background_model(node: Node) -> void:
 if node is GeometryInstance3D:
  node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
 if node is MeshInstance3D and node.mesh != null:
  for i in range(node.mesh.get_surface_count()):
   var mat: Material = node.mesh.surface_get_material(i)
   if mat is StandardMaterial3D:
    node.set_surface_override_material(i, background_material_for(mat))
 for child in node.get_children():
  style_background_model(child)

## Low-cost, background-only skyline reusing the same three Downtown City
## MegaKit models as the playable buildings, sitting far below the road
## (BACKGROUND_Y) purely for the "the map is above a real city" silhouette
## seen when looking down. No StaticBody3D/CollisionShape3D is created for
## any of it, so none of it is hookable, an obstacle, or a wire target, and
## it never needs cleanup beyond the normal chunk lifecycle it's parented to
## (streamed and freed, and rebased on origin shifts, exactly like the rest
## of the chunk's children).
func spawn_background_city(chunk: Node3D, index: int) -> void:
 var ground := MeshInstance3D.new()
 var plane := BoxMesh.new()
 plane.size = Vector3(260, 1, LENGTH)
 ground.mesh = plane
 ground.position = Vector3(0, BACKGROUND_Y - 0.5, -32)
 ground.material_override = background_ground_material()
 ground.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
 chunk.add_child(ground)
 # A wide boulevard down the middle, plus an occasional cross street, so the
 # ground reads as a city grid rather than a flat slab from above.
 var road := MeshInstance3D.new()
 var road_mesh := BoxMesh.new()
 road_mesh.size = Vector3(22, 0.06, LENGTH)
 road.mesh = road_mesh
 road.position = Vector3(0, BACKGROUND_Y + 0.03, -32)
 road.material_override = background_material_for(material(Color(0.4, 0.43, 0.48)))
 road.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
 chunk.add_child(road)
 if index % 2 == 0:
  var cross := MeshInstance3D.new()
  var cross_mesh := BoxMesh.new()
  cross_mesh.size = Vector3(240, 0.06, 18)
  cross.mesh = cross_mesh
  cross.position = Vector3(0, BACKGROUND_Y + 0.031, -32)
  cross.material_override = road.material_override
  cross.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
  chunk.add_child(cross)
 # Rooftops reach from just above the background ground up into roughly the
 # same band as playable buildings (23-65m with every height upgrade), so
 # the skyline reads as continuous depth rather than a separate low tier.
 var heights: Array[float] = [28.0, 38.0, 50.0, 62.0]
 # Three depth bands (horizontal distance from the road), each now with
 # BACKGROUND_SUBSLOTS buildings spread along the chunk's own 64m depth
 # instead of just one — ~4x the previous building count per chunk, for a
 # skyline that reads as continuous rather than sparse when seen from a
 # high swing.
 var band_distances: Array[float] = [45.0, 78.0, 115.0]
 for side in [-1, 1]:
  for band in range(band_distances.size()):
   for sub in range(BACKGROUND_SUBSLOTS):
    var block: int = index * 31 + side * 13 + band * 7 + sub
    # Only the farthest band thins out at all, and only lightly — every
    # nearer band always spawns so the skyline never looks empty.
    if band == band_distances.size() - 1 and posmod(block, 4) == 0:
     continue
    var distance: float = band_distances[band]
    var model_index: int = posmod(block, BUILDING_MODELS.size())
    var height: float = heights[posmod(block * 3 + band, heights.size())]
    var width: float = 8.0 + posmod(block, 3) * 1.5
    var depth: float = 8.0 + posmod(block + 1, 3) * 1.5
    var model: Node3D = BUILDING_MODELS[model_index].instantiate()
    chunk.add_child(model)
    var box: AABB = model_aabb(model)
    if box.size.x <= 0 or box.size.y <= 0 or box.size.z <= 0:
     model.free()
     continue
    var scale := Vector3(width / box.size.x, height / box.size.y, depth / box.size.z)
    var yaw: float = posmod(block, 4) * PI * 0.5
    var basis := Basis(Vector3.UP, yaw) * Basis.from_scale(scale)
    model.transform.basis = basis
    # A little lateral jitter on top of the band's own base distance, and
    # subslots spread evenly across the chunk's depth (with jitter too),
    # so the buildings read as an irregular city block rather than a grid.
    var x: float = side * (distance + float(posmod(block, 5) - 2) * 3.0)
    var z: float = -4.0 - float(sub) * (LENGTH / float(BACKGROUND_SUBSLOTS)) - float(posmod(block, 7)) * 1.5
    var world_box: AABB = Transform3D(basis, Vector3.ZERO) * box
    var target_min := Vector3(x - width * 0.5, BACKGROUND_Y, z - depth * 0.5)
    model.position = target_min - world_box.position
    style_background_model(model)

## Two thin emissive bands low on the road-facing wall (same wall the window
## strips sit on), reading as a repeated "safe zone" marking without a
## bright glow or any screen-space UI. Purely decorative: no collision, no
## metadata, not part of the hookable StaticBody3D's own shape.
func add_safe_zone_marking(building: Node3D, side: int) -> void:
 for h in [2.4, 5.2]:
  var band := box(building, Vector3(-side * 4.1, h, 0), Vector3(0.08, 0.28, 13), SAFE_ZONE_COLOR, false, true)
  band.get_child(0).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

## PHASE C spec section 36: "Wasteland Entry Placeholder" — a purely
## decorative Graybox boundary marker (two pillars + a glowing lintel
## spanning the road) at the exact chunk where the Rest Area ends and
## CITY_COMPLETE begins. No collision, no gameplay effect, no actual
## Wasteland content — it exists once, deterministically, at
## floori(rest_area_end_distance() / LENGTH), and is cleaned up by the
## ordinary chunk-streaming lifecycle exactly like everything else in a chunk.
func spawn_wasteland_gate_if_boundary(chunk: Node3D, index: int) -> void:
 if index != floori(DifficultyDirector.rest_area_end_distance() / LENGTH):
  return
 var gate_color := Color("7a5a3f")
 for side in [-1, 1]:
  box(chunk, Vector3(side * 7.0, 9.0, -32.0), Vector3(1.2, 18.0, 1.2), gate_color)
 box(chunk, Vector3(0, 17.5, -32.0), Vector3(15.2, 1.0, 1.2), Color("d98a3d"), false, true)

func start_height() -> float:
 var roof: float = 100
 for child in chunks[0].get_children():
  if child.get_meta("building", false) and is_equal_approx(child.position.z, -8):
   roof = minf(roof, child.get_meta("height"))
 return roof + 1.0

func has_building(index: int, slot: int, side: int) -> bool:
 if practice or index < 2:
  return true
 if event_for_chunk(index) == DifficultyDirector.EVENT_SKY_GAP:
  return false
 # 128m alternating sections; the first 16m has both walls as a transition.
 var section: int = floori(float(index - 2) / 2)
 if index % 2 == 0 and slot == 0:
  return true
 return side == (1 if section % 2 == 0 else -1)

## Which City Event (SKY_GAP/TRAFFIC_SURGE/NONE — see difficulty_director.gd)
## this chunk belongs to, purely as a function of its own index. A SKY GAP
## chunk drops both playable building walls entirely here (obstacle/hazard
## spawning is already independent of has_building(), so those keep
## appearing normally — this alone is what turns it into an "obstacle-only
## swinging" section) and skips vehicle spawning (see create_chunk()). Not
## permanent: only a short recurring span of chunks is ever an event, so the
## ordinary building-lined/normal-traffic layout keeps returning between them.
func event_for_chunk(index: int) -> String:
 return DifficultyDirector.event_for_chunk(index)

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
 windows.visible = false
 update_realistic_scale(building)

## Deliberately NOT retroactive: only updates `high_level` itself, which
## every already-loaded chunk's buildings/obstacles already baked their own
## snapshot of at creation time (resize_building()/obstacle spawn both read
## `high_level` once, when the chunk is built). Existing chunks are
## therefore untouched by an upgrade pick — only chunks created from this
## point on (create_chunk(), streamed in ahead of the player) see the new
## height and the taller obstacle spread that goes with it.
func apply_height_level(level: int) -> void:
 high_level = clampi(level, 0, 3)

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

## Two lanes, right-hand traffic: the lane matching the player's own travel
## direction (-Z) sits on the +X side (a driver facing -Z has +X on their
## right), oncoming traffic (+Z) sits on -X — real-world "drive on the
## right, oncoming on your left" laid out along this game's own -Z-forward
## convention. Density is deliberately uneven (clusters of cars close
## together, punctuated by an occasional larger gap) rather than an evenly
## spaced conveyor belt. `gap_scale` is City Progression's own knob on this
## same shape (see DifficultyDirector.get_city_difficulty()/
## TRAFFIC_SURGE_VEHICLE_GAP_SCALE): lower means denser traffic, but the
## occasional no-traffic stretch below always still happens regardless of
## scale, so a surge is never "the whole road is cars".
func spawn_vehicles(chunk: Node3D, index: int, gap_scale: float) -> void:
 for side in [-1, 1]:
  var dir_sign: float = -1.0 if side > 0 else 1.0
  var lane_x: float = side * CAR_LANE_OFFSET
  var z: float = -2.0
  var slot: int = 0
  while z > -LENGTH + 2.0 and slot < 12:
   var seed: int = index * 17 + side * 5 + slot * 3
   if posmod(seed, 9) < 2:
    # An occasional 10-20m stretch with no traffic at all, instead of an
    # unbroken line of cars.
    z -= lerpf(10.0, 20.0, float(posmod(seed, 5)) / 4.0)
    slot += 1
    continue
   var model_index: int = posmod(seed, CAR_MODELS.size())
   spawn_vehicle(chunk, model_index, Vector3(lane_x, 0, z), dir_sign)
   # Gap to the next car in this same lane: always enough to keep them from
   # spawning inside one another, and scaled by gap_scale (overall traffic
   # density) on top of the base 2-5m variation, so cars can still end up
   # close together in a loose cluster rather than uniformly spaced, just
   # with fewer/more clusters depending on the current City tier or event.
   var gap: float = (2.0 + float(posmod(seed, 4)) * 1.0) * gap_scale
   z -= CAR_TARGET_LENGTH[model_index] + gap
   slot += 1

## Builds one car: a low-cost kinematic AnimatableBody3D (no engine/
## suspension simulation — see update_vehicles(), which just advances
## position.z at a constant speed) with a BoxShape3D collision sized from
## the model's own measured AABB, scaled to CAR_TARGET_LENGTH. Never given
## "hookable"/"building" meta, so it's never a wire-attach candidate —
## manual_target()/range_limited_target() only ever consider surfaces
## carrying those tags.
func spawn_vehicle(chunk: Node3D, model_index: int, pos: Vector3, dir_sign: float) -> Node3D:
 var distance: float = -chunk.to_global(pos).z + origin_offset
 var half_depth: float = CAR_TARGET_LENGTH[model_index] * 0.5
 if DifficultyDirector.overlaps_rest_zone(distance - half_depth, distance + half_depth):
  return null
 var model: Node3D = CAR_MODELS[model_index].instantiate()
 var raw_box: AABB = model_aabb(model)
 if raw_box.size.x <= 0 or raw_box.size.y <= 0 or raw_box.size.z <= 0:
  model.free()
  return null
 var scale: float = CAR_TARGET_LENGTH[model_index] / raw_box.size.z
 var body := AnimatableBody3D.new()
 # This project moves vehicles with a plain per-frame position write (see
 # update_vehicles()), not physics-server-driven interpolation, so
 # sync_to_physics (which otherwise pulls the node's transform FROM the
 # physics server rather than the other way around, and was silently
 # discarding the position set immediately below) is off.
 body.sync_to_physics = false
 chunk.add_child(body)
 body.position = pos
 body.set_meta("vehicle", true)
 body.set_meta("dir", dir_sign)
 body.set_meta("speed", CAR_SPEED)
 # Faces its own direction of travel: models are authored nose-along-Z (raw
 # AABB's longest axis is always Z across all 5). The first pass assumed
 # nose-at-+Z (matching this project's other Sketchfab models) and yawed
 # 0/PI accordingly; confirmed in actual play to be backwards, so this is
 # flipped — nose is at -Z for these five models.
 var yaw: float = PI if dir_sign < 0 else 0.0
 var basis := Basis(Vector3.UP, yaw) * Basis.from_scale(Vector3.ONE * scale)
 model.transform.basis = basis
 var world_box: AABB = Transform3D(basis, Vector3.ZERO) * raw_box
 var target_min := Vector3(-world_box.size.x * 0.5, 0, -world_box.size.z * 0.5)
 model.position = target_min - world_box.position
 body.add_child(model)
 var collision := CollisionShape3D.new()
 var shape := BoxShape3D.new()
 shape.size = raw_box.size * scale
 collision.shape = shape
 collision.position = Vector3(0, shape.size.y * 0.5, 0)
 body.add_child(collision)
 vehicles.append(body)
 return body

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
 # The flat box mesh (child 0) stays as the real collision anchor for the
 # building's StaticBody3D, but it's never the visible surface now that the
 # realistic model is the only rendering style.
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

## `pos.y` is used exactly as given — height-awareness (if any) is now the
## caller's job (see create_chunk()'s hazard loop), not implicit here, so
## the same call always places a hazard at the same spot regardless of the
## current high_level (this is what several tests rely on when they place a
## hazard directly at a specific Y).
func obstacle(parent: Node3D, pos: Vector3, size: Vector3) -> Node3D:
 var hazard := box(parent, pos, size, Color("ad5843"), true)
 hazard.set_meta("hazard", true)
 hazard.set_meta("hookable", true)
 attach_drone_visual(hazard, size)
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
 # Uniform scale fit to the hazard box's *width* (X) ratio, with a 0.9
 # margin — not the tightest axis (Z, depth), which is what an earlier fix
 # used and was still reported as looking too small. The measured AABBs
 # (DRONE_AABB_SIZE vs this fixed 2.6x2.2x1.4 hazard box) don't share the
 # same proportions — the drone is naturally taller and deeper, relative to
 # its own width, than the box is — so no uniform scale can fill all three
 # axes at once; one of them has to give. Width is the axis players actually
 # judge "is this thing big" by (it's what's visible left-to-right as they
 # approach), so it's the one fit tightly to the box (to ~90%, inside the
 # requested 85-95% band); height/depth are left to overflow the invisible
 # collision box a bit past its edges instead, which reads as "a big drone"
 # rather than "a drone floating in a too-large hitbox".
 var fit_scale: float = (size.x / DRONE_AABB_SIZE.x) * 0.9
 drone.scale = Vector3.ONE * fit_scale
 var center: Vector3 = DRONE_AABB_POSITION + DRONE_AABB_SIZE * 0.5
 drone.position = -center * fit_scale
 # No rotation applied, and none varies per spawn: measured through the
 # model's own full correction-node chain, its face/eye/gun cluster already
 # sits on the +Z side at identity rotation, and this game's travel
 # direction is -Z — so "6 o'clock" (the direction opposite of travel) is
 # already +Z with zero extra rotation needed.

## `slack` widens only the RANGE ASSIST fallback's reach tolerance below —
## it never changes the strict `reach` check in validate_manual_point, and
## defaults to the original 0.08m so every existing caller (tests, capture
## scripts) is unaffected. Rules.UPGRADES.attach_assist is the only thing
## that passes a larger value, via Rider.aim_slack().
func manual_target(from: Vector3, ray_origin: Vector3, direction: Vector3, reach: float, exclude: RID, slack: float = 0.08) -> Dictionary:
 var query := PhysicsRayQueryParameters3D.create(ray_origin, ray_origin + direction.normalized() * 500.0, 1)
 query.exclude = [exclude]
 var hit: Dictionary = get_world_3d().direct_space_state.intersect_ray(query)
 if hit.is_empty():
  return {"valid": false, "reason": "AIM AT A SURFACE"}
 var target: Dictionary = validate_manual_point(from, hit.position, hit.normal, hit.collider, reach, exclude)
 if target.get("reason", "") == "OUT OF RANGE":
  return range_limited_target(from, hit.position, reach, exclude, slack)
 return target

func range_limited_target(from: Vector3, desired: Vector3, reach: float, exclude: RID, slack: float = 0.08) -> Dictionary:
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
   if from.distance_to(nearest) > reach + slack:
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
