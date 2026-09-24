# ──────────────────────────────────────────────────────────────────────────────
# Outputs — JOL Control Plane
# ──────────────────────────────────────────────────────────────────────────────

output "repository_names" {
  description = "List of all managed repository names"
  value       = [for r in github_repository.repo : r.name]
}

output "repository_urls" {
  description = "Map of repository names to their HTTPS clone URLs"
  value       = { for name, r in github_repository.repo : name => r.html_url }
}

output "governance_repos" {
  description = "List of governance-tier repositories"
  value       = keys(local.governance_repos)
}

output "branch_protection_governance" {
  description = "Governance repos with strict branch protection (2 reviewers)"
  value       = { for name, bp in github_branch_protection.governance : name => bp.pattern }
}

output "branch_protection_standard" {
  description = "Standard repos with branch protection (1 reviewer)"
  value       = { for name, bp in github_branch_protection.standard : name => bp.pattern }
}

output "total_managed_repos" {
  description = "Total number of repositories managed by jol-control"
  value       = length(github_repository.repo)
}

output "compliance_summary" {
  description = "Compliance posture summary"
  value = {
    frameworks       = var.compliance_frameworks
    signed_commits   = var.enforce_signed_commits
    secret_scanning  = var.enable_secret_scanning
    dependabot       = var.enable_dependabot
    total_repos      = length(github_repository.repo)
    governance_repos = length(local.governance_repos)
    standard_repos   = length(local.standard_repos)
    environment      = var.environment
  }
}
