# Changelog

All notable changes to jol-control will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- `scripts/backup_status.sh` and `make backup-status` — one pull that answers whether the state backup
  is fresh, provably on another physical disk (re-derived with `findmnt`/`lsblk`, not merely read back
  from the sidecar), and whether off-machine custody exists, with 0/1/2 semantics. **The normal answer
  today is 2**, deliberately: no check running here can prove a copy exists elsewhere, and reporting
  that as a pass is the failure mode this thread kept hitting. It exists because the estate has no
  working push channel (S2-016), so an alert would have been theatre
- `docs/runbooks.md` RB-09 and `scripts/offhost_rehearsal.sh` — the off-machine custody rehearsal as a
  challenge round-trip: `make backup-pack` stages a packet holding the newest snapshot, its sidecar, a
  recovery identity and a nonce encrypted to the recipient (only its **hash** is kept here); the packet
  carries its own `verify`, which checks a **relative-path** manifest before decrypting anything; the
  token recovered on the far machine is brought back to `make backup-attest`, which consumes the pending
  challenge so the same token cannot be replayed. Attestation **expires** after 30 days
  (`ATTEST_MAX_H`), which is what lets `make backup-status` reach 0 without becoming a permanent green
  light. This replaces an earlier version of the same instruction that staged a private identity in
  `/tmp`, shipped an absolute-path manifest that verified the files left at home, named a snapshot the
  daily guard had already superseded, and proved nothing about custody — see finding S2-017
- `make fmt-check` — non-mutating Terraform formatting STOP gate (`terraform fmt -check
  -recursive`; exit 0 clean / 3 unformatted). `make lint` now depends on it instead of on `fmt`,
  so the documented verification command no longer rewrites files as a side effect
- `tests/test_state_gate.sh` gained 7 assertions (16 → 23) and two helpers, `assert_note` /
  `assert_no_note`, which assert on what the gate *reports* rather than only on its exit code.
  The stale-copy NOTICE never changes the verdict, so exit-code-only assertions passed straight
  over the defect they existed to catch
- `scripts/state_gate.py` `stale_state_copies()` — a single helper both call sites now share, so
  the remote-backend and local-state branches cannot drift apart on what counts as a stray copy
- `docs/drift-findings.md` S1-010, S1-011, S1-012, S2-007, S2-008, S2-009, S2-010, S2-011 and
  S2-012, each with the measurements behind it, one hypothesis recorded as refuted rather than
  quietly dropped, and one agent-caused incident recorded against its own author
- Measurement trap 9 in `docs/drift-findings.md`: `$?` after a pipeline reports the **last** stage,
  which made `gitleaks detect … | tail -30; echo "RC=$?"` print `RC=0` beside `leaks found: 10`, and
  would have made the new CI secret scan fail on every run had it not been caught by executing it
- Measurement trap 10 in `docs/drift-findings.md` — the more dangerous sibling of trap 9. A failed
  producer behind a pipe does not only corrupt the exit code, it **manufactures a plausible value**:
  `age --decrypt -i key missing.age | md5sum` printed the MD5 of *empty input* and exited **0**, so a
  broken backup is indistinguishable from a verified one. Trap 9 is wrong about a status; this one is
  wrong about a measurement that looks like a measurement
- `docs/SECRETS_INVENTORY.md` row **AGE-2** for the recovery identity RB-08 depends on, added because
  the register's own Rule 2 makes an unregistered credential a review failure — and this change created
  one. **Amended the same day to record that the identity was destroyed** (see Fixed / S2-013), with
  **AGE-3** opened for the replacement. The rows state the uncomfortable facts rather than dressing them
  up: a second `age` recipient is **1-of-2** (either key alone decrypts), which is not threshold secrecy
  and not AGE-1's pending "sealed 2-of-2 envelopes", a custody procedure rather than an encryption scheme
- `docs/runbooks.md` RB-08 writes an `.info` sidecar per backup (`serial`, `lineage`, `resources`,
  `instances`, `md5`, `recipients`, `recovery-key-decrypted`, `recovery-key-location`, `device-check`),
  and the Restore half now enumerates **both** locations and reads the sidecar before decrypting.
  Previously the two halves of the same runbook did
  not agree: Create wrote `jol-control-tfstate-<stamp>.age` while Restore globbed
  `/opt/jol/backup/tfstate/jol-control-terraform.tfstate.*.age`, so a backup made by the new procedure
  was invisible to the recovery procedure written the same day. The sidecar also finally supplies the
  "checksum of the state you expect" that Restore's own prerequisite demands and that previously existed
  only on a terminal scrollback
- `scripts/backup_state.sh` — the RB-08 create-backup script **as a committed artefact**, not as prose
  inside a fenced block. It exists because the runbook instructed an operator to run `backup.sh`, a file
  that had never been created, and they got `RC=127`. The script is byte-identical to the fence and that
  identity is now *enforced*, not asserted in a document
- `tests/test_backup_gate.sh` — 56 self-tests for that script with the repository's three exit codes
  (0 both custody paths proven / 1 refused / 2 written-but-unverified), covering the guard paths (bad
  source, wiped state, absent destination, destination inside the repository, missing recovery input,
  unreachable gate, same-disk destination, unresolvable destination device) and the crypto paths (same-key
  refusal in both modes, recipient-only `NOT VERIFIED`, same-second collision, artefact permissions,
  sidecar contents, plaintext survival). Twenty-four need neither `age` nor a real state so they run in CI;
  eight report `SKIPPED` there and are announced, never counted as passes. **Nine fixed defects were
  re-introduced into throwaway copies and each was caught by a named behavioural case.** Two ordering
  assertions were added after mutation testing showed exit codes *and* refusal text were both insufficient
  on their own (see Fixed below). `make test` runs all six suites. **Caveat, because this claim was wrong
  once already:** `apply.yml` triggers on `push: branches: [main]`, so this suite has not executed in CI
  yet — a pull request shows Compliance Scan only, and first real execution is the merge commit
- `tests/test_retire_gate.sh` — 15 self-tests for that gate. The property is not "does it delete" but
  "can anything delete an identity **without proof**", so every refusal case also asserts the identity is
  still on disk. Two mutations — a vacuous proof comparison, and removing the proof check entirely —
  each make the suite fail, so the gate is shown to be able to catch its own removal
- `scripts/state_backup_guard.sh` — the scheduled front door for RB-08 (0 up to date or refreshed and
  proven / 1 refused / 2 cannot-check). It refuses rather than fabricating: with no second recipient
  recorded it exits **2** instead of writing a single-key "backup", an unmounted destination is a refusal
  with nothing written, and a non-numeric `date +%s` is reported as UNEVALUATED rather than crashing the
  arithmetic. Steady state on a correctly configured host is **2**, not 0, and that is deliberate
- `make backup-state` — supplies the arguments to the script, with a usage line naming both custody
  modes and the requirement that `DEST` sit on a different block device
- `docs/runbooks.md` **RB-09** — make the off-device backup reachable at boot and refreshed without a
  human: verify the volume identity first (this host has **40 loop devices mounted** and a recorded
  incident where a forensic image re-animated a UUID and hijacked a `by-uuid` mount), which is why the
  recommended fstab source is the device path `/dev/sdb1` rather than its UUID, then append the refresh
  to the **existing** 10-minute guard line rather than minting a timer, and rehearse a restore monthly
  to earn a real exit 0. Rollback for both steps is stated.
  **Applied 2026-10-27**: `/dev/sdb1` is mounted at `/mnt/jol-backup` (`rw,noatime`, generated unit
  present after `daemon-reload`), the guard is appended to the existing cron line, and it was run
  end-to-end — it forced a refresh, wrote
  `jol-control-terraform.tfstate.20261027T200234Z.age` (195,451 bytes, `device-check:
  verified-different: state=nvme0n1 backup=sdb`), and returned **2** with `off-host custody NOT
  verified`, which is the truthful steady state
- Measurement traps 14 and 15 in `docs/drift-findings.md`. **14:** a heredoc and `</dev/null` on the
  same command silently disable the heredoc — the later stdin redirect wins, so `python3 -` read its
  *program* from `/dev/null`, ran nothing and exited 0; the check that looked like a byte-identity
  assertion was an empty program. **15:** its repair introduced the mirror image — a stray `s==="```"`
  made the body a Python `SyntaxError`, so the case exited 1 and blamed *drift* for a typo, and every
  mutation appeared to be detected because the case always fired. A test that always fails is as useless
  as one that always passes, and reads more convincing; a **green baseline is a precondition** for
  trusting any red mutation
- `scripts/state_gate.py` — STOP gate that refuses `terraform apply` when the state in
  front of the config cannot account for what the config would create: 0-byte state file
  (Terraform writes state atomically and never produces one on its own), state that
  parses but holds zero managed resources, or no state at all while the directory
  declares resources or module blocks. Reads `terraform.tfstate` **and**
  `terraform.tfstate.d/<workspace>/terraform.tfstate`, and classifies a directory as
  "not an apply target" only on positive evidence (a parent `module` block with a
  relative source, or a vendored/quarantined tree) — never on absence of state.
  A root whose backend is declared in `.tf`/`.tpl`/`.backend.hcl` is reported
  UNEVALUATED rather than safe, because local files cannot see remote state.
- `tests/test_state_gate.sh` — 16 self-tests with distinct exit codes
  (0 safe / 1 refused / 2 cannot-check), built on the key shape of a real captured
  Terraform 1.16.1 state document
- `tests/test_drift_gate.py` + `tests/fixtures/drift_detect/` — 11 self-tests for
  `scripts/drift_detect.py`, built on two real captures of `gh repo list
  journeyoflife-org --json name,visibility`: the operator-token view (41 rows, one
  PRIVATE) and the `secrets.GITHUB_TOKEN` view reconstructed from the log of failed run
  37107745958 (39 rows, no private repository visible at all)
