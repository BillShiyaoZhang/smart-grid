class_name GridRegion
extends RefCounted
## City demographics are a gameplay model. They react to delivered energy,
## affordability and local generation pressure; reading the map never grows a city.

const MAX_BUILDINGS := 128
const MAX_EXPANSIONS := 3
const CUSTOMER_KINDS := ["home", "factory", "hospital"]
const MAX_CITY_BUILDINGS := 512
const ROLES := ["居住", "工业", "农业", "服务", "科研", "港口"]
const SETTLEMENTS := [
	{"name": "松溪镇", "anchor": Vector2i(24, 6), "role": "农业", "population": 1200.0},
	{"name": "东港", "anchor": Vector2i(38, 10), "role": "港口", "population": 1900.0},
	{"name": "临海工业城", "anchor": Vector2i(41, 25), "role": "工业", "population": 2200.0},
	{"name": "南汀", "anchor": Vector2i(33, 39), "role": "居住", "population": 1600.0},
	{"name": "白鹭大学城", "anchor": Vector2i(18, 40), "role": "科研", "population": 1100.0},
	{"name": "西岭", "anchor": Vector2i(7, 30), "role": "服务", "population": 1400.0},
	{"name": "云洲", "anchor": Vector2i(24, 24), "role": "居住", "population": 1700.0}
]

var active := false
var cities: Array[Dictionary] = []
var clock_hours := 0.0
var current_hour := 8.0
var expansion_clock := 0.0

func reset() -> void:
	active = false
	cities.clear()
	clock_hours = 0.0
	current_hour = 8.0
	expansion_clock = 0.0

func activate(sim: RefCounted) -> Dictionary:
	if active:
		return _result(false, "区域沙盘已经开启。")
	if sim.buildings.size() > MAX_BUILDINGS - SETTLEMENTS.size() * 2:
		return _result(false, "现有设施过多，请先为区域城镇保留空间。")
	# Reserve every footprint before mutating the live game. Player construction
	# near a future town moves the town's seed buildings, never overwrites it.
	var reserved: Dictionary = {}
	var placements: Array[Array] = []
	for settlement in SETTLEMENTS:
		var pair: Array = []
		for _index in 2:
			var cell := _free_cell(sim, settlement.anchor, reserved)
			if cell == Vector2i(-1, -1):
				return _result(false, "城镇附近没有足够空地，区域暂未开启。")
			reserved[cell] = true
			pair.append(cell)
		placements.append(pair)
	cities.append(_new_city(0, "青屿湾", Vector2i(8, 7), "服务", 4600.0, []))
	for index in SETTLEMENTS.size():
		var spec: Dictionary = SETTLEMENTS[index]
		cities.append(_new_city(index+1, spec.name, spec.anchor, spec.role, float(spec.population), []))
	active = true
	# Register all pre-existing customers without changing their ownership.
	for building in sim.buildings:
		register_building(sim, building, 0)
	for index in SETTLEMENTS.size():
		var spec: Dictionary = SETTLEMENTS[index]
		var ids: Array[int] = []
		for part in 2:
			var kind := "home" if part == 0 else ("hospital" if spec.role == "服务" else "factory")
			var building: Dictionary = sim._add_building(kind, placements[index][part], {
				"city_id":index+1,"ownership":"municipal","invested_capital":0.0,"refund_basis":0.0,
				"base_demand":1.4 if part==0 else (2.8 if spec.role in ["工业","港口"] else 1.8)})
			building.name = "%s · %s" % [spec.name, "住宅" if part == 0 else str(spec.role) + "片区"]
			register_building(sim, building, index+1)
			ids.append(int(building.id))
		sim._add_line(ids[0], ids[1])
	current_hour = float(sim.time_hours)
	sim._log("区域沙盘开启：七座城镇等待接入。稳定、可负担的电力吸引人口与产业；长期失供会引发衰落。", "info")
	return _result(true, "七座城镇已出现。先查看区域地图，再逐城规划馈线与电源。")

func _new_city(id: int, city_name: String, anchor: Vector2i, role: String, people: float, ids: Array[int]) -> Dictionary:
	return {"id": id, "name": city_name, "anchor": anchor, "population": people,
		"base_population": people, "specialization": role, "prosperity": 0.55,
		"service": 1.0 if id == 0 else 0.0, "growth": 0.0,
		"trend": "等待接网" if id != 0 else "观察供电与电价", "building_ids": ids,
		"expansions": 0, "role_pressure": 0.0, "unserved_hours": 0.0, "displaced_demand":0.0}

