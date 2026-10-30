class_name GridSimulation
extends RefCounted
## Deterministic, headless grid game model. All powers are MW, energy is MWh.
## The base network uses DC active power. Commissioned engineering adds
## capacity, voltage and resistive-loss approximations for management play.

signal changed
signal event_logged(entry: Dictionary)

const SCHEMA_VERSION := 8
const PlanningModel = preload("res://scripts/sim/grid_planning.gd")
const LifecycleModel = preload("res://scripts/sim/asset_lifecycle.gd")
const EngineeringModel = preload("res://scripts/sim/grid_engineering.gd")
const CustomerModel = preload("res://scripts/sim/customer_energy.gd")
const StrategyModel = preload("res://scripts/sim/strategic_economy.gd")
const ManagementModel = preload("res://scripts/sim/management_model.gd")
const CampaignModel = preload("res://scripts/sim/campaign.gd")
const ScenarioMap = preload("res://scripts/sim/scenario_map.gd")
const MarketModel = preload("res://scripts/sim/power_market.gd")
const DigitalModel = preload("res://scripts/sim/digital_grid.gd")
const EvolutionModel = preload("res://scripts/sim/grid_evolution.gd")
const RegionModel = preload("res://scripts/sim/region_world.gd")
const Dispatch = preload("res://scripts/sim/grid_dispatch.gd")
const NetworkSolver = preload("res://scripts/sim/dc_network_solver.gd")
const GRID_SIZE := 48
const LINE_COST := 1600.0
const LINE_CAPACITY := 24.0
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
var campaign: RefCounted = CampaignModel.new()
var management: RefCounted = ManagementModel.new()
var planning: RefCounted = PlanningModel.new()
var lifecycle: RefCounted = LifecycleModel.new()
var engineering: RefCounted = EngineeringModel.new()
var customers: RefCounted = CustomerModel.new()
var strategy: RefCounted = StrategyModel.new()
var _is_projection := false
var _day_ahead_budget := 0.0
var _day_ahead_delivered := 0.0
var _scenario_map_id := 0
var _scenario_map: Dictionary = {}
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
# Session-only operator acknowledgements; save schema and campaign flags stay independent.
var operator_receipts: Array[Dictionary] = []
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
	campaign = CampaignModel.new()
	lifecycle.reset()
	engineering.reset()
	customers.reset()
	strategy.reset()
	planning.reset()
	management.reset()
	_scenario_map_id = 0
	_scenario_map = {}
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
	operator_receipts.clear()
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
		{"id": "renewable", "title": "绿色转型", "description": "拥有至少3座风电或光伏设施，可再生发电占当前总供给（含进口及储能放电）至少35%。", "reward": 18000, "done": false, "progress": 0.0},
		{"id": "smart", "title": "可观测的城市", "description": "完成两级智能电网研究，解锁遥测和自动恢复。", "reward": 20000, "done": false, "progress": 0.0},
		{"id": "resilience", "title": "风暴之后", "description": "经历一次风暴，并修复所有故障线路、恢复至少 98% 的供电。", "reward": 25000, "done": false, "progress": 0.0}
	]
	digital.reset(self)
	digital.commission_initial(self,10)
	_update_weather()
	_solve(0.0)
	_log("欢迎来到海湾市。先连接东部工业园区，再建设更清洁、更可靠的电网。", "info")
	planning.reset(cash)
	changed.emit()

func _add_building(kind: String, cell: Vector2i, metadata: Dictionary = {}) -> Dictionary:
	var item: Dictionary = catalog[kind]
	var building := {
		"id": next_building_id, "kind": kind, "cell": cell,
		"name": item.name, "capacity": float(item.capacity), "base_demand": float(item.demand),
		"ownership": "player", "invested_capital": float(item.price), "refund_basis": float(item.price),
		"renewable_energy_mwh": 0.0, "renewable_served_mw": 0.0,
		"demand": 0.0, "output": 0.0, "served": 0.0, "powered": false,
		"health": 100.0, "level": 1, "online": true, "soc": 0.5,
		"energy": float(item.get("energy", 0.0)) * 0.5,
		"energy_capacity": float(item.get("energy", 0.0)),
		"dispatch": 1.0, "repair_remaining": 0.0, "charging": 0.0,
		"voltage": 1.0, "angle": 0.0, "available": 0.0,
		"import_mw": 0.0, "export_mw": 0.0, "curtailment_mw": 0.0, "grid_capacity": 0.0
	}
	building.merge(metadata,true)
	evolution.initialize_building(building)
	lifecycle.initialize_building(building)
	next_building_id += 1
	buildings.append(building)
	region.register_building(self,building,int(building.get("city_id",-1)))
	digital.sync_devices(self)
	return building

func _add_line(a: int, b: int) -> Dictionary:
	var item := {"id": next_line_id, "a": a, "b": b, "capacity": LINE_CAPACITY,
		"flow": 0.0, "closed": true, "fault": false, "heat": 0.0,
		"health": 100.0, "level": 1, "repair_remaining": 0.0, "trip_reason": ""}
	next_line_id += 1
	lifecycle.initialize_line(item)
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

func preview_build(kind: String, cell: Vector2i) -> Dictionary:
	var spec: Dictionary = catalog.get(kind,{})
	var result: Dictionary = {"ok":false,"message":"未知设施。","id":-1,"cost":float(spec.get("price",0)),
		"kind":kind,"cell":cell,"capacity":float(spec.get("capacity",0)),"demand":float(spec.get("demand",0)),
		"energy":float(spec.get("energy",0)),"maintenance":9.0+float(EvolutionModel.UPKEEP.get(kind,0)),"requires_connection":true}
	if buildings.size() >= 512:
		result.message="区域设施已达 512 座，请优先改造现有设施。"
		return result
	if not catalog.has(kind):
		return result
	var unlocked: Dictionary = can_build(kind)
	if not unlocked.ok:
		result.message=str(unlocked.message)
		return result
	# Preview must not populate scenario caches, sample telemetry or refresh the simulation.
	var scenario: Dictionary = {}
	if campaign.active:
		scenario=_scenario_map if _scenario_map_id==int(campaign.chapter_id) else ScenarioMap.for_chapter(int(campaign.chapter_id))
	var placement: Dictionary = evolution.can_place(kind,cell,scenario)
	if not placement.ok:
		result.message=str(placement.message)
		return result
	var size_limit: int = int(scenario.size) if campaign.active else (GRID_SIZE if region.active else 16)
	if cell.x < 1 or cell.y < 1 or cell.x >= size_limit-1 or cell.y >= size_limit-1:
		result.message="请在岛屿内部建造。"
		return result
	if not building_at(cell).is_empty():
		result.message="这里已有设施，请选择空地。"
		return result
	if strategy.cell_reserved(cell):
		result.message="此地块已为在建工程预留。"
		return result
	result.base_cost=float(result.cost)
	if strategy.enabled and kind in StrategyModel.PROJECT_HOURS:
		result.cost=snappedf(float(result.cost)*(1.08 if cell.x>=18 or cell.y>=18 else 1.03),.01)
		result.project_hours=float(StrategyModel.PROJECT_HOURS[kind])
	if cash<float(result.cost):
		result.message="资金不足。"
		return result
	result.ok=true
	result.message="可建造；建成后需要连接电网。"
	if result.has("project_hours"): result.message="工程费用 ¥%.0f（含场地），预计 %.2f 游戏小时后投运。" % [result.cost,result.project_hours]
	return result

func build(kind: String, cell: Vector2i) -> Dictionary:
	var preview: Dictionary = preview_build(kind,cell)
	if not preview.ok: return preview
	if strategy.enabled and kind in StrategyModel.PROJECT_HOURS:
		var project: Dictionary=strategy.start_project(self,kind,cell)
		if project.ok:
			project.project_id=project.id
			project.id=-1
			_refresh()
		return project
	var price: float = float(preview.cost)
	record_cash_change(-price,"investment","设施与电网投资")
	var building := _add_building(kind, cell)
	construction_count += 1
	record_campaign_action("build", int(building.id), {"kind":kind})
	_log("%s已建成；使用线路工具连接电网。" % building.name, "success")
	_refresh()
	return _ok("建造完成，请连接线路。", int(building.id))

