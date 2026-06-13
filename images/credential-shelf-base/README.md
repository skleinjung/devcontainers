# credential-shelf-base

The **engine** for shelf credential sidecars — generic plumbing, no provider logic.
Provider images (`credential-shelf-aws`, `credential-shelf-github`, …) build
`FROM` this and add a single minting tool + vend script.

Published as `ghcr.io/<owner>/devcontainers/credential-shelf-base`.

## What it ships

- **`/usr/local/lib/sidecar-lib.sh`** — sourced helpers that standardize the
  [SECRETS.md](../../docs/SECRETS.md) shelf conventions: `sc_atomic_write`,
  `sc_write_payload` (the `{value,expires_at}` JSON), `sc_status_ok` / `sc_status_stalled`
  (the `/creds/status/<name>` health stamps), and `sc_log`.
- The unprivileged `vscode` user and `/creds` ownership so a fresh shelf volume is
  writable by the vend loops (consumers mount the same volume read-only).

It carries **no** provider tooling on purpose — each generator brings its own (the AWS
providers install the AWS CLI), so a non-AWS provider isn't forced to ship it.

## Writing a provider

```dockerfile
FROM credential-shelf-base
USER root
# install this provider's minting tool…
COPY bin/ /usr/local/bin/
USER vscode
CMD ["vend-myprovider"]
```

```sh
# bin/vend-myprovider
. /usr/local/lib/sidecar-lib.sh
log() { sc_log vend-myprovider "$@"; }
while true; do
  # …mint a short-lived secret…
  sc_write_payload "$SC_SHELF_DIR/myprovider/thing" "$token" "$exp_epoch"
  sc_status_ok myprovider "$exp_epoch"
  sleep 60
done
```

## Deployment pattern (shelf sidecars)

Each provider sidecar is a compose service that **writes the shared `creds-shelf` volume
read-write**; consumers mount the same volume **read-only**. AWS-backed providers also
need an AWS identity — **mount the same home volume into every AWS-touching sidecar so a
single `aws sso login` serves all of them**:

```yaml
services:
  aws-creds:
    image: ghcr.io/<owner>/devcontainers/credential-shelf-aws:latest
    volumes: [creds-shelf:/creds, admin-home:/home/vscode]
  github-creds:
    image: ghcr.io/<owner>/devcontainers/credential-shelf-github:latest
    volumes: [creds-shelf:/creds, admin-home:/home/vscode]   # same home → one SSO login
  workspace:
    volumes: [creds-shelf:/creds:ro]                         # read-only in consumers

volumes: { creds-shelf: {}, admin-home: {} }
```

> The shared home means every sidecar holds the full SSO session, so this split is for
> code/operational modularity, not (yet) a blast-radius reduction. Removing the shared
> home — having one sidecar vend a narrow role to another — is the **broker** path; see
> [CREDENTIAL-BROKER.md](../../docs/CREDENTIAL-BROKER.md).
