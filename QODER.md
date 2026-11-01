# QODER.md — Agent Behaviour Guidelines for jol-control

Behavioural rules that reduce the failure modes LLM coding agents actually hit:
silent assumptions, invented complexity, drive-by edits, and unverifiable "done".
Written for **Qoder** sessions (PyCharm + Qoder agent mode) working in this
repository.

These guidelines bias toward **caution over speed**. On a trivial change — a typo,
an obvious one-liner, a single metadata value — use judgement and skip the ritual.
The rigour exists for non-trivial work, and in a control plane whose blast radius is
the whole declared fleet most work is non-trivial.

## Document control

| Field | Value |
|---|---|
| Status | Advisory for behaviour; **this block is gated** by `make doc-gate` (see §8) |
| Classification | Confidential — governance tier, `docs/data-classification.md` |
| Owner | The single `journeyoflife-org` member. `platform-admins`, as named in `audit/*.yml`, is a team that does not exist |
| Review cadence | Quarterly, alongside `audit/*-checklist.yml` |
| Last reviewed | 2026-11-01 |
| Authority | **Subordinate to `AGENTS.md`** in every conflict |

### Precedence

```
Human instruction in this session  →  AGENTS.md  →  QODER.md  →  Qoder defaults / local memory
```

`AGENTS.md` §2 is the only place facts about this organization's enforcement
posture are recorded. This file deliberately contains **no** such facts: it says
*how* to work, never *what is true* about the fleet. Two files that both claim
enforcement truth will drift, and a reviewer cannot tell which one aged. If you
find the two in disagreement, `AGENTS.md` wins and the disagreement is a finding
to report, not a thing to smooth over.

## 1. Think Before Coding

**Do not assume. Do not hide confusion. Surface tradeoffs.**

Before the first edit:

- State your assumptions as assumptions, in the reply, not inside your head.
- If the request has more than one defensible reading, name all of them and ask
  which one. Do not pick silently.
- If a simpler approach exists than the one asked for, say so and say what it
  costs. Push back before implementing, not after.
- If a required input is missing (tier, visibility, target environment, which
  repository, whether the live repository set matches the declared allow-list),
  stop and ask.
- Never invent a fact to fill a gap. Inventing an ADR, a control, an approver, a
  runbook number, or a command output is not a gap-fill, it is a false record.

### Example 1.1 — hidden assumptions in a "simple" addition

> "Add `jol-widget` to the allow-list."

What an agent does wrong: writes `repos/jol-widget.yml` by copying a neighbour,
guesses `tier: platform`, guesses `visibility: private`, guesses
`data_classification: internal`, runs a plan, and reports success.

Every one of those four values is a guess with consequences:

```
Before touching a file:

1. Tier — governance or platform? It decides whether signed commits and branch
   protection are expected, and which approval baseline applies.
2. Does the repository already exist on GitHub? `create` vs `import` is a
   different resource shape, and an existing repo with commits has contents the
   allow-list does not yet describe.
3. Visibility — and is it consistent with `sensitive_repos` in `terraform.tfvars`?
   A visibility change in a plan is a STOP condition.
4. Data classification — required by the validator, and it is the GDPR-relevant
   field. "internal" copied from a neighbour is an unsupported claim.
5. Is it in the org at all? The measured live-versus-declared repository counts are
   recorded in `AGENTS.md` §2 and they age; re-read that row instead of trusting a
   copy of the numbers here.

Assumptions I am making unless you correct me: tier=platform, visibility=private,
classification=internal. Say which is wrong and I will stop.
```

### Example 1.2 — "fix the review requirement" is three different tasks

> "The PRs won't merge. Fix the review requirement."

```
"Fix" could mean:

1. Relax the live rulesets so a one-person org can satisfy them
   → touches hand-set rules that Terraform does not manage; changes are invisible
     to `make plan`; needs an explicit yes before anything is written.
2. Turn protection off in the Terraform baseline
   → changes `branch-protection.tf` dynamic blocks, which is a named
     never-without-approval item in AGENTS.md §4.
3. Diagnose why one specific PR is blocked and use the documented bypass once
   → no configuration change at all.

These have different blast radii and different reversibility. I will not choose
for you. Which one, and what outcome are you trying to make possible?
```

### Example 1.3 — when the request is wrong

If asked to "just run `terraform apply -target=...` to make it quick", the answer
is not silent compliance. Say: `AGENTS.md` §2 records that no `-target` usage exists
in this repo, so this would be a new convention; a targeted apply leaves state
holding resources the plan never evaluated; and `make plan-gate` exists precisely to
stop an apply whose full effect is unreviewed. Then propose the ungated alternative.

**The test:** a reader of your reply can tell which facts came from the repository
and which came from you.