func preview_connection(a: int, b: int, kind: String="power") -> Dictionary:
	var first: Dictionary = get_building(a)
	var second: Dictionary = get_building(b)
	var result: Dictionary = {"ok":false,"message":"请选择两座不同的设施和有效连接类型。","id":-1,
		"a":a,"b":b,"kind":kind,"cost":0.0,"distance":0.0,"capacity":LINE_CAPACITY if kind=="power" else 0.0}
	if kind not in ["power","fiber","wireless"]: return result
	if kind!="power" and not feature_enabled("digital"):
		result.message="此时代尚未开放数字通信。"
		return result
	if kind!="power" and evolution.heritage and not evolution.has_technology("scada"):
		result.message="历史开局需先研究 SCADA，再建设通信网络。"
		return result
	if kind=="power" and lines.size()>=2000:
		result.message="区域线路已达 2000 条，请优化现有网络。"
		return result
	if a==b:
		result.message="请选择另一座设施。"
		return result
	if first.is_empty() or second.is_empty():
		result.message="线路两端都需要设施。"
		return result
	result.distance=Vector2(first.cell).distance_to(Vector2(second.cell))
	result.cost=connection_cost(a,b) if kind=="power" else digital.link_cost(self,a,b,kind)
	var existing: Array = lines if kind=="power" else digital.links
	for link in existing:
		if (int(link.a)==a and int(link.b)==b) or (int(link.a)==b and int(link.b)==a):
			result.message="两座设施间已有线路。" if kind=="power" else "两座设施已有通信链路。"
			return result
	var max_range: float = 10.0 if first.kind=="relay" or second.kind=="relay" else 6.0
	if kind=="wireless" and float(result.distance)>max_range:
		result.message="无线距离过远；普通网关 6 格，中继站 10 格。"
		return result
	if kind=="power" and not engineering.connection_allowed(self,a,b):
		result.message="此连接跨越电压等级，请通过变电站衔接。"
		return result
	result.base_cost=float(result.cost)
	if kind=="power" and strategy.enabled and float(result.distance)>8.0:
		result.cost=snappedf(float(result.cost)*1.12,.01)
		result.project_hours=.5+float(result.distance)*.08
	if cash<float(result.cost):
		result.message="资金不足。"
		return result
	result.ok=true
	result.message="可连接电力线路。" if kind=="power" else "可建设独立通信链路。"
	if result.has("project_hours"): result.message="骨干线路工程 ¥%.0f，预计 %.2f 小时后投运。" % [result.cost,result.project_hours]
	return result

func connect_buildings(a: int, b: int) -> Dictionary:
	var preview: Dictionary = preview_connection(a,b)
	if not preview.ok: return preview
	if strategy.enabled and float(preview.distance)>8.0:
		var project: Dictionary=strategy.start_line_project(self,a,b)
		if project.ok:
			project.project_id=project.id
			project.id=-1
			_refresh()
		return project
	var price: float = float(preview.cost)
	record_cash_change(-price,"investment","设施与电网投资")
	var line := _add_line(a, b)
	record_campaign_action("connect", int(line.id), {"a":a,"b":b})
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
	if not evolution.upgrade_supported(str(building.kind)):
		return _fail("此设施暂无可购买的能力升级；可维护设备或增容相连线路。")
	if int(building.level) >= 3:
		return _fail("已达到最高等级。")
	var price: float = catalog[building.kind].price * 0.65 * float(building.level)
	if cash < price:
		return _fail("资金不足。")
	record_cash_change(-price,"investment","设施与电网投资")
	evolution.apply_upgrade(building)
	building.invested_capital = float(building.get("invested_capital",catalog[building.kind].price))+price
	building.refund_basis = float(building.get("refund_basis",catalog[building.kind].price))+price
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
	record_cash_change(-price,"investment","设施与电网投资")
	line.level += 1
	line.capacity *= 1.6
	line.health = 100.0
	line.heat = 0.0
	_log("线路 #%d 已增容至 %.1f MW。" % [id, line.capacity], "success")
	record_campaign_action("upgrade_line", id)
	_refresh()
	return _ok("线路已增容。", id)

func repair(id: int) -> Dictionary:
	if lifecycle.enabled: return expansion_action("maintenance",{"target_type":"facility","id":id,"action":"overhaul"})
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
	record_cash_change(-1200.0,"maintenance","设施检修派单")
	building.repair_remaining = 0.65
	building.repair_started_at=elapsed_hours
	building.repair_duration=0.65
	building.online = false
	_log("维修队前往%s，预计 39 游戏分钟完成检修。" % building.name, "info")
	_refresh()
	return _ok("维修队已派出。", id)

func repair_line(id: int) -> Dictionary:
	if lifecycle.enabled: return expansion_action("maintenance",{"target_type":"line","id":id,"action":"overhaul"})
	var line := get_line(id)
	if line.is_empty():
		return _fail("线路不存在。")
	if float(line.repair_remaining) > 0:
		return _fail("维修队正在作业。")
	for job in digital.field_jobs:
		if int(job.get("line_id",-1)) == id:
			return _fail("该线路已有现场任务。")
	if active_repairs() >= 2:
		return _fail("两支维修队都在作业，请稍候。")
	var observation := line_observation(id)
	var located: bool = observation.fault_known
	if located and not observation.get("fault", false) and float(observation.get("health", 100.0)) > 99.5:
		return _fail("现场或遥测记录显示设备状态良好，可按需执行开关操作。")
	if cash < 900.0:
		return _fail("资金不足。")
	record_cash_change(-900.0,"maintenance","线路抢修派单")
	line.repair_remaining = 0.6 if located else 1.1
	line.repair_started_at=elapsed_hours
	line.repair_duration=float(line.repair_remaining)
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
	return count + lifecycle.active_jobs() + customers.active_jobs()

func toggle_line(id: int) -> Dictionary:
	if campaign.active:
		return _fail("本关开关操作需派现场队或提交远程命令。")
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

func preview_demolition(id: int) -> Dictionary:
	var building: Dictionary = get_building(id)
	var result: Dictionary = {"ok":false,"message":"设施不存在。","id":id,"refund":0.0,
		"line_ids":[],"communication_ids":[],"connected_count":0,"requires_confirmation":true}
	if building.is_empty():
		return result
	result.refund=float(building.get("refund_basis",catalog[building.kind].price))*0.35
	for line in lines:
		if int(line.a)==id or int(line.b)==id: result.line_ids.append(int(line.id))
	for link in digital.links:
		if int(link.a)==id or int(link.b)==id: result.communication_ids.append(int(link.id))
	result.connected_count=result.line_ids.size()+result.communication_ids.size()
	if campaign.active and id in campaign.roles.values() and str(building.kind) in ["home","factory","hospital"]:
		result.message="这是本关必须服务的客户，不能通过拆除消除供电责任。"
		return result
	if campaign.active:
		for role in campaign.roles:
			if not _campaign_line_role(str(role)) and int(campaign.roles[role]) == id:
				result.message="这是本关工程需要保留的预置设施；可拆除自己新建的设施。"
				return result
	if float(building.repair_remaining) > 0 or bool(building.get("lifecycle_busy",false)):
		result.message="检修期间无法拆除。"
		return result
	for line in lines:
		if int(line.id) in result.line_ids and bool(line.get("lifecycle_busy",false)):
			result.message="相连线路现场作业期间无法拆除。"
			return result
	result.reserve_penalty=strategy.demolition_penalty(id)
	result.ok=true
	result.message="将拆除设施与相连的 %d 条电力、%d 条通信线路；回收 ¥%.0f。" % [result.line_ids.size(),result.communication_ids.size(),result.refund]
	if float(result.reserve_penalty)>0: result.message+=" 备用承诺违约费用 ¥%.0f，净回收 ¥%.0f。" % [result.reserve_penalty,float(result.refund)-float(result.reserve_penalty)]
	return result

