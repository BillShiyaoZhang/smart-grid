extends VBoxContainer
## Advanced operations share the existing centre's draft store and commit path.
const UI=preload("res://scripts/ui/ui_kit.gd")
var game: Node
var commit: Callable
var drafts: RefCounted
var section: OptionButton
var panes: Array[Control]=[]
var status: Label
var activation: GridContainer
var guide: Label
var commissioning: Dictionary={}
var target_type: OptionButton
var asset_picker: OptionButton
var maintenance_priority: OptionButton
var asset_info: Label
var maintenance_buttons: Dictionary={}
var spare_count: SpinBox
var jobs_picker: OptionButton
var job_priority: OptionButton
var job_info: Label
var line_picker: OptionButton
var tier: OptionButton
var delay: SpinBox
var line_info: Label
var station_picker: OptionButton
var station_capacity: SpinBox
var zone: LineEdit
var engineering_info: Label
var customer_picker: OptionButton
var fields: Dictionary={}
var customer_info: Label
var response_kind: OptionButton
var response_fraction: SpinBox
var response_hours: SpinBox
var microgrid_name: LineEdit
var member_list: ItemList
var critical_list: ItemList
var microgrid_picker: OptionButton
var microgrid_method: OptionButton
var microgrid_info: Label
var _signatures: Dictionary={}
var _loading:=false
var _line_loaded:=-1
var _station_loaded:=-1
var _customer_loaded:=-1

func setup(owner_game: Node,on_commit: Callable,draft_store: RefCounted) -> void:
	game=owner_game
	commit=on_commit
	drafts=draft_store
	size_flags_horizontal=Control.SIZE_EXPAND_FILL
	add_theme_constant_override("separation",12)
	guide=_text(self,"区域负荷规划研究后可逐项投运；用户侧协调还需要 SCADA。投运后的规则持续生效。")
	activation=_grid(self,3)
	for spec in [["lifecycle","投运资产风险管理"],["engineering","投运输配电管理"],["customers","投运用户侧协调"]]:
		commissioning[spec[0]]=UI.button(activation,spec[1],_commission.bind(str(spec[0])))
	status=_text(self,"")
	section=_picker(self,"管理内容",[["设备寿命与现场队",0],["输配电与保护",1],["街区能源与需求响应",2],["微电网分区",3]])
	section.item_selected.connect(_select_section)
	_build_lifecycle()
	_build_engineering()
	_build_customers()
	_build_microgrids()
	_select_section(0)

func _text(parent: Node,text: String,color: Color=UI.MUTED) -> Label:
	var label:=UI.label(parent,text,14,color)
	label.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	return label

func _pane() -> VBoxContainer:
	var pane:=UI.column(self,12)
	pane.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	panes.append(pane)
	return pane

func _grid(parent: Node,count: int=2) -> GridContainer:
	var grid:=GridContainer.new()
	grid.columns=count
	grid.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation",12)
	grid.add_theme_constant_override("v_separation",10)
	parent.add_child(grid)
	grid.child_entered_tree.connect(func(child: Node):
		if child is Control: child.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	)
	grid.resized.connect(func(): grid.columns=1 if grid.size.x<850 else count)
	return grid

func _picker(parent: Node,caption: String,items: Array=[]) -> OptionButton:
	var body:=UI.column(parent,4)
	body.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	_text(body,caption)
	var picker:=OptionButton.new()
	picker.fit_to_longest_item=false
	picker.clip_text=true
	picker.custom_minimum_size=Vector2(0,36)
	picker.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	body.add_child(picker)
	for item in items: picker.add_item(str(item[0]),int(item[1]))
	return picker

func _number(parent: Node,caption: String,minimum: float,maximum: float,step_value: float,value: float) -> SpinBox:
	var body:=UI.column(parent,4)
	body.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	_text(body,caption)
	var spin:=SpinBox.new()
	spin.min_value=minimum
	spin.max_value=maximum
	spin.step=step_value
	spin.value=value
	spin.custom_minimum_size=Vector2(0,36)
	spin.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	body.add_child(spin)
	return spin

func _line_edit(parent: Node,caption: String,placeholder: String="") -> LineEdit:
	var body:=UI.column(parent,4)
	body.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	_text(body,caption)
	var edit:=LineEdit.new()
	edit.placeholder_text=placeholder
	edit.custom_minimum_size=Vector2(0,36)
	edit.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	edit.max_length=40
	body.add_child(edit)
	return edit

