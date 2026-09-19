extends RefCounted
## PHASE C — minimal Signal Story system (spec sections 29-34). Plain data
## (id / trigger condition / English canonical text) plus a pure
## `condition_met()` check per id — no dialogue tree, no branching, no
## save/persistence beyond one run. Playback state (which ids have already
## played) is transient, run-scoped state that lives on Main (reset by
## start_run() like everything else — see Main.played_signals), matching
## this project's existing convention for other run-scoped fields
## (Main.upgrades_taken, Rider.slides, etc.) rather than inventing a new
## persistence layer for three lines of text.
const SIGNAL_CITY_START: String = "SIGNAL_CITY_START"
const SIGNAL_CITY_MID: String = "SIGNAL_CITY_MID"
const SIGNAL_CITY_BOSS_CLEAR: String = "SIGNAL_CITY_BOSS_CLEAR"

## Iteration order only — each id's own condition_met() is independent and
## self-contained, so order here doesn't imply anything about when they can
## fire relative to each other beyond what their own conditions say.
const ORDER: Array[String] = [SIGNAL_CITY_START, SIGNAL_CITY_MID, SIGNAL_CITY_BOSS_CLEAR]

const MID_DISTANCE: float = 1500.0

## English canonical text (this project's existing convention: English is
## the lookup key everywhere else too — see localization.gd's KO dict keyed
## by English strings, and Hud.t()/Locale.text()). Natural placeholder
## translations, not final localized copy.
const MESSAGES: Dictionary = {
 SIGNAL_CITY_START: "...are you listening?",
 SIGNAL_CITY_MID: "We need to get out of the city.",
 SIGNAL_CITY_BOSS_CLEAR: "I didn't think you'd make it this far...",
}

## Pure function of (distance, chapter) — no hidden state, so a test can
## check any id's condition directly without needing a live Main/City.
static func condition_met(id: String, distance: float, chapter: String) -> bool:
 match id:
  SIGNAL_CITY_START:
   return distance >= 0.0
  SIGNAL_CITY_MID:
   return distance >= MID_DISTANCE
  SIGNAL_CITY_BOSS_CLEAR:
   return chapter == "CITY_REST" or chapter == "CITY_COMPLETE"
  _:
   return false
