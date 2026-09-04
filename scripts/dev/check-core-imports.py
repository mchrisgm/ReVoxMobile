#!/usr/bin/env python3
"""Find Swift files that use a public ReVoxCore type without importing the module.

`swiftc -parse` is the only compiler available on this Linux host and it does not resolve imports, so a
file can parse cleanly and still fail to build. Three CI rounds in a row were lost to exactly that, which
is what this exists to catch. String literals and comments are stripped first: `Label("Settings", …)`
would otherwise look like a use of the core `Settings` type.
"""
import pathlib
import re
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]


def core_types() -> set[str]:
    names: set[str] = set()
    for file in (ROOT / "ReVoxCore/Sources/ReVoxCore").glob("*.swift"):
        text = file.read_text()
        names |= set(re.findall(r"^public (?:final )?(?:struct|enum|class|actor|protocol) (\w+)", text, re.M))
        names |= set(re.findall(r"^public typealias (\w+)", text, re.M))
    return names


def code_only(text: str) -> str:
    text = re.sub(r'"""(?:.|\n)*?"""', " ", text)
    text = re.sub(r'"(?:\\.|[^"\\])*"', " ", text)
    text = re.sub(r"//[^\n]*", " ", text)
    return re.sub(r"/\*(?:.|\n)*?\*/", " ", text)


def changed_files() -> list[str]:
    tracked = subprocess.run(["git", "diff", "--name-only", "main...HEAD"], capture_output=True, text=True, cwd=ROOT)
    working = subprocess.run(["git", "status", "--porcelain"], capture_output=True, text=True, cwd=ROOT)
    paths = set(tracked.stdout.split())
    paths |= {line[3:] for line in working.stdout.splitlines() if line[3:].endswith(".swift")}
    return sorted(p for p in paths if p.endswith(".swift"))


def main() -> int:
    names = core_types()
    problems = []
    for path in changed_files():
        file = ROOT / path
        if not file.exists():
            continue
        text = file.read_text()
        if "import ReVoxCore" in text:
            continue
        used = sorted(n for n in names if re.search(r"\b" + n + r"\b", code_only(text)))
        if used:
            problems.append((path, used))
    for path, used in problems:
        print(f"::error::{path} uses {', '.join(used[:5])} from ReVoxCore without importing it")
    if problems:
        return 1
    print(f"core imports verified ({len(changed_files())} changed Swift files)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
