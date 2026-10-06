#!/bin/bash
# Builds a universal, Developer ID-signed, notarized Screenpop; publishes it as a
# GitHub release and points the Homebrew cask at it.
# Usage: scripts/release.sh 1.2.0   (or: make release VERSION=1.2.0)
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION=${1:?usage: scripts/release.sh <version>, e.g. 1.2.0}
TAG="v$VERSION"
REPO=${RELEASE_REPO:-bigblueboo/screenpop}
TAP=${TAP_REPO:-bigblueboo/homebrew-tap}
PROFILE=${NOTARY_PROFILE:-screenpop}
APP=build/Screenpop.app
ZIP="build/Screenpop-$VERSION.zip"

die() { echo "error: $*" >&2; exit 1; }
step() { printf '\n==> %s\n' "$*"; }

step "Preflight"
[[ $VERSION =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || die "version must look like 1.2.0"
[[ -z $(git status --porcelain) ]] || die "commit or stash your changes first"
[[ $(git branch --show-current) == main ]] || die "release from main"
git fetch -q origin main
[[ $(git rev-parse HEAD) == $(git rev-parse origin/main) ]] || die "main isn't in sync with origin/main"
! git rev-parse -q --verify "refs/tags/$TAG" >/dev/null || die "tag $TAG already exists"
IDENTITY=$(security find-identity -v -p codesigning | awk -F'"' '/Developer ID Application/ {print $2; exit}')
[[ -n $IDENTITY ]] || die "no Developer ID Application certificate in the keychain (README › Releasing)"
xcrun notarytool history --keychain-profile "$PROFILE" >/dev/null 2>&1 \
  || die "no notarytool profile '$PROFILE' (README › Releasing)"
gh auth status >/dev/null 2>&1 || die "gh isn't logged in"
gh repo view "$TAP" >/dev/null 2>&1 || die "tap repo $TAP doesn't exist"
echo "Signing as: $IDENTITY"
make test

step "Build"
make bundle UNIVERSAL=1 VERSION="$VERSION"
codesign --force --options runtime --timestamp --sign "$IDENTITY" "$APP"
codesign --verify --strict --verbose=2 "$APP"

step "Notarize"
ditto -c -k --keepParent "$APP" "$ZIP"
RESULT=$(xcrun notarytool submit "$ZIP" --keychain-profile "$PROFILE" --wait --output-format json)
STATUS=$(plutil -extract status raw -o - - <<<"$RESULT")
if [[ $STATUS != Accepted ]]; then
  xcrun notarytool log "$(plutil -extract id raw -o - - <<<"$RESULT")" --keychain-profile "$PROFILE" || true
  die "notarization: $STATUS"
fi
xcrun stapler staple "$APP"
spctl --assess --type execute --verbose=2 "$APP"
# Re-zip so the download carries the stapled ticket and opens offline.
rm "$ZIP" && ditto -c -k --keepParent "$APP" "$ZIP"
SHA=$(shasum -a 256 "$ZIP" | awk '{print $1}')

step "Publish $TAG"
git tag -a "$TAG" -m "Screenpop $VERSION"
git push -q origin "$TAG"
gh release create "$TAG" "$ZIP" --repo "$REPO" --title "Screenpop $VERSION" --generate-notes

step "Update cask in $TAP"
TAPDIR=$(mktemp -d)
gh repo clone "$TAP" "$TAPDIR" -- -q
mkdir -p "$TAPDIR/Casks"
sed -e "s/@VERSION@/$VERSION/" -e "s/@SHA256@/$SHA/" -e "s|@REPO@|$REPO|" packaging/screenpop.rb > "$TAPDIR/Casks/screenpop.rb"
git -C "$TAPDIR" add Casks/screenpop.rb
git -C "$TAPDIR" commit -q -m "screenpop $VERSION"
git -C "$TAPDIR" push -q

step "Done"
echo "brew install --cask ${TAP%%/*}/${TAP#*/homebrew-}/screenpop"
