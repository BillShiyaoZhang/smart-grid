extends RefCounted
## Net-metered street aggregates. Solar/self-storage is accounted behind the
## meter; only surplus generation and remaining demand enter network dispatch.

const CUSTOMER_KINDS := ["home","factory","hospital"]
const ALLOWED_SETTINGS := ["metered","consent","participation","pv_mw","battery_mwh","battery_mw","ev_mw","ev_target_mwh","deadline_hour","smart","grid_forming"]
var enabled := false
var devices: Dictionary = {}
var microgrids: Array = []
var next_microgrid_id := 1
var events: Array = []
var telemetry: Dictionary = {}
var _prepared: Dictionary = {}

func reset() -> void:
	enabled=false
	devices.clear()
	microgrids.clear()
	events.clear()
	telemetry.clear()
	_prepared.clear()
	next_microgrid_id=1

func enable(sim: RefCounted) -> Dictionary:
	if sim.campaign.active: return _result(false,"历史情景使用预设用户侧能源规则。")
	enabled=true
	return _result(true,"用户侧能源管理已开放；逐街区安装电表并签约接入。")

func configure(sim: RefCounted, id: int, settings: Dictionary) -> Dictionary:
	var b: Dictionary=sim.get_building(id)
	if not enabled or b.is_empty() or b.kind not in CUSTOMER_KINDS: return _result(false,"请选择住宅、工业或医院街区。")
	var old: Dictionary=devices.get(str(id),_defaults(sim))
	var row: Dictionary=old.duplicate(true)
	for key in settings:
		if key not in ALLOWED_SETTINGS: return _result(false,"未知用户侧设置。")
		row[key]=settings[key]
	if not _valid_device(row): return _result(false,"用户侧容量、参与率或充电期限无效。")
	if (float(row.pv_mw)>0.0 or float(row.ev_mw)>0.0 or float(row.battery_mwh)>0.0 or bool(row.smart)) and not bool(row.metered):
		return _result(false,"先为街区安装智能电表。")
	if bool(row.smart) and not bool(row.consent): return _result(false,"聚合控制需要用户授权。")
	if bool(row.grid_forming) and (float(row.battery_mwh)<=0.0 or float(row.battery_mw)<=0.0): return _result(false,"构网运行需要用户侧储能。")
	var cost: float=(2000.0 if bool(row.metered) and not bool(old.metered) else 0.0)+maxf(0.0,float(row.pv_mw)-float(old.pv_mw))*1500.0+maxf(0.0,float(row.battery_mwh)-float(old.battery_mwh))*500.0+maxf(0.0,float(row.battery_mw)-float(old.battery_mw))*300.0+maxf(0.0,float(row.ev_mw)-float(old.ev_mw))*700.0
	if float(sim.cash)<cost: return _result(false,"用户侧改造资金不足。")
	if cost>0.0: sim.record_cash_change(-cost,"customers","街区 #%d 电表与分布式能源改造" % id)
	row.energy_mwh=minf(float(row.energy_mwh),float(row.battery_mwh))
	if settings.has("ev_target_mwh") or settings.has("deadline_hour") or not devices.has(str(id)):
		row.ev_remaining_mwh=float(row.ev_target_mwh)
		row.ev_deadline=_next_deadline(sim,float(row.deadline_hour))
	devices[str(id)]=row
	return _result(true,"街区能源方案已应用；屋顶光伏和本地储能可独立运行，协同需可信通信。")

func _defaults(sim: RefCounted) -> Dictionary:
	return {"metered":false,"consent":false,"participation":0.5,"pv_mw":0.0,"battery_mwh":0.0,"battery_mw":0.0,"energy_mwh":0.0,"ev_mw":0.0,"ev_target_mwh":0.0,"deadline_hour":7.0,"smart":false,"grid_forming":false,"ev_remaining_mwh":0.0,"ev_deadline":_next_deadline(sim,7.0),"shift_debt_mwh":0.0,"fatigue":0.0,"response_kind":"none","response_fraction":0.0,"response_remaining":0.0,"response_until":float(sim.elapsed_hours),"shifted_total_mwh":0.0,"repaid_total_mwh":0.0,"curtailed_total_mwh":0.0,"missed_ev_mwh":0.0,"compensation":0.0,"pv_generated_mwh":0.0,"pv_self_mwh":0.0}

