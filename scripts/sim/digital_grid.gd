class_name DigitalGrid
extends RefCounted
## Abstract, entirely offline game model. The communication graph is separate
## from the electrical graph. Queries never advance observations or commands.

const SECURITY_COSTS := [10000.0, 22000.0]
const DEFAULT_STATE := {"security_level": 0, "policy": "open", "next_attack_in": 10.0,
	"blocked_attacks": 0, "detected_incidents": 0, "remote_success": 0,
	"remote_rejected": 0, "security_cost": 0.0, "coverage": 0.0, "trusted_coverage": 0.0}
var state: Dictionary = DEFAULT_STATE.duplicate(true)
var links: Array[Dictionary] = []
var incidents: Array[Dictionary] = []
var pending_commands: Array[Dictionary] = []
var field_jobs: Array[Dictionary] = []
var devices: Dictionary = {}
var observations: Dictionary = {}
var facility_observations: Dictionary = {}
var next_link_id := 1
var next_incident_id := 1
var next_command_id := 1
var next_attack_at := 10.0
var warning_sent := false
# Derived path memoization is excluded from snapshots and observation state.
var _path_signature := 0
var _path_views: Dictionary = {}

func reset(sim: RefCounted, migrate: bool = false) -> void:
	state = DEFAULT_STATE.duplicate(true)
	links.clear()
	incidents.clear()
	pending_commands.clear()
	field_jobs.clear()
	devices.clear()
	observations.clear()
	facility_observations.clear()
	_path_views.clear()
	_path_signature = 0
	next_link_id = 1
	next_incident_id = 1
	next_command_id = 1
	next_attack_at = 10.0 if float(sim.elapsed_hours) < 10.0 else 10.0 + (floorf((float(sim.elapsed_hours) - 10.0) / 36.0) + 1.0) * 36.0
	warning_sent = false
	sync_devices(sim)
	if migrate and not bool(sim.evolution.heritage):
		for line in sim.lines:
			_add_link(int(line.a),int(line.b),"fiber",sim)
		# Schema 1/2 did not store roles; convert their known starter gateway once.
		var legacy_root: Dictionary=sim.get_building(10)
		if legacy_root.get("kind","")=="sensor": devices[10].role="root"
	state.next_attack_in = maxf(0.0, next_attack_at - float(sim.elapsed_hours))

func _digitization_available(sim: RefCounted) -> bool:
	return not bool(sim.evolution.heritage) or sim.evolution.has_technology("scada")

func sync_devices(sim: RefCounted) -> void:
	for building in sim.buildings:
		var id := int(building.id)
		if not devices.has(id):
			var commissioned := _digitization_available(sim)
			devices[id] = {"id":id,"commissioned":commissioned,"role":"root" if building.kind=="control" else "device",
				"ups_remaining":2.0 if commissioned else 0.0,"isolated":false,"compromised":false,"intrusion":false,
				"dos_remaining":0.0,"spoof_remaining":0.0,"recover_remaining":0.0}

func commission_initial(sim: RefCounted, root_id: int) -> void:
	if not _digitization_available(sim): return
	sync_devices(sim)
	var root: Dictionary = sim.get_building(root_id)
	if root.is_empty() or root.kind not in ["sensor","control"]: return
	devices[root_id].role = "root"
	devices[root_id].commissioned = true
	for line in sim.lines:
		var exists := false
		for link in links:
			if [int(link.a),int(link.b)]==[int(line.a),int(line.b)] or [int(link.a),int(link.b)]==[int(line.b),int(line.a)]: exists=true; break
		if not exists: _add_link(int(line.a),int(line.b),"fiber",sim)

func commission_device(sim: RefCounted, id: int, role: String="device") -> Dictionary:
	var building: Dictionary=sim.get_building(id)
	if building.is_empty(): return fail("设备不存在。")
	if not _digitization_available(sim): return fail("历史开局需先研究 SCADA，再投运数字网关。")
	if role not in ["device","root"] or (role=="root" and building.kind not in ["sensor","control"]): return fail("仅智能终端或调度中心可以设置为调度根。")
	sync_devices(sim)
	devices[id].commissioned=true
	devices[id].role=role
	devices[id].ups_remaining=2.0 if building.powered else 0.0
	_path_signature=0
	return ok("数字网关已投运，角色："+("调度根" if role=="root" else "普通设备"),id)

func migrate_roles(sim: RefCounted) -> void:
	# Legacy role is inferred once from scenario metadata and then persisted.
	for building in sim.buildings:
		var id:=int(building.id)
		if not devices.has(id): continue
		var device: Dictionary=devices[id]
		if not device.has("commissioned"): device.commissioned=_digitization_available(sim)
		if not device.has("role"):
			device.role="root" if building.kind=="control" or (building.kind=="sensor" and id==10 and not bool(sim.evolution.heritage)) else "device"
		if not _digitization_available(sim):
			device.commissioned=false
			device.ups_remaining=0.0
	if not _digitization_available(sim):
		links.clear()
		pending_commands.clear()
		incidents.clear()
		observations.clear()
		facility_observations.clear()
	sync_devices(sim)
	_path_signature=0

func prune(sim: RefCounted) -> void:
	for key in devices.keys():
		if sim.get_building(int(key)).is_empty():
			devices.erase(key)
	for i in range(links.size() - 1, -1, -1):
		if sim.get_building(int(links[i].a)).is_empty() or sim.get_building(int(links[i].b)).is_empty():
			links.remove_at(i)
	for key in observations.keys():
		if sim.get_line(int(key)).is_empty():
			observations.erase(key)
	for queue in [pending_commands, field_jobs]:
		for i in range(queue.size() - 1, -1, -1):
			if (queue[i].get("kind","")=="facility" and sim.get_building(int(queue[i].get("building_id",-1))).is_empty()) or (queue[i].get("kind","")!="facility" and sim.get_line(int(queue[i].get("line_id",-1))).is_empty()):
				queue.remove_at(i)
	for key in facility_observations.keys():
		if sim.get_building(int(key)).is_empty(): facility_observations.erase(key)
	for i in range(incidents.size() - 1, -1, -1):
		if sim.get_building(int(incidents[i].target_id)).is_empty():
			incidents.remove_at(i)
		else:
			var affected: Array[int] = []
			for id in incidents[i].affected_ids:
				if not sim.get_building(int(id)).is_empty():
					affected.append(int(id))
			incidents[i].affected_ids = affected

