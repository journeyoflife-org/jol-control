# Runbooks — JOL Control Plane Operations

## RB-01: Add a New Repository

### Preconditions
- Request approved by platform-admins
- Repository name follows `jol-*` naming convention

### Steps
1. Create `repos/<repo-name>.yml` with all required fields
2. Run `python3 scripts/validate_repos.py` — must pass
3. Open PR — terraform plan will post the proposed changes
4. Review plan output (new `github_repository` + `github_branch_protection` resources)
5. Merge after required approvals — *target baseline; not enforced while
   `solo_mode = true`, see `docs/change-management.md`*
6. Verify: `terraform apply` creates the repo with correct settings (run on the
   control-plane host — it holds the only copy of `terraform.tfstate`)

### Verification
```bash
gh repo view journeyoflife-org/<repo-name> --json url,visibility
python3 scripts/drift_detect.py
```

## RB-02: Change Repository Visibility

### Preconditions
- Risk assessment completed (especially public → private)
- Approval from platform-admins + security team

### Steps
1. Update `visibility` field in `repos/<repo-name>.yml`
2. OR add repo name to `sensitive_repos` in `terraform.tfvars`
3. Open PR — review plan carefully (visibility change is a significant operation)
4. Merge after 2 approvals (governance tier) — *target baseline; not enforced
   while `solo_mode = true`*
5. Verify: `gh repo view journeyoflife-org/<repo-name> --json visibility`

### Warning
- **Public → Private**: May break external integrations, webhooks, badges
- **Private → Public**: Ensure no secrets in git history (`git log --all -S "password"`)

## RB-03: Respond to Secret Exposure

### Preconditions
- Secret detected via GitHub alert or manual discovery

### Steps
1. **Immediately rotate** the exposed credential
2. Remove from git history:
   ```bash
   pip install git-filter-repo
   git filter-repo --replace-text expressions.txt
   ```
3. Force-push cleaned history (requires temporary branch protection override)
4. File incident in `jol-incident-response`
5. Update rotation log in `jol-secrets`
6. Review `policy/compliance-gates.yml` secret_scan remediation steps

## RB-04: Update Compliance Gate

### Steps
1. Edit `policy/compliance-gates.yml` — modify gate definition
2. Update `enforcement_matrix` if tier assignments change
3. Update corresponding branch protection contexts in `repos/*.yml`
4. Open PR — run `python3 scripts/validate_repos.py`
5. Review and merge

## RB-05: Quarterly Compliance Review

### Steps
1. Run `python3 scripts/compliance_check.py --output quarterly-report.json`
2. Review each audit checklist:
   - `audit/soc2-checklist.yml`
   - `audit/gdpr-checklist.yml`
   - `audit/iso27001-checklist.yml`
3. Update `metadata.next_review` dates in policy files
4. Review all active exceptions in `compliance-gates.yml`
5. Document findings in `jol-compliance-evidence`
