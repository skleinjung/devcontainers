# sample-configs

Copyable `.devcontainer/` setups, one per [adoption layer](../docs/SECURITY.md#2-adoption-layers).
Each directory holds a `docker-compose.yml` + `devcontainer.json`; to use one, copy its
files into your project's `.devcontainer/`.

| Sample | Layer | What it gives you |
|--------|-------|-------------------|
| [`01-hardened`](01-hardened) | 1 | A single hardened container (no sudo, VS Code channel hardening, `cap_drop`, no Docker socket). No agent isolation, no credentials. |
| `02-isolated-agent` | 2 | *(coming)* adds a separate agent container sharing only `/workspace`. |
| [`03-vending`](03-vending) | 1 + 3 | Hardened workspace + the AWS & GitHub credential sidecars vending to a read-only shelf. A drop-in for a 2-container (workspace + creds) setup. |

> Replace **`skleinjung`** in the image refs with your own GHCR owner if you publish the
> toolkit images under a different namespace.

The images these reference (`base`, `default`, `credential-shelf-*`) and *why* each setting
matters are documented in [docs/SECURITY.md](../docs/SECURITY.md) and
[docs/SECRETS.md](../docs/SECRETS.md).
