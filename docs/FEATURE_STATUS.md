# Feature status

**In code** means the feature exists as GLSL in this repository and compiles. **Reviewed** means
its implementation was read and corrected in the 2026-10-26 audit
([REGRESSION_AUDIT.md](REGRESSION_AUDIT.md)). Nothing is **verified in game** yet
([TESTING.md](TESTING.md)).

| Area | In code | Reviewed 2026-10-26 | Notes |
|---|---|---|---|
| Stable cascaded shadows, PCSS, coloured shadows | yes | yes | jitter and pivot fixes; reference-tested |
| HDR, auto exposure, bloom, tone mapping, 6 colour profiles | yes | yes | sun-disk limit; contrast fix; new default tone mapper (Belgium Filmic), Oklab vibrance, split-tone black lift fixed 2026-10-27 (model-tested, awaiting in-game check) |
| Sun, Moon (2K/4K/8K NASA), phases, eclipses, stars, Milky Way | yes | partly | glare and Moon peak fixed; star twinkling added 2026-10-27 (model-tested, awaiting in-game check) |
| Volumetric clouds (stratus … cumulonimbus, anvils, cirrus, shadows) | yes | yes | shear, wind direction, reprojection fixed; second rebuild 2026-10-27: separate coverage / density / type, equalised cellular shape, full-resolution reconstruction, ambient fix (model-tested with tools/cloud_preview.py, awaiting in-game check of look and cost) |
| LabPBR 1.3, GGX BRDF, SSS, POM | yes | yes | checked against the spec; metal tint fixed |
| SSR with sky fallback | yes | partly | jitter and double-sun fixes |
| Water waves, simulation, refraction, caustics | yes | yes | in-game: speed bug and missing ripples fixed 2026-10-27 (awaiting re-check); ripple propagation, absorbing edge and third-person splash fix 2026-10-27 (model-tested); refraction not re-reviewed |
| Rain, wetness, puddles, ripples, lightning | yes | partly | ripple precision fixed; rain streaks and lightning not reviewed |
| Coloured block light (voxel flood fill), RSM bounce, AO | yes | jitter only | |
| The End: space, planets, black hole, disk light | yes | yes | in-game: veil, disk banding, rings, portal fixed 2026-10-27; galaxies replace the Milky Way; planets still procedural (NASA maps not yet integrated); light flicker: End flash in terrain ambient, view-dependent shadow culling, penumbra noise, anchor re-snap fixed 2026-10-27 (awaiting in-game check) |
| Nether smoke, heat haze, ash | yes | no | |
| Distant Horizons | yes | jitter only | compiles; untested in game |
| Voxy | yes | no | compiles; no public interface docs to check against |
| Settings: 10 categories (27 screens), 5 profiles, 132 options | yes | yes | `check_options.py`: no dead controls; debug views 25-30 (clouds, colour) |
| Held lantern | hand light only | no | a swinging 3D lantern needs a resource pack plus an animation mod; GLSL alone cannot animate the held model |
| Startup exposure | yes | yes | no fade from black after (re)load (2026-10-27, awaiting re-check) |
| Shadow flicker (reported in game) | — | open | needs a repro: debug view 9 with time frozen; see TESTING.md |
| Performance measurements | — | — | none taken |
