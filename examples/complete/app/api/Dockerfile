# checkov:skip=CKV_DOCKER_2:Kubernetes ignores Docker HEALTHCHECK; health is checked by the pod probes.
FROM python:3.13-slim

ENV PYTHONDONTWRITEBYTECODE=1 PYTHONUNBUFFERED=1
WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY main.py .

# Numeric UID so Kubernetes can enforce runAsNonRoot.
USER 10001
CMD ["python", "main.py"]
