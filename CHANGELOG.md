# Changelog

## Unreleased (2026-10-27)

* Water simulation: frequency-dependent damping (short ripples fade, metre-scale rings travel on),
  a reflection-free absorbing edge (radial, velocity damping), adjustable propagation speed and
  damping, 32-bit field, larger Ultra area. A hop's ring stays visible to ~19.5 blocks (was
  ~13); edge echoes 0.3-1.3 % (were 10-26 %). New options: Wave Propagation, Ripple Damping,
  Boat Wake Strength, Player Splash Strength; Simulation Quality moved into Ripple Simulation.
* Fix: false splashes when a third-person camera dipped under the surface; water entry now uses
  the player's own feet and eye, not the camera.
* Clouds: new weather map - ~40 km weather systems (clear highs, overcast lows), a domain-warped
  cluster field (isolated groups to banks), convective instability - with per-column cloud type,
  base and top (stratus, stratocumulus, cumulus, cumulonimbus). No visible tiling (the old map
  repeated every 32.8 km); Coverage now tracks the share of sky (0.2 / 0.45 / 0.7 -> 0.22 /
  0.47 / 0.68). Two-scale shape noise; formations drift slower than the clouds, so they evolve.
* Clouds: sky light shaded by the cloud above (dark storm interiors), depth build-up of multiple
  scattering, light marches skipped for a negligible sun or moon, Cinematic cloud quality.
  Options: Cloud Density, Weather-Based Clouds, Storm Clouds; Cloud Quality, Resolution and
  Cloud Shadows moved into the Volumetric Clouds screen. Cloud programs are disabled with clouds.
* Fix: cirrus and cloud detail jumped when the wind offset wrapped / every hour.
* Clouds, second rebuild (in-game report: smooth grey masses over most of the sky, odd openings,
  little detail). Cause: the shape noise was 0.69 +- 0.14 and was thresholded against coverage
  0.4-0.85, so every cloud group became one solid mass. Now coverage, sky cover, type, size,
  thickness and density are separate controls; the shape noise (two cell scales, small humilis
  and large congestus) is equalised so coverage is the cloud fraction, and a per-type coverage
  profile makes flat bases and narrowing domes. Partly cloudy skies hold 308 distinct clouds per
  15 km view instead of 40, the largest connected mass 46 % of the cloud instead of 86 %; sky cover
  follows the setting (0.21 / 0.47 / 0.70 for 0.2 / 0.45 / 0.7). Each Minecraft day has its own
  weather (some clearer, some cloudier, eased in over ~90 s). Cumulonimbus anvils in thunder,
  40-80 m billows that fade with distance (no shimmering edges), thinner and sparser cirrus
  strands. Shadowed cloud sides had half the sky light they should (E / 4 pi instead of E / 2 pi
  per hemisphere) and looked muddy grey. Clouds are rebuilt at full resolution from the jittered
  low-resolution march instead of being accumulated and stretched at low resolution.
  tools/cloud_preview.py renders previews from the same model; debug views 25-27 show the cloud
  weather map, lighting and temporal history.
* Colour (in-game report: dull, grey, washed out). Causes: the default tone curve had a mid-tone
  contrast of 1.0 (film / ACES ~1.3-1.4) and lifted shadows (1/8 grey at 0.0174, about twice a
  film curve), with none of a film curve's mid-tone saturation; and the colour profiles' split
  toning was added in linear display space, which lifted black to a blue-grey (Cinematic: sRGB
  ~15 % blue) and swung the hue of shaded colours by 10-25 degrees. New default tone mapper,
  Belgium Filmic: contrast 1.28, middle grey kept at 0.18, deeper shadows, fuller highlights, hue
  kept exactly (largest channel), a film-like chroma gain in the mid-tones in Oklab, gamut
  compression by chroma instead of clipping, and colours go white only far beyond white (orange
  light stays coloured to 3 stops over middle grey). Vibrance now works in Oklab, gentler on
  foliage and highlights; split toning is a per-channel gain. Profiles are milder (the tone
  mapper supplies the contrast). The old curve stays available as Meridian Filmic (flat). Night
  exposure key 0.05 -> 0.065 so average night brightness is unchanged with the darker toe.
  Debug views 28-30: colour saturation, tone mapping only, bloom contribution.
* Fix: End light flicker. Causes and fixes (docs/REGRESSION_AUDIT.md): the vanilla End flash was
  added raw to every surface's ambient (shadowed End stone 4.8x brighter, in 20 Hz steps) - now
  eased per frame and a faint glow (1.10x); Iris culled distant shadow casters with its own
  light direction, so shadows popped while turning - distance culling only; End penumbrae were
  4x the sun's and shimmered - 0.008 rad; the End shadow grid re-anchored every 32 blocks - now
  fixed at the origin. Also: with Bloom off the exposure meter read unbuilt mip levels; parallax
  self-shadowing in the End used Iris's sun.
* Stars: subtle twinkling (atmospheric scintillation) per catalogue star, stronger towards the
  horizon (airmass^1.5), weaker for faint stars, log-normal so brightness is kept on average and
  no star drops out; the Milky Way and the End sky do not twinkle. Options: Star Twinkling,
  Twinkle Intensity, Twinkle Speed.

## Unreleased (2026-10-26)

* Repository tree replaced with the Meridian codebase (no Halcyon/Glimmer code).
* Fix: shadows swimming with the camera (TAA jitter in position reconstruction; cascade grid
  pivoted at the world origin).
* Fix: oversized sun glare, double-counted and flickering sun glints, clipped Moon highlands.
* Fix: display contrast crushing night shadows to black.
* Fix: clouds shearing into streaks over time, clouds moving against the wind.
* Settings: Quality, Sun & Moon and Stars screens; option consistency checker.
* Tools: glslang validation harness, shadow-grid and sun-glare reference tests.
* Fix: interactive-water wake race; rain ripples exact at any distance; no hourly wave pop.
* Fix: LabPBR predefined metals tinted by albedo; built-in metals use albedo as F0.
* Feat: water waves prefiltered by the pixel footprint, with the lost slope variance moved into
  the roughness (no distant sparkle).
* Docs: reference-pack research (docs/REVERSE_ENGINEERING_RESEARCH.md).
* Fix (first in-game feedback): water waves no longer speed up near the player or in river/ocean
  biomes; player and boat ripples work again; End portal starfield; no fade from black on load.
* End: no dust veil, smooth rotating accretion disk, structured rings with shadows, galaxies
  instead of the Overworld Milky Way.
* Settings: ten top-level categories with submenus.
* Fix (second in-game feedback): End and Nether exposure, block light, End disk light, emission
  adapted to exposure (no white lava or End stone); puddles about 8 % instead of 77 % of open
  ground, new Puddle Size option; subtler cloud lean; larger default moon; HDR debug views.
* Water simulation sleeps when idle and resets on dimension change.
* Feat: physically based rainbows (primary, secondary, Alexander's dark band), aurora (some
  nights), snow cover in snowy biomes, optional emissive ores, Distant Horizons chunk fade.
