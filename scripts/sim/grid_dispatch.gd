extends RefCounted
## Per-island merit order and energy provenance. Query passes never commit MWh.

static func solve_component(sim: RefCounted, ids: Array[int], dt: float) -> float:
	var original_budget: float = sim._contract_budget
	var blocked: Dictionary = {}
	var result: Dictionary = {}
	for _attempt in ids.size()+1:
		sim._contract_budget = original_budget
		result = _dispatch(sim,ids,blocked,dt)
		var changed := false
		for b in result.generators:
			if b.kind not in ["nuclear","fusion"] or blocked.has(int(b.id)) or float(b.available)<=0.000001: continue
			var assignment: Dictionary = sim.evolution.support_assignment(sim,b,ids)
			if not sim.evolution.support_powered(sim,assignment):
				blocked[int(b.id)] = true
				changed = true
		if not changed: break
	var supplied := 0.0
	var renewable := 0.0
	for id in ids:
		var b: Dictionary = sim.get_building(id)
		if not sim.evolution.is_terminal(str(b.kind)): supplied += maxf(0.0,float(b.output))
		if b.kind in ["solar","wind","hydro"]: renewable += maxf(0.0,float(b.output))
		elif sim.evolution.is_storage(str(b.kind)):
			var fraction := clampf(float(b.get("renewable_energy_mwh",0.0))/maxf(0.000001,float(b.energy)),0.0,1.0)
			renewable += float(b.output)*fraction
	supplied += float(result.imports)
	var renewable_fraction := clampf(renewable/maxf(0.000001,supplied),0.0,1.0)
	for id in ids:
		var b: Dictionary = sim.get_building(id)
		b.renewable_served_mw = float(b.served)*renewable_fraction
		if sim.evolution.is_storage(str(b.kind)) and dt>0.0:
			var efficiency: float = sim.evolution.storage_efficiency(b)
			var old_energy: float = b.energy
			var old_renewable := clampf(float(b.get("renewable_energy_mwh",0.0)),0.0,old_energy)
			var withdrawn: float = minf(old_energy,float(b.output)*dt/efficiency)
			b.energy = clampf(old_energy+float(b.charging)*dt*efficiency-withdrawn,0.0,float(b.energy_capacity))
			b.renewable_energy_mwh = clampf(old_renewable-withdrawn*old_renewable/maxf(0.000001,old_energy)+float(b.charging)*dt*efficiency*renewable_fraction,0.0,float(b.energy))
		b.soc = float(b.energy)/float(b.energy_capacity) if float(b.energy_capacity)>0.0 else 0.0
		b.voltage = 1.0 if b.powered else 0.0
	sim._solve_dc(ids)
	return float(result.contract_used)

