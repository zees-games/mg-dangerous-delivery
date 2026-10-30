extends RefCounted

const DdGame := preload("res://game/dd_game.gd")
const DdProgress := preload("res://game/dd_progress.gd")

## Stats are filed under dot-game's stable key; the wallet, drivers and awards stay on `uid:...`.

class _Platform extends RefCounted:
	func key() -> String:
		return "plat-9001"


class _Identity extends RefCounted:
	var uid := "acct-9001"
	var is_guest := false
	var claims: Dictionary = {}


## Failure descriptions, empty when the split holds.
static func run(game: DdGame, progress: DdProgress) -> Array[String]:
	var bad: Array[String] = []
	var session := DotClientSession.new()
	session.userid = 9001
	session.identity = _Identity.new()
	session.data["platform"] = _Platform.new()
	var key := &"uid:acct-9001"
	var _driver := game.join(key, "Keyed")
	progress.note_session(key, session)
	progress.record(key, DdProgress.FALLS)
	if progress.stats.has_player(key) or not progress.stats.has_player(&"plat-9001"):
		bad.append("the stats session is not under the stable key")
	if progress.session_values(key).get_value(DdProgress.FALLS) != 1.0:
		bad.append("the reading did not land")
	if progress.relay.record_of.get(&"plat-9001", &"") != key:
		bad.append("the relay does not map the stats key to the driver key")
	game.leave(key)
	if progress.stats.has_player(&"plat-9001") or progress.relay.record_of.has(&"plat-9001"):
		bad.append("leave left the stats session behind")
	return bad