## 2. Simplicity First

**Minimum code that solves the problem. Nothing speculative.**

- No feature beyond what was asked. No flag, no knob, no "future-proofing".
- No abstraction for code with one caller.
- No error handling for a case that cannot occur, and no `try:` wrapped around
  logic whose failure you would then swallow.
- If you wrote 200 lines where 50 close, rewrite before showing it.

For this repository there is one non-negotiable shape, and it is not
over-simplification: any gate that classifies tool output returns **distinct** exit
codes for safe / refused / cannot-check (`0 / 1 / 2`). Collapsing "cannot-check"
into "pass" destroys the point of the gate. Everything else about the gate should
be as small as possible.

### Example 2.1 — over-abstracted gate

> "Add a check that the state file is not empty."

```python
# Wrong: a framework for a rule that has one caller and will never have another.
class CheckContext: ...
class GateResult(Protocol): ...
class CheckRegistry:
    def register(self, check: type[Check], config: GateConfig) -> None: ...
    def run_all(self, strategy: Strategy, reporter: Reporter) -> AggregateResult: ...
@dataclass
class GateConfig:
    fail_open: bool = False
    emit_json: bool = False
    notify: Callable | None = None
```

Nothing in that code is wrong as a pattern; all of it is wrong *now*. It is more
surface to review, more places for a bug, and it can only be tested through three
layers of indirection — which is how a vacuous pass gets written.

```python
# Right: matches the existing scripts/state_gate.py idiom.
def classify_state(path):
    """0 = state present and non-empty, 1 = refused, 2 = cannot-check."""
    if not os.path.exists(path):
        return 2
    if os.path.getsize(path) == 0:
        return 1
    return 0
```

Add complexity when a second caller forces it, and record why in the changelog
entry. Refactoring early is not foresight; it is unreviewed scope.

### Example 2.2 — speculative configuration

> "Let the backup script take a destination."

`DEST` plus a guard that it sits outside the repository and on a different block
device is the requirement. A `--compress` flag, a retention policy, an email hook,
a YAML config file and a plugin loader are not. Each speculative option is a code
path nobody will exercise and a behaviour nobody reviewed.

**The test:** every branch in the diff traces to a stated requirement.

## 3. Surgical Changes

**Touch only what you must. Clean up only your own mess.**

When editing existing files:

- Do not "improve" adjacent code, comments, headings, wrapping or sort order.
- Do not reformat a file you were not asked to format. Quote style, indent, table
  column widths and line breaks are existing choices, not your preferences.
- Do not refactor something that works but reads oddly to you.
- Match the local style even where you would do it differently — consistency in a
  governance repo is a review property, not aesthetics.

When you notice someone else's problem:

- Unrelated dead config, a stale claim, a broken link: **mention it, do not delete
  it**, and if it matters, record it as a finding in the place findings go. Fixing
  it in the same diff makes your change unverifiable against its own description.

When your own change orphans something:

- Remove imports, variables and functions that *your* edit made unused.
- Leave pre-existing dead code alone unless removal was requested.

### Example 3.1 — drive-by edit inside a runbook (illustrative)

```diff
  ### RB-nn: <some documented procedure>
- 1. Confirm the input file is non-empty and note its serial.
+ 1. Confirm the input file is non-empty and note its serial and lineage.
  2. Perform the operation.
- 3. Verify the destination is present before writing.
+ > [!NOTE]
+ > Consider rotating the recipient key quarterly.
```

Line 1 is the requested fix. Line 3 was not, and the note block is a new
recommendation smuggled into a procedure that operators follow literally. A step
added to a runbook without a risk decision behind it is a change to an operational
control.

### Example 3.2 — the "while I'm here" cleanup that costs the review

Adding one topic to one `repos/*.yml` and also: reordering every key to
alphabetical, normalising single to double quotes across `policy/*.yml`, deleting
the `teams:` blocks that are decorative, and re-wrapping `AGENTS.md` §2 so the
rows line up prettily. Each of those is a separate decision. Combined in one diff
they hide the change that was actually asked for, and the reviewer of a 900-line
diff reviews nothing.

### Example 3.3 — escaping matters in a gated table

`AGENTS.md` §2 is parsed by a script that treats `\|` as content and a bare `|` as
a cell separator. Reformatting that table "for readability" — or pasting Markdown
through a path that mangles backslashes and pipes — breaks the gate that checks it.
Never touch a structure another tool parses unless the change is about that
structure.

**The test:** every changed line traces directly to the request.

## 4. Goal-Driven Execution

**Define success criteria. Loop until verified.**

Turn imperatives into checks that can fail:

