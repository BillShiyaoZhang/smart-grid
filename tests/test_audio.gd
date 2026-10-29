extends SceneTree
const Director = preload("res://scripts/audio/audio_director.gd")
const Sim = preload("res://scripts/sim/grid_sim.gd")
const Evolution = preload("res://scripts/sim/grid_evolution.gd")
var checks := 0
var failures := 0

func check(value: bool, caption: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error("FAIL: " + caption)

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/audio/manifest.json"))
	check(manifest.assets.size() == 41, "complete original sound library is available")
	for path in manifest.assets:
		var asset: Dictionary = manifest.assets[path]
		check(ResourceLoader.exists("res://assets/audio/" + path), "imported playable audio: " + path)
		check(float(asset.peak_dbfs) < -1, "headroom in audio source: " + path)
		if asset.category == "music":
			var stream := load("res://assets/audio/" + path) as AudioStream
			check(stream.get_length() >= 119.9 and stream.get_length() <= 180, "complete 2-3 minute score: " + path)
	var audio := Director.new()
	root.add_child(audio)
	await process_frame
	check(audio.music_name == "title" and audio.ambience_name == "coast", "title has real music and coastal soundscape")
	check(audio.music_players.size() == 2 and audio.effect_players.size() == 12 and audio.facility_players.size() == 4, "playback resources are bounded")
	check(audio.FACILITY_FAMILIES.size() == Sim.CATALOG.merged(Evolution.EXTRA_CATALOG).size(), "all facility kinds have a sound family")
	var preferences := {"master_volume":.6, "music_volume":.3, "sfx_volume":.4, "ambience_volume":.2, "alerts_volume":.7, "mute_unfocused":true}
	audio.apply_preferences(preferences)
	var debug: Dictionary = audio.get_debug_state()
	check(absf(float(debug.volumes.Master.volume) - .6) < .001 and absf(float(debug.volumes.Alerts.volume) - .7) < .001, "actual audio buses follow preferences")
	audio._notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	check(AudioServer.is_bus_mute(0), "unfocused window mutes when requested")
	audio._notification(Node.NOTIFICATION_APPLICATION_FOCUS_IN)
	check(not AudioServer.is_bus_mute(0), "refocusing restores audio")
	preferences.master_volume = 0
	audio.apply_preferences(preferences)
	audio._notification(Node.NOTIFICATION_APPLICATION_FOCUS_IN)
	check(AudioServer.is_bus_mute(0), "zero volume remains muted after focus changes")
	preferences.master_volume = .6
	audio.apply_preferences(preferences)
	check(audio.play_ui("confirm"), "settings confirmation preview plays a real sample")
	check(not audio.play_ui("confirm"), "repeated UI sound is limited in real time")
	check(audio.play_ui("focus") and audio.played_cues[-1].cue == "hover", "keyboard focus uses the quiet hover cue")
	check(audio.play_ui("alert"), "settings alert preview uses Alerts bus")
	check(audio.played_cues[-1].bus == "Alerts", "alert preview is independently mixed")
	audio.set_context("playing")
	audio.reset_session({"snapshot":{"hour":10.0,"time_hours":12}, "alerts":[{"id":"supply","severity":"critical"}], "receipts":[{"command_id":2,"action":"facility","phase":"executed","elapsed_hours":9}]})
	var before := audio.played_cues.size()
	audio.observe_public_state({"hour":10.0,"time_hours":12}, [{"id":"supply","severity":"critical"}], [{"command_id":2,"action":"facility","phase":"executed","elapsed_hours":9}])
	check(audio.played_cues.size() == before, "loading a session does not replay existing alerts or receipts")
	check(audio.music_name == "day", "public daylight selects daytime music")
	audio.observe_public_state({"hour":11.0,"time_hours":22}, [], [])
	check(audio.music_name == "night" and audio.ambience_name == "night", "night has distinct music and ambience")
	check(audio.played_cues[-1].cue == "recovery", "publicly resolved supply alert produces a quiet recovery theme")
	audio.set_context("campaign")
	check(audio.music_name == "campaign", "historical campaign has its own score")
	audio.observe_public_state({"hour":12.0,"time_hours":22,"weather":"风暴"}, [], [])
	check(audio.music_name == "storm" and audio.ambience_name == "storm", "public weather selects storm soundscape")
	check(audio._next_thunder_ms > Time.get_ticks_msec(), "thunder uses real time and does not repeat per simulation step")
	audio.set_context("paused")
	check(audio.get_debug_state().paused and audio.music_name == "storm", "pause keeps the current score with reduced mix")
	audio.set_context("playing")
	audio.observe_public_state({"hour":13.0,"time_hours":13}, [{"id":"new_public_fault","severity":"critical"}], [])
	check(audio.played_cues[-1].cue == "critical", "new public critical alert has audible feedback")
	before = audio.played_cues.size()
	audio.observe_public_state({"hour":13.0,"time_hours":13}, [{"id":"new_public_fault","severity":"critical"}], [])
	check(audio.played_cues.size() == before, "refreshing does not replay public alerts")
	audio.observe_public_state({"hour":14.0,"time_hours":13}, [], [{"command_id":8,"action":"facility","phase":"executed","elapsed_hours":14}])
	check(audio.played_cues[-1].cue == "executed", "new public receipt plays execution feedback")
	before = audio.played_cues.size()
	audio.observe_public_state({"hour":14.0,"time_hours":13}, [], [{"command_id":8,"action":"facility","phase":"executed","elapsed_hours":14}])
	check(audio.played_cues.size() == before, "public receipt is not replayed by later renders")
	audio.observe_public_state({"hour":14.2,"time_hours":13}, [], [{"command_id":9,"phase":"pending","target_id":1}])
	check(audio.played_cues[-1].cue == "queued", "new public pending work has distinct queue feedback")
	before = audio.played_cues.size()
	audio.observe_public_state({"hour":14.2,"time_hours":13}, [], [{"command_id":9,"phase":"pending","target_id":1}])
	check(audio.played_cues.size() == before, "pending work does not repeat its sound while its countdown refreshes")
	audio.observe_public_state({"hour":5.0,"time_hours":7}, [{"id":"older_fault","severity":"critical"}], [{"command_id":7,"phase":"rejected","elapsed_hours":4}])
	check(audio.played_cues.size() == before, "rewinding via an older save establishes a silent baseline")
	audio.observe_public_state({"hour":6.0,"time_hours":7,"facilities":[{"kind":"gas","trusted":false,"output":null,"served":null}]}, [], [])
	check(not bool(audio.facility_players[0].get_meta("requested", false)), "unknown facility readings never imply a machinery sound")
	audio.observe_public_state({"hour":7.0,"time_hours":7,"facilities":[{"kind":"gas","trusted":true,"output":12.0,"served":0.0}]}, [], [])
	check(bool(audio.facility_players[0].get_meta("requested", false)) and audio.facility_players[0].get_meta("family") == "thermal", "verified public operation enables its sound family")
	audio.set_context("title")
	check(not bool(audio.facility_players[0].get_meta("requested", false)) and audio.music_name == "title", "returning to title removes old machinery and selects the title score")
	var looped := audio._stream("facilities/thermal.ogg", true) as AudioStreamOggVorbis
	var preview := audio._stream("facilities/thermal.ogg", false) as AudioStreamOggVorbis
	check(looped.loop and not preview.loop and looped != preview, "preview and looping machinery resources cannot alter each other")
	for index in range(30): audio.play_ui("hover")
	check(audio.effect_players.size() == 12, "bursty interaction never allocates extra audio players")
	for index in range(300): audio._remember_receipt("long-session-%d" % index)
	check(audio._known_receipts.size() <= 256, "long-session receipt memory stays bounded")
	audio.queue_free()
	await process_frame
	if DisplayServer.get_name() != "headless":
		# Real hardware finishes the final audio buffer asynchronously.
		await create_timer(.2).timeout
	print("AUDIO: %d checks, %d failures" % [checks, failures])
	quit(1 if failures > 0 else 0)
