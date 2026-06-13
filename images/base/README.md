# base

The foundation image. Extends `mcr.microsoft.com/devcontainers/base:ubuntu` with
the security hygiene every image here should share, and is what other images in
this repo build `FROM`.

## What it configures

### No sudo

The `sudo` package is purged (`SUDO_FORCE_REMOVE`) and the base image's
`/etc/sudoers.d/*` grant files are removed, so the image has **no setuid
privilege-escalation path**. The base image's pre-made users (uid ≥ 1000) are also
removed, eliminating the passwordless-sudo `vscode` grant the upstream ships.

### Unprivileged user

A single unprivileged account is (re)created and the image **defaults to it**
(`USER ${USERNAME}`) — consumers can still switch to `USER root` to install
software, then back. Name and ids are build args (see [Build args](#build-args)).

### Keep-alive command

Sets `CMD ["sleep", "infinity"]` so the image stays running when used as a dev
container. `CMD` is **inherited** by downstream images (e.g. `default`), so it's
defined once here. In a real devcontainer the compose `command:` / devcontainer
`overrideCommand` usually supplies this instead; this is the fallback.

### VS Code host-channel scrub

Installs `/etc/profile.d/50-scrub-vscode-git-auth.sh`, sourced from both
`/etc/profile` (login shells) and `/etc/bash.bashrc` (interactive non-login
shells). In interactive shells it `unset`s VS Code's host-reaching environment
channels so they aren't inherited by anything launched from a terminal (including
agents):

| Variable | What it exposes |
|---|---|
| `GIT_ASKPASS`, `VSCODE_GIT_ASKPASS_NODE`, `VSCODE_GIT_ASKPASS_MAIN`, `VSCODE_GIT_ASKPASS_EXTRA_ARGS`, `VSCODE_GIT_IPC_HANDLE` | VS Code's git askpass → the host's VS Code GitHub OAuth token |
| `VSCODE_IPC_HOOK_CLI` | the `code` CLI channel — acts on the host |
| `BROWSER` | host browser/command launcher (`openExternal`) |
| `GPG_AGENT_INFO` | host GPG agent |
| `SSH_AUTH_SOCK` | the forwarded SSH agent (host keys) |

Each variable is scrubbed **by default** (most secure); each is individually
opt-out at runtime — see [Customizing](#customizing).

### Git editor

Sets `git config --system core.editor nano`. The scrub disables the `code` IPC
socket, so git's usual `code --wait` editor can't launch; nano is a working
in-terminal fallback.

> Note: `SSH_AUTH_SOCK` is scrubbed by default here. If you rely on a forwarded
> SSH agent (e.g. a hardware/FIDO key) in terminals, opt out of just that one — see
> below.

## Build args

| Arg | Default | Purpose |
|-----|---------|---------|
| `USERNAME` | `vscode` | Name of the unprivileged dev account |
| `USER_UID` | `1000` | Its uid |
| `USER_GID` | `1000` | Its gid |

```sh
docker buildx bake base \
  --set base.args.USERNAME=alice \
  --set base.args.USER_UID=1001 \
  --set base.args.USER_GID=1001
```

## Customizing

### Scrub toggles (`SCRUB_<VAR>_ENABLED`)

Every scrubbed variable has a toggle named `SCRUB_<VAR>_ENABLED`. Set it to a
false-y value (`false`/`0`/`no`/`off`, case-insensitive) to **keep** that variable;
anything else (or unset) scrubs it. These are read from the shell environment, so set them via the
container environment — compose `environment:` or devcontainer `containerEnv`.
They're plain runtime env vars: a change takes effect on the next shell, **no
rebuild required**.

| Toggle | Default | Keeps when false |
|---|---|---|
| `SCRUB_GIT_ASKPASS_ENABLED` | `true` | `GIT_ASKPASS` |
| `SCRUB_VSCODE_GIT_ASKPASS_NODE_ENABLED` | `true` | `VSCODE_GIT_ASKPASS_NODE` |
| `SCRUB_VSCODE_GIT_ASKPASS_MAIN_ENABLED` | `true` | `VSCODE_GIT_ASKPASS_MAIN` |
| `SCRUB_VSCODE_GIT_ASKPASS_EXTRA_ARGS_ENABLED` | `true` | `VSCODE_GIT_ASKPASS_EXTRA_ARGS` |
| `SCRUB_VSCODE_GIT_IPC_HANDLE_ENABLED` | `true` | `VSCODE_GIT_IPC_HANDLE` |
| `SCRUB_VSCODE_IPC_HOOK_CLI_ENABLED` | `true` | `VSCODE_IPC_HOOK_CLI` |
| `SCRUB_BROWSER_ENABLED` | `true` | `BROWSER` |
| `SCRUB_GPG_AGENT_INFO_ENABLED` | `true` | `GPG_AGENT_INFO` |
| `SCRUB_SSH_AUTH_SOCK_ENABLED` | `true` | `SSH_AUTH_SOCK` |

Example — keep the forwarded SSH agent (hardware-key usage) while scrubbing
everything else, in `docker-compose.yml`:

```yaml
services:
  workspace:
    environment:
      SCRUB_SSH_AUTH_SOCK_ENABLED: 'false'
```

…or in `devcontainer.json`:

```jsonc
"containerEnv": { "SCRUB_SSH_AUTH_SOCK_ENABLED": "false" }
```

### Renaming the dev user / changing uid·gid

Use the [build args](#build-args) above (these *are* build-time — they change the
image, so they require a rebuild).

## Secrets & credentials

base ships the **consumer** side of a pluggable credential boundary — a `devcred`
resolver plus standard git/gh/AWS adapters that fetch short-lived, scoped secrets
by name from whatever credential sidecar (0 or 1) you pair in compose, and resolve
cleanly to "none" when there isn't one. The contract — naming, the v1 `GET`
protocol with a reserved verb slot, transport auto-detection (unix socket / tcp /
file shelf / env / none), and why we don't use Vault et al. — is specified in
[docs/SECRETS.md](../../docs/SECRETS.md).

Concretely, `base` wires:

- **`devcred get <name>`** — the resolver (file shelf → env → none, fail-open).
- a github.com **git credential helper** (`devcred`, with `useHttpPath`) and a **`gh`**
  wrapper, both → `devcred get github/<org>` (org from the request path / `-R` / cwd).
- **`AWS_SHARED_CREDENTIALS_FILE=/creds/aws/credentials`** (the native AWS file).

Set **`GH_DEFAULT_ORG`** so git/gh resolve an org when no repo context pins one. Per-adapter
runtime opt-outs: `DEVCRED_GIT_HELPER=off`, `DEVCRED_GH_WRAPPER=off`. (`gh` itself isn't
installed by `base` — the wrapper applies automatically once you add it.)

---

Published as `ghcr.io/<owner>/devcontainers/base`.
