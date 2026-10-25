"""Dependency map for porting the extracted Halcyon modules onto the Belgium Shaders engine.

For every GLSL file of the extracted Halcyon repository (my-code-for-shaders---j), lists the
identifiers it uses that it does not define itself, classified as:
  * glimmer  - defined somewhere in Glimmer at commit 6a59109 (needs an adapter or rewrite)
  * halcyon  - defined in another extracted Halcyon file
  * belgium  - already defined by Belgium Shaders (shaders/lib) under the same name
  * iris     - Iris uniform/sampler names (declared by the engine)
Comments are stripped first, so only real code counts.

Usage: python -P tools/halcyon_deps.py <halcyon_extract_dir> <glimmer_checkout_dir> [--json out.json]
The Glimmer checkout must be at 6a59109 (or pass a worktree of it).
"""
import argparse
import json
import re
import subprocess
from pathlib import Path

BELGIUM = Path(__file__).resolve().parent.parent / "shaders"

GLSL_WORDS = set("""
attribute const uniform varying buffer shared coherent volatile restrict readonly writeonly layout centroid flat
smooth noperspective patch sample break continue do for while switch case default if else subroutine in out inout
float double int void bool true false invariant precise discard return mat2 mat3 mat4 mat2x2 mat2x3 mat2x4 mat3x2
mat3x3 mat3x4 mat4x2 mat4x3 mat4x4 vec2 vec3 vec4 ivec2 ivec3 ivec4 bvec2 bvec3 bvec4 uint uvec2 uvec3 uvec4 lowp
mediump highp precision sampler1D sampler2D sampler3D samplerCube sampler2DShadow sampler2DArray usampler2D
isampler2D image2D image3D uimage2D uimage3D iimage2D struct define ifdef ifndef endif elif undef include version
extension pragma line defined
radians degrees sin cos tan asin acos atan sinh cosh tanh asinh acosh atanh pow exp log exp2 log2 sqrt inversesqrt
abs sign floor trunc round roundEven ceil fract mod modf min max clamp mix step smoothstep isnan isinf floatBitsToInt
floatBitsToUint intBitsToFloat uintBitsToFloat fma frexp ldexp packUnorm2x16 packSnorm2x16 packUnorm4x8 packSnorm4x8
unpackUnorm2x16 unpackSnorm2x16 unpackUnorm4x8 unpackSnorm4x8 packHalf2x16 unpackHalf2x16 length distance dot
cross normalize faceforward reflect refract matrixCompMult outerProduct transpose determinant inverse lessThan
lessThanEqual greaterThan greaterThanEqual equal notEqual any all not textureSize texture textureProj textureLod
textureOffset texelFetch texelFetchOffset textureGrad textureGather imageLoad imageStore imageSize dFdx dFdy fwidth
barrier memoryBarrier groupMemoryBarrier atomicAdd atomicMin atomicMax atomicOr atomicAnd atomicExchange
atomicCompSwap imageAtomicAdd imageAtomicMax imageAtomicOr bitfieldExtract bitfieldInsert bitCount findLSB findMSB
uaddCarry usubBorrow umulExtended imulExtended gl_Position gl_FragCoord gl_FragData gl_FragColor gl_Vertex gl_Normal
gl_Color gl_MultiTexCoord0 gl_MultiTexCoord1 gl_ModelViewMatrix gl_ProjectionMatrix gl_NormalMatrix
gl_TextureMatrix gl_ModelViewProjectionMatrix gl_GlobalInvocationID gl_LocalInvocationID gl_WorkGroupID
gl_NumWorkGroups gl_VertexID gl_InstanceID gl_FrontFacing local_size_x local_size_y local_size_z ftransform
x y z w r g b a s t p q xy xyz rgb rgba xz yz zw st
""".split())