func demolish(id: int) -> Dictionary:
	var preview: Dictionary = preview_demolition(id)
	if not preview.ok: return preview
	var building: Dictionary = get_building(id)
	var refund: float = float(preview.refund)
	# Pruning a removed target also has a terminal acknowledgement for its operator.
	for method in ["remote","field"]:
		var queue: Array = digital.pending_commands if method=="remote" else digital.field_jobs
		for command in queue:
			var facility: bool = str(command.get("kind",""))=="facility"
			var target_id: int = int(command.get("building_id",-1)) if facility else int(command.get("line_id",-1))
			if (facility and target_id==id) or (not facility and target_id in preview.line_ids):
				var action: String = "facility" if facility else ("remote_switch" if method=="remote" else ("inspect" if command.get("kind","")=="patrol" else "field_switch"))
				record_campaign_action(action,target_id,{"phase":"rejected","command_id":int(command.id),"method":method,"message":"目标或相连线路已拆除，待执行操作已取消。"})
	record_cash_change(refund,"disposal","资产拆除回收")
	region.unregister_building(self,building,true)
	for index in range(lines.size() - 1, -1, -1):
		if int(lines[index].a) == id or int(lines[index].b) == id:
			lines.remove_at(index)
	buildings.erase(building)
	digital.prune(self)
	region.prune(self)
	lifecycle.prune(self)
	engineering.prune(self)
	customers.prune(self)
	strategy.prune(self)
	_log("已拆除%s，按玩家实际投资回收 ¥%.0f；市政免费资产不产生建造退款。" % [building.name,refund], "info")
	_refresh()
	return _ok("拆除完成。", id)

func set_dispatch(id: int, ratio: float, method: String="remote") -> Dictionary:
	return configure_facility(id,{"dispatch":ratio},method)

func research() -> Dictionary:
	if not feature_enabled("digital"):
		return _fail("本关尚未开放数字电网研究。")
	if campaign.active and int(campaign.chapter_id) == 11 and research_level >= 1:
		return _fail("本关先掌握一级遥测，二级设施控制将在下一章学习。")
	if evolution.heritage and not evolution.has_technology("scada"):
		return _fail("历史开局需先研究 SCADA 调度接口，再开展遥测与自愈研究。")
	if research_level >= RESEARCH_COSTS.size():
		return _fail("智能电网研究已全部完成。")
	var price: float = RESEARCH_COSTS[research_level]
	if cash < price:
		return _fail("资金不足。")
	record_cash_change(-price,"research","馈线遥测与自愈研究")
	research_level += 1
	record_campaign_action("research", research_level, {"level":research_level})
	if research_level == 1:
		_log("馈线遥测上线：可信且可达的网关可回传线路潮流与故障信息。", "success")
	else:
		_log("设施远控上线：设置需要可信通信和执行回执；自动自愈将在下一章学习。" if campaign.active and not feature_enabled("auto_restore") else "自愈控制上线：通过可信低时延通信操作备用线路，需求响应仅面向可控负荷。", "success")
	_refresh()
	return _ok("研究完成。", research_level)

func map_size() -> int:
	if campaign.active:
		return int(map_spec().size)
	return GRID_SIZE if region.active else 16

func map_spec() -> Dictionary:
	if not campaign.active: return {}
	if _scenario_map_id != int(campaign.chapter_id):
		_scenario_map_id = int(campaign.chapter_id)
		_scenario_map = ScenarioMap.for_chapter(_scenario_map_id)
	return _scenario_map

func feature_enabled(feature: String) -> bool:
	return campaign.allows(feature) and management.allows(feature)

func can_build(kind: String) -> Dictionary:
	if not campaign.can_build(kind):
		return _fail("本关未开放这类设施，请查看当前任务与时代档案。")
	if not management.can_build(kind): return _fail("先完成当前经营任务；这一类设施将在后续阶段开放。")
	return evolution.can_build(kind)

func start_management_game(seed_value: int=42) -> Dictionary:
	reset(seed_value)
	management.start(self)
	_refresh()
	return _ok("经营路线已开始：先接通工业园，再逐步了解昼夜、成本、备用与城市扩张。")

func management_status() -> Dictionary:
	return management.status(self)

func prepare_first_storm() -> Dictionary:
	var result: Dictionary=management.prepare_storm(self)
	if result.ok: _refresh()
	return result

func operating_snapshot() -> Dictionary:
	var public_totals: Dictionary={}
	for key in ["demand","generation","served","renewable_supply_share","renewable_share","reliability","income","expenses","retail_income","export_income","import_cost","contract_cost","fuel_cost","maintenance_cost","outage_cost","import_mw","export_mw","market_price","retail_price","satisfaction","charging_mw","battery_mwh","battery_power","carbon","crews_busy","reliability_lifetime","storm_in","grid_capacity"]:
		if totals.has(key): public_totals[key]=totals[key]
	return {"elapsed_hours":elapsed_hours,"day":day,"time_hours":time_hours,"weather":weather,
		"cash":cash,"totals":public_totals,"management":management_status(),"source":"公开运营汇总",
		"operating_policy":operating_policy(),"operating_reason":operating_reason(),"history":management.state.history.duplicate(true)}

func operating_reason() -> String:
	var policy:=operating_policy()
	if not bool(policy.enabled): return "外网交换已禁用，当前使用本地电源和储能。"
	if float(totals.get("grid_capacity",0))<=0: return "尚无可用外网接口；现货策略等待联络站接入。"
	if float(market.state.spot_price)>float(market.state.buy_limit): return "现货买价高于生效阈值，当前不追加现货采购。"
	if float(totals.get("import_mw",0))>0.000001: return "经济调度在实际可交付范围内采购电力。" if policy.economic else "本地电源优先，外网补足可交付缺额。"
	if float(totals.get("export_mw",0))>0.000001: return "已允许外售，实际交付受报价、线路和接口容量共同限制。"
	return "当前没有外网交付；等待需求、价格或可交付能力变化。"

func next_event_hours(max_hours: float=1.0) -> float:
	# Only known schedules and accepted work are considered. Never reveal a hidden attack.
	var duration:=clampf(max_hours,0.001,24.0)
	for queue in [digital.pending_commands,digital.field_jobs]:
		for job in queue:
			if float(job.remaining)>0.000001: duration=minf(duration,float(job.remaining))
	for item in buildings+lines+digital.links:
		if float(item.get("repair_remaining",0))>0.000001: duration=minf(duration,float(item.repair_remaining))
	for building in buildings:
		var observed:=facility_observation(int(building.id))
		if bool(observed.trusted) and "启动" in str(observed.get("status","")) and float(building.get("startup_remaining",0))>0.000001:
			duration=minf(duration,float(building.startup_remaining))
	if not evolution.project.is_empty() and float(evolution.remaining_hours)>0.000001: duration=minf(duration,float(evolution.remaining_hours))
	if storm_warning_sent and next_storm_at>elapsed_hours: duration=minf(duration,next_storm_at-elapsed_hours)
	if storm_active: duration=minf(duration,maxf(0.001,storm_remaining))
	if float(market.state.contract_remaining)>0.000001: duration=minf(duration,float(market.state.contract_remaining))
	for job in lifecycle.jobs:
		if job.status=="travel": duration=minf(duration,maxf(.001,float(job.travel_remaining)))
		if job.status=="work": duration=minf(duration,maxf(.001,float(job.work_remaining)))
	for project in strategy.state.projects:
		if project.status=="building": duration=minf(duration,maxf(.001,float(project.remaining)))
	for grid in customers.microgrids:
		if not grid.pending.is_empty(): duration=minf(duration,maxf(.001,float(grid.pending.remaining)))
	if management.state.active and int(management.state.stage)<5:
		duration=minf(duration,maxf(0.001,float(management_status().remaining_hours)))
	return duration

func operating_policy() -> Dictionary:
	var intent:=str(management.state.operating_intent)
	if intent=="legacy_custom":
		return {"intent":intent,"enabled":market.state.market_mode!="off","economic":market.state.market_mode=="trade","allow_export":market.state.market_mode=="trade"}
	return {"intent":intent,"enabled":intent!="island","economic":intent=="economic","allow_export":bool(management.state.allow_export) and intent!="island"}

func set_operating_intent(intent: String, allow_export: bool=false) -> Dictionary:
	if not feature_enabled("market"): return _fail("当前阶段尚未开放市场经营。")
	if intent not in ["economic","self_supply","island"]: return _fail("未知经营意图。")
	management.state.operating_intent=intent
	management.state.allow_export=allow_export
	_refresh()
	return _ok("经营意图已生效；外售许可独立于经济调度。")

