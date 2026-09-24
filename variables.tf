# ──────────────────────────────────────────────────────────────────────────────
# Variables — JOL Control Plane
# ──────────────────────────────────────────────────────────────────────────────

variable "github_org" {
  description = "GitHub organization name"
  type        = string
  default     = "journeyoflife-org"
}

variable "environment" {
  description = "Deployment environment (dev, staging, prod)"
  type        = string
  default     = "prod"

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be one of: dev, staging, prod."
  }
}

variable "default_license" {
  description = "Default SPDX license identifier for new repositories"
  type        = string
  default     = "mit"
}

variable "required_approving_review_count" {
  description = "Minimum number of approving reviews for governance repos"
  type        = number
  default     = 2

  validation {
    condition     = var.required_approving_review_count >= 1 && var.required_approving_review_count <= 6
    error_message = "Review count must be between 1 and 6."
  }
}

variable "enforce_signed_commits" {
  description = "Require GPG/SSH signed commits on all repositories"
  type        = bool
  default     = true
}

variable "enable_secret_scanning" {
  description = "Enable GitHub secret scanning on all repositories"
  type        = bool
  default     = true
}

variable "enable_dependabot" {
  description = "Enable Dependabot security alerts on all repositories"
  type        = bool
  default     = true
}

variable "compliance_frameworks" {
  description = "Active compliance frameworks for the organization"
  type        = list(string)
  default     = ["soc2", "gdpr", "iso27001"]
}

variable "denied_licenses" {
  description = "SPDX license identifiers that are NOT permitted in any repository"
  type        = list(string)
  default     = ["GPL-2.0", "GPL-3.0", "AGPL-3.0", "SSPL-1.0"]
}

variable "repo_definitions_dir" {
  description = "Path to directory containing per-repo YAML definitions"
  type        = string
  default     = "repos"
}

variable "sensitive_repos" {
  description = "Repos that should be private (visibility override)"
  type        = list(string)
  default     = []
  # NOTE: Per owner decision, all repos are currently public.
  # Add repo names here to override visibility to private.
}

variable "audit_webhook_url" {
  description = "URL for audit-log streaming webhook (set via TF_VAR_audit_webhook_url)"
  type        = string
  default     = ""
  sensitive   = true
}

variable "audit_webhook_secret" {
  description = "Shared secret for audit-log webhook HMAC verification (set via TF_VAR_audit_webhook_secret)"
  type        = string
  default     = ""
  sensitive   = true
}
