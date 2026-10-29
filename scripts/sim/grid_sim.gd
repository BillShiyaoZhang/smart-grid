class_name GridSimulation
extends RefCounted
## Deterministic, headless grid game model. All powers are MW, energy is MWh.
## The DC network uses a flat voltage and length-weighted reactance; it is a
## gameplay approximation, not an AC engineering study.

signal changed
signal event_logged(entry: Dictionary)

const SCHEMA_VERSION := 4
const MarketModel = preload("res://scripts/sim/power_market.gd")
const DigitalModel = preload("res://scripts/sim/digital_grid.gd")
const EvolutionModel = preload("res://scripts/sim/grid_evolution.gd")
const RegionModel = preload("res://scripts/sim/region_world.gd")
const NetworkSolver = preload("res://scripts/sim/dc_network_solver.gd")
const GRID_SIZE := 48
const LINE_COST := 1600.0
const RESEARCH_COSTS := [16000.0, 32000.0]
const CATALOG := {
	"gas": {"name": "燃气电站", "price": 38000.0, "capacity": 24.0, "demand": 0.0, "description": "可调度的稳定电源。燃料有成本，也产生碳排放。", "color": "d48b67"},
	"solar": {"name": "光伏电站", "price": 18000.0, "capacity": 12.0, "demand": 0.0, "description": "白天发电，夜间停机；云层会降低出力。", "color": "5f9fac"},
	"wind": {"name": "风力机组", "price": 24000.0, "capacity": 14.0, "demand": 0.0, "description": "随风况变化，夜间仍可发电。", "color": "9ec8bc"},
	"battery": {"name": "储能电站", "price": 22000.0, "capacity": 10.0, "energy": 30.0, "demand": 0.0, "description": "10 MW / 30 MWh，自动吸收富余电力并在缺电时放电。", "color": "b9c875"},
	"substation": {"name": "变电站", "price": 10000.0, "capacity": 40.0, "demand": 0.0, "description": "扩展电网的连接节点。线路可形成环网以提高韧性。", "color": "e8b65e"},
	"home": {"name": "住宅街区", "price": 8000.0, "capacity": 0.0, "demand": 4.5, "description": "带来电费收入；傍晚是用电高峰。", "color": "dfb9a0"},
	"factory": {"name": "工业园区", "price": 14000.0, "capacity": 0.0, "demand": 11.0, "description": "稳定的大负荷。拓展工业前先检查线路容量。", "color": "b7b3a7"},
	"hospital": {"name": "社区医院", "price": 12000.0, "capacity": 0.0, "demand": 6.0, "description": "关键负荷，缺电时优先供电；医疗电价上限为 145 元/MWh。", "color": "c4d9d2"},
	"control": {"name": "调度中心", "price": 22000.0, "capacity": 0.0, "demand": 0.0, "description": "冗余调度根节点。接入独立通信链路，为全网遥测与远程控制提供路径。", "color": "7faac9"},
	"relay": {"name": "通信中继", "price": 12000.0, "capacity": 0.0, "demand": 0.0, "description": "将无线单跳覆盖从 6 格扩展到 10 格；光纤可靠但造价较高。", "color": "d6be85"},
	"soc": {"name": "安全中心", "price": 18000.0, "capacity": 0.0, "demand": 0.0, "description": "接入可信调度网络后加快异常检测、补丁恢复并协助阻挡抽象网络事件。", "color": "b19ad6"},
	"intertie": {"name": "市场联络站", "price": 32000.0, "capacity": 14.0, "demand": 0.0, "description": "与区域市场交换电力的物理接口，14 MW 双向容量；断线或风暴会限制交易。", "color": "84b7ce"},
	"sensor": {"name": "智能终端", "price": 7000.0, "capacity": 0.0, "demand": 0.0, "description": "为相连线路提供遥测，解锁本地远程开关与故障信息。", "color": "78b5a2"}
}

var market: RefCounted = MarketModel.new()
var digital: RefCounted = DigitalModel.new()
var evolution: RefCounted = EvolutionModel.new()
var region: RefCounted = RegionModel.new()
var catalog: Dictionary = CATALOG.merged(EvolutionModel.EXTRA_CATALOG)
var _dc_solver: RefCounted = NetworkSolver.new()
var sandbox_goal := ""
var sandbox_goal_hours := 0.0
var completed_sandbox_goals: Array[String] = []
var _contract_budget := 0.0
var _pricing_day := -1
var _pricing_hour := -1.0

var buildings: Array[Dictionary] = []
var lines: Array[Dictionary] = []
var cash := 180000.0
var time_hours := 8.0
var day := 1
var weather := "晴朗"
var research_level := 0
var totals: Dictionary = {}
var log_entries: Array[Dictionary] = []
var objectives: Array[Dictionary] = []
var rng := RandomNumberGenerator.new()
var initial_seed := 42
var next_building_id := 1
var next_line_id := 1
var elapsed_hours := 0.0
var storm_count := 0
var restored_storms := 0
var storm_active := false
var storm_remaining := 0.0
var peak_load := 0.0
var total_served_mwh := 0.0
var total_demand_mwh := 0.0
var carbon_tonnes := 0.0
var construction_count := 0
var last_income := 0.0
var last_expenses := 0.0
var demand_response_remaining := 0.0
var auto_restore_timer := 0.0
var next_storm_at := 6.0
var storm_warning_sent := false

func _init() -> void:
	reset()

func reset(seed_value: int = 42) -> void:
	initial_seed = seed_value
	rng.seed = seed_value
	market.reset()
	_dc_solver.clear()
	evolution.reset()
	region.reset()
	sandbox_goal = ""
	sandbox_goal_hours = 0.0
	completed_sandbox_goals.clear()
	_pricing_day = -1
	_pricing_hour = -1.0
	buildings.clear()
	lines.clear()
	log_entries.clear()
	cash = 180000.0
	time_hours = 8.0
	day = 1
	research_level = 0
	next_building_id = 1
	next_line_id = 1
	elapsed_hours = 0.0
	storm_count = 0
	restored_storms = 0
	storm_active = false
	storm_remaining = 0.0
	peak_load = 0.0
	total_served_mwh = 0.0
	total_demand_mwh = 0.0
	carbon_tonnes = 0.0
	construction_count = 0
	demand_response_remaining = 0.0
	auto_restore_timer = 0.0
	next_storm_at = 6.0
	storm_warning_sent = false
	_add_building("gas", Vector2i(3, 7))
	_add_building("substation", Vector2i(6, 7))
	_add_building("home", Vector2i(8, 5))
	_add_building("home", Vector2i(10, 6))
	_add_building("hospital", Vector2i(9, 9))
	_add_building("factory", Vector2i(12, 8))
	_add_building("solar", Vector2i(4, 3))
	_add_building("wind", Vector2i(3, 11))
	_add_building("battery", Vector2i(6, 10))
	_add_building("sensor", Vector2i(7, 7))
	for endpoints in [[1, 2], [2, 3], [3, 4], [2, 5], [7, 2], [8, 9], [9, 2], [2, 10]]:
		_add_line(endpoints[0], endpoints[1])
	objectives = [
		{"id": "industry", "title": "点亮海湾", "description": "把工业园区接入电网，并为全城提供至少 98% 的电力。", "reward": 12000, "done": false, "progress": 0.0},
		{"id": "renewable", "title": "绿色转型", "description": "拥有至少 3 座风电或光伏设施，可再生能源供电占比达到 35%。", "reward": 18000, "done": false, "progress": 0.0},
		{"id": "smart", "title": "可观测的城市", "description": "完成两级智能电网研究，解锁遥测和自动恢复。", "reward": 20000, "done": false, "progress": 0.0},
		{"id": "resilience", "title": "风暴之后", "description": "经历一次风暴，并修复所有故障线路、恢复至少 98% 的供电。", "reward": 25000, "done": false, "progress": 0.0}
	]
	digital.reset(self)
	_update_weather()
	_solve(0.0)
	_log("欢迎来到海湾市。先连接东部工业园区，再建设更清洁、更可靠的电网。", "info")
	changed.emit()