func advance(sim: RefCounted, dt: float) -> void:
	if not active or not is_finite(dt) or dt <= 0.0:
		return
	clock_hours += dt
	current_hour = float(sim.time_hours)
	expansion_clock += dt
	var check_expansion := expansion_clock >= 6.0
	if check_expansion:
		expansion_clock = fmod(expansion_clock, 6.0)
	for city in cities:
		# A removed urban block leaves displaced residents/businesses awaiting replacement.
		var demand := float(city.get("displaced_demand",0.0)) * float(city.population) / float(city.base_population)
		var served := 0.0
		var surviving_ids: Array[int] = []
		for id in city.building_ids:
			var building: Dictionary = sim.get_building(int(id))
			if building.is_empty():
				continue
			surviving_ids.append(int(id))
			demand += float(building.demand)
			served += float(building.served)
		city.building_ids = surviving_ids
		var delivery := clampf(served / demand, 0.0, 1.0) if demand > 0.000001 else 0.0
		var weight := 1.0 - exp(-dt / 3.0)
		city.service = lerpf(float(city.service), delivery, weight)
		city.unserved_hours = float(city.unserved_hours) + dt if delivery < 0.8 else maxf(0.0, float(city.unserved_hours) - dt * 2.0)
		var retail := float(sim.market.state.retail_price)
		var affordability := clampf((220.0 - retail) / 100.0, 0.0, 1.0)
		var pollution := _local_pollution(sim, city.anchor)
		var target := clampf(float(city.service) * 0.77 + affordability * 0.23 - pollution * 0.28, 0.0, 1.0)
		city.prosperity = lerpf(float(city.prosperity), target, 1.0 - exp(-dt / 12.0))
		var growth := clampf((float(city.prosperity) - 0.55) * 0.09, -0.04, 0.035)
		if float(city.unserved_hours) >= 8.0:
			growth = minf(growth, -0.025)
		city.growth = growth
		city.population = clampf(float(city.population) * exp(growth * dt / 24.0), float(city.base_population) * 0.35, float(city.base_population) * 3.0)
		city.trend = _trend(city, affordability, pollution)
		_update_specialization(sim, city, dt)
		if check_expansion and float(city.service) > 0.93 and float(city.prosperity) > 0.62:
			if int(city.expansions) < MAX_EXPANSIONS and float(city.population) >= float(city.base_population) * (1.16 + float(city.expansions) * 0.18):
				_expand(sim, city)

func _local_pollution(sim: RefCounted, anchor: Vector2i) -> float:
	var pressure := 0.0
	for building in sim.buildings:
		if str(building.kind) not in ["coal", "steam", "gas", "ccgt", "dc_dynamo"] or not building.online:
			continue
		var distance := Vector2(building.cell).distance_to(Vector2(anchor))
		if distance < 9.0:
			var intensity := 1.0 if building.kind in ["coal", "steam"] else (0.65 if building.kind == "dc_dynamo" else (0.2 if building.kind == "ccgt" else 0.28))
			var committed: float = maxf(float(building.output), sim.evolution.generator_minimum(building))
			pressure += committed / 24.0 * intensity * (1.0 - distance / 9.0)
	return clampf(pressure, 0.0, 1.0)

func _trend(city: Dictionary, affordability: float, pollution: float) -> String:
	if float(city.service) < 0.8:
		return "供电不足 · 人口与企业外流" if float(city.unserved_hours) >= 8.0 else "等待稳定供电"
	if affordability < 0.35:
		return "电价负担偏高 · 增长受限"
	if pollution > 0.45:
		return "本地污染压力 · 宜居度下降"
	if float(city.growth) > 0.006:
		return "人口流入 · 需求增加" if int(city.expansions) < MAX_EXPANSIONS else "城市成熟 · 继续优化供电"
	return "平稳发展 · 观察持续供电质量"

