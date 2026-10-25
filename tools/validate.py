#!/usr/bin/env python3
"""Offline validator for the Belgium Shaders pack.

What it does
  1. Expands Iris-style ``#include "/abs"`` and relative includes for every program wrapper in
     ``shaders/world*/``.
  2. Applies option overrides (defaults, every ``profile.*`` in shaders.properties, and a
     Distant Horizons variant) by rewriting ``#define`` lines exactly the way Iris toggles them.
  3. Injects the standard macros Iris defines (MC_VERSION, IRIS_VERSION, ...).
  4. Compiles each expanded source with Khronos glslang and reports errors.
  5. Lints the option menu: every option must be reachable from a screen, have a language
     string, and every profile entry must name a real option.

It cannot prove a program links or renders correctly in Minecraft; it catches compile errors,
broken includes and dead/unknown settings before the game ever sees them.

Usage: python tools/validate.py [--glslang PATH] [--profile NAME] [--quick] [-j N]
"""
from __future__ import annotations

import argparse
import concurrent.futures as cf
import os
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SHADERS = ROOT / "shaders"
SETTINGS = SHADERS / "lib" / "core" / "settings.glsl"
PROPS = SHADERS / "shaders.properties"
LANG = SHADERS / "lang" / "en_US.lang"

STAGES = {".vsh": "vert", ".fsh": "frag", ".gsh": "geom", ".csh": "comp"}
COMPUTE_RE = re.compile(r"\.csh$")

BASE_MACROS = {
    "MC_VERSION": "12111",
    "IRIS_VERSION": "11005",
    "IS_IRIS": "",
    "MC_GL_VERSION": "460",
    "MC_GLSL_VERSION": "460",
    "MC_NORMAL_MAP": "",
    "MC_SPECULAR_MAP": "",
    "MC_RENDER_QUALITY": "1.0",
    "MC_SHADOW_QUALITY": "1.0",
    "MC_HAND_DEPTH": "0.125",
    "MC_MIPMAP_LEVEL": "4",
    "MAX_COLOR_BUFFERS": "16",
    # Iris defines IRIS_FEATURE_<flag> for usable features (current Iris, OpenGL 4.6 GPU).
    "IRIS_FEATURE_SSBO": "", "IRIS_FEATURE_COMPUTE_SHADERS": "", "IRIS_FEATURE_CUSTOM_IMAGES": "",
    "IRIS_FEATURE_SEPARATE_HARDWARE_SAMPLERS": "", "IRIS_FEATURE_BLOCK_EMISSION_ATTRIBUTE": "",
    "MC_RENDER_STAGE_NONE": "0",
    "MC_RENDER_STAGE_TERRAIN_SOLID": "8",
    "MC_RENDER_STAGE_TERRAIN_CUTOUT_MIPPED": "9",
    "MC_RENDER_STAGE_TERRAIN_CUTOUT": "10",
    "MC_RENDER_STAGE_ENTITIES": "11",
    "MC_RENDER_STAGE_TERRAIN_TRANSLUCENT": "17",
}
DH_MACROS = {"DISTANT_HORIZONS": "", "DH_BLOCK_WATER": "12", "DH_BLOCK_LEAVES": "1",
             "DH_BLOCK_LAVA": "7", "DH_BLOCK_ILLUMINATED": "15", "DH_BLOCK_SNOW": "9",
             "DH_BLOCK_SAND": "10", "DH_BLOCK_METAL": "4", "DH_BLOCK_GRASS": "13"}

DEFINE_RE = re.compile(r"^(\s*)(//\s*)?#define\s+([A-Za-z_][A-Za-z0-9_]*)(?:\s+([^\s/]+))?(.*)$")
CONST_RE = re.compile(r"^(\s*)const\s+(int|float|bool)\s+([A-Za-z_][A-Za-z0-9_]*)\s*=\s*([^;]+);(.*)$")
INCLUDE_RE = re.compile(r'^\s*#include\s+"([^"]+)"')


