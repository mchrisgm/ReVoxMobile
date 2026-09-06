#!/usr/bin/env python3
"""Compose the App Store screenshots from the captures CI rendered.

One 1290 x 2796 PNG per frame of store/screenshots.json: a flat panel in one of the app's two inks, a short
rule, a headline, a subline, and the real screen whole beneath them. The screen is the capture exactly as
`ScreenshotTests` rendered it, scaled once to 950 px wide and its corners rounded like the display; nothing is
cropped, so the Start and Stop capsules, History's Merge and Delete bar and the tab bar are always in shot. A
frame marked "close-up" (the word popover, which CI can only render on its own) shows the card instead of a
mostly blank phone. Inks alternate by position: teal for the odd frames, off-white for the even ones.

The panel is an HTML file with the capture and the two Inter weights embedded as data URIs, rendered by
headless Chromium; the output's size is read back from the PNG header and anything but 1290 x 2796 is
refused. Python 3 standard library only.

Usage:
  python3 scripts/store/compose-screenshots.py --input store-screenshots \
      --spec store/screenshots.json --output docs/store/screenshots
  python3 scripts/store/compose-screenshots.py --self-test    # synthetic captures into a temporary folder

Inputs are the store-screenshots artifact (1290 x 2796). The README's 786 x 1704 renders in docs/screenshots
are accepted too, for a preview: they are upscaled, so the shipped set is composed from the artifact.
See docs/store/README.md.
"""
import argparse
import base64
import html
import json
import os
import shutil
import struct
import subprocess
import sys
import tempfile
import zlib
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
DEFAULT_SPEC = ROOT / "store" / "screenshots.json"
DEFAULT_OUTPUT = ROOT / "docs" / "store" / "screenshots"
FONTS = {800: ROOT / "store" / "fonts" / "Inter-ExtraBold.woff2", 500: ROOT / "store" / "fonts" / "Inter-Medium.woff2"}

CANVAS = (1290, 2796)

# The two inks and everything that changes with them. Contrast on teal: white 5.1:1, #D4E7EA 4.0:1; on off-white:
# #0F2A30 13.7:1, #4A5B60 6.5:1.
INKS = {
    "teal": {
        "background": "#12788C", "rule": "#F6F4EF", "headline": "#FFFFFF", "subline": "#D4E7EA",
        "stroke": "#FFFFFF47", "shadow": "0 48px 120px #00000066, 0 8px 24px #0000004D",
    },
    "off-white": {
        "background": "#F6F4EF", "rule": "#12788C", "headline": "#0F2A30", "subline": "#4A5B60",
        "stroke": "#0F2A301A", "shadow": "0 48px 120px #0F2A3033, 0 8px 24px #0F2A3021",
    },
}

# Geometry, in canvas pixels. The text and the capture share the 170 px left edge; the text is top-anchored and
# the capture never moves, so a shorter headline simply leaves more room above it.
LEFT = 170
RULE = {"top": 140, "width": 96, "height": 8}
COPY = {"top": 176, "width": 1050}
SCREEN = {"top": 672, "width": 950, "height": 2060, "radius": 120}      # bottom at 2732, 64 px margin
CLOSE_UP_RADIUS = 96

# The captures `ScreenshotTests` writes, by pixel width: pixels per point and the window's width in points.
RENDERS = {786: {"height": 1704, "scale": 2, "points": 393}, 1290: {"height": 2796, "scale": 3, "points": 430}}

# The close-up crop, in points, so it holds for both renders: the popover test hosts `WordPopoverView` in a
# 360-point-wide card, centred, 24 points under the 59-point status-bar strip. Measured on the 786 x 1704 render,
# the content spans x 65 to 697 and y 211 to 916 px, and this crop (x 0, y 150, w 760, h 830 px there) keeps
# about 32 points of the capture's own white around it. Update it if the popover test changes its frame.
CLOSE_UP = {"card_width": 360, "left_margin": 16.5, "top": 75, "width": 380, "height": 415}

PNG_SIGNATURE = b"\x89PNG\r\n\x1a\n"


# MARK: PNG

