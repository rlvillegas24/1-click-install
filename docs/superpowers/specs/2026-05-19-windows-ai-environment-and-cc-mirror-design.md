# Windows AI Environment and cc-mirror Design

## Objective

Update the Windows PowerShell installer so it installs the real AI CLI binaries into the user's environment while also offering supported cc-mirror Claude Code variants as additional commands. Codex must not be treated as a cc-mirror variant.

## Scope

This change is focused on `install.ps1` and Windows behavior. Documentation should be updated where it describes Windows AI installs, mirror mode, or supported cc-mirror variants. Bash behavior may be left unchanged unless a small documentation or test alignment change is needed.

## Environment Policy

The installer should install and verify these real CLI binaries directly through npm:

- Claude Code: `npm install -g @anthropic-ai/claude-code`, command `claude`
- Minimax: `npm install -g mmx-cli`, command `mmx`
- OpenAI Codex: `npm install -g @openai/codex`, command `codex`
- Gemini CLI: `npm install -g @google/gemini-cli`, command `gemini`
- cc-mirror: `npm install -g cc-mirror`, command `cc-mirror`

The installer should refresh the current PowerShell session `PATH` after winget installs and npm installs so newly installed commands can be detected in the same run. It should continue to show missing commands clearly when a terminal restart is required.

## cc-mirror Variant Policy

cc-mirror should be presented as a Claude Code variant manager, not as a replacement installer for every AI CLI. The Windows TUI should use a separate "CC-MIRROR VARIANTS" selector for supported variants.

Supported variants:

- `mclaude`: `npx cc-mirror quick --provider mirror --name mclaude`
- `minimax`: `npx cc-mirror quick --provider minimax --name minimax`
- `kimi`: `npx cc-mirror quick --provider kimi --name kimi`

Codex is direct-only. It must be removed from cc-mirror routing state, mirror menus, mirror install commands, mirror verification, and environment output.

Selecting any cc-mirror variant should automatically select Node.js/npm and cc-mirror because both are required to create the variant.

## TUI Behavior

The main Windows selection screen should select installable software:

- Base tools: Git, Python, Node.js
- Dev tools: VS Code, Windows Terminal, 7-Zip
- AI CLI tools: Claude Code, cc-mirror, Minimax, OpenAI Codex, Gemini CLI

A separate cc-mirror variant screen should select variant commands:

- `mclaude`
- `minimax`
- `kimi`

The plan, summary, and environment sections should distinguish direct AI CLIs from cc-mirror variants. Example:

- `OpenAI Codex` appears under direct AI CLI tools.
- `kimi -> cc-mirror (provider: kimi)` appears under cc-mirror variants.

## Install Flow

Windows native install flow:

1. Configure default selections.
2. Let the user change real tool selections in Custom mode.
3. Let the user choose supported cc-mirror variants in Custom or Mirror mode where interactive.
4. Install Windows prerequisites when needed.
5. Install selected base and dev tools through winget.
6. Refresh session `PATH`.
7. Install selected npm AI CLI packages.
8. Refresh session `PATH` again.
9. Create selected cc-mirror variants.
10. Verify direct binaries and selected variants.
11. Print summary and environment panels.

Mirror mode should install Node.js/npm, cc-mirror, the direct Codex CLI, and supported cc-mirror variants. It should not attempt to create a Codex cc-mirror variant.

## Verification

Direct CLI verification should use existing commands:

- `claude --version`
- `mmx --version`
- `codex --version`
- `gemini --version`
- `cc-mirror --help`

Variant verification should not reuse direct binary checks. It should verify that cc-mirror is available and then inspect the cc-mirror variant list or run a non-destructive cc-mirror health command when available. Dry-run mode should report variant creation as planned.

## Error Handling

If npm is unavailable, skip npm AI CLI installs and cc-mirror variant creation with one clear warning.

If a direct AI CLI install fails, continue with the remaining AI tools and report the failed package in the summary.

If a cc-mirror variant fails to create, continue with the remaining variants and report the failed variant separately from the direct CLI tool.

## Documentation

Update README behavior notes to say:

- Real AI CLIs are installed as real commands.
- cc-mirror variants are additional supported Claude Code variant commands.
- Supported cc-mirror variants are `mclaude`, `minimax`, and `kimi`.
- Codex is installed directly and is not configured through cc-mirror.

## Acceptance Criteria

- Windows `install.ps1 -Mode Quick -DryRun` shows direct AI CLI installs and supported cc-mirror variants, with no Codex cc-mirror command.
- Windows `install.ps1 -Mode Mirror -DryRun` shows `mclaude`, `minimax`, and `kimi` cc-mirror variant commands, with no Codex cc-mirror command.
- Windows `install.ps1 -Mirror claude,minimax,kimi -DryRun` selects cc-mirror and Node.js/npm automatically.
- Windows direct AI install code still installs `@openai/codex`.
- The Windows environment summary separates direct AI CLIs from cc-mirror variants.
- README documents supported variants and Codex direct-only behavior.