# --------------------------------------------------------------------------------------------
# Options
# --------------------------------------------------------------------------------------------
class Option:
    def __init__(self, name, kind, default, choices, line_no):
        self.name, self.kind, self.default, self.choices, self.line_no = name, kind, default, choices, line_no

    def __repr__(self):
        return f"Option({self.name}={self.default})"


def parse_options(settings_text: str) -> dict[str, Option]:
    """An Iris option is a #define with a [choices] comment, or a bare (possibly commented)
    #define toggle followed by a comment, or a const directive with [choices]."""
    opts: dict[str, Option] = {}
    for i, line in enumerate(settings_text.splitlines()):
        m = DEFINE_RE.match(line)
        if m:
            _, commented, name, value, rest = m.groups()
            if name.startswith("SETTINGS_") or name.startswith("_"):
                continue
            choices = re.search(r"\[([^\]]*)\]", rest or "")
            if value is not None and choices:
                opts[name] = Option(name, "value", value, choices.group(1).split(), i)
            elif value is None and not name.endswith("_GLSL"):
                # Iris lists any bare #define (comment or not) that a plain #ifdef references.
                opts[name] = Option(name, "toggle", commented is None, None, i)
            continue
        m = CONST_RE.match(line)
        if m:
            _, typ, name, value, rest = m.groups()
            choices = re.search(r"\[([^\]]*)\]", rest or "")
            if choices:
                opts[name] = Option(name, "const", value.strip(), choices.group(1).split(), i)
    return opts


def apply_overrides(settings_text: str, overrides: dict[str, object]) -> str:
    out = []
    for line in settings_text.splitlines():
        m = DEFINE_RE.match(line)
        if m and m.group(3) in overrides:
            indent, commented, name, value, rest = m.groups()
            ov = overrides[name]
            if value is None:  # toggle
                line = f"{indent}{'' if ov else '//'}#define {name}{rest}"
            else:
                line = f"{indent}#define {name} {ov}{rest}"
        else:
            m = CONST_RE.match(line)
            if m and m.group(3) in overrides:
                indent, typ, name, value, rest = m.groups()
                line = f"{indent}const {typ} {name} = {overrides[name]};{rest}"
        out.append(line)
    return "\n".join(out) + "\n"


def parse_properties(text: str) -> tuple[dict[str, dict[str, object]], dict[str, list[str]], list[str]]:
    """Returns (profiles, screens, sliders). Iris pre-processes shaders.properties with the C
    preprocessor; we evaluate only the directives we use (none affect profiles/screens)."""
    joined = re.sub(r"\\\s*\n", " ", text)
    profiles, screens, sliders = {}, {}, []
    for raw in joined.splitlines():
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        key, _, value = line.partition("=")
        key, value = key.strip(), value.strip()
        if key.startswith("profile."):
            ov: dict[str, object] = {}
            for tok in value.split():
                if tok.startswith("profile."):
                    ov.update(profiles.get(tok[len("profile."):], {}))
                elif "=" in tok or ":" in tok:
                    k, _, v = tok.replace(":", "=").partition("=")
                    ov[k] = v
                elif tok.startswith("!"):
                    ov[tok[1:]] = False
                else:
                    ov[tok] = True
            profiles[key[len("profile."):]] = ov
        elif key == "screen" or key.startswith("screen.") and not key.endswith(".columns"):
            screens[key] = value.split()
        elif key == "sliders":
            sliders = value.split()
    return profiles, screens, sliders


# --------------------------------------------------------------------------------------------
# Include expansion
# --------------------------------------------------------------------------------------------
class ExpandError(Exception):
    pass