func _next_deadline(sim: RefCounted, hour: float) -> float:
	var distance: float=fposmod(hour-float(sim.time_hours),24.0)
	return float(sim.elapsed_hours)+(24.0 if distance<0.000001 else distance)

func demand_response(sim: RefCounted, id: int, kind: String = "shift", fraction: float = 0.2, hours: float = 2.0) -> Dictionary:
	if not enabled or not devices.has(str(id)): return _result(false,"先安装电表并签约街区。")
	var row: Dictionary=devices[str(id)]
	if kind not in ["shift","curtail"] or not _number(fraction,0.05,0.5) or not _number(hours,0.25,4.0): return _result(false,"需求响应应为移峰或削减，持续0.25—4小时、比例5—50%。")
	if not bool(row.metered) or not bool(row.consent) or float(row.participation)<=0.0: return _result(false,"该街区尚未授权参与需求响应。")
	if not _reachable(sim,id): return _result(false,"需求响应需要可信通信与新鲜街区观测。")
	if float(row.response_remaining)>0.0: return _result(false,"该街区正在执行需求响应。")
	row.response_kind=kind
	row.response_fraction=fraction
	row.response_remaining=hours
	row.response_until=float(sim.elapsed_hours)+hours
	return _result(true,"需求响应已签发；按实际参与量补偿，移峰电量将在结束后回补。")

func _reachable(sim: RefCounted, id: int) -> bool:
	if not sim.digital.control_reachable(sim,id): return false
	var observed: Dictionary=sim.facility_observation(id)
	return str(observed.get("visibility","unknown")) in ["verified","field"]

func prepare_component(sim: RefCounted, ids: Array[int], dt: float) -> void:
	for id in ids:
		var b: Dictionary=sim.get_building(id)
		b.customer_generation_mw=0.0
		b.customer_local_served_mw=0.0
		b.customer_limit=1.0
		b.customer_grid_blocked=false
		var grid: Dictionary=_microgrid_for(id)
		if enabled and not grid.is_empty() and bool(grid.islanded):
			if int(grid.stage)==0:
				b.customer_limit=0.0
				b.customer_grid_blocked=true
			elif int(grid.stage)==1 and id not in grid.critical_ids: b.customer_limit=0.0
		if not enabled or not devices.has(str(id)): continue
		var row: Dictionary=devices[str(id)]
		if not bool(row.metered) or not b.online: continue
		var local_base: float=float(b.demand)
		var horizon: float=maxf(0.05,dt)
		var controllable: bool=bool(row.consent) and _reachable(sim,id)
		var response:=0.0
		var response_overlap: float=maxf(0.0,minf(float(sim.elapsed_hours),float(row.response_until))-(float(sim.elapsed_hours)-dt))/dt if dt>0.0 else (1.0 if float(row.response_until)>float(sim.elapsed_hours) else 0.0)
		if response_overlap>0.0 and controllable:
			response=local_base*float(row.participation)*float(row.response_fraction)*(1.0-float(row.fatigue))*response_overlap
		var recovery:=0.0
		if response_overlap<=0.0:
			recovery=minf(float(row.shift_debt_mwh)/horizon,maxf(0.25,local_base*0.3))
		var ev: float=minf(float(row.ev_mw),float(row.ev_remaining_mwh)/horizon)
		var hours_left: float=maxf(horizon,float(row.ev_deadline)-float(sim.elapsed_hours))
		var valley: bool=float(sim.time_hours)<7.0 or float(sim.time_hours)>=23.0
		if bool(row.smart) and controllable and not valley and hours_left>float(row.ev_remaining_mwh)/maxf(0.000001,float(row.ev_mw))+0.25:
			ev=0.0
		var gross: float=maxf(0.0,local_base-response)+recovery+ev
		var pv: float=float(row.pv_mw)*float(sim.solar_factor())
		var local_self: float=minf(pv,gross)
		var charging:=0.0
		var discharge:=0.0
		var surplus: float=maxf(0.0,pv-local_self)
		if surplus>0.0:
			charging=minf(surplus,minf(float(row.battery_mw),maxf(0.0,float(row.battery_mwh)-float(row.energy_mwh))/(horizon*0.94)))
		elif gross>local_self:
			discharge=minf(gross-local_self,minf(float(row.battery_mw),float(row.energy_mwh)*0.94/horizon))
		var battery_export:=0.0
		if not grid.is_empty() and bool(grid.islanded) and int(grid.stage)>0 and bool(row.grid_forming):
			battery_export=minf(maxf(0.0,float(row.battery_mw)-discharge),maxf(0.0,float(row.energy_mwh)*0.94/horizon-discharge)) if charging<=0.0 else 0.0
		if not grid.is_empty() and bool(grid.islanded):
			if int(grid.stage)==0:
				pv=0.0; local_self=0.0; charging=0.0; discharge=0.0; surplus=0.0
				battery_export=0.0
				b.customer_limit=0.0
			elif int(grid.stage)==1 and id not in grid.critical_ids:
				b.customer_limit=0.0
		b.demand=maxf(0.0,gross-local_self-discharge)
		b.customer_generation_mw=maxf(0.0,surplus-charging)+battery_export
		b.customer_local_served_mw=local_self+discharge
		_prepared[id]={"gross":gross,"base":local_base,"pv":pv,"local_self":local_self,"charge":charging,"discharge":discharge,"pv_export":maxf(0.0,surplus-charging),"battery_export":battery_export,"ev":ev,"recovery":recovery,"response":response,"response_kind":str(row.response_kind),"horizon":horizon}

