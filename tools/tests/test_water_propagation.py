"""Reference test for the interactive-water solver (program/prepare/water_sim.csh, SIM_STEP_N).

Runs the GLSL step in numpy, with the constants read from the shader sources, and compares it
with the previous solver (uniform loss 0.004 per step, height scaled by up to 8 % in a square edge
layer, k = 0.02):
1. stable for every speed and damping option (von Neumann amplification <= 1);
2. a ring travels at WATER_SIM_SPEED blocks/s, at a steady rate;
3. a hop's ring stays visible (slope > 0.02) much further than before, with no energy growth;
4. waves leave through the edge layer without coming back (old layer: 13-23 % reflected);
5. a boat wake persists after the boat stops, stays bounded, and the field falls asleep.

    python -P tools/tests/test_water_propagation.py
"""

import math
import os
import re

import numpy as np

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))


def src(rel):
    with open(os.path.join(ROOT, "shaders", rel), encoding="utf-8") as f:
        return f.read()


SIM = src("program/prepare/water_sim.csh")
COMMON = src("lib/water/sim_common.glsl")
SETTINGS = src("lib/settings.glsl")

DT = 1.0 / 60.0
DX = 0.25
SPEEDS = [float(v) for v in re.search(r"#define WATER_SIM_SPEED \S+ // \[([^\]]+)\]", SETTINGS).group(1).split()]
DEFAULT_SPEED = float(re.search(r"#define WATER_SIM_SPEED (\S+)", SETTINGS).group(1))
DAMPING = {int(m[0]): (float(m[1]), float(m[2])) for m in re.findall(
    r"WATER_SIM_DAMPING == (\d)\nconst float SIM_DAMPING = ([\d.]+); const float SIM_VISCOSITY = ([\d.]+);", SIM)}
DAMPING[2] = tuple(float(x) for x in re.search(
    r"#else\nconst float SIM_DAMPING = ([\d.]+); const float SIM_VISCOSITY = ([\d.]+);", SIM).groups())
SPONGE_START, SPONGE_W, SPONGE_MAX = (float(x) for x in re.search(
    r"saturate\(\(simRadius\(local\) - ([\d.]+)\) / ([\d.]+)\);\s+return ([\d.]+) \* u \* u;", COMMON).groups())
H_AWAKE, V_AWAKE = (float(x) for x in re.search(r"abs\(next\) > ([\de.-]+) \|\| abs\(next - h\) > ([\de.-]+)", SIM).groups())


def k_of(speed):
    return (speed * DT / DX) ** 2


def lap(a):
    return np.roll(a, 1, 0) + np.roll(a, -1, 0) + np.roll(a, 1, 1) + np.roll(a, -1, 1) - 4.0 * a


def smoothstep(e0, e1, x):
    t = np.clip((x - e0) / (e1 - e0), 0.0, 1.0)
    return t * t * (3.0 - 2.0 * t)


