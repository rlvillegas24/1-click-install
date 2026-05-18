# Unified Developer CLI Installer Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build polished one-command installer scripts for macOS/Linux/WSL and native Windows, plus README documentation.

**Architecture:** `install.sh` owns Unix-like platform detection, rendering, install orchestration, PATH handling, and verification. `install.ps1` owns native Windows install orchestration and WSL handoff. Both scripts keep AI CLI install metadata centralized so tool package names and verification commands can be corrected without rewriting platform logic.

**Tech Stack:** Bash 3.2-compatible shell, PowerShell 5.1+/7+, OS package managers (`brew`, `apt`, `dnf`, `yum`, `winget`), npm/pip where available, Markdown documentation.

---

## File Structure

- Create `install.sh`: Bash installer for macOS, Linux, and WSL.
- Create `install.ps1`: PowerShell installer for native Windows and WSL handoff.
- Create `README.md`: user-facing install commands, flags, supported platforms, and troubleshooting.
- Keep `docs/superpowers/specs/2026-05-18-unified-developer-cli-installer-design.md`: approved design reference.

## Task 1: Bash Installer

**Files:**
- Create: `install.sh`

- [ ] **Step 1: Create `install.sh` with CLI parsing, rendering helpers, platform detection, install orchestration, and verification**

Write this complete file:

```bash
#!/usr/bin/env bash
set -uo pipefail

APP_NAME="Developer CLI Tools Installer"
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
  printf '%s\n' "${BOLD}${BLUE}╔══════════════════════════════════════════════╗${RESET}"
  printf '%s\n' "${BOLD}${BLUE}║      Developer CLI Tools Installer          ║${RESET}"
  printf '%s\n' "${BOLD}${BLUE}╚══════════════════════════════════════════════╝${RESET}"
  printf '%s\n' "${DIM}Version ${APP_VERSION}${RESET}"
  printf '\n'
}

section() {
  printf '\n%s\n' "${BOLD}${BLUE}▶ $1${RESET}"
}

ok() {
  printf '%s\n' "${GREEN}✓${RESET} $1"
}

warn() {
  printf '%s\n' "${YELLOW}!${RESET} $1"
}

err() {
  printf '%s\n' "${RED}✗${RESET} $1" >&2
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

install_base_macos() {
  install_homebrew
  run_cmd brew update
  install_brew_package git git "Git"
  install_brew_package python3 python "Python"
  install_brew_package node node "Node.js"
}

install_brew_package() {
  binary="$1"
  package="$2"
  label="$3"
  if command_exists "$binary"; then
    ok "$label already installed"
    add_result "$label" "$("$binary" --version 2>/dev/null | head -n 1)" "skipped"
  else
    run_cmd brew install "$package" && add_result "$label" "installed" "installed" || add_result "$label" "install failed" "failed"
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
    dnf)
      install_rpm_package git git "Git"
      install_rpm_package python3 python3 "Python"
      install_rpm_package pip3 python3-pip "pip"
      install_rpm_package node nodejs "Node.js"
      install_rpm_package npm npm "npm"
      ;;
    yum)
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

install_apt_package() {
  binary="$1"
  package="$2"
  label="$3"
  if command_exists "$binary"; then
    ok "$label already installed"
    add_result "$label" "$("$binary" --version 2>/dev/null | head -n 1)" "skipped"
  else
    run_cmd $SUDO_CMD apt-get install -y "$package" && add_result "$label" "installed" "installed" || add_result "$label" "install failed" "failed"
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
    run_cmd $SUDO_CMD "$PKG_MANAGER" install -y "$package" && add_result "$label" "installed" "installed" || add_result "$label" "install failed" "failed"
  fi
}

ensure_python_minimum() {
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
      add_result "$label" "$($verify_cmd 2>/dev/null | head -n 1 || printf detected)" "skipped"
    elif [ "$manager" = "npm" ]; then
      run_cmd npm install -g "$package" && add_result "$label" "installed" "installed" || add_result "$label" "install failed for package $package" "failed"
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
```