func _add_building(kind: String, cell: Vector2i) -> Dictionary:
	var item: Dictionary = catalog[kind]
	var building := {
		"id": next_building_id, "kind": kind, "cell": cell,
		"name": item.name, "capacity": float(item.capacity), "base_demand": float(item.demand),
		"demand": 0.0, "output": 0.0, "served": 0.0, "powered": false,
		"health": 100.0, "level": 1, "online": true, "soc": 0.5,
		"energy": float(item.get("energy", 0.0)) * 0.5,
		"energy_capacity": float(item.get("energy", 0.0)),
		"dispatch": 1.0, "repair_remaining": 0.0, "charging": 0.0,
		"voltage": 1.0, "angle": 0.0, "available": 0.0,
		"import_mw": 0.0, "export_mw": 0.0, "curtailment_mw": 0.0, "grid_capacity": 0.0
	}
	evolution.initialize_building(building)
	next_building_id += 1
	buildings.append(building)
	digital.sync_devices(self)
	return building

func _add_line(a: int, b: int) -> Dictionary:
	var item := {"id": next_line_id, "a": a, "b": b, "capacity": 24.0,
		"flow": 0.0, "closed": true, "fault": false, "heat": 0.0,
		"health": 100.0, "level": 1, "repair_remaining": 0.0, "trip_reason": ""}
	next_line_id += 1
	lines.append(item)
	return item

func get_building(id: int) -> Dictionary:
	for building in buildings:
		if int(building.id) == id:
			return building
	return {}

func get_line(id: int) -> Dictionary:
	for line in lines:
		if int(line.id) == id:
			return line
	return {}

func building_at(cell: Vector2i) -> Dictionary:
	for building in buildings:
		if building.cell == cell:
			return building
	return {}

func build(kind: String, cell: Vector2i) -> Dictionary:
	if buildings.size() >= 512:
		return _fail("区域设施已达 512 座，请优先改造现有设施。")
	if not catalog.has(kind):
		return _fail("未知设施。")
	var unlocked: Dictionary = evolution.can_build(kind)
	if not unlocked.ok:
		return unlocked
	var placement: Dictionary = evolution.can_place(kind, cell)
	if not placement.ok:
		return placement
	if cell.x < 1 or cell.y < 1 or cell.x >= map_size() - 1 or cell.y >= map_size() - 1:
		return _fail("请在岛屿内部建造。")
	if not building_at(cell).is_empty():
		return _fail("这里已有设施，请选择空地。")
	var price: float = catalog[kind].price
	if cash < price:
		return _fail("资金不足。")
	cash -= price
	var building := _add_building(kind, cell)
	construction_count += 1
	_log("%s已建成；使用线路工具连接电网。" % building.name, "success")
	_refresh()
	return _ok("建造完成，请连接线路。", int(building.id))

func connect_buildings(a: int, b: int) -> Dictionary:
	if lines.size() >= 2000:
		return _fail("区域线路已达 2000 条，请优化现有网络。")
	if a == b:
		return _fail("请选择另一座设施。")
	if get_building(a).is_empty() or get_building(b).is_empty():
		return _fail("线路两端都需要设施。")
	for line in lines:
		if (int(line.a) == a and int(line.b) == b) or (int(line.a) == b and int(line.b) == a):
			return _fail("两座设施间已有线路。")
	var price := connection_cost(a, b)
	if cash < price:
		return _fail("资金不足。")
	cash -= price
	var line := _add_line(a, b)
	_log("新线路投运：%s ↔ %s。" % [get_building(a).name, get_building(b).name], "success")
	_refresh()
	return _ok("线路已连接。", int(line.id))

func connection_cost(a: int, b: int) -> float:
	var first := get_building(a)
	var second := get_building(b)
	if first.is_empty() or second.is_empty():
		return LINE_COST
	return LINE_COST + Vector2(first.cell).distance_to(Vector2(second.cell)) * 300.0

func upgrade(id: int) -> Dictionary:
	var building := get_building(id)
	if building.is_empty():
		return _fail("设施不存在。")
	if int(building.level) >= 3:
		return _fail("已达到最高等级。")
	var price: float = catalog[building.kind].price * 0.65 * float(building.level)
	if cash < price:
		return _fail("资金不足。")
	cash -= price
	building.level += 1
	building.capacity *= 1.5
	building.base_demand *= 1.3
	building.energy_capacity *= 1.5
	building.health = 100.0
	_log("%s升级为 %d 级。" % [building.name, building.level], "success")
	_refresh()
	return _ok("设施已升级。", id)

func upgrade_line(id: int) -> Dictionary:
	var line := get_line(id)
	if line.is_empty():
		return _fail("线路不存在。")
	if int(line.level) >= 3:
		return _fail("线路已达到最高等级。")
	var price := 4500.0 * float(line.level)
	if cash < price:
		return _fail("资金不足。")
	cash -= price
	line.level += 1
	line.capacity *= 1.6
	line.health = 100.0
	line.heat = 0.0
	_log("线路 #%d 已增容至 %.1f MW。" % [id, line.capacity], "success")
	_refresh()
	return _ok("线路已增容。", id)

func repair(id: int) -> Dictionary:
	var building := get_building(id)
	if building.is_empty():
		return _fail("设施不存在。")
	if float(building.repair_remaining) > 0:
		return _fail("维修队正在作业。")
	if float(building.health) >= 99.5 and building.online:
		return _fail("设备状态良好，无需检修。")
	if active_repairs() >= 2:
		return _fail("两支维修队都在作业，请稍候。")
	if cash < 1200.0:
		return _fail("资金不足。")
	cash -= 1200.0
	building.repair_remaining = 0.65
	building.online = false
	_log("维修队前往%s，预计 39 游戏分钟完成检修。" % building.name, "info")
	_refresh()
	return _ok("维修队已派出。", id)

func repair_line(id: int) -> Dictionary:
	var line := get_line(id)
	if line.is_empty():
		return _fail("线路不存在。")
	if float(line.repair_remaining) > 0:
		return _fail("维修队正在作业。")
	for job in digital.field_jobs:
		if int(job.line_id) == id:
			return _fail("该线路已有现场任务。")
	if active_repairs() >= 2:
		return _fail("两支维修队都在作业，请稍候。")
	var observation := line_observation(id)
	var located: bool = observation.fault_known
	if located and not observation.get("fault", false) and float(observation.get("health", 100.0)) > 99.5:
		return _fail("现场或遥测记录显示设备状态良好，可按需执行开关操作。")
	if cash < 900.0:
		return _fail("资金不足。")
	cash -= 900.0
	line.repair_remaining = 0.6 if located else 1.1
	line.closed = false
	_log("维修队已出发，预计 %s 游戏分钟完成%s。" % ["36" if located else "66", "精准抢修" if located else "巡检与抢修"], "info")
	_refresh()
	return _ok("维修队已派出。定位明确节省 30 游戏分钟。", id)

func active_repairs() -> int:
	var count := 0
	for item in buildings + lines:
		if float(item.repair_remaining) > 0:
			count += 1
	count += digital.field_jobs.size()
	for link in digital.links:
		if float(link.repair_remaining) > 0.0:
			count += 1
	return count

func toggle_line(id: int) -> Dictionary:
	var line := get_line(id)
	if line.is_empty():
		return _fail("线路不存在。")
	if line.fault or float(line.repair_remaining) > 0:
		return _fail("故障线路需要先派维修队修复。")
	line.closed = not line.closed
	if line.closed:
		line.heat = 0.0
		line.trip_reason = ""
	_log("线路 #%d %s。" % [id, "已合闸" if line.closed else "已断开"], "info")
	_refresh()
	return _ok("开关操作完成。", id)

func demolish(id: int) -> Dictionary:
	var building := get_building(id)
	if building.is_empty():
		return _fail("设施不存在。")
	if float(building.repair_remaining) > 0:
		return _fail("检修期间无法拆除。")
	cash += float(catalog[building.kind].price) * 0.35
	for index in range(lines.size() - 1, -1, -1):
		if int(lines[index].a) == id or int(lines[index].b) == id:
			lines.remove_at(index)
	buildings.erase(building)
	digital.prune(self)
	region.prune(self)
	_log("已拆除%s，回收 35%% 基础建造费用。" % building.name, "info")
	_refresh()
	return _ok("拆除完成。", id)

func set_dispatch(id: int, ratio: float) -> Dictionary:
	var building := get_building(id)
	if building.is_empty() or building.kind != "gas":
		return _fail("仅燃气机组可设置调度上限。")
	building.dispatch = clampf(ratio, 0.0, 1.0)
	_refresh()
	return _ok("燃气出力上限已调整。", id)

