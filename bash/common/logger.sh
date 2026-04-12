# Shared logging banners.
# Uses vars instead of functions for graceful degradation.

[[ -n "${_COMMON_LOGGER_LOADED:-}" ]] && return 0
_COMMON_LOGGER_LOADED=1

if [[ -z "${NC:-}" ]]; then
    source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/colors.sh"
fi

export INFO="${CYAN}[INFO]${NC} "
export DEBUG="${MAGENTA}[DEBUG]${NC} "
export WARNING="${YELLOW}[WARNING]${NC} "
export ERROR="${RED}[ERROR]${NC} "

export SUCCESS="${GREEN_BG}[SUCCESS]${NC} "
export FAILURE="${RED_BG}[FAILURE]${NC} "

export HINT="${MAGENTA}[HINT]${NC} "