func _build_lifecycle() -> void:
	var pane:=_pane()
	var columns:=_grid(pane)
	var assets:=UI.card(columns)
	_text(assets,"设备状态与检修",UI.TEXT)
	target_type=_picker(assets,"设备类别",[["设施",0],["电力线路",1]])
	asset_picker=_picker(assets,"选择设备")
	target_type.item_selected.connect(func(_i: int): _signatures.erase("assets"); refresh())
	asset_picker.item_selected.connect(func(_i: int): refresh())
	asset_info=_text(assets,"")
	maintenance_priority=_picker(assets,"新任务优先级",[["常规",0],["优先",1],["关键负荷",2]])
	var actions:=_grid(assets)
	for spec in [["inspect","现场巡检"],["service","计划保养"],["overhaul","部件大修"],["replace","设备更换"]]:
		maintenance_buttons[spec[0]]=UI.button(actions,spec[1],_maintain.bind(str(spec[0])))
	_text(assets,"巡检只核实状态；保养恢复部分健康；大修与更换处理故障。除巡检外，现场施工会停运设备。")
	var queue:=UI.card(columns)
	_text(queue,"现场队与关键备件",UI.TEXT)
	spare_count=_number(queue,"采购备件数量 · ¥700/件",1,20,1,1)
	UI.button(queue,"采购关键备件",func(): _apply(game.sim.expansion_action("spares",{"count":int(spare_count.value)})))
	jobs_picker=_picker(queue,"排队 / 在途任务")
	jobs_picker.item_selected.connect(func(_i: int): refresh())
	job_info=_text(queue,"")
	job_priority=_picker(queue,"调整排队优先级",[["常规",0],["优先",1],["关键负荷",2]])
	UI.button(queue,"更新任务优先级",func(): _apply(game.sim.expansion_action("priority",{"id":_id(jobs_picker),"priority":_id(job_priority)})))
	UI.button(queue,"取消未出发任务并退款",func(): _apply(game.sim.expansion_action("cancel_maintenance",{"id":_id(jobs_picker)})))

func _build_engineering() -> void:
	var pane:=_pane()
	engineering_info=_text(pane,"")
	var columns:=_grid(pane)
	var lines:=UI.card(columns)
	line_picker=_picker(lines,"电力线路")
	line_picker.item_selected.connect(func(_i: int): _load_line())
	tier=_picker(lines,"线路电压等级",[["配电",0],["输电",1]])
	delay=_number(lines,"本地保护延时倍率",0.25,2.0,0.05,1.0)
	tier.item_selected.connect(func(_i: int): _remember_line())
	delay.value_changed.connect(func(_v: float): _remember_line())
	line_info=_text(lines,"")
	UI.button(lines,"应用线路等级与保护",_apply_line)
	UI.button(lines,"重置本线路草案",func(): drafts.reset(_line_key(),_effective_line()); _load_line(true))
	_text(lines,"输电改造降低长距离压降和损耗，不直接提高线路热容量；不同电压等级通过变电站衔接。")
	UI.button(lines,"启动所选支路故障隔离演练",_fault_drill)
	_text(lines,"演练会真实损坏并隔离线路，请准备备用路径和抢修费用。",UI.AMBER)
	var stations:=UI.card(columns)
	station_picker=_picker(stations,"变电站")
	station_picker.item_selected.connect(func(_i: int): _load_station())
	station_capacity=_number(stations,"变电额定容量 · MW",10,500,1,40)
	zone=_line_edit(stations,"保护分区名称","如：东区馈线")
	station_capacity.value_changed.connect(func(_v: float): _remember_station())
	zone.text_changed.connect(func(_v: String): _remember_station())
	UI.button(stations,"应用变电容量与保护分区",_apply_station)
	UI.button(stations,"重置本变电站草案",func(): drafts.reset(_station_key(),_effective_station()); _load_station(true))
	_text(stations,"增容按新增 MW 付费。电压、容量和保护采用经营近似，可在规划推演中比较改造结果。")

