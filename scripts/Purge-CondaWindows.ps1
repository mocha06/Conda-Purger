# scripts/Purge-CondaWindows.ps1
#Requires -Version 5.1
[CmdletBinding()]
param(
    [switch]$Yes,                 # actually modify the system (default is dry-run)
    [switch]$Force,               # continue on non-fatal errors
    [switch]$Quiet,               # minimal output
    [switch]$Json,                # print JSON summary at the end
    [switch]$IncludeForge,        # also remove mambaforge/miniforge paths
    [switch]$IncludeMicromamba,   # also remove micromamba paths
    [switch]$System               # also clean Machine PATH (requires admin)
)

# =============================================================================
# CONFIGURATION
# =============================================================================

# Script settings
$DRY = -not $Yes
$Changes = New-Object System.Collections.Generic.List[object]

# PowerShell profile candidates (user + common)
$Doc = [Environment]::GetFolderPath('MyDocuments')
$ProfileCandidates = @(
    # Standard PS $PROFILE variants (user/machine, all/current host)
    $PROFILE, $PROFILE.CurrentUserAllHosts, $PROFILE.AllUsersCurrentHost, $PROFILE.AllUsersAllHosts,
    # Legacy/common locations
    (Join-Path $Doc 'WindowsPowerShell\Microsoft.PowerShell_profile.ps1'),
    (Join-Path $Doc 'PowerShell\Microsoft.PowerShell_profile.ps1'),
    (Join-Path $Doc 'WindowsPowerShell\profile.ps1'),
    (Join-Path $Doc 'PowerShell\profile.ps1')
) | Where-Object { $_ -and (Test-Path $_ -ErrorAction SilentlyContinue) } | Select-Object -Unique

# Hook patterns to scrub
$HookPatterns = @(
    '^\s*\(&?\s*"\$env:CONDA_EXE"\s+"shell\.powershell"\s+"hook"\)\s*\|\s*Out-String\s*\|\s*Invoke-Expression\s*$',
    '^\s*#\s*>>> conda initialize >>>.*$',
    '^\s*#\s*<<< conda initialize <<<.*$',
    '^\s*Import-Module\s+.*Conda\.psm1.*$',
    '^\s*\$CondaPath\s*=.*$',
    '^\s*conda\s+init.*$'
)

# Directory paths to remove
$UserHome = $HOME
$ProgramData = $env:ProgramData

$CondaDirectories = @(
    (Join-Path $UserHome 'Anaconda3'),
    (Join-Path $UserHome 'Miniconda3'),
    (Join-Path $UserHome '.conda'),
    (Join-Path $UserHome '.condarc'),
    (Join-Path $UserHome '.continuum'),
    (Join-Path $ProgramData 'Anaconda3'),
    (Join-Path $ProgramData 'Miniconda3')
)

$ForgeDirectories = @(
    (Join-Path $UserHome 'mambaforge'),
    (Join-Path $UserHome 'miniforge3')
)

$MicromambaDirectories = @(
    (Join-Path $UserHome 'micromamba')
)

# Add LOCALAPPDATA micromamba if available
if ($env:LOCALAPPDATA) {
    $MicromambaDirectories += (Join-Path $env:LOCALAPPDATA 'micromamba')
}

# =============================================================================
# UTILITY FUNCTIONS
# =============================================================================

function Say {
    param([string]$Message)
    if (-not $Quiet) {
        Write-Host $Message
    }
}

function Add-JsonRecord {
    param([object]$Record)
    if ($Json) {
        [void]$Changes.Add($Record)
    }
}

function Show-MatchPreview {
    param(
        [string]$Text,
        [string[]]$Patterns,
        [int]$Max = 6
    )
    $shown = 0
    foreach ($rx in $Patterns) {
        $ms = [regex]::Matches($Text, $rx, 'IgnoreCase,Multiline')
        foreach ($m in $ms) {
            if ($shown -lt $Max) {
                Say ("   " + $m.Value.Trim())
                $shown++
            }
        }
    }
    if ($shown -eq 0) {
        Say "   (no explicit hook lines matched; removing known blocks if present)"
    }
    if (($shown -ge $Max)) {
        Say "   ..."
    }
}

function Write-Success {
    param([string]$Message)
    Say "   ✅ $Message"
}

