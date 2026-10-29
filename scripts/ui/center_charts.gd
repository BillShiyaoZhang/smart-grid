extends Control
## Read-only visual summaries. No chart query changes game time or hidden state.
signal item_selected(id: int)
signal technology_selected(id: String)
const UI = preload("res://scripts/ui/ui_kit.gd")
var mode := "bars"
var snapshot: Dictionary = {}
var hit_regions: Array[Dictionary] = []
var _icon_regions: Dictionary = {}

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	resized.connect(queue_redraw)
	theme_changed.connect(queue_redraw)

func set_snapshot(value: Dictionary) -> void:
	snapshot = value.duplicate(true)
	queue_redraw()

func _text(at: Vector2, caption: String, color: Color=UI.TEXT, font_size: int=14, width: float=-1) -> void:
	draw_string(get_theme_default_font(),at,caption,HORIZONTAL_ALIGNMENT_LEFT,width,font_size,color)

func _bar(rect: Rect2, value: float, maximum: float, color: Color, known: bool=true) -> void:
	draw_style_box(UI.style(Color("29434e"),4,Color.TRANSPARENT,0),rect)
	if not known:
		for x in range(int(rect.position.x),int(rect.end.x),9):
			draw_line(Vector2(x,rect.end.y),Vector2(minf(x+rect.size.y,rect.end.x),rect.position.y),UI.MUTED.darkened(.35),1,true)
		return
	var amount := rect.size.x*clampf(value/maxf(.00001,maximum),0,1)
	if amount>0: draw_style_box(UI.style(color,4,Color.TRANSPARENT,0),Rect2(rect.position,Vector2(amount,rect.size.y)))

func _draw() -> void:
	hit_regions.clear()
	match mode:
		"comparison": _comparison()
		"waterfall": _waterfall()
		"profit": _profit()
		"conditions": _conditions()
		"contract": _contract()
		"cities": _cities()
		"technology": _technology()
		_: _bars()

func _bars() -> void:
	var rows: Array = snapshot.get("rows",[])
	var y := 22.0
	for row in rows:
		_text(Vector2(4,y),str(row.get("label","")),UI.MUTED)
		var known := bool(row.get("known",true))
		var caption: String=str(row.get("text","—")) if known else "? 待核实"
		_text(Vector2(maxf(140,size.x-180),y),caption,UI.TEXT)
		_bar(Rect2(4,y+10,maxf(1,size.x-8),12),float(row.get("value",0)),float(row.get("max",1)),row.get("color",UI.TEAL),known)
		y+=52

func _comparison() -> void:
	var items: Array=snapshot.get("items",[])
	if items.is_empty(): return
	var columns: int=items.size()
	var gap := 12.0
	var column_width: float=(size.x-gap*float(columns-1))/float(columns)
	var icon_size: float=minf(64,maxf(36,column_width*.35))
	for index in columns:
		var item: Dictionary=items[index]
		var x: float=float(index)*(column_width+gap)
		var asset: String="res://assets/icons/%s.png" % str(item.get("kind",""))
		if ResourceLoader.exists(asset):
			var texture: Texture2D=load(asset)
			if not _icon_regions.has(asset): _icon_regions[asset]=Rect2(texture.get_image().get_used_rect())
			draw_texture_rect_region(texture,Rect2(x+(column_width-icon_size)*.5,6,icon_size,icon_size),_icon_regions[asset])
		_text(Vector2(x+4,icon_size+24),str(item.get("name","")),UI.TEXT,16,column_width-8)
		_text(Vector2(x+4,icon_size+48),"¥%s" % str(item.get("price_text","")),UI.TEAL,20,column_width-8)
		_text(Vector2(x+4,icon_size+70),str(item.get("role","")),UI.MUTED,14,column_width-8)
	var y: float=icon_size+88
	var metrics: Array=snapshot.get("metrics",[])
	for metric in metrics:
		_text(Vector2(4,y),str(metric.label),UI.TEXT,16)
		y+=18
		for index in columns:
			var item: Dictionary=items[index]
			var x: float=float(index)*(column_width+gap)
			var key: String=str(metric.key)
			var known: bool=item.get(key)!=null
			_bar(Rect2(x+4,y+7,maxf(1,column_width-8),13),float(item.get(key,0)) if known else 0,float(metric.get("max",1)),metric.get("color",UI.TEAL),known)
			_text(Vector2(x+4,y+34),str(item.get(key+"_text","不适用")),UI.TEXT,14,column_width-8)
		y+=58
	_text(Vector2(4,size.y-8),"共同零基线 · 额定参数，实际交付受运行条件影响",UI.MUTED,14,size.x-8)

