"""Reference of program/setup_blackhole.glsl: checks the capture threshold (b_c = 3*sqrt(3)/2)
and the weak-field deflection limit 2 r_s / b. Run: python -P tools/tests/test_black_hole.py"""
import math

BC = 3 * math.sqrt(3) / 2
PHI_MAX = 4 * math.pi


def deriv(u, du):
    return du, 1.5 * u * u - u


def rk4(u, du, h):
    a1, b1 = deriv(u, du)
    a2, b2 = deriv(u + 0.5 * h * a1, du + 0.5 * h * b1)
    a3, b3 = deriv(u + 0.5 * h * a2, du + 0.5 * h * b2)
    a4, b4 = deriv(u + h * a3, du + h * b3)
    return u + h / 6 * (a1 + 2 * a2 + 2 * a3 + a4), du + h / 6 * (b1 + 2 * b2 + 2 * b3 + b4)


def trace(b, D=1e6, rows=255, sub=24):
    u = 1 / D
    du = math.sqrt(max(1 / b ** 2 - u * u * (1 - u), 0))
    h = PHI_MAX / ((rows - 1) * sub)
    phi = 0.0
    for _ in range((rows - 1) * sub):
        nu, ndu = rk4(u, du, h)
        if nu <= 0:
            return "escape", phi + h * u / (u - nu)
        if nu >= 1:
            return "capture", phi + h
        u, du, phi = nu, ndu, phi + h
    return "orbit", phi


if __name__ == "__main__":
    for b in (BC * 0.999, BC * 1.001):
        kind, _ = trace(b)
        print(f"b = {b:.5f}: {kind}")
    assert trace(BC * 0.995)[0] == "capture" and trace(BC * 1.005)[0] == "escape"
    for b in (50.0, 200.0):
        kind, phi_end = trace(b)
        # From very far away, flat space would sweep pi; the excess is the deflection.
        deflection = phi_end - math.pi
        print(f"b = {b}: deflection {deflection:.5f} rad vs weak-field {2 / b:.5f}")
        assert abs(deflection - 2 / b) / (2 / b) < 0.05
    kind, phi_end = trace(BC * 1.0005)
    print(f"near-critical ray winds {phi_end / (2 * math.pi):.2f} turns before escaping")
    print("black hole geodesic checks passed")
