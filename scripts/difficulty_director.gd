extends RefCounted
## World Progression only — distance-based City difficulty. Kept fully
## independent of Player Progression (XP/Level/Normal & Core Upgrades/
## Synergy — see rules.gd/rider.gd/main.gd, none of which this file reads or
## writes). City.gd is the only caller.
##
## Every function here is a pure function of a distance or a chunk index:
## no persistent director state, no per-frame randomness. The same input
## always produces the same output, so a chunk's own difficulty/event is
## fixed forever the moment that chunk is first created — the same
## "new chunk only, existing chunk never changes" rule PHASE A already
## established for City.high_level/City.apply_height_level() applies here
## too (see City.update_chunks(), which reads get_city_difficulty() once per
## call using the player's current *total* distance, and City.create_chunk(),
## which reads event_for_chunk() once per chunk using that chunk's own start
## distance).
##
## `distance` must always be the game's own origin-shift-independent total
## logical distance (Main.distance, derived from Rules.progress()), never a
## chunk's local/rebased Z position — otherwise a floating-origin rebase
## (City.rebase()) would incorrectly reset tiers/events back toward 0.

## Duplicated from City.LENGTH (rather than preloading city.gd here) to
## avoid a City <-> DifficultyDirector circular preload; both must stay in
## sync if the chunk length ever changes.
const LENGTH: float = 64.0

## Chapter = CITY, Loop = 1 is the only combination PHASE B actually uses.
## `chapter`/`loop` are accepted as parameters (not stored, not branched on
## beyond this constant list) purely so a future revision can widen
## progression across chapters/loops without changing every call site —
## PHASE B does not implement any other chapter or loop.
const SUPPORTED_CHAPTERS: Array[String] = ["CITY"]

## Distance a CITY tier begins at. Tier N is [TIER_DISTANCES[N], TIER_DISTANCES[N+1]).
const TIER_DISTANCES: Array[float] = [0.0, 500.0, 1000.0, 2000.0]

static func tier_for_distance(distance: float) -> int:
 var tier: int = 0
 for i in range(TIER_DISTANCES.size()):
  if distance >= TIER_DISTANCES[i]:
   tier = i
 return tier

## World Difficulty Profile for a given total distance. Building Height maps
## 1:1 onto the CITY tier (0/1/2/3, matching Rules.BUILDING_BONUS's own four
## entries and the "0 -> 1 -> 2 -> 3" progression PHASE B calls for) — Tier 0
## keeps it at the original baseline (0), each later tier raises it by one.
## The other fields are independent knobs layered on top of that, each
## starting from PHASE A's existing values and increasing gently rather than
## doubling per tier (see City.create_chunk()/spawn_vehicles()).
static func get_city_difficulty(distance: float, chapter: String = "CITY", loop: int = 1) -> Dictionary:
 var tier: int = tier_for_distance(distance)
 return {
  "tier": tier,
  "building_height_level": tier,
  ## Added on top of City's existing "4 + high_level" aerial hazard count —
  ## 0 through TIER 1 (unchanged from the pre-PHASE-B baseline), rising
  ## through TIER 2/3 ("vertical obstacle distribution 확대").
  "aerial_obstacle_count_bonus": [0, 0, 1, 2][tier],
  ## Multiplies the base per-car gap in City.spawn_vehicles(): higher =
  ## sparser traffic. TIER 0 is sparser than the historical default (5.0,
  ## now TIER 1's value); TIER 2/3 gradually denser.
  "vehicle_gap_scale": [7.0, 5.0, 4.0, 3.0][tier],
  "sky_gap_eligible": distance >= SKY_GAP_MIN_DISTANCE,
  "traffic_surge_eligible": tier >= 1,
 }

# ---------------------------------------------------------------------
# City Events (SKY_GAP, TRAFFIC_SURGE). Enum-like string ids are used
# (matching this codebase's existing convention of plain String state, e.g.
# Rider.mode/Main.phase/Main.pending_upgrades) rather than a new enum type.
# Real future candidates (High Rise, Broken City, XP Rush, Fog Zone) can be
# added as new ids/branches here later without touching City.gd's call
# sites, which only ever compare against the string a chunk's event_for_chunk()
# returns.
# ---------------------------------------------------------------------
const EVENT_NONE: String = "NONE"
const EVENT_SKY_GAP: String = "SKY_GAP"
const EVENT_TRAFFIC_SURGE: String = "TRAFFIC_SURGE"

## SKY GAP: promoted from PHASE A's "no-building special section" — same
## distance gate and period/length numbers, now expressed as a City Event.
const SKY_GAP_MIN_DISTANCE: float = 2000.0
const SKY_GAP_LENGTH_CHUNKS: int = 3
const SKY_GAP_PERIOD_CHUNKS: int = 10

## TRAFFIC SURGE: a whole PERIOD-chunk window is either "surge" or "normal" —
## never flickers chunk-to-chunk mid-window — decided once per window by a
## deterministic hash (this codebase's usual posmod-based pseudo-randomness,
## e.g. City.spawn_vehicles()'s own gap rolls), not a runtime RNG, so the
## same window index always resolves the same way regardless of call order.
## Whichever windows DO roll a surge already guarantee at least one full
## non-surge period before the next window is even evaluated, which is this
## event's whole cooldown — no separate cooldown counter is needed.
const TRAFFIC_SURGE_LENGTH_CHUNKS: int = 3
const TRAFFIC_SURGE_PERIOD_CHUNKS: int = 9
## Trigger chance per window, out of 12, indexed by tier: impossible below
## TIER 1 ("약한 event 가능" starts at TIER 1), rising through TIER 2/3.
const TRAFFIC_SURGE_CHANCE_BY_TIER: Array[int] = [0, 2, 5, 8]
## Denser than any tier's normal vehicle_gap_scale — "차가 많다", not "도로를
## 막는다": still leaves City.spawn_vehicles()'s own occasional 10-20m empty
## stretch untouched.
const TRAFFIC_SURGE_VEHICLE_GAP_SCALE: float = 2.0

## Which City Event (if any) a chunk belongs to, purely as a function of its
## own index — City.create_chunk()/City.has_building()/City.spawn_vehicles()
## all read this once per chunk. SKY_GAP is checked first: a chunk can never
## be both (SKY_GAP removes buildings but not traffic on its own; sky-gap
## chunks simply never spawn vehicles at all — see City.create_chunk()).
static func event_for_chunk(index: int) -> String:
 var distance: float = index * LENGTH
 if distance >= SKY_GAP_MIN_DISTANCE and posmod(index, SKY_GAP_PERIOD_CHUNKS) < SKY_GAP_LENGTH_CHUNKS:
  return EVENT_SKY_GAP
 var tier: int = tier_for_distance(distance)
 if is_traffic_surge_chunk(index, tier):
  return EVENT_TRAFFIC_SURGE
 return EVENT_NONE

static func is_traffic_surge_chunk(index: int, tier: int) -> bool:
 var window_index: int = floori(float(index) / float(TRAFFIC_SURGE_PERIOD_CHUNKS))
 var offset_in_window: int = index - window_index * TRAFFIC_SURGE_PERIOD_CHUNKS
 if offset_in_window >= TRAFFIC_SURGE_LENGTH_CHUNKS:
  return false
 var roll: int = posmod(window_index * 131 + 47, 12)
 return roll < TRAFFIC_SURGE_CHANCE_BY_TIER[tier]
