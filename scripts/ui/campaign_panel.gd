extends Control
## Campaign navigation and discovery progress are independent of simulation saves.
const Catalog = preload("res://scripts/sim/campaign_catalog.gd")
const UI = preload("res://scripts/ui/ui_kit.gd")
const Shell = preload("res://scripts/ui/management_shell.gd")
const VisualChart = preload("res://scripts/ui/center_charts.gd")
var game: Node
var body: VBoxContainer
var content: VBoxContainer
var profile_path := "user://campaign_profile.json"
var profile: Dictionary = {"version":1,"unlocked":1,"completed":[],"last_chapter":1,"prologue_seen":false}
var hint_level := 0
var step_signature := ""
var hold_label: Label
var mode := "directory"
var chapter_buttons: Dictionary = {}
var hold_gauge: Control
var condition_gauges: Dictionary = {}
var interruption_label: Label
var _previous_hold := 0.0

func reset_session() -> void:
	hint_level=0
	step_signature=""
	hold_label=null
	hold_gauge=null
	condition_gauges.clear()
	_previous_hold=0

func chapter_focus_ids() -> Array[int]:
	var ids: Array[int]=[]
	if not game._campaign_active(): return ids
	var roles: Dictionary=game.sim.campaign.roles
	for role in ["source","node","customer","backup","hospital"]:
		if roles.has(role) and not game.sim.get_building(int(roles[role])).is_empty(): ids.append(int(roles[role]))
	return ids

func current_focus_target() -> Dictionary:
	if not game._campaign_active(): return {}
	var roles: Dictionary=game.sim.campaign.roles
	var predicate: String=str(game.sim.campaign.current_step().get("predicate",""))
	var line_role: String="tie" if predicate in ["remote_executed","auto_restored"] else "main_feeder"
	if predicate in ["inspection","line_upgrade","field_transfer","remote_executed","telemetry","telemetry_reliable","auto_restored","physical_repaired"] and roles.has(line_role):
		var id: int=int(roles[line_role])
		var observation: Dictionary=game.sim.line_observation(id)
		if predicate!="physical_repaired" or observation.get("visibility","") in ["verified","patrol"]: return {"kind":"line","id":id}
	var role := "source"
	if predicate in ["commissioned","communication_built"]: role="root"
	elif predicate in ["trust_restored","isolated_inspected","secure_reliable"]:
		var target: int=int(roles.get("attack_target",-1))
		var status: Dictionary=game.sim.communication_status(target)
		role="attack_target" if status.get("compromised",false) else "customer"
	elif predicate in ["new_customer","pumped_connected","hvdc_connected","coordinated_storage","assessment_started"]: role="node"
	elif predicate in ["reliable","market_reliable","wind_reliable","final_assessment","physical_repaired"]: role="customer"
	if roles.has(role): return {"kind":"building","id":int(roles[role])}
	return {}

func setup(owner_game: Node) -> void:
	game = owner_game
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	body = Shell.build(self,"电力时代战役","战役目录",open_directory,close)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(scroll)
	content = UI.column(scroll,14)
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	load_profile()
	hide()

func load_profile() -> void:
	profile = {"version":1,"unlocked":1,"completed":[],"last_chapter":1,"prologue_seen":false}
	if not FileAccess.file_exists(profile_path): return
	var file := FileAccess.open(profile_path,FileAccess.READ)
	if file == null: return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if not parsed is Dictionary or parsed.get("version") != 1: return
	if not parsed.get("completed") is Array or not parsed.get("prologue_seen") is bool: return
	var done: Array[int] = []
	for id in parsed.completed:
		if not (id is int or id is float) or float(id)!=floorf(float(id)) or int(id)<1 or int(id)>15 or int(id) in done: return
		done.append(int(id))
	var unlocked := 1
	while unlocked in done and unlocked < 15: unlocked += 1
	var last_id: Variant = parsed.get("last_chapter",1)
	if not (last_id is int or last_id is float): return
	profile = {"version":1,"unlocked":unlocked,"completed":done,"last_chapter":clampi(int(last_id),1,unlocked),"prologue_seen":parsed.prologue_seen}

func save_profile() -> void:
	var file := FileAccess.open(profile_path,FileAccess.WRITE)
	if file == null:
		game._notify("无法保存战役解锁进度；当前关仍可继续。",false)
		return
	file.store_string(JSON.stringify(profile,"\t"))

