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
    Write-LineColor "+----------------------------------------------+" Cyan
    Write-LineColor "|      Developer CLI Tools Installer           |" Cyan
    Write-LineColor "+----------------------------------------------+" Cyan
    Write-Host "Version $AppVersion"
    Write-Host ""
}

function Section([string]$Name) {
    Write-Host ""
    Write-LineColor "> $Name" Cyan
}

function Ok([string]$Message) {
    Write-LineColor "[ok] $Message" Green
}

function Warn([string]$Message) {
    Write-LineColor "[!] $Message" Yellow
}

function Fail([string]$Message) {
    Write-LineColor "[x] $Message" Red
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

    Invoke-Expression $CommandLine
    return $LASTEXITCODE -eq 0
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
    if ($DryRun) {
        Write-Host "Run mode:        dry-run"
    } else {
        Write-Host "Run mode:        install"
    }
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
        if ([string]::IsNullOrWhiteSpace($version)) { $version = "detected" }
        Add-Result $Label $version "skipped"
        return
    }

    $cmd = "winget install --id $PackageId --exact --accept-source-agreements --accept-package-agreements"
    if (Invoke-Step $cmd) {
        if ($DryRun) {
            Add-Result $Label "install planned" "planned"
        } else {
            Add-Result $Label "installed" "installed"
        }
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
            if ([string]::IsNullOrWhiteSpace($value)) { $value = "detected" }
            Add-Result $tool.Name $value "skipped"
            continue
        }

        if ($tool.Manager -eq "npm") {
            $cmd = "npm install -g $($tool.Package)"
            if (Invoke-Step $cmd) {
                if ($DryRun) {
                    Add-Result $tool.Name "install planned" "planned"
                } else {
                    Add-Result $tool.Name "installed" "installed"
                }
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