def expand(path: Path, settings_override: str, seen_stack: list[Path], out: list[str], line_map: list[tuple[Path, int]]):
    if path in seen_stack:
        raise ExpandError(f"include cycle: {' -> '.join(str(p) for p in seen_stack + [path])}")
    if not path.exists():
        raise ExpandError(f"missing include {path.relative_to(SHADERS) if SHADERS in path.parents else path}")
    text = settings_override if path == SETTINGS else path.read_text(encoding="utf-8")
    for n, line in enumerate(text.splitlines(), 1):
        m = INCLUDE_RE.match(line)
        if m:
            inc = m.group(1)
            target = (SHADERS / inc.lstrip("/")) if inc.startswith("/") else (path.parent / inc)
            expand(target.resolve(), settings_override, seen_stack + [path], out, line_map)
        else:
            out.append(line)
            line_map.append((path, n))


def build_source(wrapper: Path, settings_text: str, macros: dict[str, str]) -> tuple[str, list[tuple[Path, int]]]:
    out: list[str] = []
    lmap: list[tuple[Path, int]] = []
    expand(wrapper.resolve(), settings_text, [], out, lmap)
    if not out or not out[0].startswith("#version"):
        raise ExpandError("first line must be #version")
    inject = [f"#define {k} {v}".rstrip() for k, v in macros.items()]
    # Iris injects this global into Distant Horizons vertex programs.
    if wrapper.name.startswith("dh_") and wrapper.suffix == ".vsh" and "DISTANT_HORIZONS" in macros:
        inject.append("int dhMaterialId;")
    src = [out[0]] + inject + out[1:]
    lmap = [lmap[0]] + [(wrapper, 0)] * len(inject) + lmap[1:]
    return "\n".join(src) + "\n", lmap


# --------------------------------------------------------------------------------------------
# Compilation
# --------------------------------------------------------------------------------------------
ERR_RE = re.compile(r"^(ERROR|WARNING): (?:0|[^:]*):(\d+): (.*)$")


def compile_one(glslang: str, wrapper: Path, variant: str, settings_text: str, macros: dict[str, str], tmpdir: Path):
    stage = STAGES[wrapper.suffix]
    try:
        src, lmap = build_source(wrapper, settings_text, macros)
    except ExpandError as e:
        return [(wrapper, variant, "ERROR", f"{e}")]
    rel = (wrapper.relative_to(SHADERS).as_posix() if SHADERS in wrapper.parents else "voxy/" + wrapper.name).replace("/", "__")
    tmp = tmpdir / f"{variant}__{rel}.{stage}"
    tmp.write_text(src, encoding="utf-8")
    proc = subprocess.run([glslang, "-S", stage, str(tmp)], capture_output=True, text=True)
    problems = []
    for line in (proc.stdout + proc.stderr).splitlines():
        m = ERR_RE.match(line.strip())
        if not m:
            continue
        sev, ln, msg = m.group(1), int(m.group(2)), m.group(3)
        where = ""
        if 0 < ln <= len(lmap):
            p, n = lmap[ln - 1]
            where = f"{p.relative_to(SHADERS).as_posix() if SHADERS in p.parents else p.name}:{n}"
        problems.append((wrapper, variant, sev, f"{where}: {msg}"))
    if proc.returncode != 0 and not any(p[2] == "ERROR" for p in problems):
        problems.append((wrapper, variant, "ERROR", (proc.stdout + proc.stderr).strip()[-400:]))
    if stage == "comp" and "local_size_x" not in src:
        problems.append((wrapper, variant, "ERROR", "compute shader without local_size"))
    if stage == "comp" and "workGroups" not in src:
        problems.append((wrapper, variant, "ERROR", "compute shader without workGroups/workGroupsRender"))
    return problems


def find_glslang(cli: str | None) -> str:
    cands = [cli, os.environ.get("GLSLANG"), shutil.which("glslang"), shutil.which("glslangValidator")]
    for c in cands:
        if c and Path(c).exists():
            return c
        if c and shutil.which(c):
            return shutil.which(c)
    sys.exit("glslang not found: pass --glslang or set GLSLANG")


