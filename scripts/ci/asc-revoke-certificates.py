#!/usr/bin/env python3
"""Revoke Apple Development certificates through the App Store Connect API.

Automatic signing archives with an Apple Development certificate, and every GitHub runner is a fresh machine, so
Xcode creates a new certificate on every TestFlight run and its private key is thrown away with the runner. Apple
caps development certificates per account; build 22 hit the cap ("Choose a certificate to revoke. Your account
has reached the maximum number of certificates"). This script runs at the end of every automatic-signing run and
revokes the certificate that run created — found by serial number in the run's own temporary keychain, so nothing
else on the account is ever touched — which keeps the count flat. `--all-development` is the owner's one-time
cleanup of the ones earlier builds left behind (any Mac that used one re-creates it with one click in Xcode).

Only the standard library and the `openssl` and `security` command-line tools are used, so the runner needs no
extra packages. The API token is an ES256 JWT (Apple's `appstoreconnect-v1` audience) signed with the same .p8
key `xcodebuild -allowProvisioningUpdates` uses.

Exit status is 0 whatever happened — this is housekeeping after the build and must never turn a green run red;
problems are printed as GitHub warning annotations instead. `--self-test` checks the signature plumbing offline.
"""

import argparse
import base64
import json
import os
import subprocess
import sys
import tempfile
import time
import urllib.error
import urllib.request

API = "https://api.appstoreconnect.apple.com/v1"


def b64url(data: bytes) -> str:
    return base64.urlsafe_b64encode(data).rstrip(b"=").decode("ascii")


def der_to_raw(signature: bytes, size: int = 32) -> bytes:
    """An ECDSA signature as OpenSSL writes it (DER SEQUENCE of two INTEGERs) to the fixed-width r||s JWTs carry."""
    if not signature or signature[0] != 0x30:
        raise ValueError("not a DER SEQUENCE")
    index = 2 if signature[1] < 0x80 else 2 + (signature[1] & 0x7F)
    out = b""
    for _ in range(2):
        if signature[index] != 0x02:
            raise ValueError("expected a DER INTEGER")
        length = signature[index + 1]
        value = signature[index + 2:index + 2 + length]
        index += 2 + length
        value = value.lstrip(b"\x00") or b"\x00"
        if len(value) > size:
            raise ValueError("integer wider than the curve")
        out += value.rjust(size, b"\x00")
    return out


def raw_to_der(raw: bytes, size: int = 32) -> bytes:
    """The inverse, for the self-test: r||s back to the DER form `openssl dgst -verify` reads."""
    def integer(value: bytes) -> bytes:
        value = value.lstrip(b"\x00") or b"\x00"
        if value[0] & 0x80:
            value = b"\x00" + value
        return b"\x02" + bytes([len(value)]) + value
    body = integer(raw[:size]) + integer(raw[size:])
    return b"\x30" + bytes([len(body)]) + body


def sign_es256(key_path: str, message: bytes) -> bytes:
    with tempfile.NamedTemporaryFile(delete=False) as handle:
        handle.write(message)
        message_path = handle.name
    try:
        der = subprocess.run(["openssl", "dgst", "-sha256", "-sign", key_path, "-binary", message_path],
                             check=True, capture_output=True).stdout
    finally:
        os.unlink(message_path)
    return der_to_raw(der)


def make_token(key_id: str, issuer_id: str, key_path: str, now: int | None = None) -> str:
    now = int(time.time()) if now is None else now
    header = b64url(json.dumps({"alg": "ES256", "kid": key_id, "typ": "JWT"}, separators=(",", ":")).encode())
    payload = b64url(json.dumps({"iss": issuer_id, "iat": now, "exp": now + 600, "aud": "appstoreconnect-v1"},
                                separators=(",", ":")).encode())
    signing_input = f"{header}.{payload}".encode("ascii")
    return f"{header}.{payload}.{b64url(sign_es256(key_path, signing_input))}"


def request(token: str, method: str, url: str) -> tuple[int, dict]:
    req = urllib.request.Request(url, method=method, headers={"Authorization": f"Bearer {token}", "Accept": "application/json"})
    try:
        with urllib.request.urlopen(req, timeout=60) as response:
            body = response.read()
            return response.status, (json.loads(body) if body else {})
    except urllib.error.HTTPError as error:
        body = error.read()
        try:
            return error.code, json.loads(body) if body else {}
        except json.JSONDecodeError:
            return error.code, {"raw": body.decode("utf-8", "replace")}


def normalize_serial(serial: str) -> str:
    return serial.strip().upper().replace(":", "").lstrip("0")


def keychain_development_serials(keychain: str) -> list[str]:
    """Serial numbers of the Apple Development certificates in a keychain (`security` + `openssl`, no parsing of our own)."""
    pem = subprocess.run(["security", "find-certificate", "-a", "-p", keychain], check=False, capture_output=True, text=True).stdout
    serials = []
    for block in pem.split("-----END CERTIFICATE-----"):
        if "-----BEGIN CERTIFICATE-----" not in block:
            continue
        certificate = block[block.index("-----BEGIN CERTIFICATE-----"):] + "-----END CERTIFICATE-----\n"
        info = subprocess.run(["openssl", "x509", "-noout", "-serial", "-subject"], input=certificate,
                              check=False, capture_output=True, text=True).stdout
        if "Apple Development" not in info:
            continue
        for line in info.splitlines():
            if line.startswith("serial="):
                serials.append(normalize_serial(line[len("serial="):]))
    return serials


