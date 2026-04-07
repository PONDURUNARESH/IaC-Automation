# Monitoring Setup Guide
## Prometheus + Grafana for your IaC-Automation project

---

## What was added

| File | Change |
|---|---|
| `monitoring.tf` | New file — EC2 + Security Group for monitoring server |
| `variables.tf` | Added `monitoring_instance_type`, `aws_region`, `slack_webhook_url`, `grafana_admin_password` |
| `terraform.tfvars` | Added monitoring variable values |
| `outputs.tf` | Added `prometheus_url`, `grafana_url`, `alertmanager_url`, `monitoring_public_ip` |
| `jenkins-install.sh` | Added Node Exporter install at the end |
| `scripts/monitoring-install.sh` | New file — installs full monitoring stack on boot |
| `Jenkinsfile` | Added `Verify Monitoring Stack` stage after Apply |

---

## Step 1 — Add files to your repo

Copy these files into your GitHub repo (`IaC-Automation`):

```
IaC-Automation/
├── monitoring.tf              ← new
├── variables.tf               ← replace existing
├── terraform.tfvars           ← replace existing
├── outputs.tf                 ← replace existing
├── jenkins-install.sh         ← replace existing
├── Jenkinsfile                ← replace existing
└── scripts/
    └── monitoring-install.sh  ← new (create this folder)
```

---

## Step 2 — Install Jenkins Prometheus plugin

This enables Jenkins job/build metrics to be scraped by Prometheus.

1. Open Jenkins → **Manage Jenkins → Plugins → Available**
2. Search for `Prometheus metrics`
3. Install and restart Jenkins
4. Go to **Manage Jenkins → Configure System → Prometheus**
5. Set path to `/prometheus` (default) and save

---

## Step 3 — Push to GitHub

```bash
git add .
git commit -m "feat: add Prometheus + Grafana monitoring stack"
git push origin main
```

Jenkins will detect the push within 2 minutes (pollSCM) and trigger the pipeline.

---

## Step 4 — Approve and run the pipeline

In Jenkins, the pipeline will pause at **Manual Approval - Apply**.
Review the plan and click **Yes, Apply**.

After apply completes, the `Verify Monitoring Stack` stage will poll until
Prometheus and Grafana are healthy (up to 3 minutes).

---

## Step 5 — Access your dashboards

Terraform prints these URLs after apply:

```
prometheus_url    = "http://<ip>:9090"
grafana_url       = "http://<ip>:3000"
alertmanager_url  = "http://<ip>:9093"
```

You can also run: `terraform output`

**Grafana login:** `admin` / `Admin@123` (change in `terraform.tfvars`)

---

## Step 6 — Import dashboards in Grafana

Go to **Dashboards → Import** and use these IDs:

| ID | Dashboard | What it shows |
|---|---|---|
| `1860` | Node Exporter Full | CPU, RAM, disk, network per server |
| `9964` | Jenkins | Build counts, duration, queue depth |
| `9578` | Alertmanager | Firing alerts overview |

Steps:
1. Dashboards → Import
2. Enter the ID → Load
3. Select **Prometheus** as data source → Import

---

## Step 7 — (Optional) Enable Slack alerts

Edit `terraform.tfvars`:
```hcl
slack_webhook_url = "https://hooks.slack.com/services/YOUR/WEBHOOK"
```

Then edit `/etc/alertmanager/alertmanager.yml` on the monitoring server
and add under `receivers.default-receiver`:

```yaml
  - name: 'default-receiver'
    slack_configs:
      - api_url: 'https://hooks.slack.com/services/YOUR/WEBHOOK'
        channel: '#alerts'
        title: '{{ .GroupLabels.alertname }}'
        text: '{{ range .Alerts }}{{ .Annotations.summary }}{{ end }}'
```

Reload: `sudo systemctl reload alertmanager`

---

## Ports reference

| Port | Service | Open to |
|---|---|---|
| 9090 | Prometheus | 0.0.0.0/0 (UI) |
| 3000 | Grafana | 0.0.0.0/0 (UI) |
| 9093 | Alertmanager | 0.0.0.0/0 (UI) |
| 9100 | Node Exporter | VPC CIDR only (scrape) |
| 8080 | Jenkins | 0.0.0.0/0 (existing) |

---

## Verify Prometheus targets are UP

Open `http://<monitoring-ip>:9090/targets`

You should see all these as **UP**:

- `prometheus` → localhost:9090
- `monitoring-node` → localhost:9100
- `jenkins-node` → `<jenkins-private-ip>`:9100
- `jenkins` → `<jenkins-private-ip>`:8080/prometheus
- `alertmanager` → localhost:9093

---

## Troubleshooting

**Jenkins node target is DOWN in Prometheus:**
- SSH into Jenkins server and run: `sudo systemctl status node_exporter`
- Check SG rule: the `jenkins_node_exporter` security group rule in `monitoring.tf` must exist

**Grafana cannot connect to Prometheus:**
- Both are on the same server, so this is `localhost:9090` — check `sudo systemctl status prometheus`

**Logs:**
```bash
# On monitoring server
sudo journalctl -u prometheus -f
sudo journalctl -u grafana-server -f
sudo journalctl -u alertmanager -f
cat /var/log/monitoring-install.log
```
