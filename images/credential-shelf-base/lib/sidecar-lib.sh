# sidecar-lib.sh — shared helpers for credential-shelf provider images.
#
# Source it:  . /usr/local/lib/sidecar-lib.sh
#
# Standardizes the shelf-write conventions in docs/SECRETS.md: atomic writes, the
# {value,expires_at} payload for token kinds, and /creds/status/<name> health stamps.
# Providers keep their own minting + loop; this is just the boilerplate.

SC_SHELF_DIR="${VEND_SHELF_DIR:-/creds}"

# sc_log <prefix> <msg...>   — timestamped line to stdout.
sc_log() { local p="$1"; shift; printf '%s %s: %s\n' "$(date -Is)" "$p" "$*"; }

# sc_atomic_write <dest>   (content on stdin) — write to a temp file in dest's dir
# (mktemp => 0600), then rename into place so readers never see a partial file.
sc_atomic_write() {
  local dest="$1" dir tmp
  dir="$(dirname "$dest")"
  mkdir -p "$dir"
  tmp="$(mktemp "$dir/.tmp.XXXXXX")"
  cat >"$tmp"
  mv "$tmp" "$dest"
}

# sc_write_payload <dest> <value> <expires_epoch|''>  — the {value,expires_at} shelf JSON.
sc_write_payload() {
  jq -nc --arg v "$2" --argjson e "${3:-null}" '{value: $v, expires_at: $e}' | sc_atomic_write "$1"
}

# sc_status_ok <name> <expires: epoch | iso | 'unknown'>  — health stamp at status/<name>.
sc_status_ok() {
  local exp="${2:-unknown}"
  [[ "$exp" =~ ^[0-9]+$ ]] && exp="$(date -d "@$exp" -Is 2>/dev/null || echo unknown)"
  printf 'ok expires=%s\n' "$exp" | sc_atomic_write "$SC_SHELF_DIR/status/$1"
}

# sc_status_stalled <name> <fix-text> [<since-iso>]
sc_status_stalled() {
  printf 'stalled since=%s fix="%s"\n' "${3:-$(date -Is)}" "$2" | sc_atomic_write "$SC_SHELF_DIR/status/$1"
}
