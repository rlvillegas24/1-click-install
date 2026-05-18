# 1-Click Developer CLI Installer

A polished one-command installer for the core developer environment and AI CLI tools.

## One-Line Install

macOS, Linux, and WSL:

```bash
curl -fsSL https://raw.githubusercontent.com/your-repo/bootstrap/main/install.sh | bash
```

macOS, Linux, and WSL non-interactive:

```bash
curl -fsSL https://raw.githubusercontent.com/your-repo/bootstrap/main/install.sh | bash -s -- --yes
```

Windows PowerShell:

```powershell
iwr -useb https://raw.githubusercontent.com/your-repo/bootstrap/main/install.ps1 | iex
```

Windows PowerShell with WSL handoff:

```powershell
$script = iwr -useb https://raw.githubusercontent.com/your-repo/bootstrap/main/install.ps1; & ([scriptblock]::Create($script)) -Mode WSL
```

Replace `your-repo/bootstrap` with the final GitHub repository path before publishing.

## What It Installs

Base tools:

- Git
- Python 3.10+ and pip
- Node.js LTS and npm

AI CLI tools:

- Claude Code from `@anthropic-ai/claude-code`
- cc-mirror from `cc-mirror`
- Minimax from `mmx-cli`
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

Default mode is interactive. Use `--yes` or `-Yes` when running in automation or from a non-interactive shell.

AI CLI package names are centralized near the top of each script. If a public package changes, update the relevant entry without touching the platform detection logic.

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
