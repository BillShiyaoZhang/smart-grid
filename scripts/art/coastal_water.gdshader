shader_type spatial;
render_mode unshaded, cull_back;

uniform vec4 deep_color : source_color = vec4(0.075, 0.35, 0.44, 1.0);
uniform vec4 shallow_color : source_color = vec4(0.21, 0.63, 0.65, 1.0);
uniform vec4 foam_color : source_color = vec4(0.74, 0.91, 0.86, 1.0);
uniform float island_half = 16.0;
uniform float daylight = 1.0;
uniform bool motion = true;
varying vec2 sea_point;

void vertex() {
	sea_point = VERTEX.xz;
}

void fragment() {
	float clock = motion ? TIME * 0.24 : 0.0;
	vec2 shore_point = abs(sea_point);
	float edge_distance = max(max(shore_point.x, shore_point.y) - island_half,
		(shore_point.x + shore_point.y - (island_half * 2.0 - 2.0)) * 0.7071);
	float shallow = exp(-max(0.0, edge_distance - 1.0) * 0.13);
	float swell = sin(sea_point.y * 2.4 + sin(sea_point.x * 0.31) * 0.65 + clock);
	float ribbon = smoothstep(0.95, 0.999, swell);
	float ripple = ribbon * smoothstep(0.20, 0.75, sin(sea_point.x * 0.82 - sea_point.y * 0.18));
	float shoreline = exp(-pow((edge_distance - 2.1) * 1.05, 2.0));
	float shore_foam = smoothstep(0.20, 0.82, sin(edge_distance * 7.0 + swell * 0.45 - clock)) * shoreline;
	vec3 water = mix(deep_color.rgb, shallow_color.rgb, shallow * 0.72);
	water += swell * 0.018;
	water = mix(water, foam_color.rgb, ripple * 0.14 + shore_foam * 0.36);
	ALBEDO = water * mix(0.28, 1.0, daylight);
}
