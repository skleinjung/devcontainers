# Secrets & credential brokering (base)

The workspace is **untrusted** (agents, build scripts, packages all run as our uid).
Powerful credentials must therefore live in a *different* trust domain. This image
ships only the **consumer** side of that boundary: a small resolver and the
standard credential adapters that fetch **short-lived, scoped secrets by name**
from whatever credential sidecar (if any) is paired with the workspace.

Design goals:

- **One workspace image, paired with 0–1 credential sidecars.** Which sidecar (or
  none) is a `docker-compose` choice, not an image choice.
- **Inert by default.** With no sidecar and no ambient credentials, every adapter
  resolves to "none" and tools are simply unauthenticated — nothing breaks, nothing
  leaks.
- **Provider-agnostic.** The workspace never encodes *how* a secret is produced
  (SSO, a GitHub App, a static file, a future broker) — only how to *ask* for it.

> **Status:** this document is the **v1 contract**. It is the spec the base image
> implements; treat the wire/format/precedence rules here as authoritative.

---

## 1. The one chokepoint: `devcred`

Everything funnels through a single resolver, `devcred`:

```
devcred get <name>      # prints the secret value on stdout, exit 0
                        # prints nothing, exit 0 if unavailable (fail-open)
```

The consumer adapters (git, gh, aws — §5) call `devcred`; they are **transport-blind**.
Only `devcred` knows where secrets come from, so adding a new transport never
touches a consumer. This is what makes "one workspace image, forever" real.

---

## 2. Names

Secrets are addressed by a hierarchical name, `<kind>/<scope…>`:

| Name | Meaning |
|------|---------|
| `github/<org>` | a GitHub token scoped to that org (per-org, as today's shelf) |
| `aws/<account>[/<role>]` | AWS credentials for an account/role |
| `custom/<label>` | an ad-hoc, human-provisioned grant (e.g. a time-boxed elevation) |
| `sign/<key>` | **reserved (v2)** — a signing key; see §7 |

The name **is** the routing table. The consumer adapters derive it from context
(git from the request path, `gh` from `-R`/cwd, AWS from the profile), exactly as
the current shelf filenames already encode org→token routing.

**Scope is decided by the sidecar, never by the caller.** The workspace passes a
*name*; what that name resolves to (which repos/perms/role, what TTL) is the
sidecar's trusted configuration. A workspace process cannot widen its own scope —
it can only ask for a name and get whatever the sidecar has bound to it.

---

## 3. Protocol (v1)

### Verb slot, fixed to fetch

Every brokered request carries a **verb**. v1 defines exactly one:

```
GET <name>\n
```

The verb slot exists so v2 can add operations (notably `SIGN`, §7) **without a
breaking change**. **Non-brokered sources (file shelf, env) are fetch-only** — they
have no request channel, so the verb is implicitly and permanently `GET` for them.
v1 implements only `GET` everywhere; brokered transports simply reserve room.

### Response payload

A single JSON object:

```json
{ "value": "<secret>", "expires_at": 1739481600 }
```

- `value` — the secret. A **string** for token kinds (`github/*`, `custom/*`); for
  `aws/*` over a **brokered** transport, the structured object an AWS SDK
  `credential_process` expects (`AccessKeyId` / `SecretAccessKey` / `SessionToken` /
  `Expiration`).
- `expires_at` — unix epoch seconds, or `null` if non-expiring. The resolver treats
  a secret within `DEVCRED_SKEW` seconds of expiry (default 300) as stale.

The **file shelf stores this same object** (one file per name) — **except AWS:**

**AWS on the file shelf is the native shared-credentials file, not a `{value,…}`
payload.** The sidecar writes a standard ini file and the consumer points
`AWS_SHARED_CREDENTIALS_FILE` at it (§5) — zero consumer logic, and it works with every
AWS SDK/CLI out of the box. That file is **static from the SDK's view** (it carries no
expiry the SDK refreshes on), so it relies on the sidecar rewriting it before expiry —
fine for short-lived CLI calls, a caveat for long-running SDK clients. On a **broker**
transport AWS instead flows through `credential_process` with the structured `value`
above, which the SDK refreshes on its own. (Token kinds stay uniform `{value,
expires_at}` JSON files on the shelf — no exception.)

---

## 4. Transports & detection

No single transport fits every case (a zero-daemon static provider vs an on-demand
broker vs a remote service), so the workspace supports a **closed set** and
**auto-detects** by precedence. One env var, `DEVCRED_SOURCE`, forces a choice when
auto-detection would guess wrong.

Detection precedence (first match wins):

| # | Transport | Detected by | Brokered? | Notes |
|---|-----------|-------------|-----------|-------|
| 1 | **unix socket** | `/run/devcred.sock` exists | yes | request/response; supports the verb slot |
| 2 | **tcp** | `DEVCRED_ADDR=host:port` set | yes | same protocol as unix; for a sidecar not sharing a volume |
| 3 | **file shelf** | `<DEVCRED_SHELF>/<name>` exists (default `/creds`) | no | zero-daemon; `GET`-only |
| 4 | **env** | `GH_TOKEN`, `AWS_*`, … set | no | ambient credentials; `GET`-only |
| 5 | **none** | nothing above | — | unauthenticated; fail-open |

Override: `DEVCRED_SOURCE=unix:/run/devcred.sock | tcp:host:port | file:/creds | env | none`.

