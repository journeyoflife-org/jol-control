# Runbooks — JOL Control Plane Operations

## RB-01: Add a New Repository

### Preconditions
- Request approved by platform-admins
- Repository name follows `jol-*` naming convention

### Steps
1. Create `repos/<repo-name>.yml` with all required fields
2. Run `python3 scripts/validate_repos.py` — must pass
3. Open PR — terraform plan will post the proposed changes
4. Review plan output (new `github_repository` + `github_branch_protection` resources)
5. Merge after required approvals — *target baseline; not enforced while
   `solo_mode = true`, see `docs/change-management.md`*
6. Verify: `terraform apply` creates the repo with correct settings (run on the
   control-plane host — it holds the only copy of `terraform.tfstate`)

### Verification
```bash
gh repo view journeyoflife-org/<repo-name> --json url,visibility
python3 scripts/drift_detect.py     # 0 = evaluated, no drift
                                    # 1 = drift, the named repos are the evidence
                                    # 2 = UNEVALUATED — not a pass and not a failure:
                                    #     the token could not see the whole org. Run it
                                    #     here, not in CI (see S1-002 in
                                    #     docs/drift-findings.md)
```

A new repository must be declared in `repos/*.yml` **and** exist in the organization;
`drift_detect.py` reports a declared repo that answers no `gh api` lookup as drift, and
refuses to conclude anything when its own enumeration is partial.

## RB-02: Change Repository Visibility

### Preconditions
- Risk assessment completed (especially public → private)
- Approval from platform-admins + security team

### Steps
1. Update `visibility` field in `repos/<repo-name>.yml`
2. OR add repo name to `sensitive_repos` in `terraform.tfvars`
3. Open PR — review plan carefully (visibility change is a significant operation)
4. Merge after 2 approvals (governance tier) — *target baseline; not enforced
   while `solo_mode = true`*
5. Verify: `gh repo view journeyoflife-org/<repo-name> --json visibility`

### Warning
- **Public → Private**: May break external integrations, webhooks, badges
- **Private → Public**: Ensure no secrets in git history (`git log --all -S "password"`)

## RB-03: Respond to Secret Exposure

### Preconditions
- Secret detected via GitHub alert or manual discovery

### Steps
1. **Immediately rotate** the exposed credential
2. Remove from git history:
   ```bash
   pip install git-filter-repo
   git filter-repo --replace-text expressions.txt
   ```
3. Force-push cleaned history (requires temporary branch protection override)
4. File incident in `jol-incident-response`
5. Update rotation log in `jol-secrets`
6. Review `policy/compliance-gates.yml` secret_scan remediation steps

## RB-04: Update Compliance Gate

### Steps
1. Edit `policy/compliance-gates.yml` — modify gate definition
2. Update `enforcement_matrix` if tier assignments change
3. Update corresponding branch protection contexts in `repos/*.yml`
4. Open PR — run `python3 scripts/validate_repos.py`
5. Review and merge

## RB-05: Quarterly Compliance Review

### Steps
1. Run `python3 scripts/compliance_check.py --output quarterly-report.json`
2. Review each audit checklist:
   - `audit/soc2-checklist.yml`
   - `audit/gdpr-checklist.yml`
   - `audit/iso27001-checklist.yml`
3. Update `metadata.next_review` dates in policy files
4. Review all active exceptions in `compliance-gates.yml`
5. Document findings in `jol-compliance-evidence`

## RB-06: Inspect or Change a Repository Ruleset

Rulesets and classic branch protection are **separate APIs and blind to each other**.
`GET /repos/{owner}/{repo}/branches/{branch}/protection` returns `404 Branch not protected`
for a branch guarded only by a ruleset — which reads as "unprotected" and is not. Never
conclude that a repository is unprotected from one endpoint; check both.

