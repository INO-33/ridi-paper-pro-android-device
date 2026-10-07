#!/usr/bin/env python3
"""Host-side E70Q10 partial-update replay and rectangle diagnostics.

The visible Android framebuffer is 1404x1872.  The kernel exposes it in that
portrait orientation and rotates update rectangles CCW into the 1872x1404
panel coordinate space.  Panel storage in this tool deliberately has a
1888-pixel pitch so width and pitch cannot accidentally be interchanged.

This is an observation/test tool.  It does not choose waveforms and it does not
change device behavior.
"""

from __future__ import annotations

import argparse
import json
import random
import re
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Iterable, Sequence

try:
    from PIL import Image, ImageDraw
except ImportError as exc:  # pragma: no cover - host setup failure
    raise SystemExit("Pillow is required (python3-pil): %s" % exc)


LOGICAL_WIDTH = 1404
LOGICAL_HEIGHT = 1872
LOGICAL_STRIDE = 1408
PHYSICAL_WIDTH = 1872
PHYSICAL_HEIGHT = 1404
PHYSICAL_STRIDE = 1888
ALIGNMENT = 8


@dataclass(frozen=True)
class Rect:
    left: int
    top: int
    width: int
    height: int

    @property
    def right(self) -> int:
        return self.left + self.width

    @property
    def bottom(self) -> int:
        return self.top + self.height

    def as_list(self) -> list[int]:
        return [self.left, self.top, self.width, self.height]


def rect_from(value: Sequence[int]) -> Rect:
    if len(value) != 4:
        raise ValueError("rectangle must be [left, top, width, height]")
    return Rect(*(int(part) for part in value))


def clip(rect: Rect, width: int, height: int) -> Rect:
    left = max(0, min(width, rect.left))
    top = max(0, min(height, rect.top))
    right = max(left, min(width, rect.right))
    bottom = max(top, min(height, rect.bottom))
    return Rect(left, top, right - left, bottom - top)


