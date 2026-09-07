#!/usr/bin/env bash
# One-time install of Prometheus, Loki, Promtail, and Grafana as native binaries.
# No Docker required/used — RunPod pods can't run nested docker-compose.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BIN_DIR="$SCRIPT_DIR/bin"
mkdir -p "$BIN_DIR"

PROMETHEUS_VERSION=2.55.1
LOKI_VERSION=3.1.1
GRAFANA_VERSION=11.2.0

for tool in curl tar python3; do
  command -v "$tool" >/dev/null || { echo "Missing required tool: $tool" >&2; exit 1; }
done

if [ ! -x "$BIN_DIR/prometheus/prometheus" ]; then
  echo "Installing Prometheus $PROMETHEUS_VERSION..."
  curl -fsSL "https://github.com/prometheus/prometheus/releases/download/v${PROMETHEUS_VERSION}/prometheus-${PROMETHEUS_VERSION}.linux-amd64.tar.gz" -o /tmp/prometheus.tar.gz
  mkdir -p "$BIN_DIR/prometheus"
  tar -xzf /tmp/prometheus.tar.gz -C "$BIN_DIR/prometheus" --strip-components=1 --no-same-owner
fi

if [ ! -x "$BIN_DIR/loki/loki" ]; then
  echo "Installing Loki $LOKI_VERSION..."
  curl -fsSL "https://github.com/grafana/loki/releases/download/v${LOKI_VERSION}/loki-linux-amd64.zip" -o /tmp/loki.zip
  mkdir -p "$BIN_DIR/loki"
  python3 -c "import zipfile; zipfile.ZipFile('/tmp/loki.zip').extractall('$BIN_DIR/loki')"
  mv "$BIN_DIR/loki/loki-linux-amd64" "$BIN_DIR/loki/loki"
  chmod +x "$BIN_DIR/loki/loki"
fi

if [ ! -x "$BIN_DIR/promtail/promtail" ]; then
  echo "Installing Promtail $LOKI_VERSION..."
  curl -fsSL "https://github.com/grafana/loki/releases/download/v${LOKI_VERSION}/promtail-linux-amd64.zip" -o /tmp/promtail.zip
  mkdir -p "$BIN_DIR/promtail"
  python3 -c "import zipfile; zipfile.ZipFile('/tmp/promtail.zip').extractall('$BIN_DIR/promtail')"
  mv "$BIN_DIR/promtail/promtail-linux-amd64" "$BIN_DIR/promtail/promtail"
  chmod +x "$BIN_DIR/promtail/promtail"
fi

if [ ! -x "$BIN_DIR/grafana/bin/grafana-server" ]; then
  echo "Installing Grafana $GRAFANA_VERSION..."
  curl -fsSL "https://dl.grafana.com/oss/release/grafana-${GRAFANA_VERSION}.linux-amd64.tar.gz" -o /tmp/grafana.tar.gz
  mkdir -p "$BIN_DIR/grafana"
  tar -xzf /tmp/grafana.tar.gz -C "$BIN_DIR/grafana" --strip-components=1 --no-same-owner
fi

echo "Install complete."
