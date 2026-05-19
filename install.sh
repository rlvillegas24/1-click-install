#!/usr/bin/env bash
set -uo pipefail

APP_VERSION="0.1.0"
ASSUME_YES=0
DRY_RUN=0
NO_COLOR=0
INTERACTIVE=0
MODE="quick"
ONLY_LIST=""
SKIP_LIST=""
MIRROR_LIST=""
PLATFORM="unknown"
PKG_MANAGER="unknown"
SUDO_CMD=""
RESULTS=()
BOLD=""; DIM=""; RED=""; GREEN=""; YELLOW=""; BLUE=""; RESET=""
SEL_GIT=1
SEL_PYTHON=1
SEL_NODE=1
SEL_CLAUDE=0
SEL_CC_MIRROR=1
SEL_MINIMAX=0
SEL_CODEX=1
SEL_GEMINI=1
MIRROR_CLAUDE=0
MIRROR_MINIMAX=1
MIRROR_CODEX=0
MIRROR_KIMI=0

AI_TOOLS=(
  "cc-mirror|cc-mirror|npm|cc-mirror|cc-mirror --help"
  "Claude Code|claude|npm|@anthropic-ai/claude-code|claude --version"
  "Minimax|mmx|npm|mmx-cli|mmx --version"
  "OpenAI Codex|codex|npm|@openai/codex|codex --version"
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
      --mode MODE  Choose quick, custom, or mirror
      --only LIST  Install only comma-separated tools
      --skip LIST  Skip comma-separated tools
      --mirror LIST
                  Install/use comma-separated AI tools through cc-mirror
  -h, --help      Show this help message
USAGE
}

parse_args() {
  while [ "$#" -gt 0 ]; do
    case "$1" in
      -y|--yes) ASSUME_YES=1 ;;
      --dry-run) DRY_RUN=1 ;;
      --no-color) NO_COLOR=1 ;;
      --mode)
        shift
        [ "$#" -gt 0 ] || fail "--mode requires quick, custom, or mirror"
        MODE="$1"
        ;;
      --mode=*) MODE="${1#*=}" ;;
      --only)
        shift
        [ "$#" -gt 0 ] || fail "--only requires a comma-separated list"
        ONLY_LIST="$1"
        ;;
      --only=*) ONLY_LIST="${1#*=}" ;;
      --skip)
        shift
        [ "$#" -gt 0 ] || fail "--skip requires a comma-separated list"
        SKIP_LIST="$1"
        ;;
      --skip=*) SKIP_LIST="${1#*=}" ;;
      --mirror)
        shift
        [ "$#" -gt 0 ] || fail "--mirror requires a comma-separated list"
        MIRROR_LIST="$1"
        ;;
      --mirror=*) MIRROR_LIST="${1#*=}" ;;
      -h|--help) usage; exit 0 ;;
      *) fail "Unknown option: $1" ;;
    esac
    shift
  done
}

normalize_token() {
  printf '%s' "$1" | tr '[:upper:]' '[:lower:]' | tr -d ' _-'
}

clear_selection() {
  SEL_GIT=0
  SEL_PYTHON=0
  SEL_NODE=0
  SEL_CLAUDE=0
  SEL_CC_MIRROR=0
  SEL_MINIMAX=0
  SEL_CODEX=0
  SEL_GEMINI=0
  clear_mirror_variants
}

clear_mirror_variants() {
  MIRROR_CLAUDE=0
  MIRROR_MINIMAX=0
  MIRROR_CODEX=0
  MIRROR_KIMI=0
}

