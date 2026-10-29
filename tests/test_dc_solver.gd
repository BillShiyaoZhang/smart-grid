extends SceneTree

const Solver = preload("res://scripts/sim/dc_network_solver.gd")
var checks := 0
var failures := 0

func check(condition: bool,message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("FAIL: "+message)

func near(a: float,b: float) -> bool:
	return absf(a-b) < 0.000001

func matches(actual: Array[float],expected: Array[float]) -> bool:
	if actual.size() != expected.size():
		return false
	for i in actual.size():
		if not near(actual[i],expected[i]):
			return false
	return true

func _initialize() -> void:
	var solver := Solver.new()
	var matrix: Array = [[4.0,-1.0,0.0],[-1.0,4.0,-1.0],[0.0,-1.0,3.0]]
	var before: Array = matrix.duplicate(true)
	var rhs: Array[float] = [2.0,4.0,7.0]
	var rhs_before: Array[float] = rhs.duplicate()
	check(matches(solver.solve(matrix,rhs,10),[1.0,2.0,3.0]),"known three-node grounded system has correct angles")
	check(matrix == before and rhs == rhs_before,"factorization never mutates input coefficients or injections")
	check(matches(solver.solve(matrix,[4.0,8.0,14.0],10),[2.0,4.0,6.0]),"cached factorization handles changed dispatch")
	check(solver.factorization_count == 1,"unchanged topology factorizes only once")
	check(matches(solver.solve([[2.0,0.0,0.0],[0.0,4.0,0.0],[0.0,0.0,5.0]],[2.0,8.0,15.0],11),[1.0,2.0,3.0]),"changed topology key uses a new coefficient matrix")
	check(solver.factorization_count == 2,"distinct topology factorizes independently")
	check(matches(solver.solve([[0.0,2.0,1.0],[1.0,0.0,3.0],[4.0,5.0,6.0]],[7.0,10.0,32.0],12),[1.0,2.0,3.0]),"partial pivoting solves a matrix with a zero leading diagonal")
	check(solver.solve([[1.0,2.0],[2.0,4.0]],[1.0,2.0],13).is_empty(),"singular systems return no invented solution")
	check(solver.solve([[0.0,0.0],[0.0,0.0]],[1.0,2.0],14).is_empty(),"zero matrix is rejected")
	check(solver.solve([[1.0,NAN],[0.0,1.0]],[1.0,2.0],15).is_empty(),"nonfinite coefficients are rejected")
	check(solver.solve(matrix,[1.0,NAN,2.0],10).is_empty(),"nonfinite cached RHS is rejected")
	check(solver.solve([[1.0]],[1.0,2.0],16).is_empty(),"RHS dimension mismatch is rejected")
	check(solver.solve([[1.0],[0.0,1.0]],[1.0,2.0],17).is_empty(),"ragged matrix is rejected")
	check(matches(solver.solve([[1.0e-15]],[3.0e-15],18),[3.0]),"relative pivot threshold supports small well-conditioned coefficients")
	for key in range(100,170):
		solver.solve([[2.0]],[6.0],key)
	check(solver.cached_factorizations() == 64,"factorization cache is bounded at sixty-four topologies")
	var count_before := solver.factorization_count
	solver.solve([[2.0]],[8.0],169)
	check(solver.factorization_count == count_before,"recently used topology remains cached")
	solver.solve([[2.0]],[8.0],100)
	check(solver.factorization_count == count_before+1,"oldest unused topology is evicted")
	solver.clear()
	check(solver.cached_factorizations() == 0 and solver.factorization_count == 0,"clear releases cached factors and counters")
	var size := 80
	var network: Array = []
	var load: Array[float] = []
	for i in size:
		var row: Array[float] = []
		row.resize(size)
		row.fill(0.0)
		row[i] = 3.0
		if i > 0:
			row[i-1] = -1.0
		if i < size-1:
			row[i+1] = -1.0
		network.append(row)
		load.append(1.0)
	var initial := solver.solve(network,load,200)
	var started := Time.get_ticks_usec()
	for iteration in 30:
		solver.solve(network,load,200)
	var elapsed := Time.get_ticks_usec()-started
	check(initial.size() == size and solver.factorization_count == 1,"eighty-node network reuses its factorization across thirty dispatches")
	var residual := 0.0
	for i in size:
		var sum := 0.0
		for j in size:
			sum += float(network[i][j])*initial[j]
		residual = maxf(residual,absf(sum-load[i]))
	check(residual < 0.000001,"large cached solution preserves the linear power balance")
	print("DC SOLVER TESTS: %d checks; %d failures; 30 cached 80-node solves %.2f ms" % [checks,failures,float(elapsed)/1000.0])
	quit(1 if failures > 0 else 0)