- `scripts/validate_agents_table.py` + `tests/test_agents_gate.py` (9 cases) +
  `make agents-gate` — AGENTS.md section 2 is what an agent reads before trusting any claim
  about this organization, and it was checked by nobody. Documentation-only commits were
  excluded from `apply.yml`'s `paths:` filter, so a malformed row could sit on `main` with no
  CI signal at all; `AGENTS.md` is therefore now in that filter and the gate runs in
  `Dev — Validate` on every push to `main`, plus in `compliance-scan.yml` on pull requests and
  the weekly schedule. It requires three non-empty cells per row and a non-empty evidence cell,
  treats escaped `\|` as content rather than a separator, and fails closed: 0 pass / 1
  violation / 2 cannot-check, with a missing header, a missing section, an unreadable file and
  a no-argument invocation all reporting UNEVALUATED rather than success.
  Fixtures are a verbatim capture of the live section and the broken variants are derived from
  it by mutation, reproducing the mistakes an editor actually makes — an unescaped pipe that
  silently adds a cell, a blank evidence column, a header-only table
- `docs/runbooks.md` RB-06 — "Inspect or Change a Repository Ruleset", written from the
  measurements taken while chasing the `.github` merge block: rulesets and classic branch
  protection are separate APIs blind to each other (a `404` from one is not an absence of
  protection), a ruleset `PUT` is a full replace so the current document must be snapshotted
  first, required status checks live inside the `update` rule's parameters rather than as their
  own rule type, and any verification read must be cache-busted because GitHub serves cached
  reads for up to 60 seconds. It records the measured `protect-main` state, that organization
  rulesets cannot even be listed on this plan, and an explicit instruction not to improvise a
  cause for the unresolved block — toggles made while testing must be undone.
- `policy/contact-channels.yml` — authoritative role → address mapping for
  journeyoflife-org (`dev`, `github`, `billing`, `security`, `privacy`). Splits the
  channels into an **admin plane** (billing/github/dev — GitHub-internal, never
  written into a public file) and a **public plane** (security/privacy — publishable,
  because a data subject cannot exercise a statutory right through a GitHub
  advisory). Records that all five are plus-addressed aliases of one mailbox and
  therefore provide triage, not segregation of duties or an independent failure
  domain; states which artifacts must never be edited (captured evidence, generated
  scanner output, documentation placeholders); and notes that organization email
  settings are not Terraform-managed.
- `docs/drift-findings.md` S1-003 — every contact address published across the fleet
  is undeliverable. `journeyoflife.org` has a **null MX** (`MX 0 .`, RFC 7505) on
  afternic parking nameservers, `journeyoflife.eu` has no MX, `journeyoflife.lt` does
  not resolve. 112 + 5 occurrences over 74 files in 27 repositories, including 28
  `SECURITY.md` files directing researchers to a hard-bouncing address and
  `jol-devops/monitoring/alertmanager/alertmanager.yaml` configuring an email receiver on
  it (and `smtp.journeyoflife.org` resolving to the same domain-parking addresses as the
  apex, i.e. no SMTP server). Private vulnerability reporting was also enabled on 0 of the
  40 public repositories, so the organization had no working vulnerability intake at all —
  see Fixed.
- `docs/threat-model.md` T-13 (unreachable security/DPO contacts, Availability) and
  risk acceptance **RA-04** for publishing role aliases while no domain mail exists
- `docs/drift-findings.md` S2-005 — the git-identity half of the migration, recorded as it was
  learned: `POST /user/emails` answers `404` even with the `user:email` scope so account
  addresses are UI-only, `required_signatures` and `enforce_admins` are both live on `main`,
  `--global` identity is the wrong scope on a three-organization host, and a commit authored
  by an address that is not a verified email on the key's account is **refused at push**
  (GH006), not merely unverified. Contains two same-day corrections, including the retraction
  of this entry's own earlier conclusion
- `policy/contact-channels.yml` gained an `identity_migration` block: the order of
  operations, the two-authenticated-accounts hazard, and the host state as verified
- `policy/contact-channels.yml` → `role_mapping` — every address actually published in the
  estate with its replacement or an explicit `delete`/`leave alone` verdict, so sweeping the
  remaining 24 repositories is a lookup rather than 24 fresh judgement calls. Addresses absent
  from the table must raise a question, not an invented channel.
- `docs/drift-findings.md` S1-004 + `docs/threat-model.md` T-14 — the advertised donation path
  is a parked domain: `https://journeyoflife.org/donate` answers 200 with a 114-byte redirect to
  `/lander` and `journeyoflife.eu` is Hostinger-parked, so donors reach a third-party ad page
  served under the organization's own name. A fleet-wide search found **no** real donation
  endpoint anywhere, and this change deliberately did not guess one — owner decision required
- `docs/drift-findings.md` — a measurement-traps section recording that rulesets and legacy
  branch protection are invisible to each other (`.github` main looks unprotected through the
  legacy API but is enforced by ruleset `protect-main` with signatures, linear history, merge and
  deletion blocks, code-owner review at zero required approvals, and an always-on admin bypass),
  that `github_branch_protection` must be summed across both its state resources, and that an
  unquoted heredoc silently executes backticked prose
- `docs/drift-findings.md` S1-009 — **seven governance-tier repositories have branch protection
  in state and none on GitHub.** `terraform.tfstate` (serial 306) holds 39
  `github_branch_protection` instances across 39 distinct repositories, but
  `jol-compliance-evidence`, `jol-iac`, `jol-incident-response`, `jol-payments-scope`,
  `jol-privacy`, `jol-secrets` and `jol-status` are empty (`size=0`, `409 Git Repository is
  empty`), so `GET …/branches/main/protection` answers 404 there: 32 of 41 repositories are
  protected live, and the governance tier's asserted posture (signed commits, linear history,
  force-push and deletion blocks, `enforce_admins`) is in force on only 4 of its 11 members.
  `make drift` cannot see any of this — `scripts/drift_detect.py` compares `name,visibility`
  only. Discovered by refuting someone else's claim of a *duplicate* protection: the tier
  partition in `branch-protection.tf:22,29` is disjoint by construction, and no repository is
  covered twice
