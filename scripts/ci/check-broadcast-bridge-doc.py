#!/usr/bin/env python3
"""docs/broadcast-bridge.md must describe exactly the ring header that ReVoxCore implements (design spec §5.9, A5).

Parses the "| Offset | Size | Type | Field | ..." table of the document and compares every row's offset with the
`public static let <field> = <offset>` constants of `RingHeader.Offset`, and the layout numbers with `RingLayout.v1`.
Exit 0 when everything matches; prints one line per mismatch and exits 1 otherwise.
"""
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
DOC = ROOT / "docs" / "broadcast-bridge.md"
SOURCE = ROOT / "ReVoxCore" / "Sources" / "ReVoxCore" / "RingBridge.swift"

# Document field name → Swift `Offset` constant name.
FIELD_TO_OFFSET = {
    "magic": "magic", "headerBytes": "headerBytes", "capacityFrames": "capacityFrames", "sampleRate": "sampleRate",
    "channels": "channels", "sampleFormat": "sampleFormat", "generation": "generation", "writeCursor": "writeCursor",
    "readCursor": "readCursor", "state": "state", "asbdChangeCount": "asbdChangeCount", "lastWriteAt": "lastWriteAt",
    "startedAt": "startedAt", "lastPTS.value": "lastPTSValue", "lastPTS.timescale": "lastPTSTimescale",
    "lastPTS.flags": "lastPTSFlags", "lastAsbdChangeAt": "lastAsbdChangeAt", "sourceASBD": "sourceASBD",
    "droppedInputFrames": "droppedInputFrames", "micBuffersSeen": "micBuffersSeen", "overrunCount": "overrunCount",
    "peakLevel1s": "peakLevel1s", "rmsLevel1s": "rmsLevel1s", "writerPID": "writerPID", "reserved": "reservedStart",
}
EXPECTED_SIZES = {
    "magic": 8, "headerBytes": 4, "capacityFrames": 4, "sampleRate": 4, "channels": 2, "sampleFormat": 2, "generation": 8,
    "writeCursor": 8, "readCursor": 8, "state": 4, "asbdChangeCount": 4, "lastWriteAt": 8, "startedAt": 8, "lastPTS.value": 8,
    "lastPTS.timescale": 4, "lastPTS.flags": 4, "lastAsbdChangeAt": 8, "sourceASBD": 40, "droppedInputFrames": 8,
    "micBuffersSeen": 8, "overrunCount": 8, "peakLevel1s": 4, "rmsLevel1s": 4, "writerPID": 4, "reserved": 3924,
}


def swift_offsets(text):
    offsets = {}
    block = re.search(r"public enum Offset \{(.*?)\n    \}", text, re.S)
    if not block:
        return offsets
    for name, value in re.findall(r"public static let (\w+) = (\d+)", block.group(1)):
        offsets[name] = int(value)
    return offsets


def swift_layout(text):
    match = re.search(r'RingLayout\(magic: "(\w+)", headerBytes: ([\d_]+), capacityFrames: ([\d_]+), sampleRate: ([\d_]+)\)', text)
    file_name = re.search(r'public static let fileName = "([^"]+)"', text)
    if not match or not file_name:
        return None
    return {
        "magic": match.group(1), "headerBytes": int(match.group(2).replace("_", "")),
        "capacityFrames": int(match.group(3).replace("_", "")), "sampleRate": int(match.group(4).replace("_", "")),
        "fileName": file_name.group(1),
    }


def doc_rows(text):
    rows = {}
    for line in text.splitlines():
        match = re.match(r"^\|\s*(\d+)\s*\|\s*([\d\s]+)\s*\|[^|]*\|\s*`?([\w.]+)`?\s*\|", line)
        if match:
            rows[match.group(3)] = (int(match.group(1)), int(match.group(2).replace(" ", "")))
    return rows


def main():
    problems = []
    source = SOURCE.read_text(encoding="utf-8")
    doc = DOC.read_text(encoding="utf-8")
    offsets = swift_offsets(source)
    layout = swift_layout(source)
    rows = doc_rows(doc)
    if not offsets or layout is None:
        problems.append(f"{SOURCE}: could not parse RingHeader.Offset / RingLayout.v1")
    for field, offset_name in FIELD_TO_OFFSET.items():
        if field not in rows:
            problems.append(f"{DOC}: header table is missing the row for `{field}`")
            continue
        doc_offset, doc_size = rows[field]
        if offsets.get(offset_name) != doc_offset:
            problems.append(f"{DOC}: `{field}` documented at offset {doc_offset}, RingHeader.Offset.{offset_name} is {offsets.get(offset_name)}")
        if EXPECTED_SIZES[field] != doc_size:
            problems.append(f"{DOC}: `{field}` documented with size {doc_size}, expected {EXPECTED_SIZES[field]}")
    if layout:
        for token in (layout["magic"], layout["fileName"], f"{layout['headerBytes']:,}".replace(",", " "), f"{layout['capacityFrames']:,}".replace(",", " ")):
            if token not in doc:
                problems.append(f"{DOC}: does not mention `{token}` from RingLayout.v1")
        if "3 844 096" not in doc:
            problems.append(f"{DOC}: does not state the total file size 3 844 096")
    for problem in problems:
        print(f"::error::{problem}")
    if problems:
        return 1
    print(f"broadcast-bridge.md matches RingHeader.Offset ({len(FIELD_TO_OFFSET)} rows) and RingLayout.v1")
    return 0


if __name__ == "__main__":
    sys.exit(main())
