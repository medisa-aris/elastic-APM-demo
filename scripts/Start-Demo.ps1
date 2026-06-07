<#
.SYNOPSIS
    Start the Elastic APM demo.

.DESCRIPTION
    Starts all demo services in the specified deployment mode.
    Waits for each service to become healthy before returning.

.PARAMETER Mode
    Deployment mode: compose (default), kubernetes, or openshift.

.PARAMETER Build
    Force rebuild of Docker images before starting (compose mode only).

.PARAMETER Scenario2
    Activate Scenario 2 — Payment Failure (sets PAYMENT_FAILURE_RATE=100).

.PARAMETER Scenario3
    Activate Scenario 3 — Slow Inventory (sets INVENTORY_SLOW_MS=3000).

.EXAMPLE
    .\scripts\Start-Demo.ps1
    .\scripts\Start-Demo.ps1 -Build
    .\scripts\Start-Demo.ps1 -Scenario2
    .\scripts\Start-Demo.ps1 -Mode kubernetes
#>
[CmdletBinding()]
param(
    [ValidateSet('compose', 'kubernetes', 'openshift')]
    [string]$Mode = 'compose',

    [switch]$Build,
    [switch]$Scenario2,
    [switch]$Scenario3
)

$ErrorActionPreference = 'Stop'
$ProjectRoot = Split-Path -Parent $PSScriptRoot

Set-Location $ProjectRoot

# ── Helpers ──────────────────────────────────────────────────────────────────

function Write-Step([string]$msg) {
    Write-Host "`n==> $msg" -ForegroundColor Cyan
}

function Write-OK([string]$msg) {
    Write-Host "    [OK] $msg" -ForegroundColor Green
}

function Write-Warn([string]$msg) {
    Write-Host "    [WARN] $msg" -ForegroundColor Yellow
}

function Write-Fail([string]$msg) {
    Write-Host "    [FAIL] $msg" -ForegroundColor Red
}

function Wait-ForHealthy {
    param(
        [string]$ServiceName,
        [string]$Url,
        [int]$MaxSeconds = 180
    )
    $deadline = (Get-Date).AddSeconds($MaxSeconds)
    Write-Host "    Waiting for $ServiceName at $Url" -NoNewline
    while ((Get-Date) -lt $deadline) {
        try {
            $response = Invoke-WebRequest -Uri $Url -TimeoutSec 3 -UseBasicParsing -ErrorAction Stop
            if ($response.StatusCode -ge 200 -and $response.StatusCode -lt 300) {
                Write-Host ' Ready' -ForegroundColor Green
                return $true
            }
        } catch {}
        Write-Host '.' -NoNewline
        Start-Sleep -Seconds 3
    }
    Write-Host ' TIMED OUT' -ForegroundColor Red
    return $false
}

function Load-DotEnv([string]$path) {
    if (-not (Test-Path $path)) { return }
    Get-Content $path | ForEach-Object {
        if ($_ -match '^\s*([^#][^=]+)=(.*)$') {
            $key   = $Matches[1].Trim()
            $value = $Matches[2].Trim().Trim('"').Trim("'")
            if (-not [System.Environment]::GetEnvironmentVariable($key)) {
                [System.Environment]::SetEnvironmentVariable($key, $value, 'Process')
            }
        }
    }
}

# ── Validation ────────────────────────────────────────────────────────────────

Write-Step 'Validating environment'

$envFile = Join-Path $ProjectRoot '.env'
if (-not (Test-Path $envFile)) {
    Write-Fail ".env file not found."
    Write-Host "    Copy the example and fill in your Elastic Cloud credentials:" -ForegroundColor Yellow
    Write-Host "      cp .env.example .env" -ForegroundColor Yellow
    exit 1
}

Load-DotEnv $envFile

$apmUrl = [System.Environment]::GetEnvironmentVariable('ELASTIC_APM_SERVER_URL')
if (-not $apmUrl -or $apmUrl -like '*your-apm*') {
    Write-Fail 'ELASTIC_APM_SERVER_URL is not set or still contains the placeholder value.'
    Write-Host '    Edit .env and set your real Elastic Cloud APM Server URL.' -ForegroundColor Yellow
    exit 1
}
Write-OK "APM Server: $apmUrl"

# ── Scenario overrides ────────────────────────────────────────────────────────

if ($Scenario2) {
    Write-Warn 'Scenario 2 active: PAYMENT_FAILURE_RATE=100'
    [System.Environment]::SetEnvironmentVariable('PAYMENT_FAILURE_RATE', '100', 'Process')
}
if ($Scenario3) {
    Write-Warn 'Scenario 3 active: INVENTORY_SLOW_MS=3000'
    [System.Environment]::SetEnvironmentVariable('INVENTORY_SLOW_MS', '3000', 'Process')
}