- [ ] **Step 2: Make the script executable**

Run:

```bash
chmod +x install.sh
```

Expected: no output.

- [ ] **Step 3: Run Bash syntax verification**

Run:

```bash
bash -n install.sh
```

Expected: no output and exit code `0`.

- [ ] **Step 4: Run Bash dry-run verification**

Run:

```bash
./install.sh --dry-run --no-color
```

Expected: the script prints the header, install plan, package-manager commands for the current platform, verification section, and summary without installing packages.

## Task 2: PowerShell Installer

**Files:**
- Create: `install.ps1`

- [ ] **Step 1: Create `install.ps1` with native Windows support and WSL handoff**

Write this complete file:

```powershell
[CmdletBinding()]
param(
    [Alias("y")]
    [switch]$Yes,
    [switch]$DryRun,
    [switch]$NoColor,
    [ValidateSet("Native", "WSL")]
    [string]$Mode = "Native",
    [switch]$Help
)

$AppName = "Developer CLI Tools Installer"
$AppVersion = "0.1.0"
$Results = New-Object System.Collections.Generic.List[object]

$AiTools = @(
    @{ Name = "Claude Code"; Binary = "claude"; Manager = "npm"; Package = "@anthropic-ai/claude-code"; Verify = "claude --version" },
    @{ Name = "cc-mirror"; Binary = "cc-mirror"; Manager = "npm"; Package = "cc-mirror"; Verify = "cc-mirror --help" },
    @{ Name = "Minimax"; Binary = "mmx"; Manager = "npm"; Package = "mmx-cli"; Verify = "mmx --version" },
    @{ Name = "Gemini CLI"; Binary = "gemini"; Manager = "npm"; Package = "@google/gemini-cli"; Verify = "gemini --version" }
)

function Show-Usage {
    @"
Developer CLI Tools Installer

Usage:
  powershell -ExecutionPolicy Bypass -File .\install.ps1 [options]

Options:
  -Yes              Run without confirmation prompts
  -DryRun           Print planned actions without installing
  -NoColor          Disable colored output
  -Mode Native      Install tools on native Windows
  -Mode WSL         Hand off to install.sh inside WSL
  -Help             Show this help message
"@
}

function Use-Color {
    return -not $NoColor -and $Host.UI.RawUI -and $env:TERM -ne "dumb"
}

function Write-LineColor([string]$Text, [ConsoleColor]$Color) {
    if (Use-Color) {
        Write-Host $Text -ForegroundColor $Color
    } else {
        Write-Host $Text
    }
}

function Show-Header {
    Write-LineColor "╔══════════════════════════════════════════════╗" Cyan
    Write-LineColor "║      Developer CLI Tools Installer          ║" Cyan
    Write-LineColor "╚══════════════════════════════════════════════╝" Cyan
    Write-Host "Version $AppVersion"
    Write-Host ""
}

function Section([string]$Name) {
    Write-Host ""
    Write-LineColor "▶ $Name" Cyan
}

function Ok([string]$Message) {
    Write-LineColor "✓ $Message" Green
}

function Warn([string]$Message) {
    Write-LineColor "! $Message" Yellow
}

function Fail([string]$Message) {
    Write-LineColor "✗ $Message" Red
    exit 1
}

function Add-Result([string]$Name, [string]$Value, [string]$Status) {
    $Results.Add([pscustomobject]@{ Name = $Name; Value = $Value; Status = $Status }) | Out-Null
}

function Test-Command([string]$Name) {
    return $null -ne (Get-Command $Name -ErrorAction SilentlyContinue)
}

function Invoke-Step([string]$CommandLine) {
    Write-Host "`$ $CommandLine"
    if ($DryRun) {
        return $true
    }

    $process = Start-Process powershell -ArgumentList @("-NoProfile", "-ExecutionPolicy", "Bypass", "-Command", $CommandLine) -Wait -PassThru
    return $process.ExitCode -eq 0
}

