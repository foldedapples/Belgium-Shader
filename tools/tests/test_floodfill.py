"""CPU mirror of shaders/program/shadowcomp_floodfill.glsl (wavefront propagation).

Checks on a 3-D grid: light from a level-15 emitter reaches 14 blocks and stops at
level 0 and the field settles in 15 steps; an opaque wall blocks it; hue is preserved while fading; a removed emitter's light is
gone within 15 steps; two differently coloured emitters mix where their light meets.
Run: python -P tools/tests/test_floodfill.py
"""
import numpy as np

N = (40, 8, 40)


def step(L, opaque, emit):
    """One propagation step: per-channel max of the 6 neighbours, lowered one level keeping
    the hue, plus emission; zero in opaque voxels. Out-of-grid neighbours are 0."""
    pad = np.pad(L, ((1, 1), (1, 1), (1, 1), (0, 0)))
    m = np.maximum.reduce([pad[2:, 1:-1, 1:-1], pad[:-2, 1:-1, 1:-1], pad[1:-1, 2:, 1:-1],
                           pad[1:-1, :-2, 1:-1], pad[1:-1, 1:-1, 2:], pad[1:-1, 1:-1, :-2]])
    peak = m.max(axis=-1, keepdims=True)
    with np.errstate(divide="ignore", invalid="ignore"):
        lowered = np.where(peak > 1 / 15, m * ((peak - 1 / 15) / np.maximum(peak, 1e-9)), 0.0)
    out = np.maximum(lowered, emit)
    out[opaque] = np.where(emit[opaque] > 0, emit[opaque], 0.0)
    return out


def run(steps, L, opaque, emit):
    for _ in range(steps):
        L = step(L, opaque, emit)
    return L


def main():
    L = np.zeros(N + (3,))
    opaque = np.zeros(N, bool)
    emit = np.zeros(N + (3,))
    torch = np.array([1.0, 0.55, 0.2])          # warm emitter colour (max component 1)
    emit[10, 4, 20] = torch                     # level 15
    L = run(20, L, opaque, emit)
    # Reach: 14 blocks away still lit (level 1), 15 blocks away dark (level 0), like vanilla.
    assert L[24, 4, 20].max() > 0.06 and L[25, 4, 20].max() < 1e-6, (L[24, 4, 20], L[25, 4, 20])
    # Hue preserved while fading.
    c = L[18, 4, 20]
    assert np.allclose(c / c.max(), torch, atol=1e-6)
    # Settles fast: distance d lights at step d + 1, so 15 steps give the final field.
    L14 = run(15, np.zeros_like(L), opaque, emit)
    assert np.allclose(L14, L, atol=1e-9)
    print("reach 14 blocks, settled after 15 steps (5 frames at 3 steps), hue preserved: ok")

    # Wall: a full opaque slab at x = 14 blocks light behind it.
    opaque2 = np.zeros(N, bool); opaque2[14, :, :] = True
    Lw = run(20, np.zeros_like(L), opaque2, emit)
    assert Lw[16, 4, 20].max() < 1e-6
    print("opaque wall blocks light: ok")

    # Removal: light disappears within 15 steps (wavefront counts down).
    Lr = run(15, L, opaque, np.zeros_like(emit))
    assert Lr.max() < 1e-6, Lr.max()
    print("removed emitter dark after 15 steps: ok")

    # Two colours mix where they meet.
    emit2 = emit.copy(); emit2[30, 4, 20] = np.array([0.2, 0.5, 1.0])
    Lm = run(20, np.zeros_like(L), opaque, emit2)
    mid = Lm[20, 4, 20]
    assert mid[0] > 0.1 and mid[2] > 0.1
    print("two colours mix between emitters:", np.round(mid / mid.max(), 2))
    print("PASS")


if __name__ == "__main__":
    main()
