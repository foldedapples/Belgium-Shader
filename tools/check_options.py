"""Consistency check for the Iris option menu.

* every option defined in lib/settings.glsl (or as a const option Iris knows) is placed on a
  screen exactly once and is read somewhere outside its own definition (no dead controls);
* every name on a screen, in sliders or in a profile is a real option;
* every option and screen has a name in lang/en_us.lang.

    python -I tools/check_options.py
"""

import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SHADERS = os.path.join(ROOT, "shaders")
IRIS_CONST_OPTIONS = {"shadowMapResolution", "shadowDistance"}


def read(rel):
    with open(os.path.join(SHADERS, rel), encoding="utf-8") as f:
        return f.read()


def main():
    settings = read("lib/settings.glsl")
    props = read("shaders.properties").replace("\\\n", " ")
    lang = read("lang/en_us.lang")

    options = set(re.findall(r"^\s*(?://\s*)?#define\s+([A-Z][A-Z0-9_]+)\b[^\n]*//\s*\[", settings, re.M))
    options |= set(re.findall(r"^\s*(?://\s*)?#define\s+([A-Z][A-Z0-9_]+)\s*(?://(?!\s*\[).*)?$", settings, re.M)) & \
        set(re.findall(r"\b([A-Z][A-Z0-9_]+)\b", props))
    options |= IRIS_CONST_OPTIONS

    screens = dict(re.findall(r"^screen\.([A-Z_]+)\s*=\s*(.*)$", props, re.M))
    main_screen = re.search(r"^screen\s*=\s*(.*)$", props, re.M).group(1).split()
    placed = []
    for items in screens.values():
        placed += [t for t in items.split() if not t.startswith("[") and not t.startswith("<")]
    subscreens = {t[1:-1] for t in main_screen if t.startswith("[")}
    for items in screens.values():
        subscreens |= {t[1:-1] for t in items.split() if t.startswith("[")}

    sliders = re.search(r"^sliders\s*=\s*(.*)$", props, re.M).group(1).split()
    profile_opts = set()
    for m in re.finditer(r"^profile\.\w+\s*=\s*(.*)$", props, re.M):
        for tok in m.group(1).split():
            profile_opts.add(tok.lstrip("!").split("=")[0])

    code = []
    for root, _, files in os.walk(SHADERS):
        for f in files:
            if f.endswith((".glsl", ".vsh", ".fsh", ".gsh", ".csh", ".properties")):
                p = os.path.join(root, f)
                if os.path.normpath(p) != os.path.normpath(os.path.join(SHADERS, "lib/settings.glsl")):
                    with open(p, encoding="utf-8") as fh:
                        code.append(fh.read())
    code = "\n".join(code)
    # Uses inside settings.glsl itself (derived defines) count too, minus the definition line.
    settings_uses = re.sub(r"^\s*(?://\s*)?#define\s+[A-Z0-9_]+.*$", "", settings, flags=re.M)

    errors = []
    for o in sorted(options):
        n = placed.count(o)
        if n != 1:
            errors.append(f"{o}: on {n} screens")
        # Screen/slider/profile listings are not uses.
        stripped = re.sub(r"^(screen|sliders|profile)[^\n]*$", "", code, flags=re.M)
        if not re.search(rf"\b{o}\b", stripped) and not re.search(rf"\b{o}\b", settings_uses):
            errors.append(f"{o}: never read (dead control)")
        if f"option.{o}=" not in lang and f"option.{o} =" not in lang:
            errors.append(f"{o}: no lang name")
    for t in set(placed) | set(sliders) | profile_opts:
        if t not in options:
            errors.append(f"{t}: listed in shaders.properties but not an option")
    for s in sorted(subscreens):
        if s not in screens:
            errors.append(f"[{s}]: linked but not defined")
        if f"screen.{s}=" not in lang and f"screen.{s} =" not in lang:
            errors.append(f"[{s}]: no lang name")
    for s in screens:
        if s not in subscreens:
            errors.append(f"[{s}]: defined but unreachable")

    for e in errors:
        print("ERROR", e)
    print(f"{len(options)} options, {len(screens)} screens, {len(errors)} problems")
    sys.exit(1 if errors else 0)


if __name__ == "__main__":
    main()