class Grid:
    def __init__(self, n, solver="new", speed=DEFAULT_SPEED, damping=1):
        self.n = n
        i = np.arange(n) - n // 2 + 0.5
        self.cx, self.cy = np.meshgrid(i, i, indexing="ij")          # cells from the centre corner
        self.x, self.y = self.cx * DX, self.cy * DX                   # blocks
        self.r = np.hypot(self.x, self.y)
        self.solver = solver
        if solver == "old":
            self.k, self.d, self.nu = 0.02, 0.004, 0.0
            edge = np.maximum(abs(self.cx), abs(self.cy)) / (0.5 * n)
            self.scale = 0.92 + 0.08 * (1.0 - smoothstep(0.7, 0.95, edge))
        else:
            self.k = k_of(speed)
            self.d, self.nu = DAMPING[damping]
            u = np.clip((np.hypot(self.cx, self.cy) / (0.5 * n) - SPONGE_START) / SPONGE_W, 0.0, 1.0)
            self.sponge = SPONGE_MAX * u * u
        self.h = np.zeros((n, n))
        self.hp = np.zeros((n, n))

    def gauss(self, px, py, s2):
        return np.exp(-((self.x - px) ** 2 + (self.y - py) ** 2) / s2)

    def splash(self, amp, px=0.0, py=0.0):
        return -(self.gauss(px, py, 0.6) - 0.25 * self.gauss(px, py, 2.4)) * amp

    def step(self, D=0.0):
        h, hp = self.h, self.hp
        v = h - hp
        if self.solver == "old":
            nxt = (h + v * (1.0 - self.d) + self.k * lap(h)) * self.scale
        else:
            nxt = h + v * (1.0 - self.d - self.sponge) + self.k * lap(h) + self.nu * lap(v)
        nxt = np.clip(nxt + D, -0.6, 0.6)
        moving = bool(((np.abs(nxt) > H_AWAKE) | (np.abs(nxt - h) > V_AWAKE)).any())
        self.hp, self.h = h + D, nxt
        return moving

    def slope(self):
        gx = (np.roll(self.h, -1, 0) - np.roll(self.h, 1, 0)) / (2 * DX)
        gy = (np.roll(self.h, -1, 1) - np.roll(self.h, 1, 1)) / (2 * DX)
        return np.hypot(gx, gy)


HOP = 0.85 * (1.0 - math.exp(-5.0 / 9.0)) * 1.0      # bookkeeping amplitude for a 5 blocks/s hop


def ring_history(grid, secs):
    D = grid.splash(HOP)
    grid.h += D
    grid.hp += D
    out = []
    for n in range(int(secs * 60)):
        grid.step()
        if (n + 1) % 30 == 0:
            s = grid.slope()
            out.append(((n + 1) / 60.0, float(grid.r.flat[np.argmax(s)]), float(s.max()), float((s * s).sum())))
    return out


def test_stability():
    lam = np.linspace(0.0, 8.0, 801)                  # eigenvalues of -L on the 5-point stencil
    worst = 0.0
    for speed in SPEEDS:
        for d, nu in DAMPING.values():
            for extra in (0.0, SPONGE_MAX):
                b = 2.0 - d - extra - (k_of(speed) + nu) * lam
                c = 1.0 - d - extra - nu * lam
                disc = b * b - 4.0 * c + 0j
                g = np.maximum(abs((b + np.sqrt(disc)) / 2), abs((b - np.sqrt(disc)) / 2))
                worst = max(worst, float(g.max()))
    assert worst <= 1.0 + 1e-12, worst
    print(f"stability: max |g| = {worst:.6f} over {len(SPEEDS)} speeds x {len(DAMPING)} damping levels, with and without the edge layer")


def test_speed():
    for speed in (SPEEDS[0], DEFAULT_SPEED, SPEEDS[-1]):
        hist = ring_history(Grid(320, speed=speed), 6.0)
        pts = [(t, r) for t, r, _, _ in hist if 1.5 <= t <= 6.0]
        t = np.array([p[0] for p in pts]); r = np.array([p[1] for p in pts])
        rate, _ = np.polyfit(t, r, 1)
        resid = float(np.abs(r - np.polyval(np.polyfit(t, r, 1), t)).max())
        # The steepest part of the ring is short waves, which lag a little on the grid.
        assert 0.8 * speed < rate < 1.05 * speed, (speed, rate)
        assert resid < 1.0, (speed, resid)
        print(f"speed: option {speed} blocks/s -> ring at {rate:.2f} blocks/s, steady to within {resid:.2f} blocks")


def visible_range(hist, threshold=0.02):
    reach = 0.0
    for _, r, smax, _ in hist:
        if smax >= threshold:
            reach = r
    return reach


