# ~/.bashrc
# Quality of life (autocd, dirspell, globstar require bash 4+)
shopt -s checkwinsize cdspell
((BASH_VERSINFO[0] >= 4)) && shopt -s autocd dirspell globstar

# History that merges across tabs
HISTCONTROL=ignoredups:erasedups
HISTSIZE=50000
HISTFILESIZE=100000
PROMPT_COMMAND='history -a; history -n'

# Prompt style: cyan user, green host, yellow path
export PS1="\[\033[36m\]\u\[\033[m\]@\[\033[32m\]\h:\[\033[33;1m\]\w\[\033[m\]\$ "