func record_completion() -> void:
	if not game._campaign_active() or not game.sim.campaign.completed: return
	var id := int(game.sim.campaign.chapter_id)
	if id not in profile.completed:
		profile.completed.append(id)
		var unlocked := 1
		while unlocked in profile.completed and unlocked < 15: unlocked += 1
		profile.unlocked = unlocked
		profile.last_chapter = mini(id+1,int(profile.unlocked))
		save_profile()

func _begin(caption: String) -> void:
	game._prepare_center(self)
	game._clear_children(content)
	_label(caption,26,UI.TEAL)
	show()

func _label(caption: String, font_size: int=16, color: Color=UI.TEXT) -> Label:
	var label := UI.label(content,caption,font_size,color)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return label

func open_directory() -> void:
	mode = "directory"
	_begin("从第一盏街灯，到协同运行的电网")
	_label("15 个历史现场 · 建设 → 经营 → 智能化 → 清洁可靠供电",16,UI.MUTED)
	var actions := UI.row(content,10)
	var resume := UI.button(actions,"继续战役",func(): game.continue_campaign(),Vector2(150,40))
	resume.disabled = not FileAccess.file_exists(game.campaign_save_path)
	if game._campaign_active(): UI.button(actions,"返回当前关",close,Vector2(150,40))
	UI.button(actions,"返回沙盘",func(): game.return_to_sandbox(),Vector2(150,40))
	chapter_buttons.clear()
	for chapter in Catalog.chapters():
		var id := int(chapter.id)
		var unlocked := id <= int(profile.unlocked)
		var complete: bool = id in profile.completed
		var card := PanelContainer.new()
		card.add_theme_stylebox_override("panel",UI.style(Color("193b47"),8,Color("355561"),12))
		content.add_child(card)
		var row := UI.row(card,16)
		var timeline:=UI.column(row,4)
		timeline.custom_minimum_size.x=86
		UI.label(timeline,"●" if complete else ("◉" if unlocked else "○"),28,UI.TEAL if unlocked else UI.MUTED)
		UI.label(timeline,str(chapter.years),14,UI.TEAL if unlocked else UI.MUTED)
		var text_box := UI.column(row,6)
		text_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var title := UI.label(text_box,"%02d  %s%s" % [id,chapter.title,"  ✓" if complete else ""],19,UI.TEXT if unlocked else UI.MUTED)
		title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		var location := UI.label(text_box,"%s  ·  %s" % [chapter.place,chapter.years],14,UI.TEAL if unlocked else UI.MUTED)
		location.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		var summary := UI.label(text_box,str(chapter.get("objective","")) if unlocked else "完成前章，继续探索下一种电力能力",14,UI.MUTED)
		summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		var button := UI.button(row,"重玩" if complete else ("进入情景" if unlocked else "待解锁"),func(): request_start(id),Vector2(112,44))
		button.disabled = not unlocked
		chapter_buttons[id] = button

func request_start(id: int) -> void:
	if id<1 or id>int(profile.unlocked):
		game._notify("先完成上一章，再进入这个历史现场。",false)
		return
	if id==1 and not bool(profile.prologue_seen):
		mode = "prologue"
		_begin("序章  ·  从实验到电站  /  约 1 分钟")
		_label("电并不是在第一座发电站建成时才出现。1800 年前后的伏打电堆让持续电流进入实验室；1831 年，法拉第的电磁感应实验为机械能转化成电能打开了道路。",18)
		_label("接下来，你将来到不同国家的历史现场，以当时的工程问题学习供电、调度与经营。地图与工程规模经过游戏化压缩；你操作的数值与规则属于游戏模型。",17,UI.MUTED)
		_label("这段序章只介绍背景，无需完成科学实验。",15,UI.MUTED)
		UI.button(content,"跳过序章，进入 1882 年",func(): _finish_prologue(),Vector2(0,44))
		UI.button(content,"我准备好了，进入第一章",func(): _finish_prologue(),Vector2(0,44))
		return
	game.start_campaign_chapter(id)

func _finish_prologue() -> void:
	profile.prologue_seen = true
	save_profile()
	game.start_campaign_chapter(1)

func open_briefing() -> void:
	mode = "briefing"
	var chapter: Dictionary = game.sim.campaign.chapter()
	_begin("%02d  %s" % [chapter.id,chapter.title])
	_label("%s  ·  %s" % [chapter.place,chapter.years],18,UI.TEAL)
	_label(str(chapter.briefing),19)
	_label("你的任务  ·  "+str(chapter.get("objective","根据任务单完成当地供电工程。")),18,UI.TEXT)
	var steps:=HFlowContainer.new()
	steps.add_theme_constant_override("h_separation",12)
	steps.add_theme_constant_override("v_separation",8)
	content.add_child(steps)
	for entry in Catalog.steps(int(chapter.id)):
		UI.badge(steps,"○ "+str(entry.title),UI.TEAL)
	_label("独立预算与进度 · 正常建设及运营费用 · 完成实际操作与持续考核",14,UI.MUTED)
	UI.button(content,"进入现场  →",func(): close(); game.hud.toggle_popup("missions"),Vector2(0,46))
	UI.button(content,"阅读历史档案",open_archive,Vector2(0,38))

