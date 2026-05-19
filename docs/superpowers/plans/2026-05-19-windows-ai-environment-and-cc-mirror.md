# Windows AI Environment and cc-mirror Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Update the Windows installer so it installs real AI CLI binaries directly and creates only supported cc-mirror Claude Code variants: `mclaude`, `minimax`, and `kimi`.

**Architecture:** Keep `install.ps1` as the single Windows installer entrypoint, but split direct AI tool selection from cc-mirror variant selection. Direct AI tools continue to use the existing `$ToolDefs` npm install path, while variants use a new `$MirrorVariantDefs` table and separate install, verification, plan, and environment rendering paths.

**Tech Stack:** PowerShell 5.1+/7+, npm, winget, cc-mirror CLI, Markdown documentation, Bash test wrapper for local dry-run assertions.

---

## File Structure

- Modify `install.ps1`: direct AI CLI and cc-mirror variant selection/install/verification behavior.
- Modify `README.md`: document direct AI CLIs, supported cc-mirror variants, and Codex direct-only behavior.
- Create `tests/test_install_ps1.sh`: cross-platform wrapper that runs PowerShell dry-run checks when `pwsh` or `powershell` is available.

## Task 1: Add Windows dry-run tests for the desired behavior

**Files:**
- Create: `tests/test_install_ps1.sh`

- [ ] **Step 1: Create a failing dry-run test script**

Create `tests/test_install_ps1.sh` with:

```bash
#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

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
assert_not_contains "$quick_output" "npx cc-mirror quick --provider openai"
assert_not_contains "$quick_output" "--name codex"

mirror_output="$(run_installer -Mode Mirror)"
assert_contains "$mirror_output" "npm install -g @openai/codex"
assert_contains "$mirror_output" "npx cc-mirror quick --provider minimax --name minimax --no-tweak"
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
```

- [ ] **Step 2: Run the test and verify it fails against current code**

Run:

```bash
bash tests/test_install_ps1.sh
```

Expected before implementation: fail because current `install.ps1` does not create the `kimi` variant and still attempts Codex through cc-mirror.

## Task 2: Replace mirror routing state with supported variant state

**Files:**
- Modify: `install.ps1`

- [ ] **Step 1: Replace `$MirrorSelected` and `$MirrorCapable` definitions**

Replace:

```powershell
$MirrorSelected = @{ claude=$false; minimax=$false; codex=$false }

# Maps mirror-capable tool key -> cc-mirror provider argument
$MirrorCapable  = @{ claude="mirror"; minimax="minimax"; codex="openai" }
```

with:

```powershell
$MirrorSelected = @{ mclaude=$false; minimax=$false; kimi=$false }

$MirrorVariantDefs = @(
    @{ Key="mclaude"; Name="Mirror Claude"; Command="mclaude"; Provider="mirror"; Desc="Claude Code variant using mirror provider" },
    @{ Key="minimax"; Name="MiniMax Claude"; Command="minimax"; Provider="minimax"; Desc="Claude Code variant using MiniMax provider" },
    @{ Key="kimi";    Name="Kimi Claude";    Command="kimi";    Provider="kimi";    Desc="Claude Code variant using Kimi provider" }
)
```

- [ ] **Step 2: Add helper functions for mirror variant state**

Add these functions after the `$MirrorVariantDefs` declaration:

```powershell
function script:Get-MirrorVariant([string]$key) {
    foreach ($v in $MirrorVariantDefs) {
        if ($v.Key -eq $key) { return $v }
    }
    return $null
}

function script:Any-MirrorVariantSelected {
    foreach ($k in @($MirrorSelected.Keys)) {
        if ($MirrorSelected[$k]) { return $true }
    }
    return $false
}

function script:Enable-MirrorVariant([string]$key) {
    if (-not $MirrorSelected.ContainsKey($key)) {
        Write-Warn "Unknown cc-mirror variant selector: $key"
        return
    }
    $MirrorSelected[$key] = $true
    $Selected.ccmirror = $true
    $Selected.node = $true
}

function script:Clear-MirrorVariants {
    foreach ($k in @($MirrorSelected.Keys)) {
        $MirrorSelected[$k] = $false
    }
}
```