# --------------------------------------------------------------------------------------------
# Menu lint
# --------------------------------------------------------------------------------------------
IRIS_BUILTIN_OPTIONS = {"shadowMapResolution", "shadowDistance", "sunPathRotation", "entityShadowDistanceMul"}


# Functions Iris injects into transformed programs (Sodium terrain/shadow, DH, clouds); a pack
# function of the same name is a redefinition error in game. From Iris' pipeline/transform.
IRIS_INJECTED_FUNCTIONS = {
    "signNotZero", "decodeOct24", "decode_diamond", "decode_diamond_tangent_with_sign",
    "onb_from_normal", "_vert_init", "_get_texcoord", "_get_texcoord_bias",
    "_deinterleave_u20x3", "dh_blockFaceUv", "dh_hasTexture", "dh_sampleTexture", "iris_cloudsMain",
}


def lint_iris_source_rules(opts: dict[str, Option]) -> list[str]:
    """Rules Iris applies to the raw pack text that glslang cannot see (all found in game)."""
    problems, ifdef_refs = [], set()
    sources = [p for p in sorted(SHADERS.rglob("*")) if p.is_file() and p.suffix in {".glsl", ".vsh", ".fsh", ".csh", ".gsh"}]
    for p in sources:
        rel = p.relative_to(SHADERS).as_posix()
        for n, line in enumerate(p.read_bytes().decode("ascii", "replace").splitlines(), 1):
            m = re.fullmatch(r'\s*#(?:ifdef|ifndef)\s+(\w+)\s*', line)
            if m:
                ifdef_refs.add(m.group(1))
            # workGroups / workGroupsRender are read with Integer/Float.parseInt: literals only.
            m = re.search(r'\bconst\s+(?:ivec3|vec2)\s+(workGroups(?:Render)?)\s*=\s*\w+\(([^)]*)\)', line)
            if m and not all(re.fullmatch(r'\s*\d+(\.\d*)?\s*', a) for a in m.group(2).split(",")):
                problems.append(f"{rel}:{n}: {m.group(1)} must use literal numbers (Iris does not evaluate expressions)")
            m = re.match(r'\s*\w+\s+(\w+)\s*\([^)]*\)\s*(\{|$)', line)
            if m and (m.group(1) in IRIS_INJECTED_FUNCTIONS or m.group(1).startswith("iris_")):
                problems.append(f"{rel}:{n}: function {m.group(1)} clashes with a function Iris injects")
    # A boolean #define is only a menu option if some line is exactly `#ifdef NAME`/`#ifndef NAME`.
    for name, o in opts.items():
        if o.kind == "toggle" and name not in ifdef_refs:
            problems.append(f"option {name}: no plain #ifdef/#ifndef line references it, so Iris will not list it")
    return problems


def lint_menu(opts: dict[str, Option], profiles, screens, sliders) -> list[str]:
    problems = []
    reachable = set()
    for items in screens.values():
        for it in items:
            if it.startswith("[") or it in ("<empty>", "<profile>", "*"):
                continue
            reachable.add(it)
    for name in opts:
        if name not in reachable:
            problems.append(f"option {name} is not reachable from any screen")
    for it in reachable:
        if it not in opts and it not in IRIS_BUILTIN_OPTIONS:
            problems.append(f"screen references unknown option {it}")
    for s in sliders:
        if s not in opts:
            problems.append(f"slider references unknown option {s}")
    for pname, ov in profiles.items():
        for k in ov:
            if k not in opts:
                problems.append(f"profile {pname} sets unknown option {k}")
            elif opts[k].choices and str(ov[k]) not in opts[k].choices and opts[k].kind != "toggle":
                problems.append(f"profile {pname}: {k}={ov[k]} is not one of {opts[k].choices}")
    if LANG.exists():
        lang = LANG.read_text(encoding="utf-8")
        for name in opts:
            if f"option.{name}=" not in lang:
                problems.append(f"option {name} has no language string")
        for sc in screens:
            if sc != "screen" and f"{sc}=" not in lang:
                problems.append(f"{sc} has no language string")
    for name, o in opts.items():
        if o.choices and o.kind != "toggle" and o.default not in o.choices:
            problems.append(f"option {name} default {o.default} not in its choices {o.choices}")
    return problems


