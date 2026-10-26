# Stage 1: Build the React + Vite + Tailwind dark-themed Web GUI
FROM node:22-alpine AS frontend-builder
WORKDIR /build/frontend
COPY frontend/package.json ./
RUN npm install --no-audit --no-fund
COPY frontend/ ./
RUN npm run build

# Stage 2: Python FastAPI + High-Precision Animation & Govee LAN/Cloud Controller
FROM python:3.12-slim
WORKDIR /app

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PYTHONPATH=/app \
    DATA_DIR=/mnt/media/govee_lights_sync/data \
    PORT=8200 \
    HOST=0.0.0.0

RUN apt-get update && apt-get install -y --no-install-recommends \
    curl \
    iproute2 \
    iputils-ping \
    && rm -rf /var/lib/apt/lists/*

COPY backend/requirements.txt ./requirements.txt
RUN pip install --no-cache-dir -r requirements.txt

COPY backend/ ./backend/
COPY examples/ ./examples/
COPY tests/ ./tests/
COPY --from=frontend-builder /build/frontend/dist ./frontend/dist

RUN mkdir -p /mnt/media/govee_lights_sync/data

EXPOSE 8200
EXPOSE 4001/udp
EXPOSE 4002/udp
EXPOSE 4003/udp

HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
  CMD curl -fsS http://127.0.0.1:${PORT:-8200}/api/health || exit 1

CMD ["python", "-m", "uvicorn", "backend.app.main:app", "--host", "0.0.0.0", "--port", "8200", "--no-access-log"]