def png_header(data):
    """(width, height, bit depth, colour type) from a PNG's IHDR, or a ValueError."""
    if data[:8] != PNG_SIGNATURE or data[12:16] != b"IHDR":
        raise ValueError("not a PNG")
    width, height, depth, colour = struct.unpack(">IIBB", data[16:26])
    return width, height, depth, colour


def png_chunks(data):
    position = 8
    while position < len(data):
        length = int.from_bytes(data[position:position + 4], "big")
        kind = data[position + 4:position + 8]
        yield kind, data[position + 8:position + 8 + length]
        position += 12 + length
        if kind == b"IEND":
            break


def decode_png(data):
    """(width, height, channels, rows) for an 8-bit non-interlaced PNG; rows are bytearrays of packed samples."""
    width, height, depth, colour = png_header(data)
    channels = {0: 1, 2: 3, 4: 2, 6: 4}.get(colour)
    if depth != 8 or channels is None or data[28] != 0:
        raise ValueError(f"unsupported PNG (bit depth {depth}, colour type {colour}, interlace {data[28]})")
    raw = zlib.decompress(b"".join(chunk for kind, chunk in png_chunks(data) if kind == b"IDAT"))
    stride = width * channels
    rows, previous = [], bytearray(stride)
    for y in range(height):
        start = y * (stride + 1)
        method, line = raw[start], bytearray(raw[start + 1:start + 1 + stride])
        unfilter(method, line, previous, channels)
        rows.append(line)
        previous = line
    return width, height, channels, rows


def unfilter(method, line, previous, bpp):
    if method == 0:
        return
    if method == 1:
        for i in range(bpp, len(line)):
            line[i] = (line[i] + line[i - bpp]) & 0xFF
    elif method == 2:
        for i in range(len(line)):
            line[i] = (line[i] + previous[i]) & 0xFF
    elif method == 3:
        for i in range(len(line)):
            left = line[i - bpp] if i >= bpp else 0
            line[i] = (line[i] + ((left + previous[i]) >> 1)) & 0xFF
    elif method == 4:
        for i in range(len(line)):
            a = line[i - bpp] if i >= bpp else 0
            b = previous[i]
            c = previous[i - bpp] if i >= bpp else 0
            p = a + b - c
            pa, pb, pc = abs(p - a), abs(p - b), abs(p - c)
            predictor = a if pa <= pb and pa <= pc else (b if pb <= pc else c)
            line[i] = (line[i] + predictor) & 0xFF
    else:
        raise ValueError(f"unknown PNG filter {method}")


def encode_png(width, height, rows, channels=3):
    """An 8-bit PNG (RGB by default) from rows of packed samples; filter 0 throughout."""
    colour = {1: 0, 2: 4, 3: 2, 4: 6}[channels]

    def chunk(kind, body):
        return struct.pack(">I", len(body)) + kind + body + struct.pack(">I", zlib.crc32(kind + body) & 0xFFFFFFFF)

    raw = b"".join(b"\x00" + bytes(row) for row in rows)
    return (PNG_SIGNATURE + chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, colour, 0, 0, 0))
            + chunk(b"IDAT", zlib.compress(raw, 6)) + chunk(b"IEND", b""))


def strip_alpha(data):
    """The same image as RGB. App Store Connect refuses a PNG with an alpha channel; Chromium normally writes none,
    and this is the slow pure-Python path for a build that does."""
    width, height, channels, rows = decode_png(data)
    if channels == 3:
        return data
    if channels != 4:
        raise ValueError(f"cannot strip alpha from a {channels}-channel PNG")
    rgb_rows = []
    for row in rows:
        rgb = bytearray(width * 3)
        rgb[0::3], rgb[1::3], rgb[2::3] = row[0::4], row[1::4], row[2::4]
        rgb_rows.append(rgb)
    return encode_png(width, height, rgb_rows)


# MARK: Chromium

CHROME_CANDIDATES = [
    "/opt/pw-browsers/chromium-*/chrome-linux/chrome",
    "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome",
    "google-chrome",
    "chromium",
]


