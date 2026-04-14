#!/usr/bin/env bash
set -eu

# Resolve the dotfiles repo root (one level up from runonce/)
DOTFILES_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Load shared logging functions (auto-sources colors.sh)
source "${DOTFILES_ROOT}/bash/common/logger.sh"

# Verify SHA256 checksum of a file. Exits on mismatch.
verify_checksum() {
    local file="$1"
    local expected="$2"
    local actual
    if does_cmd_exist shasum; then
        actual="$(shasum -a 256 "$file" | awk '{print $1}')"
    else
        actual="$(sha256sum "$file" | awk '{print $1}')"
    fi
    if [ "$actual" != "$expected" ]; then
        printf "CHECKSUM MISMATCH for %s\n  expected: %s\n  actual:   %s\n" "$file" "$expected" "$actual" >&2
        rm -f "$file"
        exit 1
    fi
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
        printf "$WARNING%s\n" "Source file does not exist: $source"
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
            printf "$SUCCESS%s\n" "Already linked: $target -> $source"
            return 0
        else
            # Different symlink, back it up
            local backup
            backup="$(backup_file "$target")"
            printf "$WARNING%s\n" "Existing symlink renamed to: $backup"
        fi
    elif [ -e "$target" ]; then
        # Regular file/directory exists, back it up
        local backup
        backup="$(backup_file "$target")"
        printf "$WARNING%s\n" "Existing file renamed to: $backup"
    fi

    # Create the symlink
    ln -s "$source" "$target"
    printf "$SUCCESS%s\n" "Linked: $target -> $source"
}

# Setup all dotfile symlinks
setup_symlinks() {
    printf "\n=== Setting up dotfile symlinks ===\n\n"

    # Special case: if ~/.bashrc exists as a regular file, append its contents to bashrc_tmp.sh
    if [ -f "${HOME}/.bashrc" ] && [ ! -L "${HOME}/.bashrc" ]; then
        local tmp_file="${DOTFILES_ROOT}/bash/bashrc_tmp.sh"

        # Skip if migration was already performed
        if grep -Fq "[START] Migration from original ~/.bashrc" "$tmp_file" 2>/dev/null; then
            printf "$WARNING%s\n" "Migration markers already present in bashrc_tmp.sh, skipping"
        else
            printf "Moving contents of bashrc to bashrc_tmp...\n"
            {
                echo ""
                echo "# -------------------------------------------------------"
                echo "# ------ [START] Migration from original ~/.bashrc ------"
                echo "# -------------------------------------------------------"
                cat "${HOME}/.bashrc"
                echo "# -----------------------------------------------------"
                echo "# ------ [END] Migration from original ~/.bashrc ------"
                echo "# -----------------------------------------------------"
            } >> "$tmp_file"
            printf "$SUCCESS%s\n" "Appended ~/.bashrc contents to bashrc_tmp.sh"
        fi
    fi

    # Bash configuration - main entry point
    create_symlink "${DOTFILES_ROOT}/bash/bashrc.sh" "${HOME}/.bashrc"

    # Shared libraries for scripts (~/.common/*.sh)
    create_symlink "${DOTFILES_ROOT}/bash/common/colors.sh" "${HOME}/.common/colors.sh"
    create_symlink "${DOTFILES_ROOT}/bash/common/logger.sh" "${HOME}/.common/logger.sh"

    # Bash configuration - modular config files
    # These are sourced by bashrc.sh via glob pattern bashrc_[[:alpha:]]*.sh
    create_symlink "${DOTFILES_ROOT}/bash/bashrc_config.sh" "${HOME}/.bashrc_config.sh"
    create_symlink "${DOTFILES_ROOT}/bash/bashrc_aliases.sh" "${HOME}/.bashrc_aliases.sh"
    create_symlink "${DOTFILES_ROOT}/bash/bashrc_docker.sh" "${HOME}/.bashrc_docker.sh"
    create_symlink "${DOTFILES_ROOT}/bash/bashrc_tmp.sh" "${HOME}/.bashrc_tmp.sh"

    # Mark bashrc_tmp.sh as skip-worktree so local changes don't appear in git status
    git -C "${DOTFILES_ROOT}" update-index --skip-worktree bash/bashrc_tmp.sh 2>/dev/null && \
        printf "$SUCCESS%s\n" "Marked bashrc_tmp.sh as skip-worktree" || true

    # Git configuration
    create_symlink "${DOTFILES_ROOT}/gitconfig" "${HOME}/.gitconfig"

    # Git global hooks
    mkdir -p "${HOME}/.githooks"
    create_symlink "${DOTFILES_ROOT}/git/hooks/pre-commit" "${HOME}/.githooks/pre-commit"
    create_symlink "${DOTFILES_ROOT}/git/hooks/post-commit" "${HOME}/.githooks/post-commit"
    chmod +x "${HOME}/.githooks/pre-commit" "${HOME}/.githooks/post-commit"
    printf "$SUCCESS%s\n" "Global git hooksPath set to ~/.githooks"

    # Emacs configuration
    create_symlink "${DOTFILES_ROOT}/emacs/init.el" "${HOME}/.emacs.d/init.el"

    # macOS-specific (only on Darwin)
    if [ "$(uname)" = "Darwin" ]; then
        # macOS keyboard subsystems do NOT follow symlinks for .keylayout and
        # DefaultKeyBinding.dict files — they must be real copies.
        mkdir -p "${HOME}/Library/KeyBindings"
        mkdir -p "${HOME}/Library/Keyboard Layouts"
        cp "${DOTFILES_ROOT}/mac/DefaultKeyBinding.dict" "${HOME}/Library/KeyBindings/DefaultKeyBinding.dict"
        printf "$SUCCESS%s\n" "Copied: DefaultKeyBinding.dict -> ~/Library/KeyBindings/"
        cp "${DOTFILES_ROOT}/mac/USPlain.keylayout" "${HOME}/Library/Keyboard Layouts/USPlain.keylayout"
        printf "$SUCCESS%s\n" "Copied: USPlain.keylayout -> ~/Library/Keyboard Layouts/"

        create_symlink "${DOTFILES_ROOT}/bash/mac_bashrc.sh" "${HOME}/.mac_bashrc.sh"
    fi

    printf "\n=== Symlink setup complete ===\n"
}