## Task 3: Update Windows selection and TUI rendering

**Files:**
- Modify: `install.ps1`

- [ ] **Step 1: Update inline mirror badge logic**

Replace all main tool menu badge checks that use:

```powershell
($MirrorCapable.ContainsKey($t.Key)) -and $Selected[$t.Key] -and $MirrorSelected[$t.Key]
```

with no direct tool badge for mirror variants. Direct tools and variants are separate, so direct AI rows should only show selected/unselected state.

- [ ] **Step 2: Render variant rows from `$MirrorVariantDefs`**

In `Draw-MenuBody`, replace the cc-mirror routing sub-section with:

```powershell
$variantRows = @()
if ($Selected.ccmirror) {
    $variantRows = @($MirrorVariantDefs)
}
if ($variantRows.Count -gt 0) {
    bEmpty
    bLabel "CC-MIRROR VARIANTS  (additional Claude Code commands)"
    bEmpty
    foreach ($v in $variantRows) {
        $chk      = if ($MirrorSelected[$v.Key]) { "x" } else { " " }
        $num      = ($idx + 1).ToString().PadRight(2)
        $name     = $v.Name.PadRight(19)
        $provider = $v.Provider
        $command  = $v.Command
        $row      = "  $num [$chk]  $name -> $command  (provider: $provider)"

        if ($idx -eq $cursor) {
            bRowHL $row
        } elseif ($MirrorSelected[$v.Key]) {
            bRow $row Magenta
        } else {
            bRow $row DarkGray
        }
        $idx++
    }
}
```

- [ ] **Step 3: Update menu toggle logic**

In `Invoke-InteractiveMenu`, replace mirror row calculations with `$variantRows = @($MirrorVariantDefs)` when `$Selected.ccmirror` is true. When toggling a variant row, use:

```powershell
$variantIdx = $cursor - $ToolDefs.Count
if ($variantIdx -lt $variantRows.Count) {
    $vk = $variantRows[$variantIdx].Key
    $MirrorSelected[$vk] = -not $MirrorSelected[$vk]
    if (Any-MirrorVariantSelected) {
        $Selected.ccmirror = $true
        $Selected.node = $true
    }
}
```

- [ ] **Step 4: Update all/none behavior**

When pressing `A`, select every direct tool and every mirror variant:

```powershell
foreach ($t in $ToolDefs) { $Selected[$t.Key] = $true }
foreach ($k in @($MirrorSelected.Keys)) { $MirrorSelected[$k] = $true }
$Selected.ccmirror = $true
$Selected.node = $true
```

When pressing `N`, clear direct tools and variants:

```powershell
foreach ($t in $ToolDefs) { $Selected[$t.Key] = $false }
Clear-MirrorVariants
```

- [ ] **Step 5: Update `Draw-MirrorBody` and `Invoke-MirrorMenu`**

Change `Draw-MirrorBody` to accept `$MirrorVariantDefs` rows and render `Name`, `Command`, and `Provider`.

Change `Invoke-MirrorMenu` to collect variants with:

```powershell
$mirrorTools = @($MirrorVariantDefs)
```

and toggle `$MirrorSelected[$tk]` using each variant `Key`.

## Task 4: Update selection parsing and defaults

**Files:**
- Modify: `install.ps1`

- [ ] **Step 1: Update help text**

Change help examples from:

```powershell
bRow "  .\install.ps1 -Mirror claude,minimax" White
```

to:

```powershell
bRow "  .\install.ps1 -Mirror claude,minimax,kimi" White
```

Add `kimi` to the `-Mirror` option description row:

```powershell
bRow "  -Mirror <list>         Create cc-mirror variants: claude,minimax,kimi" White
```

- [ ] **Step 2: Update `Apply-Mirror`**

Replace the switch body with:

