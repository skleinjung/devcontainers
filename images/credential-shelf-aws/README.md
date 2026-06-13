# credential-shelf-aws

AWS provider for the shelf credential sidecar (`FROM`
[credential-shelf-base](../credential-shelf-base)). Exports STS credentials for the
configured profiles from an SSO session and writes the **native AWS shared-credentials
file** at `/creds/aws/credentials` — the [SECRETS.md](../../docs/SECRETS.md) AWS
exception. Consumers read it via `AWS_SHARED_CREDENTIALS_FILE=/creds/aws/credentials`.

Published as `ghcr.io/<owner>/devcontainers/credential-shelf-aws`.

## Configuration

| Var | Purpose |
|-----|---------|
| `VEND_AWS_PROFILES` | space-separated profiles in `~/.aws/config` to vend; the **first** also becomes `[default]` |
| `VEND_REFRESH_BEFORE` | re-vend when fewer than this many seconds remain (default `900`) |

The full SSO session stays in this container; only the listed roles' ≤1h credentials
reach the shelf. With no/expired session the loop logs and waits — run `aws sso login`
here (and see the shared-home note in
[credential-shelf-base](../credential-shelf-base#deployment-pattern-shelf-sidecars)).

## Vends

- `/creds/aws/credentials` — `[default]` + a section per profile.
- `/creds/aws/expiration` — earliest expiry across profiles (drives re-vend).
- `/creds/status/aws` — `ok expires=…` / `stalled …` health stamp.