func _device(id: int) -> Dictionary:
	return devices.get(id, {"id": id, "commissioned":false,"role":"device", "ups_remaining": 0.0, "isolated": false,
		"compromised": false, "intrusion": false, "dos_remaining": 0.0,
		"spoof_remaining": 0.0, "recover_remaining": 0.0})

func _operational(sim: RefCounted, id: int) -> bool:
	var building: Dictionary = sim.get_building(id)
	if building.is_empty() or not building.online or not bool(building.get("enabled", true)):
		return false
	var device := _device(id)
	return bool(device.get("commissioned",false)) and not device.isolated and float(device.dos_remaining) <= 0.0 and float(device.recover_remaining) <= 0.0 and (building.powered or float(device.ups_remaining) > 0.000001)

func _root(building: Dictionary) -> bool:
	return bool(_device(int(building.id)).get("commissioned",false)) and _device(int(building.id)).get("role","device")=="root"

func _network_signature(sim: RefCounted) -> int:
	var parts: Array = [state.policy]
	for building in sim.buildings:
		var device := _device(int(building.id))
		parts.append([int(building.id), building.kind, device.get("role","device"), device.get("commissioned",false), bool(building.online), bool(building.get("enabled", true)), bool(building.powered),
			float(device.ups_remaining) > 0.000001, bool(device.isolated), bool(device.compromised),
			float(device.dos_remaining) > 0.0, float(device.recover_remaining) > 0.0])
	for link in links:
		parts.append([int(link.id), int(link.a), int(link.b), bool(link.online), bool(link.fault),
			float(link.repair_remaining) > 0.0, float(link.latency_ms)])
	for incident in incidents:
		parts.append([int(incident.id), bool(incident.detected), str(incident.status), incident.affected_ids])
	return hash(parts)

func _paths(sim: RefCounted, trusted_only: bool, known_only: bool = false) -> Dictionary:
	var signature := _network_signature(sim)
	if signature != _path_signature:
		_path_signature = signature
		_path_views.clear()
	var view_key := int(trusted_only) + int(known_only) * 2
	if _path_views.has(view_key):
		return _path_views[view_key]
	var distances := {}
	var unsettled: Array[int] = []
	for building in sim.buildings:
		var id := int(building.id)
		var device := _device(id)
		if _operational(sim, id) and (not trusted_only or not device.compromised or (known_only and not _known_compromised(id))):
			unsettled.append(id)
			if _root(building):
				distances[id] = 0.0
	var policy_delay := 35.0 if state.policy == "zero_trust" else (12.0 if state.policy == "segmented" else 0.0)
	while not unsettled.is_empty():
		var current := -1
		var best := INF
		for id in unsettled:
			var value: float = distances.get(id, INF)
			if value < best:
				best = value
				current = id
		if current < 0:
			break
		unsettled.erase(current)
		for link in links:
			if not link.online or link.fault or float(link.repair_remaining) > 0.0:
				continue
			var neighbor := int(link.b) if int(link.a) == current else (int(link.a) if int(link.b) == current else -1)
			if neighbor < 0 or not unsettled.has(neighbor):
				continue
			var latency := best + float(link.latency_ms) + policy_delay
			if latency < float(distances.get(neighbor, INF)):
				distances[neighbor] = latency
	_path_views[view_key] = distances
	return distances

func _known_compromised(id: int) -> bool:
	for incident in incidents:
		if incident.detected and incident.status == "active" and incident.affected_ids.has(id):
			return bool(_device(id).compromised)
	return false

func status(sim: RefCounted, id: int) -> Dictionary:
	return _status(sim, id, false)

func _status(sim: RefCounted, id: int, private: bool = true) -> Dictionary:
	var building: Dictionary = sim.get_building(id)
	if building.is_empty():
		return {"reachable": false, "trusted": false, "latency_ms": -1.0, "ups_remaining": 0.0,
			"isolated": false, "compromised": false, "root": false, "reason": "设备不存在"}
	var device := _device(id)
	var reachable := _paths(sim, false)
	var trusted := _paths(sim, true, not private)
	var reason := "可信通信正常"
	if not bool(device.get("commissioned",false)):
		reason = "数字网关尚未投运"
	elif device.isolated:
		reason = "设备已隔离"
	elif float(device.recover_remaining) > 0.0:
		reason = "补丁恢复中"
	elif float(device.dos_remaining) > 0.0:
		reason = "通信暂不可用，正在排查"
	elif not building.online or not bool(building.get("enabled", true)):
		reason = "网关随设备停机"
	elif not building.powered and float(device.ups_remaining) <= 0.000001:
		reason = "失电且网关 UPS 耗尽"
	elif not reachable.has(id):
		reason = "无可用路径到调度网关"
	elif not trusted.has(id):
		reason = "遥测或路径未经可信验证"
	return {"reachable": reachable.has(id), "trusted": trusted.has(id),
		"latency_ms": float(trusted.get(id, reachable.get(id, -1.0))),
		"ups_remaining": float(device.ups_remaining), "isolated": bool(device.isolated),
		"compromised": bool(device.compromised) if private else _known_compromised(id), "commissioned":bool(device.get("commissioned",false)),"role":str(device.get("role","device")), "root": _root(building), "reason": reason}

func get_link(id: int) -> Dictionary:
	for link in links:
		if int(link.id) == id:
			return link
	return {}

func link_cost(sim: RefCounted, a: int, b: int, kind: String) -> float:
	var first: Dictionary = sim.get_building(a)
	var second: Dictionary = sim.get_building(b)
	if first.is_empty() or second.is_empty():
		return 0.0
	var distance := Vector2(first.cell).distance_to(Vector2(second.cell))
	return 1000.0 + distance * 150.0 if kind == "fiber" else 650.0 + distance * 75.0

func connect_link(sim: RefCounted, a: int, b: int, kind: String = "fiber") -> Dictionary:
	if not _digitization_available(sim): return fail("历史开局需先研究 SCADA，再建设通信网络。")
	var first: Dictionary = sim.get_building(a)
	var second: Dictionary = sim.get_building(b)
	if first.is_empty() or second.is_empty() or a == b or kind not in ["fiber", "wireless"]:
		return fail("请选择两座不同的设施和有效通信类型。")
	for link in links:
		if (int(link.a) == a and int(link.b) == b) or (int(link.a) == b and int(link.b) == a):
			return fail("两座设施已有通信链路。")
	var distance := Vector2(first.cell).distance_to(Vector2(second.cell))
	var max_range := 10.0 if first.kind == "relay" or second.kind == "relay" else 6.0
	if kind == "wireless" and distance > max_range:
		return fail("无线距离过远；普通网关 6 格，中继站 10 格。")
	var cost := link_cost(sim, a, b, kind)
	if float(sim.cash) < cost:
		return fail("资金不足。")
	sim.cash -= cost
	var link := _add_link(a, b, kind, sim)
	sync_devices(sim)
	for endpoint in [a,b]:
		devices[endpoint].commissioned=true
	return ok("独立通信链路已建成。", int(link.id))