```powershell
switch ($tok) {
    "claude"     { Enable-MirrorVariant "mclaude" }
    "mclaude"    { Enable-MirrorVariant "mclaude" }
    "mirror"     { Enable-MirrorVariant "mclaude" }
    "minimax"    { Enable-MirrorVariant "minimax" }
    "mmx"        { Enable-MirrorVariant "minimax" }
    "kimi"       { Enable-MirrorVariant "kimi" }
    "kimiclaude" { Enable-MirrorVariant "kimi" }
    "codex"      { Write-Warn "Codex is direct-only and is not supported as a cc-mirror variant" }
    "openaicodex" { Write-Warn "Codex is direct-only and is not supported as a cc-mirror variant" }
    default      { Write-Warn "Unknown mirror selector: $item" }
}
```

- [ ] **Step 3: Update `Configure-Selection` defaults**

For `Quick` and `Custom`, keep VS Code, Windows Terminal, direct Claude, and direct Minimax off by default. Keep direct Codex, direct Gemini, cc-mirror, and only the `minimax` cc-mirror variant on:

```powershell
$Selected.vscode=$false; $Selected.terminal=$false; $Selected["7zip"]=$false
$Selected.claude=$false; $Selected.ccmirror=$true
$Selected.minimax=$false; $Selected.codex=$true; $Selected.gemini=$true
$MirrorSelected.mclaude=$false; $MirrorSelected.minimax=$true; $MirrorSelected.kimi=$false
```

For `Mirror`, set Node, cc-mirror, direct Codex, and only the `minimax` variant true:

```powershell
$Selected.git=$false; $Selected.python=$false; $Selected.node=$true
$Selected.vscode=$false; $Selected.terminal=$false; $Selected["7zip"]=$false
$Selected.claude=$false; $Selected.ccmirror=$true
$Selected.minimax=$false; $Selected.codex=$true; $Selected.gemini=$false
$MirrorSelected.mclaude=$false; $MirrorSelected.minimax=$true; $MirrorSelected.kimi=$false
```

Replace final mirror dependency check with:

```powershell
if (Any-MirrorVariantSelected) {
    $Selected.ccmirror = $true
    $Selected.node = $true
}
```

## Task 5: Update install, plan, verification, and environment output

**Files:**
- Modify: `install.ps1`

- [ ] **Step 1: Update `Show-Plan`**

Direct tools should be listed when `$Selected[$t.Key]` is true. After direct tool groups, add:

```powershell
if (Any-MirrorVariantSelected) {
    bRow "  CC-MIRROR VARIANTS" Cyan
    foreach ($v in $MirrorVariantDefs) {
        if (-not $MirrorSelected[$v.Key]) { continue }
        bRow "    [>] $($v.Command)  (provider: $($v.Provider))" White
    }
}
```

- [ ] **Step 2: Add variant installation function**

Keep `Install-MirrorVariant`, but call it with variant command names:

```powershell
Install-MirrorVariant "$($v.Name) (cc-mirror)" $v.Command $v.Provider
```

- [ ] **Step 3: Update `Install-AiTools`**

Install direct AI tools using `$Selected[$t.Key]` only:

```powershell
foreach ($t in $ToolDefs) {
    if ($t.Group -ne "ai") { continue }
    if (-not $Selected[$t.Key]) { continue }
    Install-NpmPkg $t.Name $t.Binary $t.NpmPkg $t.Verify
}
```

Then refresh PATH and create selected variants:

```powershell
Update-SessionPath
if (Any-MirrorVariantSelected) {
    foreach ($v in $MirrorVariantDefs) {
        if (-not $MirrorSelected[$v.Key]) { continue }
        Install-MirrorVariant "$($v.Name) (cc-mirror)" $v.Command $v.Provider
    }
}
```

- [ ] **Step 4: Update `Invoke-Verify`**

Verify direct tools only from `$ToolDefs`. Then verify variants separately:

