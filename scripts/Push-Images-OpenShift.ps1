<#
.SYNOPSIS
    Push locally built Docker images to the OpenShift internal registry.

.DESCRIPTION
    Tags each demo-*:local image and pushes it to the OpenShift internal registry
    so that OpenShift pods can pull them with imagePullPolicy: Always.

    Run this after building images locally (docker build), or use
    Start-Demo.ps1 -Mode openshift which calls this automatically.

    Works with:
      - OpenShift Local (CRC)    — uses podman if available for --tls-verify=false
      - Remote OpenShift cluster — uses docker; registry must have a valid TLS cert

.PARAMETER Namespace
    OpenShift namespace (default: elastic-apm-demo)

.EXAMPLE
    .\scripts\Push-Images-OpenShift.ps1
    .\scripts\Push-Images-OpenShift.ps1 -Namespace my-demo
#>
[CmdletBinding()]
param(
    [string]$Namespace = 'elastic-apm-demo'
)

$ErrorActionPreference = 'Stop'
$ProjectRoot = Split-Path -Parent $PSScriptRoot
Set-Location $ProjectRoot

function Write-Step([string]$msg) { Write-Host "`n==> $msg" -ForegroundColor Cyan }
function Write-OK([string]$msg)   { Write-Host "    [OK] $msg" -ForegroundColor Green }
function Write-Warn([string]$msg) { Write-Host "    [WARN] $msg" -ForegroundColor Yellow }
function Write-Fail([string]$msg) { Write-Host "    [FAIL] $msg" -ForegroundColor Red }

$Images = @(
    'demo-frontend',
    'demo-gateway',
    'demo-order-service',
    'demo-payment-service',
    'demo-inventory-service'
)

# ── Pre-flight ────────────────────────────────────────────────────────────────
Write-Step 'Pre-flight checks'

if (-not (Get-Command oc -ErrorAction SilentlyContinue)) {
    Write-Fail 'oc CLI not found. Install the OpenShift CLI and log in first.'
    exit 1
}

$ocUser = & oc whoami 2>&1
if ($LASTEXITCODE -ne 0) {
    Write-Fail "Not logged in to OpenShift. Run: oc login <cluster-url>"
    exit 1
}
Write-OK "Logged in as: $ocUser"

# Prefer podman (ships with CRC/OpenShift Local) — supports --tls-verify=false
# Fall back to docker for standard remote clusters
$Runtime = if (Get-Command podman -ErrorAction SilentlyContinue) { 'podman' } `
           elseif (Get-Command docker -ErrorAction SilentlyContinue) { 'docker' } `
           else { $null }

if (-not $Runtime) {
    Write-Fail 'Neither podman nor docker found. Install one of them.'
    exit 1
}
Write-OK "Container runtime: $Runtime"

# Verify local images exist
foreach ($name in $Images) {
    $check = & $Runtime image inspect "${name}:local" 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Fail "Image ${name}:local not found locally. Build it first:"
        Write-Host "    docker build -t ${name}:local ./<service-dir>" -ForegroundColor Yellow
        exit 1
    }
}
Write-OK 'All local images present'

# ── Registry route ────────────────────────────────────────────────────────────
Write-Step 'Getting OpenShift internal registry route'

$registry = & oc get route default-route -n openshift-image-registry `
    -o jsonpath='{.spec.host}' 2>&1
if ($LASTEXITCODE -ne 0 -or -not $registry) {
    Write-Warn 'Registry route not exposed — enabling it now...'
    & oc patch configs.imageregistry.operator.openshift.io/cluster `
        --patch '{"spec":{"defaultRoute":true}}' --type=merge
    Write-Host '    Waiting for route' -NoNewline
    for ($i = 0; $i -lt 20; $i++) {
        Start-Sleep -Seconds 3
        $registry = & oc get route default-route -n openshift-image-registry `
            -o jsonpath='{.spec.host}' 2>&1
        if ($registry -and $LASTEXITCODE -eq 0) { break }
        Write-Host '.' -NoNewline
    }
    Write-Host ''
}

if (-not $registry -or $LASTEXITCODE -ne 0) {
    Write-Fail 'Could not determine the registry route after waiting.'
    Write-Host '    Check: oc get route -n openshift-image-registry' -ForegroundColor Yellow
    exit 1
}
Write-OK "Registry: $registry"

# ── Login ─────────────────────────────────────────────────────────────────────
Write-Step 'Logging in to registry'

$ocToken = & oc whoami -t

if ($Runtime -eq 'podman') {
    & podman login --tls-verify=false -u $ocUser -p $ocToken $registry
    if ($LASTEXITCODE -ne 0) { Write-Fail 'podman login failed'; exit 1 }
} else {
    & docker login -u $ocUser -p $ocToken $registry
    if ($LASTEXITCODE -ne 0) {
        Write-Warn 'docker login failed — registry may use a self-signed cert (common with CRC).'
        Write-Warn "Add to Docker Desktop settings → Docker Engine:"
        Write-Warn "  { `"insecure-registries`": [`"$registry`"] }"
        Write-Warn 'Then restart Docker Desktop and retry.'
        exit 1
    }
}
Write-OK 'Login successful'

# ── Push ──────────────────────────────────────────────────────────────────────
Write-Step "Pushing images to $registry/$Namespace"

foreach ($name in $Images) {
    $dest = "${registry}/${Namespace}/${name}:latest"
    Write-Host "    $name`:local  →  latest" -NoNewline

    if ($Runtime -eq 'podman') {
        & podman tag "${name}:local" $dest
        & podman push --tls-verify=false $dest -q
    } else {
        & docker tag "${name}:local" $dest
        & docker push $dest -q
    }

    if ($LASTEXITCODE -ne 0) { Write-Fail "Push failed for $name"; exit 1 }
    Write-Host '  done' -ForegroundColor Green
}

Write-Host ''
Write-OK 'All images pushed. OpenShift pods can now pull them.'
Write-Host ''
Write-Host '  Internal pull URL (used in pod specs):'
Write-Host "  image-registry.openshift-image-registry.svc:5000/$Namespace/<name>:latest"
Write-Host ''
