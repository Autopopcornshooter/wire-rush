extends SceneTree
var game: Node3D
func _initialize() -> void:
 run.call_deferred()
func snapshot(name: String) -> void:
 game.camera.position = game.rider.position + game.Rules.CAMERA_OFFSET
 game._process(0.016)
 game.update_targets()
 game.rider.draw_wire()
 await process_frame
 await RenderingServer.frame_post_draw
 print(name, " capture=", root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://validation/v060-" + name + ".png")))
func run() -> void:
 game = load("res://scenes/main.tscn").instantiate()
 root.add_child(game)
 game.set_process(false)
 game.set_physics_process(false)
 game.demo = true
 game.start_run(true)
 await physics_frame
 game.rider.launch()
 for i in range(5):
  await physics_frame
  game.rider.simulate(1.0 / 60, 0)
 await snapshot("twin-launch")
 for route in ["sparse", "barriers"]:
  game.preferences.route = route
  game.start_run(false)
  game.rider.position = Vector3(0, 15, -150 if route == "sparse" else -127)
  game.rider.velocity = Vector3(0, 0, -20)
  game.distance = -game.rider.position.z
  game.notice_left = 0
  await physics_frame
  await snapshot(route)
 game.free()
 await process_frame
 quit()
