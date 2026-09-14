extends RefCounted
const GRAVITY: float = 20.0
const JUMP_SPEED: float = 10.95
const MAX_SPEED: float = 35.0
const HOOK_SPEED: float = 80.0
const ROPE_RANGE: float = 30.0
const REEL_SPEED: float = 5.0
const SAFE_RELEASE_HEIGHT: float = 5.0
const LAUNCH_SPEEDS: Array[float] = [28.0, 30.0, 32.0, 35.0]
const LAUNCH_SECONDS: float = 0.65
const LAUNCH_COOLDOWN: float = 10.0
const ROUTES: Dictionary = {"standard": "STANDARD", "sparse": "SPARSE BUILDINGS", "barriers": "VERTICAL BARRIERS"}
const STOP_SPEED: float = 0.15
const SKATE_FRICTION: Array[float] = [0.9, 0.35, 0.22, 0.12]
const BUILDING_BONUS: Array[float] = [0.0, 10.0, 20.0, 30.0]
const RESUME_PROTECTION: float = 2.0
const CAMERA_OFFSET := Vector3(0, 4.5, 12.0)
const UPGRADES: Dictionary = {
 "skates": ["ROLLER SKATES", "Lower ground friction each tier: 0.35 / 0.22 / 0.12. Release at player height 5m or below to slide."],
 "launcher": ["TWIN LAUNCH", "E: dash toward two forward wall anchors. Speed upgrade; no invulnerability. 10s cooldown."],
 "armor": ["IMPACT ARMOR", "Absorb an obstacle collision. Cannot save a landing after release above 5m."],
 "high": ["TALLER BUILDINGS", "Raise buildings by 10 / 20 / 30m. Aerial obstacles also rise."],
 "range": ["LONGER WIRE", "+10% wire reach. Connect to a more distant point."],
 "reel": ["FAST REEL", "+15% automatic reel speed while holding the mouse button."],
 "hook": ["FAST HOOK", "+20% hook speed. Recover sooner after firing."],
 "jump": ["HIGH JUMP", "+10% jump height. Unhooked jumps are safe to land."],
}
static func xp_required(level: int) -> int:
 return roundi(180.0 * pow(1.25, mini(level - 1, 8)))
static func progress(previous: float, position_z: float, origin_offset: float) -> float:
 return maxf(previous, -position_z + origin_offset)
