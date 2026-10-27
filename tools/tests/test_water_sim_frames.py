"""Reference test for the interactive-water inputs (program/prepare/water_sim.csh).

Iris facts used (Iris 1.21.11 source, IrisExclusiveUniforms / CameraUniforms):
  relativeEyePosition     = camera (unshifted) - eye
  relativeVehiclePosition = camera (unshifted) - vehicle
  cameraPositionInt/Fract = floor / fractional part of the unshifted camera position
  cameraPosition          = unshifted + a shift (multiples of 30000) once |x| or |z| > 30000

Checks that
1. the water plane is the surface the body is in, for a floating, swimming and boating player
   (the old estimate was one block low when floating);
2. the vehicle position is camera - relativeVehiclePosition (the old code added it);
3. cells built from cameraPositionInt/Fract are exact and the body lands in the right cell even
   when cameraPosition is shifted (the old code mixed shifted and unshifted positions).

    python -P tools/tests/test_water_sim_frames.py
"""

import math

TOP = 0.889
CPB = 4                     # cells per block


def old_plane(eye_y, swimming):
    feet = eye_y - (0.4 if swimming else 1.62)
    return math.floor(feet + 0.3) + TOP


def new_plane_fallback(eye_y):
    return math.floor(eye_y - 0.5) + TOP


def test_plane():
    surface_block = 62
    surface = surface_block + TOP
    worst_old = 0.0
    for eye_above in (0.1, 0.25, 0.4):                 # floating / treading water
        eye = surface + eye_above
        assert abs(new_plane_fallback(eye) - surface) < 1e-9
        worst_old = max(worst_old, abs(old_plane(eye, False) - surface))
    for eye_below in (0.0, -0.2, -0.35):               # swimming just under the surface
        eye = surface + eye_below
        assert abs(new_plane_fallback(eye) - surface) < 1e-9
    print(f"plane: fallback estimate exact for floating and swimming players; old estimate was off by {worst_old:.0f} block")
    assert worst_old == 1.0


def test_vehicle_sign():
    camera = (100.3, 70.2, -40.7)
    vehicle = (98.0, 62.85, -44.1)
    rel = tuple(c - v for c, v in zip(camera, vehicle))           # Iris definition
    new = tuple(c - r for c, r in zip(camera, rel))
    old = tuple(c + r for c, r in zip(camera, rel))
    assert all(abs(n - v) < 1e-9 for n, v in zip(new, vehicle))
    err = math.dist(old, vehicle)
    print(f"vehicle: camera - relativeVehiclePosition is exact; the old camera + relative was {err:.1f} blocks off")
    assert err > 1.0


def cell_exact(cam_unshifted, rel_xz):
    ci = math.floor(cam_unshifted)
    cf = cam_unshifted - ci
    camera_cell = ci * CPB + math.floor(cf * CPB)
    local = (cf * CPB - math.floor(cf * CPB)) + rel_xz * CPB
    return camera_cell + math.floor(local)


def test_cells_under_shift():
    for cam in (12.37, -0.6, -12345.81, 31234.4, -987654.3):
        shift = 0.0 if abs(cam) <= 30000 else -(cam - math.fmod(cam, 30000))
        eye = cam - 2.3                               # player 2.3 blocks from the camera
        rel_eye = cam - eye                           # relativeEyePosition (unshifted)
        new = cell_exact(cam, -rel_eye)
        truth = math.floor(eye * CPB)
        assert new == truth, (cam, new, truth)
        # Old: grid centred on the shifted cameraPosition, body from the unshifted eyePosition.
        grid_origin = math.floor((cam + shift) * CPB)
        body = math.floor(eye * CPB)
        if shift:
            assert abs(body - grid_origin) > 1000, "old frames disagree beyond 30000"
    print("cells: exact integer cells match the body's true cell at all coordinates, shifted or not")


if __name__ == "__main__":
    test_plane()
    test_vehicle_sign()
    test_cells_under_shift()
    print("OK")
