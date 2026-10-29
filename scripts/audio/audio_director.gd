extends Node
## Presentation-only audio. This node never receives the simulation or reads faults.
## Call reset_session with public snapshots/alerts/receipts after loading a session.

signal cue_played(cue: String, bus: String)

const AUDIO_ROOT := "res://assets/audio/"
const MUSIC_NAMES := ["title", "day", "night", "campaign", "storm"]
const STINGERS := ["chapter", "objective", "victory", "failure", "recovery"]
const EFFECTS := ["hover", "confirm", "cancel", "disabled", "select", "build", "connect", "demolish", "queued", "executed", "rejected", "save", "load", "repair", "toggle", "research", "warning", "critical", "outage", "storm_warning", "thunder"]
const FACILITY_FAMILIES := {
	"wind":"turbine", "gas":"thermal", "dc_dynamo":"thermal", "steam":"thermal",
	"coal":"thermal", "ccgt":"thermal", "nuclear":"thermal", "fusion":"thermal",
	"hydro":"hydro", "pumped_storage":"hydro", "solar":"storage", "battery":"storage",
	"flow_battery":"storage", "community_battery":"storage", "hydrogen":"storage", "thermal_storage":"storage",
	"substation":"transformer", "intertie":"transformer", "hvdc":"transformer", "condenser":"transformer",
	"control":"digital", "relay":"digital", "soc":"digital", "sensor":"digital",
	"home":"city", "factory":"thermal", "hospital":"city", "academy":"city", "cooling":"city"
}
const VOLUME_DEFAULTS := {"Master":.8, "Music":.5, "SFX":.75, "Ambience":.55, "Alerts":.75}
const PREFERENCE_FIELDS := {"Master":"master_volume", "Music":"music_volume", "SFX":"sfx_volume", "Ambience":"ambience_volume", "Alerts":"alerts_volume"}
const POOL_SIZE := 12

var context := "title"
var music_name := ""
var ambience_name := ""
var mute_unfocused := true
var focused := true
var music_players: Array[AudioStreamPlayer] = []
var ambience_players: Array[AudioStreamPlayer] = []
var effect_players: Array[AudioStreamPlayer] = []
var facility_players: Array[AudioStreamPlayer] = []
var played_cues: Array[Dictionary] = []
var _streams: Dictionary = {}
var _cooldowns: Dictionary = {}
var _known_alerts: Dictionary = {}
var _known_receipts: Dictionary = {}
var _receipt_order: Array[String] = []
var _baseline_initialized := false
var _last_elapsed := -1.0
var _last_real_ms := 0
var _music_slot := 0
var _music_fade := 1.0
var _ambience_slot := 0
var _ambience_fade := 1.0
var _paused := false
var _public_context: Dictionary = {}
var _next_thunder_ms := 0
var _alert_emitted_ms := -100000
var _playback_enabled := true

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	# The headless Dummy driver retains pending playback until its mixer tick,
	# which creates false stream leaks in scene tests that exit on the next frame.
	# Keep the complete routing, resource and cue logic without starting that
	# driver. Normal graphical game/capture runs always use actual playback.
	_playback_enabled = DisplayServer.get_name() != "headless"
	_ensure_buses()
	for index in range(2):
		music_players.append(_player("Music", "Music%d" % index))
		ambience_players.append(_player("Ambience", "Ambience%d" % index))
	for index in range(POOL_SIZE): effect_players.append(_player("SFX", "Effect%d" % index))
	for index in range(4): facility_players.append(_player("Ambience", "Facility%d" % index))
	_last_real_ms = Time.get_ticks_msec()
	set_context(context)

func _player(bus_name: String, node_name: String) -> AudioStreamPlayer:
	var player := AudioStreamPlayer.new()
	player.name = node_name
	player.bus = bus_name
	add_child(player)
	return player

func _start(player: AudioStreamPlayer) -> void:
	player.set_meta("requested", true)
	if _playback_enabled: player.play()

func _stop(player: AudioStreamPlayer) -> void:
	player.stop()
	player.set_meta("requested", false)

func _exit_tree() -> void:
	for players in [music_players, ambience_players, effect_players, facility_players]:
		for player in players:
			if is_instance_valid(player):
				player.stop()
				player.stream = null
	_streams.clear()

