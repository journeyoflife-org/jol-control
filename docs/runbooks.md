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

## RB-08: Back up and restore `terraform.tfstate`

**Written 2026-10-27 after this procedure was executed and verified.** An agent destroyed the live
state file during a test (see `docs/drift-findings.md` S2-012); the restore below is the path that
recovered it byte-exactly. It is recorded because the backup set existed, worked, and was named in
no runbook — recovery depended on searching the filesystem for it.

### What this protects against, and what it does not

Measured on this host, 2026-10-27:

| Path | Device | Model / medium | Same physical disk as the state? |
|---|---|---|---|
| `/opt/jol/repos/jol-control/terraform.tfstate` | `nvme0n1p8` | NVMe SSD | — (this is the reference) |
| `/opt/jol/backup/tfstate/*.age` | `nvme0n1p6` | **the same NVMe** | **yes** — one die held the inventory and every copy of it |
| `/media/jol/32f7e56a-…/jol-state-backup` | `sdb1` | Seagate **ST9320423AS**, 298 G, SATA, **rotational** (`ROTA=1`) | **no — a different disk, same chassis** |

So `sdb1` closes the measured gap, and `backup_state.sh` now *verifies* it rather than trusting the
operator: it resolves the block device under both paths (`findmnt --target` → `lsblk -no PKNAME`) and
**refuses** when they are the same disk. That check is what the earlier revision wrongly listed as a
limitation it could not perform.

**Two facts about that disk an operator must know before relying on it:**

1. **It is mounted by the desktop session, not by the system.** `/etc/fstab` holds **no** entry for it
   (`grep -c media /etc/fstab` → 0); the systemd unit is generated from `/proc/self/mountinfo`, and the
   path itself is the filesystem UUID. After a headless boot, a crash recovery, or any start without a
   GUI login, **`/media/jol/32f7e56a-…` does not exist** — and the Restore half below would find no
   candidates and conclude the off-disk copies are gone. Preflight it, and see step 3 for the mount
   command. The durable fix is a stable boot mount (`/etc/fstab` by UUID, or a `.mount` unit) — a host
   configuration change, so it is an owner decision and is not performed by this runbook.
2. **It is a spinning 2012-era laptop drive sharing this machine's power supply and backplane.** It
   protects against NVMe failure. It does not protect against surge, fire, theft, or the loss of the
   host, and its SMART health is **unverified here** (`smartctl` needs a password). A backup on the
   oldest disk in the box is a real improvement and a weak end state.

### Creating a backup

**Prerequisites:** `age` 1.1.1, `jq` 1.7 (`/usr/bin/jq`) and `python3` with the repo's
`scripts/state_gate.py`; the on-host identity `~/.config/age/state-backup-key.txt` (row
**AGE-1** in `docs/SECRETS_INVENTORY.md`); a **second** identity held off-host; a destination on a
different block device.

1. **Preflight, because this destination is a session automount.** Confirm the disk is mounted and is
   genuinely a different device before treating a failure as something else — the script enforces the
   second point, but the first is what the operator sees first:
   ```bash
   D=/media/jol/32f7e56a-b96c-486a-93da-9e1a57567cfc/jol-state-backup
   ls -ld "$D" 2>&1 || udisksctl mount -b /dev/sdb1
   lsblk -no PKNAME "$(findmnt -no SOURCE --target "$D")"   # expect sdb, not nvme0n1
   ```
2. Mint the recovery identity **outside** any auto-cleaned directory. `/tmp` is on-disk here
   (`D /tmp 1777 root root 30d`), so it survives a reboot but is reaped after 30 days — never put
   long-lived key material in it.

   > **This step has side effects and is the only step here that creates a secret.** Replace
   > `YYYYMMDD` with the real date *before* running it: pasted verbatim, `age-keygen -o ~/.config/age/
   > state-recovery-YYYYMMDD.txt` generates a live private key under the literal placeholder name.
   > That happened on 2026-10-27 while testing this runbook; the key was unreferenced and was shredded.
   > `age-keygen` will not overwrite an existing identity, so an established key cannot be clobbered
   > this way.
   ```bash
   umask 077
   age-keygen -o ~/.config/age/state-recovery-YYYYMMDD.txt
   age-keygen -y ~/.config/age/state-recovery-YYYYMMDD.txt   # the recipient; copy it down
   ```
   Then **move the identity file off this machine.** The script below can prove the two recipient
   strings differ; it cannot prove one of the keys is physically elsewhere. That is a human step, and
   skipping it makes the whole exercise decorative.
