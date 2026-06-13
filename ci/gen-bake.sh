#!/usr/bin/env bash
#
# gen-bake.sh — generate a Docker Bake definition (JSON) for every image in the
# repo, on stdout. One bake `target` per images/<name>/ directory containing a
# Dockerfile. Intra-repo dependencies are declared per image by a `from` file
# (one line: the parent image's name) and rendered as a named build context
#   contexts = { <parent> = "target:<parent>" }
# so a dependent's `FROM <parent>` resolves to the locally-built parent target —
# no registry round-trip, so it works on PRs/forks before anything is published.
#
# Tags and OCI labels are derived from the GitHub Actions context env (falling
# back to a local `dev` tag off-CI). All targets are always defined; the workflow
# selects which to build by passing target names to `docker buildx bake`.
#
# Env:
#   IMAGE_PREFIX     registry/namespace, e.g. ghcr.io/owner/devcontainers  [default: local stand-in]
#   DEFAULT_BRANCH   branch that gets the `latest` tag                      [default: main]
#   GITHUB_*         standard Actions context (event name, ref, sha, repo)
#
set -euo pipefail

IMAGES_DIR="images"
IMAGE_PREFIX="${IMAGE_PREFIX:-ghcr.io/local/devcontainers}"
IMAGE_PREFIX="${IMAGE_PREFIX,,}" # registries require lowercase
DEFAULT_BRANCH="${DEFAULT_BRANCH:-main}"

EVENT="${GITHUB_EVENT_NAME:-}"
REF="${GITHUB_REF:-}"
REF_TYPE="${GITHUB_REF_TYPE:-}"
REF_NAME="${GITHUB_REF_NAME:-}"
SHA="${GITHUB_SHA:-}"
REPO="${GITHUB_REPOSITORY:-local/devcontainers}"
SHORT="${SHA:0:7}"
SOURCE_URL="https://github.com/${REPO}"
CREATED="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

warn() { printf 'gen-bake: %s\n' "$*" >&2; }

# Tags for an image, as a JSON array. Mirrors the docker/metadata-action rules:
#   - sha-<short> always (immutable handle)
#   - pull_request -> pr-<n>
#   - tag push vX.Y.Z -> X.Y.Z and X.Y (else the raw tag)
#   - branch push -> <branch>, plus `latest` on the default branch
#   - nothing resolvable (local) -> dev
tags_for() {
  local name="$1" img="${IMAGE_PREFIX}/$1" out=()
  [ -n "$SHORT" ] && out+=("$img:sha-$SHORT")
  if [ "$EVENT" = pull_request ]; then
    local n="${REF#refs/pull/}"; n="${n%/merge}"
    out+=("$img:pr-${n:-unknown}")
  elif [ "$REF_TYPE" = tag ]; then
    local v="${REF_NAME#v}"
    if [[ "$v" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
      out+=("$img:$v" "$img:${v%.*}")
    else
      out+=("$img:$REF_NAME")
    fi
  elif [ "$REF_TYPE" = branch ]; then
    out+=("$img:$REF_NAME")
    [ "$REF_NAME" = "$DEFAULT_BRANCH" ] && out+=("$img:latest")
  fi
  [ "${#out[@]}" -gt 0 ] || out+=("$img:dev")
  printf '%s\n' "${out[@]}" | jq -R . | jq -cs .
}

targets='{}'
for dockerfile in "$IMAGES_DIR"/*/Dockerfile; do
  [ -e "$dockerfile" ] || continue
  name="$(basename "$(dirname "$dockerfile")")"

  contexts='{}'
  if [ -f "$IMAGES_DIR/$name/from" ]; then
    parent="$(tr -d '[:space:]' <"$IMAGES_DIR/$name/from")"
    if [ -n "$parent" ]; then
      [ -f "$IMAGES_DIR/$parent/Dockerfile" ] \
        || warn "image '$name' declares parent '$parent', but $IMAGES_DIR/$parent/Dockerfile does not exist"
      contexts="$(jq -nc --arg p "$parent" '{($p): ("target:" + $p)}')"
    fi
  fi

  labels="$(jq -nc \
    --arg src "$SOURCE_URL" --arg rev "$SHA" --arg created "$CREATED" --arg title "$name" '
    {
      "org.opencontainers.image.source": $src,
      "org.opencontainers.image.revision": $rev,
      "org.opencontainers.image.created": $created,
      "org.opencontainers.image.title": $title
    }')"

  target="$(jq -nc \
    --arg ctx "$IMAGES_DIR/$name" \
    --argjson tags "$(tags_for "$name")" \
    --argjson contexts "$contexts" \
    --argjson labels "$labels" \
    --arg scope "$name" '
    {
      context: $ctx,
      dockerfile: "Dockerfile",
      tags: $tags,
      labels: $labels,
      "cache-from": ["type=gha,scope=\($scope)"],
      "cache-to": ["type=gha,scope=\($scope),mode=max"]
    }
    + (if ($contexts | length) > 0 then { contexts: $contexts } else {} end)')"

  targets="$(jq -nc --argjson acc "$targets" --arg name "$name" --argjson t "$target" \
    '$acc + {($name): $t}')"
done

jq -nc --argjson t "$targets" '{target: $t}'
