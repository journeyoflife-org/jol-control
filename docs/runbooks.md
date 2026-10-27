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
                                    #     the token could not see the whole org. CI binds
                                    #     secrets.ORG_READ_TOKEN in both places that run this
                                    #     script (compliance-scan.yml's drift job and apply.yml's
                                    #     post-apply step; RB-07, S1-002 in docs/drift-findings.md);
                                    #     a run on this host is the independent second measurement
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
5. Record the rotation in `jol-secrets`' rotation log — **which does not exist yet**. That
   repository is empty (`size=0`, no commits, and `pushed_at` sits one second after `created_at` at
   2026-09-24T14:39:53/54Z, verified 2026-10-19; it is one of the seven governance-tier empties in
   S1-009), so there is no branch, no file and no history to update. Until it is populated, the
   rotation record goes into the affected credential's own inventory table (RB-07 for
   `ORG_READ_TOKEN`) and, if the exposure was real, into the findings register — and
   `jol-incident-response` in step 4 is empty too, so an incident filed "there" means creating the
   repository's first commit, not appending to a log
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

## RB-07: Mint or Rotate `ORG_READ_TOKEN` (the CI drift-detection credential)

`secrets.ORG_READ_TOKEN` is the only credential CI is allowed to hold for organization reads
(`main.tf:22-28`): the scheduled Compliance Scan's drift job needs it to enumerate **private**
repositories, because `secrets.GITHUB_TOKEN` sees public ones only. Without it the job reports
UNEVALUATED (exit 2) and the allow-list control is unproven in CI — see S1-002. It is read-only
by policy and must never be used for `terraform apply`; the apply path runs host-side.

### Required settings (each row is a condition; the consequence column says what its absence costs)

| Field | Value | Consequence if wrong |
|---|---|---|
| Type | Fine-grained PAT, **read-only** | A classic `repo` token does reach the same endpoints but is org-wide **write-capable**, and `main.tf:22-28` forbids any org-write credential in CI. Using one is an S1 finding plus an explicit risk acceptance (AGENTS.md §4/§6) — not a deviation note |
| Resource owner | **journeyoflife-org** | owner = personal account → org private repos 404 |
| Repository access | **All repositories** | "Public repositories" or a selection without `jol-dr` → exit 2 forever |
| Repository permissions | Metadata **Read-only** (automatic, cannot be cleared) + Contents **Read-only** | Metadata alone satisfies both calls the checker makes (`GET /orgs/{org}/repos` and `GET /repos/{owner}/{repo}`); Contents is granted here as headroom and **has not been measured as unnecessary** — do not strip it on the strength of that claim. Anything *write* is over-privilege |
| Organization permissions | Members **Read-only** | without it the org enumeration can omit private rows |
| Expiration | 90 days | no expiry is an audit finding |
| Name | `jol-control-drift-read-<YYYY-MM-DD>` | rotation provenance: an unnamed token cannot be retired safely |

Prefilled form: `https://github.com/settings/personal-access-tokens/new?name=jol-control-drift-read&description=Read-only+org+repo+enumeration+for+jol-control+drift+gate+(S1-002)&target_name=journeyoflife-org&expires_in=90&metadata=read&contents=read&members=read`

Mint it while signed in as an account that satisfies the organization's secure-2FA requirement
(`gh api user --jq '{login,two_factor_authentication}'` → `JourneyOfLife`, `true`). The owner of
the organization is auto-approved, so no access request has to be cleared.

### Steps
1. Mint per the table. Never paste the value into a chat, an agent session, a file, or a
   `--body`: a credential recorded in a transcript is a credential that must be rotated.
2. **Verify before storing**, assigning the token per command so it never enters the interactive
   environment:
   ```bash
   read -rs T
   GH_TOKEN="$T" gh api user --jq '"identity: \(.login)"'
   GH_TOKEN="$T" gh repo list journeyoflife-org --limit 500 --json name,visibility \
     --jq '"rows="+(length|tostring)+" private="+([.[]|select(.visibility=="PRIVATE")]|length|tostring)'
   GH_TOKEN="$T" python3 scripts/drift_detect.py; echo "rc=$?"   # want rows=41 private=1, rc=0
   unset T
   ```
   Do **not** `export GH_TOKEN` in a shell you still intend to use: `gh` prefers the variable
   over the keyring, so an empty or mistyped value makes every later call answer `401 Bad
   credentials` and reads as a broken token. `401` = the credential value; `403 Resource not
   accessible by personal access token` = the scope.