3. Back up with **`scripts/backup_state.sh`**, which is the block below verbatim — the file is
   extracted from this fence, and case 19 of `tests/test_backup_gate.sh` fails if the two diverge. Run
   it directly, or through `make backup-state`:
   ```bash
   make backup-state DEST=/media/jol/32f7e56a-b96c-486a-93da-9e1a57567cfc/jol-state-backup \
                     RECOVERY_PUB=age18457pc8jfy8jrz7qhy36mzkxn7x4crvh79nmkqfdcyxnwn9urpyqgajvnj
   ```
   It is reproduced here because a runbook that only points at a file nobody can review is not
   evidence. Note the failure this document once caused: it told an operator to run `backup.sh`,
   **a file that had never been created**, and they got `RC=127`. Prose inside a fenced block is not
   an artefact.
   ```bash
   #!/usr/bin/env bash
   # RB-08 create-backup. Exit codes follow this repository's gate convention:
   #   0 = written AND both custody paths proven   1 = refused, nothing kept
   #   2 = written but a control could not be checked - NOT a pass
   set -euo pipefail
   umask 077        # verification writes PLAINTEXT state; this host's default umask is 0002

   REPO="${REPO:-/opt/jol/repos/jol-control}"
   SRC="${SRC:-$REPO/terraform.tfstate}"
   DEST="${DEST:?DEST is required - a directory on a different block device}"
   HOST_KEY="${HOST_KEY:-$HOME/.config/age/state-backup-key.txt}"
   RECOVERY_KEY="${RECOVERY_KEY:-}"; RECOVERY_PUB="${RECOVERY_PUB:-}"
   OUT=""; KEEP=0; CREATED=0; RC=0; TMP=()
   # ONE exit trap. `trap ... RETURN` inside a function does not fire when that function calls
   # `exit`, and does not fire when `set -e` aborts mid-function - both failure paths used to leak
   # a temp file holding decrypted state. It also drops the artefact unless the run fully succeeded,
   # so a rejected backup cannot sit on the backup disk looking like a snapshot - but ONLY a file
   # this run created. Without CREATED, a refused same-second re-run deleted the ORIGINAL backup.
   # shellcheck disable=SC2317  # invoked indirectly via `trap cleanup EXIT`; shellcheck cannot follow it
   cleanup(){ local p; for p in "${TMP[@]:-}"; do if [ -n "$p" ]; then rm -f "$p"; fi; done
              if [ "$KEEP" != 1 ] && [ "$CREATED" = 1 ]; then rm -f "${OUT:-}" "${OUT:-}.info"; fi; }
   trap cleanup EXIT

   [ -n "$RECOVERY_KEY" ] || [ -n "$RECOVERY_PUB" ] || {
     echo "FAIL: set RECOVERY_KEY (identity file - verifies the off-host path) or";
     echo "      RECOVERY_PUB (age1... - records it but cannot verify it)."; exit 1; }
   [ -s "$SRC" ] || { echo "FAIL: source missing or 0 bytes: $SRC"; exit 1; }
   # Validate shape AND content before writing. A document whose `resources` array is EMPTY is a
   # perfectly valid state - it is exactly what this host produced when the inventory was destroyed
   # (S2-012) - so `has("resources")` alone would certify a wiped state as a good backup.
   jq -e '(.terraform_version|type=="string") and (.lineage|type=="string")
          and (.serial|type=="number") and ((.resources|length) > 0)' "$SRC" >/dev/null 2>&1 || {
     echo "FAIL: $SRC is not a populated Terraform state document.";
     echo "      Needs terraform_version, lineage, a numeric serial and at least one resource."; exit 1; }
   if [ ! -d "$DEST" ] || [ ! -w "$DEST" ]; then
     echo "FAIL: DEST absent or not writable: $DEST"; exit 1; fi
   # Confirmed BEFORE any encryption: a run that cannot reach the inventory check must not write a
   # backup it then has to disown. Order matters - verifying after the fact still leaves the operator
   # holding a file whose status is unknown.
   if [ ! -f "$REPO/scripts/state_gate.py" ]; then
     echo "FAIL: $REPO/scripts/state_gate.py not found - the inventory check cannot run.";
     echo "      Do not report this backup as verified."; exit 2; fi
   DEST_ABS="$(cd "$DEST" && pwd -P)"
   case "$DEST_ABS" in
     "$REPO"|"$REPO"/*) echo "FAIL: DEST is inside the repository ($DEST_ABS). Ciphertext - and on a"
                        echo "      hard failure its plaintext sibling - must never land in a git tree."; exit 1;;
   esac

   # The whole point of this runbook is a copy on a DIFFERENT PHYSICAL DISK, and writability cannot
   # tell you that: two paths can sit on different filesystems of one device, which is exactly how
   # this host was configured (live state on nvme0n1p8, its old backups on nvme0n1p6 - one NVMe).
   # findmnt --target names the filesystem, lsblk -no PKNAME names the disk underneath it.
   disk_of(){ local s; s="$(findmnt -no SOURCE --target "$1" 2>/dev/null || true)"; [ -n "$s" ] || { echo ""; return; }
              lsblk -no PKNAME "$s" 2>/dev/null | head -1; }
   STATE_DISK="$(disk_of "$SRC")"; DEST_DISK="$(disk_of "$DEST_ABS")"
   DEVICE_CHECK="unevaluated: could not resolve the disk behind one of the two paths"
   if [ -n "$STATE_DISK" ] && [ -n "$DEST_DISK" ]; then
     if [ "$STATE_DISK" = "$DEST_DISK" ]; then
       echo "FAIL: DEST is on the SAME physical disk as the state ($STATE_DISK).";
       echo "      One device failure would take the inventory and this backup together, which is";
       echo "      the hazard RB-08 exists to remove. Point DEST at a different disk."; exit 1; fi
     DEVICE_CHECK="verified-different: state=$STATE_DISK backup=$DEST_DISK"
   else
     echo "WARN: the physical disks could not be resolved, so 'different device' is UNVERIFIED."
     echo "      The backup is still written; the sidecar records it as unevaluated. Do not claim"
     echo "      off-device protection on the strength of this run."
   fi

   HOST_PUB="$(age-keygen -y "$HOST_KEY")"
   if [ -n "$RECOVERY_KEY" ]; then RECOVERY_PUB="$(age-keygen -y "$RECOVERY_KEY")"; fi
   # Compares two recipient STRINGS. That detects "you passed the same key twice". It does not prove,
   # and cannot prove, where either key is held.
   [ "$HOST_PUB" != "$RECOVERY_PUB" ] || {
     echo "FAIL: the recovery recipient equals HOST_KEY ($HOST_PUB).";
     echo "      One custody path wearing two labels survives nothing the host does not."; exit 1; }

   EXPECT_MD5="$(md5sum "$SRC" | awk '{print $1}')"
   EMPTY_MD5="$(printf '' | md5sum | awk '{print $1}')"
   STAMP="$(date -u +%Y%m%dT%H%M%SZ)"
   # Deliberately the same basename convention as /opt/jol/backup/tfstate/, so the Restore half
   # below can actually find what this half writes.
   OUT="$DEST_ABS/jol-control-terraform.tfstate.$STAMP.age"
   # Reserve the name atomically: `age -o` overwrites an existing file without warning, and a
   # second-granularity stamp means two runs in one second collide.
   set -C
   if ! : > "$OUT" 2>/dev/null; then set +C
     echo "FAIL: $OUT already exists - refusing to overwrite an existing backup"; exit 1; fi
   set +C
   CREATED=1   # from here the trap may clean this path; before here the file is not ours to remove

   age --encrypt --recipient "$HOST_PUB" --recipient "$RECOVERY_PUB" --output "$OUT" "$SRC"
   chmod 600 "$OUT"
   echo "written   : $OUT ($(stat -c%s "$OUT") bytes)"
   echo "recipients: $HOST_PUB  $RECOVERY_PUB"

   verify() {  # label, identity-file
     local t m; t="$(mktemp)"; TMP+=("$t")
     age --decrypt -i "$2" "$OUT" > "$t"
     m="$(md5sum "$t" | awk '{print $1}')"
     if [ "$m" = "$EMPTY_MD5" ]; then echo "FAIL [$1]: decrypted to ZERO BYTES - nothing was read"; exit 1; fi
     if [ "$m" != "$EXPECT_MD5" ]; then echo "FAIL [$1]: md5 $m != source $EXPECT_MD5"; exit 1; fi
     echo "PASS [$1]: a distinct identity opens this file and reproduces the source md5 $m"
   }
   verify host-key "$HOST_KEY"
   if [ -n "$RECOVERY_KEY" ]; then
     verify recovery-key "$RECOVERY_KEY"
   else
     RC=2   # deliberately not 0: an unproven control must not report success
     echo "NOT VERIFIED [recovery-key]: only the recipient was supplied, so the off-host path is"
     echo "                 recorded in the header but not proven to open this file. Prove it by"
     echo "                 decrypting on the machine that holds the identity."
   fi

   DEC="$OUT.decoded"; TMP+=("$DEC")
   age --decrypt -i "$HOST_KEY" "$OUT" > "$DEC"
   # The config directory is PINNED, not inherited. `state_gate.py` takes `dir` positionally with
   # default `.`, so calling it with only --state judges the backup against whatever directory the
   # operator happens to be standing in - measured from /tmp it answered `SAFE` over ZERO resource
   # blocks. A vacuous pass, not an honest refusal.
   set +e; python3 "$REPO/scripts/state_gate.py" "$REPO" --state "$DEC" | sed 's/^/    /'
   G=${PIPESTATUS[0]}; set -e
   if [ "$G" -ne 0 ]; then echo "FAIL [state-gate]: exit $G - refusing to certify this backup"; exit 1; fi

   # Persist the facts the Restore half demands ("a checksum of the state you expect"). Without this
   # file those numbers exist only on a terminal scrollback.
   { echo "serial    : $(jq -r '.serial' "$SRC")"
     echo "lineage   : $(jq -r '.lineage' "$SRC")"
     echo "resources : $(jq '.resources|length' "$SRC")"
     echo "instances : $(jq '[.resources[].instances[]]|length' "$SRC")"
     echo "md5       : $EXPECT_MD5"
     echo "created   : $STAMP"
     echo "recipients: $HOST_PUB $RECOVERY_PUB"
     # Two fields, because two different claims are at stake and conflating them is how a control
     # gets overstated. "recovery-key-decrypted" is what this run proved. It does NOT say where the
     # key is kept - a second key held in ~/.config/age on this same host proves nothing about
     # surviving the loss of this host.
     echo "recovery-key-decrypted: $([ "$RC" = 0 ] && echo yes || echo no)"
     echo "recovery-key-location : NOT CHECKED (the script cannot know where any key is held)"
     echo "device-check          : $DEVICE_CHECK"
   } > "$OUT.info"; chmod 600 "$OUT.info"
   KEEP=1
   echo "OK: backup written and readable; recovery path status stated above (exit 2 = not verified)"
   exit "$RC"
   ```
   Or invoke it directly. **Use the real filename, not the placeholder** from step 2, and note that
   `VAR=value command` scopes the variable **to that command only** — a following
   `cat "$DEST"/*.info` finds `DEST` empty unless you `export` it first. That exact mistake produced
   `cat: '/*.info': No such file or directory` in a real session:
   ```bash
   DEST=/media/jol/32f7e56a-b96c-486a-93da-9e1a57567cfc/jol-state-backup
   export DEST
   RECOVERY_PUB="$(cat ~/.config/age/offdisk-recipient.txt)" scripts/backup_state.sh
   ls -l "$DEST"; cat "$DEST"/*.info
   ```
   Read the recipient from the file rather than transcribing it: the recipient first published in this
   runbook, `age18457pc8jfy8jrz7qhy36mzkxn7x4crvh79nmkqfdcyxnwn9urpyqgajvnj`, is the identity that was
   destroyed (AGE-2), and encrypting to it produces a snapshot with one live key by accident.
   Pass `RECOVERY_KEY=<identity file>` instead of `RECOVERY_PUB` when you hold both identities on the
   host - at creation time, and on any restore rehearsal - to get the full two-`PASS` verification
   and exit 0.
