extends SceneTree
## Player-visible visual semantics, actual actions and responsive first-screen decisions.
const Sim = preload("res://scripts/sim/grid_sim.gd")
const Presenter = preload("res://scripts/ui/grid_presenter.gd")
const UI = preload("res://scripts/ui/ui_kit.gd")
const Chart = preload("res://scripts/ui/power_chart.gd")
var game: Node
var checks := 0
var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func check(value: bool, caption: String) -> void:
	checks+=1
	if not value:
		failures+=1
		push_error("FAIL: "+caption)

func settle() -> void:
	for frame in range(5): await process_frame

func find_button(node: Node, caption: String) -> Button:
	if node is Button and caption in node.text: return node
	for child in node.get_children():
		var found: Button=find_button(child,caption)
		if found!=null: return found
	return null

func _run() -> void:
	var sim := Sim.new()
	sim.reset(42)
	var before: Dictionary=sim.snapshot().duplicate(true)
	var snapshot: Dictionary=Presenter.operating_snapshot(sim)
	check(is_equal_approx(float(snapshot.deficit),maxf(0,float(sim.totals.demand)-float(sim.totals.served))),"deficit uses actual public delivery, not installed capacity")
	check(Presenter.customer_feedback(sim,6).powered==false,"unconnected customer has public outage feedback without telemetry")
	check(Presenter.facility_marker(sim,6).text=="!","customer outage remains visible without trustworthy device readings")
	Presenter.diagnosis(sim)
	check(sim.snapshot()==before,"visual snapshots and diagnostics neither advance time nor charge money")
	var original_health: float=float(sim.get_building(1).health)
	sim.get_building(1).health=0
	check(Presenter.facility_marker(sim,1).text=="?","an unknown generator fault is not disclosed by the new map marker")
	sim.get_building(1).health=original_health
	var diagnosis: Dictionary=Presenter.diagnosis(sim)
	var ids: Dictionary={}
	for cause in diagnosis.causes:
		check(not ids.has(str(cause.id)),"each piece of evidence appears once")
		ids[str(cause.id)]=true
	var managed := Sim.new()
	managed.start_management_game(42)
	managed.management.state.stage=5
	check(managed.explore_region().ok,"region can be inspected for prospective customer feedback")
	var prospective_count := 0
	for building in managed.buildings:
		if int(building.get("city_id",0))>0 and building.kind in ["home","factory","hospital"]:
			prospective_count+=1
			check(Presenter.customer_feedback(managed,int(building.id)).is_empty(),"cities not opened for service do not appear as company outages")
	check(prospective_count>0,"prospective-customer assertions exercise actual regional loads")
	check(sim.configure_facility(1,{"dispatch":.75},"field").ok,"real facility setting admits a field task")
	var jobs: Array=Presenter.jobs(sim)
	check(not jobs.is_empty() and jobs[0].phase=="pending","job presentation reports acceptance rather than success")
	check(float(jobs[0].duration)>0 and float(jobs[0].remaining)>0,"new task progress has a real recorded duration")
	var remaining: float=float(jobs[0].remaining)
	sim.step(.1)
	check(float(Presenter.jobs(sim)[0].remaining)<remaining and sim.get_building(1).dispatch==1.0,"progress advances before the device setting takes effect")
	var host := Control.new()
	host.theme=UI.create_theme()
	root.add_child(host)
	var gauge: Control=UI.metric(host,"已供 / 需求",5,20,"MW")
	check(is_equal_approx(gauge.ratio(),.25),"quantity length has a shared zero baseline")
	var unknown: Control=UI.metric(host,"实时功率",0,20,"MW",UI.TEAL,false)
	gauge.sync_from(unknown)
	check(gauge.ratio()<0 and not gauge.known,"unknown visual data cannot become a zero-power bar")
	var chart := Chart.new()
	chart.sample(10,12,0,8)
	chart.sample(10,12,1.0/12.0,9)
	chart.sample(10,12,1,10)
	check(chart.has_continuous_segment(1),"ordinary five-minute observations have a continuous plot")
	check(not chart.has_continuous_segment(2),"long manual-advance gaps do not fabricate an intermediate curve")
	chart.record_event("已执行",1)
	chart.record_event("已执行",1)
	check(chart.events.size()==1,"same observed event is not duplicated by a refresh")
	chart.free()
	host.queue_free()
	game=load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	await settle()
	game.set_process(false)
	game._activate_session()
	game.speed=0
	game.onboarding=false
	game.hud.onboarding_panel.hide()
	game._update_hud()
	check(is_equal_approx(game.hud.supply_gauge.ratio(),float(game.sim.totals.served)/float(game.sim.totals.demand)),"main operating rail uses the same actual supply denominator")
	var count: int=game.sim.lines.size()
	var funds: float=game.sim.cash
	game.hud._act_on_focus()
	check(game.tool=="line" and game.connection_start==6,"priority action starts connection at the identified unconnected customer")
	check(game.sim.lines.size()==count and game.sim.cash==funds,"priority navigation does not auto-build a line or promise a result")
	game._set_tool("select")
	game._hud_action("clear_selection")
	for resolution in [Vector2i(1280,720),Vector2i(1440,900)]:
		root.size=resolution
		for ratio in [1.0,1.25,1.5]:
			game.preferences.ui_scale=ratio
			game._apply_preferences()
			game.hud.operator_dock.close()
			game._hud_action("clear_selection")
			game.hud.refresh_visuals()
			await settle()
			var bounds := Rect2(Vector2.ZERO,game.root_ui.size)
			check(bounds.encloses(game.hud.status_panel.get_rect()),"supply rail stays visible at "+str(resolution)+" @"+str(ratio))
			check(bounds.encloses(game.hud.dock_panel.get_rect()),"primary map tools stay visible at "+str(resolution)+" @"+str(ratio))
			game.hud.operator_dock.show_page("diagnosis")
			await settle()
			var action: Button=find_button(game.hud.operator_dock.body,"开始接线")
			check(action!=null,"known unconnected customer has a direct action")
			if action!=null:
				var visible_area: Rect2=game.hud.operator_dock.scroll.get_global_rect()
				check(visible_area.encloses(action.get_global_rect()),"first known problem action is visible without scrolling at "+str(resolution)+" @"+str(ratio)+" viewport="+str(visible_area)+" action="+str(action.get_global_rect()))
	game.queue_free()
	await process_frame
	print("VISUAL OPERATOR: %d checks; %d failures" % [checks,failures])
	quit(1 if failures else 0)
