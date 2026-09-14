extends RefCounted
## Old aim_mode/wire_mode settings are ignored; E is a separate burst ability.
const PATH: String = "user://settings.cfg"
var route: String = "standard"
var language: String = "ko"
func load_file(path: String = PATH) -> Error:
 var config := ConfigFile.new()
 var result: Error = config.load(path)
 if result != OK:
  return result
 var saved: String = str(config.get_value("interface", "language", "ko"))
 language = saved if saved in ["ko", "en"] else "ko"
 var saved_route: String = str(config.get_value("experiment", "route", "standard"))
 route = saved_route if saved_route in ["standard", "sparse", "barriers"] else "standard"
 return OK
func save_file(path: String = PATH) -> Error:
 var config := ConfigFile.new()
 config.set_value("interface", "language", language)
 config.set_value("experiment", "route", route)
 return config.save(path)
