shader_type canvas_item;

// --- PARAMETER YANG BISA DIATUR DI INSPECTOR ---
uniform vec4 base_color : source_color = vec4(0.3, 0.3, 0.35, 1.0); // Warna Ubin
uniform vec4 mortar_color : source_color = vec4(0.1, 0.1, 0.1, 1.0); // Warna Garis
uniform float tile_size = 32.0; // Ukuran per kotak (pixel)
uniform float border_width = 2.0; // Ketebalan garis (pixel)

void fragment() {
	// Mendapatkan koordinat pixel asli
	vec2 pixel_pos = UV / TEXTURE_PIXEL_SIZE;
	
	// Menghitung posisi relatif dalam satu kotak grid (0.0 sampai 32.0)
	vec2 grid_pos = mod(pixel_pos, tile_size);
	
	// Logika pembatas (Border)
	// Jika posisi pixel berada di pinggir (kurang dari border_width), jadikan warna mortar
	float is_border_x = step(border_width, grid_pos.x) * step(grid_pos.x, tile_size - border_width);
	float is_border_y = step(border_width, grid_pos.y) * step(grid_pos.y, tile_size - border_width);
	
	float is_tile = is_border_x * is_border_y;
	
	// Campurkan warna: Jika is_tile 1 -> base_color, Jika 0 -> mortar_color
	COLOR = mix(mortar_color, base_color, is_tile);
}
