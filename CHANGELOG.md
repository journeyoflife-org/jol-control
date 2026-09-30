# Changelog

All notable changes to jol-control will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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
