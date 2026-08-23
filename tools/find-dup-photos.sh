#!/usr/bin/env bash
#
# find-dup-photos.sh — conservatively find (and optionally quarantine) duplicate photos.
#
# A "duplicate" here = two files with the SAME basename AND SAME size AND byte-identical
# content (confirmed with cmp). Same name+size alone is only a CANDIDATE; only exact
# matches are ever quarantined.
#
# Safety design (why this won't eat your photos):
#   * DEFAULT IS DRY-RUN — reports only. Nothing is moved without --apply.
#   * THIS SCRIPT NEVER DELETES. --apply MOVES duplicates to a timestamped
#     quarantine dir for later review; deleting the quarantine is a manual step.
#   * ALWAYS KEEPS ONE copy of each identical set — the OLDEST by modification
#     time (archive policy). Ties broken by shortest, then lexicographically
#     first path.
#   * Quarantine dir is flat. Name collisions (3+ copies of the same photo) get
#     _1, _2, … suffixes. A single manifest.csv in the quarantine dir records
#     every move: quarantined file, original path, kept copy, md5.
#   * --apply runs also write report.csv (metric,value rows: files scanned, dup
#     sets/files, bytes reclaimable, duration, …) next to manifest.csv in the
#     quarantine dir. Dry-runs print the same numbers to the console only.
#   * Skips symlinks, skips hardlinks to the keeper (same dev+inode), skips 0-byte files.
#   * Every move happens only after a byte-exact cmp against the keeper, and the
#     keeper is re-verified unchanged (size+mtime+inode) right before each move.
#
# Performance (built for multi-TB archives with millions of files):
#   * ONE batched find|xargs|stat|awk pipeline collects size/mtime/dev/inode for
#     every photo and emits only candidate groups (same name+size, >=2 files).
#     Bash never loops over non-candidates and never runs a per-file stat.
#   * 2-file candidate groups (the common case) are verified with a single cmp —
#     no hashing at all. 3+ groups are md5-bucketed once per file, then each
#     move is still cmp-confirmed against its keeper.
#   * Progress bars (stderr) track three labeled stages — hash (md5 of 3+ copy
#     groups), verify (byte-exact cmp of dup vs keeper), act (report/move) — so
#     long runs show live counts and ETA instead of thousands of per-file lines.
#
# Usage:
#   find-dup-photos.sh <directory>            # dry-run report (safe, default)
#   find-dup-photos.sh <directory> --apply    # move dups to quarantine
#   find-dup-photos.sh <directory> --jobs 8   # parallel content checks
#                                             # (default 4; use 1 on spinning disks)
#   find-dup-photos.sh <directory> --apply --quarantine-dir /Volumes/X
#                                             # create the quarantine dir UNDER the
#                                             # given path instead of $HOME — keeps the
#                                             # moves on the same drive (instant rename,
#                                             # no boot-disk space needed)
#
# Content checks (md5/cmp) run in parallel workers; all moves and sidecar writes
# stay serial in the main process. --jobs 1 uses the same code path.
#
# First positional arg = input directory (required).

set -euo pipefail

# Needs bash >= 4 for associative arrays (macOS stock /bin/bash is 3.2).
if (( BASH_VERSINFO[0] < 4 )); then
    echo "ERROR: needs bash >= 4 (you have $BASH_VERSION)." >&2
    echo "       Run with Homebrew bash:  /opt/homebrew/bin/bash $0 <dir> [flags]" >&2
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../bash/common/logger.sh
source "${SCRIPT_DIR}/../bash/common/logger.sh"

die() { printf "${ERROR}%s\n" "$*" >&2; exit 1; }
csv() { local s=${1//\"/\"\"}; printf '"%s"' "$s"; }   # RFC-4180 field quoting

# Photo extensions (case-insensitive). Extend via: EXT="jpg png ..." ./find-dup-photos.sh
EXT="${EXT:-jpg jpeg png heic heif gif tif tiff bmp webp dng raw cr2 cr3 nef arw orf rw2 raf}"

MODE="report"   # report | quarantine
DIR=""
JOBS=4          # parallel content-check workers (md5/cmp); moves are always serial
QUAR_PARENT="$HOME"   # --quarantine-dir: quarantine dir is created inside this

while [[ $# -gt 0 ]]; do
    case "$1" in
        --apply) MODE="quarantine"; shift ;;
        --jobs)  JOBS="${2:-}"; shift 2 ;;
        --quarantine-dir) [[ $# -ge 2 ]] || die "--quarantine-dir needs a path"; QUAR_PARENT="$2"; shift 2 ;;
        -h|--help) sed -n '3,51p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
        -*) die "Unknown option: $1 (try --help)" ;;
        *)  [[ -z "$DIR" ]] && DIR="$1" || die "Only one directory argument is allowed."; shift ;;
    esac