func research() -> Dictionary:
	if evolution.heritage and not evolution.has_technology("scada"):
		return _fail("历史开局需先研究 SCADA 调度接口，再开展遥测与自愈研究。")
	if research_level >= RESEARCH_COSTS.size():
		return _fail("智能电网研究已全部完成。")
	var price: float = RESEARCH_COSTS[research_level]
	if cash < price:
		return _fail("资金不足。")
	cash -= price
	research_level += 1
	if research_level == 1:
		_log("馈线遥测上线：可信且可达的网关可回传线路潮流与故障信息。", "success")
	else:
		_log("自愈控制上线：通过可信低时延通信操作备用线路，需求响应仅面向可控负荷。", "success")
	_refresh()
	return _ok("研究完成。", research_level)

func map_size() -> int:
	return GRID_SIZE if region.active else 16

func start_heritage() -> void:
	reset(initial_seed)
	evolution.heritage = true
	buildings.clear()
	lines.clear()
	next_building_id = 1
	next_line_id = 1
	cash = 120000.0
	var dynamo := _add_building("dc_dynamo", Vector2i(6, 7))
	dynamo.ramp_mw = float(dynamo.capacity)
	_add_building("substation", Vector2i(7, 7))
	_add_building("home", Vector2i(8, 5))
	var industry := _add_building("factory", Vector2i(11, 8))
	industry.base_demand = 3.0
	_add_line(1, 2)
	_add_line(2, 3)
	digital.reset(self)
	log_entries.clear()
	_log("历史开局：先为街区和工坊供电。直流发电坊供电距离短；研究交流技术，逐步迈向区域电网。", "info")
	_refresh()

func research_technology(id: String) -> Dictionary:
	var result: Dictionary = evolution.research(self, id)
	if result.ok:
		_log(result.message, "info")
		_refresh()
	return result

func configure_facility(id: int, settings: Dictionary) -> Dictionary:
	var result: Dictionary = evolution.configure(self, id, settings)
	if result.ok:
		_log(result.message, "info")
		_refresh()
	return result

func facility_status(id: int) -> String:
	var building := get_building(id)
	return evolution.facility_status(self, building) if not building.is_empty() else "设施不存在。"

func expand_region() -> Dictionary:
	var result: Dictionary = region.activate(self)
	if result.ok:
		_log(result.message, "success")
		_refresh()
	return result

func sandbox_goals() -> Array[Dictionary]:
	var definitions: Array[Dictionary] = [
		{"id": "regional", "name": "区域电力共同体", "description": "至少四座城市达到 98% 供电，并保持全网可靠率 ≥98%，连续运营 24 小时。"},
		{"id": "clean", "name": "清洁而可靠", "description": "全网可靠率 ≥98%，可再生能源占比 ≥70%，连续运营 12 小时。"},
		{"id": "profitable", "name": "可持续的公用事业", "description": "全网可靠率 ≥98%，每小时净收益为正，连续运营 24 小时。"}
	]
	for goal in definitions:
		var required := 12.0 if goal.id == "clean" else 24.0
		goal.complete = goal.id in completed_sandbox_goals
		goal.progress = 1.0 if goal.complete else (clampf(sandbox_goal_hours / required, 0.0, 1.0) if sandbox_goal == goal.id else 0.0)
	return definitions

func set_sandbox_goal(id: String) -> Dictionary:
	if id not in ["regional", "clean", "profitable"]:
		return _fail("未知运营目标。")
	if sandbox_goal == id:
		return _ok("已在追踪此目标，持续运营记录保留。")
	sandbox_goal = id
	sandbox_goal_hours = 0.0
	changed.emit()
	return _ok("目标已设定；连续达标计时会在条件失效时重新开始。")

func _advance_sandbox_goal(dt: float) -> void:
	if sandbox_goal.is_empty() or sandbox_goal in completed_sandbox_goals:
		return
	var qualifies := float(totals.reliability) >= 0.98 and float(totals.demand) > 1.0
	match sandbox_goal:
		"regional":
			var supplied := 0
			for city in region.cities:
				if float(city.get("service", 0.0)) >= 0.98:
					supplied += 1
			qualifies = qualifies and region.active and supplied >= 4
		"clean": qualifies = qualifies and float(totals.renewable_share) >= 0.7
		"profitable": qualifies = qualifies and float(totals.income) > float(totals.expenses)
	sandbox_goal_hours = sandbox_goal_hours + dt if qualifies else 0.0
	var required := 12.0 if sandbox_goal == "clean" else 24.0
	if sandbox_goal_hours + 0.000001 >= required:
		completed_sandbox_goals.append(sandbox_goal)
		_log("长期目标达成。你可以在区域规划中选择下一项挑战，或继续自由运营。", "success")

func has_telemetry(line_id: int) -> bool:
	return line_observation(line_id).visibility in ["verified", "patrol"]

func communication_status(building_id: int) -> Dictionary:
	return digital.status(self, building_id)

func line_observation(line_id: int) -> Dictionary:
	return digital.line_observation(self, line_id)

func connect_communication(a: int, b: int, kind: String = "fiber") -> Dictionary:
	return _digital_result(digital.connect_link(self, a, b, kind))

func toggle_communication(id: int) -> Dictionary:
	return _digital_result(digital.toggle_link(id))

func repair_communication(id: int) -> Dictionary:
	return _digital_result(digital.repair_link(self, id))

func upgrade_communication(id: int) -> Dictionary:
	return _digital_result(digital.upgrade_link(self, id))

func remote_switch(id: int) -> Dictionary:
	var line := get_line(id)
	if line.is_empty():
		return _fail("线路不存在。")
	var observation := line_observation(id)
	if observation.visibility != "verified":
		digital.state.remote_rejected += 1
		return _fail("需要新鲜可信遥测，或改派现场开关队。")
	return _digital_result(digital.queue_remote(self, id, not bool(observation.closed)))

func field_switch(id: int) -> Dictionary:
	return _digital_result(digital.queue_field(self, id, "switch"))

func patrol_line(id: int) -> Dictionary:
	return _digital_result(digital.queue_field(self, id, "patrol"))

func set_security_policy(policy: String) -> Dictionary:
	return _digital_result(digital.set_policy(policy))

func upgrade_security() -> Dictionary:
	return _digital_result(digital.upgrade_security(self))

func trigger_cyberattack(kind: String = "dos", target_id: int = -1) -> Dictionary:
	return _digital_result(digital.trigger_attack(self, kind, target_id))

func isolate_device(id: int, isolated: bool = true) -> Dictionary:
	return _digital_result(digital.isolate(self, id, isolated))

func recover_device(id: int) -> Dictionary:
	return _digital_result(digital.recover(self, id))

func _digital_result(result: Dictionary) -> Dictionary:
	if result.ok:
		_log(str(result.message), "info")
		_refresh()
		digital.state.security_cost = float(totals.security_cost)
		digital.state.coverage = float(totals.comm_coverage)
		digital.state.trusted_coverage = float(totals.comm_trusted)
	return result

func demand_response() -> Dictionary:
	if research_level < 2:
		return _fail("先研究自愈控制以解锁需求响应。")
	if demand_response_remaining > 0:
		return _fail("需求响应正在执行。")
	if cash < 1000.0:
		return _fail("资金不足。")
	cash -= 1000.0
	demand_response_remaining = 2.0
	_log("需求响应启动：未来 2 游戏小时，可通过可信通信控制的普通用户负荷下降 20%。", "success")
	_refresh()
	return _ok("需求响应已启动。")

func trigger_storm() -> Dictionary:
	if storm_active:
		return _fail("风暴仍在持续。")
	var candidates: Array[Dictionary] = []
	for line in lines:
		if not line.fault and float(line.repair_remaining) <= 0:
			candidates.append(line)
	if candidates.is_empty():
		return _fail("没有可受风暴影响的线路。")
	storm_active = true
	storm_remaining = 2.5
	storm_count += 1
	var affected: Dictionary = candidates[rng.randi_range(0, candidates.size() - 1)]
	affected.fault = true
	affected.closed = false
	affected.health = 25.0
	affected.trip_reason = "风暴损坏"
	_log("强风登陆！部分区域报告供电异常，保护已就地隔离故障。请用可信遥测或巡检定位受损区段。", "danger")
	if candidates.size() >= 10:
		var second: Dictionary = candidates[rng.randi_range(0, candidates.size() - 1)]
		if second.id != affected.id:
			second.fault = true
			second.closed = false
			second.health = 35.0
			second.trip_reason = "风暴损坏"
			_log("更多区域报告供电异常，请核实备用路径与现场信息。", "danger")
	digital.damage_wireless(self)
	_refresh()
	return _ok("风暴已抵达，先定位故障区段。")

