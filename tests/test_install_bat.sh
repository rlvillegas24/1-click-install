#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
INSTALL_BAT="$ROOT_DIR/install.bat"

assert_contains() {
  local output="$1"
  local expected="$2"
  if [[ "$output" != *"$expected"* ]]; then
    printf 'Expected install.bat to contain: %s\n' "$expected" >&2
    exit 1
  fi
}

content="$(tr -d '\r' < "$INSTALL_BAT")"

assert_contains "$content" 'Set-ExecutionPolicy RemoteSigned'
assert_contains "$content" '-ExecutionPolicy Bypass -File "%SCRIPT%"'
assert_contains "$content" 'https://raw.githubusercontent.com/lmmagbuhos/1-click-install/main/install.ps1'

if [[ "$content" == *'Start-Process -FilePath' && "$content" == *'-Verb RunAs'* ]]; then
  printf 'Expected install.bat not to elevate the full installer before npm environment setup\n' >&2
  exit 1
fi

policy_line="$(printf '%s\n' "$content" | grep -n 'Set-ExecutionPolicy RemoteSigned' | head -n1 | cut -d: -f1)"
run_line="$(printf '%s\n' "$content" | grep -n -- '-ExecutionPolicy Bypass -File "%SCRIPT%"' | head -n1 | cut -d: -f1)"

if [[ -z "$policy_line" || -z "$run_line" || "$policy_line" -ge "$run_line" ]]; then
  printf 'Expected RemoteSigned policy to be configured before install.ps1 runs\n' >&2
  exit 1
fi

printf 'install.bat execution policy tests passed\n'
