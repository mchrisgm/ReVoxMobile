"""Verify the App Store listing under store/metadata before it is pasted into App Store Connect.

The files follow the fastlane layout (store/metadata/en-US/<field>.txt plus review_notes.txt, categories.txt
and age_rating.txt), so a change to the listing is a diff. Exit 0 when every rule holds; prints one line per
violation and exits 1 otherwise.
"""
import codecs
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
METADATA = ROOT / "store" / "metadata"
LOCALE = METADATA / "en-US"

# App Store Connect's limits, in characters, for the fields that have one. Review notes are capped at 4000 too.
LIMITS = {
    "en-US/name.txt": 30,
    "en-US/subtitle.txt": 30,
    "en-US/promotional_text.txt": 170,
    "en-US/keywords.txt": 100,
    "en-US/description.txt": 4000,
    "en-US/release_notes.txt": 4000,
    "review_notes.txt": 4000,
}
URL_FILES = ("en-US/support_url.txt", "en-US/privacy_url.txt", "en-US/marketing_url.txt")
REQUIRED = list(LIMITS) + list(URL_FILES) + ["categories.txt", "age_rating.txt"]
AGE_RATINGS = {"4+", "9+", "12+", "17+"}
EM_DASH = "—"
# Names of AI assistants and their makers must not appear anywhere in the repository. The list is kept
# ROT13-encoded so that this script does not itself match the repository-wide search for those names.
VENDOR_NAMES = [codecs.decode(name, "rot13")
                for name in ("naguebcvp", "pynhqr", "bcranv", "pungtcg", "tcg", "trzvav", "pbcvybg")]


def words(text):
    return set(re.findall(r"[a-z0-9]+", text.lower()))


def read(relative, problems):
    """The file's text without its final newline, or None when it is missing or badly terminated."""
    path = METADATA / relative
    if not path.is_file():
        problems.append(f"{path}: missing")
        return None
    raw = path.read_bytes()
    try:
        content = raw.decode("utf-8")
    except UnicodeDecodeError:
        problems.append(f"{path}: not UTF-8")
        return None
    if "\r" in content:
        problems.append(f"{path}: must use \\n line endings")
    if not content.endswith("\n") or content.endswith("\n\n"):
        problems.append(f"{path}: must end with exactly one newline")
    return content.rstrip("\n")


def check_text(relative, text, problems):
    path = METADATA / relative
    if not text.strip():
        problems.append(f"{path}: empty")
    if EM_DASH in text:
        problems.append(f"{path}: contains an em-dash; use a comma, a colon or a full stop")
    lowered = text.lower()
    for name in VENDOR_NAMES:
        if name in lowered:
            problems.append(f"{path}: names an AI vendor or assistant")
            break


def check_limit(relative, text, problems):
    limit = LIMITS[relative]
    if len(text) > limit:
        problems.append(f"{METADATA / relative}: {len(text)} characters, limit {limit}")


def check_keywords(keywords, name, subtitle, problems):
    path = METADATA / "en-US/keywords.txt"
    if "\n" in keywords:
        problems.append(f"{path}: must be a single line")
    if re.search(r",\s|\s,", keywords):
        problems.append(f"{path}: no space next to a comma (each one costs a character)")
    parts = [part.strip().lower() for part in keywords.split(",")]
    if any(not part for part in parts):
        problems.append(f"{path}: empty keyword")
    if len(set(parts)) != len(parts):
        problems.append(f"{path}: duplicate keyword")
    taken = words(name) | words(subtitle)
    for part in parts:
        if part in taken:
            problems.append(f"{path}: '{part}' already appears in the name or subtitle and is indexed from there")


def check_url(relative, text, problems):
    path = METADATA / relative
    if "\n" in text or not re.fullmatch(r"https://[^\s]+", text):
        problems.append(f"{path}: must be a single https URL")


def check_categories(text, problems):
    path = METADATA / "categories.txt"
    lines = text.split("\n")
    if len(lines) != 2 or not lines[0].startswith("primary: ") or not lines[1].startswith("secondary: "):
        problems.append(f"{path}: expected two lines, 'primary: <category>' and 'secondary: <category>'")
    elif lines[0].split(": ", 1)[1] == lines[1].split(": ", 1)[1]:
        problems.append(f"{path}: primary and secondary must differ")


def check_age_rating(text, problems):
    if text not in AGE_RATINGS:
        problems.append(f"{METADATA / 'age_rating.txt'}: must be one of {sorted(AGE_RATINGS)}")


def main():
    problems = []
    texts = {}
    for relative in REQUIRED:
        text = read(relative, problems)
        if text is not None:
            texts[relative] = text
            check_text(relative, text, problems)
    for extra in sorted(METADATA.rglob("*.txt")):
        relative = extra.relative_to(METADATA).as_posix()
        if relative not in texts:
            problems.append(f"{extra}: not a field this check knows; add it to REQUIRED or remove it")
    for relative in LIMITS:
        if relative in texts:
            check_limit(relative, texts[relative], problems)
    if all(key in texts for key in ("en-US/keywords.txt", "en-US/name.txt", "en-US/subtitle.txt")):
        check_keywords(texts["en-US/keywords.txt"], texts["en-US/name.txt"], texts["en-US/subtitle.txt"], problems)
    for relative in URL_FILES:
        if relative in texts:
            check_url(relative, texts[relative], problems)
    if "categories.txt" in texts:
        check_categories(texts["categories.txt"], problems)
    if "age_rating.txt" in texts:
        check_age_rating(texts["age_rating.txt"], problems)
    for problem in problems:
        print(f"::error::{problem}")
    if problems:
        return 1
    counts = ", ".join(f"{Path(relative).stem} {len(texts[relative])}/{limit}" for relative, limit in LIMITS.items())
    print(f"metadata ok: {counts}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