func step(hours: float) -> void:
	if hours <= 0.0 or not is_finite(hours):
		return
	var remaining := minf(hours, 48.0)
	while remaining > 0.000001:
		var dt := minf(remaining, 0.05)
		# Split every wholesale/retail band boundary as well as midnight.
		for boundary in [7.0, 11.0, 15.0, 17.0, 21.0, 23.0, 24.0]:
			var distance: float = boundary - time_hours
			if distance > 0.000001:
				dt = minf(dt, distance)
				break
		if float(market.state.contract_remaining) > 0.000001:
			dt = minf(dt, float(market.state.contract_remaining))
		_tick(dt)
		remaining -= dt
	changed.emit()

func _tick(dt: float) -> void:
	var settlement_day := day
	_pricing_day = day
	_pricing_hour = time_hours + dt * 0.5
	elapsed_hours += dt
	time_hours += dt
	if time_hours >= 24.0:
		time_hours -= 24.0
		day += 1
		_log("第 %d 天开始。需求随城市发展缓慢增长，请规划备用容量。" % day, "info")
	if storm_active:
		storm_remaining = maxf(0.0, storm_remaining - dt)
		if storm_remaining <= 0.0:
			storm_active = false
			_log("风暴已离开海湾。修复受损设备，恢复全网供电。", "info")
	_update_storm_schedule()
	demand_response_remaining = maxf(0.0, demand_response_remaining - dt)
	for building in buildings:
		if float(building.repair_remaining) > 0:
			building.repair_remaining = maxf(0.0, float(building.repair_remaining) - dt)
			if building.repair_remaining <= 0.000001:
				building.repair_remaining = 0.0
				building.health = 100.0
				building.online = true
				_log("%s检修完成，恢复运行。" % building.name, "success")
		elif building.online:
			building.health = maxf(5.0, float(building.health) - dt * 0.025)
	for line in lines:
		if float(line.repair_remaining) > 0:
			line.repair_remaining = maxf(0.0, float(line.repair_remaining) - dt)
			if line.repair_remaining <= 0.000001:
				line.repair_remaining = 0.0
				line.health = 100.0
				line.fault = false
				line.closed = true
				line.heat = 0.0
				line.trip_reason = ""
				digital._sample(self, line, "patrol")
				_log("线路 #%d 抢修完成，已合闸恢复供电。" % line.id, "success")
	_update_weather()
	evolution.advance(self, dt)
	digital.advance(self, dt)
	if research_level >= 2:
		auto_restore_timer += dt
		if auto_restore_timer >= 0.1:
			auto_restore_timer = 0.0
			_auto_restore()
	# Protection evaluates a query first; commit storage energy exactly once,
	# after any breaker trips, so bills and MWh match the final physical flow.
	_solve(0.0)
	for line in lines:
		var loading := absf(float(line.flow)) / maxf(0.1, float(line.capacity))
		if line.closed and not line.fault and loading > 1.0:
			line.heat += dt * (loading * loading - 1.0) * 2.0
			line.health = maxf(10.0, float(line.health) - dt * (loading - 1.0) * 2.0)
			if line.heat >= evolution.line_trip_threshold(self, line):
				line.closed = false
				line.trip_reason = "持续过载"
				var observed := line_observation(int(line.id))
				if observed.visibility in ["verified", "patrol"]:
					_log("已监测线路 #%d 持续过载，保护已就地跳闸。" % int(line.id), "danger")
				else:
					_log("部分区域报告失电，原因与开关状态需要核实。", "warning")
		else:
			line.heat = maxf(0.0, float(line.heat) - dt * 0.8)
	_solve(dt)
	digital.sample_verified(self)
	last_income = float(totals.income)
	last_expenses = float(totals.expenses)
	cash += (last_income - last_expenses) * dt
	var contract_was_active: bool = float(market.state.contract_remaining) > 0.0
	market.settle(dt, settlement_day, totals)
	totals.satisfaction = float(market.state.satisfaction)
	totals.income = last_income
	totals.expenses = last_expenses
	total_served_mwh += float(totals.served) * dt
	total_demand_mwh += float(totals.demand) * dt
	totals.reliability_lifetime = total_served_mwh / total_demand_mwh if total_demand_mwh > 0.000001 else 1.0
	carbon_tonnes += float(totals.get("carbon", 0.0)) * dt
	totals.carbon_total = carbon_tonnes
	region.advance(self, dt)
	_advance_sandbox_goal(dt)
	if storm_count > restored_storms and _fault_count() == 0 and float(totals.reliability) >= 0.98:
		restored_storms = storm_count
		_log("全网供电已恢复。环网、储能与快速抢修让城市更有韧性。", "success")
	_update_objectives()
	if contract_was_active and float(market.state.contract_remaining) <= 0.0:
		_log("固定供电合约已履行完毕，可按新报价签订下一份合约。", "info")
	_pricing_day = -1
	_pricing_hour = -1.0
	# Refresh display at the interval endpoint; this query cannot settle bills
	# or advance battery energy, contracts, customer sentiment or the ledger.
	_solve(0.0)

func _update_storm_schedule() -> void:
	# A fixed forecast is independent of random damage selection, so weather
	# remains reproducible even when the player runs a manual emergency drill.
	if not storm_warning_sent and elapsed_hours + 0.000001 >= next_storm_at - 1.0:
		storm_warning_sent = true
		_log("气象预警：约 1 游戏小时后强风将抵达海湾，请检查备用路径与维修队。", "warning")
	if elapsed_hours + 0.000001 >= next_storm_at and not storm_active:
		trigger_storm()
		next_storm_at += 30.0
		storm_warning_sent = false

func _default_next_storm_time() -> float:
	# Schema 1 saves from before forecasts existed resume at the next future
	# forecast instead of immediately applying every missed historic storm.
	if elapsed_hours + 0.000001 < 6.0:
		return 6.0
	return 6.0 + (floorf((elapsed_hours + 0.000001 - 6.0) / 30.0) + 1.0) * 30.0

func _update_weather() -> void:
	if storm_active:
		weather = "风暴"
	elif sin(float(day) * 1.7 + time_hours * 0.11) < -0.3:
		weather = "多云"
	elif sin(float(day) * 0.8 + time_hours * 0.22) > 0.5:
		weather = "有风"
	else:
		weather = "晴朗"

func solar_factor() -> float:
	var daylight := maxf(0.0, sin((time_hours - 6.0) * PI / 12.0))
	var clouds := 0.34 if storm_active else (0.60 if weather == "多云" else 1.0)
	return daylight * clouds

func wind_factor() -> float:
	if storm_active:
		return 0.24
	return clampf(0.52 + sin(elapsed_hours * 0.4 + 0.7) * 0.2 + sin(elapsed_hours * 0.13) * 0.13, 0.15, 0.95)

func demand_factor(kind: String) -> float:
	var profile_day := _pricing_day if _pricing_day >= 0 else day
	var profile_hour := _pricing_hour if _pricing_hour >= 0.0 else time_hours
	var growth := 1.0 if region.active else 1.0 + minf(0.6, float(profile_day - 1) * 0.025)
	if kind == "home":
		var evening := exp(-pow((profile_hour - 19.0) / 3.0, 2.0))
		return growth * (0.65 + evening * 0.75)
	if kind == "factory":
		return growth * (1.0 if profile_hour >= 7.0 and profile_hour < 21.0 else 0.65)
	return growth

func set_tariff(mode: String, valley: float = 85.0, flat: float = 145.0, peak: float = 220.0) -> Dictionary:
	var result: Dictionary = market.set_tariff(mode, valley, flat, peak)
	if result.ok:
		_log(result.message, "info")
		_refresh()
	return result

func set_market_policy(mode: String, buy_limit: float = 120.0, sell_floor: float = 90.0) -> Dictionary:
	var result: Dictionary = market.set_policy(mode, buy_limit, sell_floor)
	if result.ok:
		_log(result.message, "info")
		_refresh()
	return result

func set_storage_policy(mode: String, charge_price: float = 60.0, discharge_price: float = 150.0, reserve: float = 0.2) -> Dictionary:
	var result: Dictionary = market.set_storage(mode, charge_price, discharge_price, reserve)
	if result.ok:
		_log(result.message, "info")
		_refresh()
	return result

