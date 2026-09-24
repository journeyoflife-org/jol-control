# Contributing to jol-control

## Governance Model

All changes to `jol-control` follow the **change management policy** defined in
`docs/change-management.md`. This is a governance repository — changes affect
all 40 repositories in the organization.

## How to Contribute

### Adding a New Repository
1. Create `repos/<repo-name>.yml` following the existing format
2. Ensure all required fields are present (see `scripts/validate_repos.py`)
3. Open a PR — CI will validate and terraform plan will post the proposed changes
4. Wait for required approvals (1 for standard, 2 for governance tier)

### Modifying Policy
1. Edit `policy/repo-defaults.yml` or `policy/compliance-gates.yml`
2. Document the rationale in the PR description
3. Link to any relevant ADR in `jol-docs`
4. 2 approvals required for policy changes

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