func storage_dispatch_policy(building: Dictionary) -> Dictionary:
	var local:=str(building.get("storage_intent","inherit"))
	var inherited:=local=="inherit"
	var intent:=str(management.state.storage_intent) if inherited else local
	var reserve: float=float(management.state.storage_reserve) if inherited else float(building.get("storage_reserve",0.2))
	if intent=="legacy_custom": reserve=maxf(float(building.get("reserve_soc",0)),float(market.state.reserve_soc) if market.state.storage_mode=="arbitrage" else 0.0)
	return {"intent":intent,"reserve_soc":reserve,"reserve":reserve,"inherited":inherited,"inherit":inherited,
		"legacy_custom":intent=="legacy_custom","peak_hour":float(building.get("peak_hour",17)),
		"charge_price":float(market.state.charge_price),"discharge_price":float(market.state.discharge_price)}

func storage_status(id: int) -> Dictionary:
	if id<0:
		var reserve: float=float(market.state.reserve_soc) if management.state.storage_intent=="legacy_custom" else float(management.state.storage_reserve)
		return {"intent":str(management.state.storage_intent),"reserve_soc":reserve,"reserve":reserve,
			"inherited":false,"inherit":false,"legacy_custom":management.state.storage_intent=="legacy_custom","known":true,"reason":"全网默认；单台覆盖设置不受此项改动影响。",
			"peak_hour":17.0,"charge_price":float(market.state.charge_price),"discharge_price":float(market.state.discharge_price)}
	var building:=get_building(id)
	if building.is_empty() or not evolution.is_storage(str(building.kind)): return {}
	var result:=storage_dispatch_policy(building)
	var observed:=facility_observation(id)
	result.known=bool(observed.trusted)
	result.reason="尚无新鲜可信观测；当前充放电原因需要先核实。"
	result.charging=observed.get("charging")
	result.output=observed.get("output")
	result.energy=observed.get("energy")
	result.duration_hours=null
	if not bool(building.get("enabled",true)): result.reason="运行许可已关闭。"
	elif result.known:
		var floor_energy:=float(building.energy_capacity)*float(result.reserve_soc)
		if observed.get("charging")!=null and float(observed.charging)>0.000001: result.reason="正在吸收可交付富余电力。"
		elif float(observed.output)>0.000001:
			result.reason="正在向负荷交付电力。"
			result.duration_hours=maxf(0,float(observed.energy)-floor_energy)*evolution.storage_efficiency(building)/float(observed.output)
		elif observed.get("charging")==null: result.reason="旧记录缺少充电功率；需刷新可信测量后判断充放电状态。"
		elif float(observed.energy)<=floor_energy+0.000001: result.reason="已到有效备用电量下限。"
		elif result.legacy_custom and building.get("storage_mode","auto")=="hold": result.reason="旧版自定义处于保留电量状态，两个方向均暂停。"
		elif result.intent=="peak" and not digital.control_reachable(self,id): result.reason="协同通信不可用，当前退回本地保供。"
		elif result.intent=="peak" and fposmod(time_hours-float(result.peak_hour),24)>=4: result.reason="尚未进入削峰窗口，等待充电或负荷变化。"
		else: result.reason="等待可交付富余电力、负荷或价格条件。"
	return result

func set_storage_intent(intent: String, reserve: float=0.2, building_id: int=-1, method: String="field") -> Dictionary:
	if intent not in ["inherit","supply","peak","arbitrage","legacy_custom"] or not _saved_number(reserve,0,0.9): return _fail("请选择保供、削峰或套利，备用电量范围0—90%。")
	if intent=="peak" and (not feature_enabled("storage_control") or not evolution.has_technology("smart_storage")): return _fail("削峰意图需要储能协同研究与本阶段能力。")
	if intent=="arbitrage" and not feature_enabled("market"): return _fail("套利需要开放市场经营。")
	if building_id>=0: return configure_facility(building_id,{"storage_intent":intent,"storage_reserve":reserve},method)
	if intent=="inherit": return _fail("全网策略不能继承自身。")
	management.state.storage_intent=intent
	management.state.storage_reserve=reserve
	_refresh()
	return _ok("全网储能默认意图已生效；采用单机覆盖的设施保留各自设置。")

func start_campaign(chapter_id: int = 1) -> Dictionary:
	if chapter_id < 1 or chapter_id > 15:
		return _fail("未知历史章节，当前游戏未改变。")
	reset(4200 + chapter_id)
	var result: Dictionary = campaign.start(self, chapter_id)
	if result.ok:
		_refresh()
	return result

func restart_campaign_chapter() -> Dictionary:
	return start_campaign(int(campaign.chapter_id)) if campaign.active else _fail("当前没有运行中的战役。")

func campaign_action(name: String) -> Dictionary:
	if not campaign.active:
		return _fail("当前没有运行中的战役。")
	var result: Dictionary = campaign.action(self, name)
	if result.ok: _refresh()
	return result

func record_campaign_action(action: String, target: int = -1, details: Dictionary = {}) -> void:
	var receipt := details.duplicate(true)
	if not receipt.has("phase"): receipt.phase = "executed"
	receipt.elapsed_hours = elapsed_hours
	if action in ["facility","remote_switch","field_switch","inspect"]:
		receipt.action=action
		receipt.target_id=target
		if not receipt.has("method"): receipt.method="remote" if action=="remote_switch" else "field"
		if not receipt.has("message"):
			receipt.message="已受理；尚未生效。" if receipt.phase=="accepted" else ("执行时验证未通过，设置未生效；请核实目标和通信状态。" if receipt.phase=="rejected" else "操作已完成并收到执行回执。")
		operator_receipts.append(receipt.duplicate(true))
		if operator_receipts.size()>40: operator_receipts.pop_front()
	campaign.record_action(action, target, receipt)

func operation_receipts() -> Array[Dictionary]:
	return operator_receipts.duplicate(true)

func _campaign_line_role(role: String) -> bool:
	return role.ends_with("_feeder") or role.ends_with("_feed") or role in ["tie","root_power"]

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
	if not feature_enabled("research") or not campaign.can_research(id):
		return _fail("本关未开放这项研究。")
	var result: Dictionary = evolution.research(self, id)
	if result.ok:
		_log(result.message, "info")
		_refresh()
	return result

func configure_facility(id: int, settings: Dictionary, method: String="remote") -> Dictionary:
	if method == "remote" and not feature_enabled("remote"):
		return _fail("本关请派现场设置队；远程控制将在后续章节学习。")
	if settings.has("storage_mode") and settings.storage_mode == "peak" and not feature_enabled("storage_control"):
		return _fail("本关尚未开放储能协同削峰。")
	return _campaign_result(digital.queue_facility(self,id,settings,method), "facility", id, {"phase":"accepted","settings":settings,"method":method})

func _configure_facility_now(id: int, settings: Dictionary) -> Dictionary:
	# Execution and deterministic fixtures only; player controls always queue.
	var result: Dictionary = evolution.configure(self,id,settings)
	if result.ok: _refresh()
	return result

func facility_observation(id: int) -> Dictionary:
	return digital.facility_observation(self,id)

func commission_device(id: int, role: String="device") -> Dictionary:
	if not feature_enabled("digital"): return _fail("此时代尚未开放数字通信。")
	return _campaign_result(digital.commission_device(self,id,role), "commission", id)

func facility_status(id: int) -> String:
	var building := get_building(id)
	return evolution.facility_status(self, building) if not building.is_empty() else "设施不存在。"

func expand_region() -> Dictionary:
	if campaign.active: return _fail("战役使用本章规划区域；八城沙盘可从自由运营开启。")
	var result: Dictionary = region.activate(self)
	if result.ok:
		_log(result.message, "success")
		_refresh()
	return result

func explore_region() -> Dictionary:
	if campaign.active: return _fail("战役使用本章区域，城市扩张位于自由经营。")
	if management.state.active and int(management.state.stage)<4: return _fail("先完成备用与风暴恢复，再逐城拓展服务。")
	var result: Dictionary=region.activate(self,true)
	if result.ok:
		_log(result.message,"success")
		_refresh()
	return result

func plan_city(id: int) -> Dictionary:
	var result: Dictionary=region.plan_city(id)
	if result.ok: _refresh()
	return result

func start_city_service(id: int) -> Dictionary:
	var result: Dictionary=region.start_service(self,id)
	if result.ok:
		_log(result.message,"success")
		_refresh()
	return result

func customer_service_active(id: int) -> bool:
	return region.service_active(get_building(id))

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
		goal.best_hours=float(management.state.sandbox_best.get(goal.id,0))
		goal.interruption=str(management.state.sandbox_interruption) if sandbox_goal==goal.id else ""
	return definitions