func _waterfall() -> void:
	var rows: Array=snapshot.get("rows",[])
	if rows.is_empty():
		_text(Vector2(10,40),"等待真实结算后展示收入与成本",UI.MUTED)
		return
	var high := 1.0
	var low := 0.0
	var cursor := 0.0
	for row in rows:
		cursor+=float(row.value)
		high=maxf(high,cursor)
		low=minf(low,cursor)
	var plot := Rect2(12,18,maxf(1,size.x-24),maxf(1,size.y-76))
	var span: float=maxf(1,high-low)
	var zero: float=plot.end.y-(0-low)/span*plot.size.y
	draw_line(Vector2(plot.position.x,zero),Vector2(plot.end.x,zero),UI.MUTED.darkened(.45),1,true)
	var step: float=plot.size.x/float(rows.size()+1)
	var width: float=step*.64
	cursor=0
	for index in rows.size()+1:
		var total: bool=index==rows.size()
		var value: float=cursor if total else float(rows[index].value)
		var start: float=0 if total else cursor
		var finish: float=cursor if total else cursor+value
		var top: float=plot.end.y-(maxf(start,finish)-low)/span*plot.size.y
		var bottom: float=plot.end.y-(minf(start,finish)-low)/span*plot.size.y
		var x: float=plot.position.x+float(index)*step+step*.18
		var color: Color=UI.TEAL if value>=0 else UI.RED
		if total: color=UI.AMBER if value<0 else UI.TEAL
		draw_style_box(UI.style(color,3,Color.TRANSPARENT,0),Rect2(x,top,width,maxf(2,bottom-top)))
		_text(Vector2(x,maxf(14,top-5)),"0" if absf(value)<.01 else "%.0f" % value,color,14,step)
		_text(Vector2(x,plot.end.y+24),"净收益" if total else str(rows[index].label),UI.MUTED,14,step)
		if not total: cursor=finish

func _profit() -> void:
	var entries: Array=snapshot.get("entries",[])
	if entries.is_empty():
		_text(Vector2(8,35),"尚无运营账单 · 推进时间开始积累",UI.MUTED)
		return
	var maximum := 1.0
	for entry in entries: maximum=maxf(maximum,absf(float(entry.get("net",0))))
	var y: float=size.y*.48
	draw_line(Vector2(12,y),Vector2(size.x-12,y),UI.MUTED.darkened(.4),1,true)
	var step: float=(size.x-24)/float(entries.size())
	_text(Vector2(1,y-5),"0",UI.MUTED)
	for index in entries.size():
		var entry: Dictionary=entries[index]
		var value: float=float(entry.get("net",0))
		var height: float=(size.y*.35)*absf(value)/maximum
		var width: float=minf(64,maxf(3,step-12))
		var x: float=12+float(index)*step+(step-width)*.5
		var color: Color=UI.TEAL if value>=0 else UI.RED
		draw_rect(Rect2(x,y-height if value>=0 else y,width,maxf(2,height)),color)
		_text(Vector2(x,maxf(15,y-height-5) if value>=0 else y+height+17),"%+.0f" % value,color,14,maxf(76,step))
		_text(Vector2(x,size.y-7),"D%d" % int(entry.get("day",1)),UI.MUTED,14,step)

func _conditions() -> void:
	var steps: Array=snapshot.get("steps",[])
	if steps.is_empty(): return
	var gap := 8.0
	var columns: int=steps.size()
	var width: float=(size.x-gap*float(columns-1))/float(columns)
	for index in columns:
		var step: Dictionary=steps[index]
		var known: bool=bool(step.get("known",true))
		var ok: bool=bool(step.get("ok",false))
		var color: Color=UI.TEAL if ok else UI.AMBER
		if not known: color=UI.MUTED
		var x: float=float(index)*(width+gap)
		var center := Vector2(x+width*.5,24)
		if index<columns-1: draw_line(center,Vector2(center.x+width+gap,24),UI.MUTED.darkened(.55),2,true)
		draw_circle(center,15,UI.SURFACE)
		draw_arc(center,15,0,TAU,28,color,2,true)
		_text(center+Vector2(-6,5),"✓" if ok else ("?" if not known else "!"),color,17)
		_text(Vector2(x,62),str(step.get("label","")),UI.TEXT,14,width)
		_text(Vector2(x,84),str(step.get("detail","")),color,14,width)

