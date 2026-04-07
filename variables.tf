variable "vpc_cidr" {
  description = "VPC CIDR"
  type        = string
}

variable "public_subnets" {
  description = "Public Subnet CIDRs"
  type        = list(string)
}

variable "instance_type" {
  description = "EC2 Instance Type for Jenkins"
  type        = string
}

variable "key_name" {
  description = "EC2 Key Pair Name"
  type        = string
  default     = "windowskey"
}

# ── New: Monitoring variables ──────────────────────────────────────────────────

variable "monitoring_instance_type" {
  description = "EC2 instance type for Monitoring Server (Prometheus + Grafana)"
  type        = string
  default     = "t3.small"
}

variable "aws_region" {
  description = "AWS Region"
  type        = string
  default     = "us-east-1"
}

variable "slack_webhook_url" {
  description = "Slack Incoming Webhook URL for Alertmanager notifications"
  type        = string
  default     = ""
  sensitive   = true
}

variable "grafana_admin_password" {
  description = "Admin password for Grafana dashboard"
  type        = string
  default     = "Admin@123"
  sensitive   = true
}