globals() {

    BREW_PKGS=(
        git  # Version control
        curl  # HTTP(S) client for APIs/downloads
        wget  # Alternative downloader (HTTP/FTP); handy with curl
        tree  # Directory tree viewer
        screen  # Terminal multiplexer (persistent splits/sessions)
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
        git  # Version control
        curl  # HTTP(S) client for APIs/downloads
        wget  # Alternative downloader (HTTP/FTP); handy with curl
        tree  # Directory tree viewer
        screen  # Terminal multiplexer (persistent splits/sessions)
        bash-completion  # Programmable tab-completion for Bash 4/5
        build-essential pkg-config  # C/C++
        openssh-client  # Remote connect via ssh
    )

    DNF_YUM_PKGS=(
        git  # Version control
        curl  # HTTP(S) client for APIs/downloads
        wget  # Alternative downloader (HTTP/FTP); handy with curl
        tree  # Directory tree viewer
        screen  # Terminal multiplexer (persistent splits/sessions)
        bash-completion  # Programmable tab-completion for Bash 4/5
        gcc gcc-c++ make pkg-config  # C/C++
        openssh-clients  # Remote connect via ssh
    )

    # Conda packages (user-space, no root required)
    # Channels: conda-forge (general), bioconda (bioinformatics)
    CONDA_PKGS=(
        git
        curl
        wget
        tree
        screen
        make
        pkg-config
    )
}

does_cmd_exist() {
    command -v "$1" >/dev/null 2>&1;
}