func _ensure_buses() -> void:
	for bus_name in ["Music", "Ambience", "SFX", "Alerts"]:
		if AudioServer.get_bus_index(bus_name) >= 0: continue
		AudioServer.add_bus()
		var index := AudioServer.bus_count - 1
		AudioServer.set_bus_name(index, bus_name)
		AudioServer.set_bus_send(index, "Master")

func apply_preferences(prefs: Variant) -> void:
	_ensure_buses()
	for bus_name in PREFERENCE_FIELDS:
		var field: String = PREFERENCE_FIELDS[bus_name]
		var value: Variant = prefs.get(field) if prefs != null else null
		var volume := clampf(float(value) if value != null else float(VOLUME_DEFAULTS[bus_name]), 0, 1)
		var index := AudioServer.get_bus_index(bus_name)
		AudioServer.set_bus_volume_db(index, linear_to_db(maxf(volume, .0001)))
		AudioServer.set_bus_mute(index, volume <= 0 or (bus_name == "Master" and mute_unfocused and not focused))
	var focus_value: Variant = prefs.get("mute_unfocused") if prefs != null else null
	mute_unfocused = bool(focus_value) if focus_value != null else true
	_update_focus_mute()

func set_context(value: String) -> void:
	context = value if value in ["title", "playing", "campaign", "paused"] else "playing"
	_paused = context == "paused"
	if not is_inside_tree() or music_players.is_empty(): return
	if context == "title":
		_switch_music("title")
		_switch_ambience("coast")
		for player in facility_players: _stop(player)
	elif context != "paused":
		_update_soundscape()

func _stream(relative_path: String, looping: bool = false) -> AudioStream:
	var cache_key := relative_path + (":loop" if looping else ":once")
	if _streams.has(cache_key): return _streams[cache_key]
	var path := AUDIO_ROOT + relative_path
	if not ResourceLoader.exists(path): return null
	var result := (load(path) as AudioStream).duplicate() as AudioStream
	if result is AudioStreamOggVorbis: result.loop = looping
	if result is AudioStreamWAV and looping: result.loop_mode = AudioStreamWAV.LOOP_FORWARD
	_streams[cache_key] = result
	return result

func _switch_music(value: String) -> void:
	if value == music_name: return
	var stream := _stream("music/%s.ogg" % value, true)
	if stream == null: return
	music_name = value
	_music_slot = 1 - _music_slot
	music_players[_music_slot].stream = stream
	music_players[_music_slot].volume_db = -80
	_start(music_players[_music_slot])
	_music_fade = 0

func _switch_ambience(value: String) -> void:
	if value == ambience_name: return
	var stream := _stream("ambience/%s.ogg" % value, true)
	if stream == null: return
	ambience_name = value
	_ambience_slot = 1 - _ambience_slot
	ambience_players[_ambience_slot].stream = stream
	ambience_players[_ambience_slot].volume_db = -80
	_start(ambience_players[_ambience_slot])
	_ambience_fade = 0

func _update_soundscape() -> void:
	if context == "title" or _paused: return
	var weather := str(_public_context.get("weather", ""))
	var storm := weather in ["风暴", "storm"] or bool(_public_context.get("storm_active", false))
	var time_of_day := float(_public_context.get("time_hours", 12))
	var night := time_of_day < 6 or time_of_day >= 19
	var campaign := context == "campaign" or str(_public_context.get("mode", "")) == "campaign"
	_switch_music("storm" if storm else ("campaign" if campaign else ("night" if night else "day")))
	_switch_ambience("storm" if storm else ("night" if night else "coast"))
	if storm and _next_thunder_ms == 0: _next_thunder_ms = Time.get_ticks_msec() + 17000
	if not storm: _next_thunder_ms = 0

