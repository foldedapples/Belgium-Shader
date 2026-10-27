"""Reference test for the water simulation's bookkeeping (program/prepare/water_sim.csh, SIM_BOOKKEEPING):
sleeping, frame-rate independence and the water-entry splash state machine.

A frame-by-frame model of the GLSL logic (same constants and order of operations):
1. After the player leaves the water or the boat, the field keeps stepping at 60 Hz for as long as
   it moves, at any frame rate. (The previous version cleared the "still moving" flag on every
   frame; above 60 FPS most frames have no step, so it fell asleep at once and ripples froze.)
2. A jump into water gives exactly one splash, also when the entry frame has no step.
3. No splash while bobbing at the surface, standing still, hopping without touching water, or
   riding a boat.
4. Splash strength grows with entry speed and stays bounded.

    python -P tools/tests/test_water_sim_events.py
"""

import math

SIM_DT = 1.0 / 60.0


def smoothstep(e0, e1, x):
    t = min(max((x - e0) / (e1 - e0), 0.0), 1.0)
    return t * t * (3 - 2 * t)


class Bookkeeping:
    def __init__(self):
        self.acc = 0.0
        self.moving = 0          # simFlags.x
        self.dry_ms = 0          # simFlags.z
        self.pending = 0         # simFlags.w
        self.splashes = []       # amplitudes applied by step 0

    def frame(self, dt, feet_in, riding_in_water, riding, vy, field_moves=True):
        dt = min(max(dt, 0.0), 0.1)
        dry, pending = self.dry_ms, self.pending
        if feet_in:
            if dry >= 150 and not riding:
                amp = 0.85 * (1 - math.exp(-vy / 9.0)) * smoothstep(1.5, 4.0, vy)
                pending = max(pending, int(amp * 1000))
            dry = 0
        else:
            dry = min(dry + int(dt * 1000 + 0.5), 1000000)
        body = feet_in or riding_in_water
        awake = body or pending > 0 or self.moving != 0
        acc = self.acc + dt if awake else 0.0
        steps = min(int(acc / SIM_DT), 4)
        acc = min(acc - steps * SIM_DT, SIM_DT)
        self.acc = acc
        self.moving = 0 if steps > 0 else self.moving
        self.dry_ms = dry
        self.pending = 0 if steps > 0 else pending
        if steps > 0:
            if pending > 0:
                self.splashes.append(pending / 1000.0)
            if field_moves:
                self.moving = 1          # a step found cells still moving
        return steps


def test_keeps_stepping_after_leaving():
    for fps in (30, 60, 144, 240):
        b = Bookkeeping()
        for _ in range(int(fps * 2)):                 # 2 s in a boat
            b.frame(1 / fps, False, True, True, 0.0)
        steps = sum(b.frame(1 / fps, False, False, False, 0.0) for _ in range(int(fps * 3)))   # 3 s after
        assert abs(steps / 3.0 - 60.0) < 2.0, (fps, steps)
    print("after leaving the boat: 60 steps/s at 30, 60, 144 and 240 FPS (old logic: 0 above 60 FPS)")


def test_one_splash_per_entry():
    for fps in (30, 60, 144, 240):
        b = Bookkeeping()
        for _ in range(fps):                          # 1 s dry (falling)
            b.frame(1 / fps, False, False, False, 0.0)
        b.frame(1 / fps, True, False, False, 8.0)     # entry at 8 blocks/s
        for _ in range(fps * 2):                      # 2 s in the water, slow
            b.frame(1 / fps, True, False, False, 0.3)
        assert len(b.splashes) == 1, (fps, b.splashes)
    print("jump in: exactly one splash per entry at every frame rate")


def test_no_false_splashes():
    fps = 144
    b = Bookkeeping()
    for i in range(fps * 5):                          # bobbing: feet flicker in and out every 3 frames
        b.frame(1 / fps, (i // 3) % 2 == 0, False, False, 2.5)
    assert not b.splashes, b.splashes
    b = Bookkeeping()
    for _ in range(fps * 5):                          # standing in water
        b.frame(1 / fps, True, False, False, 0.0)
    for _ in range(fps):                              # hop that never touches the water
        b.frame(1 / fps, False, False, False, 4.0)
    for _ in range(fps):                              # riding a boat into the water
        b.frame(1 / fps, True, True, True, 6.0)
    assert not b.splashes, b.splashes
    print("no splash from bobbing, standing still, hopping above water or riding")


def test_strength_bounded():
    amps = []
    for vy in (2.0, 5.0, 8.0, 12.0, 20.0, 60.0):
        b = Bookkeeping()
        for _ in range(60):
            b.frame(1 / 60, False, False, False, 0.0)
        b.frame(1 / 60, True, False, False, vy)
        b.frame(1 / 60, True, False, False, 0.0)
        amps.append(b.splashes[0] if b.splashes else 0.0)
    assert all(a < b2 + 1e-9 for a, b2 in zip(amps, amps[1:])) and amps[-1] <= 0.85
    print("splash amplitude (blocks) for 2 / 5 / 8 / 12 / 20 / 60 blocks/s: "
          + " / ".join(f"{a:.2f}" for a in amps))


if __name__ == "__main__":
    test_keeps_stepping_after_leaving()
    test_one_splash_per_entry()
    test_no_false_splashes()
    test_strength_bounded()
    print("OK")
