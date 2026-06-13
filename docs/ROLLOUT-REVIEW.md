# Rollout review — hardened devcontainers + pluggable credential sidecar

A critical, assume-breach review of adopting this offering (the `base`/`default`
images plus a paired credential sidecar) on a **small dev team**. It enumerates the
adoption path, the impacts both ways, the security findings, and a set of gates to
clear before a team rollout.

_Review date: 2026-06-13._

---

## 1. What adoption looks like

**Phase 0 — one-time platform setup (the hidden tax).** Stand up the vending
authorities: create a GitHub App, install it on the org(s), record installation
IDs, import its signing key into **KMS**; configure AWS **IAM Identity Center** + an
agent permission set. Decide the images (use `default`, or a thin layer `FROM
default`) and GHCR visibility. Author the sidecar config + a reference compose /
`devcontainer.json`. This is a day-plus of fiddly cloud/security work and needs an
**owner**.

**Phase 1 — per-developer onboarding.** Install Docker + VS Code, pull images, run
the admin-sidecar, do the **SSO device-code login**. Creds then flow via the shelf.

**Phase 2 — per-project.** Drop in `.devcontainer/` pointing at the images; set
`GH_DEFAULT_ORG` and the vended scope. Copy-paste once a template exists.

**Phase 3 — steady state.** Re-login when the SSO session lapses (the recurring
step). Pull weekly-rebuilt images. Edit scope + rebuild the sidecar when repos/roles
change. **Review agent-authored diffs before applying anything privileged.**

Daily use is smooth once set up — `git`/`gh`/`aws` "just work," creds are invisible,
agents are confined. The cost is concentrated in Phase 0 and the per-dev SSO ritual.

---

## 2. Impacts

### Positive

- **Raises the floor for everyone** — no sudo, scrubbed VS Code channels,
  `cap_drop`/`no-new-privileges`, no Docker socket — uniform, by default.
- **Blast-radius reduction** — agents get only ≤1h, scoped creds; no SSO session or
  KMS in the workspace.
- **Consistency + pluggability** — one base image; teams that don't want vending
  still get the hardened container with zero secrets (`devcred` → none).
- **Defensible posture** — short-lived + least-privilege + standard interfaces
  (KMS, `credential_process`, git helper) is the right shape and an easy story.

### Costs / friction

- **Heavy, owner-requiring setup** (App + KMS + IdC). "Pull off the shelf with light
  config" holds for the workspace *image*, **not** the vending half.
- **Bus factor / maintenance** — someone now owns image build/publish, the weekly
  rebuild, GHCR, sidecar config, key rotation, and ~hundreds of lines of
  security-critical bash. Often unfilled on a small team.
- **Distributed, silent failure modes** — creds span sidecar→shelf/socket→env with
  fail-open-to-none; "why is git unauthenticated?" becomes a multi-hop diagnosis,
  defaulting to a silent 401.
- **Workflow lock-in** — VS Code devcontainers + Docker required; other workflows
  are second-class. **No Docker socket** breaks containerized dev (testcontainers,
  image builds).
- **Stack lock-in** — vending is AWS-SSO + GitHub-App specific; a GCP/GitLab team
  gets nothing from that half.
- **Security rests on per-dev discipline** — don't authorize the VS Code git OAuth,
  and review `.devcontainer`/`.vscode` diffs before *reload*.

---

## 3. Security review (assume-breach)

The strengths are real (§3.4); the findings below are about **operational reality on
a team**, not conceptual soundness.

### 3.1 High severity / realistic break paths

