import os

from opentelemetry import trace
from opentelemetry.exporter.otlp.proto.grpc.trace_exporter import OTLPSpanExporter
from opentelemetry.instrumentation.fastapi import FastAPIInstrumentor
from opentelemetry.sdk.resources import Resource
from opentelemetry.sdk.trace import TracerProvider
from opentelemetry.sdk.trace.export import BatchSpanProcessor
from opentelemetry.semconv.resource import ResourceAttributes

from fastapi import FastAPI

# --- OTel setup (must run before app creation) ---
_service_name = os.getenv("OTEL_SERVICE_NAME", "demo-payment-service")
_environment = os.getenv("ENVIRONMENT", "local")
_otlp_endpoint = os.getenv("OTEL_EXPORTER_OTLP_ENDPOINT", "http://localhost:4317")

resource = Resource.create({
    ResourceAttributes.SERVICE_NAME: _service_name,
    ResourceAttributes.DEPLOYMENT_ENVIRONMENT: _environment,
})

provider = TracerProvider(resource=resource)
exporter = OTLPSpanExporter(endpoint=_otlp_endpoint, insecure=True)
provider.add_span_processor(BatchSpanProcessor(exporter))
trace.set_tracer_provider(provider)

# --- FastAPI app ---
from app.database import init_db
from app.routers.payments import router as payments_router

app = FastAPI(title="Payment Service", version="1.0.0")

FastAPIInstrumentor.instrument_app(app)


@app.on_event("startup")
def startup():
    init_db()


@app.get("/health")
def health():
    return {"status": "ok", "service": "payment-service"}


app.include_router(payments_router)
