extends RefCounted
## Service reliability uses public delivered power, never hidden fault state.
## One aggregate residential/industrial/hospital load is one supply point, not
## one household. The cumulative cohort never shrinks when a point is removed.

const THRESHOLD := 0.98
const HISTORY_LIMIT := 200
const TREND_LIMIT := 96
const LOAD_KINDS := ["home", "factory", "hospital"]
var state: Dictionary = {}

func _init() -> void:
	reset()

func reset(at: float=0.0) -> void:
	state={"version":1,"threshold":THRESHOLD,"started_at":at,"last_at":at,"operating_hours":0.0,
		"enrolled_points":0,"interruption_count":0,"cmi":0.0,"ens_mwh":0.0,"below_threshold_ens_mwh":0.0,
		"next_event":1,"roster":{},"active":{},"events":[],"trend":[],
		"archived":{"interruption_count":0,"cmi":0.0,"ens_mwh":0.0}}

func _eligible(sim: RefCounted,b: Dictionary) -> bool:
	return str(b.get("kind","")) in LOAD_KINDS and sim.customer_service_active(int(b.id))

func reconcile(sim: RefCounted) -> void:
	# Explicit construction/region mutations can remove a point or assign it to
	# a city before the next tick. Reconcile identities without enrolling points,
	# counting a new interruption, or adding time/energy to the window.
	for key in state.roster.keys():
		var target: Dictionary=sim.get_building(int(key))
		if target.is_empty() or not _eligible(sim,target):
			if state.active.has(key): _finish(str(key),float(state.last_at),"服务点已移除")
			state.roster.erase(key)
			continue
		state.roster[key].city_id=int(target.get("city_id",-1))
		if state.active.has(key): state.active[key].city_id=int(target.get("city_id",-1))

func advance(sim: RefCounted,dt: float) -> void:
	if dt<=0.0 or not is_finite(dt): return
	var now:=float(sim.elapsed_hours)
	# A report refresh or repeated settlement at the same timestamp cannot add
	# another interruption or count its minutes twice.
	var start:=maxf(float(state.last_at),now-dt)
	var duration:=now-start
	if duration<=0.000000001: return
	var seen: Dictionary={}
	var total_demand:=0.0
	var total_served:=0.0
	var adjacent: Dictionary={}
	for line in sim.lines:
		for id in [int(line.a),int(line.b)]:
			if not adjacent.has(id): adjacent[id]=[]
			adjacent[id].append(line)
	var receipts:=_work_receipts(sim)
	for b in sim.buildings:
		if not _eligible(sim,b): continue
		var key:=str(int(b.id))
		seen[key]=true
		if not state.roster.has(key):
			state.roster[key]={"facility_id":int(b.id),"name":str(b.name),"kind":str(b.kind),"city_id":int(b.get("city_id",-1)),"critical":b.kind=="hospital","weight":1,"enrolled_at":start}
			state.enrolled_points=int(state.enrolled_points)+1
		state.roster[key].city_id=int(b.get("city_id",-1))
		var demand:=maxf(0.0,float(b.demand))
		var served:=clampf(float(b.served),0.0,demand)
		total_demand+=demand
		total_served+=served
		var missing:=demand-served
		var fraction:=served/demand if demand>0.000001 else 1.0
		var lost:=missing*duration
		state.ens_mwh=float(state.ens_mwh)+lost
		if demand>0.000001 and fraction<THRESHOLD-0.000000001:
			if not state.active.has(key):
				state.active[key]={"id":int(state.next_event),"facility_id":int(b.id),"name":str(b.name),"kind":str(b.kind),"city_id":int(b.get("city_id",-1)),"critical":b.kind=="hospital","weight":1,
					"start":start,"end":-1.0,"duration_hours":0.0,"cmi":0.0,"ens_mwh":0.0,"deficit_mw":missing,"served_fraction":fraction,"evidence":[],"actions":[],"outcome":"持续失供"}
				state.next_event=int(state.next_event)+1
				state.interruption_count=int(state.interruption_count)+1
			var event: Dictionary=state.active[key]
			event.city_id=int(b.get("city_id",-1))
			event.duration_hours=float(event.duration_hours)+duration
			event.cmi=float(event.cmi)+duration*60.0
			event.ens_mwh=float(event.ens_mwh)+lost
			event.deficit_mw=missing
			event.served_fraction=fraction
			state.cmi=float(state.cmi)+duration*60.0
			_evidence(sim,event,adjacent.get(int(b.id),[]),receipts)
		else:
			state.below_threshold_ens_mwh=float(state.below_threshold_ens_mwh)+lost
			if state.active.has(key):
				_evidence(sim,state.active[key],adjacent.get(int(b.id),[]),receipts)
				_finish(key,start,"供电恢复")
	for key in state.roster.keys():
		if seen.has(key): continue
		if state.active.has(key): _finish(str(key),start,"服务点已移除")
		state.roster.erase(key)
	state.last_at=now
	state.operating_hours=float(state.operating_hours)+duration
	var row:={"hour":now,"enrolled_points":int(state.enrolled_points),"interruption_count":int(state.interruption_count),"cmi":float(state.cmi),"ens_mwh":float(state.ens_mwh),"served_fraction":total_served/total_demand if total_demand>0.000001 else 1.0}
	if not state.trend.is_empty() and floorf(float(state.trend[-1].hour))==floorf(now): state.trend[-1]=row
	else: state.trend.append(row)
	while state.trend.size()>TREND_LIMIT: state.trend.pop_front()

