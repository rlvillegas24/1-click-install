#!/usr/bin/env bash
set -uo pipefail

APP_VERSION="0.1.0"
ASSUME_YES=0
DRY_RUN=0
NO_COLOR=0
INTERACTIVE=0
PLATFORM="unknown"
PKG_MANAGER="unknown"
SUDO_CMD=""
RESULTS=()

AI_TOOLS=(
  "Claude Code|claude|npm|@anthropic-ai/claude-code|claude --version"
  "cc-mirror|cc-mirror|npm|cc-mirror|cc-mirror --help"
  "Minimax|mmx|npm|mmx-cli|mmx --version"
  "Gemini CLI|gemini|npm|@google/gemini-cli|gemini --version"
)

usage() {
  cat <<'USAGE'
Developer CLI Tools Installer

Usage:
  bash install.sh [options]

Options:
  -y, --yes       Run without confirmation prompts
      --dry-run   Print planned actions without installing
      --no-color  Disable colored output
  -h, --help      Show this help message
USAGE
}

parse_args() {
  while [ "$#" -gt 0 ]; do
    case "$1" in
      -y|--yes) ASSUME_YES=1 ;;
      --dry-run) DRY_RUN=1 ;;
      --no-color) NO_COLOR=1 ;;
      -h|--help) usage; exit 0 ;;
      *) fail "Unknown option: $1" ;;
    esac
    shift
  done
}

setup_terminal() {
  if [ -t 1 ] && [ "$NO_COLOR" -eq 0 ] && [ "${TERM:-}" != "dumb" ]; then
    BOLD="$(printf '\033[1m')"
    DIM="$(printf '\033[2m')"
    RED="$(printf '\033[31m')"
    GREEN="$(printf '\033[32m')"
    YELLOW="$(printf '\033[33m')"
    BLUE="$(printf '\033[34m')"
    RESET="$(printf '\033[0m')"
  else
    BOLD=""; DIM=""; RED=""; GREEN=""; YELLOW=""; BLUE=""; RESET=""
  fi

  if [ -r /dev/tty ]; then
    INTERACTIVE=1
  fi
}

header() {
  printf '%s\n' "${BOLD}${BLUE}+----------------------------------------------+${RESET}"
  printf '%s\n' "${BOLD}${BLUE}|      Developer CLI Tools Installer           |${RESET}"
  printf '%s\n' "${BOLD}${BLUE}+----------------------------------------------+${RESET}"
  printf '%s\n' "${DIM}Version ${APP_VERSION}${RESET}"
  printf '\n'
}

section() {
  printf '\n%s\n' "${BOLD}${BLUE}> $1${RESET}"
}

ok() {
  printf '%s\n' "${GREEN}[ok]${RESET} $1"
}

warn() {
  printf '%s\n' "${YELLOW}[!]${RESET} $1"
}

err() {
  printf '%s\n' "${RED}[x]${RESET} $1" >&2
}

fail() {
  err "$1"
  exit 1
}

run_cmd() {
  printf '%s\n' "${DIM}$ $*${RESET}"
  if [ "$DRY_RUN" -eq 1 ]; then
    return 0
  fi
  "$@"
}

run_shell() {
  printf '%s\n' "${DIM}$ $*${RESET}"
  if [ "$DRY_RUN" -eq 1 ]; then
    return 0
  fi
  sh -c "$*"
}

command_exists() {
  command -v "$1" >/dev/null 2>&1
}

add_result() {
  RESULTS+=("$1|$2|$3")
}

version_major() {
  "$@" 2>/dev/null | head -n 1 | sed -E 's/[^0-9]*([0-9]+).*/\1/'
}

detect_platform() {
  case "$(uname -s)" in
    Darwin)
      PLATFORM="macos"
      PKG_MANAGER="brew"
      ;;
    Linux)
      if grep -qi microsoft /proc/version 2>/dev/null; then
        PLATFORM="wsl"
      else
        PLATFORM="linux"
      fi

      if command_exists apt-get; then
        PKG_MANAGER="apt"
      elif command_exists dnf; then
        PKG_MANAGER="dnf"
      elif command_exists yum; then
        PKG_MANAGER="yum"
      else
        PKG_MANAGER="unknown"
      fi
      ;;
    *)
      fail "Unsupported OS: $(uname -s)"
      ;;
  esac

  if [ "$(id -u)" -ne 0 ] && command_exists sudo; then
    SUDO_CMD="sudo"
  fi
}

