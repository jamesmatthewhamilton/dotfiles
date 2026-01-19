# Move uncommitted bashrc.sh additions to bashrc_tmp.sh
bashrc-migrate-to-tmp() {
  local dir=$(dirname "$(readlink -f ~/.bashrc)")
  local d=$(git -C "$dir" diff bashrc.sh | grep '^+[^+]' | cut -c2-)
  [ "$d" ] && { echo "$d"; echo "$d" >> ~/.bashrc_tmp.sh; git -C "$dir" checkout bashrc.sh; } || echo "No changes"
}

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
