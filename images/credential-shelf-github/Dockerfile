# credential-shelf-github — GitHub provider for the shelf credential sidecar.
#
# Mints per-org GitHub App installation tokens (an App JWT signed via AWS KMS) and writes
# {"value":"<token>","expires_at":<epoch>} to /creds/github/<org>. It needs an AWS
# identity with kms:Sign — from the SSO session in this container's ~/.aws. Share the
# same home volume as credential-shelf-aws so one `aws sso login` serves both. The App
# signing key never leaves KMS.
FROM credential-shelf-base

USER root
RUN apt-get update && apt-get install -y --no-install-recommends openssl unzip \
  && arch="$(dpkg --print-architecture)" \
  && case "$arch" in amd64) a=x86_64 ;; arm64) a=aarch64 ;; *) echo "unsupported arch: $arch" >&2; exit 1 ;; esac \
  && curl -fsSL "https://awscli.amazonaws.com/awscli-exe-linux-${a}.zip" -o /tmp/awscli.zip \
  && unzip -q /tmp/awscli.zip -d /tmp && /tmp/aws/install \
  && rm -rf /tmp/aws /tmp/awscli.zip /var/lib/apt/lists/*

COPY bin/ /usr/local/bin/
RUN chmod 0755 /usr/local/bin/vend-github-daemon /usr/local/bin/vend-github-token \
      /usr/local/bin/import-app-private-key

# Baked default: no installations (idle). Override in a derived image (NOT a /workspace
# bind-mount) so a scope change is a reviewed rebuild:
#   FROM ghcr.io/<owner>/devcontainers/credential-shelf-github:latest
#   COPY installations.json /etc/credential-shelf/installations.json
COPY installations.json /etc/credential-shelf/installations.json

USER vscode
WORKDIR /home/vscode
CMD ["vend-github-daemon"]