static func _dispatch(sim: RefCounted, ids: Array[int], blocked: Dictionary, dt: float) -> Dictionary:
	var generators: Array[Dictionary] = []
	var renewables: Array[Dictionary] = []
	var batteries: Array[Dictionary] = []
	var loads: Array[Dictionary] = []
	var terminals: Array[Dictionary] = []
	var auxiliary_ids: Dictionary = {}
	var demand := 0.0
	var transfer_capacity := 0.0
	for id in ids:
		var b: Dictionary = sim.get_building(id)
		b.output=0.0; b.served=0.0; b.charging=0.0; b.available=0.0
		b.import_mw=0.0; b.export_mw=0.0
		if float(b.demand)>0.0:
			loads.append(b)
			if b.online: demand+=float(b.demand)
		if not b.online: continue
		if b.kind in ["solar","wind"]:
			if not b.get("enabled",true): continue
			b.available=float(b.capacity)*(sim.solar_factor() if b.kind=="solar" else sim.wind_factor())*(.7+float(b.health)*.003)
			renewables.append(b)
		elif sim.evolution.is_generator(str(b.kind)):
			b.available=0.0 if blocked.has(id) else sim.evolution.generator_available(sim,b,ids)
			generators.append(b)
			if b.kind in ["nuclear","fusion"] and (b.get("enabled",true) or float(b.get("ramp_mw",0.0))>0.000001):
				var assignment: Dictionary = sim.evolution.support_assignment(sim,b,ids)
				if assignment.ok:
					for aux in assignment.cooling_ids+assignment.academy_ids: auxiliary_ids[int(aux)]=true
		elif sim.evolution.is_storage(str(b.kind)):
			if b.get("enabled",true): batteries.append(b)
		elif sim.evolution.is_terminal(str(b.kind)):
			terminals.append(b)
			transfer_capacity+=float(b.grid_capacity)
		if b.kind in ["condenser","hvdc"] and b.get("enabled",true): auxiliary_ids[id]=true
	generators.sort_custom(func(a: Dictionary,b: Dictionary):
		var ca: float = sim.evolution.marginal_cost(a)
		var cb: float = sim.evolution.marginal_cost(b)
		return int(a.id)<int(b.id) if is_equal_approx(ca,cb) else ca<cb)
	var can_trade: bool = transfer_capacity>0.000001 and sim.market.state.market_mode!="off"
	var trade: bool = can_trade and sim.market.state.market_mode=="trade"
	var arbitrage: bool = sim.market.state.storage_mode=="arbitrage"
	var spot: float = sim.market.state.spot_price
	var can_buy: bool = can_trade and spot<=float(sim.market.state.buy_limit)
	var deficit := demand
	deficit -= _take_generation(sim,generators,deficit,INF,true)
	deficit -= _take_renewables(renewables,deficit)
	deficit -= _take_generation(sim,generators,deficit,0.000001)
	var contract_used := minf(deficit,minf(transfer_capacity,float(sim._contract_budget))) if can_trade else 0.0
	sim._contract_budget-=contract_used
	var imports := contract_used
	deficit-=contract_used
	var battery_discharge := 0.0
	if arbitrage and spot>=float(sim.market.state.discharge_price):
		battery_discharge=sim._discharge_batteries(batteries,deficit,dt,true)
		deficit-=battery_discharge
	for b in generators:
		if trade and can_buy and spot<sim.evolution.marginal_cost(b):
			var bought := minf(deficit,maxf(0.0,transfer_capacity-imports))
			imports+=bought; deficit-=bought
		var take := minf(deficit,maxf(0.0,float(b.available)-float(b.output)))
		b.output+=take; deficit-=take
	var extra_discharge: float = sim._discharge_batteries(batteries,deficit,dt,arbitrage)
	battery_discharge+=extra_discharge; deficit-=extra_discharge
	if can_buy:
		var bought := minf(deficit,maxf(0.0,transfer_capacity-imports))
		imports+=bought; deficit-=bought
	var served_supply := maxf(0.0,demand-deficit)
	var charging := 0.0
	if battery_discharge<=0.000001:
		# Already committed thermal energy has zero incremental fuel cost.
		var spill := _remaining_minimum(sim,generators)
		var charge: float = sim._charge_batteries(batteries,spill,dt)
		_take_generation(sim,generators,charge,INF,true)
		charging+=charge
		var free_surplus := _remaining_renewables(renewables)+_remaining_generation(sim,generators,0.000001)
		charge=sim._charge_batteries(batteries,free_surplus,dt)
		var clean_used := _take_renewables(renewables,charge)
		_take_generation(sim,generators,charge-clean_used,0.000001)
		charging+=charge
		if arbitrage and can_trade and deficit<=0.000001 and spot<=float(sim.market.state.charge_price):
			var import_room := maxf(0.0,transfer_capacity-imports)
			var prepaid := minf(import_room,float(sim._contract_budget))
			charge=sim._charge_batteries(batteries,import_room if can_buy else prepaid,dt)
			var paid_charge := minf(prepaid,charge)
			sim._contract_budget-=paid_charge; contract_used+=paid_charge
			imports+=charge; charging+=charge
	var exports := 0.0
	if trade and imports<=0.000001 and float(sim.market.state.export_price)>=float(sim.market.state.sell_floor):
		var price: float = sim.market.state.export_price
		var room := transfer_capacity
		var taken := _take_generation(sim,generators,room,INF,true)
		exports+=taken; room-=taken
		taken=_take_renewables(renewables,room)
		exports+=taken; room-=taken
		taken=_take_generation(sim,generators,room,price-0.000001)
		exports+=taken; room-=taken
		if arbitrage and spot>=float(sim.market.state.discharge_price) and charging<=0.000001:
			taken=sim._discharge_batteries(batteries,room,dt,true)
			exports+=taken; battery_discharge+=taken
	for b in renewables: b.curtailment_mw=maxf(0.0,float(b.available)-float(b.output))
	for b in generators: b.curtailment_mw=maxf(0.0,sim.evolution.generator_minimum(b)-float(b.output))
	for b in terminals:
		var share := float(b.grid_capacity)/transfer_capacity if transfer_capacity>0.0 else 0.0
		b.import_mw=imports*share; b.export_mw=exports*share; b.output=(imports-exports)*share
	# Self-sustaining plant auxiliaries must be delivered before customer service.
	var remaining := served_supply
	for b in loads:
		if b.online and auxiliary_ids.has(int(b.id)):
			b.served=minf(float(b.demand),remaining); remaining-=float(b.served)
	for b in loads:
		if b.online and not auxiliary_ids.has(int(b.id)) and b.kind=="hospital":
			b.served=minf(float(b.demand),remaining); remaining-=float(b.served)
	var ordinary_demand := 0.0
	for b in loads:
		if b.online and b.kind!="hospital" and not auxiliary_ids.has(int(b.id)): ordinary_demand+=float(b.demand)
	for b in loads:
		if b.online and b.kind!="hospital" and not auxiliary_ids.has(int(b.id)):
			b.served=float(b.demand)*minf(1.0,remaining/ordinary_demand) if ordinary_demand>0.0 else 0.0
	var energized: bool = served_supply+charging+exports>0.001 or (can_trade and can_buy)
	for id in ids:
		var b: Dictionary = sim.get_building(id)
		b.powered=energized and b.online and b.get("enabled",true) and (float(b.demand)<=0.0 or float(b.served)>=float(b.demand)*.98)
	return {"generators":generators,"imports":imports,"contract_used":contract_used}

