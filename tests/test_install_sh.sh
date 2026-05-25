#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

run_installer() {
  "$ROOT_DIR/install.sh" --dry-run --no-color "$@"
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

quick_output="$(run_installer --mode quick)"
assert_contains "$quick_output" "Mode:            quick"
assert_contains "$quick_output" 'Added cc-mirror bin to current session PATH'
assert_contains "$quick_output" 'npm install -g cc-mirror'
assert_contains "$quick_output" 'npx cc-mirror quick --provider minimax --name minimax --no-tweak'
assert_not_contains "$quick_output" 'npm install -g @anthropic-ai/claude-code'
assert_not_contains "$quick_output" 'npm install -g mmx-cli'
assert_not_contains "$quick_output" 'npm install -g @openai/codex'
assert_not_contains "$quick_output" 'npm install -g @google/gemini-cli'
assert_not_contains "$quick_output" 'npx cc-mirror quick --provider mirror --name mclaude --no-tweak'
assert_not_contains "$quick_output" 'npx cc-mirror quick --provider kimi --name kimi --no-tweak'
assert_not_contains "$quick_output" 'npx cc-mirror quick --provider openai'
assert_not_contains "$quick_output" '--name codex'

only_output="$(run_installer --mode custom --only git,node)"
assert_contains "$only_output" "Mode:            custom"
assert_contains "$only_output" "Git"
assert_contains "$only_output" "Node.js"
assert_not_contains "$only_output" 'npm install -g @anthropic-ai/claude-code'
assert_not_contains "$only_output" 'npm install -g @openai/codex'

mirror_output="$(run_installer --mode mirror)"
assert_contains "$mirror_output" "Mode:            mirror"
assert_contains "$mirror_output" 'npm install -g cc-mirror'
assert_contains "$mirror_output" 'npx cc-mirror quick --provider minimax --name minimax --no-tweak'
assert_not_contains "$mirror_output" 'npm install -g @anthropic-ai/claude-code'
assert_not_contains "$mirror_output" 'npm install -g mmx-cli'
assert_not_contains "$mirror_output" 'npm install -g @openai/codex'
assert_not_contains "$mirror_output" 'npm install -g @google/gemini-cli'
assert_not_contains "$mirror_output" 'npx cc-mirror quick --provider mirror --name mclaude --no-tweak'
assert_not_contains "$mirror_output" 'npx cc-mirror quick --provider kimi --name kimi --no-tweak'
assert_not_contains "$mirror_output" 'npx cc-mirror quick --provider openai'
assert_not_contains "$mirror_output" '--name codex'

mirror_flag_output="$(run_installer --mode custom --mirror claude,minimax,kimi)"
assert_contains "$mirror_flag_output" 'npm install -g cc-mirror'
assert_contains "$mirror_flag_output" 'npx cc-mirror quick --provider mirror --name mclaude --no-tweak'
assert_contains "$mirror_flag_output" 'npx cc-mirror quick --provider minimax --name minimax --no-tweak'
assert_contains "$mirror_flag_output" 'npx cc-mirror quick --provider kimi --name kimi --no-tweak'
assert_not_contains "$mirror_flag_output" 'npx cc-mirror quick --provider openai'

skip_output="$(run_installer --mode quick --skip claude,minimax,codex)"
assert_not_contains "$skip_output" 'npm install -g @anthropic-ai/claude-code'
assert_not_contains "$skip_output" 'npm install -g mmx-cli'
assert_not_contains "$skip_output" 'npm install -g @openai/codex'

printf 'install.sh selection tests passed\n'