4. **Retiring an identity: proof before destruction.** Do not `shred` a recovery identity because a
   runbook told you to. On 2026-10-27 one was destroyed with no off-host copy: the instruction to
   "copy it, verify it there, then shred" was prose, the shred was a standalone command line, and it
   ran first. The private half existed nowhere else on the host — five other age identities and two
   session transcripts were each tested for the ability to open the backup and every one returned zero
   bytes — so the snapshot became single-custody. Prose that says *verify first* is advice, and advice
   is not a control.
   ```bash
   # CHALLENGE_DIR must be on the SECOND disk. /tmp is wrong: it shares the disk the identity lives on,
   # and a nonce recovered from that disk proves nothing about a second copy. The gate refuses both
   # cases - same disk, and device unresolvable - because this deletes something unrecoverable.
   make retire-key KEY="$HOME/.config/age/state-recovery-<date>.txt" \
                   CHALLENGE_DIR=/media/jol/32f7e56a-b96c-486a-93da-9e1a57567cfc/jol-state-backup
   ```
   Phase 1 writes a challenge encrypted to that recipient, prints the nonce, and stores the expected
   answer **only as a hash**, so no local file can hand you the answer; nothing is destroyed. It also
   prints the separation it relied on (`identity on nvme0n1, challenge on sdb`) — read that line, it is
   the whole basis of the proof. Then carry the challenge to wherever the other copy lives, decrypt it
   there, and substitute the **actual value** for `<that-nonce>` — pasting the angle-bracket placeholder
   literally produced `bash: syntax error near unexpected token 'newline'` in a real run:
   ```bash
   make retire-key KEY="$HOME/.config/age/state-recovery-<date>.txt" \
                   CHALLENGE_DIR=/media/jol/32f7e56a-b96c-486a-93da-9e1a57567cfc/jol-state-backup \
                   PROOF=<the nonce printed on the other machine>
   ```
   `tests/test_retire_gate.sh` holds 15 cases: the proof is required, refusals leave the identity in
   place, the nonce is not recoverable from anything on this host, a stale nonce cannot retire a new
   identity, and the two separation refusals below. Two mutations — a vacuous proof comparison, and
   removing the proof check — each make the suite fail.

   > **Do not run this ceremony to feel safe about a copy that is merely on another disk in the same
   > box.** See S2-014: with the only other copy sitting on `sdb` next to the ciphertext, retiring the
   > local half proves disk separation, buys no redundancy (`AGE-1` opens every snapshot anyway, two
   > recipients being 1-of-2), and worsens the theft posture. Run it after a copy is genuinely
   > off-machine, or not at all.

