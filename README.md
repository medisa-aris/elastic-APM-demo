# Elastic APM Distributed Observability Demo

A full-stack microservices demo showcasing Elastic APM, OpenTelemetry distributed tracing, and Elastic RUM browser monitoring.

## Architecture

```
Browser (Elastic RUM)
    └── Frontend (Next.js :3000)
            └── Gateway (Node.js Express :4000)
                   ├── Inventory Service (Go Gin :8082)  ← SQLite
                   ├── Payment Service  (Python FastAPI :8081) ← SQLite
                   └── Order Service    (Java Spring Boot :8080) ← H2

All backend services → OTel Collector (:4317) → Elastic Cloud APM Server
```

## Quick Start (Docker Compose)

### 1. Configure Elastic Cloud credentials

```powershell
Copy-Item .env.example .env
# Edit .env and fill in:
#   ELASTIC_APM_SERVER_URL
#   ELASTIC_API_KEY
#   NEXT_PUBLIC_ELASTIC_APM_SERVER_URL
```

### 2. Start the demo

```powershell
.\scripts\Start-Demo.ps1 -Build
```

### 3. Open the demo

| URL | Description |
|-----|-------------|
| http://localhost:3000 | Shop frontend |
| http://localhost:4000/health | Gateway health |
| http://localhost:8082/inventory | Inventory API |

### 4. Stop the demo

```powershell
.\scripts\Stop-Demo.ps1
```

### 5. Reset to clean state

```powershell
.\scripts\Reset-Demo.ps1
```

---

## Demo Scenarios

### Scenario 1 — Successful Purchase (default)

Default state. Browse products → Add to cart → Checkout → success.

**What to show in Elastic APM:**
- APM → Service Map: shows all 5 services connected
- APM → Transactions: distributed trace spans gateway → inventory → payment → order
- APM → User Experience: browser page load transactions from Elastic RUM

### Scenario 2 — Payment Failure

```powershell
.\scripts\Start-Demo.ps1 -Scenario2
```

Or set `PAYMENT_FAILURE_RATE=100` in `.env` and restart:
```powershell
docker compose up -d --no-deps payment-service
```

**What to show in Elastic APM:**
- APM → Errors: Python `PaymentDeclinedException` with full stack trace
- APM → Transactions: 402 error propagated through gateway to browser
- APM → User Experience: failed user journey

### Scenario 3 — Slow Inventory Service

```powershell
.\scripts\Start-Demo.ps1 -Scenario3
```

Or set `INVENTORY_SLOW_MS=3000` in `.env` and restart:
```powershell
docker compose up -d --no-deps inventory-service
```

**What to show in Elastic APM:**
- APM → Trace Waterfall: inventory span clearly shows 3s+ added latency
- APM → Service Map: inventory node highlighted as bottleneck
- Demonstrates root cause identification for slow response times

---

## Kubernetes Deployment

### Prerequisites

- Docker Desktop with Kubernetes enabled, OR `minikube`
- `kubectl` configured

### Deploy

1. Create the secret from the example:
   ```
   cp deployment/kubernetes/secrets.yaml.example deployment/kubernetes/secrets.yaml
   # Edit secrets.yaml — base64-encode your values: echo -n 'value' | base64
   ```

2. Start:
   ```powershell
   .\scripts\Start-Demo.ps1 -Mode kubernetes
   ```

3. Stop:
   ```powershell
   .\scripts\Stop-Demo.ps1 -Mode kubernetes
   ```

**Note:** Images are built locally with `imagePullPolicy: Never`. The start script builds and loads them automatically.

---

## OpenShift Deployment

Same as Kubernetes, but uses OpenShift `Route` objects instead of `Ingress`.

```powershell
.\scripts\Start-Demo.ps1 -Mode openshift
.\scripts\Stop-Demo.ps1 -Mode openshift
```

After deployment, get the route URLs:
```
oc get routes -n elastic-apm-demo
```

---

## PowerShell Scripts Reference

| Script | Description |
|--------|-------------|
| `Start-Demo.ps1` | Start services, wait for health checks, print URLs |
| `Stop-Demo.ps1` | Stop services |
| `Reset-Demo.ps1` | Stop + wipe data + reset scenario flags + rebuild + start |

### Start-Demo.ps1 Parameters

| Parameter | Type | Description |
|-----------|------|-------------|
| `-Mode` | compose/kubernetes/openshift | Deployment target (default: compose) |
| `-Build` | switch | Force rebuild Docker images |
| `-Scenario2` | switch | Enable payment failure simulation |
| `-Scenario3` | switch | Enable inventory latency simulation |

### Stop-Demo.ps1 Parameters

| Parameter | Type | Description |
|-----------|------|-------------|
| `-Mode` | compose/kubernetes/openshift | Deployment target (default: compose) |
| `-CleanVolumes` | switch | Remove named volumes (wipe database data) |
| `-CleanImages` | switch | Remove locally built images |

---

## Project Structure

```
elastic-APM-demo/
├── .env.example              ← Copy to .env and fill in credentials
├── docker-compose.yml
├── frontend/                 ← Next.js + Elastic RUM
├── gateway/                  ← Node.js Express + OTel auto-instrumentation
├── services/
│   ├── inventory-service/    ← Go Gin + SQLite
│   ├── payment-service/      ← Python FastAPI + SQLite
│   └── order-service/        ← Java Spring Boot + H2
├── observability/
│   └── otel-collector/       ← OTel Collector config
├── deployment/
│   ├── kubernetes/           ← K8s manifests
│   └── openshift/            ← OpenShift manifests (Routes)
├── seed/
│   └── seed-data.json        ← Initial product catalog
└── scripts/
    ├── Start-Demo.ps1
    ├── Stop-Demo.ps1
    └── Reset-Demo.ps1
```

---

## Elastic Cloud Setup

### Required: Get your APM credentials

1. Go to your [Elastic Cloud console](https://cloud.elastic.co)
2. Open your deployment → **APM & Fleet**
3. Note the **APM Server URL**
4. Go to **Stack Management → API Keys** → Create a key with APM writer permissions
5. Base64-encode the key: `Format: id:api_key` → encode the whole string

### Fill in `.env`

```
ELASTIC_APM_SERVER_URL=https://xxxx.apm.us-east-1.aws.elastic-cloud.com
ELASTIC_API_KEY=base64encodedkey==
NEXT_PUBLIC_ELASTIC_APM_SERVER_URL=https://xxxx.apm.us-east-1.aws.elastic-cloud.com
```

### Verify OTel Collector is sending data

```powershell
docker compose logs otel-collector --tail=30
```

Look for `Everything is ready. Begin running and processing data.`

If you see `401 Unauthorized`, the `ELASTIC_API_KEY` is wrong.

---

## Observability Coverage

| Signal | Source | Tool |
|--------|--------|------|
| Browser page loads | Elastic RUM (`@elastic/apm-rum`) | APM → User Experience |
| Distributed traces | OTel auto-instrumentation (all backends) | APM → Traces |
| Service dependencies | W3C traceparent header propagation | APM → Service Map |
| Database spans | OTel JDBC / sqlite3 / Go SQLite instrumentation | APM → Trace Waterfall |
| Application errors | OTel exception events | APM → Errors |
| JVM metrics | Spring Boot Actuator + OTel | APM → Metrics |
| Go runtime metrics | OTel Go SDK | APM → Metrics |
