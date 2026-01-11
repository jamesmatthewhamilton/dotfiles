# ~/.bashrc
# Quality of life
shopt -s autocd cdspell dirspell globstar checkwinsize

# History that merges across tabs
HISTCONTROL=ignoredups:erasedups
HISTSIZE=50000
HISTFILESIZE=100000
PROMPT_COMMAND='history -a; history -n'
