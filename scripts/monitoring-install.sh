#!/bin/bash
# =============================================================================
# monitoring-install.sh
# Installs: Prometheus, Grafana, Alertmanager, Node Exporter
#
# JENKINS_IP and GRAFANA_PASS are injected as env vars by the wrapper
# user_data script that Terraform generates via local_file. This file is
# a plain bash script — NOT processed by templatefile().
# =============================================================================

set -euo pipefail
exec >> /var/log/monitoring-install.log 2>&1

# ── Versions ──────────────────────────────────────────────────────────────────
PROM_VERSION="2.47.0"
ALERTMANAGER_VERSION="0.26.0"
NODE_EXPORTER_VERSION="1.6.1"
GRAFANA_VERSION="10.2.0"

echo "[$(date)] Starting monitoring installation..."
echo "[$(date)] JENKINS_IP=${JENKINS_IP}"

# ── System setup ──────────────────────────────────────────────────────────────
sudo yum update -y
sudo yum install -y wget tar

# ── Create system users ────────────────────────────────────────────────────────
for svc_user in prometheus alertmanager node_exporter; do
  if ! id "$svc_user" &>/dev/null; then
    sudo useradd --no-create-home --shell /bin/false "$svc_user"
  fi
done

# =============================================================================
# 1. NODE EXPORTER
# =============================================================================
cd /tmp
wget -q "https://github.com/prometheus/node_exporter/releases/download/v${NODE_EXPORTER_VERSION}/node_exporter-${NODE_EXPORTER_VERSION}.linux-amd64.tar.gz"
tar xzf "node_exporter-${NODE_EXPORTER_VERSION}.linux-amd64.tar.gz"
sudo cp "node_exporter-${NODE_EXPORTER_VERSION}.linux-amd64/node_exporter" /usr/local/bin/
sudo chown node_exporter:node_exporter /usr/local/bin/node_exporter

sudo tee /etc/systemd/system/node_exporter.service > /dev/null <<'SVCEOF'
[Unit]
Description=Node Exporter
After=network.target

[Service]
User=node_exporter
Group=node_exporter
ExecStart=/usr/local/bin/node_exporter
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
SVCEOF

# =============================================================================
# 2. PROMETHEUS
# =============================================================================
cd /tmp
wget -q "https://github.com/prometheus/prometheus/releases/download/v${PROM_VERSION}/prometheus-${PROM_VERSION}.linux-amd64.tar.gz"
tar xzf "prometheus-${PROM_VERSION}.linux-amd64.tar.gz"

sudo mkdir -p /etc/prometheus /var/lib/prometheus
sudo cp "prometheus-${PROM_VERSION}.linux-amd64/prometheus" /usr/local/bin/
sudo cp "prometheus-${PROM_VERSION}.linux-amd64/promtool"   /usr/local/bin/
sudo cp -r "prometheus-${PROM_VERSION}.linux-amd64/consoles"          /etc/prometheus/
sudo cp -r "prometheus-${PROM_VERSION}.linux-amd64/console_libraries" /etc/prometheus/
sudo chown -R prometheus:prometheus /etc/prometheus /var/lib/prometheus
sudo chown prometheus:prometheus /usr/local/bin/prometheus /usr/local/bin/promtool

# Write prometheus.yml — ${JENKINS_IP} is a bash variable expanded here
sudo bash -c "cat > /etc/prometheus/prometheus.yml" <<PROMEOF
global:
  scrape_interval:     15s
  evaluation_interval: 15s

alerting:
  alertmanagers:
    - static_configs:
        - targets: ['localhost:9093']

