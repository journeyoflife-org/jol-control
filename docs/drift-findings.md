# Drift Findings Register

This register tracks drift between Terraform state, configuration, and live GitHub state.

**Priority:** S0 (Stop-Work) > S1 (Fix Before Apply) > S2 (Fix Soon)

---

## S0 — Stop-Work / Critical

*None currently.*

---

## S1 — Fix Before Apply / BLOCKING

### S1-001: Private repos cannot have branch protection without GitHub Pro

**Discovered:** 2026-09-30  
**Status:** FIXED  
**Finding:** `jol-dr` is private, but config declared `tier: governance` which requires branch protection. GitHub API returns 403 for branch protection on private repos without GitHub Pro.  
**Impact:** Apply would fail with 403 when trying to create branch protection for jol-dr.  
**Resolution:** Modified `branch-protection.tf` to exclude private repos from `governance_repos` and `standard_repos` locals.  
**Files changed:** `branch-protection.tf`

---

## S2 — Fix Soon / Important

### S2-001: Required status check contexts don't match reality

**Discovered:** 2026-09-30  
**Status:** FIXED  
**Finding:** 28 repos declared `ci / test`, 23 declared `codeql-analysis`, 12 declared `dependency-review` as required contexts. But CodeQL is not running on most repos, and many repos have no CI workflows.  
**Impact:** When `solo_mode` is disabled and required status checks are enforced, merges will block because the required checks never report.  
**Current mitigation:** `solo_mode = true` drops `required_status_checks` entirely, so contexts are inert.  
**Resolution:** Cleared contexts to `[]` for all repos except jol-control (which has correct contexts matching compliance-scan.yml job names). When CI is added to a repo, update its contexts to match the actual check-run names.  
**Files affected:** `repos/*.yml` (39 files updated)

### S2-002: Teams referenced in config do not exist

**Discovered:** 2026-09-30 (audit)  
**Status:** FIXED  
**Finding:** `repos/*.yml` referenced teams `platform-admins`, `developers`, `auditors` which do not exist. Existing teams: `backend`, `data`, `devops`, `frontend`, `security`.  
**Impact:** Team-based access control is not enforced. Compliance claims about team restrictions are false.  
**Resolution:** Updated team references in `repos/*.yml` to reference existing teams: `platform-admins` → `security`, `developers` → `devops`, `auditors` → `backend`. Updated `docs/architecture.md` Team Access section to match. Note: team-repository bindings are not enforced via Terraform; team assignments in YAML are decorative until bindings are provisioned.  
**Files affected:** `repos/*.yml` (40 files updated), `docs/architecture.md`

### S2-003: State is local, not remote

**Discovered:** 2026-09-30  
**Status:** OPEN (RA-03 accepted)  
**Finding:** Terraform state is local to control-plane host (`terraform.tfstate`), gitignored. No state locking or versioning.  
**Impact:** CI cannot apply (empty state → mass create). No collaboration possible.  
**Current mitigation:** Apply jobs gated behind `vars.TF_REMOTE_STATE_ENABLED == 'true'` (unset).  
**Resolution path:** Migrate to HCP Terraform remote state (planned).  
**Files affected:** `main.tf` (no backend block), `docs/architecture.md`

---

## Resolved

### RESOLVED: jol-dr visibility drift

**Discovered:** 2026-09-30  
**Resolved:** 2026-09-30  
**Finding:** State recorded `jol-dr` as `public`, live GitHub showed `PRIVATE`.  
**Resolution:** Ran `terraform apply -refresh-only` to reconcile state with live. State now correctly shows `visibility = "private"`.

### RESOLVED: jol-auth stale template block

**Discovered:** 2026-09-30  
**Resolved:** 2026-09-30  
**Finding:** `jol-auth` had stale `template {}` block in state (repo was created from template). Terraform wanted to remove it, but API kept returning it.  
**Resolution:** Added `template` to `ignore_changes` in `repositories.tf` lifecycle block.

### RESOLVED: Phantom branch protection in state

**Discovered:** 2026-09-30  
**Resolved:** 2026-09-30  
**Finding:** State had `github_branch_protection.governance["jol-dr"]` but live API showed it doesn't exist (403 on private repo).  
**Resolution:** `terraform apply -refresh-only` removed phantom resource from state. Config updated to exclude private repos from branch protection.

---

## Methodology

Drift detection uses three signals:
1. `terraform plan -refresh-only` — compares state vs live
2. `scripts/drift_detect.py` — compares config vs live (requires `GITHUB_TOKEN`)
3. Manual verification — `gh api` queries for specific resources

**Last full scan:** 2026-09-30