### Preconditions
- The target is not `journeyoflife-org/.github`'s ruleset being treated as governed: rulesets
  are deliberately outside the Terraform baseline (see `branch-protection.tf` note above the
  `github_branch_protection` resources), so any change here is out of band and invisible to
  `make drift` and to `terraform plan`. Bringing one under management is an infrastructure
  change and needs an ADR in `jol-docs` first.

### Steps
1. List what actually guards the branch:
   ```bash
   gh api repos/journeyoflife-org/<repo>/rulesets \
     --jq '.[] | .name + "  id=" + (.id|tostring) + "  enforcement=" + .enforcement + "  rules=" + ([.rules[].type]|join(","))'
   gh api repos/journeyoflife-org/<repo>/branches/main/protection   # 404 here means ruleset, not absent
   ```
2. Snapshot before editing — a ruleset `PUT` is a **full replace**, so anything omitted from
   the body is deleted, and `required_status_checks` live inside the `update` rule's
   parameters rather than as their own rule type:
   ```bash
   gh api repos/journeyoflife-org/.github/rulesets/22978013 > /tmp/rs-before.json
   ```
3. Mutate the snapshot in one place only, keeping every other field identical, and confirm
   the diff before sending it:
   ```bash
   python3 - <<'PY'
   import json
   d = json.load(open("/tmp/rs-before.json"))
   for r in d["rules"]:
       if r.get("type") == "pull_request":
           r["parameters"]["require_code_owner_review"] = False   # the single change
   json.dump({k: d[k] for k in
              ("name", "target", "enforcement", "conditions", "rules", "bypass_actors")
              if k in d}, open("/tmp/rs-body.json", "w"), indent=1)
   PY
   diff <(jq -S . /tmp/rs-before.json) <(jq -S . /tmp/rs-body.json)   # expect one line
   ```
4. Apply, then **read back through a cache-buster**. GitHub caches reads for up to 60
   seconds, so a verification issued immediately can return the pre-change value and make a
   change that landed look discarded:
   ```bash
   gh api -X PUT repos/journeyoflife-org/.github/rulesets/22978013 --input /tmp/rs-body.json --jq .updated_at
   gh api "repos/journeyoflife-org/.github/rulesets/22978013?cb=$(date +%s%N)" \
     --jq '"types=" + ([.rules[].type]|join(",")), (.rules[] | select(.type=="pull_request") | .parameters)'
   ```
   The `types=` line must still list every rule that was there before; a silently shortened
   list means the replace dropped one.
5. Record what changed, with the before-snapshot, in the findings register.

### Known state as measured 2026-10-16
`journeyoflife-org/.github` → ruleset `protect-main`, id **22978013**:
`deletion`, `non_fast_forward`, `required_linear_history`, `required_signatures`,
`pull_request` (`required_approving_review_count: 0`, `require_code_owner_review: false`,
`required_review_thread_resolution: true`, `require_extra_approval_for_unattributed_changes:
true`, `allowed_merge_methods: [squash]`), `update`; `bypass_actors: RepositoryRole admin,
bypass_mode always`. Organization-level rulesets cannot be listed on this plan
(`GET /orgs/journeyoflife-org/rulesets` → `403 Upgrade to GitHub Team`), so an org-wide
ruleset cannot be ruled out from this host.

### Open problem — do not improvise a cause
Pull requests to that repository report `mergeable=true, mergeable_state=blocked` and need
`--admin`, with every visible requirement already satisfied. Eight hypotheses were eliminated
and none was the cause; see **S1-007** in `docs/drift-findings.md`. Changing another parameter
in the hope that it is the culprit is how S1-005 acquired a wrong diagnosis in writing: undo
anything toggled for testing, and get the requirement from the merge box in the web UI or from
GitHub Support.

### Rollback
`gh api -X PUT repos/journeyoflife-org/.github/rulesets/22978013 --input /tmp/rs-before.json`
— the snapshot from step 2 must be the payload with only the identity fields (`id`, `node_id`,
`created_at`, `updated_at`, `_links`, `current_user_can_bypass`) removed.