done

[[ "$JOBS" =~ ^[0-9]+$ && "$JOBS" -ge 1 ]] || die "--jobs needs a positive integer (got: '${JOBS}')"
[[ -n "$DIR" ]]  || die "Usage: find-dup-photos.sh <directory> [--apply] [--jobs N] [--quarantine-dir <path>]"
[[ -d "$DIR" ]]  || die "Not a directory: $DIR"
DIR="${DIR%/}"
[[ -d "$QUAR_PARENT" ]] || die "Not a directory: $QUAR_PARENT (--quarantine-dir)"

# hashing backend (only used for 3+ file groups and quarantine sidecars)
if command -v md5 >/dev/null 2>&1;    then HASH() { md5 -q -- "$1"; }; HASH_CMD='md5 -q --'
elif command -v md5sum >/dev/null 2>&1; then HASH() { md5sum -- "$1" | awk '{print $1}'; }; HASH_CMD='md5sum --'
else die "Need md5 or md5sum."; fi

# Parallel verify workers (xargs -P). Each emits exactly ONE short line per task
# ("<id> <verdict>", far below PIPE_BUF), so concurrent writes stay line-atomic.
# Workers are strictly read-only: MISS/FAIL/ERR are per-file skips, never fatal.
MD5_WORKER='p="$2"
[ -f "$p" ] || { printf "%s MISS\n" "$1"; exit 0; }
h=$('"$HASH_CMD"' "$p" 2>/dev/null) || { printf "%s FAIL\n" "$1"; exit 0; }
printf "%s %s\n" "$1" "${h%% *}"'
CMP_WORKER='a="$2"; b="$3"
{ [ -f "$a" ] && [ -f "$b" ]; } || { printf "%s MISS\n" "$1"; exit 0; }
if cmp -s -- "$a" "$b"; then printf "%s EQ\n" "$1"
else
    rc=$?
    if [ "$rc" -eq 1 ]; then printf "%s NE\n" "$1"; else printf "%s ERR\n" "$1"; fi
fi'

# --- progress bar (stderr; in-place when tty, periodic lines otherwise) ---
BAR_TTY=0; [[ -t 2 ]] && BAR_TTY=1
BAR_T0=0   # set to $SECONDS when the comparison stage starts
bar_eta() {  # $1=done $2=total -> approximate ETA from running rate
    local done=$1 totl=$2 elapsed=$(( SECONDS - BAR_T0 )) secs
    if (( done == 0 || elapsed == 0 )); then printf '%s' '--:--'; return 0; fi
    secs=$(( elapsed * (totl - done) / done ))
    if (( secs >= 3600 )); then printf '%d:%02d:%02d' $((secs/3600)) $((secs%3600/60)) $((secs%60))
    else printf '%02d:%02d' $((secs/60)) $((secs%60)); fi
}
bar_draw() {  # $1=stage label $2=done $3=total
    local label=$1 done=$2 totl=$3 width=30 filled pct
    (( totl > 0 )) || return 0
    if (( BAR_TTY )); then
        pct=$(( done * 100 / totl ))
        filled=$(( done * width / totl ))
        printf '\r%s [%s%s] %3d%%  done: %d  remaining: %d  ETA: %s ' \
            "$label" \
            "$(printf '%*s' "$filled" '' | tr ' ' '#')" \
            "$(printf '%*s' $(( width - filled )) '')" \
            "$pct" "$done" $(( totl - done )) "$(bar_eta "$done" "$totl")" >&2
    elif (( done % 100 == 0 || done == totl )); then
        printf "${INFO}%s\n" "$label: $done of $totl   ETA: $(bar_eta "$done" "$totl")" >&2
    fi
}
bar_clear() { (( BAR_TTY )) && printf '\r\033[K' >&2; return 0; }

