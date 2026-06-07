# Elastic APM Distributed Observability Demo

A full-stack microservices demo showcasing Elastic APM, OpenTelemetry distributed tracing, and Elastic RUM browser monitoring across 5 services in 4 languages.

## Architecture

```
Browser (Elastic RUM)
    └── Frontend (Next.js :3000)
            └── Gateway (Node.js Express :4000)
                   ├── Inventory Service (Go Gin :8082)       ← SQLite
                   ├── Payment Service  (Python FastAPI :8081) ← SQLite
                   └── Order Service    (Java Spring Boot :8080) ← H2

All backend services → OTel Collector (:4317) → Elastic Cloud APM Server
```

---

## Quick Start (Docker Compose)

### 1. Configure Elastic Cloud credentials

```bash
cp .env.example .env
# Edit .env and fill in:
#   ELASTIC_APM_SERVER_URL
#   ELASTIC_API_KEY
#   NEXT_PUBLIC_ELASTIC_APM_SERVER_URL
```

### 2. Start the demo

**Linux / macOS:**
```bash
./scripts/start-demo.sh --build
```

**Windows (PowerShell):**
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

```bash
./scripts/stop-demo.sh
```
```powershell
.\scripts\Stop-Demo.ps1
```

### 5. Reset to clean state

```bash
./scripts/reset-demo.sh
```
```powershell
.\scripts\Reset-Demo.ps1
```

---

## Demo Scenarios

### Scenario 1 — Successful Purchase (default)

Default state. Browse products → Add to cart → Checkout → success.

**What to show in Elastic APM:**
- APM → Service Map: shows all 5 services connected
- APM → Transactions: distributed trace spanning gateway → inventory → payment → order
- APM → User Experience: browser page load transactions from Elastic RUM

### Scenario 2 — Payment Failure

```bash
./scripts/start-demo.sh --scenario2
```
```powershell
.\scripts\Start-Demo.ps1 -Scenario2
```

Or activate on a running demo by editing `.env` (`PAYMENT_FAILURE_RATE=100`) and restarting only the payment service:
```bash
docker compose up -d --no-deps payment-service
```

**What to show in Elastic APM:**
- APM → Errors: Python `PaymentDeclinedException` with full stack trace
- APM → Transactions: 402 error propagated through gateway to browser
- APM → User Experience: failed user journey visible in RUM

### Scenario 3 — Slow Inventory Service

```bash
./scripts/start-demo.sh --scenario3
```
```powershell
.\scripts\Start-Demo.ps1 -Scenario3
```

Or activate on a running demo (`INVENTORY_SLOW_MS=3000`):
```bash
docker compose up -d --no-deps inventory-service
```

**What to show in Elastic APM:**
- APM → Trace Waterfall: inventory span clearly shows 3s+ added latency
- APM → Service Map: inventory node highlighted as the bottleneck
- Demonstrates root cause identification for slow response times

---

## Kubernetes Deployment

### Prerequisites

- Docker Desktop with Kubernetes enabled, OR `minikube`
- `kubectl` configured

### Deploy

1. Create the secret from the example:
   ```bash
   cp deployment/kubernetes/secrets.yaml.example deployment/kubernetes/secrets.yaml
   # Edit secrets.yaml — base64-encode your values:
   #   echo -n 'value' | base64
   ```

2. Start:
   ```bash
   ./scripts/start-demo.sh --mode kubernetes
   ```
   ```powershell
   .\scripts\Start-Demo.ps1 -Mode kubernetes
   ```

3. Stop:
   ```bash
   ./scripts/stop-demo.sh --mode kubernetes
   ```
   ```powershell
   .\scripts\Stop-Demo.ps1 -Mode kubernetes
   ```

> Images are built locally with `imagePullPolicy: Never`. The start script builds and loads them automatically. If using minikube, images are loaded via `minikube image load`.

---

## OpenShift Deployment

Same as Kubernetes but uses OpenShift `Route` objects instead of `Ingress`.

```bash
./scripts/start-demo.sh --mode openshift
./scripts/stop-demo.sh  --mode openshift
```
```powershell
.\scripts\Start-Demo.ps1 -Mode openshift
.\scripts\Stop-Demo.ps1  -Mode openshift
```

After deployment, retrieve route URLs:
```bash
oc get routes -n elastic-apm-demo
```

---

## Scripts Reference

All scripts live in [`scripts/`](scripts/) and come in two flavours — bash (Linux/macOS) and PowerShell (Windows) — with identical behaviour and flags.

### start-demo

Validates `.env`, starts all services, waits for health checks, and prints a summary.

