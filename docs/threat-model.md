# Threat Model — JOL Control Plane

## Methodology

STRIDE (Spoofing, Tampering, Repudiation, Information Disclosure, Denial of Service, Elevation of Privilege)

## System Boundaries

```
                    ┌─────────────────────────────────┐
                    │         GitHub Platform          │
                    │  ┌───────────────────────────┐  │
                    │  │   journeyoflife-org        │  │
                    │  │  ┌─────────────────────┐  │  │
                    │  │  │   jol-control        │  │  │
                    │  │  │   (Terraform + Policy)│  │  │
                    │  │  └──────────┬──────────┘  │  │
                    │  │             │              │  │
                    │  │  ┌──────────▼──────────┐  │  │
                    │  │  │  40 managed repos     │  │  │
                    │  │  └─────────────────────┘  │  │
                    │  └───────────────────────────┘  │
                    └─────────────────────────────────┘

                    ┌─────────────────────────────────┐
                    │   Control Plane Host (Proxmox)   │
                    │  ┌───────────────────────────┐  │
                    │  │  terraform.tfstate (local) │  │
                    │  │  gitignored, no locking     │  │
                    │  └───────────────────────────┘  │
                    └─────────────────────────────────┘
```

## Threat Register

| ID | Category | Threat | Risk | Mitigation | Control |
|----|----------|--------|------|------------|---------|
| T-01 | Tampering | Unauthorized code pushed to main | High | Branch protection + signed commits + enforce_admins | `github_branch_protection` |
| T-02 | Spoofing | Compromised developer account | High | GPG signed commits + 2FA required | `require_signed_commits` |
| T-03 | Info Disclosure | Secrets committed to git | Critical | Secret scanning + push protection | `security_and_analysis` |
| T-04 | Info Disclosure | Terraform state contains sensitive data | High | State file gitignored; OS-level file permissions on control plane host; no remote backend yet | `.gitignore` `*.tfstate` + host access controls |
| T-05 | Elevation | Attacker gains admin on org | Critical | Minimal admin team + break-glass only | Team permissions + audit log |
| T-06 | Tampering | Terraform state manipulation | High | **ACCEPTED RISK** — no locking or versioning until remote backend provisioned; manual backup before apply | Local state only; mitigate via HCP Terraform migration (planned) |
| T-07 | DoS | GitHub API rate limiting during apply | Medium | Concurrency control + retry logic | `concurrency` in workflow |
| T-08 | Info Disclosure | Public repos expose infrastructure details | Medium | Owner-accepted risk; no secrets in git | `.gitignore` + secret scanning |
| T-09 | Repudiation | Changes made without audit trail | High | All changes via PR + signed commits | Branch protection |
| T-10 | Tampering | Rogue Terraform destroy | Critical | `prevent_destroy = true` lifecycle | `github_repository` lifecycle |
| T-11 | Elevation | Unauthorized team membership changes | High | Org-level 2FA + audit log monitoring | GitHub org settings |
| T-12 | Info Disclosure | Supply chain attack via dependencies | High | Dependency review + Dependabot | `dependency_scan` gate |

## Risk Acceptance Register

| ID | Risk | Decision | Date | Review By |
|----|------|----------|------|-----------|
| RA-01 | All repos public (including governance) | Accepted by owner | 2026-09-24 | 2026-12-24 |
| RA-02 | GitHub Free (no Advanced Security) | Current constraint | 2026-09-24 | 2027-01-01 |
| RA-03 | Local Terraform state (no remote backend, no locking) | Accepted until HCP Terraform migration | 2026-09-26 | 2027-03-26 |
