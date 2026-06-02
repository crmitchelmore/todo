#!/bin/bash
# Generate Sparkle appcast.xml for a Capture macOS release.
# Usage: ./scripts/generate-appcast.sh <version> <build-number> <archive-path> <private-key-base64>
#   version       Marketing version (e.g. 0.1.0), display + download URL.
#   build-number  CFBundleVersion (e.g. 202606030130); Sparkle compares on this.
#   archive-path  Path to the notarised Capture-<version>.zip enclosure.
#   private-key   Sparkle EdDSA private key (base64, the 44-char string from generate_keys -x).
#
# Emits the appcast XML to stdout. The enclosure URL points at the GitHub
# release asset; SUFeedURL in Info.plist resolves to releases/latest/download/appcast.xml.
set -euo pipefail

VERSION="${1:?version}"
BUILD_NUMBER="${2:?build number}"
ARCHIVE_PATH="${3:?archive path}"
PRIVATE_KEY_BASE64="${4:?private key (base64)}"

FILE_SIZE=$(stat -f%z "$ARCHIVE_PATH" 2>/dev/null || stat --format=%s "$ARCHIVE_PATH")
PUB_DATE=$(date -R 2>/dev/null || date)
ARCHIVE_NAME=$(basename "$ARCHIVE_PATH")

PRIVATE_KEY_FILE=$(mktemp)
trap 'rm -f "$PRIVATE_KEY_FILE"' EXIT
printf '%s\n' "$PRIVATE_KEY_BASE64" > "$PRIVATE_KEY_FILE"

# Locate sign_update (committed Sparkle artifact, PATH, or download as fallback).
SIGN_UPDATE=""
for c in \
  "clients/apps/.sparkle/bin/sign_update" \
  "$HOME/Library/Developer/Xcode/DerivedData"/*/SourcePackages/artifacts/sparkle/Sparkle/bin/sign_update; do
  if [ -f "$c" ]; then SIGN_UPDATE="$c"; break; fi
done
if [ -z "$SIGN_UPDATE" ] && command -v sign_update >/dev/null 2>&1; then
  SIGN_UPDATE="sign_update"
fi
if [ -z "$SIGN_UPDATE" ]; then
  echo "Downloading Sparkle tools..." >&2
  SPARKLE_VERSION="2.6.4"
  curl -sL "https://github.com/sparkle-project/Sparkle/releases/download/${SPARKLE_VERSION}/Sparkle-${SPARKLE_VERSION}.tar.xz" | tar xJ -C /tmp
  SIGN_UPDATE="/tmp/bin/sign_update"
fi

SIGN_OUT=$("$SIGN_UPDATE" --ed-key-file "$PRIVATE_KEY_FILE" "$ARCHIVE_PATH")
SIGNATURE=$(printf '%s' "$SIGN_OUT" | sed -n 's/.*sparkle:edSignature="\([^"]*\)".*/\1/p')
if [ -z "$SIGNATURE" ]; then
  echo "Error: failed to generate EdDSA signature" >&2
  exit 1
fi

DOWNLOAD_URL="https://github.com/crmitchelmore/todo/releases/download/mac-v${VERSION}/${ARCHIVE_NAME}"

LAST_TAG=$(git describe --tags --abbrev=0 --match 'mac-v*' HEAD^ 2>/dev/null || echo "")
if [ -n "$LAST_TAG" ]; then
  RELEASE_NOTES=$(git log "$LAST_TAG"..HEAD --pretty=format:"<li>%s</li>" 2>/dev/null | head -20 || echo "")
fi
[ -n "${RELEASE_NOTES:-}" ] || RELEASE_NOTES="<li>Improvements and fixes</li>"
# Guard against a commit subject containing the CDATA terminator, which would
# otherwise produce invalid appcast XML and break Sparkle feed parsing.
RELEASE_NOTES=${RELEASE_NOTES//]]>/]]&gt;}

cat << EOF
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle" xmlns:dc="http://purl.org/dc/elements/1.1/">
  <channel>
    <title>Capture Updates</title>
    <link>https://github.com/crmitchelmore/todo/releases/latest/download/appcast.xml</link>
    <description>Most recent updates to Capture</description>
    <language>en</language>
    <item>
      <title>Version ${VERSION}</title>
      <sparkle:version>${BUILD_NUMBER}</sparkle:version>
      <sparkle:shortVersionString>${VERSION}</sparkle:shortVersionString>
      <pubDate>${PUB_DATE}</pubDate>
      <description><![CDATA[
        <h2>What's New in ${VERSION}</h2>
        <ul>
          ${RELEASE_NOTES}
        </ul>
      ]]></description>
      <enclosure
        url="${DOWNLOAD_URL}"
        sparkle:edSignature="${SIGNATURE}"
        length="${FILE_SIZE}"
        type="application/octet-stream"/>
      <sparkle:minimumSystemVersion>12.0</sparkle:minimumSystemVersion>
    </item>
  </channel>
</rss>
EOF
