# default

The general-purpose dev image: [`base`](../base) plus common CLI tooling. Most
projects should build on (or run) this image directly.

## What it adds on top of `base`

- **gnupg2** — GPG for signing / key handling.
- **yq** (mikefarah) — installed from GitHub releases; version pinned by the
  `YQ_VERSION` build arg.
- **zsh purged** — the images standardize on bash.

Everything from `base` is inherited: no sudo, the VS Code host-channel scrub (and
its `SCRUB_*_ENABLED` toggles), the unprivileged `vscode` user, and the
`sleep infinity` keep-alive `CMD`.

## Build args

| Arg | Default | Purpose |
|-----|---------|---------|
| `YQ_VERSION` | `4.45.1` | yq release to install |

`base`'s `USERNAME` / `USER_UID` / `USER_GID` args apply when building `base`
itself; see [base](../base).

## Intra-repo dependency

This image is built `FROM base`, declared in two places:

- `Dockerfile` starts with `FROM base`.
- the `from` file contains `base` — the in-repo parent's name.

`from` is what the tooling reads: the bake generator turns it into a named build
context (`contexts = { base = "target:base" }`) so `FROM base` resolves to the
locally-built base target (no registry round-trip), and the change selector
rebuilds this image whenever `base` changes.

Published as `ghcr.io/<owner>/devcontainers/default`.
