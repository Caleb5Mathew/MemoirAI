#!/usr/bin/env python3
"""
Compute MemoryPrompt (x, y) fractions for Childhood chapter by detecting the
yellow path center in the asset image and mapping to ChapterJourneyView coords.

Layout model (matches SwiftUI ChapterJourneyView):
  - Background: Image.resizable().scaledToFill().ignoresSafeArea() fills the FULL screen.
  - GeometryReader.proposed size = safe area (SAFE_W x SAFE_H); bubble position uses:
      x = prompt.x * geo.size.width
      y = prompt.y * geo.size.height
  - Image scales to height FULL_SCREEN_H; width crops equally.
  - scale = FULL_SCREEN_H / image_height
  - norm_x = (ix * scale - left_crop) / SAFE_W
  - norm_y = (iy * scale - TOP_INSET) / SAFE_H

Spine: bottom stop uses strict yellow runs + soft fallback; upper stops chain upward with
TrackedPeak so uniform peach wash does not flatten x.

Defaults: iPhone 15 Pro portrait (SAFE_W=393, SAFE_H=759, TOP_INSET=59, FULL_SCREEN_H=852).
Override with env vars SAFE_W, SAFE_H, TOP_INSET, FULL_SCREEN_H.

Usage:
  python3 childhood_path_positions.py
  python3 childhood_path_positions.py --debug [--debug-out path/to/out.png]
"""

from __future__ import annotations

import argparse
import json
import os
import sys
from pathlib import Path

import colorsys

from PIL import Image, ImageDraw

# Asset path relative to repo root
REPO = Path(__file__).resolve().parents[1]
CHILDHOOD_PNG = REPO / (
    "MemoirAI/Assets.xcassets/childhood.imageset/"
    "ChatGPT Image Apr 14, 2025, 02_42_33 PM.png"
)

DEFAULT_SAFE_W = float(os.environ.get("SAFE_W", "393"))
DEFAULT_SAFE_H = float(os.environ.get("SAFE_H", "759"))
DEFAULT_TOP_INSET = float(os.environ.get("TOP_INSET", "59"))
DEFAULT_FULL_SCREEN_H = float(os.environ.get("FULL_SCREEN_H", "852"))


def layout_constants() -> tuple[float, float, float, float]:
    """Returns (safe_w, safe_h, top_inset, full_screen_h)."""
    return (
        DEFAULT_SAFE_W,
        DEFAULT_SAFE_H,
        DEFAULT_TOP_INSET,
        DEFAULT_FULL_SCREEN_H,
    )


def is_path_pixel(r: int, g: int, b: int) -> bool:
    """
    Strict path mask: saturated warm yellow ribbon, not the global peach wash.
    The old RGB-only rule matched ~every column on many rows.
    """
    hh, ss, vv = colorsys.rgb_to_hsv(r / 255.0, g / 255.0, b / 255.0)
    if vv < 0.72:
        return False
    if g > r + 5:
        return False
    if ss < 0.35 or ss > 0.68:
        return False
    if r - b < 32:
        return False
    return True


def _runs_for_row(pixels, width: int, iy: int) -> list[tuple[int, int]]:
    row = [is_path_pixel(*pixels[x, iy]) for x in range(width)]
    runs: list[tuple[int, int]] = []
    start = None
    for x, v in enumerate(row + [False]):
        if v and start is None:
            start = x
        elif not v and start is not None:
            runs.append((start, x - 1))
            start = None
    return runs


def _run_width(t: tuple[int, int]) -> int:
    return t[1] - t[0] + 1


def _row_yellow_scores(pixels, width: int, iy: int) -> list[float]:
    scores: list[float] = []
    for x in range(width):
        r, g, b = pixels[x, iy]
        scores.append(float(r + g - b) - 0.6 * abs(float(g - r)))
    return scores


def _soft_peak_x(
    pixels,
    width: int,
    iy: int,
    prev_x: float | None,
    half_window: int = 300,
    penalty: float = 0.72,
) -> int:
    """Fallback when run-based detection fails: strong yellow with mild continuity bias."""
    scores = _row_yellow_scores(pixels, width, iy)
    anchor = (width - 1) / 2.0 if prev_x is None else float(prev_x)
    lo = max(0, int(anchor - half_window))
    hi = min(width, int(anchor + half_window))
    if hi <= lo + 8:
        lo, hi = 0, width
    return int(max(range(lo, hi), key=lambda x: scores[x] - penalty * abs(x - anchor)))


def _tracked_peak_x(
    pixels: object,
    width: int,
    iy: int,
    prev_ix: int,
    max_delta: int = 175,
    penalty: float = 0.32,
) -> int:
    """
    Follow the path upward: local argmax of yellow score in a horizontal band around
    the previous row's spine. Works when the global wash is uniform (soft peak alone fails).
    """
    scores = _row_yellow_scores(pixels, width, iy)
    lo, hi = max(0, prev_ix - max_delta), min(width, prev_ix + max_delta)
    if hi <= lo + 4:
        lo, hi = 0, width
    return int(max(range(lo, hi), key=lambda x: scores[x] - penalty * abs(x - prev_ix)))


