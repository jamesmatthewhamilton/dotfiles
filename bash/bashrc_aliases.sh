# Move uncommitted bashrc.sh additions to bashrc_tmp.sh
bashrc-migrate-to-tmp() {
  local dir=$(dirname "$(readlink -f ~/.bashrc)")
  local d=$(git -C "$dir" diff bashrc.sh | grep '^+[^+]' | cut -c2-)
  [ "$d" ] && { echo "$d"; echo "$d" >> ~/.bashrc_tmp.sh; git -C "$dir" checkout bashrc.sh; } || echo "No changes"
}
