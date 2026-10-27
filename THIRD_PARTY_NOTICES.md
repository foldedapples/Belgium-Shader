# Third-party notices

Meridian's code is MIT licensed (LICENSE). The items below are third-party data or algorithms
that are part of the distributed pack, with their required credits and terms.

## NASA Scientific Visualization Studio

* **CGI Moon Kit** (SVS 4720, https://svs.gsfc.nasa.gov/4720) — LRO LROC colour and LOLA
  elevation, used for `textures/moon/*`.
  Credit: **NASA's Scientific Visualization Studio**. Visualizer Ernie Wright (USRA); scientist
  Noah Petro (NASA/GSFC).
* **Deep Star Maps 2020** (SVS 4851, https://svs.gsfc.nasa.gov/4851) — used for
  `textures/stars/*`.
  Credit: **NASA/Goddard Space Flight Center Scientific Visualization Studio**.

SVS content is in the public domain unless otherwise noted (https://svs.gsfc.nasa.gov/help/).
Use of NASA imagery does not imply endorsement by NASA. This pack uses no NASA logos or insignia.

## ESA Gaia (contained in the NASA Milky Way map)

`textures/stars/milkyway.png` is derived from NASA's `milkyway_2020_4k.exr`, which is built from
**Gaia DR2** data. Credit: **ESA/Gaia/DPAC**. ESA distributes Gaia data under **CC BY-NC 3.0 IGO**
(https://www.cosmos.esa.int/web/gaia-users/license). Taking the conservative reading, this one
file is provided for **non-commercial use with attribution**. If you distribute the pack
commercially, remove `textures/stars/milkyway.png` and its `customTexture.milkyWay` line and turn
**Milky Way** off. (Not legal advice.)

## Yale Bright Star Catalogue

Star positions, magnitudes and colours for stars brighter than V = 6.5 come from the *Bright Star
Catalogue, 5th Revised Ed.* (Hoffleit, D. & Warren, W.H. Jr., 1991), obtained from the CDS,
Strasbourg (catalogue V/50). Please cite Hoffleit & Warren (1991) and acknowledge the CDS.

## Khronos PBR Neutral tone mapper

The *Khronos PBR Neutral* option (`lib/post/tonemap.glsl`, `khronosPbrNeutral`) implements the
algorithm published at https://github.com/KhronosGroup/ToneMapping.

```
Copyright 2024 The Khronos Group Inc.
SPDX-License-Identifier: Apache-2.0

Licensed under the Apache License, Version 2.0 (the "License"); you may not use this file except
in compliance with the License. You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software distributed under the License
is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or
implied. See the License for the specific language governing permissions and limitations under
the License.
```

Modifications: transcribed to this pack's GLSL conventions (function name, saturation of the
result in `tonemap()`).

## Oklab

`lib/post/oklab.glsl` uses the Oklab colour space by Björn Ottosson
(https://bottosson.github.io/posts/oklab/), whose author states: "The code is available in public
domain, feel free to use it any way you please. It is also available under an MIT license". Only
the published conversion matrices are used; the tone mapper, gamut compression and vibrance built
on it are this pack's own.
