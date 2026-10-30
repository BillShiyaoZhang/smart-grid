extends RefCounted
## Two voltage classes and source-funded resistive losses. This is a strategic
## approximation: routing limits use shortest supply paths, never an AC solver.

var enabled := false
var line_settings: Dictionary = {}
var substation_settings: Dictionary = {}
var protection_events: Array = []

func reset() -> void:
	enabled = false
	line_settings.clear()
	substation_settings.clear()
	protection_events.clear()

func enable(sim: RefCounted) -> Dictionary:
	if sim.campaign.active: return _result(false,"历史情景使用预设工程规则。")
	enabled = true
	prepare(sim)
	return _result(true,"输配电约束已投运：变电容量、线路损耗与电压质量开始参与运行。")

func configure_line(sim: RefCounted, id: int, tier: String, delay: float = 1.0) -> Dictionary:
	var line: Dictionary = sim.get_line(id)
	if not enabled or line.is_empty(): return _result(false,"先投运输配电管理并选择线路。")
	if tier not in ["distribution","transmission"] or not is_finite(delay) or delay < 0.25 or delay > 2.0:
		return _result(false,"线路等级或保护延时无效。")
	for endpoint in [int(line.a),int(line.b)]:
		if sim.get_building(endpoint).kind == "substation": continue
		for neighbor in sim.lines:
			if int(neighbor.id)==id or endpoint not in [int(neighbor.a),int(neighbor.b)]: continue
			if str(line_settings.get(str(neighbor.id),{}).get("tier","distribution")) != tier:
				return _result(false,"不同电压等级只能在变电站衔接。")
	var previous: Dictionary = line_settings.get(str(id),{"tier":"distribution","delay":1.0})
	var cost := 0.0
	if tier != str(previous.tier):
		var distance: float = Vector2(sim.get_building(int(line.a)).cell).distance_to(Vector2(sim.get_building(int(line.b)).cell))
		cost = 2500.0 + distance * 250.0
	if float(sim.cash)<cost: return _result(false,"资金不足以改造线路。")
	if cost>0.0: sim.record_cash_change(-cost,"engineering","线路 #%d 电压等级改造" % id)
	line_settings[str(id)]={"tier":tier,"delay":delay}
	prepare(sim)
	return _result(true,"线路等级及本地保护延时已应用。")

func connection_allowed(sim: RefCounted, a: int, b: int, tier: String = "distribution") -> bool:
	if not enabled: return true
	for endpoint in [a,b]:
		var building: Dictionary=sim.get_building(endpoint)
		if building.is_empty(): return false
		if building.kind=="substation": continue
		for line in sim.lines:
			if endpoint not in [int(line.a),int(line.b)]: continue
			if str(line_settings.get(str(line.id),{}).get("tier","distribution"))!=tier: return false
	return true

func configure_substation(sim: RefCounted, id: int, capacity: float, zone: String = "") -> Dictionary:
	var b: Dictionary=sim.get_building(id)
	if not enabled or b.is_empty() or b.kind!="substation": return _result(false,"请选择已投运管理的变电站。")
	if not is_finite(capacity) or capacity<10.0 or capacity>500.0 or zone.length()>40:
		return _result(false,"变电容量应在10—500 MW，保护区名称最多40字。")
	var old: float=float(substation_settings.get(str(id),{}).get("capacity",b.capacity))
	var cost: float=maxf(0.0,capacity-old)*180.0
	if float(sim.cash)<cost: return _result(false,"变电站增容资金不足。")
	if cost>0.0: sim.record_cash_change(-cost,"engineering","变电站 #%d 增容" % id)
	substation_settings[str(id)]={"capacity":capacity,"zone":zone if not zone.is_empty() else "馈线区 %d" % id}
	prepare(sim)
	return _result(true,"变电容量与保护分区已应用。")

func prepare(sim: RefCounted) -> void:
	for b in sim.buildings:
		b.network_loss_mw=0.0
		b.delivery_limit=1.0
		b.transformer_loading=0.0
		b.voltage_quality="未投运" if not enabled else "正常"
		if b.kind=="substation":
			var settings: Dictionary=substation_settings.get(str(b.id),{})
			b.transformer_capacity=float(settings.get("capacity",b.capacity))
			b.protection_zone=str(settings.get("zone","馈线区 %d" % int(b.id)))
	for line in sim.lines:
		var settings: Dictionary=line_settings.get(str(line.id),{})
		line.voltage_tier=str(settings.get("tier","distribution"))
		line.protection_delay=float(settings.get("delay",1.0))
		line.loss_mw=0.0