VOXY_PRELUDE = '''#version 460 core
#define VOXY 3
struct VoxyFragmentParameters { vec4 sampledColour; vec2 tile; vec2 uv; uint face; uint modelId; vec2 lightMap; vec4 tinting; uint customId; };
uniform float viewWidth;
uniform float viewHeight;
uniform sampler2D depthtex0;
'''


def make_voxy_harnesses(folder: Path) -> list[Path]:
    """Voxy patches are GLSL bodies without #version or main(); wrap them the way Voxy does
    (prelude with the parameter struct and the uniforms listed in voxy.json) so they compile."""
    out = []
    folder.mkdir(parents=True, exist_ok=True)
    for name in ("voxy_opaque", "voxy_translucent"):
        if not (SHADERS / "program" / f"{name}.glsl").exists():
            continue
        f = folder / f"{name}.fsh"
        f.write_text(VOXY_PRELUDE + f'#define DIM_OVERWORLD\n#include "/program/{name}.glsl"\n'
                     "void main() { voxy_emitFragment(VoxyFragmentParameters(vec4(1.0), vec2(0.0), vec2(0.0), 2u, 0u, vec2(1.0), vec4(1.0), 0u)); }\n",
                     encoding="utf-8")
        out.append(f)
    return out


PP_COND_RE = re.compile(r"^\s*#\s*(?:if|elif)\b(.*)$")
IDENT_RE = re.compile(r"[A-Za-z_][A-Za-z0-9_]*")


