#ifndef MERIDIAN_END_PORTAL
#define MERIDIAN_END_PORTAL

// End portal and gateway surface. Vanilla draws these with its own shader, which Iris replaces, so
// without this the portal is its (nearly black) texture lit like stone. Here the surface is a
// window into a starfield: PORTAL_LAYERS sheets of stars at increasing depths behind the face,
// each intersected along the actual view ray, so the field shows parallax as the camera moves
// (depth without geometry). Layers drift slowly in different directions; the deepest carries a
// faint violet-blue haze. Output is display-referred sRGB albedo for the flat-emissive path
// (the deferred pass multiplies it by 6 * EMISSION_STRENGTH), so the brightest stars glow while
// the base stays near black.
// Requires noise.glsl (hashes, value noise), uniforms.glsl (frameTimeCounter, cameraPosition).

const int PORTAL_LAYERS = 6;

vec3 endPortalColor(vec3 playerPos, vec3 n) {
    vec3 viewDir = normalize(playerPos);
    // Tangent frame of the face (portals are horizontal, gateways have all six faces).
    vec3 t = abs(n.y) > 0.5 ? vec3(1.0, 0.0, 0.0) : normalize(cross(vec3(0.0, 1.0, 0.0), n));
    vec3 b = cross(n, t);
    vec3 world = playerPos + cameraPosition;
    float into = max(dot(viewDir, -n), 0.08);    // how directly the ray enters the face

    vec3 col = vec3(0.004, 0.003, 0.010);         // the void
    float time = frameTimeCounter;
    for (int i = 0; i < PORTAL_LAYERS; i++) {
        float fi = float(i);
        float depth = 0.6 + fi * 1.7;                         // blocks behind the surface
        vec3 q = world + viewDir * (depth / into);
        vec2 uv = vec2(dot(q, t), dot(q, b));
        float ang = fi * 2.399963;
        uv += vec2(cos(ang), sin(ang)) * time * (0.025 + 0.012 * fi);   // slow, different drift per sheet
        float cell = 0.45 + fi * 0.18;
        vec2 g = uv / cell;
        ivec2 c = ivec2(floor(g));
        vec3 h = hash3(c + ivec2(31 * i, 17 * i));
        // About one star in three cells, at a random place in the cell.
        if (h.z < 0.34) {
            vec2 p = (vec2(c) + 0.2 + 0.6 * h.xy) * cell;
            float d = length(uv - p);
            float px = max(fwidth(uv.x) + fwidth(uv.y), 1e-4);   // anti-aliased star size
            float r = cell * (0.03 + 0.05 * h.x) + px;
            float star = sq(saturate(1.0 - d / r)) * (0.55 + 0.45 * sin(time * (1.3 + h.y * 2.0) + h.x * 40.0));
            // Restrained palette: white-blue stars, some violet, a few teal.
            vec3 tint = h.y < 0.6 ? vec3(0.80, 0.86, 1.0) : (h.y < 0.85 ? vec3(0.72, 0.52, 1.0) : vec3(0.45, 0.95, 0.90));
            col += tint * star * (1.0 - fi / float(PORTAL_LAYERS)) * 0.55;
        }
    }
    // Deep haze: soft violet-blue clouds on the farthest sheet.
    vec3 qd = world + viewDir * ((0.6 + float(PORTAL_LAYERS) * 1.7) / into);
    vec2 uvd = vec2(dot(qd, t), dot(qd, b)) * 0.35 + time * 0.01;
    float neb = valueNoise(uvd) * 0.6 + valueNoise(uvd * 2.3 + 7.0) * 0.4;
    col += vec3(0.05, 0.03, 0.11) * smoothstep(0.35, 0.9, neb);
    return linearToSrgb(saturate(col));
}

#endif
