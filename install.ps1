[CmdletBinding()]
param(
    [Alias("y")]
    [switch]$Yes,
    [switch]$DryRun,
    [switch]$NoColor,
    [ValidateSet("Quick", "Custom", "Mirror")]
    [string]$Mode = "Custom",
    [ValidateSet("Native", "WSL")]
    [string]$Target = "Native",
    [string]$Only = "",
    [string]$Skip = "",
    [string]$Mirror = "",
    [switch]$Help,
    [switch]$SkipWingetAutoRestart
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Continue"

# ─────────────────────────────────────────────────────────────────────────────
# CONSTANTS & STATE
# ─────────────────────────────────────────────────────────────────────────────
$AppVersion = "0.1.0"
$BoxW       = 76
$InnerW     = $BoxW - 6     # "  | " + content + " |"
$ResultsMap = @{}

$ToolDefs = @(
    # ── System prerequisites (auto-selected when winget is absent) ──────────
    @{ Key="msstore";   Name="Microsoft Store";    Desc="Prerequisite for modern app installation"; Group="prereq"; Method="script"; Url=""; CheckPkg="Microsoft.WindowsStore*";           Binary=""; WinPkg=""; NpmPkg=""; Verify="" },
    @{ Key="winget";    Name="Windows Package Manager"; Desc="Primary package manager for dev dependencies"; Group="prereq"; Method="script"; Url=""; CheckPkg="Microsoft.DesktopAppInstaller*";    Binary=""; WinPkg=""; NpmPkg=""; Verify="" },
    # ── Base ────────────────────────────────────────────────────────────────
    @{ Key="git";      Name="Git";               Desc="Source control system";          Group="base"; Method="winget"; Url=""; CheckPkg=""; Binary="git";       WinPkg="Git.Git";                   NpmPkg="";                          Verify="git --version"      },
    @{ Key="python";   Name="Python 3.x";        Desc="Scripting and AI workflows";     Group="base"; Method="winget"; Url=""; CheckPkg=""; Binary="python";    WinPkg="Python.Python.3.12";        NpmPkg="";                          Verify="python --version"   },
    @{ Key="node";     Name="Node.js LTS";        Desc="Runtime for npm/AI CLI tools";   Group="base"; Method="winget"; Url=""; CheckPkg=""; Binary="node";      WinPkg="OpenJS.NodeJS.LTS";         NpmPkg="";                          Verify="node --version"     },
    # ── Dev Tools ───────────────────────────────────────────────────────────
    @{ Key="vscode";   Name="VS Code";            Desc="Editor + AI extensions hub";     Group="dev";  Method="winget"; Url=""; CheckPkg=""; Binary="code";      WinPkg="Microsoft.VisualStudioCode";NpmPkg="";                          Verify="code --version"     },
    @{ Key="terminal"; Name="Windows Terminal";   Desc="Modern tabbed terminal";         Group="dev";  Method="winget"; Url=""; CheckPkg=""; Binary="wt";        WinPkg="Microsoft.WindowsTerminal"; NpmPkg="";                          Verify="wt --version"       },
    @{ Key="7zip";     Name="7-Zip";              Desc="Fast archiver for packages";     Group="dev";  Method="winget"; Url=""; CheckPkg=""; Binary="7z";        WinPkg="7zip.7zip";                 NpmPkg="";                          Verify="7z i"               },
    # ── AI CLI Tools ────────────────────────────────────────────────────────
    @{ Key="claude";   Name="Claude Code";        Desc="Anthropic AI coding assistant";  Group="ai";   Method="npm";    Url=""; CheckPkg=""; Binary="claude";    WinPkg="";                          NpmPkg="@anthropic-ai/claude-code"; Verify="claude --version"   },
    @{ Key="ccmirror"; Name="cc-mirror";          Desc="Multi-provider AI gateway";      Group="ai";   Method="npm";    Url=""; CheckPkg=""; Binary="cc-mirror"; WinPkg="";                          NpmPkg="cc-mirror";                 Verify="cc-mirror --help"   },
    @{ Key="minimax";  Name="Minimax (mmx)";      Desc="MiniMax AI CLI assistant";       Group="ai";   Method="npm";    Url=""; CheckPkg=""; Binary="mmx";       WinPkg="";                          NpmPkg="mmx-cli";                   Verify="mmx --version"      },
    @{ Key="codex";    Name="OpenAI Codex";       Desc="OpenAI coding assistant";        Group="ai";   Method="npm";    Url=""; CheckPkg=""; Binary="codex";     WinPkg="";                          NpmPkg="@openai/codex";             Verify="codex --version"    },
    @{ Key="gemini";   Name="Gemini CLI";         Desc="Google Gemini AI assistant";     Group="ai";   Method="npm";    Url=""; CheckPkg=""; Binary="gemini";    WinPkg="";                          NpmPkg="@google/gemini-cli";        Verify="gemini --version"   }
)

# Prereq auto-selection happens in Configure-Selection after Test-Cmd is available
$Selected = @{
    msstore=$false; winget=$false                                  # set by Configure-Selection
    git=$true;  python=$true;  node=$true
    vscode=$true; terminal=$true; "7zip"=$false
    claude=$true; ccmirror=$false; minimax=$true; codex=$true; gemini=$true
}

$MirrorSelected = @{ mclaude=$false; minimax=$false; kimi=$false }

$MirrorVariantDefs = @(
    @{ Key="mclaude"; Name="Mirror Claude";  Command="mclaude"; Provider="mirror";  Desc="Claude Code variant using mirror provider" },
    @{ Key="minimax"; Name="MiniMax Claude"; Command="minimax"; Provider="minimax"; Desc="Claude Code variant using MiniMax provider" },
    @{ Key="kimi";    Name="Kimi Claude";    Command="kimi";    Provider="kimi";    Desc="Claude Code variant using Kimi provider" }
)

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

# ─────────────────────────────────────────────────────────────────────────────
# COLOR ENGINE  (prefixed "col" to avoid PowerShell built-in alias conflicts)
# ─────────────────────────────────────────────────────────────────────────────
function script:CanColor {
    return (-not $NoColor) -and ($null -ne $Host.UI.RawUI)
}

function script:colPrint {
    param(
        [string]$Text,
        [ConsoleColor]$FgColor  = [ConsoleColor]::White,
        [ConsoleColor]$BgColor  = [ConsoleColor]::Black,
        [switch]$NoNl,
        [switch]$UseBg
    )
    if (-not (CanColor)) {
        if ($NoNl) { Write-Host $Text -NoNewline } else { Write-Host $Text }
        return
    }
    $p = @{ Object=$Text; ForegroundColor=$FgColor }
    if ($UseBg) { $p.BackgroundColor = $BgColor }
    if ($NoNl)  { $p.NoNewline = $true }
    Write-Host @p
}

function colW([string]$t,[switch]$n)  { colPrint $t White    -NoNl:$n }
function colC([string]$t,[switch]$n)  { colPrint $t Cyan     -NoNl:$n }
function colG([string]$t,[switch]$n)  { colPrint $t Green    -NoNl:$n }
function colY([string]$t,[switch]$n)  { colPrint $t Yellow   -NoNl:$n }
function colR([string]$t,[switch]$n)  { colPrint $t Red      -NoNl:$n }
function colD([string]$t,[switch]$n)  { colPrint $t DarkGray -NoNl:$n }
function colM([string]$t,[switch]$n)  { colPrint $t Magenta  -NoNl:$n }
function colDC([string]$t,[switch]$n) { colPrint $t DarkCyan -NoNl:$n }

function Write-OK([string]$msg)    { colG  "  [+] $msg" }
function Write-Warn([string]$msg)  { colY  "  [*] $msg" }
function Write-Fatal([string]$msg) { colR  "  [X] $msg"; exit 1 }
function Write-Info([string]$msg)  { colC  "  [i] $msg" }
function Write-Step([string]$msg)  { colW  "  ... $msg" }

function script:PathContains {
    param([string[]]$paths, [string]$entry)
    $needle = $entry.Trim()
    if ([string]::IsNullOrWhiteSpace($needle)) { return $false }
    $needle = $needle.TrimEnd([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar).ToLowerInvariant()
    foreach ($p in $paths) {
        if ([string]::IsNullOrWhiteSpace($p)) { continue }
        if (($p.Trim().TrimEnd([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar).ToLowerInvariant()) -eq $needle) {
            return $true
        }
    }
    return $false
}

function script:Add-PathEntry {
    param([string]$entry)
    $entry = $entry.Trim()
    if ([string]::IsNullOrWhiteSpace($entry)) { return }
    $entry = [Environment]::ExpandEnvironmentVariables($entry).TrimEnd([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar)

    $machinePath  = [Environment]::GetEnvironmentVariable("Path", "Machine")
    $machineEntries = @()
    if (-not [string]::IsNullOrWhiteSpace($machinePath)) {
        $machineEntries = $machinePath -split ';'
    }

    $userPath    = [Environment]::GetEnvironmentVariable("Path", "User")
    $userEntries = @()
    if (-not [string]::IsNullOrWhiteSpace($userPath)) {
        $userEntries = $userPath -split ';'
    }
    $combinedEntries = @($machineEntries + $userEntries)

    if (-not (PathContains $combinedEntries $entry)) {
        if ([string]::IsNullOrWhiteSpace($userPath)) {
            $userPath = $entry
        } else {
            $userPath = "$userPath;$entry"
        }
        [Environment]::SetEnvironmentVariable("Path", $userPath, "User")
        Write-OK "Added `"$entry`" to user PATH"
    }
    $env:Path = if ([string]::IsNullOrWhiteSpace($machinePath)) { $userPath } else { "$machinePath;$userPath" }
}

function script:Ensure-NpmGlobalPath {
    if (-not (Test-Cmd "npm")) { return }

    $npmPrefix = ""
    try {
        $npmPrefix = (npm config get prefix 2>$null | Out-String).Trim()
    } catch {
        return
    }

    if ([string]::IsNullOrWhiteSpace($npmPrefix)) { return }

    Add-PathEntry $npmPrefix
}

function script:Ensure-ExecutionPolicy {
    if ($DryRun) {
        Write-Info "Dry-run: would run Set-ExecutionPolicy RemoteSigned -Scope CurrentUser -Force"
        return
    }

    try {
        Set-ExecutionPolicy RemoteSigned -Scope CurrentUser -Force -ErrorAction Stop
        Write-OK "PowerShell execution policy set to RemoteSigned for CurrentUser"
    } catch {
        Write-Warn "Could not set PowerShell execution policy to RemoteSigned: $_"
    }
}

# ─────────────────────────────────────────────────────────────────────────────
# BOX DRAWING
# ─────────────────────────────────────────────────────────────────────────────
function bTop {
    param([string]$Title = "")
    if ([string]::IsNullOrEmpty($Title)) {
        colD ("  +" + ("-" * ($InnerW + 2)) + "+")
    } else {
        $tp   = "-- $Title "
        $fill = [Math]::Max(0, $InnerW + 2 - $tp.Length)
        colD "  +" -n; colC $tp -n; colD ("-" * $fill + "+")
    }
}

function bRow {
    param([string]$Content = "", [ConsoleColor]$Fg = [ConsoleColor]::White)
    $p = $Content.PadRight($InnerW)
    if ($p.Length -gt $InnerW) { $p = $p.Substring(0, $InnerW - 3) + "..." }
    colD "  |" -n; colPrint (" $p ") $Fg -NoNl; colD "|"
}

function bRowHL {
    param([string]$Content = "")
    $p = $Content.PadRight($InnerW)
    if ($p.Length -gt $InnerW) { $p = $p.Substring(0, $InnerW - 3) + "..." }
    colD "  |" -n
    colPrint (" $p ") Black Cyan -UseBg -NoNl
    colD "|"
}

function bEmpty { colD ("  |" + (" " * ($InnerW + 2)) + "|") }
function bBot   { colD ("  +" + ("-" * ($InnerW + 2)) + "+") }
function bLabel([string]$lbl) { bRow "   $lbl" Cyan }
function bHRule { bRow ("   " + ("-" * ($InnerW - 4))) DarkGray }

# ─────────────────────────────────────────────────────────────────────────────
# BANNER
# ─────────────────────────────────────────────────────────────────────────────
function Show-Banner {
    Clear-Host
    $iw  = $BoxW - 2
    $top = "=" * $iw
    colC "+$top+"

    colC "|" -n
    colW "  DEV CLI INSTALLER  " -n
    colD "v$AppVersion" -n
    $badge = " [WINDOWS] "
    colW (" " * [Math]::Max(0, $iw - 22 - $badge.Length - 2)) -n
    colY $badge -n
    colW "  " -n
    colC "|"

    colC "|" -n
    colD "  One-click AI development environment setup for Windows".PadRight($iw) -n
    colC "|"

    colC "+$top+"
    Write-Host ""
}

# ─────────────────────────────────────────────────────────────────────────────
# INFO BAR
# ─────────────────────────────────────────────────────────────────────────────
function Show-InfoBar {
    colD "  " -n; colC "Platform: " -n; colW "Windows   " -n
    colC "Mode: "   -n; colW "$Mode   "   -n
    colC "Target: " -n; colW $Target      -n
    if (Test-IsAdmin) { colG "   [ADMIN]"  -n } else { colY "   [LIMITED - may need elevation]" -n }
    if ($DryRun)      { colY "   [DRY-RUN]" -n }
    Write-Host ""; Write-Host ""
}

# ─────────────────────────────────────────────────────────────────────────────
# WINGET BOOTSTRAP
# ─────────────────────────────────────────────────────────────────────────────
function script:Test-Cmd([string]$name) {
    return $null -ne (Get-Command $name -ErrorAction SilentlyContinue)
}

# Returns true if the DesktopAppInstaller (winget) AppX package is present on this machine.
# This is independent of whether winget can be executed from the current process context.
function script:Test-WingetInstalled {
    return $null -ne (Get-AppxPackage "Microsoft.DesktopAppInstaller" -ErrorAction SilentlyContinue)
}

# Returns a winget executable path that actually runs in the current process context,
# or $null if no working path is found.
# NOTE: App Execution Aliases (%LOCALAPPDATA%\Microsoft\WindowsApps\winget.exe) and the
# raw binary in C:\Program Files\WindowsApps both fail with "Access is denied" from
# elevated (admin) processes -- this is a Windows security feature. In that case callers
# should use Invoke-WingetTask instead.
$script:WingetExe = $null
function script:Get-WingetExe {
    if ($null -ne $script:WingetExe) { return $script:WingetExe }

    $candidates = @()
    $cmd = Get-Command "winget" -ErrorAction SilentlyContinue
    if ($null -ne $cmd) { $candidates += $cmd.Source }

    $real = Get-ChildItem "C:\Program Files\WindowsApps" -Filter "winget.exe" -Recurse -ErrorAction SilentlyContinue |
            Where-Object { $_.FullName -like "*DesktopAppInstaller*" } |
            Sort-Object LastWriteTime -Descending |
            Select-Object -First 1
    if ($null -ne $real) { $candidates += $real.FullName }

    foreach ($c in $candidates) {
        if ([string]::IsNullOrEmpty($c)) { continue }
        $testOk = $false
        try { $null = & $c --version 2>&1; $testOk = ($LASTEXITCODE -eq 0) } catch {}
        if ($testOk) { $script:WingetExe = $c; return $script:WingetExe }
    }
    return $null
}

# Install-Winget actual implementation from upstream file:
# https://raw.githubusercontent.com/ThioJoe/Windows-Sandbox-Tools/refs/heads/main/Installer%20Scripts/Install-Winget.ps1
function script:Install-WingetWithReferenceScript {
    $installerUrl = "https://raw.githubusercontent.com/ThioJoe/Windows-Sandbox-Tools/refs/heads/main/Installer%20Scripts/Install-Winget.ps1"
    $tmpScript = Join-Path $env:TEMP "Install-Winget.ps1"
    $psExe = $null

    foreach ($exe in @("pwsh", "powershell")) {
        $found = Get-Command $exe -ErrorAction SilentlyContinue
        if ($null -ne $found) { $psExe = $found.Source; break }
    }
    if (-not $psExe) { throw "PowerShell executable not found." }

    try {
        Write-Step "Downloading official winget installer script from upstream..."
        Invoke-WebRequest -Uri $installerUrl -OutFile $tmpScript -UseBasicParsing -ErrorAction Stop
        if ($DryRun) {
            Write-Info "Dry-run: would run $tmpScript"
            return
        }
        Write-Step "Running official winget install script..."
        $proc = Start-Process -FilePath $psExe -ArgumentList @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $tmpScript) -Wait -PassThru -NoNewWindow -ErrorAction Stop
        if (($proc.ExitCode -ne 0) -and ($proc.ExitCode -ne $null)) {
            throw "Reference winget script exited with code $($proc.ExitCode)"
        }
    } finally {
        if (Test-Path $tmpScript) { Remove-Item $tmpScript -Force -ErrorAction SilentlyContinue }
    }
}

function script:Test-MicrosoftStoreInstalled {
    $store = Get-AppxPackage -Name "Microsoft.WindowsStore" -ErrorAction SilentlyContinue
    if ($null -eq $store) {
        $store = Get-AppxPackage -AllUsers -Name "Microsoft.WindowsStore" -ErrorAction SilentlyContinue
    }
    return $null -ne $store
}

function script:Install-MicrosoftStoreWithReferenceScript {
    if (Test-MicrosoftStoreInstalled) {
        Write-Info "Microsoft Store is already installed."
        return
    }

    $installerUrl = "https://raw.githubusercontent.com/ThioJoe/Windows-Sandbox-Tools/refs/heads/main/Installer%20Scripts/Install-Microsoft-Store.ps1"
    $tmpScript = Join-Path $env:TEMP "Install-Microsoft-Store.ps1"
    $psExe = $null

    foreach ($exe in @("pwsh", "powershell")) {
        $found = Get-Command $exe -ErrorAction SilentlyContinue
        if ($null -ne $found) { $psExe = $found.Source; break }
    }
    if (-not $psExe) { throw "PowerShell executable not found." }

    try {
        Write-Step "Downloading official Microsoft Store installer script from upstream..."
        Invoke-WebRequest -Uri $installerUrl -OutFile $tmpScript -UseBasicParsing -ErrorAction Stop
        if ($DryRun) {
            Write-Info "Dry-run: would run $tmpScript"
            return
        }
        Write-Step "Running official Microsoft Store install script..."
        $proc = Start-Process -FilePath $psExe -ArgumentList @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $tmpScript) -Wait -PassThru -NoNewWindow -ErrorAction Stop
        if (($proc.ExitCode -ne 0) -and ($proc.ExitCode -ne $null)) {
            throw "Reference Microsoft Store script exited with code $($proc.ExitCode)"
        }
    } finally {
        if (Test-Path $tmpScript) { Remove-Item $tmpScript -Force -ErrorAction SilentlyContinue }
    }
}

# Runs winget install at LIMITED (non-elevated) privilege via a Scheduled Task.
# This bypasses the Windows restriction that prevents App Execution Aliases from
# running inside elevated processes. Task Scheduler launches the task at medium
# integrity (the user's normal token) even when called from an admin session.
function script:Get-WingetBin {
    # 1. Alias / PATH
    $cmd = Get-Command "winget" -ErrorAction SilentlyContinue
    if ($null -ne $cmd) { return $cmd.Source }

    # 2. Real binary via AppX package install location (works even when C:\Program Files\WindowsApps is inaccessible)
    $pkg = Get-AppxPackage "Microsoft.DesktopAppInstaller" -ErrorAction SilentlyContinue
    if ($null -ne $pkg -and (-not [string]::IsNullOrEmpty($pkg.InstallLocation))) {
        $e = Join-Path $pkg.InstallLocation "winget.exe"
        if (Test-Path $e) { return $e }
    }

    # 3. Recursive scan fallback
    $f = Get-ChildItem "C:\Program Files\WindowsApps" -Filter "winget.exe" -Recurse -ErrorAction SilentlyContinue |
         Where-Object { $_.FullName -like "*DesktopAppInstaller*" } |
         Sort-Object LastWriteTime -Descending |
         Select-Object -First 1
    if ($null -ne $f) { return $f.FullName }

    return "winget"
}

function script:Invoke-WingetTask([string]$pkgId) {
    $tName      = "1ci_" + ($pkgId -replace "[^a-zA-Z0-9]", "_")
    $logFile    = Join-Path $env:TEMP ($tName + ".log")
    $wingetBin  = Get-WingetBin

    # --disable-interactivity: no progress bars polluting the log with \r sequences
    # --verbose-logs: maximum diagnostic output
    $wArgs   = "install --id `"$pkgId`" --exact --accept-source-agreements --accept-package-agreements --disable-interactivity --verbose-logs"
    $argLine = "/c `"$wingetBin`" $wArgs > `"$logFile`" 2>&1"

    colD "  [winget] $wingetBin"
    colD "  [log]    $logFile"

    function script:Register-WingetTask([string]$level) {
        Register-ScheduledTask -TaskName $tName -Force `
            -Action   (New-ScheduledTaskAction  -Execute "cmd.exe" -Argument $argLine) `
            -Trigger  (New-ScheduledTaskTrigger -Once -At ([DateTime]::Now.AddSeconds(3))) `
            -Settings (New-ScheduledTaskSettingsSet -ExecutionTimeLimit (New-TimeSpan -Minutes 15) -StartWhenAvailable) `
            -RunLevel $level | Out-Null
    }

    function script:Read-LogLines([int]$from) {
        if (-not (Test-Path $logFile)) { return $from }
        try {
            $raw   = [System.IO.File]::ReadAllText($logFile)
            $raw   = $raw -replace '\x1b\[[0-9;]*[a-zA-Z]', '' -replace '\r', ''
            $lines = $raw.Split("`n")
            for ($i = $from; $i -lt $lines.Count; $i++) {
                $l = $lines[$i].TrimEnd()
                if (-not [string]::IsNullOrWhiteSpace($l)) { colD "    $l" }
            }
            return $lines.Count
        } catch { return $from }
    }

    try {
        if (Test-Path $logFile) { Remove-Item $logFile -Force -ErrorAction SilentlyContinue }

        # Try Limited (non-elevated) first so App Execution Aliases work.
        # Windows Sandbox has no split token so Limited tasks stay Queued - detect that and
        # fall back to Highest which always runs, using the full binary path instead of the alias.
        $usedLevel = "Limited"
        Register-WingetTask "Limited"
        Start-ScheduledTask -TaskName $tName
        Start-Sleep -Seconds 6

        $st = (Get-ScheduledTask -TaskName $tName -ErrorAction SilentlyContinue).State
        colD "  [state 6s] $st  (level=Limited)"

        if ($st -ne "Running") {
            colD "  [fallback] Limited task did not start - retrying at RunLevel Highest"
            $usedLevel = "Highest"
            Unregister-ScheduledTask -TaskName $tName -Confirm:$false -ErrorAction SilentlyContinue
            if (Test-Path $logFile) { Remove-Item $logFile -Force -ErrorAction SilentlyContinue }
            Register-WingetTask "Highest"
            Start-ScheduledTask -TaskName $tName
            Start-Sleep -Seconds 4
            $st = (Get-ScheduledTask -TaskName $tName -ErrorAction SilentlyContinue).State
            colD "  [state 4s] $st  (level=Highest)"
        }

        $lastLine = 0
        $waited   = 10

        do {
            Start-Sleep -Seconds 2
            $waited   += 2
            $lastLine  = Read-LogLines $lastLine

            if (-not (Test-Path $logFile) -and ($waited % 10 -eq 0)) {
                $st2 = (Get-ScheduledTask -TaskName $tName -ErrorAction SilentlyContinue).State
                colD "  [wait ${waited}s] state=$st2  log=missing"
            }

            $st = (Get-ScheduledTask -TaskName $tName -ErrorAction SilentlyContinue).State
        } while (($st -eq "Running" -or $st -eq "Queued") -and ($waited -lt 900))

        $lastLine = Read-LogLines $lastLine   # final flush

        if (-not (Test-Path $logFile)) { colD "  [warn] log file was never created" }

        $info    = Get-ScheduledTaskInfo -TaskName $tName -ErrorAction SilentlyContinue
        $code    = if ($null -ne $info) { [int]$info.LastTaskResult } else { 1 }
        $stFinal = (Get-ScheduledTask -TaskName $tName -ErrorAction SilentlyContinue).State
        colD "  [done] exit=$code (0x$('{0:X8}' -f $code))  state=$stFinal  waited=${waited}s  level=$usedLevel"
        return $code
    } catch {
        Write-Warn "Scheduled task error: $_"
        return 1
    } finally {
        Unregister-ScheduledTask -TaskName $tName -Confirm:$false -ErrorAction SilentlyContinue
        if (Test-Path $logFile) { Remove-Item $logFile -Force -ErrorAction SilentlyContinue }
    }
}

function script:Test-IsAdmin {
    try {
        $id = [Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
        return $id.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    } catch { return $false }
}

function script:Request-Elevation {
    Write-Host ""
    bTop "ADMINISTRATOR REQUIRED"
    bEmpty
    bRow "  winget installation requires Administrator privileges." Yellow
    bRow "  The script must be re-run as Administrator." White
    bEmpty
    bBot
    Write-Host ""

    colW "  Re-launch this script as Administrator now? " -n; colY "[y/N] " -n
    $ans = Read-Host
    if ($ans -notin @("y", "Y", "yes")) {
        Write-Host ""
        bTop "HOW TO RUN AS ADMINISTRATOR"
        bEmpty
        bRow "  1. Close this window." White
        bRow "  2. Search 'PowerShell' in Start Menu." White
        bRow "  3. Right-click -> 'Run as Administrator'." White
        bRow "  4. Re-run: powershell -ExecutionPolicy Bypass -File .\install.ps1" DarkCyan
        bEmpty
        bBot
        exit 1
    }

    # Re-launch as admin, passing all original CLI flags (TUI will re-run elevated)
    $sp = $PSCommandPath
    if ([string]::IsNullOrWhiteSpace($sp)) { $sp = $MyInvocation.PSCommandPath }
    if ([string]::IsNullOrWhiteSpace($sp)) {
        Write-Fatal "Cannot determine script path for elevation. Please run as Administrator manually."
    }

    $argList = @("-ExecutionPolicy", "Bypass", "-File", $sp, "-Mode", $Mode, "-Target", $Target)
    if ($Yes)     { $argList += "-Yes" }
    if ($DryRun)  { $argList += "-DryRun" }
    if ($NoColor) { $argList += "-NoColor" }
    if (-not [string]::IsNullOrWhiteSpace($Only))   { $argList += @("-Only",   $Only) }
    if (-not [string]::IsNullOrWhiteSpace($Skip))   { $argList += @("-Skip",   $Skip) }
    if (-not [string]::IsNullOrWhiteSpace($Mirror)) { $argList += @("-Mirror", $Mirror) }

    try {
        Start-Process powershell -ArgumentList $argList -Verb RunAs -Wait -ErrorAction Stop
    } catch {
        Write-Fatal "Elevation failed ($_). Please open PowerShell as Administrator and re-run manually."
    }
    exit 0
}

function script:Build-InstallerArgList {
    $scriptPath = $PSCommandPath
    if ([string]::IsNullOrWhiteSpace($scriptPath)) { $scriptPath = $MyInvocation.PSCommandPath }
    if ([string]::IsNullOrWhiteSpace($scriptPath)) { $scriptPath = $PSCommandPath }

    $argList = @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $scriptPath)
    $argList += @("-Mode", $Mode, "-Target", $Target)
    if ($Yes)     { $argList += "-Yes" }
    if ($DryRun)  { $argList += "-DryRun" }
    if ($NoColor) { $argList += "-NoColor" }
    if (-not [string]::IsNullOrWhiteSpace($Only))   { $argList += @("-Only",   $Only) }
    if (-not [string]::IsNullOrWhiteSpace($Skip))   { $argList += @("-Skip",   $Skip) }
    if (-not [string]::IsNullOrWhiteSpace($Mirror)) { $argList += @("-Mirror", $Mirror) }
    return $argList
}

function script:Restart-CurrentSessionForWinget {
    if ($SkipWingetAutoRestart) { return }
    $sp = $PSCommandPath
    if ([string]::IsNullOrWhiteSpace($sp)) { $sp = $MyInvocation.PSCommandPath }
    if ([string]::IsNullOrWhiteSpace($sp)) { return }

    $argList = Build-InstallerArgList
    if (-not $argList.Contains("-SkipWingetAutoRestart")) { $argList += "-SkipWingetAutoRestart" }

    $exeCandidates = @("pwsh", "powershell")
    $psExe = $null
    foreach ($exe in $exeCandidates) {
        $found = Get-Command $exe -ErrorAction SilentlyContinue
        if ($null -ne $found) { $psExe = $found.Source; break }
    }
    if ([string]::IsNullOrWhiteSpace($psExe)) { return }

    Write-Info "Restarting PowerShell session to refresh winget context..."
    try {
        Start-Process -FilePath $psExe -ArgumentList $argList -Wait -ErrorAction Stop
        exit 0
    } catch {
        Write-Warn "Could not auto-restart current session for winget resolution. Continuing in current session."
    }
}

function Install-PrereqTool([string]$label, [string]$url, [string]$method, [string]$checkPkg) {
    if (-not [string]::IsNullOrWhiteSpace($checkPkg)) {
        $existing = Get-AppxPackage $checkPkg -ErrorAction SilentlyContinue
        if ($existing) {
            Write-OK "$label already installed"
            return
        }
    }

    $safeName = $label -replace "[^a-zA-Z0-9]", "_"
    $ext      = if ($method -eq "appx") { ".appx" } else { ".exe" }
    $tmpFile  = Join-Path $env:TEMP ("prereq_$safeName$ext")

    Write-Step "Downloading $label..."
    Invoke-WebRequest $url -OutFile $tmpFile -UseBasicParsing -ErrorAction Stop

    if ($method -eq "appx") {
        Write-Step "Installing $label..."
        Add-AppxPackage -Path $tmpFile -ErrorAction Stop
    } elseif ($method -eq "runtime") {
        Write-Step "Installing $label..."
        $proc = Start-Process -FilePath $tmpFile -ArgumentList "--quiet --accept-license" -Wait -PassThru -ErrorAction Stop
        # 1638 = higher version already present; treat as success
        if (($proc.ExitCode -ne 0) -and ($proc.ExitCode -ne 1638)) {
            throw "$label installer exited with code $($proc.ExitCode)"
        }
    }

    Write-OK "$label ready"
}

function Install-Prerequisites {
    $anyPrereq = $false
    foreach ($t in $ToolDefs) {
        if (($t.Group -eq "prereq") -and $Selected[$t.Key]) { $anyPrereq = $true; break }
    }
    if (-not $anyPrereq) { return }

    if (-not (Test-IsAdmin)) {
        Write-Warn "Prerequisites require Administrator privileges. Requesting elevation..."
        Request-Elevation
        return
    }

    Show-Phase "SYSTEM PREREQUISITES"
    $progressPreference = "SilentlyContinue"

    foreach ($t in $ToolDefs) {
        if (($t.Group -ne "prereq") -or (-not $Selected[$t.Key])) { continue }
        Write-Host ""
        bTop "INSTALL: $($t.Name)"
        bEmpty
        bRow "  $($t.Desc)" DarkCyan
        bEmpty; bBot

        try {
            if ($DryRun) {
                Write-Info "Dry-run: would install $($t.Name)"
                Set-Result $t.Name "planned" "planned"
                continue
            }
            if ($t.Method -eq "script") {
                if ($t.Key -eq "msstore") {
                    Install-MicrosoftStoreWithReferenceScript
                    Set-Result $t.Name "installed" "ok"
                    continue
                }
                if ($t.Key -eq "winget") {
                    Install-WingetWithReferenceScript
                    Set-Result $t.Name "installed" "ok"
                    continue
                }
            }
            Install-PrereqTool $t.Name $t.Url $t.Method $t.CheckPkg
            Set-Result $t.Name "installed" "ok"
        } catch {
            Write-Warn "Failed to install $($t.Name): $_"
            Set-Result $t.Name "install failed" "failed"
        }
    }
}

function Ensure-Winget {
    $wgExe = Get-WingetExe
    if ($null -ne $wgExe) {
        Write-OK "winget is available"
        return
    }

    # Winget is installed but App Execution Alias can't run from this elevated session.
    # Invoke-WingetTask will be used for package installs via Task Scheduler instead.
    if (Test-WingetInstalled) {
        Write-Info "winget detected (package installs will run via limited-privilege task)"
        return
    }

    Write-Host ""
    bTop "WINGET NOT FOUND"
    bEmpty
    bRow "  winget (Windows Package Manager) is not installed." Yellow
    bRow "  Attempting automatic installation..." DarkGray
    bEmpty
    bBot
    Write-Host ""

    if (-not (Test-IsAdmin)) {
        Request-Elevation
        return
    }

    try {
        Write-Step "Ensuring Microsoft Store is installed..."
        Install-MicrosoftStoreWithReferenceScript
        Write-Step "Installing winget via official script..."
        Install-WingetWithReferenceScript
        Write-OK "winget installed successfully"
    } catch {
        Write-Fatal "winget installation failed: $_. Ensure Microsoft Store and system permissions are available and re-run as Administrator."
    }

    # Refresh PATH and clear the cached exe path so Get-WingetExe re-resolves
    $script:WingetExe = $null
    $machinePath = [Environment]::GetEnvironmentVariable("Path", "Machine")
    $userPath    = [Environment]::GetEnvironmentVariable("Path", "User")
    $env:Path    = "$machinePath;$userPath"

    $wgExe = Get-WingetExe
    if ($null -ne $wgExe) {
        Write-OK "winget is ready in this session  [$wgExe]"
    } else {
        Write-Warn "winget was installed but could not be resolved in this session."
        Restart-CurrentSessionForWinget
        Write-Info "Continuing - if installs fail, re-run as standard user in a new session."
    }
}

# ─────────────────────────────────────────────────────────────────────────────
# INTERACTIVE SELECTION MENU
# ─────────────────────────────────────────────────────────────────────────────
function script:Draw-MenuBody([int]$cursor) {
    $idx       = 0
    $lastGroup = ""
    foreach ($t in $ToolDefs) {
        if ($t.Group -ne $lastGroup) {
            $lastGroup = $t.Group
            bEmpty
            $grpLbl = switch ($t.Group) {
                "prereq" { "SYSTEM PREREQUISITES  (auto-selected: winget/msstore not found)" }
                "base"   { "BASE DEPENDENCIES" }
                "dev"    { "DEV TOOLS" }
                "ai"     { "AI CLI TOOLS" }
                default  { $t.Group.ToUpper() }
            }
            bLabel $grpLbl
            bEmpty
        }
        $chk  = if ($Selected[$t.Key]) { "x" } else { " " }
        $num  = ($idx + 1).ToString().PadRight(2)
        $name = $t.Name.PadRight(19)
        $row = "  $num [$chk]  $name $($t.Desc)"

        if ($idx -eq $cursor) {
            bRowHL $row
        } elseif ($Selected[$t.Key]) {
            bRow $row Green
        } else {
            bRow $row DarkGray
        }
        $idx++
    }

    # ── CC-MIRROR VARIANTS sub-section (visible only when cc-mirror is selected) ─
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
    bEmpty
}

function Invoke-InteractiveMenu {
    if (($Mode -ne "Custom") -or $Yes -or $DryRun -or (-not [string]::IsNullOrWhiteSpace($Only))) {
        return
    }
    $canInteract = $false
    try { $canInteract = [Environment]::UserInteractive -and ($null -ne $Host.UI.RawUI) } catch {}
    if (-not $canInteract) { return }

    Write-Host ""
    bTop "CHOOSE YOUR TOOLS"
    $menuTop = [Console]::CursorTop
    $cursor  = 0
    Draw-MenuBody $cursor
    bBot

    Write-Host ""
    colD "  Navigate " -n; colY "[UP] [DOWN]" -n
    colD "   Toggle " -n;  colY "[SPACE]" -n
    colD "   All " -n; colY "[A]" -n
    colD "   None " -n; colY "[N]" -n
    colD "   Confirm " -n; colY "[ENTER]" -n
    colD "   Quit " -n; colY "[Q]"
    Write-Host ""

    $done = $false
    while (-not $done) {
        # Recalculate total rows each iteration (variant section appears/disappears with ccmirror toggle)
        $variantRows = @()
        if ($Selected.ccmirror) {
            $variantRows = @($MirrorVariantDefs)
        }
        $totalRows = $ToolDefs.Count + $variantRows.Count
        if ($cursor -ge $totalRows) { $cursor = $totalRows - 1 }

        $key = $null
        try { $key = [Console]::ReadKey($true) } catch { $done = $true; break }

        $needRedraw = $true
        $kch = [char]::ToLower($key.KeyChar)

        if ($key.Key -eq [ConsoleKey]::UpArrow) {
            if ($cursor -gt 0) { $cursor-- }
        } elseif ($key.Key -eq [ConsoleKey]::DownArrow) {
            if ($cursor -lt ($totalRows - 1)) { $cursor++ }
        } elseif ($key.Key -eq [ConsoleKey]::Spacebar) {
            if ($cursor -lt $ToolDefs.Count) {
                # Toggle tool selection
                $tk = $ToolDefs[$cursor].Key
                $Selected[$tk] = -not $Selected[$tk]
                if (($tk -eq "ccmirror") -and (-not $Selected.ccmirror)) { Clear-MirrorVariants }
            } else {
                # Toggle the corresponding cc-mirror variant row
                $variantIdx = $cursor - $ToolDefs.Count
                if ($variantIdx -lt $variantRows.Count) {
                    $vk = $variantRows[$variantIdx].Key
                    $MirrorSelected[$vk] = -not $MirrorSelected[$vk]
                    if (Any-MirrorVariantSelected) {
                        $Selected.ccmirror = $true
                        $Selected.node = $true
                    }
                }
            }
        } elseif ($kch -eq 'a') {
            foreach ($t in $ToolDefs) { $Selected[$t.Key] = $true }
            foreach ($k in @($MirrorSelected.Keys)) { $MirrorSelected[$k] = $true }
            $Selected.ccmirror = $true; $Selected.node = $true
        } elseif ($kch -eq 'n') {
            foreach ($t in $ToolDefs) { $Selected[$t.Key] = $false }
            Clear-MirrorVariants
        } elseif ($key.Key -eq [ConsoleKey]::Enter) {
            $done = $true; $needRedraw = $false
        } elseif ($kch -eq 'q') {
            Write-Host ""; colR "  Installation cancelled."; exit 1
        } else {
            $needRedraw = $false
        }

        if ($needRedraw) {
            try { [Console]::SetCursorPosition(0, $menuTop) } catch {}
            Draw-MenuBody $cursor
        }
    }

    # Final sync: ensure ccmirror + node are selected if any variant is active
    if (Any-MirrorVariantSelected) { $Selected.ccmirror = $true; $Selected.node = $true }

    Write-Host ""
}

# ─────────────────────────────────────────────────────────────────────────────
# CC-MIRROR VARIANTS TUI
# ─────────────────────────────────────────────────────────────────────────────
function script:Draw-MirrorBody([object[]]$mirrorVariants, [int]$cursor) {
    $idx = 0
    foreach ($v in $mirrorVariants) {
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
    bEmpty
}

function Invoke-MirrorMenu {
    # Skip if -Mirror flag already provided, not Custom mode, or non-interactive
    if (($Mode -ne "Custom") -or $Yes -or $DryRun -or (-not [string]::IsNullOrWhiteSpace($Mirror))) {
        return
    }

    $mirrorVariants = @($MirrorVariantDefs)
    if ($mirrorVariants.Count -eq 0) { return }

    $canInteract = $false
    try { $canInteract = [Environment]::UserInteractive -and ($null -ne $Host.UI.RawUI) } catch {}
    if (-not $canInteract) { return }

    Write-Host ""
    bTop "CC-MIRROR VARIANTS"
    bEmpty
    bRow "  cc-mirror creates additional Claude Code variant commands." DarkCyan
    bRow "  These variants do not replace the real AI CLI binaries." DarkGray
    bRow "  cc-mirror and Node.js will be installed automatically." DarkGray
    bEmpty
    bLabel "SELECT CC-MIRROR VARIANTS"
    bEmpty

    $menuTop = [Console]::CursorTop
    $cursor  = 0
    Draw-MirrorBody $mirrorVariants $cursor
    bBot

    Write-Host ""
    colD "  Navigate " -n; colY "[UP] [DOWN]" -n
    colD "   Toggle " -n;  colY "[SPACE]" -n
    colD "   Enable All " -n; colY "[A]" -n
    colD "   Skip All " -n; colY "[S]" -n
    colD "   Confirm " -n; colY "[ENTER]"
    Write-Host ""

    $done = $false
    while (-not $done) {
        $key = $null
        try { $key = [Console]::ReadKey($true) } catch { $done = $true; break }

        $needRedraw = $true
        $kch = [char]::ToLower($key.KeyChar)

        if ($key.Key -eq [ConsoleKey]::UpArrow) {
            if ($cursor -gt 0) { $cursor-- }
        } elseif ($key.Key -eq [ConsoleKey]::DownArrow) {
            if ($cursor -lt ($mirrorVariants.Count - 1)) { $cursor++ }
        } elseif ($key.Key -eq [ConsoleKey]::Spacebar) {
            $tk = $mirrorVariants[$cursor].Key
            $MirrorSelected[$tk] = -not $MirrorSelected[$tk]
        } elseif ($kch -eq 'a') {
            foreach ($v in $mirrorVariants) { $MirrorSelected[$v.Key] = $true }
        } elseif ($kch -eq 's') {
            Clear-MirrorVariants
            $done = $true; $needRedraw = $false
        } elseif ($key.Key -eq [ConsoleKey]::Enter) {
            $done = $true; $needRedraw = $false
        } else {
            $needRedraw = $false
        }

        if ($needRedraw) {
            try { [Console]::SetCursorPosition(0, $menuTop) } catch {}
            Draw-MirrorBody $mirrorVariants $cursor
        }
    }

    # Finalize: if any mirror is on, ensure cc-mirror + node are selected
    if (Any-MirrorVariantSelected) {
        $Selected.ccmirror = $true
        $Selected.node     = $true
        Write-Host ""
        Write-Info "cc-mirror variants enabled. cc-mirror will be installed."
    } else {
        Write-Host ""
        Write-Info "No cc-mirror variants selected. Direct AI CLIs will still install when selected."
    }
    Write-Host ""
}

# ─────────────────────────────────────────────────────────────────────────────
# PLAN
# ─────────────────────────────────────────────────────────────────────────────
function Show-Plan {
    Write-Host ""
    bTop "INSTALL PLAN"
    bEmpty
    bRow "  Platform  :  Windows" DarkCyan
    bRow "  Mode      :  $Mode" DarkCyan
    bRow "  Target    :  $Target" DarkCyan
    bRow "  Manager   :  winget (bootstrap via Microsoft Store) + npm" DarkCyan
    if ($DryRun) { bRow "  Run Mode  :  DRY-RUN  (no changes will be made)" Yellow }
    bEmpty
    bHRule

    $lastGroup = ""
    foreach ($t in $ToolDefs) {
        if (-not $Selected[$t.Key]) { continue }
        if ($t.Group -ne $lastGroup) {
            $lastGroup = $t.Group
            $grpLbl = switch ($t.Group) {
                "prereq" { "  SYSTEM PREREQUISITES" }
                "base"   { "  BASE DEPENDENCIES" }
                "dev"    { "  DEV TOOLS" }
                "ai"     { "  AI CLI TOOLS" }
                default  { "  " + $t.Group.ToUpper() }
            }
            bRow $grpLbl Cyan
        }
        bRow "    [>] $($t.Name)" White
    }

    if (Any-MirrorVariantSelected) {
        bRow "  CC-MIRROR VARIANTS" Cyan
        foreach ($v in $MirrorVariantDefs) {
            if (-not $MirrorSelected[$v.Key]) { continue }
            bRow "    [>] $($v.Command)  (provider: $($v.Provider))" White
        }
    }

    bEmpty
    bBot
}

# ─────────────────────────────────────────────────────────────────────────────
# CONFIRM
# ─────────────────────────────────────────────────────────────────────────────
function Invoke-Confirm {
    if ($Yes -or $DryRun) { return }
    Write-Host ""
    colW "  Proceed with installation? " -n; colY "[y/N] " -n
    $ans = Read-Host
    if ($ans -notin @("y", "Y", "yes", "YES")) {
        colY "  Installation cancelled."; exit 0
    }
}

# ─────────────────────────────────────────────────────────────────────────────
# RESULT TRACKING
# ─────────────────────────────────────────────────────────────────────────────
function Set-Result([string]$name, [string]$value, [string]$status) {
    $ResultsMap[$name] = [pscustomobject]@{ Name=$name; Value=$value; Status=$status }
}

function script:Get-ToolVersion([string]$cmd) {
    $v = ""
    try { $v = (Invoke-Expression "$cmd 2>`$null" | Select-Object -First 1) } catch {}
    if ([string]::IsNullOrWhiteSpace($v)) { $v = "detected" }
    return $v
}

# ─────────────────────────────────────────────────────────────────────────────
# SECTION HEADER
# ─────────────────────────────────────────────────────────────────────────────
function Show-Phase([string]$title) {
    Write-Host ""
    $line   = "=" * ($BoxW - 4)
    $padded = ("  " + $title).PadRight($BoxW - 4)
    colC "  +$line+"
    colC "  |" -n; colW $padded -n; colC "|"
    colC "  +$line+"
    Write-Host ""
}

# ─────────────────────────────────────────────────────────────────────────────
# WINGET INSTALLER
# ─────────────────────────────────────────────────────────────────────────────
function Install-WinPkg([string]$label, [string]$binary, [string]$pkgId) {
    Write-Host ""
    bTop "INSTALL: $label"
    bEmpty

    if (Test-Cmd $binary) {
        $ver = Get-ToolVersion "$binary --version"
        bRow "  Status   :  Already installed" Green
        bRow "  Version  :  $ver" DarkGray
        bRow "  Action   :  Skipping" DarkGray
        bEmpty; bBot
        Set-Result $label $ver "skipped"
        return
    }

    $wingetExe = Get-WingetExe
    $useTask   = ($null -eq $wingetExe) -and (Test-IsAdmin) -and (Test-WingetInstalled)

    if (($null -eq $wingetExe) -and (-not $useTask)) {
        Write-Warn "$label skipped - winget not available"
        Set-Result $label "skipped (no winget)" "failed"
        bEmpty; bBot
        return
    }

    $method = if ($useTask) { "winget (via limited-privilege task)" } else { "winget" }
    bRow "  Package  :  $pkgId" DarkCyan
    bRow "  Manager  :  $method" DarkGray
    bEmpty; bBot

    $cmd = "winget install --id $pkgId --exact --accept-source-agreements --accept-package-agreements"
    if ($DryRun) {
        Write-Info "Dry-run: $cmd"
        Set-Result $label "planned" "planned"
        return
    }

    Write-Step "Running winget for $label..."
    $exitCode = 0
    if ($useTask) {
        $exitCode = Invoke-WingetTask $pkgId
    } else {
        & $wingetExe install --id $pkgId --exact --accept-source-agreements --accept-package-agreements --verbose-logs --disable-interactivity
        $exitCode = $LASTEXITCODE
    }

    # 0         = success
    # 3010      = success, reboot required
    # -1978335189 (0x8A15002B) = winget "package already installed" HRESULT
    $knownOk = @(0, 3010, -1978335189, -1978335215)
    $ok = ($exitCode -in $knownOk) -or (Test-Cmd $binary)

    if ($ok) {
        $note = if ($exitCode -eq 3010) { " (reboot required)" } else { "" }
        Write-OK "$label installed$note"
        Set-Result $label "installed" "ok"
    } else {
        Write-Warn "$label - winget exit code: $exitCode  (0x$('{0:X}' -f $exitCode))"
        Set-Result $label "install failed" "failed"
    }
}

# ─────────────────────────────────────────────────────────────────────────────
# NPM INSTALLER
# ─────────────────────────────────────────────────────────────────────────────
function Install-NpmPkg([string]$label, [string]$binary, [string]$pkg, [string]$verifyCmd) {
    Write-Host ""
    bTop "INSTALL: $label"
    bEmpty

    if (Test-Cmd $binary) {
        $ver = Get-ToolVersion $verifyCmd
        bRow "  Status   :  Already installed" Green
        bRow "  Version  :  $ver" DarkGray
        bRow "  Action   :  Skipping" DarkGray
        bEmpty; bBot
        Set-Result $label $ver "skipped"
        return
    }

    bRow "  Package  :  $pkg" DarkCyan
    bRow "  Manager  :  npm (global)" DarkGray
    bEmpty; bBot

    $cmd = "npm install -g $pkg"
    if ($DryRun) {
        Write-Info "Dry-run: $cmd"
        Set-Result $label "planned" "planned"
        return
    }

    Write-Step "Running npm install for $label..."
    Invoke-Expression $cmd
    $ok = ($LASTEXITCODE -eq 0)

    if ($ok) {
        Write-OK "$label installed"
        Set-Result $label "installed" "ok"
    } else {
        Write-Warn "$label - npm returned code $LASTEXITCODE"
        Set-Result $label "install failed" "failed"
    }
}

# ─────────────────────────────────────────────────────────────────────────────
# BASE DEPENDENCIES
# ─────────────────────────────────────────────────────────────────────────────
function Install-BaseDeps {
    Show-Phase "BASE DEPENDENCIES"
    Ensure-Winget
    foreach ($t in $ToolDefs) {
        if (($t.Group -eq "base") -and $Selected[$t.Key]) {
            Install-WinPkg $t.Name $t.Binary $t.WinPkg
        }
    }
}

# ─────────────────────────────────────────────────────────────────────────────
# DEV TOOLS
# ─────────────────────────────────────────────────────────────────────────────
function Install-DevTools {
    $anyDev = $false
    foreach ($t in $ToolDefs) {
        if (($t.Group -eq "dev") -and $Selected[$t.Key]) { $anyDev = $true; break }
    }
    if (-not $anyDev) { return }

    Show-Phase "DEV TOOLS"
    foreach ($t in $ToolDefs) {
        if (($t.Group -eq "dev") -and $Selected[$t.Key]) {
            Install-WinPkg $t.Name $t.Binary $t.WinPkg
        }
    }
}

# ─────────────────────────────────────────────────────────────────────────────
# PATH REFRESH
# ─────────────────────────────────────────────────────────────────────────────
function Update-SessionPath {
    Write-Host ""
    $machine  = [Environment]::GetEnvironmentVariable("Path", "Machine")
    $user     = [Environment]::GetEnvironmentVariable("Path", "User")
    $env:Path = "$machine;$user"
    Write-OK "Session PATH refreshed"
}

# ─────────────────────────────────────────────────────────────────────────────
# CC-MIRROR VARIANT
# ─────────────────────────────────────────────────────────────────────────────
function Install-MirrorVariant([string]$label, [string]$name, [string]$provider) {
    Write-Host ""
    bTop "INSTALL (mirror): $label"
    bEmpty
    bRow "  Provider :  $provider" DarkCyan
    bRow "  Name     :  $name" DarkGray
    bEmpty; bBot

    $cmd = "npx cc-mirror quick --provider $provider --name $name --no-tweak"
    if ($DryRun) {
        Write-Info "Dry-run: $cmd"
        Set-Result $label "planned (mirror)" "planned"
        return
    }

    Write-Step "Configuring $label via cc-mirror..."
    Invoke-Expression $cmd
    if ($LASTEXITCODE -eq 0) {
        Write-OK "$label configured via cc-mirror"
        Set-Result $label "via cc-mirror" "ok"
    } else {
        Write-Warn "$label mirror setup failed (code $LASTEXITCODE)"
        Set-Result $label "mirror failed" "failed"
    }
}

# ─────────────────────────────────────────────────────────────────────────────
# AI CLI TOOLS
# ─────────────────────────────────────────────────────────────────────────────
function Install-AiTools {
    $anyAi = $false
    foreach ($t in $ToolDefs) {
        if ($t.Group -ne "ai") { continue }
        if ($Selected[$t.Key]) { $anyAi = $true; break }
    }
    if ((-not $anyAi) -and (-not (Any-MirrorVariantSelected))) { return }

    Show-Phase "AI CLI TOOLS"

    if (-not (Test-Cmd "npm")) {
        Write-Warn "npm not available - skipping all AI CLI installs"
        Set-Result "AI CLI tools" "npm unavailable" "skipped"
        return
    }

    foreach ($t in $ToolDefs) {
        if ($t.Group -ne "ai") { continue }
        if (-not $Selected[$t.Key]) { continue }
        Install-NpmPkg $t.Name $t.Binary $t.NpmPkg $t.Verify
    }

    Ensure-NpmGlobalPath
    Update-SessionPath

    if (Any-MirrorVariantSelected) {
        foreach ($v in $MirrorVariantDefs) {
            if (-not $MirrorSelected[$v.Key]) { continue }
            Install-MirrorVariant "$($v.Name) (cc-mirror)" $v.Command $v.Provider
        }
    }
}

# ─────────────────────────────────────────────────────────────────────────────
# VERIFICATION
# ─────────────────────────────────────────────────────────────────────────────
function Invoke-Verify {
    Show-Phase "VERIFICATION"

    foreach ($t in $ToolDefs) {
        if (-not $Selected[$t.Key]) { continue }
        if ([string]::IsNullOrWhiteSpace($t.Binary)) { continue }
        if (Test-Cmd $t.Binary) {
            $ver = Get-ToolVersion $t.Verify
            Set-Result $t.Name $ver "verified"
            Write-OK ("$($t.Name)".PadRight(22) + " $ver")
        } else {
            Set-Result $t.Name "not found" "missing"
            Write-Warn ("$($t.Name)".PadRight(22) + " not found in PATH")
        }
    }

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
}

# ─────────────────────────────────────────────────────────────────────────────
# SUMMARY
# ─────────────────────────────────────────────────────────────────────────────
function Show-Summary {
    Write-Host ""
    bTop "INSTALLATION SUMMARY"
    bEmpty

    $c1 = 20; $c2 = 20; $c3 = 14
    $hdr = "  " + "Tool".PadRight($c1) + " " + "Version".PadRight($c2) + " " + "Status"
    bRow $hdr Cyan
    bRow ("  " + ("-" * $c1) + " " + ("-" * $c2) + " " + ("-" * $c3)) DarkGray

    $orderedResults = foreach ($t in $ToolDefs) {
        if ($ResultsMap.ContainsKey($t.Name)) { $ResultsMap[$t.Name] }
    }
    $orderedResults += foreach ($v in $MirrorVariantDefs) {
        $key = "$($v.Name) (cc-mirror)"
        if ($ResultsMap.ContainsKey($key)) { $ResultsMap[$key] }
    }

    foreach ($r in $orderedResults) {
        $n = $r.Name;  if ($n.Length -gt $c1) { $n = $n.Substring(0, $c1 - 2) + ".." }
        $v = $r.Value; if ($v.Length -gt $c2) { $v = $v.Substring(0, $c2 - 2) + ".." }

        $sym = switch ($r.Status) {
            "verified"  { "[+]" }; "ok"      { "[+]" }; "installed" { "[+]" }
            "skipped"   { "[=]" }; "planned" { "[~]" }
            "failed"    { "[X]" }; "missing" { "[X]" }
            default     { "[ ]" }
        }
        $scol = switch ($r.Status) {
            "verified"  { [ConsoleColor]::Green }
            "ok"        { [ConsoleColor]::Green }
            "installed" { [ConsoleColor]::Green }
            "skipped"   { [ConsoleColor]::DarkCyan }
            "planned"   { [ConsoleColor]::Yellow }
            "failed"    { [ConsoleColor]::Red }
            "missing"   { [ConsoleColor]::Red }
            default     { [ConsoleColor]::White }
        }

        $statusStr = "$sym $($r.Status)"
        $rowBody   = "  " + $n.PadRight($c1) + " " + $v.PadRight($c2) + " "
        $padRight  = [Math]::Max(0, $InnerW - $rowBody.Length - $statusStr.Length)

        colD "  |" -n
        colW " $rowBody" -n
        colPrint $statusStr $scol -NoNl
        colD (" " * $padRight + " |")
    }

    bEmpty
    bBot
    Write-Host ""

    $failed  = @($ResultsMap.Values | Where-Object { ($_.Status -eq "failed") -or ($_.Status -eq "missing") }).Count
    $success = @($ResultsMap.Values | Where-Object { ($_.Status -eq "verified") -or ($_.Status -eq "ok") -or ($_.Status -eq "installed") }).Count
    $total   = $ResultsMap.Count

    if ($failed -gt 0) {
        Write-Warn "$failed tool(s) had issues.  $success / $total succeeded."
    } else {
        Write-OK "Setup complete!  All $total tool(s) are ready to use."
    }
    Write-Host ""
}

# ─────────────────────────────────────────────────────────────────────────────
# ENVIRONMENT SUMMARY
# ─────────────────────────────────────────────────────────────────────────────
function Show-Environment {
    # Pick up tools installed after the last PATH refresh
    $machine  = [Environment]::GetEnvironmentVariable("Path", "Machine")
    $user     = [Environment]::GetEnvironmentVariable("Path", "User")
    $env:Path = "$machine;$user"

    Write-Host ""
    bTop "ENVIRONMENT"
    bEmpty

    # ── Runtimes ──────────────────────────────────────────────────────────────
    bLabel "RUNTIMES"
    bEmpty
    $runtimes = @(
        [pscustomobject]@{ Name="Node.js"; Bin="node";   Cmd="node --version"   }
        [pscustomobject]@{ Name="npm";     Bin="npm";    Cmd="npm --version"    }
        [pscustomobject]@{ Name="Python";  Bin="python"; Cmd="python --version" }
        [pscustomobject]@{ Name="pip";     Bin="pip";    Cmd="pip --version"    }
        [pscustomobject]@{ Name="Git";     Bin="git";    Cmd="git --version"    }
    )
    $foundAny = $false
    foreach ($r in $runtimes) {
        if (Test-Cmd $r.Bin) {
            $ver = Get-ToolVersion $r.Cmd
            bRow ("    " + $r.Name.PadRight(12) + " " + $ver) White
            $foundAny = $true
        }
    }
    if (-not $foundAny) { bRow "    (none detected)" DarkGray }
    bEmpty

    # ── AI CLI Tools ──────────────────────────────────────────────────────────
    bLabel "AI CLI TOOLS"
    bEmpty
    $anyAi = $false
    foreach ($t in $ToolDefs) {
        if ($t.Group -ne "ai") { continue }
        if (-not $Selected[$t.Key]) { continue }
        $anyAi = $true

        $n = $t.Name.PadRight(20)
        if (-not [string]::IsNullOrWhiteSpace($t.Binary)) {
            if (Test-Cmd $t.Binary) {
                $ver = Get-ToolVersion $t.Verify
                bRow "    $n $ver" Green
            } else {
                bRow "    $n [not in PATH - restart terminal]" Yellow
            }
        }
    }
    if (-not $anyAi) { bRow "    (none selected)" DarkGray }
    bEmpty

    # ── cc-mirror variants ────────────────────────────────────────────────────
    if (Any-MirrorVariantSelected) {
        bLabel "CC-MIRROR VARIANTS"
        bEmpty
        foreach ($v in $MirrorVariantDefs) {
            if (-not $MirrorSelected[$v.Key]) { continue }
            bRow ("    " + $v.Command.PadRight(20) + " provider: $($v.Provider)") Magenta
        }
        bEmpty
    }

    bBot
    Write-Host ""
}

# ─────────────────────────────────────────────────────────────────────────────
# WSL HANDOFF
# ─────────────────────────────────────────────────────────────────────────────
function Invoke-WSL {
    Show-Phase "WSL HANDOFF"

    if (-not (Test-Cmd "wsl.exe")) {
        Write-Fatal "wsl.exe not found. Enable WSL with: wsl --install"
    }

    $scriptUrl = "https://raw.githubusercontent.com/your-repo/bootstrap/main/install.sh"
    $flags     = "--mode $($Mode.ToLowerInvariant())"
    if ($Yes)     { $flags += " --yes" }
    if ($DryRun)  { $flags += " --dry-run" }
    if ($NoColor) { $flags += " --no-color" }
    if (-not [string]::IsNullOrWhiteSpace($Only))   { $flags += " --only $Only" }
    if (-not [string]::IsNullOrWhiteSpace($Skip))   { $flags += " --skip $Skip" }
    if (-not [string]::IsNullOrWhiteSpace($Mirror)) { $flags += " --mirror $Mirror" }

    $wslCmd = "curl -fsSL $scriptUrl | bash -s -- $flags"
    bTop "WSL COMMAND"
    bEmpty
    bRow "  $wslCmd" DarkGray
    bEmpty; bBot
    Write-Host ""

    if (-not $DryRun) {
        wsl bash -lc $wslCmd
    } else {
        Write-Info "Dry-run: would execute above command in WSL"
    }
}

# ─────────────────────────────────────────────────────────────────────────────
# HELP
# ─────────────────────────────────────────────────────────────────────────────
function Show-Usage {
    Show-Banner
    bTop "USAGE"
    bEmpty
    bRow "  powershell -ExecutionPolicy Bypass -File .\install.ps1 [options]" DarkCyan
    bEmpty
    bLabel "OPTIONS"
    bRow "  -Yes                   Skip all confirmation prompts" White
    bRow "  -DryRun                Preview actions without installing" White
    bRow "  -NoColor               Disable colored output" White
    bRow "  -Mode  Quick|Custom|Mirror   Installation mode  (default: Quick)" White
    bRow "  -Target Native|WSL           Target platform    (default: Native)" White
    bRow "  -Only  <list>          Comma-separated tools to install" White
    bRow "  -Skip  <list>          Comma-separated tools to skip" White
    bRow "  -Mirror <list>         Create cc-mirror variants: claude,minimax,kimi" White
    bRow "  -Help                  Show this message" White
    bEmpty
    bLabel "MODES"
    bRow "  Quick   Install the recommended default toolset" White
    bRow "  Custom  Interactive selection menu with arrow-key navigation" White
    bRow "  Mirror  Direct Codex plus supported cc-mirror variants" White
    bEmpty
    bLabel "TOOL KEYS  (for -Only / -Skip)"
    bRow "  prereq, base, dev, ai, all" DarkCyan
    bRow "  msstore, winget, git, python, node, vscode, terminal, 7zip" DarkCyan
    bRow "  claude, ccmirror, minimax, codex, gemini" DarkCyan
    bEmpty
    bLabel "EXAMPLES"
    bRow "  .\install.ps1" White
    bRow "  .\install.ps1 -Mode Custom" White
    bRow "  .\install.ps1 -Only claude,node -Yes" White
    bRow "  .\install.ps1 -Skip 7zip,terminal -DryRun" White
    bRow "  .\install.ps1 -Mirror claude,minimax,kimi" White
    bEmpty
    bBot
    Write-Host ""
}

# ─────────────────────────────────────────────────────────────────────────────
# SELECTION LOGIC
# ─────────────────────────────────────────────────────────────────────────────
function script:Normalize([string]$t) {
    return ($t.ToLowerInvariant() -replace "[ _-]", "")
}

function script:Has-ExplicitPrereqFlag([string]$list) {
    if ([string]::IsNullOrWhiteSpace($list)) { return $false }
    foreach ($item in $list.Split(",", [System.StringSplitOptions]::RemoveEmptyEntries)) {
        switch (Normalize $item.Trim()) {
            "msstore"            { return $true }
            "microsoftstore"      { return $true }
            "winget"             { return $true }
            "desktopappinstaller" { return $true }
            "prereq"             { return $true }
        }
    }
    return $false
}

function script:Clear-Selection {
    foreach ($k in @($Selected.Keys)) { $Selected[$k] = $false }
    Clear-MirrorVariants
}

function Set-ToolSel([string]$tool, [bool]$val) {
    $tok = Normalize $tool
    switch ($tok) {
        "msstore"            { $Selected.msstore      = $val }
        "microsoftstore"      { $Selected.msstore      = $val }
        "winget"             { $Selected.winget       = $val }
        "desktopappinstaller" { $Selected.winget       = $val }
        "prereq"             { $Selected.msstore = $val; $Selected.winget = $val }
        "git"           { $Selected.git      = $val }
        "python"        { $Selected.python   = $val }
        "pythonpip"     { $Selected.python   = $val }
        "pip"           { $Selected.python   = $val }
        "node"          { $Selected.node     = $val }
        "nodenpm"       { $Selected.node     = $val }
        "npm"           { $Selected.node     = $val }
        "vscode"        { $Selected.vscode   = $val }
        "code"          { $Selected.vscode   = $val }
        "terminal"      { $Selected.terminal = $val }
        "windowsterminal" { $Selected.terminal = $val }
        "7zip"          { $Selected["7zip"]  = $val }
        "sevenzip"      { $Selected["7zip"]  = $val }
        "claude"        { $Selected.claude   = $val }
        "claudecode"    { $Selected.claude   = $val }
        "ccmirror"      { $Selected.ccmirror = $val; if (-not $val) { Clear-MirrorVariants } }
        "minimax"       { $Selected.minimax  = $val }
        "mmx"           { $Selected.minimax  = $val }
        "codex"         { $Selected.codex    = $val }
        "openaicodex"   { $Selected.codex    = $val }
        "gemini"        { $Selected.gemini   = $val }
        "geminicli"     { $Selected.gemini   = $val }
        "base"          { $Selected.git=$val; $Selected.python=$val; $Selected.node=$val }
        "dev"           { $Selected.vscode=$val; $Selected.terminal=$val; $Selected["7zip"]=$val }
        "ai"            { $Selected.claude=$val; $Selected.minimax=$val; $Selected.codex=$val; $Selected.gemini=$val }
        "all"           { foreach ($k in @($Selected.Keys)) { $Selected[$k] = $val }; foreach ($k in @($MirrorSelected.Keys)) { $MirrorSelected[$k] = $val } }
        ""              {}
        default         { Write-Warn "Unknown tool selector: $tool" }
    }
}

function Apply-List([string]$list, [bool]$val) {
    if ([string]::IsNullOrWhiteSpace($list)) { return }
    foreach ($item in $list.Split(",", [System.StringSplitOptions]::RemoveEmptyEntries)) {
        Set-ToolSel $item.Trim() $val
    }
}

function Apply-Mirror {
    if ([string]::IsNullOrWhiteSpace($Mirror)) { return }
    foreach ($item in $Mirror.Split(",", [System.StringSplitOptions]::RemoveEmptyEntries)) {
        $tok = Normalize $item.Trim()
        switch ($tok) {
            "claude"      { Enable-MirrorVariant "mclaude" }
            "claudecode"  { Enable-MirrorVariant "mclaude" }
            "mclaude"     { Enable-MirrorVariant "mclaude" }
            "mirror"      { Enable-MirrorVariant "mclaude" }
            "minimax"     { Enable-MirrorVariant "minimax" }
            "mmx"         { Enable-MirrorVariant "minimax" }
            "kimi"        { Enable-MirrorVariant "kimi" }
            "kimiclaude"  { Enable-MirrorVariant "kimi" }
            "codex"       { Write-Warn "Codex is direct-only and is not supported as a cc-mirror variant" }
            "openaicodex" { Write-Warn "Codex is direct-only and is not supported as a cc-mirror variant" }
            default       { Write-Warn "Unknown mirror selector: $item" }
        }
    }
}

function Configure-Selection {
    switch ($Mode) {
        "Quick" {
            $Selected.git=$true;  $Selected.python=$true;  $Selected.node=$true
            $Selected.vscode=$false; $Selected.terminal=$false; $Selected["7zip"]=$false
            $Selected.claude=$false; $Selected.ccmirror=$true
            $Selected.minimax=$false; $Selected.codex=$true; $Selected.gemini=$true
            $MirrorSelected.mclaude=$false; $MirrorSelected.minimax=$true; $MirrorSelected.kimi=$false
        }
        "Custom" {
            $Selected.git=$true;  $Selected.python=$true;  $Selected.node=$true
            $Selected.vscode=$false; $Selected.terminal=$false; $Selected["7zip"]=$false
            $Selected.claude=$false; $Selected.ccmirror=$true
            $Selected.minimax=$false; $Selected.codex=$true; $Selected.gemini=$true
            $MirrorSelected.mclaude=$false; $MirrorSelected.minimax=$true; $MirrorSelected.kimi=$false
        }
        "Mirror" {
            $Selected.git=$false; $Selected.python=$false; $Selected.node=$true
            $Selected.vscode=$false; $Selected.terminal=$false; $Selected["7zip"]=$false
            $Selected.claude=$false; $Selected.ccmirror=$true
            $Selected.minimax=$false; $Selected.codex=$true; $Selected.gemini=$false
            $MirrorSelected.mclaude=$false; $MirrorSelected.minimax=$true; $MirrorSelected.kimi=$false
        }
    }

    if (-not [string]::IsNullOrWhiteSpace($Only)) {
        Clear-Selection
        Apply-List $Only $true
    }
    Apply-List $Skip $false
    Apply-Mirror

    if (Any-MirrorVariantSelected) {
        $Selected.ccmirror = $true
        $Selected.node     = $true
    }

    # Auto-select system prerequisites when winget is not available
    $hasExplicitPrereq = (Has-ExplicitPrereqFlag $Only) -or (Has-ExplicitPrereqFlag $Skip)
    if (-not $hasExplicitPrereq) {
        $wingetPresent    = Test-Cmd "winget"
        $Selected.msstore  = -not $wingetPresent
        $Selected.winget   = -not $wingetPresent
    }
}

# ─────────────────────────────────────────────────────────────────────────────
# ENTRYPOINT
# ─────────────────────────────────────────────────────────────────────────────
if ($Help) { Show-Usage; exit 0 }

Ensure-ExecutionPolicy
Configure-Selection
Show-Banner
Show-InfoBar
Invoke-InteractiveMenu
Show-Plan
Invoke-Confirm

if ($Target -eq "WSL") {
    Invoke-WSL
    exit 0
}

Install-Prerequisites
Install-BaseDeps
Install-DevTools
Update-SessionPath
Install-AiTools
Invoke-Verify
Show-Summary
Show-Environment

if (-not $DryRun) {
    $canPause = $false
    try { $canPause = [Environment]::UserInteractive -and ($null -ne $Host.UI.RawUI) } catch {}
    if ($canPause) {
        Write-Host ""
        colW "  Press any key to exit..." -n
        try { $null = [Console]::ReadKey($true) } catch { Read-Host }
        Write-Host ""
    }
}
