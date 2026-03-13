shader_type canvas_item;

uniform float outline_width: hint_range(0, 10) = 3.0;
uniform vec4 outline_color: source_color;

void fragment() {
	vec4 color = texture(TEXTURE, UV);
	float alpha = color.a;
	
	if (alpha > 0.0) {
		// Para mantener el modulate, necesitamos multiplicar por COLOR
		// COLOR al inicio del fragment contiene el modulate
		COLOR = color * COLOR;
	} else {
		float thickness = outline_width / float(textureSize(TEXTURE, 0).x);
		float outline = 0.0;
		
		for (float x = -outline_width; x <= outline_width; x++) {
			for (float y = -outline_width; y <= outline_width; y++) {
				if (texture(TEXTURE, UV + vec2(x, y) * thickness).a > 0.0) {
					outline = 1.0;
					break;
				}
			}
			if (outline > 0.0) break;
		}
		
		if (outline > 0.0) {
			COLOR = outline_color;
		} else {
			COLOR = vec4(0.0);
		}
	}
}