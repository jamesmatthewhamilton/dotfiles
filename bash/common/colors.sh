# ANSI color codes for terminal output
# Usage: printf "${RED}Error:${RESET} something went wrong\n"

# No Color (NC)
export NC='\033[0m'

# Colors
export BLACK='\033[0;30m'
export RED='\033[0;31m'
export GREEN='\033[0;32m'
export YELLOW='\033[0;33m'
export BLUE='\033[0;34m'
export MAGENTA='\033[0;35m'
export CYAN='\033[0;36m'
export WHITE='\033[0;37m'

# Bold Colors
export BLACK_B='\033[1;30m'
export RED_B='\033[1;31m'
export GREEN_B='\033[1;32m'
export YELLOW_B='\033[1;33m'
export BLUE_B='\033[1;34m'
export MAGENTA_B='\033[1;35m'
export CYAN_B='\033[1;36m'
export WHITE_B='\033[1;37m'

# Background Colors
export BLACK_BG='\033[40m'
export RED_BG='\033[41m'
export GREEN_BG='\033[42m'
export YELLOW_BG='\033[43m'
export BLUE_BG='\033[44m'
export MAGENTA_BG='\033[45m'
export CYAN_BG='\033[46m'
export WHITE_BG='\033[47m'