STAMP="$(date +%Y%m%d-%H%M%S)"
QUAR="$(cd "$QUAR_PARENT" && pwd)/dup-photos-quarantine-$STAMP"
MANIFEST="$QUAR/manifest.csv"
if [[ "$MODE" == quarantine ]]; then
    # never quarantine into the tree being scanned — the next run would treat the
    # quarantined copies as fresh duplicates of their keepers
    case "$QUAR" in
        "$(cd "$DIR" && pwd)"/*) die "quarantine dir would be inside the scanned tree ($QUAR) — pass --quarantine-dir <path outside $DIR>" ;;
    esac
fi

printf "${INFO}%s\n" "find-dup-photos ($STAMP)"
printf "${INFO}%s\n" "  dir   : $DIR"
printf "${INFO}%s\n" "  mode  : $MODE (keeper = oldest copy; exact byte matches only; jobs=$JOBS)"
[[ "$MODE" == quarantine ]] && printf "${INFO}%s\n" "  quarantine -> $QUAR"

# --- Stage 1: ONE batched scan; awk emits only candidate groups (name+size, >=2) ---
#
# Record protocol from awk to bash (fd 3):
#   T <total>            photos scanned (0-byte excluded)
#   C <to_check>         sum of group sizes over candidate groups
#   G <ngroups>          number of candidate groups
# then per candidate group:
#   S <n>                group size
#   <size> <mtime> <inode>           \  n times: numeric meta line,
#   <path>                           /  then the path VERBATIM on its own line
#
# NOTE: no %d (device) in the batch stat — formatting st_dev makes macOS stat
# ~60x slower (0.5ms/file, measured). Device equality for the hardlink check is
# confirmed lazily via same_file() only when two inodes already match.
#
# Newline-containing filenames are excluded from the pipeline (a separate pass
# warns about them); every other path round-trips exactly via IFS= read -r.
printf "${INFO}%s\n" "Scanning for photos and grouping by name+size…"
nl=$'\n'
find_expr=(); for e in $EXT; do find_expr+=( -iname "*.$e" -o ); done
unset 'find_expr[${#find_expr[@]}-1]'   # drop trailing -o

# warn about newline-in-name files (they are skipped, never touched)
while IFS= read -r -d '' path; do
    printf "${WARNING}%s\n" "skip (newline in name): ${path//$'\n'/\\n}"
done < <(find "$DIR" -type f \( "${find_expr[@]}" \) -name "*${nl}*" -print0 2>/dev/null)

scan_pipeline() {
    # find -type f never matches symlinks; stat batch = one exec per ~5000 files.
    # '|| true': files vanishing mid-scan must not kill the run (set -euo pipefail).
    LC_ALL=C find "$DIR" -type f \( "${find_expr[@]}" \) ! -name "*${nl}*" -print0 2>/dev/null \
      | { xargs -0 stat -f '%z//%m//%i//%N' -- 2>/dev/null || true; } \
      | LC_ALL=C awk '
        {
            # path parsing is anchored on the 3 numeric fields; "//" IN the path
            # cannot confuse it because path = remainder after the anchored match
            if (match($0, /^[0-9]+\/\/[0-9]+\/\/[0-9]+\/\//) == 0) {
                printf "[WARNING] skip (malformed scan record): %s\n", $0 > "/dev/stderr"
                next
            }
            hdr = substr($0, 1, RLENGTH); path = substr($0, RLENGTH + 1)
            split(hdr, m, "//")               # m[1]=size m[2]=mtime m[3]=inode
            if (m[1] + 0 == 0) next           # skip 0-byte
            n = split(path, seg, "/")
            key = m[1] SUBSEP seg[n]          # size + basename
            cnt[key]++
            rec[key, cnt[key]] = m[1] " " m[2] " " m[3] "\n" path
            total++
        }
        END {
            tc = 0; g = 0
            for (k in cnt) if (cnt[k] >= 2) { tc += cnt[k]; g++ }
            print "T " total + 0
            print "C " tc
            print "G " g
            for (k in cnt) if (cnt[k] >= 2) {
                print "S " cnt[k]
                for (i = 1; i <= cnt[k]; i++) print rec[k, i]
            }
        }'
}

# --- Stage 2: candidate groups only; confirm identical content, keep the oldest ---

# same_file <a> <b>: called only when inodes already match — confirm same device
# (per-file %d is too slow for the scan; here it runs a handful of times at most)
same_file() {
    local d1 d2
    d1=$(stat -f '%d' -- "$1" 2>/dev/null) || return 1
    d2=$(stat -f '%d' -- "$2" 2>/dev/null) || return 1
    [[ "$d1" == "$d2" ]]
}

# pick_keeper <idx>... -> KEEPER_IDX: oldest mtime; ties -> shortest, then lexicographic path
pick_keeper() {
    local best=$1 i
    for i in "$@"; do
        if (( mtimes[i] < mtimes[best] )) \
           || { (( mtimes[i] == mtimes[best] )) && (( ${#paths[i]} < ${#paths[best]} )); } \
           || { (( mtimes[i] == mtimes[best] )) && (( ${#paths[i]} == ${#paths[best]} )) && [[ "${paths[i]}" < "${paths[best]}" ]]; }; then
            best=$i
        fi
    done
    KEEPER_IDX=$best
}

# handle_dup <keeper idx> <dup idx> <md5 or ""> — count or quarantine one confirmed dup
handle_dup() {
    local k=$1 d=$2 h=$3 cur base dest stem ext n
    dup_files=$((dup_files+1))
    freed=$(( freed + sizes[d] ))
    case "$MODE" in
        report) : ;;                             # dry-run: counters only, no per-file output
        quarantine)
            # final safety: keeper and dup must be unchanged since the scan
            cur=$(stat -f '%z %m %i' -- "${paths[k]}" 2>/dev/null) || cur=""
            [[ "$cur" == "${sizes[k]} ${mtimes[k]} ${inodes[k]}" ]] \
                || { bar_clear; printf "${ERROR}%s\n" "  ABORT move (keeper changed): ${paths[k]}" >&2; return 0; }
            cur=$(stat -f '%z %m %i' -- "${paths[d]}" 2>/dev/null) || cur=""
            [[ "$cur" == "${sizes[d]} ${mtimes[d]} ${inodes[d]}" ]] \
                || { bar_clear; printf "${ERROR}%s\n" "  ABORT move (dup changed): ${paths[d]}" >&2; return 0; }
            mkdir -p "$QUAR"
            [[ -f "$MANIFEST" ]] || printf 'quarantined,original,keeper,md5\n' > "$MANIFEST"
            # flat quarantine: on name collision append _1, _2, …
            base="${paths[d]##*/}"
            dest="$QUAR/$base"
            if [[ -e "$dest" ]]; then
                stem="$base"; ext=""
                [[ "$base" == ?*.* ]] && { stem="${base%.*}"; ext=".${base##*.}"; }
                n=1
                while [[ -e "$QUAR/${stem}_${n}${ext}" ]]; do n=$((n+1)); done
                dest="$QUAR/${stem}_${n}${ext}"
            fi
            if mv -n -- "${paths[d]}" "$dest" && [[ -f "$dest" ]]; then
                # pair fast-path has no hash yet: hash the moved file (cache-hot from cmp)
                [[ -n "$h" ]] || h=$(HASH "$dest")
                printf '%s,%s,%s,%s\n' "$(csv "$dest")" "$(csv "${paths[d]}")" "$(csv "${paths[k]}")" "$h" >> "$MANIFEST"
                acted=$((acted+1))
            else
                bar_clear; printf "${ERROR}%s\n" "  FAILED to move: ${paths[d]}" >&2
            fi
            ;;
    esac
}