**A first version of that gate had a hole worth naming, because it is the same hole as S2-013.** It
proved *"a private key recovered the nonce"* while that private key was still sitting on this host and
no second copy existed — so the ceremony could complete, the local file be shredded, and the key be
destroyed outright. That is what nearly happened on 2026-10-27 in the literal sense: the `cp` of the
fresh identity to the second disk failed with `Permission denied` (that volume's root is `root:root
755`, only `jol-state-backup` is writable), leaving exactly one copy — and the retirement would have
"passed" anyway. The gate therefore refuses unless the challenge directory resolves to a **different
physical disk** than the identity, and refuses outright when that cannot be determined: for an
irreversible action an unverifiable separation is a no, not a warning. It prints the separation it used,
because a claim nobody can see is a claim nobody can check. Proving a copy exists *off the machine*
remains beyond it — only restoring from that copy elsewhere demonstrates it, which is RB-09 step 5.

**Expected output:** `written … (≈195 KB)` with mode 600, a `recipients:` line, `PASS [host-key]`, then
either `PASS [recovery-key]` or `NOT VERIFIED [recovery-key]`, then the pinned `state-gate` report
(`SAFE — state accounts for managed resources`), then an `OK:` line. **Exit code is the verdict:**
`0` both paths proven · `2` written but the off-host path unproven (or the gate unreachable) · `1`
refused, and no artefact left behind. A schedule that runs this must treat 2 as *not green*.

**Why both `verify` calls matter, and why the second one is allowed to be skipped but not to be
silent:** decrypting only with the host key proves the ciphertext is intact but says nothing about
whether the off-host path works, and the off-host path is the only one that matters when the host is
gone. Requiring the identity on the host would have made the script unusable for exactly the case it
exists for — once you follow step 1 and move the key off this machine, `RECOVERY_KEY` cannot resolve.
So the two modes are: **full verification** when you hold both identities (run this once, at creation,
and again on any restore rehearsal), and **recipient-recorded / NOT VERIFIED** for routine backups.
`NOT VERIFIED` is not a pass and must never be paraphrased as one.

**What a failure means:** `FAIL: the recovery recipient equals HOST_KEY` → you pointed both at one
key; the backup has a single custody path. `FAIL […]: decrypted to ZERO BYTES` → the decrypt produced
nothing and the checksum would otherwise have been md5-of-nothing. `DEST absent or not writable` → the
secondary disk is not mounted, or its directory is still `root:root` (`sudo chown jol:jol <DEST> &&
sudo chmod 700 <DEST>` — verify each effect, a pasted sudo block can run only its first line).
`refusing to overwrite an existing backup` → two runs landed in the same UTC second; wait or use a
different destination, because a silently replaced snapshot is not a backup history.
`DEST is inside the repository` → the artefact would sit in a git tree; pick a real backup device.
`not a populated Terraform state document` → `SRC` is the wrong file, **or it is a wiped state**
(`resources: []`), which the pre-write check rejects precisely because that shape is what this host
produced when its inventory was destroyed. Every `exit 1` path removes the artefact it created, so a
refusal leaves nothing on the backup disk. Note also why `age` must never be handed an empty filename:
it silently falls back to reading **stdin**, and a backgrounded reader is stopped by `SIGTTIN` instead
of failing.

**Limitations of this script, stated plainly.** It checks that the two recipient **strings** differ
and that each supplied identity reproduces the source md5. It does **not** and cannot verify:

- that the recovery identity is held **off this machine** — the documented invocation currently points
  at `~/.config/age/…`, so a `PASS [recovery-key]` proves a *second* key opens the file, not a *farther*
  one. Until that file leaves the host, S2-012's core risk is untouched;
- that `DEST` is a different **physical** device — it now does check this (`findmnt --target` then
  `lsblk -no PKNAME`, refusing when both resolve to one disk), but only when those tools can resolve
  the paths. When they cannot, the run **warns** and the sidecar records `device-check: unevaluated`;
  read the sidecar, do not infer off-device protection from a successful exit;
- **and this is the important one:** that the **private keys** are anywhere other than the state's own
  disk. `device-check` compares the live state to the ciphertext. It says nothing about the keys, and a
  backup whose every key sits on the device it is meant to survive is unreadable exactly when it is
  needed — which is the present state of this host (**S2-014**, both keys on `nvme0n1`, ciphertext on
  `sdb`). A copy that is genuinely off-machine is invisible to any check run here, so this gap can only
  be closed by a human carrying a key elsewhere, and proved by restoring from it (**step 5 of RB-09**).
  Do not read a green `device-check` as "the custody split exists".
- that the backup is **recent**, and nothing runs it on a schedule;
- **disk-full or partial-write** failures beyond what the decrypt catches: the ciphertext is read back
  by `verify`, so a truncated file fails, but a `SIGKILL` between reserving `$OUT` and finishing the
  write leaves a 0-byte `.age` that the EXIT trap never got to remove. Check for it if a run vanishes.
- Verification is **circular for a source that is already wrong in a valid-looking way**. The md5
  round-trip proves the backup equals the source, never that the source is the inventory you meant to
  keep. That is why the `.info` sidecar records `serial`/`lineage`/`instances` and why the Restore half
  requires a checksum of the state you **expect**, not merely a backup that opens.

**Tested 2026-10-27 — first as an ad-hoc 17-case matrix, then as a committed 19-case suite.** The
matrix is what found the earlier defects; it was run by extracting the block **by content** (`RB-08
create-backup`), 1 match from the bash fences here — an earlier attempt extracted *the first* fence
after the heading, which is the key-minting snippet, so "every assertion passed" while testing three
unrelated lines and the negative case exited 0. Each run is pinned to one filename by a stub `date`
on `PATH`, and asserts on **four** things: exit code, the verdict line, the number of files left in
the destination, and whether any plaintext survived. That matrix is now superseded by
`tests/test_backup_gate.sh`; the result table below describes it.

| Result | Cases |
|---|---|
| `RC=0`, 2 artefacts (`.age` + `.info`, both mode 600) | distinct `RECOVERY_KEY` |
| `RC=2`, 2 artefacts, `NOT VERIFIED` | distinct `RECOVERY_PUB` — off-host path unproven |
| `RC=2`, **0** artefacts | `REPO` has no `state_gate.py` — refuses to certify, cleans up |
| `RC=1`, **0** artefacts | recovery identity/recipient equals the host's (both modes); neither supplied; absent destination; `DEST` inside the repository; `SRC` a `Makefile`; `SRC` a **wiped state** (`resources: []`); `SRC` a valid-JSON plan fixture; `SRC` 0 bytes |
| `RC=1`, original **preserved byte-identical**, file count unchanged | refused same-second re-run |

Then: the `.info` sidecar was read back and carries `serial 306`, `lineage 25425c0f-…`, `resources 4`,
`instances 119`, the source md5 and the custody/device fields; a `RECOVERY_PUB`-only ciphertext was
independently opened with the recovery identity and reproduced the source md5; and a sweep of `/tmp`
found no `.decoded` file and no document that parses as a populated state outside the repository.

**Two of the 17 cases exist because a code review found defects my first 14 did not.** The earlier
version wrote its verification temp files at the ambient umask (`0002` on this host → mode `664`,
other-readable) and left them behind on every failure path, because `trap … RETURN` does not fire when
a function calls `exit` or when `set -e` aborts mid-function — the inventory of 40 repositories in
plaintext, beside the ciphertext, on the backup disk. It also invoked `state_gate.py` without pinning
the config directory, which measured `SAFE` **over zero resource blocks** from a foreign CWD: a
vacuous pass, not a refusal. And a first attempt to fix the leak introduced a worse bug — the cleanup
trap deleted the artefact on *any* failure, so a refused same-second re-run **destroyed the original
backup**; hence the `CREATED` flag, and hence the case that asserts preservation rather than mere
refusal. `age --list-recipients` is **not available in age 1.1.1** — an early draft used it and died
after encrypting, before verifying.

**Committed harness — 32 cases.** `tests/test_backup_gate.sh` runs `scripts/backup_state.sh` against
fixtures built from the shape of a real Terraform 1.16.1 state document, in a temp directory that a
trap removes. Case 19 extracts the fence above and requires it to be **byte-identical** to the script,
so this runbook cannot quietly drift from the code it describes; case 20 asserts `umask 077` at source
level, because the suite provably cannot detect its removal behaviourally. Cases 24–32 cover
`scripts/state_backup_guard.sh`, the scheduled front door described in RB-09. **Twenty-four** cases
need neither `age` nor a real state and therefore run in CI (24 passed, 8 skipped, exit 0); the eight
crypto cases additionally need `age` **and** a real `terraform.tfstate`, which a runner cannot have
(state is gitignored), so they report `SKIPPED` and are announced rather than counted as passes.
Locally: **32 passed, 0 failed**.

The suite was falsified rather than trusted. Nine defects that were fixed were each reintroduced into
a **throwaway copy** — never the working tree — and every one is caught by a named behavioural case:

| Mutation | Caught by | | Mutation | Caught by |
|---|---|---|---|---|
| neutralise the same-disk comparison | 21 | | drop the `CREATED` guard from the trap | 14, 16 |
| drop the `resources > 0` requirement | 7 | | gate-unreachable returns `0` not `2` | 9 |
| delete the in-repo refusal's `exit 1` | 4 | | recipient-only mode sets `RC=0` not `2` | 13 |
| remove `umask 077` | 20 | | make the same-second reservation always succeed | 12, 13, 14 |
| accept any recipient as "different" | 10, 11 | | append one newline anywhere in the script | 19 |

**Two ordering assertions exist because exit codes and refusal text were both shown to be insufficient.**
Every guard case passes a deliberately invalid `RECOVERY_KEY`, so *any* later failure also yields the
expected `RC=1` — which is how case 7 stayed green after its own guard was deleted, stopped instead by
the device check. Then asserting the refusal *text* proved insufficient too: deleting only the in-repo
refusal's `exit 1` still prints that text, and the next guard stops the run, so case 4 would have
credited a different control with its pass. The helper now requires that (a) `age` was never reached and
(b) every `FAIL:` line carries the phrase the case is about. Both rules are mutation-tested above.

A case that always fails is as useless as one that always passes, and reads more convincingly: see the
next paragraph, which is about this suite's own checker being wrong twice.

**Case 21 nearly became a false pass while it was being written, and the lesson is in the suite.** The
`lsblk` stub inspected `$1`, which is `-no`, not the device — so it returned nothing, the device check
silently never ran, and the same-disk case still exited 1 because the deliberately-fake identity file
failed later for an unrelated reason. Right exit code, no proof. Caught only because the assertion also
requires a verdict line, which came back `no-verdict`; case 21 now additionally asserts that the stubs
resolved at all, and the rule that every guard case must not reach `age` was written for it.

**How this harness itself was found to be broken twice, which is the reason to run mutations at all.**
First version of case 19 passed unconditionally: the command carried both a heredoc and `</dev/null`,
and the later stdin redirect wins, so `python3 -` read its *program* from `/dev/null`, executed
nothing, and exited 0 — a check that reports pass forever. The fix introduced the mirror image: the
body read `s==="```"`, a Python `SyntaxError`, so the case exited 1 and blamed **drift** for a typo,
which is how a suite gains a permanently-red check that looks like a real finding. Only the unmutated
baseline going red exposed it, and case 19 now separates "the checker errored" from "the files
differ". A test that always fails is as useless as one that always passes, and reads more convincing.

`make test` runs all five suites and `apply.yml`'s `Dev — Validate` runs this one, so neither can go
inert silently.

### Restoring

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
3. **Enumerate the candidates — in BOTH locations, and say so if one is not mounted.** The set on
   `/opt/jol/backup` shares one device with the live state; the `sdb1` copies written by the Create half
   above are the only ones that survive that disk, and they use the same basename convention so one glob
   shape finds both. **An empty glob on the second path is not evidence that no backup exists**: that
   mount is created by the desktop session, not by the system, so after a headless boot or a crash the
   directory simply is not there. Concluding "the backups are gone" from an unmounted path is how a
   perfectly recoverable inventory gets rebuilt by hand.
   ```bash
   D=/media/jol/32f7e56a-b96c-486a-93da-9e1a57567cfc/jol-state-backup
   ls -la /opt/jol/backup/tfstate/jol-control-terraform.tfstate.*.age
   if [ -d "$D" ]; then
     ls -la "$D"/jol-control-terraform.tfstate.*.age
   else
     echo "OFF-DISK BACKUP SET NOT VISIBLE - $D is not mounted. Do not judge the restore from this."
     lsblk -o NAME,SIZE,FSTYPE,MOUNTPOINT /dev/sdb        # is the disk present at all?
     udisksctl mount -b /dev/sdb1                         # session mount; changes nothing permanent
   fi
   ```
   Each backup has an `.info` sidecar with `serial`, `lineage`, `instances`, `md5`,
   `recovery-key-decrypted`, `recovery-key-location` and `device-check` recorded at creation. **Read the
   sidecar first** — it is the "checksum of the state you expect" the prerequisite asks for, and it costs
   no decryption:
   ```bash
   for f in "$D"/*.info; do echo "== $(basename "$f")"; cat "$f"; done
   ```
4. **Decrypt to a scratch file and compare metadata — never print state contents.** State carries
   the full inventory of every governed repository; it must not reach a log, a terminal scrollback
   or a pasted message. Run this under `umask 077`: the decrypted file is plaintext credentials.
   ```bash
   W=$(mktemp -d); chmod 700 "$W"; umask 077
   for f in /opt/jol/backup/tfstate/jol-control-terraform.tfstate.*.age \
            /media/jol/32f7e56a-b96c-486a-93da-9e1a57567cfc/jol-state-backup/jol-control-terraform.tfstate.*.age; do
     [ -f "$f" ] || continue
     age -d -i ~/.config/age/state-backup-key.txt "$f" > "$W/out.json" 2>/dev/null || continue
     echo "$(basename "$f")  bytes=$(stat -c%s "$W/out.json")  md5=$(md5sum "$W/out.json" | cut -d' ' -f1)"
     jq -r '"  serial=\(.serial) lineage=\(.lineage) instances=\([.resources[].instances[]]|length)"' "$W/out.json"
     jq -r '.resources[] | "    \(.type).\(.name) = \([.instances[]]|length)"' "$W/out.json"
     rm -f "$W/out.json"
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

**Residual risk this runbook cannot fix:** the refresh is **manual** — no cron entry and no systemd
timer runs `scripts/backup_state.sh` today. The off-device snapshot lives on a second disk **inside the
same machine**, on a mount a desktop session creates, and the second age identity is gone (see S2-013),
so host-level loss still takes the inventory and every copy of it. `make drift` compares names and
visibility, not attributes, so nothing here can rebuild the inventory. Scheduling and the boot mount
are `RB-09`; tracked as S2-012.

---

## RB-09: Make the off-device state backup reachable at boot, and refresh it without a human

RB-08 produced a snapshot on a second disk; this makes it **findable when the machine is not sitting
at a desktop session** and **renewed when nobody remembers to**. Both steps change the host, not this
repository, so they are written here to be reviewed and then executed by the operator.

> **Status 2026-10-27:** steps 1–4 are **applied and verified** — `/dev/sdb1` mounted at
> `/mnt/jol-backup`, generated unit present, recipient recorded, guard appended to the existing cron
> line, and the guard run end-to-end (it forced a refresh, wrote a third snapshot with
> `device-check: verified-different`, and returned **2**). **Step 5 is outstanding**: no copy of the
> recovery identity is off this machine, so S2-014 remains open and `off-host custody` will keep
> reporting NOT VERIFIED until that rehearsal is genuinely run elsewhere.

**Why it matters:** `/media/jol/32f7e56a-…` exists because `udisks2` mounted it for a GUI login.
`/etc/fstab` carries **no** entry for it, so after a reboot without autologin — or a crash recovery,
or an SSH-only session — the path is absent and RB-08's Restore step finds no candidates and could
conclude the backups are gone.

1. **Confirm the volume's identity, and that nothing else answers to it.** This host has **40 loop
   devices mounted**, and it carries a recorded incident where a loop-mounted forensic image
   re-animated an old filesystem UUID and hijacked a `by-uuid` fstab mount. Check before writing.
   ```bash
   lsblk -o NAME,SIZE,FSTYPE,ROTA,UUID,MOUNTPOINT /dev/sdb
   readlink -f /dev/disk/by-uuid/32f7e56a-b96c-486a-93da-9e1a57567cfc   # must print /dev/sdb1
   ls -l /dev/disk/by-uuid/ | grep -i loop                              # must print nothing
   findmnt -no SOURCE,TARGET /dev/sdb1                                 # where it is mounted now
   ```
2. **Add the boot mount.** Recommended source is the **device path**, `/dev/sdb1`, not `by-uuid`,
   precisely because of the hijack mode above: a kernel-assigned `sdX` name cannot be re-pointed at a
   loop image, whereas a UUID symlink can. The trade-off is honest and stated: if a disk is added or
   the controller enumerates differently, `sdb1` may move and this entry then fails — with `nofail`,
   boot continues and the directory simply is not there, which step 1 and the guard below both catch
   loudly rather than silently writing backups onto the root filesystem.
   ```bash
   sudo cp -a /etc/fstab "/etc/fstab.pre-rb09-$(date +%Y%m%dT%H%M%S)"
   echo '/dev/sdb1  /mnt/jol-backup  ext4  defaults,nofail,noatime  0  2' | sudo tee -a /etc/fstab
   sudo mkdir -p /mnt/jol-backup && sudo mount /mnt/jol-backup
   findmnt -T /mnt/jol-backup -o SOURCE,TARGET,FSTYPE,OPTIONS            # SOURCE must be /dev/sdb1
   ls -1 /mnt/jol-backup/jol-state-backup/                              # the existing snapshots are here
   ```
   `findmnt` showing the root device instead of `/dev/sdb1` means it did **not** mount; do not proceed.
   Then tell systemd about the new line. `mount` reads `/etc/fstab` directly and succeeds without this,
   which is exactly why it is easy to skip. Check it with `systemctl show`, **not** `ls`: systemd escapes
   the dash, so the unit file is `mnt-jol\x2dbackup.mount` and an unescaped `ls` is a permanent false
   negative — one was cited here before it was checked.
   ```bash
   sudo systemctl daemon-reload
   systemctl show -p SourcePath,UnitFileState 'mnt-jol\x2dbackup.mount' --no-pager
   ```
   Empty before the reload; `SourcePath=/etc/fstab` and `UnitFileState=generated` after it. A missing
   unit still mounts at boot, but `systemctl start`, dependencies and any later diagnosis have nothing
   to act on. (**Applied 2026-10-27:** `/dev/sdb1` is mounted at `/mnt/jol-backup`, `rw,noatime`, and
   the unit is generated.)
3. **Record the second recipient** so a scheduled run has something honest to encrypt to. The public
   key is not secret, but keeping it out of the crontab stops the custody topology leaking into every
   process listing.
   ```bash
   umask 077; mkdir -p ~/.config/age
   printf '%s\n' 'age1<the-new-off-host-recipient>' > ~/.config/age/offdisk-recipient.txt
   DEST=/mnt/jol-backup/jol-state-backup \
     RECOVERY_PUB="$(cat ~/.config/age/offdisk-recipient.txt)" scripts/backup_state.sh; echo "RC=$?"
   ```
   Expect **`RC=2`** — written, off-host custody not verified — which is the truthful steady state for
   a machine that no longer holds the second key. `RC=1` with *same physical disk* means step 2 did not
   take effect.
4. **Append the refresh to the existing 10-minute guard line.** This estate's recorded rule is that new
   guards extend `check-project-mounts.sh`'s line rather than mint a timer, so that one line stays the
   whole story and a failure has one place to be looked for.
   **Do not redirect it to a log file.** The guard already writes every line to journald through
   `logger`, which is the convention `check-project-mounts.sh` documents in its own header — journald is
   persistent on this host (`nvme0n1p5`) and survives the church-tree log directory being absent. An
   early draft of this step used `>>/opt/jol/data/logs/state-backup-guard.log 2>&1`; that directory does
   not exist on this host, so cron would have mailed a failure every ten minutes while the thing it was
   meant to record went nowhere.
   ```bash
   crontab -l > /tmp/crontab.pre-rb09-$(date +%Y%m%dT%H%M%S).txt   # back up first
   # Use awk, not sed. In a sed replacement, `&` means "the whole matched line", so the `&1` in
   # `2>&1` pastes the original crontab line into the middle of the new one. That corrupted this
   # host's crontab on the first attempt; `crontab <backup>` restored it byte-identically.
   crontab -l | awk '{ if ($0 ~ /^\*\/10 \* \* \* \* \/opt\/jol\/scripts\/check-project-mounts\.sh;/) print $0 "; cd /opt/jol/repos/jol-control && scripts/state_backup_guard.sh >/dev/null 2>&1"; else print }' | crontab -
   crontab -l | grep 'check-project-mounts'      # READ THE WHOLE LINE, do not trust a count
   diff /tmp/crontab.pre-rb09-*.txt <(crontab -l)   # exactly one line, exactly as intended
   journalctl --no-pager -t state-backup-guard -n 6               # read what it decided
   ```
   Confirm the restore path before leaving it: `crontab /tmp/crontab.pre-rb09-<stamp>.txt` puts the
   file back exactly as it was.
   The guard's three exit codes are the contract: **0** up to date or refreshed and proven, **1**
   refused (unmounted destination, same disk, no usable snapshot), **2** cannot-check (no second
   recipient, uncomputable clock). It exits 2 rather than writing a single-key backup and calling the
   job green. Expect the routine outcome to be exit 2 with `off-host custody NOT verified` until
   step 5 has been run once against a copy that is genuinely off this machine.
5. **Rehearse a restore monthly** to turn the steady `RC=2` into a real `0`. Run this **on the machine
   holding the off-machine identity**, and note the shape: the decrypt is captured to a file and its
   exit status tested, never piped into a checksum. `age … | md5sum` prints
   `d41d8cd98f00b204e9800998ecf8427e` — the MD5 of *empty input* — and exits **0**, so a failed decrypt
   is indistinguishable from a verified one. That exact command was issued from this runbook's own
   guidance and produced a false result (see measurement trap 10; this is trap 17).
   ```bash
   S=jol-control-terraform.tfstate.<stamp>.age
   # Copy BOTH files to the other machine: <snapshot>.age and its <snapshot>.age.info sidecar.
   want=$(awk '/^md5/{print $NF}' "$S.info" 2>/dev/null || true)
   age --decrypt -i <identity-file> "$S" > /tmp/rehearsal.json 2> /tmp/rehearsal.err
   rc=$?; sz=$(stat -c%s /tmp/rehearsal.json 2>/dev/null || echo 0)
   m=$(md5sum /tmp/rehearsal.json 2>/dev/null | cut -d' ' -f1); RESULT=FAIL
   if   [ "$rc" -ne 0 ]; then echo "FAIL: decrypt exited $rc"; sed -n '1,3p' /tmp/rehearsal.err
   elif [ "$sz" -lt 1000 ]; then echo "FAIL: only $sz bytes came out - nothing was decrypted"
   elif [ "$m" = d41d8cd98f00b204e9800998ecf8427e ]; then echo "FAIL: md5 of empty input"
   elif [ -z "$want" ]; then RESULT=INCONCLUSIVE; echo "INCONCLUSIVE: md5=$m bytes=$sz, but no sidecar to compare against"
   elif [ "$m" != "$want" ]; then echo "FAIL: md5=$m but the sidecar says $want - DIFFERENT INVENTORY"
   else RESULT=PASS; echo "PASS: md5=$m bytes=$sz, matches the sidecar"
   fi
   shred -u /tmp/rehearsal.json /tmp/rehearsal.err 2>/dev/null || rm -f /tmp/rehearsal.json /tmp/rehearsal.err
   # Signal, do not narrate. A block that prints FAIL and exits 0 is the false green this whole
   # section exists to prevent, and it is one `&&` away in a future cron line.
   [ "$RESULT" = PASS ] || exit 1
   ```
   `INCONCLUSIVE` is a distinct outcome on purpose: a rehearsal without the expected value proves only
   that something decrypted, which is the claim that has been wrong every time in this file. It exits 1
   as well — unproven is not passed.

   The `shred` is not ceremony: that file is plaintext Terraform state, on a machine that is not this
   one, holding the inventory of 40 repositories. Record the run — date, snapshot, the md5 that came
   back, and where the identity now lives — in `docs/drift-findings.md`. Until that happens, the
   off-host path is asserted, not demonstrated, which is the sentence S2-012 exists to keep people
   from skipping.

**Rollback:** restore the `/etc/fstab` backup from step 2 and `sudo umount /mnt/jol-backup`; restore
the crontab from step 4's capture with `crontab <file`. Neither step touches the snapshots themselves,
and no step here deletes anything.

**Not covered by RB-09:** the destination is still inside the same chassis, on a **rotational
2012-era** drive whose SMART health is unverified (`smartctl` needs a password), so fire, theft,
surge and the loss of the host remain open. And the guard's verdicts land in journald with **no alert
channel that could carry them** — this estate's whole notification chain is non-functional (finding
**S2-016**: no alertmanager process, a literal `PLACEHOLDER` Slack URL, a null-MX mail domain,
Prometheus scraping only itself), so a run of `1`s would be invisible until someone looked. `make
backup-status` is the interim: one pull, 0/1/2, that re-derives the disk separation instead of
trusting the sidecar and refuses to report anything it cannot see as a pass.

### The off-machine rehearsal, concretely

Step 5 is the one action that closes S2-014, so it is spelled out with the real file names rather than
placeholders — the last three commands written for this runbook with angle brackets or a missing file in
them each produced a failure the operator had to interpret (`RC=127`, `bash: syntax error near
unexpected token`, a false md5).

**Here**, stage the three files anywhere outside the repository:
```bash
cd /mnt/jol-backup/jol-state-backup
mkdir -p /tmp/offhost-packet && cp -p jol-control-terraform.tfstate.20261027T200234Z.age \
  jol-control-terraform.tfstate.20261027T200234Z.age.info keys/state-recovery-20261027-b.txt /tmp/offhost-packet/
sha256sum /tmp/offhost-packet/* > /tmp/offhost-packet/SHA256SUMS
cat /tmp/offhost-packet/SHA256SUMS
```
Carry `/tmp/offhost-packet` to the other machine by whatever means is not this machine, verify the
checksums there, then run **this** on that machine — it takes the identity path as one argument and
refuses if it is wrong, so there is nothing to substitute and nothing to get wrong:
```bash
ID=./state-recovery-20261027-b.txt SNAP=./jol-control-terraform.tfstate.20261027T200234Z.age \
  bash -c 'test -s "$ID" || { echo "FAIL: identity not at $ID"; exit 2; }
           test -s "$SNAP" || { echo "FAIL: snapshot not at $SNAP"; exit 2; }
           want=$(sed -n "s/^md5  *: //p" "$SNAP.info")
           age --decrypt -i "$ID" "$SNAP" > /tmp/offhost-decrypt.json 2>/tmp/offhost-decrypt.err
           rc=$?; sz=$(stat -c%s /tmp/offhost-decrypt.json 2>/dev/null || echo 0)
           got=$(md5sum /tmp/offhost-decrypt.json 2>/dev/null | cut -d" " -f1)
           shred -u /tmp/offhost-decrypt.json /tmp/offhost-decrypt.err 2>/dev/null
           if   [ "$rc" -ne 0 ]; then echo "FAIL: decrypt exited $rc"; exit 1
           elif [ "$sz" -lt 1000 ]; then echo "FAIL: $sz bytes - nothing decrypted"; exit 1
           elif [ "$got" = d41d8cd98f00b204e9800998ecf8427e ]; then echo "FAIL: md5 of empty input"; exit 1
           elif [ "$got" != "$want" ]; then echo "FAIL: got $got, sidecar says $want"; exit 1
           else echo "PASS: custody proven off-host; md5=$got matches the sidecar, plaintext shredded"
           fi'
```
A `PASS` there is the evidence S2-014 asks for: the copy that decrypts is not on this machine, and no
disk failure here leaves the inventory unreadable. Record the date, the snapshot name and that md5 in
this register — and only then consider `make retire-key` for the local copy, which it will refuse until
a copy on another **disk** proves the same thing.