- `docs/drift-findings.md` — measurement traps 6–8: a confident report that an action was taken
  is not a measurement (six claims in one turn, every one contradicted by `gh pr view`,
  `git cat-file` and a re-scan); a `Bearer`-token `curl` against `github.com` HTML cannot
  discriminate token scope, because HTML answers 404 for a private repository even to a token
  that reads it through the API; and a workflow run whose name matches a reusable workflow is
  not proof that a caller resolved it (`jol-docs`' green `compliance-check` is its own file)
- `docs/runbooks.md` RB-07 — "Mint or Rotate `ORG_READ_TOKEN`", the read-only fine-grained PAT
  the CI drift job needs to see private repositories. Carries the scope table with the consequence
  of each wrong row (resource owner, **All repositories**, Metadata/Contents read, Members read,
  90-day expiry, name pattern), the pre-filled token form, verify-before-store commands that prove
  the token can enumerate `jol-dr` **before** it is saved as a secret, the CI proof that a name
  read-back cannot substitute for, the failure signature that separates `401 Bad credentials` (the
  credential value) from `403 Resource not accessible by personal access token` (the scope), an
  inventory table whose `expires_at` must be transcribed from Settings because `GET
  /orgs/journeyoflife-org/personal-access-tokens` answers `404` from this host, and the degradation
  note: removing the secret returns the job to an honest UNEVALUATED, never to green

### Changed
- **The off-device backup destination moved to `/mnt/jol-backup/jol-control`, one directory per tree.**
  `/mnt/jol-backup` is `root:root 755`, so creation needed one `sudo mkdir` + `chown jol:jol` + `chmod 700`
  (run by the operator); the three consumers (`state_backup_guard.sh`, `backup_status.sh`,
  `offhost_rehearsal.sh`) and the runbook paths were renamed with literal `sed` — no `&` in the
  replacement, because that is measurement trap 18. The AGE-3 identity copy moved with it (`keys/` under
  the new directory), verified byte-identical by `sha256sum` after the `mv` and re-confirmed to decrypt
  the new snapshot to `b25b8821…`. **What this does *not* buy:** both trees run cron as the same user
  `jol`, so no directory mode ever separated them — the name and lineage pinning of S2-018 is the control
  and holds regardless. The three older snapshots in `jol-state-backup` are left in place, unread by any
  tool here, and rollback is `DEST=/mnt/jol-backup/jol-state-backup <script>`: no path is baked into the
  crontab, so reverting the schedule means reverting this commit. Case 51 pins the default at source
  level (same reasoning as case 20's `umask 077`) — the cron line passes no `DEST`, so the script's
  default *is* the production destination, and a silent fallback would write onto the root filesystem of
  an unmounted `nofail` volume
- `tests/test_backup_gate.sh` and `tests/test_retire_gate.sh` no longer toggle errexit. Both declare
  `set -uo pipefail` so every case runs and is counted, but wrapped their timeouts in
  `set +e … ; rc=$?; set -e`, which turned errexit **on for the rest of the file**. The backup suite then
  aborted after case 32 on an ordinary `grep -c` returning 1 for zero matches — printing 32 passes and
  no verdict — while the retire suite had the same latent fault and only survived because the `set -e`
  landed near its end. Replaced with `rc=0; cmd || rc=$?` throughout, and the rehearsal helper now counts
  its own misuse as a FAIL rather than crashing
- `docs/runbooks.md` RB-09's off-machine rehearsal is now the `offhost_rehearsal.sh` round-trip, and the
  stale CI census beside it was re-measured in a mirror tree rather than copied forward: **24 pass, 21
  skip, exit 0** (it had claimed 24/8). `make backup-status` gained `ATTEST_MAX_H` (default 720h) so a
  custody claim expires instead of calcifying, and it now re-derives disk separation with `findmnt` +
  `lsblk` rather than trusting the sidecar's own `device-check` line
- `AGENTS.md` §3: `make test` is documented as **six** gate suites with the expected counts, plus rows
  for `make backup-state` and `make retire-key`; §4 gains a standing boundary — **never delete key
  material on an agent's instruction alone** — pointing at RB-08 step 4 and S2-013
- `.github/workflows/plan.yml`: the `Destroy / Replace Gate` step is now armed only on positive
  evidence of a reachable inventory — a non-empty `terraform.tfstate` or a declared `backend` block —
  and otherwise emits a `::notice::` that the verdict is UNEVALUATED in CI. It previously ran
  unconditionally against a checkout that cannot contain state, so every plan was create-only
  (`119 to add, 0 to destroy`) and the gate correctly refused, making the check permanently red on
  every PR touching `*.tf`, `repos/**`, `policy/**` or `*.tfvars`. Not a weakening: the gate still
  runs wherever its inputs exist, and its 11-fixture self-test still runs on every PR (S1-012)
- `Makefile`: the `apply` warning claimed *"this host holds the only copy of terraform.tfstate"*.
  Three `age`-encrypted snapshots exist at `/opt/jol/backup/tfstate/`. The warning now states the
  true risk — no **off-host** copy, backups are manual and share the device — and points at RB-08
- `docs/runbooks.md` RB-08 retitled to **"Back up and restore `terraform.tfstate`"** and given the
  create-side half it lacked. It now carries a two-recipient `age` command and a verifier that
  round-trips the ciphertext with **both** identities, rejects the md5 of empty input, and refuses
  when the two recipients resolve to the same key; plus the measured device layout — live state on
  `nvme0n1p8` and the existing backups on `nvme0n1p6` are **one physical disk**, while `sdb1` is not —
  and a plain statement that `sdb1` closes single-device loss only, not fire, theft or whole-host
  loss. The restore half was written **after** executing and verifying it, not from memory:
  stop-first, preserve-and-checksum, enumerate, decrypt to metadata only (never print state
  contents), accept only an exact `serial`/`lineage`/instance/md5 match, then confirm via
  `terraform state list` and `state-gate`
- `.github/workflows/compliance-scan.yml`: the `security-scan` job lost its decorative
  `matrix.tier` — no step ever referenced it, and `actions/checkout` with no `repository:` checks
  out this repository only, so run 40072669078 ran four identical jobs against one tree. The step
  also gained the ability to fail: a match, **or** a grep that could not run, now emits `::error::`
  and exits 1 where it previously emitted `::warning::` and stayed green. It prints `file:line`
  only, never the matched text, because this repository is public and so are its Actions logs
  (S1-010)
- `Makefile`: `lint` is now `fmt-check validate`; `fmt` is retained but its help text says it
  mutates the working tree
- `AGENTS.md` §3: `make test` expected counts corrected (state-gate 16 → 23), and the combined
  `make fmt` / `make lint` row split into three rows that state plainly which target writes
- `.github/workflows/compliance-scan.yml`: the drift step binds `secrets.ORG_READ_TOKEN ||
  secrets.GITHUB_TOKEN` instead of the runner token alone, and its exit-2 annotation now points at
  RB-07 rather than telling the operator to create a credential that already exists. The fallback
  is what keeps this honest: an unset or expired secret degrades the job to UNEVALUATED, never to a
  pass and never to the old false DRIFT
- `AGENTS.md` §2 re-measured 2026-10-19 and gained two rows: the ruleset figure is restated as
  **20 active requirement-bearing rulesets across 19 repositories** (17 requiring ≥1 approving
  review, 19 requiring code-owner review) out of 24 rulesets in the fleet, replacing the less
  precise "21 rulesets across 19 of 40"; "governance-tier repositories have the strongest
  protection" is recorded as false for 7 of 11 (S1-009); "the ruleset relaxation has been applied
  and ADR-013 is accepted" is recorded as false, with the commands that decide it; and the shared
  CI library row now states that consumer-side proof is still owed
- `docs/drift-findings.md` S2-006 rescoped from a `jol-hub` defect to a fleet measurement: 41
  repositories, 14 with `dependabot.yml`, 12 declaring `labels:`, **11 of those 12 referencing
  labels that do not exist**. Severity stays S2 (triage routing, not a control), and the entry now
  names the real problem: there is no authoritative label vocabulary anywhere — `GET
  /orgs/journeyoflife-org/labels` answers `404` on this plan and no file in `jol-control` declares
  one — so "create them in all eleven" would be eleven more out-of-band mutations
- `docs/drift-findings.md` S1-008 records the withdrawal of the relax-first ordering this register
  previously recommended, and re-measures the collision with S1-003: still exactly **13 of the 24**
  repositories with a dead published address, leaving **11 sweepable without an admin bypass**
- `make plan-gate` now depends on `make state-gate`, so `make apply` is behind two
  gates instead of one; `make test` runs the state-gate suite alongside plan-gate
- `.github/workflows/apply.yml`: `dev-validate` now runs `bash tests/test_state_gate.sh`
  next to the plan-gate self-test, and `on.push.paths` gained `scripts/**` and
  `tests/**`. Before this, a change to either gate could land with no CI run at all —
  an inert gate is worse than an absent one. The gate itself is not executed in CI: it
  judges local state, and CI has neither the state nor backend credentials
- `audit/gdpr-checklist.yml`: `dpo_contact` `dpo@journeyoflife.org` →
  `journey4oflife+jol.privacy@gmail.com`. The old value could not receive mail, so the
  checklist was asserting an Art. 30/Art. 38 contact that an auditor would fail on
  first test; the reason is now recorded inline rather than silently swapped
- journeyoflife-org `billing_email` moved off the bare mailbox to
  `journey4oflife+jol.billing@gmail.com` (verified by a fresh `gh api
  orgs/journeyoflife-org` GET, not the PATCH echo; previous value
  `journey4oflife@gmail.com`). Owner-visible only, never a published surface.
  Applied out of band because this control plane declares no `github_organization`
  resource — adding one is an infrastructure change and needs an ADR in jol-docs
  first, so the setting is currently outside drift detection
- `policy/contact-channels.yml` and `docs/drift-findings.md` S2-005: the noreply authorship
  switch is **declined, not deferred**, and S2-005 is closed by decision. Measured exposure:
  1,151 of 1,341 commit objects in the estate are authored by the base mailbox, across 40
  public repositories, and the same address is the public profile field and the signing key's
  UID — so a forward-only author-field change withdraws nothing, while the cost of trying it
  was a demonstrated estate-wide push refusal. Recorded as accepted risk **RA-05**.
- `docs/drift-findings.md`: the sibling-estate warning is replaced with a scan instead of a
  hypothesis — `jolarca-docs` enforces `required_signatures` (its noreply pushes will be
  refused), 9 other jolarca repositories do not (which is why 3 noreply commits already
  pushed, each unverified), and `jolarca-dr` and `jolarca-consent` returned `404 Branch not
  protected` at all.
- `.github/workflows/apply.yml`: the post-apply `Drift detection` step now binds the same
  `secrets.ORG_READ_TOKEN || secrets.GITHUB_TOKEN` expression `compliance-scan.yml` uses, with the
  reason inline. It ran on the ambient runner token, so the day `vars.TF_REMOTE_STATE_ENABLED` is set
  the production job would fail on a step whose verdict is a token artefact rather than drift.
  Inert today because that job is gated off
- `scripts/drift_detect.py`: **docstring only** — "CI runs drift detection with
  `secrets.GITHUB_TOKEN`" is dated to the period before 2026-10-19 and now names the credential that
  replaced it. No behaviour change; all 11 drift-gate tests still pass

### Fixed
- **S2-021 — the destruction gate printed the secret that justified it.** `retire_recovery_key.sh` phase 1
  printed the custody nonce three times, once inside a ready-to-run `RETIRE_PROOF=$NONCE …` line that also
  lands in shell history. Anyone with one copy and no off-host at all could read their own terminal, paste
  the number, and successfully `shred` the only identity that opens the off-device backups — the precise
  incident (S2-013) this script exists to prevent. Phase 1 now prints only a SHA-256 fingerprint, `NONCE`
  is overridable so the suite can inject a known value (grepping a random one passes either way), and
  phase 2 prompts with hidden input. Retire suite 15 → 20 cases. Case 4 was also rewritten because it had
  been passing on the *shape* rejection rather than the comparison it names; it now supplies a well-formed
  wrong nonce and requires the words `does not match the challenge`. Four mutations, each caught by its
  named case: printing the nonce (2 and 19), removing the hex-shape check (17), removing the placeholder
  refusal (16), disabling the prompt path (18).
- **Both custody flows now refuse placeholders by design instead of documenting them away.** A third
  instance of the same failure — `make backup-attest TOKEN=<the 32 hex it prints>` typed literally,
  `bash: syntax error near unexpected token 'newline'` — appeared in a reply that claimed placeholders had
  been removed, which is measurement trap 23: telling a human to edit a command is not a fix. `attest` and
  the retire path take the secret from a hidden prompt, name the placeholder text when they see it, and
  validate the 32-hex shape before comparing anything; `make retire-key` gained `RETIRE=1` so phase 2 needs
  no argument. `offhost_rehearsal.sh` also writes `HOWTO.txt` **into the packet**, with no angle brackets
  anywhere — the far machine's instructions should not depend on this machine's terminal, and a `$PWD` in
  that text was caught being expanded on the wrong host (case 56).
- **S2-020 — the backup suite could not run where it is scheduled to run.** Its own header says the guard
  cases need "jq only — these run anywhere", but cases 3, 4, 21 and 23 invoked `backup_state.sh` without
  `SRC`, defaulting it to `$REPO/terraform.tfstate` — gitignored, so absent from every checkout. Run under
  runner conditions, the merge commit would have been **red on four cases**, and two of those returned the
  expected exit code for the wrong reason (a missing input, not the guard under test). `SRC` is now an
  explicit input of `state_backup_guard.sh` too, forwarded to the backup script, and the lineage
  cross-check reads the *same* file it protects; the guard cases supply the synthetic populated state that
  already existed for case 9, and the identity cases (46-50) now execute in CI rather than skipping there.
  Measured runner-shaped census after the fix: **30 passed, 22 skipped, exit 0**; locally **56 passed, 0
  failed**. No behaviour change on this host — the default is still `$REPO/terraform.tfstate`
- **S2-019 — the custody challenge printed its own answer.** `offhost_rehearsal.sh pack` ended by echoing
  the nonce it had just encrypted to the off-device recipient ("for comparison only"). That nonce *is* the
  proof: recovering it on the far machine is what turns an attestation from an assertion into evidence.
  Printing it put the answer in terminal scrollback, IDE local history and this session's transcript, from
  any of which a machine holding no key could run `make backup-attest` and have `ATTESTED` recorded —
  while the gate kept refusing replays and looked entirely healthy. `pack` now prints only
  `token-sha256 <prefix>…` and honours a `TOKEN` override so absence can be asserted non-vacuously
  (case 52: value absent, fingerprint present, fingerprint equals the hash of the injected token).
  Reverting the fix in place makes the suite report `51 passed, 1 failed` naming the leak. **The harness
  was the second bug**: a first mutation run looked "undetected" because it printed an exit code without
  the census, and cases 51/52 had no `else` — a skipped case was indistinguishable from a passed one.
  Both now announce a skip (suite 50 → 56 cases)
- **S2-018 — another project's backup was passing this project's freshness gate.** A cron line added
  outside this session by the jolarca tree writes `terraform.tfstate.s17.*.age` into
  `/mnt/jol-backup/jol-state-backup` — the destination RB-08/RB-09 used until this change moved ours to
  `jol-control`. Every consumer
  picked "newest `*.age`", so its file satisfied our guard: measured live, `OK: newest snapshot is 0h old
  (< 24h) - nothing to do` exit **0** while our own snapshot was hours old, and `make backup-status`
  printed the foreign file as ours. A planted 2099 mtime also passed as `newest snapshot is -632713h old
  (< 24h)` — a negative age is below every threshold. All three consumers now pin the snapshot name to
  `<repo>-terraform.tfstate.*.age` and announce how many foreign files they ignored, treat a future mtime
  as UNEVALUATED rather than fresh, and compare the sidecar's `lineage` against the live state's — a
  mismatch forces a refresh, an absent lineage is refused as unidentified. Cases 46–50; each rule was
  mutation-tested (name pinning, future-mtime refusal, mismatch force, unidentified refusal) and every
  mutation was caught by its named case, with the guard restored byte-identically (`md5sum`) after each.
  **A bug in the fix was caught this way too**: the first lineage block printed "DIFFERENT inventory —
  refreshing anyway" and then fell through to exit 0, so case 48 asserts the forbidden phrase rather than
  only the code
- **The test suites littered the host they verify, and had been doing it for a year.**
  `tests/test_drift_gate.py` called `tempfile.mkdtemp` twice per run and removed nothing: counted on this
  host today, **182 `allowlist-*` and 286 `stub-*` directories** in `/tmp`. `tests/test_plan_gate.py`
  created its empty-plan fixture with `NamedTemporaryFile(delete=False)` and never unlinked it, leaving
  27 zero-byte `/tmp/tmp*.json`. Both are fixed — scratch dirs are registered and purged via `atexit`
  (so a *failing* run cleans up too, proven by running a deliberately broken assertion in a mirror tree:
  delta 0), and the plan fixture unlinks in `finally`. Verified by two consecutive `make test` runs with
  before/after counts: **delta 0 directories, delta 0 files**. This is not cosmetic: a leftover
  `allowlist-*` is a directory full of `*.yml` repository definitions sitting outside the repository,
  one `ls` away from being mistaken for the real `repos/` tree — and `*.age`/`*.decoded` artefacts are
  not gitignored here, so a harness that forgets where it put things is the exact mechanism that nearly
  committed plaintext state (S2-012)
- **A verification command this project recommended to the operator could not fail.** `age --decrypt -i
  <copy> <snapshot> | md5sum` — offered while checking whether the off-machine key copy worked — printed
  `d41d8cd98f00b204e9800998ecf8427e`, the MD5 of *empty input*, and exited 0, because the pipe absorbed
  the very failure it was written to detect. That is measurement trap 10, a rule this changelog had
  already recorded, broken again in prose rather than in code. RB-09 step 5 now carries a fail-closed
  rehearsal block (capture to a file, test the exit status, reject an implausible size and the
  empty-input digest, then shred the plaintext), and **measurement trap 17** names the pattern: the
  commands that reached a human were the broken ones — three times over (`backup.sh` that did not exist,
  `PROOF=<that-nonce>`, `CHALLENGE_DIR=/tmp`) — while every committed script held its own bar
- **S2-015 — an instruction in this repository corrupted the host crontab, and the checks meant to
  catch it passed.** RB-09 step 4 shipped with
  `sed 's|^\*/10 …|&; …state_backup_guard.sh >/dev/null 2>&1|'`; in a sed replacement `&` is the matched
  text, so the `&1` of `2>&1` pasted the original line into the middle of the result. Applied to jol's
  crontab it produced a malformed command cron would have run every ten minutes. The verification beside
  it reported `line count 12` and `guard occurrences 1` — both green — and truncated the line at 200
  characters; only a `diff` against the pre-change backup showed the damage. Restored byte-identically
  from that backup, reapplied with `awk` (string concatenation has no metacharacters), then verified by
  reading the whole line, by a diff with exactly one intended change, and by running the command under
  cron's own minimal environment (`RC=0`). **Measurement trap 18**: never verify a live-state mutation by
  counting matching lines
- **RB-09 step 4's cron line also pointed at a log file that does not exist**
  (`/opt/jol/data/logs/`, absent on this host), which would have made cron mail a failure every ten
  minutes. Now `>/dev/null 2>&1` plus journald, matching the convention `check-project-mounts.sh`
  documents in its own header — journald is persistent here and survives the church-tree log directory
  being missing. RB-09 also states plainly that those verdicts are a **pull** (`journalctl -t
  state-backup-guard`) with no alert channel reading them
- **`RB-09`'s fstab step omitted `systemctl daemon-reload`.** `mount` reads `/etc/fstab` directly and so
  succeeds anyway, which is why the omission stays invisible. Evidence, before and after: `systemctl show
  -p SourcePath,UnitFileState` returned **empty** for `mnt-jol\x2dbackup.mount` after a working manual
  mount, and reports `SourcePath=/etc/fstab`, `UnitFileState=generated` once `daemon-reload` has run.
  (An earlier version of this entry cited `ls /run/systemd/generator/mnt-jol-backup.mount` — that is a
  permanent false negative, because systemd escapes the dash: the unit file is
  `mnt-jol\x2dbackup.mount`. Query with `systemctl show`, not `ls`.) The step now reloads and checks the
  unit
- **S2-014 — the off-device backups are undecryptable in the scenario they were created for.** Measured
  with `findmnt --target` then `lsblk -no PKNAME`: the live state and **both** age private keys are on
  `nvme0n1`; the two `age`-encrypted snapshots are on `sdb`; no key exists on `sdb` or off the machine.
  So an `nvme0n1` failure destroys the state and every key together, leaving ciphertext on `sdb` that
  nothing can open — the exact device the copy exists to survive. Nothing in the repository contradicts
  this: `backup_state.sh` prints `device-check : verified-different: state=nvme0n1 backup=sdb`, which is
  true and beside the point, because it compares the plaintext to its copy and never the keys to the
  ciphertext. Recorded as an open finding with the placement table, and RB-08's Limitations name it
  explicitly — a check that measures the right-looking pair is more dangerous than no check, because it
  closes the question. Not fixable by a script: a copy that is provably elsewhere is by definition not
  visible here
- **The retirement gate built for S2-013 had S2-013's own hole.** It proved only that *a* private key
  recovered the challenge nonce — while the local copy of that key was still present and no second copy
  existed. The operator's `cp` of the freshly minted identity to the second disk then failed with
  `Permission denied` (that volume's root is `root:root 755`), leaving exactly one copy, and the ceremony
  would still have completed, printed a success about off-host proof, and destroyed the key. The gate now
  refuses unless the challenge directory resolves to a **different physical disk** than the identity, and
  treats an unresolvable device as a refusal rather than a warning — for an irreversible operation,
  unverified is a no. It prints the separation it relied on. Cases 13–15 added (15 total)
- **Two instructions in RB-08 were actively misleading.** The direct-invocation example told the operator
  to encrypt to `age18457…`, which is the **destroyed** identity — following it now yields a snapshot with
  one live key — so it reads the recipient from `~/.config/age/offdisk-recipient.txt` instead. And
  `CHALLENGE_DIR=/tmp` was suggested in a step whose entire point is that `/tmp` is the wrong disk; a
  sentence left dangling mid-edit was caught only by re-reading the published file
- **S2-013 — a recovery identity was destroyed before any off-host copy of it existed**, following
  RB-08's own step 1. No data was lost: the one off-device snapshot opens with AGE-1 (`195,121` bytes,
  md5 `b25b8821…`, matching the live state), and five other age identities plus two session transcripts
  were each *attempted against it* and returned zero bytes. What was lost is the second custody path, so
  the snapshot is again reachable only by a key on the same machine as the state — the condition S2-012
  was opened to remove. `docs/SECRETS_INVENTORY.md` records AGE-2 as destroyed rather than deleting the
  row, and adds AGE-3 as the pending replacement. The root cause is an instruction defect, not operator
  error: three ordered actions were packed into one lettered step and the irreversible one was rendered
  as a standalone copy-paste line, so the fix had to be a gate, not a paragraph
- **The backup suite's guard cases were passing vacuously, twice over.** Every guard case supplies an
  invalid `RECOVERY_KEY`, so any later failure also returns the expected `RC=1`: with the wiped-state
  requirement deleted, case 7 was stopped by the *device* check and still passed. Adding a refusal-text
  assertion was not enough either — deleting only the in-repo refusal's `exit 1` still prints that text
  while the next guard stops the run, so case 4 credited a different control with its pass. The helper now
  requires that `age` was never reached **and** that every `FAIL:` line carries the phrase belonging to the
  case under test. Both rules are proven by mutation, not argued
- **RB-08's sidecar claimed `off-host-verified: yes` for a key whose location it had never tested.**
  The field was derived from the exit status, which only means *a second identity decrypted the file*.
  Because that identity is `~/.config/age/state-recovery-20261027.txt` on the same host as the state,
  every sidecar written so far asserted off-host custody while the condition was false. Now three
  separate fields: `recovery-key-decrypted` (proven), `recovery-key-location : NOT CHECKED` (not proven,
  and unprovable by a local script), and `device-check`. The pattern worth remembering — the one word
  carrying the risk was the one word nothing could test
- **A device check was documented as impossible while sitting unused.** The Limitations said the script
  "does not verify that `sdb1` is a different physical device (it checks writability only)"; `findmnt
  -no SOURCE --target` into `lsblk -no PKNAME` resolves the disk under a path with no privileges,
  yielding `nvme0n1` versus `sdb` here. The script now **refuses** a same-disk destination — which
  rejects the layout this host actually had before any of this (state `p8`, backups `p6`, one die) — and
  warns plus records `device-check: unevaluated` when resolution is impossible, rather than passing
  silently
- **Both halves of RB-08 assumed a mount only a desktop session creates.** `/etc/fstab` holds zero
  `media` entries and the systemd unit is generated from `/proc/self/mountinfo`, so after a headless boot
  or a crash `/media/jol/32f7e56a-…` does not exist — and the Restore half globbed that exact path, where
  an empty result reads as "the off-disk backups are gone". Each half now preflights the mount, names the
  `udisksctl mount -b /dev/sdb1` recovery, and distinguishes *not mounted* from *nothing there*. The
  durable fix (a boot mount) is a host change and is left to the owner
- **The device table described the destination without saying what it is.** `sdb` is a Seagate
  ST9320423AS, 298 G, SATA, `ROTA=1` — a 2012-era spinning laptop drive sharing the state's supply and
  backplane. It removes single-NVMe risk and nothing else; SMART health is unverified because `smartctl`
  needs a password. Recorded as "a real improvement and a weak end state"
- **`apply.yml`'s step comment understated its own suite** ("18 cases" against 20, then 23) and implied a
  CI coverage a pull request does not receive. Corrected, with the trigger condition stated inline
- **A test-harness stub silently voided the check it was written to cover.** The `lsblk` stub read `$1`,
  which is `-no` rather than the device, so it returned nothing, the device check never ran, and the
  same-disk case still exited 1 for an unrelated reason (the deliberately fake identity file). Right
  exit code, no proof. Caught only because the assertion also demands a verdict line, which came back
  `no-verdict`; the case now additionally proves the stubs resolved
- **RB-08's Create-half list carried two items numbered `2.`** after a preflight step was inserted, and
  cross-references pointed at the wrong step numbers; the Restore-half sidecar field name was left
  pointing at the retired `off-host-verified`. Corrected against the rendered numbering
- **S2-012** `terraform.tfstate` was destroyed during testing this session — a `mktemp -d` directory
  was created but never entered, so `printf … > terraform.tfstate` and a later `rm -f` acted on the
  live inventory. Recovered **byte-exactly** from `/opt/jol/backup/tfstate/…20261020T125251Z.age`:
  md5 `b25b88219552d3d5a47c749e2b3d85a5`, serial 306, lineage `25425c0f`, 119 instances — confirmed
  independently by `terraform state list | wc -l` → 119 and `make state-gate` → `SAFE` exit 0.
  Recorded in full, including cause, because the recovery succeeding is not the finding: no runbook
  named the backup set and no automation refreshed it
- **S2-012 follow-ups — three further defects, all in commands this session wrote, all caught by
  executing them rather than reading them.** (1) RB-08's backup verifier reported success for a
  backup with **one custody path**: passing the on-host identity as the "recovery" identity still
  printed *"decryptable by both keys"*, a green assurance of redundancy that would survive nothing
  the host does not already survive — the two public keys are now compared and equal ones refused
  (exit 1). (2) An earlier draft called `age --list-recipients`, which **does not exist in `age`
  1.1.1**: it encrypted successfully, then died *before* verifying. (3) A destination named
  `/secure/offhost` never existed and was written into a command without being checked; the real
  second disk is `sdb1` at `/media/jol/32f7e56a-…` with 270 G free. Separately, the recovery
  identity had been minted into `/tmp` on the strength of a **false** justification ("wiped on
  reboot") — measured here as on-disk (`/dev/nvme0n1p3`) with policy `D /tmp 1777 root root 30d`, so
  it survives a reboot and reaps the key after 30 days: right conclusion, wrong reason, the worst
  kind of guidance. It now sits at `~/.config/age/state-recovery-20261027.txt` (mode 600), verified
  byte-identical by `sha256sum` **before** the `/tmp` copy was shredded. A pasted three-line `sudo`
  block also executed only its first line, leaving the destination `root:root 755` and unwritable
  while appearing to have succeeded
- **S2-012 follow-ups 4–6 — defects in the backup script found only by running it.** (4) It
  required `RECOVERY_KEY`, an identity **file**, for its second verification, so following the
  runbook's own step 1 — moving that key off the host — made the script unrunnable for the exact
  scenario it exists for. It now accepts either `RECOVERY_KEY` (full proof) or `RECOVERY_PUB`
  (recipient recorded, off-host path reported as **`NOT VERIFIED`**, never as a pass). (5) The output
  name uses a **one-second** timestamp and `age` overwrites an existing file without comment, so two
  backups in the same second silently destroyed the earlier snapshot; found by running the script
  twice under a stubbed `date`. It now refuses to overwrite, and the refused re-run was confirmed to
  leave the original byte-identical. (6) A **garbage `SRC`** still produced a well-formed 5 KB `.age`
  on the backup disk before the final check complained; the source is now validated with
  `jq` **before** any write. Seventeen cases now pass against the script as published in
  `docs/runbooks.md`, each asserting exit code, verdict line, the number of artefacts left in the
  destination **and** whether any plaintext survived — the last two of which are what the earlier
  fourteen failed to notice. No harness for it is committed; see Fixed below
- **RB-08's backup script leaked PLAINTEXT Terraform state and passed vacuously in two places — found
  by an independent review, not by the 14 cases that preceded it.** (1) The verification step wrote
  `$OUT.decoded` at the ambient umask (`0002` on this host → mode `664`, other-readable) and left it
  behind on every failure path, because `rm -f "$DEC"` sat after a call that can fail under `set -e`
  and because `trap … RETURN` does not fire when a function calls `exit` or when `set -e` aborts
  mid-function. That is the credential inventory of 40 repositories in plaintext next to the ciphertext,
  produced by a script this changelog had just called "fail-closed". Fixed with `umask 077`, a single
  `EXIT` trap over every temp, and removal of the artefact unless the run fully succeeded. (2)
  `state_gate.py` was invoked without pinning its config directory, so from a foreign CWD it judged a
  valid inventory against no configuration at all and answered **`SAFE` over zero resource blocks** — a
  false pass, worse than the honest refusal assumed. `REPO` is now pinned, derived from neither `SRC`
  nor `CWD`. (3) A wiped state (`resources: []`) passed the pre-write check and was encrypted as a good
  backup; the guard now also requires a string `terraform_version`, a string `lineage`, a numeric
  `serial` and at least one resource — that exact shape being what this host produced when its
  inventory was destroyed. (4) `NOT VERIFIED` exited **0**; it now exits **2**, per the repository's
  0-safe / 1-refused / 2-cannot-check convention, so a scheduler cannot read an unproven control as
  green. (5) Refusing a same-second collision then **deleted the original backup** — the cleanup added
  to fix (1) removed `$OUT` on any failure whether or not this run created it. A `CREATED` flag gates
  it, and a case now asserts the original's sha256 and the destination's file count are unchanged across
  a refused re-run: a fix is verified by the case that attacks it, not the case that motivated it
- The Create-half artefact name now follows the existing `jol-control-terraform.tfstate.<stamp>.age`
  convention, and `DEST` is refused when it resolves inside the repository — `*.age` and `*.age.decoded`
  are **not** gitignored here, so a `DEST=.` run would have left an untracked, other-readable plaintext
  state one `git add -A` away from a commit AGENTS.md forbids
- `docs/runbooks.md` RB-08's device table contradicted itself and its own neighbouring files: the row
  for the separate disk was annotated "all three rows are `nvme0n1`", and `sdb1` was listed as "285 G
  free" when 285 G is its **size** and 270 G is free. Both corrected; the column is now "Same physical
  disk as the state?" with the reference row marked as such
- Two claims that outran their evidence were narrowed to what is actually checked: the script verifies
  that the two recipient **strings** differ (not "cryptographic independence", and not the *location*
  of either key), and the PASS line now says a distinct identity opens the file rather than implying the
  off-host scenario is covered while the identity is still in `~/.config/age/`
- Measurement trap 13 recorded: **a broken test harness reports itself as a broken product.** Building
  the RB-08 verification produced five false signals that each invited a fix to the wrong layer —
  `RC=127` because an expanded `VAR=value` is parsed as a *command name*, not an assignment (use
  `env`); `age` falling back to **stdin** when handed an empty filename, so the test sat in process
  state `T` after `SIGTTIN` instead of failing; `pkill -f` matching the command line of the shell
  issuing it and killing the session with **137**; a glob that returned nothing feeding an empty
  argument onward; and two assertions satisfiable only because a previous case left a file behind
- **S1-012** `.github/workflows/plan.yml`: see Changed above — the `Validate & Plan` job's
  `Destroy / Replace Gate` could never pass in CI. Confirmed pre-existing, not a regression from
  this branch: the same step failed on run `39479272770` (`bc05f3d`, 2026-10-20) with identical log
  text, established by comparing step-level conclusions rather than the shared "failed" verdict
- **S1-011** `scripts/state_gate.py`: `worst_state()` declared a parameter named `forced` while its
  per-file listing referenced a module-global `root` that does not exist, so any directory holding
  **more than one** state file raised `NameError` and the gate answered UNEVALUATED (exit 2).
  Fail-safe, but blind exactly where duplicate inventories live, and the documented "verdict is the
  WORST of them" rule was unreachable code — a healthy state beside a 0-byte one reported
  UNEVALUATED instead of REFUSED. Pre-existing at HEAD, reproduced against
  `git show HEAD:scripts/state_gate.py`; no fixture had ever held two state files
- **S2-007** `scripts/state_gate.py`: stale-copy detection filtered on
  `x.suffix in (".backup", ".bak")`, so `terraform.tfstate.backup_20260930_213529` was invisible —
  the one copy on this host that actually diverges (serial 301, still holding
  `github_team.security` after live state dropped it at serial 306). The NOTICE fired on the
  near-identical copy and stayed silent about the one that could revert inventory. Now matched on
  name, with directories and dotfiles excluded
- **S2-008** `Makefile`: `lint` depended on `fmt`, i.e. `terraform fmt -recursive`, so running the
  documented verification command silently rewrote `repositories.tf` inside a `lifecycle` block
  holding `prevent_destroy = true` — an edit AGENTS.md §4 gates behind explicit in-session approval
- **S2-009** `repositories.tf`: trailing-comment alignment in the `github_repository.repo`
  `lifecycle` block, broken since `226fa5c`, made `terraform fmt -check -recursive` exit **3** at
  HEAD. Whitespace only — `git diff -w --numstat` is empty and both `prevent_destroy` and
  `ignore_changes` are byte-identical. No CI job enforces formatting, which is why it survived four
  commits; adding one is recommended and still open
- **S2-011** `docs/drift-findings.md`: the index omitted S1-009, so an index-only reader counted
  eight S1 findings and missed the one stating that seven governance-tier repositories have branch
  protection in state and none on GitHub
- Six overstatements introduced by this session's own closure work, found by reviewing the diff
  rather than trusting the narrative, and corrected in `AGENTS.md`, `docs/drift-findings.md` and
  `docs/runbooks.md`:
  - **`||` does not fall back on an expired token.** It substitutes only a falsy operand, and a
    stored-but-dead PAT is a non-empty string. Every "unset, deleted **or lapsed** → falls back →
    `github_count: 39" sentence was wrong for the lapse case, which instead produces
    `HTTP 401: Bad credentials` with **no `github_count` line at all** (measured with a deliberately
    invalid value). RB-07 now carries a failure-mode table separating the shapes, because the old
    text would have sent the next operator grepping for a string that never appears
  - **The fallback branch has never executed in CI.** Runs `39254606046` / `39254610945` ran at
    `headSha=ba99034`, whose published file bound `secrets.GITHUB_TOKEN` alone, so they evidence the
    blind token, not the expression; and the secret predates the first run of the new expression by
    nine minutes. The claim "proving the fallback shape" is replaced with the inference it actually
    is, plus why measuring it (deleting an unrecoverable secret) is not worth the cost
  - The findings-register **index row** still said "CI still cannot evaluate" two screens above the
    body that declared it closed, and `drift_detect.py`'s docstring said the same in the present
    tense. An auditor reads the index first
  - RB-07's scope table offered a classic `repo` token as an acceptable alternative, which
    contradicts the `main.tf` policy comment this same change strengthened — a write-capable
    credential in CI is a finding plus a risk acceptance, not a deviation note
  - RB-07's inventory paragraph inferred "the host credential carries no scopes" from an
    **empty grep**, which was a swallowed pipe: `gh auth status` shows an OAuth token holding
    `admin:org`. The `404` is about caller type (GitHub App only), full stop. The episode is
    recorded in RB-07 as a lesson about reasoning from an absence
  - Minor precision: `pushed_at` is one second after `created_at`, not equal to it; step 4's run-id
    capture lacked `--event workflow_dispatch` and could have grabbed a PR run where the drift job
    never executes; step 2 said "in a subshell" for what is a per-command assignment
- Two documented instructions that could not be followed, found by **executing** them rather than
  reading them. `docs/runbooks.md` RB-07's scheduled-run guard used a `jq` expression that adds a
  number to a string, so it errored inside `$( )`, left both shell variables empty and printed a
  blank verdict while still exiting 0 — an inert check that reads as a judgement. Replaced with a
  tab-separated interpolation and run verbatim out of the runbook file to confirm its output.
  RB-03 step 5 also told the operator to update a rotation log in `jol-secrets`, a repository with
  no commits at all (`size=0`, `pushed_at` one second after `created_at`); it now states that, says where the
  record goes instead, and S1-009 carries the consequence for the incident-response path
- S1-002 residual closed — the scheduled Compliance Scan can now evaluate the whole allow-list.
  `ORG_READ_TOKEN` was minted and stored as a `jol-control` repository secret, and CI run
  **39255407378** (at `1a66742`) reports `"evaluated": true`, `"github_count": 40`,
  `"matched_count": 40`, `NO DRIFT — All 40 repos match` where the runner token's enumeration
  returned 39 rows and could not conclude absence at all. The two dispatch runs at the preceding
  commit (`39254606046`, `39254610945`) evidence the blind token **only** — their `head_sha` predates
  the binding — and the `||` fallback branch has never executed in CI; both are now stated as
  inference rather than as proof. The register also now carries the measured scheduled-run
  history — every scheduled run from 2026-09-26 through 2026-10-17 failed, the first two as a false
  DRIFT and the last two as an honest UNEVALUATED — replacing S1-002's understated "red for six
  days", and notes that no *scheduled* run has evaluated the allow-list yet (first due
  2026-10-24). `AGENTS.md` §2's "CI drift detection verifies the whole allow-list" row is restated
  accordingly, together with the credential dependency it created
- ADR-013 (`jol-docs#4`) revised twice before acceptance, both times because verification caught
  the draft rather than a reviewer: **v0.2.0** conformed the heading to the registry's short-title
  style after CI run 39028870034 failed `markdownlint` MD013 on a 123-character sentence heading
  (local checks had only measured file size and link resolution), and reversed the Ordering
  decision from relax-then-accept to **accept-then-relax** — the draft contradicted S1-008 in this
  repository, and removing a review control should be authorised by the decision record instead of
  documented after the fact. **v0.3.0** re-measured the evidence after reports claimed the
  relaxation was already applied: it was not. The ADR also now carries an implementation-status
  note stating that the capacity test its Decision promises does not exist in `scripts/` yet
- Six assertions received in one turn were tested and refuted — that the 19 rulesets had been
  relaxed, that `jol-docs#4` merged at `2026-10-19T13:10:38+03:00` (it is
  `state=open, merged_at=None`), that an ADR-014 existed at `d2593f8…`, that labels had been
  created in eleven repositories (11 of 12 declaring repositories are still broken), that two
  enforcement gates had been added to `jol-control` (`scripts/` still holds six files), and that
  `jol-auth` alone remained with "15 missing" labels (it is missing three). None of the cited shas
  exists in either clone, in either `--all` log, or on either remote
- Eleven GitHub labels created in `jol-hub` (`dependencies`, `github-actions`, `terraform`,
  `infrastructure`, `ci`, `ci-cd`, `docker`, `backend`, `frontend`, `javascript`, `python`) so the
  ten labels its `dependabot.yml` names can resolve, verified by cache-busted read-back (20 labels
  present, `missing=[]`) rather than by the POST echo. Not retro-applied: `jol-hub#151` keeps its
  old notice until the next dependabot PR, and `@dependabot recreate` is a write into another
  repository that needs the owner's word
- S1-008 measured against S1-003: **13 of the 24 repositories still publishing a dead
  `SECURITY.md` address also carry an unsatisfiable ruleset** (jol-ecommerce-engine,
  jol-infrastructure, jol-rag-server and the ten `jol-site-*` spokes), so the contact sweep
  would deliver PRs mergeable only by the admin bypass S1-007 criticises. `jol-dr` cannot be
  assessed at all — rulesets 403 for private repositories on this plan. Register order now puts
  S1-008 before the sweep. The recommendation added is sequential rather than either/or: relax
  the 19 rulesets to match the declared solo posture first (reversible, RB-06), then write the
  ADR against an already-consistent fleet — because option (b) cannot cover `jol-dr` and option
  (a) as it stands would import three different ruleset shapes, one of them named `~master`
  while applying to `~DEFAULT_BRANCH`. Not executed: changing enforcement on 19 repositories
  needs the owner's decision.
- S2-006 — `jol-hub/.github/dependabot.yml` assigns `dependencies`, `infrastructure` and
  `terraform` labels that do not exist there (all three 404; its label set is the nine GitHub
  defaults), so every automated dependency PR arrives unlabelled and the distinction between a
  PCI-relevant Terraform bump and a routine npm bump is never made. Surfaced by a browser read
  of `jol-hub#151`, confirmed against the file on `origin/main` and the labels API.
- S1-007 — one more avenue closed honestly rather than assumed: an unauthenticated browser
  renders the PR header, conversation and `21 / 21 checks OK` but not the merge-status widget,
  and `.github` has no open PR to inspect. Reading the merge box needs the owner's signed-in
  session; recorded as a verified negative result so nobody re-attempts it.
- `docs/drift-findings.md` S1-008 — **the control plane does not control enforcement.** A scan
  of all 40 public repositories found **21 hand-configured rulesets across 19 repositories
  requiring at least one approving review and/or code-owner approval** — exactly what
  `solo_mode = true` was introduced to omit, and unsatisfiable with one org member. Confirmed
  live: `jol-hub#151` (a dependabot PR) sits at `mergeable_state=blocked` with
  `requested_reviewers=0` and will never merge on its own merits. `terraform apply` cannot
  revert or converge any of it (no `github_repository_ruleset` resource exists), and
  `scripts/drift_detect.py` compares names and visibility only, so the divergence is invisible
  to every check this repo runs. `AGENTS.md` §2's first row was corrected accordingly: "reviews
  are not enforced" was true of the baseline and misleading about the fleet. Also noted:
  `jol-hub` carries two rulesets plus classic protection at once — `count=0` classic against
  `count=1` rulesets, strictest wins — and one ruleset named `~master` applies to
  `~DEFAULT_BRANCH`.
- `docs/drift-findings.md` S1-007 — three further hypotheses eliminated with evidence: no
  merge commit or unsigned commit in `.github` PRs #7/#8/#9 (every commit single-parent,
  `verified=true reason=valid`), no unresolved review threads, and a peer comparison showing
  `blocked` arises elsewhere for legitimate reasons (`jol-docs#3` clean, `jol-hub#151` blocked
  by a real approval requirement). `.github`'s empty requirement list is therefore stranger,
  not explained; it needs the web-UI merge box or GitHub Support.
- `branch-protection.tf` deferred rulesets to "`docs/runbooks.md` RB-04", but RB-04 is
  *Update Compliance Gate* and says nothing about rulesets. It now points at the new RB-06 and
  states the two facts an operator needs before touching that area: `.github` is guarded by a
  hand-set ruleset no resource here manages, so neither `make drift` nor `terraform plan` can
  see it, and the `404` from the classic protection endpoint means ruleset, not unprotected.
  Comment-only change, verified inert: `terraform validate` Success, offline plan reports
  `0 to add, 0 to change, 0 to destroy` and `plan-gate` PASSED. Separately observed and left
  alone: `terraform fmt -check` flags `repositories.tf` as non-canonical, a pre-existing
  deviation in a file this change does not touch, so `make fmt` would widen the diff.
- `AGENTS.md` §2 now records what this session proved about `journeyoflife-org/.github`, so
  the next session cannot re-derive the wrong version: the org defaults repository sits outside
  the allow-list (41 live, 40 declared — the delta is `.github`) and is protected by a
  hand-configured ruleset no Terraform resource manages; pull requests there need an
  administrator bypass **for a reason nobody has identified**, with the eight eliminated
  hypotheses listed and an explicit instruction not to repeat the retracted code-owner claim;
  and the shared CI library scanned its own definition repository while one workflow was
  uncallable-by-construction for ten spokes. The "still genuinely enforced" sentence is now
  scoped to the Terraform-managed repositories, because `.github` is not one of them — an
  unqualified version of that sentence is precisely the kind of claim §6 says gets the rest of
  the pack discounted.
- One new defect found while verifying a claim written minutes earlier:
  `branch-protection.tf:122` defers rulesets to "`docs/runbooks.md` RB-04", but RB-04 is
  *Update Compliance Gate* and says nothing about rulesets. Reported rather than edited — a
  `.tf` comment is outside this commit's stated scope.
- `.github` PR #9 (`4a94b30`) stops the shared workflow library from scanning the repository
  that only defines it, and makes `compliance-check.yml` callable. Three files filtered `push:`
  by path but left `pull_request:` unfiltered, so nine checks failed on every pull request to
  `.github` (`CodeQL could not process any code written in JavaScript/TypeScript`; unresolved
  `frontend/pnpm-lock.yaml` cache path; `No file … matched to [data/requirements.txt or
  **/pyproject.toml]`), and ten spokes were calling a workflow that never declared
  `workflow_call` even though its own jobs read `inputs.repo-layout`. No `workflow_call`
  interface changed, so no consumer breaks; each touched file is re-parsed and asserted to keep
  `workflow_call` and gain `pull_request.paths`. Recorded as S1-006 — consumer-side proof is
  still owed, because the historical failed run cannot be rerun.
- S1-007, and a retracted diagnosis. With the nine failing checks gone, one passing check, zero
  required approvals, valid signatures, attributed authors and an up-to-date branch, a pull
  request to `.github` is *still* `mergeable_state=blocked` — so the earlier conclusion that the
  code-owner rule caused it was wrong. The eight hypotheses eliminated are tabulated; the one
  parameter toggled during testing was restored to `true`, leaving no unmanaged change; and the
  public comment on PR #8 that asserted the wrong cause is corrected in-thread. Until the
  merge-box text or GitHub Support names the requirement, every change to the org-wide security
  policy or the CI library needs a recorded admin bypass — three in one day is an absent control
  with paperwork, not an enforced one.
- Two claims this session published and then retracted against better evidence: that
  journeyoflife-org/.github had *no* branch protection (it has an active ruleset — the legacy
  endpoint simply does not report rulesets), and that Terraform state held 11 branch
  protections where the register says 39 (the resource appears twice: governance 11 + standard
  28 = 39, with 40 repositories; AGENTS.md was right). Also repaired: a `.github/CHANGELOG.md`
  entry whose backticked terms were executed by bash through an unquoted heredoc delimiter,
  leaving sentences like "lives on , which has a null MX record" on a public branch — fixed in
  `4f06ed1`, with a backtick-balance assertion added to the procedure.
- `journeyoflife-org/.github` PR #7 **merged** as squash commit `c01de1b`, replacing every
  undeliverable role address in the organization-wide `SECURITY.md`, `SUPPORT.md` and
  `CODE_OF_CONDUCT.md` with channels that deliver; verified on `main` that all three now hold
  zero `@journeyoflife.org` / `@journeyoflife.lt` addresses. It orders private vulnerability
  reporting ahead of e-mail and withdraws the `SECURITY.md` claim that pull-request review and
  code-owner approval protect `main` — they are configured, not enforced, while one
  maintainer holds the organization.
- `journeyoflife-org/.github` PR #8 **withdraws the published donation link** from
  `.github/FUNDING.yml`, `.github/ISSUE_TEMPLATE/config.yml` and `SUPPORT.md`, on the owner's
  decision to remove rather than repoint. The only donation path the organization advertised
  resolves to a registrar parking lander (114-byte redirect to `/lander`) and the donation
  widget is never mounted in code, so GitHub was rendering a third-party advertising page as
  the **Sponsor** button on every repository in a charitable organization whose own
  `SECURITY.md` places donor records in PCI-DSS scope. The evidence and the condition for
  re-adding are written into `FUNDING.yml` so the link is not restored from memory.
  `github: [journeyoflife-org]` was left in place — it answers 200, not 404 — with its sponsor
  tiers explicitly unverified. S1-004 is now PARTIALLY CLOSED: the broken affordance goes, the
  inability to accept a donation online does not. The PR sits at `mergeState=BLOCKED` under
  S1-005, the second merge in one day needing the same bypass.
- `docs/drift-findings.md` S1-005 — why #7 needed `--admin`: ruleset `protect-main` requires
  code-owner review, `CODEOWNERS` resolves to the `security` and `devops` teams, and their only
  member is the PR author, whose own approval GitHub does not count. The requirement is
  unsatisfiable rather than unmet, which `.github/CHANGELOG.md` had already foretold on
  2026-09-12 while also stating that the admin bypass is not an approved merge path — so the
  bypass is recorded as a comment on the PR, and the durable fix is either to align the ruleset
  with `solo_mode` or to complete the solo-mode exit.
- `docs/drift-findings.md` S1-004 evidence extended: the donation widget is never mounted
  (`master-site/src/app/donate/page.tsx` reads `DonationWidget deferred`), the component's types
  declare no provider and no submit, and no site domain is configured anywhere — so no donation
  path exists in code either, and the recommendation is removal, not repointing.
- `docs/drift-findings.md` — a process slip recorded rather than buried: the `.github` edits
  were made from a clone 8 commits behind `origin/main`. The pre-flight concurrency check
  inspected dirty files, unpushed commits and worktrees but never fetched, so it proved the
  working copy current instead of the remote. Verified afterwards that the unfetched commits
  touched only `.github/workflows/*` and none of the edited files. A clean tree is not a
  current tree.
- `jol-hub` was the only repository on the host carrying local identity keys —
  `user.name = jol` plus a `user.email` that outranked the estate include. Both unset, so it
  now inherits `Gintaras Kazlauskas <journey4oflife@gmail.com>` like its siblings; its 17
  unpushed commits are untouched. A scan of all three estates found no other local `user.*`
  key, and a stray world-readable `~/.gitconfig.d/jol.tmp` left by an aborted switch attempt
  was removed (the three estate files are mode 600).
- Host git identity: `--global user.email` had been pointed at
  `journey4oflife+jol.dev@gmail.com` before that alias existed on the GitHub account, which
  would have made every new commit unattributable and — with `required_signatures` and
  `enforce_admins` enforced on `main` — unpushable, while also reassigning the PCI-scoped
  `/opt/jolarca/` tree to a church-project mailbox. Reverted to `journey4oflife@gmail.com`
  and verified: `jol-control` and `jolarca` resolve to the verified address, `/opt/viavitae`
  still resolves to `architects@via-vitae.com` through its includeIf. See S2-005.
- Host git identity for `/opt/jol/` was moved to GitHub's ID-prefixed noreply address and
  **reverted the same day after the push was refused**, which is how the rule was established
  by measurement instead of assumption. Three signed commits authored by
  `227570927+JourneyOfLife@users.noreply.github.com`, signed with the fleet's own
  `609F7926A8254CDB`, produced
  `GH006: Protected branch update failed … Commits must have verified signatures. Found 3
  violations` on `main`. Same key, same repository, same protection, and the only difference
  from the fleet's whole history is the author address — so GitHub verifies a signature only
  when the author email is a **verified email on the account owning the key**, and the noreply
  form is not in `gh api user/emails`. `~/.gitconfig.d/jol` now holds
  `journey4oflife@gmail.com` with that reasoning written into the file, and the noreply switch
  is recorded as a future improvement gated on a UI-only step (`POST /user/emails` → 404 for
  tokens). Estate isolation is unchanged and verified: each of `/opt/jol`, `/opt/jolarca` and
  `/opt/viavitae` names exactly one include file, and `/opt/jol/` does not match
  `/opt/jolarca/`.
- The per-tree `includeIf` migration went through an intermediate fail-safe state the same
  day: the blocks were installed, withdrawn when `gh api user/emails` showed neither alias was
  verified, then re-enabled once the noreply route removed that dependency. One empty probe
  commit carrying the unverified alias was made on local `main` and unwound with
  `git reset --mixed` — not `--hard`, which would have discarded the six uncommitted files in
  the tree — with the dirty-file count and a file checksum confirmed afterwards.
  `git rev-list --count origin/main..HEAD` stayed at `0`; nothing was ever pushed with the
  alias.
- Diagnosis recorded for a misleading failure: an org-2FA `403` on `gh api
  orgs/journeyoflife-org` was not the organization locking anyone out. `gh` had switched the
  active account to `IterVitae`, which is not compliant with the org's secure-2FA requirement.
  Check `gh api user --jq .login` before believing any `403` about org resources; recovery is
  `gh auth switch -h github.com -u JourneyOfLife`. JourneyOfLife reports
  `two_factor_authentication = true` and the org reads fine again, with `billing_email` still
  on the billing channel. Remaining roster issue: `IterVitae` must be made compliant or
  removed from the organization.
- A claim this session recorded as "refuted" is **retracted — it was correct**. GitHub does
  require the noreply author address to be added and verified under Settings → Emails before a
  signature over it verifies. The sample used to refute it (`jol-devops@3c8f9dcf`) is GitHub's
  own web-ui `Initial commit`: its verification payload reads
  `committer GitHub <noreply@github.com>`, so GitHub signed its own commit and it says nothing
  about a user key. `has_sig=true` with `reason=valid` was not sufficient evidence, and reading
  `committer` and the subject would have shown it. The jolarca-dev estate still authors as the
  noreply address and holds roughly 67 commits on no remote; if any jolarca-dev branch
  enforces `required_signatures`, those pushes meet the same refusal — recorded as a warning
  in `policy/contact-channels.yml`.
- Private vulnerability reporting is now enabled on **all 40 public repositories** in
  journeyoflife-org, closing the intake hole recorded in S1-003 (it was enabled on none).
  Two API traps are recorded in `docs/drift-findings.md` because they will recur: the verb
  is `PUT`, not `PATCH` — `PATCH …/private-vulnerability-reporting` answers a generic 404
  even with `permissions.admin = true`, with the preview header, and with a real JSON
  boolean, so a 404 here means wrong verb rather than no permission; and the read-back is
  cacheable (`Cache-Control: private, max-age=60`), so verifying immediately after a
  `204 No Content` still returned `{"enabled": false}`. Confirmation requires a
  cache-busted `GET` or waiting out the TTL — otherwise a change that landed looks like
  one that was silently discarded.
- `scripts/drift_detect.py`: the weekly Compliance Scan has failed since run 37107745958
  (2026-10-03) reporting `in_defined_not_github: ["jol-dr"]`. **Nothing is missing:**
  `jol-dr` exists with `visibility=PRIVATE` (`gh api repos/journeyoflife-org/jol-dr`),
  and `make drift` on this host reports `NO DRIFT — All 40 repos match`. CI runs the
  checker with `secrets.GITHUB_TOKEN`, which can only enumerate public repositories, so
  the fleet's one private repo looked absent. The checker treated "cannot see" as "does
  not exist". It now distinguishes the three verdicts with distinct exit codes
  (0 evaluated-clean / 1 genuine drift / 2 unevaluated), and a private-blind or partial
  enumeration returns 2 — never 1, and never 0. Every declared absence is confirmed by a
  direct lookup, and a repository that answers a lookup while missing from the listing
  makes the run UNEVALUATED rather than DRIFT.
- `scripts/drift_detect.py`: fail-open path removed. Previously an empty listing or a
  failed `gh` call printed a warning and returned **0**, so a fully blind run reported
  the control as passing. A crash now maps to 2 as well
- `.github/workflows/compliance-scan.yml`: the drift step now labels exit 2 as
  `Drift detection UNEVALUATED` with the remedy named inline (an org-read token, or
  `make drift` on the control-plane host) instead of emitting the same generic failure
  as real drift; `validate-repos` runs the drift-gate self-test on every PR so the
  checker itself cannot go inert
- `AGENTS.md`: STOP condition 7 cited "state records `jol-dr` as `public` while GitHub
  reports it PRIVATE" as a *known live example*. That was reconciled by a `-refresh-only`
  apply on 2026-09-30; state (serial 306) records `visibility = "private"` and holds no
  branch protection for `jol-dr` — re-verified 2026-10-09 and reworded as history. Added a
  row to the §2 enforcement-truth table: CI drift detection cannot see private repos, so
  its verdict is UNEVALUATED, not a pass. Registered as S1-002 and S2-004 in
  `docs/drift-findings.md`

## [1.1.3] - 2026-09-30

### Added
- `docs/drift-findings.md` — drift findings register tracking divergence between
  Terraform state, configuration, and live GitHub state. Severity levels: S0
  (stop-work), S1 (fix before apply), S2 (fix soon). Records S1-001 (private
  repo branch protection, FIXED), S2-001 (stale contexts, FIXED), S2-002
  (non-existent team references, FIXED), S2-003 (local state, OPEN/RA-03),
  plus three resolved findings from the refresh-only reconcile
- `docs/solo-mode-exit.md` — exit criteria and transition checklist for
  disabling `solo_mode`. Four sections: team structure, CI/CD infrastructure,
  compliance posture (marked DONE 2026-09-30), and approval workflow. Includes
  pre-flight verification commands, rollback procedure, and notes on decorative
  team assignments and empty contexts

### Changed
- `repos/*.yml` (39 files): cleared `required_status_checks.contexts` to `[]`.
  Contexts like `ci / test`, `codeql-analysis`, and `dependency-review`
  referenced CI workflows that do not exist in those repos. Only `jol-control`
  retains contexts (`Validate Repo Allow-List`, `Policy Compliance Check`)
  matching the check-run names emitted by `compliance-scan.yml`. While
  `solo_mode = true` makes contexts inert, clearing them prevents merge blocks
  when `solo_mode` is eventually disabled
- `repos/*.yml` (40 files): updated team references to existing teams:
  `platform-admins` → `security`, `developers` → `devops`, `auditors` →
  `backend`. The previous team names do not exist in the organization
  (verified: `backend`, `data`, `devops`, `frontend`, `security`). Team
  assignments remain decorative until `github_team_repository` Terraform
  resources are provisioned
- `docs/architecture.md`: Team Access section updated to reference existing
  teams, with a note that team-repository bindings are not enforced via
  Terraform and assignments are decorative

### Fixed
- S2-001: required status check contexts no longer reference non-existent CI
  workflows. When `solo_mode` is disabled, empty contexts will not block merges
- S2-002: team references in `repos/*.yml` now point to teams that actually
  exist in the organization
- S2-003: local Terraform state documented in `docs/drift-findings.md` as an
  open finding with RA-03 risk acceptance. No infrastructure change; mitigation
  path (HCP Terraform migration) documented in `docs/solo-mode-exit.md`

## [1.1.2] - 2026-09-30

### Changed
- `apply.yml` no longer plans or applies in CI. `dev-validate` is now a
  validation-only preflight (YAML validation, `terraform init`,
  `terraform validate`, plan-gate self-test) and the misleading empty-state
  `terraform plan` step was removed. `staging-apply` and `prod-apply` are gated
  behind `vars.TF_REMOTE_STATE_ENABLED == 'true'`, and each now runs
  `scripts/plan_gate.py` before applying
- `docs/change-management.md`: the Approval Matrix "Environment Gate" column is
  labelled target design, with the verified absence of any environment gate
  recorded

### Fixed
- `apply.yml`: removed the false "Production apply (requires manual approval)"
  claim — verified via the GitHub environments API that no `production`
  environment exists and that `dev`/`staging` have zero `protection_rules`
- `audit/soc2-checklist.yml`: CC8.1-04 changed from `implemented` to
  `not_implemented`, with the evidence field corrected to record that the cited
  control does not exist. A checklist asserting a non-existent approval gate is
  a fabricated compliance record
- `AGENTS.md`: enforcement-truth table updated for the gated apply jobs and the
  missing `production` environment

## [1.1.1] - 2026-09-30

### Added
- `scripts/plan_gate.py` — STOP gate that refuses any plan destroying or
  replacing a resource, and also refuses a create-heavy plan built on an empty
  state: the failure mode proven in this repo's own `apply.yml` history
  (`120 to add` from an empty state, then HTTP 403). Parses `terraform show -json`
  rather than plan text, and fails **closed** with distinct exit codes:
  0 safe, 1 refused, 2 unevaluated
- `tests/test_plan_gate.py` and `tests/fixtures/plan_gate/` — 11 self-tests over
  fixtures derived from real captured `terraform show -json` output, so the gate
  cannot go inert silently
- `make plan-gate` and `make test` targets; `plan.yml` now runs the gate
  self-test and the destroy/replace gate on every PR
- `AGENTS.md` — version-controlled agent rules: verified commands, edit
  boundaries, explicit STOP conditions, and the current enforcement truth

### Changed
- `make apply` now depends on `plan-gate` and no longer advises "use CI/CD
  instead" — CI cannot apply, because state is local to the control-plane host
- `repos/jol-control.yml` required status checks now name check-runs this repo
  actually emits (`Validate Repo Allow-List`, `Policy Compliance Check`) — GitHub
  reports bare Actions job names, verified live via the check-runs API, not
  `workflow / job` strings. The unsatisfiable `compliance-scan / validate` and
  `codeql-analysis` entries were removed
- `policy/repo-defaults.yml` documents that a required context must equal the
  check-run name GitHub reports (the bare Actions job `name:`), and records that
  the org-wide check names are NOT verified against the 39 managed repositories
- `.gitignore` now excludes generated `tfplan.json`

### Fixed
- Documentation accuracy: annotated reviewer/approval gates in `README.md`,
  `CONTRIBUTING.md`, `docs/architecture.md`, `docs/change-management.md`, and
  `docs/runbooks.md` to state that they are the target baseline and are **not**
  enforced while `solo_mode = true`
- `policy/repo-defaults.yml`: corrected the `allow_merge_commit: false` comment —
  the baseline is not "squash-only" because `allow_rebase_merge: true`; linearity
  comes from `require_linear_history`
- `README.md` / `docs/architecture.md` / `docs/change-management.md`: replaced the
  "applied automatically via GitHub Actions (dev → staging → prod)" claim with the
  actual apply path — local `terraform.tfstate` on the control-plane host, which
  CI runners cannot reach, with the default `GITHUB_TOKEN` only — since proven by
  both `apply.yml` runs failing with HTTP 403 after a 120-resource empty-state plan
- `CONTRIBUTING.md`: documented which checks CI actually runs, listed the
  check-run names GitHub really reports for this repo, and recorded that the
  `ci / lint` and `ci / test` contexts are not produced by any workflow here

## [1.1.0] - 2026-09-26

### Added
- `solo_mode` variable for single-owner operation — drops multi-reviewer and code-owner gates while keeping signed commits, linear history, and force-push/deletion blocks
- Dynamic branch protection blocks that adapt to solo_mode vs team operation
- RA-03 risk acceptance entry for local Terraform state (no remote backend)

### Changed
- Migrated `vulnerability_alerts` from deprecated inline argument to separate `github_repository_vulnerability_alerts` resource (provider v6.x compatibility)
- Updated `required_approving_review_count` validation to allow 0 (solo mode)
- Removed unused `data.github_organization.jol` and `data.github_team.security` data sources
- Removed security manager role resources from org-settings.tf (no teams in solo mode)

### Fixed
- Documentation accuracy: replaced false S3/DynamoDB state claims with local state reality in `docs/architecture.md` and `docs/threat-model.md`
- CI workflows: removed non-functional AWS credential references from `plan.yml` and `apply.yml` (local state requires no AWS credentials)
- Removed unnecessary `requests` dependency from `compliance-scan.yml` drift detection step
- Added `.jolarca-staging/` to `.gitignore` to prevent foreign project artifacts

### Removed
- PyCharm utility scripts (disable_pycharm_plugins.sh, disable_pycharm_power_save.sh) — not control-plane infrastructure

## [1.0.0] - 2026-09-24

### Added
- Initial release — central governance control plane for journeyoflife-org
- 40 repository YAML allow-list definitions (repos/*.yml)
- Policy baselines: repo-defaults.yml, compliance-gates.yml
- Terraform IaC: GitHub provider, repository resources, branch protection
- CI/CD workflows: plan (PR comment), apply (dev→staging→prod), compliance-scan
- Audit checklists: SOC 2, GDPR, ISO 27001
- Python scripts: validate_repos, compliance_check, drift_detect
- Documentation: architecture, runbooks, threat model, data classification, change management
- Compliance frameworks: SOC 2 Type II, GDPR, ISO 27001:2022, PCI-DSS 4.0
