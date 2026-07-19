# macOS Terminal.app opens login shells, which read ~/.bash_profile but not
# ~/.bashrc — bridge them so both shell types pick up the same config.
[[ -f ~/.bashrc ]] && source ~/.bashrc
