#!/usr/bin/env bash
#
# sync-drives.sh — mirror one external drive onto another, safely.
#
# Defaults to copying "/Volumes/Sandisk 8TB" INTO "/Volumes/Crucial X10 8TB"
# (i.e. it creates ".../Crucial X10 8TB/Sandisk 8TB/"). Non-destructive by
# default: files added/changed on the source are copied, but nothing on the
# destination is ever deleted unless you pass --delete.
#
# Guarantees baked in:
#   * Data integrity   — full APFS fidelity (-aHAXN) + optional --verify pass
#                        that re-checksums every byte on both drives.
#   * No interruption  — the whole run is wrapped in `caffeinate` so idle/display
#                        sleep can't stop it (safe to close the lid on AC power).
#   * Source untouched — rsync only ever READS the source; without --delete it
#                        also never removes anything on the destination.
#
# Logs (watch these live with `tail -f`):
#   ~/sync-drives-logs/sync-<stamp>.log     full console output (also latest.log)
#   ~/sync-drives-logs/rsync-<stamp>.log    structured rsync transfer log
#   ~/sync-drives-logs/verify-<stamp>.log   checksum verification (with --verify)
#
# Usage:
#   tools/sync-drives.sh [options] [SOURCE] [DEST]
#
# Options:
#   -n, --dry-run     Show what would change; copy nothing.
#       --verify      After syncing, run a --checksum pass to prove every file
#                     is byte-for-byte identical (slow: reads both drives fully).
#       --delete      Mirror mode: also delete dest files missing from source.
#                     (OFF by default. Only ever affects the DEST subfolder.)
#   -s, --source DIR  Override source (default: /Volumes/Sandisk 8TB).
#   -d, --dest   DIR  Override destination (default: /Volumes/Crucial X10 8TB).
#   -h, --help        Show this help.
#
# Note on hardware write-protection: this script does NOT remount the source
# read-only (that needs sudo and unmounts the drive). rsync never writes to the
# source, so it is safe. For an absolute guarantee, mount the source read-only
# yourself first:  diskutil unmount "<src>" && sudo mount_apfs -o rdonly <devN> "<src>"

set -euo pipefail

# --- load shared logging banners (auto-sources colors.sh) ---------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../bash/common/logger.sh
source "${SCRIPT_DIR}/../bash/common/logger.sh"

# --- logging helpers: colored banner to console + plain line to the run log ---
_logline() { [[ -n "${MAIN_LOG:-}" ]] && printf '%s [%s] %s\n' "$(date '+%F %T')" "$1" "$2" >>"$MAIN_LOG" || true; }
info()  { printf "${INFO}%s\n"    "$*";      _logline INFO    "$*"; }
warn()  { printf "${WARNING}%s\n" "$*";      _logline WARN    "$*"; }
err()   { printf "${ERROR}%s\n"   "$*" >&2;  _logline ERROR   "$*"; }
ok()    { printf "${SUCCESS}%s\n" "$*";      _logline SUCCESS "$*"; }
hint()  { printf "${HINT}%s\n"    "$*";      _logline HINT    "$*"; }

die() { err "$*"; exit 1; }

# --- defaults -----------------------------------------------------------------
SRC="/Volumes/Sandisk 8TB"
DST="/Volumes/Crucial X10 8TB"
RSYNC_BIN="${RSYNC_BIN:-/opt/homebrew/bin/rsync}"   # prefer Homebrew rsync 3.x
LOG_DIR="${SYNC_DRIVES_LOG_DIR:-$HOME/sync-drives-logs}"

DRY_RUN=0
VERIFY=0
DELETE=0

# Volume-index cruft that macOS regenerates on its own — never worth copying.
EXCLUDES=( ".Spotlight-V100" ".fseventsd" ".Trashes" ".DocumentRevisions-V100" ".TemporaryItems" )

usage() { sed -n '3,39p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; }

# --- parse args ---------------------------------------------------------------
POSITIONAL=()
while [[ $# -gt 0 ]]; do
    case "$1" in
        -n|--dry-run) DRY_RUN=1; shift ;;
        --verify)     VERIFY=1;  shift ;;
        --delete)     DELETE=1;  shift ;;
        -s|--source)  SRC="${2:?--source needs a path}"; shift 2 ;;
        -d|--dest)    DST="${2:?--dest needs a path}";    shift 2 ;;
        -h|--help)    usage; exit 0 ;;
        --) shift; while [[ $# -gt 0 ]]; do POSITIONAL+=("$1"); shift; done ;;
        -*) die "Unknown option: $1 (try --help)" ;;
        *)  POSITIONAL+=("$1"); shift ;;
    esac
