# Stage 1: Build dependencies
FROM python:3.11-slim AS builder
WORKDIR /build
COPY requirements.txt .
RUN pip install --no-cache-dir --prefix=/install -r requirements.txt

# Stage 2: Final minimal runtime image
FROM python:3.11-slim AS runner
RUN groupadd -r photoshare && useradd -r -g photoshare -s /bin/false photoshare
WORKDIR /app
COPY --from=builder /install /usr/local
COPY . .
RUN chown -R photoshare:photoshare /app
USER photoshare
EXPOSE 8000
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
    CMD python -c "import urllib.request; urllib.request.urlopen('http://localhost:8000/health')"
    
CMD ["gunicorn", "--bind", "0.0.0.0:8000", "--workers", "3", "--timeout", "30", "--access-logfile", "-", "--error-logfile", "-", "app:app"]
