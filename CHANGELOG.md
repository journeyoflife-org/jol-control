# Changelog

All notable changes to jol-control will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- `scripts/state_gate.py` — STOP gate that refuses `terraform apply` when the state in
  front of the config cannot account for what the config would create: 0-byte state file
  (Terraform writes state atomically and never produces one on its own), state that
  parses but holds zero managed resources, or no state at all while the directory
  declares resources or module blocks. Reads `terraform.tfstate` **and**
  `terraform.tfstate.d/<workspace>/terraform.tfstate`, and classifies a directory as
  "not an apply target" only on positive evidence (a parent `module` block with a
  relative source, or a vendored/quarantined tree) — never on absence of state.
  A root whose backend is declared in `.tf`/`.tpl`/`.backend.hcl` is reported
  UNEVALUATED rather than safe, because local files cannot see remote state.
- `tests/test_state_gate.sh` — 16 self-tests with distinct exit codes
  (0 safe / 1 refused / 2 cannot-check), built on the key shape of a real captured
  Terraform 1.16.1 state document
- `tests/test_drift_gate.py` + `tests/fixtures/drift_detect/` — 11 self-tests for
  `scripts/drift_detect.py`, built on two real captures of `gh repo list
  journeyoflife-org --json name,visibility`: the operator-token view (41 rows, one
  PRIVATE) and the `secrets.GITHUB_TOKEN` view reconstructed from the log of failed run
  37107745958 (39 rows, no private repository visible at all)

### Changed
- `make plan-gate` now depends on `make state-gate`, so `make apply` is behind two
  gates instead of one; `make test` runs the state-gate suite alongside plan-gate
- `.github/workflows/apply.yml`: `dev-validate` now runs `bash tests/test_state_gate.sh`
  next to the plan-gate self-test, and `on.push.paths` gained `scripts/**` and
  `tests/**`. Before this, a change to either gate could land with no CI run at all —
  an inert gate is worse than an absent one. The gate itself is not executed in CI: it
  judges local state, and CI has neither the state nor backend credentials

### Fixed
- `scripts/drift_detect.py`: the weekly Compliance Scan has failed since run 37107745958
  (2026-10-03) reporting `in_defined_not_github: ["jol-dr"]`. **Nothing is missing:**
  `jol-dr` exists with `visibility=PRIVATE` (`gh api repos/journeyoflife-org/jol-dr`),
  and `make drift` on this host reports `NO DRIFT — All 40 repos match`. CI runs the
  checker with `secrets.GITHUB_TOKEN`, which can only enumerate public repositories, so
  the fleet's one private repo looked absent. The checker treated "cannot see" as "does
  not exist". It now distinguishes the three verdicts with distinct exit codes
  (0 evaluated-clean / 1 genuine drift / 2 unevaluated), and a private-blind or partial
  enumeration returns 2 — never 1, and never 0. Every declared absence is confirmed by a
  direct lookup, and a repository that answers a lookup while missing from the listing
  makes the run UNEVALUATED rather than DRIFT.
- `scripts/drift_detect.py`: fail-open path removed. Previously an empty listing or a
  failed `gh` call printed a warning and returned **0**, so a fully blind run reported
  the control as passing. A crash now maps to 2 as well
- `.github/workflows/compliance-scan.yml`: the drift step now labels exit 2 as
  `Drift detection UNEVALUATED` with the remedy named inline (an org-read token, or
  `make drift` on the control-plane host) instead of emitting the same generic failure
  as real drift; `validate-repos` runs the drift-gate self-test on every PR so the
  checker itself cannot go inert

## [1.1.3] - 2026-09-30

### Added
- `docs/drift-findings.md` — drift findings register tracking divergence between
  Terraform state, configuration, and live GitHub state. Severity levels: S0
  (stop-work), S1 (fix before apply), S2 (fix soon). Records S1-001 (private
  repo branch protection, FIXED), S2-001 (stale contexts, FIXED), S2-002
  (non-existent team references, FIXED), S2-003 (local state, OPEN/RA-03),
  plus three resolved findings from the refresh-only reconcile
