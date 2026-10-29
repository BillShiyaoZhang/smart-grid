extends RefCounted
## Runtime-only drafts. Refresh reconciles clean sections and preserves edited sections.
var values: Dictionary = {}
var baselines: Dictionary = {}

func retain(key: String, effective: Dictionary, edited: Dictionary = {}) -> Dictionary:
	if not values.has(key):
		reset(key,effective)
	else:
		if not edited.is_empty(): values[key]=edited.duplicate(true)
		var changed: bool = not equivalent(values[key],baselines[key])
		baselines[key]=effective.duplicate(true)
		if not changed: values[key]=effective.duplicate(true)
	return values[key].duplicate(true)

func reset(key: String, effective: Dictionary) -> void:
	values[key]=effective.duplicate(true)
	baselines[key]=effective.duplicate(true)

func clear() -> void:
	values.clear()
	baselines.clear()

func dirty(key: String) -> bool:
	return values.has(key) and not equivalent(values[key],baselines[key])

static func equivalent(a: Dictionary,b: Dictionary) -> bool:
	if a.size()!=b.size(): return false
	for key in a:
		if not b.has(key): return false
		if (a[key] is int or a[key] is float) and (b[key] is int or b[key] is float):
			if not is_equal_approx(float(a[key]),float(b[key])): return false
		elif a[key]!=b[key]: return false
	return true