func sign_supply_contract(mw: float, hours: float = 12.0) -> Dictionary:
	market.update_prices(day, time_hours, weather)
	var capacity := 0.0
	for building in buildings:
		if evolution.is_terminal(str(building.kind)) and building.online:
			capacity += _terminal_capacity(building)
	var result: Dictionary = market.sign_contract(mw, hours, capacity, market.quote_for(day, time_hours, weather, hours))
	if result.ok:
		_log(result.message, "info")
		_refresh()
	return result

func market_forecast() -> Array[Dictionary]:
	return market.forecast(day, time_hours, weather)

func _solve(dt: float) -> void:
	market.update_prices(_pricing_day if _pricing_day >= 0 else day, _pricing_hour if _pricing_hour >= 0.0 else time_hours, weather)
	_contract_budget = float(market.state.contract_mw) if float(market.state.contract_remaining) > 0.0 and market.state.market_mode != "off" else 0.0
	var adjacency := {}
	for building in buildings:
		adjacency[int(building.id)] = []
		building.output = 0.0
		building.served = 0.0
		building.powered = false
		building.charging = 0.0
		building.angle = 0.0
		building.available = 0.0
		building.import_mw = 0.0
		building.export_mw = 0.0
		building.curtailment_mw = 0.0
		building.grid_capacity = _terminal_capacity(building) if evolution.is_terminal(str(building.kind)) and building.online else 0.0
		building.demand = evolution.demand_for(self, building) * demand_factor(str(building.kind)) * market.demand_multiplier(str(building.kind)) * region.demand_multiplier(building)
		if demand_response_remaining > 0.0 and building.kind in ["home", "factory"]:
			if digital.control_reachable(self, int(building.id)):
				building.demand *= 0.8
	for line in lines:
		line.flow = 0.0
		if line.closed and not line.fault and float(line.repair_remaining) <= 0 and adjacency.has(int(line.a)) and adjacency.has(int(line.b)):
			adjacency[int(line.a)].append(int(line.b))
			adjacency[int(line.b)].append(int(line.a))
	var visited := {}
	var contract_delivered := 0.0
	for building in buildings:
		var id := int(building.id)
		if visited.has(id):
			continue
		var component: Array[int] = []
		var queue: Array[int] = [id]
		visited[id] = true
		while not queue.is_empty():
			var current: int = queue.pop_back()
			component.append(current)
			for neighbor in adjacency[current]:
				if not visited.has(int(neighbor)):
					visited[int(neighbor)] = true
					queue.append(int(neighbor))
		contract_delivered += _solve_component(component, dt)
	var demand := 0.0
	var served := 0.0
	var generation := 0.0
	var renewable := 0.0
	var gas := 0.0
	var fuel_cost := 0.0
	var carbon := 0.0
	var committed_spill := 0.0
	var battery_energy := 0.0
	var battery_power := 0.0
	var charging := 0.0
	var import_mw := 0.0
	var export_mw := 0.0
	var curtailment := 0.0
	var grid_capacity := 0.0
	var retail_income := 0.0
	for building in buildings:
		demand += float(building.demand)
		served += float(building.served)
		var customer_rate := minf(145.0, float(market.state.retail_price)) if building.kind == "hospital" else float(market.state.retail_price)
		retail_income += float(building.served) * customer_rate
		if not evolution.is_terminal(str(building.kind)):
			generation += maxf(0.0, float(building.output))
		charging += float(building.charging)
		import_mw += float(building.import_mw)
		export_mw += float(building.export_mw)
		curtailment += float(building.curtailment_mw)
		grid_capacity += float(building.grid_capacity)
		if building.kind in ["solar", "wind", "hydro"]:
			renewable += float(building.output)
		if evolution.is_generator(str(building.kind)):
			var committed := maxf(float(building.output), minf(float(building.available), evolution.generator_minimum(building)))
			fuel_cost += evolution.fuel_cost(building)
			carbon += evolution.carbon_rate(building)
			committed_spill += maxf(0.0, committed - float(building.output))
		if building.kind == "gas":
			gas += float(building.output)
		if evolution.is_storage(str(building.kind)):
			battery_energy += float(building.energy)
			battery_power += float(building.output) - float(building.charging)
	peak_load = maxf(peak_load, demand)
	var outage_cost := maxf(0.0, demand - served) * 60.0
	var export_income := export_mw * float(market.state.export_price)
	var import_cost := maxf(0.0, import_mw - contract_delivered) * float(market.state.spot_price)
	var contract_cost := float(market.state.contract_mw) * float(market.state.contract_price) if float(market.state.contract_remaining) > 0.0 else 0.0
	var comm: Dictionary = digital.summarize(self)
	var maintenance_cost: float = float(buildings.size()) * 9.0 + float(lines.size()) * 2.0 + float(comm.communication_cost) + float(comm.security_cost) + evolution.operating_cost(self)
	var max_loading := 0.0
	for line in lines:
		max_loading = maxf(max_loading, absf(float(line.flow)) / maxf(0.1, float(line.capacity)))
	totals = {"demand": demand, "generation": generation, "served": served,
		"renewable_share": renewable / (generation + import_mw) if generation + import_mw > 0.0001 else 0.0,
		"reliability": served / demand if demand > 0.0001 else 1.0,
		"income": retail_income + export_income, "expenses": fuel_cost + maintenance_cost + outage_cost + import_cost + contract_cost,
		"retail_income": retail_income, "export_income": export_income, "import_cost": import_cost,
		"contract_cost": contract_cost, "fuel_cost": fuel_cost, "maintenance_cost": maintenance_cost,
		"import_mw": import_mw, "export_mw": export_mw, "contract_import_mw": contract_delivered,
		"market_price": float(market.state.spot_price), "retail_price": float(market.state.retail_price),
		"satisfaction": float(market.state.satisfaction), "curtailment_mw": curtailment,
		"grid_capacity": grid_capacity, "charging_mw": charging,
		"energy_balance_error": generation + import_mw - served - charging - export_mw,
		"outage_cost": outage_cost, "reliability_lifetime": total_served_mwh / total_demand_mwh if total_demand_mwh > 0.000001 else 1.0,
		"storm_in": maxf(0.0, next_storm_at - elapsed_hours),
		"battery_mwh": battery_energy, "battery_power": battery_power, "peak_load": peak_load,
		"carbon": carbon, "carbon_total": carbon_tonnes, "gas_output": gas, "renewable_output": renewable,
		"committed_spill_mw": committed_spill,
		"max_loading": max_loading, "outage": maxf(0.0, demand - served), "faults": _fault_count(),
		"customers": int(served * 320.0), "crews_busy": active_repairs(),
		"comm_coverage": comm.coverage, "comm_trusted": comm.trusted,
		"comm_online_links": comm.online_links, "comm_total_links": comm.total_links,
		"cyber_active": comm.cyber_active, "security_cost": comm.security_cost,
		"communication_cost": comm.communication_cost, "remote_pending": comm.remote_pending, "located_faults": comm.located_faults}

func _terminal_capacity(building: Dictionary) -> float:
	return evolution.terminal_capacity(self, building)