func _add_link(a: int, b: int, kind: String, sim: RefCounted) -> Dictionary:
	var distance := Vector2(sim.get_building(a).cell).distance_to(Vector2(sim.get_building(b).cell))
	var link := {"id": next_link_id, "a": a, "b": b, "kind": kind, "online": true,
		"fault": false, "latency_ms": 12.0 + distance * 2.0 if kind == "fiber" else 45.0 + distance * 8.0,
		"health": 100.0, "repair_remaining": 0.0, "level": 1}
	next_link_id += 1
	links.append(link)
	return link

func toggle_link(id: int) -> Dictionary:
	var link := get_link(id)
	if link.is_empty():
		return fail("通信链路不存在。")
	if link.fault or float(link.repair_remaining) > 0.0:
		return fail("损坏的通信链路需要先修复。")
	link.online = not link.online
	return ok("通信链路已启用。" if link.online else "通信链路已停用。", id)

func repair_link(sim: RefCounted, id: int) -> Dictionary:
	var link := get_link(id)
	if link.is_empty() or not link.fault:
		return fail("未发现需要修复的通信故障。")
	if float(link.repair_remaining) > 0.0 or sim.active_repairs() >= 2:
		return fail("维修队正在作业或已全部派出。")
	if float(sim.cash) < 650.0:
		return fail("资金不足。")
	sim.cash -= 650.0
	link.repair_remaining = 0.4 if link.kind == "wireless" else 1.0
	link.online = false
	return ok("通信抢修队已派出。", id)

func upgrade_link(sim: RefCounted, id: int) -> Dictionary:
	var link := get_link(id)
	if link.is_empty() or int(link.level) >= 3:
		return fail("链路不存在或已达最高等级。")
	if float(sim.cash) < 2000.0:
		return fail("资金不足。")
	sim.cash -= 2000.0
	link.level += 1
	link.latency_ms *= 0.62
	return ok("通信链路升级，时延已降低。", id)

func _local_sensor(sim: RefCounted, line: Dictionary, trusted_paths: Dictionary) -> bool:
	for id in [int(line.a), int(line.b)]:
		var building: Dictionary = sim.get_building(id)
		if building.is_empty() or building.kind != "sensor" or not trusted_paths.has(id):
			continue
		for link in links:
			if (int(link.a) == id or int(link.b) == id) and link.online and not link.fault and float(link.repair_remaining) <= 0.0 and _operational(sim, int(link.a)) and _operational(sim, int(link.b)):
				return true
	return false

func measurement(sim: RefCounted, line: Dictionary) -> Dictionary:
	var trusted_paths := _paths(sim, true)
	var reachable_paths := _paths(sim, false)
	var capable: bool = int(sim.research_level) >= 1 or _local_sensor(sim, line, trusted_paths)
	var a := int(line.a)
	var b := int(line.b)
	var trusted: bool = capable and (trusted_paths.has(a) or trusted_paths.has(b))
	var reachable: bool = capable and (reachable_paths.has(a) or reachable_paths.has(b))
	var latency := minf(float(trusted_paths.get(a, INF)), float(trusted_paths.get(b, INF)))
	return {"trusted": trusted, "reachable": reachable, "latency_ms": latency if trusted else -1.0}

func line_observation(sim: RefCounted, id: int) -> Dictionary:
	var line: Dictionary = sim.get_line(id)
	var unknown := {"visibility": "unknown", "fault_known": false, "flow": null, "health": null,
		"heat": null, "age_hours": 0.0, "source": "none", "reason": "尚无可信遥测，请建立通信或派现场巡检"}
	if line.is_empty():
		return unknown
	var sample: Dictionary = observations.get(id, {})
	var capabilities := measurement(sim, line)
	var age := maxf(0.0, float(sim.elapsed_hours) - float(sample.get("sampled_at", sim.elapsed_hours)))
	if not sample.is_empty() and sample.source == "patrol" and age <= 1.0:
		return _observed(sample, "patrol", age, "现场核实记录")
	if capabilities.trusted and not sample.is_empty() and sample.source == "telemetry" and age <= 0.20:
		return _observed(sample, "verified", age, "可信网关提供的遥测")
	if capabilities.reachable and not capabilities.trusted:
		unknown.visibility = "suspect"
		unknown.reason = "遥测来源或路径可疑，已拒绝自动控制"
		unknown.age_hours = age
		return unknown
	if not sample.is_empty():
		return _observed(sample, "stale", age, "通信中断或缓存过期；记录不能代表当前状态")
	return unknown

func _observed(sample: Dictionary, visibility: String, age: float, reason: String) -> Dictionary:
	return {"visibility": visibility, "fault_known": visibility in ["verified", "patrol"],
		"fault": bool(sample.fault), "closed": bool(sample.closed), "flow": float(sample.flow),
		"health": float(sample.health), "heat": float(sample.heat), "age_hours": age,
		"source": str(sample.source), "reason": reason}

func _sample(sim: RefCounted, line: Dictionary, source: String) -> void:
	observations[int(line.id)] = {"line_id": int(line.id), "fault": bool(line.fault),
		"closed": bool(line.closed), "flow": float(line.flow), "health": float(line.health),
		"heat": float(line.heat), "sampled_at": float(sim.elapsed_hours), "source": source}

func _sample_facility(sim: RefCounted, building: Dictionary, source: String) -> void:
	facility_observations[int(building.id)]={"building_id":int(building.id),"source":source,"sampled_at":float(sim.elapsed_hours),
		"available":float(building.get("available",0)),"output":float(building.get("output",0)),"served":float(building.get("served",0)),
		"demand":float(building.get("demand",0)),"energy":float(building.get("energy",0)),"health":float(building.get("health",100)),
		"fuel_cost":sim.evolution.fuel_cost(building),"status":sim.evolution.facility_status(sim,building)}

