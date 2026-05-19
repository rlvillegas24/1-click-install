# Unified Developer CLI Installer Design

## Objective

Create a cross-platform, one-step installer for the core developer environment and AI CLI tools. The installer should reduce onboarding to a single command while remaining safe to rerun on existing machines.

## Target Platforms

- macOS on Intel and Apple Silicon
- Ubuntu/Debian Linux
- RHEL-based Linux
- Windows native PowerShell
- Windows through WSL

## User Experience

The installer should feel like a polished CLI application with a GUI-like command-line flow. It will use built-in Bash and PowerShell rendering helpers instead of external UI dependencies so it can run before any tools are installed.

Default mode is interactive. The one-line installers show a branded header, detected platform, installation plan, per-step progress, and a final summary table.

Supported flags:

- `--yes` / `-y`: skip confirmations for automation
- `--dry-run`: show the planned actions without installing
- `--no-color`: disable ANSI color output
- `--mode quick|custom|mirror`: choose the installer flow
- `--only`: install only a comma-separated tool list
- `--skip`: remove a comma-separated tool list from the plan
- `--mirror`: request cc-mirror setup for supported AI tools
- `--help`: print usage

The output should gracefully fall back to plain text when color is disabled, unsupported, or the script is running in a non-interactive environment.

Installer modes:

- Quick mode installs the recommended default set.
- Custom mode lets the user select Git, Python, Node, Claude, cc-mirror, Minimax, Codex, and Gemini separately.
- Mirror mode sets up Node/npm, cc-mirror, and cc-mirror variants where supported.

Git, Python, and Node are selectable independently. Python includes pip, and Node includes npm. Claude, Minimax, and Codex expose a mirror-source choice. cc-mirror currently supports Claude mirror variants and a Minimax provider variant; Codex via cc-mirror is reported as unsupported and falls back to the normal Codex installer when selected.

## Architecture

The project will include:

- `install.sh`: Bash installer for macOS, Linux, and WSL
- `install.ps1`: PowerShell installer for native Windows and WSL handoff
- `README.md`: one-line install commands, supported platforms, tools installed, flags, and troubleshooting

Both installers use the same phases:

1. Detect platform and package manager.
2. Run preflight checks for permissions, package manager availability, network access, and PATH locations.
3. Build and display an installation plan.
4. Confirm the plan unless `--yes` is passed.
5. Install or skip base dependencies.
6. Install or skip AI CLI tools.
7. Update PATH for the current session and persist it where appropriate.
8. Verify installed tools.
9. Print a final status table.

## Install Policy

The installer is idempotent. If a tool is already installed and satisfies the minimum requirement, it is skipped. Missing tools are installed. Tools that are present but too old are reported clearly; the first version does not auto-upgrade every existing tool unless the platform package manager performs an update as part of the install flow.

One failed AI CLI install must not block installation of base dependencies. Critical platform failures, such as no supported package manager and no fallback, stop the run with clear remediation.

## Platform Strategy

macOS:

- Use Homebrew.
- Install Homebrew if missing and the user confirms.
- Install or verify `git`, `python`, `pip`, `node`, and `npm`.

Ubuntu/Debian:

- Use `apt`.
- Install or verify `git`, `python3`, `python3-pip`, `nodejs`, and `npm`.

RHEL-based Linux:

- Use `dnf` when available, otherwise `yum`.
- Install or verify `git`, `python3`, `python3-pip`, `nodejs`, and `npm`.

Windows native:

- Use `winget`.
- Install or verify Git, Python 3, and Node.js LTS.
- Install AI CLIs through public package-manager commands where available.
- Update the current PowerShell session PATH and persist user PATH entries where needed.

Windows WSL:

- `install.ps1` detects WSL availability.
- If WSL is selected and available, it invokes the Bash installer inside WSL.
- If WSL is unavailable, it explains the required setup or offers native Windows installation.

## Tool Strategy

Base dependencies:

- Python 3.10 or newer and pip
- Node.js LTS and npm
- Git

AI CLI tools:

- Claude Code
- cc-mirror
- Minimax
- OpenAI Codex
- Gemini CLI

AI CLI install commands will be centralized in small helper functions or a simple tool table in each script. This keeps public package names and verification commands easy to adjust without changing platform detection and rendering logic.

When a public package-manager installation is known, use it. When an exact public package cannot be verified in the script itself, mark the tool as requiring manual source configuration and report it in the summary instead of failing the entire installer.

## PATH Handling

The installers should update PATH for the current session whenever possible.

Persistent PATH updates:

- Bash: append guarded blocks to the detected user shell profile, such as `.bashrc`, `.zshrc`, or `.profile`.
- PowerShell: update user-level PATH only when a required install location is missing.

All profile edits must be idempotent and clearly labeled.

## Verification

At the end of the run, verify:

- `git --version`
- `python3 --version` or `python --version`
- `pip --version` or `pip3 --version`
- `node --version`
- `npm --version`
- AI CLI version or help commands

The final table includes the tool name, detected version or status, and result.

## Documentation

`README.md` will include:

- macOS/Linux one-liner
- Windows PowerShell one-liner
- Supported platforms
- Installed tools
- Flags
- WSL guidance
- Troubleshooting for permissions, execution policy, PATH, and package-manager failures

## Acceptance Criteria

- `install.sh` exists and supports macOS, Ubuntu/Debian, RHEL-based Linux, and WSL.
- `install.ps1` exists and supports native Windows and WSL handoff.
- Both scripts are safe to run multiple times.
- Both scripts support `--yes`, `--dry-run`, `--no-color`, and `--help`.
- Both scripts show a polished interactive CLI flow by default.
- Both scripts verify base dependencies and AI CLI tools at the end.
- `README.md` documents the one-line install commands and troubleshooting.
