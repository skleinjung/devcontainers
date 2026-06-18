# Rollout review — hardened devcontainers + pluggable credential sidecar

A critical, assume-breach review of adopting this offering (the `base`/`default`
images plus a paired credential sidecar) on a small dev team. It covers what
adoption actually takes, the trade-offs in both directions, the security findings,
and the gates I'd want cleared before rolling it out to a team.

Review date: 2026-06-13.

---

## 1. What adoption looks like

**Phase 0 — one-time platform setup.** This is the part that's easy to
underestimate. You stand up the vending authorities: create a GitHub App, install
it on the org(s), record the installation IDs, import its signing key into KMS, and
configure AWS IAM Identity Center with an agent permission set. Then decide on the
images (use `default`, or a thin layer `FROM default`) and the GHCR visibility, and
write the sidecar config plus a reference compose / `devcontainer.json`. That's a
day or more of fiddly cloud and security work, and it needs a clear owner.

**Phase 1 — per-developer onboarding.** Install Docker and VS Code, pull the images,
run the admin sidecar, and do the SSO device-code login. After that, credentials
flow in through the shelf.

**Phase 2 — per-project.** Drop a `.devcontainer/` in pointing at the images, and
set `GH_DEFAULT_ORG` and the vended scope. Once a template exists this is copy-paste.

**Phase 3 — steady state.** Re-login when the SSO session lapses (this is the
recurring chore). Pull the weekly-rebuilt images. Edit the scope and rebuild the
sidecar when repos or roles change. And review agent-authored diffs before applying
anything privileged.

Day to day it's smooth once it's set up: `git`, `gh`, and `aws` just work,
credentials stay invisible, and agents are confined. Almost all of the cost lands in
Phase 0 and the recurring SSO login.

---

## 2. Trade-offs

### What you gain

- A higher baseline for everyone — no sudo, scrubbed VS Code channels,
  `cap_drop`/`no-new-privileges`, no Docker socket — uniform and on by default.
- A smaller blast radius — agents get only short-lived (≤1h), scoped credentials,
  with no SSO session or KMS key in the workspace.
- Consistency, and you can adopt it in pieces — one base image, and teams that don't
  want vending still get the hardened container with no secrets in it (`devcred`
  resolves to none).
- A posture that's easy to defend — short-lived, least-privilege credentials over
  standard interfaces (KMS, `credential_process`, the git helper). It's the right
  shape and it's straightforward to explain.

### What it costs

- Setup is heavy and needs an owner (the App, KMS, and IdC work). The "pull it off
  the shelf with light config" story holds for the workspace image, but not for the
  vending half.
- Someone now owns the image build and publish, the weekly rebuild, GHCR, the sidecar
  config, key rotation, and a few hundred lines of security-critical bash. On a small
  team that role often goes unfilled.
- Failures are distributed and quiet. Credentials travel from the sidecar through the
  shelf or socket into the environment, and the whole chain fails open to none — so
  "why is git unauthenticated?" turns into a multi-hop hunt that ends in a silent 401.
- It locks you into a workflow: VS Code devcontainers and Docker. Other setups are
  second-class, and with no Docker socket, containerized dev (testcontainers, image
  builds) breaks.
- It locks you into a stack: vending is specific to AWS SSO and GitHub Apps. A GCP or
  GitLab team gets nothing from that half.
- A lot of the safety rests on each developer's discipline — not authorizing the VS
  Code git OAuth prompt, and reviewing `.devcontainer`/`.vscode` diffs before a reload.

---

## 3. Security review (assume-breach)

The strengths are real (see section 3.4). The findings below are about how this
behaves operationally on a team, not about whether the design is conceptually sound —
it is.

### 3.1 High severity / realistic break paths

