# default — the general-purpose dev image: `base` (security hygiene) plus common
# CLI tooling. This is the image most projects should build on or run directly.
#
# `FROM base` resolves to the in-repo base *target* via the named build context
# bake injects (see images/default/from), so it builds against the base from the
# same run — no registry round-trip. Build locally with: docker buildx bake default
FROM base

USER root

# gnupg2 (signing / key handling); purge zsh — the images standardize on bash.
RUN apt-get update \
  && apt-get install -y --no-install-recommends gnupg2 \
  && apt-get -y purge zsh \
  && apt-get -y autoremove \
  && apt-get clean \
  && rm -rf /var/lib/apt/lists/*

# yq (mikefarah). Pin/override the release with: --build-arg YQ_VERSION=<x.y.z>
ARG YQ_VERSION=4.53.3
RUN arch="$(dpkg --print-architecture)" \
  && wget -q "https://github.com/mikefarah/yq/releases/download/v${YQ_VERSION}/yq_linux_${arch}" \
       -O /usr/local/bin/yq \
  && chmod 0755 /usr/local/bin/yq

# Back to the unprivileged account (matching base's default)
ARG USERNAME=vscode
USER ${USERNAME}