func commit_component(sim: RefCounted, ids: Array[int], dt: float) -> void:
	if not enabled or dt<=0.0: return
	for id in ids:
		if not devices.has(str(id)) or not _prepared.has(id): continue
		var row: Dictionary=devices[str(id)]
		var p: Dictionary=_prepared[id]
		var b: Dictionary=sim.get_building(id)
		var battery_export: float=minf(float(p.battery_export),maxf(0.0,float(b.output)-float(p.pv_export)))
		row.energy_mwh=clampf(float(row.energy_mwh)+float(p.charge)*dt*0.94-(float(p.discharge)+battery_export)*dt/0.94,0.0,float(row.battery_mwh))
		var served_fraction: float=clampf((float(b.served)+float(b.customer_local_served_mw))/maxf(0.000001,float(p.gross)),0.0,1.0)
		var ev_energy: float=minf(float(row.ev_remaining_mwh),float(p.ev)*dt*served_fraction)
		row.ev_remaining_mwh=maxf(0.0,float(row.ev_remaining_mwh)-ev_energy)
		var repayment: float=minf(float(row.shift_debt_mwh),float(p.recovery)*dt*served_fraction)
		row.shift_debt_mwh=maxf(0.0,float(row.shift_debt_mwh)-repayment)
		row.repaid_total_mwh+=repayment
		var response_energy: float=float(p.response)*dt
		if p.response_kind=="shift":
			row.shift_debt_mwh+=response_energy
			row.shifted_total_mwh+=response_energy
		elif p.response_kind=="curtail": row.curtailed_total_mwh+=response_energy
		if response_energy>0.0:
			row.fatigue=minf(0.9,float(row.fatigue)+response_energy/maxf(1.0,float(p.base)*8.0))
			var compensation: float=response_energy*(35.0 if p.response_kind=="curtail" else 18.0)
			row.compensation+=compensation
			sim.record_cash_change(-compensation,"demand_response","街区 #%d 实际响应补偿" % id)
		row.pv_generated_mwh+=float(p.pv)*dt
		row.pv_self_mwh+=float(p.local_self)*dt
		if float(sim.elapsed_hours)>=float(row.ev_deadline):
			var missed: float=float(row.ev_remaining_mwh)
			if missed>0.000001:
				row.missed_ev_mwh+=missed
				sim.record_cash_change(-missed*45.0,"customers","街区 #%d 充电期限未满足补偿" % id)
				_event(sim,"充电期限已到，未完成 %.2f MWh；补偿已结算。" % missed,id)
			row.ev_remaining_mwh=float(row.ev_target_mwh)
			row.ev_deadline=float(row.ev_deadline)+24.0
		if _reachable(sim,id):
			telemetry[str(id)]={"sampled_at":float(sim.elapsed_hours),"energy_mwh":float(row.energy_mwh),"ev_remaining_mwh":float(row.ev_remaining_mwh),"shift_debt_mwh":float(row.shift_debt_mwh),"fatigue":float(row.fatigue)}