DEF_PATTERNS = [
    ("function", re.compile(r"^\s*(?:(?:in|out|inout|const|highp|mediump|lowp)\s+)*[A-Za-z_]\w*\s+([A-Za-z_]\w*)\s*\([^;{]*\)\s*\{", re.M)),
    ("macro", re.compile(r"^\s*#\s*define\s+([A-Za-z_]\w*)", re.M)),
    ("const", re.compile(r"^\s*const\s+[A-Za-z_]\w*(?:\[\d*\])?\s+([A-Za-z_]\w*)", re.M)),
    ("uniform", re.compile(r"^\s*(?:layout\s*\([^)]*\)\s*)?uniform\s+[A-Za-z_]\w*\s+([A-Za-z_]\w*)", re.M)),
    ("struct", re.compile(r"^\s*struct\s+([A-Za-z_]\w*)", re.M)),
    ("global", re.compile(r"^(?:float|int|bool|vec[234]|ivec[234]|uvec[234]|mat[234])\s+([A-Za-z_]\w*)\s*(?:=|;)", re.M)),
    ("buffer-member", re.compile(r"^\s+(?:float|int|bool|vec[234]|ivec[234]|mat[234])\s+([A-Za-z_]\w*)\s*;", re.M)),
]


def strip_comments(src: str) -> str:
    src = re.sub(r"/\*.*?\*/", " ", src, flags=re.S)
    return re.sub(r"//[^\n]*", "", src)


def definitions(src: str):
    out = {}
    for kind, pat in DEF_PATTERNS:
        for m in pat.finditer(src):
            out.setdefault(m.group(1), kind)
    return out


def identifiers(src: str):
    src = re.sub(r'"[^"\n]*"', " ", src)                  # include paths
    return set(re.findall(r"(?<![\w.])([A-Za-z_]\w*)", src))


def glimmer_defs(glimmer: Path):
    files = subprocess.run(["git", "-C", str(glimmer), "ls-tree", "-r", "--name-only", "6a59109"],
                           capture_output=True, text=True, check=True).stdout.split()
    table = {}
    for f in files:
        if not f.endswith((".glsl", ".vsh", ".fsh", ".csh")):
            continue
        src = subprocess.run(["git", "-C", str(glimmer), "show", f"6a59109:{f}"], capture_output=True,
                             text=True, errors="replace").stdout
        for name, kind in definitions(strip_comments(src)).items():
            table.setdefault(name, (f, kind))
    return table


def belgium_defs():
    table = {}
    for p in BELGIUM.rglob("*.glsl"):
        for name, kind in definitions(strip_comments(p.read_text(errors="replace"))).items():
            table.setdefault(name, (p.relative_to(BELGIUM).as_posix(), kind))
    return table


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("halcyon")
    ap.add_argument("glimmer")
    ap.add_argument("--json")
    args = ap.parse_args()
    hal = Path(args.halcyon)
    gl = glimmer_defs(Path(args.glimmer))
    be = belgium_defs()
    files = sorted(p for p in (hal / "shaders").rglob("*") if p.suffix in (".glsl", ".fsh", ".vsh", ".csh"))
    hal_defs = {}
    srcs = {}
    for p in files:
        s = strip_comments(p.read_text(errors="replace"))
        srcs[p] = s
        for n, k in definitions(s).items():
            hal_defs.setdefault(n, (p.relative_to(hal).as_posix(), k))
    report = {}
    for p, s in srcs.items():
        own = definitions(s)
        used = identifiers(s) - GLSL_WORDS - set(own)
        entry = {"glimmer": {}, "halcyon": {}, "belgium_same_name": {}, "unresolved": []}
        for n in sorted(used):
            if n in hal_defs and hal_defs[n][0] != p.relative_to(hal).as_posix():
                entry["halcyon"][n] = hal_defs[n][0]
            elif n in gl:
                entry["glimmer"][n] = f"{gl[n][0]} ({gl[n][1]})"
                if n in be:
                    entry["belgium_same_name"][n] = be[n][0]
            elif n in be:
                entry["belgium_same_name"][n] = be[n][0]
            else:
                entry["unresolved"].append(n)
        report[p.relative_to(hal).as_posix()] = entry
    for f, e in report.items():
        if not (e["glimmer"] or e["halcyon"]):
            continue
        print(f"== {f}: {len(e['glimmer'])} Glimmer names, {len(e['halcyon'])} cross-Halcyon")
        print("   glimmer:", ", ".join(sorted(e["glimmer"])))
        if e["belgium_same_name"]:
            print("   same name in Belgium:", ", ".join(sorted(e["belgium_same_name"])))
    if args.json:
        Path(args.json).write_text(json.dumps(report, indent=1))


if __name__ == "__main__":
    main()