func _work_receipts(sim: RefCounted) -> Array:
	var result: Array=sim.operation_receipts()
	for receipt in sim.lifecycle.receipts:
		if str(receipt.get("status",""))=="cancelled": continue
		var label: String=str(sim.lifecycle.ACTIONS.get(str(receipt.action),{}).get("name","资产检修"))
		result.append({"action":"facility" if receipt.target_type=="facility" else "lifecycle_line","target_id":int(receipt.target_id),"elapsed_hours":float(receipt.finished_at),"phase":"executed","method":"field","title":"资产检修 · "+label})
	var microgrids: Dictionary={}
	for grid in sim.customers.microgrids: microgrids[int(grid.id)]=grid
	for receipt in sim.customers.events:
		var message:=str(receipt.message)
		if not message.begins_with("已离网") and message!="边界重联完成": continue
		var grid: Dictionary=microgrids.get(int(receipt.id),{})
		if grid.is_empty(): continue
		result.append({"action":"microgrid","target_id":int(receipt.id),"members":grid.members.duplicate(),"elapsed_hours":float(receipt.hour),"phase":"executed","method":"microgrid","title":"微电网切换 · "+message})
	return result

func _evidence(sim: RefCounted,event: Dictionary,adjacent: Array,receipts: Array) -> void:
	var related_lines: Dictionary={}
	var connected:=false
	for line in adjacent:
		connected=true
		related_lines[int(line.id)]=true
		var observation: Dictionary=sim.line_observation(int(line.id))
		if bool(observation.get("fault_known",false)) and bool(observation.get("fault",false)):
			_unique(event.evidence,"已核实相连线路 #%d 故障" % int(line.id),8)
		elif str(observation.get("visibility","unknown")) in ["verified","patrol"] and observation.get("closed") is bool and not bool(observation.closed):
			_unique(event.evidence,"已观测相连线路 #%d 断开" % int(line.id),8)
	if not connected: _unique(event.evidence,"公开拓扑中尚无接入线路",8)
	if event.evidence.is_empty(): _unique(event.evidence,"用户报告失供；原因待核实",8)
	for receipt in receipts:
		if float(receipt.get("elapsed_hours",-1))<float(event.start)-0.000001: continue
		if float(receipt.get("elapsed_hours",-1))>float(sim.elapsed_hours)+0.000001: continue
		var target:=int(receipt.get("target_id",-1))
		if str(receipt.get("action",""))=="microgrid":
			if int(event.facility_id) not in receipt.get("members",[]): continue
		elif str(receipt.get("action",""))=="facility":
			if target!=int(event.facility_id): continue
		elif not related_lines.has(target): continue
		if str(receipt.get("phase","")) not in ["executed","rejected"]: continue
		var action: String=str({"field":"现场","remote":"远程"}.get(str(receipt.get("method","field")),""))
		var outcome:="已执行" if receipt.phase=="executed" else "已拒绝"
		_unique(event.actions,"%.2fh：%s%s #%d %s" % [float(receipt.elapsed_hours),action,str(receipt.get("title","操作")),int(receipt.target_id),outcome],10)

