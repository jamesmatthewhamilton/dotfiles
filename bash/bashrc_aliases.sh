

# ------------ Aliases ------------
# quick and used daily

# ------------ Functions ------------
# niche and used occasionally
# - must start with dev-*
# - quick reference with tab completion

# disk usage (du) in working directory sorted by available
# $1 = directory
dev-du-sort() {
  du -sh ${1}[^.]* */ 2>/dev/null | sort -hr
}

# disk free (df) sorted by available
dev-df-sort() {
  df -h | head -1; df -h | tail -n +2 | sort -hrk 3
}

# top-level sorted by size, subdirs grouped and sorted recursively
# $1 = depth
dev-tree-du() {
  local max_depth="${1:-1}"
  _tree_du_recurse() {
    local dir="$1" depth="$2" indent="$3"
    [ "$depth" -gt "$max_depth" ] && return
    for d in $(for p in "$dir"*/ "$dir".[^.]*/; do [ -d "$p" ] && du -sk "$p" 2>/dev/null; done | sort -rn | cut -f2); do
      du -sh "$d" 2>/dev/null | while IFS=$'\t' read -r size path; do
        printf "%s%-8s %s\n" "$indent" "$size" "$path"
      done
      _tree_du_recurse "$d" $((depth + 1)) "$indent  "
    done
  }
  _tree_du_recurse "./" 1 ""
  unset -f _tree_du_recurse
}

# same as dev-tree-du but single du call
# $1 = depth
dev-tree-du-fast() {
  du -k -d "${1:-1}" 2>/dev/null | awk -F'\t' '
  {
    size[$2] = $1
    tmp = $2; gsub(/[^\/]/, "", tmp)
    depths[$2] = length(tmp)
    paths[NR] = $2
    n = NR
  }
  function fmt(kb) {
    if (kb >= 1048576) return sprintf("%.1fG", kb/1048576)
    if (kb >= 1024)    return sprintf("%.0fM", kb/1024)
    return sprintf("%dK", kb)
  }
  function print_children(parent, lvl,    ii,p,nc,ch,cs,jj,kk,t,ts,indent) {
    nc = 0
    for (ii = 1; ii <= n; ii++) {
      p = paths[ii]
      if (p == parent || p == ".") continue
      if (index(p, parent) == 1 && depths[p] - depths[parent] == 1) {
        nc++; ch[nc] = p; cs[nc] = size[p]
      }
    }
    for (ii = 2; ii <= nc; ii++) {
      for (jj = ii; jj > 1 && cs[jj]+0 > cs[jj-1]+0; jj--) {
        t = ch[jj]; ch[jj] = ch[jj-1]; ch[jj-1] = t
        ts = cs[jj]; cs[jj] = cs[jj-1]; cs[jj-1] = ts
      }
    }
    for (ii = 1; ii <= nc; ii++) {
      indent = ""; for (kk = 0; kk < lvl; kk++) indent = indent "  "
      printf "%s%-8s %s\n", indent, fmt(cs[ii]+0), ch[ii]
      print_children(ch[ii], lvl+1)
    }
  }
  END { print_children(".", 0) }'
}

# refresh bash session including bashrc
dev-bashrc-refresh() {
  exec bash
  # source ~/.bashrc
}

# Move uncommitted bashrc.sh additions to bashrc_tmp.sh
dev-devops-bashrc-migrate-to-tmp() {
  local sf=~/.bashrc
  while [[ -L "$sf" ]]; do sf="$(cd "$(dirname "$sf")" && readlink "$(basename "$sf")")"; done
  local dir=$(cd "$(dirname "$sf")" && pwd)
  local d=$(git -C "$dir" diff bashrc.sh | grep '^+[^+]' | cut -c2-)
  [ "$d" ] && { echo "$d"; echo "$d" >> ~/.bashrc_tmp.sh; git -C "$dir" checkout bashrc.sh; } || echo "No changes"
}

# ------------ Comp Bio Functions ------------
# niche and used occasionally
# - must start with bio-*

# Annotate all VCFs in a directory (VEP -> CSQ), output gzipped + tabix-indexed VCFs.
# INPUT : $1 = input dir (default: .) containing *.vcf or *.vcf.gz
# OUTPUT: $2 = output dir (default: <input>/annotated) containing *.annot.vcf.gz + *.tbi
bio-vcfs-annotate() {
  set -euo pipefail; shopt -s nullglob
  local in="${1:-.}" out="${2:-"$in/annotated"}"
  mkdir -p "$out"
  for v in "$in"/*.vcf "$in"/*.vcf.gz; do
    local b; b="$(basename "${v%.vcf*}")"
    bcftools view "$v" | vep --vcf --cache --offline --assembly GRCh38 -o - \
      | bgzip -c > "$out/$b.annot.vcf.gz"
    tabix -p vcf "$out/$b.annot.vcf.gz"
  done
}


# Convert all VCFs in a directory to PLINK binary filesets (BED/BIM/FAM), one per VCF.
# INPUT : $1 = input dir (default: .) containing *.vcf or *.vcf.gz
# OUTPUT: $2 = output dir (default: <input>/plink) containing <base>.bed/.bim/.fam (+ <base>.log)
bio-vcf-2-bedbimfam() {
  local in="${1:-.}" out="${2:-"$in/plink"}" v b
  mkdir -p "$out"
  for v in "$in"/*.vcf "$in"/*.vcf.gz; do
    [[ -e "$v" ]] || continue
    b="$(basename "${v%.vcf*}")"
    plink2 --vcf "$v" --make-bed --double-id --out "$out/$b"
  done
}