func facility_observation(sim: RefCounted, id: int) -> Dictionary:
	var result: Dictionary={"visibility":"unknown","trusted":false,"reason":"尚无可信设施遥测","age_hours":0.0,
		"available":null,"output":null,"served":null,"demand":null,"energy":null,"health":null,"fuel_cost":null,
		"status":"遥测未确认；额定参数和已提交设定可查看"}
	if sim.get_building(id).is_empty(): result.reason="设施不存在"; return result
	var sample: Dictionary=facility_observations.get(id,{})
	if sample.is_empty(): return result
	var age:=maxf(0.0,float(sim.elapsed_hours)-float(sample.sampled_at))
	result.age_hours=age
	var field_fresh: bool=sample.source=="field" and age<=1.0
	var telemetry_fresh: bool=sample.source=="telemetry" and int(sim.research_level)>=1 and control_reachable(sim,id) and age<=0.20
	if not field_fresh and not telemetry_fresh:
		result.visibility="stale"
		result.reason="通信中断或设施记录过时；当前状态不可用"
		return result
	result.visibility="field" if field_fresh else "verified"
	result.trusted=true
	result.reason="现场核实记录" if field_fresh else "可信设施遥测"
	for key in ["available","output","served","demand","energy","health","fuel_cost","status"]: result[key]=sample[key]
	return result

func can_configure(sim: RefCounted, id: int) -> bool:
	if int(sim.research_level)<2 or not control_reachable(sim,id): return false
	return facility_observation(sim,id).visibility=="verified"

func queue_facility(sim: RefCounted, id: int, settings: Dictionary, method: String="remote") -> Dictionary:
	var building: Dictionary=sim.get_building(id)
	if building.is_empty() or settings.is_empty() or method not in ["remote","field"]: return fail("请选择有效设施、运行设置和执行方式。")
	var validation: Dictionary=sim.evolution.configure(sim,id,settings,false)
	if not validation.ok: return validation
	if float(building.get("repair_remaining",0))>0: return fail("设施正在检修，暂不能提交运行设置。")
	for queue in [pending_commands,field_jobs]:
		for existing in queue:
			if existing.get("kind","")=="facility" and int(existing.get("building_id",-1))==id: return fail("该设施已有在途设置命令。")
	var delay:=0.35
	if method=="remote":
		if not can_configure(sim,id): state.remote_rejected+=1; return fail("设施远程控制需要二级研究、可信低时延路径和新鲜设施遥测。")
		delay=0.05+float(_status(sim,id).latency_ms)/6000.0
	else:
		if sim.active_repairs()>=2: return fail("两支现场队均已派出。")
		if float(sim.cash)<350.0: return fail("现场设置需要 ¥350。")
		sim.cash-=350.0
	var command: Dictionary={"id":next_command_id,"kind":"facility","building_id":id,"settings":settings.duplicate(true),"remaining":delay}
	next_command_id+=1
	if method=="remote": pending_commands.append(command)
	else: field_jobs.append(command)
	return ok("远程设施命令已排队，到达时重新验证。" if method=="remote" else "现场设置队已派出，约21游戏分钟后执行。",int(command.id))

func control_reachable(sim: RefCounted, id: int) -> bool:
	var device_status := _status(sim, id)
	return device_status.trusted and float(device_status.latency_ms) <= 250.0

func can_control(sim: RefCounted, line_id: int) -> bool:
	var line: Dictionary = sim.get_line(line_id)
	if line.is_empty() or int(sim.research_level) < 1:
		return false
	var observation := line_observation(sim, line_id)
	if observation.visibility != "verified":
		return false
	for id in [int(line.a), int(line.b)]:
		var endpoint := _status(sim, id)
		if not endpoint.trusted or float(endpoint.latency_ms) > 250.0:
			return false
	return true

func queue_remote(sim: RefCounted, line_id: int, target_closed: bool) -> Dictionary:
	if not can_control(sim, line_id):
		state.remote_rejected += 1
		return fail("远程控制需要两端可信、低时延通信和新鲜遥测。")
	for command in pending_commands:
		if command.get("kind","")!="facility" and int(command.get("line_id",-1)) == line_id:
			return fail("该线路已有在途远程命令。")
	var line: Dictionary = sim.get_line(line_id)
	if target_closed and (line.fault or float(line.repair_remaining) > 0.0):
		state.remote_rejected += 1
		return fail("故障或检修线路不能远程合闸。")
	var delay := maxf(float(status(sim, int(line.a)).latency_ms), float(status(sim, int(line.b)).latency_ms))
	var command := {"id": next_command_id, "line_id": line_id, "target_closed": target_closed,
		"remaining": 0.05 + delay / 6000.0}
	next_command_id += 1
	pending_commands.append(command)
	return ok("远程命令已排队，到达时会再次验证通信与电气安全。", int(command.id))

func queue_field(sim: RefCounted, line_id: int, kind: String) -> Dictionary:
	var line: Dictionary = sim.get_line(line_id)
	if line.is_empty() or kind not in ["switch", "patrol"]:
		return fail("线路不存在或现场任务无效。")
	if sim.active_repairs() >= 2 or float(line.repair_remaining) > 0.0:
		return fail("两支现场队已派出，或线路正在检修。")
	for job in field_jobs:
		if job.get("kind","")!="facility" and int(job.get("line_id",-1)) == line_id:
			return fail("该线路已有现场队任务。")
	var cost := 500.0 if kind == "patrol" else 350.0
	if float(sim.cash) < cost:
		return fail("资金不足。")
	sim.cash -= cost
	var job := {"id": next_command_id, "line_id": line_id, "kind": kind,
		"target_closed": not bool(line.closed), "remaining": 0.5 if kind == "patrol" else 0.35}
	next_command_id += 1
	field_jobs.append(job)
	return ok("现场巡检队已派出。" if kind == "patrol" else "现场开关操作队已派出。", int(job.id))

func set_policy(policy: String) -> Dictionary:
	if policy not in ["open", "segmented", "zero_trust"]:
		return fail("未知网络安全策略。")
	state.policy = policy
	return ok("安全策略已更新；更严格的验证会增加时延与运行成本。")

func upgrade_security(sim: RefCounted) -> Dictionary:
	var level := int(state.security_level)
	if level >= SECURITY_COSTS.size():
		return fail("网络安全能力已达最高等级。")
	var cost: float = SECURITY_COSTS[level]
	if float(sim.cash) < cost:
		return fail("资金不足。")
	sim.cash -= cost
	state.security_level = level + 1
	return ok("网络安全能力已升级。", level + 1)

func isolate(sim: RefCounted, id: int, isolated: bool) -> Dictionary:
	if sim.get_building(id).is_empty():
		return fail("设备不存在。")
	sync_devices(sim)
	devices[id].isolated = isolated
	return ok("设备已隔离，传播路径和自身遥测均被阻断。" if isolated else "设备已重新接入，仍需通过可信验证。", id)

