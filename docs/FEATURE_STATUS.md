# Feature status

**In code** means the feature exists as GLSL in this repository and compiles. **Reviewed** means
its implementation was read and corrected in the 2026-10-26 audit
([REGRESSION_AUDIT.md](REGRESSION_AUDIT.md)). Nothing is **verified in game** yet
([TESTING.md](TESTING.md)).

| Area | In code | Reviewed 2026-10-26 | Notes |
|---|---|---|---|
| Stable cascaded shadows, PCSS, coloured shadows | yes | yes | jitter and pivot fixes; reference-tested |
| HDR, auto exposure, bloom, tone mapping, 6 colour profiles | yes | yes | sun-disk limit; contrast fix |
| Sun, Moon (2K/4K/8K NASA), phases, eclipses, stars, Milky Way | yes | partly | glare and Moon peak fixed; star/Milky Way code not reviewed |
| Volumetric clouds (stratus … cumulonimbus, cirrus, shadows) | yes | yes | shear, wind direction, reprojection fixed |
| LabPBR 1.3, GGX BRDF, SSS, POM | yes | yes | checked against the spec; metal tint fixed |
| SSR with sky fallback | yes | partly | jitter and double-sun fixes |
| Water waves, simulation, refraction, caustics | yes | yes | wake race and hourly pop fixed; refraction and caustics not re-reviewed |
| Rain, wetness, puddles, ripples, lightning | yes | partly | ripple precision fixed; rain streaks and lightning not reviewed |
| Coloured block light (voxel flood fill), RSM bounce, AO | yes | jitter only | |
| The End: space, planets, black hole, disk light | yes | exposure / horizon only | no fault found |
| Nether smoke, heat haze, ash | yes | no | |
| Distant Horizons | yes | jitter only | compiles; untested in game |
| Voxy | yes | no | compiles; no public interface docs to check against |
| Settings: 23 screens, 5 profiles, 112 options | yes | yes | `check_options.py`: no dead controls |
| Held lantern | hand light only | no | a swinging 3D lantern needs a resource pack plus an animation mod; GLSL alone cannot animate the held model |
| Performance measurements | — | — | none taken |