func _build_customers() -> void:
	var pane:=_pane()
	customer_picker=_picker(pane,"用户街区")
	customer_picker.item_selected.connect(func(_i: int): _load_customer())
	customer_info=_text(pane,"")
	var columns:=_grid(pane)
	var hardware:=UI.card(columns)
	for spec in [["metered","安装智能电表 · 首次 ¥2,000"],["consent","用户授权参与聚合协调"],["smart","按电价与期限智能充电"],["grid_forming","用户侧电池具备构网能力"]]:
		var check:=CheckButton.new()
		check.text=str(spec[1])
		check.size_flags_horizontal=Control.SIZE_EXPAND_FILL
		hardware.add_child(check)
		fields[spec[0]]=check
		check.toggled.connect(func(_v: bool): _remember_customer())
	for spec in [["pv_mw","屋顶光伏 · MW",100,0.5],["battery_mwh","用户侧储能容量 · MWh",500,1],["battery_mw","用户侧储能功率 · MW",100,0.5],["participation","签约参与比例",1,0.05]]:
		var spin:=_number(hardware,str(spec[1]),0,float(spec[2]),float(spec[3]),0.5 if spec[0]=="participation" else 0.0)
		fields[spec[0]]=spin
		spin.value_changed.connect(func(_v: float): _remember_customer())
	var flexibility:=UI.card(columns)
	for spec in [["ev_mw","充电设施功率 · MW",100,0.5,0],["ev_target_mwh","每日充电需求 · MWh",500,1,0],["deadline_hour","每天充电完成时刻",23,1,7]]:
		var spin:=_number(flexibility,str(spec[1]),0,float(spec[2]),float(spec[3]),float(spec[4]))
		fields[spec[0]]=spin
		spin.value_changed.connect(func(_v: float): _remember_customer())
	UI.button(flexibility,"应用街区能源方案",_apply_customer)
	UI.button(flexibility,"重置本街区草案",func(): drafts.reset(_customer_key(),_effective_customer()); _load_customer(true))
	response_kind=_picker(flexibility,"需求响应方式",[["移峰 · 结束后回补",0],["削减 · 支付较高补偿",1]])
	response_fraction=_number(flexibility,"响应比例",0.05,0.5,0.05,0.2)
	response_hours=_number(flexibility,"响应持续小时",0.25,4,0.25,2)
	UI.button(flexibility,"签发所选街区需求响应",func(): _apply(game.sim.expansion_action("response",{"id":_id(customer_picker),"kind":"shift" if response_kind.selected==0 else "curtail","fraction":response_fraction.value,"hours":response_hours.value})))
	_text(pane,"屋顶光伏先供本地、富余电量进入电网；电池必须实际充电。协调和需求响应需要授权、可信通信与新鲜观测，失联后采用本地运行方式。")

func _build_microgrids() -> void:
	var pane:=_pane()
	microgrid_name=_line_edit(pane,"新微电网名称","如：医院应急供电区")
	var columns:=_grid(pane)
	var members:=UI.card(columns)
	_text(members,"选择分区成员 · 可多选",UI.TEXT)
	member_list=_multi_list(members)
	var critical:=UI.card(columns)
	_text(critical,"选择关键负荷 · 必须同时属于分区",UI.TEXT)
	critical_list=_multi_list(critical)
	UI.button(pane,"登记所选微电网分区",_define_microgrid)
	microgrid_picker=_picker(pane,"已有微电网")
	microgrid_picker.item_selected.connect(func(_i: int): refresh())
	microgrid_method=_picker(pane,"边界开关执行方式",[["现场队 · ¥350",0],["可信远程开关",1]])
	var actions:=_grid(pane)
	UI.button(actions,"安排微电网离网",_switch_microgrid.bind(true))
	UI.button(actions,"安排微电网重联",_switch_microgrid.bind(false))
	microgrid_info=_text(pane,"")
	_text(pane,"离网会断开分区边界。需要可启动电源或有电量的构网储能，先恢复关键负荷，再恢复普通负荷；远程切换到达时重新验证通信。")

func _multi_list(parent: Node) -> ItemList:
	var list:=ItemList.new()
	list.select_mode=ItemList.SELECT_MULTI
	list.custom_minimum_size=Vector2(0,170)
	list.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	parent.add_child(list)
	return list

func _select_section(index: int) -> void:
	for i in panes.size(): panes[i].visible=i==index

func _id(picker: OptionButton) -> int:
	return picker.get_item_id(picker.selected) if picker.selected>=0 else -1

func inherit_selection(facility_id: int,line_id: int=-1) -> void:
	# Retain each object's draft before changing any picker or target category.
	capture_drafts()
	if line_id>=0 and not game.sim.get_line(line_id).is_empty():
		target_type.select(1)
		_signatures.erase("assets")
		refresh()
		_select_id(asset_picker,line_id)
		_select_id(line_picker,line_id)
	elif facility_id>=0 and not game.sim.get_building(facility_id).is_empty():
		target_type.select(0)
		_signatures.erase("assets")
		refresh()
		_select_id(asset_picker,facility_id)
		_select_id(customer_picker,facility_id)
		_select_id(station_picker,facility_id)
	refresh()

