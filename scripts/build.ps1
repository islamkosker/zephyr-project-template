#!/usr/bin/env pwsh

param(
  # short, unique aliases (avoid case-insensitive clashes)
  [Alias('b')][string] $Board,
  [Alias('dto','overlay')][string] $DT_Overlay,
  [Alias('o','out')][string] $BuildDir,
  [Alias('c','pristine')][switch] $Clean,
  [Alias('a','act')][switch] $Activate,
  # Add the help switch back to the param block
  [Alias('h','?')][switch] $Help
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

# The help check now uses the $Help parameter
if ($Help) {
    Write-Host @"
Usage:
  build.ps1 [-Board <name>] [-DT_Overlay <path>] [-BuildDir <path>] [-Clean] [-Activate]
  build.ps1 -b nucleo_f070rb -dto boards\nucleo_f070rb.overlay -c -a

Aliases:
  -Board (-b)          : target board
  -DT_Overlay (-dto)   : device tree overlay path
  -BuildDir (-o)       : build directory
  -Clean (-c)          : pristine build (west -p always)
  -Activate (-a)       : activate Zephyr/west environment
  -Help (-h, -?)       : show this help
"@ | Write-Host
    exit 0
}

# ---------- Utilities ----------
function Write-Info([string]$msg){ Write-Host "[INFO] $msg" -ForegroundColor Cyan }
function Write-Warn([string]$msg){ Write-Host "[WARN] $msg" -ForegroundColor Yellow }
function Write-Err ([string]$msg){ Write-Host "[ERROR] $msg" -ForegroundColor Red }
function Coalesce {
  param([Parameter(ValueFromRemainingArguments=$true)][object[]]$Values)
  foreach ($v in $Values) {
    if ($null -ne $v -and "$v" -ne '') { return $v }
  }
  return $null
}
function EnvTrue([string]$v) {
  if ($null -eq $v) { return $false }
  $s = $v.ToString().ToLowerInvariant()
  return ($s -eq '1' -or $s -eq 'true' -or $s -eq 'yes' -or $s -eq 'on')
}
function Load-DotEnv {
  param([string]$Path,[switch]$Silent)
  if (-not (Test-Path $Path)) { if (-not $Silent){ Write-Info ".env not found at: $Path" }; return }
  Write-Info "Loading .env: $Path"
  Get-Content -Raw -Path $Path -Encoding UTF8 |
    ForEach-Object { $_ -split "`n" } |
    ForEach-Object {
      $line = $_.Trim()
      if (-not $line -or $line.StartsWith('#') -or $line.StartsWith(';')) { return }
      $idx = $line.IndexOf('=')
      if ($idx -lt 1) { return }
      $key = $line.Substring(0, $idx).Trim()
      $val = $line.Substring($idx + 1).Trim()
      if ($val.StartsWith('"') -and $val.EndsWith('"')) { $val = $val.Substring(1, $val.Length-2) }
      [Environment]::SetEnvironmentVariable($key, $val, 'Process')
    }
}
function Normalize-PathForward([string]$p) { if (-not $p) { return $p }; return ($p -replace '\\','/') }
function Quote-IfNeeded([string]$v) { if ($null -eq $v) { return $v }; if ($v -match '\s') { return "`"$v`"" }; return $v }
function Resolve-Absolute([string]$path, [string]$baseDir){
  if ([string]::IsNullOrWhiteSpace($path)) { return $null }
  if ([System.IO.Path]::IsPathRooted($path)) { return (Resolve-Path $path).Path }
  return (Resolve-Path (Join-Path $baseDir $path)).Path
}

# ---------- Env activation state ----------
$script:EnvMode        = $null      # 'venv' | 'path' | $null
$script:SavedPath      = $env:PATH  # to restore PATH if we modified it
$script:LastErrorCode  = 1          # default exit code if we fail

function Deactivate-Env {
  try {
    if ($script:EnvMode -eq 'venv' -and (Get-Command deactivate -ErrorAction SilentlyContinue)) {
      Write-Info "Deactivating Python venv..."
      deactivate
    } elseif ($script:EnvMode -eq 'path') {
      Write-Info "Reverting PATH changes..."
      $env:PATH = $script:SavedPath
    } else {
      # no-op
    }
  } catch {
    Write-Warn "Failed to deactivate environment: $($_.Exception.Message)"
  }
}

function Activate-Env {
  param([string]$ProjectRoot,[string]$ZephyrBase)
  $projectVenv = Join-Path $ProjectRoot ".venv\Scripts\Activate.ps1"
  
  # remember PATH before any change
  $script:SavedPath = $env:PATH

  if (Test-Path $projectVenv) {
    Write-Info "Activating project venv: $projectVenv"
    . $projectVenv
    $script:EnvMode = 'venv'
    return
  }
  
  # Only try zephyr venv if ZephyrBase is provided and valid
  if ($ZephyrBase -and (Test-Path $ZephyrBase)) {
    # ZephyrBase points to zephyrproject/zephyr, so parent is zephyrproject
    $zephyrProjectRoot = (Resolve-Path (Join-Path $ZephyrBase "..\")).Path
    $zephyrVenv = Join-Path $zephyrProjectRoot ".venv\Scripts\Activate.ps1"
    
    if (Test-Path $zephyrVenv) {
      Write-Info "Activating Zephyr venv: $zephyrVenv"
      . $zephyrVenv
      $script:EnvMode = 'venv'
      return
    }
  }
  
  Write-Warn "No venv found to activate."
  $script:EnvMode = $null
}

function Exit-Fail([string]$msg, [int]$code=1){
  $script:LastErrorCode = $code
  Write-Err $msg
  throw (New-Object System.Exception("[$code] $msg"))
}

# ---------- Project roots & .env ----------
$ScriptRoot  = Split-Path -Parent -Path $MyInvocation.MyCommand.Path
$ProjectRoot = (Resolve-Path (Join-Path $ScriptRoot '..')).Path

# Load .env from script folder then project root (script-local takes precedence)
Load-DotEnv -Path (Join-Path $ScriptRoot ".env") -Silent
Load-DotEnv -Path (Join-Path $ProjectRoot ".env") -Silent

# ---------- Defaults with precedence: CLI > .env  ----------
$Board      = Coalesce $Board      $env:BOARD      
$DT_Overlay = Coalesce $DT_Overlay $env:DT_OVERLAY $null
$BuildDir   = Coalesce $BuildDir   $env:BUILD_DIR  
$Clean      = $Clean -or (EnvTrue $env:CLEAN)
$Activate   = $Activate -or (EnvTrue $env:ACTIVATE)

$ZephyrBase = Coalesce $env:ZEPHYR_BASE               
$SdkDir     = Coalesce $env:ZEPHYR_SDK_INSTALL_DIR    
$NinjaExe   = Coalesce $env:NINJA_EXE                

# ---------- Environment prep ----------
if (-not $env:ZEPHYR_BASE)            { $env:ZEPHYR_BASE = $ZephyrBase }
if (-not $env:ZEPHYR_SDK_INSTALL_DIR) { $env:ZEPHYR_SDK_INSTALL_DIR = $SdkDir }

# optional activation
if ($Activate) {
  Activate-Env -ProjectRoot $ProjectRoot -ZephyrBase $ZephyrBase
}

# ===================== MAIN (guarded) =====================
$exitCode = 0
try {
  if (-not (Get-Command west -ErrorAction SilentlyContinue)) {
    Exit-Fail "west not found on PATH. Use -Activate or ensure your Zephyr venv is active."
  }

  # Resolve overlay
  if (-not $DT_Overlay) { $DT_Overlay = "boards/$Board.overlay" }
  $OverlayAbs = Resolve-Absolute -path $DT_Overlay -baseDir $ProjectRoot
  if (-not (Test-Path $OverlayAbs)) {
    Exit-Fail "Overlay not found: $DT_Overlay (resolved: $OverlayAbs)"
  }
  $OverlayCMake = Normalize-PathForward $OverlayAbs
  $OverlayArg   = "-DEXTRA_DTC_OVERLAY_FILE=$(Quote-IfNeeded $OverlayCMake)"

  # Build directory
  if (-not [System.IO.Path]::IsPathRooted($BuildDir)) {
    $BuildDir = Join-Path $ProjectRoot $BuildDir
  }
  New-Item -ItemType Directory -Force -Path $BuildDir | Out-Null

  # Ninja resolution: env > PATH
  if (-not (Test-Path $NinjaExe)) {
    $n = Get-Command ninja -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($n) { $NinjaExe = $n.Path }
  }
  if (-not (Test-Path $NinjaExe)) {
    Exit-Fail "ninja.exe not found. Set NINJA_EXE in .env or make 'ninja' available on PATH."
  }
  $NinjaCMake = Normalize-PathForward $NinjaExe
  $NinjaArg   = "-DCMAKE_MAKE_PROGRAM:FILEPATH=$(Quote-IfNeeded $NinjaCMake)"

  # Pristine mode
  $pristine = if ($Clean) { 'always' } else { 'auto' }

  # West args (CMake args after `--`)
  $westArgs = @(
    'build','-p', $pristine,
    '-b', $Board,
    $ProjectRoot,
    '--build-dir', $BuildDir,
    '--',
    '-DCMAKE_EXPORT_COMPILE_COMMANDS=ON',
    $OverlayArg,
    '-G','Ninja',
    $NinjaArg
  )

  # ---------- Summary ----------
  Write-Host ""
  Write-Host "================ Build Configuration ================" -ForegroundColor Green
  Write-Host ("Project Root         : {0}" -f (Normalize-PathForward $ProjectRoot))
  Write-Host ("Board                : {0}" -f $Board)
  Write-Host ("Overlay              : {0}" -f (Normalize-PathForward $OverlayAbs))
  Write-Host ("Build Directory      : {0}" -f (Normalize-PathForward $BuildDir))
  Write-Host ("Pristine             : {0}" -f $pristine)
  Write-Host ("ZEPHYR_BASE          : {0}" -f (Normalize-PathForward $env:ZEPHYR_BASE))
  Write-Host ("SDK Install Dir      : {0}" -f (Normalize-PathForward $env:ZEPHYR_SDK_INSTALL_DIR))
  Write-Host ("Ninja                : {0}" -f (Normalize-PathForward $NinjaExe))
  Write-Host "=====================================================" -ForegroundColor Green
  Write-Host ""

  # ---------- Run west ----------
  $cmdPreview = "west " + ($westArgs -join ' ')
  Write-Info "Executing: $cmdPreview"

  & west @westArgs
  $code = $LASTEXITCODE
  if ($code -ne 0) {
    Exit-Fail "west build failed with exit code $code" $code
  }

  Write-Host "[DONE] Build completed successfully." -ForegroundColor Green
}
catch {
  # show error and propagate exit code captured by Exit-Fail (or default 1)
  if ($_.Exception -and $_.Exception.Message) {
    Write-Err $_.Exception.Message
  } else {
    Write-Err $_
  }
  $exitCode = $script:LastErrorCode
}
finally {
  # always deactivate environment if it was activated or PATH was changed
  Deactivate-Env
}

exit $exitCode