function Confirm-Plan {
    if ($Yes -or $DryRun) {
        return
    }

    $answer = Read-Host "Continue with installation? [y/N]"
    if ($answer -notin @("y", "Y", "yes", "YES")) {
        Fail "Installation cancelled."
    }
}

function Show-Plan {
    Section "Install Plan"
    Write-Host "Platform:        Windows"
    Write-Host "Mode:            $Mode"
    Write-Host "Package manager: winget"
    Write-Host "Run mode:        $(if ($DryRun) { "dry-run" } else { "install" })"
    Write-Host ""
    Write-Host "Tools:"
    Write-Host "  - Git"
    Write-Host "  - Python 3.10+ and pip"
    Write-Host "  - Node.js LTS and npm"
    Write-Host "  - Claude Code"
    Write-Host "  - cc-mirror"
    Write-Host "  - Minimax"
    Write-Host "  - Gemini CLI"
}

function Invoke-WSLInstall {
    Section "WSL Handoff"
    if (-not (Test-Command "wsl.exe")) {
        Fail "wsl.exe was not found. Install WSL first with: wsl --install"
    }

    $scriptUrl = "https://raw.githubusercontent.com/your-repo/bootstrap/main/install.sh"
    $flags = ""
    if ($Yes) { $flags += " --yes" }
    if ($DryRun) { $flags += " --dry-run" }
    if ($NoColor) { $flags += " --no-color" }
    $command = "curl -fsSL $scriptUrl | bash -s --$flags"
    Write-Host "`$ wsl bash -lc '$command'"
    if (-not $DryRun) {
        wsl bash -lc $command
    }
}

function Install-WingetPackage([string]$Label, [string]$Binary, [string]$PackageId) {
    if (Test-Command $Binary) {
        Ok "$Label already installed"
        $version = try { (& $Binary --version 2>$null | Select-Object -First 1) } catch { "detected" }
        Add-Result $Label $version "skipped"
        return
    }

    $cmd = "winget install --id $PackageId --exact --accept-source-agreements --accept-package-agreements"
    if (Invoke-Step $cmd) {
        Add-Result $Label "installed" "installed"
    } else {
        Add-Result $Label "install failed" "failed"
    }
}

function Install-BaseDependencies {
    Section "Base Dependencies"
    if (-not (Test-Command "winget")) {
        Fail "winget is required for native Windows installation. Install App Installer from Microsoft Store."
    }

    Install-WingetPackage "Git" "git" "Git.Git"
    Install-WingetPackage "Python" "python" "Python.Python.3.12"
    Install-WingetPackage "Node.js" "node" "OpenJS.NodeJS.LTS"
}

function Update-CurrentPath {
    Section "PATH"
    $machine = [Environment]::GetEnvironmentVariable("Path", "Machine")
    $user = [Environment]::GetEnvironmentVariable("Path", "User")
    $env:Path = "$machine;$user"
    Ok "Refreshed current PowerShell session PATH"
}

function Install-AiTools {
    Section "AI CLI Tools"
    if (-not (Test-Command "npm")) {
        Warn "Skipping AI CLI npm installs because npm is unavailable"
        Add-Result "AI CLI tools" "npm unavailable" "skipped"
        return
    }

    foreach ($tool in $AiTools) {
        if (Test-Command $tool.Binary) {
            Ok "$($tool.Name) already installed"
            $value = try { Invoke-Expression $tool.Verify 2>$null | Select-Object -First 1 } catch { "detected" }
            Add-Result $tool.Name $value "skipped"
            continue
        }

        if ($tool.Manager -eq "npm") {
            $cmd = "npm install -g $($tool.Package)"
            if (Invoke-Step $cmd) {
                Add-Result $tool.Name "installed" "installed"
            } else {
                Add-Result $tool.Name "install failed for package $($tool.Package)" "failed"
            }
        } else {
            Add-Result $tool.Name "unsupported manager $($tool.Manager)" "skipped"
        }
    }
}