- `docs/solo-mode-exit.md` — exit criteria and transition checklist for
  disabling `solo_mode`. Four sections: team structure, CI/CD infrastructure,
  compliance posture (marked DONE 2026-09-30), and approval workflow. Includes
  pre-flight verification commands, rollback procedure, and notes on decorative
  team assignments and empty contexts

### Changed
- `repos/*.yml` (39 files): cleared `required_status_checks.contexts` to `[]`.
  Contexts like `ci / test`, `codeql-analysis`, and `dependency-review`
  referenced CI workflows that do not exist in those repos. Only `jol-control`
  retains contexts (`Validate Repo Allow-List`, `Policy Compliance Check`)
  matching the check-run names emitted by `compliance-scan.yml`. While
  `solo_mode = true` makes contexts inert, clearing them prevents merge blocks
  when `solo_mode` is eventually disabled
- `repos/*.yml` (40 files): updated team references to existing teams:
  `platform-admins` → `security`, `developers` → `devops`, `auditors` →
  `backend`. The previous team names do not exist in the organization
  (verified: `backend`, `data`, `devops`, `frontend`, `security`). Team
  assignments remain decorative until `github_team_repository` Terraform
  resources are provisioned
- `docs/architecture.md`: Team Access section updated to reference existing
  teams, with a note that team-repository bindings are not enforced via
  Terraform and assignments are decorative

### Fixed
- S2-001: required status check contexts no longer reference non-existent CI
  workflows. When `solo_mode` is disabled, empty contexts will not block merges
- S2-002: team references in `repos/*.yml` now point to teams that actually
  exist in the organization
- S2-003: local Terraform state documented in `docs/drift-findings.md` as an
  open finding with RA-03 risk acceptance. No infrastructure change; mitigation
  path (HCP Terraform migration) documented in `docs/solo-mode-exit.md`

## [1.1.2] - 2026-09-30

### Changed
- `apply.yml` no longer plans or applies in CI. `dev-validate` is now a
  validation-only preflight (YAML validation, `terraform init`,
  `terraform validate`, plan-gate self-test) and the misleading empty-state
  `terraform plan` step was removed. `staging-apply` and `prod-apply` are gated
  behind `vars.TF_REMOTE_STATE_ENABLED == 'true'`, and each now runs
  `scripts/plan_gate.py` before applying
- `docs/change-management.md`: the Approval Matrix "Environment Gate" column is
  labelled target design, with the verified absence of any environment gate
  recorded

### Fixed
- `apply.yml`: removed the false "Production apply (requires manual approval)"
  claim — verified via the GitHub environments API that no `production`
  environment exists and that `dev`/`staging` have zero `protection_rules`
- `audit/soc2-checklist.yml`: CC8.1-04 changed from `implemented` to
  `not_implemented`, with the evidence field corrected to record that the cited
  control does not exist. A checklist asserting a non-existent approval gate is
  a fabricated compliance record
- `AGENTS.md`: enforcement-truth table updated for the gated apply jobs and the
  missing `production` environment

## [1.1.1] - 2026-09-30

### Added
- `scripts/plan_gate.py` — STOP gate that refuses any plan destroying or
  replacing a resource, and also refuses a create-heavy plan built on an empty
  state: the failure mode proven in this repo's own `apply.yml` history
  (`120 to add` from an empty state, then HTTP 403). Parses `terraform show -json`
  rather than plan text, and fails **closed** with distinct exit codes:
  0 safe, 1 refused, 2 unevaluated
- `tests/test_plan_gate.py` and `tests/fixtures/plan_gate/` — 11 self-tests over
  fixtures derived from real captured `terraform show -json` output, so the gate
  cannot go inert silently
- `make plan-gate` and `make test` targets; `plan.yml` now runs the gate
  self-test and the destroy/replace gate on every PR
- `AGENTS.md` — version-controlled agent rules: verified commands, edit
  boundaries, explicit STOP conditions, and the current enforcement truth