Brokered transports (1–2) speak the §3 protocol and reserve the verb slot;
non-brokered transports (3–4) are fetch-only by construction. Only `GET` ships in
v1 regardless.

---

## 5. Consumer adapters (what's wired in base)

All adapters live in base, are **wired but inert** (they no-op cleanly when
`devcred` returns none), and are **runtime-toggleable** — there are no build-arg
variants and no separate images to compose. (Rationale: the helpers are tiny and
harmless when idle; gating them at build time would fork the single workspace
image, which we explicitly don't want.)

| Consumer | Interface used | How it resolves | Runtime opt-out |
|----------|----------------|-----------------|-----------------|
| **git** | credential helper (`credential.https://github.com.helper`, `useHttpPath`) | helper → `devcred get github/<org>` (org = request path) | `DEVCRED_GIT_HELPER=off` |
| **gh** | `GH_TOKEN` via a PATH wrapper | wrapper → `devcred get github/<org>` (org = `-R`/cwd/`GH_ORG`) | `DEVCRED_GH_WRAPPER=off` |
| **AWS** | native: shared credentials file / `credential_process` | file case: sidecar writes the AWS creds file, base points `AWS_SHARED_CREDENTIALS_FILE` at it; socket case: `credential_process = devcred get aws/<account>` (emits the SDK's expected JSON) | use a profile without it |

AWS deliberately leans on the SDK's **native** mechanisms rather than a bespoke
adapter — they already give on-demand fetch and structured creds. `devcred`'s
`aws/*` kind returns exactly the `credential_process` JSON shape so it slots in
natively when you move from the file shelf to a broker.

Anything without a dedicated adapter (a `custom/*` grant, a future kind) is reached
with raw `devcred get <name>` — no new adapter required.

---

## 6. Pairing a sidecar

The workspace is fixed; you attach **0 or 1** credential sidecars in compose, each
presenting **one** transport:

- **No sidecar** → detection lands on env/none. A working container with zero
  secrets — the right default for someone pulling this off the shelf.
- **A shelf sidecar** → writes `/creds/<name>` payload files (the simplest provider;
  can even be a static file with no daemon). Fetch-only.
- **A broker sidecar** → listens on `/run/devcred.sock` (or tcp), mints on demand,
  can scope/expire/audit per request, and is where v2 operations (signing) will
  live. Nothing at rest.

Swapping shelf → broker is a sidecar change plus (at most) one env var; the
workspace image is untouched.

---

## 7. Reserved: v2 `SIGN` (e.g. git commit signing)

Commit signing is **out of v1**, and deliberately so — it is a *different verb*, not
another name. Fetching a signing key by name would pull the private key into the
untrusted workspace, defeating the point. So it is modelled as an **operation**:

```
SIGN <sign/key> <bytes>   →  signature        # v2, brokered transports only
```

The key stays in the sidecar; the workspace sends bytes and gets a signature, via
git's native replaceable signer hook (`gpg.ssh.program`). The file shelf cannot
serve it (no request channel). Until v2 lands, commit signing remains whatever the
*specialized* layer on top of this image configures (e.g. a mounted key) — base
ships nothing for it. The v1 verb slot is what lets `SIGN` arrive without a
breaking protocol change.

---

## 8. Why not an off-the-shelf product (Vault, etc.)

We are **not** avoiding COTS out of not-invented-here — we use the standard pieces
that fit (AWS KMS for signing keys, `ssh-agent`, the OS git/AWS credential
interfaces, `credential_process`). We decline the **heavyweight central** options,
for concrete reasons:

- **They require standing server infrastructure.** Vault is a service you run,
  unseal, store, back up, secure, and upgrade; Teleport is a cluster; SPIFFE/SPIRE
  is a server + node agents. The whole premise here is a *devcontainer* with **zero
  standing infra** that an associate can pull off the shelf with light config.
  "Also operate a Vault cluster" is a non-starter for that audience.
- **They don't solve the actual problem, which is a *trust boundary*, not a
  *store*.** The core requirement is "powerful creds live in a different container
  than untrusted code; only short-lived scoped derivations cross." A Vault *token*
  handed to the workspace is itself a scannable bearer credential — you still need
  a sidecar to broker between Vault and the untrusted uid, and you still can't stop
  a same-uid process from *using* what it's given. Vault would sit *behind* this
  sidecar, not replace it.
- **They don't natively mint our credential shapes.** We mint GitHub App
  installation tokens (App JWT signed via KMS) and AWS SSO/STS role creds from
  authorities we already operate. Wrapping those in a Vault secret engine or a
  SPIRE workload API is *adding* a layer over auth we already hold, not removing
  one — and the GitHub-App-via-KMS flow is bespoke enough that you'd write an
  external process either way.
- **Cloud-native workload identity** (IRSA, GCP Workload Identity) is excellent
  *inside* the cloud platform, but a devcontainer on a laptop/host isn't a pod with
  a projected service-account token. Cloud **secret managers** / 1Password are
  stores with the same "the workspace needs a credential to read them" bootstrap
  problem.

**The honest cost of building it ourselves:** the glue is bespoke and unaudited, and
we own its maintenance and the discipline not to slowly reinvent Vault badly (the
broker is intentionally a few hundred lines between authorities we already run, not
a new secret store). **When you should reach for a real secrets manager:** a fleet,
multiple users, or centralized rotation/audit/policy at scale — at which point its
operational weight finally pays for itself. For one developer's pluggable
devcontainer, it does not.
