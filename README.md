# jol-control

> Central governance control plane for the `journeyoflife-org` GitHub organization.

[![Compliance: SOC2/GDPR/ISO27001](https://img.shields.io/badge/compliance-SOC2%20%7C%20GDPR%20%7C%20ISO27001-blue)](#)
[![Terraform](https://img.shields.io/badge/IaC-Terraform-7B42BC)](#)

## Purpose

`jol-control` manages **all 40 repositories** in the Journey of Life GitHub
organization through:

- **Declarative allow-list** — one YAML file per repository (`repos/*.yml`)
- **Policy baselines** — enforced settings for every repo (`policy/`)
- **Terraform IaC** — GitHub resources provisioned via `terraform apply`
- **Compliance gates** — automated security checks on every PR
- **Audit checklists** — SOC 2, GDPR, ISO 27001 control mappings

## Compliance

| Framework | Scope |
|-----------|-------|
| SOC 2 Type II | All repositories |
| GDPR (EU 2016/679) | All repositories — 27 EU member states |
| ISO 27001:2022 | All repositories — Annex A controls |
| PCI-DSS 4.0 | Payment-related repositories |

## Repository Structure

```
jol-control/
├── repos/                          # One YAML per repo = the allow-list
│   ├── jol-control.yml
│   ├── jol-policies.yml
│   ├── jol-hub.yml
│   └── ... (40 files)
├── policy/                         # Enforced baselines for EVERY repo
│   ├── repo-defaults.yml           # License, wiki, signoff, branch protection
│   └── compliance-gates.yml        # Security gates per tier
├── main.tf                         # GitHub Terraform provider + backend
├── variables.tf                    # Input variables
├── repositories.tf                 # Repository resources (from YAML)
├── branch-protection.tf            # Branch protection rules
├── org-settings.tf                 # Organization-level settings
├── outputs.tf                      # Terraform outputs
├── terraform.tfvars                # Variable values (no secrets)
├── .github/workflows/
│   ├── plan.yml                    # terraform plan as PR comment
│   ├── apply.yml                   # apply on merge: dev → staging → prod
│   └── compliance-scan.yml         # weekly compliance scanning
├── audit/                          # Compliance checklists
│   ├── soc2-checklist.yml
│   ├── gdpr-checklist.yml
│   └── iso27001-checklist.yml
├── scripts/                        # Validation & monitoring
│   ├── validate_repos.py           # YAML allow-list validator
│   ├── compliance_check.py         # Compliance posture checker
│   └── drift_detect.py             # GitHub vs allow-list drift detector
└── docs/                           # Architecture & runbooks
    ├── architecture.md
    ├── runbooks.md
    ├── threat-model.md
    ├── data-classification.md
    └── change-management.md
```

## Quick Start

### Prerequisites
- Python 3.12+
- Terraform >= 1.9.0
- GitHub CLI (`gh`)
- `GITHUB_TOKEN` with `admin:org`, `repo`, `write:org` scopes

### Validate Repository Definitions
```bash
pip install pyyaml
python3 scripts/validate_repos.py
```

### Plan Changes
```bash
terraform init
terraform plan -out=tfplan
```

### Apply Changes (CI/CD only)
Changes are applied automatically via GitHub Actions on merge to `main`:
- **dev** → **staging** → **production** (with manual approval gate)

## Tier Model

| Tier | Repos | Reviewers | Gates |
|------|-------|-----------|-------|
| governance | 12 | 2 + CODEOWNERS | All |
| platform | 12 | 1 | Standard + container scan |
| devops | 5 | 1 | Standard + IaC + container |
| site | 10 | 1 | Standard |
| template | 1 | 1 | Basic |

## Managed Repositories

40 repositories across 5 tiers:
- **Governance**: jol-control, jol-compliance, jol-policies, jol-docs, jol-iac, jol-dr, jol-privacy, jol-incident-response, jol-payments-scope, jol-status, jol-compliance-evidence, jol-secrets
- **Platform**: jol-hub, jol-core, jol-auth, jol-ecommerce-engine, jol-analytics-ai, jol-llm, jol-rag-server, jol-mcp-servers, jol-hermes-agents, jol-bitrix24-integration, jol-link-registry, jol-domain-taxonomy
- **DevOps**: jol-infrastructure, jol-devops, jol-deploy, jol-security, jol-scripts
- **Sites**: jol-site-cathedral, jol-site-diocese, jol-site-parish, jol-site-basilica, jol-site-deanery, jol-site-orthodox, jol-site-protestant, jol-site-other-church, jol-site-funeral, jol-site-cemetery-care
- **Template**: jol-repo-template

## License

MIT
