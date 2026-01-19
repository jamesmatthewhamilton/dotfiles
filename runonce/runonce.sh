#!/usr/bin/env bash
set -euo pipefail

# Get the directory where this script lives (dotfiles root)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Load shared color definitions
source "${SCRIPT_DIR}/bash/lib_colors.sh"

warn() {
    printf "${BOLD_YELLOW}WARNING: %s${RESET}\n" "$1"
}

success() {
    printf "${GREEN}✓ %s${RESET}\n" "$1"
}

# Backup a file by adding .bak.YYYY-MM-DD suffix (with counter if needed)
backup_file() {
    local target="$1"
    local date_stamp
    date_stamp="$(date +%Y-%m-%d)"
    local backup="${target}.bak.${date_stamp}"

    # If backup already exists today, add incrementing counter
    if [ -e "$backup" ] || [ -L "$backup" ]; then
        local counter=1
        while [ -e "${backup}.${counter}" ] || [ -L "${backup}.${counter}" ]; do
            ((counter++))
        done
        backup="${backup}.${counter}"
    fi

    mv "$target" "$backup"
    echo "$backup"
}

# Create a symlink, backing up existing files if needed
create_symlink() {
    local source="$1"
    local target="$2"

    # Ensure source exists
    if [ ! -e "$source" ]; then
        warn "Source file does not exist: $source"
        return 1
    fi

    # Create parent directory if needed
    local target_dir
    target_dir="$(dirname "$target")"
    if [ ! -d "$target_dir" ]; then
        mkdir -p "$target_dir"
    fi

    # Check if target already exists
    if [ -L "$target" ]; then
        # It's a symlink - check if it points to our source
        local current_target
        current_target="$(readlink "$target")"
        if [ "$current_target" = "$source" ]; then
            success "Already linked: $target -> $source"
            return 0
        else
            # Different symlink, back it up
            local backup
            backup="$(backup_file "$target")"
            warn "Existing symlink renamed to: $backup"
        fi
    elif [ -e "$target" ]; then
        # Regular file/directory exists, back it up
        local backup
        backup="$(backup_file "$target")"
        warn "Existing file renamed to: $backup"
    fi

    # Create the symlink
    ln -s "$source" "$target"
    success "Linked: $target -> $source"
}

# Setup all dotfile symlinks
setup_symlinks() {
    printf "\n=== Setting up dotfile symlinks ===\n\n"

    # Bash configuration - main entry point
    create_symlink "${SCRIPT_DIR}/bash/bashrc.sh" "${HOME}/.bashrc"

    # Bash libraries - loaded first (lib_*.sh)
    create_symlink "${SCRIPT_DIR}/bash/lib_colors.sh" "${HOME}/.lib_colors.sh"

    # Bash configuration - modular config files
    # These are sourced by bashrc.sh via glob pattern bashrc_[[:alpha:]]*.sh
    create_symlink "${SCRIPT_DIR}/bash/bashrc_config.sh" "${HOME}/.bashrc_config.sh"
    create_symlink "${SCRIPT_DIR}/bash/bashrc_aliases.sh" "${HOME}/.bashrc_aliases.sh"
    create_symlink "${SCRIPT_DIR}/bash/bashrc_docker.sh" "${HOME}/.bashrc_docker.sh"
    create_symlink "${SCRIPT_DIR}/bash/bashrc_tmp.sh" "${HOME}/.bashrc_tmp.sh"

    # Mark bashrc_tmp.sh as skip-worktree so local changes don't appear in git status
    git -C "${SCRIPT_DIR}" update-index --skip-worktree bash/bashrc_tmp.sh 2>/dev/null && \
        success "Marked bashrc_tmp.sh as skip-worktree" || true

    # Git configuration
    create_symlink "${SCRIPT_DIR}/.gitconfig" "${HOME}/.gitconfig"

    # Emacs configuration
    create_symlink "${SCRIPT_DIR}/emacs/init.el" "${HOME}/.emacs.d/init.el"

    # macOS-specific (only on Darwin)
    if [ "$(uname)" = "Darwin" ]; then
        create_symlink "${SCRIPT_DIR}/mac/DefaultKeyBinding.dict" "${HOME}/Library/KeyBindings/DefaultKeyBinding.dict"
        create_symlink "${SCRIPT_DIR}/bash/mac_bashrc.sh" "${HOME}/.mac_bashrc.sh"
    fi

    printf "\n=== Symlink setup complete ===\n"
}

globals() {

    PKGS=(
        git  # Version control
        curl  # HTTP(S) client for APIs/downloads
        wget  # Alternative downloader (HTTP/FTP); handy with curl
        tree  # Directory tree viewer
        screen  # Terminal multiplexer (persistent splits/sessions)
    )

    BREW_PKGS=(
        bash  # Modern Bash 5+ (macOS ships ancient 3.2)
        bash-completion@2  # Programmable tab-completion for Bash 4/5
        gcc make pkg-config  # C/C++
        openssh  # Remote connect via ssh
        coreutils  # GNU core tools (ls, cp, mv…) with consistent flags
        findutils  # GNU find/xargs/locate (gfind etc.) for parity w/ Linux
        gnu-sed  # GNU sed (gsed) for portable sed scripting
        gnu-tar  # GNU tar (gtar) for consistent tar behavior
    )

    APT_PKGS=(
        bash-completion  # Programmable tab-completion for Bash 4/5
        build-essential pkg-config  # C/C++
        openssh-client  # Remote connect via ssh
    )

    DNF_YUM_PKGS=(
        bash-completion  # Programmable tab-completion for Bash 4/5
        gcc gcc-c++ make pkgconfig  # C/C++
        openssh-clients  # Remote connect via ssh
    )
}

