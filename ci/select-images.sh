#!/usr/bin/env bash
#
# select-images.sh — decide which images (bake targets) to (re)build and emit a
# GitHub Actions output line on stdout:
#
#     images=["base","default"]
#
# An "image" is any directory under images/ that contains a Dockerfile. The build
# set is:
#   * EVERY image  — when BUILD_ALL is truthy, when a shared build path (this
#     script, the bake generator, or the build workflow) changed, or when the diff
#     base is unknown (first push / force-push / shallow clone);
#   * otherwise the images whose own directory changed between BASE_SHA and
#     HEAD_SHA, PLUS their transitive dependents (if `base` changed, `default`
#     rebuilds too). Dependencies are declared per image by a `from` file.
#
# (Note: bake pulls in the *ancestors* of a built target automatically, so we only
# need to expand downward — to dependents — here.)
#
# Inputs (env):
#   BUILD_ALL   truthy (true/1/yes) forces the full set                [default: false]
#   BASE_SHA    git ref to diff against (PR base, or push "before" sha) [default: empty]
#   HEAD_SHA    git ref for the new state                              [default: HEAD]
#
# Diagnostics go to stderr; only the `images=...` line goes to stdout, so in CI:
#   ./ci/select-images.sh >> "$GITHUB_OUTPUT"
#
set -euo pipefail

IMAGES_DIR="images"
BUILD_ALL="${BUILD_ALL:-false}"
BASE_SHA="${BASE_SHA:-}"
HEAD_SHA="${HEAD_SHA:-HEAD}"

log() { printf '%s\n' "$*" >&2; }
emit() { printf 'images=%s\n' "$1"; }

# Compact, sorted, de-duplicated JSON array from newline-delimited stdin.
to_json() { sort -u | jq -R . | jq -cs .; }

# Names of all images (directories under images/ holding a Dockerfile).
list_all() {
  local dockerfile
  for dockerfile in "$IMAGES_DIR"/*/Dockerfile; do
    [ -e "$dockerfile" ] || continue
    basename "$(dirname "$dockerfile")"
  done
}

# In-repo parent of an image (its `from` file), or empty.
parent_of() { [ -f "$IMAGES_DIR/$1/from" ] && tr -d '[:space:]' <"$IMAGES_DIR/$1/from" || true; }

# Read a newline-delimited image set on stdin; print it plus all transitive
# dependents (children whose `from` points, directly or via a chain, into the set).
expand_dependents() {
  local sel changed img p
  sel="$(grep -v '^$' || true)"
  changed=1
  while [ "$changed" = 1 ]; do
    changed=0
    for img in "${ALL[@]}"; do
      printf '%s\n' "$sel" | grep -qxF "$img" && continue
      p="$(parent_of "$img")"
      if [ -n "$p" ] && printf '%s\n' "$sel" | grep -qxF "$p"; then
        sel+=$'\n'"$img"
        changed=1
      fi
    done
  done
  printf '%s\n' "$sel" | grep -v '^$' | sort -u
}

mapfile -t ALL < <(list_all)
if [ "${#ALL[@]}" -eq 0 ]; then
  log "no images found under $IMAGES_DIR/"
  emit '[]'
  exit 0
fi

build_all() {
  log "selecting ALL images: ${ALL[*]}"
  printf '%s\n' "${ALL[@]}" | to_json
}

case "$BUILD_ALL" in
  true | 1 | yes | YES | True | TRUE)
    emit "$(build_all)"
    exit 0
    ;;
esac

# Without a resolvable base commit we can't diff — build everything to be safe.
if [ -z "$BASE_SHA" ] || ! git rev-parse --quiet --verify "$BASE_SHA^{commit}" >/dev/null 2>&1; then
  log "no usable base ref (BASE_SHA='${BASE_SHA:-unset}'); building all"
  emit "$(build_all)"
  exit 0
fi

changed="$(git diff --name-only "$BASE_SHA" "$HEAD_SHA")"
log "changed files ($BASE_SHA..$HEAD_SHA):"
printf '%s\n' "$changed" | sed 's/^/  /' >&2

# A change to the pipeline itself can affect every image — rebuild all of them.
if printf '%s\n' "$changed" | grep -qE '^(ci/|\.github/workflows/build-images\.ya?ml$)'; then
  log "shared build path changed; building all"
  emit "$(build_all)"
  exit 0
fi

# Map changed files of the form images/<name>/... to <name>, keeping only those
# that still have a Dockerfile (so deleting an image doesn't try to build it).
directly_changed="$(
  printf '%s\n' "$changed" \
    | sed -n "s#^${IMAGES_DIR}/\([^/]*\)/.*#\1#p" \
    | while read -r name; do
        [ -f "$IMAGES_DIR/$name/Dockerfile" ] && printf '%s\n' "$name"
      done
)"

if [ -z "$directly_changed" ]; then
  log "no image directories changed; nothing to build"
  emit '[]'
  exit 0
fi

log "directly changed: $(printf '%s ' $directly_changed)"
selected="$(printf '%s\n' "$directly_changed" | expand_dependents)"
log "selected (with dependents): $(printf '%s ' $selected)"
emit "$(printf '%s\n' "$selected" | to_json)"