func advance(sim: RefCounted, dt: float) -> void:
	if not enabled or dt<=0.0: return
	for key in devices:
		var row: Dictionary=devices[key]
		row.response_remaining=maxf(0.0,float(row.response_until)-float(sim.elapsed_hours))
		row.fatigue=maxf(0.0,float(row.fatigue)-dt*0.015)
	for grid in microgrids:
		if not grid.pending.is_empty():
			grid.pending.remaining=maxf(0.0,float(grid.pending.remaining)-dt)
			if float(grid.pending.remaining)<=0.000001: _execute_switch(sim,grid)
		if not bool(grid.islanded): continue
		var source_ready:=false
		for id in grid.members:
			var b: Dictionary=sim.get_building(int(id))
			if b.is_empty() or not b.online or not b.get("enabled",true): continue
			if b.kind in ["gas","hydro","dc_dynamo"]: source_ready=true
			if sim.evolution.is_storage(str(b.kind)) and float(b.energy)>0.01: source_ready=true
			var row: Dictionary=devices.get(str(id),{})
			if bool(row.get("grid_forming",false)) and float(row.get("energy_mwh",0.0))>0.01: source_ready=true
		if not source_ready:
			grid.stage=0; grid.restoration_hours=0.0
		else:
			grid.restoration_hours+=dt
			grid.stage=2 if float(grid.restoration_hours)>=0.5 else 1

func define_microgrid(sim: RefCounted, name: String, member_ids: Array, critical_ids: Array = []) -> Dictionary:
	if not enabled or name.strip_edges().is_empty() or name.length()>40 or member_ids.is_empty() or member_ids.size()>512:
		return _result(false,"请命名微电网并选择有效设施。")
	var members: Array=[]
	for value in member_ids:
		if not _number(value,1,1e9) or float(value)!=floorf(float(value)): return _result(false,"微电网设施编号无效。")
		var id:=int(value)
		if sim.get_building(id).is_empty() or id in members or not _microgrid_for(id).is_empty(): return _result(false,"设施不存在、重复或已属于其他微电网。")
		members.append(id)
	var critical: Array=[]
	for value in critical_ids:
		if not _integer(value,1,1e9) or int(value) not in members or int(value) in critical: return _result(false,"关键负荷必须属于本微电网。")
		critical.append(int(value))
	if microgrids.size()>=16: return _result(false,"最多管理16个微电网分区。")
	var grid: Dictionary={"id":next_microgrid_id,"name":name.strip_edges(),"members":members,"critical_ids":critical,"islanded":false,"stage":2,"restoration_hours":0.0,"boundary_lines":[],"pending":{},"receipt":"已登记，尚未离网"}
	microgrids.append(grid)
	next_microgrid_id+=1
	return {"ok":true,"message":"微电网分区已登记，可安排离网与关键负荷恢复。","id":int(grid.id)}