func set_sandbox_goal(id: String) -> Dictionary:
	if campaign.active: return _fail("请先完成本章目标；长期沙盘目标位于自由运营。")
	if id not in ["regional", "clean", "profitable"]:
		return _fail("未知运营目标。")
	if sandbox_goal == id:
		return _ok("已在追踪此目标，持续运营记录保留。")
	sandbox_goal = id
	sandbox_goal_hours = 0.0
	management.state.sandbox_interruption=""
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
		"clean": qualifies = qualifies and float(totals.get("renewable_supply_share",0.0)) >= 0.7
		"profitable": qualifies = qualifies and float(totals.income) > float(totals.expenses)
	if qualifies:
		sandbox_goal_hours+=dt
		management.state.sandbox_best[sandbox_goal]=maxf(float(management.state.sandbox_best.get(sandbox_goal,0)),sandbox_goal_hours)
		management.state.sandbox_interruption=""
	else:
		if sandbox_goal_hours>0.000001:
			var reason:="供电率或实际需求未达标"
			if float(totals.reliability)>=0.98 and float(totals.demand)>1:
				reason={"regional":"可靠服务城市不足四座","clean":"实际清洁供电不足70%","profitable":"运营净收益未为正"}.get(sandbox_goal,reason)
			management.state.sandbox_interruption=reason+"；计时重新开始，最佳纪录已保留。"
		sandbox_goal_hours=0.0
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
	var preview: Dictionary = preview_connection(a,b,kind)
	if not preview.ok: return preview
	return _campaign_result(digital.connect_link(self, a, b, kind), "communication", a, {"b":b})

func toggle_communication(id: int) -> Dictionary:
	if not feature_enabled("digital"): return _fail("此时代尚未开放数字通信。")
	return _digital_result(digital.toggle_link(id))

func repair_communication(id: int) -> Dictionary:
	if not feature_enabled("digital"): return _fail("此时代尚未开放数字通信。")
	return _digital_result(digital.repair_link(self, id))

func upgrade_communication(id: int) -> Dictionary:
	if not feature_enabled("digital"): return _fail("此时代尚未开放数字通信。")
	return _digital_result(digital.upgrade_link(self, id))

func remote_switch(id: int) -> Dictionary:
	if not feature_enabled("remote"): return _fail("本关请派现场开关队。")
	var line := get_line(id)
	if line.is_empty():
		return _fail("线路不存在。")
	var observation := line_observation(id)
	if observation.visibility != "verified":
		digital.state.remote_rejected += 1
		return _fail("需要新鲜可信遥测，或改派现场开关队。")
	return _campaign_result(digital.queue_remote(self, id, not bool(observation.closed)), "remote_switch", id, {"phase":"accepted"})

func field_switch(id: int) -> Dictionary:
	return _campaign_result(digital.queue_field(self, id, "switch"), "field_switch", id, {"phase":"accepted"})

func patrol_line(id: int) -> Dictionary:
	return _campaign_result(digital.queue_field(self, id, "patrol"), "inspect", id, {"phase":"accepted"})

func set_security_policy(policy: String) -> Dictionary:
	if not feature_enabled("security"): return _fail("本关尚未开放安全策略。")
	return _campaign_result(digital.set_policy(policy), "security", -1, {"policy":policy})

func upgrade_security() -> Dictionary:
	if not feature_enabled("security"): return _fail("本关尚未开放安全升级。")
	return _digital_result(digital.upgrade_security(self))

func trigger_cyberattack(kind: String = "dos", target_id: int = -1) -> Dictionary:
	if campaign.active: return _fail("战役事件由当前教学阶段安排，请使用任务中的开始考核。")
	return _digital_result(digital.trigger_attack(self, kind, target_id))

func isolate_device(id: int, isolated: bool = true) -> Dictionary:
	if not feature_enabled("security"): return _fail("本关尚未开放安全处置。")
	return _campaign_result(digital.isolate(self, id, isolated), "isolate", id, {"isolated":isolated})

func recover_device(id: int) -> Dictionary:
	if not feature_enabled("security"): return _fail("本关尚未开放安全处置。")
	return _campaign_result(digital.recover(self, id), "patch", id, {"phase":"accepted"})

func _campaign_result(result: Dictionary, action: String, target: int = -1, details: Dictionary = {}) -> Dictionary:
	if result.ok:
		var receipt := details.duplicate(true)
		receipt.command_id = int(result.get("id", -1))
		record_campaign_action(action, target, receipt)
	return _digital_result(result)

func _digital_result(result: Dictionary) -> Dictionary:
	if result.ok:
		_log(str(result.message), "info")
		_refresh()
		digital.state.security_cost = float(totals.security_cost)
		digital.state.coverage = float(totals.comm_coverage)
		digital.state.trusted_coverage = float(totals.comm_trusted)
	return result

func demand_response() -> Dictionary:
	if not feature_enabled("demand_response"): return _fail("本关尚未开放需求响应。")
	if research_level < 2:
		return _fail("先研究自愈控制以解锁需求响应。")
	if customers.enabled:
		var accepted:=0
		for key in customers.devices:
			if get_building(int(key)).get("kind","")=="hospital": continue
			var result: Dictionary=customers.demand_response(self,int(key),"shift",.2,2.0)
			if result.ok: accepted+=1
		if accepted==0: return _fail("没有可执行响应的签约街区；检查电表、授权、可信观测和在途响应。")
		_log("已向%d个签约街区签发移峰；按实际响应补偿，结束后回补电量。" % accepted,"info")
		_refresh()
		return _ok("已签发%d个街区的移峰响应。" % accepted)
	if demand_response_remaining > 0:
		return _fail("需求响应正在执行。")
	if cash < 1000.0:
		return _fail("资金不足。")
	record_cash_change(-1000.0,"demand_response","需求响应补偿")
	demand_response_remaining = 2.0
	record_campaign_action("response")
	_log("需求响应启动：未来 2 游戏小时，可通过可信通信控制的普通用户负荷下降 20%。", "success")
	_refresh()
	return _ok("需求响应已启动。")

func trigger_storm() -> Dictionary:
	if management.state.active and not management.state.first_storm_prepared: return _fail("请先完成经营准备，再确认首次风暴；确认后有1游戏小时预警。")
	if campaign.active: return _fail("战役灾害由当前教学阶段安排，请使用任务中的开始考核。")
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
		if campaign.active and (campaign.completed or campaign.failed): break
		var dt := minf(remaining, 0.25 if _is_projection else 0.05)
		# Split every wholesale/retail band boundary as well as midnight.
		for boundary in range(1,25):
			var distance: float = boundary - time_hours
			if distance > 0.000001:
				dt = minf(dt, distance)
				break
		if float(market.state.contract_remaining) > 0.000001:
			dt = minf(dt, float(market.state.contract_remaining))
		var forward_boundary:=floorf(elapsed_hours+0.000000001)+1.0-elapsed_hours
		if forward_boundary>0.000001: dt=minf(dt,forward_boundary)
		_tick(dt)
		remaining -= dt
	changed.emit()

