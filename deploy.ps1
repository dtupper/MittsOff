# Copies the addon into the game's AddOns folder for testing.
# Usage: ./deploy.ps1 [-AddOns <path to Interface\AddOns>]
param(
    [string]$AddOns = $(if ($env:MITTSOFF_ADDONS) { $env:MITTSOFF_ADDONS } else { 'C:\Games\World of Warcraft\_forever_\Interface\AddOns' })
)

$ErrorActionPreference = 'Stop'

if (-not (Test-Path -LiteralPath $AddOns)) { throw "AddOns folder not found: $AddOns" }

$source = $PSScriptRoot
$target = Join-Path $AddOns 'MittsOff'
$toc = Join-Path $source 'MittsOff.toc'

# A target with its own .git is a working copy, not a deployed one. Leave it alone.
if (Test-Path -LiteralPath (Join-Path $target '.git')) { throw "$target is a git checkout. Remove it by hand before deploying." }

# The game loads exactly what the TOC lists, so that is what gets copied.
$files = @('MittsOff.toc') + (Get-Content -LiteralPath $toc | ForEach-Object { $_.Trim() } | Where-Object { $_ -and -not $_.StartsWith('#') })

$version = (git -C $source describe --tags --always --dirty --exclude unstable 2>$null)
if (-not $version) { $version = 'dev' }

if (Test-Path -LiteralPath $target) { Remove-Item -LiteralPath $target -Recurse -Force }

foreach ($file in $files) {
    $from = Join-Path $source $file
    $to = Join-Path $target $file
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $to) | Out-Null
    Copy-Item -LiteralPath $from -Destination $to
}

# Stand in for the packager, which fills this token in on real builds.
$deployedToc = Join-Path $target 'MittsOff.toc'
(Get-Content -LiteralPath $deployedToc -Raw).Replace('@project-version@', $version) | Set-Content -LiteralPath $deployedToc -NoNewline

Write-Host "Deployed $version to $target ($($files.Count) files). Use /reload in game, or restart it if files were added."