func _select_id(picker: OptionButton,id: int) -> void:
	for i in picker.item_count:
		if picker.get_item_id(i)==id:
			if picker.selected!=i:
				picker.select(i)
				picker.item_selected.emit(i)
			return

func _fill(picker: OptionButton,key: String,rows: Array) -> void:
	var signature:=str(rows)
	if _signatures.get(key,"")==signature: return
	var selected:=_id(picker)
	picker.clear()
	for row in rows: picker.add_item(str(row[0]),int(row[1]))
	for index in picker.item_count:
		if picker.get_item_id(index)==selected: picker.select(index); break
	_signatures[key]=signature

func _commission(system: String) -> void:
	_apply(game.sim.commission_expansion(system))

func _apply(result: Dictionary) -> void:
	if result.get("ok",false): game.sim._refresh()
	commit.call(result)

func _maintain(action: String) -> void:
	_apply(game.sim.expansion_action("maintenance",{"target_type":"facility" if target_type.selected==0 else "line","id":_id(asset_picker),"action":action,"priority":_id(maintenance_priority)}))

func _line_key() -> String: return "operations_line_%d" % _id(line_picker)
func _station_key() -> String: return "operations_station_%d" % _id(station_picker)
func _customer_key() -> String: return "operations_customer_%d" % _id(customer_picker)

func _effective_line() -> Dictionary:
	var row: Dictionary=game.sim.engineering.line_settings.get(str(_id(line_picker)),{})
	return {"tier":str(row.get("tier","distribution")),"delay":float(row.get("delay",1.0))}

func _effective_station() -> Dictionary:
	var id:=_id(station_picker)
	var station: Dictionary=game.sim.get_building(id)
	var row: Dictionary=game.sim.engineering.substation_settings.get(str(id),{})
	return {"capacity":float(row.get("capacity",station.get("capacity",40.0))),"zone":str(row.get("zone","馈线区 %d" % id))}

func _effective_customer() -> Dictionary:
	var row: Dictionary=game.sim.customers.devices.get(str(_id(customer_picker)),{})
	var result: Dictionary={}
	for key in fields:
		var fallback: Variant=false if fields[key] is CheckButton else (0.5 if key=="participation" else (7.0 if key=="deadline_hour" else 0.0))
		result[key]=row.get(key,fallback)
	return result

func _remember_line() -> void:
	if _loading or _id(line_picker)<0: return
	drafts.retain(_line_key(),_effective_line(),{"tier":"distribution" if tier.selected==0 else "transmission","delay":delay.value})

func _remember_station() -> void:
	if _loading or _id(station_picker)<0: return
	drafts.retain(_station_key(),_effective_station(),{"capacity":station_capacity.value,"zone":zone.text})

func _remember_customer() -> void:
	if _loading or _id(customer_picker)<0: return
	var edited: Dictionary={}
	for key in fields: edited[key]=fields[key].button_pressed if fields[key] is CheckButton else fields[key].value
	drafts.retain(_customer_key(),_effective_customer(),edited)

func capture_drafts() -> void:
	_remember_line()
	_remember_station()
	_remember_customer()

func _load_line(force: bool=false) -> void:
	var id:=_id(line_picker)
	if not force and id==_line_loaded: return
	_loading=true
	var values: Dictionary=drafts.retain(_line_key(),_effective_line())
	tier.select(0 if values.tier=="distribution" else 1)
	delay.value=float(values.delay)
	_line_loaded=id
	_loading=false

func _load_station(force: bool=false) -> void:
	var id:=_id(station_picker)
	if not force and id==_station_loaded: return
	_loading=true
	var values: Dictionary=drafts.retain(_station_key(),_effective_station())
	station_capacity.value=float(values.capacity)
	zone.text=str(values.zone)
	_station_loaded=id
	_loading=false

func _load_customer(force: bool=false) -> void:
	var id:=_id(customer_picker)
	if not force and id==_customer_loaded: return
	_loading=true
	var values: Dictionary=drafts.retain(_customer_key(),_effective_customer())
	for key in fields:
		if fields[key] is CheckButton: fields[key].set_pressed_no_signal(bool(values[key]))
		else: fields[key].value=float(values[key])
	_customer_loaded=id
	_loading=false