func _unique(rows: Array,value: String,limit: int) -> void:
	if value not in rows: rows.append(value)
	while rows.size()>limit: rows.pop_front()

func _finish(key: String,at: float,outcome: String) -> void:
	var event: Dictionary=state.active[key]
	event.end=at
	event.outcome=outcome
	state.events.append(event)
	state.active.erase(key)
	while state.events.size()>HISTORY_LIMIT:
		var old: Dictionary=state.events.pop_front()
		state.archived.interruption_count=int(state.archived.interruption_count)+1
		state.archived.cmi=float(state.archived.cmi)+float(old.cmi)
		state.archived.ens_mwh=float(state.archived.ens_mwh)+float(old.ens_mwh)

func report(sim: RefCounted) -> Dictionary:
	var active_points:=0
	for b in sim.buildings:
		if _eligible(sim,b): active_points+=1
	var denominator:=float(state.enrolled_points)
	var count:=int(state.interruption_count)
	var summary:={"scope":"负荷点口径","scope_description":"每个已开通服务的住宅街区、工业园区或医院计1个负荷点；不是居民户数。分母为本统计窗口累计纳入的负荷点，移除后不缩减。供电低于需求98%计一次持续失供，恢复后再次失供另计。ENS包含阈值内全部缺额。",
		"started_at":float(state.started_at),"last_at":float(state.last_at),"elapsed_hours":float(state.operating_hours),"threshold":THRESHOLD,"enrolled_points":int(state.enrolled_points),"active_points":active_points,
		"interruption_count":count,"cmi":float(state.cmi),"cmi_unit":"点·分钟","saidi_minutes":float(state.cmi)/denominator if denominator>0 else 0.0,"saifi":float(count)/denominator if denominator>0 else 0.0,"caidi_minutes":float(state.cmi)/float(count) if count>0 else 0.0,
		"ens_mwh":float(state.ens_mwh),"below_threshold_ens_mwh":float(state.below_threshold_ens_mwh),"active_incidents":state.active.size(),"critical_active":0,"archived":state.archived.duplicate(true)}
	summary.saidi=summary.saidi_minutes
	summary.caidi=summary.caidi_minutes
	var incidents: Array=[]
	var events: Array=[]
	for event in state.active.values():
		var row:=_display_event(sim,event,denominator)
		incidents.append(row)
		if bool(event.critical): summary.critical_active=int(summary.critical_active)+1
	for event in state.events: events.append(_display_event(sim,event,denominator))
	incidents.sort_custom(func(a: Dictionary,b: Dictionary) -> bool:
		if bool(a.critical)!=bool(b.critical): return bool(a.critical)
		return float(a.start)<float(b.start) if not is_equal_approx(float(a.start),float(b.start)) else int(a.id)<int(b.id))
	events.reverse()
	var trend: Array=state.trend.duplicate(true)
	for row in trend:
		row.saidi_minutes=float(row.cmi)/float(row.enrolled_points) if int(row.enrolled_points)>0 else 0.0
		row.saifi=float(row.interruption_count)/float(row.enrolled_points) if int(row.enrolled_points)>0 else 0.0
	return {"summary":summary,"incidents":incidents,"events":events,"trend":trend}

func _display_event(sim: RefCounted,event: Dictionary,denominator: float) -> Dictionary:
	var row:=event.duplicate(true)
	row.affected_load_ids=[int(event.facility_id)]
	row.affected_points=1
	row.cause="；".join(event.evidence)
	row.duration_minutes=float(event.duration_hours)*60.0
	row.saidi_contribution_minutes=float(event.cmi)/denominator if denominator>0 else 0.0
	row.saifi_contribution=1.0/denominator if denominator>0 else 0.0
	row.cmi_share=float(event.cmi)/float(state.cmi) if float(state.cmi)>0 else 0.0
	row.ens_share=float(event.ens_mwh)/float(state.ens_mwh) if float(state.ens_mwh)>0 else 0.0
	var target: Dictionary=sim.get_building(int(event.facility_id))
	row.has_target=not target.is_empty()
	if float(event.end)<0.0 and not target.is_empty():
		var demand:=maxf(0.0,float(target.demand))
		row.deficit_mw=maxf(0.0,demand-float(target.served))
		row.served_fraction=clampf(float(target.served)/demand,0,1) if demand>0.000001 else 1.0
		if float(row.served_fraction)>=THRESHOLD: row.outcome="供电恢复待记录"
	row.after_action="%s；持续 %.1f 游戏分钟，失供 %.2f MWh，贡献 %.1f 点·分钟。%s" % [str(row.outcome),float(row.duration_minutes),float(row.ens_mwh),float(row.cmi),"已记录操作："+"；".join(row.actions) if not row.actions.is_empty() else "未记录相关操作回执；恢复原因不作推断。"]
	return row

