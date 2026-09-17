extends SceneTree
var game: Node3D
var checks: int = 0
var failures: int = 0
func _initialize() -> void:
 create_timer(30).timeout.connect(func(): quit(1))
 run.call_deferred()
func check(ok: bool, description: String) -> void:
 checks += 1
 if ok:
  print("PASS ", description)
 else:
  failures += 1
  push_error("FAIL " + description)
func first_building() -> Node3D:
 for chunk in game.city.chunks.values():
  for child in chunk.get_children():
   if child.get_meta("building", false):
    return child
 return null
func run() -> void:
 game = load("res://scenes/main.tscn").instantiate()
 root.add_child(game)
 game.set_process(false)
 game.set_physics_process(false)
 game.start_run(false)
 await physics_frame

 check(game.city.graphics_style == "lowpoly", "default graphics style is lowpoly")
 var building: Node3D = first_building()
 check(is_instance_valid(building), "a building exists to inspect")
 check(building.get_node_or_null("RealisticModel") == null, "lowpoly buildings have no realistic model attached")
 check(building.get_child(0).visible, "the flat box mesh is visible in lowpoly mode")
 var collision_size_before: Vector3 = building.get_child(1).shape.size

 game.set_graphics_style("realistic")
 check(game.city.graphics_style == "realistic", "toggling updates the live city graphics style")
 check(is_instance_valid(building.get_node_or_null("RealisticModel")), "switching to realistic attaches a model to an existing building")
 check(not building.get_child(0).visible, "the flat box mesh is hidden in realistic mode")
 check(not building.get_node("Windows").visible, "the flat-box window strips are also hidden in realistic mode")
 check(building.get_child(1).shape.size == collision_size_before, "collision geometry is unchanged by the visual swap, so hooking still works")
 var model: Node3D = building.get_node("RealisticModel")
 check(absf(model.scale.y * model.get_meta("base_aabb").size.y - float(building.get_meta("height"))) < 0.01, "the realistic model is scaled to match the building's current height")

 # Regression: the road-facing width must never overflow past the
 # collision box — that would let the visible model poke into the road the
 # player actually flies through, unlike overflowing depth-wise which just
 # leaves a harmless gap toward the next building.
 var box: AABB = model.get_meta("base_aabb")
 var world_box: AABB = Transform3D(model.basis, Vector3.ZERO) * box
 var collision_width: float = building.get_child(1).shape.size.x
 check(absf(world_box.size.x - collision_width) < 0.01, "the realistic model's road-facing width exactly matches the collision footprint, never overflowing into the road")

 # Regression: buildings on opposite sides of the road must rotate their
 # facade toward opposite horizontal directions — a single fixed rotation
 # makes one side face away from the road instead of toward it.
 var opposite_building: Node3D = null
 for chunk in game.city.chunks.values():
  for child in chunk.get_children():
   if child.get_meta("building", false) and int(child.get_meta("road_side", 0)) == -int(building.get_meta("road_side", 0)):
    opposite_building = child
    break
  if opposite_building != null:
   break
 check(is_instance_valid(opposite_building), "a building on the opposite side of the road exists to compare")
 if opposite_building != null:
  var opposite_model: Node3D = opposite_building.get_node("RealisticModel")
  var facing_a: Vector3 = model.basis * Vector3(0, 0, 1)
  var facing_b: Vector3 = opposite_model.basis * Vector3(0, 0, 1)
  check(facing_a.x * facing_b.x < 0, "buildings on opposite sides of the road face their facade toward opposite horizontal directions")

 # Regression: a chunk streamed in while ALREADY in realistic mode goes
 # through create_chunk()'s direct attach_realistic_building() call, not
 # the live-toggle refresh path — both must hide the flat box mesh.
 game.city.update_chunks(150.0)
 var fresh_building: Node3D = null
 for chunk in game.city.chunks.values():
  for child in chunk.get_children():
   if child.get_meta("building", false) and child != building and is_instance_valid(child.get_node_or_null("RealisticModel")):
    fresh_building = child
    break
  if fresh_building != null:
   break
 check(is_instance_valid(fresh_building), "a brand-new chunk streamed in while already in realistic mode has a building")
 check(fresh_building != null and not fresh_building.get_child(0).visible, "a building created fresh in realistic mode hides its flat box mesh too")
 check(fresh_building != null and not fresh_building.get_node("Windows").visible, "a building created fresh in realistic mode hides its window strips too")

 game.rider.upgrade("high")
 check(absf(model.scale.y * model.get_meta("base_aabb").size.y - float(building.get_meta("height"))) < 0.01, "a height upgrade rescales the realistic model to match the new height")
 check(building.get_child(1).shape.size.y == float(building.get_meta("height")), "the height upgrade still resizes the real collision shape")

 game.set_graphics_style("lowpoly")
 check(building.get_node_or_null("RealisticModel") == null, "switching back to lowpoly removes the realistic model")
 check(building.get_child(0).visible, "the flat box mesh reappears in lowpoly mode")
 check(building.get_node("Windows").visible, "the window strips reappear in lowpoly mode")

 print("GRAPHICS_STYLE_RESULT ", checks - failures, "/", checks, " passed; failures=", failures)
 game.free()
 await process_frame
 quit(0 if failures == 0 else 1)