func recover(sim: RefCounted, id: int) -> Dictionary:
	if sim.get_building(id).is_empty():
		return fail("设备不存在。")
	sync_devices(sim)
	var device: Dictionary = devices[id]
	if float(device.recover_remaining) > 0.0:
		return fail("设备正在恢复中。")
	if float(sim.cash) < 900.0:
		return fail("资金不足。")
	sim.cash -= 900.0
	device.isolated = true
	device.recover_remaining = 0.4 if _soc_online(sim) else 0.75
	return ok("补丁与恢复已开始，完成后重新建立可信连接。", id)

func _soc_online(sim: RefCounted) -> bool:
	for building in sim.buildings:
		if building.kind == "soc" and _operational(sim, int(building.id)) and _status(sim, int(building.id)).trusted:
			return true
	return false

func operating_cost(sim: RefCounted) -> Dictionary:
	var communication := 0.0
	for link in links:
		communication += 8.0 if link.kind == "fiber" else 4.0
	var security := 75.0 if state.policy == "zero_trust" else (30.0 if state.policy == "segmented" else 0.0)
	security += [0.0, 18.0, 42.0][int(state.security_level)]
	for building in sim.buildings:
		if building.kind == "soc" and building.online:
			security += 35.0
	return {"communication": communication, "security": security, "total": communication + security}

func trigger_attack(sim: RefCounted, kind: String = "dos", target_id: int = -1, drill: bool=true) -> Dictionary:
	if kind not in ["dos", "spoof", "intrusion"]:
		return fail("未知演练类型。")
	sync_devices(sim)
	var candidates: Array[int] = []
	for building in sim.buildings:
		if _operational(sim, int(building.id)) and (drill or _paths(sim,false).has(int(building.id))):
			candidates.append(int(building.id))
	if target_id < 0:
		if candidates.is_empty():
			return fail("当前没有可用网关。")
		target_id = candidates[sim.rng.randi_range(0, candidates.size() - 1)]
	if sim.get_building(target_id).is_empty():
		return fail("目标设备不存在。")
	if not bool(_device(target_id).get("commissioned",false)): return fail("目标设备尚未投运数字网关。")
	if not drill and not _paths(sim,false).has(target_id): return fail("设备没有暴露的通信路径。")
	var score := int(state.security_level) + (2 if state.policy == "zero_trust" else (1 if state.policy == "segmented" else 0)) + (1 if _soc_online(sim) else 0)
	var threshold := 3 if kind == "dos" else 2
	var blocked: bool = not _operational(sim, target_id) or score >= threshold or (kind == "intrusion" and state.policy == "zero_trust")
	var incident := {"id": next_incident_id, "kind": kind, "target_id": target_id,
		"status": "blocked" if blocked else "active", "detected": blocked, "remaining": 0.4 if blocked else (1.5 if kind == "dos" else (2.0 if kind == "spoof" else 4.0)),
		"detection_remaining": 0.6 / (1.0 + float(state.security_level) + (2.0 if _soc_online(sim) else 0.0)),
		"description": "安全策略已拦截异常请求。" if blocked else "异常事件尚在分析中。", "drill":drill, "affected_ids": [target_id]}
	next_incident_id += 1
	incidents.append(incident)
	if incidents.size() > 24:
		incidents.pop_front()
	if blocked:
		state.blocked_attacks += 1
		state.detected_incidents += 1
		sim._log("安全系统拦截了异常通信请求。", "success")
		return ok("安全策略成功拦截本次抽象事件。", int(incident.id))
	_apply_compromise(target_id, kind)
	if state.policy == "open":
		for link in links:
			var neighbor := int(link.b) if int(link.a) == target_id else (int(link.a) if int(link.b) == target_id else -1)
			if neighbor > 0 and link.online and not link.fault and _operational(sim, neighbor):
				_apply_compromise(neighbor, kind)
				incident.affected_ids.append(neighbor)
				break
	if kind == "intrusion":
		for line in sim.lines:
			if (int(line.a) == target_id or int(line.b) == target_id) and line.closed and not line.fault and float(line.repair_remaining) <= 0.0:
				line.closed = false
				line.trip_reason = "控制异常"
				sim._log("部分区域报告供电异常，控制状态需要现场或可信遥测核实。", "warning")
				break
	return ok(("本地注入演练" if drill else "外部网络事件")+"已启动，监测与核实需要游戏时间。", int(incident.id))

func _apply_compromise(id: int, kind: String) -> void:
	var device: Dictionary = devices[id]
	if kind == "dos":
		device.dos_remaining = 1.5
	elif kind == "spoof":
		device.spoof_remaining = 2.0
		device.compromised = true
	else:
		device.intrusion = true
		device.compromised = true

func damage_wireless(sim: RefCounted) -> void:
	var candidates: Array[Dictionary] = []
	for link in links:
		if link.kind == "wireless" and not link.fault:
			candidates.append(link)
	if candidates.is_empty():
		return
	var affected: Dictionary = candidates[sim.rng.randi_range(0, candidates.size() - 1)]
	affected.fault = true
	affected.online = false
	affected.health = 25.0
	sim._log("强风导致一条无线通信链路中断，检查通信覆盖与备用路径。", "warning")

func advance(sim: RefCounted, dt: float) -> void:
	if dt <= 0.0:
		return
	sync_devices(sim)
	prune(sim)
	for building in sim.buildings:
		var device: Dictionary = devices[int(building.id)]
		device.ups_remaining = (2.0 if building.powered else maxf(0.0, float(device.ups_remaining) - dt)) if bool(device.get("commissioned",false)) else 0.0
		for key in ["dos_remaining", "spoof_remaining", "recover_remaining"]:
			var previous: float = device[key]
			device[key] = maxf(0.0, previous - dt)
			if key == "recover_remaining" and previous > 0.0 and float(device[key]) <= 0.000001:
				device.recover_remaining = 0.0
				device.intrusion = false
				device.spoof_remaining = 0.0
				device.dos_remaining = 0.0
				device.isolated = false
				sim._log("设备补丁恢复完成，正在重新验证通信。", "success")
		device.compromised = bool(device.intrusion) or float(device.spoof_remaining) > 0.0
	for link in links:
		if float(link.repair_remaining) > 0.0:
			link.repair_remaining = maxf(0.0, float(link.repair_remaining) - dt)
			if float(link.repair_remaining) <= 0.000001:
				link.repair_remaining = 0.0
				link.online = true
				link.fault = false
				link.health = 100.0
				sim._log("通信链路修复完成。", "success")
	_advance_incidents(sim, dt)
	if not _paths(sim,false).is_empty() and not warning_sent and float(sim.elapsed_hours) + 0.000001 >= next_attack_at - 1.0:
		warning_sent = true
		sim._log("通信监测提示异常扫描趋势，请检查网关、安全策略与备用路径。", "warning")
	if float(sim.elapsed_hours) + 0.000001 >= next_attack_at:
		var kinds := ["dos", "spoof", "intrusion"]
		if not _paths(sim,false).is_empty(): trigger_attack(sim, kinds[sim.rng.randi_range(0, 2)],-1,false)
		next_attack_at += 36.0
		warning_sent = false
	state.next_attack_in = maxf(0.0, next_attack_at - float(sim.elapsed_hours))
	sample_verified(sim)
	_advance_commands(sim, dt)
	var summary := summarize(sim)
	state.coverage = summary.coverage
	state.trusted_coverage = summary.trusted
	state.security_cost = summary.security_cost