def find_chrome(explicit):
    """--chrome, else $CHROME, else the first of CHROME_CANDIDATES that exists (globs allowed) or is on PATH."""
    for candidate in [explicit, os.environ.get("CHROME")]:
        if candidate:
            if Path(candidate).exists() or shutil.which(candidate):
                return candidate
            raise SystemExit(f"Chromium not found at {candidate}")
    for candidate in CHROME_CANDIDATES:
        if "*" in candidate:
            matches = sorted(Path("/").glob(candidate.lstrip("/")))
            if matches:
                return str(matches[-1])
        elif Path(candidate).exists() or shutil.which(candidate):
            return candidate
    raise SystemExit("no Chromium found: pass --chrome PATH or set $CHROME (see docs/store/README.md)")


def render(chrome, panel, output):
    """Renders `panel` (an HTML file) to `output` at the canvas size with headless Chromium."""
    command = [chrome, "--headless=new", "--hide-scrollbars", "--force-device-scale-factor=1",
               f"--window-size={CANVAS[0]},{CANVAS[1]}", "--virtual-time-budget=5000",
               f"--screenshot={output}", panel.as_uri()]
    if hasattr(os, "geteuid") and os.geteuid() == 0:
        command.insert(1, "--no-sandbox")       # Chromium refuses to run as root without it (containers, CI)
    result = subprocess.run(command, capture_output=True, text=True)
    if result.returncode != 0 or not output.exists():
        raise SystemExit(f"Chromium failed on {panel.name} (exit {result.returncode}):\n{result.stderr.strip()}")


# MARK: The panel

def data_uri(path, mime):
    return f"data:{mime};base64," + base64.b64encode(Path(path).read_bytes()).decode("ascii")


def font_faces(fonts=FONTS):
    faces = []
    for weight, path in fonts.items():
        if Path(path).exists():
            faces.append(f"@font-face {{ font-family: 'Inter'; font-style: normal; font-weight: {weight}; "
                         f"src: url({data_uri(path, 'font/woff2')}) format('woff2'); }}")
    return "\n".join(faces)


def screen_geometry(capture_size, presentation):
    """Where the capture goes and how much of it: (box left, top, width, height, radius, image left, top, width, height).

    Full screens scale the whole capture to the 950 x 2060 box (a resample of at most one pixel in aspect). The
    close-up scales its crop to 950 wide and sits in the band the phone occupies on the other frames, a third of
    the way down the free space rather than centred, so the card reads as the next thing after the subline instead
    of floating in the middle of the panel.
    """
    width, height = capture_size
    if presentation == "screen":
        return {"left": LEFT, "top": SCREEN["top"], "width": SCREEN["width"], "height": SCREEN["height"],
                "radius": SCREEN["radius"], "img_left": 0, "img_top": 0,
                "img_width": SCREEN["width"], "img_height": SCREEN["height"]}
    if presentation != "close-up":
        raise SystemExit(f"unknown presentation {presentation!r}: use \"screen\" or \"close-up\"")
    render_ = RENDERS[width]
    scale, points = render_["scale"], render_["points"]
    crop_left = ((points - CLOSE_UP["card_width"]) / 2 - CLOSE_UP["left_margin"]) * scale
    crop_top = CLOSE_UP["top"] * scale
    crop_width, crop_height = CLOSE_UP["width"] * scale, CLOSE_UP["height"] * scale
    if crop_left < 0 or crop_top + crop_height > height or crop_left + crop_width > width:
        raise SystemExit("the close-up crop falls outside the capture; update CLOSE_UP")
    factor = SCREEN["width"] / crop_width
    box_height = int(crop_height * factor + 0.5)
    box_top = SCREEN["top"] + (SCREEN["height"] - box_height) // 3
    return {"left": LEFT, "top": box_top, "width": SCREEN["width"], "height": box_height, "radius": CLOSE_UP_RADIUS,
            "img_left": -crop_left * factor, "img_top": -crop_top * factor,
            "img_width": width * factor, "img_height": height * factor}