select_tool() {
  token="$(normalize_token "$1")"
  value="$2"
  case "$token" in
    git) SEL_GIT="$value" ;;
    python|pythonpip|pip) SEL_PYTHON="$value" ;;
    node|nodenpm|npm) SEL_NODE="$value" ;;
    claude|claudecode) SEL_CLAUDE="$value" ;;
    ccmirror)
      SEL_CC_MIRROR="$value"
      [ "$value" -eq 1 ] || clear_mirror_variants
      ;;
    minimax|mmx) SEL_MINIMAX="$value" ;;
    codex|openaicodex) SEL_CODEX="$value" ;;
    gemini|geminicli) SEL_GEMINI="$value" ;;
    base)
      SEL_GIT="$value"; SEL_PYTHON="$value"; SEL_NODE="$value"
      ;;
    ai)
      SEL_CLAUDE="$value"; SEL_MINIMAX="$value"; SEL_CODEX="$value"; SEL_GEMINI="$value"
      ;;
    all)
      SEL_GIT="$value"; SEL_PYTHON="$value"; SEL_NODE="$value"; SEL_CLAUDE="$value"; SEL_CC_MIRROR="$value"; SEL_MINIMAX="$value"; SEL_CODEX="$value"; SEL_GEMINI="$value"
      MIRROR_CLAUDE="$value"; MIRROR_MINIMAX="$value"; MIRROR_KIMI="$value"
      ;;
    "") ;;
    *) warn "Ignoring unknown tool selector: $1" ;;
  esac
}

apply_list() {
  list="$1"
  value="$2"
  [ -n "$list" ] || return 0
  old_ifs="$IFS"
  IFS=','
  for item in $list; do
    select_tool "$item" "$value"
  done
  IFS="$old_ifs"
}

apply_mirror_list() {
  [ -n "$MIRROR_LIST" ] || return 0
  old_ifs="$IFS"
  IFS=','
  for item in $MIRROR_LIST; do
    token="$(normalize_token "$item")"
    case "$token" in
      claude|claudecode|mclaude|mirror) MIRROR_CLAUDE=1; SEL_CC_MIRROR=1; SEL_NODE=1 ;;
      minimax|mmx) MIRROR_MINIMAX=1; SEL_CC_MIRROR=1; SEL_NODE=1 ;;
      kimi|kimiclaude) MIRROR_KIMI=1; SEL_CC_MIRROR=1; SEL_NODE=1 ;;
      codex|openaicodex) warn "Codex is direct-only and is not supported as a cc-mirror variant" ;;
      "") ;;
      *) warn "Ignoring unknown mirror selector: $item" ;;
    esac
  done
  IFS="$old_ifs"
}

configure_selection() {
  case "$MODE" in
    quick)
      SEL_GIT=1; SEL_PYTHON=1; SEL_NODE=1; SEL_CLAUDE=0; SEL_CC_MIRROR=1; SEL_MINIMAX=0; SEL_CODEX=1; SEL_GEMINI=1
      MIRROR_CLAUDE=0; MIRROR_MINIMAX=1; MIRROR_CODEX=0; MIRROR_KIMI=0
      ;;
    custom)
      SEL_GIT=1; SEL_PYTHON=1; SEL_NODE=1; SEL_CLAUDE=0; SEL_CC_MIRROR=1; SEL_MINIMAX=0; SEL_CODEX=1; SEL_GEMINI=1
      MIRROR_CLAUDE=0; MIRROR_MINIMAX=1; MIRROR_CODEX=0; MIRROR_KIMI=0
      ;;
    mirror)
      SEL_GIT=0; SEL_PYTHON=0; SEL_NODE=1; SEL_CLAUDE=0; SEL_CC_MIRROR=1; SEL_MINIMAX=0; SEL_CODEX=1; SEL_GEMINI=0
      MIRROR_CLAUDE=0; MIRROR_MINIMAX=1; MIRROR_CODEX=0; MIRROR_KIMI=0
      ;;
    *) fail "Unsupported mode: $MODE. Expected quick, custom, or mirror." ;;
  esac

  if [ -n "$ONLY_LIST" ]; then
    clear_selection
    apply_list "$ONLY_LIST" 1
  fi

  apply_list "$SKIP_LIST" 0
  apply_mirror_list

  if [ "$MIRROR_CLAUDE" -eq 1 ] || [ "$MIRROR_MINIMAX" -eq 1 ] || [ "$MIRROR_KIMI" -eq 1 ]; then
    SEL_CC_MIRROR=1
    SEL_NODE=1
  fi
}