func _advance_incidents(sim: RefCounted, dt: float) -> void:
	for incident in incidents:
		if incident.status != "active":
			incident.remaining = maxf(0.0, float(incident.remaining) - dt)
			continue
		incident.remaining = maxf(0.0, float(incident.remaining) - dt)
		if not incident.detected:
			incident.detection_remaining = maxf(0.0, float(incident.detection_remaining) - dt * (2.0 if _soc_online(sim) else 1.0))
			if float(incident.detection_remaining) <= 0.000001:
				incident.detected = true
				state.detected_incidents += 1
				incident.description = {"dos": "已确认拒绝服务：网关暂不可达。", "spoof": "已确认遥测来源可疑：自动控制已被拒绝。", "intrusion": "已确认网关入侵：隔离并打补丁，现场核实开关。"}[str(incident.kind)]
				sim._log("安全监测确认异常网关，请隔离设备并启动恢复。", "warning")
		var persistent := false
		for id in incident.affected_ids:
			if bool(_device(int(id)).intrusion):
				persistent = true
		if not persistent and float(incident.remaining) <= 0.000001:
			incident.status = "resolved"
		if incident.kind == "intrusion" and not persistent:
			incident.status = "resolved"

func sample_verified(sim: RefCounted) -> void:
	# Called by the simulation only after a positive-duration physical tick.
	var trusted_paths := _paths(sim, true)
	for building in sim.buildings:
		if int(sim.research_level)>=1 and trusted_paths.has(int(building.id)):
			_sample_facility(sim,building,"telemetry")
		else:
			var sample: Dictionary=facility_observations.get(int(building.id),{})
			if sample.get("source","")=="field" and absf(float(sample.sampled_at)-float(sim.elapsed_hours))<0.000001:
				_sample_facility(sim,building,"field")
	for line in sim.lines:
		var capable: bool = int(sim.research_level) >= 1 or _local_sensor(sim, line, trusted_paths)
		if capable and (trusted_paths.has(int(line.a)) or trusted_paths.has(int(line.b))):
			_sample(sim, line, "telemetry")
		else:
			var sample: Dictionary = observations.get(int(line.id), {})
			if not sample.is_empty() and sample.source == "patrol" and absf(float(sample.sampled_at) - float(sim.elapsed_hours)) < 0.000001:
				_sample(sim, line, "patrol")

func _advance_commands(sim: RefCounted, dt: float) -> void:
	for index in range(pending_commands.size()-1,-1,-1):
		var command: Dictionary=pending_commands[index]
		command.remaining=maxf(0.0,float(command.remaining)-dt)
		if float(command.remaining)>0.000001: continue
		if command.get("kind","")=="facility":
			var building: Dictionary=sim.get_building(int(command.building_id))
			var result: Dictionary=fail("设施或通信状态已变化。")
			if not building.is_empty() and float(building.get("repair_remaining",0))<=0 and can_configure(sim,int(command.building_id)):
				result=sim.evolution.configure(sim,int(command.building_id),command.settings)
			if result.ok:
				state.remote_success+=1
				sim._log("经过验证的远程设施设置已执行。","success")
			else:
				state.remote_rejected+=1
				sim._log("远程设施设置在到达时被拒绝："+str(result.message),"warning")
		else:
			var line: Dictionary=sim.get_line(int(command.line_id))
			if not line.is_empty() and can_control(sim,int(command.line_id)) and (not command.target_closed or (not line.fault and float(line.repair_remaining)<=0.0)):
				line.closed=bool(command.target_closed)
				line.heat=0.0
				line.trip_reason=""
				state.remote_success+=1
				sim._log("经过验证的远程开关命令已执行。","success")
			else:
				state.remote_rejected+=1
				sim._log("在途远程命令未通过到达时验证，已安全拒绝。","warning")
		pending_commands.remove_at(index)
	for index in range(field_jobs.size()-1,-1,-1):
		var job: Dictionary=field_jobs[index]
		job.remaining=maxf(0.0,float(job.remaining)-dt)
		if float(job.remaining)>0.000001: continue
		if job.kind=="facility":
			var building: Dictionary=sim.get_building(int(job.building_id))
			if not building.is_empty() and float(building.get("repair_remaining",0))<=0:
				var result: Dictionary=sim.evolution.configure(sim,int(job.building_id),job.settings)
				if result.ok: _sample_facility(sim,building,"field")
				sim._log("现场设施设置"+("已完成。" if result.ok else "未通过验证："+str(result.message)),"success" if result.ok else "warning")
		else:
			var line: Dictionary=sim.get_line(int(job.line_id))
			if not line.is_empty():
				if job.kind=="switch" and (not job.target_closed or (not line.fault and float(line.repair_remaining)<=0.0)):
					line.closed=bool(job.target_closed)
					line.heat=0.0
					line.trip_reason=""
				_sample(sim,line,"patrol")
				sim._log("现场队已核实线路 #%d：%s。" % [int(line.id),"发现设备损伤" if line.fault else "开关与设备已核实"],"info")
		field_jobs.remove_at(index)

