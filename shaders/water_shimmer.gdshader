shader_type canvas_item;

// Gemericik air di layer kolam/sungai. Tidak menggeser UV: pada TileMapLayer
// TEXTURE adalah atlas, jadi wobble UV menarik pixel tile tetangga dan
// menciptakan garis di tepi ubin. Godot 4 juga tidak punya POSITION di
// canvas_item fragment, jadi frekuensinya diambil dari UV atlas — tiap ubin
// duduk di koordinat atlas berbeda, jadi fase gemeriknya tidak seragam.

uniform float speed : hint_range(0.0, 8.0) = 2.2;
uniform float strength : hint_range(0.0, 1.0) = 0.75;

void fragment() {
	vec4 c = texture(TEXTURE, UV);
	if (c.a < 0.01) {
		discard;
	}
	float band = sin(UV.y * 26.0 - TIME * speed) * 0.5 + 0.5;
	float ripple = sin(UV.x * 19.0 + TIME * speed * 0.7) * 0.5 + 0.5;
	float k = smoothstep(0.55, 1.0, band) + ripple * 0.25;
	c.rgb += vec3(0.20, 0.28, 0.34) * k * strength * c.a;
	COLOR = c;
}