func snapshot() -> Dictionary:
	return state.duplicate(true)

func restore(data: Dictionary) -> void:
	state=data.duplicate(true)
	# JSON's single number type must not change stable point/event identities
	# or nested dictionary equality on a save/continue path.
	for key in ["version","enrolled_points","interruption_count","next_event"]: state[key]=int(state[key])
	state.archived.interruption_count=int(state.archived.interruption_count)
	for member in state.roster.values():
		for key in ["facility_id","city_id","weight"]: member[key]=int(member[key])
	var events: Array=state.events.duplicate()
	events.append_array(state.active.values())
	for event in events:
		for key in ["id","facility_id","city_id","weight"]: event[key]=int(event[key])
	for row in state.trend:
		for key in ["enrolled_points","interruption_count"]: row[key]=int(row[key])

static func _number(value: Variant,low: float,high: float) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value)>=low and float(value)<=high

static func _integer(value: Variant,low: int,high: int) -> bool:
	return _number(value,float(low),float(high)) and float(value)==floorf(float(value))

static func valid_snapshot(data: Variant,elapsed: float,next_building_id: int) -> bool:
	if not data is Dictionary or not _integer(data.get("version"),1,1) or not _number(data.get("threshold"),THRESHOLD,THRESHOLD): return false
	for key in ["started_at","last_at"]:
		if not _number(data.get(key),0,elapsed+0.00001): return false
	if float(data.started_at)>float(data.last_at)+0.00001: return false
	if not _number(data.get("operating_hours"),0,float(data.last_at)-float(data.started_at)+0.00001): return false
	for key in ["enrolled_points","interruption_count"]:
		if not _integer(data.get(key),0,1000000000): return false
	if int(data.enrolled_points)>next_building_id-1 or (int(data.interruption_count)>0 and int(data.enrolled_points)==0): return false
	if not _integer(data.get("next_event"),1,1000000001) or int(data.next_event)!=int(data.interruption_count)+1: return false
	for key in ["cmi","ens_mwh","below_threshold_ens_mwh"]:
		if not _number(data.get(key),0,1e15): return false
	# At most 512 distinct supply points can operate concurrently. A bounded
	# archive must obey the same physical point-minute budget as detailed events.
	var maximum_cmi:=float(data.operating_hours)*60.0*float(mini(512,int(data.enrolled_points)))
	if float(data.cmi)>maximum_cmi+maxf(.00001,maximum_cmi*1e-9): return false
	if float(data.operating_hours)<=0 and (int(data.interruption_count)>0 or float(data.ens_mwh)>0): return false
	if not data.get("roster") is Dictionary or data.roster.size()>512 or data.roster.size()>int(data.enrolled_points): return false
	if not data.get("active") is Dictionary or data.active.size()>512 or not data.get("events") is Array or data.events.size()>HISTORY_LIMIT: return false
	if not data.get("trend") is Array or data.trend.size()>TREND_LIMIT or not data.get("archived") is Dictionary: return false
	for key in data.roster:
		var member: Variant=data.roster[key]
		if not key is String or not key.is_valid_int() or str(int(key))!=key or not member is Dictionary: return false
		if not _integer(member.get("facility_id"),1,next_building_id-1) or int(key)!=int(member.facility_id): return false
		if member.get("kind") not in LOAD_KINDS or not member.get("name") is String or member.name.length()>200: return false
		if not _integer(member.get("city_id"),-1,7) or not member.get("critical") is bool or bool(member.critical)!=(member.kind=="hospital") or not _integer(member.get("weight"),1,1): return false
		if not _number(member.get("enrolled_at"),float(data.started_at),float(data.last_at)+0.00001): return false
	var archive: Dictionary=data.archived
	if not _integer(archive.get("interruption_count"),0,int(data.interruption_count)): return false
	for key in ["cmi","ens_mwh"]:
		if not _number(archive.get(key),0,float(data[key])+0.00001): return false
	var ids: Dictionary={}
	var cumulative_cmi:=float(archive.cmi)
	var cumulative_ens:=float(archive.ens_mwh)+float(data.below_threshold_ens_mwh)
	var all: Array=data.events.duplicate()
	all.append_array(data.active.values())
	if int(archive.interruption_count)+all.size()!=int(data.interruption_count): return false
	for event in all:
		if not _valid_event(event,data,next_building_id): return false
		if ids.has(int(event.id)): return false
		ids[int(event.id)]=true
		cumulative_cmi+=float(event.cmi)
		cumulative_ens+=float(event.ens_mwh)
	for key in data.active:
		if not key is String or not data.roster.has(key) or str(int(data.active[key].facility_id))!=key or float(data.active[key].end)!=-1 or data.active[key].outcome!="持续失供": return false
		for field in ["kind","city_id","critical","weight"]:
			if data.active[key][field]!=data.roster[key][field]: return false
	for event in data.events:
		if float(event.end)<0 or event.outcome=="持续失供": return false
	if absf(cumulative_cmi-float(data.cmi))>maxf(.00001,float(data.cmi)*1e-9) or absf(cumulative_ens-float(data.ens_mwh))>maxf(.00001,float(data.ens_mwh)*1e-9): return false
	var previous: Dictionary={"hour":-1.0,"enrolled_points":0,"interruption_count":0,"cmi":0.0,"ens_mwh":0.0}
	for row in data.trend:
		if not row is Dictionary or not _number(row.get("hour"),maxf(float(data.started_at),float(previous.hour)),float(data.last_at)+.00001) or not _number(row.get("served_fraction"),0,1): return false
		for key in ["enrolled_points","interruption_count"]:
			if not _integer(row.get(key),int(previous[key]),int(data[key])): return false
		for key in ["cmi","ens_mwh"]:
			if not _number(row.get(key),float(previous[key]),float(data[key])+.00001): return false
		previous=row
	return true

