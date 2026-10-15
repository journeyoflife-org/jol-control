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
| "CI applies changes dev→staging→prod" | **Proven broken, now gated off.** Both runs failed (empty-state plan `120 to add`, then `403`). Apply jobs now require `vars.TF_REMOTE_STATE_ENABLED == 'true'` | `apply.yml` run history and job `if:` conditions; `main.tf:138-148` |
| "Production apply requires manual approval" | **False.** No `production` environment exists; `dev` and `staging` have zero `protection_rules` | GitHub environments API; `audit/soc2-checklist.yml` CC8.1-04 is now `not_implemented` |
| "Required checks ci / lint, ci / test, codeql-analysis" | **Not emitted by this repo.** GitHub reports bare job names here: `Dev — Validate`, `Staging — Apply`, `Production — Apply` | Live check-runs API; `.github/workflows/` holds only plan.yml, apply.yml, compliance-scan.yml |
| "Plan-only, no apply authority" | **False locally.** `make apply` applies on this host (now behind `plan-gate`); only CI's apply jobs are gated off | `Makefile` apply target; `apply.yml` job `if:` conditions |
| "Targeted applies (-target) are the convention" | **False.** No `-target` usage anywhere in this repo | grep across `*.tf`, `Makefile`, `*.yml` |
| "CI drift detection verifies the whole allow-list" | **Cannot verify.** In CI `scripts/drift_detect.py` runs with `secrets.GITHUB_TOKEN`, which enumerates only **public** repositories, so the fleet's one private repo (`jol-dr`) is invisible. The checker now reports that as UNEVALUATED (exit 2) instead of DRIFT — but it still cannot evaluate there. `make drift` on this host is the verifying run | Failed run 37107745958 (`in_defined_not_github: ["jol-dr"]` while `make drift` said `NO DRIFT — All 40 repos match`); `gh api repos/journeyoflife-org/jol-dr` → `visibility=PRIVATE`; `tests/test_drift_gate.py` fixture `ci_github_actions_token.json` |
| "The org defaults repo is governed like the rest of the fleet" | **False.** `journeyoflife-org/.github` is absent from the allow-list (41 live repositories, 40 declared — the delta is exactly `.github`), and its `main` is guarded by a hand-configured ruleset that no Terraform resource manages, so neither `make drift` nor any plan can see either fact. Rulesets are deliberately outside the baseline (`branch-protection.tf:119-122`), so this is an accepted deferral rather than an oversight — but the pointer that deferral gives, `docs/runbooks.md` RB-04, is "Update Compliance Gate" and says nothing about rulesets | `gh api "orgs/journeyoflife-org/repos?per_page=100" --jq 'length'` = 41 vs `ls repos/*.yml \| wc -l` = 40; `gh api repos/journeyoflife-org/.github/rulesets` → `protect-main` (id 22978013); `grep -rn ruleset *.tf` finds only the two comment lines |
| "Pull requests to `.github` merge normally" | **False, and the reason is unknown.** Three PRs on 2026-10-15 each needed `--admin`. Eight hypotheses were eliminated — failing checks, the code-owner requirement, required approvals (count is 0), required status checks (`update` carries no parameters), signatures, commit attribution, branch freshness, `require_extra_approval_for_unattributed_changes` — and a PR still reports `mergeable=true, mergeable_state=blocked`. **Do not state that code-owner review caused it; that claim was made and retracted** | `docs/drift-findings.md` S1-007 (elimination table); `gh api repos/journeyoflife-org/.github/pulls/<n> --jq .mergeable_state` |
| "The shared CI library protects the fleet" | **Partly false until 2026-10-15.** Three library workflows filtered `push:` by path but left `pull_request:` unfiltered, so application scanners ran in this docs-only definition repository and failed nine checks on every PR; and ten spokes called `compliance-check.yml` as a reusable workflow although it never declared `workflow_call`, so that compliance gate ran for nobody. Fixed in `.github` PR #9; consumer-side proof still owed | `docs/drift-findings.md` S1-006; run logs 38805059782 and 38805059669; `grep -rl compliance-check.yml@main` over the fleet |

Still genuinely enforced, **on the Terraform-managed repositories**: signed commits, linear
history, no force-push, no branch deletion, and `prevent_destroy` on `github_repository`
and `github_branch_protection`. `.github` is the exception on two counts — unmanaged
(see above) and not mergeable without a bypass — so no claim about change management in
this organization is complete until S1-007 is closed.

## 3. Verified commands

| Command | Purpose | Notes |
|---|---|---|
| `make help` | List targets | |
| `make validate` | Validate 40 repo YAML definitions | Expected: `PASSED — 40 repo definitions validated successfully.` |
| `make test` | Self-tests for all four gates | Expected: `PASSED — 11 plan-gate`, `PASSED — 16 state-gate`, `PASSED — 11 drift-gate`, `PASSED — 9 agents-table-gate` |
| `make state-gate` | STOP gate: does the state on disk account for the config? | 0 safe / 1 refused / 2 cannot-check |
| `make agents-gate` | STOP gate: is section 2 below still a well-formed table with evidence per row? | 0 pass / 1 violation / 2 cannot-check. Runs in `apply.yml`'s `Dev — Validate` on every push to `main` (`AGENTS.md` was added to that workflow's `paths:` filter for exactly this reason) and in `compliance-scan.yml` on pull requests and the weekly schedule |
| `make compliance` | Full compliance posture check | Writes `compliance-report.json` |
| `make fmt` / `make lint` | `terraform fmt` + validation | |
| `terraform validate` | Config validity | Expected: `Success! The configuration is valid.` |
| `make plan` | Real plan (needs `GITHUB_TOKEN`, refreshes state) | Writes `tfplan` |
| `terraform plan -refresh=false -input=false -out=tfplan` | Offline plan against local state | Verified to work with **no** token; shows config-vs-state deltas |
| `make plan-gate` | STOP gate on the saved plan | Halts on any destroy/replace |
| `make apply` | Apply the saved plan | Runs `plan-gate` first; asks for confirmation |
| `make drift` | Allow-list vs GitHub drift | Requires a token that can read the org. Exit codes: 0 evaluated-clean / 1 genuine drift / 2 **unevaluated** (blind or partial listing) — 2 is not a pass |

## 4. Boundaries

**Read-only, never edit:** `terraform.tfstate`, `terraform.tfstate.backup`,
`.terraform/`, `.venv/`, `.idea/`, `.terraform.lock.hcl`.

**Editable with care:** `repos/*.yml`, `policy/*.yml`, `docs/*.md`, `scripts/`,
`tests/`, `Makefile`, `.github/workflows/`.

**Never change without explicit human approval in-session:** `solo_mode`,
`enforce_signed_commits`, `sensitive_repos`, any `visibility` value, any
`prevent_destroy` or `lifecycle` block, `required_approving_review_count`, and
anything in `branch-protection.tf`'s dynamic blocks.

> **solo_mode exit criteria:** see `docs/solo-mode-exit.md` for the conditions
> under which `solo_mode` should be disabled and the transition checklist.

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
   can flip attributes the wrong way. Historical example: state recorded
   `jol-dr` as `public` while GitHub reported **PRIVATE**; reconciled by
   `terraform apply -refresh-only` — verified 2026-10-09 that state (serial 306)
   now records `visibility = "private"` and holds no branch protection for it.
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
