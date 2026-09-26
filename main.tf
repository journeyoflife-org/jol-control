# ──────────────────────────────────────────────────────────────────────────────
# Terraform — GitHub Provider & Backend Configuration
# ──────────────────────────────────────────────────────────────────────────────
# JOL Control Plane — manages ALL journeyoflife-org repositories
# Compliance: SOC 2 Type II · GDPR · ISO 27001:2022 · PCI-DSS 4.0
# ──────────────────────────────────────────────────────────────────────────────

terraform {
  required_version = ">= 1.9.0"

  required_providers {
    github = {
      source  = "integrations/github"
      version = "~> 6.0"
    }
  }

  # State stored locally (terraform.tfstate). For remote state with Proxmox,
  # consider Terraform Cloud, Consul, or HTTP backend — see docs/architecture.md.
}

# ── GitHub Provider ──────────────────────────────────────────────────────────
# Authentication via GITHUB_TOKEN environment variable (set in CI/CD)
# The token requires: admin:org, repo, write:org, admin:repo_hook
provider "github" {
  owner = var.github_org
  # token is read from GITHUB_TOKEN env var — NEVER hardcode
}

