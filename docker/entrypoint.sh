#!/usr/bin/env bash
set -euo pipefail

: "${NUM_GPUS:?set NUM_GPUS env var, e.g. NUM_GPUS=4}"
: "${GF_ADMIN_PASSWORD:?set GF_ADMIN_PASSWORD env var}"
: "${VLLM_API_KEY:?set VLLM_API_KEY env var}"

MODEL="Qwen/Qwen3.8-27B"
export HF_HOME=/workspace/hf_cache
VLLM_LOG_PATH=/var/log/vllm.log

mkdir -p "$HF_HOME" /workspace/models /var/lib/prometheus /var/lib/loki \
         /var/lib/grafana/data /var/lib/grafana/logs
touch "$VLLM_LOG_PATH"

# --- vLLM in tmux (attach with: docker compose exec vllm tmux attach -t vllm) ---
tmux kill-session -t vllm 2>/dev/null || true

tmux new -d -s vllm "\
export HF_HOME=$HF_HOME; \
export VLLM_API_KEY=$VLLM_API_KEY; \
vllm serve $MODEL \
  --host 0.0.0.0 \
  --port 8000 \
  --tensor-parallel-size $NUM_GPUS \
  --api-key \$VLLM_API_KEY \
  --download-dir /workspace/models \
  --max-model-len 8192 \
  2>&1 | tee -a $VLLM_LOG_PATH; \
echo '--- vllm serve exited (see above, or $VLLM_LOG_PATH, for details) ---'; \
exec bash"

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

echo "vLLM starting in tmux session 'vllm'. Attach with: docker compose exec vllm tmux attach -t vllm"
echo "Prometheus: :9090   Grafana: :3000   Loki: :3100   (logs in /var/log/)"

# Keep the container alive
wait
