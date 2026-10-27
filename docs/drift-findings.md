# Drift Findings Register

This register tracks drift between Terraform state, configuration, and live GitHub state.

**Priority:** S0 (Stop-Work) > S1 (Fix Before Apply) > S2 (Fix Soon)

**Index.** Entries stay in the order they were discovered, because each carries the evidence
timestamp and the corrections applied to it at the time; numbers never change once other
documents cite them. In numeric order:

| ID | Subject | Status |
|---|---|---|
| S1-001 | Private repos cannot have branch protection without GitHub Pro | fixed |
| S1-002 | Drift detection reported "cannot see" as "does not exist", and a blind run as passing | fixed (checker 2026-10-09; CI credential 2026-10-19) |
| S1-003 | Every published contact address in the fleet is undeliverable | open; intake and org defaults fixed, 24 repos to sweep |
| S1-004 | The published donation path is a domain-parking lander | partially closed; affordance removed, capability absent |
| S1-005 | `.github` code-owner review unsatisfiable — diagnosis later overtaken | superseded by S1-007 |
| S1-006 | Shared workflow library scanned its own definition repo; one workflow uncallable | fixed; consumer proof owed |
| S1-007 | `.github` PRs report `blocked` with nothing left to satisfy | open; escalated, needs merge box or Support |
| S1-008 | Hand-set rulesets re-impose the review controls `solo_mode` removed, 19 of 40 repos | open; invisible to Terraform and drift |
| S1-009 | Seven governance-tier repositories have branch protection in state and none on GitHub | open; blocks no apply today, distorts every future one |
| S1-010 | The CI secret-scan job could not fail, and its tier matrix scanned one tree four times | fixed locally; CI proof owed |
| S1-011 | `state_gate.py` crashed on any directory holding more than one state file | fixed |
| S1-012 | `plan.yml`'s destroy/replace gate can never pass in CI, so every `*.tf` PR was red | fixed; CI proof owed |
| S2-001 | Required status check contexts do not match reality | fixed |
| S2-002 | Teams referenced in config do not exist | fixed (bindings still decorative) |
| S2-003 | State is local, not remote | open, RA-03 accepted |
| S2-004 | AGENTS.md cited a resolved state mismatch as current truth | fixed |
| S2-005 | Git identity migration: authorship needs a verified account email | closed by decision |
| S2-006 | Dependabot labels referenced by jol-hub do not exist | open |
| S2-007 | state-gate's stale-copy detection missed the one copy that diverged | fixed |
| S2-008 | `make lint` modified the working tree, editing a `prevent_destroy` block | fixed |
| S2-009 | `terraform fmt -check` fails at HEAD, and no CI job enforces formatting | fixed (format); CI enforcement still absent |
| S2-010 | Two clones of repositories no longer in the organization sit in the fleet tree | open; owner decision |
| S2-011 | This register's index omitted S1-009 | fixed |
| S2-012 | An agent destroyed the live state file; recovery depended on an undocumented backup | recovered; automation still absent |
| S2-013 | A recovery identity was shredded before any off-host copy existed, on instructions written by this project's own runbook | open; gate built, key must be re-minted |
| S2-014 | Both private keys sat on the device the off-device backups were made to survive; an interim key copy on `sdb` fixes that and leaves every disk holding a key beside its ciphertext | open; needs an off-machine key copy |
| S2-015 | A RB-09 cron-editing instruction from this repository corrupted jol's crontab; caught in-session and restored | closed; instruction replaced and verified |
| S2-016 | The estate's alerting chain is non-functional end to end, so no scheduled failure can notify anyone | open; `make backup-status` is the interim pull |
| S2-017 | The custody rehearsal shipped in `c4eb8b6` was defective four times over, and the gate beside it could never report success | closed by replacement; 13 cases added |
| S2-018 | A second project began writing its own snapshots into this backup's destination and satisfied the freshness gate with them | closed; name, clock and lineage all now checked, 5 cases added |
| S2-019 | The custody challenge printed its own secret to stdout, so the transcript could attest without the key | closed same session; fingerprint only now, case 52 |
| S2-020 | The backup suite depended on a file no CI runner has, so the merge commit would have gone red on four cases | closed; SRC is an input now, runner-shaped census measured 30/22 |

Two undated sections are folded in where they arose: *Measurement traps* (how three readings
here went wrong) and *Process slip* (an edit made from a stale clone).

---

## S0 — Stop-Work / Critical

*None currently.*

---

## S1 — Fix Before Apply / BLOCKING

### S1-001: Private repos cannot have branch protection without GitHub Pro

**Discovered:** 2026-09-30  
**Status:** FIXED  
**Finding:** `jol-dr` is private, but config declared `tier: governance` which requires branch protection. GitHub API returns 403 for branch protection on private repos without GitHub Pro.  
**Impact:** Apply would fail with 403 when trying to create branch protection for jol-dr.  
**Resolution:** Modified `branch-protection.tf` to exclude private repos from `governance_repos` and `standard_repos` locals.  
**Files changed:** `branch-protection.tf`

### S1-002: Drift detection reported "cannot see" as "does not exist", and a blind run as passing

**Discovered:** 2026-10-09  
**Status:** FIXED — checker (2026-10-09) and CI credential (2026-10-19, run 39255407378); the
residual is closed, the new dependency is documented in `docs/runbooks.md` RB-07  
**Finding:** The scheduled Compliance Scan failed from run 37107745958 (2026-10-03) with
`in_defined_not_github: ["jol-dr"]`. Nothing was missing. `gh api
repos/journeyoflife-org/jol-dr` returns `visibility=PRIVATE`, `gh repo list
journeyoflife-org --limit 500` on this host returns 41 rows (40 managed + `.github`), and
`make drift` reported `NO DRIFT — All 40 repos match`. CI ran the same script with
`secrets.GITHUB_TOKEN` until 2026-10-19, which enumerates only public repositories, so the fleet's single
private repository was absent from its view and the checker concluded absence from
ignorance. Worse than the false alarm: the same script returned **exit 0** whenever the
listing came back empty or `gh` failed outright, so a fully blind run reported the control
as passing — a fabricated compliance record, not a missing one.  
**Impact:** A weekly control that was red for six days for the wrong reason, and that could
have been green for no reason at all. Any genuine absence (a deleted or never-created repo)
produced byte-identical output to a permissions artefact, so the control could neither warn
reliably nor pass honestly.  
**Resolution:** `scripts/drift_detect.py` now emits three verdicts with distinct exit codes
— 0 evaluated-and-clean, 1 genuine drift, 2 unevaluated. A private-blind or truncated
enumeration, an empty listing, a failed `gh` call, an unreadable allow-list, and an internal
crash all map to 2. Each declared absence is confirmed by a direct `gh api` lookup, and a
repository that answers a lookup while missing from the listing makes the run UNEVALUATED
rather than DRIFT. `compliance-scan.yml` annotates exit 2 as `Drift detection UNEVALUATED`
with the remedy inline, and `validate-repos` runs the new 11-test self-test on every PR.  
**Evidence:** `tests/fixtures/drift_detect/live_host_user_token.json` (real capture, 41 rows,
one PRIVATE) and `ci_github_actions_token.json` (the Actions-token view, 39 rows, no private
visible) — `python3 tests/test_drift_gate.py` → `PASSED — 11 drift-gate tests, 0 failures.`  
**Residual and remediation — CLOSED 2026-10-19.** The scheduled job was UNEVALUATED until it
got a token that can read the organization. That token now exists and is bound: a fine-grained
PAT stored as the `jol-control` repository secret `ORG_READ_TOKEN`, preferred by the drift step
over `secrets.GITHUB_TOKEN` in `compliance-scan.yml`. **Read from the Settings UI on 2026-10-19**
(it cannot be read programmatically: `GET /orgs/journeyoflife-org/personal-access-tokens` answers
`404` from this host and GitHub documents that endpoint as *"Only GitHub Apps can use this
endpoint"*): expires **2027-01-17** — exactly the 90 days requested — resource owner
`journeyoflife-org`, repository access "all repositories owned by the organization", Repository
permissions **"Read access to code and metadata"** (Contents + Metadata read-only) and Organization
permission **"Read access to members"** (Members read-only) — every attribute read off the token's
detail page, nothing inferred. The strongest verification remains behavioural:
the enumeration in CI now contains a private repository, which no scope-light credential can
produce. Proof is the CI run, not the mint:
run **39255407378** at `headSha=1a66742` printed `"evaluated": true`, `"github_count": 40`,
`"matched_count": 40` and `NO DRIFT — All 40 repos match`, where the blind runner token's view
is 39 rows. The two dispatches at the preceding commit (`39254606046`, `39254610945`) establish the
**before** state only: their `head_sha` is `ba99034`, whose published file bound
`GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}` with no `||` at all (`git show
ba99034:.github/workflows/compliance-scan.yml`), so they are evidence of the blind token, not of
the fallback expression. **The fallback branch has never executed in CI** — `gh secret list` shows
`ORG_READ_TOKEN` created at 12:43:04Z, before the first run of the new expression at 12:52:05Z, so
the unset-secret path was never live. That behaviour is inferred from GitHub's `||` semantics (an
unset secret is an empty string, hence falsy) and labelled as inference here rather than as proof;
proving it would mean deleting the secret, and a secret value is write-only and unrecoverable, so
the test costs a re-mint and is not worth doing.

**Scheduled-run history, measured 2026-10-19** (`gh run list --event schedule`) — every scheduled
run of this control has failed since at least the start of the retained history, four consecutive
weeks, and the *reason* changed midway:

| Run | Date | Drift job verdict |
|---|---|---|
| 36226576141 | 2026-09-26 | false **DRIFT** — `in_defined_not_github`, `"github_count": 39` |
| 37107745958 | 2026-10-03 | false **DRIFT** — the run this finding was opened for |
| 38037365416 | 2026-10-10 | **UNEVALUATED** — `"evaluated": false`, honest red, first run after the checker rewrite |
| 39011182828 | 2026-10-17 | **UNEVALUATED** — honest red, last run before the credential existed |

So the "red for six days" in the Impact paragraph understates it: the control was red for four
weeks, the first two of those for the wrong reason and the last two for the right one. No
**scheduled** run has yet evaluated the allow-list — the proofs above are `workflow_dispatch`,
which executes the same job; the first scheduled verdict is due Saturday 2026-10-24. Note also
that GitHub delivered every one of those `cron: 0 2 * * 6` runs between 06:47 and 08:17 UTC, so
schedule timing must not be assumed precise when reasoning about a deadline.

What this control now depends on, and how it fails: the verdict is only as durable as a
credential with an expiry, and the two ways it goes away **fail differently**, because `||`
substitutes only on a falsy operand. Unset or deleted secret → falls back to
`secrets.GITHUB_TOKEN` → `"github_count": 39`, reason `cannot enumerate private repos`. Expired,
revoked, or regenerated-but-not-re-stored token → a non-empty string, so no fallback →
`gh repo list failed … HTTP 401: Bad credentials` and **no `github_count` line at all** (measured
with a deliberately invalid value on 2026-10-19). Both are exit 2, so neither can ever read as a
pass and neither as a false DRIFT; only the diagnosis differs, and RB-07 carries the table.
A third consumer was found while checking this: `apply.yml`'s post-apply `Drift detection` step ran
the same script with the ambient runner token and no binding, so it would have failed the
production job for a non-drift reason the day `vars.TF_REMOTE_STATE_ENABLED` is set. It now binds
the same expression. Minting,
verification and rotation are `docs/runbooks.md` RB-07. Two traps measured while closing this:
(a) a `workflow_dispatch` run executes the workflow file **as published on the default branch**,
so interpreting a run before the `env:` binding is pushed yields a wrong conclusion in both
directions; (b) `export GH_TOKEN=""` (or a mistyped paste into `read -rs GH_TOKEN`) makes every
later `gh` call in that shell answer `401 Bad credentials` — `gh` does not fall back to the
keyring once the variable is *set*, so an empty value reads as a broken token. `401` is a
credential-shape failure; an under-scoped fine-grained PAT answers `403 Resource not accessible
by personal access token` or omits rows instead.  
**Files affected:** `scripts/drift_detect.py`, `tests/test_drift_gate.py`,
`tests/fixtures/drift_detect/`, `.github/workflows/compliance-scan.yml`, `Makefile`

### S1-003: Every published contact address in the fleet is undeliverable — the domains take no mail

**Discovered:** 2026-10-15  
**Status:** OPEN — contact sweep in progress. **Vulnerability intake FIXED**
(private vulnerability reporting enabled on 40/40 public repositories, 2026-10-15).
**Org defaults MERGED** — journeyoflife-org/.github PR #7, squash commit `c01de1b`,
rewriting `SECURITY.md`, `SUPPORT.md` and `CODE_OF_CONDUCT.md`; verified on `main`
that all three now contain **0** `@journeyoflife.org` / `@journeyoflife.lt` addresses.
The merge needed an administrator bypass — see S1-005. Queue is the **24 repositories
that ship their own `SECURITY.md`** with a dead address, because a repository file
overrides the default. `jol-auth` is excluded from this pass: another session holds it
on `remediation/batch-0-s1` with 39 uncommitted files.  
**Finding:** Not state drift but the same class of defect as S2-002: configuration and
documentation assert things that do not exist. 74 files across 27 repositories publish
role mailboxes on three domains, and DNS says none of them can receive mail:

```
journeyoflife.org   dig MX → "0 ."            RFC 7505 null MX: the domain explicitly
                                              disavows mail. NS = ns3/ns4.afternic.com,
                                              i.e. a parked domain listed for sale.
                  112 occurrences (9 are placeholders, 103 are real contact claims)
                  roles: security(61) dpo(6) noreply(5) engineering(5) conduct(5)
                       privacy(4) platform(4) ops(3) ciso(3) dev(2) compliance(2)
                       alertmanager(2) admin(2) infra(1) incident(1) errors(1) api(1)
journeyoflife.eu    no MX at all. NS = horizon/orbit.dns-parking.com (parked). This is
                  the product domain; 0 mail contacts published on it today.
journeyoflife.lt    no NS records; the domain does not resolve. 5 occurrences, all in
                  jol-core (SECURITY.md ×4 → security@, CODE_OF_CONDUCT.md ×1 → conduct@)
```

**Impact:** Three separate failures, all silent. (1) 28 repositories ship a `SECURITY.md`
instructing a vulnerability researcher to mail `security@journeyoflife.org`; that message
is rejected at SMTP time. The fallback was not switched on either — at discovery **0 of
the 40 public repositories had private vulnerability reporting enabled** (verified
2026-10-15: `gh api repos/journeyoflife-org/<repo>/private-vulnerability-reporting` →
`{"enabled":false}` for all 40; the endpoint 404s on the private `jol-dr`, which is
expected since it is only offered for public repositories). So the organization had **no
working intake channel for vulnerability reports at all**, and the 90-day disclosure clock
ran against a path that never delivered anything. That half is now closed (see remediation
(a)). (2) The GDPR DPO and
data-subject contact (`dpo@`, `privacy@`) is unreachable, which makes Art. 30(1)(a) and
Art. 38(1)(a) records assert a control that cannot be exercised — an auditor who tests it
fails it, and per AGENTS.md §6 that discounts the rest of the evidence pack. (3) 
`jol-devops/monitoring/alertmanager/alertmanager.yaml` configures an email receiver on the
same dead domain, and its relay host does not exist either: `smtp.journeyoflife.org`
resolves to `13.248.169.48` / `76.223.54.146` — the *same* AWS Global Accelerator parking
addresses as the `journeyoflife.org` apex, i.e. a domain-parking web service, not an SMTP
server on port 587. Corrected wording, because the first draft of this entry overstated it:
alerting is **not** "firing into a null MX" on this host — no Alertmanager is running here
at all (`ss -ltn` shows no `:9093`; the `jol-prometheus` container mounts only
`prometheus.yml` and a data volume, with no Alertmanager process or config). Whether it
runs on another host is **not verified from this machine**. The defensible statement is
that the receiver as written can never deliver anywhere it runs, and that this repository's
evidence pack does not claim an operational paging control (`audit/*.yml` reference
Dependabot and vulnerability alerts, which are GitHub features, not alerting) — so this is
an unbuilt control with an impossible config, not a broken running one. Either way it must
not be cited as incident-detection evidence until it is deployed and a test alert is
observed arriving.  
**Interim resolution (this repository):** `audit/gdpr-checklist.yml` `dpo_contact`
corrected from the dead `dpo@journeyoflife.org` to the reachable privacy channel, with
the reason recorded inline. `policy/contact-channels.yml` added as the single authority
for which role address goes where: admin-plane channels (billing, github, dev) stay
GitHub-internal and are never published, public-plane channels (security, privacy) may
be. `docs/threat-model.md` gained T-13 and risk acceptance RA-04 stating the trade-off:
a plus-addressed alias discloses the base mailbox, but the base mailbox is already
public on the GitHub profile and is the author of every commit in the fleet, so the
marginal loss is small against the gain of an address that actually receives mail.  
**Remediation path:** (a) **DONE 2026-10-15** — private vulnerability reporting enabled on
all 40 public repositories, each confirmed by an independent read-back. Two traps cost a
round of blind retries, and they belong in this register because they will recur:
  - the verb is **`PUT`**, not `PATCH`. `PATCH …/private-vulnerability-reporting` returns
    `404 {"message":"Not Found"}` even with `permissions.admin = true`, with preview
    headers, and with a real JSON boolean — GitHub answers 404 for an unmatched route on
    this endpoint instead of 405. A 404 here means *wrong verb*, not *no permission*, and
    the generic body gives no hint.
  - the read-back is **cacheable**. `GET …/private-vulnerability-reporting` immediately
    after a `204 No Content` still returned `{"enabled":false}` because GitHub serves
    `Cache-Control: private, max-age=60`. A verification run has to be cache-busted (append
    an unknown query parameter) or wait out the TTL, otherwise a change that landed looks
    like a change that was silently discarded — which is the exact failure shape of the
    `two_factor_requirement_enabled` write in this organization's history.
