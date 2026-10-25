#!/usr/bin/env python3
"""Builds the release ZIP Iris can load directly: dist/BelgiumShaders-<version>.zip containing
shaders/, LICENSE, README.md and docs/THIRD_PARTY_ASSETS.md.

Runs tools/gen_wrappers.py first and refuses to package when tools/validate.py fails (unless
--skip-validate). Usage: python tools/package.py [--version 0.1.0] [--skip-validate]
"""
import argparse
import subprocess
import sys
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--version", default="0.3.1-dev")
    ap.add_argument("--skip-validate", action="store_true")
    args = ap.parse_args()

    subprocess.run([sys.executable, str(ROOT / "tools" / "gen_wrappers.py")], check=True)
    if not args.skip_validate:
        r = subprocess.run([sys.executable, str(ROOT / "tools" / "validate.py")])
        if r.returncode != 0:
            sys.exit("validation failed: not packaging (use --skip-validate to override)")

    out_dir = ROOT / "dist"
    out_dir.mkdir(exist_ok=True)
    out = out_dir / f"BelgiumShaders-{args.version}.zip"
    files = [p for p in (ROOT / "shaders").rglob("*") if p.is_file()]
    with zipfile.ZipFile(out, "w", compression=zipfile.ZIP_DEFLATED, compresslevel=6) as z:
        for p in sorted(files):
            arc = p.relative_to(ROOT).as_posix()
            # PNG/bin are already compressed or incompressible noise: store them.
            if p.suffix in (".png", ".bin"):
                z.write(p, arc, compress_type=zipfile.ZIP_STORED)
            else:
                z.write(p, arc)
        for extra in ("LICENSE", "README.md", "docs/THIRD_PARTY_ASSETS.md"):
            z.write(ROOT / extra, extra)
    print(f"wrote {out} ({out.stat().st_size / 1e6:.1f} MB, {len(files)} pack files)")


if __name__ == "__main__":
    main()
