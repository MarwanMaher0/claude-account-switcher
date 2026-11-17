#!/usr/bin/env bash
# Publish the GitHub release for a tag, or update it when it already exists, so a
# rerun of the tag workflow repairs a half-finished release instead of failing.
# DIR holds notes.md, cc-switch-binding-X.Y.Z.vsix and SHA256SUMS; the assets are
# verified (test/release-assets.sh) before gh is called at all.
#
#   bash test/publish-release.sh --repo OWNER/NAME vX.Y.Z DIR
#
# New release: gh release create with both assets and the notes.
# Existing release: gh release upload --clobber, then gh release edit for the notes.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

die() {
    printf 'publish-release: %s\n' "$1" >&2
    exit 1
}

usage() {
    echo "usage: bash test/publish-release.sh --repo OWNER/NAME vX.Y.Z DIR" >&2
    exit 2
}

repo=""
tag=""
dir=""
while [ "$#" -gt 0 ]; do
    case "$1" in
        --repo)
            [ "$#" -ge 2 ] || usage
            repo="$2"
            shift 2
            ;;
        -*) usage ;;
        *)
            if [ -z "$tag" ]; then tag="$1"
            elif [ -z "$dir" ]; then dir="$1"
            else usage
            fi
            shift
            ;;
    esac
done
[ -n "$repo" ] && [ -n "$tag" ] && [ -n "$dir" ] || usage

notes="$dir/notes.md"
vsix="$dir/cc-switch-binding-${tag#v}.vsix"
sums="$dir/SHA256SUMS"

[ -s "$notes" ] || die "missing $notes; run test/check-release.sh --notes-out first"
bash "$HERE/release-assets.sh" verify "$dir" "$tag" || exit 1

view_err="$(gh release view "$tag" --repo "$repo" --json tagName 2>&1 >/dev/null)"
view_rc=$?
if [ "$view_rc" -eq 0 ]; then
    gh release upload "$tag" "$vsix" "$sums" --repo "$repo" --clobber \
        || die "could not re-upload the assets to $tag"
    gh release edit "$tag" --repo "$repo" --title "$tag" --notes-file "$notes" \
        || die "could not update the notes of $tag"
    echo "updated the existing release $tag"
    exit 0
fi
case "$view_err" in
    *"release not found"*) ;;
    *) die "cannot tell whether $tag is released: ${view_err:-gh exited $view_rc}" ;;
esac
gh release create "$tag" "$vsix" "$sums" --repo "$repo" --title "$tag" \
    --notes-file "$notes" --verify-tag \
    || die "could not create the release $tag"
echo "created the release $tag"
