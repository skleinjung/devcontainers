# credential-shelf-aws — AWS provider for the shelf credential sidecar.
#
# Exports STS credentials for the configured profiles (from the SSO session in this
# container's ~/.aws) and writes the native AWS shared-credentials file to
# /creds/aws/credentials — the docs/SECRETS.md AWS exception. The full SSO session stays
# here; only the listed roles' ≤1h creds reach the shelf.
FROM credential-shelf-base

USER root
# AWS CLI v2 — apt ships v1, which lacks the SSO credential-export flow.
RUN apt-get update && apt-get install -y --no-install-recommends unzip \
  && arch="$(dpkg --print-architecture)" \
  && case "$arch" in amd64) a=x86_64 ;; arm64) a=aarch64 ;; *) echo "unsupported arch: $arch" >&2; exit 1 ;; esac \
  && curl -fsSL "https://awscli.amazonaws.com/awscli-exe-linux-${a}.zip" -o /tmp/awscli.zip \
  && unzip -q /tmp/awscli.zip -d /tmp && /tmp/aws/install \
  && rm -rf /tmp/aws /tmp/awscli.zip /var/lib/apt/lists/*

COPY bin/ /usr/local/bin/
RUN chmod 0755 /usr/local/bin/vend-aws-creds

USER vscode
WORKDIR /home/vscode
CMD ["vend-aws-creds"]