func _update_specialization(sim: RefCounted, city: Dictionary, dt: float) -> void:
	# Industry needs sustained cheap power; a research district needs a
	# well-served academy nearby. A role change takes several game days.
	var desired: String = city.specialization
	if float(city.service) > 0.96 and float(city.prosperity) > 0.72:
		var has_academy := false
		for building in sim.buildings:
			if building.kind == "academy" and building.powered and Vector2(building.cell).distance_to(Vector2(city.anchor)) <= 7.0:
				has_academy = true
				break
		if has_academy:
			desired = "科研"
		elif float(sim.market.state.retail_price) <= 110.0 and city.specialization in ["居住", "农业"]:
			desired = "工业"
	if desired != city.specialization:
		city.role_pressure = float(city.role_pressure) + dt
		if float(city.role_pressure) >= 48.0:
			city.specialization = desired
			city.role_pressure = 0.0
			sim._log("%s的产业分工转向%s；用电曲线随之改变。" % [city.name, desired], "info")
	else:
		city.role_pressure = maxf(0.0, float(city.role_pressure) - dt)

func _expand(sim: RefCounted, city: Dictionary) -> void:
	if sim.buildings.size() >= MAX_BUILDINGS:
		city.trend = "区域建设接近上限 · 优先改造已有设施"
		return
	var cell := _free_cell(sim, city.anchor)
	if cell == Vector2i(-1, -1):
		city.trend = "周边用地不足 · 城市暂缓扩张"
		return
	var kind := "home" if int(city.expansions) % 2 == 0 else "factory"
	var building: Dictionary = sim._add_building(kind, cell, {
		"city_id":int(city.id),"ownership":"municipal","invested_capital":0.0,"refund_basis":0.0,
		"base_demand":0.7 if kind=="home" else 1.0})
	building.name = "%s · 新%s" % [city.name, "街区" if kind == "home" else "产业园"]
	# The urban street feeder grows with its town, but long distance generation
	# and regional capacity remain the player's responsibility.
	var nearest_id := -1
	var nearest_distance := INF
	for id in city.building_ids:
		if int(id)==int(building.id):
			continue
		var neighbor: Dictionary = sim.get_building(int(id))
		if neighbor.is_empty():
			continue
		var distance := Vector2(neighbor.cell).distance_to(Vector2(cell))
		if distance < nearest_distance:
			nearest_distance = distance
			nearest_id = int(id)
	if nearest_id>=0:
		sim._add_line(nearest_id, int(building.id))
	register_building(sim, building, int(city.id))
	city.expansions = int(city.expansions) + 1
	sim._log("%s扩建了一个%s，电力需求与馈线负载增加。" % [city.name, "住宅街区" if kind == "home" else "产业园区"], "success")

func _free_cell(sim: RefCounted, anchor: Vector2i, reserved: Dictionary = {}) -> Vector2i:
	for radius in 5:
		for y in range(-radius, radius + 1):
			for x in range(-radius, radius + 1):
				if maxi(absi(x), absi(y)) != radius:
					continue
				var cell := anchor + Vector2i(x, y)
				if cell.x >= 1 and cell.y >= 1 and cell.x <= 46 and cell.y <= 46 and not reserved.has(cell) and sim.building_at(cell).is_empty():
					return cell
	return Vector2i(-1, -1)

func demand_multiplier(building: Dictionary) -> float:
	if not active or building.get("kind","") not in CUSTOMER_KINDS or not building.has("city_id"):
		return 1.0
	var city := city_status(int(building.city_id))
	if city.is_empty():
		return 1.0
	var population_factor := float(city.population) / float(city.base_population)
	var role_factor := 1.0
	if building.kind == "factory":
		match str(city.specialization):
			"工业": role_factor = 1.35 if current_hour >= 6.0 and current_hour < 22.0 else 1.1
			"港口": role_factor = 1.2 if current_hour >= 18.0 or current_hour < 7.0 else 0.85
			"农业": role_factor = 1.2 if current_hour >= 5.0 and current_hour < 10.0 else 0.6
			"科研": role_factor = 1.25 if current_hour >= 9.0 and current_hour < 18.0 else 0.7
			"服务": role_factor = 1.2 if current_hour >= 11.0 and current_hour < 21.0 else 0.65
			_: role_factor = 0.8
	return clampf(population_factor * role_factor, 0.2, 4.5)

func _city(id: int) -> Dictionary:
	for city in cities:
		if int(city.id)==id:
			return city
	return {}