rule_files:
  - /etc/prometheus/rules/*.yml

scrape_configs:

  - job_name: 'prometheus'
    static_configs:
      - targets: ['localhost:9090']
        labels:
          instance: 'monitoring-server'

  - job_name: 'monitoring-node'
    static_configs:
      - targets: ['localhost:9100']
        labels:
          instance: 'monitoring-server'
          environment: 'dev'

  - job_name: 'jenkins-node'
    static_configs:
      - targets: ['${JENKINS_IP}:9100']
        labels:
          instance: 'Jenkins-Server'
          environment: 'dev'

  - job_name: 'jenkins'
    metrics_path: '/prometheus'
    static_configs:
      - targets: ['${JENKINS_IP}:8080']
        labels:
          instance: 'Jenkins-Server'
          environment: 'dev'

  - job_name: 'alertmanager'
    static_configs:
      - targets: ['localhost:9093']
        labels:
          instance: 'monitoring-server'
PROMEOF

sudo chown prometheus:prometheus /etc/prometheus/prometheus.yml

# ── Alert rules ───────────────────────────────────────────────────────────────
sudo mkdir -p /etc/prometheus/rules
sudo chown prometheus:prometheus /etc/prometheus/rules

sudo tee /etc/prometheus/rules/alerts.yml > /dev/null <<'RULESEOF'
groups:
  - name: instance_alerts
    rules:

      - alert: InstanceDown
        expr: up == 0
        for: 1m
        labels:
          severity: critical
        annotations:
          summary: "Instance {{ $labels.instance }} is DOWN"
          description: "{{ $labels.instance }} unreachable for more than 1 minute."

      - alert: HighCPUUsage
        expr: 100 - (avg by(instance) (rate(node_cpu_seconds_total{mode="idle"}[5m])) * 100) > 80
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "High CPU on {{ $labels.instance }}"
          description: "CPU above 80% for 5 min. Value: {{ $value | printf \"%.1f\" }}%"

      - alert: HighMemoryUsage
        expr: (1 - (node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes)) * 100 > 85
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "High memory on {{ $labels.instance }}"
          description: "Memory above 85%. Value: {{ $value | printf \"%.1f\" }}%"

      - alert: DiskSpaceLow
        expr: (node_filesystem_avail_bytes{mountpoint="/"} / node_filesystem_size_bytes{mountpoint="/"}) * 100 < 15
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "Low disk on {{ $labels.instance }}"
          description: "Less than 15% disk remaining."

  - name: jenkins_alerts
    rules:

      - alert: JenkinsDown
        expr: up{job="jenkins"} == 0
        for: 2m
        labels:
          severity: critical
        annotations:
          summary: "Jenkins is DOWN"
          description: "Jenkins has been unreachable for 2 minutes."

      - alert: JenkinsBuildFailureRateHigh
        expr: rate(jenkins_builds_failed_build_count_total[15m]) > 0.1
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "High Jenkins build failure rate"
          description: "More than 10% of builds failing in last 15 minutes."
RULESEOF

sudo chown prometheus:prometheus /etc/prometheus/rules/alerts.yml

sudo tee /etc/systemd/system/prometheus.service > /dev/null <<'SVCEOF'
[Unit]
Description=Prometheus Monitoring
After=network.target

[Service]
User=prometheus
Group=prometheus
ExecStart=/usr/local/bin/prometheus \
  --config.file=/etc/prometheus/prometheus.yml \
  --storage.tsdb.path=/var/lib/prometheus/ \
  --storage.tsdb.retention.time=15d \
  --web.listen-address=0.0.0.0:9090 \
  --web.enable-lifecycle
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
SVCEOF

# =============================================================================
# 3. ALERTMANAGER
# =============================================================================
cd /tmp
wget -q "https://github.com/prometheus/alertmanager/releases/download/v${ALERTMANAGER_VERSION}/alertmanager-${ALERTMANAGER_VERSION}.linux-amd64.tar.gz"
tar xzf "alertmanager-${ALERTMANAGER_VERSION}.linux-amd64.tar.gz"

sudo mkdir -p /etc/alertmanager /var/lib/alertmanager
sudo cp "alertmanager-${ALERTMANAGER_VERSION}.linux-amd64/alertmanager" /usr/local/bin/
sudo cp "alertmanager-${ALERTMANAGER_VERSION}.linux-amd64/amtool"       /usr/local/bin/
sudo chown alertmanager:alertmanager /usr/local/bin/alertmanager /usr/local/bin/amtool
sudo chown -R alertmanager:alertmanager /etc/alertmanager /var/lib/alertmanager

sudo tee /etc/alertmanager/alertmanager.yml > /dev/null <<'AMEOF'
global:
  resolve_timeout: 5m

route:
  group_by: ['alertname', 'instance']
  group_wait: 30s
  group_interval: 5m
  repeat_interval: 1h
  receiver: 'default-receiver'
  routes:
    - match:
        severity: critical
      receiver: 'critical-receiver'
      continue: true

receivers:
  - name: 'default-receiver'
    # Uncomment to enable Slack alerts:
    # slack_configs:
    #   - api_url: 'https://hooks.slack.com/services/YOUR/WEBHOOK'
    #     channel: '#alerts'
    #     title: '{{ .GroupLabels.alertname }}'
    #     text: '{{ range .Alerts }}{{ .Annotations.summary }}{{ end }}'

  - name: 'critical-receiver'
    # Add PagerDuty or email here

inhibit_rules:
  - source_match:
      severity: 'critical'
    target_match:
      severity: 'warning'
    equal: ['alertname', 'instance']
AMEOF

sudo chown alertmanager:alertmanager /etc/alertmanager/alertmanager.yml

sudo tee /etc/systemd/system/alertmanager.service > /dev/null <<'SVCEOF'
[Unit]
Description=Alertmanager
After=network.target

[Service]
User=alertmanager
Group=alertmanager
ExecStart=/usr/local/bin/alertmanager \
  --config.file=/etc/alertmanager/alertmanager.yml \
  --storage.path=/var/lib/alertmanager/ \
  --web.listen-address=0.0.0.0:9093
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
SVCEOF

# =============================================================================
# 4. GRAFANA
# =============================================================================
sudo tee /etc/yum.repos.d/grafana.repo > /dev/null <<'REPOEOF'
[grafana]
name=grafana
baseurl=https://packages.grafana.com/oss/rpm
repo_gpgcheck=1
enabled=1
gpgcheck=1
gpgkey=https://packages.grafana.com/gpg.key
sslverify=1
sslcacert=/etc/pki/tls/certs/ca-bundle.crt
REPOEOF

sudo yum install -y "grafana-${GRAFANA_VERSION}"

GRAFANA_PASS="${GRAFANA_PASS:-Admin@123}"
sudo sed -i "s/^;admin_password = .*/admin_password = ${GRAFANA_PASS}/" /etc/grafana/grafana.ini