### Changed
- `make apply` now depends on `plan-gate` and no longer advises "use CI/CD
  instead" — CI cannot apply, because state is local to the control-plane host
- `repos/jol-control.yml` required status checks now name check-runs this repo
  actually emits (`Validate Repo Allow-List`, `Policy Compliance Check`) — GitHub
  reports bare Actions job names, verified live via the check-runs API, not
  `workflow / job` strings. The unsatisfiable `compliance-scan / validate` and
  `codeql-analysis` entries were removed
- `policy/repo-defaults.yml` documents that a required context must equal the
  check-run name GitHub reports (the bare Actions job `name:`), and records that
  the org-wide check names are NOT verified against the 39 managed repositories
- `.gitignore` now excludes generated `tfplan.json`

### Fixed
- Documentation accuracy: annotated reviewer/approval gates in `README.md`,
  `CONTRIBUTING.md`, `docs/architecture.md`, `docs/change-management.md`, and
  `docs/runbooks.md` to state that they are the target baseline and are **not**
  enforced while `solo_mode = true`
- `policy/repo-defaults.yml`: corrected the `allow_merge_commit: false` comment —
  the baseline is not "squash-only" because `allow_rebase_merge: true`; linearity
  comes from `require_linear_history`
- `README.md` / `docs/architecture.md` / `docs/change-management.md`: replaced the
  "applied automatically via GitHub Actions (dev → staging → prod)" claim with the
  actual apply path — local `terraform.tfstate` on the control-plane host, which
  CI runners cannot reach, with the default `GITHUB_TOKEN` only — since proven by
  both `apply.yml` runs failing with HTTP 403 after a 120-resource empty-state plan
- `CONTRIBUTING.md`: documented which checks CI actually runs, listed the
  check-run names GitHub really reports for this repo, and recorded that the
  `ci / lint` and `ci / test` contexts are not produced by any workflow here

## [1.1.0] - 2026-09-26

### Added
- `solo_mode` variable for single-owner operation — drops multi-reviewer and code-owner gates while keeping signed commits, linear history, and force-push/deletion blocks
- Dynamic branch protection blocks that adapt to solo_mode vs team operation
- RA-03 risk acceptance entry for local Terraform state (no remote backend)

### Changed
- Migrated `vulnerability_alerts` from deprecated inline argument to separate `github_repository_vulnerability_alerts` resource (provider v6.x compatibility)
- Updated `required_approving_review_count` validation to allow 0 (solo mode)
- Removed unused `data.github_organization.jol` and `data.github_team.security` data sources
- Removed security manager role resources from org-settings.tf (no teams in solo mode)

### Fixed
- Documentation accuracy: replaced false S3/DynamoDB state claims with local state reality in `docs/architecture.md` and `docs/threat-model.md`
- CI workflows: removed non-functional AWS credential references from `plan.yml` and `apply.yml` (local state requires no AWS credentials)
- Removed unnecessary `requests` dependency from `compliance-scan.yml` drift detection step
- Added `.jolarca-staging/` to `.gitignore` to prevent foreign project artifacts

### Removed
- PyCharm utility scripts (disable_pycharm_plugins.sh, disable_pycharm_power_save.sh) — not control-plane infrastructure

## [1.0.0] - 2026-09-24

### Added
- Initial release — central governance control plane for journeyoflife-org
- 40 repository YAML allow-list definitions (repos/*.yml)
- Policy baselines: repo-defaults.yml, compliance-gates.yml
- Terraform IaC: GitHub provider, repository resources, branch protection
- CI/CD workflows: plan (PR comment), apply (dev→staging→prod), compliance-scan
- Audit checklists: SOC 2, GDPR, ISO 27001
- Python scripts: validate_repos, compliance_check, drift_detect
- Documentation: architecture, runbooks, threat model, data classification, change management
- Compliance frameworks: SOC 2 Type II, GDPR, ISO 27001:2022, PCI-DSS 4.0
