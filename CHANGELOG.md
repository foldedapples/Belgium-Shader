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