interactive_custom_selection() {
  if [ "$MODE" != "custom" ] || [ "$ASSUME_YES" -eq 1 ] || [ "$DRY_RUN" -eq 1 ] || [ -n "$ONLY_LIST" ] || [ "$INTERACTIVE" -ne 1 ]; then
    return 0
  fi

  while :; do
    section "Choose Tools"
    printf '1 [%s] Git\n' "$([ "$SEL_GIT" -eq 1 ] && printf x || printf ' ')"
    printf '2 [%s] Python + pip\n' "$([ "$SEL_PYTHON" -eq 1 ] && printf x || printf ' ')"
    printf '3 [%s] Node.js + npm\n' "$([ "$SEL_NODE" -eq 1 ] && printf x || printf ' ')"
    printf '4 [%s] Claude Code\n' "$([ "$SEL_CLAUDE" -eq 1 ] && printf x || printf ' ')"
    printf '5 [%s] cc-mirror\n' "$([ "$SEL_CC_MIRROR" -eq 1 ] && printf x || printf ' ')"
    printf '6 [%s] Minimax\n' "$([ "$SEL_MINIMAX" -eq 1 ] && printf x || printf ' ')"
    printf '7 [%s] OpenAI Codex\n' "$([ "$SEL_CODEX" -eq 1 ] && printf x || printf ' ')"
    printf '8 [%s] Gemini CLI\n' "$([ "$SEL_GEMINI" -eq 1 ] && printf x || printf ' ')"
    printf 'Toggle numbers, a=all, n=none, Enter=continue, q=cancel: ' >/dev/tty
    read -r answer </dev/tty
    case "$answer" in
      "") break ;;
      q|Q) fail "Installation cancelled." ;;
      a|A) select_tool all 1 ;;
      n|N) clear_selection ;;
      *)
        old_ifs="$IFS"; IFS=', '
        for item in $answer; do
          case "$item" in
            1) [ "$SEL_GIT" -eq 1 ] && SEL_GIT=0 || SEL_GIT=1 ;;
            2) [ "$SEL_PYTHON" -eq 1 ] && SEL_PYTHON=0 || SEL_PYTHON=1 ;;
            3) [ "$SEL_NODE" -eq 1 ] && SEL_NODE=0 || SEL_NODE=1 ;;
            4) [ "$SEL_CLAUDE" -eq 1 ] && SEL_CLAUDE=0 || SEL_CLAUDE=1 ;;
            5)
              if [ "$SEL_CC_MIRROR" -eq 1 ]; then
                SEL_CC_MIRROR=0
                clear_mirror_variants
              else
                SEL_CC_MIRROR=1
              fi
              ;;
            6) [ "$SEL_MINIMAX" -eq 1 ] && SEL_MINIMAX=0 || SEL_MINIMAX=1 ;;
            7) [ "$SEL_CODEX" -eq 1 ] && SEL_CODEX=0 || SEL_CODEX=1 ;;
            8) [ "$SEL_GEMINI" -eq 1 ] && SEL_GEMINI=0 || SEL_GEMINI=1 ;;
          esac
        done
        IFS="$old_ifs"
        ;;
    esac
  done
}

