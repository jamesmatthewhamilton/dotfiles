# ~/.bashrc
# Quality of life (autocd, dirspell, globstar require bash 4+)
shopt -s checkwinsize cdspell histappend
((BASH_VERSINFO[0] >= 4)) && shopt -s autocd dirspell globstar

# History that merges across tabs
HISTCONTROL=ignoredups
HISTSIZE=50000
HISTFILESIZE=100000

# Stop paste markers (00~/01~) from leaking into terminal
[[ $- == *i* ]] && bind 'set enable-bracketed-paste off'

# Prompt style: cyan user, green host, yellow path
export PS1="\[\033[36m\]\u\[\033[m\]@\[\033[32m\]\h:\[\033[33;1m\]\w\[\033[m\]\$ "
