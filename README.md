# 1-Click Developer CLI Installer

A polished one-command installer for the core developer environment and AI CLI tools.

## One-Line Install

macOS, Linux, and WSL:

```bash
curl -fsSL https://raw.githubusercontent.com/rlvillegas24/1-click-install/main/install.sh | bash -s -- --yes
```

macOS, Linux, and WSL preview:

```bash
curl -fsSL https://raw.githubusercontent.com/rlvillegas24/1-click-install/main/install.sh | bash -s -- --dry-run
```

Windows PowerShell:

```powershell
Set-ExecutionPolicy RemoteSigned -Scope CurrentUser -Force
iwr -useb https://raw.githubusercontent.com/rlvillegas24/1-click-install/main/install.ps1 | iex
```

Windows PowerShell with WSL handoff:

```powershell
Set-ExecutionPolicy RemoteSigned -Scope CurrentUser -Force
$script = iwr -useb https://raw.githubusercontent.com/rlvillegas24/1-click-install/main/install.ps1; & ([scriptblock]::Create($script)) -Target WSL
```

Source repository: https://github.com/rlvillegas24/1-click-install

## What It Installs

Base tools:

- Git
- Python 3.10+ and pip
- Node.js LTS and npm

AI CLI tools:

- Claude Code from `@anthropic-ai/claude-code`
- cc-mirror from `cc-mirror`
- Minimax from `mmx-cli`
- OpenAI Codex from `@openai/codex`
- Gemini CLI from `@google/gemini-cli`

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
./install.sh --mode quick
./install.sh --mode custom
./install.sh --mode mirror
./install.sh --only git,python,node,claude,codex
./install.sh --skip gemini,minimax
./install.sh --mirror claude,minimax,codex
```

PowerShell:

```powershell
.\install.ps1 -Help
.\install.ps1 -DryRun
.\install.ps1 -Yes
.\install.ps1 -NoColor
.\install.ps1 -Mode Quick
.\install.ps1 -Mode Custom
.\install.ps1 -Mode Mirror
.\install.ps1 -Target WSL
.\install.ps1 -Only git,python,node,claude,codex
.\install.ps1 -Skip gemini,minimax
.\install.ps1 -Mirror claude,minimax,kimi
```

## Behavior

The installer is idempotent. Existing tools are skipped when detected. Missing tools are installed through the platform package manager. The installer prints a plan before making changes, shows progress for each step, updates PATH for the current session where possible, and prints a final verification summary.

Default mode is interactive. Use `--yes` or `-Yes` when running in automation or from a non-interactive shell.

Install modes:

- `quick`: installs the recommended default set.
- `custom`: lets the user choose Git, Python, Node, Claude, cc-mirror, Minimax, Codex, and Gemini separately.
- `mirror`: sets up Node/npm, cc-mirror, and cc-mirror variants where supported.

Git, Python, and Node are separate selectable tools. Python includes pip, and Node includes npm.

By default, both installers select `cc-mirror` and the `minimax` cc-mirror variant only for AI tooling. Direct `claude`, `mmx`, `codex`, and `gemini` installs are available in Custom mode or through `--only` / `-Only`, but they are not selected by default.

VS Code and Windows Terminal are Windows-only options in the PowerShell Custom selector; they are not selected by default and are not part of the Linux/macOS installer.

The Windows installer supports these cc-mirror variants:

- `mclaude` using provider `mirror`
- `minimax` using provider `minimax`
- `kimi` using provider `kimi`

Codex is direct-only on Windows. It is installed from `@openai/codex` and is not configured through cc-mirror.

AI CLI package names are centralized near the top of each script. If a public package changes, update the relevant entry without touching the platform detection logic.

## Troubleshooting

### macOS Homebrew

The macOS installer uses Homebrew. If Homebrew is missing, the one-line `--yes` command installs Homebrew noninteractively, refreshes the current session with `brew shellenv`, then installs the selected tools with `brew`.

### Linux permissions

Linux package installs may require `sudo`. Run from a user account with sudo permissions.

### Windows execution policy

Before running the Windows installer, allow locally created scripts for the current user:

```powershell
Set-ExecutionPolicy RemoteSigned -Scope CurrentUser -Force
```

If PowerShell still blocks a local `install.ps1`, run it with a process-scoped bypass:

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
.\install.ps1 -Target WSL
```

### PATH

Open a new terminal after installation if a command is still not found. The installer updates the current session where possible and persists common PATH entries for future sessions, including npm global binaries and the cc-mirror variant command directory (`~/.cc-mirror/bin` or `%USERPROFILE%\.cc-mirror\bin`).

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
codex --version
gemini --version
```