static func _take_generation(sim: RefCounted, generators: Array[Dictionary], requested: float, max_cost: float=INF, minimum_only: bool=false) -> float:
	var total := 0.0
	for b in generators:
		if not minimum_only and sim.evolution.marginal_cost(b)>max_cost: continue
		var limit: float = sim.evolution.generator_minimum(b) if minimum_only else b.available
		var take := minf(maxf(0.0,requested-total),maxf(0.0,limit-float(b.output)))
		b.output+=take; total+=take
	return total

static func _take_renewables(renewables: Array[Dictionary], requested: float) -> float:
	var total := _remaining_renewables(renewables)
	var used := minf(maxf(0.0,requested),total)
	for b in renewables:
		b.output+=used*maxf(0.0,float(b.available)-float(b.output))/total if total>0.0 else 0.0
	return used

static func _remaining_renewables(renewables: Array[Dictionary]) -> float:
	var result := 0.0
	for b in renewables: result+=maxf(0.0,float(b.available)-float(b.output))
	return result

static func _remaining_generation(sim: RefCounted, generators: Array[Dictionary], max_cost: float) -> float:
	var result := 0.0
	for b in generators:
		if sim.evolution.marginal_cost(b)<=max_cost: result+=maxf(0.0,float(b.available)-float(b.output))
	return result

static func _remaining_minimum(sim: RefCounted, generators: Array[Dictionary]) -> float:
	var result := 0.0
	for b in generators: result+=maxf(0.0,sim.evolution.generator_minimum(b)-float(b.output))
	return result
