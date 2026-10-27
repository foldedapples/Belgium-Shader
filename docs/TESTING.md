# Testing

## Automated (run before every commit)

```
python -I tools/validate.py --variants base dh voxy --profiles   # glslang, every program
python -I tools/check_options.py                                 # settings menu consistency
python -P tools/tests/test_shadow_stability.py                   # cascade grid maths
python -P tools/tests/test_sun_glare.py                          # bloom of the sun disk
python -P tools/tests/test_ripple_precision.py                   # rain-ripple coordinates
python -P tools/tests/test_wave_filter.py                        # water footprint prefilter
```

`validate.py` also fails if a dimension's Voxy shader copy differs from `program/voxy/` (Voxy
compiles those files itself and cannot `#include`; they are not compiled by glslang here).

`validate.py` inlines `#include`s the way Iris does and injects Iris' built-in macros (and the DH
`dhMaterialId` attribute). It then compiles each program in `world0`, `world-1` and `world1` with
Khronos glslang, for the base, Distant Horizons and Voxy variants, at the defaults and at each
quality profile in `shaders.properties`. Last result (2026-10-26): 18 configurations, 0 failures
(265 programs per base/Voxy configuration, 283 with DH).

glslang is a reference front end, not the GPU driver. Driver-specific errors, Iris' own
preprocessing (option rewriting, custom uniforms) and link-time interface mismatches between
stages are **not** covered.

## In game: not yet done

Nothing in this repository has been run in Minecraft since the 2026-10-26 fixes. Still to verify,
on Minecraft 1.21.11 + Fabric + Sodium + Iris:

* Iris loads the pack with no errors in `logs/latest.log`.
* Shadows stay put while walking, strafing, flying and turning, at x≈0 and at x≈±20,000 (debug
  view 9 shows the texel checker, which must not swim).
* Sun: a moderate glow, no flat glare disc; water and wet surfaces show a single sun glint.
* Night: shadows are not crushed at Vibrant / Cinematic; the Moon shows maria and highlands.
* Clouds keep their shape after 30+ minutes of play and move with the rain's lean.
* End and Nether exposure; Distant Horizons and Voxy, each **on its own**. Simultaneous use is
  not supported or claimed.
* Performance: none measured. Record the GPU, resolution, profile, scene and frame time here when
  measured. Do not estimate.