def _refine_ix_strict_median(
    pixels: object,
    width: int,
    height: int,
    iy: int,
    ix: int,
    half_x: int = 30,
    half_y: int = 6,
    min_samples: int = 10,
) -> int:
    """Snap spine toward strict yellow pixels near the tracker, when available."""
    xs: list[int] = []
    y0, y1 = max(0, iy - half_y), min(height - 1, iy + half_y)
    x0, x1 = max(0, ix - half_x), min(width - 1, ix + half_x)
    for yy in range(y0, y1 + 1):
        for xx in range(x0, x1 + 1):
            if is_path_pixel(*pixels[xx, yy]):
                xs.append(xx)
    if len(xs) < min_samples:
        return ix
    xs.sort()
    mid = len(xs) // 2
    return xs[mid] if len(xs) % 2 else (xs[mid - 1] + xs[mid]) // 2


def path_center_constrained_band(
    pixels,
    width: int,
    height: int,
    iy: int,
    half_band: int = 7,
    prev_x: float | None = None,
) -> int | None:
    """
    1) Prefer disjoint runs from strict yellow mask with plausible path width.
    2) If only mega-runs remain, follow soft yellow peak near previous spine x.
    3) Median x of strict-mask pixels in a small band around chosen interval.
    """
    runs = _runs_for_row(pixels, width, iy)
    max_w = int(0.42 * width)
    min_w = 45
    spine_seed = float(prev_x) if prev_x is not None else (width - 1) / 2.0

    def mid(t):
        return (t[0] + t[1]) / 2

    chosen: tuple[int, int] | None = None
    if runs:
        valid = [t for t in runs if min_w <= _run_width(t) <= max_w]
        if valid:
            best = min(valid, key=lambda t: abs(mid(t) - spine_seed))
            if abs(mid(best) - spine_seed) <= 185:
                chosen = best
    if chosen is None:
        cx = _soft_peak_x(pixels, width, iy, prev_x)
        a, b = max(0, cx - 110), min(width - 1, cx + 110)
    else:
        a, b = chosen

    margin = 26
    a0, b0 = max(0, a - margin), min(width - 1, b + margin)
    xs: list[int] = []
    y0 = max(0, iy - half_band)
    y1 = min(height - 1, iy + half_band)
    for yy in range(y0, y1 + 1):
        for xx in range(a0, b0 + 1):
            if is_path_pixel(*pixels[xx, yy]):
                xs.append(xx)
    if not xs:
        return (a + b) // 2
    xs.sort()
    mi = len(xs) // 2
    return xs[mi] if len(xs) % 2 else (xs[mi - 1] + xs[mi]) // 2


def map_image_to_geo_norm(
    ix: float,
    iy: float,
    img_w: int,
    img_h: int,
    safe_w: float,
    safe_h: float,
    top_inset: float,
    full_screen_h: float,
) -> tuple[float, float]:
    scale = full_screen_h / img_h
    disp_w = img_w * scale
    left_crop = (disp_w - safe_w) / 2.0
    x_pt = ix * scale - left_crop
    y_pt = iy * scale - top_inset
    return x_pt / safe_w, y_pt / safe_h


def geo_norm_y_to_image_row(
    norm_y: float,
    img_h: int,
    safe_h: float,
    top_inset: float,
    full_screen_h: float,
) -> int:
    scale = full_screen_h / img_h
    iy = (norm_y * safe_h + top_inset) / scale
    return int(round(max(0.0, min(float(img_h - 1), iy))))


def clamp01(v: float, lo: float = 0.04, hi: float = 0.96) -> float:
    return max(lo, min(hi, v))


def write_debug_png(
    im: Image.Image,
    pixels,
    img_w: int,
    img_h: int,
    results: list[dict],
    safe_w: float,
    safe_h: float,
    top_inset: float,
    full_screen_h: float,
    out_path: Path,
) -> None:
    """Full-screen-sized crop + path tint + bubble centers (same coords as simulator)."""
    scale = full_screen_h / img_h
    disp_w = img_w * scale
    left_crop = (disp_w - safe_w) / 2.0

    scaled = im.resize((int(round(disp_w)), int(round(full_screen_h))), Image.Resampling.LANCZOS)
    crop_x0 = int(round(left_crop))
    crop_x1 = int(round(left_crop + safe_w))
    visible = scaled.crop((crop_x0, 0, crop_x1, int(round(full_screen_h)))).convert("RGBA")

    overlay = Image.new("RGBA", visible.size, (0, 0, 0, 0))
    opx = overlay.load()
    spx = scaled.load()
    for sy in range(visible.height):
        for sx in range(visible.width):
            gx = crop_x0 + sx
            gy = sy
            ix_f = gx / scale
            iy_f = gy / scale
            ix = int(max(0, min(img_w - 1, ix_f)))
            iy = int(max(0, min(img_h - 1, iy_f)))
            if is_path_pixel(*pixels[ix, iy]):
                opx[sx, sy] = (255, 80, 80, 90)
    out = Image.alpha_composite(visible, overlay)

    draw = ImageDraw.Draw(out)
    for r in results:
        if r.get("image_x_center") is None:
            continue
        nx, ny = r["final_norm_x"], r["final_norm_y"]
        cx = nx * safe_w
        cy = top_inset + ny * safe_h
        cx_i, cy_i = int(round(cx)), int(round(cy))
        draw.ellipse((cx_i - 10, cy_i - 10, cx_i + 10, cy_i + 10), outline=(255, 255, 255), width=3)
        draw.ellipse((cx_i - 7, cy_i - 7, cx_i + 7, cy_i + 7), outline=(0, 200, 100), width=2)

    out_path.parent.mkdir(parents=True, exist_ok=True)
    out.convert("RGB").save(out_path, "PNG")
    print(f"Wrote debug image: {out_path}", file=sys.stderr)


