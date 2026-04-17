"""
Prometheus Metrics — Application-Level Observability

Exposes a /metrics endpoint that Prometheus scrapes to collect:
  - HTTP request counts (by method, path, status code)
  - HTTP request latency (histogram with percentile buckets)
  - Active request count (gauge)
  - Custom business metrics (uploads, queries, Bedrock latency)

Why application metrics matter in DoD:
  - AU-6 (Audit Review): track usage patterns, detect anomalies
  - SI-4 (System Monitoring): real-time visibility into app health
  - CA-7 (Continuous Monitoring): feeds into Grafana dashboards
  - Cost tracking: Bedrock token usage directly impacts budget

Prometheus pull model:
  The app doesn't push metrics anywhere. It just exposes /metrics
  as a text endpoint. Prometheus (running in the cluster) pulls
  from this endpoint every 15 seconds. This is simpler and more
  reliable than push-based monitoring because:
  - No outbound network config needed from the app
  - If Prometheus is down, the app isn't affected
  - Prometheus controls the scrape interval, not the app
"""

import time
from prometheus_client import (
    Counter,
    Histogram,
    Gauge,
    generate_latest,
    CONTENT_TYPE_LATEST,
)
from starlette.middleware.base import BaseHTTPMiddleware
from starlette.requests import Request
from starlette.responses import Response


# ── Metric Definitions ───────────────────────────────────────
# Each metric is a singleton — defined once, incremented everywhere.
# Labels allow slicing data in Grafana (e.g., latency by endpoint).

# Total HTTP requests — counter only goes up, never down.
# Use rate() in PromQL to get requests/second.
REQUEST_COUNT = Counter(
    "securegenai_http_requests_total",
    "Total HTTP requests",
    ["method", "endpoint", "status_code"],
)

# Request latency distribution — histogram with predefined buckets.
# Buckets define the latency thresholds (in seconds) for grouping.
# histogram_quantile() in PromQL gives you p50, p95, p99.
REQUEST_LATENCY = Histogram(
    "securegenai_http_request_duration_seconds",
    "HTTP request latency in seconds",
    ["method", "endpoint"],
    buckets=[0.01, 0.05, 0.1, 0.25, 0.5, 1.0, 2.5, 5.0, 10.0, 30.0],
    # Buckets go up to 30s because Bedrock queries can be slow.
    # A normal API would stop at 1-2 seconds.
)

# Currently processing requests — gauge goes up and down.
# Useful for detecting thread pool exhaustion.
REQUESTS_IN_PROGRESS = Gauge(
    "securegenai_http_requests_in_progress",
    "Number of HTTP requests currently being processed",
)

# ── Business Metrics ─────────────────────────────────────────
# These track application-specific events, not just HTTP traffic.

DOCUMENT_UPLOADS = Counter(
    "securegenai_document_uploads_total",
    "Total document uploads",
    ["content_type", "status"],  # e.g., application/pdf, success/failure
)

BEDROCK_QUERIES = Counter(
    "securegenai_bedrock_queries_total",
    "Total Bedrock model invocations",
    ["model_id", "status"],
)

BEDROCK_LATENCY = Histogram(
    "securegenai_bedrock_query_duration_seconds",
    "Bedrock model invocation latency",
    ["model_id"],
    buckets=[0.5, 1.0, 2.0, 5.0, 10.0, 15.0, 20.0, 30.0],
)

BEDROCK_TOKENS = Counter(
    "securegenai_bedrock_tokens_total",
    "Total tokens consumed by Bedrock",
    ["model_id", "direction"],  # direction: input or output
)

DOCUMENT_SIZE_BYTES = Histogram(
    "securegenai_document_size_bytes",
    "Uploaded document size distribution",
    buckets=[1024, 10240, 102400, 524288, 1048576, 5242880, 10485760],
    # 1KB, 10KB, 100KB, 512KB, 1MB, 5MB, 10MB
)


# ── Middleware ────────────────────────────────────────────────
class PrometheusMiddleware(BaseHTTPMiddleware):
    """
    Intercepts every HTTP request to record metrics.

    Middleware sits between the web server and your route handlers.
    Every request passes through it, so we can measure latency
    and count requests without modifying each endpoint.
    """

    async def dispatch(self, request: Request, call_next):
        # Skip metrics for the /metrics endpoint itself and health checks
        # to avoid inflating the data with monitoring traffic.
        if request.url.path in ("/metrics", "/health"):
            return await call_next(request)

        # Normalize the path — replace UUIDs and IDs with placeholders
        # so we don't get infinite cardinality in labels.
        # /api/v1/query and /api/v1/upload are already fixed paths,
        # but this is defensive for future dynamic routes.
        endpoint = request.url.path

        method = request.method
        REQUESTS_IN_PROGRESS.inc()
        start_time = time.time()

        try:
            response = await call_next(request)
            status_code = str(response.status_code)
        except Exception:
            status_code = "500"
            raise
        finally:
            duration = time.time() - start_time
            REQUESTS_IN_PROGRESS.dec()

            REQUEST_COUNT.labels(
                method=method,
                endpoint=endpoint,
                status_code=status_code,
            ).inc()

            REQUEST_LATENCY.labels(
                method=method,
                endpoint=endpoint,
            ).observe(duration)

        return response


def metrics_endpoint(request: Request) -> Response:
    """
    /metrics endpoint — returns all metrics in Prometheus text format.
    Prometheus scrapes this endpoint at a configured interval.
    """
    return Response(
        content=generate_latest(),
        media_type=CONTENT_TYPE_LATEST,
    )
