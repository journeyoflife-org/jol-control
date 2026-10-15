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
| T-13 | Availability | Published security/DPO contacts are undeliverable — every `@journeyoflife.org` and `@journeyoflife.lt` address in the fleet points at a null-MX or non-resolving domain, so vulnerability reports and data-subject requests bounce silently | High | Interim: GitHub private vulnerability reporting as first channel plus reachable role aliases; permanent: MX on journeyoflife.eu | `policy/contact-channels.yml`, S1-003 |
| T-14 | Fraud / Reputation | The advertised donation path (`SUPPORT.md`, `.github/FUNDING.yml`, issue-form sidebar) is `https://journeyoflife.org/donate` on a **parked** domain whose response is a 114-byte redirect to `/lander`: donors are sent to a registrar parking page serving third-party ads and links under the organization's own name, and no real donation endpoint exists anywhere in the estate | High | Owner must supply a verified endpoint or remove the link; all three files change together so the funding button, support table and sidebar cannot disagree, and the target is re-fetched to confirm it is not a redirect | S1-004 |

## Risk Acceptance Register

| ID | Risk | Decision | Date | Review By |
|----|------|----------|------|-----------|
| RA-01 | All repos public (including governance) | Accepted by owner | 2026-09-24 | 2026-12-24 |
| RA-02 | GitHub Free (no Advanced Security) | Current constraint | 2026-09-24 | 2027-01-01 |
| RA-03 | Local Terraform state (no remote backend, no locking) | Accepted until HCP Terraform migration | 2026-09-26 | 2027-03-26 |
| RA-04 | Role contacts published as plus-addressed aliases of one personal mailbox — the base address is recoverable from any alias, and the base address is also the GitHub account login email, so a public alias is a phishing lure aimed at org ownership | Accepted because the only alternative today is an undeliverable contact (see T-13, S1-003); the base address is already public via `gh api user/emails` (`visibility=public`) and is the author of every commit in the fleet, so the marginal disclosure is small. Withdraw when MX exists on journeyoflife.eu | 2026-10-15 | 2027-01-15 |
| RA-05 | The base mailbox is **permanently published** in 1,151 of the 1,341 commit objects across the estate, on 40 public repositories, as the account's public profile field, and as the UID of the signing key itself | Accepted as irrevocable. Withdrawal needs a history rewrite, which signed commits + linear history + blocked force-push forbid by design — the controls this plane exists to protect. The forward-only alternative (author as the ID-prefixed noreply address) withdraws nothing and is refused by `required_signatures` anyway (GH006, measured), so it is **declined, not deferred**. See S2-005 Resolution | 2026-10-15 | 2027-01-15 |
