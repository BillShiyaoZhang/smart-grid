extends Control
## Health and public consequence remain separate axes; unknown health is never zero.
signal target_selected(kind: String, id: int)
const UI=preload("res://scripts/ui/ui_kit.gd")
var rows: Array=[]
var hit_regions: Array[Dictionary]=[]

func _init() -> void:
	custom_minimum_size=Vector2(0,220)
	mouse_filter=Control.MOUSE_FILTER_STOP
	resized.connect(queue_redraw)

func set_rows(value: Array) -> void:
	rows=value.duplicate(true)
	queue_redraw()

func _draw() -> void:
	hit_regions.clear()
	var font:=get_theme_default_font()
	var area:=Rect2(36,32,maxf(1,size.x-52),maxf(1,size.y-74))
	draw_rect(area,Color("142e38"))
	draw_rect(Rect2(area.position,area.size*.5),Color("663c3755"))
	for x in [0.0,.5,1.0]:
		draw_line(area.position+Vector2(area.size.x*x,0),area.position+Vector2(area.size.x*x,area.size.y),Color("45616b"),1)
	for y in [0.0,.5,1.0]:
		draw_line(area.position+Vector2(0,area.size.y*y),area.position+Vector2(area.size.x,area.size.y*y),Color("45616b"),1)
	draw_string(font,Vector2(4,20),"影响高 ↑",HORIZONTAL_ALIGNMENT_LEFT,-1,14,UI.MUTED)
	draw_string(font,Vector2(36,size.y-20),"健康低  ←          →  健康高",HORIZONTAL_ALIGNMENT_LEFT,-1,14,UI.MUTED)
	var unknown:=0
	var stale:=0
	for row in rows:
		if row.get("health")==null or row.get("confidence","") not in ["trusted","field"]:
			unknown+=1
			if row.get("health")!=null: stale+=1
			continue
		var health: float=clampf(float(row.health)/100.0,0,1)
		var consequence: float=clampf(float(row.get("criticality",0)),0,1)
		var at: Vector2=area.position+Vector2(health,1.0-consequence)*area.size
		var color: Color=UI.RED if health<.5 and consequence>.5 else (UI.AMBER if health<.75 else UI.TEAL)
		draw_circle(at,7,UI.SURFACE)
		draw_arc(at,6,0,TAU,20,color,2,true)
		hit_regions.append({"rect":Rect2(at-Vector2(10,10),Vector2(20,20)),"row":row})
	draw_string(font,Vector2(4,size.y-2),"? %d 项当前未知（含旧记录 %d）" % [unknown,stale],HORIZONTAL_ALIGNMENT_LEFT,size.x-8,14,UI.MUTED)

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion or (event is InputEventMouseButton and event.pressed):
		for region in hit_regions:
			if not region.rect.has_point(event.position): continue
			var row: Dictionary=region.row
			tooltip_text="%s · 健康 %.0f%%\n%s\n%s" % [row.get("name","资产"),float(row.health),row.get("criticality_detail","影响为公开连接与关键负荷代理"),row.get("source","已知记录")]
			if event is InputEventMouseButton and event.button_index==MOUSE_BUTTON_LEFT:
				target_selected.emit(str(row.get("target_type","facility")),int(row.get("target_id",row.get("id",-1))))
			return
		tooltip_text="未知健康不进入矩阵。影响依据公开网络与关键负荷，不是故障概率。"
