# Resolve symlinks
sf="${BASH_SOURCE[0]}"
while [[ -L "$sf" ]]; do sf="$(readlink "$sf")"; done
dir="$(cd "$(dirname "$sf")" && pwd)"

# Load everything
for f in "${HOME}"/.common/*.sh "$dir"/bashrc_*.sh "$dir"/mac_*.sh; do
    [ -f "$f" ] && source "$f"
done

# Conda init (auto-detect)
for c in ~/Repos/conda ~/miniconda3; do
    [ -x "$c/bin/conda" ] && eval "$("$c/bin/conda" shell.bash hook)" && break
done
