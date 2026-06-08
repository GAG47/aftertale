shader_type canvas_item;

uniform vec4 panel_color : source_color = vec4(0.035, 0.045, 0.050, 0.92);
uniform float fade_start : hint_range(0.0, 1.0) = 0.28;
uniform float end_alpha : hint_range(0.0, 1.0) = 0.10;
uniform float edge_softness : hint_range(0.01, 0.5) = 0.20;

void fragment() {
	float fade = smoothstep(fade_start, min(1.0, fade_start + edge_softness), UV.x);
	float alpha = mix(panel_color.a, end_alpha, fade);
	COLOR = vec4(panel_color.rgb, alpha);
}
