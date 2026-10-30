extends VBoxContainer
## Comparable outcomes from independent worlds, never commands to the live grid.
const UI=preload("res://scripts/ui/ui_kit.gd")
const METRICS=[
	["served_mwh","已供电量","MWh",1.0,"higher"],
	["unserved_mwh","失供电量","MWh",1.0,"lower"],
	["net_cash","净现金变化","¥",1.0,"higher"],
	["max_loading","最高线路利用率","%",100.0,"lower"],
	["min_voltage","最低电压","pu",1.0,"higher"],
	["min_reserve_mw","最低可用功率余量","MW",1.0,"higher"],
	["clean_supply_share","清洁供电参考占比","%",100.0,"higher"],
	["local_carbon_tonnes","本地发电排放","t CO₂",1.0,"lower"],
	["critical_unserved_points","受影响医院负荷点","点",1.0,"lower"],
	["critical_unserved_point_hours","医院失供参考点时","点·h",1.0,"lower"]]
var plans: Array=[]
var plan_titles: Array[String]=[]
var comparison_rows: Array=[]
var shared_maximum:=1.0
var stale:=false
var validity: Label
var table: GridContainer
var charts: GridContainer

class ScenarioChart extends Control:
	var rows: Array=[]
	var maximum:=1.0
	var caption:=""
	func _init() -> void:
		custom_minimum_size=Vector2(0,180)
		size_flags_horizontal=Control.SIZE_EXPAND_FILL
		mouse_filter=Control.MOUSE_FILTER_STOP
		resized.connect(queue_redraw)
	func _draw() -> void:
		var font:=get_theme_default_font()
		draw_style_box(UI.style(Color("102630"),6),Rect2(Vector2.ZERO,size))
		draw_string(font,Vector2(10,22),caption,HORIZONTAL_ALIGNMENT_LEFT,size.x-20,14,UI.TEXT)
		var plot:=Rect2(40,38,maxf(1,size.x-56),maxf(1,size.y-68))
		for mark in 3:
			var amount:=float(mark)*.5
			var y:=plot.end.y-plot.size.y*amount
			draw_line(Vector2(plot.position.x,y),Vector2(plot.end.x,y),Color(.6,.7,.8,.16))
			draw_string(font,Vector2(5,y+4),"%.0f" % (maximum*amount),HORIZONTAL_ALIGNMENT_LEFT,32,12,UI.MUTED)
		var channels:=["demand","served","unserved"]
		var colors:=[UI.AMBER,UI.TEAL,UI.RED]
		for index in range(1,rows.size()):
			var x1:=plot.position.x+float(index-1)/maxf(1,rows.size()-1)*plot.size.x
			var x2:=plot.position.x+float(index)/maxf(1,rows.size()-1)*plot.size.x
			for channel in channels.size():
				var before:=float(rows[index-1].get(channels[channel],0.0))
				var after:=float(rows[index].get(channels[channel],0.0))
				draw_line(Vector2(x1,plot.end.y-before/maximum*plot.size.y),Vector2(x2,plot.end.y-after/maximum*plot.size.y),colors[channel],2,true)
		if not rows.is_empty():
			draw_string(font,Vector2(plot.position.x,plot.end.y+20),"+1 h",HORIZONTAL_ALIGNMENT_LEFT,70,12,UI.MUTED)
			draw_string(font,Vector2(maxf(plot.position.x,plot.end.x-48),plot.end.y+20),"+%d h" % rows.size(),HORIZONTAL_ALIGNMENT_LEFT,48,12,UI.MUTED)
	func _gui_input(event: InputEvent) -> void:
		if event is InputEventMouseMotion and not rows.is_empty():
			var index:=clampi(roundi((event.position.x-40)/maxf(1,size.x-56)*float(rows.size()-1)),0,rows.size()-1)
			var row: Dictionary=rows[index]
			tooltip_text="%s · +%d h\n需求 %.1f MW · 已供 %.1f MW · 失供 %.1f MW" % [caption,index+1,row.demand,row.get("served",0.0),row.unserved]

func _init() -> void:
	size_flags_horizontal=Control.SIZE_EXPAND_FILL
	add_theme_constant_override("separation",10)
	resized.connect(_adapt)

static func rows_for(results: Array) -> Array:
	if results.size()<2: return []
	var rows: Array=[]
	for spec in METRICS:
		if not results[0].has(spec[0]) or not results[1].has(spec[0]): continue
		var current: float=float(results[0][spec[0]])*float(spec[3])
		var plan: float=float(results[1][spec[0]])*float(spec[3])
		var contingency: Variant=float(results[2][spec[0]])*float(spec[3]) if results.size()>2 and results[2].has(spec[0]) else null
		rows.append({"id":spec[0],"label":spec[1],"unit":spec[2],"current":current,"plan":plan,"delta":plan-current,
			"contingency":contingency,"contingency_delta":float(contingency)-plan if contingency!=null else null,"preferred":spec[4],
			"delta_unit":"百分点" if spec[2]=="%" else spec[2]})
	return rows