def align_outward(rect: Rect, width: int = LOGICAL_WIDTH,
                  height: int = LOGICAL_HEIGHT,
                  alignment: int = ALIGNMENT) -> Rect:
    """Mirror framebuffer.cpp: floor origin, ceil end, then visible clip."""
    rect = clip(rect, width, height)
    left = (rect.left // alignment) * alignment
    top = (rect.top // alignment) * alignment
    right = min(width, ((rect.right + alignment - 1) // alignment) * alignment)
    bottom = min(height, ((rect.bottom + alignment - 1) // alignment) * alignment)
    return Rect(left, top, right - left, bottom - top)


def align_floor_end_bug(rect: Rect, width: int = LOGICAL_WIDTH,
                        height: int = LOGICAL_HEIGHT,
                        alignment: int = ALIGNMENT) -> Rect:
    """Deliberately wrong regression model: floors the exclusive end."""
    rect = clip(rect, width, height)
    left = (rect.left // alignment) * alignment
    top = (rect.top // alignment) * alignment
    right = min(width, (rect.right // alignment) * alignment)
    bottom = min(height, (rect.bottom // alignment) * alignment)
    return Rect(left, top, max(0, right - left), max(0, bottom - top))


def rotate_ccw(rect: Rect, logical_width: int = LOGICAL_WIDTH) -> Rect:
    """Mirror mxc_epdc_fb.c adjust_coordinates(FB_ROTATE_CCW)."""
    return Rect(rect.top, logical_width - rect.right,
                rect.height, rect.width)


def contains(outer: Rect, inner: Rect) -> bool:
    return (outer.left <= inner.left and outer.top <= inner.top and
            outer.right >= inner.right and outer.bottom >= inner.bottom)


def logical_pixel_to_physical(x: int, y: int) -> tuple[int, int]:
    return y, LOGICAL_WIDTH - 1 - x


def kernel_layout(rect: Rect) -> dict[str, object]:
    """Model the current i.MX6SL PxP math for a CCW RGB565 update."""
    pxp_width = ((rect.width + 7) // 8) * 8
    pxp_height = ((rect.height + 7) // 8) * 8
    width_pxp_blocks = pxp_height
    post_rotation_x = 0
    post_rotation_y = pxp_width - rect.width
    epdc_offset = post_rotation_y * width_pxp_blocks + post_rotation_x
    source_offset = (rect.top * LOGICAL_STRIDE + rect.left) * 2
    return {
        "logical": rect.as_list(),
        "rotated": rotate_ccw(rect).as_list(),
        "source_offset_bytes": source_offset,
        "source_pitch_bytes": LOGICAL_STRIDE * 2,
        "pxp_source": [0, 0, pxp_width, pxp_height],
        "pxp_output": [post_rotation_x, post_rotation_y,
                       width_pxp_blocks, pxp_width],
        "epdc_offset_bytes": epdc_offset,
        "epdc_stride_bytes": width_pxp_blocks,
    }


class Replay:
    def __init__(self, panel_initial: int = 255) -> None:
        self.logical = bytearray([panel_initial]) * (LOGICAL_STRIDE * LOGICAL_HEIGHT)
        self.panel = bytearray([panel_initial]) * (PHYSICAL_STRIDE * PHYSICAL_HEIGHT)
        self.update_rects: list[Rect] = []

    def fill_logical(self, rect: Rect, gray: int) -> None:
        rect = clip(rect, LOGICAL_WIDTH, LOGICAL_HEIGHT)
        gray = max(0, min(255, int(gray)))
        row = bytes([gray]) * rect.width
        for y in range(rect.top, rect.bottom):
            offset = y * LOGICAL_STRIDE + rect.left
            self.logical[offset:offset + rect.width] = row

    def snapshot(self) -> bytearray:
        return bytearray(self.logical)

    def submit(self, rect: Rect, source: bytearray | None = None) -> None:
        source = self.logical if source is None else source
        rect = clip(rect, LOGICAL_WIDTH, LOGICAL_HEIGHT)
        if rect.width <= 0 or rect.height <= 0:
            return
        self.update_rects.append(rotate_ccw(rect))
        for y in range(rect.top, rect.bottom):
            src_row = y * LOGICAL_STRIDE
            for x in range(rect.left, rect.right):
                physical_x, physical_y = logical_pixel_to_physical(x, y)
                self.panel[physical_y * PHYSICAL_STRIDE + physical_x] = source[src_row + x]

    def expected_physical(self, source: bytearray | None = None) -> bytearray:
        source = self.logical if source is None else source
        result = bytearray([255]) * (PHYSICAL_STRIDE * PHYSICAL_HEIGHT)
        for y in range(LOGICAL_HEIGHT):
            src_row = y * LOGICAL_STRIDE
            for x in range(LOGICAL_WIDTH):
                physical_x, physical_y = logical_pixel_to_physical(x, y)
                result[physical_y * PHYSICAL_STRIDE + physical_x] = source[src_row + x]
        return result


def visible_image(buffer: bytearray) -> Image.Image:
    packed = bytearray(PHYSICAL_WIDTH * PHYSICAL_HEIGHT)
    for y in range(PHYSICAL_HEIGHT):
        source = y * PHYSICAL_STRIDE
        target = y * PHYSICAL_WIDTH
        packed[target:target + PHYSICAL_WIDTH] = buffer[source:source + PHYSICAL_WIDTH]
    return Image.frombytes("L", (PHYSICAL_WIDTH, PHYSICAL_HEIGHT), bytes(packed))


def save_outputs(output_dir: Path, replay: Replay, expected_source: bytearray,
                 metadata: dict[str, object]) -> int:
    output_dir.mkdir(parents=True, exist_ok=True)
    expected = replay.expected_physical(expected_source)
    expected_image = visible_image(expected)
    panel_image = visible_image(replay.panel)
    expected_image.save(output_dir / "expected_frame.png")
    panel_image.save(output_dir / "simulated_panel.png")

    difference = Image.new("RGB", expected_image.size, "white")
    diff_pixels = difference.load()
    expected_pixels = expected_image.load()
    panel_pixels = panel_image.load()
    mismatch_count = 0
    for y in range(PHYSICAL_HEIGHT):
        for x in range(PHYSICAL_WIDTH):
            if expected_pixels[x, y] != panel_pixels[x, y]:
                mismatch_count += 1
                # Red is stale/different; intensity retains direction information.
                diff_pixels[x, y] = (255, min(expected_pixels[x, y], 180),
                                     min(panel_pixels[x, y], 180))
    difference.save(output_dir / "missing_or_stale_pixels.png")

    overlay = expected_image.convert("RGB")
    draw = ImageDraw.Draw(overlay)
    colors = ("red", "blue", "green", "magenta", "orange", "cyan")
    for index, rect in enumerate(replay.update_rects):
        if rect.width and rect.height:
            draw.rectangle((rect.left, rect.top, rect.right - 1, rect.bottom - 1),
                           outline=colors[index % len(colors)], width=2)
    overlay.save(output_dir / "update_rect_overlay.png")

    metadata = dict(metadata)
    metadata["mismatch_pixels"] = mismatch_count
    metadata["geometry"] = {
        "logical": [LOGICAL_WIDTH, LOGICAL_HEIGHT],
        "logical_stride": LOGICAL_STRIDE,
        "physical": [PHYSICAL_WIDTH, PHYSICAL_HEIGHT],
        "physical_stride": PHYSICAL_STRIDE,
    }
    (output_dir / "replay_result.json").write_text(
        json.dumps(metadata, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    return mismatch_count


def run_json_scenario(path: Path, output_dir: Path) -> int:
    scenario = json.loads(path.read_text(encoding="utf-8"))
    replay = Replay(int(scenario.get("panel_initial", 255)))
    for operation in scenario.get("initial_draw", []):
        replay.fill_logical(rect_from(operation["rect"]), operation["gray"])
    for event in scenario.get("events", []):
        for operation in event.get("draw", []):
            replay.fill_logical(rect_from(operation["rect"]), operation["gray"])
        for value in event.get("update_rects", []):
            replay.submit(rect_from(value))
    expected = replay.snapshot()
    mismatch = save_outputs(output_dir, replay, expected,
                            {"scenario": str(path), "events": scenario.get("events", [])})
    print("REPLAY %s mismatch_pixels=%d output=%s" %
          ("PASS" if mismatch == 0 else "STALE", mismatch, output_dir))
    return 0


def run_demo(output_dir: Path) -> int:
    # 1) Correct current outward alignment: black -> white at the top-panel edge.
    correct = Replay(255)
    edge = Rect(LOGICAL_WIDTH - 1, 0, 1, 16)
    correct.fill_logical(edge, 0)
    correct.submit(align_outward(edge))
    correct.fill_logical(edge, 255)
    correct.submit(align_outward(edge))
    correct_expected = correct.snapshot()
    correct_mismatch = save_outputs(output_dir / "current_alignment", correct,
                                    correct_expected,
                                    {"case": "current_outward_alignment"})

    # 2) Deliberately floor the exclusive edge. This reproduces a stale black dot.
    floor_bug = Replay(255)
    floor_bug.fill_logical(edge, 0)
    floor_bug.submit(align_outward(edge))
    floor_bug.fill_logical(edge, 255)
    floor_bug.submit(align_floor_end_bug(edge))
    floor_expected = floor_bug.snapshot()
    floor_mismatch = save_outputs(output_dir / "floor_end_regression", floor_bug,
                                  floor_expected,
                                  {"case": "exclusive_end_floor_regression"})

    # 3) SEND queues page N, shadow records it, HWC releases it, then the same
    # page is reused before deferred PxP reads it. The panel receives different
    # bytes from the userspace shadow/expected frame.
    reuse = Replay(255)
    line = Rect(LOGICAL_WIDTH - 1, 100, 1, 800)
    reuse.fill_logical(line, 0)
    queued_snapshot = reuse.snapshot()
    submitted = align_outward(line)
    reuse.fill_logical(line, 255)  # simulated framebuffer-page reuse
    reuse.submit(submitted, source=reuse.logical)
    reuse_mismatch = save_outputs(output_dir / "deferred_page_reuse", reuse,
                                  queued_snapshot,
                                  {"case": "deferred_pxp_source_page_reuse",
                                   "submitted": submitted.as_list()})

    print("DEMO current_alignment=%d floor_end_regression=%d "
          "deferred_page_reuse=%d output=%s" %
          (correct_mismatch, floor_mismatch, reuse_mismatch, output_dir))
    return 0


def interesting_axis(limit: int) -> list[int]:
    values = {0, 1, 7, 8, 9, limit - 1, limit - 2,
              limit - 7, limit - 8, limit - 9}
    return sorted(value for value in values if 0 <= value < limit)


def fuzz(iterations: int, seed: int) -> int:
    rng = random.Random(seed)
    widths = [1, 2, 7, 8, 9, LOGICAL_WIDTH]
    heights = [1, 2, 7, 8, 9, LOGICAL_HEIGHT]
    cases: list[Rect] = []
    for x in interesting_axis(LOGICAL_WIDTH):
        for y in interesting_axis(LOGICAL_HEIGHT):
            for width in widths:
                for height in heights:
                    cases.append(Rect(x, y, min(width, LOGICAL_WIDTH - x),
                                      min(height, LOGICAL_HEIGHT - y)))
    for _ in range(iterations):
        left = rng.randrange(LOGICAL_WIDTH)
        top = rng.randrange(LOGICAL_HEIGHT)
        cases.append(Rect(left, top, rng.randint(1, LOGICAL_WIDTH - left),
                          rng.randint(1, LOGICAL_HEIGHT - top)))

    failures: list[dict[str, object]] = []
    floor_failures = 0
    for original in cases:
        aligned = align_outward(original)
        rotated_original = rotate_ccw(original)
        rotated_aligned = rotate_ccw(aligned)
        if not contains(aligned, original) or not contains(rotated_aligned, rotated_original):
            failures.append({"original": original.as_list(),
                             "aligned": aligned.as_list(),
                             "rotated_original": rotated_original.as_list(),
                             "rotated_aligned": rotated_aligned.as_list()})
        bad = align_floor_end_bug(original)
        if not contains(bad, original):
            floor_failures += 1
        layout = kernel_layout(aligned)
        rotated = rect_from(layout["rotated"])
        if (rotated.left < 0 or rotated.top < 0 or
                rotated.right > PHYSICAL_WIDTH or rotated.bottom > PHYSICAL_HEIGHT):
            failures.append({"original": original.as_list(),
                             "reason": "rotated_out_of_bounds", "layout": layout})
        # Validate the exact ROT_270 output offset used by the current kernel.
        # PxP writes desired source columns after any right-side padding, and
        # epdc_offs skips those padding rows. Every source corner must therefore
        # land at the same relative coordinate as adjust_coordinates().
        pxp_width = ((aligned.width + 7) // 8) * 8
        pxp_stride = ((aligned.height + 7) // 8) * 8
        epdc_offset = (pxp_width - aligned.width) * pxp_stride
        for x, y in ((aligned.left, aligned.top),
                     (aligned.right - 1, aligned.top),
                     (aligned.left, aligned.bottom - 1),
                     (aligned.right - 1, aligned.bottom - 1)):
            dx = x - aligned.left
            dy = y - aligned.top
            pxp_index = (pxp_width - 1 - dx) * pxp_stride + dy
            relative = pxp_index - epdc_offset
            actual_x = relative % pxp_stride
            actual_y = relative // pxp_stride
            expected_x = y - aligned.top
            expected_y = aligned.right - 1 - x
            if (actual_x, actual_y) != (expected_x, expected_y):
                failures.append({"original": original.as_list(),
                                 "reason": "pxp_offset_mapping",
                                 "actual": [actual_x, actual_y],
                                 "expected": [expected_x, expected_y],
                                 "layout": layout})
                break

    print("FUZZ cases=%d seed=%d current_failures=%d floor_regression_failures=%d" %
          (len(cases), seed, len(failures), floor_failures))
    if failures:
        print(json.dumps(failures[:10], indent=2))
        return 1
    if floor_failures == 0:
        print("ERROR: negative-control alignment did not fail")
        return 1
    return 0


TRACE_TAG = re.compile(r"(E70Q10_(?:FRAME|DAMAGE|DIFF(?:_R)?|FINAL(?:_R)?|REQ(?:_DONE)?|SHADOW|EPDC_[A-Z_]+).*)")


def extract_trace(input_path: Path, output_path: Path) -> int:
    selected: list[str] = []
    counts: dict[str, int] = {}
    for line in input_path.read_text(encoding="utf-8", errors="replace").splitlines():
        match = TRACE_TAG.search(line)
        if not match:
            continue
        record = match.group(1)
        selected.append(record)
        tag = record.split()[0]
        counts[tag] = counts.get(tag, 0) + 1
    output_path.parent.mkdir(parents=True, exist_ok=True)
    output_path.write_text("\n".join(selected) + ("\n" if selected else ""),
                           encoding="utf-8")
    print("TRACE records=%d output=%s counts=%s" %
          (len(selected), output_path, json.dumps(counts, sort_keys=True)))
    return 0


def quantize(input_path: Path, output_dir: Path) -> int:
    output_dir.mkdir(parents=True, exist_ok=True)
    image = Image.open(input_path).convert("RGB")
    gray = image.convert("L")
    gray.save(output_dir / "grayscale_8bit.png")
    gray.point(lambda value: (value // 17) * 17).save(output_dir / "grayscale_4bit.png")
    gray.point(lambda value: 255 if value >= 128 else 0).save(
        output_dir / "binary_threshold_128.png")
    # RGB565 round trip, including the quantization applied before EPDC input.
    pixels = []
    for red, green, blue in image.getdata():
        red5 = red * 31 // 255
        green6 = green * 63 // 255
        blue5 = blue * 31 // 255
        pixels.append((red5 * 255 // 31, green6 * 255 // 63,
                       blue5 * 255 // 31))
    rgb565 = Image.new("RGB", image.size)
    rgb565.putdata(pixels)
    rgb565.save(output_dir / "rgb565_roundtrip.png")
    print("QUANTIZE output=%s" % output_dir)
    return 0


def line_pattern(output_dir: Path) -> int:
    """Create matched AA/integer/binary/gray line samples for panel A/B."""
    output_dir.mkdir(parents=True, exist_ok=True)
    width, height = 800, 600
    image = Image.new("RGB", (width, height), "white")
    draw = ImageDraw.Draw(image)
    draw.text((20, 15), "integer 1px pure black", fill="black")
    for x in range(40, 361, 32):
        draw.line((x, 50, x, 260), fill="black", width=1)
    for y in range(70, 251, 24):
        draw.line((30, y, 380, y), fill="black", width=1)

    draw.text((420, 15), "gray levels", fill="black")
    for index, gray in enumerate((0, 32, 64, 96, 128, 160, 192, 224)):
        x = 430 + index * 42
        draw.line((x, 50, x, 260), fill=(gray, gray, gray), width=3)

    # Supersampling deliberately creates fractional/subpixel antialiasing.
    scale = 4
    aa = Image.new("L", (width * scale, 280 * scale), 255)
    aa_draw = ImageDraw.Draw(aa)
    aa_draw.text((20 * scale, 10 * scale), "AA/subpixel diagonal and 0.75px lines", fill=0)
    for offset in range(10):
        x = (30 + offset * 35) * scale + (offset % scale)
        aa_draw.line((x, 50 * scale, x + 150 * scale, 250 * scale),
                     fill=0, width=3)
    aa = aa.resize((width, 280), Image.Resampling.LANCZOS).convert("RGB")
    image.paste(aa, (0, 300))
    source = output_dir / "ui_line_source.png"
    image.save(source)
    quantize(source, output_dir)
    print("LINE_PATTERN output=%s" % output_dir)
    return 0


def parser() -> argparse.ArgumentParser:
    result = argparse.ArgumentParser(description=__doc__)
    sub = result.add_subparsers(dest="command", required=True)
    demo_parser = sub.add_parser("demo", help="generate stale-pixel demonstrations")
    demo_parser.add_argument("--output-dir", type=Path, required=True)
    fuzz_parser = sub.add_parser("fuzz", help="fuzz current rectangle transforms")
    fuzz_parser.add_argument("--iterations", type=int, default=50000)
    fuzz_parser.add_argument("--seed", type=int, default=0xE70)
    replay_parser = sub.add_parser("replay", help="replay a JSON partial-update scenario")
    replay_parser.add_argument("--scenario", type=Path, required=True)
    replay_parser.add_argument("--output-dir", type=Path, required=True)
    trace_parser = sub.add_parser("extract-trace", help="extract structured E70Q10 lines")
    trace_parser.add_argument("--input", type=Path, required=True)
    trace_parser.add_argument("--output", type=Path, required=True)
    quantize_parser = sub.add_parser("quantize", help="render E-Ink quantization views")
    quantize_parser.add_argument("--input", type=Path, required=True)
    quantize_parser.add_argument("--output-dir", type=Path, required=True)
    line_parser = sub.add_parser("line-pattern", help="generate AA/grayscale line A/B images")
    line_parser.add_argument("--output-dir", type=Path, required=True)
    return result


def main(argv: Sequence[str] | None = None) -> int:
    args = parser().parse_args(argv)
    if args.command == "demo":
        return run_demo(args.output_dir)
    if args.command == "fuzz":
        return fuzz(args.iterations, args.seed)
    if args.command == "replay":
        return run_json_scenario(args.scenario, args.output_dir)
    if args.command == "extract-trace":
        return extract_trace(args.input, args.output)
    if args.command == "quantize":
        return quantize(args.input, args.output_dir)
    if args.command == "line-pattern":
        return line_pattern(args.output_dir)
    raise AssertionError(args.command)


if __name__ == "__main__":
    sys.exit(main())
