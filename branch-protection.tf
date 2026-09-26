# ──────────────────────────────────────────────────────────────────────────────
# Branch Protection — enforced on main branch for ALL repositories
# ──────────────────────────────────────────────────────────────────────────────
# Implements SOC2 CC6.1/CC6.2, ISO 27001 A.6.6/A.7.1, PCI-DSS 6.3
#
# SOLO MODE (var.solo_mode): the organisation currently has a single owner and
# no teams, so multi-reviewer and code-owner gates cannot be satisfied and would
# lock the owner out of their own repositories. When solo_mode = true we drop the
# review/status-check gates but KEEP the integrity controls that still add value
# for one person: signed commits, linear history, and no force-push/deletion.
# CI workflows still run on push (they are simply not blocking merge gates).
# Set solo_mode = false once the first engineers are hired to restore the full
# governance baseline (2 reviewers + CODEOWNERS + required status checks).
# ──────────────────────────────────────────────────────────────────────────────

locals {
  # Governance repos require 2 reviewers + CODEOWNERS enforcement (non-solo)
  governance_repos = {
    for name, def in local.repo_defs : name => def
    if lookup(def, "tier", "") == "governance"
  }

  # All other repos require 1 reviewer (non-solo)
  standard_repos = {
    for name, def in local.repo_defs : name => def
    if lookup(def, "tier", "") != "governance"
  }
}

# ── Governance tier: 2 reviewers + CODEOWNERS (0 in solo mode) ───────────────
resource "github_branch_protection" "governance" {
  for_each = local.governance_repos

  repository_id = github_repository.repo[each.key].node_id
  pattern       = "main"

  # Status checks — disabled in solo mode (they would block direct pushes)
  dynamic "required_status_checks" {
    for_each = var.solo_mode ? [] : [1]
    content {
      strict = true
      contexts = lookup(
        lookup(lookup(each.value, "branch_protection", {}), "main", {}),
        "required_status_checks", {}
      )["contexts"]
    }
  }

  # Pull-request reviews — omitted entirely in solo mode. A PR requirement with
  # 0 approvals still blocks direct pushes, so the block must be absent for the
  # owner to push to main. CI workflows still run on push (non-blocking).
  dynamic "required_pull_request_reviews" {
    for_each = var.solo_mode ? [] : [1]
    content {
      required_approving_review_count = var.required_approving_review_count
      dismiss_stale_reviews           = true
      require_code_owner_reviews      = true
      require_last_push_approval      = true
    }
  }

  # Enforcement — integrity controls kept even in solo mode
  enforce_admins          = true
  require_signed_commits  = var.enforce_signed_commits
  required_linear_history = true
  allows_force_pushes     = false
  allows_deletions        = false

  lifecycle {
    prevent_destroy = true
  }
}

# ── Standard tier: 1 reviewer (0 in solo mode) ───────────────────────────────
resource "github_branch_protection" "standard" {
  for_each = local.standard_repos

  repository_id = github_repository.repo[each.key].node_id
  pattern       = "main"

  # Status checks — disabled in solo mode
  dynamic "required_status_checks" {
    for_each = var.solo_mode ? [] : [1]
    content {
      strict = true
      contexts = lookup(
        lookup(lookup(each.value, "branch_protection", {}), "main", {}),
        "required_status_checks", {}
      )["contexts"]
    }
  }

  # Pull-request reviews — omitted entirely in solo mode (see governance note).
  dynamic "required_pull_request_reviews" {
    for_each = var.solo_mode ? [] : [1]
    content {
      required_approving_review_count = 1
      dismiss_stale_reviews           = true
      require_code_owner_reviews      = false
      require_last_push_approval      = true
    }
  }

  # Enforcement — integrity controls kept even in solo mode
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
