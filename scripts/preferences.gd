extends RefCounted
## Settings are stored separately from distance records.
const PATH: String = "user://settings.cfg"
var language: String = "ko"
var aim_mode: String = "auto"

func load_file(path: String = PATH) -> Error:
 var config := ConfigFile.new()
 var result: Error = config.load(path)
 if result != OK:
  return result
 var saved_language: String = str(config.get_value("interface", "language", "ko"))
 var saved_aim: String = str(config.get_value("controls", "aim_mode", "auto"))
 language = saved_language if saved_language in ["ko", "en"] else "ko"
 aim_mode = saved_aim if saved_aim in ["auto", "manual"] else "auto"
 return OK

func save_file(path: String = PATH) -> Error:
 var config := ConfigFile.new()
 config.set_value("interface", "language", language)
 config.set_value("controls", "aim_mode", aim_mode)
 return config.save(path)
