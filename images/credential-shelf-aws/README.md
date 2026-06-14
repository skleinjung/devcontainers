# credential-shelf-aws

AWS provider for the shelf credential sidecar (`FROM`
[credential-shelf-base](../credential-shelf-base)). Exports STS credentials for the
profiles in its baked **`accounts.yaml`** from an SSO session and writes the **native AWS
shared-credentials file** at `/creds/aws/credentials` — the [SECRETS.md](../../docs/SECRETS.md)
AWS exception. Consumers read it via `AWS_SHARED_CREDENTIALS_FILE=/creds/aws/credentials`.

Published as `ghcr.io/<owner>/devcontainers/credential-shelf-aws`.

Config is split into two parts, by lifetime: the **upstream SSO session** (start URL +
region) is plain deployment env, while the **grant table** (which account/role each shelf
profile maps to) is baked into the image so a scope change is a reviewed rebuild. On
start, `generate-aws-config` renders the two into `~/.aws/config`; you then log in once.

## (a) How to configure

### Upstream SSO session — env

| Var | Purpose |
|-----|---------|
| `VEND_AWS_SSO_START_URL` | your IAM Identity Center start URL (**required**) |
| `VEND_AWS_SSO_REGION` | SSO region (default `us-east-1`) |
| `VEND_AWS_SSO_SESSION` | `[sso-session]` name in the generated config (default `sso`) |
| `VEND_REFRESH_BEFORE` | re-vend when fewer than this many seconds remain (default `900`) |

### Grant table — baked `accounts.yaml`

One entry per role to vend; the **first** also becomes `[default]` on the shelf. Consumers
select the others with `AWS_PROFILE=<name>`.

```yaml
profiles:
  - account_id: "084828590319"
    role: developer-ai-agent   # the SSO permission-set / role name
    # name: developer          # optional; defaults to <account_id>-<role>
    # region: us-west-2        # optional; defaults to VEND_AWS_SSO_REGION
  - account_id: "084828590319"
    role: view-only            # → profile name 084828590319-view-only
  - account_id: "084828590319" # config-only: NOT vended to the shelf (see below)
    role: github-app-signer
    name: kms-signer
    vend: false
```

Only `account_id` and `role` are required. `name` defaults to `<account_id>-<role>`;
`region` defaults to `VEND_AWS_SSO_REGION`; `vend` defaults to `true`.

Set `vend: false` on an entry to write it to `~/.aws/config` **but keep it off the
shelf** — use this for a role another sidecar consumes over the shared `admin-home`
(e.g. the `kms:Sign` profile `credential-shelf-github` reads via `VEND_GH_AWS_PROFILE`),
so that capability never reaches consumers.

> **Temporary.** `vend: false` is a shelf-era stopgap: the shelf is all-or-nothing, so a
> role another sidecar needs has no home except "on the shelf for everyone" or "off it, via
> the shared home." Once per-container vending lands (the **broker** —
> [docs/CREDENTIAL-BROKER.md](../../docs/CREDENTIAL-BROKER.md)), that role is granted to the
> one sidecar that needs it and nowhere else, and this flag goes away.

The baked default is `profiles: []` (the sidecar idles). Provide your own by **deriving an
image** — not a `/workspace` bind-mount — so a scope change is a reviewed rebuild:

```dockerfile
FROM ghcr.io/<owner>/devcontainers/credential-shelf-aws:latest
COPY accounts.yaml /etc/credential-shelf/accounts.yaml
```

`generate-aws-config` turns this into one `[sso-session]` block plus one `[profile]` per
entry. The full SSO session stays in this container; only the listed roles' ≤1h
credentials reach the shelf.

## (b) How to authenticate (once the container is running)

`generate-aws-config` runs at start and writes `~/.aws/config`, but the sidecar can't vend
until it holds an SSO session. Log in **once per SSO session** (org default ~8h), from a
**host** terminal — the session lives only in the sidecar, never in a consumer:

```sh
docker exec -it <project>-credential-shelf-aws-1 aws sso login --sso-session sso
```

(`sso` is the default session name; use your `VEND_AWS_SSO_SESSION` if you changed it.)
Within ~60s it vends. Check health from anywhere that mounts the shelf:

```sh
cat /creds/status/aws        # → ok expires=…   (or: stalled … fix="run 'aws sso login' …")
```

When the session lapses, consumers' `aws` calls fail with `ExpiredToken` and the loop
stamps `stalled`; repeat the `aws sso login` above. To prove a fresh config end-to-end
without waiting for the loop: `docker exec … vend-aws-creds --once` (vends once, exits
nonzero on failure).

## Vends

- `/creds/aws/credentials` — `[default]` + a section per profile.
- `/creds/aws/expiration` — earliest expiry across profiles (drives re-vend).
- `/creds/status/aws` — `ok expires=…` / `stalled …` health stamp.