func summarize(sim: RefCounted) -> Dictionary:
	var reachable := _paths(sim, false)
	var trusted := _paths(sim, true, true)
	var online_links := 0
	for link in links:
		if link.online and not link.fault and float(link.repair_remaining) <= 0.0 and _operational(sim, int(link.a)) and _operational(sim, int(link.b)):
			online_links += 1
	var detected_active := 0
	for incident in incidents:
		if incident.detected and incident.status == "active":
			detected_active += 1
	var located := 0
	var actual_trusted := _paths(sim, true)
	for line in sim.lines:
		var sample: Dictionary = observations.get(int(line.id), {})
		if sample.is_empty() or not sample.fault:
			continue
		var age := maxf(0.0, float(sim.elapsed_hours) - float(sample.sampled_at))
		var patrol_fresh: bool = sample.source == "patrol" and age <= 1.0
		var capable: bool = int(sim.research_level) >= 1 or _local_sensor(sim, line, actual_trusted)
		var telemetry_fresh: bool = sample.source == "telemetry" and age <= 0.20 and capable and (actual_trusted.has(int(line.a)) or actual_trusted.has(int(line.b)))
		if patrol_fresh or telemetry_fresh:
			located += 1
	var cost := operating_cost(sim)
	return {"coverage": float(reachable.size()) / maxf(1.0, float(sim.buildings.size())),
		"trusted": float(trusted.size()) / maxf(1.0, float(sim.buildings.size())),
		"online_links": online_links, "total_links": links.size(), "cyber_active": detected_active,
		"security_cost": cost.security, "communication_cost": cost.communication,
		"remote_pending": pending_commands.size(), "located_faults": located}

func snapshot() -> Dictionary:
	var saved_devices: Array = []
	for device in devices.values():
		saved_devices.append(device.duplicate(true))
	var saved_observations: Array = []
	for sample in observations.values():
		saved_observations.append(sample.duplicate(true))
	return {"state": state.duplicate(true), "links": links.duplicate(true),
		"incidents": incidents.duplicate(true), "pending_commands": pending_commands.duplicate(true),
		"field_jobs": field_jobs.duplicate(true), "devices": saved_devices, "observations": saved_observations,
		"facility_observations":facility_observations.values().duplicate(true),
		"next_link_id": next_link_id, "next_incident_id": next_incident_id,
		"next_command_id": next_command_id, "next_attack_at": next_attack_at, "warning_sent": warning_sent}

func load_snapshot(data: Dictionary) -> void:
	state = data.state.duplicate(true)
	for key in ["security_level", "blocked_attacks", "detected_incidents", "remote_success", "remote_rejected"]:
		state[key] = int(state[key])
	links.clear()
	for item in data.links:
		var link: Dictionary = item.duplicate(true)
		for key in ["id", "a", "b", "level"]:
			link[key] = int(link[key])
		links.append(link)
	incidents.clear()
	for item in data.incidents:
		var incident: Dictionary = item.duplicate(true)
		for key in ["id", "target_id"]:
			incident[key] = int(incident[key])
		var affected: Array[int] = []
		for id in incident.affected_ids:
			affected.append(int(id))
		incident.affected_ids = affected
		incidents.append(incident)
	pending_commands.clear()
	field_jobs.clear()
	for pair in [[data.pending_commands, pending_commands], [data.field_jobs, field_jobs]]:
		for item in pair[0]:
			var command: Dictionary = item.duplicate(true)
			command.id = int(command.id)
			if command.get("kind","")=="facility": command.building_id=int(command.building_id)
			else: command.line_id = int(command.line_id)
			pair[1].append(command)
	devices.clear()
	for item in data.devices:
		var device: Dictionary = item.duplicate(true)
		device.id = int(device.id)
		devices[int(device.id)] = device
	observations.clear()
	for item in data.observations:
		var sample: Dictionary = item.duplicate(true)
		sample.line_id = int(sample.line_id)
		observations[int(sample.line_id)] = sample
	facility_observations.clear()
	for item in data.get("facility_observations",[]):
		var sample: Dictionary=item.duplicate(true)
		sample.building_id=int(sample.building_id)
		facility_observations[int(sample.building_id)]=sample
	next_link_id = int(data.next_link_id)
	next_incident_id = int(data.next_incident_id)
	next_command_id = int(data.next_command_id)
	next_attack_at = float(data.next_attack_at)
	warning_sent = bool(data.warning_sent)

