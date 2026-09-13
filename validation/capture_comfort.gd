extends SceneTree
# Render fixtures: Godot --path . --script res://validation/capture_comfort.gd -- --test
var game: Node3D
func _initialize() -> void:
 run.call_deferred()
func snapshot(name: String) -> void:
 game.camera.position = game.rider.position + game.Rules.CAMERA_OFFSET
 game._process(0.016)
 if is_instance_valid(game.rider.anchor):
  game.aim_screen = game.camera.unproject_position(game.rider.anchor.global_position)
 game.update_targets()
 await process_frame
 await RenderingServer.frame_post_draw
 var result: Error = root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://validation/v050-" + name + ".png"))
 print(name, " capture=", result)
func frames(count: int) -> void:
 for i in range(count):
  await physics_frame
  game.rider.simulate(1.0 / 60, 0)
func run() -> void:
 game = load("res://scenes/main.tscn").instantiate()
 root.add_child(game)
 game.set_physics_process(false)
 game.set_process(false)
 game.demo = true
 for tier in [0, 3]:
  game.start_run(false)
  for i in range(tier):
   game.rider.upgrade("high")
  game.rider.position = Vector3(0, 10 + tier * 8, -122)
  game.rider.velocity = Vector3(0, 0, -10)
  await physics_frame
  var hazard: Node3D = game.city.chunks[2].get_children().filter(func(n: Node): return n.get_meta("hazard", false))[0]
  var aim: Vector3 = hazard.global_position + Vector3(0, 0, 0.7)
  var selection: Dictionary = game.city.manual_target(game.rider.position, game.rider.position, (aim - game.rider.position).normalized(), 30, game.rider.get_rid())
  print("aerial fixture hook ", selection.get("valid", false))
  game.rider.fire_manual(selection, -1)
  await frames(16)
  game.aim_screen = game.camera.unproject_position(aim)
  await snapshot("aerial" if tier == 0 else "tall")
 for height in [4.0, 8.0]:
  game.start_run(false)
  game.rider.upgrade("skates")
  await physics_frame
  var point := Vector3(-7.4, height, -8)
  var selection: Dictionary = game.city.manual_target(game.rider.position, game.rider.position, (point - game.rider.position).normalized(), 30, game.rider.get_rid())
  game.rider.fire_manual(selection, -1)
  await frames(20)
  game.rider.release_wire()
  game.rider.position = Vector3(0, 0.9, -4)
  game.rider.velocity = Vector3(0, -20, -14)
  await frames(3)
  await snapshot("friction" if height == 4 else "fatal")
 game.free()
 await process_frame
 quit()
