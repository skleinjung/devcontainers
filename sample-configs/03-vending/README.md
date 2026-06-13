# 03-vending — hardened workspace + credential vending

A drop-in for a workspace that consumes vended **AWS + GitHub** credentials from a
read-only shelf — the Layer 1 + Layer 3 shape (no isolated agent; an agent, if you run
one, runs in the workspace). Copy this **whole directory's** contents into your
project's `.devcontainer/` (it includes `github-creds/`).

```
workspace                  the dev container (default image, or build your own FROM it)
credential-shelf-aws       vends AWS role creds → /creds/aws/credentials
credential-shelf-github    vends per-org GitHub App tokens → /creds/github/<org>
  └ github-creds/          a tiny derived image that bakes YOUR installations.json
```

Credentials flow: **sidecars → the read-only `/creds` shelf → base's `devcred`/git/gh/aws
shims**. `git push/pull` over HTTPS and `aws`/`gh` work once the sidecars are vending.

## 1. Fill in before first run

- **`docker-compose.yml`**: `GH_DEFAULT_ORG`, `VEND_AWS_PROFILES`, `VEND_GH_APP_ID`,
  `VEND_GH_KMS_KEY_ID`, `VEND_GH_AWS_PROFILE` (the `<placeholders>`).
- **`github-creds/installations.json`**: your org(s) + installation id(s) (+ optional
  `repos`/`perms`). Empty `[]` → GitHub vending idles.

## 2. One-time KMS setup (GitHub App key)

The GitHub sidecar signs App JWTs via KMS. Once, with AWS creds that can create KMS keys,
run `import-app-private-key <app-key.pem>` (shipped in the sidecar) to import the App's
RSA key as a non-extractable KMS key; use the printed alias as `VEND_GH_KMS_KEY_ID`, grant
`kms:Sign` on it to `VEND_GH_AWS_PROFILE`, then shred the `.pem`. (See
[images/credential-shelf-github](../../images/credential-shelf-github).)

## 3. First run — the SSO login (once per SSO session)

Both sidecars share the `admin-home` volume, so **one** login serves both. From a **host**
terminal (the sidecars hold your SSO session; the workspace never does):

```sh
# bring up the sidecars
docker compose -p <project> up -d credential-shelf-aws credential-shelf-github
# set up ~/.aws/config (your SSO start URL + the agent/kms profiles) in the shared home,
# then log in — its cache lands in admin-home and both sidecars use it:
docker exec -it <project>-credential-shelf-aws-1 aws sso login --profile <your-agent-profile>
```

Within ~60s both vend. Check health from anywhere with the volume:
`cat /creds/status/*` (`ok expires=…` per loop).

When the SSO session lapses (org default ~8h), repeat the `aws sso login` step. If creds
go stale, the workspace's `git`/`gh`/`aws` print a `devcred` breadcrumb pointing here.
