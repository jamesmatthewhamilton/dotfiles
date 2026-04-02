# dotfiles

Personal dotfiles with automated provisioning for **macOS** (ARM64/x86_64), **Ubuntu/Debian**, and **RHEL/CentOS** systems.

## Quick Start

```bash
git clone <repo-url> ~/Repos/dotfiles
cd ~/Repos/dotfiles
./runonce/runonce.sh
```

## Usage

| Command | Description |
|---------|-------------|
| `./runonce/runonce.sh` | Full setup (install packages + symlink dotfiles) |
| `./runonce/runonce.sh link` | Symlink dotfiles only (no package installation) |
| `./runonce/runonce.sh install` | Install packages only (requires root on Linux) |
| `./runonce/runonce.sh install-conda` | Install packages via conda (no root required) |

## Design Principles

**Cross-platform.** Every change must work on all three target platforms: macOS (ARM64/x86_64), Ubuntu/Debian, and RHEL/CentOS. Do not use GNU-specific flags, platform-specific paths, or package names without handling all targets.

**Idempotent.** All commands can be run repeatedly without side effects. Existing symlinks are detected and skipped. Packages that are already installed are left alone. Files are never silently overwritten -- conflicts are backed up with a `.bak.<date>` suffix. Exception: macOS keybinding files (`DefaultKeyBinding.dict`, `USPlain.keylayout`) are always overwritten because macOS does not follow symlinks for these files.

## Platform Support

- **macOS**: Installs via Homebrew (auto-installed if missing)
- **Ubuntu/Debian**: Installs via apt
- **RHEL/CentOS/Fedora**: Installs via dnf/yum
- **No root access**: `install-conda` provides core tools via Miniconda