# Install conda to ~/Repos/conda with auto_activate_base disabled
# This makes conda available as a command without starting in (base)
setup_conda() {
    local CONDA_DIR="$HOME/Repos/conda"
    # Skip if already installed
    if [ -x "$CONDA_DIR/bin/conda" ]; then
        printf "$SUCCESS%s\n" "Conda already installed at $CONDA_DIR"
        return 0
    fi

    printf "Installing Miniconda to %s...\n" "$CONDA_DIR"

    # Create Repos directory if needed
    mkdir -p "$HOME/Repos"

    # Pinned Miniconda versions and checksums for supply chain safety
    local MINICONDA_URL MINICONDA_SHA256
    if [ "$(uname)" = "Darwin" ]; then
        if [ "$(uname -m)" = "arm64" ]; then
            MINICONDA_URL="https://repo.anaconda.com/miniconda/Miniconda3-py313_26.1.1-1-MacOSX-arm64.sh"
            MINICONDA_SHA256="745f97a6553ebdce0bfdaafe00b0d1939784b38cdaadb3378ca7868a51616a65"
        else
            MINICONDA_URL="https://repo.anaconda.com/miniconda/Miniconda3-py313_25.7.0-2-MacOSX-x86_64.sh"
            MINICONDA_SHA256="9c88674b1a839eeb4cff006df397a05ea7d896472318fd84b7070278f9653dc6"
        fi
    else
        if [ "$(uname -m)" = "aarch64" ]; then
            MINICONDA_URL="https://repo.anaconda.com/miniconda/Miniconda3-py313_26.1.1-1-Linux-aarch64.sh"
            MINICONDA_SHA256="07c82b5aec04d5f0f3e4b246835b6bc85e104821cbcb0a059c7ea80f028503f4"
        else
            MINICONDA_URL="https://repo.anaconda.com/miniconda/Miniconda3-py313_26.1.1-1-Linux-x86_64.sh"
            MINICONDA_SHA256="f6dfb5b59614fd7b2956b240b2575a9d58203ec7f7a99f85128158a0fdc5c1d7"
        fi
    fi

    local conda_tmp
    conda_tmp="$(mktemp /tmp/miniconda-XXXXXX.sh)"

    curl -fsSL "$MINICONDA_URL" -o "$conda_tmp"
    verify_checksum "$conda_tmp" "$MINICONDA_SHA256"
    chmod +x "$conda_tmp"
    "$conda_tmp" -b -p "$CONDA_DIR"
    rm -f "$conda_tmp"

    # Disable auto-activation of base environment
    "$CONDA_DIR/bin/conda" config --set auto_activate_base false

    printf "$SUCCESS%s\n" "Conda installed to $CONDA_DIR (base auto-activation disabled)"
}

# Install Homebrew on macOS if not present, and ensure it's in PATH
setup_homebrew() {
    # Only run on macOS
    if [ "$(uname)" != "Darwin" ]; then
        return 0
    fi

    # Check if brew already exists
    local need_install=true
    if [ -x /opt/homebrew/bin/brew ] || [ -x /usr/local/bin/brew ]; then
        printf "$SUCCESS%s\n" "Homebrew already installed"
        need_install=false
    fi

    # Install if needed
    if [ "$need_install" = true ]; then
        printf "Installing Homebrew...\n"

        # Pinned commit and checksum for supply chain safety
        local brew_commit="6d5e2670d07961e7985d2079a2f0a484420f3c38"
        local brew_sha256="dfd5145fe2aa5956a600e35848765273f5798ce6def01bd08ecec088a1268d91"
        local brew_tmp
        brew_tmp="$(mktemp /tmp/brew-install-XXXXXX)"

        curl -fsSL "https://raw.githubusercontent.com/Homebrew/install/${brew_commit}/install.sh" -o "$brew_tmp"
        verify_checksum "$brew_tmp" "$brew_sha256"
        NONINTERACTIVE=1 /bin/bash "$brew_tmp"
        rm -f "$brew_tmp"

        printf "$SUCCESS%s\n" "Homebrew installed"
    fi

    # Always add brew to PATH for this session (needed for non-interactive scripts)
    if [ -x /opt/homebrew/bin/brew ]; then
        eval "$(/opt/homebrew/bin/brew shellenv)"
    elif [ -x /usr/local/bin/brew ]; then
        eval "$(/usr/local/bin/brew shellenv)"
    fi
}

# Install Docker and enable on boot (Linux only)
setup_docker() {
    # Skip if already installed
    if does_cmd_exist docker; then
        printf "$SUCCESS%s\n" "Docker already installed"
        return 0
    fi

    if [ "$(uname)" = "Darwin" ]; then
        printf "Installing Docker Desktop (brew cask)…\n"
        brew install --cask docker || true
        printf "$SUCCESS%s\n" "Docker Desktop installed (launch manually from Applications)"
    elif does_cmd_exist apt-get; then
        printf "Installing Docker (official apt repo)…\n"
        # Prerequisites
        $SUDO apt-get install -y ca-certificates curl gnupg

        # Add Docker's official GPG key
        $SUDO install -m 0755 -d /etc/apt/keyrings
        curl -fsSL https://download.docker.com/linux/ubuntu/gpg | $SUDO gpg --dearmor -o /etc/apt/keyrings/docker.gpg
        $SUDO chmod a+r /etc/apt/keyrings/docker.gpg

        # Add the repository
        echo \
          "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
          $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
          $SUDO tee /etc/apt/sources.list.d/docker.list > /dev/null

        $SUDO apt-get update -y
        $SUDO apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

        # Enable and start on boot
        $SUDO systemctl enable docker
        $SUDO systemctl start docker

        # Allow current user to run docker without sudo
        $SUDO usermod -aG docker "$USER" 2>/dev/null || true
        printf "$SUCCESS%s\n" "Docker installed and enabled on boot (log out and back in for group change)"

    elif does_cmd_exist dnf || does_cmd_exist yum; then
        printf "Installing Docker (official yum/dnf repo)…\n"
        local PM_CMD
        if does_cmd_exist dnf; then PM_CMD="dnf"; else PM_CMD="yum"; fi

        # Add Docker's official repo
        $SUDO $PM_CMD install -y yum-utils
        $SUDO yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo

        # CentOS 8+ may conflict with podman
        $SUDO $PM_CMD install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin \
            --allowerasing || \
        $SUDO $PM_CMD install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

        # Enable and start on boot
        $SUDO systemctl enable docker
        $SUDO systemctl start docker

        # Allow current user to run docker without sudo
        $SUDO usermod -aG docker "$USER" 2>/dev/null || true
        printf "$SUCCESS%s\n" "Docker installed and enabled on boot (log out and back in for group change)"
    else
        printf "$WARNING%s\n" "Could not install Docker: unsupported package manager"
    fi
}

