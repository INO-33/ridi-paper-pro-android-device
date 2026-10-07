#!/usr/bin/env python3
"""Host checks for the NXP EPDC queue/merge geometry semantics.

This intentionally models only pure rectangle/order logic.  It does not model
waveform physics or claim that a conditional collision sequence occurred on a
device.
"""

import argparse
import json
import random
from dataclasses import dataclass


@dataclass(frozen=True)
class Rect:
    left: int
    top: int
    width: int
    height: int

    @property
    def right(self):
        return self.left + self.width

    @property
    def bottom(self):
        return self.top + self.height

    def contains(self, other):
        return (self.left <= other.left and self.top <= other.top and
                self.right >= other.right and self.bottom >= other.bottom)


def overlaps_or_touches(a, b):
    # Exact half-open arithmetic used by epdc_submit_merge().
    return not (a.left > b.right or b.left > a.right or
                a.top > b.bottom or b.top > a.bottom)


def merge(a, b):
    if not overlaps_or_touches(a, b):
        return None
    left = min(a.left, b.left)
    top = min(a.top, b.top)
    right = max(a.right, b.right)
    bottom = max(a.bottom, b.bottom)
    return Rect(left, top, right - left, bottom - top)


def rotate(rect, xres, yres, rotation):
    if rotation == 0:  # FB_ROTATE_UR
        return rect
    if rotation == 1:  # FB_ROTATE_CW
        return Rect(yres - rect.bottom, rect.left,
                    rect.height, rect.width)
    if rotation == 2:  # FB_ROTATE_UD
        return Rect(xres - rect.right, yres - rect.bottom,
                    rect.width, rect.height)
    if rotation == 3:  # FB_ROTATE_CCW
        return Rect(rect.top, xres - rect.right,
                    rect.height, rect.width)
    raise ValueError(rotation)


def inverse_rotation(rotation):
    return {0: 0, 1: 3, 2: 2, 3: 1}[rotation]


def random_rect(rng, width, height):
    left = rng.randrange(width)
    top = rng.randrange(height)
    return Rect(left, top, rng.randrange(1, width - left + 1),
                rng.randrange(1, height - top + 1))


def run(iterations, seed):
    rng = random.Random(seed)
    merge_containment_failures = 0
    rotation_roundtrip_failures = 0

    for _ in range(iterations):
        a = random_rect(rng, 1404, 1872)
        # Generate both arbitrary and deliberately touching pairs.
        if rng.randrange(2):
            b = random_rect(rng, 1404, 1872)
        else:
            b = Rect(min(a.right, 1403), a.top, 1, a.height)
        combined = merge(a, b)
        if combined is not None and not (combined.contains(a) and
                                         combined.contains(b)):
            merge_containment_failures += 1

        for rotation in range(4):
            rotated = rotate(a, 1404, 1872, rotation)
            if rotation in (1, 3):
                back = rotate(rotated, 1872, 1404,
                              inverse_rotation(rotation))
            else:
                back = rotate(rotated, 1404, 1872,
                              inverse_rotation(rotation))
            if back != a:
                rotation_roundtrip_failures += 1

    # Conditional counterexample for the canonical NXP collision policy:
    # a retried update collides with one older LUT on the left and one newer
    # LUT on the right. Hardware exposes one minimum bounding collision rect.
    # The driver drops that entire rect when *any* colliding LUT is newer,
    # although the newer LUT covers only its right edge.
    retry = Rect(0, 0, 10, 1)
    older_overlap = Rect(0, 0, 2, 1)
    newer_overlap = Rect(8, 0, 2, 1)
    collision_bbox = Rect(0, 0, 10, 1)
    newer_covers_collision_bbox = newer_overlap.contains(collision_bbox)
    conditional_uncovered_pixels = collision_bbox.width - newer_overlap.width

    return {
        "iterations": iterations,
        "seed": seed,
        "merge_containment_failures": merge_containment_failures,
        "rotation_roundtrip_checks": iterations * 4,
        "rotation_roundtrip_failures": rotation_roundtrip_failures,
        "mixed_order_collision_model": {
            "retry": retry.__dict__,
            "older_overlap": older_overlap.__dict__,
            "newer_overlap": newer_overlap.__dict__,
            "hardware_collision_bbox": collision_bbox.__dict__,
            "driver_rule": "drop bbox if any colliding LUT order >= retry order",
            "newer_covers_collision_bbox": newer_covers_collision_bbox,
            "conditionally_uncovered_pixels": conditional_uncovered_pixels,
            "status": "conditional model reproduced; device occurrence unproven",
        },
    }


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--iterations", type=int, default=50000)
    parser.add_argument("--seed", type=int, default=0xE70)
    args = parser.parse_args()
    result = run(args.iterations, args.seed)
    print(json.dumps(result, indent=2, sort_keys=True))
    if result["merge_containment_failures"]:
        raise SystemExit(1)
    if result["rotation_roundtrip_failures"]:
        raise SystemExit(1)


if __name__ == "__main__":
    main()
