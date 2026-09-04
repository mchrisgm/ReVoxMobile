"""Flag `await` inside an XCTest autoclosure argument, which never compiles.

`XCTAssertEqual`, `XCTAssertNil`, `XCTUnwrap` and friends take `@autoclosure () throws -> T`. The autoclosure is
not `async`, so `XCTAssertEqual(await next(), x)` fails with "'async' call in an autoclosure that does not support
concurrency" — a swiftc -parse clean file that costs a whole CI round. Hoist the await into a `let` first.

Usage: python3 scripts/dev/check-test-autoclosures.py [paths...]   (default: the two test trees)
"""
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
DEFAULT_PATHS = ["ReVoxMobileTests", "ReVoxCore/Tests"]
CALL = re.compile(r"\bXCT(?:Assert\w*|Unwrap)\s*\(")
AWAIT = re.compile(r"\bawait\b")


def code_only(line):
    """Drop `//` comments and string literals so text inside them never trips the check."""
    line = re.sub(r'"(?:[^"\\]|\\.)*"', '""', line)
    return line.split("//", 1)[0]


def offending_spans(line):
    """Yield the argument list of every XCTest call on the line that contains an `await`."""
    for match in CALL.finditer(line):
        depth = 0
        start = match.end() - 1
        for index in range(start, len(line)):
            if line[index] == "(":
                depth += 1
            elif line[index] == ")":
                depth -= 1
                if depth == 0:
                    arguments = line[start + 1:index]
                    if AWAIT.search(arguments):
                        yield match.group(0), arguments
                    break
        else:
            # Unbalanced on this line (a multi-line call): check what is here anyway.
            arguments = line[start + 1:]
            if AWAIT.search(arguments):
                yield match.group(0), arguments


def main(argv):
    paths = argv[1:] or DEFAULT_PATHS
    problems = []
    for entry in paths:
        base = ROOT / entry
        files = sorted(base.rglob("*.swift")) if base.is_dir() else [base]
        for path in files:
            for number, line in enumerate(path.read_text().split("\n"), start=1):
                for call, arguments in offending_spans(code_only(line)):
                    relative = path.relative_to(ROOT) if path.is_relative_to(ROOT) else path
                    problems.append(f"{relative}:{number}: `await` inside {call}…) — the autoclosure is not async; "
                                    f"bind it to a let first ({arguments.strip()[:60]}…)")
    for problem in problems:
        print(f"::error::{problem}")
    if problems:
        return 1
    print(f"no await inside an XCTest autoclosure ({', '.join(paths)})")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