# Apply preferred macOS System Settings — mimics clicking through Settings.app.
#
# Currently handles:
#   - Privacy & Security > Analytics & Improvements (all toggles off)
#
# macOS ONLY — caller must guard with `[ "$(uname)" = "Darwin" ]`.
# Safe to run repeatedly; each toggle is idempotent. Uses sudo for the system-wide
# CrashReporter plist; other toggles write to the user's defaults domain.
settings_app() {
    printf "\n=== Applying Settings.app preferences ===\n"

    # ------------ Analytics & Improvements ------------
    printf "\n--- Privacy & Security > Analytics & Improvements ---\n\n"

    # Share Mac Analytics — diagnostic and usage data (may include location)
    if sudo defaults write "/Library/Application Support/CrashReporter/DiagnosticMessagesHistory.plist" AutoSubmit -bool false 2>/dev/null \
       && defaults write com.apple.CrashReporter DialogType -string "none" 2>/dev/null; then
        printf "$SUCCESS%s\n" "Share Mac Analytics: disabled"
    else
        printf "$FAILURE%s\n" "Share Mac Analytics: failed to disable (may need Full Disk Access)"
    fi

    # Improve Siri & Dictation — audio recordings of Siri, Dictation, and Translate
    if defaults write com.apple.assistant.support "Siri Data Sharing Opt-In Status" -int 2 2>/dev/null; then
        printf "$SUCCESS%s\n" "Improve Siri & Dictation: disabled"
    else
        printf "$FAILURE%s\n" "Improve Siri & Dictation: failed to disable"
    fi

    # Improve Assistive Voice Features — audio from Voice Shortcuts and Voice Control
    if defaults write com.apple.Accessibility AXSAssistiveVoiceFeaturesOptIn -bool false 2>/dev/null; then
        printf "$SUCCESS%s\n" "Improve Assistive Voice Features: disabled"
    else
        printf "$FAILURE%s\n" "Improve Assistive Voice Features: failed to disable"
    fi

    # Share with App Developers — app crash and usage data
    if defaults write com.apple.appleseed.FeedbackAssistant "Autosend" -bool false 2>/dev/null; then
        printf "$SUCCESS%s\n" "Share with App Developers: disabled"
    else
        printf "$FAILURE%s\n" "Share with App Developers: failed to disable"
    fi

    # Share iCloud Analytics — iCloud, Siri, and intelligent features usage data
    if defaults write com.apple.assistant.support "iCloud Analytics Opt-In Status" -int 1 2>/dev/null; then
        printf "$SUCCESS%s\n" "Share iCloud Analytics: disabled"
    else
        printf "$FAILURE%s\n" "Share iCloud Analytics: failed to disable"
    fi

    printf "\n=== Settings.app preferences complete ===\n"
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

    # ----- Install Homebrew on macOS if needed -----
    setup_homebrew

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
    fi

    if [ -z "$PM" ]; then
        printf "No supported package manager found (brew/apt/dnf/yum).\n"
        printf "For systems without root access, use: ./runonce.sh install-conda\n"
        exit 1
    fi

    printf "Detected package manager: $PM\n"

    # Need sudo for system package managers (not brew)
    if [ "$PM" != "brew" ]; then
        need_sudo
    fi

    # ----- Install packages -----
    case "$PM" in
        brew)
            # Ensure Brew is initialized in non-login shells
            if [ -d "/opt/homebrew" ] && ! echo "$PATH" | grep -q "/opt/homebrew/bin"; then
                eval "$(/opt/homebrew/bin/brew shellenv)"
            elif [ -d "/home/linuxbrew/.linuxbrew" ] && ! echo "$PATH" | grep -q "/home/linuxbrew/.linuxbrew/bin"; then
                eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"
            fi

            printf "Updating Homebrew…\n"
            brew update || true

            printf "Installing packages (brew)…\n"
            brew install "${BREW_PKGS[@]}" || true

            # Set Homebrew bash as login shell (eliminates macOS zsh nag)
            local brew_bash=""
            if [ -x /opt/homebrew/bin/bash ]; then
                brew_bash="/opt/homebrew/bin/bash"
            elif [ -x /usr/local/bin/bash ]; then
                brew_bash="/usr/local/bin/bash"
            fi
            if [ -n "$brew_bash" ]; then
                if ! grep -Fxq "$brew_bash" /etc/shells 2>/dev/null; then
                    sudo sh -c "echo '$brew_bash' >> /etc/shells"
                fi
                if [ "$(dscl . -read /Users/$USER UserShell | awk '{print $2}')" != "$brew_bash" ]; then
                    chsh -s "$brew_bash"
                    printf "$SUCCESS%s\n" "Login shell set to $brew_bash"
                else
                    printf "$SUCCESS%s\n" "Login shell already set to $brew_bash"
                fi
            else
                printf "$WARNING%s\n" "Homebrew bash not found, skipping login shell change"
            fi

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

    # ----- Install Docker -----
    setup_docker

    # ----- macOS system settings (Privacy & Security toggles, etc.) -----
    if [ "$(uname)" = "Darwin" ]; then
        settings_app
    fi

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

    # ----- Install Conda (optional, no base activation) -----
    setup_conda

    printf "Done. Open a new shell and try:  git chec<Tab>   or   rg --he<Tab>\n"
}