function Verify-Tool([string]$Label, [string]$Binary, [string]$CommandLine) {
    if (Test-Command $Binary) {
        $value = try { Invoke-Expression $CommandLine 2>$null | Select-Object -First 1 } catch { "detected" }
        if ([string]::IsNullOrWhiteSpace($value)) { $value = "detected" }
        Add-Result $Label $value "verified"
    } else {
        Add-Result $Label "not found" "missing"
    }
}

function Verify-All {
    Section "Verification"
    Verify-Tool "Git" "git" "git --version"
    Verify-Tool "Python" "python" "python --version"
    Verify-Tool "pip" "pip" "pip --version"
    Verify-Tool "Node.js" "node" "node --version"
    Verify-Tool "npm" "npm" "npm --version"
    Verify-Tool "Claude Code" "claude" "claude --version"
    Verify-Tool "cc-mirror" "cc-mirror" "cc-mirror --help"
    Verify-Tool "Minimax" "mmx" "mmx --version"
    Verify-Tool "Gemini CLI" "gemini" "gemini --version"
}

function Show-Summary {
    Section "Summary"
    $Results | Format-Table -AutoSize
}

if ($Help) {
    Show-Usage
    exit 0
}

Show-Header
Show-Plan
Confirm-Plan

if ($Mode -eq "WSL") {
    Invoke-WSLInstall
    exit 0
}

Install-BaseDependencies
Update-CurrentPath
Install-AiTools
Verify-All
Show-Summary
```

- [ ] **Step 2: Run PowerShell parser verification when PowerShell is available**

Run:

```bash
pwsh -NoProfile -Command '$null = [System.Management.Automation.Language.Parser]::ParseFile("./install.ps1", [ref]$null, [ref]$null)'
```

Expected: no parser errors.

- [ ] **Step 3: Run PowerShell dry-run verification when PowerShell is available**

Run:

```bash
pwsh -NoProfile -ExecutionPolicy Bypass -File ./install.ps1 -DryRun -NoColor
```

Expected: the script prints the header, install plan, winget commands, verification section, and summary without installing packages.

## Task 3: README

**Files:**
- Create: `README.md`

- [ ] **Step 1: Create user-facing documentation**

Write this complete file:

```markdown
# 1-Click Developer CLI Installer

A polished one-command installer for the core developer environment and AI CLI tools.

## One-Line Install

macOS, Linux, and WSL:

```bash
curl -fsSL https://raw.githubusercontent.com/your-repo/bootstrap/main/install.sh | bash
```

Windows PowerShell:

```powershell
iwr -useb https://raw.githubusercontent.com/your-repo/bootstrap/main/install.ps1 | iex
```

Windows with WSL handoff:

```powershell
iwr -useb https://raw.githubusercontent.com/your-repo/bootstrap/main/install.ps1 | iex -Mode WSL
```

Replace `your-repo/bootstrap` with the final GitHub repository path before publishing.

## What It Installs

Base tools:

- Git
- Python 3.10+ and pip
- Node.js LTS and npm

AI CLI tools:

- Claude Code
- cc-mirror
- Minimax
- Gemini CLI

## Supported Platforms

- macOS on Intel and Apple Silicon
- Ubuntu/Debian Linux
- RHEL-based Linux with `dnf` or `yum`
- Windows native PowerShell with `winget`
- Windows through WSL

## Options

Bash:

```bash
./install.sh --help
./install.sh --dry-run
./install.sh --yes
./install.sh --no-color
```

PowerShell:

```powershell
.\install.ps1 -Help
.\install.ps1 -DryRun
.\install.ps1 -Yes
.\install.ps1 -NoColor
.\install.ps1 -Mode WSL
```

