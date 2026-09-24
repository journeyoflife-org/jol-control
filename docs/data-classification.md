# Data Classification Policy

## Classification Levels

| Level | Description | Examples | Git Allowed |
|-------|-------------|---------|-------------|
| **Public** | Information approved for public disclosure | Documentation, open-source code, status pages | Yes |
| **Internal** | Information for internal use only | Internal tools, non-sensitive configs | Yes (public repos OK) |
| **Confidential** | Sensitive business information | API designs, architecture docs, audit reports | Yes (prefer private repos) |
| **Restricted** | Highly sensitive — legal/regulatory constraints | PII, payment data, credentials, legal docs | No — vault only |

## Repository Classification Assignments

| Tier | Default Classification | Rationale |
|------|----------------------|-----------|
| governance | confidential | Contains control definitions, policy baselines, audit evidence |
| platform | internal | Application code and configurations |
| devops | internal | Infrastructure configs and deployment scripts |
| site | internal | Frontend application code |
| template | public | Boilerplate template — by design |

## Handling Rules

### For Git Repositories
- **Public / Internal**: May be stored in public repositories
- **Confidential**: Prefer private repositories; if public, ensure no sensitive data in code
- **Restricted**: NEVER store in git — use vault (HashiCorp Vault, AWS Secrets Manager, GitHub Secrets)

### Required .gitignore Patterns
All repositories MUST include these patterns in their `.gitignore`:
```
*.pem
*.key
*.p12
secrets.json
credentials.json
.env
.env.*
terraform.tfstate
terraform.tfstate.*
.terraform/
```

## Review Cadence
- Classification assignments reviewed quarterly
- Any new repository must be classified before first commit
- Reclassification requires platform-admins approval
