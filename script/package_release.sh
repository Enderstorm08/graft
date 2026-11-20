#!/usr/bin/env bash
set -euo pipefail

if [[ $# != 2 || ! -x "$1" ]]; then
  echo "Usage: $0 /path/to/sparkle/bin/sign_update /path/to/output" >&2
  exit 2
fi
SIGN_UPDATE="$(cd "$(dirname "$1")" && pwd)/$(basename "$1")"
if [[ "$(uname -m)" != "arm64" ]]; then
  echo "Graft's current Mac release channel targets Apple Silicon. Run on an Apple Silicon Mac." >&2
  exit 1
fi
mkdir -p "$2"
OUTPUT="$(cd "$2" && pwd)"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/graft-release.XXXXXX")"
trap 'rm -rf "$WORK_DIR"' EXIT
ACCOUNT="com.itsasheruwu.graft.mac"

npm run build
GRAFT_ENABLE_UPDATES=1 GRAFT_DIST_DIR="$WORK_DIR" GRAFT_BUILD_CONFIGURATION=release script/build_and_run.sh build

APP="$WORK_DIR/Graft.app"
PLIST="$APP/Contents/Info.plist"
VERSION="$(/usr/bin/plutil -extract CFBundleVersion raw "$PLIST")"
MINIMUM_OS="$(/usr/bin/plutil -extract LSMinimumSystemVersion raw "$PLIST")"
PUBLIC_KEY="$(/usr/bin/plutil -extract SUPublicEDKey raw "$PLIST")"
if [[ "$("$(dirname "$SIGN_UPDATE")/generate_keys" --account "$ACCOUNT" -p)" != "$PUBLIC_KEY" ]]; then
  echo "The Graft release signing key in this Keychain does not match the app." >&2
  exit 1
fi
MAC_ARCHIVE="Graft-Mac.zip"
RELEASE_URL="https://github.com/itsasheruwu/graft/releases/tag/v$VERSION"
DOWNLOAD_URL="https://github.com/itsasheruwu/graft/releases/download/v$VERSION/$MAC_ARCHIVE"

/usr/bin/ditto -c -k --sequesterRsrc --keepParent "$APP" "$WORK_DIR/$MAC_ARCHIVE"
(cd dist && /usr/bin/zip -q -r "$WORK_DIR/Graft-Chrome.zip" manifest.json *.html assets src)

SIGNATURE="$("$SIGN_UPDATE" --account "$ACCOUNT" -p "$WORK_DIR/$MAC_ARCHIVE")"
"$SIGN_UPDATE" --account "$ACCOUNT" --verify "$WORK_DIR/$MAC_ARCHIVE" "$SIGNATURE"
LENGTH="$(/usr/bin/stat -f %z "$WORK_DIR/$MAC_ARCHIVE")"

cat > "$WORK_DIR/appcast.xml" <<XML
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>Graft for Mac</title>
    <sparkle:bundleIdentifier>$ACCOUNT</sparkle:bundleIdentifier>
    <item>
      <title>Graft $VERSION</title>
      <sparkle:version>$VERSION</sparkle:version>
      <sparkle:shortVersionString>$VERSION</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>$MINIMUM_OS</sparkle:minimumSystemVersion>
      <description><![CDATA[<p><a href="$RELEASE_URL">Read the Graft $VERSION release notes on GitHub.</a></p>]]></description>
      <enclosure url="$DOWNLOAD_URL" type="application/octet-stream" length="$LENGTH" sparkle:edSignature="$SIGNATURE" />
    </item>
  </channel>
</rss>
XML

"$SIGN_UPDATE" --account "$ACCOUNT" "$WORK_DIR/appcast.xml"
"$SIGN_UPDATE" --account "$ACCOUNT" --verify "$WORK_DIR/appcast.xml"
mv "$WORK_DIR/$MAC_ARCHIVE" "$WORK_DIR/Graft-Chrome.zip" "$WORK_DIR/appcast.xml" "$OUTPUT/"
