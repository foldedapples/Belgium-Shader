"""Reference test for rain-ripple coordinates (lib/weather/ripples.glsl).

1. wrapInt matches a true modulo for negative and positive integers (GLSL % is undefined for
   negatives).
2. The wrapped coordinate is exactly periodic: a camera one RIPPLE_PERIOD further on sees the
   same cells (cell index shifts by a whole number of wrapped cells for both layers).
3. Precision: far from the origin, float32 camera + offset loses a visible fraction of the
   ripple wavelength; the wrapped coordinate does not.

    python -P tools/tests/test_ripple_precision.py
"""

import numpy as np

PERIOD = 1536
LAYERS = ((0.5, 3072, 0.0), (0.375, 4096, 3.7))
WAVELENGTH = 2 * np.pi / 26.0


def wrap_int(a, n):
    """Transcription of wrapInt() using only operations GLSL defines for non-negative operands."""
    if a >= 0:
        return a - (a // n) * n
    m = -a - 1
    return n - 1 - (m - (m // n) * n)


def ripple_coord(cam, offset):
    ci = int(np.floor(cam))
    cf = np.float32(cam - ci)
    return np.float32(wrap_int(ci, PERIOD)) + cf + np.float32(offset)


def test_wrap():
    for a in range(-5000, 5000, 7):
        for n in (PERIOD, 3072, 4096):
            assert wrap_int(a, n) == a % n, (a, n)
    print("wrapInt: matches modulo for negative and positive values")


def test_periodic():
    rng = np.random.default_rng(3)
    for _ in range(2000):
        cam = rng.uniform(-3e4, 3e4)
        off = rng.uniform(-200, 200)
        for size, cells, shift in LAYERS:
            c0 = int(np.floor((ripple_coord(cam, off) + np.float32(shift)) / np.float32(size)))
            c1 = int(np.floor((ripple_coord(cam + PERIOD, off) + np.float32(shift)) / np.float32(size)))
            assert wrap_int(c0, cells) == wrap_int(c1, cells), (cam, off, size)
    print("periodicity: identical cells one period apart, both layers")


def test_precision():
    rng = np.random.default_rng(4)
    for cam_mag in (3e4, 1e6):
        worst_plain = worst_wrapped = 0.0
        for _ in range(4000):
            cam = cam_mag + rng.uniform(0, 1000)
            off = rng.uniform(-50, 50)
            exact = cam + off
            plain = float(np.float32(np.float32(cam) + np.float32(off)))
            wrapped = float(ripple_coord(cam, off))
            worst_plain = max(worst_plain, abs(plain - exact))
            worst_wrapped = max(worst_wrapped, abs((wrapped - exact + PERIOD / 2) % PERIOD - PERIOD / 2))
        print(f"x~{cam_mag:.0e}: plain float error up to {worst_plain:.1e} block "
              f"({100 * worst_plain / WAVELENGTH:.1f} % of a wavelength), wrapped {worst_wrapped:.1e}")
        assert worst_wrapped < 2e-4
    assert worst_plain / WAVELENGTH > 0.05


if __name__ == "__main__":
    test_wrap()
    test_periodic()
    test_precision()
    print("OK")
