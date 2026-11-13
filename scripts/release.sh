#!/usr/bin/env bash
# Builds a universal Tilty.app, packs it into a DMG and publishes a GitHub release.
#
# Usage:
#   1. Set the new version in VERSION.
#   2. Add a "## <version>" section to CHANGELOG.md.
#   3. Commit, then run: scripts/release.sh
#
# Pass --dry-run to build the DMG without tagging or publishing.
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="$(tr -d '[:space:]' < VERSION)"
TAG="v$VERSION"
DMG="build/Tilty.dmg"
DRY_RUN=0
[[ "${1:-}" == "--dry-run" ]] && DRY_RUN=1

# Release notes come from this version's section of CHANGELOG.md.
NOTES="$(awk -v v="$VERSION" '
  $0 ~ "^## " v "([^0-9.]|$)" { found = 1; next }
  found && /^## / { exit }
  found { print }
' CHANGELOG.md)"
if [[ -z "${NOTES//[[:space:]]/}" ]]; then
  echo "CHANGELOG.md has no section for $VERSION" >&2
  exit 1
fi

if [[ "$DRY_RUN" == 0 ]]; then
  if [[ -n "$(git status --porcelain --untracked-files=no)" ]]; then
    echo "Commit your changes before releasing." >&2
    exit 1
  fi
  if git rev-parse "$TAG" >/dev/null 2>&1; then
    echo "Tag $TAG already exists. Bump VERSION first." >&2
    exit 1
  fi
fi

scripts/build-app.sh --universal

# DMG with the app and a shortcut to Applications, so people can drag it across.
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
cp -R build/Tilty.app "$STAGE/Tilty.app"
ln -s /Applications "$STAGE/Applications"
rm -f "$DMG"
hdiutil create -quiet -volname "Tilty $VERSION" -srcfolder "$STAGE" -fs HFS+ -format UDZO -ov "$DMG"
echo "Built $DMG"

if [[ "$DRY_RUN" == 1 ]]; then
  echo "Dry run. Notes for $TAG:"
  echo "$NOTES"
  exit 0
fi

git tag -a "$TAG" -m "Tilty $VERSION"
git push origin "$TAG"
printf '%s\n' "$NOTES" > build/release-notes.md
gh release create "$TAG" "$DMG" --title "Tilty $VERSION" --notes-file build/release-notes.md --latest
echo "Published $TAG"
