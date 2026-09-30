# AGENTS.md — Rules for AI Agents Working in jol-control

Version-controlled on purpose: agent rules that live only in a local AI memory
store are per-machine, unversioned, unreviewable, and lost on host failure. They
cannot be peer-reviewed and cannot serve as compliance evidence. This file is the
authoritative statement of how an agent must behave in this repository.

`jol-control` is the governance control plane for the `journeyoflife-org` GitHub
organization. A careless change here has a **40-repository blast radius**.

## 1. Non-negotiable workflow

```
VERIFY FIRST → COMMIT → PUSH → REVIEW → MERGE → VERIFY AGAIN
```

Verify empirically. Do not trust a prior report, a previous session's summary, a
README claim, or your own earlier statement. Never commit or push unless the
human explicitly asks in the current session.

## 2. Current enforcement truth (verified — do not re-derive false beliefs)

| Statement | Reality | Evidence |
|---|---|---|
| "2 reviewers + CODEOWNERS protect main" | **Not enforced.** `solo_mode = true` | `terraform.tfvars:17`; `branch-protection.tf:39,53` omit the blocks |
| "Squash-merge only" | **False.** Merge commits disabled, squash *and* rebase enabled | `allow_merge_commit=false`, `allow_squash_merge=true`, `allow_rebase_merge=true` |
| "CI applies changes dev→staging→prod" | **Proven broken.** Both runs failed: empty-state plan `120 to add`, then `403 Resource not accessible by integration` | `apply.yml` run history; `main.tf:138-148`; state is local and gitignored |
| "Required checks ci / lint, ci / test, codeql-analysis" | **Not emitted by this repo.** GitHub reports bare job names here: `Dev — Validate`, `Staging — Apply`, `Production — Apply` | Live check-runs API; `.github/workflows/` holds only plan.yml, apply.yml, compliance-scan.yml |
| "Plan-only, no apply authority" | **False.** `make apply` and `apply.yml` both apply | `Makefile` apply target; `apply.yml:84,117` |
| "Targeted applies (-target) are the convention" | **False.** No `-target` usage anywhere in this repo | grep across `*.tf`, `Makefile`, `*.yml` |

Still genuinely enforced: signed commits, linear history, no force-push, no
branch deletion, and `prevent_destroy` on `github_repository` and
`github_branch_protection`.

## 3. Verified commands

| Command | Purpose | Notes |
|---|---|---|
| `make help` | List targets | |
| `make validate` | Validate 40 repo YAML definitions | Expected: `PASSED — 40 repo definitions validated successfully.` |
| `make test` | Plan-gate self-tests | Expected: `PASSED — 11 plan-gate tests, 0 failures.` |
| `make compliance` | Full compliance posture check | Writes `compliance-report.json` |
| `make fmt` / `make lint` | `terraform fmt` + validation | |
| `terraform validate` | Config validity | Expected: `Success! The configuration is valid.` |
| `make plan` | Real plan (needs `GITHUB_TOKEN`, refreshes state) | Writes `tfplan` |
| `terraform plan -refresh=false -input=false -out=tfplan` | Offline plan against local state | Verified to work with **no** token; shows config-vs-state deltas |
| `make plan-gate` | STOP gate on the saved plan | Halts on any destroy/replace |
| `make apply` | Apply the saved plan | Runs `plan-gate` first; asks for confirmation |
| `make drift` | Allow-list vs GitHub drift | Requires `GITHUB_TOKEN` |

## 4. Boundaries

**Read-only, never edit:** `terraform.tfstate`, `terraform.tfstate.backup`,
`.terraform/`, `.venv/`, `.idea/`, `.terraform.lock.hcl`.

**Editable with care:** `repos/*.yml`, `policy/*.yml`, `docs/*.md`, `scripts/`,
`tests/`, `Makefile`, `.github/workflows/`.

**Never change without explicit human approval in-session:** `solo_mode`,
`enforce_signed_commits`, `sensitive_repos`, any `visibility` value, any
`prevent_destroy` or `lifecycle` block, `required_approving_review_count`, and
anything in `branch-protection.tf`'s dynamic blocks.

## 5. STOP conditions — halt and report, do not proceed

1. A plan shows **any** destroy or replace action (`make plan-gate` exits 1).
2. `make plan-gate` exits **2** (UNEVALUATED). An unproven plan is not a safe
   plan. Never work around it by grepping plan text instead.
3. A plan is built on an **empty state** while proposing creates (`make
   plan-gate` reports "EMPTY state"). This is the proven `apply.yml` failure
   mode, and `prevent_destroy` does not catch it — from an empty state nothing
   is being destroyed, everything is a create.
4. A plan shows a **visibility** change on any repository.
5. A plan touches more resources than the change under discussion justifies.
6. A required edit would remove `prevent_destroy`, signed commits, linear
   history, or force-push blocks.
7. State and config disagree and live GitHub state has not been checked
   (`gh repo view journeyoflife-org/<repo> --json visibility`). A blind apply
   can flip attributes the wrong way. Known live example: state records
   `jol-dr` as `public` while GitHub reports it **PRIVATE**.
8. The same step has failed **twice**. Stop, report the exact command and full
   error output, and escalate — do not loop, and do not start "fixing" adjacent
   files that were not part of the task.

## 6. Evidence rules

- No completion claim without fresh command output from this session.
  "I've updated the file successfully" is not evidence; `terraform validate`
  returning `Success!` and an exit code of 0 is.
- Distinguish **verified** from **assumed** in every professional opinion, and
  label inferences as inferences.
- Never fabricate compliance records, ADRs, approvals, or audit evidence. ADRs
  live in `jol-docs`; if one does not exist, say so.
- A documented gap with a risk acceptance is defensible. An overstated control
  is an audit finding: the auditor tests it, it fails, and every other
  assertion in the evidence pack gets discounted.

## 7. Change discipline

- Small diffs. A ~40-line reviewable diff is safe; a 900-line one is not.
- One task per session; start a fresh session at completed-task boundaries.
- Record user-facing changes in `CHANGELOG.md` using the Keep a Changelog format
  (Added / Changed / Fixed / Removed).
- Any gate that parses tool output must ship with a fixture derived from **real**
  captured output of that tool, and must use distinct exit codes for
  safe / refused / cannot-check. See `scripts/plan_gate.py` and
  `tests/test_plan_gate.py`.