def panel_html(frame, ink_name, capture_path, capture_size, presentation, fonts=FONTS):
    ink = INKS[ink_name]
    g = screen_geometry(capture_size, presentation)
    return f"""<!doctype html>
<html lang="en-GB"><head><meta charset="utf-8"><title>{html.escape(frame['id'])}</title>
<style>
{font_faces(fonts)}
html, body {{ margin: 0; padding: 0; background: {ink['background']}; }}
body {{ position: relative; width: {CANVAS[0]}px; height: {CANVAS[1]}px; overflow: hidden;
  font-family: 'Inter', -apple-system, 'SF Pro Display', 'Helvetica Neue', Arial, sans-serif;
  text-rendering: optimizeLegibility; font-feature-settings: normal; -webkit-hyphens: none; hyphens: none; }}
.rule {{ position: absolute; left: {LEFT}px; top: {RULE['top']}px; width: {RULE['width']}px; height: {RULE['height']}px;
  border-radius: 0; background: {ink['rule']}; }}
.copy {{ position: absolute; left: {LEFT}px; top: {COPY['top']}px; width: {COPY['width']}px; }}
h1 {{ margin: 0; font-weight: 800; font-size: 136px; line-height: 140px; letter-spacing: -4px; color: {ink['headline']}; }}
p {{ margin: 28px 0 0; font-weight: 500; font-size: 50px; line-height: 62px; letter-spacing: -0.5px; color: {ink['subline']}; }}
.screen {{ position: absolute; left: {g['left']}px; top: {g['top']}px; width: {g['width']}px; height: {g['height']}px;
  border-radius: {g['radius']}px; overflow: hidden; box-shadow: {ink['shadow']}; }}
.screen img {{ position: absolute; display: block; left: {g['img_left']}px; top: {g['img_top']}px;
  width: {g['img_width']}px; height: {g['img_height']}px; }}
.screen .edge {{ position: absolute; inset: 0; border-radius: {g['radius']}px; box-shadow: inset 0 0 0 1.5px {ink['stroke']}; }}
</style></head>
<body>
<div class="rule"></div>
<div class="copy"><h1>{html.escape(frame['headline'])}</h1><p>{html.escape(frame['subline'])}</p></div>
<div class="screen"><img src="{data_uri(capture_path, 'image/png')}" alt=""><div class="edge"></div></div>
</body></html>
"""


# MARK: Composing

def load_spec(path):
    spec = json.loads(Path(path).read_text(encoding="utf-8"))
    frames = spec.get("frames")
    if not isinstance(frames, list) or not frames:
        raise SystemExit(f"{path}: no frames")
    for frame in frames:
        for key in ("id", "capture", "headline", "subline"):
            if not isinstance(frame.get(key), str) or not frame[key]:
                raise SystemExit(f"{path}: frame {frame.get('id', '?')} needs a {key}")
        for text in (frame["headline"], frame["subline"]):
            if "—" in text or "\n" in text:
                raise SystemExit(f"{path}: frame {frame['id']}: no em-dashes and no manual line breaks in the copy")
    return frames


def capture_for(frame, input_dir):
    """(path, headline, subline, note) for the frame's capture, or its fallback when the capture is missing."""
    path = Path(input_dir) / f"{frame['capture']}.png"
    if path.exists():
        return path, frame["headline"], frame["subline"], None
    fallback = frame.get("fallback")
    if fallback and (Path(input_dir) / f"{fallback['capture']}.png").exists():
        return (Path(input_dir) / f"{fallback['capture']}.png", fallback["headline"], fallback["subline"],
                f"{frame['capture']}.png is missing; using the {fallback['capture']} stand-in")
    raise SystemExit(f"{frame['id']}: {path.name} is missing from {input_dir}"
                     + (f" and so is its fallback {fallback['capture']}.png" if fallback else ""))


def check_capture(path):
    data = path.read_bytes()
    width, height, depth, colour = png_header(data)
    if width not in RENDERS or RENDERS[width]["height"] != height:
        sizes = " or ".join(f"{w} x {r['height']}" for w, r in RENDERS.items())
        raise SystemExit(f"{path}: {width} x {height} is not a ScreenshotTests render ({sizes})")
    return width, height


