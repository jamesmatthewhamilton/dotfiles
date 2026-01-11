# macOS-specific bash config
[[ "$OSTYPE" != darwin* ]] && return 0        # only on macOS
case $- in *i*) ;; *) return 0 ;; esac        # only in interactive shells
[ -n "${BASH_VERSION-}" ] || return 0         # only in bash

if [ -f $(brew --prefix)/etc/bash_completion ]; then
. $(brew --prefix)/etc/bash_completion
fi