exec 3< <(scan_pipeline)
read -r -u3 tag total    || die "scan pipeline produced no output"
read -r -u3 tag to_check || die "scan pipeline truncated (no C header)"
read -r -u3 tag ngroups  || die "scan pipeline truncated (no G header)"

naive=$(( total * (total - 1) / 2 ))
printf "${INFO}%s\n" "Photos scanned: $total   candidate name+size groups: $ngroups"
printf "${INFO}%s\n" "naive O(n^2) exact compare: $total*$((total-1))/2 = $naive pairwise comparisons"
printf "${INFO}%s\n" "this script O(n) grouping : $to_check file(s) need a content check"

dup_sets=0; dup_files=0; freed=0; acted=0

# ---- Phase 1: PLAN (serial) — load candidate groups, build the verify worklist ----
# Global parallel arrays over ALL candidate files; groups reference index ranges.
paths=(); sizes=(); mtimes=(); inodes=()
pair_k=(); pair_d=()               # cmp tasks from 2-file groups (keeper, dup)
multi_start=(); multi_n=()         # 3+ groups, md5-bucketed after the hash round
set_h=(); set_k=(); set_dups=(); set_types=()   # dup sets for the act phase

while read -r -u3 tag n; do        # "S <n>"
    base=${#paths[@]}
    for ((i = 0; i < n; i++)); do
        read -r -u3 sz mt ino
        IFS= read -r -u3 p
        sizes+=("$sz"); mtimes+=("$mt"); inodes+=("$ino"); paths+=("$p")
    done
    if (( n == 2 )); then
        pick_keeper "$base" "$(( base + 1 ))"
        k=$KEEPER_IDX; d=$(( k == base ? base + 1 : base ))
        if [[ "${inodes[d]}" == "${inodes[k]}" ]] && same_file "${paths[d]}" "${paths[k]}"; then
            set_h+=(""); set_k+=("$k"); set_dups+=("$d"); set_types+=("HL")   # resolved without reading a byte
        else
            pair_k+=("$k"); pair_d+=("$d")
        fi
    else
        multi_start+=("$base"); multi_n+=("$n")
    fi
done
exec 3<&-

# ---- Phase 2: VERIFY (parallel, read-only) — md5 round, then cmp round ----

# md5 round: hash every member of 3+ groups; verdicts keyed by global index
md5_total=0
for ((g = 0; g < ${#multi_start[@]}; g++)); do md5_total=$(( md5_total + multi_n[g] )); done
declare -A md5v=()
if (( md5_total > 0 )); then
    BAR_T0=$SECONDS; md5_done=0
    while read -r idx h; do
        md5v[$idx]=$h
        md5_done=$((md5_done+1)); bar_draw "hash   (1/3)" "$md5_done" "$md5_total"
    done < <(
        for ((g = 0; g < ${#multi_start[@]}; g++)); do
            for ((i = multi_start[g]; i < multi_start[g] + multi_n[g]; i++)); do
                printf '%s\0%s\0' "$i" "${paths[i]}"
            done
        done | xargs -0 -n2 -P"$JOBS" sh -c "$MD5_WORKER" _
    )
    bar_clear
    printf "${INFO}%s\n" "hash stage done: md5'd $md5_done file(s) in 3+ copy groups"
fi

# bucket 3+ groups by hash; record their dup sets; queue keeper-vs-dup cmp tasks
cmp_id=(); cmp_a=(); cmp_b=()
for ((t = 0; t < ${#pair_k[@]}; t++)); do
    cmp_id+=("P:${pair_k[t]}:${pair_d[t]}")
    cmp_a+=("${paths[pair_k[t]]}"); cmp_b+=("${paths[pair_d[t]]}")
done
for ((g = 0; g < ${#multi_start[@]}; g++)); do
    declare -A byhash=()
    for ((i = multi_start[g]; i < multi_start[g] + multi_n[g]; i++)); do
        h=${md5v[$i]:-MISS}
        [[ "$h" == MISS || "$h" == FAIL ]] && continue
        byhash["$h"]+="$i "
    done
    for h in "${!byhash[@]}"; do
        read -r -a idxs <<< "${byhash[$h]}"
        (( ${#idxs[@]} >= 2 )) || continue
        pick_keeper "${idxs[@]}"; k=$KEEPER_IDX
        dups=""; types=""
        for d in "${idxs[@]}"; do
            (( d == k )) && continue
            if [[ "${inodes[d]}" == "${inodes[k]}" ]] && same_file "${paths[d]}" "${paths[k]}"; then
                dups+="$d "; types+="HL "
            else
                dups+="$d "; types+="CMP "
                cmp_id+=("M:$k:$d"); cmp_a+=("${paths[k]}"); cmp_b+=("${paths[d]}")
            fi
        done
        set_h+=("$h"); set_k+=("$k"); set_dups+=("${dups% }"); set_types+=("${types% }")
    done
done

# cmp round: byte-exact confirmation for every pair task and every 3+ dup
declare -A cmpv=()
if (( ${#cmp_id[@]} > 0 )); then
    BAR_T0=$SECONDS; cmp_done=0
    while read -r id verdict; do
        cmpv[$id]=$verdict
        cmp_done=$((cmp_done+1)); bar_draw "verify (2/3)" "$cmp_done" "${#cmp_id[@]}"
        if [[ "$verdict" == ERR ]]; then
            bar_clear
            printf "${WARNING}%s\n" "  SKIP (unreadable during cmp): ${paths[${id##*:}]}"
        fi
    done < <(
        for ((t = 0; t < ${#cmp_id[@]}; t++)); do
            printf '%s\0%s\0%s\0' "${cmp_id[t]}" "${cmp_a[t]}" "${cmp_b[t]}"
        done | xargs -0 -n3 -P"$JOBS" sh -c "$CMP_WORKER" _
    )
    bar_clear
    printf "${INFO}%s\n" "verify stage done: byte-compared $cmp_done candidate pair(s) against keepers"
fi

# pair groups become dup sets only when cmp confirmed byte-equality
for ((t = 0; t < ${#pair_k[@]}; t++)); do
    v=${cmpv["P:${pair_k[t]}:${pair_d[t]}"]:-MISS}
    [[ "$v" == EQ ]] || continue                # NE: name+size collision; MISS: vanished
    set_h+=(""); set_k+=("${pair_k[t]}"); set_dups+=("${pair_d[t]}"); set_types+=("CMP")
done

# ---- Phase 3: ACT (serial, main shell only) — report or quarantine each dup set ----
act_total=0
for ((s = 0; s < ${#set_dups[@]}; s++)); do
    read -r -a ds <<< "${set_dups[s]}"
    act_total=$(( act_total + ${#ds[@]} ))
done
BAR_T0=$SECONDS; act_done=0
for ((s = 0; s < ${#set_k[@]}; s++)); do
    k=${set_k[s]}
    dup_sets=$((dup_sets+1))
    read -r -a ds <<< "${set_dups[s]}"
    read -r -a ts <<< "${set_types[s]}"
    for ((j = 0; j < ${#ds[@]}; j++)); do
        d=${ds[j]}
        act_done=$((act_done+1)); bar_draw "act    (3/3)" "$act_done" "$act_total"
        [[ "${ts[j]}" == HL ]] && continue      # hardlink to keeper: same data, nothing to reclaim
        v=${cmpv["M:$k:$d"]:-${cmpv["P:$k:$d"]:-MISS}}
        case "$v" in
            EQ) handle_dup "$k" "$d" "${set_h[s]}" ;;
            NE) [[ -n "${set_h[s]}" ]] && { bar_clear; printf "${WARNING}%s\n" "  SKIP (md5 matched but bytes differ!): ${paths[d]}"; } ;;
            *)  : ;;                            # MISS silent; ERR already warned
        esac
    done
done

bar_clear
printf "${INFO}%s\n" "act stage done: processed $act_done duplicate(s)"
human_freed=$(awk -v b=$freed 'BEGIN{u="B S K M G T";split(u,a," ");i=1;while(b>=1024&&i<6){b/=1024;i++}printf "%.1f %sB", b, (i==1?"":substr("KMGT",i-1,1))}')
printf "${INFO}%s\n" "Content checks: $md5_total md5 hash(es) + ${#cmp_id[@]} byte comparison(s) (vs $naive naive pairwise comparisons)"
printf "${SUCCESS}%s\n" "Done. Duplicate sets: $dup_sets   redundant copies: $dup_files   reclaimable: ${human_freed}"
case "$MODE" in
    report)     printf "${HINT}%s\n" "Dry-run only. Re-run with --apply to quarantine (safe/recoverable)." ;;
    quarantine) printf "${SUCCESS}%s\n" "Moved $acted file(s) to: $QUAR"
                printf "${HINT}%s\n" "manifest.csv there maps every file to its original path, keeper, and md5. Review, then delete the quarantine dir manually to reclaim space." ;;
esac

# --- per-run metrics: report.csv (metric,value rows) next to manifest.csv ---
if [[ "$MODE" == quarantine ]]; then
    mkdir -p "$QUAR"
    REPORT="$QUAR/report.csv"
    {
        printf 'metric,value\n'
        printf 'date,%s\n'               "$STAMP"
        printf 'scanned_dir,%s\n'        "$(csv "$DIR")"
        printf 'extensions,%s\n'         "$(csv "$EXT")"
        printf 'jobs,%s\n'               "$JOBS"
        printf 'files_scanned,%s\n'      "$total"
        printf 'candidate_groups,%s\n'   "$ngroups"
        printf 'candidate_files,%s\n'    "$to_check"
        printf 'md5_hashes,%s\n'         "$md5_total"
        printf 'byte_comparisons,%s\n'   "${#cmp_id[@]}"
        printf 'duplicate_sets,%s\n'     "$dup_sets"
        printf 'duplicate_files,%s\n'    "$dup_files"
        printf 'files_moved,%s\n'        "$acted"
        printf 'bytes_reclaimable,%s\n'  "$freed"
        printf 'reclaimable_human,%s\n'  "$(csv "$human_freed")"
        printf 'duration_seconds,%s\n'   "$SECONDS"
    } > "$REPORT"
    printf "${INFO}%s\n" "run metrics written to: $REPORT"
fi
