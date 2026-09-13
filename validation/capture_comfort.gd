extends SceneTree
# Render-only fixtures: Godot --path . --script res://validation/capture_comfort.gd -- --test
# Generated PNGs stay in validation/ and are excluded from Git and Windows exports.
var game: Node3D
func _initialize() -> void:
 run.call_deferred()
func snapshot(name: String) -> void:
 game.camera.position = game.rider.position + Vector3(0, 2.2, 6)
 game._process(0.016)
 await process_frame
 await RenderingServer.frame_post_draw
 var result: Error = root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://validation/v030-" + name + ".png"))
 print(name, " capture=", result)
func run() -> void:
 game = load("res://scenes/main.tscn").instantiate()
 root.add_child(game)
 game.set_physics_process(false)
 game.set_process(false)
 game.demo = true
 game.start_run(true)
 await physics_frame
 game.rider.launch()
 for i in range(8):
  game.rider.simulate(1.0/60, 0)
  await physics_frame
 await snapshot("dash")
 game.start_run(true)
 game.rider.position = Vector3(0, 1, 0)
 game.rider.velocity = Vector3(0, -25, -14)
 for i in range(5):
  await physics_frame
  game.rider.simulate(1.0/60, 0)
 await snapshot("skate")
 game.start_run(false)
 game.rider.position = Vector3(0, 1, 0)
 game.rider.velocity = Vector3(0, -25, -14)
 for i in range(5):
  await physics_frame
  game.rider.simulate(1.0/60, 0)
 await snapshot("stopped")
 game.phase = "paused"
 game.resume()
 game.countdown = 0
 game.demo = false
 game._physics_process(1.0/60)
 await snapshot("shield")
 game.free()
 await process_frame
 quit()