func _tick(dt: float) -> void:
	var settlement_day := day
	_pricing_day = day
	_pricing_hour = time_hours + dt * 0.5
	# Stable nanohour boundaries avoid platform JSON parsing moving an event by
	# one floating-point ULP after a save/restore.
	elapsed_hours = round((elapsed_hours+dt)*1e9)/1e9
	time_hours = round((time_hours+dt)*1e9)/1e9
	if time_hours >= 24.0:
		time_hours -= 24.0
		day += 1
		_log("第 %d 天开始。需求随城市发展缓慢增长，请规划备用容量。" % day, "info")
	if storm_active:
		storm_remaining = maxf(0.0, storm_remaining - dt)
		if storm_remaining <= 0.0:
			storm_active = false
			_log("风暴已离开海湾。修复受损设备，恢复全网供电。", "info")
	if not campaign.active: _update_storm_schedule()
	demand_response_remaining = maxf(0.0, demand_response_remaining - dt)
	for building in buildings:
		if float(building.repair_remaining) > 0:
			building.repair_remaining = maxf(0.0, float(building.repair_remaining) - dt)
			if building.repair_remaining <= 0.000001:
				building.repair_remaining = 0.0
				building.health = 100.0
				building.online = true
				record_campaign_action("repair", int(building.id), {"kind":"building"})
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
				record_campaign_action("repair", int(line.id), {"kind":"line"})
				_log("线路 #%d 抢修完成，已合闸恢复供电。" % line.id, "success")
	_update_weather()
	strategy.advance(self,dt)
	customers.advance(self,dt)
	lifecycle.advance(self,dt)
	evolution.advance(self, dt)
	digital.advance(self, dt)
	if research_level >= 2 and feature_enabled("auto_restore"):
		auto_restore_timer += dt
		if auto_restore_timer >= 0.1:
			auto_restore_timer = 0.0
			_auto_restore()
	# Protection evaluates a query first; commit storage energy exactly once,
	# after any breaker trips, so bills and MWh match the final physical flow.
	_solve(0.0)
	engineering.advance(self,dt)
	for line in lines:
		var loading := absf(float(line.flow)) / maxf(0.1, float(line.capacity))
		if line.closed and not line.fault and loading > 1.0:
			line.heat += dt * (loading * loading - 1.0) * 2.0
			line.health = maxf(10.0, float(line.health) - dt * (loading - 1.0) * 2.0)
			if line.heat >= evolution.line_trip_threshold(self, line) * (float(line.get("protection_delay",1.0)) if engineering.enabled else 1.0):
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
	lifecycle.after_solve(self,dt)
	digital.sample_verified(self)
	last_income = float(totals.income)
	last_expenses = float(totals.expenses)
	record_cash_change((last_income - last_expenses) * dt,"operations","运营与市场结算")
	var contract_was_active: bool = float(market.state.contract_remaining) > 0.0
	market.settle(dt, settlement_day, totals)
	strategy.settle(self,dt)
	if not _is_projection: planning.advance(self,dt)
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
	management.advance(self,dt)
	campaign.advance(self, dt)
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
	if management.state.active and not management.state.first_storm_prepared: return
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
	if not feature_enabled("market"): return _fail("本关采用固定供电安排，现代电价配置将在市场章节开放。")
	var result: Dictionary = market.set_tariff(mode, valley, flat, peak)
	if result.ok:
		record_campaign_action("market", -1, {"kind":"tariff","operation":"tariff"})
		_log(result.message, "info")
		_refresh()
	return result

func set_market_policy(mode: String, buy_limit: float = 120.0, sell_floor: float = 90.0) -> Dictionary:
	if not feature_enabled("market"): return _fail("本关未开放现货购售电策略。")
	var result: Dictionary = market.set_policy(mode, buy_limit, sell_floor)
	if result.ok:
		management.state.operating_intent="legacy_custom"
		record_campaign_action("market", -1, {"kind":"policy","operation":"policy"})
		_log(result.message, "info")
		_refresh()
	return result

func set_storage_policy(mode: String, charge_price: float = 60.0, discharge_price: float = 150.0, reserve: float = 0.2) -> Dictionary:
	if not feature_enabled("market"): return _fail("本关未开放市场储能套利策略。")
	var result: Dictionary = market.set_storage(mode, charge_price, discharge_price, reserve)
	if result.ok:
		management.state.storage_intent="legacy_custom"
		management.state.storage_reserve=reserve
		record_campaign_action("market", -1, {"kind":"storage","operation":"storage"})
		_log(result.message, "info")
		_refresh()
	return result

func sign_supply_contract(mw: float, hours: float = 12.0) -> Dictionary:
	if not feature_enabled("market"): return _fail("本关尚未开放锁价合约。")
	_update_market_prices(day, time_hours)
	var capacity := 0.0
	for building in buildings:
		if evolution.is_terminal(str(building.kind)) and building.online:
			capacity += _terminal_capacity(building)
	var result: Dictionary = market.sign_contract(mw, hours, capacity, market.quote_for(day, time_hours, weather, hours))
	if result.ok:
		record_campaign_action("contract", -1, {"mw":mw,"hours":hours})
		_log(result.message, "info")
		_refresh()
	return result

func market_forecast() -> Array[Dictionary]:
	if campaign.active and not feature_enabled("market"):
		var fixed: Array[Dictionary] = []
		for offset in 24:
			fixed.append({"day":day + int((time_hours + offset) / 24.0),"hour":fposmod(time_hours + offset,24.0),"spot":float(campaign.chapter().get("fixed_import_price",90.0)),"retail":145.0})
		return fixed
	return strategy.forecast_prices(self,market.forecast(day, time_hours, weather))

func _update_market_prices(pricing_day: int, pricing_hour: float) -> void:
	market.update_prices(pricing_day, pricing_hour, weather)
	market.state.spot_price=strategy.spot_price(self,float(market.state.spot_price))
	market.state.export_price=float(market.state.spot_price)*0.72
	market.state.retail_price=minf(float(market.state.retail_price),strategy.retail_cap())
	if campaign.active and not feature_enabled("market"):
		# Regulated external supply uses the same physical delivery and ledger,
		# without silently applying a modern time-varying wholesale price.
		market.state.spot_price = float(campaign.chapter().get("fixed_import_price",90.0))
		market.state.export_price = 0.0
		market.state.market_mode = "balanced" if feature_enabled("external_supply") else "off"
		market.state.buy_limit = 500.0
		market.state.storage_mode = "reserve"
		market.state.tariff_mode = "flat"
		market.state.retail_price = 145.0

