"""Mirror of lib/post/bloom_layout.glsl: every bloom level must lie inside the atlas
(0.75 W x 0.5 H, rounded down like Iris' relative image size) and no two levels may overlap.
Run: python -P tools/tests/test_bloom_layout.py"""
import math

LEVELS = 5


def size(w, h, level):
    return max(w >> level, 1), max(h >> level, 1)


def offset(w, h, level):
    if level <= 1:
        return 0, 0
    y = sum(max(h >> k, 1) for k in range(2, level))
    return w >> 1, y


def check(w, h):
    aw, ah = math.floor(w * 0.75), math.floor(h * 0.5)
    rects = []
    for lv in range(1, LEVELS + 1):
        sx, sy = size(w, h, lv)
        ox, oy = offset(w, h, lv)
        assert ox + sx <= aw and oy + sy <= ah, (w, h, lv, ox + sx, aw, oy + sy, ah)
        rects.append((ox, oy, ox + sx, oy + sy))
    for i in range(len(rects)):
        for j in range(i + 1, len(rects)):
            a, b = rects[i], rects[j]
            assert a[2] <= b[0] or b[2] <= a[0] or a[3] <= b[1] or b[3] <= a[1], (w, h, i + 1, j + 1)


if __name__ == "__main__":
    for w, h in [(1280, 720), (1920, 1080), (2560, 1440), (3440, 1440), (3840, 2160), (1366, 768), (1001, 677)]:
        check(w, h)
    print("bloom atlas layout checks passed")
