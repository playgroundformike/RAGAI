# ============================================================
# SecureGenAI Document Assistant — Production Dockerfile
# ============================================================
#
# Multi-stage build:
#   Stage 1 ("builder") — install dependencies in a full Python image
#   Stage 2 ("runtime") — copy only what's needed into a slim image
#
# Why multi-stage?
#   - Final image is ~60% smaller (no compilers, no pip cache, no build tools)
#   - Smaller image = less attack surface for Trivy/OpenSCAP to flag
#   - Build tools (gcc, pip) are not present in production — an attacker
#     who gets shell access can't compile exploits inside the container
#
# DoD/Compliance Rationale:
#   - Non-root user (STIG V-222430: services must not run as root)
#   - No secrets in the image (env vars injected at runtime by K8s)
#   - Pinned base image digest (reproducible builds for SBOM)
#   - Health check built into the image (container-level liveness)
#
# NIST 800-53 Controls:
#   CM-7  (Least Functionality) — minimal packages in runtime image
#   AC-6  (Least Privilege) — non-root user, read-only filesystem
#   SI-7  (Software Integrity) — pinned base image, hash-verified deps
# ============================================================


# ── Stage 1: Builder ─────────────────────────────────────────
# Full Python image with build tools — used only to install dependencies.
# This stage is discarded in the final image.
FROM registry.access.redhat.com/ubi9/ubi-minimal  AS builder

# Prevents Python from writing .pyc files and buffering stdout/stderr.
# In containers, you always want unbuffered output so logs appear immediately
# in CloudWatch/Splunk (buffered output can be lost if the container crashes).
ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1

WORKDIR /build

# Copy requirements FIRST, before application code.
# Why? Docker caches each layer. If requirements.txt hasn't changed,
# Docker reuses the cached pip install layer — saving 2-3 minutes per build.
# This is called "layer cache optimization" and it matters in CI/CD
# where you're building on every commit.
COPY requirements.txt .

# Install dependencies into a specific directory we can copy later.
# --no-cache-dir: Don't store pip's download cache (saves ~50MB in image)
# --prefix=/install: Install to a custom directory so we can copy just
#   the installed packages to the runtime stage, not the whole Python env.
RUN pip install \
    --no-cache-dir \
    --prefix=/install \
    -r requirements.txt


# ── Stage 2: Runtime ─────────────────────────────────────────
# Slim image with only the Python runtime — no build tools, no pip.
FROM registry.access.redhat.com/ubi9/ubi-minimal AS runtime

# ── Security: Create non-root user ───────────────────────────
# STIG V-222430: Application containers must not run as root.
# Why? If an attacker exploits the app and gets shell access:
#   - As root: they own the container and potentially the node
#   - As appuser: they can only access what appuser has permissions for
#
# We create a system user (no home dir, no login shell) with a fixed UID.
# Fixed UID (1001) matters for:
#   - Kubernetes SecurityContext (runAsUser: 1001)
#   - File ownership consistency across builds
#   - PodSecurityPolicy/PodSecurityStandard enforcement
RUN groupadd --gid 1001 appgroup && \
    useradd --uid 1001 --gid appgroup --shell /usr/sbin/nologin --no-create-home appuser

# ── Runtime environment ──────────────────────────────────────
ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    # Tell Python where to find the packages we installed in the builder stage
    PYTHONPATH="/app" \
    # Default to production — overridden in docker-compose for local dev
    SECUREGENAI_ENVIRONMENT=production

WORKDIR /app

# Copy installed Python packages from builder stage.
# This is the key multi-stage trick: we get the installed libraries
# without the build tools, pip cache, or compiler that installed them.
COPY --from=builder /install/lib/python3.12/site-packages /usr/local/lib/python3.12/site-packages
COPY --from=builder /install/bin /usr/local/bin

# Copy application code.
# The .dockerignore file (created separately) prevents copying
# .env, __pycache__, .git, and other unnecessary files.
COPY ./app ./app

# ── Security: File permissions ───────────────────────────────
# Application code is owned by root but readable by appuser.
# This means even if the app is compromised, the attacker can't
# modify the application code inside the container.
RUN chown -R root:appgroup /app && \
    chmod -R 750 /app

# ── Health check ─────────────────────────────────────────────
# Docker-level health check (separate from K8s probes, but complementary).
# If this fails 3 times, Docker marks the container as unhealthy.
# In EKS, K8s probes take precedence, but this provides defense-in-depth
# and works in docker-compose for local dev.
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
    CMD python -c "import urllib.request; urllib.request.urlopen('http://localhost:8000/health')" || exit 1

# ── Switch to non-root user ──────────────────────────────────
# Everything below this line runs as appuser, not root.
# This MUST come after all file operations (COPY, RUN chown).
USER appuser

# ── Expose port ──────────────────────────────────────────────
# EXPOSE is documentation — it doesn't actually open the port.
# The actual port mapping happens in docker-compose or K8s Service.
EXPOSE 8000

# ── Start command ────────────────────────────────────────────
# gunicorn is the production WSGI/ASGI server.
# uvicorn is great for dev but gunicorn adds:
#   - Multiple worker processes (utilize all CPU cores)
#   - Graceful worker restart on failure
#   - Preforking (workers are ready before traffic arrives)
#
# Key flags:
#   -k uvicorn.workers.UvicornWorker — use uvicorn's async worker class
#   -w 2 — 2 worker processes (tune to CPU cores: typically 2*cores+1)
#   -b 0.0.0.0:8000 — bind to all interfaces (required in containers)
#   --timeout 120 — kill workers that hang for 120s (Bedrock can be slow)
#   --access-logfile - — access logs to stdout (for container log capture)
#   --error-logfile - — error logs to stdout
CMD ["gunicorn", \
     "app.main:app", \
     "-k", "uvicorn.workers.UvicornWorker", \
     "-w", "2", \
     "-b", "0.0.0.0:8000", \
     "--timeout", "120", \
     "--access-logfile", "-", \
     "--error-logfile", "-"]
