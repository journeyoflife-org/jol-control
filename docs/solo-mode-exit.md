# solo_mode Exit Criteria

This document defines the conditions under which `solo_mode` should be disabled and the checklist for transitioning to full governance.

## Current State

`solo_mode = true` in `terraform.tfvars`. This drops:
- `required_pull_request_reviews` (multi-reviewer gates)
- `required_status_checks` (CI gate requirements)
- `require_code_owner_reviews`
- `require_last_push_approval`

But keeps:
- `enforce_admins = true`
- `require_signed_commits = true`
- `required_linear_history = true`
- `allows_force_pushes = false`
- `allows_deletions = false`

## Exit Criteria

Disable `solo_mode` when **ALL** of the following are true:

### 1. Team Structure

- [ ] At least **2 active engineers** with write access to the organization
- [ ] Teams exist and are populated (current teams: `backend`, `data`, `devops`, `frontend`, `security`)
- [ ] Team assignments in `repos/*.yml` reference actual teams (currently: `security` for admin, `devops` for push, `backend` for pull)
- [ ] Team-repository bindings enforced via `github_team_repository` Terraform resources
- [ ] CODEOWNERS file in each repo referencing the correct teams

> **Note:** Team assignments in `repos/*.yml` are currently decorative — Terraform does not provision `github_team_repository` resources. Before exiting solo_mode, implement team-repository bindings in Terraform or create them manually via GitHub UI.

### 2. CI/CD Infrastructure

- [ ] Remote Terraform state backend provisioned (HCP Terraform)
- [ ] State migration executed (local → remote)
- [ ] Org-scoped GitHub token configured in CI secrets
- [ ] CI workflows added to repos and `repos/*.yml` contexts updated to match actual check-run names
- [ ] `TF_REMOTE_STATE_ENABLED=true` repository variable set

> **Note:** As of 2026-09-30, `repos/*.yml` contexts are cleared to `[]` (except jol-control which has `Validate Repo Allow-List` and `Policy Compliance Check`). Before exiting solo_mode, add CI workflows to repos and update contexts to match the check-run names GitHub reports. Use: `gh api repos/OWNER/REPO/commits/BRANCH/check-runs --jq '.check_runs[].name'` to discover actual names.

### 3. Compliance Posture

- [x] Audit checklists (SOC2, ISO 27001, GDPR) updated to reflect actual enforcement — **DONE 2026-09-30**
- [x] All controls claimed "implemented" are verified against live API — **DONE 2026-09-30**
- [x] Drift findings register (`docs/drift-findings.md`) has no open S0 or S1 items — **DONE 2026-09-30** (S2-001, S2-002, S2-003 fixed)

### 4. Approval Workflow

- [ ] `production` environment created with required reviewers
- [ ] Manual approval gate configured for production apply
- [ ] Break-glass procedure documented and tested

## Transition Checklist

When exiting `solo_mode`, execute in this order:

1. **Pre-flight**
   ```bash
   # Verify team structure
   gh api orgs/journeyoflife-org/teams --jq '.[].slug'
   # Expected: backend, data, devops, frontend, security
   
   # Verify CI check-run names match contexts in repos/*.yml
   gh api repos/journeyoflife-org/jol-control/commits/main/check-runs --jq '.check_runs[].name'
   # Compare output to contexts: [] in each repos/*.yml
   
   # Verify remote state
   terraform init  # should pull from remote backend
   
   # Verify no open S0/S1 drift findings
   grep -c "Status:.*OPEN" docs/drift-findings.md
   # Expected: 0 (or only S2 items)
   ```

2. **Update terraform.tfvars**
   ```hcl
   solo_mode = false
   ```

3. **Plan and verify**
   ```bash
   make plan
   make plan-gate  # should exit 0 (no destroys/replaces)
   ```

4. **Apply**
   ```bash
   make apply
   ```

5. **Post-apply verification**
   ```bash
   # Verify branch protection now includes review requirements
   gh api repos/journeyoflife-org/jol-control/branches/main/protection \
     --jq '.required_pull_request_reviews'
   
   # Verify required status checks are enforced
   gh api repos/journeyoflife-org/jol-control/branches/main/protection \
     --jq '.required_status_checks'
   ```

6. **Update compliance checklists**
   - SOC2 CC8.1-01: "All changes require pull request with approvals" → `implemented`
   - SOC2 CC8.1-02: "Changes to governance repos require 2 approvals" → `implemented`
   - ISO 27001 A.7.1-02: "Branch protection prevents unauthorized code changes" → `implemented`

## Rollback

If issues arise after disabling `solo_mode`:

```bash
# Re-enable solo_mode
sed -i 's/solo_mode = false/solo_mode = true/' terraform.tfvars
make plan
make apply
```

This will drop review requirements while keeping integrity controls.

## Notes

- `solo_mode` is a safety valve for single-owner operation, not a permanent state
- The goal is to enable full governance as soon as team structure supports it
- Document the decision to exit `solo_mode` in an ADR in `jol-docs`