func _contract() -> void:
	var mw: float=float(snapshot.get("mw",0))
	var hours: float=float(snapshot.get("hours",12))
	var maximum: float=maxf(mw,float(snapshot.get("max",mw)))
	var plot := Rect2(42,22,maxf(1,size.x-62),maxf(1,size.y-66))
	var height: float=plot.size.y*mw/maxf(1,maximum)
	draw_line(plot.position,Vector2(plot.position.x,plot.end.y),UI.MUTED,1,true)
	draw_line(Vector2(plot.position.x,plot.end.y),plot.end,UI.MUTED,1,true)
	draw_rect(Rect2(plot.position.x,plot.end.y-height,plot.size.x,height),Color(UI.TEAL,.22))
	draw_rect(Rect2(plot.position.x,plot.end.y-height,plot.size.x,height),UI.TEAL,false,2)
	_text(Vector2(4,20),"MW",UI.MUTED)
	_text(Vector2(plot.position.x+8,plot.end.y-height+24),"%.1f MW × %.0fh = %.1f MWh" % [mw,hours,mw*hours],UI.TEAL,16)
	_text(Vector2(plot.position.x,plot.end.y+24),"开始",UI.MUTED)
	_text(Vector2(maxf(plot.position.x,plot.end.x-86),plot.end.y+24),"%.0f 小时后" % hours,UI.MUTED)

func _cities() -> void:
	var cities: Array=snapshot.get("cities",[])
	var y := 24.0
	for city in cities:
		var active: bool=str(city.get("service_phase","active"))=="active"
		_text(Vector2(4,y),str(city.get("name","城市")),UI.TEXT,14,100)
		var service: float=float(city.get("service",0))
		_bar(Rect2(112,y-13,maxf(1,size.x-214),12),service,1,UI.TEAL if service>=.93 else UI.AMBER,active)
		_text(Vector2(maxf(120,size.x-94),y),"%.0f%%" % (service*100) if active else "待接管",UI.MUTED)
		hit_regions.append({"rect":Rect2(0,y-20,size.x,36),"id":int(city.get("id",-1))})
		y+=40

func _technology() -> void:
	var nodes: Array=snapshot.get("nodes",[])
	if nodes.is_empty(): return
	var count: int=nodes.size()
	var width: float=minf(360,(size.x-36)/float(mini(3,count)))
	var start_x: float=maxf(12,(size.x-(width+6)*float(mini(3,count)))*.5)
	var locations: Dictionary={}
	for index in count:
		locations[str(nodes[index].id)]=Vector2(start_x+float(index%3)*(width+6),10+float(index/3)*100)
	for node in nodes:
		var pos: Vector2=locations[str(node.id)]
		for prerequisite in node.get("requires",[]):
			if locations.has(str(prerequisite)):
				var from: Vector2=locations[str(prerequisite)]+Vector2(width*.5,58)
				draw_line(from,pos+Vector2(width*.5,0),UI.MUTED,2,true)
	for node in nodes:
		var pos: Vector2=locations[str(node.id)]
		var color: Color=UI.TEAL if node.get("complete",false) else UI.MUTED
		if node.get("project",false): color=UI.AMBER
		var rect:=Rect2(pos,Vector2(width-8,60))
		draw_style_box(UI.style(Color("173541"),6,UI.TEXT if node.get("selected",false) else color,7),rect)
		_text(pos+Vector2(10,24),str(node.get("name","")),UI.TEXT,14,width-26)
		_text(pos+Vector2(10,46),"✓ 已掌握" if node.get("complete",false) else ("研发中" if node.get("project",false) else "○ 选择查看前置"),color,14,width-26)
		if not str(node.get("previous","")).is_empty():
			_text(pos+Vector2(4,82),"↑ "+str(node.previous),UI.MUTED,14,width-8)
		hit_regions.append({"rect":rect,"technology_id":str(node.id)})

func _gui_input(event: InputEvent) -> void:
	if not event is InputEventMouseButton or not event.pressed or event.button_index!=MOUSE_BUTTON_LEFT: return
	for hit in hit_regions:
		if hit.rect.has_point(event.position):
			if hit.has("technology_id"): technology_selected.emit(str(hit.technology_id))
			else: item_selected.emit(int(hit.id))
			accept_event()
			return