does_cmd_exist() {
    command -v "$1" >/dev/null 2>&1;
}

need_sudo() {
  if [ "$(id -u)" -eq 0 ]; then
    SUDO=""
  else
    if does_cmd_exist sudo; then
      SUDO="sudo"
    else
      printf "This script needs root privileges (no sudo found). Run as root."
      exit 1
    fi
  fi
}

install() {

    globals

    # ----- Detect package manager -----
    PM=""
    if does_cmd_exist brew; then
        PM="brew"
    elif does_cmd_exist apt-get || does_cmd_exist apt; then
        PM="apt"
    elif does_cmd_exist dnf; then
        PM="dnf"
    elif does_cmd_exist yum; then
        PM="yum"
    else
        printf "No supported package manager found (brew/apt/dnf/yum)."
        exit 1
    fi

    printf "Detected package manager: $PM"
    need_sudo

    # ----- Install packages -----
    case "$PM" in
        brew)
            # Ensure Brew is initialized in non-login shells
            if [ -d "/opt/homebrew" ] && ! echo "$PATH" | grep -q "/opt/homebrew/bin"; then
                eval "$(/opt/homebrew/bin/brew shellenv)"
            elif [ -d "/home/linuxbrew/.linuxbrew" ] && ! echo "$PATH" | grep -q "/home/linuxbrew/.linuxbrew/bin"; then
                eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"
            fi

            printf "Updating Homebrew…"
            brew update

            printf "Installing packages (brew)…"
            brew install "${BREW_PKGS[@]}"

            # Optional: set up fzf key bindings if installed
            if does_cmd_exist fzf && [ -f "$(brew --prefix)/opt/fzf/install" ]; then
                yes | "$(brew --prefix)"/opt/fzf/install --key-bindings --completion --no-update-rc >/dev/null
            fi
            ;;

        apt)
            printf "Updating APT metadata…"
            $SUDO apt-get update -y || $SUDO apt-get update

            printf "Installing packages (apt)…"
            $SUDO apt-get install -y "${APT_PKGS[@]}"

            # Debian/Ubuntu: fd-find installs 'fdfind' — add a friendly 'fd' shim if missing
            if does_cmd_exist fdfind && ! does_cmd_exist fd; then
                printf "Linking fdfind -> fd in /usr/local/bin…"
                $SUDO ln -sf "$(command -v fdfind)" /usr/local/bin/fd
            fi
            ;;

        dnf|yum)
            # Try to enable EPEL on RHEL-like if available (for ripgrep/htop on some releases)
            if [ -r /etc/os-release ]; then
                . /etc/os-release
                if echo "${ID_LIKE:-$ID}" | grep -qi "rhel\|centos\|fedora"; then
                    if [ "${ID:-}" != "fedora" ]; then
                        # RHEL/Rocky/Alma
                        if does_cmd_exist dnf; then $SUDO dnf install -y epel-release || true
                        else $SUDO yum install -y epel-release || true
                        fi
                    fi
                fi
            fi

            printf "Refreshing metadata…"
            if [ "$PM" = "dnf" ]; then
                $SUDO dnf makecache -y || true
                printf "Installing packages (dnf)…"
                $SUDO dnf install -y "${DNF_YUM_PKGS[@]}"
            else
                $SUDO yum makecache -y || true
                printf "Installing packages (yum)…"
                $SUDO yum install -y "${DNF_YUM_PKGS[@]}"
            fi
            ;;

    esac

    # ----- Post-install quality-of-life tweaks -----

    # Readline niceties (affects bash completion behavior, paste handling)
    INPUTRC="${INPUTRC:-$HOME/.inputrc}"
    if ! grep -q "enable-bracketed-paste" "${INPUTRC}" 2>/dev/null; then
        printf "Enabling basic Readline tweaks in ${INPUTRC}…"
        {
            echo "set enable-bracketed-paste on"
            echo "set completion-ignore-case on"
            echo "set show-all-if-ambiguous on"
        } >> "${INPUTRC}"
    fi

    printf "Done. Open a new shell and try:  git chec<Tab>   or   rg --he<Tab>\n"
}

usage() {
    printf "Usage: %s [command]\n\n" "$(basename "$0")"
    printf "Commands:\n"
    printf "  link      Setup symlinks only (no package installation)\n"
    printf "  install   Install packages only (no symlinks)\n"
    printf "  all       Install packages AND setup symlinks (default)\n"
    printf "  help      Show this help message\n"
}

main() {
    local cmd="${1:-all}"

    case "$cmd" in
        link)
            setup_symlinks
            ;;
        install)
            install
            ;;
        all)
            install
            setup_symlinks
            ;;
        help|--help|-h)
            usage
            ;;
        *)
            printf "Unknown command: %s\n\n" "$cmd"
            usage
            exit 1
            ;;
    esac
}

main "$@"
