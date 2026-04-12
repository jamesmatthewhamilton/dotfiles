# Shared logging banners.
# Uses vars instead of functions for graceful degradation.

[[ -n "${_COMMON_LOGGER_LOADED:-}" ]] && return 0
_COMMON_LOGGER_LOADED=1

if [[ -z "${NC:-}" ]]; then
    source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/colors.sh"
fi

INFO="${CYAN}[INFO]${NC} "
DEBUG="${MAGENTA}[DEBUG]${NC} "
WARNING="${YELLOW}[WARNING]${NC} "
ERROR="${RED}[ERROR]${NC} "

SUCCESS="${GREEN_BG}[SUCCESS]${NC} "
FAILURE="${RED_BG}[FAILURE]${NC} "

HINT="${MAGENTA}[HINT]${NC} "
