FROM vllm/vllm-openai:latest

ARG DEBIAN_FRONTEND=noninteractive

RUN apt-get update -qq && \
    apt-get install -y -qq --no-install-recommends tmux curl ca-certificates && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

ARG PROMETHEUS_VERSION=2.55.1
ARG LOKI_VERSION=3.1.1
ARG GRAFANA_VERSION=11.2.0

RUN mkdir -p /opt/bin/prometheus /opt/bin/loki /opt/bin/promtail && \
    curl -fsSL "https://github.com/prometheus/prometheus/releases/download/v${PROMETHEUS_VERSION}/prometheus-${PROMETHEUS_VERSION}.linux-amd64.tar.gz" -o /tmp/prometheus.tar.gz && \
    tar -xzf /tmp/prometheus.tar.gz -C /opt/bin/prometheus --strip-components=1 --no-same-owner && \
    curl -fsSL "https://github.com/grafana/loki/releases/download/v${LOKI_VERSION}/loki-linux-amd64.zip" -o /tmp/loki.zip && \
    python3 -c "import zipfile; zipfile.ZipFile('/tmp/loki.zip').extractall('/opt/bin/loki')" && \
    mv /opt/bin/loki/loki-linux-amd64 /opt/bin/loki/loki && chmod +x /opt/bin/loki/loki && \
    curl -fsSL "https://github.com/grafana/loki/releases/download/v${LOKI_VERSION}/promtail-linux-amd64.zip" -o /tmp/promtail.zip && \
    python3 -c "import zipfile; zipfile.ZipFile('/tmp/promtail.zip').extractall('/opt/bin/promtail')" && \
    mv /opt/bin/promtail/promtail-linux-amd64 /opt/bin/promtail/promtail && chmod +x /opt/bin/promtail/promtail && \
    rm -f /tmp/prometheus.tar.gz /tmp/loki.zip /tmp/promtail.zip && \
    curl -fsSL "https://dl.grafana.com/oss/release/grafana-${GRAFANA_VERSION}.linux-amd64.tar.gz" -o /tmp/grafana.tar.gz && \
    mkdir -p /opt/grafana && \
    tar -xzf /tmp/grafana.tar.gz -C /opt/grafana --strip-components=1 --no-same-owner && \
    rm -f /tmp/grafana.tar.gz

COPY configs/ /opt/configs/
COPY grafana/dashboards/vllm.json /opt/configs/grafana/dashboards/vllm.json
RUN mkdir -p /opt/configs/grafana/datasources /opt/configs/grafana/alerting /opt/configs/grafana/plugins && \
    mv /opt/configs/datasource.yml /opt/configs/grafana/datasources/datasource.yml && \
    mv /opt/configs/dashboard.yml /opt/configs/grafana/dashboards/dashboard.yml
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

EXPOSE 8000 9090 3100 3000 9080

ENTRYPOINT ["/entrypoint.sh"]
