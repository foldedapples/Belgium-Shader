"""Import the extracted Halcyon feature code into the Belgium Shaders engine.

Copies Halcyon modules byte-for-byte into shaders/lib/halcyon/ (same sub-paths as in Halcyon's
shaders/lib/), copies Halcyon's textures into shaders/textures/halcyon/, and generates the two
namespace headers that make the copies coexist with Belgium's own modules:

  shaders/lib/halcyon/hc_begin.glsl  #define <name> hc_<name>   for every global name defined by
                                     both a Halcyon module and Belgium (functions, constants,
                                     structs, internal macros), so neither side redefines the other
  shaders/lib/halcyon/hc_end.glsl    the matching #undef lines

Programs include Halcyon modules only between the two headers (lib/halcyon/halcyon.glsl does
this); the adapter (lib/halcyon/adapter.glsl) supplies what the modules used to get from Glimmer.
Halcyon's own option names are not renamed: where Belgium used the same option name with a
different meaning, Belgium's option was renamed (BE_*), see docs/HALCYON_INTEGRATION.md.

Usage: python -P tools/import_halcyon.py <halcyon_extract_dir>
Re-run after changing the module list below or the Halcyon sources.
"""
import re
import shutil
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from halcyon_deps import definitions, strip_comments  # noqa: E402

ROOT = Path(__file__).resolve().parent.parent
SHADERS = ROOT / "shaders"
DEST = SHADERS / "lib" / "halcyon"

# Halcyon modules imported so far (paths relative to Halcyon's shaders/lib/).
MODULES = [
    "atmosphere/sky/stars.glsl",
    "atmosphere/sky/celestial.glsl",
    "atmosphere/sky/aurora.glsl",
    # atmosphere/sky/cirrus.glsl: replaced by Belgium's cirrus + 22 deg halo (docs/HALCYON_INTEGRATION.md)
    "atmosphere/sky/rainbow.glsl",
    "water/rainRipples.glsl",
    "atmosphere/volumetricClouds.glsl",
    "water/waterSim.glsl",
    "water/caustics.glsl",
    "water/underwaterShafts.glsl",
]
# Halcyon programs (paths relative to Halcyon's shaders/), copied to shaders/program/halcyon/.
# They are whole translation units built from Halcyon code only, so they are not wrapped in the
# hc_ region; Glimmer-path includes they use are served by shims (lib/common.glsl, ...).
PROGRAMS = [
    "program/waterSim.glsl",
]
# Modules assembled verbatim from line ranges of Halcyon's integration notes (Halcyon's own
# code that lived inside edited Glimmer files). (target, [(note, first line, last line), ...]).
ASSEMBLED = [
    ("water/halcyon_waves.glsl", [
        ("integration/shaders/lib/water/waveNormals.glsl.md", 10, 15),    # waveTime()
        ("integration/shaders/lib/water/waveNormals.glsl.md", 85, 174),   # swells, swellSlope()
    ]),
    ("water/halcyon_waterfog.glsl", [
        ("integration/shaders/lib/water/waterFog.glsl.md", 41, 58),       # refraction helpers
    ]),
]
TEXTURES = [
    "moon_2k.png", "moon_2k.png.mcmeta", "moon_4k.png", "moon_4k.png.mcmeta",
    "milkyway_4k.png", "milkyway_4k.png.mcmeta", "milkyway_8k.png", "milkyway_8k.png.mcmeta",
    "starCatalog.bin", "CREDITS-night-sky.md", "cloudNoise.bin",
]
# Names the adapter deliberately shares with Belgium (same meaning and signature).
SHARED = {"luminance"}
# Glimmer-interface names whose Belgium namesake has a different meaning: inside the region they
# map to the adapter's hc_ versions (lib/halcyon/adapter_core.glsl).
ADAPTER_RENAMES = {
    "henyeyGreenstein",   # Halcyon: (g, cosTheta); Belgium: (cosTheta, g)
    "surfaceWetness",     # Halcyon: a custom uniform; Belgium: a function
}
# Option macros are resolved in settings.glsl, never renamed here.
OPTION_RE = re.compile(r"^\s*(?://\s*)?#define\s+([A-Z_][A-Z0-9_]*)\b", re.M)


