#!/usr/bin/env python3
"""Bootstrap the Capture app in App Store Connect.

Registers the required bundle IDs and creates the iOS app record so TestFlight
uploads have somewhere to land. Idempotent: skips anything that already exists.

Auth: App Store Connect API key (.p8) signed into a short-lived ES256 JWT.

Required env:
  APP_STORE_CONNECT_ISSUER_ID   issuer UUID
Optional env:
  APP_STORE_CONNECT_KEY_ID      default Y6C8R5DA75
  APP_STORE_CONNECT_KEY_PATH    default ~/.private_keys/AuthKey_<KEY_ID>.p8
  CAPTURE_APP_NAME              default "Capture"
  CAPTURE_PRIMARY_LOCALE        default en-GB
  CAPTURE_SKU                   default capture-ios

Needs PyJWT + cryptography:  pip install pyjwt cryptography requests
"""
import os
import sys
import time
import json
import urllib.request
import urllib.error

try:
    import jwt  # PyJWT
except ImportError:
    sys.exit("Missing dependency: pip install pyjwt cryptography")

API = "https://api.appstoreconnect.apple.com/v1"

KEY_ID = os.environ.get("APP_STORE_CONNECT_KEY_ID", "Y6C8R5DA75")
KEY_PATH = os.environ.get(
    "APP_STORE_CONNECT_KEY_PATH",
    os.path.expanduser(f"~/.private_keys/AuthKey_{KEY_ID}.p8"),
)
ISSUER_ID = os.environ.get("APP_STORE_CONNECT_ISSUER_ID")
APP_NAME = os.environ.get("CAPTURE_APP_NAME", "Capture")
LOCALE = os.environ.get("CAPTURE_PRIMARY_LOCALE", "en-GB")
SKU = os.environ.get("CAPTURE_SKU", "capture-ios")

BUNDLE_IDS = [
    ("dev.crmitchelmore.capture.ios", "Capture iOS", "IOS"),
    ("dev.crmitchelmore.capture.ios.share", "Capture Share Extension", "IOS"),
    ("dev.crmitchelmore.capture.mac", "Capture macOS", "MAC_OS"),
]
PRIMARY_BUNDLE_ID = "dev.crmitchelmore.capture.ios"

if not ISSUER_ID:
    sys.exit("Set APP_STORE_CONNECT_ISSUER_ID")
if not os.path.isfile(KEY_PATH):
    sys.exit(f"API key not found: {KEY_PATH}")


def token() -> str:
    with open(KEY_PATH) as f:
        private_key = f.read()
    now = int(time.time())
    payload = {"iss": ISSUER_ID, "iat": now, "exp": now + 600, "aud": "appstoreconnect-v1"}
    return jwt.encode(payload, private_key, algorithm="ES256", headers={"kid": KEY_ID, "typ": "JWT"})


def call(method: str, path: str, body=None):
    url = path if path.startswith("http") else f"{API}{path}"
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(url, data=data, method=method)
    req.add_header("Authorization", f"Bearer {token()}")
    req.add_header("Content-Type", "application/json")
    try:
        with urllib.request.urlopen(req) as resp:
            raw = resp.read()
            return resp.status, (json.loads(raw) if raw else {})
    except urllib.error.HTTPError as e:
        raw = e.read()
        return e.code, (json.loads(raw) if raw else {})


def ensure_bundle_id(identifier, name, platform):
    status, data = call("GET", f"/bundleIds?filter[identifier]={identifier}&limit=1")
    if status == 200 and data.get("data"):
        print(f"  bundleId exists: {identifier}")
        return data["data"][0]["id"]
    status, data = call("POST", "/bundleIds", {
        "data": {"type": "bundleIds", "attributes": {
            "identifier": identifier, "name": name, "platform": platform, "seedId": None}}})
    if status in (200, 201):
        print(f"  bundleId created: {identifier}")
        return data["data"]["id"]
    print(f"  bundleId FAILED {identifier}: {status} {json.dumps(data)}")
    return None


def ensure_app():
    status, data = call("GET", f"/apps?filter[bundleId]={PRIMARY_BUNDLE_ID}&limit=1")
    if status == 200 and data.get("data"):
        print(f"  app exists: {APP_NAME} ({data['data'][0]['id']})")
        return data["data"][0]["id"]
    # Need the bundleId resource id to link.
    _, bd = call("GET", f"/bundleIds?filter[identifier]={PRIMARY_BUNDLE_ID}&limit=1")
    if not bd.get("data"):
        print("  cannot create app: primary bundleId missing")
        return None
    bundle_resource_id = bd["data"][0]["id"]
    body = {"data": {
        "type": "apps",
        "attributes": {
            "name": APP_NAME,
            "primaryLocale": LOCALE,
            "sku": SKU,
            "bundleId": PRIMARY_BUNDLE_ID,
        },
        "relationships": {
            "bundleId": {"data": {"type": "bundleIds", "id": bundle_resource_id}},
        },
    }}
    status, data = call("POST", "/apps", body)
    if status in (200, 201):
        print(f"  app created: {APP_NAME}")
        return data["data"]["id"]
    print(f"  app create returned {status}: {json.dumps(data)}")
    print("  NOTE: App creation via API may require an existing agreement/role. "
          "If this failed, create the app once in App Store Connect UI (Apps -> +).")
    return None


def main():
    print("Registering bundle IDs...")
    for ident, name, platform in BUNDLE_IDS:
        ensure_bundle_id(ident, name, platform)
    print("Ensuring app record...")
    ensure_app()
    print("Done.")


if __name__ == "__main__":
    main()
