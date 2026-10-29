extends SceneTree
## Real OpenGL visual matrix. All discovery and saves use isolated paths.
var game: Node
var captures := 0
var failures := 0
var destination := ""
const PATHS := ["user://render_campaign_profile.json","user://render_campaign_save.json","user://render_campaign_auto.json","user://render_campaign_backup.json"]

func _initialize() -> void:
	_run.call_deferred()

func settle() -> void:
	for i in range(5): await process_frame

func find_button(node: Node, caption: String) -> Button:
	if node is Button and caption in node.text: return node
	for child in node.get_children():
		var found := find_button(child,caption)
		if found!=null: return found
	return null

func capture(caption: String) -> void:
	await settle()
	await RenderingServer.frame_post_draw
	if root.get_texture().get_image().save_png(destination.path_join(caption+".png"))!=OK: failures+=1
	captures+=1

func _run() -> void:
	game=load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	await settle()
	game.set_process(false)
	game.campaign_panel.profile_path=PATHS[0]
	game.campaign_save_path=PATHS[1]
	game.campaign_autosave_path=PATHS[2]
	game.campaign_backup_path=PATHS[3]
	game.campaign_panel.load_profile()
	game.campaign_panel.profile.unlocked=15
	game.campaign_panel.profile.completed=range(1,16)
	for resolution in [Vector2i(1280,720),Vector2i(1440,900),Vector2i(1600,1000),Vector2i(1920,1080)]:
		DisplayServer.window_set_size(resolution)
		root.size=resolution
		destination="res://.godot/campaign-qa/ui/%dx%d" % [resolution.x,resolution.y]
		DirAccess.make_dir_recursive_absolute(destination)
		game.campaign_panel.open_directory()
		await capture("directory")
		game.campaign_panel.profile.prologue_seen=false
		game.campaign_panel.request_start(1,true)
		await capture("prologue")
		game.campaign_panel._finish_prologue()
		await capture("briefing")
		find_button(game.campaign_panel,"进入现场").pressed.emit()
		game.notice_label.hide()
		await capture("current_task")
		var hint := find_button(game.mission_box,"给我一个提示")
		if hint!=null: hint.pressed.emit()
		await capture("hint")
		game.hud.close_popups()
		await capture("map_01_city")
		var roles: Dictionary=game.sim.campaign.roles
		game.sim.connect_buildings(roles.node,roles.customer)
		var home: Dictionary=game.sim.build("home",Vector2i(8,8))
		var source: Dictionary=game.sim.build("dc_dynamo",Vector2i(8,9))
		game.sim.connect_buildings(int(source.id),roles.node)
		game.sim.connect_buildings(int(home.id),roles.node)
		game.sim.step(3.0)
		game._sync_world(true)
		game._update_hud()
		await capture("report")
		game.campaign_panel.open_archive()
		await capture("archive")
		for chapter_id in [5,8]:
			game.start_campaign_chapter(chapter_id)
			game.campaign_panel.close()
			game.cam_target=game._cell_position(Vector2i(23,23))
			game.zoom=130
			game._update_camera()
			game.notice_label.hide()
			await capture("map_%02d" % chapter_id)
		game.start_campaign_chapter(15)
		game.campaign_panel.open_archive()
		await capture("archive_optional")
		game.campaign_panel.close()
		# Present the longest task text without altering any persistent progress.
		game.sim.campaign.step_index=3
		game.mission_snapshot=""
		game._update_hud()
		game.hud.toggle_popup("missions")
		for i in range(3):
			var final_hint := find_button(game.mission_box,"给我一个提示")
			if final_hint!=null: final_hint.pressed.emit()
		await capture("final_task_hints")
	for path in PATHS:
		if FileAccess.file_exists(path): DirAccess.remove_absolute(path)
	game.queue_free()
	await settle()
	print("CAMPAIGN RENDER: %d captures, %d failures" % [captures,failures])
	quit(1 if failures else 0)
