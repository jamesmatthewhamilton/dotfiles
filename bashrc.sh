# Add this file path to your ~/.bashrc

main() {
    local script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

    # Imports
    source "${script_dir}"/bashrc_alias.sh
    source "${script_dir}"/bashrc_docker.sh

    # Preferred style for bash command prompt.
    export PS1="\[\033[36m\]\u\[\033[m\]@\[\033[32m\]\h:\[\033[33;1m\]\w\[\033[m\]\$ "
}

main ${@}
