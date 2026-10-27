"""Compile every shader program the way Iris would see it, using Khronos glslang.

Iris resolves `#include "/..."` relative to the `shaders/` folder and injects a few built-in macros
after the `#version` line. This script does the same, then hands each program to glslang.

    python -I tools/validate.py                         # base variant, default options
    python -I tools/validate.py --variants base dh voxy # also the Distant Horizons / Voxy builds
    python -I tools/validate.py --define CLOUD_RES=1 --undef TAA
    python -I tools/validate.py --profiles              # every quality profile in shaders.properties

Exit status is non-zero when any program fails. Needs `glslang` (or `glslangValidator`) on PATH.
"""

import argparse
import os
import re
import shutil
import subprocess
import sys
import tempfile
from concurrent.futures import ThreadPoolExecutor

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SHADERS = os.path.join(ROOT, "shaders")
DIMENSIONS = ("world0", "world-1", "world1")
STAGES = {".vsh": "vert", ".fsh": "frag", ".gsh": "geom", ".csh": "comp"}

INCLUDE_RE = re.compile(r'^\s*#include\s+"([^"]+)"', re.M)

# Macros Iris defines for every program (values match Iris 1.10 on an NVIDIA GPU, MC 1.21.11).
IRIS_MACROS = {
    "MC_VERSION": "12111",
    "MC_GL_VERSION": "460",
    "MC_GLSL_VERSION": "460",
    "MC_OS_WINDOWS": "",
    "MC_GL_VENDOR_NVIDIA": "",
    "MC_GL_RENDERER_GEFORCE": "",
    "IRIS_VERSION": "11008",
    "MC_HAND_DEPTH": "0.125",
    "MC_RENDER_QUALITY": "1.0",
    "MC_SHADOW_QUALITY": "1.0",
    "MC_RENDER_STAGE_NONE": "0",
}

# Iris adds these when Distant Horizons is installed (values from Iris' DHBlockIds).
DH_MACROS = {
    "DISTANT_HORIZONS": "",
    "DH_BLOCK_UNKNOWN": "0", "DH_BLOCK_LEAVES": "1", "DH_BLOCK_STONE": "2", "DH_BLOCK_WOOD": "3",
    "DH_BLOCK_METAL": "4", "DH_BLOCK_DIRT": "5", "DH_BLOCK_LAVA": "6", "DH_BLOCK_DEEPSLATE": "7",
    "DH_BLOCK_SNOW": "8", "DH_BLOCK_SAND": "9", "DH_BLOCK_TERRACOTTA": "10",
    "DH_BLOCK_NETHER_STONE": "11", "DH_BLOCK_WATER": "12", "DH_BLOCK_GRASS": "13",
    "DH_BLOCK_AIR": "14", "DH_BLOCK_ILLUMINATED": "15",
}

VARIANTS = {"base": {}, "dh": DH_MACROS, "voxy": {"VOXY": ""}}


def find_glslang():
    for name in ("glslang", "glslangValidator"):
        path = shutil.which(name)
        if path:
            return path
    sys.exit("glslang not found on PATH")


def resolve(path, seen_stack=()):
    """Inline includes recursively. Include paths are absolute from shaders/ or relative to the file."""
    if path in seen_stack:
        raise RuntimeError("include cycle: " + " -> ".join(seen_stack + (path,)))
    with open(path, encoding="utf-8") as f:
        text = f.read()

    def sub(m):
        inc = m.group(1)
        if inc.startswith("/"):
            target = os.path.join(SHADERS, inc.lstrip("/"))
        else:
            target = os.path.join(os.path.dirname(path), inc)
        target = os.path.normpath(target)
        if not os.path.isfile(target):
            raise RuntimeError(f"{os.path.relpath(path, SHADERS)}: missing include {inc}")
        return resolve(target, seen_stack + (path,))

    return INCLUDE_RE.sub(sub, text)


def inject(source, macros):
    lines = source.split("\n")
    for i, line in enumerate(lines):
        if line.strip().startswith("#version"):
            defs = [f"#define {k} {v}".rstrip() for k, v in macros.items()]
            # #line keeps glslang's line numbers equal to the wrapper's own after the injection.
            return "\n".join(lines[: i + 1] + defs + [f"#line {i + 2}"] + lines[i + 1:])
    raise RuntimeError("no #version line")


def apply_options(source, defines, undefs):
    """Override option values the way the Iris option menu rewrites lib/settings.glsl."""
    for name in undefs:
        source = re.sub(rf"^(\s*)#define\s+{name}\b.*$", r"\1// #define " + name, source, flags=re.M)
    for name, value in defines.items():
        pat = re.compile(rf"^(\s*)(//\s*)?#define\s+{name}\b[^\n]*$", re.M)
        if pat.search(source):
            source = pat.sub(lambda m: f"{m.group(1)}#define {name} {value}".rstrip(), source)
        else:
            # const options such as shadowMapResolution
            source = re.sub(rf"(const\s+\w+\s+{name}\s*=\s*)[^;]+;", rf"\g<1>{value};", source)
    return source