interactive_mirror_selection() {
  if [ "$MODE" != "custom" ] || [ "$ASSUME_YES" -eq 1 ] || [ "$DRY_RUN" -eq 1 ] || [ -n "$MIRROR_LIST" ] || [ "$INTERACTIVE" -ne 1 ]; then
    return 0
  fi

  for item in claude minimax kimi; do
    printf 'Create cc-mirror variant for %s? [y/N] ' "$item" >/dev/tty
    read -r answer </dev/tty
    case "$answer" in
      y|Y|yes|YES)
        case "$item" in
          claude) MIRROR_CLAUDE=1; SEL_CC_MIRROR=1; SEL_NODE=1 ;;
          minimax) MIRROR_MINIMAX=1; SEL_CC_MIRROR=1; SEL_NODE=1 ;;
          kimi) MIRROR_KIMI=1; SEL_CC_MIRROR=1; SEL_NODE=1 ;;
        esac
        ;;
    esac
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
  printf 'Mode:            %s\n' "$MODE"
  printf 'Run mode:        %s\n' "$([ "$DRY_RUN" -eq 1 ] && printf dry-run || printf install)"
  printf '\nTools:\n'
  [ "$SEL_GIT" -eq 1 ] && printf '  - Git\n'
  [ "$SEL_PYTHON" -eq 1 ] && printf '  - Python 3.10+ and pip\n'
  [ "$SEL_NODE" -eq 1 ] && printf '  - Node.js LTS and npm\n'
  [ "$SEL_CLAUDE" -eq 1 ] && printf '  - Claude Code\n'
  [ "$SEL_CC_MIRROR" -eq 1 ] && printf '  - cc-mirror\n'
  [ "$MIRROR_CLAUDE" -eq 1 ] && printf '  - mclaude cc-mirror variant\n'
  [ "$MIRROR_MINIMAX" -eq 1 ] && printf '  - minimax cc-mirror variant\n'
  [ "$MIRROR_KIMI" -eq 1 ] && printf '  - kimi cc-mirror variant\n'
  [ "$SEL_MINIMAX" -eq 1 ] && printf '  - Minimax\n'
  [ "$SEL_CODEX" -eq 1 ] && printf '  - OpenAI Codex\n'
  [ "$SEL_GEMINI" -eq 1 ] && printf '  - Gemini CLI\n'
}

install_homebrew() {
  refresh_homebrew_path

  if command_exists brew; then
    ok "Homebrew found"
    return 0
  fi

  warn "Homebrew is required on macOS and is not installed"
  if [ "$ASSUME_YES" -eq 1 ] || [ "$INTERACTIVE" -ne 1 ]; then
    run_shell 'NONINTERACTIVE=1 CI=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"'
  else
    run_shell '/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"'
  fi

  if [ "$DRY_RUN" -eq 1 ]; then
    return 0
  fi

  refresh_homebrew_path

  if command_exists brew; then
    ok "Homebrew installed and available"
  else
    fail "Homebrew installation finished but brew is not available in PATH. Open a new terminal or install Homebrew manually, then rerun."
  fi
}

refresh_homebrew_path() {
  if command_exists brew; then
    return 0
  fi

  brew_bin=""
  if [ -x /opt/homebrew/bin/brew ]; then
    brew_bin="/opt/homebrew/bin/brew"
  elif [ -x /usr/local/bin/brew ]; then
    brew_bin="/usr/local/bin/brew"
  fi

  if [ -n "$brew_bin" ]; then
    brew_prefix="$("$brew_bin" --prefix 2>/dev/null || true)"
    if [ -n "$brew_prefix" ] && [ -x "$brew_prefix/bin/brew" ]; then
      eval "$("$brew_prefix/bin/brew" shellenv)"
    else
      export PATH="$(dirname "$brew_bin"):$PATH"
    fi
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
  [ "$SEL_GIT" -eq 1 ] && install_brew_package git git "Git"
  if [ "$SEL_PYTHON" -eq 1 ]; then
    install_brew_package python3 python "Python"
    install_brew_package pip3 python "pip"
  fi
  if [ "$SEL_NODE" -eq 1 ]; then
    install_brew_package node node "Node.js"
    install_brew_package npm node "npm"
  fi
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
      [ "$SEL_GIT" -eq 1 ] && install_apt_package git git "Git"
      if [ "$SEL_PYTHON" -eq 1 ]; then
        install_apt_package python3 python3 "Python"
        install_apt_package pip3 python3-pip "pip"
      fi
      if [ "$SEL_NODE" -eq 1 ]; then
        install_apt_package node nodejs "Node.js"
        install_apt_package npm npm "npm"
      fi
      ;;
    dnf|yum)
      [ "$SEL_GIT" -eq 1 ] && install_rpm_package git git "Git"
      if [ "$SEL_PYTHON" -eq 1 ]; then
        install_rpm_package python3 python3 "Python"
        install_rpm_package pip3 python3-pip "pip"
      fi
      if [ "$SEL_NODE" -eq 1 ]; then
        install_rpm_package node nodejs "Node.js"
        install_rpm_package npm npm "npm"
      fi
      ;;
    *)
      fail "No supported Linux package manager found. Expected apt, dnf, or yum."
      ;;
  esac
}

