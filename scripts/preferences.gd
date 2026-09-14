extends RefCounted
## Old aim_mode/wire_mode/route settings are ignored.
const PATH: String = "user://settings.cfg"
var language: String = "ko"
func load_file(path: String = PATH) -> Error:
 var config := ConfigFile.new()
 var result: Error = config.load(path)
 if result != OK:
  return result
 var saved: String = str(config.get_value("interface", "language", "ko"))
 language = saved if saved in ["ko", "en"] else "ko"
 return OK
func save_file(path: String = PATH) -> Error:
 var config := ConfigFile.new()
 config.set_value("interface", "language", language)
 return config.save(path)