func _process(_delta: float) -> void:
	var now := Time.get_ticks_msec()
	var elapsed := clampf(float(now - _last_real_ms) / 1000, 0, .25)
	_last_real_ms = now
	_music_fade = minf(1, _music_fade + elapsed / 2.4)
	_ambience_fade = minf(1, _ambience_fade + elapsed / 1.8)
	var duck := .44 if _paused else 1.0
	for index in range(music_players.size()):
		var amount := _music_fade if index == _music_slot else 1 - _music_fade
		music_players[index].volume_db = linear_to_db(maxf(.0001, amount * .40 * duck))
		if amount == 0: _stop(music_players[index])
	for index in range(ambience_players.size()):
		var amount := _ambience_fade if index == _ambience_slot else 1 - _ambience_fade
		ambience_players[index].volume_db = linear_to_db(maxf(.0001, amount * .20 * duck))
		if amount == 0: _stop(ambience_players[index])
	for player in facility_players: player.volume_db = -29 if not _paused else -40
	if _next_thunder_ms > 0 and now >= _next_thunder_ms and not _paused and context != "title":
		_emit("thunder", "Ambience", .2, 10.0)
		_next_thunder_ms = now + 23000

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		focused = false
		_update_focus_mute()
	elif what == NOTIFICATION_APPLICATION_FOCUS_IN:
		focused = true
		_update_focus_mute()

func _update_focus_mute() -> void:
	var index := AudioServer.get_bus_index("Master")
	if index < 0: return
	AudioServer.set_bus_mute(index, (mute_unfocused and not focused) or AudioServer.get_bus_volume_db(index) <= -79.9)

func play_ui(cue: String = "confirm") -> bool:
	if cue == "alert": return _emit("warning", "Alerts", .42, .15)
	if cue == "focus": cue = "hover"
	return _emit(cue if cue in EFFECTS else "confirm", "SFX", .40, .07 if cue == "hover" else .10)

func play_action(cue: String, success: bool = true) -> bool:
	var resolved := cue
	if not success: resolved = "rejected"
	if resolved in STINGERS: return _emit(resolved, "Music", .54, 1.2)
	if resolved == "line" or resolved == "datalink": resolved = "connect"
	if resolved == "remove": resolved = "demolish"
	if not resolved in EFFECTS: resolved = "confirm" if success else "rejected"
	return _emit(resolved, "SFX", .48, .16)

func play_facility(kind: String) -> bool:
	var family := str(FACILITY_FAMILIES.get(kind, "city"))
	return _emit("facility:" + family, "Ambience", .12, .45)

func _emit(cue: String, bus_name: String, volume: float, cooldown_seconds: float) -> bool:
	var now := Time.get_ticks_msec()
	if now - int(_cooldowns.get(cue, -100000)) < int(cooldown_seconds * 1000): return false
	var stream: AudioStream
	if cue.begins_with("facility:"):
		# A single cycle preview; loop resources have separate cache entries.
		stream = _stream("facilities/%s.ogg" % cue.trim_prefix("facility:"), false)
	else:
		stream = _stream(("stingers/" if cue in STINGERS else "sfx/") + cue + ".wav")
	if stream == null or effect_players.is_empty(): return false
	var player: AudioStreamPlayer = null
	for candidate in effect_players:
		if not candidate.playing and (_playback_enabled or now >= int(candidate.get_meta("busy_until", 0))):
			player = candidate
			break
	if player == null: return false
	player.bus = bus_name
	player.volume_db = linear_to_db(maxf(volume, .0001))
	player.stream = stream
	player.set_meta("busy_until", now + int(stream.get_length() * 1000))
	_start(player)
	_cooldowns[cue] = now
	played_cues.append({"cue":cue, "bus":bus_name, "real_ms":now})
	if played_cues.size() > 64: played_cues.pop_front()
	cue_played.emit(cue, bus_name)
	return true

func _receipt_id(receipt: Dictionary) -> String:
	return str([receipt.get("command_id", receipt.get("id", -1)), receipt.get("action", ""), receipt.get("elapsed_hours", 0), receipt.get("phase", "")])

func _remember_receipt(identity: String) -> void:
	if _known_receipts.has(identity): return
	_known_receipts[identity] = true
	_receipt_order.append(identity)
	if _receipt_order.size() > 256: _known_receipts.erase(_receipt_order.pop_front())

func reset_session(baseline: Dictionary = {}) -> void:
	_known_alerts.clear()
	_known_receipts.clear()
	_receipt_order.clear()
	_cooldowns.clear()
	for player in effect_players:
		_stop(player)
		player.set_meta("busy_until", 0)
	for player in facility_players: _stop(player)
	_public_context = baseline.get("snapshot", {}).duplicate(true)
	_last_elapsed = float(_public_context.get("hour", _public_context.get("elapsed_hours", -1)))
	for alert in baseline.get("alerts", []):
		if alert is Dictionary: _known_alerts[str(alert.get("id", ""))] = str(alert.get("severity", "warning"))
	for receipt in baseline.get("receipts", []):
		if receipt is Dictionary: _remember_receipt(_receipt_id(receipt))
	_baseline_initialized = not baseline.is_empty()
	_alert_emitted_ms = -100000
	_update_soundscape()

