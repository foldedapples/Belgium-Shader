"""CPU reference of program/water_sim_step.glsl (same equations) used to test the scheme.

Checks:
  1. stability: 10 minutes of continuous boat forcing at the default and maximum settings
     stays bounded with no NaN;
  2. a splash impulse conserves water volume and spreads as a round ring (isotropy);
  3. the sponge absorbs outgoing waves instead of reflecting them;
  4. a boat faster than the wave speed leaves a V-shaped wake behind it;
  5. toroidal scrolling: a ripple keeps its world position while the window moves.
Run: python -P tools/tests/test_water_sim.py
"""
import math
import numpy as np

HZ = 60.0
BOAT_FORCE = 2.5
DT = 1.0 / HZ


class Sim:
    def __init__(self, n=256, cpb=8, wave_speed=1.4, damping=0.45, sponge=14.0, sponge_width=0.12, omega0=2 * math.pi * 0.8):
        self.n, self.cpb = n, cpb
        self.dx = 1.0 / cpb
        self.c = min(wave_speed, 0.6 * self.dx / DT)
        self.nu = 0.05 * self.dx * self.dx / DT
        self.damping, self.sponge, self.sw = damping, sponge, sponge_width
        self.omega0 = omega0
        self.h = np.zeros((n, n))
        self.hp = np.zeros((n, n))
        self.centre = np.array([0, 0])
        idx = np.arange(n)
        r = np.abs(idx - n // 2 + 0.5) / (n // 2)
        edge = np.maximum(r[:, None], r[None, :])
        t = np.clip((edge - (1 - self.sw)) / self.sw, 0, 1)
        self.sponge_mask = t * t * (3 - 2 * t)

    def lap(self, a):
        orth = np.roll(a, 1, 0) + np.roll(a, -1, 0) + np.roll(a, 1, 1) + np.roll(a, -1, 1)
        diag = (np.roll(np.roll(a, 1, 0), 1, 1) + np.roll(np.roll(a, 1, 0), -1, 1) +
                np.roll(np.roll(a, -1, 0), 1, 1) + np.roll(np.roll(a, -1, 0), -1, 1))
        return (0.5 * orth + 0.25 * diag - 3.0 * a) / (self.dx * self.dx)

    def step(self, force=None, impulse=None):
        h, hp = self.h, self.hp
        gamma = self.damping + self.sponge * self.sponge_mask
        lap_h = self.lap(h)
        lap_v = lap_h - self.lap(hp)
        hn = h + (h - hp) * (1 - gamma * DT) + (self.c * DT) ** 2 * lap_h + self.nu * DT * lap_v - (self.omega0 * DT) ** 2 * h
        if force is not None:
            hn += DT * DT * force
        if impulse is not None:
            hn += impulse
            h = h + impulse
        hn = np.clip(hn, -0.6, 0.6)
        h = np.clip(h, -0.6, 0.6)
        bad = ~np.isfinite(hn) | ~np.isfinite(h)
        hn[bad] = 0.0
        h[bad] = 0.0
        self.hp, self.h = h, hn

    def coords(self):
        i = np.arange(self.n) - self.n // 2 + 0.5
        return np.meshgrid(i, i, indexing="ij")


def mexican_hat(x, y, cx, cy, sigma):
    r2 = ((x - cx) ** 2 + (y - cy) ** 2) / sigma ** 2
    return np.where(r2 > 50, 0.0, (1 - 0.5 * r2) * np.exp(-0.5 * r2))


def hull(x, y, bx, by, heading, dx):
    dxb, dyb = (x - bx) * dx, (y - by) * dx
    fx, fy = math.cos(heading), math.sin(heading)
    along = (dxb * fx + dyb * fy) / 0.78
    across = (-dxb * fy + dyb * fx) / 0.42
    return np.exp(-(along ** 2) ** 2 - (across ** 2) ** 2)


def test_stability():
    for cpb, ws in [(8, 1.4), (16, 6.0), (4, 3.0)]:
        sim = Sim(n=128, cpb=cpb, wave_speed=ws)
        x, y = sim.coords()
        peak = 0.0
        for k in range(int(600 * HZ) // 10):  # 60 s of sim time, coarse but long
            t = k * DT
            bx = 20 * math.cos(t * 0.3) * cpb / 8
            by = 20 * math.sin(t * 0.3) * cpb / 8
            f = -BOAT_FORCE * hull(x, y, bx, by, t * 0.3 + math.pi / 2, sim.dx)
            sim.step(force=f)
            peak = max(peak, float(np.abs(sim.h).max()))
        assert np.isfinite(sim.h).all()
        assert peak < 0.15, peak
        print(f"stability cpb={cpb} c={sim.c:.2f} courant={sim.c * DT / sim.dx:.2f}: peak |h| {peak:.3f}")


def test_splash():
    sim = Sim(n=256, cpb=8)
    x, y = sim.coords()
    imp = -0.1 * mexican_hat(x, y, 0.0, 0.0, 0.55 * 8)
    vol0 = imp.sum()
    sim.step(impulse=imp)
    print(f"splash impulse net volume {vol0:.2e} (peak {imp.min():.3f})")
    assert abs(vol0) < 1e-3 * np.abs(imp).sum()
    for _ in range(90):  # 1.5 s
        sim.step()
    # ring isotropy: radius of the leading wavefront along an axis and along a diagonal
    r = np.hypot(x, y)
    ang = np.arctan2(y, x)
    thresh = 0.05 * np.abs(sim.h).max()

    def front(mask):
        rr = r[mask & (np.abs(sim.h) > thresh)]
        return rr.max() if rr.size else 0.0

    r_axis = front(np.abs(ang) < 0.05)
    r_diag = front(np.abs(ang - math.pi / 4) < 0.05)
    print(f"wavefront radius after 1.5 s: axis {r_axis / 8:.2f} blocks, diagonal {r_diag / 8:.2f} blocks")
    assert r_axis > 8 and abs(r_axis - r_diag) / r_axis < 0.08, "ripples should be round"
    print(f"water volume after 1.5 s: {sim.h.sum():.2e}")


def test_sponge():
    # Reflection test: after the ring has reached the window edge, the energy that comes back
    # into the interior should be far smaller with the sponge than with a hard edge.
    def run(sponge):
        # The restoring term is off here: its slow dispersive tail would mask reflections.
        sim = Sim(n=128, cpb=8, damping=0.0, sponge=sponge, omega0=0.0)
        x, y = sim.coords()
        sim.step(impulse=-0.1 * mexican_hat(x, y, 0, 0, 4))
        for _ in range(int(9 * HZ)):
            sim.step()
        r = np.hypot(x, y)
        ring = (r > 2.5 * 8) & (r < 6.5 * 8)
        return float((sim.h[ring] ** 2).sum())
    with_sponge, hard_edge = run(14.0), run(0.0)
    print(f"reflected energy in the interior: sponge {with_sponge:.3e} vs hard edge {hard_edge:.3e}")
    assert with_sponge < 0.2 * hard_edge, "sponge should absorb outgoing waves"


def test_wake():
    sim = Sim(n=256, cpb=8)
    x, y = sim.coords()
    speed = 6.0 * 8  # 6 blocks/s in cells/s
    bx = -80.0
    for _ in range(int(3.0 * HZ)):
        bx += speed * DT
        sim.step(force=-BOAT_FORCE * hull(x, y, bx, 0.0, 0.0, sim.dx))
    # behind the boat the disturbance should spread sideways (V), ahead it should be calm
    behind = np.abs(sim.h[(x < bx - 40) & (x > bx - 60)]).max()
    ahead = np.abs(sim.h[(x > bx + 30)]).max()
    width_far = np.abs(y[(x > bx - 60) & (x < bx - 50) & (np.abs(sim.h) > 0.3 * behind)]).max()
    width_near = np.abs(y[(x > bx - 15) & (x < bx - 5) & (np.abs(sim.h) > 0.3 * behind)]).max()
    print(f"wake: |h| behind {behind:.4f}, ahead {ahead:.5f}; half-width near {width_near / 8:.2f} far {width_far / 8:.2f} blocks")
    assert behind > 20 * ahead and width_far > width_near, "expected a widening wake behind the boat"


def test_scrolling():
    # Window that follows a player moving +x; a ripple created at world cell 0 must stay there.
    n, cpb = 128, 8
    store = np.zeros((n, n, 2))
    centre = np.array([0, 0])
    world_ripple = (0, 0)

    def load(cell, prev_centre, first):
        r = cell - centre
        if not (np.all(r >= -n // 2) and np.all(r < n // 2)):
            return np.zeros(2)
        pr = cell - prev_centre
        if first and not (np.all(pr >= -n // 2) and np.all(pr < n // 2)):
            return np.zeros(2)
        return store[cell[0] & (n - 1), cell[1] & (n - 1)]

    def scroll(frames, step):
        nonlocal store, centre
        for _ in range(frames):
            prev = centre.copy()
            centre = centre + np.array([step, 0])
            new = np.zeros_like(store)
            lo = centre - n // 2
            for tx in range(n):
                for ty in range(n):
                    t = np.array([tx, ty])
                    cell = lo + ((t - lo) & (n - 1))
                    new[tx, ty] = load(cell, prev, True)
            store = new

    def value_at(cell):
        return store[cell[0] & (n - 1), cell[1] & (n - 1), 0]

    store[0, 0] = [0.2, 0.2]                       # displaced cell at world (0, 0)
    scroll(25, 2)                                  # 50 cells: still inside the half-window (64)
    print(f"after scrolling {centre[0]} cells the world-anchored cell holds {value_at(np.array(world_ripple)):.2f}")
    assert abs(value_at(np.array(world_ripple)) - 0.2) < 1e-6
    entering = centre + np.array([n // 2 - 1, 0])  # just wrapped in from the far edge
    assert value_at(entering) == 0.0
    scroll(10, 2)                                  # 70 cells: the cell has left the window ...
    scroll(35, -2)                                 # ... and when we come back it must be calm
    print(f"after leaving and returning, the cell holds {value_at(np.array(world_ripple)):.2f}")
    assert value_at(np.array(world_ripple)) == 0.0


if __name__ == "__main__":
    test_stability()
    test_splash()
    test_sponge()
    test_wake()
    test_scrolling()
    print("all water sim checks passed")
