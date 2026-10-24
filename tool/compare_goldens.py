#!/usr/bin/env python3
"""Compare Flutter and browser screenshots for the pixel-enabled corpus."""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

from PIL import Image, ImageChops


ROOT = Path(__file__).resolve().parents[1]
MANIFEST_PATH = ROOT / "conformance" / "manifest.json"
DEFAULT_BROWSER = ROOT / "build" / "conformance" / "browser"
DEFAULT_FLUTTER = ROOT / "conformance" / "goldens" / "flutter"
DEFAULT_OUTPUT = ROOT / "build" / "conformance" / "diff"


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Compare browser and Flutter conformance screenshots."
    )
    parser.add_argument("--browser-dir", type=Path, default=DEFAULT_BROWSER)
    parser.add_argument("--flutter-dir", type=Path, default=DEFAULT_FLUTTER)
    parser.add_argument("--output", type=Path, default=DEFAULT_OUTPUT)
    parser.add_argument(
        "--report-only",
        action="store_true",
        help="Write metrics but return success even when thresholds fail.",
    )
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    manifest = json.loads(MANIFEST_PATH.read_text(encoding="utf-8"))
    gate = manifest.get("crossEngineTarget", {})
    channel_tolerance = int(gate.get("channelTolerance", 8))
    max_diff_ratio = float(gate.get("maxDiffRatio", 0.01))
    cases = [item for item in manifest["cases"] if item.get("pixel") is True]
    if not cases:
        raise SystemExit("No pixel cases are enabled in the manifest.")

    output = args.output.resolve()
    overlay_dir = output / "overlay"
    diff_dir = output / "diff-only"
    overlay_dir.mkdir(parents=True, exist_ok=True)
    diff_dir.mkdir(parents=True, exist_ok=True)

    results = []
    failed = False
    for item in cases:
        case_id = item["id"]
        browser_path = args.browser_dir.resolve() / "images" / f"{case_id}.png"
        flutter_path = args.flutter_dir.resolve() / "images" / f"{case_id}.png"
        if not browser_path.is_file() or not flutter_path.is_file():
            results.append(
                {
                    "id": case_id,
                    "status": "missing",
                    "browser": str(browser_path),
                    "flutter": str(flutter_path),
                }
            )
            failed = True
            continue

        browser = Image.open(browser_path).convert("RGB")
        flutter = Image.open(flutter_path).convert("RGB")
        if browser.size != flutter.size:
            results.append(
                {
                    "id": case_id,
                    "status": "size-mismatch",
                    "browserSize": list(browser.size),
                    "flutterSize": list(flutter.size),
                }
            )
            failed = True
            continue

        difference = ImageChops.difference(browser, flutter)
        red, green, blue = difference.split()
        max_channel = ImageChops.lighter(
            ImageChops.lighter(red, green),
            blue,
        )
        mask = max_channel.point(
            lambda value: 255 if value > channel_tolerance else 0
        )
        histogram = mask.histogram()
        diff_pixels = sum(histogram[1:])
        total_pixels = browser.width * browser.height
        diff_ratio = diff_pixels / total_pixels
        threshold_failed = diff_ratio > max_diff_ratio
        if threshold_failed:
            failed = True

        white = Image.new("RGB", browser.size, (255, 255, 255))
        faded = Image.blend(browser, white, 0.55)
        red_overlay = Image.new("RGB", browser.size, (255, 0, 0))
        overlay = faded.copy()
        overlay.paste(red_overlay, mask=mask)
        overlay_path = overlay_dir / f"{case_id}.png"
        overlay.save(overlay_path)

        amplified = max_channel.point(lambda value: min(255, value * 8))
        amplified_path = diff_dir / f"{case_id}.png"
        amplified.save(amplified_path)

        results.append(
            {
                "id": case_id,
                "status": "fail" if threshold_failed else "pass",
                "width": browser.width,
                "height": browser.height,
                "channelTolerance": channel_tolerance,
                "maxDiffRatio": max_diff_ratio,
                "diffPixels": diff_pixels,
                "totalPixels": total_pixels,
                "diffRatio": round(diff_ratio, 6),
                "overlay": str(overlay_path.relative_to(output)).replace(
                    "\\", "/"
                ),
                "diffOnly": str(amplified_path.relative_to(output)).replace(
                    "\\", "/"
                ),
            }
        )

    browser_metadata_path = args.browser_dir.resolve() / "metadata.json"
    import_metadata = {}
    if browser_metadata_path.is_file():
        browser_meta = json.loads(
            browser_metadata_path.read_text(encoding="utf-8")
        )
        import_metadata["browser"] = browser_meta.get("browser")

    report = {
        "manifestVersion": manifest["version"],
        "mode": "cross-engine-advisory",
        "thresholds": {
            "channelTolerance": channel_tolerance,
            "maxDiffRatio": max_diff_ratio,
        },
        "environment": import_metadata,
        "results": results,
        "passed": not failed,
    }
    (output / "report.json").write_text(
        json.dumps(report, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )

    for result in results:
        if result["status"] == "pass":
            print(
                f"PASS {result['id']}: {result['diffRatio'] * 100:.3f}% "
                f"pixels exceed {result['channelTolerance']} channel delta"
            )
        elif result["status"] == "fail":
            print(
                f"FAIL {result['id']}: {result['diffRatio'] * 100:.3f}% "
                f"pixels exceed {result['maxDiffRatio'] * 100:.3f}% budget"
            )
        else:
            print(f"{result['status'].upper()} {result['id']}")

    if failed and not args.report_only:
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