func set_microgrid(sim: RefCounted, id: int, island: bool, method: String = "field") -> Dictionary:
	var grid: Dictionary={}
	for row in microgrids:
		if int(row.id)==id: grid=row
	if not enabled or grid.is_empty() or method not in ["field","remote"]: return _result(false,"微电网或操作方式无效。")
	if not grid.pending.is_empty(): return _result(false,"该微电网已有在途切换。")
	if bool(grid.islanded)==island: return _result(false,"微电网已处于目标运行方式。")
	var boundaries: Array=[]
	for line in sim.lines:
		var a_inside: bool=int(line.a) in grid.members
		var b_inside: bool=int(line.b) in grid.members
		if a_inside==b_inside: continue
		if island and line.closed: boundaries.append(int(line.id))
		elif not island and int(line.id) in grid.boundary_lines and not line.fault: boundaries.append(int(line.id))
	if method=="remote":
		for line_id in boundaries:
			if not sim.digital.can_control(sim,int(line_id)): return _result(false,"边界开关需要新鲜观测与可信低时延通信。")
	else:
		if sim.active_repairs()>=2: return _result(false,"现场队正忙，请稍后安排分区切换。")
		if float(sim.cash)<350.0: return _result(false,"现场切换费用不足。")
		sim.record_cash_change(-350.0,"microgrid","微电网分区现场切换")
	grid.pending={"island":island,"method":method,"lines":boundaries,"remaining":0.35 if method=="field" else 0.05}
	grid.receipt="现场队在途" if method=="field" else "远程切换在途"
	return _result(true,"微电网切换已排队，到达时再次验证边界。")

func _execute_switch(sim: RefCounted, grid: Dictionary) -> void:
	var pending: Dictionary=grid.pending
	for id in pending.lines:
		var line: Dictionary=sim.get_line(int(id))
		var valid_boundary: bool=not line.is_empty() and ((int(line.a) in grid.members)!=(int(line.b) in grid.members))
		if not valid_boundary or (not bool(pending.island) and line.fault) or (pending.method=="remote" and not sim.digital.can_control(sim,int(id))):
			grid.receipt="切换被拒绝：边界已变化或通信不可用"
			grid.pending={}
			return
	for id in pending.lines:
		var line: Dictionary=sim.get_line(int(id))
		line.closed=not bool(pending.island)
	if bool(pending.island): grid.boundary_lines=pending.lines.duplicate()
	grid.islanded=bool(pending.island)
	grid.stage=0 if grid.islanded else 2
	grid.restoration_hours=0.0
	grid.receipt="已离网；先恢复关键负荷，再分阶段恢复普通负荷" if grid.islanded else "边界重联完成"
	grid.pending={}
	_event(sim,str(grid.receipt),int(grid.id))

func _microgrid_for(id: int) -> Dictionary:
	for grid in microgrids:
		if id in grid.members: return grid
	return {}

func active_jobs() -> int:
	var count:=0
	for grid in microgrids:
		if not grid.pending.is_empty() and grid.pending.method=="field": count+=1
	return count

func prune(sim: RefCounted) -> void:
	for key in devices.keys():
		if sim.get_building(int(key)).is_empty():
			devices.erase(key)
			telemetry.erase(key)
			_prepared.erase(int(key))
	for index in range(microgrids.size()-1,-1,-1):
		var grid: Dictionary=microgrids[index]
		for field in ["members","critical_ids"]:
			var keep: Array=[]
			for id in grid[field]:
				if not sim.get_building(int(id)).is_empty(): keep.append(int(id))
			grid[field]=keep
		var boundary: Array=[]
		for id in grid.boundary_lines:
			if not sim.get_line(int(id)).is_empty(): boundary.append(int(id))
		grid.boundary_lines=boundary
		if not grid.pending.is_empty():
			for id in grid.pending.lines:
				if sim.get_line(int(id)).is_empty():
					grid.pending={}
					grid.receipt="边界设施已拆除，切换作业取消"
					break
		if grid.members.is_empty(): microgrids.remove_at(index)

