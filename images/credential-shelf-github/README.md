# credential-shelf-github

GitHub provider for the shelf credential sidecar (`FROM`
[credential-shelf-base](../credential-shelf-base)). Mints per-org GitHub App
**installation tokens** — an App JWT signed via **AWS KMS**, exchanged for a token
narrowed to the configured repos/perms — and writes the
[SECRETS.md](../../docs/SECRETS.md) payload `{"value":"<token>","expires_at":<epoch>}`
to `/creds/github/<org>`. The App signing key never leaves KMS.

Published as `ghcr.io/<owner>/devcontainers/credential-shelf-github`.

## Configuration

**Common (env):**

| Var | Purpose |
|-----|---------|
| `VEND_GH_APP_ID` | GitHub App id |
| `VEND_GH_KMS_KEY_ID` | KMS alias/arn of the App signing key |
| `VEND_GH_AWS_PROFILE` | profile (`~/.aws/config`) holding `kms:Sign` |
| `VEND_GH_AWS_REGION` | KMS key region (default `us-east-1`) |

**Per-org (`installations.json`, baked into the image):**

```json
[
  { "org": "myorg", "installation_id": "139694269", "repos": ["app", "infra"],
    "perms": { "contents": "read", "pull_requests": "write" } },
  { "org": "otherorg", "installation_id": "139866498" }
]
```

`repos`/`perms` are optional (omit → the App's full grant for that field). The baked
default is `[]` (the sidecar idles). Provide your own by **deriving an image** — not a
`/workspace` bind-mount — so a scope change is a reviewed rebuild:

```dockerfile
FROM ghcr.io/<owner>/devcontainers/credential-shelf-github:latest
COPY installations.json /etc/credential-shelf/installations.json
```

## AWS / KMS bootstrap

This sidecar needs an AWS identity with `kms:Sign`. It reads the SSO session from its
`~/.aws` — **share the same home volume as `credential-shelf-aws` so a single
`aws sso login` serves both** (see
[credential-shelf-base](../credential-shelf-base#deployment-pattern-shelf-sidecars)).

One-time: `import-app-private-key <app-key.pem>` imports the App's RSA private key into
KMS as a **non-extractable** signing key and prints the alias/ARN for
`VEND_GH_KMS_KEY_ID`. Run it once (with KMS-create permissions), grant `kms:Sign` on the
key to `VEND_GH_AWS_PROFILE`, then shred the local `.pem`.

## Vends

- `/creds/github/<org>` — `{"value":"<token>","expires_at":<epoch>}`, one file per org.
- `/creds/status/github-<org>` — `ok expires=…` / `stalled …` health stamp.
