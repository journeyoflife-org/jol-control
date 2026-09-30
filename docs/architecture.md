# Architecture — JOL Control Plane

## Overview

`jol-control` is the central governance control plane for all repositories in the
`journeyoflife-org` GitHub organization. It enforces a consistent security and
compliance baseline across 40 repositories using Infrastructure as Code (Terraform),
declarative policy definitions, and automated compliance gates.

## Compliance Scope

| Framework | Version | Scope |
|-----------|---------|-------|
| SOC 2 Type II | 2017 TSC | All repositories |
| GDPR | Regulation (EU) 2016/679 | All repositories (27 EU states) |
| ISO 27001 | 2022 Annex A | All repositories |
| PCI-DSS | 4.0 | Payment-related repos (jol-payments-scope, jol-ecommerce-engine) |

## Architecture Diagram

```
┌──────────────────────────────────────────────────────────────────────┐
│                        jol-control (this repo)                       │
├──────────────────────────────────────────────────────────────────────┤
│                                                                      │
│  repos/*.yml          policy/                Terraform                │
│  ───────────          ──────                ─────────                │
│  Per-repo allow-list  repo-defaults.yml     main.tf                  │
│  (40 YAML files)      compliance-gates.yml  repositories.tf          │
│                                              branch-protection.tf     │
│                                              variables.tf             │
│                                              outputs.tf               │
│                                                                      │
│  .github/workflows/   audit/                scripts/                  │
│  ──────────────────   ─────                ────────                  │
│  plan.yml             soc2-checklist.yml    validate_repos.py        │
│  apply.yml            gdpr-checklist.yml    compliance_check.py      │
│  compliance-scan.yml  iso27001-checklist.yml drift_detect.py         │
│                                                                      │
└──────────────────────────┬───────────────────────────────────────────┘
                           │
                    Terraform Apply
                           │
              ┌────────────┴────────────┐
              │    GitHub Organization   │
              │   journeyoflife-org      │
              ├─────────────────────────┤
              │                         │
              │  ┌─────────────────┐    │
              │  │ Governance (12) │    │  2 reviewers + CODEOWNERS
              │  └─────────────────┘    │
              │  ┌─────────────────┐    │
              │  │ Platform  (12)  │    │  1 reviewer + CI gates
              │  └─────────────────┘    │
              │  ┌─────────────────┐    │
              │  │ DevOps    ( 5)  │    │  1 reviewer + CI gates
              │  └─────────────────┘    │
              │  ┌─────────────────┐    │
              │  │ Sites     (10)  │    │  1 reviewer + CI gates
              │  └─────────────────┘    │
              │  ┌─────────────────┐    │
              │  │ Template  ( 1)  │    │  1 reviewer
              │  └─────────────────┘    │
              │                         │
              └─────────────────────────┘
```

## Tier Model

| Tier | Repos | Reviewers | Code Owners | Compliance Gates |
|------|-------|-----------|-------------|-----------------|
| governance | 12 | 2 | Required | All gates |
| platform | 12 | 1 | Optional | dependency, secret, license, quality, SAST, container |
| devops | 5 | 1 | Optional | dependency, secret, license, quality, SAST, IaC, container |
| site | 10 | 1 | Optional | dependency, secret, license, quality, SAST |
| template | 1 | 1 | Optional | dependency, secret, license, quality |

> **Enforcement status:** the Reviewers / Code Owners columns and the tier
> labels in the diagram above are the **target baseline**. With
> `solo_mode = true` in `terraform.tfvars`, `branch-protection.tf` omits both
> `required_pull_request_reviews` and `required_status_checks`, so no approval
> or CI gate currently blocks a merge to `main`. Still enforced: signed commits,
> linear history, no force-push, no branch deletion, and `prevent_destroy` on
> `github_repository` and `github_branch_protection`. Set `solo_mode = false`
> when the first engineers are hired.

## Data Flow

1. **Define**: Engineer creates/edits `repos/<name>.yml` with repo settings
2. **Validate**: `scripts/validate_repos.py` checks YAML against policy
3. **Plan**: PR triggers `terraform plan` → posted as PR comment
4. **Review**: 2 approvers (governance) or 1 approver (standard) review plan —
   target baseline, not enforced while `solo_mode = true` (see note above)
5. **Apply**: the authoritative apply runs on the control-plane host against the
   local `terraform.tfstate`; CI runners have no access to that state (see State
   Management below). Verified: both `apply.yml` runs failed after planning
   `120 to add` from an empty state and hitting HTTP 403 on
   `POST /orgs/journeyoflife-org/repos`
6. **Monitor**: Weekly `compliance-scan.yml` checks for drift and violations

## State Management

- Terraform state stored **locally** in `terraform.tfstate` on the control plane host
- No remote backend configured (no S3, no DynamoDB, no locking)
- State file is gitignored (never committed to version control)
- **Risk**: Host loss = inability to reason about repository ownership; concurrent applies may corrupt state
- **Mitigation plan**: Migrate to HCP Terraform (free tier) for remote state, locking, and versioning — see ADR-0006 in jolarca-control for reference architecture
- **Guard**: `scripts/plan_gate.py` (invoked by `make plan-gate` and by `plan.yml`) refuses any plan that destroys or replaces a resource, and refuses a create-heavy plan built on an empty state — the exact failure mode observed in `apply.yml`. It fails closed: a missing, empty, or unparseable plan yields exit 2, never a pass

## Team Access

> **Current status:** The teams listed below are the **target baseline**. The
> actual GitHub organization currently has five teams: `backend`, `data`,
> `devops`, `frontend`, `security`. No team-repository bindings are enforced
> via Terraform. The `repos/*.yml` team assignments reference existing teams
> (`security`, `devops`, `backend`) but are decorative until team-repository
> bindings are provisioned.

| Team | Permission | Purpose |
|------|-----------|---------|
| security | admin | Break-glass, Terraform apply, org settings |
| devops | push (platform/devops/site), pull (governance) | Day-to-day development |
| backend | pull (all repos) | Read-only compliance review |