func _solve_component(ids: Array[int], dt: float) -> float:
	var generators: Array[Dictionary] = []
	var renewable: Array[Dictionary] = []
	var batteries: Array[Dictionary] = []
	var loads: Array[Dictionary] = []
	var terminals: Array[Dictionary] = []
	var demand := 0.0
	var renewable_available := 0.0
	var gas_available := 0.0
	var minimum_available := 0.0
	var transfer_capacity := 0.0
	for id in ids:
		var building := get_building(id)
		if float(building.demand) > 0.0:
			loads.append(building)
			if building.online:
				demand += float(building.demand)
		if not building.online:
			continue
		var derating := 0.7 + float(building.health) * 0.003
		if building.kind == "solar" or building.kind == "wind":
			if not bool(building.get("enabled", true)):
				continue
			var factor := solar_factor() if building.kind == "solar" else wind_factor()
			building.available = float(building.capacity) * factor * derating
			renewable_available += float(building.available)
			renewable.append(building)
		elif evolution.is_generator(str(building.kind)):
			building.available = evolution.generator_available(self, building, ids)
			gas_available += float(building.available)
			minimum_available += minf(float(building.available), evolution.generator_minimum(building))
			generators.append(building)
		elif evolution.is_storage(str(building.kind)):
			if bool(building.get("enabled", true)):
				batteries.append(building)
		elif evolution.is_terminal(str(building.kind)):
			terminals.append(building)
			transfer_capacity += float(building.grid_capacity)
	var can_trade: bool = transfer_capacity > 0.000001 and market.state.market_mode != "off"
	var trade_mode: bool = can_trade and market.state.market_mode == "trade"
	var arbitrage: bool = market.state.storage_mode == "arbitrage"
	var spot: float = market.state.spot_price
	var can_buy: bool = can_trade and spot <= float(market.state.buy_limit)
	var baseload_used := minf(minimum_available, demand)
	var renew_used := minf(renewable_available, maxf(0.0, demand - baseload_used))
	var deficit := maxf(0.0, demand - renew_used - baseload_used)
	# A committed take-or-pay delivery has no extra marginal cost, but cannot
	# be dispatched across a disconnected island or resold as free energy.
	var contract_used := minf(deficit, minf(transfer_capacity, _contract_budget)) if can_trade else 0.0
	_contract_budget -= contract_used
	var imports := contract_used
	deficit -= contract_used
	var battery_discharge := 0.0
	if arbitrage and spot >= float(market.state.discharge_price):
		battery_discharge = _discharge_batteries(batteries, deficit, dt, true)
		deficit -= battery_discharge
	# Trading substitutes cheap off-peak purchases for fuel. Balanced mode
	# keeps local generators and reserves ahead of emergency spot imports.
	if trade_mode and can_buy and spot < 68.0:
		var cheap_import := minf(deficit, maxf(0.0, transfer_capacity - imports))
		imports += cheap_import
		deficit -= cheap_import
	var gas_extra := minf(maxf(0.0, gas_available - baseload_used), deficit)
	var gas_used := baseload_used + gas_extra
	deficit -= gas_extra
	var battery_extra := _discharge_batteries(batteries, deficit, dt, arbitrage)
	battery_discharge += battery_extra
	deficit -= battery_extra
	if can_buy:
		var emergency_import := minf(deficit, maxf(0.0, transfer_capacity - imports))
		imports += emergency_import
		deficit -= emergency_import
	var served_supply := maxf(0.0, demand - deficit)
	var surplus := maxf(0.0, renewable_available - renew_used)
	var charging := 0.0
	if battery_discharge <= 0.000001:
		var baseload_charge := _charge_batteries(batteries, maxf(0.0, minimum_available - gas_used), dt)
		gas_used += baseload_charge
		var renewable_charge := _charge_batteries(batteries, surplus, dt)
		charging = baseload_charge + renewable_charge
		renew_used += renewable_charge
		surplus -= renewable_charge
		if arbitrage and can_trade and deficit <= 0.000001 and spot <= float(market.state.charge_price):
			var import_room := maxf(0.0, transfer_capacity - imports)
			var contract_charge := minf(import_room, _contract_budget)
			var allowed_charge := import_room if can_buy else contract_charge
			var bought_charge := _charge_batteries(batteries, allowed_charge, dt)
			var extra_contract := minf(contract_charge, bought_charge)
			_contract_budget -= extra_contract
			contract_used += extra_contract
			imports += bought_charge
			charging += bought_charge
	var exports := 0.0
	if trade_mode and imports <= 0.000001 and float(market.state.export_price) >= float(market.state.sell_floor):
		var renewable_export := minf(surplus, transfer_capacity)
		exports += renewable_export
		renew_used += renewable_export
		surplus -= renewable_export
		if arbitrage and spot >= float(market.state.discharge_price) and charging <= 0.000001:
			var battery_export := _discharge_batteries(batteries, maxf(0.0, transfer_capacity - exports), dt, true)
			exports += battery_export
			battery_discharge += battery_export
		# Serve local customers first, then offer spare dispatchable capacity
		# only when the export settlement price exceeds marginal fuel cost.
		if float(market.state.export_price) > 68.0:
			var gas_export := minf(maxf(0.0, gas_available - gas_used), maxf(0.0, transfer_capacity - exports))
			gas_used += gas_export
			exports += gas_export
	for building in renewable:
		building.output = float(building.available) * renew_used / renewable_available if renewable_available > 0.0 else 0.0
		building.curtailment_mw = maxf(0.0, float(building.available) - float(building.output))
	for building in generators:
		var committed := minf(float(building.available), evolution.generator_minimum(building))
		var base_share := committed * minf(1.0, gas_used / minimum_available) if minimum_available > 0.0 else 0.0
		var flexible_share := (float(building.available) - committed) * maxf(0.0, gas_used - minimum_available) / (gas_available - minimum_available) if gas_available > minimum_available else 0.0
		building.output = base_share + flexible_share
		building.curtailment_mw = maxf(0.0, committed - float(building.output))
	for terminal in terminals:
		var share := float(terminal.grid_capacity) / transfer_capacity if transfer_capacity > 0.0 else 0.0
		terminal.import_mw = imports * share
		terminal.export_mw = exports * share
		terminal.output = (imports - exports) * share
	# Allocate critical load first, then proportional service for other users.
	var remaining_supply := served_supply
	for building in loads:
		if building.kind == "hospital" and building.online:
			building.served = minf(float(building.demand), remaining_supply)
			remaining_supply -= float(building.served)
	var normal_demand := 0.0
	for building in loads:
		if building.kind != "hospital" and building.online:
			normal_demand += float(building.demand)
	for building in loads:
		if building.kind != "hospital" and building.online:
			building.served = float(building.demand) * minf(1.0, remaining_supply / normal_demand) if normal_demand > 0.0 else 0.0
	var energized := renew_used + gas_used + battery_discharge + imports > 0.001 or can_trade
	for id in ids:
		var building := get_building(id)
		if evolution.is_storage(str(building.kind)) and dt > 0.0:
			var efficiency: float = evolution.storage_efficiency(building)
			building.energy = clampf(float(building.energy) + float(building.charging) * dt * efficiency - float(building.output) * dt / efficiency, 0.0, float(building.energy_capacity))
		building.powered = energized and building.online and bool(building.get("enabled", true)) and (float(building.demand) <= 0.0 or float(building.served) >= float(building.demand) * 0.98)
		building.soc = float(building.energy) / float(building.energy_capacity) if float(building.energy_capacity) > 0.0 else 0.0
		building.voltage = 1.0 if building.powered else 0.0
	_solve_dc(ids)
	return contract_used

func _discharge_batteries(batteries: Array[Dictionary], requested: float, dt: float, preserve_reserve: bool) -> float:
	var total := 0.0
	var interval := dt if dt > 0.0 else 0.05
	for battery in batteries:
		if float(battery.charging) > 0.000001:
			continue
		if not evolution.storage_can_discharge(self, battery):
			continue
		var reserve := maxf(float(battery.get("reserve_soc", 0.0)), float(market.state.reserve_soc) if preserve_reserve else 0.0)
		var floor_energy := float(battery.energy_capacity) * reserve
		var energy_power: float = maxf(0.0, float(battery.energy) - floor_energy) * evolution.storage_efficiency(battery) / interval
		var rated: float = float(battery.capacity) * evolution.storage_power_factor(self, battery)
		var room := maxf(0.0, minf(rated, energy_power) - float(battery.output))
		var power := minf(room, maxf(0.0, requested - total))
		battery.output += power
		total += power
	return total

func _charge_batteries(batteries: Array[Dictionary], requested: float, dt: float) -> float:
	var total := 0.0
	var interval := dt if dt > 0.0 else 0.05
	for battery in batteries:
		if float(battery.output) > 0.000001:
			continue
		if not evolution.storage_can_charge(self, battery):
			continue
		var energy_room: float = maxf(0.0, float(battery.energy_capacity) - float(battery.energy)) / (evolution.storage_efficiency(battery) * interval)
		var rated: float = float(battery.capacity) * evolution.storage_power_factor(self, battery)
		var room := maxf(0.0, minf(rated, energy_room) - float(battery.charging))
		var power := minf(room, maxf(0.0, requested - total))
		battery.charging += power
		total += power
	return total

