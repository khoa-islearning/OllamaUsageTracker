#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

PROJECT="OllamaUsageTracker.xcodeproj"
SCHEME="OllamaUsageTracker"
ARCHIVE_PATH="build/OllamaBalance.xcarchive"
EXPORT_DIR="build/export"
DMG_STAGING="build/dmg"
APP_NAME="Ollama Balance.app"
MOUNT_POINT=""

log() {
    printf '\n==> %s\n' "$*"
}

warn() {
    printf 'warning: %s\n' "$*" >&2
}

cleanup() {
    if [[ -n "$MOUNT_POINT" ]]; then
        hdiutil detach "$MOUNT_POINT" -quiet >/dev/null 2>&1 || true
        rmdir "$MOUNT_POINT" >/dev/null 2>&1 || true
    fi
}
trap cleanup EXIT

if (( $# > 1 )); then
    printf 'Usage: ./scripts/make_release.sh [version]\n' >&2
    exit 2
fi

for tool in xcodebuild python3 hdiutil; do
    if ! command -v "$tool" >/dev/null 2>&1; then
        printf 'error: required tool not found: %s\n' "$tool" >&2
        exit 1
    fi
done

if [[ ! -d "$PROJECT" ]]; then
    printf 'error: %s was not found in %s\n' "$PROJECT" "$ROOT_DIR" >&2
    exit 1
fi

PROJECT_FILE="$PROJECT/project.pbxproj"
if [[ ! -f "$PROJECT_FILE" ]]; then
    PROJECT_FILE="$PROJECT/project.xcproj"
fi
if [[ ! -f "$PROJECT_FILE" ]]; then
    printf 'error: neither project.pbxproj nor project.xcproj exists in %s\n' "$PROJECT" >&2
    exit 1
fi

REQUESTED_VERSION="${1:-}"
if [[ "$REQUESTED_VERSION" == *'/'* || "$REQUESTED_VERSION" == *$'\n'* ]]; then
    printf 'error: version must not contain slashes or newlines\n' >&2
    exit 2
fi

if [[ -n "$REQUESTED_VERSION" ]]; then
    log "Setting both targets to version $REQUESTED_VERSION"
    python3 - "$PROJECT_FILE" "$REQUESTED_VERSION" <<'PY'
import re
import sys
from pathlib import Path

path = Path(sys.argv[1])
version = sys.argv[2]
text = path.read_text()


def replace_setting(source, setting, value):
    # Support both modern project.xcproj JSON and traditional project.pbxproj.
    pattern = re.compile(
        r'("' + re.escape(setting) + r'"\s*:\s*")([^"\n]*)(")'
        r'|(\b' + re.escape(setting) + r'\s*=\s*)([^;\n]*)(;)'
    )

    def replacement(match):
        if match.group(1) is not None:
            return match.group(1) + value + match.group(3)
        return match.group(4) + value + match.group(6)

    return pattern.subn(replacement, source)


for setting in ("MARKETING_VERSION", "CURRENT_PROJECT_VERSION"):
    text, count = replace_setting(text, setting, version)
    if count < 2:
        raise SystemExit(
            f"error: expected {setting} in both targets; found {count} occurrence(s)"
        )

path.write_text(text)
PY
fi

VERSION="$(python3 - "$PROJECT_FILE" <<'PY'
import re
import sys
from pathlib import Path

text = Path(sys.argv[1]).read_text()
patterns = (
    r'"MARKETING_VERSION"\s*:\s*"([^"\n]+)"',
    r'\bMARKETING_VERSION\s*=\s*([^;\n]+);',
)
for pattern in patterns:
    match = re.search(pattern, text)
    if match:
        print(match.group(1).strip())
        break
else:
    raise SystemExit("error: MARKETING_VERSION was not found")
PY
)"

if [[ -z "$VERSION" ]]; then
    printf 'error: MARKETING_VERSION is empty\n' >&2
    exit 1
fi

DMG_PATH="dist/OllamaBalance-${VERSION}.dmg"

DEVELOPMENT_TEAM="$(python3 - "$PROJECT_FILE" <<'PY'
import re
import sys
from pathlib import Path

text = Path(sys.argv[1]).read_text()
patterns = (
    r'"DEVELOPMENT_TEAM"\s*:\s*"([^"\n]+)"',
    r'\bDEVELOPMENT_TEAM\s*=\s*([^;\n]+);',
)
for pattern in patterns:
    match = re.search(pattern, text)
    if match:
        print(match.group(1).strip())
        break
PY
)"

mkdir -p build dist
rm -rf "$ARCHIVE_PATH" "$DMG_STAGING"
if [[ -n "$DEVELOPMENT_TEAM" ]]; then
    rm -rf "$EXPORT_DIR"
else
    mkdir -p "$EXPORT_DIR"
fi
rm -f "$DMG_PATH"

if [[ -z "$DEVELOPMENT_TEAM" ]]; then
    warn "DEVELOPMENT_TEAM is missing; automatic export cannot be configured."
    cat <<'EOF'
Manual export instructions:
  1. In Xcode, choose Product > Archive.
  2. In Organizer, select the new archive and click Distribute App.
  3. Choose Custom > Development, then Export.
  4. Export the app to: build/export
  5. Re-run this script without a version argument to package it.
EOF
fi