def main() -> int:
    parser = argparse.ArgumentParser(description="Childhood path bubble positions")
    parser.add_argument(
        "--debug",
        action="store_true",
        help="Write annotated PNG (path mask + bubble centers)",
    )
    parser.add_argument(
        "--debug-out",
        type=Path,
        default=REPO / "scripts" / "output" / "childhood_path_debug.png",
        help="Output path for --debug",
    )
    args = parser.parse_args()

    if not CHILDHOOD_PNG.is_file():
        print(f"Missing asset: {CHILDHOOD_PNG}", file=sys.stderr)
        return 1

    safe_w, safe_h, top_inset, full_screen_h = layout_constants()
    im = Image.open(CHILDHOOD_PNG).convert("RGB")
    w, h = im.size
    pixels = im.load()

    target_norm_ys = [0.80, 0.63, 0.43, 0.28]

    results: list[dict] = []
    chain_ix: int | None = None
    for prompt_idx, norm_y in enumerate(target_norm_ys):
        iy = geo_norm_y_to_image_row(norm_y, h, safe_h, top_inset, full_screen_h)
        iy = max(0, min(h - 1, iy))
        ix: int | None = None
        chosen_yy = iy

        if prompt_idx == 0:
            # Bottom stop: run/soft segmentation (no upstream spine yet).
            for delta in range(0, 80, 2):
                found = False
                for sign in (1, -1):
                    if delta == 0 and sign == -1:
                        continue
                    dy = (delta if sign > 0 else -delta) if delta > 0 else 0
                    yy = iy + dy
                    if yy < 0 or yy >= h:
                        continue
                    cx = path_center_constrained_band(
                        pixels, w, h, yy, half_band=7, prev_x=None
                    )
                    if cx is not None:
                        chosen_yy, ix = yy, cx
                        found = True
                        break
                if found:
                    break
        else:
            # Follow the yellow spine upward from the previous row (wash is uniform row-to-row).
            assert chain_ix is not None
            ix = _tracked_peak_x(pixels, w, iy, chain_ix)
            chosen_yy = iy

        if ix is None:
            print(f"WARNING: no path at norm_y={norm_y}", file=sys.stderr)
            nx, ny = 0.5, norm_y
            results.append(
                {
                    "target_norm_y_input": norm_y,
                    "image_row_used": None,
                    "image_x_center": None,
                    "final_norm_x": round(nx, 4),
                    "final_norm_y": round(ny, 4),
                }
            )
            continue

        ix = _refine_ix_strict_median(pixels, w, h, chosen_yy, ix)
        chain_ix = ix

        nx, ny = map_image_to_geo_norm(
            float(ix), float(chosen_yy), w, h, safe_w, safe_h, top_inset, full_screen_h
        )
        nx = clamp01(nx)
        ny = clamp01(ny)
        results.append(
            {
                "target_norm_y_input": norm_y,
                "image_row_used": chosen_yy,
                "image_x_center": ix,
                "final_norm_x": round(nx, 4),
                "final_norm_y": round(ny, 4),
            }
        )

    meta = {
        "safe_area": {"W": safe_w, "H": safe_h},
        "top_inset": top_inset,
        "full_screen_h": full_screen_h,
        "image_size": [w, h],
        "prompts": results,
    }
    print(json.dumps(meta, indent=2))

    print("\n// Swift MemoryPrompt lines (chapter 1 order: bottom prompt first):\n")
    sample_texts = [
        "What is one of your clearest early memories?",
        "What games or activities made you happiest as a child?",
        "Tell me about a place you loved to spend time when you were small.",
        "Who showed you kindness when you were young, and what did they do?",
    ]
    for r, t in zip(results, sample_texts):
        sx, sy = r["final_norm_x"], r["final_norm_y"]
        print(f'        MemoryPrompt(text: "{t}", x: {sx}, y: {sy}),')

    if args.debug:
        write_debug_png(
            im,
            pixels,
            w,
            h,
            results,
            safe_w,
            safe_h,
            top_inset,
            full_screen_h,
            args.debug_out,
        )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