done
[[ ${#POSITIONAL[@]} -ge 1 ]] && SRC="${POSITIONAL[0]}"
[[ ${#POSITIONAL[@]} -ge 2 ]] && DST="${POSITIONAL[1]}"

SRC="${SRC%/}"                    # strip trailing slash so SRC copies AS a subdir
FINAL_DEST="$DST/$(basename "$SRC")"

# --- preflight checks ---------------------------------------------------------
[[ -x "$RSYNC_BIN" ]] || RSYNC_BIN="$(command -v rsync || true)"
[[ -n "$RSYNC_BIN" ]] || die "rsync not found. Install it with: brew install rsync"

RSYNC_VER="$("$RSYNC_BIN" --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+(\.[0-9]+)?' | head -1)"
if [[ "${RSYNC_VER%%.*}" -lt 3 ]] 2>/dev/null; then
    warn "rsync $RSYNC_VER is old (likely openrsync) — extended attributes/ACLs/hardlinks"
    warn "will NOT be preserved. Install a modern rsync:  brew install rsync"
fi

[[ -d "$SRC" ]] || die "Source not found or not mounted: $SRC"
[[ -r "$SRC" ]] || die "Source not readable: $SRC"
[[ -d "$DST" ]] || die "Destination not found or not mounted: $DST"
[[ -w "$DST" ]] || die "Destination not writable: $DST"
[[ "$SRC" != "$DST" ]] || die "Source and destination are the same path."

# Free-space sanity check (uses volume-level df — instant, unlike du on 6.5 TB).
SRC_USED_K="$(df -k "$SRC" | awk 'NR==2{print $3}')"
DST_AVAIL_K="$(df -k "$DST" | awk 'NR==2{print $4}')"
to_gib() { awk -v k="$1" 'BEGIN{printf "%.1f", k/1024/1024}'; }
if [[ "$DST_AVAIL_K" -lt "$SRC_USED_K" ]]; then
    warn "Destination free ($(to_gib "$DST_AVAIL_K") GiB) < source used ($(to_gib "$SRC_USED_K") GiB)."
    warn "That's fine for an incremental top-up, but a first full sync may not fit."
fi

# --- prepare logs -------------------------------------------------------------
mkdir -p "$LOG_DIR"
STAMP="$(date +%Y%m%d-%H%M%S)"
MAIN_LOG="$LOG_DIR/sync-$STAMP.log"
RSYNC_LOG="$LOG_DIR/rsync-$STAMP.log"
ln -sfn "$MAIN_LOG"  "$LOG_DIR/latest.log"
ln -sfn "$RSYNC_LOG" "$LOG_DIR/latest-rsync.log"

# --- caffeinate wrapper (prevents idle/display sleep during the whole run) ----
CAFF=()
command -v caffeinate >/dev/null 2>&1 && CAFF=(caffeinate -imsu)

# --- build the rsync argument list --------------------------------------------
#   -a  archive (recursive, symlinks, perms, times, group, owner, devices)
#   -H  hardlinks   -A  ACLs   -X  xattrs   -N  crtimes (APFS birth time)
RSYNC_ARGS=( -aHAXN --partial --human-readable --info=progress2 --stats
             --log-file="$RSYNC_LOG" )
for e in "${EXCLUDES[@]}"; do RSYNC_ARGS+=( --exclude "$e" ); done
(( DELETE ))  && RSYNC_ARGS+=( --delete )
(( DRY_RUN )) && RSYNC_ARGS+=( --dry-run --itemize-changes )

# --- summary before we start --------------------------------------------------
info "sync-drives starting  ($STAMP)"
info "  source : $SRC"
info "  dest   : $FINAL_DEST"
info "  rsync  : $RSYNC_BIN (v$RSYNC_VER)"
info "  mode   : $( ((DRY_RUN)) && echo 'DRY-RUN' || echo 'LIVE' ) / $( ((DELETE)) && echo 'delete (mirror)' || echo 'no-delete' )"
info "  logs   : $MAIN_LOG"
info "           $RSYNC_LOG"
hint "  monitor: tail -f \"$LOG_DIR/latest.log\""

# --- run the sync -------------------------------------------------------------
info "Copying… (this can take hours; safe to close the lid on AC power)"
set +e
"${CAFF[@]}" "$RSYNC_BIN" "${RSYNC_ARGS[@]}" "$SRC" "$DST/" 2>&1 | tee -a "$MAIN_LOG"
rc=${PIPESTATUS[0]}
set -e

if [[ "$rc" -ne 0 ]]; then
    err "rsync exited with code $rc — see $MAIN_LOG"
    err "Re-run the same command to resume (rsync picks up where it left off)."
    exit "$rc"
fi
ok "Sync completed with no errors."

# --- optional integrity verification ------------------------------------------
if (( VERIFY )) && ! (( DRY_RUN )); then
    VERIFY_LOG="$LOG_DIR/verify-$STAMP.log"
    ln -sfn "$VERIFY_LOG" "$LOG_DIR/latest-verify.log"
    info "Verifying integrity (checksumming every file on both drives)…"
    VERIFY_ARGS=( -aHAXN --checksum --dry-run --itemize-changes )
    for e in "${EXCLUDES[@]}"; do VERIFY_ARGS+=( --exclude "$e" ); done
    (( DELETE )) && VERIFY_ARGS+=( --delete )

    set +e
    "${CAFF[@]}" "$RSYNC_BIN" "${VERIFY_ARGS[@]}" "$SRC" "$DST/" 2>&1 | tee "$VERIFY_LOG"
    vrc=${PIPESTATUS[0]}
    set -e
    [[ "$vrc" -eq 0 ]] || die "Verification pass failed to run (code $vrc) — see $VERIFY_LOG"

    # A content mismatch itemizes as a '>f...' line. Zero of those == identical.
    mismatches="$(grep -cE '^>f' "$VERIFY_LOG" || true)"
    if [[ "$mismatches" -eq 0 ]]; then
        ok "Integrity verified: every file is byte-for-byte identical."
    else
        warn "$mismatches file(s) differ from the source — see $VERIFY_LOG"
        warn "Re-run without --dry-run to heal them, then verify again."
    fi
fi

ok "Done. Full log: $MAIN_LOG"