func register_building(_sim: RefCounted, building: Dictionary, city_id: int=-1) -> bool:
	if not active or building.get("kind","") not in CUSTOMER_KINDS:
		return false
	var target := city_id if city_id>=0 else int(building.get("city_id",-1))
	if _city(target).is_empty():
		var nearest := INF
		for city in cities:
			var distance := Vector2(building.cell).distance_squared_to(Vector2(city.anchor))
			if distance<nearest:
				nearest = distance
				target = int(city.id)
	var destination := _city(target)
	if destination.is_empty():
		return false
	var already_registered := false
	for city in cities:
		if int(building.id) in city.building_ids:
			already_registered = true
			if int(city.id)!=target:
				city.building_ids.erase(int(building.id))
	if int(building.id) not in destination.building_ids:
		destination.building_ids.append(int(building.id))
	building.city_id = target
	if not already_registered:
		destination.displaced_demand = maxf(0.0,float(destination.get("displaced_demand",0.0))-float(building.base_demand))
	return true

func unregister_building(sim: RefCounted, building: Dictionary, demolished: bool=false) -> void:
	if not active or building.get("kind","") not in CUSTOMER_KINDS:
		return
	for city in cities:
		if int(building.id) not in city.building_ids:
			continue
		if demolished:
			var total_base := 0.0
			for id in city.building_ids:
				var item: Dictionary = sim.get_building(int(id))
				total_base += float(item.get("base_demand",0.0))
			var lost := maxf(0.0,float(building.base_demand))
			var fraction := clampf(lost/maxf(0.001,total_base),0.0,1.0)
			city.displaced_demand = float(city.get("displaced_demand",0.0))+lost
			city.population = maxf(float(city.base_population)*0.35,float(city.population)*(1.0-0.1*fraction))
			city.prosperity = maxf(0.0,float(city.prosperity)-0.1*fraction)
			city.trend = "城区拆迁 · 居民与企业等待替代用地"
		city.building_ids.erase(int(building.id))
	building.erase("city_id")

func reconcile_buildings(sim: RefCounted, legacy_assets: bool=false) -> void:
	if not active:
		return
	# Older regions may include auxiliaries as city customers; remove those and
	# attach formerly unregistered player-built customers using the same rule.
	for city in cities:
		city.displaced_demand = float(city.get("displaced_demand",0.0))
		var kept: Array[int] = []
		for id in city.building_ids:
			var building: Dictionary = sim.get_building(int(id))
			if building.is_empty():
				continue
			if building.get("kind","") not in CUSTOMER_KINDS:
				building.erase("city_id")
				continue
			kept.append(int(id))
		city.building_ids = kept
	for building in sim.buildings:
		if building.get("kind","") not in CUSTOMER_KINDS:
			building.erase("city_id")
			continue
		if legacy_assets:
			# Generated legacy blocks have an explicit city-name prefix. Ordinary
			# player assets retain their catalog names and their invested basis.
			var city := _city(int(building.get("city_id",-1)))
			if not city.is_empty() and str(building.name).begins_with(str(city.name)+" · "):
				var level: int = int(building.get("level",1))
				var upgrades: float = float(sim.catalog[building.kind].price)*0.65*float(level*(level-1))/2.0
				building.ownership = "municipal"
				building.invested_capital = upgrades
				building.refund_basis = upgrades
		register_building(sim,building)

func prune(sim: RefCounted) -> void:
	# External removals cannot create invalid references. Public demolition must
	# call unregister_building before erasing to retain its city consequences.
	for city in cities:
		var ids: Array[int] = []
		for id in city.building_ids:
			var building: Dictionary = sim.get_building(int(id))
			if not building.is_empty() and building.get("kind","") in CUSTOMER_KINDS:
				ids.append(int(id))
		city.building_ids = ids

func city_status(id: int) -> Dictionary:
	for city in cities:
		if int(city.id) == id:
			return city.duplicate(true)
	return {}

func summary() -> Dictionary:
	var people := 0.0
	var growing := 0
	var declining := 0
	var service := 0.0
	for city in cities:
		people += float(city.population)
		growing += 1 if float(city.growth) > 0.005 else 0
		declining += 1 if float(city.growth) < -0.005 else 0
		service += float(city.service)
	return {"active": active, "city_count": cities.size(), "population": people,
		"growing": growing, "declining": declining,
		"average_service": service / float(cities.size()) if not cities.is_empty() else 0.0,
		"max_cities": 8}