func prepare_component(sim: RefCounted, ids: Array[int]) -> void:
	if not enabled: return
	var sources: Array[int]=[]
	for id in ids:
		var b: Dictionary=sim.get_building(id)
		b.delivery_limit=1.0
		if not b.online: continue
		# A preliminary merit-order dispatch identifies actual producing nodes.
		# Cold, fuel-starved or reserved generators cannot masquerade as sources.
		if float(b.output)>0.000001: sources.append(id)
	if sources.is_empty(): return
	var distances: Dictionary={}
	var previous: Dictionary={}
	var previous_line: Dictionary={}
	var pending: Array[int]=ids.duplicate()
	for id in ids: distances[id]=0.0 if id in sources else INF
	while not pending.is_empty():
		pending.sort_custom(func(a: int,b: int): return float(distances[a])<float(distances[b]))
		var current: int=pending.pop_front()
		if not is_finite(float(distances[current])): break
		for line in sim.lines:
			if not sim.electrical_line_active(line) or current not in [int(line.a),int(line.b)]: continue
			var other: int=int(line.b) if int(line.a)==current else int(line.a)
			if other not in pending: continue
			var length: float=maxf(1.0,Vector2(sim.get_building(current).cell).distance_to(Vector2(sim.get_building(other).cell)))
			var candidate: float=float(distances[current])+length*(0.25 if line.get("voltage_tier","distribution")=="transmission" else 1.0)
			if candidate<float(distances[other]): distances[other]=candidate; previous[other]=current; previous_line[other]=int(line.id)
	var station_loads: Dictionary={}
	var line_loads: Dictionary={}
	var paths: Dictionary={}
	var route_lines: Dictionary={}
	for id in ids:
		var b: Dictionary=sim.get_building(id)
		if float(b.demand)<=0.0: continue
		var path: Array[int]=[]
		var route: Array[int]=[]
		var node: int=id
		for _guard in ids.size():
			if sim.get_building(node).kind=="substation":
				path.append(node)
				station_loads[node]=float(station_loads.get(node,0.0))+float(b.demand)
			if not previous.has(node): break
			var line_id: int=int(previous_line[node])
			route.append(line_id)
			line_loads[line_id]=float(line_loads.get(line_id,0.0))+float(b.demand)
			node=int(previous[node])
		paths[id]=path
		route_lines[id]=route
	for station_id in station_loads:
		var station: Dictionary=sim.get_building(int(station_id))
		station.transformer_loading=float(station_loads[station_id])/maxf(0.1,float(station.get("transformer_capacity",station.capacity)))
	for id in paths:
		var limit:=1.0
		for station_id in paths[id]:
			var station: Dictionary=sim.get_building(station_id)
			limit=minf(limit,1.0/maxf(1.0,float(station.transformer_loading)))
		var drop:=0.0
		for line_id in route_lines[id]:
			var line: Dictionary=sim.get_line(line_id)
			var length: float=maxf(1.0,Vector2(sim.get_building(int(line.a)).cell).distance_to(Vector2(sim.get_building(int(line.b)).cell)))
			drop+=length*(0.00008 if line.get("voltage_tier","distribution")=="transmission" else 0.0008)*float(line_loads[line_id])
		if drop>0.05: limit=minf(limit,clampf((0.25-drop)/0.2,0.1,1.0))
		sim.get_building(id).delivery_limit=limit
	# The path proxy alone would incorrectly let a tiny local generator hide a
	# remote transformer bottleneck. Preliminary DC through-flow independently
	# bounds its downstream recipients, including export terminals.
	var downstream: Dictionary={}
	for id in ids: downstream[id]=[]
	for line in sim.lines:
		if not sim.electrical_line_active(line) or int(line.a) not in ids or int(line.b) not in ids: continue
		if float(line.flow)>0.000001: downstream[int(line.a)].append(int(line.b))
		elif float(line.flow)<-0.000001: downstream[int(line.b)].append(int(line.a))
	for station_id in ids:
		var station: Dictionary=sim.get_building(station_id)
		if station.kind!="substation": continue
		var outgoing:=0.0
		for line in sim.lines:
			if not sim.electrical_line_active(line): continue
			if int(line.a)==station_id: outgoing+=maxf(0.0,float(line.flow))
			elif int(line.b)==station_id: outgoing+=maxf(0.0,-float(line.flow))
		var capacity: float=maxf(0.1,float(station.get("transformer_capacity",station.capacity)))
		station.transformer_loading=maxf(float(station.transformer_loading),outgoing/capacity)
		if outgoing<=capacity: continue
		var factor: float=capacity/(outgoing*1.02)
		var queue: Array[int]=[station_id]
		var visited: Dictionary={station_id:true}
		while not queue.is_empty():
			var current: int=queue.pop_back()
			for next_id in downstream[current]:
				if visited.has(next_id): continue
				visited[next_id]=true
				queue.append(int(next_id))
				var recipient: Dictionary=sim.get_building(int(next_id))
				if float(recipient.demand)>0.0 or float(recipient.output)<-0.000001:
					recipient.delivery_limit=minf(float(recipient.delivery_limit),factor)

