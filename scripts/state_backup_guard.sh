#!/usr/bin/env bash
# RB-09: scheduled refresh of the off-device Terraform state backup.
#
# Why a script rather than a cron one-liner: the crontab on this host already carries a 10-minute
# guard line, and the recorded rule for this estate is to append to that line rather than mint new
# timers. A one-liner that has to decide "is the newest snapshot stale, is the disk mounted, do we
# hold a second recipient" is not a one-liner, and cron swallows the difference between "nothing to
# do", "could not check" and "failed". Those are three outcomes and need three exit codes.
#
# Exit codes:
#   0  up to date (nothing run), or a refresh completed successfully
#   1  a refresh was attempted and REFUSED, or the destination is unusable
#   2  UNEVALUATED - no second recipient recorded, so no backup can be made honestly
#
# A run that cannot obtain a second recipient exits 2 on purpose. Writing a single-key "backup" and
# reporting it as a scheduled success is the exact overstatement S2-012 and S2-013 were opened for.
set -uo pipefail
umask 077

REPO="${REPO:-/opt/jol/repos/jol-control}"
DEST="${DEST:-/mnt/jol-backup/jol-control}"
RECIPIENT_FILE="${RECIPIENT_FILE:-$HOME/.config/age/offdisk-recipient.txt}"
MAX_AGE_H="${MAX_AGE_H:-24}"          # refresh if the newest snapshot is older than this
LOG_TAG="${LOG_TAG:-state-backup-guard}"

say() { echo "$*"; if command -v logger >/dev/null 2>&1; then logger -t "$LOG_TAG" -- "$*" || true; fi; }

[ -f "$REPO/scripts/backup_state.sh" ] || { say "UNEVALUATED: $REPO/scripts/backup_state.sh missing"; exit 2; }

# The recipient is public key material, but it is still a file, not a value baked into a crontab:
# putting it in the crontab would leak the custody topology into every process listing.
if [ ! -s "$RECIPIENT_FILE" ]; then
  say "UNEVALUATED: no off-host recipient recorded at $RECIPIENT_FILE."
  say "           Mint and carry off-host per runbooks.md RB-08 step 1-2, then write the"
  say "           'age1...' recipient to that path. Refusing to back up to a single key."
  exit 2
fi
RECIPIENT="$(tr -d ' \t\n\r' < "$RECIPIENT_FILE")"
case "$RECIPIENT" in age1*) : ;; *) say "UNEVALUATED: $RECIPIENT_FILE does not hold an age1... recipient"; exit 2 ;; esac

# A destination that is not mounted must never be treated as an empty directory. With `nofail` in
# fstab the mount point persists while the disk is absent, and writing there lands on the root
# filesystem and is later shadowed - this host has done that before. backup_state.sh enforces the
# device separation too; this is the earlier, clearer refusal.
if [ ! -d "$DEST" ]; then
  say "FAIL: $DEST is absent - the off-device volume is not mounted (runbooks.md RB-09 preflight)."
  say "      Not attempting a backup. Nothing was written to the root filesystem."
  exit 1
fi

# Pin the snapshot NAME, not just "any .age". Measured 2026-10-27: another tree
# (`jolarca-control`) began writing its own `terraform.tfstate.s17.*.age` into this same destination,
# and a glob of `*.age` let its newest file satisfy this guard - `RC=0 nothing to do` while the
# jol-control inventory was hours stale. A freshness gate that another project's artefact can pass is
# not a freshness gate. The convention is the one backup_state.sh writes (and the RB-08 restore half
# globs): <repo>-terraform.tfstate.<stamp>.age.
SNAP_GLOB="$(basename "$REPO")-terraform.tfstate.*.age"
NEWEST="$(find "$DEST" -maxdepth 1 -type f -name "$SNAP_GLOB" -printf '%T@ %p\n' 2>/dev/null | sort -rn | head -1 | cut -d' ' -f2-)"
FOREIGN="$(find "$DEST" -maxdepth 1 -type f -name '*.age' ! -name "$SNAP_GLOB" 2>/dev/null | wc -l)"
if [ "$FOREIGN" -gt 0 ]; then
  say "NOTE: $FOREIGN *.age file(s) in $DEST are not this repository's snapshots and are excluded"
  say "      (expected pattern: $SNAP_GLOB). A shared destination is how one project's backup"
  say "      masks another's; see runbooks.md RB-09."
