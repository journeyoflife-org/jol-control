# Contributing to jol-control

## Governance Model

All changes to `jol-control` follow the **change management policy** defined in
`docs/change-management.md`. This is a governance repository — changes affect
all 40 repositories in the organization.

> **Current enforcement status:** `solo_mode = true` in `terraform.tfvars`
> (single-owner operation). Every approval count quoted in this file is the
> **target baseline**, not a live control: while solo_mode is true,
> `branch-protection.tf` omits `required_pull_request_reviews` and
> `required_status_checks`, so the owner pushes directly to `main`. Still
> enforced: signed commits, linear history, no force-push, no branch deletion.

## How to Contribute

### Adding a New Repository
1. Create `repos/<repo-name>.yml` following the existing format
2. Ensure all required fields are present (see `scripts/validate_repos.py`)
3. Open a PR — CI will validate and terraform plan will post the proposed changes
4. Wait for required approvals (1 for standard, 2 for governance tier) —
   target baseline; not enforced while `solo_mode = true` (see note above)

### Modifying Policy
1. Edit `policy/repo-defaults.yml` or `policy/compliance-gates.yml`
2. Document the rationale in the PR description
3. Link to any relevant ADR in `jol-docs`
4. 2 approvals required for policy changes — target baseline; not enforced
   while `solo_mode = true` (see note above)

### Updating Compliance Gates
1. Edit `policy/compliance-gates.yml`
2. Update the `enforcement_matrix` if tier assignments change
3. Update corresponding `required_status_checks` in affected `repos/*.yml` files
4. Run `python3 scripts/validate_repos.py` locally before pushing

## Code Standards

- YAML files must pass `yamllint` with project defaults
- Terraform must pass `terraform fmt -check` and `terraform validate`
- Python scripts must pass `ruff check` and `mypy --strict`
- All PRs must include signed commits (GPG or SSH)

> **What CI actually runs:** the workflows in `.github/workflows/` execute
> `scripts/validate_repos.py`, `scripts/compliance_check.py`,
> `scripts/drift_detect.py`, `terraform init`, `terraform validate`, and
> `terraform plan`. No `yamllint`, `ruff`, `mypy`, or `terraform fmt -check`
> job exists, and no workflow declares a `ci` workflow with `lint`/`test` jobs —
> so the `ci / lint` and `ci / test` contexts in `policy/repo-defaults.yml` are
> not produced by this repository. The check-run names GitHub actually reports
> here are bare job names, verified live: `Dev — Validate` (success),
> `Staging — Apply` (**failure**), `Production — Apply` (skipped).
>
> `apply.yml` fails because the runner plans from an **empty state**
> (`Plan: 120 to add, 0 to change, 0 to destroy`) and then receives
> `403 Resource not accessible by integration` from
> `POST /orgs/journeyoflife-org/repos`. Treat the bullets above as contributor
> expectations run locally, not as enforced gates. Signed commits *are*
> enforced (`require_signed_commits`, which stays active in solo mode).

## Compliance Requirements

Every PR is subject to:
- Dependency vulnerability scanning
- Secret scanning (push protection)
- License compliance check
- CodeQL SAST analysis
- Policy validation (`scripts/validate_repos.py`)

## Emergency Changes

For incident response requiring immediate changes:
1. Make the change with 1 approval
2. Document in PR within 24 hours
3. Retroactive review by 2nd approver required
