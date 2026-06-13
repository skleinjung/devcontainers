# Derived GitHub credential sidecar that bakes THIS project's installations.json — a
# reviewed rebuild, NOT a /workspace bind-mount, so changing vend scope is human-gated.
# Fill installations.json with your org(s) + installation id(s).
FROM ghcr.io/skleinjung/devcontainers/credential-shelf-github:latest
COPY installations.json /etc/credential-shelf/installations.json