func _solve(dt: float) -> void:
	_update_market_prices(_pricing_day if _pricing_day >= 0 else day, _pricing_hour if _pricing_hour >= 0.0 else time_hours)
	_contract_budget = float(market.state.contract_mw) if float(market.state.contract_remaining) > 0.0 and bool(operating_policy().enabled) else 0.0
	_day_ahead_budget = strategy.committed_mw(self) if bool(operating_policy().enabled) else 0.0
	_day_ahead_delivered = 0.0
	engineering.prepare(self)
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
		building.demand *= strategy.demand_factor(self,building)
		if not customers.enabled and demand_response_remaining > 0.0 and building.kind in ["home", "factory"]:
			if digital.control_reachable(self, int(building.id)):
				building.demand *= 0.8
	for line in lines:
		line.flow = 0.0
		if electrical_line_active(line) and adjacency.has(int(line.a)) and adjacency.has(int(line.b)):
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
	var renewable_served := 0.0
	for building in buildings:
		demand += float(building.demand)
		served += float(building.served)
		renewable_served += float(building.get("renewable_served_mw",0.0))
		var customer_rate := minf(strategy.retail_cap(),minf(145.0, float(market.state.retail_price)) if building.kind == "hospital" else float(market.state.retail_price))
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
		if float(building.get("customer_generation_mw",0.0))>0.0: renewable+=maxf(0.0,float(building.output))
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
	var import_cost := maxf(0.0, import_mw - contract_delivered - _day_ahead_delivered) * float(market.state.spot_price)
	var contract_cost := float(market.state.contract_mw) * float(market.state.contract_price) if float(market.state.contract_remaining) > 0.0 else 0.0
	var comm: Dictionary = digital.summarize(self)
	var billable_buildings:=0
	var billable_lines:=0
	for building in buildings:
		if region.billable_building(building): billable_buildings+=1
	for line in lines:
		if region.billable_building(get_building(int(line.a))) or region.billable_building(get_building(int(line.b))): billable_lines+=1
	var maintenance_cost: float = float(billable_buildings) * 9.0 + float(billable_lines) * 2.0 + float(comm.communication_cost) + float(comm.security_cost) + evolution.operating_cost(self)
	var max_loading := 0.0
	for line in lines:
		max_loading = maxf(max_loading, absf(float(line.flow)) / maxf(0.1, float(line.capacity)))
	totals = {"demand": demand, "generation": generation, "served": served,
		"renewable_supply_share": renewable_served / served if served > 0.000001 else 0.0,
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
	var losses:=0.0
	var min_voltage:=1.0
	for b in buildings:
		losses+=float(b.get("network_loss_mw",0.0))
		if float(b.served)>0.0: min_voltage=minf(min_voltage,float(b.voltage))
	totals.network_loss_mw=losses
	totals.min_voltage=min_voltage
	totals.day_ahead_import_mw=_day_ahead_delivered
	totals.energy_balance_error=float(totals.energy_balance_error)-losses
	var extra_rates: Dictionary=strategy.rates(self)
	totals.income=float(totals.income)+float(extra_rates.get("income",0.0))
	totals.expenses=float(totals.expenses)+float(extra_rates.get("expenses",0.0))
	for key in extra_rates:
		if key not in ["income","expenses"]: totals[key]=extra_rates[key]

func _terminal_capacity(building: Dictionary) -> float:
	return evolution.terminal_capacity(self, building)

func _solve_component(ids: Array[int], dt: float) -> float:
	return Dispatch.solve_component(self,ids,dt)

func electrical_line_active(line: Dictionary) -> bool:
	if not line.closed or line.fault or float(line.get("repair_remaining",0.0))>0.0: return false
	for id in [int(line.a),int(line.b)]:
		var b := get_building(id)
		if b.is_empty(): return false
		if b.kind=="substation" and (not b.online or not b.get("enabled",true) or float(b.get("repair_remaining",0.0))>0.0): return false
	return true

func _discharge_batteries(batteries: Array[Dictionary], requested: float, dt: float, preserve_reserve: bool) -> float:
	var total := 0.0
	var interval := dt if dt > 0.0 else 0.05
	for battery in batteries:
		if float(battery.charging) > 0.000001:
			continue
		if not evolution.storage_can_discharge(self, battery):
			continue
		var policy:=storage_dispatch_policy(battery)
		var reserve: float=float(policy.reserve_soc) if not policy.legacy_custom else maxf(float(battery.get("reserve_soc", 0.0)), float(market.state.reserve_soc) if preserve_reserve else 0.0)
		var floor_energy := float(battery.energy_capacity) * reserve
		var energy_power: float = maxf(0.0, float(battery.energy) - floor_energy) * evolution.storage_efficiency(battery) / interval
		var rated: float = maxf(0.0,float(battery.capacity) * evolution.storage_power_factor(self, battery)-strategy.reserved_mw(int(battery.id)))
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
		injections.append(float(building.output) - float(building.served) - float(building.charging) - float(building.get("network_loss_mw",0.0)))
	for line in lines:
		if not electrical_line_active(line) or not index.has(int(line.a)) or not index.has(int(line.b)):
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
		if electrical_line_active(line) and index.has(int(line.a)) and index.has(int(line.b)):
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
	if campaign.active or management.state.active: return
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
			record_cash_change(float(objective.reward),"reward","运营委托奖励")
			_log("目标完成「%s」，获得城市发展基金 ¥%s。" % [objective.title, objective.reward], "success")

func _refresh() -> void:
	_update_weather()
	_solve(0.0)
	_update_objectives()
	campaign.evaluate(self)
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

func record_cash_change(amount: float, category: String, description: String) -> void:
	if not is_finite(amount): return
	if _is_projection:
		cash+=amount
		return
	planning.record(self,amount,category,description)

func commission_expansion(system: String) -> Dictionary:
	if campaign.active: return _fail("历史教学使用章节指定的规则；在经营或区域沙盘中投运。")
	if management.state.active and int(management.state.stage)<3: return _fail("先完成接网、昼夜供需和清洁盈利，再投运高级经营体系。")
	if not evolution.has_technology("regional_planning"): return _fail("先研究区域负荷规划，再投运新的经营体系。")
	var result: Dictionary
	match system:
		"lifecycle": result=lifecycle.enable(self)
		"engineering": result=engineering.enable(self)
		"customers":
			if not evolution.has_technology("scada"): return _fail("用户侧协调还需要 SCADA 调度接口研究。")
			result=customers.enable(self)
		"strategy": result=strategy.enable(self)
		_: return _fail("未知投运体系。")
	if bool(result.ok): _refresh()
	return result

func planning_forecast(settings: Dictionary={}, hours: int=24) -> Dictionary:
	return planning.forecast(self,settings,hours)

func compare_operating_plans(plans: Array) -> Dictionary:
	return planning.compare(self,plans)

func operating_report() -> Dictionary:
	return planning.report(self)

func expansion_action(action: String, args: Dictionary={}) -> Dictionary:
	if campaign.active: return _fail("本关使用情景指定的规则。")
	var result: Dictionary
	match action:
		"maintenance": result=lifecycle.maintenance(self,str(args.get("target_type","facility")),int(args.get("id",-1)),str(args.get("action","inspect")),int(args.get("priority",0)))
		"spares": result=lifecycle.restock(self,int(args.get("count",1)))
		"priority": result=lifecycle.set_priority(int(args.get("id",-1)),int(args.get("priority",0)))
		"cancel_maintenance": result=lifecycle.cancel(self,int(args.get("id",-1)))
		"line_tier": result=engineering.configure_line(self,int(args.get("id",-1)),str(args.get("tier","distribution")),float(args.get("delay",1.0)))
		"substation": result=engineering.configure_substation(self,int(args.get("id",-1)),float(args.get("capacity",40)),str(args.get("zone","馈线1")))
		"customer": result=customers.configure(self,int(args.get("id",-1)),args.get("settings",{}))
		"response": result=customers.demand_response(self,int(args.get("id",-1)),str(args.get("kind","shift")),float(args.get("fraction",.2)),float(args.get("hours",2)))
		"microgrid_define": result=customers.define_microgrid(self,str(args.get("name","街区微电网")),args.get("members",[]),args.get("critical_ids",[]))
		"microgrid_switch": result=customers.set_microgrid(self,int(args.get("id",-1)),bool(args.get("island",true)),str(args.get("method","field")))
		_: return _fail("未知经营操作。")
	if bool(result.get("ok",false)): _refresh()
	return result

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
		"campaign": campaign.snapshot(),
		"management": management.snapshot(),
		"planning": planning.snapshot(), "lifecycle": lifecycle.snapshot(),
		"engineering": engineering.snapshot(), "customers": customers.snapshot(), "strategy": strategy.snapshot(),
		"sandbox_goal": sandbox_goal, "sandbox_goal_hours": sandbox_goal_hours,
		"completed_sandbox_goals": completed_sandbox_goals.duplicate()}

func save_game(path: String = "user://bay_grid_save.json") -> Dictionary:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return _fail("无法写入存档。")
	file.store_string(JSON.stringify(snapshot(), "\t", true, true))
	file.flush()
	var write_error: Error = file.get_error()
	file.close()
	if write_error!=OK: return _fail("存档写入未完成，请检查存储空间与权限。")
	return _ok("存档已保存。")

func load_game(path: String = "user://bay_grid_save.json") -> Dictionary:
	if not FileAccess.file_exists(path):
		return _fail("还没有存档。")
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return _fail("无法读取存档。")
	var data: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	return restore_snapshot(data)

