# Stage 1: Build the application virtual environment. Alpine has a far smaller
# OS package footprint than the Debian slim image previously used here.
FROM python:3.11-alpine3.22 AS builder
WORKDIR /build
COPY requirements.txt .
RUN apk upgrade --no-cache \
    && python -m venv /venv \
    && /venv/bin/pip install --no-cache-dir --upgrade pip \
    && /venv/bin/pip install --no-cache-dir -r requirements.txt \
    && rm -rf /venv/lib/python3.11/site-packages/pip* \
              /venv/lib/python3.11/site-packages/setuptools* \
              /venv/lib/python3.11/site-packages/wheel* \
              /venv/lib/python3.11/site-packages/pkg_resources

# Stage 2: Keep only Python, the application, and its runtime dependencies.
FROM python:3.11-alpine3.22 AS runner
ENV PATH="/venv/bin:${PATH}" \
    PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1

RUN apk upgrade --no-cache \
    && rm -rf /usr/local/lib/python3.11/site-packages/pip* \
              /usr/local/lib/python3.11/site-packages/setuptools* \
              /usr/local/lib/python3.11/site-packages/wheel* \
              /usr/local/lib/python3.11/site-packages/jaraco* \
    && rm -f /usr/local/bin/pip /usr/local/bin/pip3 \
    && addgroup -S photoshare \
    && adduser -S -G photoshare -s /sbin/nologin photoshare
WORKDIR /app
COPY --from=builder --chown=photoshare:photoshare /venv /venv
COPY --chown=photoshare:photoshare . .
USER photoshare
EXPOSE 8000
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
    CMD ["python", "-c", "import urllib.request; urllib.request.urlopen('http://localhost:8000/health')"]
    
CMD ["gunicorn", "--bind", "0.0.0.0:8000", "--workers", "3", "--timeout", "30", "--access-logfile", "-", "--error-logfile", "-", "app:app"]
