#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
INSTALL_PS1="$ROOT_DIR/install.ps1"

ps1_content="$(tr -d '\r' < "$INSTALL_PS1")"

if [[ "$ps1_content" != *'Set-ExecutionPolicy RemoteSigned -Scope CurrentUser -Force'* ]]; then
  printf 'Expected install.ps1 to configure RemoteSigned execution policy\n' >&2
  exit 1
fi

if [[ "$ps1_content" != *'npm config get prefix'* || "$ps1_content" != *'SetEnvironmentVariable("Path", $userPath, "User")'* ]]; then
  printf 'Expected install.ps1 to persist npm global prefix in user PATH for cc-mirror commands\n' >&2
  exit 1
fi

policy_line="$(printf '%s\n' "$ps1_content" | grep -n 'Set-ExecutionPolicy RemoteSigned -Scope CurrentUser -Force' | head -n1 | cut -d: -f1)"
entry_line="$(printf '%s\n' "$ps1_content" | grep -n '^# ENTRYPOINT' | head -n1 | cut -d: -f1)"

if [[ -z "$policy_line" || -z "$entry_line" || "$policy_line" -ge "$entry_line" ]]; then
  printf 'Expected RemoteSigned policy setup to be defined before install.ps1 entrypoint\n' >&2
  exit 1
fi

PS_BIN="${PS_BIN:-}"
if [[ -z "$PS_BIN" ]]; then
  if command -v pwsh >/dev/null 2>&1; then
    PS_BIN="pwsh"
  elif command -v powershell >/dev/null 2>&1; then
    PS_BIN="powershell"
  else
    printf 'PowerShell not found; skipping install.ps1 dry-run tests\n'
    exit 0
  fi
fi

run_installer() {
  "$PS_BIN" -NoProfile -ExecutionPolicy Bypass -File "$ROOT_DIR/install.ps1" -DryRun -NoColor "$@"
}

assert_contains() {
  local output="$1"
  local expected="$2"
  if [[ "$output" != *"$expected"* ]]; then
    printf 'Expected output to contain: %s\n' "$expected" >&2
    exit 1
  fi
}

assert_not_contains() {
  local output="$1"
  local unexpected="$2"
  if [[ "$output" == *"$unexpected"* ]]; then
    printf 'Expected output not to contain: %s\n' "$unexpected" >&2
    exit 1
  fi
}

quick_output="$(run_installer -Mode Quick)"
assert_contains "$quick_output" "npm install -g @openai/codex"
assert_contains "$quick_output" "npm install -g @google/gemini-cli"
assert_contains "$quick_output" "npm install -g cc-mirror"
assert_contains "$quick_output" "npx cc-mirror quick --provider minimax --name minimax --no-tweak"
assert_not_contains "$quick_output" "npm install -g @anthropic-ai/claude-code"
assert_not_contains "$quick_output" "npm install -g mmx-cli"
assert_not_contains "$quick_output" "winget install --id Microsoft.VisualStudioCode"
assert_not_contains "$quick_output" "winget install --id Microsoft.WindowsTerminal"
assert_not_contains "$quick_output" "npx cc-mirror quick --provider mirror --name mclaude --no-tweak"
assert_not_contains "$quick_output" "npx cc-mirror quick --provider kimi --name kimi --no-tweak"
assert_not_contains "$quick_output" "npx cc-mirror quick --provider openai"
assert_not_contains "$quick_output" "--name codex"

mirror_output="$(run_installer -Mode Mirror)"
assert_contains "$mirror_output" "npm install -g @openai/codex"
assert_contains "$mirror_output" "npx cc-mirror quick --provider minimax --name minimax --no-tweak"
assert_not_contains "$mirror_output" "npm install -g @anthropic-ai/claude-code"
assert_not_contains "$mirror_output" "npm install -g mmx-cli"
assert_not_contains "$mirror_output" "npx cc-mirror quick --provider mirror --name mclaude --no-tweak"
assert_not_contains "$mirror_output" "npx cc-mirror quick --provider kimi --name kimi --no-tweak"
assert_not_contains "$mirror_output" "npx cc-mirror quick --provider openai"
assert_not_contains "$mirror_output" "--name codex"

mirror_flag_output="$(run_installer -Mode Custom -Mirror claude,minimax,kimi)"
assert_contains "$mirror_flag_output" "Node.js LTS"
assert_contains "$mirror_flag_output" "cc-mirror"
assert_contains "$mirror_flag_output" "npx cc-mirror quick --provider mirror --name mclaude --no-tweak"
assert_contains "$mirror_flag_output" "npx cc-mirror quick --provider minimax --name minimax --no-tweak"
assert_contains "$mirror_flag_output" "npx cc-mirror quick --provider kimi --name kimi --no-tweak"
assert_not_contains "$mirror_flag_output" "npx cc-mirror quick --provider openai"

printf 'install.ps1 AI environment tests passed\n'
