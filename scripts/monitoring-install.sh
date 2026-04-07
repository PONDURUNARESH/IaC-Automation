#!/bin/bash
# =============================================================================
# monitoring-install.sh
# Installs: Prometheus, Grafana, Alertmanager, Node Exporter
# Rendered by Terraform templatefile() — variables injected at apply time:
#   ${jenkins_private_ip}  — private IP of Jenkins-Server EC2
#   ${vpc_cidr}            — VPC CIDR for internal-only scrape rules
#   ${aws_region}          — AWS region (e.g. us-east-1)
# =============================================================================

set -euo pipefail
exec > /var/log/monitoring-install.log 2>&1

# ── Versions ──────────────────────────────────────────────────────────────────
PROM_VERSION="2.47.0"
ALERTMANAGER_VERSION="0.26.0"
NODE_EXPORTER_VERSION="1.6.1"
GRAFANA_VERSION="10.2.0"

# ── System setup ──────────────────────────────────────────────────────────────
sudo yum update -y
sudo yum install -y wget tar

# ── Create system users ────────────────────────────────────────────────────────
for user in prometheus alertmanager node_exporter; do
  if ! id "$user" &>/dev/null; then
    sudo useradd --no-create-home --shell /bin/false "$user"
  fi
done

# =============================================================================
# 1. NODE EXPORTER (monitors this monitoring server itself)
# =============================================================================
cd /tmp
wget -q https://github.com/prometheus/node_exporter/releases/download/v${NODE_EXPORTER_VERSION}/node_exporter-${NODE_EXPORTER_VERSION}.linux-amd64.tar.gz
tar xzf node_exporter-${NODE_EXPORTER_VERSION}.linux-amd64.tar.gz
sudo cp node_exporter-${NODE_EXPORTER_VERSION}.linux-amd64/node_exporter /usr/local/bin/
sudo chown node_exporter:node_exporter /usr/local/bin/node_exporter

sudo tee /etc/systemd/system/node_exporter.service > /dev/null <<'EOF'
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
EOF

# =============================================================================
# 2. PROMETHEUS
# =============================================================================
cd /tmp
wget -q https://github.com/prometheus/prometheus/releases/download/v${PROM_VERSION}/prometheus-${PROM_VERSION}.linux-amd64.tar.gz
tar xzf prometheus-${PROM_VERSION}.linux-amd64.tar.gz

sudo mkdir -p /etc/prometheus /var/lib/prometheus
sudo cp prometheus-${PROM_VERSION}.linux-amd64/{prometheus,promtool} /usr/local/bin/
sudo cp -r prometheus-${PROM_VERSION}.linux-amd64/{consoles,console_libraries} /etc/prometheus/
sudo chown -R prometheus:prometheus /etc/prometheus /var/lib/prometheus
sudo chown prometheus:prometheus /usr/local/bin/{prometheus,promtool}

# prometheus.yml — scrapes this server, Jenkins server, and Alertmanager
sudo tee /etc/prometheus/prometheus.yml > /dev/null <<EOF
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

  # Prometheus self-monitoring
  - job_name: 'prometheus'
    static_configs:
      - targets: ['localhost:9090']
        labels:
          instance: 'monitoring-server'

  # This monitoring server's own OS metrics
  - job_name: 'monitoring-node'
    static_configs:
      - targets: ['localhost:9100']
        labels:
          instance: 'monitoring-server'
          environment: 'dev'

  # Jenkins Server (EC2 at ${jenkins_private_ip})
  - job_name: 'jenkins-node'
    static_configs:
      - targets: ['${jenkins_private_ip}:9100']
        labels:
          instance: 'Jenkins-Server'
          environment: 'dev'

  # Jenkins application metrics (requires Prometheus plugin in Jenkins)
  - job_name: 'jenkins'
    metrics_path: '/prometheus'
    static_configs:
      - targets: ['${jenkins_private_ip}:8080']
        labels:
          instance: 'Jenkins-Server'
          environment: 'dev'

  # Alertmanager self-monitoring
  - job_name: 'alertmanager'
    static_configs:
      - targets: ['localhost:9093']
        labels:
          instance: 'monitoring-server'
EOF

sudo chown prometheus:prometheus /etc/prometheus/prometheus.yml

# Alert rules directory
sudo mkdir -p /etc/prometheus/rules
sudo chown prometheus:prometheus /etc/prometheus/rules