func _event(sim: RefCounted, message: String, id: int) -> void:
	events.append({"hour":float(sim.elapsed_hours),"id":id,"message":message})
	while events.size()>100: events.pop_front()
	if sim.has_method("_log"): sim._log(message,"info")

func report(sim: RefCounted) -> Dictionary:
	var rows: Array=[]
	var totals: Dictionary={"pv_mw":0.0,"battery_mwh":0.0,"ev_remaining_mwh":0.0,"shift_debt_mwh":0.0,"compensation":0.0,"missed_ev_mwh":0.0,"pv_generated_mwh":0.0,"pv_self_mwh":0.0}
	for key in devices:
		var b: Dictionary=sim.get_building(int(key))
		if b.is_empty(): continue
		var row: Dictionary=devices[key]
		var display: Dictionary=row.duplicate(true)
		display.id=int(key)
		display.name=str(b.name)
		display.controllable=_reachable(sim,int(key)) and bool(row.consent)
		var sample: Dictionary=telemetry.get(key,{})
		var fresh: bool=not sample.is_empty() and _reachable(sim,int(key)) and float(sim.elapsed_hours)-float(sample.sampled_at)<=0.2
		display.telemetry_visibility="verified" if fresh else ("unknown" if sample.is_empty() else "stale")
		for field in ["energy_mwh","ev_remaining_mwh","shift_debt_mwh","fatigue"]:
			display[field]=sample.get(field,null) if fresh else null
		rows.append(display)
		for field in totals:
			if field in ["ev_remaining_mwh","shift_debt_mwh"]:
				if fresh: totals[field]+=float(sample.get(field,0.0))
			else: totals[field]+=float(row.get(field,0.0))
	return {"enabled":enabled,"customers":rows,"totals":totals,"microgrids":microgrids.duplicate(true),"events":events.duplicate(true)}

func snapshot() -> Dictionary:
	return {"enabled":enabled,"devices":devices.duplicate(true),"microgrids":microgrids.duplicate(true),"events":events.duplicate(true),"telemetry":telemetry.duplicate(true),"next_microgrid_id":next_microgrid_id}

func restore(data: Dictionary) -> void:
	reset()
	enabled=bool(data.get("enabled",false))
	devices=data.get("devices",{}).duplicate(true)
	microgrids=data.get("microgrids",[]).duplicate(true)
	events=data.get("events",[]).duplicate(true)
	telemetry=data.get("telemetry",{}).duplicate(true)
	next_microgrid_id=int(data.get("next_microgrid_id",1))
	for event in events: event.id=int(event.id)
	for grid in microgrids:
		grid.id=int(grid.id)
		grid.stage=int(grid.stage)
		for field in ["members","critical_ids","boundary_lines"]:
			for index in grid[field].size(): grid[field][index]=int(grid[field][index])
		if not grid.pending.is_empty():
			for index in grid.pending.lines.size(): grid.pending.lines[index]=int(grid.pending.lines[index])