func _apply_line() -> void:
	_remember_line()
	var result: Dictionary=game.sim.engineering.configure_line(game.sim,_id(line_picker),"distribution" if tier.selected==0 else "transmission",delay.value)
	if result.ok: drafts.reset(_line_key(),_effective_line())
	_apply(result)

func _apply_station() -> void:
	_remember_station()
	var result: Dictionary=game.sim.engineering.configure_substation(game.sim,_id(station_picker),station_capacity.value,zone.text)
	if result.ok: drafts.reset(_station_key(),_effective_station())
	_apply(result)

func _apply_customer() -> void:
	_remember_customer()
	var result: Dictionary=game.sim.expansion_action("customer",{"id":_id(customer_picker),"settings":drafts.values.get(_customer_key(),{})})
	if result.ok: drafts.reset(_customer_key(),_effective_customer())
	_apply(result)

func _fault_drill() -> void:
	_apply(game.sim.engineering.trip_fault(game.sim,_id(line_picker)))

func _list_ids(list: ItemList) -> Array:
	var ids: Array=[]
	for index in list.get_selected_items(): ids.append(int(list.get_item_metadata(index)))
	return ids

func _define_microgrid() -> void:
	_apply(game.sim.customers.define_microgrid(game.sim,microgrid_name.text,_list_ids(member_list),_list_ids(critical_list)))

func _switch_microgrid(island: bool) -> void:
	_apply(game.sim.customers.set_microgrid(game.sim,_id(microgrid_picker),island,"field" if microgrid_method.selected==0 else "remote"))

func reset_session() -> void:
	_signatures.clear()
	_line_loaded=-1
	_station_loaded=-1
	_customer_loaded=-1
	_loading=true
	target_type.select(0)
	section.select(0)
	_select_section(0)
	microgrid_name.text=""
	member_list.deselect_all()
	critical_list.deselect_all()
	_loading=false

func refresh() -> void:
	var sim: RefCounted=game.sim
	var ready: bool=sim.evolution.has_technology("regional_planning") and not sim.campaign.active
	var all_running: bool=sim.lifecycle.enabled and sim.engineering.enabled and sim.customers.enabled
	activation.visible=not all_running
	guide.visible=not all_running
	for key in commissioning:
		var module: RefCounted=sim.get(key)
		commissioning[key].disabled=module.enabled or not ready or (key=="customers" and not sim.evolution.has_technology("scada"))
		commissioning[key].text={"lifecycle":"资产风险管理已投运" if module.enabled else "投运资产风险管理","engineering":"输配电管理已投运" if module.enabled else "投运输配电管理","customers":"用户侧协调已投运" if module.enabled else "投运用户侧协调"}[key]
	status.text="现场队 %d / 2 · 关键备件 %d · 投运后规则持续生效，配置草案需应用。" % [sim.active_repairs(),sim.lifecycle.spares]
	var facilities: Array=[]
	var customers: Array=[]
	var stations: Array=[]
	for b in sim.buildings:
		var row: Array=["%02d · %s" % [b.id,b.name],int(b.id)]
		facilities.append(row)
		if b.kind in ["home","factory","hospital"]: customers.append(row)
		if b.kind=="substation": stations.append(row)
	var lines: Array=[]
	for line in sim.lines: lines.append(["E%02d · %d ↔ %d" % [line.id,line.a,line.b],int(line.id)])
	_fill(asset_picker,"assets",facilities if target_type.selected==0 else lines)
	_fill(line_picker,"lines",lines)
	_fill(station_picker,"stations",stations)
	_fill(customer_picker,"customers",customers)
	_load_line()
	_load_station()
	_load_customer()
	_refresh_assets()
	_refresh_engineering()
	_refresh_customers()
	_refresh_microgrids(facilities,customers)

