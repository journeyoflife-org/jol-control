# ──────────────────────────────────────────────────────────────────────────────
# Terraform variable values — JOL Control Plane
# ──────────────────────────────────────────────────────────────────────────────
# NOTE: Do NOT put secrets here. Use environment variables or a vault.
# ──────────────────────────────────────────────────────────────────────────────

github_org                      = "journeyoflife-org"
environment                     = "prod"
default_license                 = "mit"
required_approving_review_count = 2
enforce_signed_commits          = true
enable_secret_scanning          = true
enable_dependabot               = true
repo_definitions_dir            = "repos"

compliance_frameworks = ["soc2", "gdpr", "iso27001", "pci-dss"]

denied_licenses = [
  "GPL-2.0",
  "GPL-3.0",
  "AGPL-3.0",
  "SSPL-1.0",
  "EUPL-1.2",
]

# Per owner decision: all repos are currently public.
# To make specific repos private, add their names here:
sensitive_repos = []

# Audit webhook URL/secret are NOT stored here (secrets must never live in git).
# Provide them at runtime via environment variables:
#   export TF_VAR_audit_webhook_url="https://..."
#   export TF_VAR_audit_webhook_secret="..."
# Their declarations live in variables.tf.