func snapshot() -> Dictionary:
	var saved: Array = []
	for city in cities:
		var item: Dictionary = city.duplicate(true)
		item.anchor = [city.anchor.x, city.anchor.y]
		saved.append(item)
	return {"active": active, "cities": saved, "clock_hours": clock_hours,
		"current_hour": current_hour, "expansion_clock": expansion_clock}

func load_snapshot(data: Variant) -> bool:
	if not valid_snapshot(data):
		return false
	var restored: Array[Dictionary] = []
	for item in data.cities:
		var city: Dictionary = item.duplicate(true)
		city.id = int(city.id)
		city.anchor = Vector2i(int(city.anchor[0]), int(city.anchor[1]))
		city.expansions = int(city.expansions)
		city.displaced_demand = float(city.get("displaced_demand",0.0))
		var ids: Array[int] = []
		for id in city.building_ids:
			ids.append(int(id))
		city.building_ids = ids
		restored.append(city)
	cities = restored
	active = bool(data.active)
	clock_hours = float(data.clock_hours)
	current_hour = float(data.current_hour)
	expansion_clock = float(data.expansion_clock)
	return true

static func valid_snapshot(data: Variant, buildings_by_id: Dictionary = {}, strict_registration: bool=false) -> bool:
	if not data is Dictionary or not data.get("active") is bool or not data.get("cities") is Array:
		return false
	if data.cities.size() != (8 if data.active else 0):
		return false
	if not _number(data.get("clock_hours"), 0.0, 1e12) or not _number(data.get("current_hour"), 0.0, 24.0) or float(data.current_hour) >= 24.0:
		return false
	if not _number(data.get("expansion_clock"), 0.0, 6.0) or float(data.expansion_clock) >= 6.0:
		return false
	var city_ids: Dictionary = {}
	var building_ids: Dictionary = {}
	for city in data.cities:
		if not city is Dictionary or not _integer(city.get("id"), 0, 7) or city_ids.has(int(city.id)):
			return false
		city_ids[int(city.id)] = true
		if not city.get("name") is String or city.name.length() > 80 or city.name.is_empty() or city.get("specialization") not in ROLES:
			return false
		if not city.get("trend") is String or city.trend.length() > 160:
			return false
		if not city.get("anchor") is Array or city.anchor.size() != 2 or not _integer(city.anchor[0], 1, 46) or not _integer(city.anchor[1], 1, 46):
			return false
		if not _number(city.get("base_population"), 1.0, 1000000.0) or not _number(city.get("population"), float(city.base_population) * 0.35 - 0.00001, float(city.base_population) * 3.0 + 0.00001):
			return false
		for key in ["service", "prosperity"]:
			if not _number(city.get(key), 0.0, 1.0):
				return false
		if not _number(city.get("growth"), -0.04, 0.035) or not _number(city.get("role_pressure"), 0.0, 48.0) or not _number(city.get("unserved_hours"), 0.0, 1e12) or not _integer(city.get("expansions"), 0, MAX_EXPANSIONS):
			return false
		if city.has("displaced_demand") and not _number(city.displaced_demand,0.0,1e9):
			return false
		if not city.get("building_ids") is Array or city.building_ids.size() > MAX_CITY_BUILDINGS:
			return false
		for id in city.building_ids:
			if not _integer(id, 1, 1000000000) or building_ids.has(int(id)):
				return false
			if not buildings_by_id.is_empty():
				if not buildings_by_id.has(int(id)) or int(buildings_by_id[int(id)].get("city_id", -1)) != int(city.id):
					return false
				if strict_registration and buildings_by_id[int(id)].get("kind","") not in CUSTOMER_KINDS:
					return false
			building_ids[int(id)] = true
	if strict_registration and not buildings_by_id.is_empty():
		for id in buildings_by_id:
			var building: Dictionary = buildings_by_id[id]
			if data.active and building.get("kind","") in CUSTOMER_KINDS:
				if not building_ids.has(int(id)) or not city_ids.has(int(building.get("city_id",-1))):
					return false
			elif building.has("city_id"):
				return false
	return true

static func _number(value: Variant, minimum: float, maximum: float) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value) >= minimum and float(value) <= maximum

static func _integer(value: Variant, minimum: int, maximum: int) -> bool:
	return _number(value, minimum, maximum) and float(value) == floorf(float(value))

func _result(ok: bool, message: String) -> Dictionary:
	return {"ok": ok, "message": message, "id": -1}
