extends SceneTree
## All submitted field work shares two real crews; waiting work is not active.
const Sim=preload("res://scripts/sim/grid_sim.gd")
const Presenter=preload("res://scripts/ui/grid_presenter.gd")
const Dock=preload("res://scripts/ui/operator_dock.gd")
var checks:=0
var failures:=0

class GameStub extends Node:
	var sim: RefCounted
	var target: Array=[]
	func focus_target(kind: String,id: int) -> void: target=[kind,id]

func _initialize() -> void: _run.call_deferred()

func check(condition: bool,message: String) -> void:
	checks+=1
	if not condition:
		failures+=1
		push_error("FAIL: "+message)

func _world() -> RefCounted:
	var sim: RefCounted=Sim.new()
	sim.next_storm_at=10000.0
	sim.digital.next_attack_at=10000.0
	sim.cash=1000000.0
	return sim

func _of(rows: Array,source: String) -> Array:
	return rows.filter(func(row: Dictionary): return row.source==source)

func _active(rows: Array) -> Array:
	return rows.filter(func(row: Dictionary): return bool(row.get("crew_active",false)))

func _labels(node: Node) -> Array[String]:
	var result: Array[String]=[]
	if node is Label: result.append(node.text)
	for child in node.get_children(): result.append_array(_labels(child))
	return result

func _buttons(node: Node) -> Array[Button]:
	var result: Array[Button]=[]
	if node is Button and node.text=="查看目标": result.append(node)
	for child in node.get_children(): result.append_array(_buttons(child))
	return result

func _run() -> void:
	var sim:=_world()
	check(sim.configure_facility(1,{"dispatch":0.5},"field").ok,"existing field control occupies a real crew")
	check(sim.lifecycle.enable(sim).ok,"asset management can issue real work")
	check(sim.lifecycle.maintenance(sim,"facility",2,"inspect").ok,"maintenance uses the second crew")
	check(sim.lifecycle.maintenance(sim,"facility",3,"inspect").ok,"additional inspection enters waiting queue")
	var before: Dictionary=sim.snapshot().duplicate(true)
	var rows: Array=Presenter.jobs(sim)
	var maintenance: Array=_of(rows,"资产检修工单")
	check(maintenance.size()==2,"unified queue includes both lifecycle orders")
	check(_active(rows).size()==sim.active_repairs() and _active(rows).size()==2,"crew lanes agree with the simulation across old and new jobs")
	check(maintenance.filter(func(row: Dictionary): return row.phase=="queued").size()==1,"waiting lifecycle job is distinguished from active work")
	for row in maintenance:
		check(row.crew_active==(row.phase=="pending"),"waiting order cannot claim a crew")
		check(row.duration==0.0,"maintenance does not fabricate an unrecorded original duration")
	var keys: Dictionary={}
	for row in rows:
		check(not keys.has(row.key),"order identities are namespaced across independent ID counters")
		keys[row.key]=true
	check(sim.snapshot()==before,"reading all work does not change money, RNG, clock or observations")
	rows[0].message="tampered display"
	check(Presenter.jobs(sim)[0].message!="tampered display","queue DTO mutation never mutates submitted orders")
	sim.step(2.0)
	var receipts: Array=_of(Presenter.jobs(sim),"资产检修回执")
	check(receipts.size()==2 and _active(Presenter.jobs(sim)).is_empty(),"completed maintenance frees real crews and remains visible as receipts")
	for row in receipts:
		check(row.phase=="executed" and not row.has("health"),"maintenance receipt confirms work without exporting raw hidden health")

	var mixed:=_world()
	mixed.lifecycle.enable(mixed)
	mixed.customers.enable(mixed)
	var defined: Dictionary=mixed.customers.define_microgrid(mixed,"医院分区",[2],[])
	check(defined.ok,"microgrid partition is defined through production API")
	check(mixed.customers.set_microgrid(mixed,int(defined.id),true,"field").ok,"microgrid switch dispatches a real field crew")
	check(mixed.configure_facility(1,{"dispatch":0.5},"field").ok,"digital field command shares the second crew")
	check(mixed.lifecycle.maintenance(mixed,"facility",3,"inspect").ok and mixed.lifecycle.maintenance(mixed,"facility",4,"inspect").ok,"maintenance queues behind microgrid and digital field crews")
	rows=Presenter.jobs(mixed)
	var microgrid: Dictionary=_of(rows,"微电网切换工单")[0]
	check(_active(rows).size()==2 and mixed.active_repairs()==2,"microgrid switch appears in shared crew occupancy")
	check(microgrid.target_type=="facility" and microgrid.target_id==2,"partition work navigates to an existing member")
	check(_of(rows,"资产检修工单").all(func(row: Dictionary): return row.phase=="queued" and not row.crew_active),"queued inspections stay outside active lanes")
	var saved: Dictionary=mixed.snapshot()
	var restored:=_world()
	check(restored.restore_snapshot(saved).ok,"production save restores mixed work")
	check(Presenter.jobs(restored)==rows,"all pending and queued work survives snapshot restore with stable keys")
	var game:=GameStub.new()
	game.sim=mixed
	root.add_child(game)
	var dock:=Dock.new()
	root.add_child(dock)
	dock.game=game
	dock.body=VBoxContainer.new()
	dock.add_child(dock.body)
	dock._jobs(rows)
	await process_frame
	var labels:=_labels(dock.body)
	check(labels.count("执行中")==2,"real job page shows exactly two occupied lanes")
	check(labels.count("◷ 等待现场队")==2,"job page displays both waiting orders outside the lanes")
	check(labels.filter(func(value: String): return "出发时间未定" in value).size()==2,"waiting UI explains unknown departure time")
	var buttons:=_buttons(dock.body)
	check(buttons.size()==rows.size(),"every active or waiting order retains a target action")
	if not buttons.is_empty():
		buttons[0].pressed.emit()
		check(game.target.size()==2 and game.target[0]=="facility","real target button uses existing map navigation")
	mixed.step(0.4)
	var grid_receipts: Array=_of(Presenter.jobs(mixed),"微电网最近回执")
	check(grid_receipts.size()==1 and grid_receipts[0].phase=="executed","successful actual switch becomes an explicit receipt")
	check(not grid_receipts[0].has("elapsed_hours") and grid_receipts[0].method=="microgrid","latest microgrid receipt invents neither method nor timestamp")
	var grid: Dictionary=mixed.customers.microgrids[0]
	grid.receipt="切换被拒绝：边界已变化或通信不可用"
	check(_of(Presenter.jobs(mixed),"微电网最近回执")[0].phase=="rejected","explicit rejection is never presented as completion")
	grid.receipt="边界设施已拆除，切换作业取消"
	check(_of(Presenter.jobs(mixed),"微电网最近回执")[0].phase=="cancelled","explicit cancellation remains distinct from success")
	game.queue_free()
	dock.queue_free()
	await process_frame
	print("UNIFIED JOBS: %d checks; %d failures" % [checks,failures])
	quit(1 if failures else 0)
