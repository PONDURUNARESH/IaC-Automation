vpc_cidr       = "10.0.0.0/16"
public_subnets = ["10.0.1.0/24"]
instance_type  = "t3.micro"
key_name       = "windowskey"

# ── Monitoring ─────────────────────────────────────────────────────────────────
monitoring_instance_type = "t3.small"
aws_region               = "us-east-1"
slack_webhook_url        = ""        # paste your Slack webhook here
grafana_admin_password   = "Admin@123"  # change before deploying to production