function Warn {
    param([string]$Message)
    Say "   ⚠️ $Message"
}

function Write-Info {
    param([string]$Message)
    Say "📄 $Message"
}

function Write-Section {
    param([string]$Message)
    Say "🗑 $Message"
}

function Write-PathSection {
    param([string]$Message)
    Say "🛣 $Message"
}

# =============================================================================
# PROFILE OPERATIONS
# =============================================================================

function Backup-EditProfile {
    param([string]$Path)
    
    Write-Info "Checking $Path..."
    try {
        $text = Get-Content -Raw -Encoding UTF8 -ErrorAction Stop $Path
    }
    catch {
        if (-not $Force) { throw }
        else { Say "   ❌ Read error: $_"; return }
    }

    $orig = $text
    $hasMatch = $HookPatterns | ForEach-Object {
        if ([regex]::IsMatch($text, $_, 'IgnoreCase,Multiline')) { $true }
    } | Where-Object { $_ } | Select-Object -First 1

    if ($hasMatch) {
        Warn "Found conda hooks:"
        Show-MatchPreview $text $HookPatterns 6

        # scrub all patterns
        foreach ($rx in $HookPatterns) {
            $text = [regex]::Replace($text, $rx, '', 'IgnoreCase,Multiline')
        }

        if (-not $DRY) {
            $bak = "$Path.bak"
            try {
                Copy-Item -Force -Path $Path -Destination $bak
                Set-Content -Encoding UTF8 -Path $Path -Value $text
                Write-Success "Cleaned (backup: $bak)"
                Add-JsonRecord ([pscustomobject]@{ type = "profile"; action = "cleaned"; file = $Path; backup = $bak })
            }
            catch {
                if (-not $Force) { throw }
                else { Say "   ❌ Write error: $_" }
            }
        }
        else {
            Say "   (dry) Would clean hooks and save backup: $Path.bak"
            Add-JsonRecord ([pscustomobject]@{ type = "profile"; action = "would-clean"; file = $Path })
        }
    }
    else {
        Write-Success "No conda hooks"
    }
}

function Clean-PowerShellProfiles {
    Write-Section "PowerShell profiles"
    
    if ($ProfileCandidates.Count -gt 0) {
        foreach ($f in $ProfileCandidates) {
            Backup-EditProfile $f
        }
    }
    else {
        Write-Info "No PowerShell profile files found"
    }
}

# =============================================================================
# PATH OPERATIONS
# =============================================================================

function Clean-PathScope {
    param([string]$Scope)
    
    try {
        $current = [Environment]::GetEnvironmentVariable('Path', $Scope)
    }
    catch {
        if (-not $Force) { throw }
        else { Say "   ❌ Could not read $Scope PATH: $_"; return }
    }

    if ([string]::IsNullOrEmpty($current)) {
        Say "   ℹ️ No $Scope PATH"
        return
    }

    $parts = $current -split ';' | Where-Object { $_ -ne '' }
    $toRemove = [System.Collections.Generic.List[string]]::new()

    foreach ($p in $parts) {
        if ($p -match '(?i)(\\|/)(anaconda3|miniconda3|conda)(\\|/)?') {
            [void]$toRemove.Add($p)
            continue
        }
        if ($IncludeForge -and ($p -match '(?i)(\\|/)(mambaforge|miniforge3)(\\|/)?')) {
            [void]$toRemove.Add($p)
            continue
        }
        if ($IncludeMicromamba -and ($p -match '(?i)micromamba')) {
            [void]$toRemove.Add($p)
            continue
        }
    }

    $toRemove = $toRemove | Select-Object -Unique
    if ($toRemove.Count -eq 0) {
        Write-Success "No $Scope PATH entries to remove"
        return
    }

    Warn "Removing from $Scope PATH:"
    $toRemove | ForEach-Object { Say ("   " + $_) }

    $new = ($parts | Where-Object { $toRemove -notcontains $_ }) -join ';'
    if (-not $DRY) {
        try {
            [Environment]::SetEnvironmentVariable('Path', $new, $Scope)
            Write-Success "Updated $Scope PATH"
            Add-JsonRecord ([pscustomobject]@{ type = "path"; scope = $Scope; action = "updated"; removed = $toRemove })
        }
        catch {
            if (-not $Force) { throw }
            else { Say "   ❌ Failed to update $Scope PATH: $_" }
        }
    }
    else {
        Say "   (dry) Would update $Scope PATH"
        Add-JsonRecord ([pscustomobject]@{ type = "path"; scope = $Scope; action = "would-update"; removed = $toRemove })
    }
}