func estimate_losses(sim: RefCounted, ids: Array[int]) -> Dictionary:
	var losses: Dictionary={}
	for id in ids: losses[id]=0.0
	if not enabled: return losses
	for line in sim.lines:
		if int(line.a) not in ids or int(line.b) not in ids or not sim.electrical_line_active(line): continue
		var length: float=maxf(1.0,Vector2(sim.get_building(int(line.a)).cell).distance_to(Vector2(sim.get_building(int(line.b)).cell)))
		var resistance: float=length*(0.00003 if line.get("voltage_tier","distribution")=="transmission" else 0.0003)
		var power: float=absf(float(line.flow))
		var loss: float=minf(power*0.15,resistance*power*power)
		line.loss_mw=loss
		losses[int(line.a)]+=loss*0.5
		losses[int(line.b)]+=loss*0.5
	return losses

func update_voltage(sim: RefCounted, ids: Array[int]) -> void:
	if not enabled: return
	var reference: Dictionary={}
	var distance: Dictionary={}
	for id in ids:
		var b: Dictionary=sim.get_building(id)
		b.voltage=1.0 if b.powered or float(b.served)>0.001 or float(b.output)>0.001 else 0.0
		distance[id]=0.0 if float(b.output)>0.01 else INF
		reference[id]=1.0
	for _pass in ids.size():
		var changed:=false
		for line in sim.lines:
			if int(line.a) not in ids or int(line.b) not in ids or not sim.electrical_line_active(line): continue
			var a: int=int(line.a)
			var b: int=int(line.b)
			var length: float=maxf(1.0,Vector2(sim.get_building(a).cell).distance_to(Vector2(sim.get_building(b).cell)))
			var impedance: float=length*(0.00008 if line.get("voltage_tier","distribution")=="transmission" else 0.0008)
			for pair in [[a,b,1.0],[b,a,-1.0]]:
				if float(distance[pair[0]])+length<float(distance[pair[1]]):
					distance[pair[1]]=float(distance[pair[0]])+length
					reference[pair[1]]=clampf(float(reference[pair[0]])-float(line.flow)*float(pair[2])*impedance,0.7,1.12)
					changed=true
		if not changed: break
	for id in ids:
		var b: Dictionary=sim.get_building(id)
		if float(b.voltage)>0.0: b.voltage=float(reference[id])
		b.voltage_quality="停电" if float(b.voltage)<=0.0 else ("低电压" if float(b.voltage)<0.95 else ("高电压" if float(b.voltage)>1.05 else "正常"))

func trip_fault(sim: RefCounted, id: int) -> Dictionary:
	var line: Dictionary=sim.get_line(id)
	if not enabled or line.is_empty(): return _result(false,"请选择有效馈线。")
	line.fault=true
	line.closed=false
	line.trip_reason="分区保护隔离"
	_record(sim,id,"本地分区保护已隔离故障支路，其余支路保留运行。")
	return _result(true,"故障区段已就地隔离，可检查健康联络线转供。")

func advance(sim: RefCounted, dt: float) -> void:
	if not enabled or dt<=0.0: return
	for line in sim.lines:
		if line.fault and line.closed:
			line.closed=false
			line.trip_reason="分区保护隔离"
			_record(sim,int(line.id),"故障支路本地隔离，通信中断不影响保护。")
	for b in sim.buildings:
		if b.kind!="substation" or not b.online: continue
		var outgoing:=0.0
		for line in sim.lines:
			if not sim.electrical_line_active(line): continue
			if int(line.a)==int(b.id): outgoing+=maxf(0.0,float(line.flow))
			elif int(line.b)==int(b.id): outgoing+=maxf(0.0,-float(line.flow))
		var loading: float=outgoing/maxf(0.1,float(b.get("transformer_capacity",b.capacity)))
		b.transformer_heat=maxf(0.0,float(b.get("transformer_heat",0.0))+dt*(loading*loading-1.0))
		if float(b.transformer_heat)<1.0: continue
		var candidate: Dictionary={}
		for line in sim.lines:
			if int(b.id) not in [int(line.a),int(line.b)] or not sim.electrical_line_active(line): continue
			var outward: float=float(line.flow) if int(line.a)==int(b.id) else -float(line.flow)
			if outward<=0.000001: continue
			if candidate.is_empty() or absf(float(line.flow))>absf(float(candidate.flow)): candidate=line
		if not candidate.is_empty():
			candidate.closed=false
			candidate.trip_reason="变电保护分段"
			b.transformer_heat=0.0
			_record(sim,int(candidate.id),"变电容量持续超限，下级重载支路分段退出。")

