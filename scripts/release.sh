#!/usr/bin/env bash
# Usage: ./scripts/release.sh 1.0.0
set -euo pipefail

VERSION="${1:-}"
if [ -z "$VERSION" ]; then
  echo "Usage: $0 <version> (e.g. ./scripts/release.sh 1.0.0)"
  exit 1
fi

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="/tmp/lumo-release-$VERSION"
APP="$BUILD_DIR/Lumo.app"
ZIP="$BUILD_DIR/Lumo.zip"

echo "=== Packaging Lumo v$VERSION ==="

# ── 1. Code Signing Identity ──────────────────────────────────────────────────
IDENTITY=$(security find-identity -v -p codesigning 2>/dev/null | grep "Developer ID Application" | head -1 | sed 's/.*"\(Developer ID Application[^"]*\)".*/\1/' || true)

if [ -n "$IDENTITY" ]; then
  echo "✓ Using Apple Developer ID: $IDENTITY"
  SIGN_FLAGS="CODE_SIGN_IDENTITY=$IDENTITY CODE_SIGNING_REQUIRED=YES CODE_SIGNING_ALLOWED=YES"
else
  echo "ℹ No Developer ID Application certificate found. Building with ad-hoc signing."
  SIGN_FLAGS="CODE_SIGN_IDENTITY=- CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=YES"
fi

# ── 2. Xcode Release Build ────────────────────────────────────────────────────
cd "$REPO_ROOT/NotchBuddy"
rm -rf "$BUILD_DIR" && mkdir -p "$BUILD_DIR"

echo "Building Lumo (Release configuration)..."
xcodebuild \
  -project Lumo.xcodeproj \
  -scheme Lumo \
  -configuration Release \
  build \
  $SIGN_FLAGS \
  CONFIGURATION_BUILD_DIR="$BUILD_DIR"

if [ ! -d "$APP" ]; then
  echo "error: Build failed, $APP does not exist." >&2
  exit 1
fi

# ── 3. Apple Notarization (Optional) ──────────────────────────────────────────
NOTARY_PROFILE="${LUMO_NOTARY_PROFILE:-lumo-notary}"
if [ -n "$IDENTITY" ] && xcrun notarytool credentials-history --keychain-profile "$NOTARY_PROFILE" &>/dev/null; then
  echo "Submitting $APP to Apple Notary Service..."
  ditto -c -k --keepParent "$APP" "$ZIP"
  xcrun notarytool submit "$ZIP" --keychain-profile "$NOTARY_PROFILE" --wait
  xcrun stapler staple "$APP"
  spctl -a -vv "$APP" || true
  rm "$ZIP"
else
  echo "ℹ Notarization skipped (no notary profile found or ad-hoc signed)."
fi

# ── 4. Package Release Archive ────────────────────────────────────────────────
echo "Creating release zip..."
ditto -c -k --keepParent "$APP" "$ZIP"
echo "✓ Release zip created at: $ZIP"

# ── 5. Tag & GitHub Release ───────────────────────────────────────────────────
cd "$REPO_ROOT"

if git rev-parse "v$VERSION" >/dev/null 2>&1; then
  echo "Tag v$VERSION already exists locally."
else
  echo "Creating git tag v$VERSION..."
  git tag "v$VERSION"
fi

if command -v gh >/dev/null 2>&1; then
  echo "Publishing release via GitHub CLI..."
  gh release create "v$VERSION" "$ZIP" \
    --title "Lumo v$VERSION" \
    --notes "$(cat <<EOF
## Lumo v$VERSION

A native macOS notch companion for Google Antigravity CLI (\`agy\`) & Gemini models.

### Installation
1. Download **Lumo.zip**
2. Unzip and drag **Lumo.app** to your \`/Applications\` folder
3. Launch Lumo and interact with Antigravity & Gemini directly from your MacBook notch!

### Requirements
- macOS 15.0+ (Apple Silicon recommended)
- Google Antigravity CLI (\`agy\`)
EOF
)"
  echo "✓ GitHub release published successfully!"
else
  echo "ℹ 'gh' (GitHub CLI) is not installed."
  echo "  To publish this release to GitHub manually, upload:"
  echo "  -> $ZIP"
  echo "  Or install gh via: brew install gh"
fi

echo "=== Done! Lumo v$VERSION is ready at: $ZIP ==="
