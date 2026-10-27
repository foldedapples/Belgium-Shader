# Changelog

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