sudo mkdir -p /etc/grafana/provisioning/datasources
sudo tee /etc/grafana/provisioning/datasources/prometheus.yml > /dev/null <<'DSEOF'
apiVersion: 1
datasources:
  - name: Prometheus
    type: prometheus
    access: proxy
    url: http://localhost:9090
    isDefault: true
    editable: true
    jsonData:
      timeInterval: "15s"
DSEOF

sudo mkdir -p /etc/grafana/provisioning/dashboards
sudo tee /etc/grafana/provisioning/dashboards/default.yml > /dev/null <<'DBEOF'
apiVersion: 1
providers:
  - name: default
    orgId: 1
    folder: ''
    type: file
    disableDeletion: false
    updateIntervalSeconds: 30
    options:
      path: /var/lib/grafana/dashboards
DBEOF

sudo mkdir -p /var/lib/grafana/dashboards
sudo chown -R grafana:grafana /var/lib/grafana/dashboards

# =============================================================================
# 5. START ALL SERVICES
# =============================================================================
sudo systemctl daemon-reload
sudo systemctl enable --now node_exporter
sudo systemctl enable --now prometheus
sudo systemctl enable --now alertmanager
sudo systemctl enable --now grafana-server

PUBLIC_IP=$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4)
echo "=========================================="
echo "[$(date)] Monitoring installation complete."
echo "  Prometheus   -> http://${PUBLIC_IP}:9090"
echo "  Grafana      -> http://${PUBLIC_IP}:3000"
echo "  Alertmanager -> http://${PUBLIC_IP}:9093"
echo "=========================================="