func _record(sim: RefCounted, id: int, message: String) -> void:
	protection_events.append({"hour":float(sim.elapsed_hours),"line_id":id,"message":message})
	while protection_events.size()>100: protection_events.pop_front()
	if sim.has_method("_log"): sim._log(message,"warning")

func report(sim: RefCounted) -> Dictionary:
	var loss:=0.0
	var minimum:=1.0
	var low:=0
	var stations: Array=[]
	for b in sim.buildings:
		loss+=float(b.get("network_loss_mw",0.0))
		var observed: Dictionary=sim.facility_observation(int(b.id))
		if str(observed.get("visibility","unknown")) in ["verified","field"]:
			var measured_voltage: float=float(observed.get("voltage",0.0)) if observed.get("voltage",null)!=null else 0.0
			if measured_voltage>0.0: minimum=minf(minimum,measured_voltage)
			if measured_voltage>0.0 and measured_voltage<0.95: low+=1
			if b.kind=="substation": stations.append({"id":int(b.id),"capacity":float(b.get("transformer_capacity",b.capacity)),"loading":float(b.get("transformer_loading",0.0)),"zone":str(b.get("protection_zone",""))})
	return {"enabled":enabled,"loss_mw":loss,"minimum_known_voltage":minimum,"known_low_voltage":low,"substations":stations,"events":protection_events.duplicate(true),"approximation":"双电压等级；最短供电路径容量约束；有功损耗与电压近似"}

func prune(sim: RefCounted) -> void:
	for key in line_settings.keys():
		if sim.get_line(int(key)).is_empty(): line_settings.erase(key)
	for key in substation_settings.keys():
		if sim.get_building(int(key)).is_empty(): substation_settings.erase(key)

func snapshot() -> Dictionary:
	return {"enabled":enabled,"lines":line_settings.duplicate(true),"substations":substation_settings.duplicate(true),"events":protection_events.duplicate(true)}

func restore(data: Dictionary) -> void:
	reset()
	enabled=bool(data.get("enabled",false))
	line_settings=data.get("lines",{}).duplicate(true)
	substation_settings=data.get("substations",{}).duplicate(true)
	protection_events=data.get("events",[]).duplicate(true)
	for event in protection_events: event.line_id=int(event.line_id)

static func valid(data: Dictionary) -> bool:
	if not data.get("enabled",false) is bool or not data.get("lines",{}) is Dictionary or not data.get("substations",{}) is Dictionary or not data.get("events",[]) is Array: return false
	if data.get("lines",{}).size()>2000 or data.get("substations",{}).size()>512 or data.get("events",[]).size()>100: return false
	for key in data.get("lines",{}):
		if not str(key).is_valid_int() or int(key)<=0: return false
		var row: Variant=data.lines[key]
		if not row is Dictionary or row.get("tier","") not in ["distribution","transmission"] or not _number(row.get("delay",-1),0.25,2.0): return false
	for key in data.get("substations",{}):
		if not str(key).is_valid_int() or int(key)<=0: return false
		var row: Variant=data.substations[key]
		if not row is Dictionary or not _number(row.get("capacity",-1),10,500) or not row.get("zone","") is String or str(row.zone).length()>40: return false
	for row in data.get("events",[]):
		if not row is Dictionary or not _number(row.get("hour",-1),0,1e9) or not _number(row.get("line_id",-1),1,1e9) or not row.get("message",null) is String: return false
	return true

static func references_valid(data: Dictionary, ids: Variant, line_ids: Variant) -> bool:
	for key in data.get("lines",{}):
		if not line_ids.has(int(key)): return false
	for key in data.get("substations",{}):
		if not ids.has(int(key)): return false
		if ids is Dictionary and ids[int(key)] is Dictionary and str(ids[int(key)].get("kind",""))!="substation": return false
	return true

static func _number(value: Variant, minimum: float, maximum: float) -> bool:
	return (value is float or value is int) and is_finite(float(value)) and float(value)>=minimum and float(value)<=maximum

static func _result(ok: bool, message: String) -> Dictionary:
	return {"ok":ok,"message":message,"id":-1}
