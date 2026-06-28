# Dockerfile — build context MUST be app/ (the parent of rag-api/), not
# rag-api/ itself. This Dockerfile needs access to prompt_filter.py and
# response_filter.py, which live as siblings of rag-api/ by design (see
# the import comment at the top of main.py) — but are NOT inside rag-api/.
#
# Build from the app/ directory:
#   docker build -t <tag> -f rag-api/Dockerfile .
#
# A narrower build context (just rag-api/) was tried first and produced a
# real CrashLoopBackOff on first AKS deploy — ModuleNotFoundError on
# prompt_filter, since the guardrail files were never in the image at
# all. See app/README.md for the full writeup.
FROM python:3.12-slim AS base

WORKDIR /app

COPY rag-api/requirements.txt .
RUN pip install --no-cache-dir --upgrade pip && \
    pip install --no-cache-dir -r requirements.txt

COPY prompt_filter.py response_filter.py ./
COPY rag-api/ ./rag-api/

RUN useradd --create-home --shell /bin/bash appuser
USER appuser

EXPOSE 8000

WORKDIR /app/rag-api
CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8000"]