def compose(input_dir, spec_path, output_dir, chrome, only=None, keep_panels=None, fonts=FONTS, verbose=True):
    frames = load_spec(spec_path)
    if only:
        unknown = set(only) - {f["id"] for f in frames}
        if unknown:
            raise SystemExit(f"{spec_path}: no frame named {', '.join(sorted(unknown))}")
    output_dir = Path(output_dir)
    output_dir.mkdir(parents=True, exist_ok=True)
    panels = Path(keep_panels) if keep_panels else Path(tempfile.mkdtemp(prefix="revox-store-"))
    panels.mkdir(parents=True, exist_ok=True)
    composed = []
    try:
        for index, frame in enumerate(frames):          # the ink goes by position, so --frame keeps the index
            if only and frame["id"] not in only:
                continue
            ink = "teal" if index % 2 == 0 else "off-white"
            capture, headline, subline, note = capture_for(frame, input_dir)
            size = check_capture(capture)
            if note and verbose:
                print(f"note: {frame['id']}: {note}")
            if size[0] != CANVAS[0] and verbose:
                print(f"note: {frame['id']}: {capture.name} is the README render ({size[0]} x {size[1]}), upscaled; "
                      f"compose the shipped set from the store-screenshots artifact")
            presentation = frame.get("presentation", "screen")
            panel = panels / f"{frame['id']}.html"
            panel.write_text(panel_html({**frame, "headline": headline, "subline": subline}, ink, capture, size,
                                        presentation, fonts), encoding="utf-8")
            output = output_dir / f"{frame['id']}.png"
            render(chrome, panel, output)
            data = output.read_bytes()
            width, height, depth, colour = png_header(data)
            if (width, height) != CANVAS:
                output.unlink()
                raise SystemExit(f"{output}: Chromium wrote {width} x {height}, not {CANVAS[0]} x {CANVAS[1]}; refused")
            if colour in (4, 6):
                output.write_bytes(strip_alpha(data))
                if verbose:
                    print(f"note: {frame['id']}: Chromium wrote an alpha channel; stripped")
            if verbose:
                print(f"{output.name}  {width} x {height}  {ink:9}  {presentation:8}  from {capture.name} ({size[0]} x {size[1]})")
            composed.append(output)
    finally:
        if not keep_panels:
            shutil.rmtree(panels, ignore_errors=True)
    return composed


# MARK: Self-test

def synthetic_capture(width, height, tint):
    """A screen-shaped PNG: white, a status-bar strip left blank, a dark title, grey rows, a capsule at the
    bottom and a tinted band, so a composed frame shows the geometry without a simulator."""
    scale = RENDERS[width]["scale"]
    white, dark, grey, capsule = b"\xff\xff\xff", b"\x11\x11\x11", b"\xd9\xd9\xd9", b"\xff\x3b\x30"
    band = bytes(tint)

    def rect(rows, x, y, w, h, colour):
        for yy in range(y, min(y + h, height)):
            rows[yy][x * 3:(x + w) * 3] = colour * w

    rows = [bytearray(white * width) for _ in range(height)]
    p = scale
    points_high = height // p
    rect(rows, 16 * p, 75 * p, 140 * p, 40 * p, dark)                        # title
    for i in range(4):                                                        # transcript rows
        rect(rows, 16 * p, (150 + i * 44) * p, (280 - i * 30) * p, 22 * p, grey)
    rect(rows, 0, 340 * p, width, 24 * p, band)                               # the frame's own colour
    rect(rows, 16 * p, (points_high - 34 - 60) * p, width - 32 * p, 56 * p, capsule)   # above the home indicator
    return encode_png(width, height, rows)