def test_range_and_decay():
    old = ring_history(Grid(400, "old"), 14.0)
    new = ring_history(Grid(400), 14.0)
    r_old, r_new = visible_range(old), visible_range(new)
    energy = [e for t, _, _, e in new if t >= 1.0]
    assert all(b <= a * 1.001 for a, b in zip(energy, energy[1:])), "energy grew"
    assert r_new > 1.35 * r_old, (r_old, r_new)
    lo = visible_range(ring_history(Grid(400, damping=2), 14.0))
    hi = visible_range(ring_history(Grid(400, damping=0), 14.0))
    assert lo < r_new < hi, (lo, r_new, hi)
    print(f"range: a hop's ring stays above slope 0.02 out to {r_new:.1f} blocks (old solver {r_old:.1f}); "
          f"damping High / Normal / Low {lo:.1f} / {r_new:.1f} / {hi:.1f}; energy never grows")


def run_reflection(grid, steps, snaps):
    D = grid.splash(HOP)
    grid.h += D
    grid.hp += D
    out = {}
    for n in range(steps):
        grid.step()
        if n + 1 in snaps:
            out[n + 1] = grid.h.copy()
    return out


def crop(a, n):
    c = a.shape[0] // 2
    return a[c - n // 2:c + n // 2, c - n // 2:c + n // 2]


def reflection(n, solver):
    half = n * DX / 2
    speed = 0.02 ** 0.5 * DX / DT if solver == "old" else DEFAULT_SPEED
    t_in = 0.55 * half / speed
    snaps = [int(t_in * 60), int(1.6 * half / speed * 60), int(2.2 * half / speed * 60)]
    small = run_reflection(Grid(n, solver), snaps[-1], snaps)
    ref = Grid(3 * n, solver)   # its edge is too far for an echo to return in time
    if solver == "old":
        ref.scale = 1.0
    else:
        ref.sponge = 0.0
    big = run_reflection(ref, snaps[-1], snaps)
    g = Grid(n)
    inc = np.sqrt((crop(big[snaps[0]], n)[(g.r > 0.4 * half) & (g.r < 0.7 * half)] ** 2).mean())
    inner = g.r < 0.5 * half
    return max(float(np.sqrt(((crop(small[s], n) - crop(big[s], n))[inner] ** 2).mean()) / inc) for s in snaps[1:])


def test_edge_reflection():
    for n in (128, 256):
        new, old = reflection(n, "new"), reflection(n, "old")
        assert new < 0.02 and old > 0.08, (n, new, old)
        print(f"edge: {n}^2 grid reflects {100 * new:.1f} % of an outgoing ring back inside (old edge layer {100 * old:.0f} %)")


def test_boat_wake():
    g = Grid(256)
    speed, cruise, after = 8.0, 3.0, 25.0   # the boat stops at the centre, like the camera's domain
    steps_cruise = int(cruise * 60)
    peak, asleep = 0.0, None
    for n in range(int((cruise + after) * 60)):
        D = 0.0
        if n < steps_cruise:
            x0, dl = -24.0 + speed * n * DT, speed * DT
            for i in (-1, 0, 1):
                p = x0 + 0.6 * i
                D = D - (g.gauss(p, 0.0, 0.55) - g.gauss(p - dl, 0.0, 0.55)) * 0.2
        moving = g.step(D)
        peak = max(peak, float(np.abs(g.h).max()))
        if n == steps_cruise + 60:
            wake_1s = float(g.slope().max())
        if n >= steps_cruise and not moving and asleep is None:
            asleep = (n - steps_cruise) / 60.0
    assert wake_1s > 0.05, wake_1s
    assert peak < 0.5, peak
    assert asleep is not None and asleep < after, asleep
    print(f"boat: wake slope {wake_1s:.2f} one second after stopping; peak height {peak:.2f} blocks; "
          f"the field falls asleep {asleep:.0f} s after the boat stops")


if __name__ == "__main__":
    test_stability()
    test_speed()
    test_range_and_decay()
    test_edge_reflection()
    test_boat_wake()
    print("OK")