confirm_plan() {
  if [ "$ASSUME_YES" -eq 1 ] || [ "$DRY_RUN" -eq 1 ]; then
    return 0
  fi

  if [ "$INTERACTIVE" -ne 1 ]; then
    fail "Interactive confirmation is unavailable. Re-run with --yes for non-interactive install."
  fi

  printf 'Continue with installation? [y/N] ' >/dev/tty
  read -r answer </dev/tty
  case "$answer" in
    y|Y|yes|YES) ;;
    *) fail "Installation cancelled." ;;
  esac
}

show_plan() {
  section "Install Plan"
  printf 'Platform:        %s\n' "$PLATFORM"
  printf 'Package manager: %s\n' "$PKG_MANAGER"
  printf 'Mode:            %s\n' "$([ "$DRY_RUN" -eq 1 ] && printf dry-run || printf install)"
  printf '\nTools:\n'
  printf '  - Git\n'
  printf '  - Python 3.10+ and pip\n'
  printf '  - Node.js LTS and npm\n'
  printf '  - Claude Code\n'
  printf '  - cc-mirror\n'
  printf '  - Minimax\n'
  printf '  - Gemini CLI\n'
}

install_homebrew() {
  if command_exists brew; then
    ok "Homebrew found"
    return 0
  fi

  warn "Homebrew is required on macOS and is not installed"
  run_shell '/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"'

  if [ -x /opt/homebrew/bin/brew ]; then
    export PATH="/opt/homebrew/bin:$PATH"
  elif [ -x /usr/local/bin/brew ]; then
    export PATH="/usr/local/bin:$PATH"
  fi
}

install_brew_package() {
  binary="$1"
  package="$2"
  label="$3"
  if command_exists "$binary"; then
    ok "$label already installed"
    add_result "$label" "$("$binary" --version 2>/dev/null | head -n 1)" "skipped"
  else
    if run_cmd brew install "$package"; then
      [ "$DRY_RUN" -eq 1 ] && add_result "$label" "install planned" "planned" || add_result "$label" "installed" "installed"
    else
      add_result "$label" "install failed" "failed"
    fi
  fi
}

install_base_macos() {
  install_homebrew
  run_cmd brew update
  install_brew_package git git "Git"
  install_brew_package python3 python "Python"
  install_brew_package pip3 python "pip"
  install_brew_package node node "Node.js"
  install_brew_package npm node "npm"
}

install_apt_package() {
  binary="$1"
  package="$2"
  label="$3"
  if command_exists "$binary"; then
    ok "$label already installed"
    add_result "$label" "$("$binary" --version 2>/dev/null | head -n 1)" "skipped"
  else
    if run_cmd $SUDO_CMD apt-get install -y "$package"; then
      [ "$DRY_RUN" -eq 1 ] && add_result "$label" "install planned" "planned" || add_result "$label" "installed" "installed"
    else
      add_result "$label" "install failed" "failed"
    fi
  fi
}

install_rpm_package() {
  binary="$1"
  package="$2"
  label="$3"
  if command_exists "$binary"; then
    ok "$label already installed"
    add_result "$label" "$("$binary" --version 2>/dev/null | head -n 1)" "skipped"
  else
    if run_cmd $SUDO_CMD "$PKG_MANAGER" install -y "$package"; then
      [ "$DRY_RUN" -eq 1 ] && add_result "$label" "install planned" "planned" || add_result "$label" "installed" "installed"
    else
      add_result "$label" "install failed" "failed"
    fi
  fi
}

install_base_linux() {
  case "$PKG_MANAGER" in
    apt)
      run_cmd $SUDO_CMD apt-get update
      install_apt_package git git "Git"
      install_apt_package python3 python3 "Python"
      install_apt_package pip3 python3-pip "pip"
      install_apt_package node nodejs "Node.js"
      install_apt_package npm npm "npm"
      ;;
    dnf|yum)
      install_rpm_package git git "Git"
      install_rpm_package python3 python3 "Python"
      install_rpm_package pip3 python3-pip "pip"
      install_rpm_package node nodejs "Node.js"
      install_rpm_package npm npm "npm"
      ;;
    *)
      fail "No supported Linux package manager found. Expected apt, dnf, or yum."
      ;;
  esac
}

ensure_python_minimum() {
  if ! command_exists python3; then
    warn "Python 3 was not detected after install"
    return 0
  fi

  major="$(version_major python3 --version)"
  minor="$(python3 --version 2>/dev/null | sed -E 's/[^0-9]*[0-9]+\.([0-9]+).*/\1/')"
  if [ -n "${major:-}" ] && [ -n "${minor:-}" ] && [ "$major" -eq 3 ] && [ "$minor" -ge 10 ]; then
    ok "Python version satisfies 3.10+"
  else
    warn "Python 3.10+ was not detected after install. Check your package manager repositories."
  fi
}