function Clean-EnvironmentPaths {
    Write-PathSection "Checking PATHs..."
    Clean-PathScope -Scope 'User'
    if ($System) {
        Clean-PathScope -Scope 'Machine'
    }
}

# =============================================================================
# DIRECTORY OPERATIONS
# =============================================================================

function Remove-TargetDirectory {
    param([string]$Directory)
    
    if (Test-Path $Directory) {
        Warn "Removing $Directory"
        if (-not $DRY) {
            try {
                Remove-Item -Recurse -Force -ErrorAction Stop $Directory
                Add-JsonRecord ([pscustomobject]@{ type = "dir"; action = "removed"; path = $Directory })
            }
            catch {
                # ProgramData often needs admin; allow continue with -Force
                if (-not $Force) { throw }
                else { Say "   ❌ Failed (continuing): $_" }
            }
        }
        else {
            Say "   (dry) Would remove $Directory"
            Add-JsonRecord ([pscustomobject]@{ type = "dir"; action = "would-remove"; path = $Directory })
        }
    }
    else {
        Write-Success "Not found: $Directory"
    }
}

function Clean-Directories {
    Write-Section "Directories"
    
    # Build complete list of directories to remove
    $allDirectories = @($CondaDirectories)
    
    if ($IncludeForge) {
        $allDirectories += $ForgeDirectories
    }
    
    if ($IncludeMicromamba) {
        $allDirectories += $MicromambaDirectories
    }
    
    foreach ($d in $allDirectories) {
        Remove-TargetDirectory $d
    }
}

# =============================================================================
# SYSTEM OPERATIONS
# =============================================================================

function Find-InstalledEntries {
    Write-Info "Detecting installed entries..."
    
    try {
        $apps = Get-ItemProperty `
            HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*, `
            HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*, `
            HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\* `
            -ErrorAction SilentlyContinue |
            Where-Object { $_.DisplayName -match '(?i)(Anaconda|Miniconda)\b' }

        if ($apps) {
            Write-Info "Detected installed entries (use Apps & Features or vendor uninstaller if needed):"
            $apps | ForEach-Object { Say ("   " + $_.DisplayName) }
            if ($Json) {
                foreach ($a in $apps) {
                    Add-JsonRecord ([pscustomobject]@{ type = "uninstall-entry"; action = "detected"; name = $a.DisplayName })
                }
            }
        }
        else {
            Write-Success "No Anaconda/Miniconda entries found in registry"
        }
    }
    catch {
        Say "   ❌ Could not check registry: $_"
    }
}

# =============================================================================
# POST-CLEANUP OPERATIONS
# =============================================================================

function Test-CondaAvailability {
    Say "🔎 Post-check:"
    try {
        $cmds = Get-Command conda -All -ErrorAction Stop
        $cmds | ForEach-Object { Say ("   resolves to: " + $_.Source) }
    }
    catch {
        Say "   conda not found in current shell"
    }
}

function Output-JsonSummary {
    if ($Json) {
        $Changes | ConvertTo-Json -Depth 6
    }
}

function Write-CompletionMessage {
    Say "✅ Done. Restart PowerShell/Terminal (or sign out/in) to apply PATH changes."
}

# =============================================================================
# MAIN EXECUTION
# =============================================================================

function Main {
    param([string[]]$Arguments)
    
    Say "🧹 Windows conda cleanup (dry-run=$DRY)"
    
    Clean-PowerShellProfiles
    Clean-EnvironmentPaths
    Clean-Directories
    Find-InstalledEntries
    
    Output-JsonSummary
    Test-CondaAvailability
    Write-CompletionMessage
}

# Execute main function
Main $PSBoundParameters



# From repo root:
# Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass

# Dry run:
# pwsh -File .\scripts\Purge-CondaWindows.ps1

# Real run:
# pwsh -File .\scripts\Purge-CondaWindows.ps1 -Yes -IncludeForge -IncludeMicromamba

# JSON summary:
# pwsh -File .\scripts\Purge-CondaWindows.ps1 -Yes -Json | ConvertFrom-Json | Format-List

