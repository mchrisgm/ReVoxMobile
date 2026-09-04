"""Verify the Info.plists, privacy manifests and entitlements before a build or an upload (design spec §11, C7, §5.6).

Exit 0 when every rule holds; prints one line per violation and exits 1 otherwise.
"""
import plistlib
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
APP_PLIST = ROOT / "ReVoxMobile" / "Info.plist"
EXT_PLIST = ROOT / "ReVoxBroadcast" / "Info.plist"
APP_PRIVACY = ROOT / "ReVoxMobile" / "PrivacyInfo.xcprivacy"
EXT_PRIVACY = ROOT / "ReVoxBroadcast" / "PrivacyInfo.xcprivacy"
APP_ENTITLEMENTS = ROOT / "ReVoxMobile" / "ReVoxMobile.entitlements"
EXT_ENTITLEMENTS = ROOT / "ReVoxBroadcast" / "ReVoxBroadcast.entitlements"
APP_GROUPS_ENTITLEMENT = "com.apple.security.application-groups"
MEMORY_ENTITLEMENT = "com.apple.developer.kernel.increased-memory-limit"
EXPECTED_APP_GROUPS = ["group.$(REVOX_BUNDLE_PREFIX).revox"]

APP_REASONS = {
    "NSPrivacyAccessedAPICategoryUserDefaults": {"CA92.1", "1C8F.1"},
    "NSPrivacyAccessedAPICategoryFileTimestamp": {"C617.1"},
    "NSPrivacyAccessedAPICategoryDiskSpace": {"E174.1", "85F4.1"},
}
EXT_REASONS = {
    "NSPrivacyAccessedAPICategoryUserDefaults": {"1C8F.1"},
    "NSPrivacyAccessedAPICategoryFileTimestamp": {"C617.1"},
}
FORBIDDEN_CATEGORIES = {"NSPrivacyAccessedAPICategorySystemBootTime"}


def load(path):
    with open(path, "rb") as handle:
        return plistlib.load(handle)


def check_app_plist(problems):
    plist = load(APP_PLIST)
    if plist.get("ITSAppUsesNonExemptEncryption") is not False:
        problems.append(f"{APP_PLIST}: ITSAppUsesNonExemptEncryption must be false")
    description = plist.get("NSMicrophoneUsageDescription", "")
    if not description or not description.endswith("."):
        problems.append(f"{APP_PLIST}: NSMicrophoneUsageDescription must be a complete sentence ending with a period")
    if "audio" not in plist.get("UIBackgroundModes", []):
        problems.append(f"{APP_PLIST}: UIBackgroundModes must contain audio")
    for key in ("REVOXAppGroup", "REVOXBroadcastExtensionBundleID"):
        if not plist.get(key):
            problems.append(f"{APP_PLIST}: missing {key}")


def check_extension_plist(problems):
    plist = load(EXT_PLIST)
    if plist.get("ITSAppUsesNonExemptEncryption") is not False:
        problems.append(f"{EXT_PLIST}: ITSAppUsesNonExemptEncryption must be false")
    if not plist.get("REVOXAppGroup"):
        problems.append(f"{EXT_PLIST}: missing REVOXAppGroup")
    extension = plist.get("NSExtension", {})
    if extension.get("NSExtensionPointIdentifier") != "com.apple.broadcast-services-upload":
        problems.append(f"{EXT_PLIST}: NSExtensionPointIdentifier must be com.apple.broadcast-services-upload")
    if extension.get("RPBroadcastProcessMode") != "RPBroadcastProcessModeSampleBuffer":
        problems.append(f"{EXT_PLIST}: RPBroadcastProcessMode must be a direct child of NSExtension")


def check_privacy(path, expected, problems):
    manifest = load(path)
    if manifest.get("NSPrivacyTracking") is not False:
        problems.append(f"{path}: NSPrivacyTracking must be false")
    if manifest.get("NSPrivacyCollectedDataTypes"):
        problems.append(f"{path}: NSPrivacyCollectedDataTypes must be empty")
    declared = {}
    for entry in manifest.get("NSPrivacyAccessedAPITypes", []):
        category = entry.get("NSPrivacyAccessedAPIType")
        declared[category] = set(entry.get("NSPrivacyAccessedAPITypeReasons", []))
    for category in FORBIDDEN_CATEGORIES & set(declared):
        problems.append(f"{path}: {category} must not be declared (no host-time API is used, §11)")
    for category, reasons in expected.items():
        if not reasons <= declared.get(category, set()):
            problems.append(f"{path}: {category} must declare {sorted(reasons)}, found {sorted(declared.get(category, set()))}")


def check_entitlements(problems):
    """Design spec §5.6 and §11: the memory entitlement is on the app only; both targets share exactly one App Group."""
    app = load(APP_ENTITLEMENTS)
    extension = load(EXT_ENTITLEMENTS)
    for path, entitlements in ((APP_ENTITLEMENTS, app), (EXT_ENTITLEMENTS, extension)):
        if entitlements.get(APP_GROUPS_ENTITLEMENT) != EXPECTED_APP_GROUPS:
            problems.append(f"{path}: {APP_GROUPS_ENTITLEMENT} must be exactly {EXPECTED_APP_GROUPS}")
    if app.get(MEMORY_ENTITLEMENT) is not True:
        problems.append(f"{APP_ENTITLEMENTS}: {MEMORY_ENTITLEMENT} must be true (design spec §5.6)")
    if MEMORY_ENTITLEMENT in extension:
        problems.append(f"{EXT_ENTITLEMENTS}: {MEMORY_ENTITLEMENT} must never be declared for the extension (design spec §11)")


def main():
    problems = []
    check_app_plist(problems)
    check_extension_plist(problems)
    check_privacy(APP_PRIVACY, APP_REASONS, problems)
    check_privacy(EXT_PRIVACY, EXT_REASONS, problems)
    check_entitlements(problems)
    for problem in problems:
        print(f"::error::{problem}")
    if problems:
        return 1
    print("plists and privacy manifests verified")
    return 0


if __name__ == "__main__":
    sys.exit(main())
