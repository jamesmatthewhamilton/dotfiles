# Add this file path to your ~/.bashrc
main() {
    local script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

    source "${script_dir}"/bashrc_[[:alpha:]]*.sh

    # Only on macOS (Darwin). Note, "bachrc__*" is project or OS specific.
    if [[ "$OSTYPE" == darwin* ]] && [[ -r "${script_dir}/bashrc_mac.sh" ]]; then
        source "${script_dir}"/bashrc__mac.sh
    fi

    # Preferred style for bash command prompt.
    export PS1="\[\033[36m\]\u\[\033[m\]@\[\033[32m\]\h:\[\033[33;1m\]\w\[\033[m\]\$ "
}

main ${@}
