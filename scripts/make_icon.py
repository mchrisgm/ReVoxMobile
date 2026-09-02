#!/usr/bin/env python3
"""Generate the placeholder ReVox app icon as a 1024x1024 RGB PNG (no alpha).

Standard library only, so it runs anywhere. App Store icons must not contain
an alpha channel, hence colour type 2 (RGB).
"""

from __future__ import annotations

import math
import pathlib
import struct
import zlib

SIZE = 1024
OUTPUT = pathlib.Path(__file__).resolve().parents[1] / (
    "ReVoxMobile/Assets.xcassets/AppIcon.appiconset/AppIcon.png"
)

TOP = (14, 32, 92)  # deep navy
BOTTOM = (18, 120, 140)  # teal
INK = (255, 255, 255)


def _chunk(tag: bytes, payload: bytes) -> bytes:
    crc = zlib.crc32(tag + payload) & 0xFFFFFFFF
    return struct.pack(">I", len(payload)) + tag + payload + struct.pack(">I", crc)


def _pixel(x: int, y: int) -> tuple[int, int, int]:
    t = y / (SIZE - 1)
    background = tuple(round(a + (b - a) * t) for a, b in zip(TOP, BOTTOM))

    cx, cy = SIZE * 0.36, SIZE * 0.5
    dx, dy = x - cx, y - cy
    r = math.hypot(dx, dy)

    if r < SIZE * 0.12:  # the "voice" dot
        return INK
    if dx > 0 and abs(dy) < dx * 1.1:  # three arcs fanning out to the right
        for radius in (0.24, 0.35, 0.46):
            if abs(r - SIZE * radius) < SIZE * 0.03:
                return INK
    return background  # type: ignore[return-value]


def render() -> bytes:
    rows = bytearray()
    for y in range(SIZE):
        rows.append(0)  # PNG filter type: none
        for x in range(SIZE):
            rows.extend(_pixel(x, y))
    header = struct.pack(">IIBBBBB", SIZE, SIZE, 8, 2, 0, 0, 0)
    return (
        b"\x89PNG\r\n\x1a\n"
        + _chunk(b"IHDR", header)
        + _chunk(b"IDAT", zlib.compress(bytes(rows), 9))
        + _chunk(b"IEND", b"")
    )


if __name__ == "__main__":
    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    OUTPUT.write_bytes(render())
    print(f"wrote {OUTPUT} ({OUTPUT.stat().st_size} bytes)")
