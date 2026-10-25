"""Reference simulation of lib/sky/celestial.glsl (same formulas, NumPy) to check that:
  * moonPhase 0 is a full moon opposite the sun at midnight, phase 4 is new;
  * the illuminated fraction follows the vanilla phase sequence;
  * eclipses recur with the configured cycle and include both solar and lunar ones;
  * the time warp keeps the elongation monotonic.
Run: python -P tools/tests/test_celestial.py
"""
import math
import numpy as np

SUN_SIZE, MOON_SIZE, INCL, CYCLE, SLOW = 1.0, 1.05, 5.1, 48, 0.85
UMBRA, PENUMBRA = 2.7, 4.9


def rot(v, k, a):
    c, s = math.cos(a), math.sin(a)
    return v * c + np.cross(k, v) * s + k * np.dot(k, v) * (1 - c)


def sun_dir(world_time, path_rot=-25.0):
    # Minecraft: sunAngle 0 at sunrise (worldTime 0), rises in +X.
    ang = 2 * math.pi * (world_time % 24000) / 24000.0
    r = math.radians(path_rot)
    axis = np.array([0.0, math.sin(r), math.cos(r)])
    return rot(np.array([1.0, 0, 0]), axis, ang), axis


def warp(phi, s):
    k = s * 128.0 / 93.0
    x = 2 * math.pi * phi
    series = 28 * math.sin(2 * x) + 7 * math.sin(4 * x) + (4 / 3) * math.sin(6 * x) + 0.125 * math.sin(8 * x)
    return phi - k / (2 * math.pi * 128.0) * series


def state(day, wt):
    s, axis = sun_dir(wt)
    frac = (wt % 24000) / 24000.0
    tr = ((day % 8) + frac - 0.75) % 8.0
    phi = tr / 7.0 if tr < 3.5 else 0.5 + (tr - 3.5) / 9.0
    phiw = warp(phi, SLOW)
    E = math.pi + 2 * math.pi * phiw
    wrap = 2 * CYCLE + 5
    nodal = (((day % wrap) + frac) / (CYCLE + 2.5)) % 1.0
    beta = math.radians(INCL) * math.sin(2 * math.pi * (phiw + nodal))
    inplane = rot(s, axis, -E)
    m = inplane * math.cos(beta) + axis * math.sin(beta)
    m /= np.linalg.norm(m)
    return s, m, phiw


def test_phases():
    # midnight of day 0 (worldTime 18000) is full moon: moon opposite the sun
    s, m, _ = state(0, 18000)
    assert np.dot(s, m) < -0.99, np.dot(s, m)
    assert m[1] > 0.5, "full moon should be high at midnight"
    # day 4 noon (worldTime 6000): new moon, moon within the orbital tilt of the sun
    s, m, _ = state(4, 6000)
    assert np.dot(s, m) > math.cos(math.radians(INCL) + 1e-3), np.dot(s, m)
    assert s[1] > 0.5, "new moon should be at noon so solar eclipses are visible"
    # illuminated fraction decreases from full (phase 0) to new (phase 4)
    fr = []
    for d in range(0, 5):
        s, m, _ = state(d, 18000)
        alpha = math.pi - math.acos(np.clip(np.dot(s, m), -1, 1))
        fr.append(0.5 * (1 + math.cos(alpha)))
    assert all(a > b for a, b in zip(fr, fr[1:])), fr
    print("phases ok, lit fraction at midnight days 0..4:", [round(x, 3) for x in fr])


def test_monotonic_warp():
    x = np.linspace(0, 1, 10001)
    w = np.array([warp(v, SLOW) for v in x])
    assert np.all(np.diff(w) > 0)
    assert abs(w[-1] - 1.0) < 1e-9 and abs(w[0]) < 1e-12, "warp must map [0,1] onto [0,1]"
    print("warp monotonic, min speed", round(float(np.min(np.diff(w)) / (x[1] - x[0])), 3))


def test_eclipses():
    rs, rm = math.radians(SUN_SIZE) / 2, math.radians(MOON_SIZE) / 2
    solar, lunar = [], []
    for day in range(0, (CYCLE + 1) * 8):
        best_s, best_l = 9, 9
        for wt in range(0, 24000, 50):
            s, m, _ = state(day, wt)
            sep = math.acos(np.clip(np.dot(s, m), -1, 1))
            if s[1] > 0.05:
                best_s = min(best_s, sep)
            if m[1] > 0.05:
                best_l = min(best_l, math.pi - sep)
        if best_s < rs + rm:
            solar.append((day, round(1 - best_s / (rs + rm), 2)))
        if best_l < (PENUMBRA + 1) * rm:
            lunar.append((day, "umbral" if best_l < (UMBRA + 1) * rm else "penumbral"))
    print(f"over {(CYCLE+1)*8} days: solar eclipses {solar}")
    print(f"                    lunar eclipses {lunar}")
    assert solar and lunar, "expected both kinds within eight nodal cycles"
    # duration of the first solar eclipse in real seconds (20 min day)
    day = solar[0][0]
    inside = sum(1 for wt in range(0, 24000, 10)
                 if math.acos(np.clip(np.dot(*state(day, wt)[:2]), -1, 1)) < rs + rm)
    print("first solar eclipse lasts", round(inside * 10 / 20.0, 1), "s of real time (20 ticks/s)")


if __name__ == "__main__":
    test_phases()
    test_monotonic_warp()
    test_eclipses()
