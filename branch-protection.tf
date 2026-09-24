# ──────────────────────────────────────────────────────────────────────────────
# Branch Protection — enforced on main branch for ALL repositories
# ──────────────────────────────────────────────────────────────────────────────
# Implements SOC2 CC6.1/CC6.2, ISO 27001 A.6.6/A.7.1, PCI-DSS 6.3
# ──────────────────────────────────────────────────────────────────────────────

locals {
  # Governance repos require 2 reviewers + CODEOWNERS enforcement
  governance_repos = {
    for name, def in local.repo_defs : name => def
    if lookup(def, "tier", "") == "governance"
  }

  # All other repos require 1 reviewer
  standard_repos = {
    for name, def in local.repo_defs : name => def
    if lookup(def, "tier", "") != "governance"
  }
}

# ── Governance tier: 2 reviewers + CODEOWNERS ────────────────────────────────
resource "github_branch_protection" "governance" {
  for_each = local.governance_repos

  repository_id = github_repository.repo[each.key].node_id
  pattern       = "main"

  # Status checks
  required_status_checks {
    strict = true
    contexts = lookup(
      lookup(lookup(each.value, "branch_protection", {}), "main", {}),
      "required_status_checks", {}
    )["contexts"]
  }

  # Pull-request reviews
  required_pull_request_reviews {
    required_approving_review_count = var.required_approving_review_count
    dismiss_stale_reviews           = true
    require_code_owner_reviews      = true
    require_last_push_approval      = true
  }

  # Enforcement
  enforce_admins          = true
  require_signed_commits  = var.enforce_signed_commits
  required_linear_history = true
  allows_force_pushes     = false
  allows_deletions        = false


  lifecycle {
    prevent_destroy = true
  }
}

# ── Standard tier: 1 reviewer ────────────────────────────────────────────────
resource "github_branch_protection" "standard" {
  for_each = local.standard_repos

  repository_id = github_repository.repo[each.key].node_id
  pattern       = "main"

  # Status checks
  required_status_checks {
    strict = true
    contexts = lookup(
      lookup(lookup(each.value, "branch_protection", {}), "main", {}),
      "required_status_checks", {}
    )["contexts"]
  }

  # Pull-request reviews
  required_pull_request_reviews {
    required_approving_review_count = 1
    dismiss_stale_reviews           = true
    require_code_owner_reviews      = false
    require_last_push_approval      = true
  }

  # Enforcement
  enforce_admins          = true
  require_signed_commits  = var.enforce_signed_commits
  required_linear_history = true
  allows_force_pushes     = false
  allows_deletions        = false


  lifecycle {
    prevent_destroy = true
  }
}

# NOTE: Release-tag protection (v* tags) is enforced via GitHub Rulesets, which
# the integrations/github provider v6.x models as github_repository_ruleset.
# Ruleset definitions are intentionally kept out of this baseline until the
# org ruleset strategy is finalized (see docs/runbooks.md RB-04).