ensure_node_available() {
  if command_exists node && command_exists npm; then
    ok "Node.js and npm available"
  else
    warn "Node.js/npm are not available after base install. AI CLI npm installs may fail."
  fi
}

install_ai_tools() {
  section "AI CLI Tools"
  if ! command_exists npm; then
    warn "Skipping AI CLI npm installs because npm is unavailable"
    add_result "AI CLI tools" "npm unavailable" "skipped"
    return 0
  fi

  old_ifs="$IFS"
  for tool in "${AI_TOOLS[@]}"; do
    IFS='|' read -r label binary manager package verify_cmd <<EOF_TOOL
$tool
EOF_TOOL
    IFS="$old_ifs"

    if command_exists "$binary"; then
      ok "$label already installed"
      add_result "$label" "$(sh -c "$verify_cmd" 2>/dev/null | head -n 1 || printf detected)" "skipped"
    elif [ "$manager" = "npm" ]; then
      if run_cmd npm install -g "$package"; then
        [ "$DRY_RUN" -eq 1 ] && add_result "$label" "install planned" "planned" || add_result "$label" "installed" "installed"
      else
        add_result "$label" "install failed for package $package" "failed"
      fi
    else
      add_result "$label" "unsupported manager $manager" "skipped"
    fi
  done
  IFS="$old_ifs"
}

configure_path() {
  section "PATH"
  npm_prefix="$(npm config get prefix 2>/dev/null || true)"
  if [ -n "$npm_prefix" ] && [ -d "$npm_prefix/bin" ]; then
    case ":$PATH:" in
      *":$npm_prefix/bin:"*) ok "npm global bin already in current PATH" ;;
      *) export PATH="$npm_prefix/bin:$PATH"; ok "Added npm global bin to current session PATH" ;;
    esac
  fi

  profile=""
  shell_name="$(basename "${SHELL:-}")"
  case "$shell_name" in
    zsh) profile="$HOME/.zshrc" ;;
    bash) profile="$HOME/.bashrc" ;;
    *) profile="$HOME/.profile" ;;
  esac

  if [ -n "$npm_prefix" ] && [ -d "$npm_prefix/bin" ] && [ "$DRY_RUN" -eq 0 ]; then
    marker="# Developer CLI Tools Installer PATH"
    if [ ! -f "$profile" ] || ! grep -Fq "$marker" "$profile"; then
      {
        printf '\n%s\n' "$marker"
        printf 'export PATH="%s/bin:$PATH"\n' "$npm_prefix"
      } >> "$profile"
      ok "Persisted npm global bin PATH in $profile"
    else
      ok "PATH profile block already present in $profile"
    fi
  fi
}

verify_tool() {
  label="$1"
  binary="$2"
  command_text="$3"
  if command_exists "$binary"; then
    value="$(sh -c "$command_text" 2>/dev/null | head -n 1 || true)"
    [ -n "$value" ] || value="detected"
    add_result "$label" "$value" "verified"
  else
    add_result "$label" "not found" "missing"
  fi
}

verify_all() {
  section "Verification"
  verify_tool "Git" git "git --version"
  verify_tool "Python" python3 "python3 --version"
  verify_tool "pip" pip3 "pip3 --version"
  verify_tool "Node.js" node "node --version"
  verify_tool "npm" npm "npm --version"
  verify_tool "Claude Code" claude "claude --version"
  verify_tool "cc-mirror" cc-mirror "cc-mirror --help"
  verify_tool "Minimax" mmx "mmx --version"
  verify_tool "Gemini CLI" gemini "gemini --version"
}

summary() {
  section "Summary"
  printf '%-18s | %-40s | %-10s\n' "Tool" "Version/Status" "Result"
  printf '%-18s-+-%-40s-+-%-10s\n' "------------------" "----------------------------------------" "----------"
  for row in "${RESULTS[@]}"; do
    IFS='|' read -r name value status <<EOF_ROW
$row
EOF_ROW
    printf '%-18s | %-40.40s | %-10s\n' "$name" "$value" "$status"
  done
}

main() {
  parse_args "$@"
  setup_terminal
  header
  detect_platform
  show_plan
  confirm_plan

  section "Base Dependencies"
  case "$PLATFORM" in
    macos) install_base_macos ;;
    linux|wsl) install_base_linux ;;
    *) fail "Unsupported platform: $PLATFORM" ;;
  esac

  ensure_python_minimum
  ensure_node_available
  configure_path
  install_ai_tools
  verify_all
  summary
}

main "$@"