def programs(variant):
    for dim in DIMENSIONS:
        d = os.path.join(SHADERS, dim)
        for name in sorted(os.listdir(d)):
            ext = os.path.splitext(name)[1]
            # Iris only loads dh_* programs when Distant Horizons is installed.
            if ext in STAGES and (variant == "dh" or not name.startswith("dh_")):
                yield os.path.join(d, name), STAGES[ext]


def compile_one(glslang, path, stage, macros, defines, undefs, tmpdir):
    rel = os.path.relpath(path, SHADERS).replace("\\", "/")
    try:
        src = apply_options(inject(resolve(path), macros), defines, undefs)
    except RuntimeError as e:
        return rel, False, str(e)
    if stage == "vert" and os.path.basename(path).startswith("dh_"):
        # Iris declares the DH material attribute itself in DH vertex programs.
        src = re.sub(r"^(#line \d+)$", r"in int dhMaterialId;\n\1", src, count=1, flags=re.M)
    out = os.path.join(tmpdir, rel.replace("/", "__") + "." + stage)
    with open(out, "w", encoding="utf-8") as f:
        f.write(src)
    r = subprocess.run([glslang, "-S", stage, out], capture_output=True, text=True)
    msg = (r.stdout + r.stderr).strip()
    msg = "\n".join(l for l in msg.splitlines() if l.strip() and not l.strip().endswith(stage))
    return rel, r.returncode == 0, msg


def parse_profiles():
    with open(os.path.join(SHADERS, "shaders.properties"), encoding="utf-8") as f:
        text = f.read().replace("\\\n", " ")
    profiles = {}
    for m in re.finditer(r"^profile\.(\w+)\s*=\s*(.*)$", text, re.M):
        defs, undefs = {}, []
        for tok in m.group(2).split():
            if tok.startswith("!"):
                undefs.append(tok[1:])
            elif "=" in tok:
                k, v = tok.split("=", 1)
                defs[k] = v
            else:
                defs[tok] = ""
        profiles[m.group(1)] = (defs, undefs)
    return profiles


def run(glslang, variant, label, macros, defines, undefs, jobs):
    tmpdir = tempfile.mkdtemp(prefix="validate_")
    try:
        with ThreadPoolExecutor(jobs) as ex:
            results = list(ex.map(lambda p: compile_one(glslang, p[0], p[1], dict(IRIS_MACROS, **macros),
                                                        defines, undefs, tmpdir), programs(variant)))
    finally:
        shutil.rmtree(tmpdir, ignore_errors=True)
    failed = [r for r in results if not r[1]]
    for rel, _, msg in failed:
        print(f"FAIL [{label}] {rel}\n{msg}\n")
    print(f"[{label}] {len(results) - len(failed)}/{len(results)} programs compiled")
    return len(failed)


def check_voxy_copies():
    """Voxy cannot #include, so each dimension holds a copy of program/voxy/*; they must match."""
    src = os.path.join(SHADERS, "program", "voxy")
    stale = []
    for name in sorted(os.listdir(src)):
        with open(os.path.join(src, name), "rb") as f:
            ref = f.read()
        for dim in DIMENSIONS:
            p = os.path.join(SHADERS, dim, name)
            if not os.path.isfile(p) or open(p, "rb").read() != ref:
                stale.append(f"{dim}/{name}")
    for s in stale:
        print(f"FAIL stale Voxy copy {s} (copy it from program/voxy/)")
    return len(stale)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--variants", nargs="+", default=["base"], choices=list(VARIANTS))
    ap.add_argument("--define", action="append", default=[], help="NAME=VALUE option override")
    ap.add_argument("--undef", action="append", default=[], help="turn a boolean option off")
    ap.add_argument("--profiles", action="store_true", help="also compile every quality profile")
    ap.add_argument("-j", "--jobs", type=int, default=os.cpu_count() or 4)
    args = ap.parse_args()

    glslang = find_glslang()
    defines = dict(d.split("=", 1) if "=" in d else (d, "") for d in args.define)

    configs = [("default", defines, args.undef)]
    if args.profiles:
        for name, (d, u) in parse_profiles().items():
            configs.append((name, dict(d, **defines), u + args.undef))

    failures = check_voxy_copies()
    for variant in args.variants:
        for cname, d, u in configs:
            failures += run(glslang, variant, f"{variant}/{cname}", VARIANTS[variant], d, u, args.jobs)
    sys.exit(1 if failures else 0)


if __name__ == "__main__":
    main()
