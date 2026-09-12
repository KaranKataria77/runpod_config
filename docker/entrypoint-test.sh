#!/usr/bin/env bash
set -euo pipefail

# Test build: no vLLM, no GPUs. Verifies tmux + all monitoring stack installs and starts.
: "${GF_ADMIN_PASSWORD:?set GF_ADMIN_PASSWORD}"

mkdir -p /var/lib/prometheus /var/lib/loki /var/lib/grafana/data /var/lib/grafana/logs
touch /var/log/vllm.log

# Fake "vLLM" workload: a small python HTTP server exposing /metrics on :8000
# (runs in tmux like the real vllm serve does)
cat > /tmp/fake_vllm.py <<'PYEOF'
import http.server, socketserver

class Handler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        body = b"fake_vllm_up 1\n"
        self.send_response(200)
        self.send_header("Content-Type", "text/plain")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)
    def log_message(self, *args):
        pass

with socketserver.TCPServer(("0.0.0.0", 8000), Handler) as httpd:
    httpd.serve_forever()
PYEOF

tmux kill-session -t vllm 2>/dev/null || true
tmux new -d -s vllm "python3 /tmp/fake_vllm.py 2>&1 | tee -a /var/log/vllm.log; exec bash"

# --- Monitoring stack ---

/opt/bin/prometheus/prometheus \
  --config.file=/opt/configs/prometheus.yml \
  --storage.tsdb.path=/var/lib/prometheus \
  --web.listen-address=:9090 \
  > /var/log/prometheus.log 2>&1 &

/opt/bin/loki/loki \
  -config.file=/opt/configs/loki-config.yml \
  > /var/log/loki.log 2>&1 &

/opt/bin/promtail/promtail \
  -config.file=/opt/configs/promtail-config.yml \
  > /var/log/promtail.log 2>&1 &

GF_PATHS_DATA=/var/lib/grafana/data \
GF_PATHS_LOGS=/var/lib/grafana/logs \
GF_PATHS_PLUGINS=/var/lib/grafana/plugins \
GF_PATHS_PROVISIONING=/opt/configs/grafana \
GF_SECURITY_ADMIN_USER=admin \
GF_SECURITY_ADMIN_PASSWORD="$GF_ADMIN_PASSWORD" \
GF_AUTH_ANONYMOUS_ENABLED=false \
/opt/grafana/bin/grafana-server --homepath=/opt/grafana \
  > /var/log/grafana.log 2>&1 &

echo "Stack started. Fake vLLM in tmux session 'vllm'. Prometheus :9090, Grafana :3000, Loki :3100"

wait