3. Store it as a **repository** secret (an org secret with `visibility: private` is invisible to
   this public repository). Set the new value before deleting the old token:
   ```bash
   gh secret set ORG_READ_TOKEN --repo journeyoflife-org/jol-control   # hidden prompt
   gh secret list --repo journeyoflife-org/jol-control
   ```
4. Prove it in CI — a name read-back proves placement, not function. The binding must already be
   published on `main`, because `workflow_dispatch` runs the workflow file **as it exists on the
   default branch**, never your working tree:
   ```bash
   gh api repos/journeyoflife-org/jol-control/contents/.github/workflows/compliance-scan.yml \
     --jq .content | base64 -d | grep -n 'secrets.ORG_READ_TOKEN'   # the env: line, not just prose
   gh workflow run compliance-scan.yml --repo journeyoflife-org/jol-control
   R=$(gh run list --repo journeyoflife-org/jol-control --workflow compliance-scan.yml \
        --event workflow_dispatch --limit 1 --json databaseId --jq '.[0].databaseId')
   gh run view "$R" --repo journeyoflife-org/jol-control --log \
     | grep -aE '"evaluated"|"github_count"|NO DRIFT|UNEVALUATED'
   ```
   Accepting evidence is `"evaluated": true` with `"github_count": 40` (39 means the enumeration
   could not see private repositories). Baseline: run 39255407378 at `1a66742`, 2026-10-19.
   The `--event workflow_dispatch` filter matters: `compliance-scan.yml` also triggers on
   `pull_request`, where the drift job is gated off entirely, so an unfiltered `--limit 1` can
   capture a run that never printed an `"evaluated"` line at all and read as a missing verdict.

   **Guard any scheduled-run check against a stale capture.** `gh run list --event schedule
   --limit 1` returns the newest *scheduled* run, and until 2026-10-24 that is a pre-binding
   failure whose log reads `"github_count": 39` — indistinguishable in shape from a credential
   that just broke. Assert the date before interpreting it:
   ```bash
   read -r R RD <<< "$(gh run list --repo journeyoflife-org/jol-control \
     --workflow compliance-scan.yml --event schedule --limit 1 --json databaseId,createdAt \
     --jq '.[0] | "\(.databaseId)\t\(.createdAt)"')"
   if [[ "$RD" < "2026-10-24" ]]; then
     echo "No scheduled run since the binding yet (latest: $RD  run $R) — nothing to judge"
   else
     gh run view "$R" --repo journeyoflife-org/jol-control --log \
       | grep -aE '"evaluated"|"github_count"|NO DRIFT|UNEVALUATED'
   fi
   ```
   Written exactly as tested on 2026-10-19, when it correctly answered `No scheduled run since the
   binding yet (latest: 2026-10-17T06:47:01Z run 39011182828)`. The `--jq` form matters: `jq`
   cannot add a **number** to a string, so `'.[0].databaseId + " " + .[0].createdAt'` is an error,
   and because it fails inside `$( )` both variables come back **empty** — the guard then prints
   "latest:  run " and still exits 0, which reads as a verdict rather than as the broken command it
   is. Interpolating into one tab-separated string is what makes it work.
   Note that expiry needs no separate detector: the exit-2 annotation already names "missing,
   expired, or lacks private-repository read" as its own cause, so a lapsed token turns the weekly
   job red by design. What is **not** automated is advance warning — the deadline above is a
   documented date, not a gate, and becomes a red job only after the credential is already dead.
5. Record the mint in the inventory below, and cite the run id in the findings register.

### Inventory
`GET /orgs/journeyoflife-org/personal-access-tokens` answers `404` from this host because GitHub
documents it as **"Only GitHub Apps can use this endpoint"** — and the acting credential here is an
OAuth token holding `admin:org` (`gh auth status` → scopes `admin:org, gist, read:user, repo,
user:email, workflow`), which proves the `404` is about the **caller type**, not about a missing
scope. Do not chase it by granting more permissions.

> Recorded because it was got wrong here once: an empty result from a pipeline is not a measurement.
> `gh api -i user | grep -i x-oauth-scopes` printed nothing in this session and was read as "the
> token has no scopes". It was a swallowed pipe. Check the thing directly (`gh auth status`) before
> reasoning from an absence.

