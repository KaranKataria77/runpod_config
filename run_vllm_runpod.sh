#!/usr/bin/env bash
set -euo pipefail

: "${GF_ADMIN_PASSWORD:?set GF_ADMIN_PASSWORD before running, e.g. GF_ADMIN_PASSWORD=mysecret ./run_vllm_runpod.sh}"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BIN_DIR="$SCRIPT_DIR/bin"
DATA_DIR="$SCRIPT_DIR/data"

for tool in python3 pip openssl tmux; do
  command -v "$tool" >/dev/null || MISSING="${MISSING:-}${MISSING:+ }$tool"
done

if [ -n "${MISSING:-}" ]; then
  # tmux is the only one apt can plausibly fix here; the rest are expected on a vLLM base image.
  if echo "$MISSING" | grep -qw tmux && ! command -v tmux >/dev/null; then
    apt-get update -qq && apt-get install -y -qq tmux
    MISSING="$(echo "$MISSING" | sed 's/\btmux\b//')"
  fi
  if [ -n "$(echo "$MISSING" | tr -d '[:space:]')" ]; then
    echo "Missing required tool(s):$MISSING" >&2
    exit 1
  fi
fi

python3 -c "import vllm" 2>/dev/null || pip install -q vllm
python3 -c "import flashinfer" 2>/dev/null || pip install -q -U flashinfer-python

export VLLM_USE_FLASHINFER_SAMPLER=0
export HF_HOME=/workspace/hf_cache
export VLLM_API_KEY=$(openssl rand -hex 32)
VLLM_API_KEY_FILE=/workspace/vllm_api_key.txt
VLLM_LOG_PATH=/root/vllm.log
MODEL_LABEL="Qwen3.8-27B"
MODEL_SLUG="$(echo "$MODEL_LABEL" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]/-/g')"

mkdir -p "$HF_HOME" /workspace/models
echo "$VLLM_API_KEY" > "$VLLM_API_KEY_FILE"
echo "VLLM_API_KEY=$VLLM_API_KEY"

# --- vLLM ---

tmux kill-session -t vllm 2>/dev/null || true
pkill -f "vllm serve Qwen/Qwen3.8-27B" 2>/dev/null || true
sleep 1

tmux new-session -d -s vllm -n vllm-server "\
export VLLM_USE_FLASHINFER_SAMPLER=0; \
export HF_HOME=$HF_HOME; \
export VLLM_API_KEY=$VLLM_API_KEY; \
vllm serve Qwen/Qwen3.8-27B \
  --host 0.0.0.0 \
  --port 8000 \
  --tensor-parallel-size 4 \
  --api-key \$VLLM_API_KEY \
  --download-dir /workspace/models \
  --max-model-len 8192 \
  2>&1 | tee -a $VLLM_LOG_PATH"

# --- Monitoring stack (Prometheus, Loki, Promtail, Grafana) ---

bash "$SCRIPT_DIR/install.sh"

mkdir -p \
  "$DATA_DIR/prometheus" \
  "$DATA_DIR/loki" \
  "$DATA_DIR/grafana/data" \
  "$DATA_DIR/grafana/logs" \
  "$DATA_DIR/grafana/plugins" \
  "$DATA_DIR/grafana/provisioning/datasources" \
  "$DATA_DIR/grafana/provisioning/dashboards"

cp "$SCRIPT_DIR/grafana/provisioning/datasources/datasource.yml" \
  "$DATA_DIR/grafana/provisioning/datasources/datasource.yml"

sed \
  -e "s#__VLLM_TARGET__#localhost:8000#" \
  -e "s#__MODEL_LABEL__#${MODEL_LABEL}#" \
  -e "s#__BEARER_TOKEN_LINE__#    bearer_token_file: $VLLM_API_KEY_FILE#" \
  "$SCRIPT_DIR/prometheus/prometheus.yml.tmpl" > "$DATA_DIR/prometheus.yml"

sed \
  -e "s#__MODEL_SLUG__#${MODEL_SLUG}#" \
  -e "s#__VLLM_LOG_PATH__#${VLLM_LOG_PATH}#" \
  "$SCRIPT_DIR/promtail/promtail-config.yml.tmpl" > "$DATA_DIR/promtail-config.yml"

cat > "$DATA_DIR/grafana/provisioning/dashboards/dashboard.yml" <<EOF
apiVersion: 1

providers:
  - name: vllm
    orgId: 1
    folder: ""
    type: file
    disableDeletion: false
    updateIntervalSeconds: 10
    allowUiUpdates: true
    options:
      path: $SCRIPT_DIR/grafana/dashboards
EOF

# tmux's kill-session sends SIGHUP, which these binaries don't always honor,
# so they can survive as orphans holding their ports across restarts.
pkill -f "$BIN_DIR/prometheus/prometheus " 2>/dev/null || true
pkill -f "$BIN_DIR/loki/loki " 2>/dev/null || true
pkill -f "$BIN_DIR/promtail/promtail " 2>/dev/null || true
pkill -f "homepath=$BIN_DIR/grafana" 2>/dev/null || true
sleep 1

tmux new-window -t vllm -n prometheus \
  "$BIN_DIR/prometheus/prometheus \
    --config.file=$DATA_DIR/prometheus.yml \
    --storage.tsdb.path=$DATA_DIR/prometheus \
    --web.listen-address=:9090"

tmux new-window -t vllm -n loki \
  "LOKI_PATH_PREFIX=$DATA_DIR/loki $BIN_DIR/loki/loki \
    -config.file=$SCRIPT_DIR/loki/loki-config.yml \
    -config.expand-env=true"

tmux new-window -t vllm -n promtail \
  "$BIN_DIR/promtail/promtail -config.file=$DATA_DIR/promtail-config.yml"

tmux new-window -t vllm -n grafana \
  "GF_PATHS_DATA=$DATA_DIR/grafana/data \
   GF_PATHS_LOGS=$DATA_DIR/grafana/logs \
   GF_PATHS_PLUGINS=$DATA_DIR/grafana/plugins \
   GF_PATHS_PROVISIONING=$DATA_DIR/grafana/provisioning \
   GF_SECURITY_ADMIN_USER=admin \
   GF_SECURITY_ADMIN_PASSWORD=$GF_ADMIN_PASSWORD \
   GF_AUTH_ANONYMOUS_ENABLED=false \
   $BIN_DIR/grafana/bin/grafana-server --homepath=$BIN_DIR/grafana"

echo "vLLM + monitoring stack starting in tmux session 'vllm' (windows: vllm-server, prometheus, loki, promtail, grafana)."
echo "Attach with: tmux attach -t vllm  (Ctrl+b then window number to switch, Ctrl+b d to detach)"
echo "API key saved to $VLLM_API_KEY_FILE"
echo "Prometheus: http://<pod-host>:9090   Grafana: http://<pod-host>:3000"
