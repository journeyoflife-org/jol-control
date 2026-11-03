# mise-en-place Rollout — Analysis & Plan

Owner: architecture (agent-drafted, human-approved)
Classification: internal
Framework: SOC2 / GDPR / ISO 27001
Status: **PILOT EXECUTED & MERGED (2026-11-03).** jol-scripts runs on mise (PR #19 → `b3c278e`); pre-existing mypy red closed (PR #20 → `c1fd3c98`); main CI green (run `41680219947`). Expansion to other repos pending.
Review cadence: revisit after the pilot CI run is verified.

> This document is the durable, reviewable form of the mise evaluation. It is a
> plan and a set of ready-to-apply artifacts. It does **not** activate mise
> anywhere; the control plane (`jol-control`) deliberately adopts mise **last**,
> as a thin wrapper only, because the Makefile gates below are working and
> compliance-gated.

---

## Pilot outcome (jol-scripts, 2026-11-03) — verified

| Phase | Evidence |
|---|---|
| Install | mise 2026.11.0, SHA256 OK, in `~/Applications/mise` (NOT the `/opt/jol` governance tree) |
| Config | `mise.toml` (py 3.11/3.12 + uv; tasks mirror Makefile) + `mise.lock` v3, 7 platforms, SHA256 + github-attestations |
| Checks | lint/scan/typecheck/test all pass locally (23 tests, 89% cov) |
| CI | `ci.yml` → pinned `jdx/mise-action@c37c93293d6b742fc901e1406b8f764f6fb19dac`, `version:"2026.11.0"`; job `lint-and-test` + `3.11/3.12` matrix preserved |
| PR #19 | mise migration, squash-merged `b3c278e` (signed `ec2bf0d`, **no admin bypass**) |
| PR #20 | mypy `--strict` fix (`dict[str, object]`, `dict[str, list[object]]`), merged `c1fd3c98` |
| main | CI run `41680219947` = success |

Findings fixed: wrong `experimental:` → `version:` input; action pinned to a SHA; uv-vs-pip editable `lib` import (via `[env] PYTHONPATH="."`); **false "no signatures" claim corrected** — jol-scripts enforces `required_signatures` + `enforce_admins`, so commits are signed, never bypassed.

## 0. What mise is (verified against mise.jdx.dev, 2026-11-03)

`mise` ("meez") is an MIT-licensed, Rust-built dev-tool **version manager + task
runner + environment manager**, configured from one `mise.toml` per directory:
- `[tools]` — pin interpreters/binaries (1,000+ registry entries: python, node,
  terraform, gh, jq, uv, age …). A spec like `"3.12"` is a **prefix**, not exact;
  exactness comes from a committed **`mise.lock`** (`mise lock`).
- `[env]` — project environment variables loaded on entry.
- `[tasks]` — named build/test/lint commands with `depends` and parallelism.
- **Trust model** — a `mise.toml` with `[env]`/`[tasks]`/hooks **can execute code**;
  mise loads it only once trusted. Read every config/task before trusting it.
- **CI** — `jdx/mise-action@v2` installs a pinned mise on the runner.
- Reads existing `.tool-versions` / `.nvmrc` / `.python-version`.

Not used here: `mise bootstrap` (whole-machine dotfiles/packages) — out of scope for
repos and a GDPR/change-control hazard; any machine-level setup stays on the host's
existing `/opt/jol` convention.

---

## 1. Verified operating context (fresh evidence, this session)

| Fact | Value | How verified |
|---|---|---|
| Live org repos | **41** (39 public + `jol-dr` private + `.github`) | `gh api orgs/journeyoflife-org/repos?per_page=100` |
| Declared allow-list | **40** `repos/*.yml` (delta = unmanaged `.github`) | python inventory of `repos/*.yml` (N=40) |
| Empty repos (size 0) | **7**: jol-iac, jol-privacy, jol-incident-response, jol-payments-scope, jol-status, jol-compliance-evidence, jol-secrets | repo list + languages API "(empty/none)" |
| Declared languages | Python 13 / TypeScript 11 / YAML 11 / Shell 4 / Makefile 1 | `repos/*.yml` `language:` (5 sampled against live languages — field trustworthy; repos are polyglot) |
| Host toolchain | python3 3.12.3, node 20.20.2, **terraform 1.16.1**, gh 2.100.0, git 2.43.0, age 1.1.1, **mise NOT installed** | version probe |
| Governance posture | `solo_mode = true`, `enforce_signed_commits = true`, `required_approving_review_count = 2`, `sensitive_repos = []` | `terraform.tfvars:10,11,16,33` |
| Merge-blocking rulesets | **20 repos** carry rulesets (protect-main etc.); `.github` too | fleet ruleset scan (below) |
| Pilot repo | **jol-scripts**: no ruleset, no branch protection; Python+uv; CI job `lint-and-test` | ruleset/protection scan + `ci.yml` read |

---

## 2. Decisions A–E — LOCKED (professional opinion)

**A — Scope model: HYBRID (per-repo `mise.toml` + a governed org baseline).**
The fleet is polyglot and tiered; a single central config cannot fit 40 repos, and
un-pinned per-repo drift is precisely what SOC2/ISO change control rejects. Each repo
gets its own `mise.toml` + `mise.lock`; a small reviewed **baseline** (§4) pins the mise
release, its provenance, and fleet-default tool versions that repos may override.
Rationale: matches the existing host pattern ("IaC tooling pinned under /opt/jol") and
the existing `.terraform.lock.hcl` discipline (a tool lockfile is the right shape).

**B — Pilot repo: `jol-scripts`, seeded into `jol-repo-template`.**
`jol-scripts` is the ideal first target: **no ruleset and no branch protection** (a PR
merges on merit, so the full loop is provable), low blast radius (devops tier), and a
real, already-instrumented check set (`ruff`, `bandit`, `mypy`, `pytest`, `pre-commit`,
`uv.lock`) that exercises mise tasks honestly. `jol-repo-template` (tier=template,
Makefile) then carries the canonical starter `mise.toml` so **new** repos inherit the
pattern. Rejected as pilots: jol-hub / jol-core (impact), the ten jol-site-* and the
other 20 ruleste-set repos (PRs merge only by admin bypass — cannot prove the loop).

**C — mise version + provenance: pin `v2026.11.0` (2026-11-03) from a checksum-verified
release binary; never `curl https://mise.run | sh`.**
The release ships `SHASUMS256.txt` (signed `.asc` + `.minisig`) and
`mise-v2026.11.0-linux-x64.tar.gz`. Install method (§5) downloads via `gh release
download`, verifies `sha256sum -c`, and extracts under `/opt/jol/mise`. In CI, pin
`jdx/mise-action@v2` **to a commit SHA** and pass the exact mise version, so a runner
cannot silently pull a different build.

**D — Exclusions / deferrals.**
- **Exclude (7 empty):** the size-0 repos above — nothing to manage. `jol-secrets` is
  empty *and* a secret store: do not introduce a code-executing tool there.
- **Exclude/defer private:** `jol-dr` — ruleset API returns **403 "Upgrade to GitHub
  Pro"** (private repos can't carry rulesets on this plan); defer and protect separately.
- **Defer to LAST:** `.github` (shared CI library, unmanaged by Terraform, carries a
  `protect-main` ruleset **and** an unresolved merge-block mystery S1-007) and
  `jol-control` (governance control plane, ~40-repo blast radius).

**E — Regression risks (where mise could break a working control) — mitigations.**
1. **Terraform version drift.** Host runs a pinned **1.16.1**; a mise `[tools]
   terraform` resolving to any other version changes plans/state. Mitigation: baseline
   pins `terraform = "1.16.1"` exactly and a `mise.lock` records it; Phase 1 diffs it.
2. **Python isolation.** `jol-control` has **no dependency manifest** (verified: no
   `pyproject.toml`/`requirements.txt`). Do not run gates against system site-packages.
   In the pilot, **uv stays the dependency/lock mechanism** (`uv run …`); mise only
   supplies interpreters. `mise.lock` (tools) is distinct from `.terraform.lock.hcl`
   (providers) and from `uv.lock` (python deps) — all three must exist independently.
3. **Required status-check names.** Branch protection/rulesets key on job names; GitHub
   reports the job's own `name:` (e.g. `lint-and-test`), not a `workflow / job` string.
   **Never rename a job/step in a CI migration.** (Verified: jol-control.yml requires
   contexts "Validate Repo Allow-List" / "Policy Compliance Check".)
4. **`mise [tasks]` = arbitrary code execution.** Phase 3 trust gate reads every task
   before `mise trust`.
5. **CI apply gating.** CI `apply.yml` jobs are gated by `vars.TF_REMOTE_STATE_ENABLED`;
   a mise CI change must not enable apply or drop that gate.

---

## 3. Fleet applicability matrix & sequencing

| Band | Repos | Action | Why |
|---|---|---|---|
| **Pilot** | jol-scripts | Phases 1–7 now | no ruleset/protection; real uv+pytest checks; tiny blast radius |
| **Seed** | jol-repo-template | carry starter `mise.toml` after pilot | future repos inherit the pattern |
| **Adopt — clean** | jol-core, jol-auth, jol-analytics-ai, jol-bitrix24-integration, jol-link-registry, jol-mcp-servers, jol-devops, jol-security, jol-docs, jol-policies | Phase 8, one repo/PR, risk-ascending | no ruleset → PRs merge on merit |
| **Adopt — ruleset-blocked** | jol-hub, jol-compliance, jol-deploy, jol-infrastructure, jol-domain-taxonomy, jol-ecommerce-engine, jol-hermes-agents, jol-rag-server, jol-llm, 10 × jol-site-* | Phase 8 **after** the ruleset obstacle is resolved | each carries `protect-main`; a mise PR can only merge via admin bypass (unsatisfiable reviews) |
| **Control — LAST** | jol-control (wrapper only, Makefile kept), `.github` | only after fleet stable | highest blast radius; `.github` has the S1-007 merge mystery |
| **Exclude** | 7 empty repos + jol-secrets | none | size 0 / secret store |
| **Defer** | jol-dr | revisit after private-repo protection is fixed | rulesets 403 on private repos |

**Hygiene flags found during the scan (fix before relying on check names):**
`jol-compliance` has **three overlapping rulesets** ("Protect main branch",
"jol-compliance-main-protection", "protect-main"); `jol-hub` has a stale `~master`
ruleset while its default branch is `main`.

---

## 4. Org baseline (reference config — NOT an active file)

```toml
# journeyoflife-org mise baseline. Repos copy/override this; exact versions land in
# each repo's committed mise.lock. Approved mise release: v2026.11.0 (verify SHASUMS256).
# CI: jdx/mise-action@v2, pinned to a commit SHA, experimental:"2026.11.0".
[tools]
python    = "3.12"     # fleet default; a repo may extend (e.g. jol-scripts: ["3.11","3.12"])
node      = "20"       # matches host 20.20.2 (verify per TS repo)
terraform = "1.16.1"   # MUST equal the host-pinned version + .terraform.lock.hcl (risk E.1)
gh        = "latest"   # pin via mise.lock
jq        = "latest"
age       = "1.1.1"    # matches RB-08 backup/retire tooling
```

---

## 5. Host install (pinned + checksum; runs only on explicit operator go)

> Not executed by this session (network download + host mutation require explicit
> human action per the ground rules). The tarball layout is confirmed before extraction.

```bash
mkdir -p /opt/jol/mise && cd /opt/jol/mise
gh release download v2026.11.0 --repo jdx/mise \
  -p 'mise-v2026.11.0-linux-x64.tar.gz' -p 'SHASUMS256.txt'
tar -tzf mise-v2026.11.0-linux-x64.tar.gz | head        # inspect layout first
grep 'linux-x64.tar.gz' SHASUMS256.txt | sha256sum -c -  # verify before extract
tar -xzf mise-v2026.11.0-linux-x64.tar.gz
./mise/bin/mise --version ; ./mise/bin/mise doctor
```

---

## 6. Pilot artifact — `mise.toml` for jol-scripts

> Python deps stay in **uv**; mise tasks invoke the **same** commands the CI already
> runs, so behaviour and job names are unchanged. Place at the repo root of jol-scripts.

```toml
[tools]
python = ["3.11", "3.12"]   # match ci.yml matrix
uv = "latest"

[tasks.deps]
run = "uv sync --all-extras"

[tasks.lint]
run = "uv run ruff check lib/ scripts/ && uv run ruff format --check lib/ scripts/"

[tasks.security]
run = "uv run bandit -c pyproject.toml -r lib/ scripts/"

[tasks.types]
run = "uv run mypy lib/ scripts/"

[tasks.test]
run = "uv run pytest --cov=lib --cov-report=term-missing"

[tasks.check]
description = "Full gate set (mirrors CI job lint-and-test)"
depends = ["lint", "security", "types", "test"]
```

**Lockfile (Phase 6, genuine):** `mise lock` → commit `mise.lock`; `uv lock` already
present (`uv.lock`) stays authoritative for Python deps. Verify a clean install on the
runner image: `mise install && mise run check`.

---

## 7. Pilot CI migration (Phase 7) — thin, names preserved

Variant A (first, lowest risk): add mise for local/dev parity, **leave `ci.yml`
untouched**; prove `mise run check` reproduces the green CI locally.

Variant B (the actual CI migration proof): keep the job name `lint-and-test` and every
step name; replace the interpreter bootstrap with a pinned mise action and call tasks.

```yaml
# inside jobs.lint-and-test.steps — AFTER actions/checkout, replacing setup-python+pip
      - name: Install mise                     # job/step names stay valid
        uses: jdx/mise-action@v2               # pin to a commit SHA before merge (rule 7)
        with: { experimental: "2026.11.0" }
      - name: Install dependencies
        run: mise run deps
      - name: Ruff lint / Bandit / Mypy / Pytest
        run: mise run check                     # same underlying commands as before
```

Preserve `permissions: { contents: read }` and the codeql/compliance workflows.
**Do not rename `lint-and-test`** (risk E.3). Because jol-scripts currently has no
required checks and no ruleset, the pilot PR merges on merit; the required-check-
preservation proof is deferred to Phase 8 governance repos, where checks actually exist.

---

## 8. Phase evidence & rollback

| Phase | Verification evidence | Rollback |
|---|---|---|
| 1 Version review | diff table: proposed pins vs installed vs ci.yml matrix (done §1,§6) | n/a (analysis) |
| 2 mise release | `mise --version`=2026.11.0; `sha256sum -c` OK; `mise doctor` clean | `rm -rf /opt/jol/mise` |
| 3 config review | list of `[tasks]`/`[env]` with a trust decision per line; no unexplained exec/shell/net | un-trust / delete file |
| 4 install tools | `mise ls --current`, `mise config ls`; uv venv isolated (deps not in system) | `uv cache clean`; delete `.venv` |
| 5 run checks | `mise run check` exit 0, output tail; investigate any skip/unevaluated | n/a |
| 6 lockfile | committed `mise.lock` contents; clean `mise install && mise run check` on runner image | revert lockfile |
| 7 CI pilot | pilot run URL green with **unchanged** `lint-and-test`; diff proves no control weakened | revert workflow file (one-line) |
| 8 expand | per-repo record (config, lock, CI run, control-preservation proof, rollback) | per-repo `git revert` |

---

## 9. Compliance cross-reference (map to real audit files; do not invent IDs)

- **SOC 2 (CC8 change management / CC6 least privilege):** every band change lands as a
  signed PR with a documented rollback (§8) and evidence; mise's own execution surface is
  gated by the trust review (Phase 3). See `audit/soc2-checklist.yml`.
- **ISO/IEC 27001 (supplier & secure-configuration / reproducible builds):** the mise
  release + SHA256 provenance (§5) and pinned `[tools]` are recorded as controlled
  configuration; lockfiles make builds reproducible. See `audit/iso27001-checklist.yml`.
- **GDPR:** adopting a dev tool introduces **no new personal-data processing**. Guardrails:
  never put secrets in `[env]`/committed files; ensure `mise run` output in CI logs does not
  echo credentials; `mise bootstrap` (machine dotfiles) is **out of scope**. See
  `audit/gdpr-checklist.yml`.
- Change-management control: `docs/change-management.md`; drift register: `docs/drift-findings.md`.

---

## 10. What has NOT been done (and needs your explicit go)

This session performed **only read-only verification**. The following are deliberate,
reversible but real **mutations** that the ground rules and the rollout plan gate behind
an explicit per-target instruction:
- Installing mise on the host (§5) — network download + `/opt/jol` write.
- Adding `mise.toml`/`mise.lock` and opening a PR in **jol-scripts** — a different repo,
  not in this workspace; requires a signed commit.
- Editing any workflow / the `.github` library / `jol-control` (Phase 8, LAST).
- `terraform`/apply actions of any kind — none are required to adopt mise.
