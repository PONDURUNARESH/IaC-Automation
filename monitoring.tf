# =============================================================================
# monitoring.tf
#
# user_data strategy:
#   - Write monitoring-install.sh to the instance via a base64-encoded
#     write_files cloud-init block, then run it with env vars exported.
#   - This completely avoids any heredoc / shebang collision.
# =============================================================================

# ── Security Group for Monitoring Server ──────────────────────────────────────
module "monitoring_sg" {
  source = "terraform-aws-modules/security-group/aws"

  name        = "monitoring-sg"
  description = "Security Group for Prometheus and Grafana"
  vpc_id      = module.vpc.vpc_id

  ingress_with_cidr_blocks = [
    {
      from_port   = 9090
      to_port     = 9090
      protocol    = "tcp"
      description = "Prometheus UI"
      cidr_blocks = "0.0.0.0/0"
    },
    {
      from_port   = 3000
      to_port     = 3000
      protocol    = "tcp"
      description = "Grafana UI"
      cidr_blocks = "0.0.0.0/0"
    },
    {
      from_port   = 9093
      to_port     = 9093
      protocol    = "tcp"
      description = "Alertmanager UI"
      cidr_blocks = "0.0.0.0/0"
    },
    {
      from_port   = 9100
      to_port     = 9100
      protocol    = "tcp"
      description = "Node Exporter - internal VPC only"
      cidr_blocks = var.vpc_cidr
    },
    {
      from_port   = 22
      to_port     = 22
      protocol    = "tcp"
      description = "SSH"
      cidr_blocks = "0.0.0.0/0"
    }
  ]

  egress_with_cidr_blocks = [
    {
      from_port   = 0
      to_port     = 0
      protocol    = "-1"
      cidr_blocks = "0.0.0.0/0"
    }
  ]

  tags = {
    Name        = "monitoring-sg"
    Terraform   = "true"
    Environment = "dev"
  }
}

# ── Monitoring EC2 Instance ───────────────────────────────────────────────────
# user_data:
#   1. Export JENKINS_IP and GRAFANA_PASS as env vars (Terraform resolves these)
#   2. Decode and write monitoring-install.sh from base64 (no heredoc clash)
#   3. Run it
locals {
  install_script_b64 = base64encode(file("${path.module}/scripts/monitoring-install.sh"))
}

module "monitoring_instance" {
  source = "terraform-aws-modules/ec2-instance/aws"

  name = "Monitoring-Server"

  ami                         = data.aws_ami.example.id
  instance_type               = var.monitoring_instance_type
  key_name                    = aws_key_pair.jenkins.key_name
  monitoring                  = true
  vpc_security_group_ids      = [module.monitoring_sg.security_group_id]
  subnet_id                   = module.vpc.public_subnets[0]
  associate_public_ip_address = true

  user_data = <<-USERDATA
    #!/bin/bash
    set -euo pipefail
    exec >> /var/log/userdata-bootstrap.log 2>&1
    echo "[$(date)] Bootstrap starting..."

    # Terraform-injected values
    export JENKINS_IP="${module.ec2_instance.private_ip}"
    export GRAFANA_PASS="${var.grafana_admin_password}"

    echo "[$(date)] JENKINS_IP=$JENKINS_IP"

    # Decode and write the install script (base64 avoids any heredoc collisions)
    echo "${local.install_script_b64}" | base64 -d > /tmp/monitoring-install.sh
    chmod +x /tmp/monitoring-install.sh

    echo "[$(date)] Running monitoring-install.sh..."
    bash /tmp/monitoring-install.sh
    echo "[$(date)] Bootstrap complete."
  USERDATA

  depends_on = [module.ec2_instance]

  tags = {
    Name        = "Monitoring-Server"
    Terraform   = "true"
    Environment = "dev"
    Role        = "monitoring"
  }
}

# ── Allow Prometheus to scrape Node Exporter on the Jenkins server ─────────────
resource "aws_security_group_rule" "jenkins_node_exporter" {
  type                     = "ingress"
  from_port                = 9100
  to_port                  = 9100
  protocol                 = "tcp"
  source_security_group_id = module.monitoring_sg.security_group_id
  security_group_id        = module.sg.security_group_id
  description              = "Allow Prometheus (monitoring-sg) to scrape Jenkins Node Exporter"
}