| Bash flag | PowerShell flag | Description |
|-----------|-----------------|-------------|
| `-m`, `--mode` | `-Mode` | `compose` \| `kubernetes` \| `openshift` (default: `compose`) |
| `-b`, `--build` | `-Build` | Force rebuild of Docker images |
| `--scenario2` | `-Scenario2` | Enable payment failure simulation (`PAYMENT_FAILURE_RATE=100`) |
| `--scenario3` | `-Scenario3` | Enable slow inventory simulation (`INVENTORY_SLOW_MS=3000`) |

```bash
./scripts/start-demo.sh                        # default compose
./scripts/start-demo.sh --build                # rebuild images
./scripts/start-demo.sh --scenario2            # payment failure demo
./scripts/start-demo.sh --scenario3            # slow inventory demo
./scripts/start-demo.sh --mode kubernetes      # deploy to K8s
```

### stop-demo

Stops all services in the specified mode.

| Bash flag | PowerShell flag | Description |
|-----------|-----------------|-------------|
| `-m`, `--mode` | `-Mode` | Deployment target (default: `compose`) |
| `-v`, `--clean-volumes` | `-CleanVolumes` | Remove named volumes (wipes database data) |
| `-i`, `--clean-images` | `-CleanImages` | Remove locally built Docker images |

```bash
./scripts/stop-demo.sh                         # stop containers
./scripts/stop-demo.sh --clean-volumes         # stop + wipe databases
./scripts/stop-demo.sh --clean-images          # stop + remove images
```

### reset-demo

Full clean restart: stops with `--clean-volumes`, resets `PAYMENT_FAILURE_RATE` and `INVENTORY_SLOW_MS` to `0` in `.env`, then rebuilds and starts.

| Bash flag | PowerShell flag | Description |
|-----------|-----------------|-------------|
| `-m`, `--mode` | `-Mode` | Deployment target (default: `compose`) |

```bash
./scripts/reset-demo.sh                        # full clean restart
./scripts/reset-demo.sh --mode kubernetes      # clean restart on K8s
```

---

## Project Structure

```
elastic-APM-demo/
├── .env.example                  ← Copy to .env and fill in credentials
├── docker-compose.yml
├── frontend/                     ← Next.js + Elastic RUM
├── gateway/                      ← Node.js Express + OTel auto-instrumentation
├── services/
│   ├── inventory-service/        ← Go Gin + SQLite
│   ├── payment-service/          ← Python FastAPI + SQLite
│   └── order-service/            ← Java Spring Boot + H2
├── observability/
│   └── otel-collector/           ← OTel Collector config (OTLP → Elastic Cloud)
├── deployment/
│   ├── kubernetes/               ← K8s manifests (Deployment, Service, Ingress)
│   └── openshift/                ← OpenShift manifests (Deployment, Service, Route)
├── seed/
│   └── seed-data.json            ← Initial product catalog (loaded on first start)
└── scripts/
    ├── start-demo.sh / Start-Demo.ps1
    ├── stop-demo.sh  / Stop-Demo.ps1
    └── reset-demo.sh / Reset-Demo.ps1
```

---

## Elastic Cloud Setup

### 1. Get your APM credentials

1. Open your [Elastic Cloud console](https://cloud.elastic.co)
2. Go to your deployment → **APM & Fleet**
3. Copy the **APM Server URL**
4. Go to **Stack Management → API Keys** → create a key with APM writer permissions
5. The API Key value to use is `id:api_key` — base64-encode the whole string:
   ```bash
   echo -n 'your-id:your-api-key' | base64
   ```

### 2. Fill in `.env`

```bash
ELASTIC_APM_SERVER_URL=https://xxxx.apm.us-east-1.aws.elastic-cloud.com
ELASTIC_API_KEY=base64encodedkey==
NEXT_PUBLIC_ELASTIC_APM_SERVER_URL=https://xxxx.apm.us-east-1.aws.elastic-cloud.com
```

### 3. Verify the OTel Collector is shipping data

```bash
docker compose logs otel-collector --tail=30
```

- `Everything is ready. Begin running and processing data.` → collector is up
- `401 Unauthorized` → `ELASTIC_API_KEY` is wrong
- `connection refused` → check `ELASTIC_APM_SERVER_URL`

---

## Observability Coverage

| Signal | Instrumentation | Where to look in Elastic APM |
|--------|----------------|------------------------------|
| Browser page loads & Core Web Vitals | Elastic RUM (`@elastic/apm-rum`) | APM → User Experience |
| Distributed traces across all services | OTel auto-instrumentation | APM → Traces |
| Service dependency graph | W3C `traceparent` header propagation | APM → Service Map |
| Database query spans | OTel JDBC / SQLite / Go instrumentation | APM → Trace Waterfall |
| Application errors & stack traces | OTel exception events | APM → Errors |
| JVM metrics | Spring Boot Actuator + OTel | APM → Metrics |
| Go runtime metrics | OTel Go SDK | APM → Metrics |
| Python runtime metrics | OTel Python SDK | APM → Metrics |