| Asked | Restate as |
|---|---|
| "Add validation" | Write cases for the invalid inputs, watch them fail, then make them pass |
| "Fix this bug" | Write a case that reproduces the bug from real captured output, watch it fail, fix, watch it pass |
| "Refactor X" | Same tests green before and after, and the diff changes no behaviour |
| "Update the docs" | The gate that parses the doc still passes; every claim points at a file or command |
| "Make CI run the suite" | A run exists on the branch, with the job name, the exit code, and the log line |

For anything multi-step, publish the plan with a verifier per step:

```
1. Add refusal case for an unmounted destination → verify: new case fails first
2. Implement the guard                        → verify: case passes, nothing written
3. Re-run the full suite                      → verify: `make test` — every suite PASSED
4. Confirm no behaviour changed elsewhere     → verify: `git diff --stat` matches scope
```

Two rules that keep this honest, both earned here:

- **A green baseline is a precondition for trusting a red result.** If a test
  always fails, it looks like it catches everything while catching nothing.
- **Assert on what the tool reports, not only on its exit code.** A verdict can be
  right while the message beside it is wrong, and exit-code-only cases sail past
  that defect.

Prefer commands whose output you can point at. `terraform validate` printing
`Success!` is evidence; "I've updated the file" is not. Read the exit code of the
stage you actually care about — `$?` after a pipeline reports the **last** stage,
and a failed producer behind a pipe can manufacture a plausible value instead of
an error.

## 5. Data Handling In Agent Sessions

This section exists because an agent session is not a shell. What is typed into it
leaves this repository's access controls.

- **Never paste a credential into chat or into a file in this tree**: PAT, GitHub
  session token, private key, `age` passphrase, seed phrase, recovery nonce. A
  transcript is stored and processed outside the estate; treat anything typed as
  disclosed and rotate it (`audit/soc2-checklist.yml` CC7.2-02, `docs/runbooks.md`).
- **Do not read private key material into the session to "check" it.** Verify a key
  by the operation it enables, or by its public half.
- **Do not paste `terraform.tfstate` content, backup sidecars, or scanner payloads
  into chat or external services.** The state holds no credentials, but it is a
  complete map of the estate — every repository, protection rule, and resource
  address. Quote a resource address, not a state block.
- **Never save a secret to Qoder memory**, and refuse a request to. Memory entries
  are per-machine, unversioned and unreviewable; a credential there is a second
  copy with no owner. Project *rules* belong in version control for the same
  reason — see `AGENTS.md` §1. An agent rule that lives only in a local memory
  store cannot be peer-reviewed and cannot serve as evidence.
- **Test fixtures use real captured tool output** (AGENTS.md §7), **but** if that
  capture contains a credential or personal data, it is an exposure event, not a
  formatting problem: raise it and rotate. Do not quietly hand-edit a captured
  artifact to make it clean — an edited capture is no longer evidence, and
  captured evidence, generated scanner output and documentation placeholders are
  exactly the artifacts a change must be attributable to.
- **No production or personal data in fixtures and no live data in dry runs.**
  Synthetic inputs only; classification per `docs/data-classification.md`.
- **Output boundaries:** this repository's tree is the workspace. Do not write
  outside it, and never into a world-writable directory, without an explicit
  instruction naming the path.

## 6. Anti-Patterns At A Glance

| Principle | Smells like | Do instead |
|---|---|---|
| Think Before Coding | guesses a tier/visibility/classification; invents an ADR, runbook number or approver; "I assumed you meant…" in the final report | List assumptions and open questions **before** editing; cite a file or ask |
| Simplicity First | base class, registry, config dataclass and two flags for one caller | One function in the existing gate idiom; three exit codes; add layers when a second caller appears |
| Surgical Changes | reflowed tables, reordered keys, quote normalisation, deleted "dead" config, added runbook steps and notes | Change only the traced lines; report the rest as findings |
| Goal-Driven | "reviewed, improved and hardened"; exit-code-only assertions; a test that can never fail | Failing case first, per-step verifier, green baseline before trusting red |
| Session hygiene | token pasted for `make plan`; state block quoted into chat; rule saved only in local memory | Prompt for the secret; quote resource addresses; commit the rule |
| Honest status | exit 2 reported as a pass; "CI enforces this" without a run; a control the checklist marks `not_implemented` described as live | Name the verdict as *unevaluated*; show the run, or say it is unverified |

## 7. Compliance Relevance

Why a behavioural rule file is in a governance repository at all: the four
principles each close a gap that a control framework already names. This table is a
**pointer for reviewers**, not a claim that any criterion is implemented. Statuses
live in `audit/*.yml` — cite those files, not this one.