static func valid_snapshot(data: Variant, building_ids: Dictionary, line_ids: Dictionary, elapsed: float, strict: bool=false) -> bool:
	if not data is Dictionary or not data.get("state") is Dictionary:
		return false
	for key in ["links", "incidents", "pending_commands", "field_jobs", "devices", "observations"]:
		if not data.get(key) is Array or data[key].size() > 2000:
			return false
	for key in DEFAULT_STATE:
		if not data.state.has(key):
			return false
	if data.state.policy not in ["open", "segmented", "zero_trust"] or not _integer(data.state.security_level, 0, 2):
		return false
	for key in ["blocked_attacks", "detected_incidents", "remote_success", "remote_rejected"]:
		if not _integer(data.state[key], 0, 1000000000):
			return false
	for key in ["coverage", "trusted_coverage"]:
		if not _number(data.state[key], 0.0, 1.0):
			return false
	for key in ["next_attack_in", "security_cost"]:
		if not _number(data.state[key], 0.0, 1e12):
			return false
	for key in ["next_link_id", "next_incident_id", "next_command_id"]:
		if not _integer(data.get(key), 1, 1000000000):
			return false
	if not _number(data.get("next_attack_at"), 0.0, 1e12) or not data.get("warning_sent") is bool:
		return false
	if strict and not data.get("facility_observations") is Array: return false
	var device_ids := {}
	for device in data.devices:
		if not device is Dictionary or not _integer(device.get("id"), 1, 1000000000) or not building_ids.has(int(device.id)) or device_ids.has(int(device.id)):
			return false
		if strict and (not device.get("commissioned") is bool or device.get("role") not in ["device","root"]): return false
		device_ids[int(device.id)] = true
		for key in ["ups_remaining", "dos_remaining", "spoof_remaining", "recover_remaining"]:
			if not _number(device.get(key), 0.0, 2.0):
				return false
		for key in ["isolated", "compromised", "intrusion"]:
			if not device.get(key) is bool:
				return false
		if device.has("commissioned") and not device.commissioned is bool: return false
		if device.has("role") and device.role not in ["device","root"]: return false
		if device.get("role", "device")=="root" and building_ids[int(device.id)] is Dictionary and building_ids[int(device.id)].kind not in ["sensor","control"]: return false
		if bool(device.compromised) != (bool(device.intrusion) or float(device.spoof_remaining) > 0.0):
			return false
	if device_ids.size() != building_ids.size():
		return false
	var comm_ids := {}
	var comm_pairs := {}
	for link in data.links:
		if not link is Dictionary or not _integer(link.get("id"), 1, int(data.next_link_id) - 1) or comm_ids.has(int(link.id)):
			return false
		comm_ids[int(link.id)] = true
		for key in ["a", "b"]:
			if not _integer(link.get(key), 1, 1000000000) or not building_ids.has(int(link[key])):
				return false
		var pair := Vector2i(mini(int(link.a), int(link.b)), maxi(int(link.a), int(link.b)))
		if int(link.a) == int(link.b) or comm_pairs.has(pair) or link.get("kind") not in ["fiber", "wireless"]:
			return false
		comm_pairs[pair] = true
		if link.kind == "wireless" and building_ids[int(link.a)] is Dictionary and building_ids[int(link.b)] is Dictionary:
			var first: Dictionary = building_ids[int(link.a)]
			var second: Dictionary = building_ids[int(link.b)]
			var first_cell := Vector2(float(first.cell[0]), float(first.cell[1]))
			var second_cell := Vector2(float(second.cell[0]), float(second.cell[1]))
			var max_range := 10.0 if first.kind == "relay" or second.kind == "relay" else 6.0
			if first_cell.distance_to(second_cell) > max_range + 0.000001:
				return false
		if not _integer(link.get("level"), 1, 3) or not link.get("online") is bool or not link.get("fault") is bool:
			return false
		if not _number(link.get("latency_ms"), 0.001, 10000.0) or not _number(link.get("health"), 0.0, 100.0) or not _number(link.get("repair_remaining"), 0.0, 1.0):
			return false
	var observation_ids := {}
	for sample in data.observations:
		if not sample is Dictionary or not _integer(sample.get("line_id"), 1, 1000000000) or not line_ids.has(int(sample.line_id)) or observation_ids.has(int(sample.line_id)):
			return false
		observation_ids[int(sample.line_id)] = true
		if sample.get("source") not in ["telemetry", "patrol"] or not sample.get("fault") is bool or not sample.get("closed") is bool:
			return false
		if not _number(sample.get("sampled_at"), 0.0, elapsed + 0.00001) or not _number(sample.get("flow"), -1e6, 1e6):
			return false
		for key in ["health", "heat"]:
			if not _number(sample.get(key), 0.0, 10000.0):
				return false
	var command_ids := {}
	var facility_targets := {}
	for pair in [[data.pending_commands, false], [data.field_jobs, true]]:
		for command in pair[0]:
			if not command is Dictionary or not _integer(command.get("id"), 1, int(data.next_command_id) - 1) or command_ids.has(int(command.id)):
				return false
			command_ids[int(command.id)] = true
			if not _number(command.get("remaining"),0.0,100.0): return false
			if command.get("kind","")=="facility":
				if not _integer(command.get("building_id"),1,1000000000) or not building_ids.has(int(command.building_id)): return false
				if facility_targets.has(int(command.building_id)): return false
				facility_targets[int(command.building_id)]=true
				if not _valid_settings(command.get("settings"),str(building_ids[int(command.building_id)].kind)): return false
			else:
				if not _integer(command.get("line_id"),1,1000000000) or not line_ids.has(int(command.line_id)) or not command.get("target_closed") is bool: return false
				if pair[1] and command.get("kind") not in ["switch","patrol"]: return false
	if data.has("facility_observations"):
		if not data.facility_observations is Array or data.facility_observations.size()>512: return false
		var sample_ids: Dictionary={}
		for sample in data.facility_observations:
			if not sample is Dictionary or not _integer(sample.get("building_id"),1,1000000000) or not building_ids.has(int(sample.building_id)) or sample_ids.has(int(sample.building_id)): return false
			sample_ids[int(sample.building_id)]=true
			if sample.get("source") not in ["telemetry","field"] or not sample.get("status") is String or not _number(sample.get("sampled_at"),0.0,elapsed+0.00001): return false
			for key in ["available","output","served","demand","energy","health","fuel_cost"]:
				if not _number(sample.get(key),-1000000.0 if key=="output" else 0.0,1e9): return false
	if data.field_jobs.size() > 2:
		return false
	var incident_ids := {}
	for incident in data.incidents:
		if not incident is Dictionary or not _integer(incident.get("id"), 1, int(data.next_incident_id) - 1) or incident_ids.has(int(incident.id)):
			return false
		incident_ids[int(incident.id)] = true
		if not _integer(incident.get("target_id"), 1, 1000000000) or not building_ids.has(int(incident.target_id)) or incident.get("kind") not in ["dos", "spoof", "intrusion"] or incident.get("status") not in ["active", "blocked", "resolved"]:
			return false
		if not incident.get("detected") is bool or not incident.get("description") is String or not incident.get("affected_ids") is Array:
			return false
		for key in ["remaining", "detection_remaining"]:
			if not _number(incident.get(key), 0.0, 100.0):
				return false
		for id in incident.affected_ids:
			if not _integer(id, 1, 1000000000) or not building_ids.has(int(id)):
				return false
	return true

static func _valid_settings(settings: Variant, kind: String) -> bool:
	if not settings is Dictionary or settings.is_empty() or settings.size()>12: return false
	for key in settings:
		var value: Variant=settings[key]
		match str(key):
			"enabled":
				if not value is bool or (not value and kind in ["home","factory","hospital"]): return false
			"dispatch":
				if kind not in ["gas","dc_dynamo","steam","coal","hydro","ccgt","nuclear","fusion"] or not _number(value,0,1): return false
			"cooling_mode":
				if kind!="cooling" or value not in ["wet","dry"]: return false
			"boost_cooling":
				if kind!="cooling" or not value is bool: return false
			"flexible_mode":
				if kind not in ["steam","coal","ccgt"] or not value is bool: return false
			"storage_mode":
				if kind not in ["battery","pumped_storage","flow_battery","community_battery","hydrogen","thermal_storage"] or value not in ["auto","hold","peak"]: return false
			"reserve_soc":
				if kind not in ["battery","pumped_storage","flow_battery","community_battery","hydrogen","thermal_storage"] or not _number(value,0,.9): return false
			"peak_hour":
				if kind not in ["battery","pumped_storage","flow_battery","community_battery","hydrogen","thermal_storage"] or not _number(value,0,23): return false
			"environmental_release":
				if kind!="hydro" or not _number(value,.1,.6): return false
			"protection_margin":
				if kind!="substation" or not _number(value,.8,1.2): return false
			_: return false
	return true

static func _number(value: Variant, minimum: float, maximum: float) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value) >= minimum and float(value) <= maximum

static func _integer(value: Variant, minimum: int, maximum: int) -> bool:
	return _number(value, float(minimum), float(maximum)) and float(value) == floorf(float(value))

static func ok(message: String, id: int = -1) -> Dictionary:
	return {"ok": true, "message": message, "id": id}

static func fail(message: String) -> Dictionary:
	return {"ok": false, "message": message, "id": -1}
