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

## Data Flow

1. **Define**: Engineer creates/edits `repos/<name>.yml` with repo settings
2. **Validate**: `scripts/validate_repos.py` checks YAML against policy
3. **Plan**: PR triggers `terraform plan` → posted as PR comment
4. **Review**: 2 approvers (governance) or 1 approver (standard) review plan
5. **Apply**: Merge to main → `terraform apply` through dev → staging → prod
6. **Monitor**: Weekly `compliance-scan.yml` checks for drift and violations

## State Management

- Terraform state stored in S3 (`eu-central-1`) with encryption at rest
- DynamoDB table for state locking (prevents concurrent applies)
- State file contains sensitive data — access restricted to platform-admins

## Team Access

| Team | Permission | Purpose |
|------|-----------|---------|
| platform-admins | admin | Break-glass, Terraform apply, org settings |
| developers | push (platform/devops/site), pull (governance) | Day-to-day development |
| auditors | pull (all repos) | Read-only compliance review |
| security | push (all repos) | Incident response access |
