# ──────────────────────────────────────────────────────────────────────────────
# JOL Control Plane — Makefile
# ──────────────────────────────────────────────────────────────────────────────

.PHONY: help validate plan plan-gate state-gate apply fmt fmt-check lint drift compliance test backup-state retire-key clean init list-repos count-repos

.DEFAULT_GOAL := help

# ── Help ─────────────────────────────────────────────────────────────────────
help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-20s\033[0m %s\n", $$1, $$2}'

# ── Validation ───────────────────────────────────────────────────────────────
validate: ## Validate all repo YAML definitions
	python3 scripts/validate_repos.py

compliance: ## Run full compliance check
	python3 scripts/compliance_check.py

test: ## Run gate self-tests (plan + state + drift + agents-table + backup + retire gates, no pytest required)
	python3 tests/test_plan_gate.py
	bash tests/test_state_gate.sh
	python3 tests/test_drift_gate.py
	python3 tests/test_agents_gate.py
	bash tests/test_backup_gate.sh
	bash tests/test_retire_gate.sh

# RB-08. Exists because the runbook told an operator to run `backup.sh`, a file that was never
# created: prose in a fenced block is not an artefact. The script is scripts/backup_state.sh and
# its test is tests/test_backup_gate.sh; this target only supplies the arguments.
backup-state: ## Back up terraform.tfstate off-device per runbooks.md RB-08 (needs DEST= and a recovery recipient)
	@test -n "$(DEST)" || { \
		echo "usage: make backup-state DEST=/media/<other-disk>/jol-state-backup RECOVERY_PUB=age1..."; \
		echo "   or, to also prove the second custody path while both identities are on this host:"; \
		echo "       make backup-state DEST=... RECOVERY_KEY=~/.config/age/<recovery-identity-file>"; \
		echo "DEST must be on a DIFFERENT block device than terraform.tfstate (see RB-08's device table)."; \
		exit 1; }
	DEST='$(DEST)' RECOVERY_PUB='$(RECOVERY_PUB)' RECOVERY_KEY='$(RECOVERY_KEY)' bash scripts/backup_state.sh

# Proof before destruction. A recovery identity was shredded on 2026-10-27 with no off-host copy
# because the runbook said "verify first" in prose and the shred was a standalone command line.
# This target makes the proof a precondition: run it once with no PROOF to get the challenge, decrypt
# that challenge on the machine holding the other copy, then re-run with PROOF=<the nonce>.
retire-key: ## Retire an age recovery identity ONLY after proving an off-host copy can open it
	@test -n "$(KEY)" || { echo "usage: make retire-key KEY=~/.config/age/<identity-file>"; \
		echo "       then: make retire-key KEY=... CHALLENGE_DIR=/path/off/the/identity/dir"; \
		echo "       then decrypt the challenge on the OTHER machine and pass PROOF=<nonce>"; exit 1; }
	@test -z "$(PROOF)" || { echo "retiring $(KEY) with proof"; \
		RETIRE_PROOF='$(PROOF)' bash scripts/retire_recovery_key.sh '$(KEY)' \
			--challenge-dir '$(or $(CHALLENGE_DIR),.)' --retire; }
	@test -n "$(PROOF)" || bash scripts/retire_recovery_key.sh '$(KEY)' \
		--challenge-dir '$(or $(CHALLENGE_DIR),.)'

agents-gate: ## STOP gate — is AGENTS.md section 2 still a well-formed table with evidence per row
	python3 scripts/validate_agents_table.py AGENTS.md

# ── Terraform ────────────────────────────────────────────────────────────────
init: ## Initialize Terraform
	terraform init -input=false

fmt: ## Format Terraform files (MUTATES the working tree — never a verification step)
	terraform fmt -recursive

fmt-check: ## STOP gate — verify Terraform formatting WITHOUT modifying anything
	terraform fmt -check -recursive

# `lint` must not write. It used to depend on `fmt`, which rewrites files in place, so
# running the documented verification command silently edited repositories.tf inside a
# lifecycle block holding prevent_destroy = true — an area AGENTS.md §4 gates behind
# explicit human approval. Verification has to be side-effect free. See docs/drift-findings.md S2-008.
lint: fmt-check validate ## Run all linting (non-mutating: terraform fmt -check + YAML validation)

plan: validate ## Run terraform plan
	terraform plan -input=false -out=tfplan

state-gate: ## STOP gate — halt when local state cannot account for this config
	python3 scripts/state_gate.py .

plan-gate: state-gate ## STOP gate — halt if the plan destroys or replaces anything
	terraform show -json tfplan > tfplan.json
	python3 scripts/plan_gate.py tfplan.json

apply: plan-gate ## Apply the saved plan (blocked when either gate halts)
	@echo "WARNING: terraform.tfstate has no OFF-HOST copy."
	@echo "         Encrypted ON-HOST backups do exist (/opt/jol/backup/tfstate/*.age) but they"
	@echo "         are manual, and share this device — a disk failure loses both. Restore and"
	@echo "         verify them with docs/runbooks.md RB-08 before applying anything."
	@echo "         CI cannot apply — it has no access to this state."
	@echo "         state-gate: the state file accounts for what this config declares."
	@echo "         plan-gate: the plan contains no destroy/replace actions."
	@read -p "Continue? [y/N] " confirm && [ "$$confirm" = "y" ] || exit 1
	terraform apply -input=false tfplan

# ── Drift Detection ──────────────────────────────────────────────────────────
drift: ## Detect drift between definitions and GitHub
	python3 scripts/drift_detect.py

# ── Utilities ────────────────────────────────────────────────────────────────
list-repos: ## List all managed repositories
	@ls -1 repos/*.yml | sed 's|repos/||;s|\.yml||' | sort

count-repos: ## Count managed repositories
	@echo "Managed repositories: $$(ls -1 repos/*.yml | wc -l)"

clean: ## Remove generated files
	rm -f tfplan tfplan.json plan-output.txt compliance-report.json compliance-snapshot.json
