extends SceneTree
## Real saved sessions across title, campaign detours and failed writes.
const Sim=preload("res://scripts/sim/grid_sim.gd")
const Saves=preload("res://scripts/ui/save_catalog.gd")
const BASE: String="user://test_session_safety/"
const FILES: Array[String]=["sandbox.json","sandbox_auto.json","campaign.json","campaign_auto.json","backup.json","profile.json","preferences.cfg","midnight.json"]
var game: Node
var checks:=0
var failures:=0

func _initialize() -> void:
	_run.call_deferred()

func check(condition: bool, caption: String) -> void:
	checks+=1
	if not condition:
		failures+=1
		push_error("FAIL: "+caption)
	else: print("PASS: "+caption)

func settle() -> void:
	for i in range(4): await process_frame

func cleanup() -> void:
	for filename in FILES:
		for suffix in ["",".pending"]:
			var path: String=ProjectSettings.globalize_path(BASE+filename+suffix)
			if FileAccess.file_exists(path): DirAccess.remove_absolute(path)

func read_cash(path: String) -> float:
	var preview:=Sim.new()
	var loaded: Dictionary=preview.load_game(path)
	check(bool(loaded.get("ok",false)),"fixture remains a valid complete save: "+path.get_file())
	return float(preview.cash)

func escape() -> void:
	var event:=InputEventKey.new()
	event.keycode=KEY_ESCAPE
	event.physical_keycode=KEY_ESCAPE
	event.pressed=true
	root.push_input(event)
	event=event.duplicate() as InputEventKey
	event.pressed=false
	root.push_input(event)