def structural_options(opts):
    """Value options referenced by #if/#elif lines anywhere in the pack."""
    used = set()
    for f in SHADERS.rglob("*.glsl"):
        for line in f.read_text(encoding="utf-8").splitlines():
            m = PP_COND_RE.match(line)
            if m:
                used.update(IDENT_RE.findall(m.group(1)))
    return {n for n, o in opts.items() if o.kind in ("value", "const") and n in used}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--glslang")
    ap.add_argument("--profile", help="only this profile (default: all)")
    ap.add_argument("--quick", action="store_true", help="default settings only, no DH variant")
    ap.add_argument("-j", type=int, default=os.cpu_count() or 4)
    args = ap.parse_args()

    glslang = find_glslang(args.glslang)
    settings_text = SETTINGS.read_text(encoding="utf-8")
    opts = parse_options(settings_text)
    profiles, screens, sliders = parse_properties(PROPS.read_text(encoding="utf-8")) if PROPS.exists() else ({}, {}, [])

    menu_problems = lint_menu(opts, profiles, screens, sliders)
    for p in sorted(SHADERS.rglob("*")):
        if p.is_file() and p.suffix in {".glsl", ".properties", ".lang", ".vsh", ".fsh", ".csh", ".json"}:
            raw = p.read_bytes()
            if p.suffix == ".lang":
                # Minecraft reads .lang as UTF-8 (Halcyon's strings use section-sign colour codes).
                try:
                    raw.decode("utf-8")
                except UnicodeDecodeError:
                    menu_problems.append(f"{p.relative_to(SHADERS).as_posix()} is not valid UTF-8")
            elif any(b > 127 for b in raw):
                menu_problems.append(f"{p.relative_to(SHADERS).as_posix()} contains non-ASCII bytes")
            # Iris takes everything after `#include` as the path (quotes stripped), so any
            # trailing text, even a comment, breaks the include in game.
            for n, line in enumerate(p.read_bytes().decode("ascii", "replace").splitlines(), 1):
                if re.match(r'^\s*#\s*include\b', line) and not re.fullmatch(r'\s*#\s*include\s+"[^"]+"\s*', line):
                    menu_problems.append(f"{p.relative_to(SHADERS).as_posix()}:{n}: text after #include path (Iris rejects it)")
    menu_problems += lint_iris_source_rules(opts)

    variants: list[tuple[str, dict, dict]] = [("default", {}, BASE_MACROS)]
    if not args.quick:
        variants.append(("dh", {}, {**BASE_MACROS, **DH_MACROS}))
        variants.append(("voxy", {}, {**BASE_MACROS, "VOXY": "3"}))
        variants.append(("old_iris", {}, {**BASE_MACROS, "IRIS_VERSION": "10802"}))
        # Iris 1.6.14 (Minecraft 1.20.2): no split camera position, no block emission attribute.
        iris16 = {k: v for k, v in BASE_MACROS.items() if k != "IRIS_FEATURE_BLOCK_EMISSION_ATTRIBUTE"}
        variants.append(("iris_1_6", {}, {**iris16, "IRIS_VERSION": "10614", "MC_VERSION": "12002"}))
        for mc, iv in (("12001", "10706"), ("12006", "10702"), ("12105", "10811"), ("12110", "10907"), ("260300", "11107")):
            variants.append((f"mc_{mc}", {}, {**BASE_MACROS, "MC_VERSION": mc, "IRIS_VERSION": iv}))
        for pname, ov in profiles.items():
            if args.profile and pname != args.profile:
                continue
            variants.append((f"profile_{pname}", ov, BASE_MACROS))
        # every toggle flipped against default, one at a time, catches dead #ifdef branches
        for name, o in opts.items():
            if o.kind == "toggle":
                variants.append((f"flip_{name}", {name: not o.default}, BASE_MACROS))
        # every choice of options that select code in preprocessor conditionals
        for name in sorted(structural_options(opts)):
            o = opts[name]
            for choice in o.choices:
                if choice != o.default:
                    variants.append((f"{name}={choice}", {name: choice}, BASE_MACROS))

    wrappers = sorted(p for p in SHADERS.glob("world*/*") if p.suffix in STAGES)
    wrappers += make_voxy_harnesses(Path(tempfile.gettempdir()) / "belgium_voxy_harness")
    if not wrappers:
        sys.exit("no program wrappers found (run tools/gen_wrappers.py)")

    problems = []
    with tempfile.TemporaryDirectory() as td, cf.ThreadPoolExecutor(args.j) as ex:
        futs = []
        for vname, ov, macros in variants:
            st = apply_overrides(settings_text, ov)
            targets = wrappers if vname in ("default", "dh", "voxy", "iris_1_6") else [w for w in wrappers if w.parent.name in ("world0", "belgium_voxy_harness")]
            for w in targets:
                futs.append(ex.submit(compile_one, glslang, w, vname, st, macros, Path(td)))
        for f in cf.as_completed(futs):
            problems.extend(f.result())

    errors = [p for p in problems if p[2] == "ERROR"]
    warnings = [p for p in problems if p[2] == "WARNING"]
    seen = set()
    for w, v, sev, msg in sorted(problems, key=lambda p: (p[2], str(p[0]), p[1])):
        key = (sev, msg)
        if key in seen:
            continue
        seen.add(key)
        name = w.relative_to(SHADERS).as_posix() if SHADERS in w.parents else f"voxy/{w.name}"
        print(f"{sev:7} [{v}] {name}: {msg}")
    for m in menu_problems:
        print(f"MENU    {m}")
    n_compiles = len(variants)  # informational
    print(f"\n{len(wrappers)} program files, {len(variants)} variants, "
          f"{len(errors)} errors, {len(warnings)} warnings, {len(menu_problems)} menu problems")
    sys.exit(1 if errors or menu_problems else 0)


if __name__ == "__main__":
    main()