func open_archive() -> void:
	if not game._campaign_active(): return
	mode = "archive"
	var chapter: Dictionary = game.sim.campaign.chapter()
	_begin("历史档案  ·  "+str(chapter.title))
	_label("%s  ·  %s" % [chapter.place,chapter.years],18,UI.TEAL)
	_label(str(chapter.briefing),18)
	_label(str(chapter.debrief),17,UI.MUTED)
	var experiments: Array[String]=optional_experiments(int(chapter.id))
	if not experiments.is_empty():
		_label("选做实验",18,UI.TEAL)
		_label("以下实验使用本关已开放能力，不计必修进度。可在保存当前方案后比较，也可重玩本关。",15,UI.MUTED)
		for experiment in experiments: _label("• "+experiment,16)
	_label("史实来源",18,UI.TEAL)
	for source in chapter.get("sources",[]):
		var link := RichTextLabel.new()
		link.bbcode_enabled = true
		link.fit_content = true
		link.custom_minimum_size.y = 30
		link.text = "[url=%s]%s[/url]" % [source.get("url",""),source.get("title","参考资料")]
		link.meta_clicked.connect(func(url: Variant): OS.shell_open(str(url)))
		content.add_child(link)
	UI.button(content,"返回任务",close,Vector2(0,42))

func optional_experiments(id: int) -> Array[String]:
	match id:
		8: return ["比较抽蓄的 MW 与 MWh：先记录放电功率和剩余能量，再升级一次，观察瞬时能力与持续时长如何变化。", "以现场设置提高保留荷电比例，观察可用备用与日常放电量的取舍；保持自动策略，勿把保留电量模式误当作持续充电。"]
		9: return ["保存开局，分别比较仅用现货与签订十二小时锁价合约的同一时间窗口。核对账本的进口电量、合约费用与净收益；固定承诺用不完仍需付费。"]
		10: return ["为相同负荷分别安排联合循环与快速燃气备用。用现场队提交启停，观察启动等待、实际出力和燃料成本；高效率不能替代即时备用。"]
		15: return ["比较液流与电氢储能：连接后记录额定 MW、MWh、充电量和实际交付量，体会功率、时长与往返损耗。", "在市场储能页尝试低价充电、高价放电，按同一窗口比较净收益；价差必须覆盖损耗与运维。", "为社区储能配置可信削峰后，临时停用一条通信链路。观察本地保供回退，再恢复通信；电力线保持连接。", "比较湿冷与干冷、普通热机与柔性档：通过现场或远程提交，等待执行后核对出力、辅机与费用。"]
	return []

func open_report(victory: bool) -> void:
	mode = "report"
	var chapter: Dictionary = game.sim.campaign.chapter()
	_begin(("工程完成  ·  " if victory else "经营报告  ·  ")+str(chapter.title))
	_label(str(chapter.debrief) if victory else str(game.sim.campaign.failure_reason),19)
	var operating_net := 0.0
	for entry in game.sim.market.ledger: operating_net+=float(entry.get("net",0.0))
	var reliability := float(game.sim.total_served_mwh)/float(game.sim.total_demand_mwh) if float(game.sim.total_demand_mwh)>0.000001 else 1.0
	_label("实际供电 %.1f MWh  ·  累计供电率 %.1f%%  ·  账本运营净收益 ¥%s" % [game.sim.total_served_mwh,reliability*100,game._number(operating_net)],18,UI.TEAL)
	_label("当前资金 ¥%s  ·  %d 座设施  ·  %d 条线路" % [game._number(game.sim.cash),game.sim.buildings.size(),game.sim.lines.size()],17,UI.TEAL)
	var metrics:=UI.row(content,18)
	UI.metric(metrics,"累计供电率",reliability*100,100,"%",UI.TEAL,true,"实际供电 %.1f MWh" % float(game.sim.total_served_mwh)).size_flags_horizontal=Control.SIZE_EXPAND_FILL
	var profit:=UI.column(metrics,3)
	profit.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	UI.label(profit,"运营净收益",14,UI.MUTED)
	UI.label(profit,"%s¥%s" % ["+" if operating_net>=0 else "−",game._number(absf(operating_net))],30,UI.TEAL if operating_net>=0 else UI.RED)
	var history:=VisualChart.new()
	history.mode="profit"
	history.custom_minimum_size=Vector2(0,128)
	history.set_snapshot({"entries":game.sim.market.ledger})
	content.add_child(history)
	if victory:
		record_completion()
		_label("你把这一时代的工程选择变成了真实供电。下一关将从新的现场开始，已完成章节的解锁进度会单独保留。",16,UI.MUTED)
		if int(chapter.id)<15:
			UI.button(content,"前往下一章  →",func(): request_start(int(chapter.id)+1),Vector2(0,46))
		else:
			_label("电力时代战役已完成。你已经掌握建设、调度、经营、通信和恢复的主要系统。",22,UI.TEAL)
	UI.button(content,"重试本关",func(): game.restart_campaign_chapter(),Vector2(0,42))
	UI.button(content,"历史档案",open_archive,Vector2(0,38))
	UI.button(content,"章节目录",open_directory,Vector2(0,38))
	UI.button(content,"留在本关查看电网",close,Vector2(0,38))

