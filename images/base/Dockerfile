# base — the foundation image for this repo.
#
# Extends the upstream devcontainers base with the security hygiene every image
# here should share: no sudo / setuid privilege-escalation path, and the VS Code
# "host-reaching channel" scrub wired into interactive shells. Other images build
# FROM this one (see images/default). OCI labels are injected at build time by
# the bake generator (ci/gen-bake.sh).
FROM mcr.microsoft.com/devcontainers/base:ubuntu

# The unprivileged dev account. Defaults to the base image's `vscode` at uid/gid
# 1000; override (e.g. to match a host user) with `--build-arg`, e.g.
# `--build-arg USERNAME=alice --build-arg USER_UID=1001 --build-arg USER_GID=1001`.
ARG USERNAME=vscode
ARG USER_UID=1000
ARG USER_GID=1000

USER root

# Remove sudo so the image has no setuid privilege-escalation path.
# SUDO_FORCE_REMOVE permits purging the (protected) package.
RUN export SUDO_FORCE_REMOVE=yes \
  && apt-get update \
  && apt-get install -y --no-install-recommends jq \
  && apt-get -y purge sudo \
  && apt-get -y autoremove \
  && apt-get clean \
  && rm -rf /var/lib/apt/lists/*

# Drop the base image's pre-made users (uid >= 1000) and any residual sudoers grant
# files — the base grants its `vscode` user passwordless sudo via /etc/sudoers.d/vscode,
# and userdel removes the account but not that file. Then (re)create USERNAME as a
# plain, unprivileged account at the requested uid/gid.
RUN getent passwd \
    | awk -F: '($3 >= 1000) && ($1 != "nobody") {print $1}' \
    | xargs -r -n 1 userdel -r \
  && rm -rf /etc/sudoers.d/* \
  && if [ "${USERNAME}" != "root" ]; then \
       groupadd --gid "${USER_GID}" "${USERNAME}" || true \
       && useradd -s /bin/bash -m -u "${USER_UID}" -g "${USER_GID}" "${USERNAME}"; \
     fi

# Install the VS Code git-auth/IPC scrub (rootfs/etc/profile.d/...) and source it
# from /etc/bash.bashrc so interactive NON-login shells get it too (the profile.d
# drop-in already covers login shells). Each scrubbed var is opt-out at runtime via
# SCRUB_<VAR>_ENABLED — see the script and this image's README.
COPY rootfs/ /
RUN printf '\n# Drop VS Code host-reaching channels from interactive shells\n. /etc/profile.d/50-scrub-vscode-git-auth.sh\n' \
    >> /etc/bash.bashrc

# Default git's editor to nano: the scrub disables the `code` IPC socket, so git's
# usual `code --wait` editor can't launch. nano is a working in-terminal fallback.
RUN git config --system core.editor nano

# Credential consumer adapters (shipped in rootfs/usr/local/bin: devcred + the git/gh
# shims — see docs/SECRETS.md). Wire the github.com credential helper to `devcred`
# (per-org tokens from the shelf, routed by the request path), and point AWS at the
# shelf credentials file. All are INERT when no credential sidecar is attached: with no
# /creds the helpers resolve to nothing and tools are simply unauthenticated.
RUN chmod 0755 /usr/local/bin/devcred /usr/local/bin/git-credential-devcred \
      /usr/local/bin/gh /usr/local/bin/reap-vscode-sockets
RUN git config --system --unset-all 'credential.https://github.com.helper' 2>/dev/null || true; \
    git config --system --add 'credential.https://github.com.helper' '' \
  && git config --system --add 'credential.https://github.com.helper' 'devcred' \
  && git config --system 'credential.https://github.com.useHttpPath' true
ENV AWS_SHARED_CREDENTIALS_FILE=/creds/aws/credentials

# Default to the unprivileged account (consumers can still `USER root` to install).
USER ${USERNAME}

# Keep-alive for `docker run`/compose use as a dev container. CMD is inherited by
# downstream images (e.g. `default`), so it's set once here. In a real devcontainer
# the compose `command:` / devcontainer `overrideCommand` usually supplies this
# instead; this is the fallback when nothing overrides it.
CMD ["sleep", "infinity"]