# ── Start ─────────────────────────────────────────────────────────────────────

switch ($Mode) {

    'compose' {
        Write-Step 'Starting services with Docker Compose'

        # Ensure Go module cache is populated before first build
        $goSum = Join-Path $ProjectRoot 'services\inventory-service\go.sum'
        $goSumContent = if (Test-Path $goSum) { Get-Content $goSum -Raw } else { '' }
        if ($Build -and ($goSumContent -match '^\s*#' -or $goSumContent.Trim() -eq '')) {
            Write-Host '    Running go mod tidy for inventory-service...' -NoNewline
            $goExe = Get-Command go -ErrorAction SilentlyContinue
            if ($goExe) {
                Push-Location (Join-Path $ProjectRoot 'services\inventory-service')
                & go mod tidy
                Pop-Location
                Write-Host ' done' -ForegroundColor Green
            } else {
                Write-Warn 'go not found in PATH — go.sum will be generated inside the Docker build (requires network access)'
            }
        }

        $composeArgs = @('compose', 'up', '-d')
        if ($Build) { $composeArgs += '--build' }

        & docker @composeArgs
        if ($LASTEXITCODE -ne 0) { Write-Fail 'docker compose up failed'; exit 1 }

        Write-Step 'Waiting for services to be healthy'

        $healthy = $true
        $healthy = $healthy -and (Wait-ForHealthy 'otel-collector'    'http://localhost:13133/')
        $healthy = $healthy -and (Wait-ForHealthy 'inventory-service' 'http://localhost:8082/health')
        $healthy = $healthy -and (Wait-ForHealthy 'payment-service'   'http://localhost:8081/health')
        $healthy = $healthy -and (Wait-ForHealthy 'order-service'     'http://localhost:8080/actuator/health')
        $healthy = $healthy -and (Wait-ForHealthy 'gateway'           'http://localhost:4000/health')
        $healthy = $healthy -and (Wait-ForHealthy 'frontend'          'http://localhost:3000')

        if (-not $healthy) {
            Write-Fail 'One or more services failed to become healthy.'
            Write-Host '    Check logs: docker compose logs --tail=50' -ForegroundColor Yellow
            exit 1
        }
    }

    'kubernetes' {
        Write-Step 'Building Docker images for Kubernetes (imagePullPolicy: Never)'

        $images = @(
            @{ tag = 'demo-frontend:local';         ctx = './frontend' },
            @{ tag = 'demo-gateway:local';           ctx = './gateway' },
            @{ tag = 'demo-order-service:local';     ctx = './services/order-service' },
            @{ tag = 'demo-payment-service:local';   ctx = './services/payment-service' },
            @{ tag = 'demo-inventory-service:local'; ctx = './services/inventory-service' }
        )

        foreach ($img in $images) {
            Write-Host "    Building $($img.tag)..." -NoNewline
            & docker build -t $img.tag $img.ctx -q
            if ($LASTEXITCODE -ne 0) { Write-Fail "Build failed for $($img.tag)"; exit 1 }
            Write-Host ' done' -ForegroundColor Green
        }

        # If using minikube, load images into the cluster
        $minikube = Get-Command minikube -ErrorAction SilentlyContinue
        if ($minikube) {
            Write-Step 'Loading images into minikube'
            foreach ($img in $images) {
                & minikube image load $img.tag
            }
        }

        Write-Step 'Applying Kubernetes manifests'
        & kubectl apply -f deployment/kubernetes/
        if ($LASTEXITCODE -ne 0) { Write-Fail 'kubectl apply failed'; exit 1 }

        Write-Step 'Waiting for rollouts'
        & kubectl rollout status deployment -n elastic-apm-demo --timeout=180s
        if ($LASTEXITCODE -ne 0) { Write-Fail 'Rollout timed out'; exit 1 }
    }

    'openshift' {
        Write-Step 'Building Docker images'

        $images = @(
            @{ tag = 'demo-frontend:local';         ctx = './frontend' },
            @{ tag = 'demo-gateway:local';           ctx = './gateway' },
            @{ tag = 'demo-order-service:local';     ctx = './services/order-service' },
            @{ tag = 'demo-payment-service:local';   ctx = './services/payment-service' },
            @{ tag = 'demo-inventory-service:local'; ctx = './services/inventory-service' }
        )

        foreach ($img in $images) {
            Write-Host "    Building $($img.tag)..." -NoNewline
            & docker build -t $img.tag $img.ctx -q
            if ($LASTEXITCODE -ne 0) { Write-Fail "Build failed for $($img.tag)"; exit 1 }
            Write-Host ' done' -ForegroundColor Green
        }

        Write-Step 'Pushing images to OpenShift internal registry'

        # Expose the internal registry route if not already exposed
        $routeCheck = & oc get route default-route -n openshift-image-registry 2>&1
        if ($LASTEXITCODE -ne 0) {
            & oc patch configs.imageregistry.operator.openshift.io/cluster `
                --patch '{"spec":{"defaultRoute":true}}' --type=merge
            Start-Sleep -Seconds 10
        }

        $registry = & oc get route default-route -n openshift-image-registry `
            -o jsonpath='{.spec.host}' 2>&1
        if (-not $registry -or $LASTEXITCODE -ne 0) {
            Write-Fail 'Could not determine the OpenShift image registry route.'
            Write-Host "    Run: oc patch configs.imageregistry.operator.openshift.io/cluster --patch '{`"spec`":{`"defaultRoute`":true}}' --type=merge" -ForegroundColor Yellow
            exit 1
        }
        Write-Host "    Registry: $registry"

        $ocToken = & oc whoami -t
        $ocUser  = & oc whoami
        & docker login -u $ocUser -p $ocToken $registry
        if ($LASTEXITCODE -ne 0) { Write-Fail 'docker login to OpenShift registry failed'; exit 1 }

        $names = @('demo-frontend','demo-gateway','demo-order-service','demo-payment-service','demo-inventory-service')
        foreach ($name in $names) {
            Write-Host "    Pushing ${name}..." -NoNewline
            & docker tag "${name}:local" "${registry}/elastic-apm-demo/${name}:latest"
            & docker push "${registry}/elastic-apm-demo/${name}:latest" -q
            if ($LASTEXITCODE -ne 0) { Write-Fail "Push failed for $name"; exit 1 }
            Write-Host ' done' -ForegroundColor Green
        }

        Write-Step 'Creating demo-secrets from .env'
        $nextPublicUrl = [System.Environment]::GetEnvironmentVariable('NEXT_PUBLIC_ELASTIC_APM_SERVER_URL')
        if (-not $nextPublicUrl) { $nextPublicUrl = $apmUrl }
        $apiKey = [System.Environment]::GetEnvironmentVariable('ELASTIC_API_KEY')
        & oc create secret generic demo-secrets `
            --from-literal="ELASTIC_APM_SERVER_URL=$apmUrl" `
            --from-literal="ELASTIC_API_KEY=$apiKey" `
            --from-literal="NEXT_PUBLIC_ELASTIC_APM_SERVER_URL=$nextPublicUrl" `
            -n elastic-apm-demo `
            --dry-run=client -o yaml | oc apply -f -
        if ($LASTEXITCODE -ne 0) { Write-Fail 'Secret creation failed'; exit 1 }

        Write-Step 'Applying OpenShift manifests'
        & oc apply -f deployment/openshift/
        if ($LASTEXITCODE -ne 0) { Write-Fail 'oc apply failed'; exit 1 }

        Write-Step 'Waiting for rollouts'
        & oc rollout status deployment -n elastic-apm-demo --timeout=180s
        if ($LASTEXITCODE -ne 0) { Write-Fail 'Rollout timed out'; exit 1 }
    }
}

# ── Summary ───────────────────────────────────────────────────────────────────

Write-Host ''
Write-Host '============================================================' -ForegroundColor Green
Write-Host '  Demo is running!' -ForegroundColor Green
Write-Host '============================================================' -ForegroundColor Green
Write-Host ''

if ($Mode -eq 'openshift') {
    $frontendHost = & oc get route frontend -n elastic-apm-demo -o jsonpath='{.spec.host}' 2>&1
    $gatewayHost  = & oc get route gateway  -n elastic-apm-demo -o jsonpath='{.spec.host}' 2>&1
    Write-Host "  Frontend:    https://$frontendHost"
    Write-Host "  Gateway API: https://$gatewayHost"
} else {
    Write-Host '  Frontend:          http://localhost:3000'
    Write-Host '  Gateway API:       http://localhost:4000'
    Write-Host '  OTel Collector:    http://localhost:13133  (health check)'
}
Write-Host ''
Write-Host "  APM Server:        $apmUrl"
Write-Host ''

if ($Scenario2) {
    Write-Host '  [Scenario 2] Payment failures are ON  (PAYMENT_FAILURE_RATE=100)' -ForegroundColor Yellow
}
if ($Scenario3) {
    Write-Host '  [Scenario 3] Slow inventory is ON  (INVENTORY_SLOW_MS=3000)' -ForegroundColor Yellow
}

Write-Host ''
Write-Host '  To stop:   .\scripts\Stop-Demo.ps1'
Write-Host '  To reset:  .\scripts\Reset-Demo.ps1'
Write-Host ''
