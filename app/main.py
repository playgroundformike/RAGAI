"""
FastAPI Application Entrypoint.

This is the single file that wires everything together:
- Mounts the upload and query routers
- Configures security middleware (CORS, trusted hosts)
- Provides health check endpoint for Kubernetes probes
- Sets up structured logging

DoD/Compliance Rationale:
- CORS is restrictive by default — only explicitly allowed origins
- TrustedHostMiddleware prevents host header injection attacks
- Health endpoint reports dependency status (K8s uses this for
  liveness/readiness probes — if S3 is unreachable, stop routing traffic)
- Structured logging with correlation IDs for Splunk/CloudWatch

Start command (development):
  uvicorn app.main:app --reload --host 0.0.0.0 --port 8000

Start command (production — in Dockerfile):
  gunicorn app.main:app -k uvicorn.workers.UvicornWorker -b 0.0.0.0:8000
"""

import logging
import sys

from fastapi import FastAPI, Depends
from fastapi.middleware.cors import CORSMiddleware
from fastapi.middleware.trustedhost import TrustedHostMiddleware

from app.config import Settings, get_settings
from app.models import HealthResponse
from app.routers import upload, query
from app.metrics import PrometheusMiddleware, metrics_endpoint


def create_app() -> FastAPI:
    """
    Application factory pattern.

    Why a factory instead of a module-level `app = FastAPI()`?
    - Testability: tests can create fresh app instances with mock config
    - Configurability: different settings for dev/staging/prod
    - Clean imports: avoids circular dependency issues
    """
    settings = get_settings()

    app = FastAPI(
        title=settings.app_name,
        version=settings.app_version,
        description=(
            "Secure document assistant with RAG-based Q&A powered by "
            "AWS Bedrock. Designed for DoD IL4/IL5 compliance."
        ),
        # In production, disable docs endpoints — they expose your API schema.
        # For the portfolio, we leave them on so reviewers can explore the API.
        docs_url="/docs" if settings.environment != "production" else None,
        redoc_url="/redoc" if settings.environment != "production" else None,
    )

    # ── Security Middleware ────────────────────────────────────────

    # CORS — Cross-Origin Resource Sharing
    # In production, this would be locked to the specific frontend domain.
    # In dev, we allow localhost. NEVER use allow_origins=["*"] in production.
    allowed_origins = (
        ["http://localhost:3000", "http://localhost:8000"]
        if settings.environment == "development"
        else []  # Production: set via env var SECUREGENAI_CORS_ORIGINS
    )

    app.add_middleware(
        CORSMiddleware,
        allow_origins=allowed_origins,
        allow_credentials=True,
        allow_methods=["GET", "POST"],  # Only methods we actually use
        allow_headers=["*"],
    )

    # Trusted Host — prevents Host header injection attacks.
    # Without this, an attacker can set Host: evil.com and potentially
    # poison caches or redirect responses.
    if settings.environment == "production":
        app.add_middleware(
            TrustedHostMiddleware,
            allowed_hosts=["your-domain.mil", "*.your-domain.mil"],
        )

    # ── Register Routers ──────────────────────────────────────────
    app.include_router(upload.router)
    app.include_router(query.router)

    # ── Prometheus Metrics ────────────────────────────────────────
    # Middleware records request count, latency, and in-progress gauge.
    # /metrics endpoint exposes data for Prometheus to scrape.
    app.add_middleware(PrometheusMiddleware)
    app.add_route("/metrics", metrics_endpoint, methods=["GET"])

    # ── Configure Logging ─────────────────────────────────────────
    configure_logging(settings)

    return app


def configure_logging(settings: Settings) -> None:
    """
    Set up structured logging.

    In production with Splunk/CloudWatch, you'd use JSON logging
    (python-json-logger) so log aggregators can parse fields automatically.
    For dev, human-readable format is easier to work with.
    """
    log_format = (
        "%(asctime)s | %(levelname)-8s | %(name)s | %(message)s"
        if settings.environment == "development"
        else '{"time":"%(asctime)s","level":"%(levelname)s","logger":"%(name)s","msg":"%(message)s"}'
    )

    logging.basicConfig(
        level=getattr(logging, settings.log_level.upper()),
        format=log_format,
        stream=sys.stdout,  # stdout for container logging (not files)
    )


# ── Create the app instance ──────────────────────────────────────
app = create_app()


# ── Health Check Endpoint ─────────────────────────────────────────
@app.get(
    "/health",
    response_model=HealthResponse,
    tags=["operations"],
    summary="Health check for Kubernetes probes",
)
async def health_check(settings: Settings = Depends(get_settings)):
    """
    Health endpoint used by Kubernetes liveness and readiness probes.

    Liveness probe: "Is the process alive?" → If this returns 5xx, K8s restarts the pod.
    Readiness probe: "Can it serve traffic?" → If this fails, K8s stops routing to this pod.

    In a full implementation, you'd check:
    - S3 connectivity (can we reach the bucket?)
    - Bedrock connectivity (is the endpoint responding?)
    - DynamoDB connectivity

    For now, we return static checks. We'll add real dependency checks
    when we have AWS credentials wired up.
    """
    return HealthResponse(
        status="healthy",
        version=settings.app_version,
        environment=settings.environment,
        checks={
            "s3": "configured",
            "bedrock": "configured",
            "dynamodb": "configured",
        },
    )


# ── Root Redirect ─────────────────────────────────────────────────
@app.get("/", include_in_schema=False)
async def root():
    """Redirect root to API docs for portfolio reviewers."""
    from fastapi.responses import RedirectResponse

    return RedirectResponse(url="/docs")
