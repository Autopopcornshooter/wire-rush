extends RefCounted
## Old aim_mode/wire_mode/route settings are ignored.
const PATH: String = "user://settings.cfg"
const WINDOW_PRESETS: Array[Vector2i] = [Vector2i(1280, 720), Vector2i(1600, 900), Vector2i(1920, 1080)]
var language: String = "ko"
var window_size: Vector2i = Vector2i(1280, 720)
var fullscreen: bool = false
var sfx_volume: float = 1.0
var graphics_style: String = "lowpoly"
func load_file(path: String = PATH) -> Error:
 var config := ConfigFile.new()
 var result: Error = config.load(path)
 if result != OK:
  return result
 var saved: String = str(config.get_value("interface", "language", "ko"))
 language = saved if saved in ["ko", "en"] else "ko"
 var saved_size: Vector2i = config.get_value("display", "window_size", Vector2i(1280, 720))
 window_size = saved_size if WINDOW_PRESETS.has(saved_size) else Vector2i(1280, 720)
 fullscreen = bool(config.get_value("display", "fullscreen", false))
 sfx_volume = clampf(float(config.get_value("audio", "sfx_volume", 1.0)), 0.0, 1.0)
 var saved_style: String = str(config.get_value("display", "graphics_style", "lowpoly"))
 graphics_style = saved_style if saved_style in ["lowpoly", "realistic"] else "lowpoly"
 return OK
func save_file(path: String = PATH) -> Error:
 var config := ConfigFile.new()
 config.set_value("interface", "language", language)
 config.set_value("display", "window_size", window_size)
 config.set_value("display", "fullscreen", fullscreen)
 config.set_value("audio", "sfx_volume", sfx_volume)
 config.set_value("display", "graphics_style", graphics_style)
 return config.save(path)