ensure_python_minimum() {
  [ "$SEL_PYTHON" -eq 1 ] || return 0
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
  [ "$SEL_NODE" -eq 1 ] || return 0
  if command_exists node && command_exists npm; then
    ok "Node.js and npm available"
  else
    warn "Node.js/npm are not available after base install. AI CLI npm installs may fail."
  fi
}

install_ai_tools() {
  section "AI CLI Tools"
  if [ "$SEL_CLAUDE" -eq 0 ] && [ "$SEL_CC_MIRROR" -eq 0 ] && [ "$SEL_MINIMAX" -eq 0 ] && [ "$SEL_CODEX" -eq 0 ] && [ "$SEL_GEMINI" -eq 0 ]; then
    ok "No AI CLI tools selected"
    return 0
  fi

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

    case "$binary" in
      claude) [ "$SEL_CLAUDE" -eq 1 ] || continue ;;
      cc-mirror) [ "$SEL_CC_MIRROR" -eq 1 ] || continue ;;
      mmx) [ "$SEL_MINIMAX" -eq 1 ] || continue ;;
      codex) [ "$SEL_CODEX" -eq 1 ] || continue ;;
      gemini) [ "$SEL_GEMINI" -eq 1 ] || continue ;;
    esac

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

  if [ "$MIRROR_CLAUDE" -eq 1 ]; then
    install_cc_mirror_variant "Claude Code via cc-mirror" "mclaude" "mirror"
  fi
  if [ "$MIRROR_MINIMAX" -eq 1 ]; then
    install_cc_mirror_variant "Minimax via cc-mirror" "minimax" "minimax"
  fi
  if [ "$MIRROR_KIMI" -eq 1 ]; then
    install_cc_mirror_variant "Kimi via cc-mirror" "kimi" "kimi"
  fi
}

install_cc_mirror_variant() {
  label="$1"
  name="$2"
  provider="$3"
  cmd="npx cc-mirror quick --provider $provider --name $name --no-tweak"
  if run_shell "$cmd"; then
    [ "$DRY_RUN" -eq 1 ] && add_result "$label" "variant planned" "planned" || add_result "$label" "variant installed" "installed"
  else
    add_result "$label" "variant install failed" "failed"
  fi
}

configure_path() {
  section "PATH"
  if ! command_exists npm; then
    warn "npm unavailable; skipping npm global PATH configuration"
    return 0
  fi

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
  [ "$SEL_GIT" -eq 1 ] && verify_tool "Git" git "git --version"
  if [ "$SEL_PYTHON" -eq 1 ]; then
    verify_tool "Python" python3 "python3 --version"
    verify_tool "pip" pip3 "pip3 --version"
  fi
  if [ "$SEL_NODE" -eq 1 ]; then
    verify_tool "Node.js" node "node --version"
    verify_tool "npm" npm "npm --version"
  fi
  [ "$SEL_CLAUDE" -eq 1 ] && verify_tool "Claude Code" claude "claude --version"
  [ "$SEL_CC_MIRROR" -eq 1 ] && verify_tool "cc-mirror" cc-mirror "cc-mirror --help"
  [ "$SEL_MINIMAX" -eq 1 ] && verify_tool "Minimax" mmx "mmx --version"
  [ "$SEL_CODEX" -eq 1 ] && verify_tool "OpenAI Codex" codex "codex --version"
  [ "$SEL_GEMINI" -eq 1 ] && verify_tool "Gemini CLI" gemini "gemini --version"
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
  configure_selection
  detect_platform
  interactive_custom_selection
  interactive_mirror_selection
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