static func valid(data: Dictionary) -> bool:
	if not data.get("enabled",false) is bool or not data.get("devices",{}) is Dictionary or not data.get("microgrids",[]) is Array or not data.get("events",[]) is Array or not data.get("telemetry",{}) is Dictionary: return false
	if data.get("devices",{}).size()>512 or data.get("microgrids",[]).size()>16 or data.get("events",[]).size()>100 or not _integer(data.get("next_microgrid_id",1),1,1e9): return false
	for key in data.get("devices",{}):
		if not str(key).is_valid_int() or int(key)<=0 or not data.devices[key] is Dictionary or not _valid_device(data.devices[key]): return false
	var members: Array=[]
	var ids: Array=[]
	for grid in data.get("microgrids",[]):
		if not grid is Dictionary or not _number(grid.get("id",0),1,1e9) or int(grid.id) in ids or floorf(float(grid.id))!=float(grid.id) or int(grid.id)>=int(data.get("next_microgrid_id",1)): return false
		ids.append(int(grid.id))
		if not grid.get("name",null) is String or str(grid.name).length()>40 or not grid.get("members",null) is Array or grid.members.size()>512: return false
		if not grid.get("critical_ids",null) is Array or not grid.get("boundary_lines",null) is Array or grid.boundary_lines.size()>2000 or not grid.get("islanded",null) is bool or not _integer(grid.get("stage",-1),0,2) or not _number(grid.get("restoration_hours",-1),0,1e9) or not grid.get("pending",null) is Dictionary or not grid.get("receipt",null) is String: return false
		for value in grid.members:
			if not _number(value,1,1e9) or floorf(float(value))!=float(value) or int(value) in members: return false
			members.append(int(value))
		for value in grid.critical_ids:
			if not _integer(value,1,1e9) or value not in grid.members: return false
		for value in grid.boundary_lines:
			if not _integer(value,1,1e9): return false
		if not grid.pending.is_empty():
			var p: Dictionary=grid.pending
			if not p.get("island",null) is bool or p.get("method","") not in ["remote","field"] or not _number(p.get("remaining",-1),0,100) or not p.get("lines",null) is Array or p.lines.size()>2000: return false
			for value in p.lines:
				if not _integer(value,1,1e9): return false
	for row in data.get("events",[]):
		if not row is Dictionary or not _number(row.get("hour",-1),0,1e9) or not _number(row.get("id",0),1,1e9) or not row.get("message",null) is String: return false
	if data.get("telemetry",{}).size()>512: return false
	for key in data.get("telemetry",{}):
		if not data.get("devices",{}).has(key) or not data.telemetry[key] is Dictionary: return false
		for field in ["sampled_at","energy_mwh","ev_remaining_mwh","shift_debt_mwh","fatigue"]:
			if not _number(data.telemetry[key].get(field,-1),0,1e12): return false
	return true

static func references_valid(data: Dictionary, ids: Variant, line_ids: Variant) -> bool:
	for key in data.get("devices",{}):
		if not ids.has(int(key)): return false
		if ids is Dictionary and ids[int(key)] is Dictionary and str(ids[int(key)].get("kind","")) not in CUSTOMER_KINDS: return false
	for grid in data.get("microgrids",[]):
		for value in grid.members:
			if not ids.has(int(value)): return false
		for value in grid.boundary_lines:
			if not line_ids.has(int(value)): return false
		if not grid.pending.is_empty():
			for value in grid.pending.lines:
				if not line_ids.has(int(value)): return false
	return true

static func _valid_device(row: Dictionary) -> bool:
	for field in ["metered","consent","smart","grid_forming"]:
		if not row.get(field,null) is bool: return false
	for field in ["participation","fatigue","response_fraction"]:
		if not _number(row.get(field,-1),0,1): return false
	for field in ["pv_mw","battery_mwh","battery_mw","energy_mwh","ev_mw","ev_target_mwh","ev_remaining_mwh","shift_debt_mwh","response_remaining","response_until","ev_deadline","shifted_total_mwh","repaid_total_mwh","curtailed_total_mwh","missed_ev_mwh","compensation","pv_generated_mwh","pv_self_mwh"]:
		if not _number(row.get(field,-1),0,1e12): return false
	if float(row.pv_mw)>100.0 or float(row.battery_mwh)>500.0 or float(row.battery_mw)>100.0 or float(row.ev_mw)>100.0 or float(row.ev_target_mwh)>500.0 or float(row.energy_mwh)>float(row.battery_mwh)+0.00001 or not _number(row.get("deadline_hour",-1),0,23.99): return false
	return row.get("response_kind","") in ["none","shift","curtail"]

static func _number(value: Variant, minimum: float, maximum: float) -> bool:
	return (value is float or value is int) and is_finite(float(value)) and float(value)>=minimum and float(value)<=maximum

static func _integer(value: Variant, minimum: float, maximum: float) -> bool:
	return _number(value,minimum,maximum) and floorf(float(value))==float(value)

static func _result(ok: bool, message: String) -> Dictionary:
	return {"ok":ok,"message":message,"id":-1}