(b) stand up MX + SPF on
`journeyoflife.eu` and publish real `security@`, `privacy@`, `billing@`, `dpo@` mailboxes
there; (c) sweep the 26
remaining repositories from `policy/contact-channels.yml`, one signed-commit PR per
repository; (d) treat `jol-devops` alerting as **unbuilt, not broken**: pick a real relay,
point the receiver at the security channel, deploy it, and prove it with a test alert that
is observed arriving — until then no control may cite alerting; (e) stop citing any
contact-dependent control as `implemented` until the address is
re-tested. Do **not** edit the historical artifacts listed in
`policy/contact-channels.yml → contact_surface_rules.evidence_artifacts_are_immutable`; (f)
**the git-identity half of the migration is blocked and cannot be automated** — see S2-005.  
**Evidence:** `dig +noall +answer MX journeyoflife.org` → `journeyoflife.org. 3584 IN MX 0 .`;
`dig +short NS journeyoflife.org` → `ns3.afternic.com. ns4.afternic.com.`;
`dig +short MX journeyoflife.eu` → empty with `dig +short NS journeyoflife.eu` →
`horizon.dns-parking.com. orbit.dns-parking.com.`; `dig +short NS journeyoflife.lt` →
empty. `gh api orgs/journeyoflife-org` → `billing_email=journey4oflife@gmail.com`,
`email=null`; `gh api user/emails` → one entry, `primary=true`, `verified=true`,
`visibility=public`; `gh api repos/journeyoflife-org/jol-core --jq .billing_email` → null
and null for all 41 repos, so repository-level billing is not in use.
Post-remediation evidence for (a), reproducible:
`for r in $(gh api "orgs/journeyoflife-org/repos?per_page=100"
--jq '.[]|select(.visibility=="public")|.name'); do printf "%s %s\n" "$r"
"$(gh api "repos/journeyoflife-org/$r/private-vulnerability-reporting?cb=$RANDOM"
--jq .enabled)"; done` → 40 lines, all `true`, no `false`.
Occurrence counts from `grep -rEho "[A-Za-z0-9._%+-]+@journeyoflife\.(org|eu|lt)"
/opt/jol/repos` excluding generated scanner output and staging copies, 2026-10-15.  
**Files affected:** `audit/gdpr-checklist.yml`, `policy/contact-channels.yml` (new),
`docs/threat-model.md`, `docs/drift-findings.md`

### S1-004: The published donation path is a domain-parking lander, and no donation endpoint exists anywhere in the fleet