1. **Within the dev container, same-uid containment is zero.** A compromised
   dependency or extension running there obtains *every* credential that container can
   fetch and exfiltrates it. (The agent is isolated in its own container; this is the
   dev container's residual untrusted code — deps and extensions.) This buys
   **blast-radius and time-bound reduction, not secrecy**: "short-lived" defeats *later
   replay*, not a *live* attacker who keeps asking.
2. **Scope discipline is the only real control — and the tooling doesn't help you do
   it.** A `contents:write` token *is* push access for whatever code holds it; the AWS
   role *is* whatever IAM allows. All safety rides on narrow grants, which the toolkit
   deliberately leaves to the operator. The path of least resistance (org-wide install,
   broad role) is the easy default — the tooling makes vending easy and narrowing hard,
   and that asymmetry is where teams get hurt.
3. **Applying agent output re-crosses every boundary.** Agent-authored code is
   contained only while it runs in the agent container; the moment a human runs it with
   privilege in a trusted context — their own machine, or a CI/CD pipeline — that
   context's authority applies, not the agent's. "Agents prepare, humans
   review-and-apply" is a *social* control that erodes under deadline pressure; the
   likeliest real compromise is a tired dev applying unreviewed agent output — not
   crypto.
4. **Desktop extension-host RCE is unmitigated and scales badly.** Untrusted code in
   the dev container (a malicious extension or dependency) can write `.vscode`/extension
   JS and, on a window reload, execute code on the dev's host — bypassing every
   credential boundary. "Review before reload" does not hold across N developers.

### 3.2 Medium severity

5. **Supply chain of the trusted image is under-governed.** The build pulls
   `curl | bash` (Claude), `yq` **with no checksum** (pandoc has one — inconsistent),
   and the **weekly rebuild auto-republishes `latest`** with no review gate. The
   whole team trusts this image; most will pin `latest`, not `sha-`. A
   security-foundational image doing unpinned `curl|bash` is a red-circle item.
6. **No audit in the shipping (shelf) posture.** File reads are invisible — you
   cannot answer "did the agent use these creds, when, for what." Incident response
   starts blind. The broker fixes it, but that's deferred.
7. **Fail-open-to-none has a security cost, not just a UX one.** Silent unauth
   normalizes "creds sometimes don't work" — exactly the noise a compromise or a
   botched scope-narrowing hides under. It should at minimum be *observable*.
8. **Bespoke security-critical bash, unaudited, no tests.** `devcred`, the adapters,
   the vend scripts, the scrub all do secret/env string-handling in shell (including
   `eval`). One quoting/word-split bug = a token leak or scrub bypass. This is the
   code that most needs tests and a second reviewer.

### 3.3 Lower / model-level

9. **The host is the real perimeter.** Each developer's machine runs the sidecar with
   a live upstream authority (e.g. an SSO session); the host itself is not hardened by
   this design. The devcontainer gives a *feeling* of sandboxing that does not extend
   to the host — a compromised machine is total game-over, and that narrative can breed
   false confidence.
10. **(Future) the broker escalation flow is a social-engineering surface.** Agents
    are persuasive; "I need elevated to do X" → human provisions a 15m grant the
    agent then uses. Design the confirmation UX defensively when built.

### 3.4 What's genuinely strong (balance)

- Real privilege separation where enforced (no SSO/KMS/Docker-socket in workspace,
  `cap_drop`, bridge networking).
- An **unusually honest** threat model — candid residuals mean no false confidence,
  itself a control.
- Leaning on KMS / `credential_process` / git-helper avoids bespoke crypto.

This is competent, security-literate work.

---

## 4. Who this fits

**Fits:** a GitHub+AWS-native team that runs agents, has at least one platform/security
owner, and accepts a devcontainer-only workflow.

**Does not fit:** a team with no platform owner, heavy Docker-in-dev needs, or a
non-AWS/GitHub stack — for them the cost/benefit inverts.

---

## 5. Rollout gates (clear these before a team rollout)

1. **Least-privilege scoping guide + narrow defaults.** Ship sane minimal
   `installations.json` / IAM templates and a "how to scope a grant" doc. Closes the
   asymmetry in finding #2 — the single highest-value fix.
2. **Image supply-chain hygiene.** Pin by digest in consuming projects; put a
   **review gate on the auto-rebuilt base**; add the missing `yq` checksum and drop
   (or pin/verify) `curl | bash`. Closes #5.
3. **Make auth failure loud / observable.** Replace silent fail-open-to-none with a
   logged/surfaced signal (e.g. a SessionStart warning + a one-line breadcrumb).
   Closes #7.
4. **Tests + a second reviewer on every secret/env-touching script.** `devcred`,
   adapters, vend scripts, scrub. Closes #8.
5. **A one-page "what this does NOT protect" for every dev** — the
   same-uid-within-a-container reality, host-is-the-perimeter, review-before-apply,
   scope-is-the-real-control, no-audit in the shelf posture. Captured in
   [SECURITY.md §3](./SECURITY.md#3-what-this-does-not-protect). Closes #1/#3/#9.

The broker + audit (#6) may remain v2 — but until then, **document that you have no
usage audit.**
