# credential-shelf-base — the engine for shelf credential sidecars.
#
# Generic plumbing only: the shelf-write conventions (atomic writes, the
# {value,expires_at} payload, /creds/status/<name> health stamps — see docs/SECRETS.md)
# in a sourced shell library, plus the user + /creds ownership setup. Provider images
# build FROM this, add their own minting tool + vend script, and source the library:
#
#   FROM credential-shelf-base
#   # ...install the provider's tooling, COPY its vend script...
#   CMD ["vend-<provider>"]
#
# It deliberately carries NO provider tooling (no AWS CLI, etc.) — each generator brings
# its own, so a non-AWS provider isn't forced to ship the AWS CLI.
#
# A sidecar is a *service*, not a devcontainer, so this uses a minimal debian-slim base
# rather than the heavy dev image — smaller image, smaller attack surface for a trusted
# container. It stays on glibc (not Alpine/musl) because the AWS-backed providers install
# the official AWS CLI v2, which is glibc-only; the vend scripts also use bash + GNU
# `date`, both absent/different on Alpine's busybox.
FROM debian:stable-slim

# Runtime deps the engine + the providers' shells need (providers add their own minting
# tools). `vscode` (uid/gid 1000) matches the consumer uid so the 0600 shelf files this
# writes are readable on the consumer's read-only mount.
RUN apt-get update \
  && apt-get install -y --no-install-recommends bash ca-certificates curl jq \
  && rm -rf /var/lib/apt/lists/* \
  && groupadd -g 1000 vscode \
  && useradd -m -u 1000 -g 1000 -s /bin/bash vscode

COPY lib/sidecar-lib.sh /usr/local/lib/sidecar-lib.sh

# Seed /creds ownership so a fresh shelf volume is writable by the vend loops; consumers
# mount the same volume read-only.
RUN mkdir -p /creds && chown vscode /creds

USER vscode
WORKDIR /home/vscode
# No default CMD — a provider image sets its own.
