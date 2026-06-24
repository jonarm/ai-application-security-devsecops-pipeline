# Minimal, non-root container for the RAG API service.
# Trivy (.github/workflows/trivy.yml) scans this image as part of the
# CI/CD static gate — see docs/architecture-overview.md for where this
# fits in the pipeline.

FROM python:3.12-slim AS base

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY . .

# Run as a non-root user — required to pass the Restricted Pod Security
# Standard applied in kubernetes/pod-security.yaml.
RUN useradd --create-home --shell /bin/bash appuser
USER appuser

EXPOSE 8000

CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8000"]