# alert rules
sudo tee /etc/prometheus/rules/alerts.yml > /dev/null <<'EOF'
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
          description: "{{ $labels.instance }} has been unreachable for more than 1 minute."

      - alert: HighCPUUsage
        expr: 100 - (avg by(instance) (rate(node_cpu_seconds_total{mode="idle"}[5m])) * 100) > 80
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "High CPU on {{ $labels.instance }}"
          description: "CPU usage is above 80% for 5 minutes on {{ $labels.instance }}. Current: {{ $value | printf \"%.1f\" }}%"

      - alert: HighMemoryUsage
        expr: (1 - (node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes)) * 100 > 85
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "High memory on {{ $labels.instance }}"
          description: "Memory usage above 85% on {{ $labels.instance }}. Current: {{ $value | printf \"%.1f\" }}%"

      - alert: DiskSpaceLow
        expr: (node_filesystem_avail_bytes{mountpoint="/"} / node_filesystem_size_bytes{mountpoint="/"}) * 100 < 15
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "Low disk space on {{ $labels.instance }}"
          description: "Less than 15% disk free on {{ $labels.instance }}."

  - name: jenkins_alerts
    rules:

      - alert: JenkinsDown
        expr: up{job="jenkins"} == 0
        for: 2m
        labels:
          severity: critical
        annotations:
          summary: "Jenkins is DOWN"
          description: "Jenkins application at ${jenkins_private_ip}:8080 has been down for 2 minutes."

      - alert: JenkinsBuildFailureRateHigh
        expr: rate(jenkins_builds_failed_build_count_total[15m]) > 0.1
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "High Jenkins build failure rate"
          description: "More than 10% of Jenkins builds are failing in the last 15 minutes."
EOF

sudo chown prometheus:prometheus /etc/prometheus/rules/alerts.yml

sudo tee /etc/systemd/system/prometheus.service > /dev/null <<EOF
[Unit]
Description=Prometheus Monitoring
After=network.target

[Service]
User=prometheus
Group=prometheus
ExecStart=/usr/local/bin/prometheus \\
  --config.file=/etc/prometheus/prometheus.yml \\
  --storage.tsdb.path=/var/lib/prometheus/ \\
  --storage.tsdb.retention.time=15d \\
  --web.listen-address=0.0.0.0:9090 \\
  --web.enable-lifecycle
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

# =============================================================================
# 3. ALERTMANAGER
# =============================================================================
cd /tmp
wget -q https://github.com/prometheus/alertmanager/releases/download/v${ALERTMANAGER_VERSION}/alertmanager-${ALERTMANAGER_VERSION}.linux-amd64.tar.gz
tar xzf alertmanager-${ALERTMANAGER_VERSION}.linux-amd64.tar.gz

sudo mkdir -p /etc/alertmanager /var/lib/alertmanager
sudo cp alertmanager-${ALERTMANAGER_VERSION}.linux-amd64/{alertmanager,amtool} /usr/local/bin/
sudo chown alertmanager:alertmanager /usr/local/bin/{alertmanager,amtool}
sudo chown -R alertmanager:alertmanager /etc/alertmanager /var/lib/alertmanager

sudo tee /etc/alertmanager/alertmanager.yml > /dev/null <<'EOF'
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
    # Add Slack or email here — see README for instructions

  - name: 'critical-receiver'
    # Add PagerDuty or escalation channel here

inhibit_rules:
  - source_match:
      severity: 'critical'
    target_match:
      severity: 'warning'
    equal: ['alertname', 'instance']
EOF

sudo chown alertmanager:alertmanager /etc/alertmanager/alertmanager.yml

sudo tee /etc/systemd/system/alertmanager.service > /dev/null <<EOF
[Unit]
Description=Alertmanager
After=network.target

[Service]
User=alertmanager
Group=alertmanager
ExecStart=/usr/local/bin/alertmanager \\
  --config.file=/etc/alertmanager/alertmanager.yml \\
  --storage.path=/var/lib/alertmanager/ \\
  --web.listen-address=0.0.0.0:9093
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

# =============================================================================
# 4. GRAFANA
# =============================================================================
sudo tee /etc/yum.repos.d/grafana.repo > /dev/null <<'EOF'
[grafana]
name=grafana
baseurl=https://packages.grafana.com/oss/rpm
repo_gpgcheck=1
enabled=1
gpgcheck=1
gpgkey=https://packages.grafana.com/gpg.key
sslverify=1
sslcacert=/etc/pki/tls/certs/ca-bundle.crt
EOF

sudo yum install -y grafana-${GRAFANA_VERSION}

# Pre-configure Grafana: admin password, anonymous access off, server URL
sudo sed -i 's/^;admin_password = .*/admin_password = ${grafana_admin_password:-Admin@123}/' /etc/grafana/grafana.ini
sudo sed -i 's/^;domain = .*/domain = localhost/' /etc/grafana/grafana.ini

# Auto-provision Prometheus as a Grafana datasource
sudo mkdir -p /etc/grafana/provisioning/datasources
sudo tee /etc/grafana/provisioning/datasources/prometheus.yml > /dev/null <<'EOF'
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
EOF

# Auto-provision dashboards folder
sudo mkdir -p /etc/grafana/provisioning/dashboards
sudo tee /etc/grafana/provisioning/dashboards/default.yml > /dev/null <<'EOF'
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
EOF

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

# =============================================================================
# 6. INSTALL NODE EXPORTER ON JENKINS SERVER VIA SSM (optional fallback note)
# The Jenkins server's node_exporter is installed via jenkins-install.sh
# =============================================================================

echo "✅ Monitoring stack installation complete."
echo "   Prometheus  → http://$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4):9090"
echo "   Grafana     → http://$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4):3000"
echo "   Alertmanager→ http://$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4):9093"
