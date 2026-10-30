extends Control
## A common MW scale, with a demand uncertainty band. Energy stays in tooltips.
var rows: Array=[]
func _init() -> void:
	custom_minimum_size=Vector2(0,230)
	mouse_filter=Control.MOUSE_FILTER_STOP
func set_rows(value: Array) -> void:
	rows=value.duplicate(true)
	queue_redraw()
func _draw() -> void:
	var font:=get_theme_default_font()
	var area:=Rect2(55,44,maxf(1,size.x-74),maxf(1,size.y-78))
	draw_style_box(preload("res://scripts/ui/ui_kit.gd").style(Color("102630")),Rect2(Vector2.ZERO,size))
	draw_string(font,Vector2(14,25),"需求及范围 · 橙     净负荷 · 青     外购 · 蓝  [MW]",HORIZONTAL_ALIGNMENT_LEFT,-1,14,Color("e2e8dc"))
	if rows.is_empty():
		draw_string(font,Vector2(62,110),"点击计算，查看未来24小时",HORIZONTAL_ALIGNMENT_LEFT,-1,16,Color("a4bbc0"))
		return
	var maximum:=1.0
	for row in rows: maximum=maxf(maximum,float(row.demand_high))
	for i in 5:
		var y:=area.end.y-area.size.y*float(i)/4.0
		draw_line(Vector2(area.position.x,y),Vector2(area.end.x,y),Color(.6,.7,.8,.16))
		draw_string(font,Vector2(8,y+4),"%.0f" % (maximum*float(i)/4),HORIZONTAL_ALIGNMENT_LEFT,-1,13,Color("a4bbc0"))
	var colors:=[Color("efbb7d"),Color("77dbc0"),Color("81c9ee")]
	var channels:=["demand","net_load","imports"]
	for i in rows.size():
		var x:=area.position.x+area.size.x*float(i)/maxf(1,rows.size()-1)
		var high:=area.end.y-float(rows[i].demand_high)/maximum*area.size.y
		var low:=area.end.y-float(rows[i].demand_low)/maximum*area.size.y
		draw_line(Vector2(x,high),Vector2(x,low),Color(.94,.72,.4,.18),maxf(2,area.size.x/maxf(1,rows.size())))
		if i%4==0: draw_string(font,Vector2(x-8,area.end.y+22),"%02d" % int(rows[i].hour),HORIZONTAL_ALIGNMENT_LEFT,-1,13,Color("a4bbc0"))
		if i==0: continue
		var previous_x:=area.position.x+area.size.x*float(i-1)/maxf(1,rows.size()-1)
		for j in channels.size():
			draw_line(Vector2(previous_x,area.end.y-maxf(0,float(rows[i-1][channels[j]]))/maximum*area.size.y),Vector2(x,area.end.y-maxf(0,float(rows[i][channels[j]]))/maximum*area.size.y),colors[j],2.0,true)
func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and not rows.is_empty():
		var index:=clampi(int(round((event.position.x-55)/maxf(1,size.x-74)*float(rows.size()-1))),0,rows.size()-1)
		var r: Dictionary=rows[index]
		tooltip_text="D%d %02d:00\n需求 %.1f [%.1f—%.1f] MW\n风 %.1f · 光 %.1f MW\n储能 %.1f MWh · 外购 %.1f MW\n失供 %.1f MW · 最大负载 %.0f%% · 最低电压 %.3f pu" % [r.day,int(r.hour),r.demand,r.demand_low,r.demand_high,r.wind,r.solar,r.storage_mwh,r.imports,r.unserved,float(r.max_loading)*100,r.min_voltage]
