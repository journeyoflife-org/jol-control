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
**Status:** OPEN  
**Finding:** 28 repos declare `ci / test`, 23 declare `codeql-analysis`, 12 declare `dependency-review` as required contexts. But CodeQL is not running on most repos, and many repos have no CI workflows.  
**Impact:** When `solo_mode` is disabled and required status checks are enforced, merges will block because the required checks never report.  
**Current mitigation:** `solo_mode = true` drops `required_status_checks` entirely, so contexts are inert.  
**Resolution path:** Either implement the CI workflows in each repo, or update contexts to match what each repo actually emits.  
**Files affected:** `repos/*.yml` (28 files with incorrect contexts)

### S2-002: Teams referenced in config do not exist

**Discovered:** 2026-09-30 (audit)  
**Status:** OPEN  
**Finding:** `repos/*.yml` reference teams `platform-admins`, `developers`, `auditors` which do not exist. Existing teams: `backend`, `data`, `devops`, `frontend`, `security`.  
**Impact:** Team-based access control is not enforced. Compliance claims about team restrictions are false.  
**Resolution path:** Either create the referenced teams, or update `repos/*.yml` to reference existing teams.  
**Files affected:** `repos/*.yml` (team assignments)

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