func populate_task(box: VBoxContainer) -> void:
	hold_label=null
	hold_gauge=null
	condition_gauges.clear()
	var campaign: RefCounted = game.sim.campaign
	var step: Dictionary = campaign.current_step()
	var signature := "%d:%d" % [campaign.chapter_id,campaign.step_index]
	if signature!=step_signature:
		step_signature = signature
		hint_level = 0
		game.hud.mission_scroll.scroll_vertical=0
		_previous_hold=0
	UI.label(box,"本关步骤 %d / %d" % [mini(int(campaign.step_index)+1,Catalog.steps(int(campaign.chapter_id)).size()),Catalog.steps(int(campaign.chapter_id)).size()],13,UI.MUTED)
	var title := UI.label(box,str(step.get("title","情景运营")),19,UI.TEAL)
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var instruction := UI.label(box,str(step.get("instruction","查看本关报告，或继续观察电网。")),15)
	instruction.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	if float(step.get("hold_hours",0))>0:
		hold_label = UI.label(box,"持续达标 %.1f / %.1f 游戏小时" % [step.get("elapsed_hours",0),step.hold_hours],14,UI.TEAL)
		hold_gauge=UI.metric(box,"连续达标时间",float(step.get("elapsed_hours",0)),float(step.hold_hours),"小时",UI.TEAL)
		hold_gauge.compact=true
		hold_gauge.custom_minimum_size.y=50
		for spec in _condition_specs(step):
			var gauge: Control=UI.metric(box,str(spec.label),float(spec.value),float(spec.max),str(spec.unit),UI.TEAL,true,str(spec.detail))
			gauge.compact=true
			gauge.custom_minimum_size.y=62
			gauge.show_value=str(spec.key) not in ["net","telemetry"]
			condition_gauges[str(spec.key)]=gauge
	interruption_label=UI.label(box,"",14,UI.AMBER)
	interruption_label.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	var why_button:=UI.button(box,"为什么这样做？",func(): pass,Vector2(0,30),true)
	var why := UI.label(box,str(step.get("why","")),14,UI.MUTED)
	why.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	why.hide()
	why_button.toggled.connect(func(value: bool): why.visible=value)
	if not str(step.get("action","")).is_empty():
		var action := str(step.action)
		UI.button(box,"准备完成，开始考核",func(): game._apply(game.sim.campaign_action(action)); game._update_hud(),Vector2(0,38))
	UI.button(box,"定位操作入口",func(): guide_to(str(step.get("ui_target","inspect"))),Vector2(0,34))
	var hints: Array = step.get("hints",[])
	for i in mini(hint_level,hints.size()):
		var hint := UI.label(box,"提示 %d  ·  %s" % [i+1,hints[i]],14,UI.AMBER)
		hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	if hint_level<hints.size():
		UI.button(box,"给我一个提示",func(): hint_level+=1; game.mission_snapshot=""; game._update_hud(),Vector2(0,34))
	UI.button(box,"历史档案与来源",open_archive,Vector2(0,34))
	UI.button(box,"章节目录",open_directory,Vector2(0,34))