func restore_snapshot(data: Variant) -> Dictionary:
	if not data is Dictionary or not _saved_integer(data.get("schema_version"), 1, SCHEMA_VERSION):
		return _fail("存档格式不兼容。")
	if not _valid_save(data):
		return _fail("存档数据不完整，当前游戏未改变。")
	var restored_market: RefCounted = MarketModel.new()
	if int(data.schema_version) >= 2 and not restored_market.load_snapshot(data.market):
		return _fail("市场存档数据不完整，当前游戏未改变。")
	var restored_evolution: RefCounted = EvolutionModel.new()
	var restored_region: RefCounted = RegionModel.new()
	var restored_campaign: RefCounted = CampaignModel.new()
	var restored_management: RefCounted = ManagementModel.new()
	if int(data.schema_version)>=7: restored_management.load_snapshot(data.management)
	if int(data.schema_version) >= 6 and not restored_campaign.load_snapshot(data.campaign):
		return _fail("战役存档数据不完整，当前游戏未改变。")
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
		var legacy_investment: float = float(catalog[restored.kind].price)*(1.0+0.65*float(int(restored.level)-1)*float(restored.level)/2.0)
		for key in ["invested_capital","refund_basis"]:
			restored[key] = legacy_investment if int(data.schema_version)<5 else float(restored[key])
		restored.ownership = "player" if int(data.schema_version)<5 else str(restored.ownership)
		restored.renewable_energy_mwh = 0.0 if int(data.schema_version)<5 else float(restored.renewable_energy_mwh)
		restored.renewable_served_mw = 0.0
		restored_evolution.initialize_building(restored)
		if int(data.schema_version)<7:
			restored.storage_intent="legacy_custom"
			restored.storage_reserve=0.2
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
	if int(data.schema_version)<7:
		for city in region.cities:
			city.service_phase="active"
			city.erase("role_effects")
			city.erase("initial_demand_scale")
	campaign = restored_campaign
	management = restored_management
	planning=PlanningModel.new()
	lifecycle=LifecycleModel.new()
	engineering=EngineeringModel.new()
	customers=CustomerModel.new()
	strategy=StrategyModel.new()
	if int(data.schema_version)>=8:
		planning.restore(data.planning)
		lifecycle.restore(data.lifecycle)
		engineering.restore(data.engineering)
		customers.restore(data.customers)
		strategy.restore(data.strategy)
	else:
		planning.reset(float(data.cash))
	for b in buildings: lifecycle.initialize_building(b)
	for l in lines: lifecycle.initialize_line(l)
	sandbox_goal = str(data.get("sandbox_goal", ""))
	sandbox_goal_hours = float(data.get("sandbox_goal_hours", 0.0))
	if int(data.schema_version)<7 and not sandbox_goal.is_empty(): management.state.sandbox_best[sandbox_goal]=sandbox_goal_hours
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
		if not management.state.active and restored_objective.id=="renewable": restored_objective.description="拥有至少3座风电或光伏设施，可再生发电占当前总供给（含进口及储能放电）至少35%。"
		objectives.append(restored_objective)
	log_entries.clear()
	for item in data.log_entries:
		log_entries.append(item.duplicate(true))
	operator_receipts.clear()
	if int(data.schema_version) < 3:
		digital.reset(self, true)
	digital.migrate_roles(self)
	region.reconcile_buildings(self,int(data.schema_version)<5)
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
	if int(data.schema_version)>=8:
		for key in ["planning","lifecycle","engineering","customers","strategy"]:
			if not data.get(key) is Dictionary: return false
		if not data.get("campaign") is Dictionary: return false
		if not PlanningModel.valid(data.get("planning")) or not LifecycleModel.valid_snapshot(data.get("lifecycle")): return false
		if not EngineeringModel.valid(data.get("engineering")) or not CustomerModel.valid(data.get("customers")) or not StrategyModel.valid(data.get("strategy")): return false
		if bool(data.get("campaign",{}).get("active",false)):
			for key in ["lifecycle","engineering","customers","strategy"]:
				if bool(data[key].enabled): return false
	if int(data.schema_version) >= 2 and not MarketModel.valid_snapshot(data.get("market")):
		return false
	if int(data.schema_version) >= 6 and not CampaignModel.valid_snapshot(data.get("campaign")):
		return false
	if int(data.schema_version)>=7:
		if not ManagementModel.valid_snapshot(data.get("management"),float(data.get("elapsed_hours",-1))): return false
		if bool(data.management.active) and bool(data.campaign.get("active",false)): return false
	for key in ["buildings", "lines", "objectives", "log_entries"]:
		if not data.get(key) is Array:
			return false
	if int(data.schema_version)>=8:
		for asset in data.buildings+data.lines:
			if not asset is Dictionary or not LifecycleModel.validate_asset(asset): return false
	var managed: bool=int(data.schema_version)>=7 and bool(data.get("management",{}).get("active",false))
	if data.buildings.size() > 512 or data.lines.size() > 2000 or data.objectives.size() > (5 if managed else 4) or data.log_entries.size() > 40:
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
		if not _valid_repair_timing(building,float(data.elapsed_hours)): return false
		if int(data.schema_version)>=5:
			if building.get("ownership") not in ["player","municipal"]: return false
			for key in ["invested_capital","refund_basis","renewable_energy_mwh"]:
				if not _saved_number(building.get(key),0.0,1e12): return false
			if float(building.renewable_energy_mwh)>float(building.energy)+0.000001 or float(building.refund_basis)>float(building.invested_capital)+0.000001: return false
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
		if not _valid_repair_timing(line,float(data.elapsed_hours)): return false
	if int(data.next_line_id) <= maximum_line_id:
		return false
	if int(data.schema_version) >= 6 and bool(data.campaign.get("active",false)):
		var chapter_map: Dictionary = ScenarioMap.for_chapter(int(data.campaign.chapter_id))
		for building in data.buildings:
			if float(building.cell[0]) >= float(chapter_map.size)-1 or float(building.cell[1]) >= float(chapter_map.size)-1:
				return false
		for role_id in data.campaign.get("roles",{}).values():
			if not ids.has(int(role_id)) and not line_ids.has(int(role_id)): return false
		for role in data.campaign.roles:
			var references: Dictionary = line_ids if _campaign_line_role(str(role)) else ids
			if not references.has(int(data.campaign.roles[role])): return false
		if int(data.campaign.initial_customer_count) != data.campaign.required_customers.size(): return false
		for customer_id in data.campaign.required_customers:
			if not ids.has(int(customer_id)) or ids[int(customer_id)].kind not in ["home","factory","hospital"]: return false
	var objective_ids := {}
	for objective in data.objectives:
		if not objective is Dictionary:
			return false
		for key in ["id", "title", "description"]:
			if not objective.get(key) is String:
				return false
		if objective.id not in (["industry", "renewable", "smart", "resilience","regional"] if managed else ["industry", "renewable", "smart", "resilience"]) or objective_ids.has(objective.id):
			return false
		objective_ids[objective.id] = true
		if not objective.get("done") is bool or not _saved_number(objective.get("progress"), 0.0, 1.0) or not _saved_integer(objective.get("reward"), 0, 1000000):
			return false
	if managed:
		if data.objectives.size()!=5: return false
		if int(data.management.stage)<3 and bool(data.management.first_storm_prepared): return false
		if int(data.management.stage)>=4 and not bool(data.management.first_storm_prepared): return false
		var sequence: Array=["industry","renewable","smart","resilience","regional"]
		for index in 5:
			if data.objectives[index].id!=sequence[index] or bool(data.objectives[index].done)!=(index<int(data.management.stage)): return false
	for entry in data.log_entries:
		if not entry is Dictionary:
			return false
		for key in ["time", "text", "message", "severity"]:
			if not entry.get(key) is String:
				return false
	if int(data.schema_version) >= 3:
		if not DigitalModel.valid_snapshot(data.get("digital"), ids, line_ids, float(data.elapsed_hours),int(data.schema_version)>=5):
			return false
		var crews: int = data.digital.field_jobs.size()
		if int(data.schema_version)>=8:
			for job in data.lifecycle.jobs:
				if job.status in ["travel","work"]: crews+=1
			for grid in data.customers.microgrids:
				if not grid.pending.is_empty() and grid.pending.method=="field": crews+=1
		for item in data.buildings + data.lines + data.digital.links:
			if float(item.repair_remaining) > 0.0:
				crews += 1
		if crews > 2:
			return false
	if int(data.schema_version) >= 4:
		if not EvolutionModel.valid_snapshot(data.get("evolution")) or not RegionModel.valid_snapshot(data.get("region"), ids,int(data.schema_version)>=5):
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
	if int(data.schema_version)>=8:
		if not LifecycleModel.valid_references(data.lifecycle,data.buildings,data.lines,float(data.elapsed_hours)): return false
		if not StrategyModel.references_valid(data.strategy,ids,line_ids,catalog): return false
		if not EngineeringModel.references_valid(data.engineering,ids,line_ids) or not CustomerModel.references_valid(data.customers,ids,line_ids): return false
		for key in data.engineering.lines:
			if not line_ids.has(int(key)): return false
		for key in data.engineering.substations:
			if not ids.has(int(key)) or ids[int(key)].kind!="substation": return false
		for key in data.customers.devices:
			if not ids.has(int(key)) or ids[int(key)].kind not in ["home","factory","hospital"]: return false
		for grid in data.customers.microgrids:
			for id in grid.get("members",[]):
				if not ids.has(int(id)): return false
	return true

func _saved_number(value: Variant, minimum: float, maximum: float) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value) >= minimum and float(value) <= maximum

func _valid_repair_timing(item: Dictionary, elapsed: float) -> bool:
	if not item.has("repair_duration") and not item.has("repair_started_at"): return true
	return _saved_number(item.get("repair_duration"),0.000001,100) and _saved_number(item.get("repair_started_at"),0,elapsed+0.00001) and float(item.get("repair_remaining",0))<=float(item.repair_duration)+0.00001

func _saved_integer(value: Variant, minimum: int, maximum: int) -> bool:
	return _saved_number(value, float(minimum), float(maximum)) and float(value) == floorf(float(value))
