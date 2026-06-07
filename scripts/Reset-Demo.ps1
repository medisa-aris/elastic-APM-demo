<#
.SYNOPSIS
    Reset the Elastic APM demo to a clean state.

.DESCRIPTION
    Stops all services, wipes database volumes, resets scenario flags to 0,
    then rebuilds and restarts everything with fresh seed data.

.PARAMETER Mode
    Deployment mode: compose (default), kubernetes, or openshift.

.EXAMPLE
    .\scripts\Reset-Demo.ps1
    .\scripts\Reset-Demo.ps1 -Mode kubernetes
#>
[CmdletBinding()]
param(
    [ValidateSet('compose', 'kubernetes', 'openshift')]
    [string]$Mode = 'compose'
)

$ErrorActionPreference = 'Stop'
$ProjectRoot = Split-Path -Parent $PSScriptRoot
Set-Location $ProjectRoot

function Write-Step([string]$msg) {
    Write-Host "`n==> $msg" -ForegroundColor Cyan
}

# ── Stop ──────────────────────────────────────────────────────────────────────

Write-Step 'Stopping demo'
& "$PSScriptRoot\Stop-Demo.ps1" -Mode $Mode -CleanVolumes

# ── Reset scenario flags in .env ──────────────────────────────────────────────

Write-Step 'Resetting scenario flags in .env'

$envFile = Join-Path $ProjectRoot '.env'
if (Test-Path $envFile) {
    $content = Get-Content $envFile -Raw

    # Reset PAYMENT_FAILURE_RATE to 0
    $content = $content -replace '(?m)^PAYMENT_FAILURE_RATE=.*$', 'PAYMENT_FAILURE_RATE=0'

    # Reset INVENTORY_SLOW_MS to 0
    $content = $content -replace '(?m)^INVENTORY_SLOW_MS=.*$', 'INVENTORY_SLOW_MS=0'

    Set-Content -Path $envFile -Value $content -Encoding utf8
    Write-Host '    PAYMENT_FAILURE_RATE=0' -ForegroundColor Green
    Write-Host '    INVENTORY_SLOW_MS=0' -ForegroundColor Green
} else {
    Write-Host '    .env not found — skipping flag reset' -ForegroundColor Yellow
}

# ── Restart ───────────────────────────────────────────────────────────────────

Write-Step 'Starting demo with fresh build'
& "$PSScriptRoot\Start-Demo.ps1" -Mode $Mode -Build