def belgium_kinds():
    kinds = {}
    for p in SHADERS.rglob("*.glsl"):
        if DEST in p.parents:
            continue
        for n, k in definitions(strip_comments(p.read_text(errors="replace"))).items():
            kinds.setdefault(n, k)
    return kinds


def main():
    src = Path(sys.argv[1])
    options = set(OPTION_RE.findall((SHADERS / "lib/core/settings.glsl").read_text()))
    be = belgium_kinds()
    collisions = set()
    macro_collisions = set()
    DEST.mkdir(parents=True, exist_ok=True)
    for rel in MODULES:
        s = src / "shaders" / "lib" / rel
        d = DEST / rel
        d.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(s, d)
        code = strip_comments(s.read_text(errors="replace"))
        for name, kind in definitions(code).items():
            if name in be and name not in SHARED and name not in options:
                # include guards are file-unique; skip them
                if kind == "macro" and name.endswith("_GLSL"):
                    continue
                if kind == "macro":
                    # Halcyon #defines it, so it cannot be pre-renamed; undefine it after the region.
                    if be[name] == "macro":
                        raise SystemExit(f"{name}: a macro in both Halcyon and Belgium - resolve by hand")
                    macro_collisions.add(name)
                else:
                    collisions.add(name)
    for target, parts in ASSEMBLED:
        guard = "HALCYON_" + target.replace("/", "_").replace(".", "_").upper()
        body = [f"// GENERATED by tools/import_halcyon.py from Halcyon's integration notes - do not edit.",
                f"#ifndef {guard}", f"#define {guard}"]
        for note, a, b in parts:
            lines = (src / note).read_text(encoding="utf-8").splitlines()[a - 1:b]
            body.append(f"// --- {note} lines {a}-{b}")
            body += lines
        body.append(f"#endif")
        text = "\n".join(body) + "\n"
        d = DEST / target
        d.parent.mkdir(parents=True, exist_ok=True)
        d.write_text(text, encoding="utf-8", newline="\n")
        for name, kind in definitions(strip_comments(text)).items():
            if name in be and name not in SHARED and name not in options and not (kind == "macro" and name.endswith("_GLSL")):
                if kind == "macro":
                    macro_collisions.add(name)
                else:
                    collisions.add(name)
    for rel in PROGRAMS:
        d = SHADERS / "program" / "halcyon" / Path(rel).name
        d.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(src / "shaders" / rel, d)
    # Iris binds samplers and uniforms by name: they must never be renamed.
    bad = sorted(n for n in collisions if be.get(n) == "uniform")
    if bad:
        raise SystemExit(f"uniform names defined by both Halcyon and Belgium (resolve by hand): {bad}")
    tdir = SHADERS / "textures" / "halcyon"
    tdir.mkdir(parents=True, exist_ok=True)
    for t in TEXTURES:
        shutil.copyfile(src / "shaders" / "textures" / t, tdir / t)
    names = sorted(collisions | ADAPTER_RENAMES)
    head = ("// GENERATED by tools/import_halcyon.py - do not edit.\n"
            "// Names defined by both Halcyon modules and Belgium Shaders: Halcyon's copies get an hc_\n"
            "// prefix between hc_begin.glsl and hc_end.glsl.\n")
    (DEST / "hc_begin.glsl").write_text(head + "".join(f"#define {n} hc_{n}\n" for n in names), newline="\n")
    undefs = sorted(collisions | ADAPTER_RENAMES | macro_collisions)
    (DEST / "hc_end.glsl").write_text(head + "".join(f"#undef {n}\n" for n in undefs), newline="\n")
    print(f"{len(MODULES)} modules, {len(TEXTURES)} textures; renamed: {' '.join(names)}; "
          f"undefined after the region: {' '.join(sorted(macro_collisions))}")


if __name__ == "__main__":
    main()
