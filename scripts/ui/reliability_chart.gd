extends Control
## A single metric per plot keeps units explicit. Samples retain their real times.
const UI=preload("res://scripts/ui/ui_kit.gd")
var rows: Array=[]
var metric:="saidi_minutes"
var unit:="分钟/点"
var title:="平均停电时长 SAIDI"

func _init() -> void:
	custom_minimum_size=Vector2(0,174)
	mouse_filter=Control.MOUSE_FILTER_STOP
	resized.connect(queue_redraw)

func set_rows(value: Array,key: String="saidi_minutes") -> void:
	rows=value.duplicate(true)
	metric=key
	var names: Dictionary={"saidi_minutes":["平均停电时长 SAIDI","分钟/点"],"saifi":["平均停电次数 SAIFI","次/点"],"cmi":["累计失供点分钟 CMI","点·分钟"],"ens_mwh":["累计失供电量 ENS","MWh"]}
	var captions: Array=names.get(key,names.saidi_minutes)
	title=captions[0]; unit=captions[1]
	queue_redraw()

func _draw() -> void:
	var font:=get_theme_default_font()
	draw_style_box(UI.style(Color("102630"),6),Rect2(Vector2.ZERO,size))
	draw_string(font,Vector2(8,22),title+" · "+unit,HORIZONTAL_ALIGNMENT_LEFT,size.x-16,14,UI.TEXT)
	if rows.is_empty():
		draw_string(font,Vector2(12,90),"推进时间后积累实际统计",HORIZONTAL_ALIGNMENT_LEFT,size.x-24,14,UI.MUTED)
		return
	var plot:=Rect2(48,39,maxf(1,size.x-66),maxf(1,size.y-70))
	var maximum:=.01
	for row in rows: maximum=maxf(maximum,float(row.get(metric,0)))
	for mark in 3:
		var y:=plot.end.y-plot.size.y*float(mark)/2.0
		draw_line(Vector2(plot.position.x,y),Vector2(plot.end.x,y),Color("35505c"),1)
		draw_string(font,Vector2(4,y+4),"%.1f" % (maximum*float(mark)/2.0),HORIZONTAL_ALIGNMENT_LEFT,42,12,UI.MUTED)
	var start: float=float(rows[0].hour)
	var finish: float=float(rows[-1].hour)
	var previous:=Vector2.ZERO
	for i in rows.size():
		var point:=Vector2(plot.position.x+(float(rows[i].hour)-start)/maxf(.001,finish-start)*plot.size.x,plot.end.y-float(rows[i].get(metric,0))/maximum*plot.size.y)
		if i>0:
			draw_line(previous,point,UI.TEAL,2,true)
		draw_circle(point,2,UI.TEAL)
		previous=point
	draw_string(font,Vector2(plot.position.x,plot.end.y+21),"%.1f h" % start,HORIZONTAL_ALIGNMENT_LEFT,80,12,UI.MUTED)
	draw_string(font,Vector2(maxf(plot.position.x,plot.end.x-65),plot.end.y+21),"%.1f h" % finish,HORIZONTAL_ALIGNMENT_LEFT,65,12,UI.MUTED)

func _gui_input(event: InputEvent) -> void:
	if not event is InputEventMouseMotion or rows.is_empty(): return
	var at: float=clampf((event.position.x-48)/maxf(1,size.x-66),0,1)
	var hour: float=lerpf(float(rows[0].hour),float(rows[-1].hour),at)
	var nearest: Dictionary=rows[0]
	for row in rows:
		if absf(float(row.hour)-hour)<absf(float(nearest.hour)-hour): nearest=row
	tooltip_text="实际运行 %.2f h\n%s %.3f %s\n累计纳入 %d 个负荷点；分母随服务开通变化" % [float(nearest.hour),title,float(nearest.get(metric,0)),unit,int(nearest.get("enrolled_points",0))]
