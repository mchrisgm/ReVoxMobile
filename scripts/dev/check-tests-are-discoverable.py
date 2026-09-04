"""Find `func test…` methods that XCTest will never run.

A test method only runs if its enclosing type is an XCTestCase subclass. Put one in a helper class — easy to do
when a test file keeps its recorders below the test class and something appends to the end of the file — and it
compiles, passes review, and is silently never executed. Three such tests shipped green in CI that way.

Usage: python3 scripts/dev/check-tests-are-discoverable.py [paths...]   (default: the two test trees)
"""
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
DEFAULT_PATHS = ["ReVoxMobileTests", "ReVoxCore/Tests"]
# `final class Foo: XCTestCase, Bar {` / `class Foo: Baz {` — captures the name and its inheritance clause.
TYPE = re.compile(r"^(?:public |internal |private |fileprivate )?(?:final )?(class|struct|enum|actor|extension)\s+(\w+)\s*(?::\s*([^{]*))?\{", re.M)
TEST_FUNC = re.compile(r"^\s+(?:@MainActor\s+)?(?:public |internal |private |fileprivate )?func (test\w*)\s*\(", re.M)


def code_only(text):
    text = re.sub(r'"""(?:.|\n)*?"""', " ", text)
    text = re.sub(r'"(?:\\.|[^"\\])*"', ' "" ', text)
    text = re.sub(r"//[^\n]*", " ", text)
    return re.sub(r"/\*(?:.|\n)*?\*/", " ", text)


def type_spans(text):
    """(name, inherits, start, end) for each top-level type, by brace matching from its opening brace."""
    spans = []
    for match in TYPE.finditer(text):
        kind, name, inherits = match.group(1), match.group(2), match.group(3) or ""
        depth, index = 0, match.end() - 1
        while index < len(text):
            if text[index] == "{":
                depth += 1
            elif text[index] == "}":
                depth -= 1
                if depth == 0:
                    break
            index += 1
        spans.append((name, inherits, kind, match.end(), index))
    return spans


def main(argv):
    paths = [a for a in argv[1:] if not a.startswith("-")] or DEFAULT_PATHS
    problems = []
    checked = 0
    for entry in paths:
        base = ROOT / entry
        files = sorted(base.rglob("*.swift")) if base.is_dir() else [base]
        for path in files:
            text = code_only(path.read_text())
            spans = type_spans(text)
            # A type is a test case if it names XCTestCase, or inherits a type in this file that does.
            cases = {name for name, inherits, _, _, _ in spans if "XCTestCase" in inherits}
            for _ in range(3):
                cases |= {name for name, inherits, _, _, _ in spans
                          if any(re.search(r"\b" + c + r"\b", inherits) for c in cases)}
            for match in TEST_FUNC.finditer(text):
                checked += 1
                offset = match.start()
                owners = [name for name, _, _, start, end in spans if start <= offset <= end]
                if not any(owner in cases for owner in owners):
                    line = text[:offset].count("\n") + 1
                    relative = path.relative_to(ROOT) if path.is_relative_to(ROOT) else path
                    owner = owners[-1] if owners else "file scope"
                    problems.append(f"{relative}:{line}: {match.group(1)} is declared in `{owner}`, "
                                    f"which is not an XCTestCase — XCTest will never run it")
    for problem in problems:
        print(f"::error::{problem}")
    if problems:
        return 1
    print(f"every test method is inside an XCTestCase ({checked} across {', '.join(paths)})")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
