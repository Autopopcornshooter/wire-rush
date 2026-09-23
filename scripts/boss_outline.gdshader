shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, depth_test_disabled, cull_back;

// A translucent sensor silhouette keeps the distant interceptor identifiable
// through near route drones without hiding or moving those gameplay obstacles.
void fragment() {
 float rim = pow(1.0 - abs(dot(normalize(NORMAL), normalize(VIEW))), 2.5);
 ALBEDO = vec3(0.15, 0.85, 1.0);
 ALPHA = rim * 0.55;
}