func _solve_dc(ids: Array[int]) -> void:
	if ids.size() < 2:
		return
	var index := {}
	for i in ids.size():
		index[ids[i]] = i
	var matrix: Array = []
	var injections: Array[float] = []
	for i in ids.size():
		var row: Array[float] = []
		row.resize(ids.size())
		row.fill(0.0)
		matrix.append(row)
		var building := get_building(ids[i])
		injections.append(float(building.output) - float(building.served) - float(building.charging))
	for line in lines:
		if not line.closed or line.fault or not index.has(int(line.a)) or not index.has(int(line.b)):
			continue
		var a: int = index[int(line.a)]
		var b: int = index[int(line.b)]
		var weight := _line_weight(line)
		matrix[a][a] += weight
		matrix[b][b] += weight
		matrix[a][b] -= weight
		matrix[b][a] -= weight
	# Node 0 is the angle reference. Topology/weights fix this matrix, so
	# reuse its pivoted LU while dispatch, demand and storage keep changing.
	var n := ids.size() - 1
	var reduced: Array = []
	var rhs: Array[float] = []
	for i in n:
		var row: Array[float] = []
		for j in n:
			row.append(float(matrix[i + 1][j + 1]))
		reduced.append(row)
		rhs.append(injections[i + 1])
	var angles: Array[float] = _dc_solver.solve(reduced, rhs, hash([ids, reduced]))
	if angles.size() != n:
		return
	for i in n:
		get_building(ids[i + 1]).angle = angles[i]
	for line in lines:
		if line.closed and not line.fault and index.has(int(line.a)) and index.has(int(line.b)):
			line.flow = (float(get_building(int(line.a)).angle) - float(get_building(int(line.b)).angle)) * _line_weight(line)

func _line_weight(line: Dictionary) -> float:
	return 1.0 / maxf(1.0, Vector2(get_building(int(line.a)).cell).distance_to(Vector2(get_building(int(line.b)).cell)))

func _auto_restore() -> void:
	if float(totals.get("reliability", 1.0)) >= 0.98:
		return
	# Healthy open ties are candidates; faulted or overloaded protection trips
	# must remain open. Roll back a tie if it creates an unsafe loading.
	for line in lines:
		if line.closed or line.fault or float(line.repair_remaining) > 0.0 or line.trip_reason == "持续过载" or not digital.can_control(self, int(line.id)):
			continue
		var old_served: float = totals.get("served", 0.0)
		line.closed = true
		_solve(0.0)
		if float(totals.served) > old_served + 0.01 and float(totals.max_loading) <= 1.05:
			line.closed = false
			_solve(0.0)
			digital.queue_remote(self, int(line.id), true)
		else:
			line.closed = false
			_solve(0.0)

func _fault_count() -> int:
	var count := 0
	for line in lines:
		if line.fault:
			count += 1
	return count

func _update_objectives() -> void:
	var renewable_count := 0
	var industry_powered := false
	for building in buildings:
		if building.kind == "solar" or building.kind == "wind":
			renewable_count += 1
		if building.kind == "factory" and building.powered:
			industry_powered = true
	for objective in objectives:
		if objective.done:
			continue
		match str(objective.id):
			"industry":
				objective.progress = 1.0 if industry_powered and float(totals.reliability) >= 0.98 else float(totals.reliability) * 0.7
			"renewable":
				objective.progress = minf(1.0, float(renewable_count) / 3.0) * minf(1.0, float(totals.renewable_share) / 0.35)
			"smart":
				objective.progress = float(research_level) / 2.0
			"resilience":
				objective.progress = 1.0 if restored_storms > 0 else (0.5 if storm_count > 0 else 0.0)
		if float(objective.progress) >= 0.9999:
			objective.done = true
			cash += float(objective.reward)
			_log("目标完成「%s」，获得城市发展基金 ¥%s。" % [objective.title, objective.reward], "success")

func _refresh() -> void:
	_update_weather()
	_solve(0.0)
	_update_objectives()
	changed.emit()

func _log(message: String, severity: String = "info") -> void:
	var entry := {"time": "D%d %02d:%02d" % [day, int(time_hours), int(fmod(time_hours, 1.0) * 60.0)], "text": message, "message": message, "severity": severity}
	log_entries.push_back(entry)
	if log_entries.size() > 40:
		log_entries.pop_front()
	event_logged.emit(entry)

func _ok(message: String, id: int = -1) -> Dictionary:
	return {"ok": true, "message": message, "id": id}

func _fail(message: String) -> Dictionary:
	return {"ok": false, "message": message, "id": -1}

func snapshot() -> Dictionary:
	var saved_buildings: Array = []
	for building in buildings:
		var saved: Dictionary = building.duplicate(true)
		saved.cell = [building.cell.x, building.cell.y]
		saved_buildings.append(saved)
	return {"schema_version": SCHEMA_VERSION, "seed": initial_seed, "rng_state": str(rng.state),
		"buildings": saved_buildings, "lines": lines.duplicate(true), "cash": cash,
		"time_hours": time_hours, "day": day, "research_level": research_level,
		"next_building_id": next_building_id, "next_line_id": next_line_id,
		"elapsed_hours": elapsed_hours, "storm_count": storm_count, "restored_storms": restored_storms,
		"storm_active": storm_active, "storm_remaining": storm_remaining, "peak_load": peak_load,
		"total_served_mwh": total_served_mwh, "total_demand_mwh": total_demand_mwh,
		"carbon_tonnes": carbon_tonnes, "construction_count": construction_count,
		"demand_response_remaining": demand_response_remaining, "auto_restore_timer": auto_restore_timer,
		"next_storm_at": next_storm_at, "storm_warning_sent": storm_warning_sent,
		"objectives": objectives.duplicate(true), "log_entries": log_entries.duplicate(true),
		"market": market.snapshot(), "digital": digital.snapshot(),
		"evolution": evolution.snapshot(), "region": region.snapshot(),
		"sandbox_goal": sandbox_goal, "sandbox_goal_hours": sandbox_goal_hours,
		"completed_sandbox_goals": completed_sandbox_goals.duplicate()}

func save_game(path: String = "user://bay_grid_save.json") -> Dictionary:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return _fail("无法写入存档。")
	file.store_string(JSON.stringify(snapshot(), "\t", true, true))
	file.close()
	return _ok("存档已保存。")

func load_game(path: String = "user://bay_grid_save.json") -> Dictionary:
	if not FileAccess.file_exists(path):
		return _fail("还没有存档。")
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return _fail("无法读取存档。")
	var data: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if not data is Dictionary or not _saved_integer(data.get("schema_version"), 1, SCHEMA_VERSION):
		return _fail("存档格式不兼容。")
	if not _valid_save(data):
		return _fail("存档数据不完整，当前游戏未改变。")
	var restored_market: RefCounted = MarketModel.new()
	if int(data.schema_version) >= 2 and not restored_market.load_snapshot(data.market):
		return _fail("市场存档数据不完整，当前游戏未改变。")
	var restored_evolution: RefCounted = EvolutionModel.new()
	var restored_region: RefCounted = RegionModel.new()
	if int(data.schema_version) >= 4:
		if not restored_evolution.load_snapshot(data.evolution) or not restored_region.load_snapshot(data.region):
			return _fail("科技或城市存档数据不完整，当前游戏未改变。")
	buildings.clear()
	for item in data.buildings:
		var restored: Dictionary = item.duplicate(true)
		restored.cell = Vector2i(int(item.cell[0]), int(item.cell[1]))
		# JSON has a single number type. Stable graph identities must remain
		# integers so dictionaries in the renderer retain their existing keys.
		for key in ["id", "level"]:
			restored[key] = int(restored[key])
		for key in ["import_mw", "export_mw", "curtailment_mw", "grid_capacity"]:
			restored[key] = float(restored.get(key, 0.0))
		restored_evolution.initialize_building(restored)
		buildings.append(restored)
	lines.clear()
	for item in data.lines:
		var restored_line: Dictionary = item.duplicate(true)
		for key in ["id", "a", "b", "level"]:
			restored_line[key] = int(restored_line[key])
		lines.append(restored_line)
	market = restored_market
	evolution = restored_evolution
	region = restored_region
	sandbox_goal = str(data.get("sandbox_goal", ""))
	sandbox_goal_hours = float(data.get("sandbox_goal_hours", 0.0))
	completed_sandbox_goals.clear()
	for goal in data.get("completed_sandbox_goals", []):
		completed_sandbox_goals.append(str(goal))
	var restored_digital: RefCounted = DigitalModel.new()
	if int(data.schema_version) >= 3:
		restored_digital.load_snapshot(data.digital)
	digital = restored_digital
	cash = float(data.cash)
	time_hours = float(data.time_hours)
	day = int(data.day)
	research_level = int(data.research_level)
	next_building_id = int(data.next_building_id)
	next_line_id = int(data.next_line_id)
	initial_seed = int(data.seed)
	rng.seed = initial_seed
	rng.state = int(data.rng_state)
	elapsed_hours = float(data.elapsed_hours)
	next_storm_at = float(data.get("next_storm_at", _default_next_storm_time()))
	storm_warning_sent = bool(data.get("storm_warning_sent", false))
	storm_count = int(data.storm_count)
	restored_storms = int(data.restored_storms)
	storm_active = bool(data.storm_active)
	storm_remaining = float(data.storm_remaining)
	peak_load = float(data.peak_load)
	total_served_mwh = float(data.total_served_mwh)
	total_demand_mwh = float(data.total_demand_mwh)
	carbon_tonnes = float(data.carbon_tonnes)
	construction_count = int(data.construction_count)
	demand_response_remaining = float(data.get("demand_response_remaining", 0.0))
	auto_restore_timer = float(data.get("auto_restore_timer", 0.0))
	objectives.clear()
	for item in data.objectives:
		var restored_objective: Dictionary = item.duplicate(true)
		restored_objective.reward = int(restored_objective.reward)
		objectives.append(restored_objective)
	log_entries.clear()
	for item in data.log_entries:
		log_entries.append(item.duplicate(true))
	if int(data.schema_version) < 3:
		digital.reset(self, true)
	_update_weather()
	_solve(0.0)
	_log("存档已载入，电网状态已恢复。", "info")
	changed.emit()
	return _ok("存档已载入。")

