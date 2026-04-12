# Shared logging functions for all dotfiles scripts.
# Provides: info, success, warn, error
# Dependency: ./colors.sh (auto-sourced if needed)

[[ -n "${_COMMON_LOGGER_LOADED:-}" ]] && return 0
_COMMON_LOGGER_LOADED=1

if [[ -z "${RC:-}" ]]; then
    source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/colors.sh"
fi

info-log()    { printf "${CYAN_B}[INFO]${RC} %s\n" "$1"; }
success-log() { printf "${GREEN_B}[SUCCESS]${RC} %s\n" "$1"; }
warning-log() { printf "${YELLOW_B}[WARNING]${RC} %s\n" "$1" >&2; }
error-log()   { printf "${RED_B}[ERROR]${RC} %s\n" "$1" >&2; }