## Behavior

The installer is idempotent. Existing tools are skipped when detected. Missing tools are installed through the platform package manager. The installer prints a plan before making changes, shows progress for each step, updates PATH for the current session where possible, and prints a final verification summary.

AI CLI package names are centralized inside each script. If a public package changes, update the relevant entry near the top of the script.

## Troubleshooting

### macOS Homebrew

The macOS installer uses Homebrew. If Homebrew is missing, the installer asks before installing it.

### Linux permissions

Linux package installs may require `sudo`. Run from a user account with sudo permissions.

### Windows execution policy

If PowerShell blocks script execution, run:

```powershell
powershell -ExecutionPolicy Bypass -File .\install.ps1
```

### Windows package manager

Native Windows installation requires `winget`. If `winget` is missing, install App Installer from Microsoft Store.

### WSL

To install WSL:

```powershell
wsl --install
```

Then rerun the installer with:

```powershell
.\install.ps1 -Mode WSL
```

### PATH

Open a new terminal after installation if a command is still not found. The installer updates the current session where possible and persists common PATH entries for future sessions.

## Verification

The installer checks:

```bash
git --version
python3 --version
pip3 --version
node --version
npm --version
claude --version
cc-mirror --help
mmx --version
gemini --version
```
```

## Task 4: Final Verification

**Files:**
- Verify: `install.sh`
- Verify: `install.ps1`
- Verify: `README.md`

- [ ] **Step 1: Run file listing**

Run:

```bash
find . -maxdepth 3 -type f | sort
```

Expected output includes:

```text
./README.md
./docs/superpowers/plans/2026-05-18-unified-developer-cli-installer.md
./docs/superpowers/specs/2026-05-18-unified-developer-cli-installer-design.md
./install.ps1
./install.sh
```

- [ ] **Step 2: Run Bash checks**

Run:

```bash
bash -n install.sh
./install.sh --dry-run --no-color
```

Expected: syntax check passes and dry-run prints the install plan without changing packages.

- [ ] **Step 3: Run PowerShell checks if `pwsh` is installed**

Run:

```bash
if command -v pwsh >/dev/null 2>&1; then
  pwsh -NoProfile -Command '$null = [System.Management.Automation.Language.Parser]::ParseFile("./install.ps1", [ref]$null, [ref]$null)'
  pwsh -NoProfile -ExecutionPolicy Bypass -File ./install.ps1 -DryRun -NoColor
else
  printf 'pwsh not installed; skipping PowerShell runtime verification\n'
fi
```

Expected: parser check and dry-run pass when `pwsh` is available; otherwise the skip message is printed.

- [ ] **Step 4: Scan for unfinished markers**

Run:

```bash
rg -n "TB[D]|TO[D]O" .
```

Expected: no unfinished-marker results should appear. The string `your-repo/bootstrap` may remain in README one-liners and the WSL handoff URL until the final repository URL is known.

- [ ] **Step 5: Commit when the directory is a git repository**

Run:

```bash
git status --short
git add README.md install.sh install.ps1 docs/superpowers/specs/2026-05-18-unified-developer-cli-installer-design.md docs/superpowers/plans/2026-05-18-unified-developer-cli-installer.md
git commit -m "feat: add unified developer cli installer"
```

Expected: commit succeeds if this directory has been initialized as a git repository. In the current empty workspace, initialize git first only if the project owner wants this directory to become a repository.

## Self-Review

- Spec coverage: the plan covers `install.sh`, `install.ps1`, README documentation, idempotent install behavior, interactive CLI output, flags, PATH handling, and verification.
- Unfinished-marker scan: the only intentionally unresolved string is `your-repo/bootstrap`, which must remain configurable until the publishing repository is known.
- Scope check: the feature is small enough for one implementation plan because the deliverables are two scripts and one README.
