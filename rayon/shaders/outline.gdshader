shader_type spatial;
// Inverted-hull outline. The smoothed normal is packed in UV.xy + UV2.x by MeshKit.
render_mode unshaded, cull_front, depth_draw_opaque, shadows_disabled, fog_disabled;

uniform vec4 outline_color : source_color = vec4(0.09, 0.08, 0.1, 1.0);
uniform float thickness = 0.025;
uniform float outline_scale = 1.0;

void vertex() {
	vec3 sn = vec3(UV.x, UV.y, UV2.x);
	if (length(sn) < 0.01) {
		sn = NORMAL;
	}
	VERTEX += normalize(sn) * thickness * outline_scale;
}

void fragment() {
	ALBEDO = outline_color.rgb;
}