func _refresh_assets() -> void:
	var sim: RefCounted=game.sim
	var report: Dictionary=sim.lifecycle.report(sim)
	var target: String="facility" if target_type.selected==0 else "line"
	asset_info.text="尚无当前可信状态，请安装遥测或安排现场巡检。"
	for row in report.assets:
		if row.target_type!=target or int(row.id)!=_id(asset_picker): continue
		asset_info.text="设备年龄 %.1f 小时 · %s\n健康 %s · 每小时故障风险 %s\n储能健康 %s · 累计吞吐 %s" % [row.age_hours,"当前可信观测" if row.current_verified else ("上次巡检记录" if row.health!=null else "状态待核实"),"%.1f%%" % float(row.health) if row.health!=null else "未知","%.2f%%" % (float(row.risk_per_hour)*100.0) if row.risk_per_hour!=null else "未知","%.2f%%" % float(row.soh) if row.soh!=null else "待核实 / 不适用","%.1f MWh" % float(row.throughput_mwh) if row.throughput_mwh!=null else "待核实 / 不适用"]
	for action in maintenance_buttons:
		var quote: Dictionary=sim.lifecycle.quote(sim,target,_id(asset_picker),str(action))
		maintenance_buttons[action].disabled=not bool(report.enabled) or _id(asset_picker)<0
		maintenance_buttons[action].tooltip_text=str(quote.message)
	var rows: Array=[]
	for job in report.jobs: rows.append(["#%d · %s #%d · %s" % [job.id,"设施" if job.target_type=="facility" else "线路",job.target_id,{"queued":"排队","travel":"出行","work":"施工"}[job.status]],int(job.id)])
	_fill(jobs_picker,"jobs",rows)
	job_info.text="当前没有现场维护任务。"
	for job in report.jobs:
		if int(job.id)==_id(jobs_picker): job_info.text="%s · 优先级 %d\n出行剩余 %.1f 分钟 · 施工剩余 %.1f 分钟\n已支付 ¥%.0f · 已预留备件 %d" % [{"inspect":"现场巡检","service":"计划保养","overhaul":"部件大修","replace":"设备更换"}.get(str(job.action),"现场维护"),job.priority,float(job.travel_remaining)*60.0,float(job.work_remaining)*60.0,job.cost,job.spares]

func _refresh_engineering() -> void:
	var report: Dictionary=game.sim.engineering.report(game.sim)
	engineering_info.text="%s · 网络损耗 %.2f MW · 已核实最低电压 %.3f p.u. · 已核实低电压设施 %d" % ["输配电约束运行中" if report.enabled else "输配电约束尚未投运",report.loss_mw,report.minimum_known_voltage,report.known_low_voltage]
	line_info.text="未应用草案" if drafts.dirty(_line_key()) else "当前线路配置已生效"

func _refresh_customers() -> void:
	var report: Dictionary=game.sim.customers.report(game.sim)
	customer_info.text="街区尚未接入。安装电表后可部署光伏、储能与充电服务。"
	for row in report.customers:
		if int(row.id)!=_id(customer_picker): continue
		customer_info.text="%s · 用户侧电量 %s · 待完成充电 %s\n移峰待回补 %s · 疲劳 %s · 累计补偿 ¥%.0f · 充电违约 %.2f MWh\n%s" % ["可信协同就绪" if row.controllable else "采用本地运行方式",_reading(row.energy_mwh,"MWh"),_reading(row.ev_remaining_mwh,"MWh"),_reading(row.shift_debt_mwh,"MWh"),_reading(row.fatigue,"%",100.0),row.compensation,row.missed_ev_mwh,"未应用草案" if drafts.dirty(_customer_key()) else "当前街区方案已生效"]

func _reading(value: Variant,unit: String,multiplier: float=1.0) -> String:
	return "未知" if value==null else "%.2f %s" % [float(value)*multiplier,unit]

func _refresh_microgrids(facilities: Array,customers: Array) -> void:
	for spec in [[member_list,"members",facilities],[critical_list,"critical",customers]]:
		var list: ItemList=spec[0]
		var key: String=str(spec[1])
		if _signatures.get(key,"")==str(spec[2]): continue
		var selected:=_list_ids(list)
		list.clear()
		for row in spec[2]:
			var index:=list.add_item(str(row[0]))
			list.set_item_metadata(index,int(row[1]))
			if int(row[1]) in selected: list.select(index,false)
		_signatures[key]=str(spec[2])
	var report: Dictionary=game.sim.customers.report(game.sim)
	var rows: Array=[]
	for grid in report.microgrids: rows.append(["%d · %s" % [grid.id,grid.name],int(grid.id)])
	_fill(microgrid_picker,"microgrids",rows)
	microgrid_info.text="登记分区后，可安排离网和重联。"
	for grid in report.microgrids:
		if int(grid.id)!=_id(microgrid_picker): continue
		microgrid_info.text="%s · %s · 成员 %d · 关键负荷 %d\n%s\n%s" % [grid.name,"孤岛运行" if grid.islanded else "并网运行",grid.members.size(),grid.critical_ids.size(),["等待可启动电源","关键负荷恢复中","分阶段恢复完成"][int(grid.stage)],grid.receipt]