func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(BASE))
	cleanup()
	game=load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	await settle()
	game.set_process(false)
	game.sandbox_save_path=BASE+"sandbox.json"
	game.sandbox_autosave_path=BASE+"sandbox_auto.json"
	game.campaign_save_path=BASE+"campaign.json"
	game.campaign_autosave_path=BASE+"campaign_auto.json"
	game.campaign_backup_path=BASE+"backup.json"
	game.campaign_panel.profile_path=BASE+"profile.json"
	game.campaign_panel.load_profile()
	game.preferences.storage_path=BASE+"preferences.cfg"
	game._refresh_title()
	game._open_campaign_directory()
	game.campaign_panel.request_start(1,true)
	check(game.campaign_panel.mode=="prologue" and not game.session_started,"first-run historical prologue has not started a player session")
	escape()
	await settle()
	check(game.campaign_panel.visible and game.campaign_panel.mode=="directory","Escape from title prologue returns to visible chapter selection")
	escape()
	await settle()
	check(game.welcome.visible and not game.session_started,"Escape from the restored directory returns to the real title")
	_test_stale_backup_after_title()
	_test_live_backup_timestamp_tie()
	_test_continue_campaign_detour()
	_test_failed_return_save()
	_test_chapter_replacement()
	_test_midnight_summary()
	game.queue_free()
	await settle()
	cleanup()
	print("SESSION SAFETY: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)

func _test_stale_backup_after_title() -> void:
	game._begin_free_sandbox(true)
	game.sim.cash=201111.0
	check(game._atomic_save(game.sandbox_save_path).ok,"sandbox A is saved to its real canonical slot")
	game.start_campaign_chapter(1,true)
	check(game._campaign_active() and is_equal_approx(read_cash(game.campaign_backup_path),201111.0),"entering campaign backs up the actual active sandbox A")
	game._leave_session(false,true)
	check(not game.session_started and game.welcome.visible,"leaving campaign saves it before restoring title")
	game._request_new_mode("sandbox",true)
	game.sim.cash=202222.0
	game._save()
	game._leave_session(false,true)
	check(not game.session_started and is_equal_approx(read_cash(game.sandbox_save_path),202222.0),"new sandbox B is really saved and survives returning to title")
	game.start_campaign_chapter(1,true)
	check(game._campaign_active() and is_equal_approx(read_cash(game.campaign_backup_path),201111.0),"title campaign entry preserves the old backup rather than backing up a display fixture")
	game.return_to_sandbox(true)
	check(not game._campaign_active() and is_equal_approx(game.sim.cash,202222.0),"campaign entered from title restores canonical sandbox B instead of stale backup A")
	game._leave_session(false,true)
	check(is_equal_approx(read_cash(game.sandbox_save_path),202222.0),"saving after the return cannot overwrite sandbox B with historical backup A")

func _test_live_backup_timestamp_tie() -> void:
	var same_timestamp:=false
	var expected_lines:=0
	# Filesystem mtimes expose whole seconds. Retry only when this very short
	# scenario crosses a second boundary; no sleep or platform-specific utime.
	for attempt in range(8):
		game._begin_free_sandbox(true)
		game.sim.cash=310000.0
		game._atomic_save(game.sandbox_save_path)
		game.sim.connect_buildings(2,6)
		game.sim.cash=310077.0
		expected_lines=game.sim.lines.size()
		game.start_campaign_chapter(1,true)
		same_timestamp=FileAccess.get_modified_time(game.sandbox_save_path)==FileAccess.get_modified_time(game.campaign_backup_path)
		if same_timestamp: break
	check(same_timestamp,"live-backup regression actually exercises identical filesystem modification timestamps")
	check(is_equal_approx(read_cash(game.sandbox_save_path),310000.0) and is_equal_approx(read_cash(game.campaign_backup_path),310077.0),"disk manual and detour backup retain different real sandbox states")
	game.return_to_sandbox(true)
	check(not game._campaign_active() and is_equal_approx(game.sim.cash,310077.0),"active sandbox detour restores its unsaved budget even when manual and backup mtimes tie")
	check(game.sim.lines.size()==expected_lines,"active detour also restores the newly built, unpersisted physical connection")

func _test_continue_campaign_detour() -> void:
	game.sim.cash=410055.0
	game.continue_campaign(true)
	check(game._campaign_active(),"continuing the historical save loads a real campaign from an active sandbox")
	game.return_to_sandbox(true)
	check(not game._campaign_active() and is_equal_approx(game.sim.cash,410055.0),"Continue Campaign preserves the unsaved sandbox just like starting a chapter")

func _test_failed_return_save() -> void:
	game.start_campaign_chapter(1,true)
	game.sim.cash=590005.0
	var canonical_path: String=game.campaign_save_path
	var canonical_text: String=FileAccess.get_file_as_string(canonical_path)
	var before: String=JSON.stringify(game.sim.snapshot(),"",true,true)
	var started: bool=game.session_started
	var visual_count: int=game.visuals.size()
	game.campaign_save_path=BASE+"missing_parent/campaign.json"
	game.return_to_sandbox(true)
	check(game._campaign_active() and game.session_started==started,"failed campaign save cannot switch the active session to sandbox")
	check(JSON.stringify(game.sim.snapshot(),"",true,true)==before,"failed return preserves every simulation value and in-flight operation")
	check(game.visuals.size()==visual_count and game.campaign_panel.visible,"failed return retains the live campaign scene and its source page")
	check(FileAccess.get_file_as_string(canonical_path)==canonical_text,"failed return does not truncate the prior valid canonical campaign")
	check("无法" in game.notice_label.text,"failed return exposes the actual storage failure to the player")
	game.campaign_save_path=canonical_path
	game.return_to_sandbox(true)
	check(not game._campaign_active(),"restoring a writable destination makes the same return operation succeed")

func _test_chapter_replacement() -> void:
	game.campaign_panel.profile.completed=[1]
	game.campaign_panel.profile.unlocked=2
	game.start_campaign_chapter(1,true)
	game.sim.cash=890000.0
	check(game._atomic_save(game.campaign_autosave_path).ok,"an old chapter automatic save exists before replacing its slot")
	game._leave_session(false,true)
	game.start_campaign_chapter(2,true)
	check(game._campaign_active() and int(game.sim.campaign.chapter_id)==2,"confirmed new chapter entry creates the actual second historical scenario")
	check(not FileAccess.file_exists(game.campaign_autosave_path),"successfully entering a new chapter removes the previous chapter automatic member")
	var catalog: Dictionary=Saves.inspect([game.campaign_save_path,game.campaign_autosave_path],"campaign")
	check(not catalog.latest.is_empty() and int(catalog.latest.chapter)==2,"Continue discovery points at the new chapter rather than its stale automatic predecessor")
	game.continue_campaign(true)
	check(int(game.sim.campaign.chapter_id)==2 and not is_equal_approx(game.sim.cash,890000.0),"actual Continue restores the newly selected chapter")
	game.sim.cash=920000.0
	game._atomic_save(game.campaign_autosave_path)
	game.restart_campaign_chapter(true)
	check(not FileAccess.file_exists(game.campaign_autosave_path) and int(game.sim.campaign.chapter_id)==2,"restarting a chapter also clears its obsolete automatic member after saving")
	game.sim.cash=930000.0
	game._atomic_save(game.campaign_autosave_path)
	var automatic_text: String=FileAccess.get_file_as_string(game.campaign_autosave_path)
	var canonical_path: String=game.campaign_save_path
	var manual_text: String=FileAccess.get_file_as_string(canonical_path)
	game.campaign_save_path=BASE+"missing_parent/new_chapter.json"
	game.start_campaign_chapter(1,true)
	check(FileAccess.get_file_as_string(game.campaign_autosave_path)==automatic_text,"failed new-chapter persistence preserves the existing automatic fallback")
	check(FileAccess.get_file_as_string(canonical_path)==manual_text,"failed new-chapter persistence also preserves the prior manual slot")
	game.campaign_save_path=canonical_path

func _test_midnight_summary() -> void:
	var model:=Sim.new()
	model.reset(42)
	model.next_storm_at=1000.0
	model.digital.next_attack_at=1000.0
	model.step(40.501)
	check(int(model.day)==3 and float(model.time_hours)<1.0,"the actual simulator has crossed two midnights before summary inspection")
	check(model.save_game(BASE+"midnight.json").ok,"multi-day game time is persisted through the real save format")
	var catalog: Dictionary=Saves.inspect([BASE+"midnight.json"])
	check(not catalog.latest.is_empty() and "第 3 天 00:30" in str(catalog.latest.detail),"SaveCatalog reads the saved day and clock instead of reconstructing day from wrapped time_hours")
