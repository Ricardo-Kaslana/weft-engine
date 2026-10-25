#!/usr/bin/env python3
"""Generate deterministic PNG fixtures for conformance image cases.

The fixtures use hard-edged rectangles only (no anti-aliasing, no gradients)
so that Chrome and Flutter rasterize them near-identically at a 1:1 scale.
Run after changing any fixture: python tool/generate_assets.py
"""

from __future__ import annotations

from pathlib import Path

from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[1]
ASSETS = ROOT / "conformance" / "assets"


def float_left() -> Image.Image:
    image = Image.new("RGB", (120, 96), "#3366cc")
    draw = ImageDraw.Draw(image)
    draw.rectangle((4, 4, 115, 91), outline="#ffffff", width=2)
    draw.rectangle((16, 16, 103, 79), fill="#6699e0")
    draw.rectangle((28, 28, 91, 67), fill="#1d4d99")
    draw.rectangle((40, 40, 79, 55), fill="#a8c8f0")
    return image


def float_right() -> Image.Image:
    image = Image.new("RGB", (144, 72), "#cc6633")
    draw = ImageDraw.Draw(image)
    draw.rectangle((4, 4, 139, 67), outline="#ffffff", width=2)
    draw.rectangle((16, 14, 127, 57), fill="#e09966")
    for x in range(24, 120, 24):
        draw.rectangle((x, 24, x + 8, 47), fill="#8f4318")
    return image


def block_hero() -> Image.Image:
    image = Image.new("RGB", (240, 120), "#2e7d32")
    draw = ImageDraw.Draw(image)
    draw.rectangle((4, 4, 235, 115), outline="#ffffff", width=2)
    draw.rectangle((16, 16, 223, 103), fill="#4caf50")
    for x in range(32, 208, 32):
        draw.rectangle((x, 32, x + 12, 87), fill="#1b5e20")
    draw.rectangle((16, 92, 223, 103), fill="#a5d6a7")
    return image


def main() -> None:
    ASSETS.mkdir(parents=True, exist_ok=True)
    fixtures = {
        "float_left.png": float_left,
        "float_right.png": float_right,
        "block_hero.png": block_hero,
    }
    for name, factory in fixtures.items():
        path = ASSETS / name
        factory().save(path, format="PNG", optimize=True)
        print(f"wrote {path.relative_to(ROOT).as_posix()}")


if __name__ == "__main__":
    main()