log "Archiving Ollama Balance $VERSION"
if [[ -n "$DEVELOPMENT_TEAM" ]]; then
    xcodebuild -project "$PROJECT" \
        -scheme "$SCHEME" \
        -destination 'platform=macOS' \
        -archivePath "$ARCHIVE_PATH" \
        archive
else
    xcodebuild -project "$PROJECT" \
        -scheme "$SCHEME" \
        -destination 'platform=macOS' \
        -archivePath "$ARCHIVE_PATH" \
        CODE_SIGNING_ALLOWED=NO \
        archive
fi

EXPORTED_APP=""
if [[ -n "$DEVELOPMENT_TEAM" ]]; then
    log "Exporting the archive with development signing"
    cat > build/ExportOptions.plist <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key>
    <string>development</string>
    <key>teamID</key>
    <string>${DEVELOPMENT_TEAM}</string>
    <key>signingStyle</key>
    <string>automatic</string>
</dict>
</plist>
EOF
    xcodebuild -exportArchive \
        -archivePath "$ARCHIVE_PATH" \
        -exportOptionsPlist build/ExportOptions.plist \
        -exportPath "$EXPORT_DIR"
    EXPORTED_APP="$(find "$EXPORT_DIR" -maxdepth 2 -type d -name '*.app' -print -quit)"
else
    # Keep going with an already-exported app or the archived app so staging,
    # DMG creation, and diagnostics can still run where possible.
    EXPORTED_APP="$(find "$EXPORT_DIR" -maxdepth 2 -type d -name '*.app' -print -quit 2>/dev/null || true)"
    if [[ -z "$EXPORTED_APP" ]]; then
        EXPORTED_APP="$(find "$ARCHIVE_PATH/Products/Applications" -maxdepth 1 -type d -name '*.app' -print -quit 2>/dev/null || true)"
        if [[ -n "$EXPORTED_APP" ]]; then
            warn "Using the app directly from the archive; inspect its signing before distribution."
        fi
    fi
fi

if [[ -z "$EXPORTED_APP" || ! -d "$EXPORTED_APP" ]]; then
    printf 'error: no exported .app was found. Complete the manual export instructions above, then re-run.\n' >&2
    exit 1
fi

log "Assembling DMG staging"
mkdir -p "$DMG_STAGING"
ditto "$EXPORTED_APP" "$DMG_STAGING/$APP_NAME"
ln -s /Applications "$DMG_STAGING/Applications"

STAGED_APP="$DMG_STAGING/$APP_NAME"
WIDGET_PATH="$STAGED_APP/Contents/PlugIns/OllamaUsageBalance.appex"
if [[ ! -d "$WIDGET_PATH" ]]; then
    # Current projects created with the longer target name use this product name.
    WIDGET_PATH="$STAGED_APP/Contents/PlugIns/OllamaUsageRemainingBalanceWidget.appex"
fi
if [[ ! -d "$WIDGET_PATH" ]]; then
    printf 'error: widget extension not found in %s/Contents/PlugIns\n' "$STAGED_APP" >&2
    exit 1
fi

log "Checking widget code signature (non-fatal)"
codesign -dv "$WIDGET_PATH" 2>&1 || warn "codesign could not inspect the widget extension"

log "Creating $DMG_PATH"
if command -v create-dmg >/dev/null 2>&1; then
    if ! create-dmg \
        --volname "Ollama Balance" \
        --window-pos 200 120 \
        --window-size 620 420 \
        --icon-size 100 \
        --icon "$APP_NAME" 155 205 \
        --app-drop-link 465 205 \
        "$DMG_PATH" \
        "$DMG_STAGING"; then
        warn "create-dmg failed; falling back to hdiutil"
        rm -f "$DMG_PATH"
    fi
fi
if [[ ! -f "$DMG_PATH" ]]; then
    hdiutil create -volname "Ollama Balance" \
        -srcfolder "$DMG_STAGING" \
        -format UDZO \
        "$DMG_PATH"
fi

log "Verifying DMG and mounted contents"
hdiutil verify "$DMG_PATH"
MOUNT_POINT="$(mktemp -d "${TMPDIR:-/tmp}/ollama-balance-dmg.XXXXXX")"
hdiutil attach "$DMG_PATH" -nobrowse -readonly -mountpoint "$MOUNT_POINT"
test -d "$MOUNT_POINT/$APP_NAME"
test -L "$MOUNT_POINT/Applications"
test "$(readlink "$MOUNT_POINT/Applications")" = "/Applications"
test -d "$MOUNT_POINT/$APP_NAME/Contents/PlugIns/$(basename "$WIDGET_PATH")"
hdiutil detach "$MOUNT_POINT" -quiet
rmdir "$MOUNT_POINT"
MOUNT_POINT=""

DMG_SIZE="$(du -h "$DMG_PATH" | awk '{print $1}')"
DMG_BYTES="$(stat -f '%z' "$DMG_PATH")"

cat <<EOF

Release ready
-------------
Version: ${VERSION}
DMG:     ${ROOT_DIR}/${DMG_PATH}
Size:    ${DMG_SIZE} (${DMG_BYTES} bytes)

Edit RELEASE_TEMPLATE.md, then create the GitHub Release from this repository root:
  gh release create "v${VERSION}" "${DMG_PATH}" --title "Ollama Balance ${VERSION}" --notes-file RELEASE_TEMPLATE.md

To add the DMG to an existing release instead:
  gh release upload "v${VERSION}" "${DMG_PATH}" --clobber
EOF
