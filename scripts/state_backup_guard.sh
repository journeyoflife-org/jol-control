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
DEST="${DEST:-/mnt/jol-backup/jol-state-backup}"
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

NEWEST="$(find "$DEST" -maxdepth 1 -type f -name '*.age' -printf '%T@ %p\n' 2>/dev/null | sort -rn | head -1 | cut -d' ' -f2-)"
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
  if [ "$AGE_H" -lt "$MAX_AGE_H" ]; then
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