def self_test(chrome, spec_path):
    frames = load_spec(spec_path)
    with tempfile.TemporaryDirectory(prefix="revox-store-selftest-") as tmp:
        tmp = Path(tmp)
        full, partial, output = tmp / "captures", tmp / "captures-missing-one", tmp / "out"
        full.mkdir()
        partial.mkdir()
        names = {f["capture"] for f in frames} | {f["fallback"]["capture"] for f in frames if "fallback" in f}
        for index, name in enumerate(sorted(names)):
            data = synthetic_capture(1290, 2796, (40 + index * 30, 120, 200 - index * 20))
            (full / f"{name}.png").write_bytes(data)
            (partial / f"{name}.png").write_bytes(data)
        # 1. Every frame composes at the canvas size, without an alpha channel.
        composed = compose(full, spec_path, output, chrome)
        assert len(composed) == len(frames), (len(composed), len(frames))
        for path in composed:
            width, height, depth, colour = png_header(path.read_bytes())
            assert (width, height) == CANVAS and colour in (0, 2), (path, width, height, colour)
        # 2. A missing capture with a fallback composes from the stand-in; one without is refused.
        with_fallback = next(f for f in frames if "fallback" in f)
        (partial / f"{with_fallback['capture']}.png").unlink()
        compose(partial, spec_path, tmp / "out-fallback", chrome, only={with_fallback["id"]}, verbose=False)
        assert (tmp / "out-fallback" / f"{with_fallback['id']}.png").exists()
        without = next(f for f in frames if "fallback" not in f)
        (partial / f"{without['capture']}.png").unlink()
        try:
            compose(partial, spec_path, tmp / "out-refused", chrome, only={without["id"]}, verbose=False)
            raise AssertionError("a missing capture without a fallback was not refused")
        except SystemExit as error:
            assert "is missing" in str(error), error
        # 3. The README render is accepted (upscaled), close-up included.
        readme = tmp / "captures-readme"
        readme.mkdir()
        close_up = next(f for f in frames if f.get("presentation") == "close-up")
        (readme / f"{close_up['capture']}.png").write_bytes(synthetic_capture(786, 1704, (200, 120, 60)))
        compose(readme, spec_path, tmp / "out-readme", chrome, only={close_up["id"]}, verbose=False)
        assert png_header((tmp / "out-readme" / f"{close_up['id']}.png").read_bytes())[:2] == CANVAS
        # 4. The bundled fonts are what Chromium set the copy in: the same panel without them renders differently.
        compose(full, spec_path, tmp / "out-nofont", chrome, only={frames[0]["id"]}, fonts={}, verbose=False)
        with_font = (output / f"{frames[0]['id']}.png").read_bytes()
        without_font = (tmp / "out-nofont" / f"{frames[0]['id']}.png").read_bytes()
        assert with_font != without_font, "the panel renders the same with and without Inter: the fonts did not load"
        # 5. The alpha strip keeps every pixel.
        rgba = encode_png(3, 2, [bytearray(b"\x10\x20\x30\xff\x40\x50\x60\xff\x70\x80\x90\xff"),
                                 bytearray(b"\x01\x02\x03\xff\x04\x05\x06\xff\x07\x08\x09\xff")], channels=4)
        assert decode_png(strip_alpha(rgba))[3] == [bytearray(b"\x10\x20\x30\x40\x50\x60\x70\x80\x90"),
                                                    bytearray(b"\x01\x02\x03\x04\x05\x06\x07\x08\x09")]
    print(f"self-test passed: {len(frames)} frames composed at {CANVAS[0]} x {CANVAS[1]}, the fallback, the refusal, "
          f"the README render, the fonts and the alpha strip checked")


def main(argv):
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0], epilog="See docs/store/README.md.")
    parser.add_argument("--input", help="folder of the captures ScreenshotTests wrote (the store-screenshots artifact)")
    parser.add_argument("--spec", default=str(DEFAULT_SPEC), help=f"the frames and their copy (default {DEFAULT_SPEC.relative_to(ROOT)})")
    parser.add_argument("--output", default=str(DEFAULT_OUTPUT), help=f"where the PNGs go (default {DEFAULT_OUTPUT.relative_to(ROOT)})")
    parser.add_argument("--chrome", help="Chromium or Chrome binary (else $CHROME, else the usual places)")
    parser.add_argument("--frame", action="append", help="compose only this frame id (repeatable)")
    parser.add_argument("--keep-panels", metavar="DIR", help="keep the HTML panels here instead of a temporary folder")
    parser.add_argument("--self-test", action="store_true", help="compose synthetic captures into a temporary folder and check the pipeline")
    args = parser.parse_args(argv)

    chrome = find_chrome(args.chrome)
    if args.self_test:
        self_test(chrome, args.spec)
        return 0
    if not args.input:
        parser.error("--input is required (or --self-test)")
    composed = compose(args.input, args.spec, args.output, chrome, only=set(args.frame) if args.frame else None,
                       keep_panels=args.keep_panels)
    print(f"composed {len(composed)} frames into {args.output}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