1. **Inside the dev container, there's no containment between same-uid processes.** A
   compromised dependency or extension running there can read every credential that
   container can fetch and exfiltrate it. (The agent has its own container; the
   residual untrusted code here is the dev container's deps and extensions.) What you
   get from short-lived credentials is a smaller blast radius and a time limit, not
   secrecy: "short-lived" stops a later replay, but it does nothing against a live
   attacker who just keeps asking.
2. **Scope discipline is the only real control, and the tooling doesn't help you get
   it right.** A `contents:write` token is push access for whatever code holds it, and
   the AWS role is whatever IAM lets it be. All of the safety rides on keeping grants
   narrow, and the toolkit deliberately leaves that to the operator. The easy default —
   org-wide install, a broad role — is the path of least resistance, while narrowing is
   the hard path. That asymmetry is where teams get burned.
3. **Applying agent output re-crosses every boundary you just built.** Agent-authored
   code is only contained while it runs in the agent container. The moment a human runs
   it with privilege in a trusted context — their own machine, or CI/CD — that context's
   authority applies, not the agent's. "Agents prepare, humans review and apply" is a
   social control, and it erodes under deadline pressure. The likeliest real compromise
   here isn't broken crypto; it's a tired developer applying unreviewed agent output.
4. **Desktop extension-host RCE isn't mitigated, and it gets worse with team size.**
   Untrusted code in the dev container — a malicious extension or dependency — can write
   `.vscode`/extension JS and, on a window reload, run code on the developer's host,
   bypassing every credential boundary. "Review before reload" doesn't hold up across N
   developers.

### 3.2 Medium severity

5. **The trusted image's supply chain is under-governed.** The build pulls `curl | bash`
   (Claude) and `yq` with no checksum (pandoc has one, so it's inconsistent), and the
   weekly rebuild auto-republishes `latest` with no review gate. The whole team trusts
   this image, and most people will pin `latest` rather than a `sha-` tag. Unpinned
   `curl | bash` in a security-foundational image is the kind of thing that should stop
   a review.
6. **The shipping (shelf) posture has no audit.** File reads leave no trace, so you
   can't answer "did the agent use these credentials, when, and for what." Incident
   response starts blind. The broker fixes this, but it's deferred.
7. **Failing open to none isn't just a UX cost, it's a security one.** Silent unauth
   trains people to accept that "credentials sometimes don't work," which is exactly the
   noise a compromise or a botched scope change can hide under. It should at least be
   observable.
8. **The security-critical bash is bespoke, unaudited, and untested.** `devcred`, the
   adapters, the vend scripts, and the scrub all do secret- and env-string handling in
   shell, including `eval`. One quoting or word-splitting bug is a token leak or a scrub
   bypass. This is exactly the code that should have tests and a second reviewer.

### 3.3 Lower / model-level

9. **The host is the real perimeter.** Each developer's machine runs the sidecar with a
   live upstream authority (an SSO session, say), and this design doesn't harden the host
   itself. The devcontainer gives a feeling of sandboxing that doesn't extend to the
   host — a compromised machine is game over — and that mismatch can breed false
   confidence.
10. **(Future) the broker's escalation flow is a social-engineering surface.** Agents
    are persuasive: "I need elevated access to do X" leads to a human provisioning a
    15-minute grant the agent then uses. Design the confirmation UX defensively when you
    build it.

### 3.4 What's genuinely strong

- Real privilege separation where it's enforced — no SSO, KMS, or Docker socket in the
  workspace, plus `cap_drop` and bridge networking.
- An honest threat model. Being candid about the residuals means nobody walks away with
  false confidence, which is itself a kind of control.
- Leaning on KMS, `credential_process`, and the git helper instead of rolling its own
  crypto.

This is competent, security-literate work.

---

## 4. Who this fits

Fits: a GitHub- and AWS-native team that runs agents, has at least one platform or
security owner, and is fine with a devcontainer-only workflow.

Doesn't fit: a team with no platform owner, heavy Docker-in-dev needs, or a
non-AWS/GitHub stack. For them the cost/benefit inverts.

---

## 5. Rollout gates (clear these first)

1. **A least-privilege scoping guide, and narrow defaults.** Ship sane minimal
   `installations.json` / IAM templates and a "how to scope a grant" doc. This closes
   the asymmetry in finding #2, and it's the single highest-value fix.
2. **Image supply-chain hygiene.** Pin by digest in consuming projects, put a review
   gate on the auto-rebuilt base, add the missing `yq` checksum, and drop or pin/verify
   the `curl | bash`. Closes #5.
3. **Make auth failure loud.** Replace the silent fail-open-to-none with a logged or
   surfaced signal — a SessionStart warning plus a one-line breadcrumb, say. Closes #7.
4. **Tests and a second reviewer on every script that touches secrets or env.**
   `devcred`, the adapters, the vend scripts, the scrub. Closes #8.
5. **A one-page "what this does not protect" for every developer** — the
   same-uid-within-a-container reality, host-is-the-perimeter, review-before-apply,
   scope-is-the-real-control, and no-audit on the shelf. Captured in
   [SECURITY.md, section 3](./SECURITY.md#3-what-this-does-not-protect). Closes #1, #3,
   and #9.

The broker and its audit (#6) can stay v2 — but until then, document that you have no
usage audit.