func refresh_task_progress() -> void:
	if not is_instance_valid(hold_label) or not game._campaign_active(): return
	var step: Dictionary = game.sim.campaign.current_step()
	hold_label.text="持续达标 %.1f / %.1f 游戏小时" % [step.get("elapsed_hours",0),step.get("hold_hours",0)]
	var elapsed: float=float(step.get("elapsed_hours",0))
	if is_instance_valid(hold_gauge): hold_gauge.configure("连续达标时间",elapsed,float(step.get("hold_hours",1)),"小时",UI.TEAL)
	var shortfalls: Array[String]=[]
	for spec in _condition_specs(step):
		if condition_gauges.has(str(spec.key)) and is_instance_valid(condition_gauges[str(spec.key)]):
			condition_gauges[str(spec.key)].configure(str(spec.label),float(spec.value),float(spec.max),str(spec.unit),UI.TEAL if float(spec.value)>=float(spec.max) else UI.AMBER,true,str(spec.detail))
		if float(spec.value)<float(spec.max): shortfalls.append(str(spec.label))
	if elapsed+0.00001<_previous_hold and is_instance_valid(interruption_label):
		interruption_label.text="连续计时已中断 · "+("、".join(shortfalls) if not shortfalls.is_empty() else "考核条件变化，请核对结果")
	_previous_hold=elapsed

func _condition_specs(step: Dictionary) -> Array:
	var result: Array=[]
	var predicate: String=str(step.get("predicate",""))
	var totals: Dictionary=game.sim.totals
	if predicate in ["reliable","import_reliable","nuclear_reliable","market_reliable","wind_reliable","telemetry_reliable","secure_reliable","final_assessment"]:
		result.append({"key":"supply","label":"当前供电率","value":float(totals.get("reliability",0))*100,"max":98.0,"unit":"%","detail":"目标 ≥98%"})
	if predicate in ["wind_reliable","final_assessment"]:
		var threshold:=50.0 if predicate=="final_assessment" else 35.0
		result.append({"key":"clean","label":"实际清洁供电","value":float(totals.get("renewable_supply_share",0))*100,"max":threshold,"unit":"%","detail":"目标 ≥%.0f%% · 含已知来源储能" % threshold})
	if predicate=="market_reliable":
		result.append({"key":"customers","label":"客户满意度","value":float(game.sim.market.state.satisfaction),"max":60.0,"unit":"%","detail":"目标 ≥60"})
	if predicate=="telemetry_reliable":
		var line_id: int=int(game.sim.campaign.roles.get("main_feeder",-1))
		var fresh: bool=game.sim.line_observation(line_id).get("visibility","")=="verified"
		result.append({"key":"telemetry","label":"主馈线可信遥测","value":1.0 if fresh else 0.0,"max":1.0,"unit":"","detail":"新鲜且可信" if fresh else "需要更新可信观测"})
	if predicate=="final_assessment":
		result.append({"key":"net","label":"窗口运营收益","value":1.0 if game.sim.campaign.assessment_net>=0 else 0.0,"max":1.0,"unit":"","detail":"¥%.0f · 目标不亏损" % game.sim.campaign.assessment_net})
	return result

func guide_to(target: String) -> void:
	var focus: Dictionary=current_focus_target()
	if not focus.is_empty() and game.has_method("focus_target"): game.focus_target(str(focus.kind),int(focus.id))
	match target:
		"cable": game._set_tool("line"); game.hud.close_popups()
		"build":
			var id := int(game.sim.campaign.chapter_id)
			var category: String = "city" if id in [1,7] else ("grid" if id==6 else ("storage" if id==8 else "power"))
			if id==8:
				game.cam_target=game._cell_position(Vector2i(28,28))
				game.zoom=52
				game._update_camera()
			game.hud.toggle_category(category)
		"planning", "research":
			game._open_center("planning")
			var predicate: String=str(game.sim.campaign.current_step().get("predicate",""))
			if predicate in ["remote_facility","coordinated_storage"]:
				var facility_id: int=int(game.sim.campaign.roles.get("source",-1))
				if predicate=="coordinated_storage":
					for building in game.sim.buildings:
						if building.kind=="community_battery": facility_id=int(building.id); break
				if facility_id>=0: game.planning_panel.select_facility(facility_id)
		"market": game._open_center("market")
		"digital":
			game._open_center("network")
			if not focus.is_empty():
				game.digital_panel.inherit_selection(int(focus.id) if focus.kind=="building" else -1,int(focus.id) if focus.kind=="line" else -1)
				game.digital_panel.refresh(true)
				game.digital_panel.tabs.current_tab=1 if focus.kind=="line" else 0
		"statistics": game.hud.toggle_popup("stats")
		_: game.hud.close_popups(); game._notify("已定位当前任务对象；右侧详情只显示已知信息，执行结果请核对回执。")

func close() -> void:
	hide()
	game._update_hud()