install_conda() {
    globals

    # Bootstrap miniconda if not installed
    if ! does_cmd_exist conda; then
        printf "Bootstrapping miniconda...\n"
        local MINICONDA_URL MINICONDA_SHA256
        if [ "$(uname)" = "Darwin" ]; then
            if [ "$(uname -m)" = "arm64" ]; then
                MINICONDA_URL="https://repo.anaconda.com/miniconda/Miniconda3-py313_26.1.1-1-MacOSX-arm64.sh"
                MINICONDA_SHA256="745f97a6553ebdce0bfdaafe00b0d1939784b38cdaadb3378ca7868a51616a65"
            else
                MINICONDA_URL="https://repo.anaconda.com/miniconda/Miniconda3-py313_25.7.0-2-MacOSX-x86_64.sh"
                MINICONDA_SHA256="9c88674b1a839eeb4cff006df397a05ea7d896472318fd84b7070278f9653dc6"
            fi
        else
            if [ "$(uname -m)" = "aarch64" ]; then
                MINICONDA_URL="https://repo.anaconda.com/miniconda/Miniconda3-py313_26.1.1-1-Linux-aarch64.sh"
                MINICONDA_SHA256="07c82b5aec04d5f0f3e4b246835b6bc85e104821cbcb0a059c7ea80f028503f4"
            else
                MINICONDA_URL="https://repo.anaconda.com/miniconda/Miniconda3-py313_26.1.1-1-Linux-x86_64.sh"
                MINICONDA_SHA256="f6dfb5b59614fd7b2956b240b2575a9d58203ec7f7a99f85128158a0fdc5c1d7"
            fi
        fi
        local conda_tmp
        conda_tmp="$(mktemp /tmp/miniconda-XXXXXX.sh)"

        curl -fsSL "$MINICONDA_URL" -o "$conda_tmp"
        verify_checksum "$conda_tmp" "$MINICONDA_SHA256"
        chmod +x "$conda_tmp"
        "$conda_tmp" -b -p "$HOME/miniconda3"
        rm -f "$conda_tmp"
        export PATH="$HOME/miniconda3/bin:$PATH"
    fi

    printf "Installing packages (conda)…\n"
    conda install -y --override-channels -c conda-forge "${CONDA_PKGS[@]}"

    printf "Done. Add to PATH: export PATH=\"\$HOME/miniconda3/bin:\$PATH\"\n"
}

usage() {
    printf "Usage: %s [command]\n\n" "$(basename "$0")"
    printf "Commands:\n"
    printf "  link           Setup symlinks only (no package installation)\n"
    printf "  install        Install packages via system package manager (requires root)\n"
    printf "  install-conda  Install packages via conda (no root required)\n"
    printf "  all            Install packages AND setup symlinks (default)\n"
    printf "  help           Show this help message\n"
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
        install-conda)
            install_conda
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