So the authoritative read of name, granted permissions, repository selection and `expires_at` is
the Settings UI: `https://github.com/settings/tokens?type=beta` (list, with expiry and last-used)
and the token's detail page (full permission set). Transcribe those into this table by hand at
mint time; an empty cell means the record is unverified, not that the token is wrong. The
behavioural proof (RB-07 step 2's private-repository count) is what actually validates the scope.

| Name | Minted | Expires | Granted permissions (read from the UI) | Verified in CI |
|---|---|---|---|---|
| `jol-control-drift-read` | 2026-10-19 | **2027-01-17** (exactly 90 days) | Resource owner `journeyoflife-org`; repository access "all repositories owned by the organization"; Repository permissions **"Read access to code and metadata"** (Contents + Metadata read-only); Organization permission **"Read access to members"** (Members read-only) | run 39255407378 |

**Rotate before 2027-01-17.** That expiry falls on a Sunday and the scan runs on Saturdays, so
Sat **2027-01-16** is the last scheduled run that can pass and Sat **2027-01-23** is the first that
will report UNEVALUATED — a missed rotation is therefore discovered up to a week after it happens,
and GitHub delivered this `cron: 0 2 * * 6` between 06:47 and 08:17 UTC in every measured week, so
don't reason about the deadline as if 02:00 were precise. Rotate in December.

> **Do not press "Update" while inspecting the token.** The detail page opens in edit form, and
> the adjacent controls are `Update`, `Regenerate token` and `Delete`. `Regenerate token` mints a
> **new value** while the stored secret keeps the old one, and the drift job then authenticates with
> a revoked credential — see the failure modes below: that is the `401` shape, **not** the
> `github_count: 39` shape. Cancel out of the form; if a regeneration ever does happen, re-run step 3
> before anything else.

### Failure modes — two shapes, and they are not interchangeable

`||` substitutes only when the first operand is **falsy**, i.e. an empty string. A stored but dead
token is not empty, so it never falls back. Measured 2026-10-19 with a deliberately invalid value:
`GH_TOKEN="github_pat_BOGUS…" python3 scripts/drift_detect.py` → `UNEVALUATED: gh repo list failed
(exit 1): HTTP 401: Bad credentials`, `rc=2`, and **no `github_count` line in the output at all**.

| Situation | Expression resolves to | Log signature | Exit |
|---|---|---|---|
| Secret **unset or deleted** | `secrets.GITHUB_TOKEN` | `"evaluated": false`, `"reason": "cannot enumerate private repos"`, `"github_count": 39` | 2 |
| Token **expired, revoked, or regenerated** (stale value stored) | the dead PAT | `gh repo list failed … HTTP 401: Bad credentials`, no `github_count` | 2 |
| Token valid but **under-scoped** | the PAT | `403 Resource not accessible by personal access token`, or `github_count: 39` if only the org permission is missing | 2 |
| Real drift | either | `DRIFT: <name> is declared in repos/ but does not exist…` | 1 |

Both token-failure shapes end in UNEVALUATED, so the **safety** property holds either way — the
job cannot go green on a broken credential. What differs is the diagnosis: grep for
`github_count` and you will find it in the first case and never in the second.

Both remain honest reds, and neither can produce a green verdict — that property is what
`tests/test_drift_gate.py` fixture `ci_github_actions_token.json` pins.

Every attribute of this credential is now read from the token's own detail page rather than
inferred from the mint URL. That page is the only source GitHub offers — the API equivalent is
GitHub-App-only — so re-read it after **any** permission edit, and treat step 4's private-repository
count as the backstop that catches a grant narrowed or widened without a corresponding change to
this table.

### Rollback / degradation
Deleting the secret is safe and honest: the step falls back to `secrets.GITHUB_TOKEN`, the
enumeration loses `jol-dr`, and the job returns exit 2 with the `github_count: 39` signature above.
Letting the token **expire** is equally honest but looks different — `401 Bad credentials` and no
`github_count` — so read the failure-mode table before concluding the binding broke. There is no
path by which losing this credential produces a green drift verdict.

---

## RB-08: Restore `terraform.tfstate` from the encrypted backup set

**Written 2026-10-27 after this procedure was executed and verified.** An agent destroyed the live
state file during a test (see `docs/drift-findings.md` S2-012); the restore below is the path that
recovered it byte-exactly. It is recorded because the backup set existed, worked, and was named in
no runbook — recovery depended on searching the filesystem for it.

**Prerequisites:** `age` on PATH; the X25519 identity `~/.config/age/state-backup-key.txt`
(inventory row **AGE-1** in `docs/SECRETS_INVENTORY.md`); a *checksum of the state you expect*,
not just a backup you hope is right.

1. **Stop.** Do not run `terraform init`, `plan`, `apply` or `refresh` in the directory. With no
   state file, `apply` would recreate everything — which is why `state-gate` and `plan-gate` exist,
   and why they will refuse. A refused apply is the control working; do not route around it.
2. **Preserve every surviving copy before touching anything**, so a second mistake cannot be
   unrecoverable. Make them read-only and checksum them:
   ```bash
   D=/opt/jol/evidence/$(date +%F)-state-incident; mkdir -p "$D"
   cd /opt/jol/repos/jol-control
   cp -p terraform.tfstate* "$D/" 2>/dev/null; chmod a-w "$D"/*
   ( cd "$D" && sha256sum * > CHECKSUMS.sha256 )
   ```
3. **Enumerate the candidates.** There is no automation behind these — they are manual snapshots:
   ```bash
   ls -la /opt/jol/backup/tfstate/jol-control-terraform.tfstate.*.age
   ```
4. **Decrypt to a scratch file and compare metadata — never print state contents.** State carries
   the full inventory of every governed repository; it must not reach a log, a terminal scrollback
   or a pasted message.
   ```bash
   W=$(mktemp -d); chmod 700 "$W"
   for f in /opt/jol/backup/tfstate/jol-control-terraform.tfstate.*.age; do
     age -d -i ~/.config/age/state-backup-key.txt "$f" > "$W/out.json" 2>/dev/null || continue
     echo "$(basename "$f")  bytes=$(stat -c%s "$W/out.json")  md5=$(md5sum "$W/out.json" | cut -d' ' -f1)"
     jq -r '"  serial=\(.serial) lineage=\(.lineage) instances=\([.resources[].instances[]]|length)"' "$W/out.json"
     jq -r '.resources[] | "    \(.type).\(.name) = \([.instances[]]|length)"' "$W/out.json"
   done
   ```
   **Accept a candidate only on an exact match** of `serial`, `lineage`, instance count and, if you
   have one, the recorded md5. Today all three jol-control snapshots resolve to serial **306**,
   lineage `25425c0f-…`, **119** instances (`github_repository.repo` 40,
   `github_repository_vulnerability_alerts.repo` 40, `github_branch_protection.governance` 11,
   `.standard` 28), so a stale restore is not a silent risk here — but re-derive the numbers rather
   than trusting this sentence, because they move with every apply.
5. **Restore with tight permissions and verify byte-exactly:**
   ```bash
   cd /opt/jol/repos/jol-control
   ( umask 077; age -d -i ~/.config/age/state-backup-key.txt <CHOSEN.age> > terraform.tfstate )
   md5sum terraform.tfstate            # must equal the value from step 4
   stat -c '%A %U:%G %s' terraform.tfstate   # expect -rw------- jol:jol
   ```
6. **Confirm Terraform itself agrees, then let the gate judge it:**
   ```bash
   terraform state list | wc -l   # expect 119 — matches the instance count independently
   make state-gate                # expect: SAFE — state accounts for managed resources, exit 0
   terraform validate             # expect: Success!
   rm -rf "$W"                    # destroy the plaintext scratch copy
   ```
7. **Record it** in `docs/drift-findings.md` and `CHANGELOG.md`: what was lost, which snapshot was
   used, the checksum that proves fidelity, and who caused it.

**Expected output:** step 4 prints the same `serial`/`instances` for every snapshot; step 5's md5
equals step 4's; step 6 prints `119`, then `SAFE`, then `Success!`, all exit 0.

**What a failure means:** `age: Error … failed to read next cipher block` → wrong or corrupted
identity file; `MAC failed to decrypt` → the snapshot was not encrypted to this key. A `serial`
**lower** than expected → you picked a stale snapshot; restoring it would silently revert inventory,
which is the exact hazard `state_gate.py`'s NOTICE describes. If no candidate matches, **stop and
escalate** — do not restore a near-match, and do not re-create state by applying.

**Rollback:** the copies from step 2 are the rollback. Nothing in this procedure writes outside
`terraform.tfstate`, which is gitignored and therefore invisible to `git`.

**Residual risk this runbook cannot fix:** the backups are **manual** (newest 2026-10-20 as of
writing, i.e. 7 days stale) and live on the **same physical device** as the live state
(`/dev/nvme0n1p6` vs `/dev/nvme0n1p8`, one NVMe). No cron and no systemd timer refreshes them, and
no off-host copy exists. A single disk failure loses the inventory and its backups together, and
`make drift` cannot rebuild it. Tracked as S2-012.