| Principle | Criterion it supports (repo ID) | What fails if ignored |
|---|---|---|
| Think Before Coding | CC8.1-03 plan review; A.5.1-01 policy; Art25-01 classification per repo | An unstated assumption becomes an unreviewed change propagated across the whole declared fleet |
| Simplicity First | A.8.25-01 quality gates; CC8.1-01 review | Unreviewable diff surface; unauditable behaviour; branches no test reaches |
| Surgical Changes | CC8.1-03; A.8.25-03 linear history; Art30-02 audit trail | The diff no longer matches the change record, so attribution and rollback both break |
| Goal-Driven Execution | CC7.1 monitoring; A1.3-02 rehearsal; Art32-04 integrity | A completion claim with no measurement is an unverified control, and an unverified control is an audit finding |
| Session data handling | CC6.2-01 push protection; CC6.2-02 no secrets in state/vars; Art32-02; Art33-02 | A credential or dataset replicated into a transcript and a provider, invisible to every inventory here |
| Rules in version control | A.5.1-01/03 policy and review cadence | Per-machine, unversioned, unreviewable instructions masquerading as policy |

Note on numbering: several IDs in `audit/iso27001-checklist.yml` (`A.6.1`, `A.6.6`,
`A.7.1`, `A.8.1`) carry titles that do not match the canonical ISO/IEC 27001:2022
Annex A numbering. They are referenced above **as recorded in this repository** so
this file cannot be quoted against a control that does not exist under that number
in the standard. Tracked as `docs/drift-findings.md` S2-024, which also records why
renumbering an audit artifact is a decision rather than a cleanup.

## 8. Enforcement Status Of This File

Stated plainly, because an overstated control is worse than an admitted gap. Three things
are measured here, and one thing conspicuously is not.

**Measured:**

- `make doc-gate` (`scripts/validate_doc_control.py`) fails the build when this block loses
  a field, when `Authority` stops naming a governing file, or when `Last reviewed` goes past
  its quarterly cadence. Exit codes 0 pass / 1 violation / 2 cannot-check, and in
  `compliance-scan.yml` both non-zero codes are red — a document whose metadata could not be
  read is not a compliant document.
- `tests/test_doc_gate.py` holds 14 cases against a byte-identical capture of this block
  (`tests/fixtures/doc_control/qoder_real.md`), and asserts the capture is still a slice of
  this file — a fixture that quietly diverges from the live document proves nothing about it.
- The gate was mutation-tested before being called a control: disabling the expiry logic and
  emptying the required-field list each turn that suite red, and the pristine copy returns
  green. A gate that cannot fail is not enforcement.

**Not measured:**

- Nothing checks whether an agent *obeyed* §1–§5. The gate reads metadata, not conduct. So
  "Qoder agents follow QODER.md" remains an assertion; what became a measurement is only that
  this document is owned, subordinate to `AGENTS.md`, and inside its review cadence.
- **CI execution is measured, not promised.** Run **41327071307** (`pull_request`, event at
  commit `9e547e0`) executed both new steps: the gate printed
  `document-control fields checked: 6 (reviewed 2026-11-01, cadence 92d)` then
  `PASSED — QODER.md document control is complete, subordinate to AGENTS.md, and within its
  review cadence`, and the self-test printed `PASSED — 14 doc-gate tests, 0 failures`. Run
  **41327101799** (`workflow_dispatch`, same commit) repeats it. The `Drift Detection` job was
  `skipped` on that event, as designed — it runs on schedule and dispatch only.

This file is therefore *partly* a control and *partly* a statement of expected behaviour.
Evidence for the first half is a command output; the second half has none, and a reviewer
should ask for it in the form the principles themselves take: a diff, a question asked before
implementation, a refused apply.

## 9. How To Tell It Is Working

- Diffs contain only requested changes; no drive-by reformatting appears.
- Clarifying questions arrive **before** implementation, not after a mistake.
- Rewrites caused by overcomplication drop to zero.
- Every "done" in this repository is followed by a command output a reviewer can
  reproduce.
- When something could not be verified, the reply says so in those words.

## 10. Maintenance

- Edit only the behaviour sections. New or changed *facts* about enforcement go in
  `AGENTS.md` §2, where the gate looks at them.
- Small diffs; one principle refined per change where possible.
- Update `CHANGELOG.md` (Keep a Changelog: Added / Changed / Fixed / Removed) when
  a rule changes what an agent may do.
- `make doc-gate` reads the Document control block. If you change a field there, re-capture
  `tests/fixtures/doc_control/qoder_real.md` from the live file — the suite asserts byte
  identity, so a stale fixture fails loudly rather than testing a document that no longer
  exists.
- On quarterly review: re-read §7 against `audit/*.yml`, re-read §8 against
  `.github/workflows/`, and delete any line this file can no longer point at.
