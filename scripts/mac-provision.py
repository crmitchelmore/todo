#!/usr/bin/env python3
"""Create or fetch a Developer ID (MAC_APP_DIRECT) provisioning profile for the
Capture Mac app and write it to disk so the CI archive step can embed it.

Sign in with Apple is a *restricted* entitlement: a Developer ID (non-App-Store)
macOS app that declares com.apple.developer.applesignin must be signed with a
provisioning profile that authorises that entitlement, embedded at
  Capture.app/Contents/embedded.provisionprofile
Without it the app builds/notarises but ASAuthorizationController fails at runtime.

This script is idempotent: it reuses an existing valid MAC_APP_DIRECT profile for
the bundle id if one exists, otherwise creates one bound to the Developer ID
Application certificate(s). The profile inherits whatever capabilities are enabled
on the App ID, so "Sign in with Apple" must already be enabled on the bundle id in
the Apple Developer portal (and grouped under the primary App ID for a shared sub).

Auth: App Store Connect API key (.p8) signed into a short-lived ES256 JWT.

Required env:
  APP_STORE_CONNECT_ISSUER_ID   issuer UUID
Optional env:
  APP_STORE_CONNECT_KEY_ID      default Y6C8R5DA75
  APP_STORE_CONNECT_KEY_PATH    default ~/.private_keys/AuthKey_<KEY_ID>.p8
  MAC_BUNDLE_ID                 default dev.crmitchelmore.capture.mac
  PROFILE_NAME                  default "Capture Mac Developer ID"
  OUTPUT_PATH                   default ./CaptureMac_DeveloperID.provisionprofile

Prints two lines to stdout for the caller to capture:
  PROFILE_NAME=<name>
  PROFILE_PATH=<path>

Needs PyJWT + cryptography:  pip install pyjwt cryptography
"""
import base64
import json
import os
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

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
BUNDLE_ID = os.environ.get("MAC_BUNDLE_ID", "dev.crmitchelmore.capture.mac")
PROFILE_NAME = os.environ.get("PROFILE_NAME", "Capture Mac Developer ID")
OUTPUT_PATH = os.environ.get(
    "OUTPUT_PATH", os.path.abspath("./CaptureMac_DeveloperID.provisionprofile")
)
PROFILE_TYPE = "MAC_APP_DIRECT"

if not ISSUER_ID:
    sys.exit("Set APP_STORE_CONNECT_ISSUER_ID")
if not os.path.isfile(KEY_PATH):
    sys.exit(f"API key not found: {KEY_PATH}")


def token() -> str:
    with open(KEY_PATH) as f:
        private_key = f.read()
    now = int(time.time())
    payload = {"iss": ISSUER_ID, "iat": now, "exp": now + 600, "aud": "appstoreconnect-v1"}
    return jwt.encode(payload, private_key, algorithm="ES256",
                      headers={"kid": KEY_ID, "typ": "JWT"})


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


def bundle_resource_id() -> str:
    status, data = call("GET", f"/bundleIds?filter[identifier]={BUNDLE_ID}&limit=1")
    if status != 200 or not data.get("data"):
        sys.exit(f"bundleId {BUNDLE_ID} not found in portal: {status} {json.dumps(data)}")
    return data["data"][0]["id"]


def assert_siwa_enabled(bundle_res: str) -> None:
    status, data = call("GET", f"/bundleIds/{bundle_res}/bundleIdCapabilities?limit=50")
    caps = [c.get("attributes", {}).get("capabilityType") for c in data.get("data", [])]
    if "APPLE_ID_AUTH" not in caps:
        sys.exit(
            f"Sign in with Apple (APPLE_ID_AUTH) is NOT enabled on {BUNDLE_ID}. "
            f"Enable it in the Apple Developer portal first. Capabilities seen: {caps}"
        )
    print(f"  Sign in with Apple capability present on {BUNDLE_ID}")


def developer_id_cert_ids() -> list:
    status, data = call(
        "GET", "/certificates?filter[certificateType]=DEVELOPER_ID_APPLICATION&limit=50")
    if status != 200 or not data.get("data"):
        sys.exit(f"No DEVELOPER_ID_APPLICATION certificate found: {status} {json.dumps(data)}")
    return [c["id"] for c in data["data"]]


def find_existing_profile():
    status, data = call(
        "GET",
        f"/profiles?filter[name]={urllib.parse.quote(PROFILE_NAME)}"
        f"&filter[profileType]={PROFILE_TYPE}&limit=10&include=bundleId",
    )
    if status != 200:
        return None
    for prof in data.get("data", []):
        attrs = prof.get("attributes", {})
        if attrs.get("profileState") == "ACTIVE" and attrs.get("profileContent"):
            return prof
    return None


def delete_profile(profile_id: str) -> None:
    call("DELETE", f"/profiles/{profile_id}")


def create_profile(bundle_res: str, cert_ids: list):
    body = {
        "data": {
            "type": "profiles",
            "attributes": {"name": PROFILE_NAME, "profileType": PROFILE_TYPE},
            "relationships": {
                "bundleId": {"data": {"type": "bundleIds", "id": bundle_res}},
                "certificates": {
                    "data": [{"type": "certificates", "id": cid} for cid in cert_ids]
                },
            },
        }
    }
    status, data = call("POST", "/profiles", body)
    if status not in (200, 201):
        sys.exit(f"profile create failed: {status} {json.dumps(data)}")
    return data["data"]


def main():
    print(f"Provisioning {PROFILE_TYPE} profile '{PROFILE_NAME}' for {BUNDLE_ID}...")
    bundle_res = bundle_resource_id()
    assert_siwa_enabled(bundle_res)

    prof = find_existing_profile()
    if prof:
        # Recreate so the profile always reflects current certs + capabilities.
        print(f"  replacing existing profile {prof['id']}")
        delete_profile(prof["id"])

    cert_ids = developer_id_cert_ids()
    print(f"  using {len(cert_ids)} Developer ID certificate(s)")
    prof = create_profile(bundle_res, cert_ids)

    content_b64 = prof["attributes"]["profileContent"]
    with open(OUTPUT_PATH, "wb") as f:
        f.write(base64.b64decode(content_b64))
    print(f"  wrote {OUTPUT_PATH}")
    # Machine-readable for the workflow.
    print(f"PROFILE_NAME={PROFILE_NAME}")
    print(f"PROFILE_PATH={OUTPUT_PATH}")


if __name__ == "__main__":
    main()