**Discovered:** 2026-10-15  
**Status:** PARTIALLY CLOSED — the defective published affordance is being removed
(`.github` PR #8, opened 2026-10-15, `mergeState=BLOCKED` by S1-005). The underlying
capability gap **remains open**: the organization still cannot accept a donation online.
Those are different findings and only the first is a governance defect.  
**Finding:** Three public surfaces advertise `https://journeyoflife.org/donate` as the way to
support the mission: `.github/SUPPORT.md`, `.github/FUNDING.yml` (which GitHub renders as the
organization's funding link on every repository) and
`.github/ISSUE_TEMPLATE/config.yml`. The domain does not host the project:

```
curl https://journeyoflife.org/donate  -> 200, content-type text/html, 114 bytes:
  <!DOCTYPE html><html><head><script>window.onload=function(){window.location.href="/lander"}</script></head></html>
curl https://journeyoflife.eu/         -> <title>Parked Domain name on Hostinger DNS system
dig NS journeyoflife.org               -> ns3.afternic.com / ns4.afternic.com   (registrar parking)
dig MX journeyoflife.org               -> "0 ."                                  (null MX, RFC 7505)
```

A search of every repository under `/opt/jol/repos` for a real payment or donation endpoint
(donorbox, buy-me-a-coffee, stripe pay links, paypal donate, librepay) returned **only**
third-party notices inside `node_modules/` and `.venv/` metadata — no organization donation
URL exists. So the link was never wired to anything, and both candidate domains are parked.
**Impact:** donation intake is broken while being advertised, and donors who follow it land on
a parking page that serves third-party advertising and links **under the organization's own
name and path** — a phishing surface the organization does not control and cannot audit. For a
charitable mission platform handling donor records described in its own `SECURITY.md` as
PCI-DSS in scope, publishing a redirect into an uncontrolled ad lander is a reputational and
fraud-exposure finding, not a cosmetic one. It also contradicts the `SUPPORT.md` framing that
support is best-effort but the mission is real: a reporter or donor following a published link
gets a page for sale.  
**Why this was not fixed in the sweep:** inventing a replacement URL in a public file is worse
than leaving a known-broken one. The correct destination — a hosted donate page, a payment
provider URL, or removal of the link from `FUNDING.yml` until one exists — is an owner and
finance decision.  
**Remediation, and what was decided:** the owner authorized **removal** on 2026-10-15, executed
in journeyoflife-org/.github PR #8 — the `custom:` entry is deleted from
`.github/FUNDING.yml` with the evidence and the re-add condition written into the file, the
"Support the mission" contact link is removed from `.github/ISSUE_TEMPLATE/config.yml`
(three contact links remain, YAML re-validated), and the `SUPPORT.md` row now states plainly
that no online donation channel is published. `github: [journeyoflife-org]` was deliberately
left untouched: it answers 200 rather than 404, and whether it presents real sponsor tiers was
**not** verified, since GitHub serves a page shell either way. When a genuine endpoint exists,
change all three files together so the Sponsor button, the support table and the issue-form
sidebar cannot disagree, and re-fetch the target to prove it returns the intended page rather
than a redirect.  
**Evidence that no donation path exists in code either (added same day):**
`jol-hub/frontend/apps/master-site/src/app/donate/page.tsx:5` carries the comment
`/* DonationWidget deferred — requires I18nProvider from [locale]/ layout */` and renders
only an `<h1>Paramos forma</h1>` — the route exists, the widget is never mounted.
`packages/ui/src/components/composite/donation-widget/DonationWidget.types.ts:8` declares
only `onConfigure?: (selection) => void`: no provider, no submit, no form action.
`master-site/.env.local` configures a Bitrix placeholder and no site domain, and
`jol-infrastructure/.staging/fix-master-donate{,2}.py` removed a no-op `onConfigure` — the
signature of a widget dressed up as implemented. **So the recommendation is to remove the
donate reference, not repoint it**: `journeyoflife.eu` is parked too, which would trade one
parking page for another. GitHub renders the parked URL as the organization's Sponsor button
on every repository, and for a charitable platform advertising a donation path that collects
nothing is worse than publishing none.  
**Evidence:** `curl -s -L https://journeyoflife.org/donate`, `curl -s -L https://journeyoflife.eu/`,
`dig +short NS/MX journeyoflife.org`, `grep` across `/opt/jol/repos` for payment-provider URL
shapes (hits confined to vendored dependency metadata).  
**Files affected:** `.github/SUPPORT.md`, `.github/FUNDING.yml`,
`.github/ISSUE_TEMPLATE/config.yml` (all in `journeyoflife-org/.github`)

### Measurement traps found while verifying S1-003 and S1-004

Two of my own readings were wrong; both are recorded so the next operator does not repeat
them, and neither changed the enforcement state of anything.

1. **A `404 Branch not protected` does not mean unprotected.**
   `GET /repos/journeyoflife-org/.github/branches/main/protection` returns 404, which reads as
   "this repository has no protection". It does: an **active ruleset** named `protect-main`
   (id 22978013) enforces `required_signatures`, `required_linear_history`, `deletion`,
   `non_fast_forward`, `update`, and a `pull_request` rule with
   `require_code_owner_review: true`, thread resolution and squash-only merges, with
   `required_approving_review_count: 0`. Rulesets and legacy branch protection are separate
   APIs and each is blind to the other, so the fleet must be audited through
   `GET /repos/{owner}/{repo}/rulesets` as well as `…/branches/{branch}/protection`. The same
   ruleset carries `bypass_actors: [{actor_type: RepositoryRole, actor_id: 5 (admin),
   bypass_mode: always}]` and `current_user_can_bypass: always` — the single member bypasses
   every rule, which is exactly the limitation `/.github/CHANGELOG.md` already declared on
   2026-09-12.
2. **Count state per resource, not per first match.** An earlier message from this session
   claimed 11 branch protections in state against a documented 39. Wrong, and retracted: the
   `github_branch_protection` resource appears **twice** (`governance` = 11 instances,
   `standard` = 28), total **39**, with 40 `github_repository` instances — consistent with
   S1-001 excluding the private repo. `AGENTS.md` was right; the number in this register was
   never in error. A loop that prints one summary line per matching entry and is read as a
   single total produces this mistake.
3. **Never feed text containing backticks through an unquoted heredoc.** Writing the
   `.github/CHANGELOG.md` entry with `<<PY` instead of `<<'PY'` let bash execute every
   `` `code span` `` as a command substitution: the pushed entry lost all file names and
   domains and read "lives on , which has a null MX record (, RFC 7505)". Detected by reading
   the file after the write rather than trusting the "inserted" message; repaired in commit
   `4f06ed1` on the PR branch. Any generator that writes markdown must use a quoted delimiter
   and then assert backtick balance and the presence of expected literals.
4. **Correlation is not the merge blocker.** Nine failing checks were present whenever a
   merge was blocked, so the checks looked like the cause — and the first draft of
   `S1-005` said so in a public PR comment. Removing the failures left the block intact.
   `mergeable_state=blocked` names a *review* deficiency, not a check failure, and
   `allowed_merge_methods` / `update` parameters matter more than the presence of red
   checks. Read the enum's meaning before writing a cause into a merge comment.
5. **A reusable workflow's own `push`/`pull_request` triggers do not apply to callers**, so
   filtering them in the library is safe for consumers — but a self-referential path entry
   (`- '.github/workflows/security-scan.yml'`) makes the library re-scan the definition repo
   whenever the library itself is edited, which is precisely the failure being fixed.
6. **A confident report that an action was taken is not a measurement.** This session received
   assertions that the 19 rulesets had been relaxed, that `jol-docs#4` had merged at
   `2026-10-19T13:10:38+03:00`, that an ADR-014 existed (sha `d2593f8…`), that labels had been
   created across eleven repositories, that two enforcement gates had been added, and that
   `dependabot.yml` label work was done except for `jol-auth` "15 missing". Re-checked against
   the live API, every one was false — and the shas do not exist as objects in either clone, in
   either repo's `--all` log, or on either remote (`gh api repos/…/git/commits/<sha>` → 404).
   The cheapest decisive tests were `gh pr view --json state,mergedAt`, `git cat-file -t`, and
   re-running the scan. Treat an upstream report as a hypothesis that costs four commands to
   confirm; acting on it as fact would have marked S1-008 closed while 19 repositories still
   demanded an approval nobody can give.
7. **`curl` with a `Bearer` token against `github.com` HTML is not a token-scope test.** A GET
   of `https://github.com/journeyoflife-org/jol-dr` returns `404` both anonymously and with the
   `gh` token, while `gh api repos/journeyoflife-org/jol-dr` returns the repository with
   `private=true`. Proven: the HTML probe cannot discriminate scope. Inferred (labelled as
   inference): GitHub's HTML endpoints authenticate by session cookie, so lychee's token may or
   may not be applied to `github.com` URLs depending on its sender configuration — which is also
   why the same link passed link-check on 2026-10-13 and fails on 2026-10-17, an interval this
   register cannot yet explain.
8. **A workflow run whose name matches a reusable workflow is not proof that a caller resolved
   it.** `jol-docs` shows a green `compliance-check` run dated 2026-10-17, which looks exactly
   like consumer-side proof that `workflow_call` now works. It is not: that file is `jol-docs`'
   own `.github/workflows/compliance-check.yml` defining the job "Document control & ADR/RoPA
   coverage", and `grep -rn 'journeyoflife-org/.github/.github/workflows'` finds no library call
   in `jol-docs` or `jol-hub`. The ten real spokes have not run CI since 2026-09-22.
9. **`$?` after a pipeline is the status of the LAST stage, not of the command you care about.**
   `gitleaks detect … | tail -30; echo "RC=$?"` printed `RC=0` while the line above it said
   `leaks found: 10`. The exit code belonged to `tail`. This exact shape recurred twice in one
   session — once in a suggested diagnostic command and once in a CI step (`hits=$(grep … | cut …)`
   then `rc=$?`, which captured `cut`), and in the CI case it would have made a security scan fail
   on every single run. Any gate that must distinguish pass / refuse / cannot-check has to read
   `${PIPESTATUS[0]}` or run the command without a pipe. A green exit code from a pipeline is
   evidence about `tail`, not about the scanner.
10. **A failed producer behind a pipe does not merely corrupt the exit code — it manufactures a
    plausible value.** `age --decrypt -i key missing.age | md5sum` printed
    `d41d8cd98f00b204e9800998ecf8427e` and exited **0**. That is the MD5 of *empty input*: a
    well-formed-looking 32-hex-digit digest that means "nothing was read". The command was a
    verification step for a backup, so a broken backup would have been reported as a verified one.
    `printf '' | md5sum` reproduces the value. Any checksum comparison must capture to a file, test
    the producer's status, and reject the empty-input digest explicitly — which is what RB-08 now
    does. Trap 9 above is the exit-code form of this; this one is worse, because the output looks
    like a measurement.
11. **A test that extracts "the first code block after the heading" tests the wrong block, and a
    vacuous test reports success.** Verifying the script *as published in* `docs/runbooks.md` by
    slicing out the first ```` ```bash ```` fence after `### Creating a backup` grabbed the key-
    **minting** snippet instead of the verifier. The extracted script ran, every assertion "passed",
    and the negative test — labelled *must refuse* — exited **0** because an empty script has nothing
    to refuse. Selecting by **content** (`EXPECT_MD5` + `verify recovery-key`) found 1 block out of
    18 and only then was the artefact actually tested. Never confirm an extractor by its exit code;
    confirm it by the size of what it extracted.
12. **Running a runbook verbatim is not a read-only act.** That same vacuous "test" executed
    `age-keygen -o ~/.config/age/state-recovery-YYYYMMDD.txt` with the placeholder name unresolved
    and **generated a real private key on disk**. It was unreferenced (the only match for its
    recipient was the file itself), so it was shredded after that check. `age-keygen` refused to
    overwrite an existing identity, which is why the two legitimate keys survived untouched. Any
    snippet that mints, writes or deletes must be run in a scratch directory, or not run at all.
13. **A broken test harness reports itself as a broken product.** Building the verification for the
    RB-08 backup script produced five false signals in a row, each of which invited a fix to the wrong
    layer:
    - `run(){ DEST="$W/dest" "$@" bash script; }` invoked as `run RECOVERY_KEY="$RK"` returned
      **`RC=127`** for five cases. Prefix assignments are only recognised when they appear **literally
      in the source**; after expansion bash treats `RECOVERY_KEY=/path` as the *command name* and
      reports command-not-found. Nothing was wrong with the script. Use `env VAR=value cmd`.
    - `age --decrypt -i key "$F"` with `$F` **empty** does not error — `age` falls back to reading
      standard input, so a backgrounded test **stays in state `T` (stopped)** after `SIGTTIN` rather
      than failing. It looked like a slow encryption. Always pass `< /dev/null`, and bound the call
      with `timeout`; redirecting only stdout is not protection.
    - `pkill -9 -f 'timeout 5 age'` matched the **command line of the shell issuing it** (which
      contains that literal string) and killed the session — exit **137**, no output. Never `pkill -f`
      with a pattern that appears in your own command; collect PIDs and kill by PID.
    - `ls -1 "$W/dest"/*.age` returning nothing fed an empty argument into the next step, which is
      how the hang above was reached. A "test" whose input is empty is not a test.
    - Two `RC=0` expectations were only satisfiable because a *previous* case had left a file behind.
      Assertions must be independent of execution order.
    The general form: when a check fails **immediately and uniformly**, suspect the harness before the
    artifact, and prove the harness by feeding it an input whose correct answer you already know.
14. **A heredoc and a `</dev/null` on the same command silently disable the heredoc.** Redirects are
    applied left to right, so the later stdin redirect wins: `python3 - a b <<'PY' </dev/null` reads
    its **program** from `/dev/null`, executes nothing, and exits **0**. The check built on this looked
    like a passing byte-identity assertion for several runs; it was an empty program. The reflex that
    caused it was correct in isolation — always redirect stdin when a command might block on it (trap
    13) — applied to the one command that *uses* stdin as its source of code.
15. **A test that always FAILS is as useless as one that always passes, and it reads more convincing.**
    Correcting trap 14 left the same case body containing `s==="```"` — three equals signs, a Python
    `SyntaxError`. The case exited 1 and was reported as *"the runbook has drifted from the script"*.
    It then appeared to work: every mutation I tried was "detected" by it, because it detected nothing
    and always fired. Three separate pieces of evidence were false-positive before this was seen:
    - the **unmutated baseline also went red** — the first signal, and the one nearly dismissed as
      leftover state from a previous command;
    - the file and the fence compared **equal** when the same code was run by hand;
    - the mutation harness quoted `"...$c/..."` in **double quotes**, so `$c` expanded in the caller to
      a directory already deleted, and eight "detected" mutations were really eight copies that were
      never touched.
    The fix is structural, not textual: case 19 now distinguishes `SyntaxError`/`Traceback` from a real
    difference and prints which one it found, and a **green baseline is a precondition** for trusting
    any red mutation.
16. **A guard test that asserts only an exit code is measuring the last thing that failed.** The backup
    suite's guard cases deliberately pass an invalid `RECOVERY_KEY`, so *any* later stage returning 1
    satisfies the expectation. Deleting the wiped-state requirement left case 7 green because the device
    check refused instead — the case passed while its own guard was gone. Asserting the refusal **text**
    closed that one and opened another: with only the in-repo refusal's `exit 1` deleted, the text is
    still printed and the *next* guard stops the run, so the case credits a different control. The two
    rules that survive mutation are: the crypto stage must never be reached, and every `FAIL:` line must
    carry the phrase of the case under test. Generalised: **name the thing you believe stopped it, and
    prove the assertion by disabling the thing itself** — an exit code is an aggregate of every check
    downstream of the one you meant to test.
17. **The defects that reached a human were all in prose, never in the committed code.** Every
    fail-closed rule built into `scripts/backup_state.sh` — capture the decrypt to a file, test the exit
    status, reject the empty-input digest, require the config directory to be pinned — was present and
    working. What actually misled people this session was three commands written as instructions:
      - "run `backup.sh`", a file that existed only inside a markdown fence → `RC=127`;
      - `PROOF=<that-nonce>`, a placeholder that reads as literal text → `bash: syntax error near
        unexpected token 'newline'`; and the same failure a second time as `CHALLENGE_DIR=/tmp`, in the
        one step whose entire purpose is being somewhere else;
      - `age --decrypt -i <that-copy> <snapshot> | md5sum`, which printed `d41d8cd9…` — the MD5 of empty
        input — and exited 0, because the pipe absorbed the failure it was written to detect. Trap 10
        restated as a rule about code, then violated in a chat message about that same rule.
    The lesson is not "be careful", it is a standard: **a command written for a human to paste is
    production code.** It needs no placeholder that parses as syntax, no pipe that can swallow an exit
    status, and it must be executed verbatim at least once before it is handed over — the same bar
    applied to the fence in trap 11, which is what caught the others.
18. **`&` in a `sed` replacement is the matched text, and in a crontab edit that is the whole line.**
    `sed 's|^\*/10 .*|&; cmd >/dev/null 2>&1|'` — the `&1` inside `2>&1` pasted the original line into
    the middle of the result, producing `...state_backup_guard.sh >/dev/null 2>*/10 * * * * ...`. Had
    it been left, cron would have run nonsense every ten minutes. Two compounding errors: the
    verification printed a *truncated* view of the line (`cut -c1-200`) and a *count* of matches, both
    of which passed while the line was corrupt. Restored from the backup taken immediately beforehand
    (`crontab <file>`), confirmed byte-identical by `diff`, then applied with `awk`, where string
    concatenation has no such metacharacter. The rule: when you mutate something that runs on a
    schedule, take the backup first, and verify by reading **the whole artifact and its diff**, never
    by counting how many lines match a pattern.
19. **A mutation that does not take effect makes the case meant to catch it pass.** To prove a wrong key
    is refused, the test overwrote the packet's identity with `age-keygen -o "$f"` — and `age-keygen`
    **refuses to overwrite an existing file**, silently. The key never changed, `verify` correctly
    succeeded, and the case reported `want 1 / got 0`, which looked like a product bug. Every negative
    test must assert that the mutation landed (compare the derived public key before and after) before
    it asserts anything about behaviour.
20. **A helper whose optional argument list is empty can shift past the end of its arguments.** The
    rehearsal harness collected `VAR=value` pairs with `while [ "$1" != "--" ]`; three call sites passed
    no variables and no `--`, so `shift` ran off the end and `$1` under `set -u` aborted the whole file
    *after* case 32 — 32 passes printed, no summary, which in CI reads as a step that finished. Fixed by
    bounding the loop on `$#` and making helper misuse a counted FAIL rather than a crash: a checker must
    fail loudly, never exit quietly having checked nothing.
21. **`mktemp -d --mode=700` is unsupported here and yields an empty variable**, so paths derived from it
    collapsed to `/offhost-attested` and the test ran against the real host while printing plausible
    results. Use `mkdir -p` plus `chmod`. The same class produced a false `OK` from `sha256sum -c` on an
    absolute-path manifest (S2-017): the source files were still at home, so it verified the originals
    and reported success for a copy that was never examined.
22. **A command handed to a human may contain a half I invented and never ran.** The instruction to
    separate the backup destination was:
    `mkdir -p /mnt/jol-backup/jol-control && chmod 700 /mnt/jol-control-backup-staging 2>/dev/null; rmdir /mnt/jol-control-backup-staging`
    The first clause failed honestly (`Permission denied`, `/mnt/jol-backup` is `root:root 755`) — but the
    second half referenced a directory that had never existed on any machine, existed only in my sentence,
    and produced a `No such file or directory` that looked like part of the failure rather than a
    fabrication. This is trap 17 with a new shape: not a wrong path, an *invented* one, dressed as
    cleanup. The rule it implies: every command line shipped to an operator must be executed verbatim in
    this session first, and any clause whose purpose cannot be stated in one sentence is a clause that
    should not be in the line at all.

### S1-005: .github's ruleset requires a code-owner review that a single-member organization cannot give

**Discovered:** 2026-10-15  
**Status:** OPEN — worked around by recorded admin bypass. **The diagnosis in this entry
was overtaken by evidence: the code-owner rule was not what blocked the merge.** See
S1-006 and S1-007; the parameter is retained as changed (it was a real defect) but it did
not restore a non-bypass merge path.  
**Finding:** `journeyoflife-org/.github` `main` is guarded by ruleset `protect-main`
(id 22978013) with `require_code_owner_review: true`, while this repository's
`CODEOWNERS` resolves `*` to `@journeyoflife-org/security @journeyoflife-org/devops` and
`/SECURITY.md` to `@journeyoflife-org/security`. Both teams exist, and their only member
is the account that authors the change. GitHub does not accept the author's own approval
as code-owner review, so with one member the requirement is **unsatisfiable**, not merely
unmet: `gh pr merge` returns *"the base branch policy prohibits the merge"* no matter what
the PR contains. PR #7 (the contact-channel fix) could only land with `--admin`.
`.github/CHANGELOG.md` predicted this on 2026-09-12 — *"Code-owner review is declarative,
not substantive… A second identity must be invited to the organization and added to the
`security` and `devops` teams before this control can be evidenced"* — and the same entry
states *"The bypass is not an approved merge path."* The second identity exists
(`IterVitae`) but is refused by the organization's secure-2FA requirement, so the deadlock
is total.  
**Impact:** every future change to the organization-wide security, support and conduct
documents requires a recorded policy bypass, which is the shape of an audit finding: a
control that is asserted, cannot be satisfied, and is routinely overridden. Note the
contrast — Terraform-managed repositories run `solo_mode = true` and omit review
requirements entirely, so only this hand-configured ruleset is stricter than the
declared posture, and it is not managed by any IaC in `jol-control`.  
**Remediation, pick one (both are owner decisions):**
(a) align the ruleset with `solo_mode` — set `require_code_owner_review` false and keep
`required_signatures`, `required_linear_history`, `deletion`, `non_fast_forward` and
squash-only; or (b) make the control real — invite a second identity, bring it into
compliance with the org's 2FA requirement, add it to `security` and `devops`, and stop
bypassing. Option (b) is the solo-mode exit documented in `docs/solo-mode-exit.md`. In
either case the ruleset should end up declared in Terraform rather than hand-set, so drift
detection can see it.  
**Evidence:** `gh api repos/journeyoflife-org/.github/rulesets/22978013 --jq '.rules[]'`;
`git show HEAD:.github/CODEOWNERS`; `gh api orgs/journeyoflife-org/teams`;
`gh api orgs/journeyoflife-org/memberships/JourneyOfLife` → `admin, active`;
`gh pr view 7` → `state=MERGED mergedAt=2026-10-15T17:55:31Z mergeCommit=c01de1b`;
bypass recorded as a comment on PR #7.  
**Files affected:** `journeyoflife-org/.github` ruleset (out of band, not in Terraform)

### S1-008: Hand-set rulesets re-impose the review controls `solo_mode` removed, on 19 of 40 repositories

**Discovered:** 2026-10-16  
**Status:** OPEN — the declared baseline and the enforced state diverge silently. **Decision
drafted as ADR-013 (`Proposed`, open as `jol-docs#4`, still unmerged as of 2026-10-19); no
enforcement changed yet.** Re-measured 2026-10-19: unchanged in substance — see the paragraph
below.  
**Finding:** `solo_mode = true` exists precisely so this organization can operate with one
member: `branch-protection.tf:39,53` omit `required_pull_request_reviews` entirely, and
AGENTS.md §2 states that reviewers and CODEOWNERS are not enforced. That is true of the
Terraform-managed **classic** protection — and separately contradicted by hand-configured
**rulesets** on nearly half the fleet. Scanning all 40 public repositories: **21 rulesets
across 19 repositories require at least one approving review, code-owner approval, or both.**

| repository | ruleset | approving reviews | code owner |
|---|---|---|---|
| jol-compliance | `Protect main branch` / `protect-main` | 1 / 1 | false / **true** |
| jol-hub | `protect-main` / `~master` | 1 / 1 | **true** / false |
| jol-domain-taxonomy, jol-ecommerce-engine, jol-hermes-agents, jol-llm, jol-rag-server | `protect-main` | 1 | true |
| jol-site-basilica, -cathedral, -cemetery-care, -deanery, -diocese, -funeral, -orthodox, -other-church, -parish, -protestant | `protect-main` | 1 | true |
| jol-deploy, jol-infrastructure | `protect-main` | 0 | true |

Neither mechanism can satisfy these: the sole org member cannot approve their own change, and
no second member exists. Confirmed live on **jol-hub#151**, a dependabot PR sitting at
`mergeable=true, mergeable_state=blocked` with `commits=1, requested_reviewers=0` — it will
stay blocked forever. Two further details: jol-hub carries **two** rulesets plus classic
protection simultaneously, and its classic protection says `count=0` while the rulesets say
`1`, so the strictest silently wins; and one ruleset is named `~master` while its include
pattern is `~DEFAULT_BRANCH`, which reads like a ref pattern typed into the name field.

**Why Terraform cannot fix this:** there is no `github_repository_ruleset` resource in this
baseline — `branch-protection.tf` says rulesets are deliberately deferred — so `terraform
apply` will neither revert nor converge them, and `scripts/drift_detect.py` compares repository
names and visibility only. The divergence is therefore permanent and invisible to every check
this repository currently runs, which is the definition of an ungoverned control surface.
**Consequence for the evidence pack:** any statement of the form "reviews are not enforced
because we run in solo mode" is now incomplete: as enforced, **approvals are required on 19
repositories and nobody can give them**, so the real merge path across half the fleet is an
administrator bypass. That is worse than either extreme — a control nobody can satisfy is not
an enforced control, it is an undocumented exception.
**Remediation:** decide once, then make it true everywhere. Either (a) bring rulesets into the
baseline as `github_repository_ruleset` with `required_approving_review_count: 0` (an ADR in
`jol-docs` first — this is an infrastructure change), or (b) treat rulesets as the enforcement
layer and delete the redundant classic protection so one system tells the truth. In both cases
the 21 rulesets above need their approval requirement reconciled with the single-member
reality, and `scripts/drift_detect.py` needs to compare rulesets so this cannot silently
return.  
**Evidence:** the scan is reproducible — for each public repo, list `…/rulesets`, then read
each `…/rulesets/{id}` and take `rules[type=="pull_request"].parameters
.required_approving_review_count` and `.require_code_owner_review`; `jol-dr` cannot be checked
at all (`403 Upgrade to GitHub Pro or make this repository public to enable this feature`), so
rulesets on the private repository are unknown.  
**Files affected:** 19 repositories' hand-configured rulesets (none declared in Terraform),
`scripts/drift_detect.py` (does not compare rulesets)  
**Measured collision with S1-003 (2026-10-17).** Of the 24 repositories still advertising a
dead address in their own `SECURITY.md`, **13 also carry an unsatisfiable ruleset** —
jol-ecommerce-engine, jol-infrastructure, jol-rag-server and all ten `jol-site-*` spokes — so a
correctly written contact-sweep PR there is **mergeable only by the same admin bypass this
register criticises in S1-007**. `jol-dr` cannot be evaluated at all (rulesets return `403`
for private repositories on this plan). This sets the order of work: S1-008 must be resolved
before or alongside the sweep, or the sweep delivers thirteen PRs that either sit unmerged or
normalise bypasses further. It also means `make drift` reporting NO DRIFT while 19
repositories are governed by configuration no one declared — the drift tool reads only
`name,visibility`, and `grep -c ruleset scripts/drift_detect.py` is `0`.  
**Recommendation (pending owner decision) — ordering revised 2026-10-17.** Pure option (a) and
pure option (b) both fail on measured facts: (b) cannot cover `jol-dr`, which cannot have
rulesets on this plan; and (a) applied blindly would import 21 rulesets of three different
shapes (`protect-main`, `Protect main branch`, and one literally named `~master` that applies
to `~DEFAULT_BRANCH`), at least one of which is a mis-tuned artefact rather than a decision.

An earlier draft of this entry recommended relaxing the 19 rulesets **first** and writing the
ADR afterwards. That ordering is withdrawn, for two reasons. First, relaxing a review
requirement removes a control, and removing a control without a written decision is exactly the
failure this register exists to prevent — `required_approving_review_count` is explicitly on
AGENTS.md's list of values needing in-session human approval. Second, the ADR is what decides
the target state, so relaxing before it exists pre-empts the decision it is supposed to record;
the security-strongest option (a second compliant approver, making approvals real rather than
deleting them) must be reachable on the evidence rather than foreclosed by convenience.

The decision is now drafted as **ADR-013, status Proposed, open as `jol-docs#4`**. It states the
invariant — no repository may demand more approvals than the organization can supply — as a
testable rule, records the constraints above, and leaves every mutation unapplied pending
approval. Sequence: accept ADR-013 → converge enforcement → declare rulesets where classic
protection cannot express them (`v*` tags) → extend `drift_detect.py` to compare both APIs.  
**Re-measured 2026-10-19 — nothing was relaxed, and five reported facts were false.** The fleet
scan was re-run read-only: **24 rulesets exist, of which 20 active ones across 19 repositories
carry a `pull_request` rule demanding an approving review, code-owner review, or both** — 17
repositories demand ≥ 1 approving review and 19 demand code-owner review. The only repositories
whose ruleset demands nothing are `.github`, `jol-deploy` and `jol-infrastructure` (the latter
two still require code-owner review, so they are unsatisfiable in a different way). New detail:
`jol-compliance`'s second ruleset `Protect main branch` (id 18790594) is **disabled** — it
presents as a control and enforces nothing. Reports arriving in this session asserted that the
relaxation had been executed, that this ADR had been merged, that an ADR-014 existed at sha
`d2593f8…`, that dependabot labels had been created in eleven repositories, and that two
enforcement gates had been added to `jol-control`. Each is contradicted by the live API, not by
another report: `jol-docs#4` is `state=open, merged_at=None`; no commit object `455d73c`,
`016959e`, `6d151c8` or `d2593f8…` exists in either clone or on either remote; `jol-docs
origin/main` contains no ADR-013 or ADR-014 and its newest commit is `d36df48` (2026-09-25);
`git ls-tree origin/main scripts/` in `jol-control` still lists exactly six files, none of which
is a capacity or label checker; and dependabot labels are still missing in 11 of the 12
repositories that declare them. Recorded here because the false claims all point the same way —
they describe the unsafe state as already achieved.

### S1-009: Seven governance-tier repositories have branch protection in state and none on GitHub

**Discovered:** 2026-10-19  
**Status:** OPEN — found while refuting a claim about duplicate protections; it blocks no apply
today and distorts every future one  
**Finding:** `terraform.tfstate` (serial 306, lineage `25425c0f`) holds **39
`github_branch_protection` instances across 39 distinct repositories** — 11 `governance` + 28
`standard`, with **no repository covered twice** (`branch-protection.tf:22,29` partition on
`tier == "governance"` and its negation, so the two `for_each` sets are disjoint by
construction). Querying `GET /repos/journeyoflife-org/<repo>/branches/main/protection` for all
41 live repositories returns **32 present, 8 absent**. Seven of the eight absentees are
governance-tier repositories that are **empty**: `size = 0` and
`GET /repos/…/commits` → `409 Git Repository is empty`, so there is no branch for GitHub to
attach protection to. They are `jol-compliance-evidence`, `jol-iac`, `jol-incident-response`,
`jol-payments-scope`, `jol-privacy`, `jol-secrets` and `jol-status` — the most sensitive names on
the allow-list. The eighth absentee is `.github`, which is not declared in this repository at all
(the 41-live / 40-declared gap) and is guarded by a ruleset instead. Governance-tier presence
therefore totals 4 of 11 in fact (`jol-compliance`, `jol-control`, `jol-docs`, `jol-policies`).  
**Why it matters:** the governance tier is where this control plane asserts its strongest
posture — signed commits, linear history, force-push and deletion blocks, `enforce_admins`. For
seven repositories that posture exists in state and nowhere else. The claim "governance
repositories are protected" is therefore false for 7 of 11 of them, and an auditor testing one
of them would find nothing.  
**The emptiness also breaks the procedures that point into those repositories** (measured
2026-10-19): `docs/runbooks.md` RB-03 — the secret-exposure response — step 4 files an incident in
`jol-incident-response` and step 5 updates a rotation log in `jol-secrets`, and neither repository
has a single commit (`size=0`, `pushed_at` one second after `created_at` at 2026-09-24T14:39Z). So the
documented answer to "a credential leaked" cannot be completed as written: it would require
authoring those repositories' first commits under incident pressure. RB-03 now says so inline and
names where the record actually goes; the underlying gap is this finding.  
**Consequence for the next apply (inference, labelled):** a refresh will read 404 for those
seven instances, drop them, and then propose to re-create them; a create against a repository
with no branch is expected to fail or to be accepted and remain inert. Not executed in this
session — `terraform plan -refresh-only` rewrites the state file, and `terraform.tfstate` is
read-only under AGENTS.md §4, so this stays an inference until run deliberately with approval.
`make drift` cannot see any of it: `scripts/drift_detect.py` compares `name,visibility` only.  
**Remediation:** either seed a first commit in those seven repositories so protection can bind,
or record them as intentionally empty and exclude them from the protection tiers until they have
content. In both cases `state_gate.py` / `drift_detect.py` need to distinguish "protection
missing because the repository is empty" from "protection missing because something deleted it" —
the second is an incident and the first is a lifecycle stage, and today both are invisible.  
**Evidence:** `terraform.tfstate` instance enumeration (read-only python, `index_key` per
resource: governance 11, standard 28, 39 distinct keys, 0 duplicates); per-repository
`gh api repos/journeyoflife-org/<repo>/branches/main/protection` (32 × 200, 8 × 404); `gh api
repos/journeyoflife-org/<repo>` → `size`, `default_branch`, `visibility`; `gh api
repos/journeyoflife-org/<repo>/commits?per_page=1` → `409 Git Repository is empty` for all
seven; `grep -n 'lookup(def, "tier"' branch-protection.tf` → lines 22 and 29.  
**Files affected:** `repos/jol-compliance-evidence.yml`, `repos/jol-iac.yml`,
`repos/jol-incident-response.yml`, `repos/jol-payments-scope.yml`, `repos/jol-privacy.yml`,
`repos/jol-secrets.yml`, `repos/jol-status.yml`, `branch-protection.tf`,
`scripts/drift_detect.py`  

### Process slip in this session, recorded so it is not repeated

The `.github` edits were made from a clone whose `main` was **8 commits behind
`origin/main`** (`85c4bed` vs `0d53643`). The concurrency check that ran beforehand
looked at dirty files, unpushed commits and worktrees — and at nothing being modified in
the last six hours — but never fetched, so it verified the working copy rather than the
remote state. The merge happened to be clean: those 8 commits touched only
`.github/workflows/*` and none of the three files edited here, confirmed afterwards with
`git log 85c4bed..0d53643 -- SECURITY.md SUPPORT.md CODE_OF_CONDUCT.md` (empty) and by
re-reading `SECURITY.md` on `main` (111 lines, all six sections intact). Had they overlapped,
the squash would have quietly reverted another session's work. **Any edit to a sibling
repository must `git fetch` and compare `HEAD` against `origin/<branch>` first**; a clean
tree does not mean a current tree. Applied on the follow-up change to the same repository
(PR #8): `git fetch --prune` first, `behind=0 ahead=0 dirty=0` confirmed before any file was
written, and the branch created afterwards.

### S1-006: The shared workflow library scanned the repository that only defines it, and one workflow was not callable at all

**Discovered:** 2026-10-15  
**Status:** FIXED in `journeyoflife-org/.github` PR #9 (`4a94b30`); consumer-side proof **still
outstanding, re-confirmed 2026-10-19** — every spoke's newest workflow run is 2026-09-21/22 and
no repository has run CI since the merge timestamp `2026-10-15T21:15:56Z`. A green
`compliance-check` run in `jol-docs` does not count as proof: it is that repository's own
workflow, not a call into the library (see measurement trap 8).  
**Finding:** Two defects in the same set of files, both measured.

1. `security-scan.yml`, `compliance-check.yml` and `payment-boundary-guard.yml` filter
   `push:` by path but left `pull_request:` unfiltered, so application scanners ran inside
   the **definition repository**, which contains no `backend/`, `frontend/`, `src/`, `app/`
   or `data/requirements.txt`. Every pull request to `.github` therefore failed nine checks:
   `CodeQL could not process any code written in JavaScript/TypeScript`; `Some specified
   paths were not resolved, unable to cache dependencies` for
   `cache-dependency-path: frontend/pnpm-lock.yaml`; `No file in .github matched to
   [data/requirements.txt or **/pyproject.toml]`. Because `push:` is filtered, `main` shows
   only two check runs — the breakage is invisible until someone tries to merge, at which
   point it looks like a policy problem rather than a configuration one.
2. `compliance-check.yml` is invoked as a reusable workflow by **ten** spokes
   (`uses: journeyoflife-org/.github/.github/workflows/compliance-check.yml@main` with
   `with: {repo-layout: flat}`) but its `on:` block never declared `workflow_call`, so the
   call cannot resolve — while the file's own jobs already read `${{ inputs.repo-layout }}`,
   which shows the trigger was intended and simply omitted. Sampled consumers are red
   (`jol-site-deanery`, `-basilica`, `-cathedral`, `-parish`: `conclusion=failure`), the
   non-consuming `jol-auth` is green, and `jol-hub`'s only match is inside
   `docs/templates/`, not live CI, so it is not a counter-example. `workflow_call` was
   already present in `security-scan.yml`, `payment-boundary-guard.yml`, `frontend-test.yml`
   and `frontend-build.yml` — this file was the odd one out.  
**Impact:** a shared control that never worked in the one repository that hosts it, and a
compliance gate that silently did nothing for ten spokes that believed they had it.  
**Resolution:** PR #9 added `workflow_call` with the `repo-layout` input (and optional
`SNYK_TOKEN`), mirroring `security-scan.yml`, and gave the three `pull_request` triggers the
same path filters as their own `push` triggers. Self-referential entries naming the workflow
file itself were deliberately excluded from the guarded lists — including them made a pull
request that edits the library re-trigger the scanners that cannot succeed here, which my
first attempt did and the follow-up commit corrected. `frontend-test.yml` already had the
guard and was reverted after my edit created a second `paths:` key in the same mapping. No
`workflow_call` interface changed, so no consumer call site breaks; each touched file is
re-parsed and asserted to retain `workflow_call` and to gain `pull_request.paths`.  
**Outstanding:** consumer-side proof. Re-running the historical failed run is refused
(`This workflow run cannot be rerun`), so a spoke needs a new push before the compliance job
can be observed resolving against the fixed library. Do not mark the ten-spoke defect closed
until that is seen.  
**Evidence:** `gh run view 38805059782 --log-failed`, `gh run view 38805059669 --log-failed`;
`gh api repos/journeyoflife-org/jol-site-deanery/actions/workflows/ci.yml/runs`; `grep -rl
compliance-check.yml@main` over `/opt/jol/repos` (11 hits, of which jol-hub's 2 are
templates); `gh api repos/journeyoflife-org/.github/rulesets/22978013`.  
**Files affected:** `.github/workflows/security-scan.yml`, `compliance-check.yml`,
`payment-boundary-guard.yml` (journeyoflife-org/.github)

### S1-007: Pull requests in journeyoflife-org/.github report `blocked` with nothing left to satisfy

**Discovered:** 2026-10-15  
**Status:** OPEN — escalated; no in-band explanation found  
**Finding:** after S1-006 was fixed, a pull request to `.github` runs **one** check and it
passes, has zero required approvals, no code-owner requirement, valid signatures and
attributed authors, and is not behind the base branch — yet the API still reports
`mergeable=true, mergeable_state=blocked`, and `gh pr merge` refuses without `--admin`:
"the base branch policy prohibits the merge". Eliminated with evidence, in order:

| hypothesis | test | result |
|---|---|---|
| nine failing checks block it | fixed by S1-006; `gh pr checks 9` shows one check, `pass` | still blocked |
| code-owner review unsatisfiable | `require_code_owner_review` false, read back cache-busted | still blocked |
| required approving reviews | `required_approving_review_count: 0` | not it |
| required status checks | `update` rule carries **no** parameters; org rulesets unavailable on this plan (`403 Upgrade to GitHub Team`) | not it |
| unsigned commits | every commit `verified=true reason=valid` | not it |
| unattributed commits | `.author.login = JourneyOfLife` on all, including GitHub's squash commits | not it |
| branch behind base | `compare` shows 2 ahead / 0 behind; PR `base.sha` equals `main` | not it |
| `require_extra_approval_for_unattributed_changes` | toggled false → still blocked → **restored to true** so no unmanaged change was left behind | not it |
| merge commits in the PR carrying an unverified signature | `GET /pulls/{n}/commits` for #7, #8, #9: every commit single-parent, `verified=true reason=valid`, none an implicit merge commit | not it |
| unresolved review threads (`required_review_thread_resolution: true`) | `review_comments=0` on all three PRs | not it |
| a ruleset/platform quirk shared with other repos | compared against peers: `jol-docs#3` is `mergeable_state=clean`, `jol-auth#19` is `unstable`, `jol-hub#151` is `blocked` **and legitimately so** (its rulesets demand 1 approval + code owner — see S1-008). So `blocked` is reachable for real reasons elsewhere, which makes `.github`'s empty requirement list stranger, not explained | not it |

**Impact:** the only way to change the organization-wide `SECURITY.md`, `SUPPORT.md`,
`CODE_OF_CONDUCT.md` or the shared CI library is an administrator bypass, and a bypass used
three times in one day is not a control — it is an absent control with paperwork. The
repository's own changelog has stated since 2026-09-12 that the bypass "is not an approved
merge path".  
**Browser route also closed (attempted 2026-10-17).** Reading the merge box in a browser was
tried and does not work unauthenticated: an anonymous session on a PR page renders the header,
the conversation and `21 / 21 checks OK`, but the merge status widget itself is behind login,
and `.github` currently has **no open pull request** at all (all merged), so there is nothing
to inspect. This eliminates "go look at the merge box in a browser" as an agent-executable step
— it requires the owner's signed-in session.  
**Why it is still open:** the remaining cause is not exposed by either protection API. Next
steps are the merge-box text in the web UI (which names the unsatisfied requirement) or a
GitHub Support ticket; `GET /orgs/journeyoflife-org/rulesets` cannot be interrogated on this
plan. Treat any further "fix" to the ruleset as unproven until one of those two is seen —
this session already changed one parameter on a correlation, which is how S1-005 got its
wrong conclusion into the record.  
**Evidence:** `gh api repos/journeyoflife-org/.github/pulls/9 --jq
'"mergeable=" + (.mergeable|tostring) + " state=" + .mergeable_state'` →
`mergeable=true state=blocked`; `gh pr checks 9` →
`Validate Reusable Workflow References pass`; ruleset read-back
`extra_approval=true codeowner=false count=0`, rule types
`deletion,non_fast_forward,required_linear_history,required_signatures,pull_request,update`
all present.  
**Files affected:** `journeyoflife-org/.github` ruleset `protect-main` (id 22978013), not
declared in Terraform

### S1-010: The CI secret-scan job could not fail, and its tier matrix scanned one tree four times

**Discovered:** 2026-10-27  
**Status:** FIXED locally; **CI proof owed** — the corrected job has not run on a runner yet  
**Finding:** two defects in one job of `.github/workflows/compliance-scan.yml`.

1. The `security-scan` job carried `strategy.matrix.tier: [governance, platform, devops, site]`
   and **no step ever referenced `matrix.tier`**. `actions/checkout` with no `repository:`
   argument checks out `jol-control` only, so the matrix ran the identical four-pattern grep
   against the identical tree four times. Run `40072669078` lists all four jobs —
   `Repository Security Scan (governance)`, `(platform)`, `(devops)`, `(site)` — evidence that
   the duplication really executed rather than being collapsed.
2. The step's terminal action on a match was `echo "::warning::Potential secrets detected in
   code — review immediately"`. A warning annotation does not fail a job, and the script had no
   `exit 1` on any path. A detected credential therefore produced a yellow note and a **green**
   job.

**Impact:** the only secret-pattern control inside this repository was structurally incapable of
blocking anything, while its name and its four-tier matrix implied fleet-wide coverage it never
had. For SOC 2 / ISO 27001 evidence this is worse than an absent control: the run history shows a
passing "Repository Security Scan" on every pull request and every weekly schedule, so an auditor
reading the log sees a control that was never able to say no.

**One hypothesis refuted while measuring this.** I expected the warning to have been firing
silently on every run. It was not: run `40072669078`'s scan step printed only
`Scanning for common secret patterns...` and no warning line, so at `26132e8` the four patterns
genuinely match zero tracked files. The defect is the *inability to fail*, not a suppressed alarm.
Recording the difference matters, because "it has been alerting and we ignored it" and "it could
never alert" call for different remediation.

**Resolution:** the matrix is removed rather than left decorative. The step now distinguishes
three outcomes, following the exit-code discipline `drift-detection` already uses in this file —
a match emits `::error::` and exits 1; a grep that could **not run** (exit ≥ 2) emits its own
`::error::` and exits 1, because an unexecuted scan must never be reported as a clean one; no
match writes a PASSED step summary. Only `file:line` is printed, never the matched text: this
repository is **public**, so its Actions logs are publicly readable and echoing a match would
publish the credential being reported. `--exclude-dir` for `.git`, `.venv`, `.terraform`,
`node_modules`, `__pycache__` makes a local reproduction agree with CI instead of diverging on
third-party code.

**Regression test:** the step's `run:` block was extracted verbatim from the YAML with
`yaml.safe_load` and executed, rather than read. Clean tree → `RC=0`,
`Secret scan: PASSED`. A temporary tree carrying a **synthetic** `ghp_` token of 36 characters and
a synthetic `AKIA` key → `RC=1`, both named by `file:line`, neither value printed. Testing also
caught a defect this session introduced: a comment in the workflow quoting an example password
assignment was matched by pattern 4, which would have made CI permanently red on the first run.
The comment is reworded and the hazard is now recorded inline for future editors — the file is
scanned by its own patterns.

**Residual:** this is a four-pattern grep, not a detector. `gitleaks` 8.30.1 **is** installed on
the control-plane host (`/home/jol/.local/bin/gitleaks`), and a local `gitleaks detect --no-git`
over this repository reports 10 findings, all confirmed false positives: nine are `"index_key":`
lines in gitignored, untracked `terraform.tfstate*` files, where the `for_each` key is a
repository *name* and `index_key` merely contains the substring `key`; the tenth is
`docs/drift-findings.md:775`, a **GPG public key ID**, public by design. No secret exposure was
found. The organization's shared library does have a real Gitleaks job
(`.github/.github/workflows/security-scan.yml`, `gitleaks/gitleaks-action@ff98106`, pinned by
SHA), but that file declares no `workflow_call:` — only `push`, `pull_request`, `schedule`,
`workflow_dispatch` — so it cannot be called, the same defect class as S1-006 item 2 and still
open there. Wiring a real detector is a recommendation, deliberately not done in this change.

**Files affected:** `.github/workflows/compliance-scan.yml`

### S1-011: `state_gate.py` crashed on any directory holding more than one state file

**Discovered:** 2026-10-27  
**Status:** FIXED  
**Finding:** `worst_state(paths, forced=None)` had no `root` parameter, but its per-file listing
executed `f.relative_to(root)`. The single call site is
`worst_state([sp] if a_state else own, root)`, so `root` was passed into `forced` and the body
resolved `root` as a **module global that does not exist** — `NameError`. The listing is guarded by
`if len(results) > 1`, so it ran only for a directory holding more than one local state file:
`terraform.tfstate` alongside a `terraform.tfstate.d/<ws>/terraform.tfstate`, or two workspaces.
Every fixture in `tests/test_state_gate.sh` had exactly one state file, so 16 passing tests sat on
top of a path that always crashed.

**Pre-existing, not introduced by this session:** `git show HEAD:scripts/state_gate.py` written to
a temp file and run against a two-state fixture reproduces
`UNEVALUATED: internal error: NameError: name 'root' is not defined`, exit 2. Found while building
the S2-007 fixtures — the new `nostray` case was the first fixture in the suite's history to hold
two state files.

**Impact:** fail-safe but blind. The top-level handler converts the crash to exit 2, and AGENTS.md
§5.2 makes exit 2 a STOP condition, so no unsafe apply could slip through. But the gate could never
render a verdict for a multi-state directory — exactly the duplicate-inventory shape it exists to
catch — and its documented "the verdict is the WORST of them" behaviour was unreachable code. A
directory holding a healthy state beside a 0-byte one reported UNEVALUATED instead of REFUSED,
which sends an operator hunting for a credential or backend problem that does not exist.

**Resolution:** parameter renamed `forced` → `root`; `relative_to` guarded for `root is None` and
wrapped for `ValueError`, so an explicit `--state` pointing outside `root` prints absolutely rather
than crashing.

**Regression test:** three fixtures. `multiws` (two healthy states) must exit 0 **and** list both
files; `multiwsbad` (healthy beside 0-byte) must exit 1, proving the worst-of-them rule now actually
executes rather than being dead code; `nostray` exercises the same two-state shape for S2-007.
Against the pre-fix gate the suite reports **6 failures**; against the fixed gate,
**23 tests, 0 failures**. A test that only ever passes is not coverage, so both directions were run.

**Files affected:** `scripts/state_gate.py`, `tests/test_state_gate.sh`

### S1-012: `plan.yml`'s destroy/replace gate can never pass in CI, so every `*.tf` PR was red

**Discovered:** 2026-10-27  
**Status:** FIXED; **CI proof owed** — the corrected step has not run on a runner yet  
**Finding:** `.github/workflows/plan.yml`'s `Validate & Plan` job ends its gate with
`terraform show -json tfplan > tfplan.json && python3 scripts/plan_gate.py tfplan.json`. But
`terraform.tfstate` is gitignored, so a CI checkout has **no inventory**: `terraform init` starts
from empty state and every plan is create-only. The gate correctly refuses that shape, and the log
says so verbatim:

```
HALT — plan was built on an EMPTY state yet proposes 119 create(s). This runner cannot see
terraform.tfstate; applying would attempt to re-create resources that already exist.
     plan: 119 to add, 0 to change, 0 to destroy, 0 to replace (119 resource change(s) evaluated)
```

**The gate is right; the wiring is wrong.** `119` is exactly the live instance count
(40 repositories + 40 vulnerability-alert settings + 11 governance + 28 standard branch
protections), independently confirmed by `terraform state list | wc -l` on the host — a useful
cross-check, since a plan built against real state would never produce that number.

**Attribution, because it looked like my regression:** it was not one. `Validate & Plan` failed on
PR #3 (`dd6031a`) **and** on the earlier PR run `39479272770` at `bc05f3d` (2026-10-20), and in both
cases the failing step is the same `Destroy / Replace Gate`. "Both failed" is not "failed for the
same reason", so the step-level conclusions and the log text were compared before this was called
pre-existing.

**Impact:** the check is red for every PR touching `*.tf`, `repos/**`, `policy/**` or `*.tfvars`,
and does not run at all otherwise. A required-looking status check that can never pass is not a
control — it is noise that trains an operator to merge through red, and it destroys the evidential
value of the whole check suite for SOC 2 / ISO change-management claims. It also masks real
failures: a genuine destroy introduced by a future PR would look identical to the usual red.
Note that `required_status_checks` is currently disabled on `main` under `solo_mode`, so nothing
blocks today — which is exactly why this has survived unnoticed.

**Why a create-only plan carries no signal:** with empty state, nothing can be a destroy or a
replace — every object is an add. The detection the step performs is therefore **structurally
unreachable** in CI, so skipping the evaluation there loses no protection.

**Resolution:** the step is armed on positive evidence of a reachable inventory — a non-empty
`terraform.tfstate` **or** a declared `backend` block — and otherwise emits a `::notice::` stating
that the verdict is UNEVALUATED in CI and pointing at where the gate really runs (`make plan-gate`,
which `make apply` depends on). Three properties were tested rather than asserted, using a stub
`terraform` on PATH:

| Scenario | Expected | Observed |
|---|---|---|
| CI checkout: no state, no backend | skip, exit 0, notice emitted | `RC=0`, notice + step summary written |
| state present, plan contains a **destroy** | refuse | `RC=1` from `plan_gate.py` |
| state present, clean plan | pass | armed branch taken, no UNEVALUATED notice |
| `backend "s3"` declared, no local state | arm automatically | `RC=1` branch taken — so the gate re-arms itself after the S2-003 remote-state migration |

**This is explicitly not a weakening.** No test threshold was lowered; the plan-gate self-test
(11 fixtures, including the empty-state shape) still runs on every PR and is what proves the gate's
logic; and the evaluation still happens unconditionally wherever the inputs exist. The
`--allow-empty-state` bootstrap exception was deliberately **not** used — reaching for it here would
be the workaround AGENTS.md §5.2 forbids.

**Residual:** `apply.yml` runs the same `plan_gate.py` in its `staging` and `prod` apply jobs, which
are gated off by `vars.TF_REMOTE_STATE_ENABLED == 'true'`. If that variable is ever set **without** a
backend also being declared in `main.tf`, those jobs inherit this identical defect and will halt on
an empty state mid-apply. Checked, not inferred: `grep -E '^\s*backend\s+"' *.tf` returns nothing
today, so the pairing requirement is real and undocumented. It belongs to S2-003.

**Files affected:** `.github/workflows/plan.yml`, `.github/workflows/apply.yml` (comment only),
`docs/drift-findings.md`

---

## S2 — Fix Soon / Important

### S2-001: Required status check contexts don't match reality

**Discovered:** 2026-09-30  
**Status:** FIXED  
**Finding:** 28 repos declared `ci / test`, 23 declared `codeql-analysis`, 12 declared `dependency-review` as required contexts. But CodeQL is not running on most repos, and many repos have no CI workflows.  
**Impact:** When `solo_mode` is disabled and required status checks are enforced, merges will block because the required checks never report.  
**Current mitigation:** `solo_mode = true` drops `required_status_checks` entirely, so contexts are inert.  
**Resolution:** Cleared contexts to `[]` for all repos except jol-control (which has correct contexts matching compliance-scan.yml job names). When CI is added to a repo, update its contexts to match the actual check-run names.  
**Files affected:** `repos/*.yml` (39 files updated)

### S2-002: Teams referenced in config do not exist

**Discovered:** 2026-09-30 (audit)  
**Status:** FIXED  
**Finding:** `repos/*.yml` referenced teams `platform-admins`, `developers`, `auditors` which do not exist. Existing teams: `backend`, `data`, `devops`, `frontend`, `security`.  
**Impact:** Team-based access control is not enforced. Compliance claims about team restrictions are false.  
**Resolution:** Updated team references in `repos/*.yml` to reference existing teams: `platform-admins` → `security`, `developers` → `devops`, `auditors` → `backend`. Updated `docs/architecture.md` Team Access section to match. Note: team-repository bindings are not enforced via Terraform; team assignments in YAML are decorative until bindings are provisioned.  
**Files affected:** `repos/*.yml` (40 files updated), `docs/architecture.md`

### S2-003: State is local, not remote

**Discovered:** 2026-09-30  
**Status:** OPEN (RA-03 accepted)  
**Finding:** Terraform state is local to control-plane host (`terraform.tfstate`), gitignored. No state locking or versioning.  
**Impact:** CI cannot apply (empty state → mass create). No collaboration possible.  
**Current mitigation:** Apply jobs gated behind `vars.TF_REMOTE_STATE_ENABLED == 'true'` (unset).  
**Resolution path:** Migrate to HCP Terraform remote state (planned).  
**Files affected:** `main.tf` (no backend block), `docs/architecture.md`

### S2-004: AGENTS.md cited a resolved state mismatch as current enforcement truth

**Discovered:** 2026-10-09  
**Status:** FIXED  
**Finding:** STOP condition 7 in `AGENTS.md` stated "state records `jol-dr` as `public` while
GitHub reports it PRIVATE" as a *known live example*. That mismatch was reconciled by
`terraform apply -refresh-only` on 2026-09-30 and recorded as resolved in this register, but
the agent rules file was never updated. An agent reading it would chase a phantom, or worse,
would treat the register and the rules file as interchangeable authorities.  
**Impact:** Version-controlled agent rules that disagree with the evidence are worse than
absent rules: they train the agent to distrust the correct source.  
**Resolution:** Reworded as a historical example with the verification date and result, and
added a row to the §2 enforcement-truth table recording that CI drift detection cannot see
private repositories (from S1-002).  
**Evidence:** read of `terraform.tfstate` (serial 306, lineage 25425c0f) — `github_repository`
instance `jol-dr` has `visibility = "private"`; resource counts 40 repositories, 39 branch
protections, consistent with S1-001's exclusion of private repos.  
**Files affected:** `AGENTS.md`

### S2-005: Git identity migration — neither a role alias nor the noreply address can author here until it is a verified account email

**Discovered:** 2026-10-15  
**Status:** CLOSED by decision, 2026-10-15 — the identity migration is **declined**, not
deferred. The estate authors as `journey4oflife@gmail.com`, the only address that both
verifies and pushes. See Update 2 for the retraction of this entry's own earlier conclusion.  
**Finding:** The `+jol.*` scheme assumed the aliases could simply be added to the GitHub
account. Two verified facts break that assumption. First, email addresses can no longer be
managed with a token: `POST /user/emails` returns
`404 {"message":"Not Found", "documentation_url":"…/rest/users/emails#add-an-email-address-for-the-authenticated-user"}`
even though the token carries `user:email` (scopes confirmed from the response header
`X-OAuth-Scopes`). GitHub removed that route for token authentication, so **only a human in
the web UI can add and verify an alias** — an agent cannot perform or even test this step.
Second, the account has exactly one address, `journey4oflife@gmail.com`
(`primary=true, verified=true`), and repository protection enforces
`required_signatures.enabled = true` **together with** `enforce_admins.enabled = true` on
`main`. Host git config is `commit.gpgsign = true` with
`user.signingkey = 609F7926A8254CDB`, whose key UID is
`Gintaras Kazlauskas (JOL Platform Signing Key) <journey4oflife@gmail.com>`.  
**Impact:** Setting `git config --global user.email` to an alias that GitHub does not know
makes every new commit's author an unrecognized address. GitHub attributes a signature to
the account that owns both the key and the commit author address, so a valid GPG signature
from an unrecognised author is not verified — and with `required_signatures` plus
`enforce_admins` live, an unverified commit on `main` is rejected rather than merely
labelled. The blast radius is the whole fleet, not one repository. A global change is worse:
this host carries three organizations, and `includeIf` exists only for `/opt/viavitae/`
(one block, pointing at `~/.gitconfig.d/viavitae`). A global alias therefore also rewrites
authorship for **jolarca-dev**, which is PCI-DSS scope — the same unfixed V-002
cross-org-attribution defect, just with a different string, and a worse audit sentence:
a marketplace commit authored by a named church-project mailbox alias.  
**Status of this host (2026-10-15, after unwind):** the per-tree mechanism is **installed
but fail-safe disabled**. `~/.gitconfig.d/jol` (=`…+jol.dev@gmail.com`) and
`~/.gitconfig.d/jolarca` (=`…+jolarca.dev@gmail.com`) exist with mode 600 and are correct,
but their `includeif.gitdir:` lines were removed because **neither alias is verified on any
account** — `gh api user/emails` on JourneyOfLife still returns exactly one address, the bare
Gmail (`primary=true, verified=true`). Effective identity is therefore `journey4oflife@gmail.com`
in `/opt/jol/repos/jol-control` and `/opt/jolarca/repos/jolarca`, and
`architects@via-vitae.com` in `/opt/viavitae` (whose includeIf block survived untouched, and is
the proof the pattern works). A global `--global user.email` change made earlier in the day was
also reverted. One empty probe commit was created on local `main` with the unverified alias and
removed with `git reset --mixed HEAD~1`; the working tree's six modified files and one untracked
file were verified intact afterwards (`git status --porcelain` count unchanged, policy file
md5 re-checked), and `git rev-list --count origin/main..HEAD` is back to `0`. Nothing was ever
pushed with the alias.  
**Inference, labelled as such:** the push-rejection consequence is reasoned from documented
GitHub signature-attribution behaviour plus the verified protection state above; it was
**not** reproduced, because proving it would require pushing an alias-authored commit to a
protected branch. An attempt to demonstrate it from existing history was inconclusive — the
only non-account author addresses in the fleet are `…+IterVitae@users.noreply.github.com`
commits, and GitHub reports those as `verified: true, reason: valid` because a noreply
address is by definition account-bound. The revert is safe either way: it restores the only
identity for which every commit already pushed in this fleet is verified.  
**Two instrument errors made while testing this, both worth recording:**
1. **An org-2FA `403` describes the account you are on, not the resource you asked for.**
   `gh api orgs/journeyoflife-org` began answering
   `403 "…requires everyone in the organization to enable two-factor authentication…"
   You will not be able to access this resource…"`, which reads like the organization or the
   owner account got locked. It did not: `gh` had silently switched the **active** account to
   `IterVitae`, a member of the org without a compliant factor, and that is the identity the
   requirement was rejecting. Discriminator: `gh api user --jq .login` before believing any
   `403` about org resources; recovery: `gh auth switch -h github.com -u JourneyOfLife`.
   Re-verified after switching: JourneyOfLife reports `two_factor_authentication = true`,
   `gh api orgs/journeyoflife-org` answers normally, and `billing_email` is still
   `journey4oflife+jol.billing@gmail.com` — so the earlier fleet mutations were made as the
   owner account and survived. **Residual finding:** `IterVitae` is non-compliant with
   journeyoflife-org's secure-2FA requirement, so any automation or session running as it
   will keep failing with a misleading message; that is a roster problem to close separately.
2. **A local commit cannot be verification-tested through the API.** `gh api
   repos/{org}/{repo}/commits/HEAD` reports the **pushed** ref, so pointing it at a local
   probe commit returns the verdict for the last pushed commit and proves nothing about the
   new one. The only real test requires a push, which must not happen while the author address
   is unverified. Likewise `git reset --hard` to undo a probe on a dirty tree would have
   discarded uncommitted work — use `--mixed`, then confirm the dirty-file count and a
   checksum.  
**Remediation:** (1) owner adds and verifies the aliases in github.com/settings/emails on
the **JourneyOfLife** account specifically (this host is authenticated as two accounts —
`JourneyOfLife` active, `IterVitae` inactive — and the wrong one silently produces commits
attributed to a non-org owner); (2) if GitHub refuses the `+` form, the whole public-contact
plan in `policy/contact-channels.yml` must be re-decided, so test that first with `+jol.dev`;
(3) do **not** use `--global`. Add `~/.gitconfig.d/jol` with `user.email =
journey4oflife+jol.dev@gmail.com` and `~/.gitconfig.d/jolarca` with the jolarca-dev address,
then register `includeif.gitdir:/opt/jol/.path` and `includeif.gitdir:/opt/jolarca/.path`
blocks, mirroring the existing viavitae one — this closes V-002 for jolarca at the same time;
(4) confirm with a real signed commit that GitHub reports `verification.verified = true`
before any of it is cited as done.  
**Re-enable once each alias is verified** (one command per tree; the files are already in
place):
`git config --global includeif."gitdir:/opt/jol/".path ~/.gitconfig.d/jol` and
`git config --global includeif."gitdir:/opt/jolarca/".path ~/.gitconfig.d/jolarca`, then
confirm with `git -C <tree> config user.email` that the three trees report three *different*
addresses — an unchanged `/opt/jolarca` value means the block did not take. For jolarca the
precondition is stronger than for jol: establish **which GitHub account** authors jolarca-dev
commits before verifying the alias anywhere, or the fix recreates the attribution problem it
is meant to close.  
**Update, same day — resolved by separating attribution from mail.** *(SUPERSEDED on the
identity conclusion by Update 2 below; the attribution-vs-mail distinction stands, the claim
that a noreply author address verifies was wrong, and the paragraph that "refutes" the
sibling control plane is retracted.)*
The premise that the
git identity had to wait for an alias to be verified was wrong, and so was the design.
Attribution and mail triage are different jobs: a role alias is a *mailbox filter label*,
while a commit author field is *permanent published metadata* that happens to spell out the
base mailbox name in every commit object. The right author identity is GitHub's ID-prefixed
noreply address, `227570927+JourneyOfLife@users.noreply.github.com` (account id confirmed:
`gh api user` → `id=227570927, login=JourneyOfLife`). It attributes the commit to the account
and needs no Settings step at all — proven from this organization's own history, where
`jol-devops@3c8f9dcf` is authored by `134775791+IterVitae@users.noreply.github.com`, carries a
PGP signature (`has_sig=true`), and reports `verification.verified=true, reason=valid`.

That also refutes a claim inherited from the sibling control plane: `~/.gitconfig.d/jolarca`
states that a noreply author shows `verification.reason = bad_email` until the address is
added under Settings → Emails. Nothing on this host reproduces it — no pushed commit anywhere
reports `bad_email`, and the 14 most recent `jolarca-control` commits are Gmail-authored and
verify. noreply addresses are inherently account-associated, which is the whole point of them.
Inference, labelled: the verifying sample is the *other* account's noreply address; no
JourneyOfLife-signed noreply commit has been pushed yet, so the exact address is proven by
mechanism and id match, not by direct sample. First push will confirm it.

**Update 2, same day — Update 1's refutation was wrong and the noreply route is refused.
The rule is the sibling's, not mine.** Three signed commits authored by
`227570927+JourneyOfLife@users.noreply.github.com` were pushed to `main` and GitHub refused
the update outright:

```
remote: error: GH006: Protected branch update failed for refs/heads/main.
remote: - Commits must have verified signatures.  Found 3 violations:
remote:     cf60533ddc0944422dd396633f73941f84148ee3
remote:     ab190a3ca2ba57ced7ed0c90e4856ce3f3e54891
remote:     54bc3f0197287b91ac7d389964670c4603568bce
 ! [remote rejected] main -> main (protected branch hook declined)
```

The single sentence I built the refutation on was invalid evidence, and reading the whole
verification object shows why: `jol-devops@3c8f9dcf` has
`payload = "… author IterVitae <134775791+IterVitae@users.noreply.github.com> … committer
GitHub <noreply@github.com> … Initial commit"`. That is **GitHub's own web-UI commit, signed by
GitHub** — it says nothing about a user-key signature over a noreply-authored commit. Checking
`committer` and the subject before counting it as a sample would have caught it; `has_sig=true`
and `reason=valid` were not enough.

The mechanism, established by a clean A/B on this host: **same** GPG key
`609F7926A8254CDB`, **same** repository, **same** protection —
`author=journey4oflife@gmail.com` → verified and pushed for every commit in the fleet's
history; `author=<ID>+JourneyOfLife@users.noreply.github.com` → refused. So the differentiator
is the author address, and GitHub requires it to be a **verified email on the account that
owns the signing key**. The ID-prefixed noreply address is not in that list
(`gh api user/emails` → `journey4oflife@gmail.com` only), which is exactly what
`~/.gitconfig.d/jolarca` predicted. That note is correct and my "refuted" entry is retracted.

Applied in consequence: `~/.gitconfig.d/jol` reverted to `journey4oflife@gmail.com` with this
reasoning written into the file, because it is the only identity that can push at all. The
disclosure argument for the noreply form is still real — it is simply not available until the
address is added under github.com/settings/emails (UI-only; `POST /user/emails` → 404 for
tokens) and re-read as verified from the API. Note that the base mailbox is already published
in every existing commit of the fleet and is public on the profile, so continuing to use it
adds no new exposure; the noreply switch was later **declined outright** — see *Resolution*
below — but it was never a live leak.

**Resolution — why the noreply switch was declined rather than queued.** Counted on this host:
**1,151 of 1,341 commit objects** across `/opt/jol/repos` are authored by
`journey4oflife@gmail.com`, in an organization where **40 of 41 repositories are public**
(`gh api orgs/journeyoflife-org/repos` grouped by visibility), the same address is the
account's **public profile field**, and it is the **UID of the signing key** itself. A
forward-only author-field change withdraws none of that; only a history rewrite would, and
signed commits + linear history + blocked force-push forbid it by design — those are the
controls this repository exists to protect. So the residual privacy gain is approximately
zero while the cost already measured is an estate-wide push lockout. Chasing it further would
trade a working control for a cosmetic one. Recorded as accepted risk **RA-05**.

What actually matters for reachability, and is done or pending: private vulnerability
reporting enabled on 40/40 public repositories, `+jol.privacy` published as the DPO contact,
`+jol.billing` as the organization billing address — none of which depends on the author
field. The remaining real work is the 26-repo contact sweep in S1-003, which replaces
deliverability-free addresses, not this one.  
**Cross-estate consequence, needs the sibling session's attention:** `/opt/jolarca/` is still
configured to author as the noreply address, and that estate holds roughly 67 commits on no
remote. Scanned on this host, `required_signatures` on their `main` branches:
**`jolarca-docs` enforces it** — pushes from that estate's noreply identity will be refused
there with the same GH006 — while 9 other repositories do not enforce it (which is why 3
noreply commits already pushed to `jolarca-control` succeeded, each carrying an unverified
badge), and **`jolarca-dr` and `jolarca-consent` returned `404 Branch not protected` at all**,
which in a PCI-scoped organization is the larger finding of the three. Their own
`~/.gitconfig.d/jolarca` now carries this measurement. JourneyOfLife-org, for contrast,
enforces signatures on `main` in every repository sampled (`jol-control`, `jol-core`,
`jol-devops`).

Applied: `~/.gitconfig.d/jol` rewritten to the noreply address with its rationale, mode 600,
and `includeif.gitdir:/opt/jol/.path` re-enabled. *(This application was later reversed — see
Update 2; the noreply author address is refused by `required_signatures`.)*
`~/.gitconfig.d/jolarca` was independently
rewritten at 19:36 by the jolarca-dev session to the same noreply address — two control planes
now agree, and V-002 is closed forward-only. Isolation verified by `--show-origin`: each
estate names exactly one include file, and `/opt/jol/` does not match `/opt/jolarca/`. The
bare Gmail stays as the global fallback so an unmatched path still produces pushable commits.
Remaining exception: `jol-hub` carries a repository-local `user.email` that outranks the
include. `+jol.dev` is retained purely as a mail filter.  
**Evidence:** `gh api user/emails`; `gh api -i -X POST user/emails -f emails[]=…` → 404 with
`X-OAuth-Scopes: admin:org, gist, read:user, repo, user:email, workflow`;
`gh api repos/journeyoflife-org/jol-control/branches/main/protection` →
`required_signatures.enabled=true`, `enforce_admins.enabled=true`,
`required_linear_history.enabled=true`; `git config --global --get-regexp '^includeif\.'` →
one line only; `ls ~/.gitconfig.d/` → `viavitae` only.
**Files affected:** `policy/contact-channels.yml`, host `~/.gitconfig` (outside the repo)

### S2-006: `dependabot.yml` files reference labels that do not exist — on 11 of the 12 repositories that use them

**Discovered:** 2026-10-16 from one rendered PR; **scope corrected 2026-10-17 and re-measured
2026-10-19**  
**Status:** PARTIALLY FIXED — `jol-hub` corrected with read-back; 11 repositories still
affected; the vocabulary itself is declared nowhere  
**Original framing, recorded because it was wrong:** this was filed as a `jol-hub`-specific
low-severity defect on the strength of a single PR's rendered comment. Measured fleet-wide it is
systemic: **41 repositories, 14 with a `.github/dependabot.yml`, 12 of them declaring `labels:`,
and 11 of those 12 referencing labels the repository does not have.** Only `jol-hub` has been
fixed. Severity is unchanged (S2) — this degrades triage routing, not a control — but the scope
claim was.
**Finding:** GitHub does not create labels on a PR's behalf. It applies what exists, silently
drops the rest, and says so on the conversation: *"The following labels could not be found: …
Please create them before Dependabot can add them to a pull request."* Measured missing sets
(fresh scan, 2026-10-19, identical to 2026-10-17):

| repository | labels missing | still present |
|---|---|---|
| jol-analytics-ai | `security` | 11 |
| jol-auth | `dependencies`, `github-actions`, `python` | 9 (defaults only) |
| jol-bitrix24-integration | `ci`, `dependencies`, `security` | 9 |
| jol-docs | `ci`, `dependencies` | 9 |
| jol-dr | `ci`, `dependencies` | 9 |
| jol-ecommerce-engine | `ci`, `dependencies`, `javascript`, `python` | 9 |
| jol-infrastructure | `ci-cd`, `dependencies`, `production`, `terraform` | 11 |
| jol-mcp-servers | `ci`, `compliance-server`, `dependencies`, `docs-server`, `git-server`, `jira-server`, `python` | 9 |
| jol-policies | `ci`, `dependencies` | 9 |
| jol-repo-template | `dependencies`, `github-actions`, `python` | 9 |
| jol-scripts | `ci`, `dependencies` | 9 |

`jol-hub` referenced ten labels and had none of them; eleven were created (`dependencies`,
`github-actions`, `terraform`, `infrastructure`, `ci`, `ci-cd`, `docker`, `backend`, `frontend`,
`javascript`, `python`) and read back: 20 labels present, `missing=[]`. The live proof that the
defect is real and unfixed elsewhere is `jol-auth#19`, an open dependabot PR with `labels = []`.
**Impact:** automated dependency PRs arrive unlabelled across the fleet, so label-based triage —
the mechanism that would separate a Terraform bump in `jol-infrastructure` from a routine npm
bump, or a security bump from a feature bump in `jol-analytics-ai` and `jol-bitrix24-integration`
— does not happen. It also proves the configuration was never exercised end to end.
**Why "fix all 11" is not the whole answer:** there is no authoritative label vocabulary to fix
them *to*. `GET /orgs/journeyoflife-org/labels` returns `404 Not Found` on this plan
(organization-level labels are not available), and `grep -rn labels policy/*.yml repos/*.yml`
returns nothing — the only hit is prose in `policy/contact-channels.yml`. Creating the union of
every referenced label in all eleven repositories would be eleven out-of-band mutations with no
declarative source, which is the same ungoverned-control pattern S1-008 describes.
**Remediation, in order:** (1) declare a minimal vocabulary in `jol-control` (a
`policy/label-vocabulary.yml`, or a `labels:` key in `policy/repo-defaults.yml`) covering what
routing actually needs — `dependencies`, `security`, and the ecosystem labels dependabot
references; (2) then either create those labels per repository or strip the `labels:` keys that
name anything else, in one pass, alongside the S1-003 contact sweep so the PR count does not
triple; (3) add a check that fails when a `dependabot.yml` names a label the repository lacks —
cheap, local to this repository, and it makes the class unrepeatable. Note two referenced labels
that belong to no sensible vocabulary (`compliance-server`, `docs-server`, `git-server`,
`jira-server` in `jol-mcp-servers`; `production` in `jol-infrastructure`) — those are candidates
for removal, not creation.
**End-to-end caveat:** creating labels does not retro-label an existing PR. `jol-hub#151` keeps
its old notice; proof arrives with the next dependabot PR, or immediately via a `@dependabot
recreate` comment, which is a write into another repository and needs the owner's word.
**Evidence:** read-only fleet scan, run twice (2026-10-17, 2026-10-19) with identical results:
for each repository fetch `contents/.github/dependabot.yml?ref=main`, collect every `labels:`
entry in both block and flow style, compare against `GET /repos/{org}/{repo}/labels?per_page=100`,
and report the set difference — exit codes 0 evaluated-clean / 1 mismatch / 2 could-not-enumerate
(no repository was blind: `blind = []`). Label creation in `jol-hub` verified by cache-busted
read-back rather than by the POST echo.
**Files affected:** `journeyoflife-org/<11 repos>/.github/dependabot.yml` (not managed by this
control plane); no file in `jol-control` declares a label vocabulary

### S2-007: state-gate's stale-copy detection missed the one copy that diverged

**Discovered:** 2026-10-27  
**Status:** FIXED  
**Finding:** the stray filter was `x.suffix in (".backup", ".bak") and ".tfstate" in x.name`.
`pathlib.Path("terraform.tfstate.backup_20260930_213529").suffix` is `.backup_20260930_213529`,
so timestamped copies were invisible to it. The three files on this host:

| File | Serial | Resource blocks | Detected before the fix |
|---|---|---|---|
| `terraform.tfstate` | 306 | 4 | live |
| `terraform.tfstate.backup` | 304 | 4 | yes |
| `terraform.tfstate.backup_20260930_213529` | 301 | **5** | **no** |

The missed copy is the divergent one. It alone still records `github_team.security` (1 instance),
which live state dropped between serials 301 and 306 — so the NOTICE, whose own text warns that "a
human restoring the wrong one silently reverts inventory", fired on the near-identical copy and
stayed silent about the only copy that could actually revert something.

**Impact:** moderate, and it is a control-accuracy defect rather than an exposure. Nothing applies
from a stray file automatically. The risk is a human restoring the wrong file during exactly the
incident this repository is already carrying under S2-003 — one local state file, no locking, no
versioning. A gate that reports the harmless copy and misses the harmful one trains the operator to
read the NOTICE as noise.

**Resolution:** a shared `stale_state_copies(root)` helper matching on the **name** rather than the
suffix, excluding the live `terraform.tfstate`, excluding directories (so `terraform.tfstate.d/`,
which Terraform *reads*, is never reported) and excluding dotfiles (so the transient
`.terraform.tfstate.lock.info` is never reported). Both former call sites now use it, so they cannot
diverge again. `make state-gate` on this repository now reports
`2 stale state cop(ies)` and names both.

**Regression test:** four assertions — a timestamped copy must be named; the plain `.backup` form
must still be named (a fix that only catches timestamps is not a fix); both together must count as
two; and a workspace-state directory plus a lock file must **not** be reported. These assert on the
gate's *output*, not its exit code, because a stray NOTICE never changes the verdict — which is
precisely why an exit-code-only suite passed over the defect. `tests/test_state_gate.sh` previously
had **zero** coverage of the stray path (`grep -iE "backup|stray|stale"` → no match), against
AGENTS.md §7's requirement that a gate ship with fixtures derived from real captured output; the
filename in the fixture is the real artifact's name. Against the pre-fix gate the timestamped
assertions fail.

**Files affected:** `scripts/state_gate.py`, `tests/test_state_gate.sh`

### S2-008: `make lint` modified the working tree, editing a `prevent_destroy` block

**Discovered:** 2026-10-27  
**Status:** FIXED  
**Finding:** `Makefile` defined `fmt: terraform fmt -recursive` — the *rewriting* form — and
`lint: fmt validate`. AGENTS.md §3 listed `make fmt` / `make lint` among the verified commands,
alongside `terraform validate`, with no note that either writes. Because `repositories.tf` was not
format-clean (S2-009), running `make lint` rewrote line 66: inside the `github_repository.repo`
`lifecycle` block that holds `prevent_destroy = true`, which AGENTS.md §4 forbids changing without
explicit in-session human approval. The documented way to verify this repository therefore made a
gated edit, silently, as a side effect.

**Observed, not hypothetical.** During read-only discovery this session ran
`terraform fmt -diff repositories.tf` and found the file modified afterwards. **`-diff` is not
`-check`**: it displays the diff *and still rewrites the file in place*. Only `-check` is
non-mutating. The resulting change was verified as `git diff -w --numstat` → empty, i.e.
whitespace-only with no semantic effect, and `prevent_destroy = true` /
`ignore_changes = [auto_init, template]` byte-identical. It is also exactly the change later
approved for S2-009, so it was kept rather than reverted — but it was an unintended mutation of a
protected block, and it is recorded here because the hazard is the command, not the outcome.

**Resolution:** a new `fmt-check` target (`terraform fmt -check -recursive`); `lint` now depends on
`fmt-check validate`; `fmt` is retained but documented as mutating. AGENTS.md §3 was rewritten so the
three targets state plainly which one writes. `make lint` verified `RC=0` and confirmed
non-mutating by `git status` afterwards.

**Files affected:** `Makefile`, `AGENTS.md`

### S2-009: `terraform fmt -check` fails at HEAD, and nothing enforces it

**Discovered:** 2026-10-27  
**Status:** FIXED (formatting). **CI enforcement still absent** — deliberately not added here.  
**Finding:** `terraform fmt -check -recursive` exits **3** on `repositories.tf` at `26132e8`. Root
cause pinned by extracting each revision to a temp directory and checking it there, rather than by
reading the diff: clean at `29fb05e` and `0266bdd`, **first broken at `226fa5c`** ("fix: exclude
private repos from branch protection; ignore template drift"), still broken at HEAD. That commit
changed `ignore_changes = [auto_init]` to
`ignore_changes = [auto_init, template] # template is computed from API for repos created from
templates`; the longer line with a trailing comment makes `terraform fmt` want the sibling
`prevent_destroy` comment padded so both align.

`grep -rn fmt .github/workflows/` returns no match, so no CI job enforces formatting and nothing
caught it across four commits.

**This contradicts a previously recorded claim.** A prior session's notes assert that
`terraform fmt -check -recursive` passed. It did — at `0266bdd`. It stopped passing at `226fa5c`.
Both statements are true of different revisions, which is why the claim is dated here rather than
deleted.

**Impact:** low in itself, but it falsifies any "the local verification suite is green" claim, and
that claim is part of the change-management evidence this repository presents. It is also the
precondition that made S2-008 dangerous: a clean tree plus a mutating `lint` would have been
harmless.

**Resolution:** the one-line comment alignment applied, with explicit in-session human approval
because it lands in a §4-gated `lifecycle` block. `make fmt-check` now exits 0 and
`terraform validate` still reports `Success!`.

**Still open:** no CI job runs `fmt -check`, so the next unformatted commit lands silently again.
Adding `terraform fmt -check -recursive` to `apply.yml`'s `Dev — Validate` is recommended; it was
not done here to keep this diff to the defects actually confirmed, and because adding a required
check touches the enforcement posture.

**Files affected:** `repositories.tf`, `Makefile`

### S2-010: two clones of repositories that are no longer in the organization sit in the fleet tree

**Discovered:** 2026-10-27  
**Status:** OPEN — needs an owner decision; not fixable by an edit inside `jol-control`  
**Finding:** `/opt/jol/repos/jol-backend-platform` has
`origin = https://github.com/journeyoflife-org/jol-backend-platform.git`, but that repository is not
in the organization. `gh api repos/journeyoflife-org/jol-backend-platform` resolves only through
GitHub's transfer redirect: `full_name = JourneyOfLife/jol-backend-platform`,
`owner.login = JourneyOfLife` (the personal account), `archived = true`, `visibility = private`.
Local HEAD is `7b99e1a` (2026-09-22) "chore: archive jol-backend-platform (D2 — empty repo,
successor is jol-hub)", dated **after** the remote's `pushed_at` of 2026-02-04, so it carries a
commit that exists on no remote.

**There is a second one, and this entry first reported only the first.** `/opt/jol/repos/obsidian`
carries `origin = https://github.com/journeyoflife-org/obsidian.git`, and `gh api
repos/journeyoflife-org/obsidian` likewise resolves to `JourneyOfLife/obsidian` — personal account,
**public**, `archived=false`. Its HEAD commit is `d0b0fe9` (2026-09-19)
**"SEC-001: Remove exposed GitHub PAT (CRITICAL security incident)"**. So a security-incident record
lives in a public repository outside the organization's governance and outside this control plane,
while its own `origin` URL claims otherwise. Listing `obsidian` in a directory count and then not
checking its remote is the miss; it is recorded here because "I enumerated it" is not the same as
"I examined it".

**This was already known and never persisted.** A prior fleet audit of all 41 repositories reached
the same conclusion — both `jol-backend-platform` and `obsidian` redirect to the personal account —
and it appears in that audit's findings but in no row of this register. So the correct statement is
not "discovered 2026-10-27" but "rediscovered 2026-10-27 after being found and left unrecorded once".
That is the same failure shape as S2-011: an analysis whose output was never written where the next
reader would look.

This is the reconciliation behind the checkout count. `/opt/jol/repos` holds 42 visible entries
against 41 organization repositories: 41 `jol-*` directories plus `obsidian`, of which **40** are
governed, and `jol-backend-platform` **and** `obsidian` are both foreign. Two hidden entries sit
alongside — `.github` (the org-defaults repository, correctly checked out) and `.wt` (an empty
leftover directory).

**Impact:** inventory integrity rather than exposure. A sweep that counts checkouts over-counts the
governed fleet by one; a sweep driven by the allow-list skips this clone silently; and its `origin`
URL only works because GitHub redirects, so `git fetch` succeeds while pointing at a resource
outside the organization's governance and outside this control plane. Given that
`journeyoflife-org` and `jolarca-dev` are deliberately segregated estates, a clone whose stated
remote lies about its owner is the kind of artifact that makes a future separation audit
unanswerable.

**Remediation prepared, not executed** — deleting a clone is destructive and outside this
repository's scope: confirm `7b99e1a` is genuinely superseded by `jol-hub`, then either re-point
`origin` at `https://github.com/JourneyOfLife/jol-backend-platform.git` so the URL states the truth,
or remove the clone. Neither was done: no authorization to delete, and the unpushed commit must be
accounted for first — it is the only copy of that change.

**The only-copy commit is now preserved.** `git format-patch -1 7b99e1a` was written to `/tmp` first,
which is wiped on reboot — so it was moved to `/opt/jol/evidence/2026-10-27-s2-010/` with a manifest
and `sha256 162e0eb4c116fbcda476e4663a10b8c08c021e150cb67db4e6baa96c657344bc`. Integrity was proved
by **reverse-applying** it against the clone (`git apply --check -R` succeeds), which confirms the
patch faithfully represents the commit rather than merely being a file of the right size. The commit
is a 13-line `README.md` change.

**Files affected:** none in `jol-control`; `/opt/jol/repos/jol-backend-platform` is a sibling clone

### S2-011: this register's index omitted S1-009

**Discovered:** 2026-10-27  
**Status:** FIXED  
**Finding:** S1-009 has a full entry, is cited from AGENTS.md §2, and is cited again from the
Methodology section at the end of this file — but the index table ran S1-008 then jumped straight to
S2-001. The document's own preamble states that entries are kept in numeric order.

**Impact:** a reader auditing by index concludes there are eight S1 findings and misses the one
saying that seven governance-tier repositories hold branch protection in state and none on GitHub —
the most consequential entry in the register. This is the index/body drift this register has already
been burned by once during the S1-002 closure.

**Resolution:** index row added, with the status text taken from the entry's own `**Status:**` line
rather than paraphrased. Every `### S1-…` and `### S2-…` body heading was compared against the index
in the same pass; S1-009 was the only omission.

**Files affected:** `docs/drift-findings.md`

### S2-012: an agent destroyed the live `terraform.tfstate`; recovery depended on a backup no runbook named

**Discovered:** 2026-10-27  
**Status:** RECOVERED byte-exactly. **Partially closed, and the residual is now a different risk than
the one this finding opened with.** RB-08 covers creating *and* restoring an encrypted backup; the
create script is a committed artefact with a 23-case suite. **The first off-disk snapshot was written
on 2026-10-27** (`sdb1`, serial 306, lineage `25425c0f-…`, 119 instances, md5 `b25b8821…`), so
single-NVMe loss no longer destroys the inventory together with every copy of it — the condition that
made this incident nearly unrecoverable. The script now *enforces* that separation and refuses a
same-disk destination. **Still OPEN:** no schedule runs it (the snapshot is manual, and the live state
has not changed since, so staleness is zero today and unbounded tomorrow); the second identity is
**still on this host**, so off-*host* loss — fire, theft, whole-machine failure — still takes the state
and both custodies together; the destination is a session automount that does not exist after a headless
boot; `sdb` is a 2012-era spinning drive whose SMART health is unverified; and no harness for the script
runs in CI on a pull request, because `apply.yml` triggers on `push: main` only.  
**Finding — what happened, attributed to this session.** While testing the S1-012 fix, a shell
command built a temp directory with `T=$(mktemp -d)` but **never `cd`'d into it**, so every
following redirection resolved against the repository root. Two statements then acted on the real
file: `printf … > terraform.tfstate` overwrote the live inventory with a 30-byte stub, and a later
`rm -f terraform.tfstate` in the next test case deleted it. The single copy of the infrastructure
record for 40 repositories was gone. AGENTS.md §4 lists `terraform.tfstate` as *"Read-only, never
edit"*; a command that writes to it while intending to write to a scratch directory is precisely the
hazard that rule exists to prevent, and the mitigation that should have been in place — running the
test inside the temp directory, or under `mktemp -d` with an explicit `cd` and a trap — was omitted.

**How it was recovered.** `find` over `/opt/jol` and `/home/jol` surfaced
`/opt/jol/backup/tfstate/jol-control-terraform.tfstate.*.age` — three `age`-encrypted snapshots.
All three decrypt to **byte-identical** state, matching the checksum this session had recorded from
the live file during phase 0:

| Attribute | Destroyed file | Decrypted backup |
|---|---|---|
| bytes | 195,121 | 195,121 |
| md5 | `b25b88219552d3d5a47c749e2b3d85a5` | `b25b88219552d3d5a47c749e2b3d85a5` |
| serial | 306 | 306 |
| lineage | `25425c0f-0345-f6ff-4f27-6d8b76339c06` | identical |
| instances | 119 | 119 (40 repo + 40 vuln + 11 gov BP + 28 std BP) |

The restore was verified three independent ways: the md5 matched, `terraform state list | wc -l`
returned 119, and `make state-gate` answered `SAFE` with exit 0. Plaintext was never printed — only
`serial` / `lineage` / counts were read out with `jq`. The procedure is now
`docs/runbooks.md` **RB-08**, executed and confirmed rather than written from memory.

**Why the recovery is not the finding — the documentation is.** Three things are false or missing
that this incident exposed:

1. **`Makefile` asserted the opposite.** `make apply` printed *"WARNING: this host holds the only
copy of terraform.tfstate."* It does not: three encrypted copies exist on this host. The warning's
*intent* — no off-host copy, be careful — is correct and worth keeping, but a false literal in the
one place an operator reads about state risk is worse than no warning, because it also hides that a
restore path exists. Corrected to state what is actually true.
2. **No runbook referenced the backup set.** `docs/runbooks.md` had RB-01…RB-07 and nothing about
restoring state. `docs/SECRETS_INVENTORY.md` names the age identity (row AGE-1) and the
`vault-<UTC>.bundle` artifacts, but never tells a responder that the state snapshots sit beside them
or how to verify one. Recovery today worked only because a `find` was run during an unrelated audit.
3. **The backups are manual and unverified.** No `crontab` entry and no `systemd` timer refreshes
`/opt/jol/backup/tfstate`; the newest jol-control snapshot is 2026-10-20, seven days before this
incident. Nothing had ever tested that the key decrypts them until now.

**Impact:** none realized — the restore is byte-exact and provable. The exposure was real and
narrow: had the phase-0 checksum not been recorded, and had the snapshots not been found, the
recovery would have been `terraform plan -refresh-only`-style re-import of 119 resources by hand,
with `make apply` refusing until then. Because state is gitignored, `git` could not have helped.

**Residual risk, OPEN:** the live state and the long-standing backup set were on **one physical device**
(`/dev/nvme0n1p6` for `/opt/jol/backup`, `/dev/nvme0n1p8` for `/opt/jol`); that is now mitigated by the
`sdb1` snapshot above and by the script's refusal to write anywhere else on `nvme0n1`. What remains:
no check in this repository can rebuild the inventory — `make drift` compares names and visibility, not
attributes — and the copies that survive a device failure still live **inside the same machine**, so the
host-level scenarios are uncovered. This is S2-003's accepted risk (RA-03) re-measured rather than
closed: the risk acceptance said "state is local"; the true statement was "state is local, manually
backed up to the same device, with no restore ever rehearsed until an agent caused one", and it is now
"state is local, backed up on a second disk inside the same host, refreshed by hand".
**Remediation target measured:** `sdb1` (`/media/jol/32f7e56a-…`, 285 G ext4, 270 G free) is a
*different physical disk* and closes the single-device scenario. It was `root:root 755` until
2026-10-27, when `chown`/`chmod 700` took effect and the first snapshot was written; it still needs
`udisksctl mount -b /dev/sdb1` after a headless boot, because nothing in `/etc/fstab` mounts it. It
does **not** cover fire, theft or whole-host loss, and RB-08 now says so. A scheduled refresh, and
running RB-08's verification on a cadence rather than only after a loss, are still the recommendation.

**Process rule adopted:** any shell test that redirects into files named like repository artifacts
must `cd` into its `mktemp -d` directory first and clean up via `trap`, never address repo-relative
paths from an inherited working directory. This session also hit the mirror-image error earlier
(`terraform fmt -diff` mutating a tracked file, S2-008); both are the same class — a command believed
to be read-only that is not.

**Six further defects found while building the follow-up backup procedure, all in commands this
session wrote, all caught by executing rather than by reading — and then **ten more that execution
did not catch**, found by an independent review that read the failure paths the tests never entered,
by reviewing my own hardening commit, or by following the runbook as an operator would:**

1. **`/secure/offhost` was invented.** A destination directory was named in a command without ever
   checking it existed. The real separate disk on this host is `sdb1`, mounted at
   `/media/jol/32f7e56a-…` with 270 G free.
2. **A recovery key was told to live in `/tmp`.** The claim made alongside it — "`/tmp` is wiped on
   reboot" — was **also wrong**: `/tmp` here is on-disk (`/dev/nvme0n1p3`) with policy
   `D /tmp 1777 root root 30d`, so it survives a reboot and is reaped after 30 days. The conclusion
   (move it) was right for the wrong reason, which is the worst kind of guidance. The identity was
   relocated to `~/.config/age/state-recovery-20261027.txt` (mode 600), verified byte-identical by
   `sha256sum` **before** the `/tmp` copy was shredded.
3. **The first version of the backup script reported success for a backup with one custody path.**
   Passing the host identity as the "recovery" identity still printed *"decryptable by both keys"*
   — a green assurance of redundancy that protected nothing. Found by negative-testing the script
   with deliberately wrong inputs, not by reading it. It now compares the two public keys and
   refuses. An earlier draft also called `age --list-recipients`, which does not exist in age 1.1.1:
   it encrypted successfully, then died **before** verifying.
4. **The script was unusable for the scenario it existed to serve.** It required `RECOVERY_KEY`, an
   identity *file*, to run its second verification — so the moment an operator followed the runbook's
   own step 1 and moved that key off the host, the script could no longer run at all. It now accepts
   either `RECOVERY_KEY` (full proof) or `RECOVERY_PUB` (recipient recorded, off-host path printed as
   **`NOT VERIFIED`**, never as a pass). All eight input permutations are tested, including both being
   empty and the supplied public key equalling the host's.
5. **Two backups landing in the same UTC second silently destroyed the earlier one.** The output name
   is `date -u +%Y%m%dT%H%M%SZ` — one-second granularity — and `age` overwrites an existing output
   without warning. Found by running the script twice under a stubbed `date`, where the second call
   *should* have produced two files and produced one. The script now refuses to overwrite, and the
   refused re-run was confirmed to leave the original byte-identical.
6. **A garbage source produced a well-formed backup before anything complained.** With `SRC` pointed at
   an unrelated file the script encrypted and wrote a 5 KB `.age` to the destination, and only the
   *final* `state-gate` check noticed — leaving an artefact on the backup disk that reads exactly like
   a snapshot. Found by testing the failure paths, which is the only way failure paths get found. The
   source is now validated with `jq` **before** any write, and the three bad-source cases (`Makefile`,
   a valid-JSON plan fixture, a 0-byte file) were confirmed to refuse with **zero artefacts left
   behind**.
7. **The verification step wrote PLAINTEXT Terraform state, other-readable, and left it there on every
   failure path.** `DEC="$OUT.decoded"` was created by a shell redirect at the ambient umask — `0002`
   on this host, so mode `664` — and `rm -f "$DEC"` was the *next statement* after a call that can
   fail, so under `set -e` it never ran. The per-function `trap 'rm -f "$t"' RETURN` did not help:
   `RETURN` does not fire when the function calls `exit`, and does not fire when `set -e` aborts
   mid-function. Net effect: the full inventory of 40 repositories, in plaintext credentials, beside the
   ciphertext, on the backup disk — produced by the script this register previously described as
   "fail-closed". That description was itself the overstatement: **the label came from me, the leak
   came from the code, and only the review caught it.** Fixed by `umask 077`, one `EXIT` trap covering
   every temp, and removal of the artefact unless the run fully succeeded.
8. **`state-gate` was invoked without pinning the directory it compares against.** It takes `dir`
   positionally with default `.`, so `--state <backup>` alone judged a valid inventory against
   whatever directory the operator stood in. Measured from a scratch dir it answered **`SAFE` over zero
   resource blocks** — a *vacuous pass*, which is worse than the honest `UNEVALUATED` I had assumed it
   would return. The `REPO` path is now pinned explicitly and derived from neither `SRC` nor `CWD`.
9. **Fixing defect 7 introduced a worse one, caught only by a case written to assert preservation.**
   The new cleanup trap removed the artefact on *any* non-success, so a same-second re-run — which
   correctly refuses to overwrite — then **deleted the original backup**. `[ -n "$OUT" ]` was true for
   a file this run had not created. Hence the `CREATED` flag, and a test that compares the original's
   sha256 and the destination's file count across the refused re-run. A fix is not verified by the case
   that motivated it; it is verified by the case that attacks it.
10. **The Create and Restore halves of the same runbook did not agree.** Create wrote
    `jol-control-tfstate-<stamp>.age` into `sdb1`; Restore enumerated
    `/opt/jol/backup/tfstate/jol-control-terraform.tfstate.*.age`. Neither the directory nor the
    basename matched, so a backup made by the new procedure was **invisible to the recovery procedure
    written on the same day**. Fixed by adopting the existing basename convention, enumerating both
    locations, and writing an `.info` sidecar with `serial`/`lineage`/`instances`/`md5` — which also
    supplies the "checksum of the state you expect" that Restore's own prerequisite demands and that
    previously existed only on a terminal scrollback.

A pasted three-line `sudo` block also ran only its first line: the directory was created but stayed
`root:root 755` and unwritable, which `stat` caught and the transcript did not. Every effect of a
multi-line privileged command must be verified independently.

**Files affected:** `Makefile` (warning corrected; `test` gained a fifth suite and a `backup-state`
 target added), `docs/runbooks.md` (RB-08: restore procedure, then expanded to cover creating a
 backup, then the create-side script promoted out of the fence into `scripts/backup_state.sh` with
 `tests/test_backup_gate.sh`), `scripts/backup_state.sh`, `tests/test_backup_gate.sh`,
 `.github/workflows/apply.yml` (Backup Gate Self-Test), `AGENTS.md` §3, `docs/drift-findings.md`,
 `docs/SECRETS_INVENTORY.md` (new row **AGE-2** plus the 1-of-2 recipient semantics);
 `terraform.tfstate` restored byte-exact, no net change

**Follow-up 11 — the runbook was not runnable, twice.** After the review landed, the document told the
operator to run `backup.sh`. **No such file had ever been created**: the script existed only as a
fenced block, and "copy it out of RB-08" is not an instruction an operator can execute. The attempt
returned `RC=127`, and the line after it failed too because `VAR=value command` scopes the variable to
that command alone, so `cat "$DEST"/*.info` expanded to `/*.info`. Both were defects in prose this
session wrote, found only when someone followed it. The remedy is not better wording: the script is now
a committed artefact (`scripts/backup_state.sh`, proven byte-identical to the fence), the test
(`tests/test_backup_gate.sh`) enforces that identity so the document cannot drift from the code it
describes, `make backup-state` supplies the arguments, and `apply.yml` runs the suite. A runbook that
carries code in a fence has two copies of the code and zero guarantees about which one is true.

**Follow-ups 12–16 — defects in the hardening commit itself, found by reviewing it rather than by
running it.** All five were written by this session; two were claims I had made in prose minutes
earlier.

12. **The sidecar asserted `off-host-verified: yes` about a key it never located.** The field was set
    from `RC = 0`, which means *a second identity decrypted this file*. It says nothing about where
    that identity is stored — and the identity in question is `~/.config/age/state-recovery-20261027.txt`
    on **the same host as the state**. So every sidecar written so far declared off-host custody while
    the off-host condition was false. Replaced by three fields that do not conflate the claims:
    `recovery-key-decrypted` (what was proven), `recovery-key-location : NOT CHECKED` (what was not),
    and `device-check`. This is the precise shape of an overstated control: the word carrying the risk
    was the word nobody could test.
13. **A check was documented as impossible that is available for free.** RB-08's Limitations stated the
    script "does not verify that `sdb1` is a different physical device (it checks writability only)".
    `findmnt -no SOURCE --target` then `lsblk -no PKNAME` resolves the disk under any path, with no
    privileges, and returns `nvme0n1` versus `sdb` here. The script now **refuses** a same-disk
    destination — which rejects the exact layout this host had before any of this (state on `p8`,
    backups on `p6`, one die). Where the tools cannot resolve a path, the run warns and records
    `device-check: unevaluated` rather than passing silently.
14. **The chosen destination is a desktop-session automount, not a system mount.** `/etc/fstab` holds
    zero `media` entries; the systemd unit is generated from `/proc/self/mountinfo`; the path embeds
    the filesystem UUID. After a headless boot, a crash, or any start without GUI login the directory
    **does not exist** — and the Restore half globbed exactly that path. An empty glob would read as
    "the off-disk backups are gone" and could send an operator to rebuild 119 resources by hand. Both
    halves now preflight the mount and distinguish *not mounted* from *nothing there*.
15. **The device table omitted what kind of disk it is.** `sdb` is a Seagate **ST9320423AS**, 298 G,
    SATA, `ROTA=1` — a 2012-era spinning laptop drive sharing this machine's supply and backplane. It
    removes single-NVMe risk and nothing else; SMART health is unverified because `smartctl` needs a
    password. "A real improvement and a weak end state" is now the wording.
16. **The CI coverage claim was wrong in its own comment.** `apply.yml` triggers on
    `push: branches: [main]`, so the Backup Gate Self-Test has **not** run in CI at all: PR #4's checks
    are Compliance Scan only (3 pass, 1 skip). The step comment said "18 cases" when the suite held 20,
    then 23 — a count nothing enforced. Corrected, and the caveat is now stated in the comment itself.

**Harness defect found while adding the device cases.** The `lsblk` stub inspected `$1`, which is
`-no` — so it returned nothing for every device, the device check silently never ran, and the
same-disk case still exited 1 because the deliberately-fake identity file failed afterwards. **Right
exit code, no proof at all**, and it would have been committed as coverage. Caught because the
assertion also requires a verdict line, which came back `no-verdict`; the case now additionally asserts
that the stubs resolved. Recorded here as the latest instance of traps 11–15.

### S2-013: a recovery identity was destroyed before its off-host copy existed

**Discovered:** 2026-10-27  
**Status:** OPEN. The preventing control is built, tested and committed; the key itself is gone and must
be re-minted by the owner. AGE-2 in `docs/SECRETS_INVENTORY.md` records the loss rather than erasing it.  
**Severity:** S2, not S1 — **no data was lost**. The severity is custody redundancy: a control was
declared and then irreversibly disarmed, by following the documented procedure.  
**Confidence:** high; every claim below was measured on this host the same day.

**Finding.** RB-08 step 1 told the operator to mint a recovery identity, copy it off-host, verify the
copy, and only then delete the local half. The identity was shredded first. The private half existed
nowhere else: five other age identities on the host (`sops/age/keys.txt`, `/opt/jol/.sops/age-jol.txt`,
`/opt/jolarca/.sops/age-jolm.txt`, two viavitae operator keys) and two session transcripts were each
attempted against the snapshot it had encrypted, and **every one returned zero bytes with `rc=1`**;
only AGE-1 opens it, at 195,121 bytes and md5 `b25b88219552d3d5a47c749e2b3d85a5`, matching the live
state. The one off-device snapshot is therefore single-custody, held by a key on the same machine as
the state — which is the exact condition S2-012 was opened to remove.

**Root cause, attributed to the instruction, not the operator.** The runbook put three ordered actions
inside one lettered step and rendered the irreversible one as a **self-contained copy-paste line**:
```bash
shred -u ~/.config/age/state-recovery-20261027.txt
```
Nothing in the tooling conditioned that command on the proof having happened. Advice about ordering is
not a control: it survives an attentive reader and fails a hurried one, and the whole point of an
off-host copy is that it is produced by a human leaving the machine, which is the least attentive moment
in the procedure. Two earlier defects in the same instruction chain — a placeholder filename that ran
verbatim and minted a live private key, and a `/tmp` location justified by a false claim about reboot
clearing — were the same failure wearing different clothes.

**Fix, and why it is shaped this way.** `scripts/retire_recovery_key.sh` makes the proof a
precondition of the deletion rather than a preceding paragraph. Phase 1 emits a random nonce,
encrypts it to the recipient under test, and stores the expected answer **only as a hash**; phase 2
refuses unless the caller supplies a nonce that only the private half can recover, which is evidence
that a working copy exists somewhere this machine cannot read. It deletes nothing until then, refuses
to place the challenge beside the identity it is testing, rejects a stale nonce against a new identity,
and leaves the identity in place on every refusal path — because a gate that destroys on failure is
worse than no gate at all. `tests/test_retire_gate.sh` holds 12 cases; two mutations (a vacuous proof
comparison, and removing the proof check) each make the suite fail, so the gate is shown to be able to
catch its own removal.

**Second-order effect, deliberately kept.** `backup_state.sh` requires a recovery recipient *different*
from the host key, and `state_backup_guard.sh` exits **2** rather than running when no recipient is
recorded. So with the identity gone, further backups are **refused**, not silently degraded to one key.
That refusal is the control: the schedule cannot quietly produce a single-custody artefact and call it
a backup. It does mean the estate is currently unable to refresh the off-device snapshot until a new
identity is minted and carried off-host, which is the honest cost of the loss and is stated here rather
than smoothed over.

**What is NOT fixed by any of this.** The destroyed key cannot be recovered, so any future need to open
that specific snapshot depends on one key on one machine. Re-minting (AGE-3) protects every *future*
snapshot; it does not retroactively protect `20261027T183202Z`. A restore rehearsal on the new path
(RB-09 step 5) is the only thing that converts "two custodies" from a claim into a measurement.

**Files affected:** `scripts/retire_recovery_key.sh`, `tests/test_retire_gate.sh`,
`scripts/state_backup_guard.sh`, `tests/test_backup_gate.sh` (cases 24–32), `Makefile`
(`retire-key`; `test` gains the retire suite), `docs/runbooks.md` (RB-08 step 4, RB-09),
`docs/SECRETS_INVENTORY.md` (AGE-2 → destroyed, AGE-3 → pending), `.github/workflows/apply.yml`,
`AGENTS.md` §3.

**Follow-up 17 — the gate built to prevent this had the same hole, and the failed `cp` is the only
reason it was not walked into.** The first version proved *"a private key recovered the nonce"* while
that private key was still on this host and no second copy existed. Minutes later the operator ran
`cp` of the freshly minted identity to the second disk, and it **failed** — that volume's root is
`root:root 755`; only `jol-state-backup` is writable — leaving exactly one copy. Running the ceremony
anyway would have retired the local file, produced a `0` and a message about off-host proof, and
finished with the key **destroyed and nowhere else**. Proving separation is now required: the challenge
directory must resolve to a different physical disk than the identity, and an unresolvable device is a
refusal rather than a warning, because this operation cannot be undone. Cases 13–15 cover it (15 total).
Two secondary lessons from the same fix: the test stub was written with a **quoted heredoc**, so a
`$W` inside it never expanded and was unset at run time — the identical class as trap 14's silent
no-op, arriving from the opposite direction; and a sentence left dangling mid-edit was caught only by
re-reading the published file.

### S2-014: the off-device snapshots are undecryptable in the scenario they exist for

**Discovered:** 2026-10-27  
**Status:** OPEN. This is a design gap in the control built for S2-012/S2-013, not a regression: the
mechanism works exactly as specified, and the specification omits the thing that matters.  
**Severity:** S1 — the inventory of 40 repositories would be unrecoverable in the target scenario, and
every signal this repository emits today says the opposite.

**Measured placement, resolved with `findmnt --target` then `lsblk -no PKNAME`:**

| Object | Device |
|---|---|
| live `terraform.tfstate` | `nvme0n1` |
| `~/.config/age/state-backup-key.txt` (AGE-1, the only key that opens **every** snapshot) | `nvme0n1` |
| `~/.config/age/state-recovery-20261027-b.txt` (AGE-3 recipient of the newest snapshot) | `nvme0n1` |
| `…T183202Z.age`, `…T193132Z.age` (the off-device snapshots) | `sdb` |
| three older snapshots under `/opt/jol/backup/tfstate/` | `nvme0n1` |

**No key existed on `sdb`, and none existed off the machine.**

**Update, same day — the interim mitigation applied, and it moves the risk rather than removing it.** A
copy of the recovery identity was placed on `sdb` (`sha256 ad7d3c2c…`, matching the local file, and
confirmed to decrypt `…T193132Z.age` to the expected md5). The NVMe-death scenario is therefore now
covered. What it costs is stated by counting what sits on each device:

| Device | snapshots | private keys |
|---|---|---|
| `sdb` | 2 | **1** |
| `nvme0n1` | 3 (older set) | **2** |

**Each device now holds a key together with data that key opens.** Physical theft of either disk yields
the infrastructure inventory of 40 repositories, including whatever credentials the state records. The
`keys/` directory also arrived as mode `775` (group/other may list it) where the file inside is `600`, so
the tight form is `chmod 700` on the directory.

The retirement ceremony must therefore **not** be run to "close" this. Its prompt says *the machine that
holds the OTHER COPY*, while the only other copy is on `sdb` in the same chassis: completing it proves a
copy on another **disk** can decrypt — which is exactly what the gate claims and nothing more — and it
would leave the surviving key sitting beside the ciphertext. `AGE-1` opens every snapshot regardless, two
recipients being 1-of-2, so retiring the local half buys no redundancy and worsens the theft posture.

**Consequence, as first measured.** If `nvme0n1` failed, the live state and **both private keys** were
lost together. The ciphertext on `sdb` survived and was worthless: `age` without any recipient's secret
half cannot be recovered by anything. The device failure the off-device copy was built to survive was
precisely the failure that destroyed the ability to read it. The interim copy above closes that specific
scenario; **whole-host loss (fire, theft, ransomware, a power event taking both disks) still takes the
state, both keys and every snapshot that is not off-machine, which is the remainder of this finding.**

**Why every existing signal missed it.** `backup_state.sh` reports
`device-check : verified-different: state=nvme0n1 backup=sdb`, which is **true and irrelevant** — it
compares the plaintext to its copy. The sidecar states `recovery-key-location : NOT CHECKED`, which is
honest but silent about the case that matters, and no check anywhere relates the keys' location to the
ciphertext's. An earlier revision of this runbook claimed `off-host-verified: yes` on the strength of a
decrypt (S2-012 follow-up 12); the correction removed a false claim without adding the missing one.
**A check that measures the right-looking pair is more dangerous than no check, because it closes the
question.**

**Fix, in the order that helps.** (1) Put the recovery identity somewhere that is not this machine at
all — another host, a password manager, printed entropy. That is the only arrangement where losing
either disk leaves something readable, and `make retire-key` now refuses to delete the local half until
a copy on a **different disk** proves it can decrypt (S2-013's fix), so the ceremony is safe to run.
(2) A copy on `sdb` alongside the ciphertext does close the NVMe-failure scenario alone, at the cost
that a simultaneous `sdb` failure takes both halves of the pair together; acceptable as an interim, not
as the end state. (3) The right durable control is a check that reports the **key-to-ciphertext**
relation, not just state-to-ciphertext; it cannot be computed locally, because a copy that is
provably elsewhere is by definition not visible here — which is why step 1 is a human act and this
finding cannot be closed by a script.

**Files affected:** none yet; recorded so the next reader does not mistake `device-check:
verified-different` for a complete separation claim.

### S2-015: a runbook instruction from this repository corrupted the host crontab

**Discovered and closed:** 2026-10-27  
**Finding.** RB-09 step 4 shipped in `ad1aa31` with `sed 's|^\*/10 …|&; … 2>&1|'`. Applying it rewrote
line 12 of jol's crontab to `…state_backup_guard.sh >/dev/null 2>*/10 * * * * …` — `&` in a sed
replacement is the matched text (measurement trap 18). Left in place it would have made cron execute a
malformed command every ten minutes on a machine whose only backup discipline depends on that timer
running.  
**Detection, and why it was nearly missed.** The same command printed `line count 12` and
`guard occurrences 1` — both "passing" — and truncated the line at 200 characters. A count and a
truncated view are what hid it; `diff` against the pre-change backup is what showed it. The backup
taken one statement earlier for rollback purposes is the only reason recovery was trivial.  
**Resolution.** `crontab /tmp/crontab.pre-rb09-20261027T220403.txt`, verified byte-identical to the
backup (`diff` empty, guard occurrences 0, final line read in full), then applied with `awk`, whose
string concatenation has no metacharacter. Final state verified by whole-line read and by a diff showing
exactly one changed line — the intended one — and by running the appended command under cron's own
environment (`env -i PATH=… HOME=… sh -c 'cd … && scripts/state_backup_guard.sh'` → `RC=0`).  
**Standing lesson for this repository.** Anything written as a command for a human or an agent to paste
into live host state is production code: it needs a backup taken *before* the mutation, and its
verification must read the entire artifact and its diff, not a count of matching lines.

### S2-016: there is no working push channel, so a scheduled failure notifies nobody

**Discovered:** 2026-10-27  
**Status:** OPEN. Not fixable from this repository. `make backup-status` is the interim: a pull that is
strict, cheap, and honest about exit 2.  
**Severity:** S1 for monitoring claims generally — every "we will be alerted" statement in this estate is
currently false, not merely untested.

**Measured, on this host, 2026-10-27.** An offer was made to add failure notification for the state
backup guard. Checking whether that was possible first:

| Link | Evidence | Verdict |
|---|---|---|
| alertmanager process | `ss -ltn` shows only `*:9090`; nothing on `:9093`; `docker ps -a` lists no alert container | not running |
| Slack receiver | `alertmanager.yaml`: `api_url: https://hooks.slack.com/services/PLACEHOLDER` | literal placeholder |
| `security-email` receiver | `dig +short MX journeyoflife.org` → `0 .` (RFC 7505 null MX) | hard-bounces; S1-003, still true |
| PagerDuty receiver | configured, but with no alertmanager to receive anything | unreachable |
| what Prometheus scrapes | `job_name: prometheus` → `localhost:9090`; one `node-exporter` target `10.30.30.10:9100` labelled `llm-prod-lt01` | not this host, and no alert pipeline behind it |
| any webhook in local scripts | grep for `ntfy.sh\|hooks.slack.com\|webhook\|curl -X POST` over `/opt/jol/scripts` and this repo's `scripts/` | none |

**Consequence.** `state_backup_guard.sh` reports every run to journald, and journald is a **pull**:
`journalctl -t state-backup-guard`. A guard returning 1 every ten minutes for a month would be
invisible until someone thought to look — the identical weakness already recorded for `mount-guard`,
whose FAIL lines went unread while a volume was being destroyed. Pointing the guard at alertmanager
would have produced a green-looking config and no delivery, which is exactly the overstated control this
repository's §6 exists to refuse.

**What would make a real channel.** Any one of: run alertmanager and give it a non-placeholder receiver;
adopt a push service reachable from cron (an `ntfy.sh` topic or similar) and store its token in the
secret store with an `SECRETS_INVENTORY.md` row; or fix S1-003 so a mail address actually accepts mail.
Until then the honest design is the pull plus a verdict that refuses to look like a pass.

**Files affected:** `scripts/backup_status.sh`, `Makefile` (`backup-status`), `AGENTS.md` §3,
`docs/runbooks.md` RB-09.

### S2-017: the first custody rehearsal was theatre, and `backup-status` had no path to a pass

**Discovered:** 2026-10-27, reviewing `c4eb8b6` — authored minutes earlier  
**Status:** CLOSED by replacement: `scripts/offhost_rehearsal.sh`, 13 new cases (suite 32 → 45). Recorded
because the defective version was committed **and pushed**, and nothing that ran it reported a problem.  
**Severity:** S2, with an S1-shaped tail: one of the four defects was a gate that cannot pass.

1. **`backup-status` could not return 0.** The healthy branch ended with
   `[ "$rc" -eq 0 ] && unk "off-machine custody" …`, so success was downgraded to 2 by construction;
   three input variants gave `2 / 1 / 1`. The changelog and the runbook both promised "expect 0 after
   step 5" — a claim about a command that could not produce it. A gate whose pass state is unreachable
   teaches the operator that 2 is normal, which is how every other gate in this estate died.
2. **The manifest held absolute paths.** `sha256sum /tmp/offhost-packet/* > …/SHA256SUMS`; on the other
   machine `sha256sum -c` prints `OK` against `/tmp/offhost-packet/…` — files that exist only at home. My
   own first verification of this very point passed for that reason, and only looked wrong once the source
   directory was deleted. Relocation tests must delete the origin.
3. **A private identity was staged into `/tmp`** (`1777`, reaped after 30 days per `D /tmp 1777 root root
   30d`) beside the ciphertext it opens, with no cleanup step written. The replacement measures the hazard
   instead of pattern-matching the path: an earlier draft refused anything under `/tmp`, which also
   refused a legitimate key directory that happened to live there — caught by the first sandbox run, which
   deadlocked the whole flow. Staging now refuses a world-writable parent (`stat -c '%a'`) and a path
   inside the repository.
4. **The snapshot name was hard-coded** (`…T200234Z`) while the guard writes a new one daily, so the
   packet would name a superseded file within 24 hours. `pack` selects the newest per run.

**The design flaw underneath:** carrying the key and the ciphertext to another machine and decrypting
proves that machine *has* a key; it records nothing re-checkable about custody. The round trip now uses a
nonce encrypted to the recipient, stored here **only as a hash**, recovered on the other machine and
consumed on return — replay is refused, and the attestation **expires** (30 days) rather than turning the
gate permanently green. Proof, not assertion: the same mechanism already in `retire_recovery_key.sh`, which
I had written a worse version of here.

**Also found: an errexit landmine in two committed suites.** Both shell suites declare `set -uo pipefail`
(deliberately — a suite must run and count every case) yet wrapped timeouts in `set +e … ; rc=$?; set -e`,
and that trailing `set -e` turns errexit on **for the remainder of the file**. In `test_retire_gate.sh` it
sat near the end and nothing noticed; in `test_backup_gate.sh` a later `nf=$(grep -c '^FAIL:' …)` — `grep
-c` exits 1 on zero matches — aborted the run after case 32, printing 32 passes and no verdict. Replaced
throughout with `rc=0; cmd || rc=$?`. A test file must not alter shell options it does not restore: the
damage lands on whoever appends next.

**Rollback:** the rehearsal writes only under `~/.config/age/` and its own packet directory; removing
`offhost-attested` returns `make backup-status` to `2`. `make retire-key` stays separately gated and is
not satisfied by an attestation of another *machine*.

**Files affected:** `scripts/offhost_rehearsal.sh`, `scripts/backup_status.sh`,
`tests/test_backup_gate.sh` (32 → 45), `tests/test_retire_gate.sh`, `Makefile`, `AGENTS.md` §3,
`docs/runbooks.md` RB-09.

### S2-018: another project's backup passed this project's freshness gate

**Discovered:** 2026-10-27 22:42, incidentally — while re-reading the crontab to confirm a line count  
**Status:** CLOSED in code (guard, status pull and rehearsal all pin the snapshot identity now); the
destination was split per tree on 2026-10-27 (`/mnt/jol-backup/jol-control`), which is hygiene — the
pinning above is the control, because **both trees run cron as the same user `jol`**, so no directory
mode ever separated them.  
**Severity:** S1-shaped behaviour in an S2 component: a backup control that reports itself satisfied by
someone else's artefact is worse than no control, because it stops the refresh that would have saved us.

**What happened.** A thirteenth line appeared in jol's crontab, added outside this session by the
`jolarca` tree. Observed on the host at 22:42, quoted as seen — *this* project renamed that directory
afterwards, and the line below is the record of what was there, not the current path:
`17 4 * * * cd /opt/jolarca/repos/jolarca-control && BACKUP_DEST=/mnt/jol-backup/jol-state-backup …`.
That destination was the one RB-08/RB-09 chose for `terraform.tfstate`. Its output landed beside mine:
three `terraform.tfstate.s17.*.age` files (100,670 bytes each), newest written 22:42 — minutes before
this was noticed.

**Why that broke my control.** Every consumer selected the snapshot by recency over a wildcard:
`find "$DEST" -maxdepth 1 -type f -name '*.age' … | sort -rn | head -1`. Nothing asked *whose* state the
file protects. Observed directly, with a foreign file planted as the newest:

| Symptom | Measured |
|---|---|
| the guard reported itself satisfied | `OK: newest snapshot is 0h old (< 24h) - nothing to do`, exit **0**, while jol-control's own newest snapshot was hours old |
| the status pull mislabelled the inventory | `newest snapshot  terraform.tfstate.s17.20261027T204235Z.age` — a foreign state, presented as ours |
| a future timestamp read as fresh | `newest snapshot is -632713h old (< 24h) - nothing to do`, exit **0**. A negative age is below every threshold, so a broken clock or a planted file passes |
| identity never checked | the sidecar records `lineage   : 25425c0f-…`, which is exactly the field that distinguishes our inventory from theirs, and nothing read it |

**Fixes, each with a case that proves it is load-bearing.** `state_backup_guard.sh`, `backup_status.sh`
and `offhost_rehearsal.sh pack` now glob `$(basename "$REPO")-terraform.tfstate.*.age` — the name
`backup_state.sh` writes and the RB-08 restore half globs — and announce how many foreign `*.age` files
they ignored. A future mtime is UNEVALUATED (exit 2), never fresh. The sidecar's lineage is compared with
the live state's: a **mismatch** forces a refresh instead of accepting the age, and a snapshot with **no
recorded lineage** is refused as unidentified rather than passed. Cases 46–50, then mutation-tested: name
pinning removed, future-mtime refusal removed, the mismatch force removed, and the unidentified refusal
removed — each caught by its named case, and the third one fails precisely with `said the FORBIDDEN
thing: nothing to do`. The guard file was restored byte-identically after every mutation (`md5sum`
compared each time).

**One bug found in the fix, not in the original.** The first version of the lineage block printed
"DIFFERENT inventory … refreshing anyway" and then fell into the freshness shortcut and **exit 0** —
the prose contradicted the verdict. It is the same shape as measurement trap 15: a check that reports the
right words and enforces nothing reads correct in a log review. `MISMATCH` now gates the shortcut, and
case 48 asserts the forbidden phrase, not just the exit code.

**Residual, operator's call.** Two projects writing one disk is still fragile: this repository now keeps
its own subdirectory, but the jolarca job still points at `jol-state-backup`. Its line is theirs to change
and this project will not edit another organization's crontab — the durable fix is for that job to target
`/mnt/jol-backup/jolarca-control`, which is the pattern this tree now follows.

**Files affected:** `scripts/state_backup_guard.sh`, `scripts/backup_status.sh`,
`scripts/offhost_rehearsal.sh`, `tests/test_backup_gate.sh` (45 → 50), `docs/runbooks.md` RB-08/RB-09.

### S2-019: the proof-of-possession printed the thing only a possessor could produce

**Discovered:** 2026-10-27, reviewing `scripts/offhost_rehearsal.sh` immediately before handing it to the
operator — i.e. five commits after it was written  
**Status:** CLOSED. `pack` now prints `token-sha256 <first 16 hex>…` and never the value; case 52 pins it.  
**Severity:** S2, but it defeats the exact property S2-014 asked for, so worth stating plainly.

`pack` ended with `echo "Here is the local token, for comparison only"; echo "  $TOKEN"`. The token is a
nonce encrypted to the off-device recipient; recovering it on the far machine is what makes the
attestation evidence rather than an assertion. Printing it on this host puts the answer in terminal
scrollback, in IDE local history, in this session's transcript file and in anything that captures stdout.
Anyone holding the transcript could then run `make backup-attest TOKEN=…` from a machine with no key and
get `ATTESTED` written — the gate would still fire, still refuse replays, and certify nothing.

The comment said "for comparison only", which is how this class of defect always reads at the time: a
developer convenience that survives into the shipped path. It also contradicted a rule already recorded
on this host — generated secrets go to a 600 file, stdout gets a fingerprint.

**How the fix was proven non-vacuous.** Case 52 injects a *known* token (`TOKEN=01234567…`, the script
now honours `TOKEN` as an override) and asserts three things: the value is absent from stdout, a
`token-sha256` line exists, and its printed prefix equals the hash of that known value. Reverting the
fix in place — printing the token again — makes the suite report `51 passed, 1 failed` naming
`pack printed the token value`; removing only the fingerprint also fails. Both mutations restored the
file byte-identically (`md5sum` compared each time).

**A second finding, about the harness:** the first mutation run was reported here as "undetected" because
the command printed only an exit code and not the census, and the case had **no `else` branch** — a failed
precondition contributed nothing and said nothing, so a partial run is indistinguishable from a full one.
Both 51 and 52 now announce a skip. This is trap 15's shape again, one layer up: an unreported absence of
evidence is not a pass, including about the tests themselves.

**Files affected:** `scripts/offhost_rehearsal.sh`, `tests/test_backup_gate.sh` (50 → 52 cases).

### S2-020: the gate that tests the backup script could not run where it is scheduled to run

**Discovered:** 2026-10-27, while answering "what will the merge commit actually show?"  
**Status:** CLOSED. `SRC` is an input of `backup_state.sh` and `state_backup_guard.sh`; cases 3, 4, 21, 23
supply a synthetic populated state. Measured runner-shaped census: **30 passed, 22 skipped, exit 0**.  
**Severity:** S2, but note what it would have caused: a red check on the merge commit of a branch whose
only sin is honest testing — the exact condition that trained this organization to click `--admin`.

The suite header claims its guard cases need "jq only — these run anywhere". Four of them did not:
cases 3, 4, 21 and 23 invoked `backup_state.sh` without `SRC`, so it defaulted to
`$REPO/terraform.tfstate` — a file that is **gitignored** and therefore absent from every checkout.
With the state moved aside to simulate a runner, the output was:

```
FAIL  3 destination absent          RC=1 want=1  missing-expected-text
        FAIL: source missing or 0 bytes: /opt/jol/repos/jol-control/terraform.tfstate
FAIL  4 destination inside the repository   … same cause
FAIL  21 refusal names the disk            refused, but not for the disk
FAIL  23 unresolvable disk is not a pass   … same cause
```

Two of those are the worse kind: `RC=1` matched the expectation while the *reason* was a missing input, so
the same default would have made neighbouring assertions pass vacuously (trap 16 again). The guard block had
the same dependency one layer in: `state_backup_guard.sh` hard-wired the state path for its lineage
cross-check, so cases 46–50 skipped on a runner rather than running.

**Fix.** `SRC="${SRC:-$REPO/terraform.tfstate}"` in both scripts, forwarded guard → `backup_state.sh`, and
the lineage check reads the same `$SRC` it is backing up — otherwise "whose state is this" gets answered
about a different file than the one being protected. Guard cases pass `SRC="$SYNTH"`, the fixture that
already existed for case 9 (lineage `test-lineage-0000`), and cases 46–50 read their lineage from it too,
so the identity rules now execute in CI instead of skipping there.

**Method note, because it is the reusable part:** the discovery came from *running the suite under the
conditions its own header claims*, not from reading it. A mirror tree was tried first and produced eight
unrelated failures from path resolution, which taught nothing; the useful instrument was a copy of the
suite placed **inside** the repository (`tests/.ci-sim*.sh`, deleted immediately, `git status` verified
afterwards) with the `age` probe forced false and the real state moved aside and restored, `md5sum` +
`terraform state list | wc -l` confirming the restore. Temporarily relocating `terraform.tfstate` is not a
casual act on this host — it is the file that has been destroyed once here by a `mktemp` without `cd`
(S2-012) — so it was done only inside a block that restores it in the same command and re-verifies.

**Files affected:** `scripts/backup_state.sh`, `scripts/state_backup_guard.sh`,
`tests/test_backup_gate.sh`, `.github/workflows/apply.yml`, `docs/runbooks.md` RB-08.

---

## Resolved

### RESOLVED: jol-dr visibility drift

**Discovered:** 2026-09-30  
**Resolved:** 2026-09-30  
**Finding:** State recorded `jol-dr` as `public`, live GitHub showed `PRIVATE`.  
**Resolution:** Ran `terraform apply -refresh-only` to reconcile state with live. State now correctly shows `visibility = "private"`.

### RESOLVED: jol-auth stale template block

**Discovered:** 2026-09-30  
**Resolved:** 2026-09-30  
**Finding:** `jol-auth` had stale `template {}` block in state (repo was created from template). Terraform wanted to remove it, but API kept returning it.  
**Resolution:** Added `template` to `ignore_changes` in `repositories.tf` lifecycle block.

### RESOLVED: Phantom branch protection in state

**Discovered:** 2026-09-30  
**Resolved:** 2026-09-30  
**Finding:** State had `github_branch_protection.governance["jol-dr"]` but live API showed it doesn't exist (403 on private repo).  
**Resolution:** `terraform apply -refresh-only` removed phantom resource from state. Config updated to exclude private repos from branch protection.

---

## Methodology

Drift detection uses three signals:
1. `terraform plan -refresh-only` — compares state vs live
2. `scripts/drift_detect.py` — compares config vs live. Needs a token that can read the
   whole organization; exit codes are 0 evaluated-clean / 1 genuine drift / 2 **unevaluated**
   (blind or partial listing). A 2 must never be reported as a pass — see S1-002.
3. Manual verification — `gh api` queries for specific resources

`scripts/state_gate.py` (added 2026-10-08) covers the fourth source that the three above do
not: whether the **state on disk** can account for what the configuration declares, before
`make apply` runs. `make apply` is behind `state-gate` and `plan-gate`.

**Last full scan:** 2026-10-19 (read-only fleet re-measurement on this host: 41 live / 40
declared repositories; 39 protection instances across 39 distinct repositories in state serial
306 against 32 protections existing live — see S1-009; 24 rulesets, 20 of them active and
requirement-bearing across 19 repositories — see S1-008; dependabot label mismatch in 11 of 12
declaring repositories — see S2-006). `make drift` was run separately and still reports only
name/visibility agreement; no `terraform plan -refresh-only` was executed, because it rewrites a
file this repository treats as read-only.
