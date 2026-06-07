<#
.SYNOPSIS
    Stop the Elastic APM demo.

.PARAMETER Mode
    Deployment mode: compose (default), kubernetes, or openshift.

.PARAMETER CleanVolumes
    Also remove named volumes (wipes SQLite databases — use Reset-Demo.ps1 instead for a clean restart).

.PARAMETER CleanImages
    Also remove locally built Docker images.

.EXAMPLE
    .\scripts\Stop-Demo.ps1
    .\scripts\Stop-Demo.ps1 -CleanVolumes
    .\scripts\Stop-Demo.ps1 -Mode kubernetes
#>
[CmdletBinding()]
param(
    [ValidateSet('compose', 'kubernetes', 'openshift')]
    [string]$Mode = 'compose',

    [switch]$CleanVolumes,
    [switch]$CleanImages
)

$ErrorActionPreference = 'Stop'
$ProjectRoot = Split-Path -Parent $PSScriptRoot
Set-Location $ProjectRoot

function Write-Step([string]$msg) {
    Write-Host "`n==> $msg" -ForegroundColor Cyan
}

switch ($Mode) {

    'compose' {
        Write-Step 'Stopping Docker Compose services'

        $downArgs = @('compose', 'down')
        if ($CleanVolumes) {
            $downArgs += '-v'
            Write-Host '    --volumes flag set: named volumes will be removed (database data wiped)' -ForegroundColor Yellow
        }
        if ($CleanImages) {
            $downArgs += '--rmi'
            $downArgs += 'local'
            Write-Host '    --rmi local flag set: locally built images will be removed' -ForegroundColor Yellow
        }

        & docker @downArgs
        if ($LASTEXITCODE -ne 0) { Write-Host '[FAIL] docker compose down failed' -ForegroundColor Red; exit 1 }
    }

    'kubernetes' {
        Write-Step 'Deleting Kubernetes resources'
        & kubectl delete -f deployment/kubernetes/ --ignore-not-found
        if ($LASTEXITCODE -ne 0) { Write-Host '[FAIL] kubectl delete failed' -ForegroundColor Red; exit 1 }
    }

    'openshift' {
        Write-Step 'Deleting OpenShift resources'
        & oc delete -f deployment/openshift/ --ignore-not-found
        if ($LASTEXITCODE -ne 0) { Write-Host '[FAIL] oc delete failed' -ForegroundColor Red; exit 1 }
    }
}

Write-Host ''
Write-Host '  Demo stopped.' -ForegroundColor Green
Write-Host ''
