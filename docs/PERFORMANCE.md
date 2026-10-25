# Performance

**No frame-time measurements exist yet** — the pack has not been run. The numbers below are
memory facts (exact) and cost expectations (estimates to be replaced by measurements).

## Memory (exact, from the buffer layouts)

Per-pixel targets at 2560×1440 (3.69 MP): seven RGBA16F + one RGBA16 + three RGBA8 targets =
76 B/px ≈ **280 MB** (≈ 630 MB at 3840×2160). SSGI adds colortex12/13 (2 × RGBA16F, full-size
allocation, half used) and colortex14 (R11F_G11F_B10F) = 20 B/px ≈ **74 MB** at 1440p. Whether Iris still allocates them with
SSGI off (programs disabled via `program.*.enabled`) has not been checked. The debug target (colortex11) is only allocated
when a debug view uses it.

| Resource | LOW | MEDIUM | HIGH | ULTRA | CINEMATIC |
|---|---|---|---|---|---|
| Shadow map (2 depth + 2 colour, 16 B/texel) | 1024² 17 MB | 2048² 67 MB | 3072² 151 MB | 4096² 268 MB | 8192² 1.07 GB |
| Water simulation (2 × N² × 8 B) | 256² 1 MB | 512² 4 MB | 512² 4 MB | 1024² 16 MB | 2048² 64 MB |
| Coloured-light volume (2 × 8 MB + 4 MB voxels) | off | 20 MB | 20 MB | 20 MB | 20 MB |
| Moon textures (albedo + normal atlas) | 2K: 25 MB | 4K: 101 MB | 4K: 101 MB | 4K: 101 MB | 8K: 252 MB |
| Cloud noise, LUTs, bloom, cloud shadow | ~25 MB | ~25 MB | ~25 MB | ~28 MB | ~28 MB |

## Expected cost drivers (to be measured)

1. Volumetric clouds (`deferred`): steps × light steps × resolution². Halving `CLOUD_RES`
   quarters the cost; the temporal pass is cheap.
2. Shadow pass: geometry-bound; `shadowDistance` matters more than resolution. With
   `shadow.culling = false` Iris renders everything inside the shadow-distance box.
3. Water composite with SSR (`composite`), opaque SSR (`OPAQUE_SSR`) — bandwidth-bound.
4. Volumetric light (`composite1`, half resolution, `VL_STEPS`).
5. Deferred lighting: PCF taps (`SHADOW_FILTER`), SSAO samples, contact shadows.
6. Water simulation: N² cells × up to 4 steps/frame, very cheap per cell (≈ 0.1 ms expected
   at 512² on a modern GPU); sleeps after 30 s without contact.
7. SSGI (`deferred2`/`deferred3`, half resolution): rays × steps depth reads per half-res
   pixel (MEDIUM 1×8, HIGH 1×12, ULTRA 2×16, CINEMATIC 4×24) plus a 9-tap filter. Off on LOW.
8. Hand light, block-light specular: a few ALU ops and 6 light-volume reads per pixel.
9. Black hole (End): LUT modes are a few texture lookups per sky pixel; Cinematic integrates
   480 RK4 steps per pixel and is intended for screenshots.

## Measurement protocol

Tools: in-game frame time (F3 graph / F3+2), NVIDIA Nsight Graphics or RenderDoc frame
capture for per-pass GPU time.

1. Fixed scene set (see `docs/TESTING.md`): plains noon, forest, ocean at sunset, storm,
   night with aurora, cave with torches, Nether wastes, End island. 2560×1440, 16-chunk render
   distance.
2. For each preset record median and 1 % low frame time over 30 s.
3. Per feature: toggle it alone from HIGH and record the delta (clouds, VL, opaque SSR,
   coloured light, SSAO, contact shadows, SSGI, water sim, TAA, bloom).
5. With Distant Horizons / Voxy: repeat at 32 and 64 LOD chunks, and with LOD Shadows on.
4. Record results in the table below and adjust presets from evidence, not guesses.

| Scene | LOW | MEDIUM | HIGH | ULTRA | CINEMATIC |
|---|---|---|---|---|---|
| (to be filled) | | | | | |

## Built-in cost controls

Reduced-resolution clouds and volumetric light with depth-aware reconstruction; adaptive cloud
step counts, empty-space skipping and early termination; fewer light-march steps; band-limited
waves (distant components are skipped, not just faded); simulation sleep; optional programs
(`program.*.enabled`) are not dispatched at all when their feature is off.

## Known inefficiencies (planned work)

* Reduced-resolution passes render into full-size targets (simple sampling, wasted VRAM).
* SSR is a linear march without a depth pyramid.
* The opaque-SSR branch re-decodes the G-buffer and re-applies wetness in composite.