func _valid_save(data: Dictionary) -> bool:
	# Validate the whole document before mutating any live state. JSON numbers
	# are floats, so identifiers also require an explicit integrality check.
	if not _saved_integer(data.get("schema_version"), 1, SCHEMA_VERSION):
		return false
	if int(data.schema_version) >= 2 and not MarketModel.valid_snapshot(data.get("market")):
		return false
	for key in ["buildings", "lines", "objectives", "log_entries"]:
		if not data.get(key) is Array:
			return false
	if data.buildings.size() > 512 or data.lines.size() > 2000 or data.objectives.size() > 4 or data.log_entries.size() > 40:
		return false
	if not _saved_number(data.get("cash"), -1e15, 1e15) or not _saved_number(data.get("time_hours"), 0.0, 24.0) or float(data.time_hours) >= 24.0:
		return false
	for key in ["day", "next_building_id", "next_line_id"]:
		if not _saved_integer(data.get(key), 1, 1000000000):
			return false
	for key in ["research_level", "storm_count", "restored_storms", "construction_count"]:
		if not _saved_integer(data.get(key), 0, 1000000000):
			return false
	if int(data.research_level) > 2 or int(data.restored_storms) > int(data.storm_count):
		return false
	if not _saved_integer(data.get("seed"), -9007199254740991, 9007199254740991) or not data.get("rng_state") is String or not data.rng_state.is_valid_int():
		return false
	for key in ["elapsed_hours", "storm_remaining", "peak_load", "total_served_mwh", "total_demand_mwh", "carbon_tonnes"]:
		if not _saved_number(data.get(key), 0.0, 1e15):
			return false
	if float(data.total_served_mwh) > float(data.total_demand_mwh) + 0.00001 or not data.get("storm_active") is bool:
		return false
	for key in ["next_storm_at", "demand_response_remaining", "auto_restore_timer"]:
		if data.has(key) and not _saved_number(data[key], 0.0, 1e12):
			return false
	if data.has("storm_warning_sent") and not data.storm_warning_sent is bool:
		return false
	var ids := {}
	var occupied := {}
	var maximum_id := 0
	for building in data.buildings:
		if not building is Dictionary or not _saved_integer(building.get("id"), 1, 1000000000) or not catalog.has(str(building.get("kind", ""))):
			return false
		if not building.get("kind") is String or not building.get("name") is String or not _saved_integer(building.get("level"), 1, 3):
			return false
		if ids.has(int(building.id)) or not building.get("cell") is Array or building.cell.size() != 2:
			return false
		if not _saved_integer(building.cell[0], 1, GRID_SIZE - 2) or not _saved_integer(building.cell[1], 1, GRID_SIZE - 2):
			return false
		var cell := Vector2i(int(building.cell[0]), int(building.cell[1]))
		if occupied.has(cell):
			return false
		occupied[cell] = true
		for key in ["capacity", "base_demand", "demand", "served", "energy", "energy_capacity", "repair_remaining", "charging", "available"]:
			if not _saved_number(building.get(key), 0.0, 1000000.0):
				return false
		for key in ["output", "angle"]:
			if not _saved_number(building.get(key), -1000000.0, 1000000.0):
				return false
		if not _saved_number(building.get("health"), 0.0, 100.0) or not _saved_number(building.get("soc"), 0.0, 1.0) or not _saved_number(building.get("dispatch"), 0.0, 1.0):
			return false
		if float(building.energy) > float(building.energy_capacity) + 0.00001 or not building.get("online") is bool or not building.get("powered") is bool:
			return false
		if int(data.schema_version) >= 4 and not EvolutionModel.validate_building(building):
			return false
		if building.has("city_id") and not _saved_integer(building.city_id, 0, 7):
			return false
		for key in ["import_mw", "export_mw", "curtailment_mw", "grid_capacity"]:
			if building.has(key) and not _saved_number(building[key], 0.0, 1000000.0):
				return false
		ids[int(building.id)] = building
		maximum_id = maxi(maximum_id, int(building.id))
	if int(data.next_building_id) <= maximum_id:
		return false
	var line_ids := {}
	var endpoint_pairs := {}
	var maximum_line_id := 0
	for line in data.lines:
		if not line is Dictionary or not _saved_integer(line.get("id"), 1, 1000000000) or not _saved_integer(line.get("a"), 1, 1000000000) or not _saved_integer(line.get("b"), 1, 1000000000):
			return false
		if line_ids.has(int(line.id)) or not ids.has(int(line.a)) or not ids.has(int(line.b)) or int(line.a) == int(line.b):
			return false
		var pair := Vector2i(mini(int(line.a), int(line.b)), maxi(int(line.a), int(line.b)))
		if endpoint_pairs.has(pair):
			return false
		endpoint_pairs[pair] = true
		line_ids[int(line.id)] = true
		maximum_line_id = maxi(maximum_line_id, int(line.id))
		if not _saved_integer(line.get("level"), 1, 3) or not line.get("closed") is bool or not line.get("fault") is bool or not line.get("trip_reason") is String:
			return false
		if not _saved_number(line.get("capacity"), 0.001, 1000000.0) or not _saved_number(line.get("flow"), -1000000.0, 1000000.0) or not _saved_number(line.get("health"), 0.0, 100.0):
			return false
		for key in ["heat", "repair_remaining"]:
			if not _saved_number(line.get(key), 0.0, 1000000.0):
				return false
	if int(data.next_line_id) <= maximum_line_id:
		return false
	var objective_ids := {}
	for objective in data.objectives:
		if not objective is Dictionary:
			return false
		for key in ["id", "title", "description"]:
			if not objective.get(key) is String:
				return false
		if objective.id not in ["industry", "renewable", "smart", "resilience"] or objective_ids.has(objective.id):
			return false
		objective_ids[objective.id] = true
		if not objective.get("done") is bool or not _saved_number(objective.get("progress"), 0.0, 1.0) or not _saved_integer(objective.get("reward"), 0, 1000000):
			return false
	for entry in data.log_entries:
		if not entry is Dictionary:
			return false
		for key in ["time", "text", "message", "severity"]:
			if not entry.get(key) is String:
				return false
	if int(data.schema_version) >= 3:
		if not DigitalModel.valid_snapshot(data.get("digital"), ids, line_ids, float(data.elapsed_hours)):
			return false
		var crews: int = data.digital.field_jobs.size()
		for item in data.buildings + data.lines + data.digital.links:
			if float(item.repair_remaining) > 0.0:
				crews += 1
		if crews > 2:
			return false
	if int(data.schema_version) >= 4:
		if not EvolutionModel.valid_snapshot(data.get("evolution")) or not RegionModel.valid_snapshot(data.get("region"), ids):
			return false
		if data.get("sandbox_goal") not in ["", "regional", "clean", "profitable"] or not _saved_number(data.get("sandbox_goal_hours"), 0.0, 1e12):
			return false
		if not data.get("completed_sandbox_goals") is Array or data.completed_sandbox_goals.size() > 3:
			return false
		var goal_ids := {}
		for goal in data.completed_sandbox_goals:
			if goal not in ["regional", "clean", "profitable"] or goal_ids.has(goal):
				return false
			goal_ids[goal] = true
	return true

func _saved_number(value: Variant, minimum: float, maximum: float) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value) >= minimum and float(value) <= maximum

func _saved_integer(value: Variant, minimum: int, maximum: int) -> bool:
	return _saved_number(value, float(minimum), float(maximum)) and float(value) == floorf(float(value))
