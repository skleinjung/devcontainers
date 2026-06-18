# Credential vending via a broker socket

> **Status:** target design — not the shipping baseline, and not fully implemented.
> What ships today is the read-only credential shelf (the same vended secrets for
> every consumer), described in
> [SECURITY.md, section 10](./SECURITY.md#10-layer-3--credential-vending-the-shelf).
> This document describes the broker variant, which adds per-consumer credential
> policy. The consumer-side wire contract is in [SECRETS.md](./SECRETS.md).

## Why a broker (vs the shelf)

The shelf vends one set of short-lived, scoped credentials, read-only, identical for
every consumer — the agent and the dev read the same files. It's simple and it's what
ships today, but it can't:

- give the agent a narrower, audited, or shorter-TTL grant than the dev, even though
  both draw on the same upstream authority;
- avoid at-rest exposure — shelf files are readable by any process in a consumer that
  mounts them;
- produce a usage audit — file reads are invisible.

The broker fixes all three: each consumer talks to its own socket, the sidecar mints
on demand (nothing at rest), and it can scope and audit per request.

## Per-consumer sockets

The sidecar exposes one socket per consumer, and the socket is the policy boundary —
each is mounted into exactly one consumer container:

- `/creds/dev.sock` → the dev's grants
- `/creds/agent.sock` → the agent's (narrower) grants

A consumer asks for a credential by name; what that name resolves to (which
repos/perms/role, what TTL) is decided in the sidecar, never by the caller, so a
consumer can't widen its own grant. Because identity comes from *which socket you can
reach* (mount topology, set by compose), the consumers can share a uid — the broker
doesn't rely on `SO_PEERCRED`, whose pid is unreliable across namespaces.

## Prototypical config

The grant tables are baked into the sidecar image (so a change is a human-gated
rebuild), not bind-mounted from an untrusted `/workspace` — so changing scope is a
reviewed rebuild:

```yaml
# sidecar grants config — baked into the sidecar image. Trusted config.
consumers:
  dev:
    endpoint: { type: unix, path: /creds/dev.sock }
    grants:
      github/myorg: { kind: github, installation_id: "…", repos: [opus, aws],
                      perms: { contents: write, pull_requests: write }, ttl: 1h }
      aws/0848…:    { kind: aws, profile: 0848…-developer, ttl: 1h }
  agent:
    endpoint: { type: unix, path: /creds/agent.sock }
    grants:
      github/myorg: { kind: github, installation_id: "…", repos: [opus],
                      perms: { contents: read }, ttl: 15m, audit: true }
```

Deployers fan this out to as many consumers as they like (a second agent, a CI runner,
a scratch box) — each gets its own socket and grant table.

## Properties

- **Per-consumer scope** — agent read-only / short-TTL, dev read-write, same upstream
  authority.
- **Nothing at rest** — minted on demand, never written to a consumer-readable file.
- **Per-request audit** — every issuance is attributable (the `audit: true` above).
- **No signing capability or upstream authority in any consumer** — it can only request
  what its grant table allows.
- **Accepted residual (unchanged from the shelf)** — a consumer fully controls the token
  it's granted (use + network exfil). The broker controls *acquisition* and *audit*, not
  use; pair it with an egress allowlist to blunt exfiltration.

## Sidecar-to-sidecar vending — removing the shared SSO home

The shelf split (`credential-shelf-aws` + `credential-shelf-github`) bootstraps auth
with a shortcut: both sidecars mount the same home volume, so one `aws sso login`
populates the SSO cache for both. The cost is that both then hold the full SSO
session — so that split is code and operational modularity, not (yet) a reduction in
blast radius.

The broker removes the coupling. A sidecar is just another consumer, so the AWS sidecar
(the sole SSO holder) vends a narrow role to the GitHub sidecar over a socket — for
example, a grant whose only power is `kms:Sign` on the App key:

```yaml
consumers:
  github-sidecar:
    endpoint: { type: unix, path: /run/devcred-internal/github.sock }
    grants:
      aws/kms-signer: { kind: aws, role: kms-signer-role, ttl: 15m }
```

The GitHub sidecar fetches `aws/kms-signer` on demand and uses it to sign App JWTs.
Now it never holds the SSO session — only a ≤1h `kms:Sign` credential. Compromise it
and the attacker can sign for an hour, not assume the user's other roles. The SSO
session lives in exactly one container and the shared home disappears.

*(On the shelf this same fan-out is possible by vending the signer role to a private
inter-sidecar volume the consumers never mount — but the socket is cleaner:
per-consumer, on demand, nothing at rest.)*

## Wire protocol

How a consumer fetches over the socket — the `GET <name>` request, the response
payload, transport auto-detection (unix socket / tcp / file shelf / env / none), and
the reserved `SIGN` verb — is specified in [SECRETS.md](./SECRETS.md). The broker is
just the *socket* transport of that contract with per-consumer grant tables behind it;
the shelf is the *file* transport of the same contract.
