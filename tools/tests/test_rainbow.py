"""Reference test for the rainbow geometry (lib/sky/sky.glsl, rainbowAngle).

Minimum-deviation angles from the antisolar point for water with the Cauchy fit
n = 1.3242 + 3080 / lambda^2 must match the observed bows: primary red ~42.3 deg, violet ~40.6 deg;
secondary red ~50.3 deg, violet ~53.6 deg (colours reversed), with Alexander's dark band between.

    python -P tools/tests/test_rainbow.py
"""

import math


def rainbow_angle(lam, secondary):
    n = 1.3242 + 3080.0 / lam ** 2
    cos_i = math.sqrt((n * n - 1.0) / (8.0 if secondary else 3.0))
    i = math.acos(cos_i)
    r = math.asin(math.sin(i) / n)
    return math.degrees(math.pi - (6 * r - 2 * i) if secondary else 4 * r - 2 * i)


if __name__ == "__main__":
    p_red, p_violet = rainbow_angle(700, False), rainbow_angle(400, False)
    s_red, s_violet = rainbow_angle(700, True), rainbow_angle(400, True)
    print(f"primary: red {p_red:.2f} deg, violet {p_violet:.2f} deg")
    print(f"secondary: red {s_red:.2f} deg, violet {s_violet:.2f} deg")
    assert 41.9 < p_red < 42.6 and 40.3 < p_violet < 41.0 and p_red > p_violet
    assert 49.8 < s_red < 51.0 and 52.8 < s_violet < 54.3 and s_violet > s_red   # reversed order
    assert s_red - p_red > 7.0                                                    # dark band width
    print("OK")
