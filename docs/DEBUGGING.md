# Debugging

## Debug views

Shader settings → **Debugging → Debug View**. The view replaces the final image; everything
else keeps running, so the cost of the view itself is negligible.

| # | View | Produced in | What to look for |
|---|---|---|---|
| 1 | Albedo | G-buffer | Texture colour without lighting (sRGB). Dark = material darkening, e.g. wetness is applied later and not shown here. |
| 2 | Normals | G-buffer | Scene-space normals (+X red, +Y green, +Z blue). Flicker or noise here = normal-map problem. |
| 3 | Roughness | G-buffer | sqrt(GGX alpha); black = mirror. |
| 4 | Metal / F0 | G-buffer | Gold tint = metal; grey level = dielectric F0 × 4. |
| 5 | Emission | G-buffer | LabPBR / synthesised emission. |
| 6 | Shadow visibility | deferred4 | Shadow map + contact shadows, before light colour. |
| 7 | Direct light | deferred4 | Sun/moon/black-hole contribution only. |
| 8 | Indirect light | deferred4 | Sky, block light, emission excluded. |
| 9 | Reflection hits | composite | Red = SSR confidence, green = water Fresnel, blue = smoothness of SSR-receiving blocks. |
| 10 | Cloud scattering | deferred1 | Reconstructed cloud radiance. Ghost trails here = temporal reprojection issue. |
| 11 | Cloud transmittance | deferred1 | White = clear sky. |
| 12 | Water sim height | composite | Red = up, blue = down (×10); faint green = simulated area. |
| 13 | Water sim velocity | composite | Same colours for vertical velocity. |
| 14 | TAA history rejection | composite3 | White = history discarded (disocclusion, fast motion). |
| 15 | Motion vectors | composite3 | Pixel motion (red = x, green = y). |
| 16 | Exposure | final | Scene luminance relative to the metered average: blue −4 EV … red +4 EV. |
| 17 | LOD terrain mask | final | Orange = DH/Voxy terrain, blue = vanilla. |
| 18 | Linear depth | G-buffer | Use to check LOD depth alignment. |
| 19 | Ambient occlusion | deferred4 | SSAO × vanilla/texture AO. |
| 20 | Light volume | deferred4 | Coloured-light chroma × confidence; black = vanilla-coloured block light. |
| 21 | Bounce light (SSGI) | deferred4 | Denoised SSGI correction before albedo (bounce added; occluded sky shows black because negatives clip); noise or ghosting here = SSGI. |
| 22 | Lightmap | final | Block light red, sky light blue, as used by lighting. Black LOD terrain outdoors = missing sky light. |

Isolating an artifact: if it is visible in 1–5 it comes from materials/resource pack; in 6–8
from lighting; in 10–11 from clouds; 12–13 from the water simulation; 14–15 from TAA.

## Other tools

* **Eclipse preview** (Eclipses → Eclipse Preview): loops a partial/total solar or lunar
  eclipse every 60 s without changing world time. Solar previews need daytime.
* **Disabling a pass:** every optional pass has an option (clouds, volumetric light, coloured
  light, SSR, SSAO, contact shadows, bloom, DOF, motion blur, TAA). Disabled passes are not
  dispatched at all.
* **Iris log:** `logs/latest.log` lists compile errors with file and line of the expanded
  source; run `python tools/validate.py` first — it reports the same errors with the original
  `shaders/...` file and line.
* **Frame captures:** RenderDoc or NVIDIA Nsight Graphics. Pass names follow Iris program names
  (`deferred4`, `composite3`, …); `docs/ORIGINAL_ARCHITECTURE.md §1` maps them to features.

## Offline validation

```
# glslang from https://github.com/KhronosGroup/glslang/releases
set GLSLANG=C:\path\to\glslang.exe
python tools/gen_wrappers.py        # regenerate world*/ wrappers after adding programs
python tools/validate.py            # all variants (~2-3 min); --quick for defaults only
python -P tools/tests/test_water_sim.py
python -P tools/tests/test_celestial.py
python -P tools/tests/test_black_hole.py
python -P tools/tests/test_cloud_march.py
python -P tools/tests/render_end_planets.py <dir>   # End planet preview images
```

`validate.py` compiles every program of every dimension for: defaults, Distant Horizons,
Voxy, pre-1.10.4 Iris, every preset, every on/off option flipped, and every value of options
that select code in `#if` blocks. It also fails on menu problems (options missing from a
screen or language file, unknown preset entries) and on non-ASCII bytes in pack files.
