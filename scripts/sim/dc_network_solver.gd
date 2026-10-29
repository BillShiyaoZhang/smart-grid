extends RefCounted
## Cached partial-pivot LU for a grounded DC network matrix.
## The caller's cache key must identify every matrix coefficient and the node
## order. Dispatch changes only the RHS, so the O(n^3) factorization is reused.
## All caller-owned arrays remain unchanged. Singular/invalid solves return [].

const CACHE_LIMIT := 64
const PIVOT_RELATIVE_TOLERANCE := 1.0e-12

var _cache: Dictionary = {}
var _recency: Array[int] = []
var factorization_count := 0

func clear() -> void:
	_cache.clear()
	_recency.clear()
	factorization_count = 0

func cached_factorizations() -> int:
	return _cache.size()

func solve(matrix: Array, injections: Array[float], cache_key: int) -> Array[float]:
	var n := matrix.size()
	if n == 0 or injections.size() != n:
		return []
	for i in n:
		if not (matrix[i] is Array or matrix[i] is PackedFloat64Array or matrix[i] is PackedFloat32Array) or matrix[i].size() != n or not is_finite(injections[i]):
			return []
	var factor: Dictionary
	if _cache.has(cache_key) and int(_cache[cache_key].size) == n:
		factor = _cache[cache_key]
		_recency.erase(cache_key)
		_recency.append(cache_key)
	else:
		factor = _factorize(matrix)
		factorization_count += 1
		if factor.is_empty():
			return []
		if _cache.has(cache_key):
			_recency.erase(cache_key)
		_cache[cache_key] = factor
		_recency.append(cache_key)
		if _recency.size() > CACHE_LIMIT:
			_cache.erase(_recency.pop_front())
	var lu: PackedFloat64Array = factor.lu
	var permutation: PackedInt32Array = factor.permutation
	var values := PackedFloat64Array()
	values.resize(n)
	# Forward substitution in Ly = Pb; L has an implicit unit diagonal.
	for i in n:
		var value := injections[permutation[i]]
		var offset := i*n
		for j in i:
			value -= lu[offset+j]*values[j]
		values[i] = value
	# Back substitution in Ux = y, in the original column/node order.
	for i in range(n-1,-1,-1):
		var value := values[i]
		var offset := i*n
		for j in range(i+1,n):
			value -= lu[offset+j]*values[j]
		value /= lu[offset+i]
		if not is_finite(value):
			return []
		values[i] = value
	var result: Array[float] = []
	result.assign(values)
	return result

func _factorize(matrix: Array) -> Dictionary:
	var n := matrix.size()
	var lu := PackedFloat64Array()
	lu.resize(n*n)
	var permutation := PackedInt32Array()
	permutation.resize(n)
	var scale := 0.0
	for i in n:
		permutation[i] = i
		for j in n:
			var value: Variant = matrix[i][j]
			if not (value is int or value is float) or not is_finite(float(value)):
				return {}
			lu[i*n+j] = float(value)
			scale = maxf(scale,absf(float(value)))
	if scale == 0.0:
		return {}
	var tolerance := scale*PIVOT_RELATIVE_TOLERANCE
	for k in n:
		var pivot := k
		var largest := absf(lu[k*n+k])
		for i in range(k+1,n):
			var magnitude := absf(lu[i*n+k])
			if magnitude > largest:
				largest = magnitude
				pivot = i
		if largest <= tolerance:
			return {}
		if pivot != k:
			for j in n:
				var value := lu[k*n+j]
				lu[k*n+j] = lu[pivot*n+j]
				lu[pivot*n+j] = value
			var old_index := permutation[k]
			permutation[k] = permutation[pivot]
			permutation[pivot] = old_index
		var diagonal := lu[k*n+k]
		var pivot_offset := k*n
		for i in range(k+1,n):
			var offset := i*n
			var multiplier := lu[offset+k]/diagonal
			lu[offset+k] = multiplier
			for j in range(k+1,n):
				lu[offset+j] -= multiplier*lu[pivot_offset+j]
	return {"size":n,"lu":lu,"permutation":permutation}
