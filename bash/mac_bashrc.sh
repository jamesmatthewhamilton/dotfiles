# macOS-specific bash config
[[ "$OSTYPE" != darwin* ]] && return 0        # only on macOS
case $- in *i*) ;; *) return 0 ;; esac        # only in interactive shells
[ -n "${BASH_VERSION-}" ] || return 0         # only in bash

# Initialize Homebrew (must come before using brew commands)
if [ -x /opt/homebrew/bin/brew ]; then
    # Apple Silicon
    eval "$(/opt/homebrew/bin/brew shellenv)"
elif [ -x /usr/local/bin/brew ]; then
    # Intel Mac
    eval "$(/usr/local/bin/brew shellenv)"
fi

# Bash completion (if installed via brew)
if command -v brew &>/dev/null; then
    local brew_prefix
    brew_prefix="$(brew --prefix)"
    if [ -f "$brew_prefix/etc/profile.d/bash_completion.sh" ]; then
        . "$brew_prefix/etc/profile.d/bash_completion.sh"
    elif [ -f "$brew_prefix/etc/bash_completion" ]; then
        . "$brew_prefix/etc/bash_completion"
    fi
fi
