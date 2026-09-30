# ──────────────────────────────────────────────────────────────────────────────
# Repository Resources — generated from repos/*.yml allow-list
# ──────────────────────────────────────────────────────────────────────────────
# Each repository is defined here with settings derived from its YAML definition.
# Changes to repo settings MUST go through repos/*.yml → terraform plan → apply.
# ──────────────────────────────────────────────────────────────────────────────

locals {
  # Load all repo definitions from YAML files
  repo_files = fileset(path.module, "${var.repo_definitions_dir}/*.yml")
  repo_defs = {
    for f in local.repo_files :
    trimsuffix(basename(f), ".yml") => yamldecode(file("${path.module}/${f}"))
  }
}

# ── Repository creation & configuration ──────────────────────────────────────
resource "github_repository" "repo" {
  for_each = local.repo_defs

  name        = each.value.name
  description = each.value.description
  visibility  = contains(var.sensitive_repos, each.value.name) ? "private" : each.value.visibility

  # Feature flags
  has_issues      = lookup(each.value.settings, "has_issues", true)
  has_wiki        = lookup(each.value.settings, "has_wiki", false)
  has_projects    = lookup(each.value.settings, "has_projects", false)
  has_discussions = false

  # Merge strategy
  allow_merge_commit = lookup(each.value.settings, "allow_merge_commit", false)
  allow_squash_merge = lookup(each.value.settings, "allow_squash_merge", true)
  allow_rebase_merge = lookup(each.value.settings, "allow_rebase_merge", true)

  # Lifecycle
  delete_branch_on_merge = lookup(each.value.settings, "delete_branch_on_merge", true)
  archived               = lookup(each.value.settings, "archived", false)
  auto_init              = lookup(each.value.settings, "auto_init", false)
  is_template            = lookup(each.value.settings, "is_template", false)

  # Security
  security_and_analysis {
    dynamic "secret_scanning" {
      for_each = var.enable_secret_scanning ? [1] : []
      content {
        status = "enabled"
      }
    }
    dynamic "secret_scanning_push_protection" {
      for_each = var.enable_secret_scanning ? [1] : []
      content {
        status = "enabled"
      }
    }
  }

  # Topics
  topics = lookup(each.value, "topics", [])

  # NOTE: provider v6.x manages license/gitignore via repo content (LICENSE /
  # .gitignore files), not repository arguments. Repos are created empty; their
  # .gitignore and LICENSE are provisioned per-repo outside this control plane.

  lifecycle {
    prevent_destroy = true # never accidentally delete a repo
    ignore_changes  = [auto_init, template] # template is computed from API for repos created from templates
  }
}

# ── Vulnerability alerts (separate resource — inline arg deprecated) ─────────
resource "github_repository_vulnerability_alerts" "repo" {
  for_each = local.repo_defs

  repository = github_repository.repo[each.key].name
  enabled    = lookup(each.value.settings, "vulnerability_alerts", true)
}
