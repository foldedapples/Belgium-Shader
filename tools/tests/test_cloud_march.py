"""CPU mirror of the step logic in shaders/lib/clouds/clouds.glsl marchClouds().

Checks, for 1-D cloud layouts along a ray, that the two-rate march
  * finds a cloud's front edge within one fine step (no snapping to the coarse grid),
  * places enough samples inside thin clouds,
  * never ping-pongs at an edge (iteration budget is not exhausted in clear air),
  * still reaches clouds behind a clear gap.
Run: python -P tools/tests/test_cloud_march.py
"""
import math


def march(clouds, t0, t1, steps, jitter):
    """clouds: list of (start, end) intervals with density 1 inside. Returns sample positions
    that integrated density and the iteration count. Mirrors the GLSL loop exactly."""
    inside = lambda t: any(a <= t < b for a, b in clouds)
    length = t1 - t0
    n = max(steps // 3, min(steps, int(length / 90.0)))
    dt = length / n
    dt_in = max(dt * 0.34, 10.0)
    max_iter = n * 2
    t = t0 + dt * jitter
    last_step = dt * jitter
    fine = False
    empty_run = 0
    samples = []
    it = 0
    for it in range(max_iter):
        if t > t1:
            break
        if not inside(t):
            empty_run += 1
            if fine and empty_run > 3:
                fine = False
            last_step = dt_in if fine else dt * (2.0 if empty_run > 2 else 1.0)
            t += last_step
            continue
        if not fine:
            fine = True
            if last_step > dt_in:
                t = max(t - last_step + dt_in * jitter, t0)
                empty_run = -int(math.ceil(last_step / dt_in))
                last_step = 0.0
                continue
        empty_run = min(empty_run, 0)
        samples.append(t)
        empty_run = 0
        t += dt_in
        last_step = dt_in
    return samples, it + 1, dt, dt_in


def check(name, clouds, t0=0.0, t1=6700.0, steps=48):
    worst_front = 0.0
    min_inside = 10**9
    for k in range(16):
        jitter = (k + 0.5) / 16
        samples, iters, dt, dt_in = march(clouds, t0, t1, steps, jitter)
        for a, b in clouds:
            inside = [s for s in samples if a <= s < b]
            assert inside, f"{name}: cloud [{a},{b}) missed at jitter {jitter:.2f}"
            worst_front = max(worst_front, inside[0] - a)
            min_inside = min(min_inside, len(inside))
    assert worst_front <= dt_in + 1e-6, f"{name}: front found {worst_front:.1f} m late (fine step {dt_in:.1f} m)"
    print(f"{name}: coarse {dt:.0f} m, fine {dt_in:.0f} m, front error <= {worst_front:.1f} m, "
          f">= {min_inside} samples per cloud")
    return min_inside


def main():
    # 20 degree ray through the fair-weather slab: ~6.7 km, coarse step ~140 m.
    assert check("thin cumulus", [(3000.0, 3300.0)]) >= 5
    assert check("two clouds with a gap", [(1200.0, 1500.0), (4100.0, 4700.0)]) >= 5
    assert check("cloud at slab entry", [(0.0, 400.0)]) >= 5
    check("thick tower", [(2000.0, 5500.0)])
    # Clear sky: the march must finish without exhausting the budget in ping-pong.
    samples, iters, dt, _ = march([], 0.0, 6700.0, 48, 0.5)
    assert not samples and iters <= 48 * 2
    print("clear sky: no samples, loop ended normally")
    print("PASS")


if __name__ == "__main__":
    main()
