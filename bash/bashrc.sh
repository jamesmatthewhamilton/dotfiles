# Resolve symlinks
sf="${BASH_SOURCE[0]}"
while [[ -L "$sf" ]]; do sf="$(readlink "$sf")"; done
dir="$(cd "$(dirname "$sf")" && pwd)"

# Load everything (including bashrc_conda.sh if it exists)
for f in "${HOME}"/.common/*.sh "$dir"/bashrc_*.sh "$dir"/mac_*.sh; do
    [ -f "$f" ] && source "$f"
done