def list_development_certificates(token: str) -> list[dict]:
    certificates = []
    url = f"{API}/certificates?filter[certificateType]=DEVELOPMENT&limit=200"
    while url:
        status, body = request(token, "GET", url)
        if status != 200:
            raise RuntimeError(f"GET certificates returned {status}: {json.dumps(body)[:300]}")
        certificates.extend(body.get("data", []))
        url = body.get("links", {}).get("next")
    return certificates


def revoke(token: str, certificates: list[dict]) -> int:
    revoked = 0
    for certificate in certificates:
        attributes = certificate.get("attributes", {})
        status, body = request(token, "DELETE", f"{API}/certificates/{certificate['id']}")
        label = f"{attributes.get('name', '?')} serial {attributes.get('serialNumber', '?')} (expires {attributes.get('expirationDate', '?')})"
        if status == 204:
            print(f"revoked {label}")
            revoked += 1
        else:
            print(f"::warning::could not revoke {label}: {status} {json.dumps(body)[:200]}")
    return revoked


def self_test() -> int:
    with tempfile.TemporaryDirectory() as directory:
        ec = os.path.join(directory, "ec.pem")
        key = os.path.join(directory, "key.p8")
        public = os.path.join(directory, "pub.pem")
        subprocess.run(["openssl", "ecparam", "-name", "prime256v1", "-genkey", "-noout", "-out", ec], check=True, capture_output=True)
        subprocess.run(["openssl", "pkcs8", "-topk8", "-nocrypt", "-in", ec, "-out", key], check=True, capture_output=True)
        subprocess.run(["openssl", "ec", "-in", ec, "-pubout", "-out", public], check=True, capture_output=True)
        token = make_token("KEYID", "issuer", key, now=1_700_000_000)
        header, payload, signature = token.split(".")
        assert json.loads(base64.urlsafe_b64decode(header + "==")) == {"alg": "ES256", "kid": "KEYID", "typ": "JWT"}
        claims = json.loads(base64.urlsafe_b64decode(payload + "=="))
        assert claims["aud"] == "appstoreconnect-v1" and claims["exp"] - claims["iat"] == 600
        raw = base64.urlsafe_b64decode(signature + "==")
        assert len(raw) == 64, len(raw)
        der_path = os.path.join(directory, "sig.der")
        message_path = os.path.join(directory, "msg")
        with open(der_path, "wb") as handle:
            handle.write(raw_to_der(raw))
        with open(message_path, "wb") as handle:
            handle.write(f"{header}.{payload}".encode("ascii"))
        verified = subprocess.run(["openssl", "dgst", "-sha256", "-verify", public, "-signature", der_path, message_path],
                                  check=False, capture_output=True, text=True)
        assert "Verified OK" in verified.stdout, verified.stdout + verified.stderr
        assert normalize_serial("00:aB:0c") == "AB0C"
        assert der_to_raw(raw_to_der(bytes(range(1, 65)))) == bytes(range(1, 65))
    print("self-test passed: ES256 JWT verifies with openssl, serials normalise")
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--key-id")
    parser.add_argument("--issuer-id")
    parser.add_argument("--key-path")
    scope = parser.add_mutually_exclusive_group()
    scope.add_argument("--keychain", help="revoke the Apple Development certificates found in this keychain (this run's)")
    scope.add_argument("--all-development", action="store_true", help="revoke every Apple Development certificate on the team")
    parser.add_argument("--self-test", action="store_true")
    args = parser.parse_args()
    if args.self_test:
        return self_test()
    if not (args.key_id and args.issuer_id and args.key_path and os.path.exists(args.key_path)):
        print("::warning::asc-revoke-certificates: no App Store Connect API key on this runner; nothing revoked")
        return 0
    try:
        if args.all_development:
            wanted = None
        elif args.keychain and os.path.exists(args.keychain):
            wanted = keychain_development_serials(args.keychain)
            if not wanted:
                print("no Apple Development certificate in this run's keychain; nothing to revoke")
                return 0
            print(f"this run's keychain holds Apple Development serial(s): {', '.join(wanted)}")
        else:
            print("no signing keychain on this runner; nothing to revoke")
            return 0
        token = make_token(args.key_id, args.issuer_id, args.key_path)
        certificates = list_development_certificates(token)
        print(f"the team has {len(certificates)} Apple Development certificate(s)")
        if wanted is not None:
            certificates = [c for c in certificates if normalize_serial(c.get("attributes", {}).get("serialNumber", "")) in wanted]
            if not certificates:
                print("::warning::this run's certificate was not found on App Store Connect; nothing revoked")
                return 0
        revoked = revoke(token, certificates)
        print(f"revoked {revoked} certificate(s)")
    except Exception as error:  # noqa: BLE001 — housekeeping never fails the build
        print(f"::warning::asc-revoke-certificates: {error}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
