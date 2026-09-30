# Change Management Policy

## Scope
This policy governs all changes to the jol-control Terraform configuration,
policy baselines, and repository allow-list definitions.

## Change Categories

### Standard Changes (Pre-approved)
- Adding a new repository to the allow-list
- Updating repository description or topics
- Adjusting branch protection contexts (within policy bounds)

### Normal Changes (Requires Review)
- Changing repository visibility (public ↔ private)
- Modifying team access permissions
- Adding or removing compliance gates
- Changing required reviewer counts

### Emergency Changes (Break-glass)
- Incident response requiring immediate access changes
- Security vulnerability requiring urgent patching
- Must be documented retroactively within 24 hours

## Change Process

```
┌──────────┐    ┌──────────┐    ┌──────────┐    ┌──────────┐    ┌──────────┐
│  Define   │───▶│ Validate │───▶│  Review  │───▶│  Approve │───▶│  Apply   │
│  (PR)     │    │ (CI)     │    │ (Plan)   │    │ (Merge)  │    │ (CD)     │
└──────────┘    └──────────┘    └──────────┘    └──────────┘    └──────────┘
```

1. **Define**: Create/edit files in a feature branch
2. **Validate**: CI runs `validate_repos.py` + `terraform validate`
3. **Review**: `terraform plan` output posted as PR comment
4. **Approve**: 
   - Governance changes: 2 reviewers required (target baseline — see note below)
   - Standard changes: 1 reviewer required (target baseline — see note below)
5. **Apply**: the authoritative apply runs on the control-plane host against the
   local `terraform.tfstate`; `apply.yml` runners have no access to that state
   (see `docs/architecture.md` → State Management)

## Approval Matrix

| Change Type | Approvers | Environment Gate (target design) |
|-------------|-----------|-----------------|
| Add repo | 1 | Auto (dev → staging → prod) |
| Remove repo | 2 | Manual prod approval |
| Change visibility | 2 | Manual prod approval |
| Policy change | 2 | Manual prod approval |
| Emergency | 1 (post-hoc: 2) | Immediate, documented within 24h |

> **Enforcement status:** the approver counts above are the target baseline.
> With `solo_mode = true` in `terraform.tfvars`, `branch-protection.tf` omits
> both `required_pull_request_reviews` and `required_status_checks`, so no
> approval or CI gate currently blocks a change to `main`. Controls that remain
> enforced: signed commits, linear history, no force-push, no branch deletion,
> and `prevent_destroy` on `github_repository` and `github_branch_protection`.
> Set `solo_mode = false` when the first engineers are hired to restore the
> matrix above.
>
> **Environment gate status:** none operates today. Verified via the GitHub
> environments API: only `dev` and `staging` exist — there is **no `production`
> environment** — and neither has any `protection_rules`, so no manual approval
> gate is configured. `apply.yml`'s apply jobs are additionally gated off behind
> `TF_REMOTE_STATE_ENABLED`, because a CI runner cannot reach the local state.
> The "Environment Gate" column above is therefore a target design, not a live
> control.

## Rollback Procedure
1. Revert the PR that caused the issue
2. Terraform apply will revert GitHub state
3. Verify with `python3 scripts/drift_detect.py`
