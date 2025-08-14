# tests/windows.ps1
# Safe test for scripts/Purge-CondaWindows.ps1
# Run from repo root (or anywhere): pwsh -NoProfile -File tests/windows.ps1
# Or: powershell -NoProfile -ExecutionPolicy Bypass -File tests/windows.ps1

param(
  [switch]$VerboseLog  # prints captured outputs on success too
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# --- Locate script under test ---
$RepoRoot = Split-Path -Parent $PSCommandPath
if ($RepoRoot -notmatch 'tests$') { $RepoRoot = Split-Path -Parent $RepoRoot }
$Script = Join-Path $RepoRoot 'scripts\Purge-CondaWindows.ps1'
if (-not (Test-Path $Script)) {
  Write-Error "Script not found: $Script"
}

Write-Host "▶ Using script: $Script"

# --- Safety: ensure current user PATH doesn't include conda-like entries ---
$UserPath = [Environment]::GetEnvironmentVariable('Path','User')
$pathHasConda = $false
if ($UserPath) {
  $pathHasConda = $UserPath -match '(?i)(conda|miniconda|anaconda|mambaforge|miniforge|micromamba)'
}
if ($pathHasConda) {
  Write-Warning @"
Skipping test: your *User* PATH contains conda-like entries.
Running the apply phase would require writing to HKCU:\Environment.
Please remove those PATH entries or run this test on a clean CI runner.
"@
  exit 0
}

# --- Sandbox everything else ---
$TmpRoot = New-Item -ItemType Directory -Force -Path ([System.IO.Path]::GetTempPath()) | % FullName
$TmpRoot = Join-Path $TmpRoot ("conda-purge-win-test-" + [guid]::NewGuid().ToString())
New-Item -ItemType Directory -Path $TmpRoot | Out-Null
$cleanup = { if (Test-Path $using:TmpRoot) { Remove-Item -Recurse -Force $using:TmpRoot -ErrorAction SilentlyContinue } }
$null = Register-EngineEvent PowerShell.Exiting -Action $cleanup
$HOME  = Join-Path $TmpRoot 'home'
$BIN   = Join-Path $TmpRoot 'bin'
$PData = Join-Path $TmpRoot 'ProgramData'
$Docs  = Join-Path $TmpRoot 'Documents'

$null = New-Item -ItemType Directory -Force -Path $HOME,$BIN,$PData,$Docs

# Override environment so script only touches sandbox
$env:HOME = $HOME
$env:USERPROFILE = $HOME
$env:ProgramData = $PData

# For $PROFILE path we’ll point to a sandbox profile file
$SandboxProfile = Join-Path $HOME 'WindowsPowerShell\Microsoft.PowerShell_profile.ps1'
$null = New-Item -ItemType Directory -Force (Split-Path $SandboxProfile) | Out-Null

# Seed fake conda hooks in our sandbox profile
$condaHook = @"
# >>> conda initialize >>>
(& "$env:CONDA_EXE" "shell.powershell" "hook") | Out-String | Invoke-Expression
# <<< conda initialize <<<
conda init powershell
"@
$condaHook | Set-Content -Path $SandboxProfile -Encoding UTF8

# Seed sandbox conda-like directories (HOME + ProgramData)
$dirs = @(
  (Join-Path $HOME 'Anaconda3'),
  (Join-Path $HOME 'Miniconda3'),
  (Join-Path $HOME '.conda'),
  (Join-Path $HOME '.condarc'),
  (Join-Path $HOME '.continuum'),
  (Join-Path $PData 'Anaconda3'),
  (Join-Path $PData 'Miniconda3'),
  (Join-Path $HOME 'mambaforge'),
  (Join-Path $HOME 'miniforge3'),
  (Join-Path $HOME 'micromamba')
)
foreach ($d in $dirs) { New-Item -ItemType Directory -Force -Path $d | Out-Null }

# Helper: run script in a new PowerShell so its automatic $PROFILE vars initialize,
# but force $PROFILE to our sandbox file before calling the script.
function Invoke-UnderTest {
  param(
    [string[]]$Args,
    [ref]$OutputText
  )

  $cmd = @"
`$ErrorActionPreference = 'Stop'
# Override automatic variable `$PROFILE for this session
`$PROFILE = '$SandboxProfile'
# Also set commonly used variants to the same path to be safe
try { `$PROFILE = [System.Management.Automation.PSObject].AsPSObject(`$PROFILE) } catch {}
# Call the script
& '$Script' @Args
"@

  $psi = New-Object System.Diagnostics.ProcessStartInfo
  # Prefer pwsh if available
  $pwsh = (Get-Command pwsh -ErrorAction SilentlyContinue)?.Source
  if ($pwsh) { $psi.FileName = $pwsh } else { $psi.FileName = (Get-Command powershell).Source }
  $psi.Arguments = '-NoProfile -ExecutionPolicy Bypass -Command -'
  $psi.RedirectStandardInput  = $true
  $psi.RedirectStandardOutput = $true
  $psi.RedirectStandardError  = $true
  $psi.UseShellExecute = $false
  $proc = New-Object System.Diagnostics.Process
  $proc.StartInfo = $psi
  $null = $proc.Start()
  $sw = $proc.StandardInput
  $sw.WriteLine($cmd)
  $sw.Close()
  $stdout = $proc.StandardOutput.ReadToEnd()
  $stderr = $proc.StandardError.ReadToEnd()
  $proc.WaitForExit()
  $OutputText.Value = $stdout + $stderr
  return $proc.ExitCode
}

function Should-Equal($cond, $msg){
  if ($cond) { Write-Host "✅ $msg" }
  else       { throw "❌ $msg" }
}

Write-Host "▶ Sandbox:"
Write-Host "  HOME:        $HOME"
Write-Host "  ProgramData: $PData"
Write-Host "  Profile:     $SandboxProfile"

# -----------------------
# 1) Dry-run: no changes
# -----------------------
Write-Host "▶ Dry run…"
$dryOut = ''
$rc = Invoke-UnderTest -Args @('--Json') -OutputText ([ref]$dryOut)
if ($VerboseLog) { Write-Host $dryOut }
Should-Equal ($rc -eq 0) "Dry-run exit code 0"
# Ensure profile untouched, no .bak
Should-Equal (Test-Path $SandboxProfile) "Sandbox profile exists after dry-run"
Should-Equal (-not (Test-Path ($SandboxProfile + '.bak'))) "No backup in dry-run"
# Ensure our HOME dirs still exist
Should-Equal (Test-Path (Join-Path $HOME 'Miniconda3')) "Miniconda3 exists after dry-run"

# ---------------------------------
# 2) Apply: only sandbox is changed
# ---------------------------------
Write-Host "▶ Apply (--Yes)…"
$applyOut = ''
$rc = Invoke-UnderTest -Args @('-Yes','-IncludeForge','-IncludeMicromamba','-Json') -OutputText ([ref]$applyOut)
if ($VerboseLog) { Write-Host $applyOut }
Should-Equal ($rc -eq 0) "Apply exit code 0"

# a) Profile cleaned & backup created
Should-Equal (Test-Path ($SandboxProfile + '.bak')) "Backup profile created"
$profileText = Get-Content -Raw -Path $SandboxProfile
Should-Equal (-not ($profileText -match 'conda initialize')) "Conda block removed from profile"
Should-Equal (-not ($profileText -match 'conda init')) "conda init line removed from profile"

# b) HOME-scoped dirs removed
foreach ($d in @('Anaconda3','Miniconda3','.conda','.continuum','mambaforge','miniforge3','micromamba')) {
  $path = Join-Path $HOME $d
  Should-Equal (-not (Test-Path $path)) "Removed $path"
}

# c) ProgramData dirs removed (we redirected ProgramData)
foreach ($d in @('Anaconda3','Miniconda3')) {
  $path = Join-Path $PData $d
  Should-Equal (-not (Test-Path $path)) "Removed $path"
}

# d) Verify User PATH was not changed (we refused to run if it contained conda)
$UserPathAfter = [Environment]::GetEnvironmentVariable('Path','User')
Should-Equal ($UserPathAfter -eq $UserPath) "User PATH unchanged"

# -----------------------
# 3) Idempotency
# -----------------------
Write-Host "▶ Idempotency…"
$idOut = ''
$rc = Invoke-UnderTest -Args @('-Yes','-IncludeForge','-IncludeMicromamba') -OutputText ([ref]$idOut)
if ($VerboseLog) { Write-Host $idOut }
Should-Equal ($rc -eq 0) "Second apply exit code 0"

Write-Host ""
Write-Host "Sandbox: $TmpRoot"
Write-Host "Dry log saved in memory (${dryOut.Length} chars)"
Write-Host "Apply log saved in memory (${applyOut.Length} chars)"
Write-Host ""
Write-Host "✅ Windows test passed safely"