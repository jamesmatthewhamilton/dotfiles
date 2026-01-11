# Resolve symlinks
sf="${BASH_SOURCE[0]}"
while [[ -L "$sf" ]]; do sf="$(readlink "$sf")"; done
dir="$(cd "$(dirname "$sf")" && pwd)"

# Load everything
for f in "$dir"/lib_*.sh "$dir"/bashrc_*.sh "$dir"/mac_*.sh; do source "$f"; done