```powershell
if (Any-MirrorVariantSelected) {
    if (Test-Cmd "cc-mirror") {
        $variantList = ""
        try { $variantList = (npx cc-mirror list 2>$null | Out-String) } catch {}
        foreach ($v in $MirrorVariantDefs) {
            if (-not $MirrorSelected[$v.Key]) { continue }
            if ($variantList -match [regex]::Escape($v.Command)) {
                Set-Result "$($v.Name) (cc-mirror)" $v.Command "verified"
                Write-OK ("$($v.Name)".PadRight(22) + " variant: $($v.Command)")
            } else {
                Set-Result "$($v.Name) (cc-mirror)" "variant not listed" "missing"
                Write-Warn ("$($v.Name)".PadRight(22) + " variant not listed")
            }
        }
    } else {
        foreach ($v in $MirrorVariantDefs) {
            if (-not $MirrorSelected[$v.Key]) { continue }
            Set-Result "$($v.Name) (cc-mirror)" "cc-mirror unavailable" "missing"
            Write-Warn ("$($v.Name)".PadRight(22) + " cc-mirror unavailable")
        }
    }
}
```

- [ ] **Step 5: Update `Show-Summary` ordering**

After `$ToolDefs` result ordering, append variant results:

```powershell
foreach ($v in $MirrorVariantDefs) {
    $key = "$($v.Name) (cc-mirror)"
    if ($ResultsMap.ContainsKey($key)) { $ResultsMap[$key] }
}
```

- [ ] **Step 6: Update `Show-Environment`**

Direct AI tools should render only direct selected tools. Then render variants separately:

```powershell
if (Any-MirrorVariantSelected) {
    bLabel "CC-MIRROR VARIANTS"
    bEmpty
    foreach ($v in $MirrorVariantDefs) {
        if (-not $MirrorSelected[$v.Key]) { continue }
        bRow ("    " + $v.Command.PadRight(20) + " provider: $($v.Provider)") Magenta
    }
    bEmpty
}
```

## Task 6: Update README documentation

**Files:**
- Modify: `README.md`

- [ ] **Step 1: Update PowerShell mirror example**

Change:

```powershell
.\install.ps1 -Mirror claude,minimax,codex
```

to:

```powershell
.\install.ps1 -Mirror claude,minimax,kimi
```

- [ ] **Step 2: Update behavior section**

Replace the paragraph about Claude, Minimax, and Codex mirror requests with:

```markdown
On Windows, the default AI CLI set installs `codex`, `gemini`, and `cc-mirror`. Direct `claude` and `mmx` installs are available in Custom mode or through `-Only`, but they are not selected by default. The default cc-mirror variant is `minimax`.

Supported cc-mirror variants are:

- `mclaude` using provider `mirror`
- `minimax` using provider `minimax`
- `kimi` using provider `kimi`

Codex is direct-only. It is installed from `@openai/codex` and is not configured through cc-mirror.
```

## Task 7: Verify and commit implementation

**Files:**
- Modify: `install.ps1`
- Modify: `README.md`
- Create: `tests/test_install_ps1.sh`

- [ ] **Step 1: Run PowerShell dry-run tests**

Run:

```bash
bash tests/test_install_ps1.sh
```

Expected: `install.ps1 AI environment tests passed`

- [ ] **Step 2: Run existing Bash tests**

Run:

```bash
bash tests/test_install_sh.sh
```

Expected: `install.sh selection tests passed`

- [ ] **Step 3: Inspect for accidental Codex mirror routing**

Run:

```bash
rg -n "codex.*Mirror|Mirror.*codex|provider openai|--name codex|MirrorCapable" install.ps1 README.md
```

Expected: no matches except README statements that Codex is direct-only.

- [ ] **Step 4: Review git diff**

Run:

```bash
git diff -- install.ps1 README.md tests/test_install_ps1.sh
```

Expected: diff only contains direct AI CLI plus supported variant behavior.

- [ ] **Step 5: Commit the implementation**

Run:

```bash
git add install.ps1 README.md tests/test_install_ps1.sh
git commit -m "Fix Windows AI CLI and cc-mirror variant installs"
```

## Self-Review

- Spec coverage: Tasks cover direct AI CLI installs, supported cc-mirror variants, Codex direct-only behavior, automatic Node/cc-mirror selection for variants, separate plan/summary/environment output, README updates, and dry-run verification.
- Placeholder scan: no TBD, TODO, placeholder, or "similar to" steps remain.
- Type consistency: variant state uses `$MirrorSelected` keys `mclaude`, `minimax`, and `kimi`; variant metadata uses `$MirrorVariantDefs` properties `Key`, `Name`, `Command`, `Provider`, and `Desc`.
