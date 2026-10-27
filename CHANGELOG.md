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
