#!/usr/bin/env python3

import tempfile
import unittest
from pathlib import Path

import epdc_panel_replay as replay


class RectTransformTest(unittest.TestCase):
    def test_right_edge_one_pixel_is_preserved(self):
        original = replay.Rect(1403, 0, 1, 1)
        aligned = replay.align_outward(original)
        self.assertEqual(replay.Rect(1400, 0, 4, 8), aligned)
        self.assertTrue(replay.contains(aligned, original))
        self.assertEqual(replay.Rect(0, 0, 8, 4), replay.rotate_ccw(aligned))

    def test_floor_end_negative_control_drops_edge(self):
        original = replay.Rect(1403, 0, 1, 1)
        self.assertFalse(replay.contains(replay.align_floor_end_bug(original), original))

    def test_stride_padding_is_not_visible_width(self):
        model = replay.kernel_layout(replay.Rect(1400, 0, 4, 8))
        self.assertEqual(2816, model["source_pitch_bytes"])
        self.assertEqual(0, replay.rotate_ccw(replay.Rect(1400, 0, 4, 8)).top)
        self.assertNotEqual(replay.PHYSICAL_WIDTH, replay.PHYSICAL_STRIDE)

    def test_demo_produces_both_pass_and_stale_cases(self):
        with tempfile.TemporaryDirectory() as temporary:
            output = Path(temporary)
            replay.run_demo(output)
            current = (output / "current_alignment" / "replay_result.json").read_text()
            floor = (output / "floor_end_regression" / "replay_result.json").read_text()
            reuse = (output / "deferred_page_reuse" / "replay_result.json").read_text()
            self.assertIn('"mismatch_pixels": 0', current)
            self.assertNotIn('"mismatch_pixels": 0', floor)
            self.assertNotIn('"mismatch_pixels": 0', reuse)


if __name__ == "__main__":
    unittest.main()