fi
if [ -n "$NEWEST" ]; then
  # A non-numeric `date +%s` must not reach $(( )). It happened: a test put a stub `date` on PATH and
  # the guard died with "value too great for base" - in production the same shape comes from a broken
  # clock or a hostile PATH, and a crash is not a verdict.
  NOW="$(date +%s 2>/dev/null)"; NEWEST_TS="$(stat -c %Y "$NEWEST" 2>/dev/null || echo 0)"
  case "$NOW$NEWEST_TS" in
    ''|*[!0-9]*) say "UNEVALUATED: cannot compute snapshot age (date +%s='$NOW', mtime='$NEWEST_TS')"
                 exit 2 ;;
  esac
  AGE_H=$(( (NOW - NEWEST_TS) / 3600 ))
  # A snapshot from the FUTURE is not "fresh", it is a broken clock or a planted file, and a negative
  # age satisfies every threshold below it. Observed while testing this very guard with a 2099 mtime:
  # "newest snapshot is -632713h old (< 24h) - nothing to do", exit 0.
  if [ "$AGE_H" -lt 0 ]; then
    say "UNEVALUATED: $NEWEST has a future mtime ($(( -AGE_H ))h ahead of this host) - refusing to treat it as fresh"
    exit 2
  fi
  # Cross-check the identity of the snapshot against the state it is supposed to protect. Timestamps
  # are trivially forged; the lineage is a UUID terraform generated once per state file.
  LIVE_LIN="$(jq -r '.lineage // empty' "$REPO/terraform.tfstate" 2>/dev/null)"
  SN_LIN="$(sed -n 's/^lineage  *: //p' "$NEWEST.info" 2>/dev/null)"
  # MISMATCH=1 forces a refresh past the freshness shortcut. An earlier revision of this block printed
  # "DIFFERENT inventory - refreshing anyway" and then fell into the `nothing to do` branch and exited 0,
  # so the message contradicted the verdict and a foreign snapshot named like ours still passed the gate.
  MISMATCH=0
  if [ -n "$LIVE_LIN" ] && [ -n "$SN_LIN" ] && [ "$LIVE_LIN" != "$SN_LIN" ]; then
    say "FAIL: $(basename "$NEWEST") protects lineage $SN_LIN; this state is lineage $LIVE_LIN."
    say "      That is a DIFFERENT inventory. Refreshing regardless of its age."
    MISMATCH=1
  elif [ -z "$SN_LIN" ] && [ -n "$LIVE_LIN" ]; then
    # Unknown identity is not a pass. Same rule as everywhere else in this repository.
    say "UNEVALUATED: $(basename "$NEWEST") has no lineage recorded, so this guard cannot tell whose"
    say "             state it protects. Refusing to call it fresh. Snapshots written by"
    say "             backup_state.sh always carry the field; re-run one to restore the evidence."
    exit 2
  fi
  if [ "$MISMATCH" = 0 ] && [ "$AGE_H" -lt "$MAX_AGE_H" ]; then
    say "OK: newest snapshot is ${AGE_H}h old (< ${MAX_AGE_H}h) - nothing to do"
    exit 0
  fi
  say "refresh due: newest snapshot is ${AGE_H}h old (>= ${MAX_AGE_H}h)"
else
  say "refresh due: no snapshot present in $DEST"
fi

OUT="$(cd "$REPO" && DEST="$DEST" RECOVERY_PUB="$RECIPIENT" bash scripts/backup_state.sh 2>&1)"; rc=$?
printf '%s\n' "$OUT" | while IFS= read -r line; do say "  $line"; done
case "$rc" in
  0) say "OK: backup refreshed and both custody paths proven"; exit 0 ;;
  # Exit 2 is the steady state of a pub-only schedule: the snapshot exists, and the off-host proof
  # cannot be produced from this machine. It is reported as 2 and NOT folded into 0 - a job that
  # silently green-lights its own unverified control is how this drifts back to single custody.
  # Runbooks.md RB-09 asks for a monthly rehearsal with the off-host identity to earn a 0.
  2) say "UNEVALUATED: snapshot written, off-host custody NOT verified - rehearse a restore (RB-09)"; exit 2 ;;
  *) say "FAIL: backup_state.sh exited $rc - no usable snapshot assured"; exit 1 ;;
esac