static func references_valid(data: Dictionary,buildings: Dictionary,region: Dictionary) -> bool:
	var phases: Dictionary={}
	if bool(region.get("active",false)):
		for city in region.get("cities",[]): phases[int(city.id)]=str(city.get("service_phase","active"))
	for key in data.roster:
		var id:=int(key)
		if not buildings.has(id): return false
		var target: Dictionary=buildings[id]
		var member: Dictionary=data.roster[key]
		if target.kind!=member.kind or int(target.get("city_id",-1))!=int(member.city_id): return false
		if phases.get(int(target.get("city_id",-1)),"active")!="active": return false
	# Ended events retain the identity recorded at the time, including removed
	# or renamed points. They are not live navigation or roster references.
	return true

static func _valid_event(event: Variant,data: Dictionary,next_building_id: int) -> bool:
	if not event is Dictionary or not _integer(event.get("id"),1,int(data.next_event)-1) or not _integer(event.get("facility_id"),1,next_building_id-1): return false
	if event.get("kind") not in LOAD_KINDS or not event.get("name") is String or event.name.length()>200 or not _integer(event.get("city_id"),-1,7): return false
	if not event.get("critical") is bool or bool(event.critical)!=(event.kind=="hospital") or not _integer(event.get("weight"),1,1): return false
	if not _number(event.get("start"),float(data.started_at),float(data.last_at)+.00001): return false
	if not _number(event.get("end"),-1,float(data.last_at)+.00001) or (float(event.end)<0 and float(event.end)!=-1): return false
	var end:=float(data.last_at) if float(event.end)<0 else float(event.end)
	if not _number(event.get("duration_hours"),0,end-float(event.start)+.00001): return false
	for key in ["cmi","ens_mwh","deficit_mw"]:
		if not _number(event.get(key),0,1e15): return false
	if absf(float(event.cmi)-float(event.duration_hours)*60)>maxf(.00001,float(event.cmi)*1e-9): return false
	if not _number(event.get("served_fraction"),0,1) or event.get("outcome") not in ["持续失供","供电恢复","服务点已移除"]: return false
	for key in ["evidence","actions"]:
		if not event.get(key) is Array or event[key].size()>(8 if key=="evidence" else 10): return false
		for text in event[key]:
			if not text is String or text.length()>300: return false
	return true
