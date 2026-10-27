"""Reference test: water wave speed must not depend on where the water (or the camera) is.

The apparent temporal frequency of a wave at a fixed world point is d(phase)/dt. For a train
with phase k(t) . x - omega t it is -omega + x . dk/dt: if the wave vector changes over time, the
waves run faster the further they are from the coordinate origin. This compares, for the
shortest train (0.55-block wavelength), the old model (lib/water/waves.glsl before 2026-10-27:
trains rotated with the wind, long wavelengths and river flow tied to the player's smoothed
biome) with the new one (fixed lattice wave vectors, amplitude-only weather, bounded advection).

    python -P tools/tests/test_wave_speed.py
"""

import numpy as np

G = 9.81
TICKS_PER_S = 20.0
WRAP = 1536
LATTICE = 2 * np.pi / WRAP


def wind_angle(world_ticks):
    """windDirection() angle (lib/common/wind.glsl), worldDay fixed."""
    return 0.6 + 0.35 * np.sin(1.7 * 3 + world_ticks * 2.6e-4)


def omega(k):
    cyc = 2 * np.pi / 3600
    return max(round(np.sqrt(G * k) / cyc), 1) * cyc


def old_phase(x, t, river):
    """Old model, train 11 (shortest): direction = wind rotated by a fixed angle; position
    advected by flow * t with flow = wind * 0.35 * biomeRiver."""
    k = 2 * np.pi / 0.55
    a = wind_angle(t * TICKS_PER_S) + 0.4
    d = np.array([np.cos(a), np.sin(a)])
    w = np.array([np.cos(a - 0.4), np.sin(a - 0.4)])
    pos = x - w * 0.35 * river(t) * t
    return k * d.dot(pos) - omega(k) * t


def new_phase(x, t, river):
    """New model, train 15: fixed lattice vector, exact wrapped coordinate; weather and biome
    only change amplitudes, so they do not enter the phase."""
    lam = 46.0 * (0.55 / 46.0) ** (15 / 15)
    ang = 15 * 2.399963 + 0.5
    kv = np.round(np.array([np.cos(ang), np.sin(ang)]) * (2 * np.pi / lam) / LATTICE) * LATTICE
    xw = np.mod(x, WRAP)
    return kv.dot(xw) - omega(np.linalg.norm(kv)) * t


def apparent_frequency(phase, x, t, river, dt=0.05):
    return (phase(x, t + dt, river) - phase(x, t - dt, river)) / (2 * dt)


def main():
    no_river = lambda t: 0.0
    # Walking into a river biome at t = 3000 s: biomeRiver ramps 0 -> 1 over ~120 s.
    entering_river = lambda t: float(np.clip((t - 3000.0) / 120.0, 0.0, 1.0))
    k = 2 * np.pi / 0.55
    true_omega = omega(k)
    print(f"shortest train: true angular frequency {true_omega:.2f} rad/s")
    for label, river in (("calm weather, no biome change", no_river), ("entering a river biome", entering_river)):
        print(label)
        for xs in (0.0, 1000.0, 10000.0):
            x = np.array([xs, xs * 0.6])
            f_old = abs(apparent_frequency(old_phase, x, 3060.0, river))
            f_new = abs(apparent_frequency(new_phase, x, 3060.0, river))
            print(f"  |x| ~ {np.linalg.norm(x):7.0f}: old {f_old:8.2f} rad/s   new {f_new:6.2f} rad/s")
            assert abs(f_new - omega(np.linalg.norm(
                np.round(np.array([np.cos(15 * 2.399963 + 0.5), np.sin(15 * 2.399963 + 0.5)]) * k / LATTICE) * LATTICE))) < 1e-3
        # The old model is badly wrong somewhere in each scenario (errors partly cancel at some points).
        worst = max(abs(abs(apparent_frequency(old_phase, np.array([s, s * 0.6]), 3060.0, river)) - true_omega)
                    for s in (0.0, 1000.0, 10000.0))
        assert worst > 2 * true_omega, worst
    print("OK: new wave frequency is the same everywhere; the old one grew with distance and biome")


if __name__ == "__main__":
    main()