func set_results(results: Array,titles: Array=[]) -> void:
	for child in get_children(): remove_child(child); child.queue_free()
	plans=results.duplicate(true)
	plan_titles.clear()
	for index in 3: plan_titles.append(str(titles[index]) if index<titles.size() else ["当前","计划","退出情景"][index])
	comparison_rows=rows_for(plans)
	stale=false
	validity=null; table=null; charts=null
	if plans.is_empty(): hide(); return
	show()
	validity=_text(self,"")
	set_stale(false)
	_text(self,"%s → %s：差值为后者减前者；%s括号内与%s比较。颜色同时配改善／代价文字。" % [plan_titles[0],plan_titles[1],plan_titles[2],plan_titles[1]],UI.MUTED)
	for index in plans.size():
		var quote: Dictionary=plans[index].get("maintenance_quote",{})
		if quote.is_empty(): continue
		_text(self,"%s · 工单参考费用 ¥%.0f · 路程 %.0f 分钟 / 作业 %.0f 分钟 · 备件 %d · %s\n工单费用计入现金差分；以上时长不含等待空闲队伍。不会自动派遣真实现场队。" % [plan_titles[mini(index,2)],float(quote.cost),float(quote.travel_hours)*60,float(quote.work_hours)*60,int(quote.spares),"等待现场队" if quote.initial_status=="queued" else "现场队已在副本出发"],UI.MUTED)
	table=GridContainer.new()
	table.columns=5
	table.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	table.add_theme_constant_override("h_separation",12)
	table.add_theme_constant_override("v_separation",9)
	add_child(table)
	for title in ["共同口径",plan_titles[0],plan_titles[1],"变化",plan_titles[2]]: _text(table,title,UI.TEAL)
	for row in comparison_rows:
		_text(table,"%s\n%s" % [row.label,row.unit])
		_text(table,_number(float(row.current),str(row.unit)))
		_text(table,_number(float(row.plan),str(row.unit)))
		var improved: bool=float(row.delta)>0.00001 if row.preferred=="higher" else float(row.delta)<-0.00001
		var unchanged: bool=absf(float(row.delta))<0.00001
		var note: String="持平" if unchanged else ("改善" if improved else "代价")
		_text(table,"%s\n%s · %s" % [_signed_delta(float(row.delta),str(row.unit)),row.delta_unit,note],UI.MUTED if unchanged else (UI.TEAL if improved else UI.AMBER))
		_text(table,"%s\n(%s %s)" % [_number(float(row.contingency),str(row.unit)),_signed_delta(float(row.contingency_delta),str(row.unit)),row.delta_unit] if row.contingency!=null else "—")
	_text(self,"三图共用 MW 零基线及同一预测时段：需求 橙 · 已供 青 · 失供 红。曲线为每小时端点，能量与失供点时见上表。",UI.MUTED)
	shared_maximum=1.0
	for result in plans:
		for row in result.rows: shared_maximum=maxf(shared_maximum,maxf(float(row.demand),float(row.get("served",0.0))))
	charts=GridContainer.new()
	charts.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	charts.add_theme_constant_override("h_separation",12)
	charts.add_theme_constant_override("v_separation",10)
	add_child(charts)
	for index in plans.size():
		var chart:=ScenarioChart.new()
		chart.rows=plans[index].rows.duplicate(true)
		chart.maximum=shared_maximum
		chart.caption=plan_titles[mini(index,2)]
		charts.add_child(chart)
	_adapt()

func set_stale(value: bool,reason: String="运行状态已变化") -> void:
	stale=value
	if validity==null or plans.is_empty(): return
	var first: Dictionary=plans[0]
	validity.text="已过期 · %s；请重新比较。以下保留旧方案供回看。" % reason if stale else "同一基准 D%d %02d:%02d · 未来%d小时 · 15分钟参考步长 · 仅推演，尚未提交" % [int(first.get("source_day",1)),int(first.get("source_time_hours",0)),int(fposmod(float(first.get("source_time_hours",0)),1.0)*60),int(first.get("horizon_hours",24))]
	validity.add_theme_color_override("font_color",UI.AMBER if stale else UI.TEAL)

func _adapt() -> void:
	if charts!=null: charts.columns=3 if size.x>=870 else 1

static func _number(value: float,unit: String) -> String:
	return "%.3f" % value if unit=="pu" else ("%.0f" % value if unit in ["¥","点"] else "%.2f" % value)

static func _signed_delta(value: float,unit: String) -> String:
	return "%+.3f" % value if unit=="pu" else "%+.2f" % value

func _text(parent: Node,caption: String,color: Color=UI.TEXT) -> Label:
	var label:=UI.label(parent,caption,13,color)
	label.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	return label