func observe_public_state(snapshot: Dictionary, alerts: Array = [], receipts: Array = []) -> void:
	var elapsed := float(snapshot.get("hour", snapshot.get("elapsed_hours", 0)))
	if not _baseline_initialized or elapsed + .00001 < _last_elapsed:
		reset_session({"snapshot":snapshot, "alerts":alerts, "receipts":receipts})
		_update_facilities(snapshot.get("facilities", []))
		return
	_public_context = snapshot.duplicate(true)
	_last_elapsed = elapsed
	_update_soundscape()
	_update_facilities(snapshot.get("facilities", []))
	var now := Time.get_ticks_msec()
	var current_alerts: Dictionary = {}
	var alert_cue := ""
	var previously_short := _known_alerts.has("supply")
	for alert in alerts:
		if not alert is Dictionary: continue
		var id := str(alert.get("id", ""))
		var severity := str(alert.get("severity", "warning"))
		current_alerts[id] = severity
		if not _known_alerts.has(id) or (_known_alerts[id] != "critical" and severity == "critical"):
			if severity == "critical": alert_cue = "critical"
			elif alert_cue.is_empty(): alert_cue = "storm_warning" if id == "storm" else "warning"
	_known_alerts = current_alerts
	if previously_short and not current_alerts.has("supply") and not _paused and context != "title":
		_emit("recovery", "Music", .35, 25.0)
	if not alert_cue.is_empty() and now - _alert_emitted_ms >= 3000 and not _paused and context != "title":
		if _emit(alert_cue, "Alerts", .42, 3.0): _alert_emitted_ms = now
	var receipt_cue := ""
	for receipt in receipts:
		if not receipt is Dictionary or str(receipt.get("phase", "")) not in ["pending", "accepted", "executed", "rejected"]: continue
		var id := _receipt_id(receipt)
		if _known_receipts.has(id): continue
		_remember_receipt(id)
		if str(receipt.phase) == "rejected": receipt_cue = "rejected"
		elif str(receipt.phase) == "executed" and receipt_cue != "rejected": receipt_cue = "executed"
		elif receipt_cue.is_empty(): receipt_cue = "queued"
	if not receipt_cue.is_empty() and not _paused and context != "title": _emit(receipt_cue, "SFX", .40, 1.0)

func _update_facilities(rows: Array) -> void:
	if context == "title": return
	var families: Array[String] = []
	for row in rows:
		if not row is Dictionary or not bool(row.get("trusted", false)): continue
		# Unknown values are null and never inferred from raw hidden operation.
		if row.get("output") == null and row.get("served") == null: continue
		if float(row.get("output", 0) if row.get("output") != null else 0) <= .01 and float(row.get("served", 0) if row.get("served") != null else 0) <= .01: continue
		var family := str(FACILITY_FAMILIES.get(str(row.get("kind", "")), "city"))
		if not family in families: families.append(family)
		if families.size() >= facility_players.size(): break
	for index in range(facility_players.size()):
		var player := facility_players[index]
		if index >= families.size():
			_stop(player)
			player.set_meta("family", "")
			continue
		if str(player.get_meta("family", "")) == families[index] and bool(player.get_meta("requested", false)): continue
		player.stream = _stream("facilities/%s.ogg" % families[index], true)
		player.volume_db = -29
		player.set_meta("family", families[index])
		_start(player)

func get_debug_state() -> Dictionary:
	var volumes: Dictionary = {}
	for bus_name in PREFERENCE_FIELDS:
		var index := AudioServer.get_bus_index(bus_name)
		volumes[bus_name] = {"volume":db_to_linear(AudioServer.get_bus_volume_db(index)), "muted":AudioServer.is_bus_mute(index)}
	return {"context":context, "music":music_name, "ambience":ambience_name, "paused":_paused, "playback_enabled":_playback_enabled,
		"pool_size":effect_players.size(), "music_players":music_players.size(), "facility_players":facility_players.size(),
		"receipt_count":_known_receipts.size(), "alert_count":_known_alerts.size(), "volumes":volumes,
		"played":played_cues.duplicate(true)}
