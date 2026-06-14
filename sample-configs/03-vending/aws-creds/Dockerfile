# Derived AWS credential sidecar that bakes THIS project's accounts.yaml — a reviewed
# rebuild, NOT a /workspace bind-mount, so changing vend scope is human-gated. Fill
# accounts.yaml with the account/role(s) to vend; SSO start URL + region are env (see
# docker-compose.yml).
FROM ghcr.io/skleinjung/devcontainers/credential-shelf-aws:latest
COPY accounts.yaml /etc/credential-shelf/accounts.yaml
